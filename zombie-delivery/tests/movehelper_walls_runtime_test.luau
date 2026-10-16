-- 9.0 carrying in two with Danny inside a real house, walked FORWARDS into a wall (the owner, 8.9.3: "When I want to walk
-- forwards, Danny can't walk backwards"; walking forwards Danny goes first, backwards, into whatever is behind him). The
-- real server/Moving.luau, server/MoveHelper.luau and server/PairHold.luau on tests/runtime/MovingRuntime.luau's fakes
-- (Config.Sandbox.On) with the real art (shared/FurnitureLooks.luau, shared/HouseLayout.luau, server/HouseInterior.luau
-- and its shell's real wall parts): a move into The Old Farmstead. Danny's hold the GAME's (MoveHelper.gameMover's keep
-- and free: PairHold's constraints) played as Roblox plays them every frame, as tests/movehelper_backwards_runtime_
-- test.luau does. 9.2 (you drive his end): his body is Sol's (SetNetworkOwner), her client the real client/PairLead.luau
-- (E.leadClient) in client/PairSteer.luau's drive branch: the house's walls at his end are HER rays (at the real shell's
-- Wall parts), no lag, nothing of the server's (no PairWall).
-- Sol lifts a two-person piece with Danny, then stands in the middle of a room facing one of its walls (Danny between
-- her piece and that wall) and walks FORWARDS: Danny backs up to the wall.
--   * he never goes through a wall: no step of his root crosses the shell's wall parts (a ray along it at his chest),
--     his root always HoldWall.Clear studs off them; never a snap
--   * against it her client takes her walk into the wall away (PairLead.walk: her own ray, nothing late): her piece
--     stops, his place no more than a frame's walk past his clearance (the piece never pushed into him there)
--   * forwards and to the side along the wall: he slides along it (on along the wall, still clear of it)
--   * she walks back from the wall: the wall lets go, he follows his end again
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Rules = require("./MovingRules")
local PairCarry = require("./PairCarry")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local HouseRoute = require("./HouseRoute")
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

local H = Config.MoveHelper
local FRAME = 1 / 60
local TICK = 6
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (no roamers near)
end
H.HoldLead.Base, H.HoldLead.Ping = E.gameLead.Base, E.gameLead.Ping -- (the game's lead)

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

-- His own walk: straight toward the point he is given (his way's next corner); holding: the game's keep and free.
local gameMover = MoveHelper.gameMover
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
	keep = gameMover.keep,
	free = gameMover.free,
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
local heartbeat = E.game:GetService("RunService").Heartbeat

local function promptIn(model: any, action: string): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and d.ActionText ~= nil and string.find(tostring(d.ActionText), action, 1, true) == 1 then
			return d
		end
	end
	return nil
end
local function yawOf(frame: any): number
	local look = frame.LookVector
	return PairCarry.yawOf(look.X, look.Z)
end

-- Roblox's constraints on his root, one frame (tests/movehelper_backwards_runtime_test.luau's)
local danny: any = nil
local function goalOf(c: any): any?
	if c.props.Mode == "OneAttachment" then
		return if c.ClassName == "AlignOrientation" then c.props.CFrame else CF(c.props.Position.X, c.props.Position.Y, c.props.Position.Z)
	end
	local a1 = c.props.Attachment1
	local part = a1 and a1.props.Parent
	return if part then part.CFrame * (a1.props.CFrame or CF()) else nil
end
local function physics(dt: number)
	local body = danny and danny.body
	local grip = body and body.grip
	if not grip or grip.align.props.Parent == nil or grip.align.props.Enabled == false then
		return
	end
	local root = body.root
	local here = root.CFrame
	local p = here.Position
	local x, y, z = p.X, p.Y, p.Z
	local goal = goalOf(grip.align)
	if goal then
		local dx, dz = goal.Position.X - x, goal.Position.Z - z
		local d = math.sqrt(dx * dx + dz * dz)
		local most = grip.align.MaxVelocity * dt
		if d > most then
			dx, dz = dx / d * most, dz / d * most
		end
		x, z = x + dx, z + dz
	end
	local lift = grip.lift
	if lift then
		local most = lift.MaxVelocity * dt
		y += math.clamp(lift.props.Position.Y - y, -most, most)
	end
	local yaw = yawOf(here)
	local turn = goalOf(grip.orient)
	if turn then
		yaw = PairCarry.turn(yaw, yawOf(turn), grip.orient.MaxAngularVelocity, dt)
	end
	root.CFrame = CF(x, y, z) * M.CFrame.Angles(0, yaw, 0)
end
local frames = 0
local function run(seconds: number, done: (() -> boolean)?, before: (() -> ())?, after: (() -> ())?): boolean
	for _ = 1, math.ceil(seconds / FRAME - 1e-9) do
		frames += 1
		E.clock += FRAME
		if before then
			before()
		end
		physics(FRAME)
		heartbeat:Fire(FRAME)
		if frames % TICK == 0 then
			MoveHelper.step(TICK * FRAME)
			if frames % (2 * TICK) == 0 then
				Moving.step()
			end
		end
		if after then
			after()
		end
		if done and done() then
			return true
		end
	end
	return done == nil
end

-- A move into The Old Farmstead (the big house)
local house: any = nil
for _, h in SandboxMap.Houses do
	if h.kind == "big" then
		house = h
	end
end
local plot = SandboxMap.Plots[1]
local sol = E.player(201, "Sol", V3(plot.spawn.x, 3, plot.spawn.z))
E.plots[sol] = plot
E.profiles[sol] = { money = 5000, sandboxHouse = house.id, sandboxHouseSeed = 1 }
local started = Moving.admin(sol, "start")
local b = built[#built]
check(`{house.name}: a move into it`, string.find(started, "started", 1, true) ~= nil and b ~= nil and b.plan.kind == "big", started)
Moving.step()
danny = MoveHelper.find(sol)
local truck = E.cars[sol]
truck.chassis.CFrame = CF(house.curb.x, 2, house.curb.z) * M.CFrame.Angles(0, math.rad(house.curb.yaw), 0)
E.request(sol, "helper", "hire")
run(0.6)
local lead = E.leadClient(sol) -- 9.2 Sol's client/PairLead.luau
check("Danny comes, Sol hires him, his grid the house's plan", danny ~= nil and danny.hirer == sol and danny.route ~= nil)
local plan, origin = b.plan, b.origin
local grid = HouseRoute.grid(plan) :: HouseRoute.Grid -- (the test's own: the walls)
local y = origin.Position.Y + 3
local character = sol.Character
local body = danny.body

-- the real shell's wall parts: is any of them between two points (a ray along the line)?
local walls: { any } = {}
for _, part in b.model:FindFirstChild("Shell"):GetChildren() do
	if part.Name == "Wall" then
		table.insert(walls, part)
	end
end
local wallParams = M.RaycastParams.new()
wallParams.FilterType = "Include"
wallParams.FilterDescendantsInstances = walls
local function throughWall(a: any, c: any): boolean
	return (c - a).Magnitude > 1e-6 and E.sightRay(a, c - a, wallParams) ~= nil
end
-- 9.2 studs from a world point to the nearest of the shell's wall parts along the ground (her client's rays find those)
local function offParts(at: any): number
	local least = math.huge
	for _, part in walls do
		local p = part.CFrame:PointToObjectSpace(at)
		local half = part.Size * 0.5
		local dx, dz = math.max(math.abs(p.X) - half.X, 0), math.max(math.abs(p.Z) - half.Z, 0)
		least = math.min(least, math.sqrt(dx * dx + dz * dz))
	end
	return least
end

-- A two-person piece of the house: lifted with Danny (Sol at one end of its length, facing along it)
local spot: any = nil
for _, s in plan.spots do
	if FurnitureLooks.Items[s.item].class == "pair" and (spot == nil or s.item == "sofa") then
		spot = s
	end
end
local model = b.pieces[spot.id]
local root = model.PrimaryPart
local size = FurnitureLooks.Items[spot.item].size
local name = FurnitureLooks.Items[spot.item].name
local length = math.max(size.X, size.Z)
local planAt = function(p: any): any
	return origin:PointToObjectSpace(p)
end

-- A room and one of its walls with no doorway in his way (a line to it 2 studs either side): the piece set down there
-- lengthwise toward that wall, Sol at its near end facing along it, his end 3 studs from the wall
local chosen: any = nil
for _, room in plan.rooms do
	if room.id == "corridor" then
		continue
	end
	local cx, cz = (room.min.X + room.max.X) / 2, (room.min.Z + room.max.Z) / 2
	for _, dir in { V3(1, 0, 0), V3(-1, 0, 0), V3(0, 0, 1), V3(0, 0, -1) } do
		local span = if dir.X ~= 0 then (room.max.X - room.min.X) / 2 else (room.max.Z - room.min.Z) / 2
		local side = V3(-dir.Z, 0, dir.X)
		local walled = true
		for _, k in { -2, 0, 2 } do
			local a = V3(cx, 0, cz) + side * k
			local c = a + dir * (span + 2)
			walled = walled and not HouseRoute.sees(grid, a.X, a.Z, c.X, c.Z)
		end
		if walled and span * 2 > length + 9 and (chosen == nil or span > chosen.span) then
			chosen = { room = room, cx = cx, cz = cz, d = dir, span = span }
		end
	end
end
check(`{house.name}: a room with a wall (no doorway in his way) long enough for the {name}`, chosen ~= nil)
local d = chosen.d
local sign = if d.X ~= 0 then d.X else d.Z
local wallCoord = if d.X ~= 0 then (if d.X > 0 then chosen.room.max.X else chosen.room.min.X) else (if d.Z > 0 then chosen.room.max.Z else chosen.room.min.Z)
local function onLine(a: number): any -- (a plan point on the line to the wall, `a` its coordinate along it)
	return if d.X ~= 0 then V3(a, 0, chosen.cz) else V3(chosen.cx, 0, a)
end
local middleAt = wallCoord - sign * (3 + H.Standoff + length / 2)
local middle = origin * onLine(middleAt)
local lengthwise = if size.X >= size.Z then M.CFrame.Angles(0, math.atan2(-d.Z, d.X), 0) else M.CFrame.Angles(0, math.atan2(d.X, d.Z), 0)
model:PivotTo(CF(middle.X, root.Position.Y, middle.Z) * (origin.Rotation * lengthwise))
local solAt = origin * onLine(middleAt - sign * (length / 2 + 1.5))
E.place(sol, V3(solAt.X, y, solAt.Z))
E.rootOf(sol).CFrame = M.CFrame.lookAt(V3(solAt.X, y, solAt.Z), V3(middle.X, y, middle.Z))
Moving.step()
Config.CarryGrip.On = true
promptIn(model, "Lift").Triggered:Fire(sol)
local up = run(60, function()
	return select(2, Rules.holding(danny.s.move, danny.id)) == "helper"
end)
Config.CarryGrip.On = false
check(`{house.name}: Sol lifts the {name} with Danny in the {chosen.room.id}, lengthwise toward its wall`, up and character:GetAttribute("MoveCarry") == spot.id)
local weld = E.rootOf(sol).CFrame:ToObjectSpace(root.CFrame)
local function follow()
	root.CFrame = E.rootOf(sol).CFrame * weld
end
follow()
-- Sol's client, one frame (client/PairSteer.luau's drive branch, as tests/movehelper_backwards_runtime_test.luau's): her
-- stick → the walk without its part into a wall at his end (PairLead.walk), the heading at PairLead.Turn (PairLead.turn),
-- the piece turned with her root, his goals (PairLead.step), her walk this physics step
local truth = E.rootOf(sol).CFrame
local steer = PairCarry.newSteer(yawOf(truth))
local humanoid = character:FindFirstChildOfClass("Humanoid")
local L = H.PairLead
local function client(wx: number, wz: number)
	local drive = lead.of(danny.body.model)
	if not drive then
		return
	end
	local x, z = lead.walk(drive, wx, wz)
	local facingNow = yawOf(truth)
	steer.heading = facingNow
	local factor = PairCarry.steer(steer, x, z, FRAME, math.rad(L.Turn), false, L.TurnWalk)
	steer.heading = lead.turn(drive, facingNow, steer.heading)
	truth = CF(truth.Position) * M.CFrame.Angles(0, steer.heading, 0)
	E.rootOf(sol).CFrame = truth
	follow()
	local velocity = V3(x, 0, z) * (character:GetAttribute("CarrySpeed") or 0) * factor
	E.rootOf(sol).AssemblyLinearVelocity = velocity
	lead.step(drive, FRAME, E.rootOf(sol), humanoid)
	truth = CF(truth.Position + velocity * FRAME) * truth.Rotation
	E.rootOf(sol).CFrame = truth
	follow()
end
run(1.5, nil, function()
	client(0, 0)
end)
local startAt = planAt(body.root.Position)
local fromWall = sign * (wallCoord - (if d.X ~= 0 then startAt.X else startAt.Z))
check(`{house.name}: Danny between her {name} and the wall, a few studs from it`, fromWall > H.HoldWall.Clear + 1 and fromWall < 6
	and (function(): boolean
		local place = planAt(root.CFrame * danny.holdEnd)
		return math.sqrt((place.X - startAt.X) ^ 2 + (place.Z - startAt.Z) ^ 2) < 0.5
	end)(), string.format("%.2f from it", fromWall))
check(`9.2 {house.name}: his body Sol's to drive (her client's rays at the house's walls; the server's PairWall none)`, body.root.NetworkOwner == sol
	and lead.of(body.model) ~= nil and character:GetAttribute("PairWall") == nil)

-- Sol walks (her client's step: her screen her own simulation, his body in it)
local worst = { crossed = 0, nearest = math.huge, jump = 0, walled = 0, deepest = -math.huge, serverWall = 0 }
local lastRoot = body.root.Position
local lastPlace = root.CFrame * danny.holdEnd
local function measure()
	local here = body.root.Position
	local chest = V3(here.X, here.Y + 1, here.Z)
	local before = V3(lastRoot.X, lastRoot.Y + 1, lastRoot.Z)
	if throughWall(before, chest) then
		worst.crossed += 1
	end
	worst.nearest = math.min(worst.nearest, offParts(here))
	-- a step no longer than his place's own and the glide (no snap)
	local place = root.CFrame * danny.holdEnd
	worst.jump = math.max(worst.jump, (V3(here.X, 0, here.Z) - V3(lastRoot.X, 0, lastRoot.Z)).Magnitude
		- ((V3(place.X, 0, place.Z) - V3(lastPlace.X, 0, lastPlace.Z)).Magnitude + L.Glide * FRAME + 0.02))
	lastRoot, lastPlace = here, place
	local drive = lead.of(body.model)
	if drive and math.sqrt(drive.wallX ^ 2 + drive.wallZ ^ 2) >= 0.999 then
		worst.walled += 1 -- (her client: his end against the wall, her walk into it all gone)
	end
	if character:GetAttribute("PairWall") ~= nil then
		worst.serverWall += 1
	end
	-- how far her piece's far end (his place) came toward the wall past his clearance off it
	local at = planAt(place)
	local toward = (if d.X ~= 0 then at.X * d.X else at.Z * d.Z) - (wallCoord * (if d.X ~= 0 then d.X else d.Z) - H.HoldWall.Clear)
	worst.deepest = math.max(worst.deepest, toward)
end
local function walk(wx: number, wz: number, seconds: number)
	run(seconds, nil, function()
		client(wx, wz)
	end, measure)
end
local forward = truth.LookVector
local fx, fz = forward.X, forward.Z
local rx, rz = -fz, fx
local frameWalk = (character:GetAttribute("CarrySpeed") or 0) * FRAME -- (studs her walk goes in a frame)
walk(fx, fz, 4) -- forwards: Danny backs up to the wall
local pinned = worst.walled
local heldAt = body.root.Position
check(`{house.name}: forwards to the {chosen.room.id}'s wall: Danny backs up to it and stops HoldWall.Clear off it, never through it (no step across the shell's wall parts)`,
	worst.crossed == 0 and worst.nearest >= H.HoldWall.Clear - 0.02 and math.abs(offParts(heldAt) - H.HoldWall.Clear) < 0.3,
	string.format("%d across, %.2f off the walls at least, %.2f now", worst.crossed, worst.nearest, offParts(heldAt)))
check(`9.2 {house.name}: …against it her client takes her walk into the wall away (her own ray, no lag): her piece stops, his place a frame's walk past his clearance at most`,
	pinned > 30 and worst.deepest <= frameWalk + 0.02 and worst.serverWall == 0, string.format("%d frames walled, %.2f past", pinned, worst.deepest))
local slideFrom = planAt(heldAt)
local function offFront(at: any): number -- (studs from the room's wall she walked at)
	local q = planAt(at)
	return sign * (wallCoord - (if d.X ~= 0 then q.X else q.Z))
end
walk((fx + rx) * math.sqrt(0.5), (fz + rz) * math.sqrt(0.5), 1) -- forwards and to her right: along the wall
local slid = planAt(body.root.Position)
local moved = if d.X ~= 0 then math.abs(slid.Z - slideFrom.Z) else math.abs(slid.X - slideFrom.X)
check(`{house.name}: forwards and to the side: he slides along the wall (on along it, still clear of it, never through)`,
	moved > 2 and worst.crossed == 0 and worst.nearest >= H.HoldWall.Clear - 0.02, string.format("%.2f along it, %d across, %.2f off", moved, worst.crossed, worst.nearest))
walk(-fx, -fz, 2) -- backwards, away from the wall: he follows his end
local into = (origin.Rotation * d).Unit -- (the way into that wall, in the world)
local drive = lead.of(body.model)
check(`{house.name}: walked back from the wall: the wall lets go, he follows his end again (off the wall), never a snap`,
	drive ~= nil and math.abs(drive.wallX * into.X + drive.wallZ * into.Z) < 1e-3 and offFront(body.root.Position) > H.HoldWall.Clear + 1
	and worst.jump <= 1e-3, string.format("%.2f off the wall, %.3f over", offFront(body.root.Position), worst.jump))
walk((fx + rx) * math.sqrt(0.5), (fz + rz) * math.sqrt(0.5), 5) -- into the wall again and on along it into the room's corner
local corner = planAt(body.root.Position)
local room = chosen.room
local offSide = if d.X ~= 0 then math.min(corner.Z - room.min.Z, room.max.Z - corner.Z) else math.min(corner.X - room.min.X, room.max.X - corner.X)
check(`9.2 {house.name}: …on into the room's corner: the wall beside his end stops him too (her ray the way she walks or turns him), never through`,
	worst.crossed == 0 and worst.nearest >= H.HoldWall.Clear - 0.05 and worst.jump <= 1e-3 and offSide <= H.HoldWall.Clear + 0.3
	and offFront(body.root.Position) <= H.HoldWall.Clear + 0.3,
	string.format("%d across, %.2f off, %.3f over, %.2f / %.2f off the two walls", worst.crossed, worst.nearest, worst.jump, offFront(body.root.Position), offSide))
E.Net.get("PutDown").OnServerEvent:Fire(sol)
run(0.5)
check("put down: his body the server's again; Sol's PairWith / PairFar / PairWall gone", body.root.NetworkOwner == false and character:GetAttribute("PairWith") == nil
	and character:GetAttribute("PairFar") == nil and character:GetAttribute("PairWall") == nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
