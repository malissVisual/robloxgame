--!strict
-- 8.9.4, the driving dashboard's rules (shared/PedalRules.luau, Config.DrivePedals): which gear and which pedal an
-- automatic shows for the driver's throttle and the car's speed: standing with nothing pressed P; W: D and the gas (the
-- brake while backing up, in R); S: the brake while rolling forward (still D), R and the gas standing or backing up;
-- rolling with nothing pressed D or R; Config's Stop the edge of standing; a pedal easing toward the foot at Config's
-- Ease, never past it, never out of 0 … 1; junk in (NaN, infinities, out of range) safe. (client/DrivePedals.luau on a
-- recorder: tools/phone-ui/drivepedals.luau.)
-- Run with tests/run_tests.py.
local Config = require("./Config")
local PedalRules = require("./PedalRules")

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
local function is(s: PedalRules.State, gear: string, gas: number, brake: number): boolean
	return s.gear == gear and near(s.gas, gas) and near(s.brake, brake)
end
local function show(s: PedalRules.State): string
	return `{s.gear} gas {s.gas} brake {s.brake}`
end

-- ── Config ─────────────────────────────────────────────────────────────────

local T = Config.DrivePedals
check("Config.DrivePedals: on", T.On == true)
check("Config.DrivePedals.Stop: a small speed (studs a second)", T.Stop > 0 and T.Stop <= 2, T.Stop)
check("Config.DrivePedals.Ease: a pedal down in a fraction of a second", T.Ease >= 4 and T.Ease <= 30, T.Ease)
check("the selector: P R N D, top to bottom", table.concat(PedalRules.Gears, " ") == "P R N D")

-- ── The gear and the pedals ────────────────────────────────────────────────

local s = PedalRules.state
check("standing, nothing pressed: P", is(s(0, 0), "P", 0, 0), show(s(0, 0)))
check("creeping under Stop, nothing pressed: P", is(s(0, T.Stop * 0.9), "P", 0, 0) and is(s(0, -T.Stop * 0.9), "P", 0, 0))
check("W standing: D and the whole gas", is(s(1, 0), "D", 1, 0), show(s(1, 0)))
check("W half (a gamepad's trigger): D and half the gas", is(s(0.5, 0), "D", 0.5, 0))
check("W rolling forward: D and the gas", is(s(1, 20), "D", 1, 0))
check("W backing up: the brake, still R", is(s(1, -6), "R", 0, 1), show(s(1, -6)))
check("W backing up slower than Stop: D and the gas", is(s(1, -T.Stop * 0.9), "D", 1, 0))
check("S rolling forward: the brake, still D", is(s(-1, 15), "D", 0, 1), show(s(-1, 15)))
check("S half rolling forward: half the brake", is(s(-0.5, 15), "D", 0, 0.5))
check("S standing: R and the gas", is(s(-1, 0), "R", 1, 0), show(s(-1, 0)))
check("S backing up: R and the gas", is(s(-1, -5), "R", 1, 0))
check("S rolling forward slower than Stop: R and the gas", is(s(-1, T.Stop * 0.9), "R", 1, 0))
check("rolling forward, nothing pressed: D, no pedal", is(s(0, 12), "D", 0, 0))
check("backing up, nothing pressed: R, no pedal", is(s(0, -4), "R", 0, 0))
check("never N (an automatic rolls in D)", (function()
	for _, t in { -1, -0.5, 0, 0.5, 1 } do
		for _, v in { -30, -1, -0.2, 0, 0.2, 1, 30 } do
			if s(t, v).gear == "N" then
				return false
			end
		end
	end
	return true
end)())
check("never both pedals at once, each 0 … 1", (function()
	for _, t in { -2, -1, -0.3, 0, 0.3, 1, 2 } do
		for _, v in { -30, -1, 0, 1, 30 } do
			local st = s(t, v)
			if st.gas < 0 or st.gas > 1 or st.brake < 0 or st.brake > 1 or (st.gas > 0 and st.brake > 0) then
				return false
			end
		end
	end
	return true
end)())
check("a throttle out of range: clamped", is(s(3, 0), "D", 1, 0) and is(s(-3, 10), "D", 0, 1))
check("junk in (NaN, infinities): P, nothing pressed", is(s(0 / 0, 0 / 0), "P", 0, 0) and is(s(math.huge, -math.huge), "P", 0, 0) and is(s((nil :: any), (nil :: any)), "P", 0, 0))

-- ── A pedal following the foot ─────────────────────────────────────────────

local ease = PedalRules.ease
check("one 60th of a second: down by Ease / 60", near(ease(0, 1, 1 / 60), T.Ease / 60), ease(0, 1, 1 / 60))
check("up again the same", near(ease(1, 0, 1 / 60), 1 - T.Ease / 60))
check("never past the foot", ease(0.95, 1, 0.1) == 1 and ease(0.05, 0, 0.1) == 0)
check("all the way down in 1 / Ease seconds", (function()
	local x, t = 0, 0
	while x < 1 and t < 5 do
		x = ease(x, 1, 1 / 60)
		t += 1 / 60
	end
	return x == 1 and near(t, 1 / T.Ease, 1 / 60 + 1e-9)
end)())
check("no time: stays", ease(0.4, 1, 0) == 0.4 and ease(0.4, 1, -1) == 0.4)
check("a foot out of range: 0 … 1", ease(0.99, 5, 1) == 1 and ease(0.01, -5, 1) == 0)
check("junk in: safe", ease(0 / 0, 1, 1) == 1 and ease(0.5, 0 / 0, 1) == 0 and ease(0.5, 1, 0 / 0) == 0.5)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
