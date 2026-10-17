-- 10.1 THE HELPERS' CREW in the runs: the real server/Moving.luau, server/MoveHelper.luau and server/HelperCrew.luau
-- (MovingServer, MoveHelperServer, HelperCrewServer through tests/run_tests.py) on tests/runtime/MovingRuntime.luau's
-- fakes in the sandbox (Config.Sandbox.On) with the real art (shared/FurnitureLooks.luau, shared/HouseLayout.luau,
-- server/HouseInterior.luau: the sandbox's house's real plan and pieces; no physics: his walk a straight step of speed ×
-- dt, his ways outside straight, a piece in his arms put in front of him), a party of two: Ann (the host) and Bob. The rules: tests/crewrules_test.luau;
-- the save's migration: tests/saving_runtime_test.luau.
--   * Danny is free and everybody's from the start: before any run he waits by Ann's warehouse (her "Crew" prompt only
--     hers: the CREW window's state and "open"); her first run: Danny with the party at once, nothing paid, no hire
--     anywhere, his name and kind on everybody's attributes; at its end he goes (back to her warehouse).
--   * Ann picks Bruno (the Crew remote's "pick": refused while he is not hers, saved once he is): her next run's helper
--     is Bruno (his look's name, his body's CrewKind and CrewSolo), the sofa (a piece for two) given him: he carries it
--     ALONE (no Lift, nobody at its other end), slowly (the drag × his Solo × his Speed), into the van.
--   * Zip refuses a piece for two and a heavy one (why, who can), takes the lamp; Gus refuses every piece and goes for
--     a zombie by Ann (server/Zombies.luau's damage, cause "melee", by nobody); Lucy in the run: CrewSense on Ann, Bob
--     and the run's inside, gone at its end.
--   * The rescue: a run's trapped helper (its odds rolled: HelperCrew.random), the kind the party lacks most, tied to a
--     chair in a room away from the way in (tagged RunRescue, his CrewKind on him); Bob's Untie: every party member who
--     lacks him gets him (saved soon), one who has him the bonus money (CrewRescue); he follows the party (put by them
--     in the other world), gone at the run's end; a stranger's Untie does nothing.
--   * Down in a run: at 0 health he lies down (CrewDownUntil, tagged CrewDown, "Revive <name>" on him); a party
--     player's revive within Down.Seconds: up with half his health; a stranger's: nothing; nobody: out of the run (his
--     body gone, no comeback this run) and in hospital (Hospital.Seconds, saved); the next run his pick in hospital:
--     Danny comes instead (said); the CREW window's DISCHARGE: paid (CrewDischarge), ready again.
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local HelperCrew = require("./HelperCrewServer")
local CrewRules = require("./CrewRules")
local Rules = require("./MovingRules")
local SandboxMap = require("./SandboxMap")
local Brain = require("./MoveHelperBrain")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local C = Config.Crew
local H = Config.MoveHelper
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
local House = SandboxMap.House
local plot1, plot2 = SandboxMap.Plots[1], SandboxMap.Plots[2]
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (the run's own roamers far off: this test brings its zombie itself)
end

-- His walk: straight toward the point, speed × dt a step (the last speed asked kept).
local lastSpeed = 0
MoveHelper.useMover({
	move = function(body: any, to: any, speed: number, dt: number)
		local root = body.root
		local here = root.Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		local length = way.Magnitude
		if length > 1e-6 then
			local step = math.min(length, speed * dt)
			root.CFrame = CF(here.X + way.X / length * step, here.Y, here.Z + way.Z / length * step)
		end
		body.walking = true
		lastSpeed = speed
	end,
	halt = function(body: any)
		body.walking = false
	end,
})

local ann = E.player(11, "Ann", V3(plot1.spawn.x, 3, plot1.spawn.z))
local bob = E.player(22, "Bob", V3(plot2.spawn.x, 3, plot2.spawn.z))
local cid = E.player(33, "Cid", V3(0, 3, 0)) -- (not in the party)
E.plots[ann] = plot1
E.plots[bob] = plot2
E.carId = "sprinter"
E.crew[ann] = { bob }
E.profiles[ann] = { money = 5000 } -- (no crew in it: a new player's, Danny)
E.profiles[bob] = { money = 5000 }
E.profiles[cid] = { money = 5000 }
Moving.parkVan = function(player: any, spot: any, _seat: boolean, carId: string?): (string?, any)
	local old = E.cars[player]
	if old then
		old.model:Destroy()
	end
	local car = E.makeCar(player, carId or Config.Sandbox.Van, V3(spot.x, 2, spot.z))
	E.cars[player] = car
	return nil, car
end
-- the map's front door (server/SandboxWorld.luau's: the attribute SandboxDoor, a door leaf)
do
	local frontDoor = M.Instance.new("Part")
	frontDoor.Name = "FrontDoor"
	frontDoor.Size = V3(4, 7, 0.4)
	frontDoor.CFrame = CF(House.door.x, 3.5, House.door.z + 0.5)
	frontDoor:SetAttribute("SandboxDoor", true)
	frontDoor:SetAttribute("DoorLeaf", 1)
	frontDoor:SetAttribute("DoorSwing", 1)
	frontDoor:SetAttribute("DoorDark", true)
	frontDoor.Parent = workspace
end
-- his ways outside: PathfindingService's, straight (no physics, no walls out there)
E.services.PathfindingService = {
	CreatePath = function(_, _params: any): any
		local path: any = { Status = "NoPath", points = {} }
		function path.ComputeAsync(self: any, from: any, to: any)
			self.points = { { Position = from, Action = "Walk" }, { Position = to, Action = "Walk" } }
			self.Status = "Success"
		end
		function path.GetWaypoints(self: any): any
			return self.points
		end
		return path
	end,
}
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
Moving.start()
HelperCrew.random = function(): number
	return 0.99 -- (no trapped helper unless a check asks for one)
end
HelperCrew.start() -- (the Crew remote, the lobby's stands; its loop is the test's: HelperCrew.step)

local function promptIn(model: any, action: string?): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and (action == nil or string.find(tostring(d.ActionText), action, 1, true) == 1) then
			return d
		end
	end
	return nil
end
local function heard(player: any, text: string, since: number?): boolean
	for index = (since or 0) + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then
			return true
		end
	end
	return false
end
local function crewSent(player: any, kind: string, since: number?): any
	local found = nil
	for index = (since or 0) + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Crew" and type(m.kind) == "table" and m.kind.kind == kind then
			found = m.kind
		end
	end
	return found
end
local function crewRequest(player: any, message: any)
	E.Net.get("Crew").OnServerEvent:Fire(player, message)
end
local function itemModel(spot: number): any
	return built[#built].pieces[spot]
end
-- The run's first piece of a class (and weight within `most`; "pair": a piece for two) still in the house.
local function pieceOf(s: any, class: string, least: number?, most: number?): number?
	for _, spot in built[#built].plan.spots do
		local thing = s.move.things[spot.id]
		if thing.state == "home" and thing.class == class and thing.weight >= (least or 0) and thing.weight <= (most or 99) and Rules.canLoad(s.move, spot.id) then
			return spot.id
		end
	end
	return nil
end
local function crewOf(player: any): any
	return HelperCrew.crewOf(player)
end
local function same(list: { string }, want: { string }): boolean
	return table.concat(list, ",") == table.concat(want, ",")
end

-- The steps: 0.1 s each (his loop's, the crew's), the move's tick every other one; until `done`, or `seconds` long. What
-- the helper carries alone stays in front of him (the weld, in Roblox).
local helper: any = nil
local function carryAlong()
	local h = helper
	if not h or not h.body then
		return
	end
	local spot, role = Rules.holding(h.s.move, h.id)
	local model = if spot and role == "carrier" then itemModel(spot) else nil
	if model and not E.welded(model) then
		model.PrimaryPart.CFrame = h.body.root.CFrame * CF(0, 0, -1.5)
	end
end
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		E.now += 0.1
		MoveHelper.step(0.1)
		carryAlong()
		HelperCrew.step(0.1)
		if index % 2 == 0 then
			Moving.step()
		end
		if done and done() then
			Moving.step()
			return true
		end
	end
	Moving.step()
	return done == nil
end
-- A run of Ann's party into the sandbox's house (9.7: the truck at its curb first, as server/Runs.luau's Runs.begin).
local function startRun(difficulty: string?): (string?, any)
	Moving.parkVan(ann, House.curb, false)
	local truck = E.cars[ann]
	truck.chassis.CFrame = CF(House.curb.x, 2, House.curb.z) * M.CFrame.Angles(0, math.rad(House.curb.yaw), 0)
	local why = Moving.startRun(ann, House.id, difficulty or "normal")
	truck.model:SetAttribute("BackOpen", true)
	run(0.6)
	helper = MoveHelper.find(ann)
	return why, helper
end
local function endRun()
	Moving.endRun(ann, "test")
	run(0.6)
	helper = nil
end
-- Ann or Bob in the run's house, by a piece (the interior: another world off the map).
local function inside(player: any, model: any)
	E.place(player, model.PrimaryPart.Position + V3(3, 0, 0))
end
-- 8.5 orders mode: a click on a piece with the clipboard out (the Moving remote's ("helper", "assign", model)).
local function give(model: any, player: any?)
	local who = player or ann
	inside(who, model)
	who.Character:SetAttribute("ClipboardHeld", true)
	E.request(who, "helper", "assign", model)
end

-- Ann's helper by her warehouse (the lobby's stand), nil: none.
local function standOf(player: any): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("CrewStand") == player.UserId and not d.destroyed and d.Parent ~= nil then
			return d
		end
	end
	return nil
end

-- ── Danny: free, everybody's from the start ────────────────────────────────
do
	run(C.Lobby.Every + 0.2)
	local stand = standOf(ann)
	local door = plot1.door
	check("10.1 before any run: Danny waits by Ann's warehouse (CrewKind danny, beside its door)", stand ~= nil and stand:GetAttribute("CrewKind") == "danny"
		and (stand.PrimaryPart.Position - V3(door.x + C.Lobby.Stand[1], stand.PrimaryPart.Position.Y, door.z + C.Lobby.Stand[2])).Magnitude < 0.5)
	local prompt = stand and promptIn(stand, "Crew")
	check("… his \"Crew\" prompt Ann's only (MoveOwner: the others never see it)", prompt ~= nil and prompt:GetAttribute("MoveOwner") == ann.UserId)
	local since = #E.messages
	if prompt then
		prompt.Triggered:Fire(bob)
	end
	check("… Bob's E on it: nothing", crewSent(bob, "open", since) == nil and crewSent(ann, "open", since) == nil)
	if prompt then
		prompt.Triggered:Fire(ann)
	end
	local state = crewSent(ann, "state", since)
	check("… Ann's: the CREW window opens with her crew (Danny ready and picked, the rest locked)", crewSent(ann, "open", since) ~= nil and state ~= nil
		and state.rows[1].id == "danny" and state.rows[1].state == "ready" and state.rows[1].pick == true and state.rows[2].state == "locked"
		and state.comes == "danny" and state.instead == false)
	check("… her crew: Danny alone, picked (no hire: no money asked)", same(crewOf(ann).have, { "danny" }) and crewOf(ann).pick == "danny")
	local spentBefore = #E.spent
	local why, h = startRun("normal")
	check("her first run: Danny with the party at once (nothing paid, no hire)", why == nil and h ~= nil and h.kind == "danny" and h.name == "Danny"
		and #E.spent == spentBefore, why)
	check("… his name and kind on everybody's attributes (the HUD, the card, the guide)", ann:GetAttribute("MoveHelper") == "hired" and bob:GetAttribute("MoveHelper") == "hired"
		and ann:GetAttribute("MoveHelperName") == "Danny" and bob:GetAttribute("MoveHelperName") == "Danny" and ann:GetAttribute("MoveHelperPrice") == nil)
	check("… his body: CrewKind danny, no CrewSolo", h and h.body and h.body.model:GetAttribute("CrewKind") == "danny" and h.body.model:GetAttribute("CrewSolo") == nil)
	local hire = false
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and string.find(string.lower(tostring(d.ActionText)), "hire", 1, true) then
			hire = true
		end
	end
	check("… no \"Hire\" anywhere", not hire)
	run(C.Lobby.Every + 0.2)
	check("… the lobby's stand gone while she is in a run (he is with her)", standOf(ann) == nil)
	endRun()
	check("the run over: he goes with it", MoveHelper.find(ann) == nil and ann:GetAttribute("MoveHelper") == nil)
	run(C.Lobby.Every + 0.2)
	check("… back by her warehouse", standOf(ann) ~= nil and standOf(ann):GetAttribute("CrewKind") == "danny")
end

-- ── Ann picks Bruno: a piece for two, alone ────────────────────────────────
do
	local since = #E.messages
	crewRequest(ann, { kind = "pick", id = "bruno" })
	check("10.1 a pick of a helper not hers (Bruno): refused, how to get him said", crewOf(ann).pick == "danny" and heard(ann, "Rescue Bruno in a run first", since))
	CrewRules.add(crewOf(ann), "bruno") -- (rescued: below, in a run of its own)
	local saved = #E.savedSoon
	crewRequest(ann, { kind = "pick", id = "bruno" })
	check("… once he is hers: picked, saved soon, the window's state sent", crewOf(ann).pick == "bruno" and #E.savedSoon > saved
		and crewSent(ann, "state", since) ~= nil and crewSent(ann, "state", since).pick == "bruno")
	local why, h = startRun("normal")
	check("her next run: Bruno (his name and kind; his body's CrewSolo)", why == nil and h ~= nil and h.kind == "bruno" and h.name == "Bruno"
		and h.body.model:GetAttribute("CrewKind") == "bruno" and h.body.model:GetAttribute("CrewSolo") == true and ann:GetAttribute("MoveHelperName") == "Bruno", why)
	check("… his health his kind's", h and h.health == C.Kinds.bruno.Health)
	local spot = pieceOf(h.s, "pair") :: number
	local sofa = itemModel(spot)
	local thing = h.s.move.things[spot]
	check(`(the {thing.name}: a piece for two)`, sofa ~= nil and thing.class == "pair")
	give(sofa)
	check(`the {thing.name} given him: on his list`, h.queue[1] == spot, E.lastNotice(ann))
	E.place(ann, V3(plot1.spawn.x, 3, plot1.spawn.z)) -- (Ann away: nobody at its other end)
	local lifted = run(90, function(): boolean
		local held, role = Rules.holding(h.s.move, h.id)
		return held == spot and role == "carrier"
	end)
	check("he walks to it and lifts it ALONE (its carrier, no helper at its other end)", lifted and thing.carrier == h.id and thing.helper == nil, thing.state)
	run(0.5)
	local walk = Config.Movement.Walk
	local want = walk * H.Speed * Config.Moving.Speed.Drag * C.Kinds.bruno.Speed * C.Kinds.bruno.Solo
	check(`… slowly: the drag × his Solo × his Speed ({string.format("%.2f", want)} studs/s)`, math.abs(lastSpeed - want) < 0.05, lastSpeed)
	local loaded = run(180, function(): boolean
		return thing.state == "truck"
	end)
	check("… and into the van, alone", loaded and Rules.holding(h.s.move, h.id) == nil, thing.state)
	endRun()
end

-- ── Zip, Gus, Lucy ─────────────────────────────────────────────────────────
do
	for _, id in { "zip", "gus", "lucy" } do
		CrewRules.add(crewOf(ann), id)
	end
	crewOf(ann).pick = "zip"
	local _, h = startRun("normal")
	check("10.1 Zip comes (Ann's pick)", h ~= nil and h.kind == "zip")
	local since = #E.messages
	give(itemModel(pieceOf(h.s, "pair") :: number))
	check("Zip: a piece for two refused, why and who can said", #h.queue == 0 and heard(ann, "piece for two", since) and heard(ann, "Bruno", since))
	since = #E.messages
	local heavy = pieceOf(h.s, "both", C.Kinds.zip.Carry.Both + 1)
	give(itemModel(heavy :: number))
	check("… a heavy two-hands piece refused", heavy ~= nil and #h.queue == 0 and heard(ann, "too heavy", since))
	local light = pieceOf(h.s, "hand") :: number
	give(itemModel(light))
	check("… a one-hand piece taken", h.queue[1] == light)
	endRun()

	crewOf(ann).pick = "gus"
	local _, g = startRun("normal")
	check("Gus comes", g ~= nil and g.kind == "gus" and g.health == C.Kinds.gus.Health)
	since = #E.messages
	give(itemModel(pieceOf(g.s, "hand") :: number))
	check("Gus: every piece refused (he carries nothing: he guards)", #g.queue == 0 and heard(ann, "carries nothing", since))
	-- a zombie by Ann outside, Gus beside her
	E.place(ann, V3(House.door.x + 6, 3, House.door.z + 14))
	local at = E.rootOf(ann).Position
	if g.body then
		g.body.root.CFrame = CF(at.X + 3, at.Y, at.Z)
	end
	local z = E.Zombies.spawn("walker", at + V3(6, 0, 2), nil)
	local hits = #E.zombieHits
	run(4)
	local mine = nil
	for index = hits + 1, #E.zombieHits do
		local hit = E.zombieHits[index]
		if hit.z == z then
			mine = hit
		end
	end
	check("… a zombie by Ann: he goes for it and hits it (Zombies.damage, cause \"melee\", by nobody)", mine ~= nil and mine.amount == C.Kinds.gus.Guard.Damage
		and mine.info and mine.info.cause == "melee" and mine.by == nil, #E.zombieHits - hits)
	z.dead = true
	z.model:Destroy()
	endRun()

	crewOf(ann).pick = "lucy"
	local _, l = startRun("normal")
	run(0.6)
	local interior = l and l.s.interior
	check("Lucy in the run: CrewSense (her Sense) on Ann, Bob and the run's inside", l ~= nil and l.kind == "lucy" and ann:GetAttribute("CrewSense") == C.Kinds.lucy.Sense
		and bob:GetAttribute("CrewSense") == C.Kinds.lucy.Sense and interior ~= nil and interior:GetAttribute("CrewSense") == C.Kinds.lucy.Sense)
	endRun()
	check("… the run over: gone", ann:GetAttribute("CrewSense") == nil and bob:GetAttribute("CrewSense") == nil)
	crewOf(ann).pick = "bruno"
end

-- ── The rescue ─────────────────────────────────────────────────────────────
do
	crewOf(bob).have = { "danny", "zip" } -- (Bob has Zip already: his bonus)
	local rolls = { 0, 0 } -- (the odds: a trapped helper; the kind: the first the party lacks most)
	HelperCrew.random = function(): number
		return table.remove(rolls, 1) or 0.99
	end
	local _, h = startRun("hard")
	HelperCrew.random = function(): number
		return 0.99
	end
	local rescue = h and HelperCrew.rescueOf(h.s)
	check("10.1 a run's trapped helper (its odds rolled at its first look): one", rescue ~= nil)
	if not rescue then
		return
	end
	-- Ann lacks Zip (Bob has him), Bob lacks Bruno, Gus, Lucy; Ann has all but Zip: the most lack … each one once,
	-- Bruno, Gus, Lucy by Bob, Zip by Ann: a tie of all four, the roll's first
	local model = rescue.model
	check("… the kind the party lacks most (a tie: the roll's), his CrewKind on him, tagged RunRescue", rescue.kind == "bruno" and model:GetAttribute("CrewKind") == "bruno"
		and model:GetAttribute("RunRescue") == true and model:GetAttribute("Tag_RunRescue") == true, rescue.kind)
	local origin = h.s.origin
	local local_ = origin:PointToObjectSpace(model.PrimaryPart.Position)
	local entry = h.s.plan.entry.Position
	check(`… on a chair in a room, at least Rescue.Away ({C.Rescue.Away}) studs from the way in`, rescue.chair ~= nil and rescue.chair.Parent ~= nil
		and V3(local_.X - entry.X, 0, local_.Z - entry.Z).Magnitude >= C.Rescue.Away)
	local prompt = promptIn(model, "Untie")
	check("… \"Untie Bruno\" on him, held Rescue.Hold s", prompt ~= nil and prompt.ActionText == "Untie Bruno" and prompt.HoldDuration == C.Rescue.Hold)
	E.place(ann, model.PrimaryPart.Position + V3(4, 0, 0))
	local since = #E.messages
	run(C.Rescue.Help + 0.2)
	check("… \"Help!\" while a party player is near", (function(): boolean
		for index = #E.said, 1, -1 do
			if E.said[index] == "Help! Over here!" then
				return true
			end
		end
		return false
	end)())
	prompt.Triggered:Fire(cid)
	check("a stranger's Untie: nothing", not rescue.freed and model:GetAttribute("RunRescue") == true)
	-- Bob lacks Bruno: he joins Bob's crew; Ann has him: her bonus
	crewOf(ann).have = { "danny", "bruno", "gus", "lucy" }
	local money = #E.money
	local saved = #E.savedSoon
	prompt.Triggered:Fire(bob)
	check("Bob's Untie: freed (the tag off, RunFreed), his line said", rescue.freed and model:GetAttribute("RunRescue") == nil and model:GetAttribute("Tag_RunRescue") == nil
		and model:GetAttribute("RunFreed") == true and E.said[#E.said] == C.Kinds.bruno.Freed)
	check("… Bob lacked him: Bruno joins Bob's crew, saved soon, told", CrewRules.has(crewOf(bob), "bruno") and #E.savedSoon > saved
		and heard(bob, "Bruno joined your crew", since))
	local bonus = nil
	for index = money + 1, #E.money do
		local m = E.money[index]
		if m.player == ann and m.reason == "CrewRescue" then
			bonus = m
		end
	end
	check("… Ann has him already: the bonus instead (CrewRescue, the difficulty's)", bonus ~= nil and bonus.amount == C.Rescue.Bonus.hard and bonus.sku == "bruno"
		and heard(ann, "in your crew already", since))
	-- he follows the party: put by them in the other world
	E.place(ann, V3(House.door.x + 2, 3, House.door.z + 10))
	E.place(bob, V3(House.door.x + 4, 3, House.door.z + 10))
	run(1)
	local near = (model.PrimaryPart.Position - E.rootOf(ann).Position).Magnitude
	check("… he follows the party (out of the house: put by them)", near < 8, near)
	endRun()
	check("the run over: he goes (his body, the chair)", model.destroyed == true or model.Parent == nil)
end

-- ── Down in a run: revived, or out to hospital ─────────────────────────────
do
	crewOf(ann).pick = "bruno"
	local _, h = startRun("normal")
	check("10.1 Bruno in the run", h ~= nil and h.kind == "bruno")
	local body = h.body
	body.humanoid.Health = 0
	run(0.3)
	local model = body.model
	local untilAt = model:GetAttribute("CrewDownUntil")
	local prompt = promptIn(model, "Revive")
	check("at 0 health: down (lying, not gone): CrewDownUntil (the server time + Down.Seconds), tagged CrewDown", h.dead and h.body == body and type(untilAt) == "number"
		and math.abs(untilAt - (E.now + C.Down.Seconds)) < 1 and model:GetAttribute("Tag_CrewDown") == true)
	check(`… "Revive Bruno" on him (E held Down.Revive s, within Down.Reach)`, prompt ~= nil and prompt.ActionText == "Revive Bruno" and prompt.HoldDuration == C.Down.Revive
		and prompt.MaxActivationDistance == C.Down.Reach)
	check("… the party told (hold E by him within the seconds)", heard(ann, "Bruno is down", 0) and heard(bob, "Bruno is down", 0))
	check("… his status: down, hold E to revive him", ann:GetAttribute("MoveHelperDoing") == Brain.doing("revive"), ann:GetAttribute("MoveHelperDoing"))
	run(C.Down.Seconds / 2)
	check("… still down halfway (no getting up by himself, no van comeback)", h.dead and h.body == body)
	prompt.Triggered:Fire(cid)
	check("a stranger's revive: nothing", h.dead)
	prompt.Triggered:Fire(bob)
	run(0.3)
	check("Bob's revive within the time: up with half his health, the ring's attribute and the prompt gone", not h.dead and h.health == CrewRules.reviveHealth("bruno")
		and h.health == math.floor(C.Kinds.bruno.Health * C.Down.Health + 0.5) and model:GetAttribute("CrewDownUntil") == nil and model:GetAttribute("Tag_CrewDown") == nil
		and promptIn(model, "Revive") == nil)
	-- down again, nobody comes
	h.body.humanoid.Health = 0
	run(0.3)
	check("down again", h.dead and h.body ~= nil and h.body.model:GetAttribute("CrewDownUntil") ~= nil)
	local saved = #E.savedSoon
	local since = #E.messages
	run(C.Down.Seconds + 1)
	local left = CrewRules.hospitalLeft(crewOf(ann), "bruno", os.time())
	check("nobody in time: out of the run (his body gone), in hospital for Hospital.Seconds, saved", h.body == nil and left > C.Hospital.Seconds - 5
		and left <= C.Hospital.Seconds and #E.savedSoon > saved, left)
	check("… the party told, his status out", heard(ann, "in hospital", since) and heard(bob, "in hospital", since) and ann:GetAttribute("MoveHelperDoing") == Brain.doing("out"),
		ann:GetAttribute("MoveHelperDoing"))
	run(H.Respawn + 2)
	check("… no comeback this run", h.body == nil and MoveHelper.find(ann) == h)
	endRun()
	-- the next run: Danny instead
	since = #E.messages
	local _, next_ = startRun("normal")
	check("the next run: Bruno in hospital, Danny comes instead (said)", next_ ~= nil and next_.kind == "danny" and heard(ann, "Bruno is in hospital", since))
	endRun()
	-- the CREW window: his time left, DISCHARGE
	since = #E.messages
	crewRequest(ann, { kind = "state" })
	local state = crewSent(ann, "state", since)
	local row = state and state.rows[2]
	check("the CREW window: Bruno in hospital, his time left, the price to discharge", row ~= nil and row.id == "bruno" and row.state == "hospital" and row.left > 0
		and row.price == CrewRules.dischargePrice(row.left) and state.instead == true and state.comes == "danny")
	E.wallet[ann] = 10
	crewRequest(ann, { kind = "discharge", id = "bruno" })
	check("DISCHARGE without the money: refused, still in hospital", CrewRules.hospitalLeft(crewOf(ann), "bruno", os.time()) > 0 and heard(ann, "Not enough money", since))
	E.wallet[ann] = 5000
	local spent = #E.spent
	crewRequest(ann, { kind = "discharge", id = "bruno" })
	local paid = E.spent[#E.spent]
	check("DISCHARGE: paid (CrewDischarge), ready again", #E.spent == spent + 1 and paid.reason == "CrewDischarge" and paid.sku == "bruno"
		and paid.amount == CrewRules.dischargePrice(row.left) and CrewRules.ready(crewOf(ann), "bruno", os.time()))
	local _, again = startRun("normal")
	check("… the next run: Bruno again", again ~= nil and again.kind == "bruno")
	endRun()
end

-- ── Junk on the Crew remote ────────────────────────────────────────────────
do
	local before = crewOf(ann).pick
	crewRequest(ann, 5)
	crewRequest(ann, { kind = "pick", id = 7 })
	crewRequest(ann, { kind = "pick", id = "nobody" })
	crewRequest(ann, { kind = "discharge", id = "danny" })
	crewRequest(ann, { kind = "nonsense" })
	check("junk on the Crew remote: nothing changes", crewOf(ann).pick == before and CrewRules.ready(crewOf(ann), "danny", os.time()))
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
