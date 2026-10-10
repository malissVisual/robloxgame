-- 6.16: the cars' visual suspension (shared/Suspension.luau, Config.DriveFeel.Sway) in the standalone Luau CLI: the body
-- rolls out of a turn, dips its nose on the brake, squats as it pulls away, sinks as it lands, rocks back once after a
-- hard stop and settles; capped, steady at any frame rate, softer for a truck than for the muscle car.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Suspension = require("./Suspension")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Sway = Config.DriveFeel.Sway
check("the numbers are there", Sway.Roll > 0 and Sway.RollMax >= Sway.Roll and Sway.Dive > 0 and Sway.Squat > 0
	and Sway.PitchMax >= Sway.Dive and Sway.Frequency > 0.5 and Sway.Damping > 0.1 and Sway.Damping < 1)
check("the angles stay small (a look, not a tumble)", Sway.RollMax <= 6 and Sway.PitchMax <= 4 and Sway.HeaveMax <= 0.4)

local car = Suspension.tune(nil)
local deg = math.deg

-- The goal's signs: a left turn (acceleration to the left) leans the roof right (roll < 0); a brake dips the nose
-- (pitch < 0); pulling away lifts it (pitch > 0); landing (upward acceleration) sinks the body.
local roll, pitch, heave = Suspension.goal(car, 100, 0, 0)
check("a left turn rolls it out to the right", roll < 0 and math.abs(deg(roll) - -Sway.Roll) < 0.01, deg(roll))
roll = Suspension.goal(car, -100, 0, 0)
check("a right turn rolls it out to the left", roll > 0)
_, pitch = Suspension.goal(car, 0, -60, 0)
check("the brake dips the nose", pitch < 0 and math.abs(deg(pitch) + Sway.Dive) < 0.01, deg(pitch))
_, pitch = Suspension.goal(car, 0, 30, 0)
check("pulling away squats it (nose up)", pitch > 0 and math.abs(deg(pitch) - Sway.Squat) < 0.01, deg(pitch))
_, _, heave = Suspension.goal(car, 0, 0, 150)
check("landing sinks it", heave < 0 and math.abs(heave + Sway.Sink) < 1e-6, heave)
roll, pitch, heave = Suspension.goal(car, 5000, -5000, -5000)
check("everything is capped", math.abs(deg(roll)) <= Sway.RollMax + 1e-6 and math.abs(deg(pitch)) <= Sway.PitchMax + 1e-6
	and math.abs(heave) <= Sway.HeaveMax + 1e-6)
local still, level, flat = Suspension.goal(car, 0, 0, 0)
check("standing still: no lean", still == 0 and level == 0 and flat == 0)

-- The spring: a step toward the goal, an overshoot on letting go, settling.
local function run(state: Suspension.State, tune: Suspension.Tune, r: number, p: number, h: number, seconds: number, dt: number)
	local t = 0
	while t < seconds - 1e-9 do
		Suspension.step(state, tune, r, p, h, dt)
		t += dt
	end
end

local s = Suspension.new()
check("a new body rests", Suspension.resting(s))
local _, braking = Suspension.goal(car, 0, -60, 0)
run(s, car, 0, braking, 0, 1.5, 1 / 60)
check("held on the brake it settles at the dip", math.abs(s.pitch - braking) < math.rad(0.05), deg(s.pitch))
local dipped = s.pitch
local most = 0
for _ = 1, 90 do
	Suspension.step(s, car, 0, 0, 0, 1 / 60)
	most = math.max(most, s.pitch)
end
check("after the stop it rocks back once (nose up for a moment)", most > 0, deg(most))
check("… less than it dipped", most < math.abs(dipped) * 0.6, deg(most))
run(s, car, 0, 0, 0, 4, 1 / 60)
check("then it rests", Suspension.resting(s), deg(s.pitch))

-- The same at 20 fps and at 240 fps (the steps inside), and through a long hitch.
local turning = Suspension.goal(car, 100, 0, 0)
local slow, fast = Suspension.new(), Suspension.new()
run(slow, car, turning, braking, 0, 0.5, 1 / 20)
run(fast, car, turning, braking, 0, 0.5, 1 / 240)
check("the frame rate does not change the swing", math.abs(slow.pitch - fast.pitch) < math.rad(0.15), deg(slow.pitch - fast.pitch))
local hitch = Suspension.new()
Suspension.step(hitch, car, turning, braking, 0, 3)
check("a long hitch stays sane", math.abs(hitch.pitch) <= car.pitchMax * 1.5 and hitch.pitch == hitch.pitch)
local wild = Suspension.new()
for n = 1, 600 do
	Suspension.step(wild, car, if n % 2 == 0 then car.rollMax else -car.rollMax, 0, 0, 1 / 30)
end
check("shaken hard it never passes its overshoot cap", math.abs(wild.roll) <= car.rollMax * 1.5 + 1e-9)

-- A truck sways more and slower than a van; the muscle car less.
local truck, muscle = Suspension.tune("bus"), Suspension.tune("muscle")
check("a bus rolls more than a van", truck.roll > car.roll and truck.k < car.k)
check("the muscle car rolls less and is stiffer", muscle.roll < car.roll and muscle.k > car.k)
check("an unknown style is a plain car", Suspension.tune("nosuchstyle").roll == car.roll)
for style, soft in Sway.Soft do
	check(`{style}'s softness is sensible`, soft >= 0.4 and soft <= 1.6, soft)
end
Suspension.reset(wild)
check("reset rests", Suspension.resting(wild))

if failures > 0 then
	print(`{failures} FAILED`)
else
	print("ALL CHECKS PASSED")
end
