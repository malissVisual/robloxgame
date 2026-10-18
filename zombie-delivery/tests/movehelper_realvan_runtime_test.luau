-- 8.5.1 (the owner: "Danny STILL goes through the van"): Danny round the REAL van. The other moves' tests walk him round
-- tests/runtime/MovingRuntime.luau's stub van (a 6 × 18 box); here the van is the one the game builds:
-- server/Vehicles.luau's own factory (tests/run_tests.py stages it as RealVanVehicles.luau on the same recorder) builds
-- the sandbox's ZDC Sprinter (Config.Sandbox.Van: its hull boxes, chassis, wheel colliders, its back doors and their
-- attachments) into the moves' runtime, and the real server/Moving.luau and server/MoveHelper.luau walk Danny round it.
-- No physics: his walk is a straight step toward where the game sends him (PathfindingService's way: straight
-- waypoints PathSpacing apart that know nothing of the van, the worst a path can do), his body a 2-stud-wide column over
-- the floor. 10.6 (only the sandbox is the game: nobody drives, he never sits in the van):
--   * the van as built: its hull Config.Sprinter's, anchored, no seat anywhere in it, its back's CargoDoor behind it;
--   * Danny with Ann (10.1 free) at the house's curb: he waits by the van's back, clear of it;
--   * from all round the van (sixteen spots on a ring, a van turned at an odd angle too) back to his spot behind it:
--     never with his body over a colliding part of the van, no teleport, no fade;
--   * a body put inside the van's outline (the van parked over him) is put beside it at once, faded in, never walked on
--     through it; from inside the house (out of its front door, the van backed up to it) he comes out beside the van.
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local RealVehicles = require("./RealVanVehicles")
local SandboxMap = require("./SandboxMap")
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

local H = Config.MoveHelper
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
local function realVan(player: any, ground: any): any
	local built = RealVehicles.__testBuild(SPRINTER, M.Color3.fromRGB(217, 204, 176), ground, false)
	built.model.Parent = cars
	return { owner = player, id = SPRINTER.id, model = built.model, chassis = built.chassis, paintParts = built.paintParts, size = built.size,
		wrecked = false, ground = ground }
end

-- the sandbox: Ann's plot, her own van (server/SandboxBoot.luau's parkVan, the test's): the real Sprinter
local ann = E.player(11, "Ann", V3(plot.spawn.x, 3, plot.spawn.z))
E.plots[ann] = plot
E.carId = SPRINTER.id
Moving.parkVan = function(player: any, spot: any): (string?, any)
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

-- ── The move, Danny with Ann (10.1 free) ───────────────────────────────────

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

local halfX, halfZ = truck.size.X / 2, truck.size.Z / 2
local function rel(at: any): any
	return truck.chassis.CFrame:PointToObjectSpace(at)
end
check(`the real Sprinter: its hull {truck.size.X} wide, {truck.size.Z} long (Vehicles' size: Config.Sprinter's body to its bumpers)`,
	math.abs(truck.size.X - Config.Sprinter.Width) < 1e-6 and math.abs(truck.size.Z - Config.Sprinter.Length) < 0.3, f(truck.size))
local seats, backs = 0, 0
for _, d in truck.model:GetDescendants() do
	if d.ClassName == "Seat" or d.ClassName == "VehicleSeat" then
		seats += 1
	elseif d.Name == "BackHinge" then
		backs += 1
	end
