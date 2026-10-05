-- Logic test of the 3.9 melee (shared/Melee.luau, Config.Melee) in the standalone Luau CLI: the punch is weaker and
-- quicker than the gun strike, the cone reaches what is in front within Reach and HalfAngle and nothing behind, above
-- or too far, and the arm's swing curve starts and ends at rest and is continuous.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Melee = require("./Melee")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local M = Config.Melee

-- ── The kinds ──────────────────────────────────────────────────────────────

check("holstered punches, drawn strikes with the gun", Melee.kindOf(true) == "punch" and Melee.kindOf(false) == "gun")
local punch, strike = Melee.def("punch"), Melee.def("gun")
check("the punch is weaker than the gun strike", punch.damage < strike.damage, `{punch.damage} / {strike.damage}`)
check("the punch is quicker than the gun strike", punch.cooldown < strike.cooldown, `{punch.cooldown} / {strike.cooldown}`)
check("both push and hurt", punch.damage > 0 and strike.damage > 0 and punch.push > 0 and strike.push > 0)
check("an unknown kind is a punch", Melee.def("kick") == punch)
check("a swing ends before the next can start", M.SwingTime > 0 and M.SwingTime <= punch.cooldown)
check("the reach is short (a few studs)", M.Reach >= 3 and M.Reach <= 8, M.Reach)
check("the cone is under a half turn", M.HalfAngle > 20 and M.HalfAngle < 90, M.HalfAngle)

-- ── The cone ───────────────────────────────────────────────────────────────

-- From the origin facing -Z (Roblox's forward).
local function at(x: number, y: number, z: number): number?
	return Melee.reach(0, 0, 0, 0, -1, x, y, z)
end
check("straight ahead in reach", at(0, 0, -4) ~= nil and math.abs((at(0, 0, -4) :: number) - 4) < 1e-9)
check("ahead at the very edge of the reach", at(0, 0, -M.Reach) ~= nil)
check("just past the reach: missed", at(0, 0, -(M.Reach + 0.1)) == nil)
check("behind: missed", at(0, 0, 4) == nil)
check("straight to the side: missed", at(4, 0, 0) == nil)
local inside = math.rad(M.HalfAngle - 5)
local outside = math.rad(M.HalfAngle + 5)
check("inside the half angle: hit", at(4 * math.sin(inside), 0, -4 * math.cos(inside)) ~= nil)
check("outside the half angle: missed", at(4 * math.sin(outside), 0, -4 * math.cos(outside)) == nil)
check("the other side is the same", at(-4 * math.sin(inside), 0, -4 * math.cos(inside)) ~= nil and at(-4 * math.sin(outside), 0, -4 * math.cos(outside)) == nil)
check("a little up or down: hit", at(0, 2, -3) ~= nil and at(0, -2, -3) ~= nil)
check("far above (a ledge): missed", at(0, M.Height + 1, -3) == nil)
check("right on top of you: hit whatever the direction", at(0.5, 0, 0.3) ~= nil)
check("an unnormalised direction works the same", Melee.reach(0, 0, 0, 0, -7, 0, 0, -4) ~= nil and Melee.reach(0, 0, 0, 0, -7, 0, 0, 4) == nil)
check("no direction: only what is on top of you", Melee.reach(0, 0, 0, 0, 0, 0, 0, -3) == nil)
check("a moved origin", Melee.reach(100, 10, 50, 1, 0, 104, 11, 50) ~= nil and Melee.reach(100, 10, 50, 1, 0, 96, 10, 50) == nil)
-- The nearest wins (CloseCombat picks the smallest distance).
local near, far = at(0, 0, -2), at(1, 0, -4.5)
check("distances order the targets", near ~= nil and far ~= nil and (near :: number) < (far :: number))

-- ── The swing curve ────────────────────────────────────────────────────────

local t0, k0 = Melee.swing(0)
check("the swing starts at rest", t0 == 0 and k0 == 0)
local tEnd = Melee.swing(M.SwingTime)
check("the swing ends at rest", tEnd == 0)
check("before it starts: rest", (Melee.swing(-0.1)) == 0)
local tMid, kMid = Melee.swing(M.SwingTime * 0.5)
check("halfway: fully out, at the hit", math.abs(tMid - 1) < 1e-6 and math.abs(kMid - 1) < 1e-6)
local tWind, kWind = Melee.swing(M.SwingTime * 0.2499)
check("the wind-up first", tWind > 0.9 and kWind == 0)
-- Continuous: no jump bigger than a small step between two close moments (up to the last moment before the end,
-- where the pose is back to nothing and where it was between wind-up and hit no longer matters).
local worst = 0
local lastT, lastK = Melee.swing(0)
local steps = 400
for i = 1, steps - 1 do
	local t, k = Melee.swing(M.SwingTime * i / steps)
	worst = math.max(worst, math.abs(t - lastT), math.abs(k - lastK))
	lastT, lastK = t, k
end
check("the curve is smooth (no jumps)", worst < 0.05, worst)
local inRange = true
for i = 0, steps do
	local t, k = Melee.swing(M.SwingTime * i / steps)
	if t < 0 or t > 1 or k < 0 or k > 1 then
		inRange = false
	end
end
check("the curve stays in 0..1", inRange)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
