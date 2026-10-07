-- Logic test of the 5.7 interactions (shared/InteractPose.luau, Config.Interact) in the standalone Luau CLI: the routes
-- (their times add up, a fitted route keeps its shape, a sample walks from the start to the end), every zip line's
-- ladder climbed up and down (from the street to the platform and back, at the ladder's speed, ending where the server
-- puts a late climber), the poses (a bike's mount ends in the seated rider's pose and moves smoothly, the strides and
-- the rungs swing, the hands reach up to the trolley) and the numbers (the bus's boarding fits in its stop).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local InteractPose = require("./InteractPose")
local RiderPose = require("./RiderPose")
local ZipLines = require("./ZipLines")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) < (eps or 1e-6)
end

local I = Config.Interact

-- The numbers ---------------------------------------------------------------------

check("getting on a bike takes about half a second", I.BikeMount >= 0.4 and I.BikeMount <= 0.9, I.BikeMount)
check("the step to its side is a part of it", I.BikeStep > 0 and I.BikeStep < 0.6)
check("getting off is no slower", I.BikeDismount > 0 and I.BikeDismount <= I.BikeMount)
check("the server's check of a bike's dismount comes after it", Config.Cargo.AlightSeconds + 0.4 > I.BikeDismount)
check("the bus's boarding fits in its stop", I.BusBoard + I.BusDoorShut + 0.5 < Config.Bus.Dwell, I.BusBoard)
check("getting off the bus fits in its stop too", I.BusAlight + I.BusDoorShut < Config.Bus.Dwell)
check("a ladder is climbed at a walk's pace or slower", I.ClimbSpeed > 3 and I.ClimbSpeed <= Config.Movement.Walk)
check("the dock's scooter slides a little", I.DockSlide > 0.3 and I.DockSlide < 2 and I.DockUnclip > 0.1 and I.DockUnclip < 1)

-- The routes ----------------------------------------------------------------------

local P = InteractPose.point
local route = InteractPose.route({
	P(0, 3, 0, "walk", 0, 0, -1),
	P(0, 3, -10, "walk", 1, 0, -1),
	P(4, 3, -10, "hop", 0.5, 1, 0, 1.5),
	P(4, 6, -10, "climb", 1.5, 1, 0),
})
check("the times add up", near(route.total, 3) and near(route.times[3], 1.5), route.total)
check("the lengths add up", near(route.lengths[2], 10) and near(route.lengths[4], 17), route.lengths[4])
local x, y, z, fx, fz, kind, u, dist = InteractPose.sample(route, 0)
check("t 0: at the start", near(x, 0) and near(y, 3) and near(z, 0) and kind == "walk" and near(dist, 0), `{x} {y} {z} {kind}`)
x, y, z, fx, fz, kind, u, dist = InteractPose.sample(route, 0.5)
check("half the first segment: halfway, walking", near(z, -5) and kind == "walk" and near(u, 0.5) and near(dist, 5), `{z} {kind} {u} {dist}`)
x, y, z, fx, fz, kind, u, dist = InteractPose.sample(route, 1.25)
check("a hop arcs up in its middle", kind == "hop" and near(x, 2) and near(y, 4.5), `{x} {y} {kind}`)
check("turned to the hop's way by its middle", near(fx, 1, 1e-3) and near(fz, 0, 1e-3), `{fx} {fz}`)
x, y, z, fx, fz, kind, u, dist = InteractPose.sample(route, 99)
check("past the end: at the end", near(x, 4) and near(y, 6) and kind == "climb" and near(u, 1) and near(dist, 17), `{x} {y} {kind}`)
local fitted = InteractPose.fit(route, 6)
check("a fitted route takes its time", near(fitted.total, 6) and near(fitted.times[2], 2) and near(fitted.times[3], 3))
local fx2 = select(1, InteractPose.sample(fitted, 2.5))
check("… and keeps its shape", near(fx2, 2), fx2)

-- Every zip line's ladders ---------------------------------------------------------

