-- 6.26 (6.24's bike test, now every vehicle): a vehicle knocked over gets back up (shared/CarUpright.luau,
-- Config.CarUpright; server/CarRighting.luau does what it says) in the standalone Luau CLI: how far it is tipped and
-- rolled however it lies, a hill is never "down", the owner's case (a van resting nose down with a wheel in the air)
-- is, a jump or a stunt is left alone, the ground's level under four wheels, the way it points kept (on its side, on
-- its nose, on its tail), and the watch: a bump left alone, a vehicle down for Hold seconds turned back up, the turn
-- ended when it is up again or, wedged, after Give seconds.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local CarUpright = require("./CarUpright")

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
	return math.abs(a - b) <= (eps or 1e-6)
end

local Cfg = Config.CarUpright
local Car, Bike = Cfg.Kinds.car, Cfg.Kinds.bike
check("the numbers are there", Cfg.Check > 0 and Cfg.Check <= 0.5 and Cfg.Slow > 0 and Cfg.Gap > 0 and Cfg.Probe > Cfg.Gap * 2
	and Cfg.Level > 14 and Config.BikeUpright == nil)
for name, k in { car = Car, bike = Bike } do
	check(name .. ": a full set of numbers", k.Hold >= 0.5 and k.Hold <= 2 and k.Give > k.Hold and k.Responsiveness > 0
		and k.TurnRate > 0 and k.Torque > 12000 and k.Lift >= 0 and k.Settled > 0 and k.Settled < k.Lean and k.Lean < k.Tilt)
	-- The roads climb 14° at most (Map: the curb's grade; the footbridge ramps no steeper): a vehicle on one is up.
	check(name .. ": on the steepest road (14°) it is down only with a wheel in the air", k.Tilt > 14 + 5 and k.Lean < 14)
end
check("the bike keeps 6.24's 45°, a car goes at about 35°", Bike.Tilt == 45 and Car.Tilt >= 30 and Car.Tilt <= 40)
check("the turn back holds a car down by more than its steering does (6000 × the mass)", Car.Torque > 6000 and Bike.Torque > 12000)

-- A frame: roll about its length (degrees, + lifts its right side), then pitch (+ nose up), then the way it points
-- (yaw). Returns its right, up and look vectors as { x, y, z }.
local function frame(roll: number, pitch: number, yaw: number): ({ number }, { number }, { number })
	local r, p, w = math.rad(roll), math.rad(pitch), math.rad(yaw)
	local function rotZ(v: { number }): { number }
		return { v[1] * math.cos(r) - v[2] * math.sin(r), v[1] * math.sin(r) + v[2] * math.cos(r), v[3] }
	end
	local function rotX(v: { number }): { number }
		return { v[1], v[2] * math.cos(p) - v[3] * math.sin(p), v[2] * math.sin(p) + v[3] * math.cos(p) }
	end
	local function rotY(v: { number }): { number }
		return { v[1] * math.cos(w) + v[3] * math.sin(w), v[2], -v[1] * math.sin(w) + v[3] * math.cos(w) }
	end
	local function turn(v: { number }): { number }
		return rotY(rotX(rotZ(v)))
	end
	return turn({ 1, 0, 0 }), turn({ 0, 1, 0 }), turn({ 0, 0, -1 })
end

-- tilt / roll
local right, up = frame(0, 0, 0)
check("upright: no tilt, no roll", near(CarUpright.tilt(up[2]), 0) and near(CarUpright.roll(right[2], up[2]), 0))
right, up = frame(90, 0, 30)
check("on its side: 90° both ways", near(CarUpright.tilt(up[2]), 90, 1e-4) and near(CarUpright.roll(right[2], up[2]), 90, 1e-4))
right, up = frame(-90, 0, 0)
check("on its other side too", near(CarUpright.roll(right[2], up[2]), 90, 1e-4))
right, up = frame(180, 0, 0)
check("on its back: 180°", near(CarUpright.tilt(up[2]), 180, 1e-4) and near(CarUpright.roll(right[2], up[2]), 180, 1e-4))
right, up = frame(0, 14, 0)
check("climbing a 14° ramp: tilted 14°, not rolled", near(CarUpright.tilt(up[2]), 14, 1e-4) and near(CarUpright.roll(right[2], up[2]), 0, 1e-4))
right, up = frame(30, 14, 70)
check("rolled 30° on a ramp: the roll is still 30°", near(CarUpright.roll(right[2], up[2]), 30, 1e-4), CarUpright.roll(right[2], up[2]))
check("tilt is clamped (a hair over 1 from the engine)", near(CarUpright.tilt(1.0000001), 0) and near(CarUpright.tilt(-1.0000001), 180))

-- tipped / settled (6.24's helpers, still there)
check("tipped / settled at a limit", CarUpright.tipped(math.cos(math.rad(50)), 45) and not CarUpright.tipped(math.cos(math.rad(40)), 45)
	and CarUpright.settled(math.cos(math.rad(5)), 6) and not CarUpright.settled(math.cos(math.rad(8)), 6))

-- down: what counts as down, for a car and a bike
local function tiltOf(roll: number, pitch: number): number
	local _, u = frame(roll, pitch, 0)
	return CarUpright.tilt(u[2])
end
local slow, fast = Cfg.Slow * 0.5, Cfg.Slow * 3
local function down(kind: any, roll: number, pitch: number, speed: number, gap: number): boolean
	return CarUpright.down(tiltOf(roll, pitch), speed, gap, kind, Cfg.Slow, Cfg.Gap)
end
check("standing level: not down", not down(Car, 0, 0, 0, 0) and not down(Bike, 0, 0, 0, 0))
check("parked on the steepest ramp, on all its wheels: not down", not down(Car, 0, 14, 0, 0) and not down(Car, 4, 14, 0, 0.1))
check("leaning into a turn (the bike's look's 9°): not down", not down(Bike, 9, 0, slow, 0))
check("THE OWNER'S CASE: a van 22° nose down, a back wheel 1.9 studs in the air, parked: down",
	down(Car, 8, -22, 0, 1.9) and down(Car, 0, -20, 0, 1.6))
check("... the same tilt on all four wheels (a ramp's crest): not down", not down(Car, 8, -22, 0, Cfg.Gap * 0.5))
check("on its side, slow: down (car and bike)", down(Car, 90, 0, slow, 0) and down(Bike, -80, 0, 0, 0))
check("half over (40°) slow: a car is down, a bike not yet (45°)", down(Car, 40, 0, slow, 0) and not down(Bike, 40, 0, slow, 0))
check("on its nose or its tail: down", down(Car, 0, -80, 0, 0) and down(Bike, 0, 80, 0, 0))
check("on its back: down at any speed", down(Car, 180, 0, fast, 0) and down(Bike, 175, 10, fast, 0))
check("a jump, a stunt (fast): left alone however it is tilted short of its back", not down(Car, 60, 0, fast, 3)
	and not down(Car, 0, -30, fast, 2) and not down(Bike, 80, 0, fast, 0))
check("at exactly Slow it counts as moving", not CarUpright.down(50, Cfg.Slow, 0, Car, Cfg.Slow, Cfg.Gap))

-- the ground's level under four wheels (front left, front right, back left, back right)
local flat = CarUpright.groundUp({ { -3, 0.4, -5 }, { 3, 0.4, -5 }, { -3, 0.4, 5 }, { 3, 0.4, 5 } })
check("flat ground: straight up", flat ~= nil and near(flat[1], 0) and near(flat[2], 1) and near(flat[3], 0))
local rise = math.tan(math.rad(14)) * 10
local ramp = CarUpright.groundUp({ { -3, rise, -5 }, { 3, rise, -5 }, { -3, 0, 5 }, { 3, 0, 5 } })
check("a 14° ramp rising ahead: 14° off up, leaning back", ramp ~= nil and near(CarUpright.angle(ramp, { 0, 1, 0 }), 14, 1e-4) and ramp[3] > 0,
	if ramp then `{ramp[1]}, {ramp[2]}, {ramp[3]}` else "nil")
local kerb = CarUpright.groundUp({ { -3, 0.4, -5 }, { 3, 0.9, -5 }, { -3, 0.4, 5 }, { 3, 0.9, 5 } })
check("two wheels on the kerb: a little rolled, still facing up", kerb ~= nil and kerb[2] > 0.99 and kerb[1] < 0)
local backwards = CarUpright.groundUp({ { 3, 0.4, 5 }, { -3, 0.4, 5 }, { 3, 0.4, -5 }, { -3, 0.4, -5 } })
check("the order turned round: still facing up", backwards ~= nil and near(backwards[2], 1))
check("in a line: none", CarUpright.groundUp({ { 0, 0, -5 }, { 0, 0, -5 }, { 0, 0, 5 }, { 0, 0, 5 } }) == nil)
check("fewer than four: none", CarUpright.groundUp({ { 0, 0, 0 }, { 1, 0, 0 }, { 0, 0, 1 } }) == nil)
check("angle", near(CarUpright.angle({ 0, 1, 0 }, { 1, 0, 0 }), 90) and near(CarUpright.angle({ 0, 2, 0 }, { 0, 1, 0 }), 0, 1e-4))

-- facing: the turn back's frame on the ground's level
local look, side = CarUpright.facing(0, -1, { 0, 1, 0 })
check("on flat ground facing -Z: look -Z, right +X", near(look[1], 0) and near(look[2], 0) and near(look[3], -1) and near(side[1], 1) and near(side[3], 0))
if ramp then
	look, side = CarUpright.facing(0, -1, ramp)
	check("up a 14° ramp: the look climbs 14° and lies on the ramp", near(math.deg(math.asin(look[2])), 14, 1e-4)
		and near(look[1] * ramp[1] + look[2] * ramp[2] + look[3] * ramp[3], 0, 1e-9) and near(side[1], 1, 1e-9))
end
look, side = CarUpright.facing(1, 0, { 0, 1, 0 })
check("facing +X: right +Z", near(side[3], 1) and near(look[1], 1))

-- heading
local function headingOf(roll: number, pitch: number, yaw: number): (number, number)
	local _, u, l = frame(roll, pitch, yaw)
	return CarUpright.heading(l[1], l[2], l[3], u[1], u[3])
end
local hx, hz = headingOf(0, 0, 0)
check("upright facing -Z keeps -Z", near(hx, 0) and near(hz, -1))
hx, hz = headingOf(90, 0, 0)
check("on its side it still points where it went", near(hx, 0, 1e-6) and near(hz, -1, 1e-6), `{hx}, {hz}`)
hx, hz = headingOf(-85, 20, 90)
local _, _, l90 = frame(0, 0, 90)
check("on its side on a slope, turned: its nose on the ground", near(hx, l90[1], 1e-6) and near(hz, l90[3], 1e-6), `{hx}, {hz}`)
hx, hz = headingOf(0, 90, 0)
check("standing on its tail: the way it pointed (its top faces back)", near(hx, 0, 1e-6) and near(hz, -1, 1e-6), `{hx}, {hz}`)
hx, hz = headingOf(0, -90, 0)
check("standing on its nose: the way it pointed (its top faces forward)", near(hx, 0, 1e-6) and near(hz, -1, 1e-6), `{hx}, {hz}`)
hx, hz = headingOf(0, 85, 45)
local _, _, l45 = frame(0, 0, 45)
check("nearly on its tail, turned 45°: still that way", near(hx, l45[1], 1e-6) and near(hz, l45[3], 1e-6), `{hx}, {hz}`)
hx, hz = CarUpright.heading(0, 1, 0, 0, 0)
check("nothing to go by: a flat unit anyway", near(hx * hx + hz * hz, 1))
hx, hz = headingOf(170, 10, -120)
check("always a flat unit", near(hx * hx + hz * hz, 1, 1e-9))

-- the watch
for name, k in { car = Car, bike = Bike } do
	local state = CarUpright.new()
	local hold, give = k.Hold, k.Give
	check(name .. ": upright: nothing", CarUpright.step(state, false, true, 0, hold, give) == "none")
	check(name .. ": down: wait first", CarUpright.step(state, true, false, 10, hold, give) == "wait")
	check(name .. ": ... still waiting before Hold", CarUpright.step(state, true, false, 10 + hold * 0.6, hold, give) == "wait")
	check(name .. ": a bump that rights itself is left alone", CarUpright.step(state, false, true, 10 + hold * 0.8, hold, give) == "none" and state.since == nil)
	check(name .. ": down again: the wait starts over", CarUpright.step(state, true, false, 20, hold, give) == "wait"
		and CarUpright.step(state, true, false, 20 + hold * 0.9, hold, give) == "wait")
	check(name .. ": down for Hold: turn it back up", CarUpright.step(state, true, false, 20 + hold, hold, give) == "start" and state.righting == 20 + hold)
	check(name .. ": turning (not up yet): keep", CarUpright.step(state, true, false, 20 + hold + 0.2, hold, give) == "keep"
		and CarUpright.step(state, false, false, 20 + hold + 0.4, hold, give) == "keep")
	check(name .. ": up again: stop", CarUpright.step(state, false, true, 20 + hold + 0.6, hold, give) == "stop" and state.righting == nil)
	check(name .. ": then it stands: nothing", CarUpright.step(state, false, true, 20 + hold + 0.8, hold, give) == "none")
	local wedged = CarUpright.new()
	CarUpright.step(wedged, true, false, 0, hold, give)
	check(name .. ": wedged: started", CarUpright.step(wedged, true, false, hold, hold, give) == "start")
	check(name .. ": wedged: keep until Give", CarUpright.step(wedged, true, false, hold + give - 0.1, hold, give) == "keep")
	check(name .. ": wedged: stood up at Give", CarUpright.step(wedged, true, false, hold + give, hold, give) == "fallback" and wedged.righting == nil and wedged.since == nil)
	check(name .. ": after that it watches afresh", CarUpright.step(wedged, true, false, hold + give + 0.2, hold, give) == "wait")
end

if failures > 0 then
	print(`{failures} FAILED`)
else
	print("ALL CHECKS PASSED")
end
