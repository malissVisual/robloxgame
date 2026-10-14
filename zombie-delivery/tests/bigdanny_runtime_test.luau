-- 8.3 the big move × Danny for hire: the real server/Moving.luau, server/MoveHelper.luau (on
-- tests/runtime/MovingRuntime.luau's fakes, Config.Sandbox.On) with the real art (shared/FurnitureLooks.luau,
-- shared/HouseLayout.luau's kind "big", server/HouseInterior.luau: tests/run_tests.py builds them on the recorder), a solo
-- move into the sandbox's big house (The Old Chalet, the owner's big Blender house: its big plan). No
-- physics, no pathfinding: his walk is a straight step (useMover, as tests/movehelper_art_runtime_test.luau's), a carried
-- piece goes where its carrier is (the test moves it); his paths through the real walls are PathfindingService's in
-- Roblox (the big house's doorways are a house's; its leaves PassThrough: tests/biglayout_test.luau), the floor under
-- his end tests/movehelper_hop_runtime_test.luau's.
--   * Danny comes with the van, for hire (MoveHelper "offer", the big house's price: MoveHelperBrain.hirePrice); his ways
--     are the house's two (the front door, the back door: Moving's ways, their insides the plan's exits, their outsides
--     the map's doors), every doorway of the plan his to keep out of, every piece may leave by either
--     (Moving.helperExits: HouseLayout.exitsFor); not hired, he touches nothing;
--   * Ann hires him (PlayerData.spend "HelperHire") and gives him two pieces (a click on each, from beside it): a light
--     one (the one whose way to the van is the back door's by the most; a plan with none clearly so: the front door's)
--     and a piece for two (the nearest to the back door in a room off the corridor); he carries the light one out by the
--     door nearer, either (MoveHelperBrain.routeVia over his two ways: from the corridor's east end the back door, from
--     the hall the front door) and loads it at the van at the curb, never a piece for two alone; then he goes to the
--     piece for two and waits there ("give me a hand!", the crew's toast, "🙋 Danny needs you", "Lift with Danny");
--   * Ann in by the back door: Lift with Danny, they carry it out of its room by its doorway, along the corridor and out
--     of the back door together (the door nearer to it; walked into, no E: he comes through with it, behind the house at
--     its far end, on the ground), round the house to the van; loaded, off his list.
--   * 8.3 the doors swing (server/Moving.luau WalkIn.helper): hired, the leaves of a door he goes out by (the
--     interior's, shared/DoorSwing.luau's) are open as he goes through.
-- (math.randomseed: the sandbox's seeds are math.random's.)
math.randomseed(83) -- (the sandbox's seeds are math.random's: one plan every run)
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Rules = require("./MovingRules")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local SandboxMap = require("./SandboxMap")
local PairCarry = require("./PairCarry")
local Brain = require("./MoveHelperBrain")

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
local H = Config.MoveHelper
local WALK = Config.Movement.Walk
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
local House = SandboxMap.House
local plot = SandboxMap.Plots[1]
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (no roamers near)
end

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

-- His walk: straight toward the point, speed × dt a step.
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
	end,
	halt = function(body: any)
		body.walking = false
	end,
})

-- the sandbox: Ann's plot, her own van (server/SandboxBoot.luau's parkVan, the test's: as tests/sandboxmove_runtime_test.luau)
local ann = E.player(11, "Ann", V3(plot.spawn.x, 3, plot.spawn.z))
E.plots[ann] = plot
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
-- the map's front door (server/SandboxWorld.luau's FrontDoor: the attribute SandboxDoor)
local frontDoor = M.Instance.new("Part")
frontDoor.Name = "FrontDoor"
frontDoor.Size = V3(House.doorWidth, 7, 0.4)
frontDoor.CFrame = CF(House.door.x, 3.5, House.door.z + 0.5)
frontDoor:SetAttribute("SandboxDoor", true)
frontDoor.Parent = workspace
Moving.start()

local function promptIn(model: any, action: string): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and d.ActionText ~= nil and string.find(tostring(d.ActionText), action, 1, true) == 1 then
			return d
		end
	end
	return nil
