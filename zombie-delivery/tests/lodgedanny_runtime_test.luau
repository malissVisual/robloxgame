-- 8.3 the lodge × Danny: the real server/Moving.luau, server/MoveHelper.luau (on tests/runtime/MovingRuntime.luau's
-- fakes, Config.Sandbox.On) with the real art (shared/FurnitureLooks.luau, shared/HouseLayout.luau's kind "lodge",
-- server/HouseInterior.luau: tests/run_tests.py builds them on the recorder), a solo move into The Alpine Lodge. No
-- physics, no pathfinding: his walk is a straight step (useMover, as tests/movehelper_art_runtime_test.luau's), a carried
-- piece goes where its carrier is (the test moves it); his paths through the real walls are PathfindingService's in
-- Roblox (the lodge's doorways are a house's; its leaves PassThrough: tests/lodgelayout_test.luau), the floor under
-- his end tests/movehelper_hop_runtime_test.luau's.
--   * Danny comes with the van on AUTO; his ways are the lodge's two (the front door, the terrace door: Moving's ways,
--     their insides the plan's exits, their outsides the map's doors), every doorway of the plan his to keep out of,
--     every piece may leave by either (Moving.helperExits: HouseLayout.exitsFor);
--   * AUTO on the lodge: a heavy piece nobody handles (a piece for two), he goes to it and asks for a hand ("give me a
--     hand!", the 🙋 marker); nobody comes: the light pieces, carried out and loaded at the van at the curb, never a
--     heavy one alone; his way to the van by the door nearer (from the corridor's east end the terrace door, from the
--     hall the front door: MoveHelperBrain.routeVia over his two ways);
--   * Ann in by the terrace door: she lifts a piece for two (the nearest to it in a room off the corridor) with him,
--     they carry it out of its room by its doorway, along the corridor and out of the terrace door together (walked
--     into, no E: he comes through with it, on the terrace at its far end, on the ground), round to the van; loaded.
-- (math.randomseed: the sandbox's seeds are math.random's; 80 seeds passed when it was written.)
math.randomseed(83) -- (the sandbox's seeds are math.random's: one lodge every run)
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
local function askPrompt(model: any): any -- (Moving's "<Lift / Pick up> with Danny")
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and string.find(tostring(d.ActionText), ` with {H.Name}`, 1, true) then
			return d
		end
	end
	return nil
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
-- His ways through the doors: each transfer (his doorAt) by the way whose inside or outside he came out at.
local through = { 0, 0 }
local heavyAlone = false
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
				local thing = h.s.move.things[spot]
				heavyAlone = heavyAlone or not Brain.light(thing.class, thing.weight)
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

-- ── A solo move into the real lodge ──────────────────────────────────────────

local started = Moving.admin(ann, "start")
check("a solo move into The Alpine Lodge starts (the real lodge's plan)", string.find(started, "started", 1, true) ~= nil and #built == 1
	and built[1].plan.kind == "lodge", started)
Moving.step()
danny = MoveHelper.find(ann)
local truck = E.cars[ann]
-- the van at the lodge's curb (the Driver's call's spot: its nose to the road, its back to the door), its back open
truck.chassis.CFrame = CF(House.curb.x, 2, House.curb.z) * M.CFrame.Angles(0, math.rad(House.curb.yaw), 0)
truck.model:SetAttribute("BackOpen", true)
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
local plan = built[1].plan
local origin = built[1].origin
check("Danny comes with the van, on AUTO", danny ~= nil and danny.body ~= nil and danny.mode == "auto")
danny.body.root.CFrame = CF(cargoDoor.WorldPosition + V3(3, 1, 3)) -- (by the van's back at the curb)

local exits = HouseLayout.exitsOf(plan)
local ways = danny.ways
check("his ways: the lodge's two, their insides the plan's exits (the front door's, the terrace door's)", #ways == 2
	and distance(ways[1].exitIn, origin * exits[1]) < 1 and distance(ways[2].exitIn, origin * exits[2]) < 1,
	`{#ways} ways`)
check("…their outsides the map's doors: the front door (House.door), the terrace door on the east wall (House.back)", #ways == 2
	and distance(ways[1].outside.Position, V3(House.door.x, 0, House.door.z)) < 6 and distance(ways[2].outside.Position, V3(House.back.x, 0, House.back.z)) < 6
	and ways[2].outside.Position.X > House.back.x)
check(`…every doorway of the plan his to keep out of ({#danny.doorways} for the plan's {#plan.doors})`, #danny.doorways >= #plan.doors)
local both = true
for _, s in plan.spots do
	local list = Moving.helperExits(danny.s, s.id)
	both = both and #list == 2 and list[1] == 1 and list[2] == 2
end
check("every piece may leave by either door (Moving.helperExits: HouseLayout.exitsFor)", both)

-- ── AUTO: he asks for a hand with a heavy piece, nobody comes, the light ones ─

E.place(ann, V3(House.curb.x - 60, 3, House.curb.z - 30)) -- (out on the road, out of the way: nobody handles a thing)
local said = #E.said
local noticeAt = #E.messages
local asked = run(60, function()
	return danny.ask ~= nil and (danny.askAt or 0) > 0
end)
local askSpot = danny.ask
local askThing = if askSpot then danny.s.move.things[askSpot] else nil
local askModel = if askSpot then pieceOf(askSpot) else nil
check("AUTO on the lodge: a heavy piece nobody handles (a piece for two), he goes to it and asks", asked and askThing ~= nil
	and not Brain.light(askThing.class, askThing.weight) and danny.action == "ask", askThing and askThing.item)
check("…beside it: \"give me a hand!\", the crew's toast, the 🙋 marker, \"Lift with Danny\" (or Pick up)", askModel ~= nil
	and E.saidSince("This one's too heavy for me alone, give me a hand!", said) and told(ann, "Danny needs a hand", noticeAt)
	and askModel.PrimaryPart:FindFirstChild("DannyAsk") ~= nil and askPrompt(askModel) ~= nil
	and distance(danny.body.root.Position, askModel.PrimaryPart.Position) < 12)
local gaveUp = run(H.AskWait + 2, function()
	return danny.ask == nil
end)
check("…nobody came: back to the light pieces", gaveUp and askModel ~= nil and askModel.PrimaryPart:FindFirstChild("DannyAsk") == nil)
-- the light pieces carried out and loaded (both doors), never a heavy one alone
local loaded: { number } = {}
local function inVan(): number
	local n = 0
	for _, thing in danny.s.move.things do
		n += if thing.state == "truck" then 1 else 0
	end
	return n
end
run(300, function()
	return inVan() >= 6 and through[1] > 0
end)
for spot, thing in danny.s.move.things do
	if thing.state == "truck" then
		table.insert(loaded, spot)
	end
end
check(`AUTO: he carries the lodge's light pieces out and loads them at the curb ({#loaded} in the van)`, #loaded >= 4, #loaded)
check("…never a heavy one alone", not heavyAlone)
-- (his way to the van from the corridor's east end, Brain.routeVia over his ways' doors: the terrace door; from the
-- hall the front door)
local van = cargoDoor.WorldPosition
local east = origin * exits[2]
local hall = origin * (exits[1] + V3(0, 0, 4))
local _, fromEast = Brain.routeVia(true, east.X, east.Z, false, van.X, van.Z, danny.wayDoors, Moving.helperExits(danny.s, nil))
local _, fromHall = Brain.routeVia(true, hall.X, hall.Z, false, van.X, van.Z, danny.wayDoors, Moving.helperExits(danny.s, nil))
check(`…by the door nearer: the terrace door from the corridor's east end, the front door from the hall (this run: {through[1]} times by the front door, {through[2]} by the terrace)`,
	through[1] > 0 and fromEast == 2 and fromHall == 1, `{fromEast} {fromHall}`)

-- ── Ann answers by the terrace door: the heavy piece out of the terrace door together ─

-- (the heavy piece Danny asked about, or another heavy one in a room off the corridor: the nearest to the terrace door)
local terraceDoor: any = nil
for index, d in plan.doors do
	if index > 1 and d.rooms[2] == "outside" then
		terraceDoor = d
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
		local d = distance(s.at.Position, terraceDoor.at)
		if not pick or d < distance(pick.at.Position, terraceDoor.at) then
			pick, pickDoor = s, door
		end
	end
end
check("a heavy piece for two in a room off the corridor, still in the lodge", pick ~= nil and terraceDoor ~= nil, pick and pick.item)
if pick and terraceDoor then
	local model = pieceOf(pick.id)
	carried = model
	local y = origin.Position.Y + 3
	local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{House.id}`)
	local back = V3(House.back.x, 3, House.back.z)
	E.place(ann, back + V3(4, 0, 0))
	trigger(promptIn(site, "Enter by the terrace door"), ann)
	check("Ann in by the terrace door: inside, by the corridor's east end", distance(E.rootOf(ann).Position, origin * exits[2]) < Config.Furniture.EntryIn + 1.5,
		E.rootOf(ann).Position)
	-- at the piece's front, facing it: Lift (Danny's ask answered, or he is called)
	local size = FurnitureLooks.Items[pick.item].size
	local front = model.PrimaryPart.CFrame * CF(0, 0, -(size.Z / 2 + 2))
	E.rootOf(ann).CFrame = M.CFrame.lookAt(V3(front.Position.X, y, front.Position.Z), V3(model.PrimaryPart.Position.X, y, model.PrimaryPart.Position.Z))
	local lift = askPrompt(model) or promptIn(model, "Lift")
	trigger(lift, ann)
	local function helped(): boolean
		return math.abs((ann.Character:GetAttribute("CarrySpeed") or 0) - WALK * T.Speed.Pair) < 1e-6
	end
	local up = run(40, helped)
	check(`Ann lifts the {FurnitureLooks.Items[pick.item].name} with Danny: up together (the two-person walk)`, up and ann.Character:GetAttribute("MoveCarry") == pick.id, ann.Character:GetAttribute("MoveCarry"))
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
	-- out of its room by its doorway (across the doorway's wall), along the corridor to the terrace door's inside
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
	local w3, d3, h3 = walk(V3(exitIn.X - Config.Moving.Doors.Through - 2, y, exitIn.Z))
	check("out of its room by its doorway and along the corridor to the terrace door together: he never leaves its far end, on the floor",
		math.max(w1, w2, w3) < 0.05 and not (d1 or d2 or d3) and helped() and math.max(h1, h2, h3) < 0.5 and room ~= nil, `{math.max(w1, w2, w3)} off, {math.max(h1, h2, h3)} up`)
	-- out of the terrace door (8.1 walk-in doors: into its zone facing it, the dwell): he comes through with it
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
	check("out of the terrace door together (walked into it, no E): on the terrace (east of the house), Danny with it at its far end, on the ground",
		inZone and distance(out, V3(House.back.x, 0, House.back.z)) < 6 and out.X > House.back.x and distance(danny.body.root.Position, farEnd()) < 0.05
		and math.abs(danny.body.root.Position.Y - out.Y) < 0.5 and helped(), `{out.X}, {out.Y}, {out.Z}`)
	-- round the house to the van's back
	local backAt = cargoDoor.WorldPosition
	local away = V3(backAt.X - truck.chassis.Position.X, 0, backAt.Z - truck.chassis.Position.Z).Unit
	local corner = V3(House.back.x + 6, 3, House.door.z - 4)
	local w4, d4 = walk(corner)
	local w5, d5 = walk(backAt + away * 3)
	check("round the lodge to the van at the curb together, no drop", math.max(w4, w5) < 0.05 and not (d4 or d5) and helped(), math.max(w4, w5))
	run(0.2)
	trigger(promptIn(truck.model, "Load"), ann)
	check(`Ann loads the {FurnitureLooks.Items[pick.item].name}: in the van`, danny.s.move.things[pick.id].state == "truck" and ann.Character:GetAttribute("MoveCarry") == nil,
		E.lastNotice(ann))
end

Moving.admin(ann, "end")
run(0.2)
check("the move ends: he goes, the lodge's inside taken down", MoveHelper.find(ann) == nil and E.destroyed == 1)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
