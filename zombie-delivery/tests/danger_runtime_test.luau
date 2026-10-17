-- 10.x DANGER: a run's danger with the REAL server/RunDanger.luau beside the real server/Moving.luau, MoveHelper.luau and
-- Loot.luau on tests/runtime/MovingRuntime.luau's fakes (Config.Sandbox.On; tests/run_tests.py stages them), the real
-- art (shared/FurnitureLooks.luau, shared/HouseLayout.luau, server/HouseInterior.luau): a HARD run into The Lone House
-- (Ann the host, Bob her party), then a NIGHTMARE run into The Orchard Cottage.
--   * the run's start: its danger planned (shared/DangerRules.luau, the same plan for the same house and difficulty),
--     the locked doorways' leaves (RunLock, Open false), every searchable piece's Search prompt, the vault's cases
--     (RunVault) round its sealed pieces, the hazards (RunHazard, their Kind), the locked rooms' pieces a tier up and
--     the vault's Epic or better; Danny's grid told what is shut (s.danger.route)
--   * zombies spawn: Hard's in the house and in its yard, never near a player, the way in or the truck, the yard's in
--     the run's zone; resident roamers that notice you inside at Zombies.Aggro; they walk the house's way through its
--     doorways (Zombies.steer), never through a locked one
--   * a key found by searching: a piece with nothing ("Nothing in the …"), then the key's ("🔑 … found by Ann", the
--     party's HUD view), the piece tagged RunKey; the door opens with it (its leaf passes, RunLock Open, the grids open)
--   * the vault: its piece refused while sealed, the gold key found, the vault opened: the piece picked up
--   * Danny: a piece behind the locked door refused to him (no way there), given to him once it is open
--   * the hazards: carrying over a creak drops the piece (a knock), a puddle slides you, the plaster shakes and drops
--   * a bite drops a carried piece; a death drops it too and the body comes back by the truck; the party hears it
--   * the bat (Hard and up): in every party member's backpack, put away while carrying, gone at the end
--   * the end: zombies stopped counted, the results card's lines (vault, zombies), everything of the danger gone
--   * Nightmare: the boss by the vault (THE LANDLORD), the wave once half the clock is gone ("A horde is coming!")
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
-- 10.5: the game has no zombies any more (the owner: "zombies I don't want in the game at all": Config.Runs.Danger has
-- none at any difficulty, no bat, no boss; tests/roundrules_test.luau checks so). Their code and rules stay: this test
-- turns them on as they were before 10.5.
for id, were in {
	hard = { Inside = 3, Yard = 3, Wave = 0, Speed = 1, Boss = false, Weapon = true, Kinds = { walker = 1 } },
	insane = { Inside = 5, Yard = 4, Wave = 8, Speed = 1.2, Boss = false, Weapon = true, Kinds = { walker = 0.65, runner = 0.25, bloater = 0.1 } },
	nightmare = { Inside = 7, Yard = 6, Wave = 12, Speed = 1.3, Boss = true, Weapon = true, Kinds = { walker = 0.5, runner = 0.25, brute = 0.15, bloater = 0.1 } },
} :: { [string]: { [string]: any } } do
	for key, value in were do
		(Config.Runs.Danger[id] :: any)[key] = value
	end
end
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local RunDanger = require("./RunDangerServer")
local DangerRules = require("./DangerRules")
local HouseRoute = require("./HouseRoute")
local LootRules = require("./LootRules")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local SandboxMap = require("./SandboxMap")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
local R = Config.Runs
math.randomseed(1010)

