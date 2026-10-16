-- 8.9 six houses, 9.4 the countryside (the blocks marked "six houses" in server/Moving.luau): the six places to
-- empty of shared/SandboxMap.luau (Houses: The Old Farmstead and the countryside's five spots) with the real
-- server/Moving.luau (MoveLobby, MoveGreeters, MoveHelper and MoveSites with it) on tests/runtime/MovingRuntime.luau's
-- fakes, Config.Sandbox.On (tests/run_tests.py builds them; the fake art's plans record their seeds and kinds):
--   * a site per house (Move_<id>): a doormat at its front door, its "Enter house" on that house's own map door (the
--     SandboxDoor part in the model whose SandboxHouse is its id: server/SandboxWorld.luau's stand-ins; the farmstead's
--     has none: a door of no house's is the farmstead's); a back door (its doormat, "Enter by the back door") only on the
--     farmstead, which has one
--   * two players never on one house: Ann's first card the farmstead, Bob's the next free one (The Pond Cabin); their
--     cards and moves stay apart; Ann's next cards skip the house on Bob's
--   * a whole move on each of the six (Ann five in turn, Bob The Pond Cabin): the card at your kiosk (its family, its
--     place, its clock, its plan's kind: its contract's, the place's own on the map, 9.5 the countryside's), START,
--     LAUNCH, the van called to the door (at its curb on its street's asphalt, its back to the door), walked in through
--     its door (no E), a piece carried out through it, loaded, driven home, a trip into your warehouse, FINISH; the next
--     card the next house (round to the farmstead after the last); a death with the van wrecked: out of that house's own
--     door
--   * the seed kept across a leave (the save's sandboxHouse and sandboxHouseSeed): back on this server or another, the
--     same house and the same seed; a save with a house another player here has: the next free one, its seed kept; a
--     save whose seed a trip spent (none, its house the one emptied last): the next house after it; an 8.4 save (a seed,
--     no house: PlayerData gives it the farmstead's) the farmstead with its seed
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
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

local T = Config.Moving
local S = T.Sandbox
local D = T.Doors
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
local Houses = SandboxMap.Houses
local Farm = SandboxMap.House
local plot1, plot2, plot3 = SandboxMap.Plots[1], SandboxMap.Plots[2], SandboxMap.Plots[3]
-- 9.5 the countryside: a place's card's words, its contract's (Config.Moving.Sandbox.Houses: every place of the map
-- has its own, of the place's kind)
local function contractOf(h: any): { Client: string, Address: string, Kind: string, Time: number }
	return S.Houses[h.id]
end
check("every place of the map with its contract (Config.Moving.Sandbox.Houses), of the place's own kind", (function(): boolean
	for _, h in Houses do
		local own = S.Houses[h.id]
		if not own or own.Kind ~= h.kind then
			return false
		end
	end
	return #Houses == 6
end)())
E.Zombies.findSpot = function(center: any): any
	return center + V3(60, 0, 0)
end
E.carId = "sprinter"

local function promptIn(model: any, action: string?): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and (action == nil or string.find(tostring(d.ActionText), action, 1, true) == 1) then
			return d
		end
	end
	return nil
end
local function trigger(prompt: any, player: any)
	if prompt then
		prompt.Triggered:Fire(player)
	end
end
local function step(seconds: number?)
	E.clock += seconds or 0.3
	E.now += seconds or 0.3
	Moving.step()
end
local function flat(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function yawLook(yaw: number): any
	local r = math.rad(yaw)
	return V3(-math.sin(r), 0, -math.cos(r))
end
-- A van parked at a spot ({ x, z, yaw }: SandboxMap's, its nose that way).
local function park(truck: any, spot: any)
	truck.chassis.CFrame = CF(spot.x, 2, spot.z) * M.CFrame.Angles(0, math.rad(spot.yaw), 0)
end
local function onAsphalt(x: number, z: number): boolean
	for _, r in SandboxMap.Roads do
		if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
			return true
		end
	end
	local t = SandboxMap.Turnaround
	return (x - t.x) ^ 2 + (z - t.z) ^ 2 <= t.r * t.r
end
-- The message of `kind` on `remote` sent to `player` after message `from` (nil: none).
local function since(player: any, remote: string, kind: string, from: number): any
	for index = #E.messages, from + 1, -1 do
		local m = E.messages[index]
		if m.player == player and m.remote == remote and m.kind == kind then
			return m
		end
	end
	return nil
end
-- The model of the piece at `spot` in the interior at `origin` (every move's interior has its own).
local function newItem(spot: number, origin: any): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed and d.PrimaryPart
			and (d.PrimaryPart.Position - origin.Position).Magnitude < 100 then
			return d
		end
	end
	return nil
end

-- the fake art's plans and interiors: their seeds and kinds
local plans: { { seed: number, kind: string } } = {}
local planOf = E.art.layout.plan
E.art.layout.plan = function(seed: number, kind: string): any
	table.insert(plans, { seed = seed, kind = kind })
	return planOf(seed, kind)
end
local built: { { seed: number, kind: string } } = {}
local buildOf = E.art.interior.build
E.art.interior.build = function(plan: any, origin: any): (any, any)
	table.insert(built, { seed = plan.seed, kind = plan.kind })
	return buildOf(plan, origin)
end

-- The map's front doors (server/SandboxWorld.luau's FrontDoor parts, SandboxDoor): the farmstead's on its own (a door of
-- no house's is the farmstead's, as 8.0 – 8.9's map), every other house's in a model whose SandboxHouse is its id (its
-- stand-in's); and the farmstead's back door's leaf (BackLeaf).
local doorOf: { [string]: any } = {}
for index, h in Houses do
	local parent: any = workspace
	if index > 1 then
		local holder = M.Instance.new("Model")
		holder.Name = `StandIn{index}`
		holder:SetAttribute("SandboxHouse", h.id)
		holder.Parent = workspace
		parent = holder
	end
	local door = M.Instance.new("Part")
	door.Name = "FrontDoor"
	door.Size = V3(4, 7, 0.4)
	door.CFrame = CF(h.door.x, 3.5, h.door.z) * M.CFrame.Angles(0, math.rad(h.door.yaw), 0) * CF(0, 0, 0.5)
	door:SetAttribute("SandboxDoor", true)
	door.Parent = parent
	doorOf[h.id] = door
end
local backLeaf = M.Instance.new("Part")
backLeaf.Name = "BackLeaf"
backLeaf.Size = V3(3, 7, 0.4)
backLeaf.CFrame = CF(Farm.back.x, 3.5, Farm.back.z - 0.2)
backLeaf:SetAttribute("DoorLeaf", -1)
backLeaf:SetAttribute("DoorSwing", 1)
backLeaf:SetAttribute("DoorDark", true)
backLeaf.Parent = workspace

-- Ann and Bob with saves (E.profiles: PlayerData.loaded; the seed and the house go into them)
local ann = E.player(11, "Ann", V3(plot1.spawn.x, 3, plot1.spawn.z))
local bob = E.player(22, "Bob", V3(plot2.spawn.x, 3, plot2.spawn.z))
E.plots[ann], E.plots[bob] = plot1, plot2
E.profiles[ann], E.profiles[bob] = { money = 5000 }, { money = 5000 }

-- server/SandboxBoot.luau's parkVan (as tests/sandboxmove_runtime_test.luau sets it): the player's van at the spot
Moving.parkVan = function(player: any, spot: any, _seat: boolean, carId: string?): (string?, any)
	local old = E.cars[player]
	if old then
		old.model:Destroy()
	end
	local car = E.makeCar(player, carId or Config.Sandbox.Van, V3(spot.x, 2, spot.z))
	E.cars[player] = car
	return nil, car
end

Moving.useArt(E.art)
Moving.start()

-- The sites -------------------------------------------------------------------------------------------------------------

local moves = workspace:FindFirstChild("Moves")
do
	local ok, why = true, nil :: string?
	for _, h in Houses do
		local site = moves:FindFirstChild(`Move_{h.id}`)
		local mats, back = 0, nil :: any
		for _, d in (if site then site:GetDescendants() else {}) do
			if d.Name == "WalkInMat" then
				mats += 1
			elseif d.Name == "EnterDoor2" then
				back = d
			end
		end
		local want = if h.back then 2 else 1
		if not site or site:FindFirstChild("EnterDoor") == nil or mats ~= want or (back ~= nil) ~= (h.back ~= nil) then
			ok, why = false, `{h.name}: {mats} mats, back {back ~= nil}`
		end
	end
	check("six houses: a site per house (Move_<id>), a doormat at each of its doors; a back door only on the farmstead (its own mat)", ok and #Houses == 6, why)
end

-- Two players, two houses ------------------------------------------------------------------------------------------------

-- The contract card at the player's plot's kiosk (nil: none came).
local function cardAt(player: any, plot: any): any
	local kiosk = moves:FindFirstChild(`MovingBoard{plot.id}`)
	E.place(player, kiosk:FindFirstChild("Board").Position + V3(0, 0, 4))
	local from = #E.messages
	trigger(promptIn(kiosk, "Moving contracts"), player)
	local m = since(player, "Moving", "contract", from)
	return m and m.a
end

local annCard = cardAt(ann, plot1)
local bobCard = cardAt(bob, plot2)
check("Ann's first card: the farmstead (the first house), The Nováks at the end of Pražská, its big plan, 25 minutes", annCard ~= nil and annCard.id == Farm.id
	and annCard.client == "The Nováks" and annCard.address == "the end of Pražská" and annCard.time == 25 * 60 and plans[#plans - 1].kind == "big" and annCard.busy == nil,
	annCard and annCard.id)
check(`Bob's: never Ann's house, the next free one, {Houses[2].name} ({contractOf(Houses[2]).Client}, {contractOf(Houses[2]).Address}), its contract's plan and clock`, bobCard ~= nil
	and bobCard.id == Houses[2].id and bobCard.name == Houses[2].name and bobCard.client == contractOf(Houses[2]).Client and bobCard.address == contractOf(Houses[2]).Address
	and bobCard.time == contractOf(Houses[2]).Time and plans[#plans].kind == contractOf(Houses[2]).Kind and #bobCard.contracts == 1 and bobCard.contracts[1].id == bobCard.id, bobCard and bobCard.id)
check("…each card lists only its own house (one at a time)", #annCard.contracts == 1 and annCard.contracts[1].id == Farm.id)
check("…their saves keep each card's house and seed", E.profiles[ann].sandboxHouse == Farm.id and E.profiles[bob].sandboxHouse == Houses[2].id
	and E.profiles[ann].sandboxHouseSeed == plans[#plans - 1].seed and E.profiles[bob].sandboxHouseSeed == plans[#plans].seed)
check("…Moving.houseOf: each one's card's house", Moving.houseOf(ann) == Farm and Moving.houseOf(bob) == Houses[2])
check("…their cards again: the same houses, the same seeds (nothing planned anew)", (function()
	local n = #plans
	local a, b = cardAt(ann, plot1), cardAt(bob, plot2)
	return a.id == Farm.id and b.id == Houses[2].id and #plans == n
end)())

-- A whole move on a house ---------------------------------------------------------------------------------------------------

local THROUGH = math.max(D.Dwell, D.Open) + 0.01 -- (the zone faced Dwell s, a leaf open Open s)
local up = V3(0, Config.Furniture.EntryUp, 0)
local function stand(player: any, at: any, look: any)
	E.rootOf(player).CFrame = M.CFrame.lookAt(at, at + look)
end

-- `player` (at their plot `plot`) moves house `h` out: their card, START, LAUNCH, the van called to its door, walked in,
-- a piece carried out and loaded, home, a trip, FINISH. Says what went wrong (nil: all of it went right).
local function moveOn(player: any, plot: any, h: any): string?
	local own = contractOf(h)
	local card = cardAt(player, plot)
	if not card or card.id ~= h.id then
		return `the card: {card and card.id}`
	end
	if card.client ~= own.Client or card.address ~= own.Address or card.time ~= own.Time or card.name ~= h.name then
		return "the card's words"
	end
	E.request(player, "start", card.id)
	E.Net.get("MoveLobby").OnServerEvent:Fire(player, "launch")
	step()
	local state = E.last(player, "Moving", "state")
	local view = state and state.a
	if not view or view.contract ~= h.id or view.name ~= h.name or view.house.x ~= h.curb.x or view.house.z ~= h.curb.z then
		return `the move's state: {view and view.contract}`
	end
	local kind = built[#built].kind
	if kind ~= own.Kind or kind ~= h.kind then -- (9.5: the contract's kind, the place's own on the map)
		return `the plan's kind {kind}`
	end
	-- the van called to the door: at its curb on the street's asphalt, its nose away from the door, its back to it
	local truck = E.cars[player]
	local facing = yawLook(h.door.yaw)
	local foot = V3(h.door.x, h.door.y, h.door.z)
	stand(player, foot + up + facing * 6, facing)
	E.request(player, "call")
	local back = truck.chassis:FindFirstChild("CargoDoor").WorldPosition
	local middle = truck.chassis.Position
	local look = truck.chassis.CFrame.LookVector
	if flat(middle, V3(h.curb.x, 0, h.curb.z)) > 1 or look:Dot(yawLook(h.curb.yaw)) < 0.99 or flat(back, foot) >= flat(middle, foot)
		or not onAsphalt(middle.X, middle.Z) or not onAsphalt(back.X, back.Z) then
		return `the van's call: {middle.X}, {middle.Z}`
	end
	-- walked in through its door (no E: its walk-in zone, facing it; Rearm s after the last trip through a door)
	step(D.Rearm + 0.1)
	local enter = promptIn(doorOf[h.id], "Enter house")
	if not enter or enter.Enabled or enter:GetAttribute("MoveOwner") ~= player.UserId then
		return "its Enter house on its map door (off: walked through)"
	end
	stand(player, foot + up + facing * 2, -facing)
	step(0.1)
	step(THROUGH)
	local origin = E.interiors[#E.interiors]
	local into = V3(0, 0, 1) -- (the fake plan's +Z)
	local exitAt = origin * V3(0, 0, 0.5) + up
	if (E.rootOf(player).Position - origin.Position).Magnitude > 100 then
		return "walked in"
	end
	stand(player, exitAt + into * 8, -into)
	step(0.1)
	step(D.Rearm)
	-- a piece out through the door, into the van
	local lamp = newItem(1, origin)
	E.place(player, lamp.PrimaryPart.Position + V3(1, 0, 0))
	trigger(promptIn(lamp, "Pick up"), player)
	step()
	stand(player, exitAt + into * 1, -into)
	step(0.1)
	step(THROUGH)
	local at = E.rootOf(player).Position
	if (at - origin.Position).Magnitude < 100 or math.abs(flat(at, foot) - 4) > 0.6 or E.rootOf(player).CFrame.LookVector:Dot(facing) < 0.99 then
		return `walked out: {at.X}, {at.Z}`
	end
	truck.model:SetAttribute("BackOpen", true)
	local out = V3(back.X - middle.X, 0, back.Z - middle.Z).Unit
	E.place(player, back + out * 2)
	step()
	trigger(promptIn(truck.model, "Load"), player)
	step()
	local thing: any = nil
	for _, item in E.last(player, "Moving", "state").a.items do
		if item.spot == 1 then
			thing = item
		end
	end
	if not thing or thing.state ~= "truck" then
		return `loaded: {thing and thing.state}`
	end
	-- home: a trip into the warehouse, then FINISH
	local stored = #E.collected
	park(truck, plot.vanSpot)
	step()
	if E.last(player, "Moving", "state").a.trips ~= 1 or #E.collected ~= stored + 1 then
		return "the trip home"
	end
	E.request(player, "finish")
	local result = E.last(player, "Moving", "result")
	if not result or result.a.home.pieces ~= 1 or Moving.busy(player) ~= nil then
		return "FINISH"
	end
	return nil
end

-- Ann: the farmstead, then the next place each time (Bob's card has The Pond Cabin: she never gets it), round to the
-- farmstead after the last; Bob: The Pond Cabin
local order = { 1, 3, 4, 5, 6 }
for _, index in order do
	local h = Houses[index]
	local why = moveOn(ann, plot1, h)
	check(`a move on {h.name} ({h.street}, its plan {contractOf(h).Kind}): its card, LAUNCH, the van at its curb (on asphalt, its back to the door), walked in and out, a piece home, FINISH`,
		why == nil, why)
	check(`…her save: {h.name} spent (no seed), the house she emptied last`, E.profiles[ann].sandboxHouse == h.id and E.profiles[ann].sandboxHouseSeed == nil)
end
local whyBob = moveOn(bob, plot2, Houses[2])
check(`a move on {Houses[2].name} (Bob's, at the same time as Ann's cards): the same, its own house`, whyBob == nil, whyBob)
local again = cardAt(ann, plot1)
check("Ann's card after the last house: round to the farmstead again (a new seed)", again ~= nil and again.id == Farm.id and plans[#plans].kind == "big"
	and plans[#plans].seed == E.profiles[ann].sandboxHouseSeed)
local bobNext = cardAt(bob, plot2)
check(`Bob's after {Houses[2].name}: the next free one after it ({Houses[3].name})`, bobNext ~= nil and bobNext.id == Houses[3].id, bobNext and bobNext.id)

-- Two moves at once, never on one house; the back door; a death -------------------------------------------------------------

do
	check("(both moves)", string.find(Moving.admin(ann, "start"), "started", 1, true) ~= nil and string.find(Moving.admin(bob, "start"), "started", 1, true) ~= nil)
	step()
	local a, b = E.last(ann, "Moving", "state").a, E.last(bob, "Moving", "state").a
	check("two moves at once: Ann on the farmstead, Bob on the Blue Gate House, their own interiors", a.contract == Farm.id and b.contract == Houses[3].id
		and a.id ~= b.id)
	check("…Moving.houseOf: the move's house", Moving.houseOf(ann) == Farm and Moving.houseOf(bob) == Houses[3])
	local farmSite = moves:FindFirstChild(`Move_{Farm.id}`)
	local blueSite = moves:FindFirstChild(`Move_{Houses[3].id}`)
	check("the back door only on the farmstead: Enter by the back door on Ann's site, none on Bob's", promptIn(farmSite, "Enter by the back door") ~= nil
		and promptIn(blueSite, "Enter by the back door") == nil and promptIn(blueSite, "Enter house") == nil and promptIn(doorOf[Houses[3].id], "Enter house") ~= nil)
	-- a death with the van wrecked: out of the move's house's own door
	local van = E.cars[bob]
	van.wrecked = true
	local out = Moving.respawnAt(bob)
	local h = Houses[3]
	local facing = yawLook(h.door.yaw)
	check("a death with the van wrecked: 6 studs out of the move's house's own door, looking out", out ~= nil
		and flat(out.Position, V3(h.door.x, 0, h.door.z) + facing * 6) < 1e-6 and out.LookVector:Dot(facing) > 0.99, out and out.Position)
	van.wrecked = false
	-- another player with a save on Bob's house (another server's): the next free one, its seed kept
	local cy = E.player(33, "Cy", V3(plot3.spawn.x, 3, plot3.spawn.z))
	E.plots[cy] = plot3
	E.profiles[cy] = { money = 5000, sandboxHouse = Houses[3].id, sandboxHouseSeed = 777 }
	local card = cardAt(cy, plot3)
	check("a save with a house another player is on (Bob's move): the next free one, its seed kept (never two on one house)", card ~= nil
		and card.id == Houses[4].id and E.profiles[cy].sandboxHouse == Houses[4].id and E.profiles[cy].sandboxHouseSeed == 777 and plans[#plans].seed == 777
		and plans[#plans].kind == contractOf(Houses[4]).Kind, card and card.id)
	Moving.admin(ann, "end")
	Moving.admin(bob, "end")
	E.leave(cy)
end

-- The seed kept across a leave ----------------------------------------------------------------------------------------------

do
	local function join(id: number, save: any): any
		local player = E.player(id, "Dee", V3(plot3.spawn.x, 3, plot3.spawn.z))
		E.plots[player] = plot3
		E.profiles[player] = save
		return player
	end
	local dee = join(44, { money = 5000 })
	local card = cardAt(dee, plot3)
	local save = E.profiles[dee]
	local house, seed = save.sandboxHouse, save.sandboxHouseSeed
	check("Dee's first card: a free house (not Ann's, not Bob's), its house and seed in her save", card ~= nil and house == card.id and seed == plans[#plans].seed
		and house ~= Moving.houseOf(ann).id and house ~= Moving.houseOf(bob).id, card and card.id)
	check("…her move built in it", string.find(Moving.admin(dee, "start"), "started", 1, true) ~= nil and built[#built].seed == seed)
	E.request(dee, "giveup")
	E.leave(dee)
	check("…GIVE UP with nothing home, she leaves: her save keeps the house and the seed", save.sandboxHouse == house and save.sandboxHouseSeed == seed)
	local dee2 = join(44, table.clone(save))
	local back = cardAt(dee2, plot3)
	check("back (another server, the same save): the same house and the same seed (no reroll by leaving)", back ~= nil and back.id == house
		and plans[#plans].seed == seed, back and back.id)
	E.leave(dee2)
	local dee3 = join(44, nil) -- (no save read: Studio without a DataStore: this server's memory of her)
	local remembered = cardAt(dee3, plot3)
	check("…back on this server without a save read: this server's memory, the same house and seed", remembered ~= nil and remembered.id == house
		and plans[#plans].seed == seed)
	E.leave(dee3)
	-- a save whose seed a trip spent (none; its house the one emptied last): the next house after it, a new seed
	local after = 0
	for index, h in Houses do
		if h.id == house then
			after = index
		end
	end
	local dee4 = join(45, { money = 5000, sandboxHouse = house })
	local nextCard = cardAt(dee4, plot3)
	local want: string? = nil
	for step = 1, #Houses do
		local h = Houses[(after + step - 1) % #Houses + 1]
		if h ~= Moving.houseOf(ann) and h ~= Moving.houseOf(bob) then
			want = h.id
			break
		end
	end
	check("a save whose house was spent (its seed none): the next free house after it, a new seed in the save", nextCard ~= nil and nextCard.id == want
		and E.profiles[dee4].sandboxHouse == want and E.profiles[dee4].sandboxHouseSeed == plans[#plans].seed and plans[#plans].seed ~= seed, nextCard and nextCard.id)
	E.leave(dee4)
	-- an 8.4 save (a seed, no house: PlayerData reads the farmstead's into it), the farmstead free: the farmstead, that seed
	Moving.admin(ann, "refill") -- (Ann's card off the farmstead)
	local dee5 = join(46, { money = 5000, sandboxHouse = Farm.id, sandboxHouseSeed = 4242 })
	local farmCard = cardAt(dee5, plot3)
	check("an 8.4 save (its seed the farmstead's, server/PlayerData.luau's migration): the farmstead with that seed", farmCard ~= nil and farmCard.id == Farm.id
		and plans[#plans].seed == 4242 and plans[#plans].kind == "big", farmCard and farmCard.id)
	E.leave(dee5)
end

-- Every house taken -----------------------------------------------------------------------------------------------------

do
	-- (six players' cards on the six houses: a seventh player's card says why, no house rolled)
	local players = {}
	local plotsFree = SandboxMap.Plots
	for n = 1, 4 do
		local p = E.player(60 + n, `P{n}`, V3(plot3.spawn.x, 3, plot3.spawn.z))
		E.plots[p] = plotsFree[(n - 1) % #plotsFree + 1]
		E.profiles[p] = { money = 5000 }
		table.insert(players, p)
		cardAt(p, E.plots[p])
	end
	local seen: { [string]: boolean } = {}
	local distinct = true
	for _, p in { ann, bob, table.unpack(players) } do
		local h = Moving.houseOf(p)
		if not h or seen[h.id] then
			distinct = false
		elseif h then
			seen[h.id] = true
		end
	end
	check("six players, six cards, six houses: never one house on two cards", distinct)
	local last = E.player(70, "Seventh", V3(plot3.spawn.x, 3, plot3.spawn.z))
	E.plots[last] = plot3
	E.profiles[last] = { money = 5000 }
	local planned = #plans
	local card = cardAt(last, plot3)
	check("…a seventh: no card, no house rolled; the board says every place is being emptied", card == nil and #plans == planned
		and string.find(E.lastNotice(last), "Every place", 1, true) ~= nil and Moving.houseOf(last) == nil, E.lastNotice(last))
	E.leave(players[1])
	card = cardAt(last, plot3)
	check("…one leaves: theirs is free again, the seventh gets it", card ~= nil and Moving.houseOf(last) ~= nil, card and card.id)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
