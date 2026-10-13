-- 6.24: a bike knocked over gets back up (shared/BikeUpright.luau, Config.BikeUpright; server/BikeRighting.luau does
-- what it says) in the standalone Luau CLI: how far a bike is tipped and rolled however it lies, a hill is never
-- "tipped", the way it points kept (on its side, on its nose, on its tail), and the watch: a bump left alone, a bike
-- down for Hold seconds turned back up, the turn ended when it is up again or, wedged, after Give seconds.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local BikeUpright = require("./BikeUpright")

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

local Cfg = Config.BikeUpright
check("the numbers are there", Cfg.Check > 0 and Cfg.Check <= 0.5 and Cfg.Hold >= 0.5 and Cfg.Hold <= 2 and Cfg.Give > Cfg.Hold
	and Cfg.Responsiveness > 0 and Cfg.TurnRate > 0 and Cfg.Torque > 12000 and Cfg.Lift >= 0)
check("tipped over at about 45° (the brief), up again well before that", Cfg.Tilt >= 35 and Cfg.Tilt <= 60 and Cfg.Settled < Cfg.Tilt)
-- The roads climb 14° at most (Map: the curb's grade; the footbridge ramps no steeper): a bike on one is upright.
check("a bike on the steepest road is neither tipped nor unsettled", Cfg.Settled > 14 and Cfg.Tilt > 14)

-- A bike's frame: roll about its length (degrees, + lifts its right side), then pitch (+ nose up), then the way it
-- points (yaw). Returns its right, up and look vectors as { x, y, z }.
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
local right, up, look = frame(0, 0, 0)
check("upright: no tilt, no roll", near(BikeUpright.tilt(up[2]), 0) and near(BikeUpright.roll(right[2], up[2]), 0))
right, up = frame(90, 0, 30)
check("on its side: 90° both ways", near(BikeUpright.tilt(up[2]), 90, 1e-4) and near(BikeUpright.roll(right[2], up[2]), 90, 1e-4))
right, up = frame(-90, 0, 0)
check("on its other side too", near(BikeUpright.roll(right[2], up[2]), 90, 1e-4))
right, up = frame(180, 0, 0)
check("on its back: 180°", near(BikeUpright.tilt(up[2]), 180, 1e-4) and near(BikeUpright.roll(right[2], up[2]), 180, 1e-4))
right, up = frame(0, 14, 0)
check("climbing a 14° ramp: tilted 14°, not rolled", near(BikeUpright.tilt(up[2]), 14, 1e-4) and near(BikeUpright.roll(right[2], up[2]), 0, 1e-4))
right, up = frame(30, 14, 70)
check("rolled 30° on a ramp: the roll is still 30°", near(BikeUpright.roll(right[2], up[2]), 30, 1e-4), BikeUpright.roll(right[2], up[2]))
check("tilt is clamped (a hair over 1 from the engine)", near(BikeUpright.tilt(1.0000001), 0) and near(BikeUpright.tilt(-1.0000001), 180))

-- tipped / settled
local function tippedAt(roll: number, pitch: number): boolean
	local _, u = frame(roll, pitch, 0)
	return BikeUpright.tipped(u[2], Cfg.Tilt)
end
local function settledAt(roll: number, pitch: number): boolean
	local _, u = frame(roll, pitch, 0)
	return BikeUpright.settled(u[2], Cfg.Settled)
end
check("leaning into a turn (the look's 9°) is not tipped", not tippedAt(9, 0) and settledAt(9, 0))
check("on the steepest ramp, leaning: not tipped, settled", not tippedAt(9, 14) and settledAt(5, 14))
check("on its side: tipped", tippedAt(90, 0) and tippedAt(-80, 0))
check("on its back: tipped", tippedAt(180, 0))
check("on its nose or its tail: tipped", tippedAt(0, -80) and tippedAt(0, 80))
check("half over (60°) is tipped, 30° is not settled yet", tippedAt(60, 0) and not settledAt(30, 0))

-- heading
local function headingOf(roll: number, pitch: number, yaw: number): (number, number)
	local _, u, l = frame(roll, pitch, yaw)
	return BikeUpright.heading(l[1], l[2], l[3], u[1], u[3])
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
hx, hz = BikeUpright.heading(0, 1, 0, 0, 0)
check("nothing to go by: a flat unit anyway", near(hx * hx + hz * hz, 1))
hx, hz = headingOf(170, 10, -120)
check("always a flat unit", near(hx * hx + hz * hz, 1, 1e-9))

-- the watch
local state = BikeUpright.new()
local hold, give = Cfg.Hold, Cfg.Give
check("upright: nothing", BikeUpright.step(state, false, true, 0, hold, give) == "none")
check("tipped: wait first", BikeUpright.step(state, true, false, 10, hold, give) == "wait")
check("... still waiting before Hold", BikeUpright.step(state, true, false, 10 + hold * 0.6, hold, give) == "wait")
check("a bump that rights itself is left alone", BikeUpright.step(state, false, true, 10 + hold * 0.8, hold, give) == "none" and state.since == nil)
check("tipped again: the wait starts over", BikeUpright.step(state, true, false, 20, hold, give) == "wait"
	and BikeUpright.step(state, true, false, 20 + hold * 0.9, hold, give) == "wait")
check("down for Hold: turn it back up", BikeUpright.step(state, true, false, 20 + hold, hold, give) == "start" and state.righting == 20 + hold)
check("turning (not up yet): keep", BikeUpright.step(state, true, false, 20 + hold + 0.2, hold, give) == "keep"
	and BikeUpright.step(state, false, false, 20 + hold + 0.4, hold, give) == "keep")
check("up again: stop", BikeUpright.step(state, false, true, 20 + hold + 0.6, hold, give) == "stop" and state.righting == nil)
check("then it stands: nothing", BikeUpright.step(state, false, true, 20 + hold + 0.8, hold, give) == "none")
local wedged = BikeUpright.new()
BikeUpright.step(wedged, true, false, 0, hold, give)
check("wedged: started", BikeUpright.step(wedged, true, false, hold, hold, give) == "start")
check("wedged: keep until Give", BikeUpright.step(wedged, true, false, hold + give - 0.1, hold, give) == "keep")
check("wedged: stood up at Give", BikeUpright.step(wedged, true, false, hold + give, hold, give) == "fallback" and wedged.righting == nil and wedged.since == nil)
check("after that it watches afresh", BikeUpright.step(wedged, true, false, hold + give + 0.2, hold, give) == "wait")

if failures > 0 then
	print(`{failures} FAILED`)
else
	print("ALL CHECKS PASSED")
end