end
local function trigger(prompt: any, player: any)
	prompt.Triggered:Fire(player)
end
local function distance(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function told(player: any, text: string, from: number): boolean
	for index = from + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) then
			return true
		end
	end
	return false
end

local danny: any = nil
local carried: any = nil -- (what Ann carries: in front of her)
local function pieceOf(spot: number): any
	return built[#built].pieces[spot]
end
local function follow(model: any)
	model.PrimaryPart.CFrame = E.rootOf(ann).CFrame * CF(0, 0, -3)
end
-- 8.3 a click on a piece (its model: the Moving remote's ("helper", "assign", model)) by Ann, from beside it.
local function give(model: any)
	local was = E.rootOf(ann).Position
	E.place(ann, model.PrimaryPart.Position + V3(3, 0, 0))
	E.request(ann, "helper", "assign", model)
	E.place(ann, was)
end
local function markOf(model: any): string?
	local gui = model.PrimaryPart:FindFirstChild("DannyMark")
	local label = gui and gui:FindFirstChild("Label")
	return if label then label.Text else nil
end
local function listIs(list: { number }): boolean
	if #danny.queue ~= #list then
		return false
	end
	for index, spot in list do
		if danny.queue[index] ~= spot then
			return false
		end
	end
	return true
end
-- His ways through the doors: each transfer (his doorAt) by the way whose inside or outside he came out at; the way
-- he first went through with a piece in his arms (8.3: his list's), by spot.
local through = { 0, 0 }
local leafNear, leafOpen = { 0, 0 }, { 0, 0 } -- (8.3: by way, at his transfers: the interior's leaves there, those open)
local carriedBy: { [number]: number } = {}
local pairAlone = false
local lastDoor = -math.huge
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		MoveHelper.step(0.1)
		local h = danny
		if h and h.body then
			local spot, role = Rules.holding(h.s.move, h.id)
			if spot and role == "carrier" then
				pieceOf(spot).PrimaryPart.CFrame = h.body.root.CFrame * CF(0, 0, -1.5)
				pairAlone = pairAlone or h.s.move.things[spot].class == "pair"
			end
			if h.doorAt ~= lastDoor and h.doorAt > 0 then
				lastDoor = h.doorAt
				local at = h.body.root.Position
				local best, which = math.huge, 0
				for k, way in h.ways do
					local d = math.min(distance(at, way.outside.Position), distance(at, way.entryIn.Position))
					if d < best then
						best, which = d, k
					end
				end
				through[which] = (through[which] or 0) + 1
				if spot and role == "carrier" and carriedBy[spot] == nil then
					carriedBy[spot] = which
				end
				-- (8.3 the doors swing: out of the house, that way's leaves inside, the interior's, open as he goes through:
				-- WalkIn.helper, the move's look while he walked up to them)
				local way = h.ways[which]
				local out = way ~= nil and distance(at, way.outside.Position) < distance(at, way.entryIn.Position)
				for _, d in (if out then built[#built].model:GetDescendants() else {}) do
					if d:GetAttribute("DoorLeaf") ~= nil then
						local p = if d.ClassName == "Model" then d.PrimaryPart.CFrame.Position else d.CFrame.Position
						leafNear[which] = (leafNear[which] or 0) + (if distance(p, way.exitIn) < 6 then 1 else 0)
						leafOpen[which] = (leafOpen[which] or 0) + (if distance(p, way.exitIn) < 6 and d:GetAttribute("DoorOpen") == true then 1 else 0)
					end
				end
			end
		end
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

-- ── A solo move into the real big plan ───────────────────────────────────────

local started = Moving.admin(ann, "start")
check("a solo move into the big house starts (the real big house's plan)", string.find(started, "started", 1, true) ~= nil and #built == 1
	and built[1].plan.kind == "big", started)
Moving.step()
danny = MoveHelper.find(ann)
local truck = E.cars[ann]
-- the van at the big house's curb (the Driver's call's spot: its nose to the road, its back to the door), its back open
truck.chassis.CFrame = CF(House.curb.x, 2, House.curb.z) * M.CFrame.Angles(0, math.rad(House.curb.yaw), 0)
truck.model:SetAttribute("BackOpen", true)
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
local plan = built[1].plan
local origin = built[1].origin
check("Danny comes with the van, for hire (not hired yet)", danny ~= nil and danny.body ~= nil and danny.hirer == nil)
danny.body.root.CFrame = CF(cargoDoor.WorldPosition + V3(3, 1, 3)) -- (by the van's back at the curb)

local exits = HouseLayout.exitsOf(plan)
local ways = danny.ways
check("his ways: the big house's two, their insides the plan's exits (the front door's, the back door's)", #ways == 2
	and distance(ways[1].exitIn, origin * exits[1]) < 1 and distance(ways[2].exitIn, origin * exits[2]) < 1,
	`{#ways} ways`)
check("…their outsides the map's doors: the front door (House.door), the back door in the back wall (House.back)", #ways == 2
	and distance(ways[1].outside.Position, V3(House.door.x, 0, House.door.z)) < 6 and distance(ways[2].outside.Position, V3(House.back.x, 0, House.back.z)) < 6
	and ways[2].outside.Position.Z > House.back.z)
check(`…every doorway of the plan his to keep out of ({#danny.doorways} for the plan's {#plan.doors})`, #danny.doorways >= #plan.doors)
local both = true
for _, s in plan.spots do
	local list = Moving.helperExits(danny.s, s.id)
	both = both and #list == 2 and list[1] == 1 and list[2] == 2
end
check("every piece may leave by either door (Moving.helperExits: HouseLayout.exitsFor)", both)

-- ── For hire: the big house's price, he touches nothing ──────────────────────

E.place(ann, V3(House.curb.x - 60, 3, House.curb.z - 30)) -- (out on the road, out of the way: nobody handles a thing)
local price = danny.price
run(5)
local touched = false
for _, thing in danny.s.move.things do
	touched = touched or thing.state ~= "home"
end
check(`for hire on the big house ({Brain.money(price)}: MoveHelperBrain.hirePrice of its {#danny.s.move.order} pieces): Ann's strip says so, he touches nothing`,
	price == Brain.hirePrice(#danny.s.move.order) and ann:GetAttribute("MoveHelper") == "offer" and ann:GetAttribute("MoveHelperPrice") == price
	and Rules.holding(danny.s.move, danny.id) == nil and not touched, ann:GetAttribute("MoveHelperPrice"))

-- ── The two pieces: a light one by the back door's way, one for two off the corridor ─

local van = cargoDoor.WorldPosition
local function wayCost(at: any, way: number): number
	return (Brain.routeVia(true, at.X, at.Z, false, van.X, van.Z, danny.wayDoors, { way }))
end
-- the light one: the piece (not for two) whose way to the van is the back door's by the most (a plan with none clearly
-- so: the front door's by the most), either door
local light: any = nil
local lightBy = -math.huge
local front: any = nil
local frontBy = math.huge
for _, s in plan.spots do
	local thing = danny.s.move.things[s.id]
	local def = FurnitureLooks.Items[s.item]
	if thing.state == "home" and def.class ~= "pair" and not def.fragile and Rules.canLoad(danny.s.move, s.id) then
		local at = pieceOf(s.id).PrimaryPart.Position
		local by = wayCost(at, 1) - wayCost(at, 2)
		if by > lightBy then
			light, lightBy = s, by
		end
		if by < frontBy then
			front, frontBy = s, by
		end
	end
end
if lightBy <= 5 then
	light, lightBy = front, frontBy
end
local lightWay = if lightBy > 0 then 2 else 1
local lightModel = if light then pieceOf(light.id) else nil
local lightName = if light then FurnitureLooks.Items[light.item].name else "?"
check(`a light piece: the {lightName} (its way to the van {if lightWay == 2 then "the back door's" else "the front door's"}, {math.floor(math.abs(lightBy))} studs shorter)`,
	light ~= nil and math.abs(lightBy) > 5, lightBy)
-- the piece for two: in a room off the corridor, the nearest to the back door (nearer to it than to the front door)
local backDoor: any = nil
for index, d in plan.doors do
	if index > 1 and d.rooms[2] == "outside" then
		backDoor = d
	end
end
local byRoom: { [string]: any } = {}
for _, d in plan.doors do
	if d.rooms[2] == "corridor" then
		byRoom[d.rooms[1]] = d
	elseif d.rooms[1] == "corridor" and d.rooms[2] ~= "outside" then
		byRoom[d.rooms[2]] = d
	end
end
local pick: any = nil
local pickDoor: any = nil
for _, s in plan.spots do
	local thing = danny.s.move.things[s.id]
	local def = FurnitureLooks.Items[s.item]
	local door = byRoom[s.room]
	if thing.state == "home" and def.class == "pair" and door and not def.fragile then
		local d = distance(s.at.Position, backDoor.at)
		if not pick or d < distance(pick.at.Position, backDoor.at) then
			pick, pickDoor = s, door
		end
	end
end
check("a heavy piece for two in a room off the corridor, nearer to the back door than to the front door", pick ~= nil and backDoor ~= nil
	and distance(pick.at.Position, exits[2]) < distance(pick.at.Position, exits[1]), pick and pick.item)
local pairModel = if pick then pieceOf(pick.id) else nil
local pairName = if pick then FurnitureLooks.Items[pick.item].name else "?"

-- ── Ann hires him, gives him both ────────────────────────────────────────────

local money = E.wallet[ann] or E.startMoney
local spentAt = #E.spent
E.request(ann, "helper", "hire")
local paid = E.spent[spentAt + 1]
run(0.3)
check(`Ann hires Danny: {Brain.money(price)} paid (PlayerData.spend "HelperHire"), hers`, danny.hirer == ann and paid ~= nil and paid.player == ann
	and paid.amount == price and paid.reason == "HelperHire" and E.wallet[ann] == money - price and ann:GetAttribute("MoveHelper") == "hired")
if light and pick then
	give(lightModel)
	give(pairModel)
end
local said = #E.said
local noticeAt = #E.messages
check(`…and gives him the {lightName}, then the {pairName}: his list in that order, numbered over them`, light ~= nil and pick ~= nil
	and listIs({ light.id, pick.id }) and markOf(lightModel) == "🧑‍🔧 Danny · 1" and markOf(pairModel) == "🧑‍🔧 Danny · 2", #danny.queue)

-- ── He carries the light one out by the door nearer, then waits at the piece for two ─

local loaded = light ~= nil and run(300, function()
	return danny.s.move.things[light.id].state == "truck"
end)
check(`he carries the {lightName} out by the door nearer (this plan: {if lightWay == 2 then "the back door" else "the front door"}) and loads it at the van at the curb`,
	loaded and carriedBy[light.id] == lightWay, light and carriedBy[light.id])
check("…never a piece for two alone", not pairAlone)
check(`8.3 hired, he opens the doors he goes through (WalkIn.helper): out by a way, its leaves inside open as he went (by the front door {leafOpen[1]} of {leafNear[1]}, by the back door {leafOpen[2]} of {leafNear[2]})`,
	leafNear[lightWay] > 0 and leafOpen[1] == leafNear[1] and leafOpen[2] == leafNear[2])
-- (his way to the van from the corridor's east end, Brain.routeVia over his ways' doors: the back door; from the
-- hall the front door)
local east = origin * exits[2]
local hall = origin * (exits[1] + V3(0, 0, 4))
local _, fromEast = Brain.routeVia(true, east.X, east.Z, false, van.X, van.Z, danny.wayDoors, Moving.helperExits(danny.s, nil))
local _, fromHall = Brain.routeVia(true, hall.X, hall.Z, false, van.X, van.Z, danny.wayDoors, Moving.helperExits(danny.s, nil))
check(`…the door nearer: the back door from the corridor's east end, the front door from the hall (this run: {through[1]} times by the front door, {through[2]} by the back door)`,
	fromEast == 2 and fromHall == 1, `{fromEast} {fromHall}`)
local waiting = pick ~= nil and run(120, function()
	return danny.needs == pick.id and danny.needsAt > 0
end)
check(`then the {pairName} (two people): he goes to it and waits there, his list the {pairName}`, waiting and danny.action == "needs" and listIs({ pick.id })
	and distance(danny.body.root.Position, pairModel.PrimaryPart.Position) < 12)
check("…\"give me a hand!\", the crew's toast, \"🙋 Danny needs you\" over it, its prompt \"Lift with Danny\"", pairModel ~= nil
	and E.saidSince("This one's too heavy for me alone, give me a hand!", said) and told(ann, `Danny is at the {pairName}: lift it with him.`, noticeAt)
	and markOf(pairModel) == "🙋 Danny needs you" and pairModel:GetAttribute("DannyNeeds") == true and promptIn(pairModel, "Lift with Danny") ~= nil,
	pairModel and markOf(pairModel))

-- ── Ann answers by the back door: the piece for two out of the back door together ─

if pick and backDoor then
	local model = pairModel
	carried = model
	local y = origin.Position.Y + 3
	local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{House.id}`)
	local back = V3(House.back.x, 3, House.back.z)
	E.place(ann, back + V3(0, 0, 4))
	trigger(promptIn(site, "Enter by the back door"), ann)
	check("Ann in by the back door: inside, by the corridor's east end", distance(E.rootOf(ann).Position, origin * exits[2]) < Config.Furniture.EntryIn + 1.5,
		E.rootOf(ann).Position)
	-- at the piece's front, facing it: Lift with Danny (a call he answers at once: he is there)
	local size = FurnitureLooks.Items[pick.item].size
	local front = model.PrimaryPart.CFrame * CF(0, 0, -(size.Z / 2 + 2))
	E.rootOf(ann).CFrame = M.CFrame.lookAt(V3(front.Position.X, y, front.Position.Z), V3(model.PrimaryPart.Position.X, y, model.PrimaryPart.Position.Z))
	noticeAt = #E.messages
	trigger(promptIn(model, "Lift with Danny"), ann)
	local function helped(): boolean
		return math.abs((ann.Character:GetAttribute("CarrySpeed") or 0) - WALK * T.Speed.Pair) < 1e-6
	end
	local up = run(40, helped)
	check(`Ann lifts the {pairName} with Danny: up together (the two-person walk)`, up and ann.Character:GetAttribute("MoveCarry") == pick.id, ann.Character:GetAttribute("MoveCarry"))
	check("…off his list (lifted with him), the marker gone", #danny.queue == 0 and markOf(model) == nil and model:GetAttribute("DannyNeeds") == nil
		and not told(ann, "You took", noticeAt))
	local function farEnd(): any
		return (model.PrimaryPart.CFrame * CF(0, 0, -(model.PrimaryPart.Size.Z / 2 + H.Standoff))).Position
	end
	local steer = PairCarry.newSteer(0)
	local function walk(to: any): (number, boolean, number)
		local worst, down, high = 0, false, 0
		for _ = 1, 600 do
			local here = E.rootOf(ann).Position
			local way = V3(to.X - here.X, 0, to.Z - here.Z)
			if way.Magnitude < 0.05 then
				break
			end
			local look = E.rootOf(ann).CFrame.LookVector
			steer.heading = PairCarry.yawOf(look.X, look.Z)
			local factor = PairCarry.steer(steer, way.X, way.Z, 0.1, math.rad(ann.Character:GetAttribute("PairTurn") or H.PairTurn))
			local nextAt = here + way.Unit * math.min((ann.Character:GetAttribute("CarrySpeed") or 0) * factor * 0.1, way.Magnitude)
			E.rootOf(ann).CFrame = CF(nextAt) * M.CFrame.Angles(0, steer.heading, 0)
			follow(model)
			run(0.1)
			local _, role = Rules.holding(danny.s.move, danny.id)
			if role == "helper" then
				worst = math.max(worst, distance(danny.body.root.Position, farEnd()))
				high = math.max(high, math.abs(danny.body.root.Position.Y - E.rootOf(ann).Position.Y))
			else
				down = true
			end
		end
		return worst, down, high
	end
	follow(model)
	run(0.6)
	-- out of its room by its doorway (across the doorway's wall), along the corridor to the back door's inside
	local door = pickDoor
	local across = if door.axis == "X" then V3(0, 0, 1) else V3(1, 0, 0) -- (a doorway in a wall along X: through it along Z)
	local room = byRoom[pick.room]
	local roomRect: any = nil
	for _, r in plan.rooms do
		if r.id == pick.room then
			roomRect = r
		end
	end
	local mid = (roomRect.min + roomRect.max) / 2
	local sign = if (door.at - mid):Dot(across) > 0 then 1 else -1
	local inRoom = origin * (door.at - across * sign * 5)
	local inHall = origin * (door.at + across * sign * 5)
	local exitIn = origin * exits[2]
	local w1, d1, h1 = walk(V3(inRoom.X, y, inRoom.Z))
	local w2, d2, h2 = walk(V3(inHall.X, y, inHall.Z))
	local w3, d3, h3 = walk(V3(exitIn.X - (Config.Moving.Doors.Depth + 4.5), y, exitIn.Z)) -- (8 studs short of it: clear of its zone)
	check("out of its room by its doorway and along the corridor to the back door together: he never leaves its far end, on the floor",
		math.max(w1, w2, w3) < 0.05 and not (d1 or d2 or d3) and helped() and math.max(h1, h2, h3) < 0.5 and room ~= nil, `{math.max(w1, w2, w3)} off, {math.max(h1, h2, h3)} up`)
	-- out of the back door, the door nearer to it (8.1 walk-in doors: into its zone facing it, the dwell): he comes
	-- through with it
	local inZone = false
	for _ = 1, 40 do
		E.rootOf(ann).CFrame = M.CFrame.lookAt(V3(exitIn.X - 1.5, y, exitIn.Z), V3(exitIn.X + 1, y, exitIn.Z))
		follow(model)
		run(0.1)
		if (E.rootOf(ann).Position - origin.Position).Magnitude > 1000 then
			inZone = true
			break
		end
	end
	follow(model)
	run(0.3)
	local out = E.rootOf(ann).Position
	check("out of the back door together (the door nearer; walked into it, no E): behind the house (south of it), Danny with it at its far end, on the ground",
		inZone and distance(out, V3(House.back.x, 0, House.back.z)) < 6 and out.Z > House.back.z and distance(danny.body.root.Position, farEnd()) < 0.05
		and math.abs(danny.body.root.Position.Y - out.Y) < 0.5 and helped(), `{out.X}, {out.Y}, {out.Z}`)
	-- round the house to the van's back
	local backAt = cargoDoor.WorldPosition
	local away = V3(backAt.X - truck.chassis.Position.X, 0, backAt.Z - truck.chassis.Position.Z).Unit
	local eastSide = House.house.x + House.house.sx / 2 + 10 -- (round the house's east side)
	local w4, d4 = walk(V3(eastSide, 3, House.back.z + 6))
	local w6, d6 = walk(V3(eastSide, 3, House.door.z - 6))
	local w5, d5 = walk(backAt + away * 3)
	check("round the house to the van at the curb together, no drop", math.max(w4, w5, w6) < 0.05 and not (d4 or d5 or d6) and helped(), math.max(w4, w5, w6))
	run(0.2)
	trigger(promptIn(truck.model, "Load"), ann)
	check(`Ann loads the {pairName}: in the van, beside the {lightName}`, danny.s.move.things[pick.id].state == "truck" and ann.Character:GetAttribute("MoveCarry") == nil
		and danny.s.move.things[light.id].state == "truck", E.lastNotice(ann))
end

Moving.admin(ann, "end")
run(0.2)
check("the move ends: he goes, the big house's inside taken down", MoveHelper.find(ann) == nil and E.destroyed == 1)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
