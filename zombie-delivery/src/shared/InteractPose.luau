--!strict
-- 5.7: the interactions at the car's level (Config.Interact), the pure part: no Roblox at its top level, so
-- tests/interact_test.luau runs it in the standalone Luau. The clients build their CFrames and joint rotations from
-- these plain numbers (client/Interact.luau lays the poses over the R15 joints; client/CarBoarding.luau,
-- client/BusRide.luau and client/ZipRide.luau move the bodies), the server times its checks by the same routes
-- (server/ZipLines.luau, server/Buses.luau, server/Vehicles.luau).
--
-- A route: points the body's root goes through, each with how it gets there (`kind`: "walk", "turn", "climb", "over",
-- "hop", "step", "onto", "off", "sit", "stand"), in how many seconds, the way it faces on arrival (fx, fz; turned to over the
-- segment's first TURN seconds) and an arc (studs up in the segment's middle: over a rail, up a step).
--
--   InteractPose.route(points)              the route with its times added up (points[1] is the start)
--   InteractPose.fit(route, seconds)        the same route played in `seconds`
--   InteractPose.sample(route, t)           where the root is t seconds in: x, y, z, fx, fz, kind, u (the segment's
--                                           progress 0..1), dist (studs walked or climbed so far)
--   InteractPose.climbRoute(line, which, up, x, y, z, lift)   a zip line's ladder climb (which: 1 the start's ladder,
--                                           2 the end's), from (x, y, z): the street, up the ladder, over the roof's
--                                           edge, across the roof onto the platform (up), or all of it backwards
--   InteractPose.climbEnd(line, which, up, lift)   where a climb ends: x, y, z, fx, fz (the server's end too)
--
-- The poses: a joint table (InteractPose.Pose: radians about X, Y, Z in the R15 joints' own frames: +X swings a limb
-- forward, +Z swings the right limbs out to the right, the left ones in; the waist's -X leans forward).
--
--   InteractPose.walk(dist, amount)         a walking stride (legs and arms swing with the distance walked)
--   InteractPose.climb(dist)                hand over hand up a ladder (the rungs pass with the distance climbed)
--   InteractPose.over(u)                    over a roof's edge: the arms push down, a knee comes up
--   InteractPose.hop(u)                     a high step over a rail (or up into the bus): the right knee, then the left
--   InteractPose.sit(u)                     from standing (0) to sitting (1)
--   InteractPose.forKind(kind, u, dist)     the pose of a route's segment
--   InteractPose.bikeMount(u, stand, step)  getting onto a bike (a leg swung over the saddle) or a scooter (a step onto
--                                           its deck, the hands to the bar); u 0..1, step: the walk to its side's share
--   InteractPose.reachUp(u)                 the hands going up to the zip line's trolley (0..1 of the full grip)
--   InteractPose.blend(a, b, k)             two poses mixed

local Config = require(script.Parent.Config)
local RiderPose = require(script.Parent.RiderPose)
local ZipLines = require(script.Parent.ZipLines)

local InteractPose = {}

export type Angles = { x: number, y: number, z: number }
export type Pose = { [string]: Angles } -- waist, rightHip, rightKnee, leftHip, leftKnee, rightShoulder, …
export type Point = {
	x: number,
	y: number,
	z: number,
	kind: string,
	seconds: number, -- to get here from the point before
	fx: number, -- facing on arrival (flat, unit)
	fz: number,
	arc: number,
}
export type Route = { points: { Point }, times: { number }, lengths: { number }, total: number }

InteractPose.Joints = { "waist", "rightHip", "rightKnee", "leftHip", "leftKnee", "rightShoulder", "leftShoulder", "rightElbow", "leftElbow" }

local TURN = 0.25 -- seconds: a segment turns the body to its facing over this much of its start
local LADDER_OUT = 2.7 -- the climber's root this far out of the wall (the truss is 2 deep, 1.05 out)
local RAIL_OUT = 1.3 -- outside a platform's rail, this far
local SIT_THIGH = math.rad(88) -- the sit animation's thighs (level, forward) and knees, roughly
local SIT_KNEE = math.rad(-88)

-- Smooth start, smooth end (0..1 → 0..1).
function InteractPose.ease(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end
local ease = InteractPose.ease

function InteractPose.point(x: number, y: number, z: number, kind: string, seconds: number, fx: number, fz: number, arc: number?): Point
	local length = math.sqrt(fx * fx + fz * fz)
	if length < 1e-6 then
		fx, fz, length = 0, -1, 1
	end
	return { x = x, y = y, z = z, kind = kind, seconds = math.max(0, seconds), fx = fx / length, fz = fz / length, arc = arc or 0 }
end

-- The route with its times and lengths added up.
function InteractPose.route(points: { Point }): Route
	local times: { number } = { 0 }
	local lengths: { number } = { 0 }
	local t, d = 0, 0
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		t += b.seconds
		d += math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2)
		times[i] = t
		lengths[i] = d
	end
	return { points = points, times = times, lengths = lengths, total = t }
end

-- The same route played in `seconds` (every segment scaled alike).
function InteractPose.fit(route: Route, seconds: number): Route
	if route.total <= 0 then
		return route
	end
	local k = seconds / route.total
	local points: { Point } = {}
	for i, p in route.points do
		points[i] = InteractPose.point(p.x, p.y, p.z, p.kind, p.seconds * k, p.fx, p.fz, p.arc)
	end
	return InteractPose.route(points)
end

-- These kinds ease in and out over their segment; the walks and the climbs go at an even pace.
local EASED: { [string]: boolean } = { over = true, hop = true, step = true, onto = true, off = true, sit = true, stand = true }

-- Where the root is t seconds into the route: x, y, z, the facing (fx, fz), the segment's kind and progress (0..1) and
-- the studs travelled so far.
function InteractPose.sample(route: Route, t: number): (number, number, number, number, number, string, number, number)
	local points = route.points
	local n = #points
	if n == 1 or t <= 0 then
		local p = points[1]
		return p.x, p.y, p.z, p.fx, p.fz, if n > 1 then points[2].kind else p.kind, 0, 0
	end
	if t >= route.total then
		local p = points[n]
		return p.x, p.y, p.z, p.fx, p.fz, p.kind, 1, route.lengths[n]
	end
	local i = 2
	while i < n and route.times[i] <= t do
		i += 1
	end
	local a, b = points[i - 1], points[i]
	local t0 = route.times[i - 1]
	local raw = if b.seconds > 0 then math.clamp((t - t0) / b.seconds, 0, 1) else 1
	local u = if EASED[b.kind] then ease(raw) else raw
	local x = a.x + (b.x - a.x) * u
	local y = a.y + (b.y - a.y) * u + b.arc * math.sin(math.pi * u)
	local z = a.z + (b.z - a.z) * u
	-- turning from the facing before to this segment's over its start
	local k = ease(if b.seconds > 0 then (t - t0) / math.min(TURN, b.seconds) else 1)
	local fx, fz = a.fx + (b.fx - a.fx) * k, a.fz + (b.fz - a.fz) * k
	local length = math.sqrt(fx * fx + fz * fz)
	if length < 1e-3 then
		fx, fz = b.fx, b.fz
	else
		fx, fz = fx / length, fz / length
	end
	local dist = route.lengths[i - 1] + (route.lengths[i] - route.lengths[i - 1]) * u
	return x, y, z, fx, fz, b.kind, raw, dist
end

-- ── The zip lines' ladders ──────────────────────────────────────────────────

local function platformOf(line: ZipLines.Line, which: number): ZipLines.Platform
	return if which == 1 then line.a else line.b
end

local function ladderOf(line: ZipLines.Line, which: number): ZipLines.Ladder
	return if which == 1 then line.ladderA else line.ladderB
end

-- Where a climb ends: up on the platform's back half looking at the cable; down on the sidewalk 3.5 out from the
-- ladder's foot, looking at the street. lift: the root's height over the feet.
function InteractPose.climbEnd(line: ZipLines.Line, which: number, up: boolean, lift: number): (number, number, number, number, number)
	if up then
		local p = platformOf(line, which)
		local back = Config.ZipLines.Platform / 2 - 1.6
		return p.x - p.fx * back, p.floor + lift, p.z - p.fz * back, p.fx, p.fz
	end
	local ladder = ladderOf(line, which)
	return ladder.x + ladder.nx * 3.5, ladder.base + lift, ladder.z + ladder.nz * 3.5, ladder.nx, ladder.nz
end

-- The fixed points of a climb, from the ladder's foot to the end on the platform (up's order): each point with the
-- kind of the move that reaches it.
local function climbPoints(line: ZipLines.Line, which: number, lift: number): { Point }
	local cfg = Config.Interact
	local ladder = ladderOf(line, which)
	local p = platformOf(line, which)
	local nx, nz = ladder.nx, ladder.nz
	local lx, lz = ladder.x + nx * LADDER_OUT, ladder.z + nz * LADDER_OUT
	local roof = ladder.top + lift
	local points: { Point } = {}
	-- on the ladder at its foot, facing the wall
	table.insert(points, InteractPose.point(lx, ladder.base + lift + 0.6, lz, "onto", cfg.ClimbOnto, -nx, -nz, 0))
	-- up to the top: the hands on the roof's edge
	local topY = ladder.top - 2.4 + lift
	table.insert(points, InteractPose.point(lx, topY, lz, "climb", math.max(0.1, (topY - (ladder.base + lift + 0.6)) / cfg.ClimbSpeed), -nx, -nz, 0))
	-- over the edge onto the roof
	local rx, rz = ladder.x - nx * 2.2, ladder.z - nz * 2.2
	table.insert(points, InteractPose.point(rx, roof, rz, "over", cfg.ClimbOver, -nx, -nz, 2))
	-- across the roof onto the platform: straight on when the edge is the platform's own, else to the nearest rail
	-- and a hop over it
	local half = Config.ZipLines.Platform / 2
	local fx, fz = p.fx, p.fz
	local sx, sz = -fz, fx -- the platform's side (right of the cable)
	local ax = (rx - p.x) * fx + (rz - p.z) * fz -- along the cable
	local ay = (rx - p.x) * sx + (rz - p.z) * sz -- across
	local ex, ey, ez, endFx, endFz = InteractPose.climbEnd(line, which, true, lift)
	local function walkTo(x: number, y: number, z: number, kind: string, seconds: number?, arc: number?)
		local last = points[#points]
		local dx, dz = x - last.x, z - last.z
		local d = math.sqrt(dx * dx + dz * dz)
		table.insert(points, InteractPose.point(x, y, z, kind, seconds or math.max(0.15, d / cfg.ClimbWalk), dx, dz, arc))
	end
	if math.abs(ax) <= half and math.abs(ay) <= half then
		-- (up onto the platform's floor already)
		points[#points].y = p.floor + lift
	elseif math.abs(ay) > half and ax > -half then
		-- beside it: to its side rail, over it
		local side = if ay > 0 then 1 else -1
		local along = math.clamp(ax, -half + 1, half - 1.5)
		walkTo(p.x + fx * along + sx * side * (half + RAIL_OUT), roof, p.z + fz * along + sz * side * (half + RAIL_OUT), "walk")
		walkTo(p.x + fx * along + sx * side * (half - 1.2), p.floor + lift, p.z + fz * along + sz * side * (half - 1.2), "hop", cfg.ClimbHop, 1.4)
	else
		-- behind it: to its back rail, over it
		local across = math.clamp(ay, -half + 1, half - 1)
		walkTo(p.x - fx * (half + RAIL_OUT) + sx * across, roof, p.z - fz * (half + RAIL_OUT) + sz * across, "walk")
		walkTo(p.x - fx * (half - 1.2) + sx * across, p.floor + lift, p.z - fz * (half - 1.2) + sz * across, "hop", cfg.ClimbHop, 1.4)
	end
	walkTo(ex, ey, ez, "walk")
	points[#points].fx, points[#points].fz = endFx, endFz
	return points
end

-- A whole climb from (x, y, z): up (the street → the platform) or down (the platform → the street).
function InteractPose.climbRoute(line: ZipLines.Line, which: number, up: boolean, x: number, y: number, z: number, lift: number): Route
	local cfg = Config.Interact
	local fixed = climbPoints(line, which, lift)
	local points: { Point } = {}
	if up then
		local first = fixed[1]
		table.insert(points, InteractPose.point(x, y, z, "walk", 0, first.x - x, first.z - z, 0))
		for _, p in fixed do
			table.insert(points, p)
		end
		return InteractPose.route(points)
	end
	-- Down: the same points backwards. Each segment keeps the kind of its way up (played the other way: "climb"
	-- down, "over" back over the edge, "hop" back over the rail), the climber faces the wall on the ladder and the
	-- way they walk on the roof.
	local last = fixed[#fixed]
	table.insert(points, InteractPose.point(x, y, z, "walk", 0, last.x - x, last.z - z, 0))
	table.insert(points, InteractPose.point(last.x, last.y, last.z, "walk", cfg.ClimbOnto * 0.6, last.x - x, last.z - z, 0))
	for i = #fixed - 1, 1, -1 do
		local here, after = fixed[i], fixed[i + 1] -- `after` reached `here`'s point on the way up
		local fx, fz = here.fx, here.fz
		if after.kind == "walk" or after.kind == "hop" then
			fx, fz = here.x - after.x, here.z - after.z -- the way they walk
		end
		local kind = if after.kind == "over" then "under" elseif after.kind == "climb" then "climbdown" else after.kind
		table.insert(points, InteractPose.point(here.x, here.y, here.z, kind, after.seconds, fx, fz, after.arc))
	end
	-- off the ladder at its foot, back onto the sidewalk
	local ex, ey, ez, fx, fz = InteractPose.climbEnd(line, which, false, lift)
	table.insert(points, InteractPose.point(ex, ey, ez, "off", cfg.ClimbOnto, fx, fz, 0))
	return InteractPose.route(points)
end

-- ── The poses ───────────────────────────────────────────────────────────────

local function v(x: number, y: number?, z: number?): Angles
	return { x = x, y = y or 0, z = z or 0 }
end

local function rad(d: number): number
	return math.rad(d)
end

function InteractPose.zero(): Pose
	local pose: Pose = {}
	for _, name in InteractPose.Joints do
		pose[name] = v(0)
	end
	return pose
end

function InteractPose.blend(a: Pose, b: Pose, k: number): Pose
	local pose: Pose = {}
	for _, name in InteractPose.Joints do
		local p, q = a[name] or v(0), b[name] or v(0)
		pose[name] = v(p.x + (q.x - p.x) * k, p.y + (q.y - p.y) * k, p.z + (q.z - p.z) * k)
	end
	return pose
end

-- A stride: the legs and arms swing with the distance walked (one step per StepLength studs).
function InteractPose.walk(dist: number, amount: number): Pose
	local c = dist / Config.Interact.StepLength * math.pi
	local s = math.sin(c) * amount
	local pose = InteractPose.zero()
	pose.rightHip = v(rad(28) * s)
	pose.leftHip = v(-rad(28) * s)
	-- the knee of the leg swinging back bends
	pose.rightKnee = v(-rad(34) * math.max(0, -s) - rad(6) * amount)
	pose.leftKnee = v(-rad(34) * math.max(0, s) - rad(6) * amount)
	pose.rightShoulder = v(-rad(22) * s)
	pose.leftShoulder = v(rad(22) * s)
	pose.rightElbow = v(rad(12) * amount)
	pose.leftElbow = v(rad(12) * amount)
	return pose
end

-- Hand over hand: one hand reaches up while the other pulls, the opposite knee steps up a rung.
function InteractPose.climb(dist: number): Pose
	local c = dist / (2 * Config.Interact.RungStep) * math.pi
	local s = math.sin(c)
	local pose = InteractPose.zero()
	pose.waist = v(-rad(4))
	pose.rightShoulder = v(rad(148) + rad(24) * s, 0, rad(10))
	pose.leftShoulder = v(rad(148) - rad(24) * s, 0, -rad(10))
	pose.rightElbow = v(rad(26) - rad(18) * s)
	pose.leftElbow = v(rad(26) + rad(18) * s)
	pose.rightHip = v(rad(38) - rad(30) * s)
	pose.leftHip = v(rad(38) + rad(30) * s)
	pose.rightKnee = v(-rad(52) + rad(36) * s)
	pose.leftKnee = v(-rad(52) - rad(36) * s)
	return pose
end

-- Over a roof's edge (u 0..1): the hands on the edge push the body up, the right knee comes up onto it, then the body
-- stands on the roof.
function InteractPose.over(u: number): Pose
	local k = math.sin(math.pi * math.clamp(u, 0, 1))
	local arms = 1 - ease(u)
	local pose = InteractPose.zero()
	pose.waist = v(-rad(26) * k)
	pose.rightShoulder = v(rad(140) * arms + rad(30) * k, 0, rad(8) * arms)
	pose.leftShoulder = v(rad(140) * arms + rad(30) * k, 0, -rad(8) * arms)
	pose.rightElbow = v(rad(30) * k)
	pose.leftElbow = v(rad(30) * k)
	pose.rightHip = v(rad(84) * k)
	pose.rightKnee = v(-rad(96) * k)
	pose.leftHip = v(rad(30) * k)
	pose.leftKnee = v(-rad(40) * k)
	return pose
end

-- A high step (over a rail, up into the bus): the right knee up first, the left one after.
function InteractPose.hop(u: number): Pose
	local x = math.clamp(u, 0, 1)
	local right = math.sin(math.pi * math.clamp(x / 0.65, 0, 1))
	local left = math.sin(math.pi * math.clamp((x - 0.35) / 0.65, 0, 1))
	local pose = InteractPose.zero()
	pose.waist = v(-rad(8) * math.max(right, left))
	pose.rightHip = v(rad(70) * right)
	pose.rightKnee = v(-rad(84) * right)
	pose.leftHip = v(rad(70) * left)
	pose.leftKnee = v(-rad(84) * left)
	pose.rightShoulder = v(-rad(18) * right + rad(18) * left, 0, rad(10) * math.max(right, left))
	pose.leftShoulder = v(rad(18) * right - rad(18) * left, 0, -rad(10) * math.max(right, left))
	return pose
end

-- From standing (0) to sitting (1): the thighs come up level, the knees bend, a little lean forward on the way.
function InteractPose.sit(u: number): Pose
	local k = ease(u)
	local mid = math.sin(math.pi * math.clamp(u, 0, 1))
	local pose = InteractPose.zero()
	pose.waist = v(-rad(14) * mid)
	pose.rightHip = v(SIT_THIGH * k)
	pose.leftHip = v(SIT_THIGH * k)
	pose.rightKnee = v(SIT_KNEE * k)
	pose.leftKnee = v(SIT_KNEE * k)
	pose.rightShoulder = v(rad(16) * mid)
	pose.leftShoulder = v(rad(16) * mid)
	return pose
end

-- A route segment's pose. dist: the studs walked or climbed so far (the stride and the rungs follow it).
function InteractPose.forKind(kind: string, u: number, dist: number): Pose
	if kind == "climb" or kind == "climbdown" then
		return InteractPose.climb(dist)
	elseif kind == "over" then
		return InteractPose.over(u)
	elseif kind == "under" then
		return InteractPose.over(1 - u)
	elseif kind == "hop" or kind == "step" then
		return InteractPose.hop(u)
	elseif kind == "sit" then
		return InteractPose.sit(u)
	elseif kind == "stand" then
		return InteractPose.sit(1 - u)
	elseif kind == "turn" then
		return InteractPose.zero() -- (a turn on the spot)
	end
	return InteractPose.walk(dist, 1)
end

-- Getting onto a bike (stand false: the right leg swung up and over the saddle behind you) or a scooter (stand true:
-- the left foot steps onto the deck, the right one follows), the hands going to the grips (the bar) all along. u 0..1
-- over the whole move, `step` the share of it spent walking to the side. The end is the seated rider's pose (the sit
-- animation's thighs and knees and shared/RiderPose.luau's, at the crank's start), so the seat takes over without a
-- jump. Getting off is the same backwards (u from 1 to 0).
function InteractPose.bikeMount(u: number, stand: boolean, step: number): Pose
	local rider: { [string]: { x: number, y: number } } = RiderPose.pose(stand, 0) :: any
	local x = math.clamp(u, 0, 1)
	local s = math.clamp(step, 0, 0.9)
	local reach = ease(x / math.max(1e-3, s + (1 - s) * 0.4)) -- the hands are on the grips before the leg is over
	local m = if x <= s then 0 else (x - s) / (1 - s) -- the mount's own progress
	local settle = ease(m)
	local function riderAt(name: string, sitX: number): Angles
		local r = rider[name]
		return v(((r and r.x or 0) + sitX) * settle, (r and r.y or 0) * settle, 0)
	end
	local pose = InteractPose.zero()
	-- the arms to the grips (the rider's own arm pose), the body leaning in with them
	local arm = rider.rightShoulder
	local larm = rider.leftShoulder
	local elbow = rider.elbow
	pose.rightShoulder = v((arm and arm.x or 0) * reach, (arm and arm.y or 0) * reach, 0)
	pose.leftShoulder = v((larm and larm.x or 0) * reach, (larm and larm.y or 0) * reach, 0)
	pose.rightElbow = v((elbow and elbow.x or 0) * reach)
	pose.leftElbow = v((elbow and elbow.x or 0) * reach)
	local waist = rider.waist
	pose.waist = v((waist and waist.x or 0) * math.max(reach * 0.5, settle))
	local bump = math.sin(math.pi * m)
	if stand then
		-- the left foot up onto the deck first, the right one after; the legs straight on it at the end
		local first = math.sin(math.pi * math.clamp(m / 0.6, 0, 1))
		local second = math.sin(math.pi * math.clamp((m - 0.4) / 0.6, 0, 1))
		pose.leftHip = v(riderAt("leftHip", SIT_THIGH).x + rad(52) * first)
		pose.leftKnee = v(riderAt("leftKnee", SIT_KNEE).x - rad(70) * first)
		pose.rightHip = v(riderAt("rightHip", SIT_THIGH).x + rad(40) * second)
		pose.rightKnee = v(riderAt("rightKnee", SIT_KNEE).x - rad(56) * second)
	else
		-- the right leg up and back, out over the rear wheel, and down on the far side; the left one bends into the sit
		local swing = math.sin(math.pi * math.clamp(m / 0.8, 0, 1))
		pose.rightHip = v(riderAt("rightHip", SIT_THIGH).x - rad(34) * swing, 0, rad(72) * swing)
		pose.rightKnee = v(riderAt("rightKnee", SIT_KNEE).x - rad(48) * swing)
		pose.leftHip = v(riderAt("leftHip", SIT_THIGH).x + rad(10) * bump)
		pose.leftKnee = v(riderAt("leftKnee", SIT_KNEE).x - rad(14) * bump)
		pose.waist = v(pose.waist.x - rad(10) * swing, 0, -rad(6) * swing)
	end
	return pose
end

-- The hands up to the zip line's trolley: how far (0..1) the hanging pose is laid on, u seconds into the ride's start.
function InteractPose.reachUp(u: number): number
	return ease(u / math.max(1e-3, Config.Interact.ZipReach))
end

-- The bike's mount timeline (getting on: Config.Interact BikeMount, the step to the side BikeStep of it), plus a
-- `lead` before it (a rented scooter sliding off its dock: you walk to its side meanwhile). Returns the move's length
-- and the step's share of it.
function InteractPose.mountTimes(lead: number): (number, number)
	local cfg = Config.Interact
	local total = math.max(0, lead) + cfg.BikeMount
	return total, (math.max(0, lead) + cfg.BikeMount * cfg.BikeStep) / total
end

return InteractPose
