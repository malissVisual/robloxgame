-- 8.5.1 (the owner: "Danny STILL goes through the van. I want him to go, open the door and get in"): Danny riding with
-- you on the REAL van. The 8.5 tests ride him round tests/runtime/MovingRuntime.luau's stub van (a 6 × 18 box, its
-- door at z -3); here the van is the one the game builds: server/Vehicles.luau's own factory (tests/run_tests.py
-- stages it as RealVanVehicles.luau on the same recorder) builds the sandbox's ZDC Sprinter (Config.Sandbox.Van: its
-- hull boxes, chassis, wheel colliders, its seats, its doors' list and their attachments) into the moves' runtime, and
-- the real server/Moving.luau and server/MoveHelper.luau (Config.Sandbox.On) ride Danny round it. No physics: his walk
-- is a straight step toward where the game sends him (PathfindingService's way: straight waypoints PathSpacing apart
-- that know nothing of the van, the worst a path can do), his body a 2-stud-wide column over the floor.
--   * the van as built: its front -Z, the passenger seat on the right (+X: Door 2, its cab door hinged there), its
--     Door2 attachment (where a player stands to get in) DoorStandOut out of the body's side at the seat;
--   * Danny with Ann (10.1 free), Ann at the wheel at the house's curb: from his spot by the van's back he walks round the van to his
--     spot at the REAL passenger door (RideStand out of its side, level with its seat), never with his body over any
--     colliding part of the van, no fade, no teleport; there a step to the real handle (the Door2 attachment) facing the
--     van, the passenger door (2) swung, the slide in to the real passenger seat;
--   * out again the same way when Ann gets out: at that door, outside every part of the van;
--   * from all round the van (sixteen spots on a ring, a van turned at an odd angle too), from inside the house (out of
--     its front door, the van backed up to it): never over the van, always in at its passenger door;
--   * 8.5.1 a body walked or put inside the van's outline (a nudge, the van parked over him) is walked out of it the
--     shortest way before anything else, never on through it.
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local RealVehicles = require("./RealVanVehicles")
local SandboxMap = require("./SandboxMap")
local Brain = require("./MoveHelperBrain")
local Boarding = require("./Boarding")

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
local CARGO = Config.Cargo
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
local House = SandboxMap.House
local plot = SandboxMap.Plots[1]
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (no roamers near)
end
-- (the recorder keeps an Attachment's Position in its props: read there, as Roblox gives it)
do
	local O = getmetatable(M.Instance.new("Folder"))
	local base = O.__index
	O.__index = function(self: any, key: string): any
		if key == "Position" and rawget(self, "props") and self.props.ClassName == "Attachment" then
			return self.props.Position or V3(0, 0, 0)
		end
		return base(self, key)
	end
end

-- ── The real van ───────────────────────────────────────────────────────────

local SPRINTER: any = nil
for _, def in Config.Cars do
	if def.id == Config.Sandbox.Van then
		SPRINTER = def
	end
end
local cars = M.Instance.new("Folder")
cars.Name = "Cars"
cars.Parent = workspace
local seatSit: any = nil -- (the runtime's Seat:Sit: its stub car's)
local function realVan(player: any, ground: any): any
	local built = RealVehicles.__testBuild(SPRINTER, M.Color3.fromRGB(217, 204, 176), ground, false, nil, nil, 0)
	if not seatSit then
		local stub = E.makeCar(player, "van", V3(0, -500, 0))
		seatSit = stub.passengers[1].Sit
		stub.model:Destroy()
	end
	built.seat.Sit = seatSit
	for _, seat in built.passengers do
		seat.Sit = seatSit
	end
	built.model:SetAttribute("BackOpen", false)
	built.model.Parent = cars
	return { owner = player, id = SPRINTER.id, model = built.model, chassis = built.chassis, seat = built.seat, passengers = built.passengers,
		doors = RealVehicles.__testDoors(RealVehicles.__testStyle(SPRINTER, 0)), size = built.size, wrecked = false, lent = false, rental = false,
		bike = false, speed = 0 }
end

-- the sandbox: Ann's plot, her own van (server/SandboxBoot.luau's parkVan, the test's): the real Sprinter
local ann = E.player(11, "Ann", V3(plot.spawn.x, 3, plot.spawn.z))
E.plots[ann] = plot
E.carId = SPRINTER.id
Moving.parkVan = function(player: any, spot: any, _seat: boolean, _carId: string?): (string?, any)
	local old = E.cars[player]
	if old then
		old.model:Destroy()
	end
	local car = realVan(player, CF(spot.x, 0, spot.z) * M.CFrame.Angles(0, math.rad(spot.yaw), 0))
	E.cars[player] = car
	return nil, car
end
local frontDoor = M.Instance.new("Part")
frontDoor.Name = "FrontDoor"
frontDoor.Size = V3(House.doorWidth, 7, 0.4)
frontDoor.CFrame = CF(House.door.x, 3.5, House.door.z + 0.5)
frontDoor:SetAttribute("SandboxDoor", true)
frontDoor.Parent = workspace
Moving.useArt(E.art)

-- His walk: straight toward the point the game sends him to, speed × dt a step; his paths (PathfindingService's) straight
-- waypoints PathSpacing apart that know nothing of the van (worked out at once: the runtime's task.spawn only records).
local fades = 0
local walker = {
	appear = function(_body: any)
		fades += 1
	end,
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
	route = function(_body: any, from: any, to: any): { any }?
		local way = V3(to.X - from.X, 0, to.Z - from.Z)
		local points = { from }
		local n = math.max(1, math.ceil(way.Magnitude / H.PathSpacing))
		for k = 1, n do
			table.insert(points, V3(from.X + way.X * k / n, to.Y, from.Z + way.Z * k / n))
		end
		return points
	end,
}
MoveHelper.useMover(walker)
Moving.start()
local recordSpawn = E.task.spawn
local function now(callback: any, ...: any)
	callback(...)
end


local function f(v: any): string
	return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z)
end
local function flat(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- ── The move, Danny with Ann (10.1 free) ──────────────────────────────────────────────────

local started = E.startRun(ann, House.id)
check("a solo run starts, Ann's van the real Sprinter (the game's factory)", started == nil
	and E.cars[ann] ~= nil and E.cars[ann].model:GetAttribute("Sprinter") == true, started)
Moving.step()
local danny = MoveHelper.find(ann)
local truck = E.cars[ann]
local body = danny and danny.body
check("Danny comes with it", danny ~= nil and body ~= nil)
check("Danny is Ann's from the start (10.1 free)", danny.hirer == ann)

-- ── The van as built ───────────────────────────────────────────────────────

local seat = truck.passengers[1]
local halfX, halfZ = truck.size.X / 2, truck.size.Z / 2
local function rel(at: any): any
	return truck.chassis.CFrame:PointToObjectSpace(at)
end
local seatAt = rel(seat.Position)
local door2 = truck.chassis:FindFirstChild("Door2")
local handle = door2 and door2.Position
local panel = truck.doors[2] and truck.doors[2].panel
check(`the real Sprinter: its hull {truck.size.X} wide, {truck.size.Z} long (Vehicles' size: Config.Sprinter's body to its bumpers)`,
	math.abs(truck.size.X - Config.Sprinter.Width) < 1e-6 and math.abs(truck.size.Z - Config.Sprinter.Length) < 0.3, f(truck.size))
check("…its front -Z, the driver on the left (-X, Door 1), the one passenger seat on the right (+X: Door 2), level with the driver",
	rel(truck.seat.Position).X < 0 and truck.seat:GetAttribute("Door") == 1 and #truck.passengers == 1 and seatAt.X > 0 and seat:GetAttribute("Door") == 2
	and math.abs(seatAt.Z - rel(truck.seat.Position).Z) < 1e-6 and seatAt.Z < -halfZ / 3, f(seatAt))
check("…Door 2 a cab door on the right where the seat is, with a panel that swings, its handle's spot (the Door2 attachment) DoorStandOut out of the body's side",
	truck.doors[2].side == 1 and math.abs(truck.doors[2].z - seatAt.Z) < 1e-6 and panel ~= nil and handle ~= nil
	and math.abs(handle.X - (truck.doors[2].outside + CARGO.DoorStandOut)) < 1e-6 and math.abs(handle.Z - seatAt.Z) < 1e-6
	and math.abs(truck.doors[2].outside - halfX) < 1e-6, handle and f(handle))
local hinged = false
for _, child in truck.chassis:GetChildren() do
	hinged = hinged or (child.Name == "DoorHinge" and child:GetAttribute("Door") == 2)
end
check("…its passenger door's hinge (the door every client swings, client/CarVisuals.luau)", hinged)

-- His body over a colliding part of the van (its hull boxes, chassis, wheel colliders, the walk-in bay's walls: what a
-- body would walk through): a column RADIUS round his root, from his feet to his head.
local RADIUS = 1 -- (the R15 root's half width)
local function over(at: any): string?
	for _, p in truck.model:GetDescendants() do
		if p:IsA("BasePart") and p.CanCollide then
			local r, s = p.CFrame.R, p.Size
			local q = p.CFrame:PointToObjectSpace(at)
			local ey = math.abs(r[4]) * s.X / 2 + math.abs(r[5]) * s.Y / 2 + math.abs(r[6]) * s.Z / 2
			local dx, dz = math.max(math.abs(q.X) - s.X / 2, 0), math.max(math.abs(q.Z) - s.Z / 2, 0)
			if math.sqrt(dx * dx + dz * dz) < RADIUS and at.Y - 3 < p.Position.Y + ey and at.Y + 2.5 > p.Position.Y - ey then
				return p.Name
			end
		end
	end
	return nil
end

-- The steps: MoveHelper's (his paths worked out at once) and the move's.
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		E.now += 0.1
		E.task.spawn = now
		MoveHelper.step(0.1)
		E.task.spawn = recordSpawn
		if index % 2 == 0 then
			Moving.step()
		end
		if done and done() then
			return true
		end
	end
	return done == nil
end
-- His walk watched until `done`: steps with his body over the van (and the last part), steps longer than his sprint
-- (put somewhere: a nudge, a fade), fades (his walk only: not while he gets in or out, or sits).
type Track = { over: number, part: string, jumps: number, fades: number }
local function track(seconds: number, done: () -> boolean): (boolean, Track)
	local t: Track = { over = 0, part = "", jumps = 0, fades = fades }
	local top = Brain.speed(Config.Movement.Walk, "ride", nil, 0) * Brain.trained(ann) * 0.1 + 1e-3
	local was = body.root.Position
	local ok = run(seconds, function()
		local at = body.root.Position
		if danny.board == nil and danny.seat == nil then
			local hit = over(at)
			if hit then
				t.over += 1
				t.part = `{hit} at {f(rel(at))}`
			end
			if flat(at, was) > top then
				t.jumps += 1
			end
		end
		was = at
		return done()
	end)
	t.fades = fades - t.fades
	return ok, t
end
local function put(at: any, floor: number?) -- (on the street's ground, else on `floor`)
	body.root.CFrame = CF(at.X, (floor or 0) + 3, at.Z)
	danny.pathGoal, danny.lastPos, danny.stuckFor = nil, nil, 0
	table.clear(danny.path)
end
local function swingsSince(from: number): { any }
	local list = {}
	for index = from + 1, #E.doorSwings do
		local swing = E.doorSwings[index]
		if swing.car == truck and swing.door == 2 then
			table.insert(list, swing)
		end
	end
	return list
end
local heartbeat = E.services.RunService.Heartbeat

-- ── At the house's curb: in and out at the real passenger door ──────────────

local CURB = CF(House.curb.x, 1.8, House.curb.z) * M.CFrame.Angles(0, math.rad(House.curb.yaw), 0)
truck.model:PivotTo(CURB) -- (the Driver's call's spot: its nose to the road, its back to the house's door)
E.place(ann, V3(House.curb.x - 200, 3, House.curb.z - 30)) -- (9.3 out of sight: Danny far off is put at the van only unseen, faded in)
run(6)
local waiting = rel(body.root.Position)
check("with nothing to carry, he waits by the van's back (behind it: byTruck), clear of it", danny.action == "wait" and waiting.Z > halfZ
	and over(body.root.Position) == nil, f(waiting))

E.seated[ann] = truck
local swingsAt = #E.doorSwings
local ok, t = track(30, function()
	return danny.board ~= nil
end)
local b = danny.board
check("8.5.1 Ann at the wheel: from behind the van he walks round it to his spot at the REAL passenger door (RideStand out of its right side, level with its seat)",
	ok and b ~= nil and not b.out and b.seat == seat and math.abs(b.from.X - (halfX + H.RideStand)) <= H.RideReach + 1e-6
	and math.abs(b.from.Z - seatAt.Z) <= H.RideReach + 1e-6, b and f(b.from))
check("…never with his body over a colliding part of the van (his path knows nothing of it), never put anywhere, no fade", t.over == 0 and t.jumps == 0
	and t.fades == 0, `{t.over} {t.part} {t.jumps} {t.fades}`)
check("…a step to the real handle (the Door2 attachment: where a player stands to get in), facing the van", b ~= nil and handle ~= nil
	and math.abs(b.stand.X - handle.X) < 1e-6 and math.abs(b.stand.Z - handle.Z) < 1e-6 and math.abs(b.standYaw - math.pi / 2) < 1e-6
	and b.door == 2 and not b.climb, b and f(b.stand))
local swing = swingsSince(swingsAt)[1]
check("…its door (2, the cab door on the right) swung for everybody: open as his hand reaches the handle, shut as he sits", swing ~= nil
	and swing.openAt ~= nil and math.abs(swing.openAt - swing.now - CARGO.BoardStepSeconds * 0.7) < 1e-6
	and math.abs(swing.closeAt - swing.now - CARGO.BoardSeconds) < 1e-6)
check("8.5.1 his right hand to the handle, a player's: BoardAt (that moment, server time) and BoardReach (a door with a panel) on his body for client/ArmPose.luau",
	swing ~= nil and body.model:GetAttribute("BoardAt") == swing.now and body.model:GetAttribute("BoardReach") == true
	and body.model:GetAttribute("AlightAt") == nil)
check("…the reach (shared/Boarding.luau's curve) full as he stands at the handle, gone by the time he sits", Boarding.reach(CARGO.BoardStepSeconds, false) == 1
	and Boarding.reach(CARGO.BoardSeconds, false) <= 1e-6)
E.clock = b.at + CARGO.BoardStepSeconds
heartbeat:Fire(1 / 60)
local atHandle = rel(body.root.Position)
check("…at the handle as his hand is on it (his pose, every frame)", math.abs(atHandle.X - handle.X) < 0.01 and math.abs(atHandle.Z - handle.Z) < 0.01, f(atHandle))
E.clock = b.at + (CARGO.BoardStepSeconds + CARGO.BoardSeconds) / 2
heartbeat:Fire(1 / 60)
local through = rel(body.root.Position)
local front, back = panel.offset.Z - panel.size.Z / 2, panel.offset.Z + panel.size.Z / 2
check("…then the slide in through the door's opening (along the van within its panel's span), between the handle and the seat",
	through.X < handle.X - 0.5 and through.X > seatAt.X and through.Z > front and through.Z < back, f(through))
local seated = run(2, function()
	return danny.seat ~= nil
end)
local inSeat = rel(body.root.Position)
check("…and in the real passenger seat (Seat:Sit), his hand off the handle (the attributes gone), no fade", seated and danny.seat == seat
	and seat.Occupant == body.humanoid and math.abs(inSeat.X - seatAt.X) < 0.01 and math.abs(inSeat.Z - seatAt.Z) < 0.01
	and body.model:GetAttribute("BoardAt") == nil and body.model:GetAttribute("BoardReach") == nil and fades == (danny.teleports.far or 0), f(inSeat)) -- (9.3 his far jump to the van at the start: faded in)

-- out again: Ann off the wheel, the van standing
E.seated[ann] = nil
swingsAt = #E.doorSwings
run(0.2, function()
	return danny.board ~= nil
end)
local out = danny.board
local outSwing = swingsSince(swingsAt)[1]
check("8.5 the van stands, nobody at its wheel: he gets out as a player does, at the same door (2 swung open now)", out ~= nil and out.out
	and outSwing ~= nil and outSwing.openAt == outSwing.now)
check("8.5.1 …his hand pushes the door, a player's: AlightAt and AlightReach on his body", outSwing ~= nil and body.model:GetAttribute("AlightAt") == outSwing.now
	and body.model:GetAttribute("AlightReach") == true)
local outDone = run(2, function()
	return danny.board == nil
end)
local spot = rel(body.root.Position)
check("…the slide out ends at his spot outside the door (RideStand out), his body clear of every part of the van, his hand off the door",
	outDone and danny.seat == nil and math.abs(spot.X - (halfX + H.RideStand)) < 0.3 and math.abs(spot.Z - seatAt.Z) < 0.3
	and over(body.root.Position) == nil and body.model:GetAttribute("AlightAt") == nil and body.model:GetAttribute("AlightReach") == nil, f(spot))
ok, t = track(8, function()
	return danny.action == "wait" and flat(body.root.Position, truck.chassis.CFrame * V3(waiting.X, 0, waiting.Z)) < 2
end)
check("8.5.1 …and back to wait behind the van: round its back corner (the straight way scrapes it), never over it, no teleport, no fade",
	ok and t.over == 0 and t.jumps == 0 and t.fades == 0, `{t.over} {t.part} {t.jumps} {t.fades}`)

-- ── From all round the van ─────────────────────────────────────────────────

-- In again from `at` (world): Ann out of the seat first (he gets out, waits), him put there, Ann at the wheel.
local function rideFrom(at: any): (boolean, Track, any)
	E.seated[ann] = nil
	run(10, function()
		return danny.board == nil and danny.seat == nil and danny.action ~= "ride"
	end)
	put(at)
	E.seated[ann] = truck
	local done, seen = track(30, function()
		return danny.board ~= nil or danny.seat ~= nil
	end)
	return done, seen, danny.board
end
local function atDoor(board: any): boolean
	return board ~= nil and not board.out and math.abs(board.from.X - (halfX + H.RideStand)) <= H.RideReach + 1e-6
		and math.abs(board.from.Z - seatAt.Z) <= H.RideReach + 1e-6 and math.abs(board.stand.X - handle.X) < 1e-6
end
local function ring(label: string)
	local good, bad = 0, ""
	for k = 0, 15 do
		local a = k * math.pi / 8
		local from = truck.chassis.CFrame * V3(15 * math.sin(a), 0, 15 * math.cos(a))
		local done, seen, board = rideFrom(from)
		if done and atDoor(board) and seen.over == 0 and seen.jumps == 0 and seen.fades == 0 then
			good += 1
		else
			bad ..= ` [{k}: {done} {board and f(board.from)} over {seen.over} {seen.part} jumps {seen.jumps} fades {seen.fades}]`
		end
	end
	check(label, good == 16, `{good}/16{bad}`)
end
ring("8.5.1 from sixteen spots all round the van (15 studs from its middle): each time round it to the real passenger door and in, never over it, no teleport, no fade")
truck.model:PivotTo(CF(House.curb.x + 70, 1.8, House.curb.z - 10) * M.CFrame.Angles(0, math.rad(37), 0))
ring("…the van parked turned 37° elsewhere: the same, in its own frame")
truck.model:PivotTo(CURB)

-- ── 8.5.1 never left inside the van ─────────────────────────────────────────

local fadesAt = fades
local inBay = truck.chassis.CFrame * V3(0.8, 0, 4) -- (the walk-in bay's middle, on the ground under its floor: a load with him at its far end)
E.seated[ann] = nil
run(10, function()
	return danny.board == nil and danny.seat == nil and danny.action ~= "ride"
end)
put(inBay)
E.seated[ann] = truck
run(0.1)
local outside = rel(body.root.Position)
check("8.5.1 his root inside the van (the bay's middle, on the ground under its floor): beside its nearer side at once (RideHug out), faded in, never walked through its shell",
	math.abs(math.abs(outside.X) - (halfX + H.RideHug + 0.05)) < 0.2 and math.abs(outside.Z - 4) < 0.2 and fades == fadesAt + 1
	and over(body.root.Position) == nil, f(outside))
ok, t = track(30, function()
	return danny.board ~= nil or danny.seat ~= nil
end)
check("…then round the van to its passenger door and in, never over it", ok and atDoor(danny.board) and t.over == 0 and t.fades == 0,
	`{t.over} {t.part} {t.fades}`)

-- the van backed up to the house's door: he comes out of it (his way out of the house's front door) clear of the van
E.seated[ann] = nil
run(10, function()
	return danny.board == nil and danny.seat == nil and danny.action ~= "ride"
end)
local doorOut = danny.ways[1].outside
truck.model:PivotTo(CF(doorOut.Position.X, 1.8, doorOut.Position.Z - halfZ - 0.6))
local entry = danny.ways[1].entryIn
put(entry.Position + entry.LookVector * 3, danny.s.origin.Position.Y) -- (in the house, on its floor)
local cameOut: any = nil
E.seated[ann] = truck
local inside = true
ok, t = track(40, function()
	if inside and flat(body.root.Position, danny.s.origin.Position) > 300 then
		inside = false
		cameOut = rel(body.root.Position)
	end
	return danny.board ~= nil or danny.seat ~= nil
end)
check("8.5.1 from inside the house, the van's back right at its front door: out of the door beside the van (never in it), round it, in at its passenger door",
	ok and cameOut ~= nil and math.max(math.abs(cameOut.X) - halfX, math.abs(cameOut.Z) - halfZ) >= H.RideHug and atDoor(danny.board) and t.over == 0
	and t.fades == 0, `{cameOut and f(cameOut)} {t.over} {t.part} {t.fades}`)
truck.model:PivotTo(CURB)

-- the van backing up at him while he waits behind it (to the house's door, the warehouse's): out of its way, sideways
E.seated[ann] = nil
run(10, function()
	return danny.board == nil and danny.seat == nil and danny.action == "wait"
end)
run(4)
local behind = rel(body.root.Position)
fadesAt = fades
local overWhile, stepped = 0, false
truck.speed = 8
for _ = 1, 12 do -- (1.2 s at 8 studs/s backward: its back 9.6 studs on, over where he stood)
	truck.model:PivotTo(truck.chassis.CFrame * CF(0, 0, 0.8))
	run(0.1)
	if over(body.root.Position) then
		overWhile += 1
	end
	stepped = stepped or math.abs(rel(body.root.Position).X) >= halfX + H.RideMargin
end
truck.speed = 0
check("8.5.1 the van backing up at him where he waits behind it: he steps out of its way (its side, RideMargin out), never inside it, no fade",
	behind.Z > halfZ and stepped and overWhile == 0 and fades == fadesAt, `{f(behind)} {stepped} {overWhile} {fades - fadesAt}`)
ok, t = track(8, function()
	return danny.action == "wait" and flat(body.root.Position, truck.chassis.CFrame * V3(waiting.X, 0, waiting.Z)) < 2
end)
check("…it stands: back to his spot behind it, round it", ok and t.over == 0 and t.fades == 0, `{t.over} {t.part}`)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
