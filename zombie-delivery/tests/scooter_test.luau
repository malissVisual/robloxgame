-- Logic test of the 6.10 E-Scooter ride (shared/ScooterRide.luau, Config.Scooter, Config.Interact's Scooter… numbers)
-- in the standalone Luau CLI: the steering curve (quick at walking pace, calm at the top speed) and its ramp, the pull,
-- the brake, the coast and the carve (6.14.1), the quick hop on and off (its path and the legs: InteractPose.scooterHop
-- ends in the rider's pose). (6.14.2: the wheelie is gone.)
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local ScooterRide = require("./ScooterRide")
local InteractPose = require("./InteractPose")
local Economy = require("./Economy")

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

local S = Config.Scooter
local I = Config.Interact
local def = Economy.findCar("escooter")
local TURN = if def then def.turn else 2.8
local TOP = if def then def.maxSpeed else 32

-- The numbers ---------------------------------------------------------------------

check("the E-Scooter is still a stand-up bike", def ~= nil and def.bike == true and def.stand == true and def.style == "scooter")
check("the rental is the same scooter", Config.Rental.CarId == "escooter")
check("the hop onto the deck is quick (≈0.3 s)", I.ScooterHop >= 0.2 and I.ScooterHop <= 0.35, I.ScooterHop)
check("… and off it no slower", I.ScooterHopOff > 0 and I.ScooterHopOff <= I.ScooterHop)
check("… quicker than a bike's step and leg over", I.ScooterHop < I.BikeMount and I.ScooterHopOff < I.BikeDismount)
check("the server's check of a dismount comes after the hop off", Config.Cargo.AlightSeconds + 0.4 > I.ScooterHopOff)
check("the scooter's prompt reaches only right beside it", I.ScooterReach >= 3 and I.ScooterReach <= 5 and I.ScooterReach < Config.Cargo.DriverDoorReach)
check("… from just left of its deck", I.ScooterPromptOut > 0 and I.ScooterPromptOut < 1)
check("off the deck you land clear of it", I.ScooterOff > 2 and I.ScooterOff < 3.5)
check("a scooter hopped onto stands within the seating's range", I.ScooterHopReach < Config.Cargo.BoardRange and I.ScooterCallSide < I.ScooterHopReach)
check("the rental's Ride needs no hold", Config.Rental.Hold == 0)
check("6.14.2: no wheelie any more", Config.Scooter.Wheelie == nil and (Config.Robust.Limits :: any).Wheelie == nil)
check("the dock's slide stays short", I.DockUnclip > 0.1 and I.DockUnclip <= I.ScooterHop)

-- The steering --------------------------------------------------------------------

check("no turn from a stand", near(ScooterRide.turnRate(0, TOP, TURN), 0))
check("full lock at walking pace (quick and tight)", near(ScooterRide.turnRate(S.GripSpeed + 0.5, TOP, TURN), TURN * S.LowTurn), ScooterRide.turnRate(3, TOP, TURN))
check("eased off at the top speed", near(ScooterRide.turnRate(TOP, TOP, TURN), TURN * S.HighTurn))
check("the same backing up", near(ScooterRide.turnRate(-4, TOP, TURN), ScooterRide.turnRate(4, TOP, TURN)))
local falling, before = true, math.huge
for v = S.EaseFrom, TOP, 0.5 do
	local rate = ScooterRide.turnRate(v, TOP, TURN)
	falling = falling and rate <= before + 1e-9
	before = rate
end
check("the turn eases off steadily with the speed", falling)
-- 6.14.1 (the owner: "a more pleasant ride"): the turn's radius (speed / turn rate) at walking pace, a middle speed and the
-- top: tight, calm (not the 6.10 twitch at 16 studs/s), not lazy (6.10: about 25 studs round at the top)
local function radius(v: number): number
	return v / ScooterRide.turnRate(v, TOP, TURN)
end
check("quick at walking pace: a turn under 3 studs round", radius(4) < 3, radius(4))
check("calm at a middle speed: a 16 studs/s turn at least 6.5 studs round", radius(16) >= 6.5, radius(16))
check("not lazy at the top: under 22 studs round", radius(TOP) < 22 and radius(TOP) > 14, radius(TOP))

local steer, t = 0, 0
while steer < 1 and t < 2 do
	steer = ScooterRide.steerStep(steer, 1, 1 / 60)
	t += 1 / 60
end
check("the steering ramps in, no snap (6.14.1: about a fifth of a second, a tap is a small turn)", t > 0.15 and t < 0.3, t)
local back = 0
while steer > 0 and back < 2 do
	steer = ScooterRide.steerStep(steer, 0, 1 / 60)
	back += 1 / 60
end
check("… and back to the middle quicker", back < t and near(steer, 0), back)
local s2 = ScooterRide.steerStep(0.6, -1, 1 / 60)
check("the other way: through the middle first", s2 < 0.6 and s2 >= 0)
check("a stick's share is held, not overshot", near(ScooterRide.steerStep(0.49, 0.5, 1), 0.5))

-- Throttle, brake, coast ------------------------------------------------------------

local target, rate = ScooterRide.drive(0, 1, TOP, 42)
check("a soft first push from a stand (6.14.1)", near(target, TOP) and near(rate, 42 * S.Pull.Start) and S.Pull.Start >= 0.5 and S.Pull.Start < 1, rate)
target, rate = ScooterRide.drive(TOP * 0.5, 1, TOP, 42)
check("… the full pull at a middle speed", near(rate, 42))
target, rate = ScooterRide.drive(TOP * 0.98, 1, TOP, 42)
check("… gliding into the top speed", rate < 42 * 0.5 and rate > 0, rate)
local rising, last = true, -1
for share = 0, S.Pull.Ease, 0.01 do
	local p = ScooterRide.pull(share)
	rising = rising and p >= last - 1e-9
	last = p
end
check("the pull never drops on the way to the full pull", rising)
do -- the time from a stand to 95 % of the top speed, as client/Drive.luau steps it
	local v, time = 0, 0
	while v < TOP * 0.95 and time < 5 do
		local goal, pull = ScooterRide.drive(v, 1, TOP, def and def.accel or 38)
		v = math.min(goal, v + pull / 60)
		time += 1 / 60
	end
	check("to 95 % of the top speed in about a second (quick, never a jolt)", time > 0.8 and time < 1.6, time)
end
target, rate = ScooterRide.drive(TOP, -1, TOP, 42)
check("a brake on S", rate == S.Brake and target < 0, rate)
check("… stops from the top speed in about half a second, not a jolt (6.14.1)", TOP / S.Brake >= 0.45 and TOP / S.Brake <= 0.8, TOP / S.Brake)
check("the carve follows the nose quickly, never all at once", ScooterRide.carve(1 / 60) > 0.15 and ScooterRide.carve(1 / 60) < 0.5 and near(ScooterRide.carve(0), 0), ScooterRide.carve(1 / 60))
target, rate = ScooterRide.drive(TOP, 0, TOP, 42)
check("no key: it coasts on", near(target, 0) and rate == S.Coast and S.Coast < 42 / 2)
target, rate = ScooterRide.drive(0, -1, TOP, 42)
check("S from a stand walks it back slowly", near(target, -TOP * S.Reverse) and target > -TOP / 3)
target, rate = ScooterRide.drive(-4, 1, TOP, 42)
check("W rolling back brakes first", rate == S.Brake and target > 0)

check("the lean into a turn is capped", near(ScooterRide.lean(5, 40), S.LeanMax) and near(ScooterRide.lean(-5, 40), -S.LeanMax))
check("… and none going straight", near(ScooterRide.lean(0, 30), 0))

-- The hop -------------------------------------------------------------------------

local k0, l0, r0 = ScooterRide.hop(0)
local k1, l1, r1 = ScooterRide.hop(1)
local _, lMid = ScooterRide.hop(0.5)
check("the hop starts where you stand and ends on the deck", near(k0, 0) and near(k1, 1) and near(l0, 0) and near(l1, 0, 1e-9))
check("… in an arc", near(lMid, I.ScooterArc))
check("… turned to the deck's way by 70%", near(r0, 0) and near(r1, 1) and near(select(3, ScooterRide.hop(0.7)), 1))
local ahead, last = true, -1
for n = 0, 20 do
	local k = ScooterRide.hop(n / 20)
	ahead = ahead and k >= last
	last = k
end
check("… always onward", ahead)
check("… quick off the ground", ScooterRide.hop(0.25) > 0.4)

local function maxDiff(a: InteractPose.Pose, b: InteractPose.Pose): number
	local d = 0
	for _, name in InteractPose.Joints do
		local p1, q1 = a[name], b[name]
		d = math.max(d, math.abs(p1.x - q1.x), math.abs(p1.y - q1.y), math.abs(p1.z - q1.z))
	end
	return d
end
check("the hop's legs start from the plain body", maxDiff(InteractPose.scooterHop(0), InteractPose.zero()) < 1e-6)
check("… and end in the scooter rider's pose (the mount's end)", maxDiff(InteractPose.scooterHop(1), InteractPose.bikeMount(1, true, 0.3)) < 1e-6)
check("… the knees tuck up in the air", InteractPose.scooterHop(0.5).leftHip.x > math.rad(60) and InteractPose.scooterHop(0.5).rightKnee.x < -math.rad(60))
check("… the hands on the bar by halfway", near(InteractPose.scooterHop(0.5).rightShoulder.x, InteractPose.bikeMount(1, true, 0.3).rightShoulder.x))
local jump, prev = 0, InteractPose.scooterHop(0)
for n = 1, 100 do
	local pose = InteractPose.scooterHop(n / 100)
	jump = math.max(jump, maxDiff(pose, prev))
	prev = pose
end
check("… smoothly", jump < 0.15, jump)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