-- the real art
local built: { any } = {}
Moving.useArt({
	looks = FurnitureLooks,
	layout = HouseLayout,
	interior = {
		slot = HouseInterior.slot,
		build = function(plan: any, origin: any): (any, any)
			E.built += 1
			table.insert(E.interiors, origin)
			local model, pieces = HouseInterior.build(plan, origin)
			table.insert(built, { model = model, plan = plan, origin = origin, pieces = pieces })
			return model, pieces
		end,
		destroy = function(model: any)
			E.destroyed += 1
			HouseInterior.destroy(model)
		end,
	},
})
E.carId = "sprinter"
Moving.parkVan = function(player: any, spot: any, _seat: boolean, carId: string?): (string?, any)
	local old = E.cars[player]
	if old then
		old.model:Destroy()
	end
	local car = E.makeCar(player, carId or Config.Sandbox.Van, V3(spot.x, 2, spot.z))
	E.cars[player] = car
	return nil, car
end
Moving.start()
RunDanger.start(Moving)

local function step(seconds: number?)
	E.clock += seconds or 0.3
	E.now += seconds or 0.3
	Moving.step()
	RunDanger.step()
end
local function promptIn(root: any, name: string): any
	for _, d in root:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.Name == name and not d.destroyed then
			return d
		end
	end
	return nil
end
local function since(player: any, remote: string, from: number, pick: (any) -> boolean): any
	for index = #E.messages, from + 1, -1 do
		local m = E.messages[index]
		if m.player == player and m.remote == remote and pick(m) then
			return m
		end
	end
	return nil
end
local function heard(player: any, from: number, text: string): boolean
	return since(player, "Runs", from, function(m: any): boolean
		return type(m.kind) == "table" and m.kind.kind == "danger" and type(m.kind.event) == "string" and string.find(m.kind.event, text, 1, true) ~= nil
	end) ~= nil
end
local function noticed(player: any, from: number, text: string): boolean
	return since(player, "Notice", from, function(m: any): boolean
		return type(m.kind) == "string" and string.find(m.kind, text, 1, true) ~= nil
	end) ~= nil