local lines = ZipLines.lines()
check("there are zip lines to climb", #lines > 0)
local lift = 3
local climbsOk, endsOk, speedOk, downOk, arcOk, smoothOk = true, true, true, true, true, true
local worst = ""
for _, line in lines do
	for which = 1, 2 do
		local ladder = if which == 1 then line.ladderA else line.ladderB
		local platform = if which == 1 then line.a else line.b
		local sx, sz = ladder.x + ladder.nx * 3, ladder.z + ladder.nz * 3
		local up = InteractPose.climbRoute(line, which, true, sx, ladder.base + lift, sz, lift)
		local ex, ey, ez = InteractPose.climbEnd(line, which, true, lift)
		local x1, y1, z1 = InteractPose.sample(up, up.total)
		if not (near(x1, ex) and near(y1, ey) and near(z1, ez)) then
			endsOk = false
			worst = `{line.name} {which} up ends at {x1},{y1},{z1}`
		end
		if not near(ey, platform.floor + lift) then
			endsOk = false
			worst = `{line.name} {which}: not on the platform`
		end
		-- the climb itself at the ladder's pace, as long as the ladder
		local climbed = false
		for i = 2, #up.points do
			local a, b = up.points[i - 1], up.points[i]
			if b.kind == "climb" then
				climbed = true
				local speed = (b.y - a.y) / b.seconds
				if not near(speed, I.ClimbSpeed, 0.01) or b.y - a.y < (ladder.top - ladder.base) - 4 then
					speedOk = false
					worst = `{line.name} {which}: climbs {b.y - a.y} at {speed}`
				end
			end
		end
		if not climbed then
			climbsOk = false
		end
		-- never more than the arc over the roof, never under the street
		local t = 0
		local lastX, lastY, lastZ = sx, ladder.base + lift, sz
		while t <= up.total do
			local px, py, pz = InteractPose.sample(up, t)
			if py < ladder.base + lift - 0.01 or py > platform.floor + lift + 2 then
				arcOk = false
				worst = `{line.name} {which}: y {py} at {t}`
			end
			-- no jumps between two frames (60 fps)
			if math.sqrt((px - lastX) ^ 2 + (py - lastY) ^ 2 + (pz - lastZ) ^ 2) > 1.6 then
				smoothOk = false
				worst = `{line.name} {which}: a jump at {t}`
			end
			lastX, lastY, lastZ = px, py, pz
			t += 1 / 60
		end
		-- and down: from the platform back to the street by the ladder
		local down = InteractPose.climbRoute(line, which, false, ex, ey, ez, lift)
		local dx, dy, dz = InteractPose.sample(down, down.total)
		local fx3, fy3, fz3 = InteractPose.climbEnd(line, which, false, lift)
		if not (near(dx, fx3) and near(dy, fy3) and near(dz, fz3)) or not near(dy, ladder.base + lift) or math.abs(down.total - up.total) > 2 then
			downOk = false
			worst = `{line.name} {which} down ends at {dx},{dy},{dz} ({down.total} vs {up.total})`
		end
	end
end
check("every climb has the ladder in it", climbsOk, worst)
check("every climb up ends on its platform, where the server puts a late climber", endsOk, worst)
check("every ladder is climbed at ClimbSpeed, all the way", speedOk, worst)
check("no climb goes under the street or high over the platform", arcOk, worst)
check("no climb jumps between two frames", smoothOk, worst)
check("every climb down ends on the sidewalk by its ladder", downOk, worst)

-- The poses -----------------------------------------------------------------------

local function maxDiff(a: InteractPose.Pose, b: InteractPose.Pose): number
	local m = 0
	for _, name in InteractPose.Joints do
		local p, q = a[name], b[name]
		m = math.max(m, math.abs(p.x - q.x), math.abs(p.y - q.y), math.abs(p.z - q.z))
	end
	return m
end

for _, stand in { false, true } do
	local label = if stand then "the scooter" else "the bike"
	local start = InteractPose.bikeMount(0, stand, 0.3)
	check(`{label}: the mount starts from the plain body`, maxDiff(start, InteractPose.zero()) < 1e-6)
	local finish = InteractPose.bikeMount(1, stand, 0.3)
	local rider = RiderPose.pose(stand, 0)
	check(`{label}: the mount ends in the rider's arms`, near(finish.rightShoulder.x, rider.rightShoulder.x) and near(finish.leftShoulder.y, rider.leftShoulder.y) and near(finish.rightElbow.x, rider.elbow.x))
	check(`{label}: … and the seated legs (the sit under the rider's)`, finish.rightHip.x > rider.rightHip.x + 1 and finish.rightKnee.x < rider.rightKnee.x - 1 and near(finish.rightHip.z, 0), finish.rightHip.x)
	local jump, peak = 0, 0
	local before = start
	for n = 1, 100 do
		local pose = InteractPose.bikeMount(n / 100, stand, 0.3)
		jump = math.max(jump, maxDiff(pose, before))
		peak = math.max(peak, pose.rightHip.z, pose.leftHip.x)
		before = pose
	end
	check(`{label}: the mount moves smoothly`, jump < 0.15, jump)
	if stand then
		check("the scooter: the left foot steps up onto the deck", peak > math.rad(40), peak)
	else
		check("the bike: the right leg swings out over the saddle", peak > math.rad(60), peak)
	end
end
local total, share = InteractPose.mountTimes(0)
check("a mount takes BikeMount", near(total, I.BikeMount) and near(share, I.BikeStep))
total, share = InteractPose.mountTimes(I.DockUnclip)
check("… plus the dock's unclip, walked to the side meanwhile", near(total, I.BikeMount + I.DockUnclip) and share > I.BikeStep and share < 1)

local still = InteractPose.walk(0, 1)
check("a stride at its start: the legs together", near(still.rightHip.x, 0) and near(still.leftHip.x, 0))
local stride = InteractPose.walk(I.StepLength / 2, 1)
check("half a step on: the legs apart, the arms against them", stride.rightHip.x > 0.3 and stride.leftHip.x < -0.3 and stride.rightShoulder.x < 0 and stride.leftShoulder.x > 0)
check("no stride without walking", maxDiff(InteractPose.walk(1.3, 0), InteractPose.zero()) < 1e-6)
local c0, c1 = InteractPose.climb(0), InteractPose.climb(I.RungStep)
check("climbing: the hands up over the head", c0.rightShoulder.x > math.rad(120) and c0.leftShoulder.x > math.rad(120))
check("… one reaching while the other pulls, a rung on", c1.rightShoulder.x > c0.rightShoulder.x + 0.2 and c1.leftShoulder.x < c0.leftShoulder.x - 0.2)
check("over the edge: a knee comes up", InteractPose.over(0.5).rightHip.x > math.rad(60))
check("… and the body stands on the roof at its end", maxDiff(InteractPose.over(1), InteractPose.zero()) < 1e-6)
check("a hop lifts the right knee, then the left", InteractPose.hop(0.3).rightHip.x > InteractPose.hop(0.3).leftHip.x and InteractPose.hop(0.8).leftHip.x > InteractPose.hop(0.8).rightHip.x)
check("sitting ends with the thighs level and the knees bent", InteractPose.sit(1).rightHip.x > math.rad(80) and InteractPose.sit(1).leftKnee.x < math.rad(-80))
check("standing up is sitting backwards", maxDiff(InteractPose.forKind("stand", 0.3, 0), InteractPose.sit(0.7)) < 1e-6)
check("climbing down is a climb", maxDiff(InteractPose.forKind("climbdown", 0, 3), InteractPose.climb(3)) < 1e-6)
check("the hands reach up to the trolley", near(InteractPose.reachUp(0), 0) and near(InteractPose.reachUp(I.ZipReach), 1) and InteractPose.reachUp(I.ZipReach / 2) > 0.3)
check("a blend halfway is halfway", near(InteractPose.blend(InteractPose.zero(), InteractPose.sit(1), 0.5).rightHip.x, InteractPose.sit(1).rightHip.x / 2))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
