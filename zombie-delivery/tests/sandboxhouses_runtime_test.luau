-- 8.9 six houses, 9.4 the countryside (the blocks marked "six houses" in server/Moving.luau), 9.7 runs: the six places to
-- empty of shared/SandboxMap.luau (Houses: The Old Farmstead and the countryside's five spots) with the real
-- server/Moving.luau (MoveLobby, MoveGreeters, MoveHelper and MoveSites with it) on tests/runtime/MovingRuntime.luau's
-- fakes, Config.Sandbox.On (tests/run_tests.py builds them; the fake art's plans record their seeds and kinds):
--   * a site per house (Move_<id>): a doormat at its front door, its "Enter house" on that house's own map door (the
--     SandboxDoor part in the model whose SandboxHouse is its id: server/SandboxWorld.luau's stand-ins; the farmstead's
--     has none: a door of no house's is the farmstead's); a back door (its doormat, "Enter by the back door") only on the
--     farmstead, which has one
--   * 9.7 a whole run on each of the six (Ann five, each at another difficulty; Bob The Pond Cabin): Moving.startRun
--     (the lobby's portal: server/Runs.luau parks the truck at the curb first), the run's state (its house, its plan's
--     kind, its difficulty: on its inside too), the truck at its curb on its yard's asphalt, its back to the door,
--     walked in through its door (no E), a piece carried out through it and loaded, FINISH at the truck: the piece in
--     the loader's warehouse, the house spent in the save; two runs at once, the back door only the farmstead's; a death
--     with the van wrecked: out of that house's own door
--   * the seed kept across a leave (the save's sandboxHouse and sandboxHouseSeed): back on this server or another, a run
--     on the same house plans the same seed; a save whose seed a trip spent: a new one; an 8.4 save (a seed, no house:
--     PlayerData gives it the farmstead's) the farmstead with its seed; a run on another house: a new seed, the save's
--     house that one
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
	return false -- (9.7: no turnaround; every place's yard is a road)
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

-- A whole run on a house ------------------------------------------------------------------------------------------------------

local THROUGH = math.max(D.Dwell, D.Open) + 0.01 -- (the zone faced Dwell s, a leaf open Open s)
local up = V3(0, Config.Furniture.EntryUp, 0)
local function stand(player: any, at: any, look: any)
	E.rootOf(player).CFrame = M.CFrame.lookAt(at, at + look)
end
-- The truck at the house's curb, as server/Runs.luau's Runs.begin parks it before Moving.startRun (Moving.parkVan, its
-- nose away from the door).
local function parkAt(player: any, h: any): any
	Moving.parkVan(player, h.curb, false)
	local truck = E.cars[player]
	park(truck, h.curb)
	return truck
end

-- `player` runs house `h` (9.7: a portal's run: Moving.startRun at `difficulty`, the truck at its curb): walked in, a
-- piece carried out and loaded, FINISH at the truck: the piece in their warehouse. Says what went wrong (nil: all of it
-- went right).
local function runOn(player: any, h: any, difficulty: string): string?
	local own = contractOf(h)
	local truck = parkAt(player, h)
	local why = Moving.startRun(player, h.id, difficulty)
	if why then
		return `startRun: {why}`
	end
	step()
	local state = E.last(player, "Moving", "state")
	local view = state and state.a
	if not view or view.contract ~= h.id or view.name ~= h.name or view.house.x ~= h.curb.x or view.house.z ~= h.curb.z then
		return `the run's state: {view and view.contract}`
	end
	if type(view.run) ~= "table" or view.run.difficulty ~= difficulty or view.run.mine ~= true then
		return "the run's view (its difficulty, the host's)"
	end
	local kind = built[#built].kind
	if kind ~= own.Kind or kind ~= h.kind then -- (9.5: the contract's kind, the place's own on the map)
		return `the plan's kind {kind}`
	end
	local marked = false -- (its inside says the run's difficulty: traps, zombies and the loot read it)
	for _, d in workspace:GetDescendants() do
		marked = marked or (not d.destroyed and d:GetAttribute("RunDifficulty") == difficulty)
	end
	if not marked then
		return "its inside without RunDifficulty"
	end
	-- the truck at its curb on the yard's asphalt, its nose away from the door, its back to it
	local facing = yawLook(h.door.yaw)
	local foot = V3(h.door.x, h.door.y, h.door.z)
	local back = truck.chassis:FindFirstChild("CargoDoor").WorldPosition
	local middle = truck.chassis.Position
	local look = truck.chassis.CFrame.LookVector
	if flat(middle, V3(h.curb.x, 0, h.curb.z)) > 1 or look:Dot(yawLook(h.curb.yaw)) < 0.99 or flat(back, foot) >= flat(middle, foot)
		or not onAsphalt(middle.X, middle.Z) or not onAsphalt(back.X, back.Z) then
		return `the truck: {middle.X}, {middle.Z}`
	end
	-- walked in through its door (no E: its walk-in zone, facing it; Rearm s after the last trip through a door)
	stand(player, foot + up + facing * 6, facing)
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
	-- a piece out through the door, into the truck
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
	-- FINISH at the truck (no drive home): what is in it goes into the loader's warehouse, the run over
	local stored = #E.collected
	E.request(player, "finish")
	if #E.collected ~= stored + 1 or Moving.busy(player) ~= nil or E.collected[#E.collected].player ~= player then
		return "FINISH"
	end
	return nil
end

-- Ann: five of the places, each at a difficulty of its own; Bob: The Pond Cabin
local order = { 1, 3, 4, 5, 6 }
local levels = { "easy", "normal", "hard", "insane", "nightmare" }
for n, index in order do
	local h = Houses[index]
	local why = runOn(ann, h, levels[n])
	check(`a run on {h.name} ({levels[n]}, its plan {contractOf(h).Kind}, on its inside): the truck at its curb (on asphalt, its back to the door), walked in and out, a piece loaded, FINISH: it is in her warehouse`,
		why == nil, why)
	check(`…her save: {h.name} spent (no seed), the house she emptied last`, E.profiles[ann].sandboxHouse == h.id and E.profiles[ann].sandboxHouseSeed == nil)
end
local whyBob = runOn(bob, Houses[2], "normal")
check(`a run on {Houses[2].name} (Bob's): the same, its own house`, whyBob == nil, whyBob)

-- Two runs at once; the back door; a death ---------------------------------------------------------------------------------

do
	parkAt(ann, Farm)
	parkAt(bob, Houses[3])
	check("(both runs)", Moving.startRun(ann, Farm.id, "normal") == nil and Moving.startRun(bob, Houses[3].id, "hard") == nil)
	step()
	local a, b = E.last(ann, "Moving", "state").a, E.last(bob, "Moving", "state").a
	check("two runs at once: Ann's on the farmstead, Bob's on The Lone House, their own interiors", a.contract == Farm.id and b.contract == Houses[3].id
		and a.id ~= b.id and a.run.difficulty == "normal" and b.run.difficulty == "hard")
	check("…Moving.houseOf: the run's house", Moving.houseOf(ann) == Farm and Moving.houseOf(bob) == Houses[3])
	local farmSite = moves:FindFirstChild(`Move_{Farm.id}`)
	local blueSite = moves:FindFirstChild(`Move_{Houses[3].id}`)
	check("the back door only on the farmstead: Enter by the back door on Ann's site, none on Bob's", promptIn(farmSite, "Enter by the back door") ~= nil
		and promptIn(blueSite, "Enter by the back door") == nil and promptIn(blueSite, "Enter house") == nil and promptIn(doorOf[Houses[3].id], "Enter house") ~= nil)
	-- a death with the van wrecked: out of the run's house's own door
	local van = E.cars[bob]
	van.wrecked = true
	local out = Moving.respawnAt(bob)
	local h = Houses[3]
	local facing = yawLook(h.door.yaw)
	check("a death with the van wrecked: 6 studs out of the run's house's own door, looking out", out ~= nil
		and flat(out.Position, V3(h.door.x, 0, h.door.z) + facing * 6) < 1e-6 and out.LookVector:Dot(facing) > 0.99, out and out.Position)
	van.wrecked = false
	-- another player with a save on a house (another server's): a run there keeps its seed
	local cy = E.player(33, "Cy", V3(plot3.spawn.x, 3, plot3.spawn.z))
	E.plots[cy] = plot3
	E.profiles[cy] = { money = 5000, sandboxHouse = Houses[4].id, sandboxHouseSeed = 777 }
	parkAt(cy, Houses[4])
	check("a save with a house and its seed (another server's): a run there plans that seed", Moving.startRun(cy, Houses[4].id, "normal") == nil
		and built[#built].seed == 777 and plans[#plans].kind == contractOf(Houses[4]).Kind and E.profiles[cy].sandboxHouseSeed == 777)
	check("…Moving.endRun: the host's run ends (nothing loaded: called off), nothing in anybody's warehouse", (function(): boolean
		local before = #E.collected
		return Moving.endRun(cy, nil) and Moving.busy(cy) == nil and #E.collected == before and not Moving.endRun(cy, nil)
	end)())
	check("…the seed still Cy's (nothing came home)", E.profiles[cy].sandboxHouse == Houses[4].id and E.profiles[cy].sandboxHouseSeed == 777)
	Moving.endRun(ann)
	Moving.endRun(bob)
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
	local house = Houses[5].id
	local dee = join(44, { money = 5000 })
	parkAt(dee, Houses[5])
	check("Dee's first run: a new seed, its house and seed in her save", Moving.startRun(dee, house, "easy") == nil and E.profiles[dee].sandboxHouse == house
		and E.profiles[dee].sandboxHouseSeed == built[#built].seed)
	local save = E.profiles[dee]
	local seed = save.sandboxHouseSeed
	E.request(dee, "giveup")
	E.leave(dee)
	check("…GIVE UP with nothing home, she leaves: her save keeps the house and the seed", save.sandboxHouse == house and save.sandboxHouseSeed == seed)
	local dee2 = join(44, table.clone(save))
	parkAt(dee2, Houses[5])
	check("back (another server, the same save): a run there plans the same seed (no reroll by leaving)", Moving.startRun(dee2, house, "easy") == nil
		and built[#built].seed == seed)
	Moving.endRun(dee2)
	E.leave(dee2)
	local dee3 = join(44, nil) -- (no save read: Studio without a DataStore: this server's memory of her)
	parkAt(dee3, Houses[5])
	check("…back on this server without a save read: this server's memory, the same seed", Moving.startRun(dee3, house, "easy") == nil and built[#built].seed == seed)
	Moving.endRun(dee3)
	E.leave(dee3)
	-- a save whose seed a trip spent (none; its house the one emptied last): a run there plans a new seed
	local dee4 = join(45, { money = 5000, sandboxHouse = house })
	parkAt(dee4, Houses[5])
	check("a save whose house was spent (its seed none): a run there plans a new seed, kept in the save", Moving.startRun(dee4, house, "easy") == nil
		and E.profiles[dee4].sandboxHouseSeed == built[#built].seed and built[#built].seed ~= seed)
	Moving.endRun(dee4)
	E.leave(dee4)
	-- an 8.4 save (a seed, no house: PlayerData reads the farmstead's into it): a run on the farmstead plans that seed
	local dee5 = join(46, { money = 5000, sandboxHouse = Farm.id, sandboxHouseSeed = 4242 })
	parkAt(dee5, Farm)
	check("an 8.4 save (its seed the farmstead's, server/PlayerData.luau's migration): a run on the farmstead plans that seed", Moving.startRun(dee5, Farm.id, "normal") == nil
		and built[#built].seed == 4242 and built[#built].kind == "big")
	Moving.endRun(dee5)
	E.leave(dee5)
	-- a run on another house than the save's: a new seed, the save's house that one now
	local dee6 = join(47, { money = 5000, sandboxHouse = Houses[2].id, sandboxHouseSeed = 999 })
	parkAt(dee6, Houses[6])
	check("a run on another house than the save's: a new seed, the save's house the run's now", Moving.startRun(dee6, Houses[6].id, "normal") == nil
		and built[#built].seed ~= 999 and E.profiles[dee6].sandboxHouse == Houses[6].id and E.profiles[dee6].sandboxHouseSeed == built[#built].seed)
	Moving.endRun(dee6)
	E.leave(dee6)
	check("Moving.startRun refuses a house there is none of (an old save's village house)", Moving.startRun(ann, "Hlavní_n_5", "normal") ~= nil and Moving.busy(ann) == nil)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