end
-- A humanoid that takes damage and unequips its tools (Roblox's), on a fake body.
local function body(player: any)
	local humanoid = player.Character:FindFirstChild("Humanoid")
	humanoid.TakeDamage = function(self: any, amount: number)
		self.Health -= amount
	end
	humanoid.UnequipTools = function()
		local backpack = player:FindFirstChild("Backpack")
		for _, child in player.Character:GetChildren() do
			if child.ClassName == "Tool" then
				child.Parent = backpack
			end
		end
	end
	local backpack = M.Instance.new("Backpack")
	backpack.Name = "Backpack"
	backpack.Parent = player
end

-- ── A HARD run into The Lone House ─────────────────────────────────────────
local house = SandboxMap.house("lone_house") :: any
local plot1, plot2 = SandboxMap.Plots[1], SandboxMap.Plots[2]
local SEED = 31
local ann = E.player(11, "Ann", V3(plot1.spawn.x, 3, plot1.spawn.z))
local bob = E.player(22, "Bob", V3(plot2.spawn.x, 3, plot2.spawn.z))
body(ann)
body(bob)
E.plots[ann], E.plots[bob] = plot1, plot2
E.profiles[ann] = { money = 5000, sandboxHouse = house.id, sandboxHouseSeed = SEED }
E.profiles[bob] = { money = 5000 }
E.crew[ann] = {} -- (Bob joins once Danny is hired: a crew of two has him for hire no more, Config.MoveHelper.Duo)
Moving.parkVan(ann, house.curb, false)
local truck = E.cars[ann]
truck.chassis.CFrame = CF(house.curb.x, 2, house.curb.z) * M.CFrame.Angles(0, math.rad(house.curb.yaw), 0)
local zone = SandboxMap.zone(house.id) :: any
-- the party in the house's front yard (as server/Runs.luau jumps them there)
E.place(ann, V3(zone.arrive.x, 3, zone.arrive.z))
E.place(bob, V3(zone.arrive.x + 3.5, 3, zone.arrive.z))
local zombiesBefore = #E.zombies
local started = Moving.startRun(ann, house.id, "hard")
local b = built[#built]
step()
local st = RunDanger.stateFor(ann) :: any
check("a Hard run into The Lone House: its danger begun with the run (Moving.onRunStart)", started == nil and b ~= nil and st ~= nil and st.id == "hard", started)
local s = st.s
local plan, origin = b.plan, b.origin
local expect = DangerRules.plan(plan, "hard")
check("… the plan DangerRules makes for this house and difficulty: its locks and their keys, its vault, its hazards",
	#st.locks == #expect.locks and #st.locks >= 1 and st.vault ~= nil and #st.hazards == #expect.hazards and st.locks[1].key.spot == expect.locks[1].key)
check("… the run's state on its session (Moving's sealed vault pieces, Danny's shut doorways and hazards)", s.danger == st and next(st.sealed) ~= nil
	and #st.route.walls == #st.locks and #st.route.floors == #st.hazards)
-- Danny hired by Ann alone, then Bob joins her party
E.request(ann, "helper", "hire")
step(0.3)
E.crew[ann] = { bob }
step(0.3)
check("… the party in it (the members' set: the host and Bob)", s.members[ann] == true and s.members[bob] == true)

-- the leaves, the prompts, the cases, the hazards
do
	local leaves, tagged = 0, true
	for _, lock in st.locks do
		local leaf = lock.leaf
		if leaf and leaf.CanCollide and leaf:GetAttribute("Open") == false and leaf:GetAttribute("Tag_RunLock") == true then
			leaves += 1
		end
		tagged = tagged and promptIn(lock.parts[1], "RunUnlock") ~= nil
	end
	check("every locked doorway: a solid leaf (RunLock, Open false) with its padlock and its Unlock prompt", leaves == #st.locks and tagged)
	local searches = 0
	for _, spot in expect.searchable do
		if promptIn(s.items[spot].root, "RunSearch") then
			searches += 1
		end
	end
	local p = promptIn(s.items[expect.searchable[1]].root, "RunSearch")
	check(`every searchable piece has its Search prompt ({searches}: F, the gamepad's Y, held {R.Search.Hold} s; the party's only)`,
		searches == #expect.searchable and p.KeyboardKeyCode == "F" and p.GamepadKeyCode == "ButtonY" and p.HoldDuration == R.Search.Hold
			and p:GetAttribute("MoveOwner") == ann.UserId and p:GetAttribute("Tag_MovePrompt") == true)
	local cases = 0
	for _, case in st.vault.cases do
		local item = s.items[case.spot]
		if case.model:GetAttribute("Tag_RunVault") == true and case.model:GetAttribute("Open") == false and item.pick.Enabled == false then
			cases += 1
		end
	end
	check("the vault: a case round each of its pieces (RunVault, Open false), their pick-up prompts off", cases == #st.vault.cases and cases >= 1)
	local kinds = true
	for _, h in st.hazards do
		kinds = kinds and h.part:GetAttribute("Tag_RunHazard") == true and h.part:GetAttribute("Kind") == h.plan.kind
	end
	check(`the hazards on the floor (RunHazard, their Kind: {#st.hazards} of them)`, kinds and #st.hazards >= 2)
	local liftOk = true
	local rolls = require("./LootServer").rollOf(s)
	for spot, steps in expect.lifts do
		local thing = s.move.things[spot]
		liftOk = liftOk and rolls[spot].rarity == thing.rarity and s.items[spot].model:GetAttribute("Rarity") == thing.rarity and steps == R.Locks.Lift
			and (LootRules.rank(thing.rarity) > LootRules.rank(rolls[spot].own) or thing.rarity == "legendary" or LootRules.rank(thing.rarity) >= 2)
	end
	local vaultOk = true
	for _, spot in st.vault.spots do
		vaultOk = vaultOk and LootRules.rank(s.move.things[spot].rarity) >= LootRules.rank("epic") and s.items[spot].model:GetAttribute("Stars") >= 4
	end
	check("the loot: a locked room's pieces a tier up, the vault's Epic or better (server/Loot.luau boost: the move's thing, the model)", liftOk and vaultOk)
end

-- zombies spawn
do
	local made = #E.zombies - zombiesBefore
	local inside, yard, far, resident = 0, 0, true, true
	local entry = (origin * plan.entry).Position
	local truckAt = truck.chassis.Position
	for n = zombiesBefore + 1, #E.zombies do
		local z = E.zombies[n]
		local at = z.at
		if (at - origin.Position).Magnitude < 300 then
			inside += 1
			far = far and (at - entry).Magnitude >= R.Zombies.Away and z.aggro == R.Zombies.Aggro
		else
			yard += 1
			local r = zone.rect
			far = far and at.X >= r.x0 and at.X <= r.x1 and at.Z >= r.z0 and at.Z <= r.z1
				and V3(at.X - truckAt.X, 0, at.Z - truckAt.Z).Magnitude >= R.Zombies.Truck
				and V3(at.X - zone.arrive.x, 0, at.Z - zone.arrive.z).Magnitude >= R.Zombies.YardAway and z.aggro == R.Zombies.YardAggro
		end
		for _, p in { ann, bob } do
			far = far and (E.rootOf(p).Position - at).Magnitude >= math.min(R.Zombies.Away, R.Zombies.YardAway)
		end
		resident = resident and z.roamer == true and z.model:GetAttribute("RunZombie") == s.id
	end
	check(`zombies spawn: {inside} in the house, {yard} in the yard (Hard: {R.Danger.hard.Inside} and {R.Danger.hard.Yard})`,
		made == R.Danger.hard.Inside + R.Danger.hard.Yard and inside == R.Danger.hard.Inside and yard == R.Danger.hard.Yard)
	check("… never by a player, the way in or the truck; the yard's in the run's zone; they notice you at Zombies.Aggro (the yard's YardAggro)", far)
	check("… the game's own zombies: roamers of the run (resident: they never despawn while you are elsewhere)", resident)
end

-- the zombies' way through the house (Zombies.steer)
do
	local lock = st.locks[1]
	local door = plan.doors[lock.plan.door]
	local behind: any = nil
	for _, room in plan.rooms do
		if room.id == lock.plan.room then
			behind = room
		end
	end
	local inner = (behind.min + behind.max) / 2
	local entry = (origin * plan.entry).Position
	local into = origin * V3(inner.X, 0, inner.Z)
	local steered = E.Zombies.steer({}, entry, into)
	check("a zombie walks the house's way (Zombies.steer): never through a locked doorway (no way: straight on, at the door)", steered == nil)
	-- the other rooms: a way through their doorways, a corner of it (never the goal through a wall)
	local other: any = nil
	for _, room in plan.rooms do
		if room.id ~= lock.plan.room and not table.find(lock.plan.behind, room.id) and room.id ~= "hall" and room.id ~= "corridor"
			and not (st.locks[2] and table.find(st.locks[2].plan.behind, room.id)) then
			other = room
		end
	end
	local goal = origin * V3((other.min.X + other.max.X) / 2, 0, (other.min.Z + other.max.Z) / 2)
	local to = E.Zombies.steer({}, entry, goal)
	check("… to another room through its doorway: a corner of its way, inside the house", to ~= nil and (to - goal).Magnitude > 1 and (origin:PointToObjectSpace(to)).Z > plan.min.Z)
	local _ = door
end

-- Danny: a piece behind the locked door is refused him (no way there)
local danny = MoveHelper.find(ann)
local function give(player: any, model: any)
	local was = E.rootOf(player).Position
	E.place(player, model.PrimaryPart.Position + V3(0, 0, 0))
	player.Character:SetAttribute("ClipboardHeld", true)
	E.request(player, "helper", "assign", model)
	E.place(player, was)
end
local lock = st.locks[1]
local locked: any = nil
for _, spot in plan.spots do
	if spot.room == lock.plan.room and not st.sealed[spot.id] then
		locked = spot
	end
end
do
	danny = MoveHelper.find(ann)
	check("Danny hired for the run, his grid the house's", danny ~= nil and danny.hirer == ann and danny.route ~= nil)
	local from = #E.messages
	give(ann, s.items[locked.id].model)
	check("… a piece behind the locked door refused to him (no way there: the doorway a wall on his grid)", table.find(danny.queue, locked.id) == nil
		and noticed(ann, from, "can't get to"))
end

-- a key found by searching; the door opens with it
do
	local keySpot = lock.key.spot
	local decoy: number? = nil
	for _, spot in expect.searchable do
		if expect.keys[spot] == nil and spot ~= keySpot and s.move.things[spot].state == "home" then
			local room = ""
			for _, planned in plan.spots do
				if planned.id == spot then
					room = planned.room
				end
			end
			local shut = false
			for _, l in st.locks do
				shut = shut or table.find(l.plan.behind, room) ~= nil
			end
			if not shut then
				decoy = spot
			end
		end
	end
	local from = #E.messages
	if decoy then
		E.place(ann, s.items[decoy].root.Position + V3(0, 0, 0))
		promptIn(s.items[decoy].root, "RunSearch").Triggered:Fire(ann)
	end
	check("a search with nothing in it: \"Nothing in the …\", its prompt gone", decoy ~= nil and noticed(ann, from, "Nothing in the") and promptIn(s.items[decoy :: number].root, "RunSearch") == nil)
	local door = plan.doors[lock.plan.door]
	E.place(ann, origin * V3(door.at.X, 3, door.at.Z))
	from = #E.messages
	lock.prompt.Triggered:Fire(ann)
	check("… the locked door without its key: still shut, and how to open it", lock.open == false and noticed(ann, from, "search it"))
	from = #E.messages
	E.place(ann, s.items[keySpot].root.Position)
	promptIn(s.items[keySpot].root, "RunSearch").Triggered:Fire(ann)
	local view = since(bob, "Runs", from, function(m: any): boolean
		return type(m.kind) == "table" and m.kind.kind == "danger" and m.kind.house ~= nil
	end)
	check(`a key found by searching: "{DangerRules.keyText(lock.key.name, "Ann")}" for the party, the piece tagged RunKey`, lock.key.found and lock.key.by == "Ann"
		and heard(bob, from, DangerRules.keyText(lock.key.name, "Ann")) and s.items[keySpot].model:GetAttribute("Tag_RunKey") == true)
	check("… the party's HUD view: the key found, by whom", view ~= nil and view.kind.keys[1].found == true and view.kind.keys[1].by == "Ann" and view.kind.difficulty == "hard")
	E.place(ann, origin * V3(door.at.X, 3, door.at.Z))
	from = #E.messages
	local p = lock.prompt
	p.Triggered:Fire(ann)
	local leaf = lock.leaf
	check("the door opens with it: its leaf passes (CanCollide off, RunLock Open), the padlock gone, the party told", lock.open and leaf.CanCollide == false
		and leaf:GetAttribute("Open") == true and lock.prompt == nil and heard(bob, from, DangerRules.lockText(lock.plan.name, "Ann")))
	check("… Danny's and the zombies' grids open there again (s.danger.route without it)", #st.route.walls == #st.locks - 1)
	-- Danny now: given the piece behind it, he takes it on
	from = #E.messages
	give(ann, s.items[locked.id].model)
	check("Danny: the piece behind the opened door given to him now (his way through the doorway)", table.find(danny.queue, locked.id) ~= nil and noticed(ann, from, "will take"))
	E.request(ann, "helper", "assign", s.items[locked.id].model) -- (back off his list)
	ann.Character:SetAttribute("ClipboardHeld", nil)
	local steered = E.Zombies.steer({}, (origin * plan.entry).Position, origin * V3((st.locks[1].plan.rect.x0 + st.locks[1].plan.rect.x1) / 2, 0, (st.locks[1].plan.rect.z0 + st.locks[1].plan.rect.z1) / 2))
	check("… and the zombies' way through it", steered ~= nil)
end

-- the vault
do
	local spot = st.vault.spots[1]
	local item = s.items[spot]
	E.place(ann, item.root.Position + V3(0, 0, -3))
	local from = #E.messages
	item.pick.Triggered:Fire(ann)
	check("the vault's piece: refused while sealed (no pick, the words why)", s.move.things[spot].state == "home" and noticed(ann, from, "vault"))
	local case = st.vault.cases[1]
	local box = case.model:FindFirstChild("VaultLock")
	E.place(ann, box.Position)
	from = #E.messages
	case.prompt.Triggered:Fire(ann)
	check("… the vault without its gold key: shut", st.vault.open == false and noticed(ann, from, "gold key"))
	local keySpot = st.vault.key.spot
	-- (its key may lie behind the second lock: that one opened first, its key searched for)
	for _, other in st.locks do
		if not other.open then
			E.place(ann, s.items[other.key.spot].root.Position)
			promptIn(s.items[other.key.spot].root, "RunSearch").Triggered:Fire(ann)
			local d = plan.doors[other.plan.door]
			E.place(ann, origin * V3(d.at.X, 3, d.at.Z))
			other.prompt.Triggered:Fire(ann)
		end
	end
	E.place(ann, s.items[keySpot].root.Position)
	promptIn(s.items[keySpot].root, "RunSearch").Triggered:Fire(ann)
	E.place(ann, box.Position)
	from = #E.messages
	case.prompt.Triggered:Fire(ann)
	check("… the gold key found, the vault opened: its case sinks away (RunVault Open), the piece free, the party told",
		st.vault.open and case.model:GetAttribute("Open") == true and st.sealed[spot] == nil and item.pick.Enabled == true and heard(bob, from, DangerRules.vaultText("Ann")))
	E.place(ann, item.root.Position + V3(0, 0, -3))
	item.pick.Triggered:Fire(ann)
	check("… and picked up", s.move.things[spot].state == "carried" and s.move.things[spot].carrier == ann.UserId)
	-- (put down again)
	Moving.runDrop(ann, "put", 0)
end

-- the bat (Hard): in the backpack, away while carrying
do
	step(0.6)
	local backpack = ann:FindFirstChild("Backpack")
	local bat = backpack and backpack:FindFirstChild(R.Weapon.Name)
	local bobBat = bob:FindFirstChild("Backpack"):FindFirstChild(R.Weapon.Name)
	check(`the run's bat in every party member's backpack ("{R.Weapon.Name}", a Tool: its Handle; {R.Weapon.Kind} swings)`, bat ~= nil and bat.ClassName == "Tool"
		and bat:FindFirstChild("Handle") ~= nil and bat:GetAttribute("RunWeapon") == R.Weapon.Kind and bobBat ~= nil and noticed(ann, 0, "bat"))
	bat.Parent = ann.Character -- (equipped)
	ann.Character:SetAttribute("Carrying", "crate")
	step(0.1)
	check("… carrying puts it away (back in the backpack)", bat.Parent == backpack)
	ann.Character:SetAttribute("Carrying", nil)
end

-- a piece to carry: a one-person piece of a room you can get to, not in the vault
local function pieceToCarry(avoid: number?): any
	for _, spot in plan.spots do
		local thing = s.move.things[spot.id]
		local open = true
		for _, l in st.locks do
			open = open and (l.open or not table.find(l.plan.behind, spot.room))
		end
		if open and thing.state == "home" and thing.class ~= "pair" and not st.sealed[spot.id] and spot.id ~= avoid then
			return spot
		end
	end
	return nil
end
local function pickUp(player: any, spot: any): boolean
	local item = s.items[spot.id]
	E.place(player, item.root.Position + V3(0, 0, 0.5))
	item.pick.Triggered:Fire(player)
	return s.move.things[spot.id].state == "carried"
end

-- a bite drops a carried piece
do
	local spot = pieceToCarry(nil)
	local carried = pickUp(ann, spot)
	local from = #E.messages
	local humanoid = ann.Character:FindFirstChild("Humanoid")
	E.Zombies.onBite(ann, humanoid, { def = { damage = 6 } })
	local thing = s.move.things[spot.id]
	check("a bite drops what you carry (Zombies.onBite → Moving.runDrop): on the floor, a knock, the words", carried and thing.state == "ground" and thing.condition < 1
		and ann.Character:GetAttribute("Carrying") == nil and noticed(ann, from, "Bitten"))
	-- a buddy's body (not the player's own): nothing
	local other = pieceToCarry(spot.id)
	pickUp(ann, other)
	E.Zombies.onBite(ann, M.Instance.new("Humanoid"), { def = { damage = 6 } })
	check("… a bite on another body (a buddy's, Danny's) is not hers", s.move.things[other.id].state == "carried")
	Moving.runDrop(ann, "put", 0)
end

-- the hazards
do
	local creak: any, puddle: any, plaster: any = nil, nil, nil
	for _, h in st.hazards do
		if h.plan.kind == "creak" and not creak then
			creak = h
		elseif h.plan.kind == "puddle" and not puddle then
			puddle = h
		elseif h.plan.kind == "plaster" and not plaster then
			plaster = h
		end
	end
	if creak then
		local spot = pieceToCarry(nil)
		pickUp(ann, spot)
		local before = s.move.things[spot.id].condition
		E.place(ann, origin * V3(creak.plan.x, 3, creak.plan.z))
		local from = #E.messages
		step(0.1)
		local thing = s.move.things[spot.id]
		check("carrying over a creaky patch: you stumble, the piece drops and takes a knock (more if fragile)", thing.state == "ground" and thing.condition < before
			and noticed(ann, from, "stumbled"))
		E.place(bob, origin * V3(creak.plan.x - 30, 3, creak.plan.z))
		E.place(bob, origin * V3(creak.plan.x, 3, creak.plan.z))
		from = #E.messages
		step(0.1)
		check("… walking over it empty-handed: only a creak underfoot (the warning)", not noticed(bob, from, "stumbled") and since(bob, "Runs", from, function(m: any): boolean
			return type(m.kind) == "table" and m.kind.sound == "house_door_creak"
		end) ~= nil)
	else
		check("(a creaky patch in this house)", false)
	end
	if puddle then
		E.place(bob, origin * V3(puddle.plan.x, 3, puddle.plan.z))
		E.rootOf(bob).AssemblyLinearVelocity = V3(12, 0, 0)
		local from = #E.messages
		step(0.1)
		local knock = since(bob, "Knock", from, function(): boolean
			return true
		end)
		check("a puddle: you slide on along your walk (the Knock remote, Hazard.Puddle.Slide)", knock ~= nil and math.abs(knock.kind.Magnitude - R.Hazard.Puddle.Slide) < 1e-6)
		E.rootOf(bob).AssemblyLinearVelocity = nil
	else
		check("(a puddle in this house)", false)
	end
	if plaster then
		local humanoid = bob.Character:FindFirstChild("Humanoid")
		E.place(bob, origin * V3(plaster.plan.x, 3, plaster.plan.z))
		step(0.1)
		local warned = plaster.warnAt ~= nil and plaster.part:GetAttribute("Warn") == true
		local hp = humanoid.Health
		step(R.Hazard.Plaster.Warn + 0.05)
		check("the plaster: a player near and it shakes first (Warn), then it drops: damage under it",
			warned and humanoid.Health == hp - DangerRules.plasterDamage("hard") and plaster.warnAt == nil and plaster.part:GetAttribute("Warn") == nil)
		E.place(bob, origin * V3(plaster.plan.x, 3, plaster.plan.z))
		local again = humanoid.Health
		step(0.2)
		step(R.Hazard.Plaster.Warn + 0.05)
		check("… not again before Rearm s", humanoid.Health == again)
		humanoid.Health = 100
	else
		check("(a cracked ceiling in this house)", false)
	end
end

-- a death drops the piece; the body comes back by the truck
do
	local spot = pieceToCarry(nil)
	pickUp(bob, spot)
	local humanoid = bob.Character:FindFirstChild("Humanoid")
	local from = #E.messages
	humanoid.Health = 0
	humanoid.Died:Fire()
	step(0.1)
	local at = Moving.respawnAt(bob)
	local truckAt = truck.chassis.Position
	check("a death in the run drops what was carried (Moving), the party hears it", s.move.things[spot.id].state == "ground" and heard(ann, from, "Bob is down"))
	check("… the body comes back by the truck (Moving.respawnAt), not in the lobby", at ~= nil and V3(at.Position.X - truckAt.X, 0, at.Position.Z - truckAt.Z).Magnitude < 15)
	humanoid.Health = 100
	step(0.6)
end

-- zombies stopped; the end
do
	local z = E.zombies[#E.zombies]
	z.dead, z.killed = true, true
	step(0.6)
	check("a zombie killed counts: Zombies stopped", st.stopped == 1)
	local folder = st.folder
	local bat = ann:FindFirstChild("Backpack"):FindFirstChild(R.Weapon.Name)
	local atEnd: any = nil
	Moving.onRunEnd(function(host: any) -- (as server/Runs.luau's results card reads it)
		atEnd = atEnd or RunDanger.result(host)
	end)
	Moving.endRun(ann, "Finished")
	step(0.1)
	local result = RunDanger.result(ann)
	check("the run's end: the results card's lines (the vault opened, the zombies stopped), kept a while after it", atEnd ~= nil and atEnd.vault == true
		and atEnd.stopped == 1 and atEnd.zombies == true and result ~= nil and result.stopped == 1)
	check("… everything of the danger gone: its parts, the bats, its state", folder.destroyed == true and (bat == nil or bat.destroyed == true) and RunDanger.stateFor(ann) == nil)
end

-- ── A NIGHTMARE run into The Orchard Cottage: the boss, the wave ───────────
do
	local cottage = SandboxMap.house("orchard_cottage") :: any
	local cz = SandboxMap.zone(cottage.id) :: any
	local cy = E.player(33, "Cy", V3(cz.arrive.x, 3, cz.arrive.z))
	body(cy)
	E.plots[cy] = SandboxMap.Plots[3]
	E.profiles[cy] = { money = 5000, sandboxHouse = cottage.id, sandboxHouseSeed = 5 }
	Moving.parkVan(cy, cottage.curb, false)
	local before = #E.zombies
	local marched = E.marched
	check("a Nightmare run into The Orchard Cottage", Moving.startRun(cy, cottage.id, "nightmare") == nil)
	step()
	local nst = RunDanger.stateFor(cy) :: any
	local boss = nst.boss
	local L = R.Danger.nightmare
	check(`… its zombies: {L.Inside} in the house, {L.Yard} in the yard, and {R.Zombies.Boss.Name} by the vault`, #E.zombies - before == L.Inside + L.Yard + 1
		and boss ~= nil and boss.kind == R.Zombies.Boss.Kind and boss.model:GetAttribute("RunBoss") == R.Zombies.Boss.Name
		and (nst.vault == nil or V3(boss.at.X - nst.vault.at.X, 0, boss.at.Z - nst.vault.at.Z).Magnitude <= 18),
		`{#E.zombies - before} zombies, boss {boss ~= nil}`)
	local from = #E.messages
	local move = nst.s.move
	E.now = move.startedAt + move.seconds * R.Zombies.WaveAt + 1
	step(0.6)
	check(`… half the clock gone: the wave ({L.Wave} marching at the door) and "A horde is coming!" with its banner and siren`, nst.waved
		and E.marched - marched == L.Wave and since(cy, "Runs", from, function(m: any): boolean
			return type(m.kind) == "table" and m.kind.banner == true and m.kind.sound == "horde_siren" and string.find(m.kind.event, "A horde is coming", 1, true) ~= nil
		end) ~= nil)
	E.now += 5
	step(0.6)
	check("… once", E.marched - marched == L.Wave)
	Moving.endRun(cy, "Finished")
	step(0.1)
end

if failures == 0 and #E.messages > 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