end
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
check("10.6 …anchored, no seat anywhere in it (nobody sits in a van), its two back doors on their hinges, its CargoDoor behind it",
	truck.chassis.Anchored == true and seats == 0 and backs == 2 and cargoDoor ~= nil and cargoDoor.Position.Z > halfZ / 2,
	`{seats} seats {backs} backs {cargoDoor and f(cargoDoor.Position)}`)

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
-- His walk watched until `done`: steps with his body over the van (and the last part), steps longer than his walk
-- (put somewhere: a nudge, a fade), fades.
type Track = { over: number, part: string, jumps: number, fades: number }
local function track(seconds: number, done: () -> boolean): (boolean, Track)
	local t: Track = { over = 0, part = "", jumps = 0, fades = fades }
	local top = Brain.speed(Config.Movement.Walk, "help", nil, 0) * Brain.trained(ann) * 0.1 + 1e-3
	local was = body.root.Position
	local ok = run(seconds, function()
		local at = body.root.Position
		local hit = over(at)
		if hit then
			t.over += 1
			t.part = `{hit} at {f(rel(at))}`
		end
		if flat(at, was) > top then
			t.jumps += 1
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

-- ── At the house's curb: he waits behind it ────────────────────────────────

local CURB = CF(House.curb.x, 1.8, House.curb.z) * M.CFrame.Angles(0, math.rad(House.curb.yaw), 0)
truck.model:PivotTo(CURB) -- (its nose to the road, its back to the house's door)
E.place(ann, V3(House.curb.x - 200, 3, House.curb.z - 30)) -- (9.3 out of sight: Danny far off is put at the van only unseen, faded in)
run(6)
local waiting = rel(body.root.Position)
check("with nothing to carry, he waits by the van's back (behind it: byTruck), clear of it", danny.action == "wait" and waiting.Z > halfZ
	and over(body.root.Position) == nil, f(waiting))
local function waitSpot(): any
	return truck.chassis.CFrame * V3(waiting.X, 0, waiting.Z)
end

-- ── From all round the van ─────────────────────────────────────────────────

-- Back to his spot behind the van from `at` (world).
local function backFrom(at: any): (boolean, Track)
	put(at)
	return track(30, function()
		return danny.action == "wait" and flat(body.root.Position, waitSpot()) < 2
	end)
end
local function ring(label: string)
	local good, bad = 0, ""
	for k = 0, 15 do
		local a = k * math.pi / 8
		local from = truck.chassis.CFrame * V3(15 * math.sin(a), 0, 15 * math.cos(a))
		local done, seen = backFrom(from)
		if done and seen.over == 0 and seen.jumps == 0 and seen.fades == 0 then
			good += 1
		else
			bad ..= ` [{k}: {done} over {seen.over} {seen.part} jumps {seen.jumps} fades {seen.fades}]`
		end
	end
	check(label, good == 16, `{good}/16{bad}`)
end
ring("8.5.1 from sixteen spots all round the van (15 studs from its middle): each time round it to his spot behind it, never over it, no teleport, no fade")
truck.model:PivotTo(CF(House.curb.x + 70, 1.8, House.curb.z - 10) * M.CFrame.Angles(0, math.rad(37), 0))
run(6)
ring("…the van parked turned 37° elsewhere: the same, in its own frame")
truck.model:PivotTo(CURB)
run(6)

-- ── 8.5.1 never left inside the van ─────────────────────────────────────────

local fadesAt = fades
local inBay = truck.chassis.CFrame * V3(0.8, 0, 4) -- (the walk-in bay's middle, on the ground under its floor: the van parked over him)
put(inBay)
run(0.1)
local outside = rel(body.root.Position)
check("8.5.1 his root inside the van (the bay's middle, on the ground under its floor): beside its nearer side at once (RideHug out), faded in, never walked through its shell",
	math.abs(math.abs(outside.X) - (halfX + H.RideHug + 0.05)) < 0.2 and math.abs(outside.Z - 4) < 0.2 and fades == fadesAt + 1
	and over(body.root.Position) == nil, f(outside))
local ok, t = track(30, function()
	return danny.action == "wait" and flat(body.root.Position, waitSpot()) < 2
end)
check("…then round the van to his spot behind it, never over it", ok and t.over == 0 and t.fades == 0, `{t.over} {t.part} {t.fades}`)

-- the van backed up to the house's door: he comes out of it (his way out of the house's front door) clear of the van
local doorOut = danny.ways[1].outside
truck.model:PivotTo(CF(doorOut.Position.X, 1.8, doorOut.Position.Z - halfZ - 0.6))
run(1)
local entry = danny.ways[1].entryIn
put(entry.Position + entry.LookVector * 3, danny.s.origin.Position.Y) -- (in the house, on its floor)
local cameOut: any = nil
local inside = true
ok, t = track(40, function()
	if inside and flat(body.root.Position, danny.s.origin.Position) > 300 then
		inside = false
		cameOut = rel(body.root.Position)
	end
	return not inside and danny.action == "wait" and flat(body.root.Position, waitSpot()) < 2
end)
check("8.5.1 from inside the house, the van's back right at its front door: out of the door beside the van (never in it), round it to his spot",
	ok and cameOut ~= nil and math.max(math.abs(cameOut.X) - halfX, math.abs(cameOut.Z) - halfZ) >= H.RideHug and t.over == 0
	and t.fades == 0, `{cameOut and f(cameOut)} {t.over} {t.part} {t.fades}`)

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
