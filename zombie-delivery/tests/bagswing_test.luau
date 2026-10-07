-- 6.1, the plastic bag as a pendulum on a spring (shared/BagSwing.luau, Config.Courier.Bag): it hangs still, trails when
-- you start, leans back at a run, swings forward when you stop, out on a turn, settles, never flips over, ignores a
-- teleport and a broken frame, and stays steady at any frame rate. Run with tests/run_tests.py.
local Config = require("./Config")
local BagSwing = require("./BagSwing")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Courier.Bag
local MAX = math.rad(T.MaxTilt)

-- A body walking along -z: `speed(t)` studs / s; the hand at the body (no arm swing). Returns the last tilt (x, z), the
-- largest |tilt|, the largest back (+z) and forward (−z) tilt seen.
local function run(state: BagSwing.State, seconds: number, dt: number, speed: (number) -> number, start: number?, sideways: ((number) -> number)?)
	local t = start or 0
	local z, x = 0, 0
	local lx, lz = 0, 0
	local most, back, forward = 0, 0, 0
	local steps = math.floor(seconds / dt + 0.5)
	for _ = 1, steps do
		t += dt
		local v = speed(t)
		local side = if sideways then sideways(t) else 0
		z -= v * dt
		x += side * dt
		lx, lz = BagSwing.step(state, dt, { x, 1, z }, { side, 0, -v }, T)
		local size = math.sqrt(lx * lx + lz * lz)
		most = math.max(most, size)
		back = math.max(back, lz)
		forward = math.max(forward, -lz)
	end
	return lx, lz, most, back, forward, t
end

local function still(_: number): number
	return 0
end

-- The numbers ---------------------------------------------------------------------------------------------------------

check("a spring and a damping that settle (under-damped, not wild)", T.Spring > 10 and T.Damp > 0 and T.Damp < 2 * math.sqrt(T.Spring))
check("the kick about a real pendulum's (1 / g)", T.Kick > 0.002 and T.Kick < 0.02)
check("the air leans it 30-70° at a full run", math.deg(T.Drag * T.FullSpeed * T.FullSpeed) > 30 and math.deg(T.Drag * T.FullSpeed * T.FullSpeed) < 70)
check("a tilt limit under 90°", T.MaxTilt > 30 and T.MaxTilt < 90)
check("within ~120 studs of the camera", T.Range >= 80 and T.Range <= 160)

-- At rest -------------------------------------------------------------------------------------------------------------

local s = BagSwing.new()
local x, z, most = run(s, 2, 1 / 60, still)
check("standing: it hangs straight", math.abs(x) < 1e-6 and math.abs(z) < 1e-6 and most < 1e-6, most)

-- Starting to run, running, stopping ----------------------------------------------------------------------------------

s = BagSwing.new()
run(s, 0.5, 1 / 60, still)
local function sprint(t: number): number
	return math.min(T.FullSpeed, (t - 0.5) * 200) -- (Roblox's walk: up to speed in a few frames)
end
local _, _, _, back = run(s, 0.4, 1 / 60, sprint, 0.5)
check("starting: it trails back", back > math.rad(20), math.deg(back))
x, z = run(s, 3, 1 / 60, function(): number
	return T.FullSpeed
end, 0.9)
check("running: it leans back by the air", z > math.rad(30) and z <= MAX + 1e-6 and math.abs(x) < math.rad(T.Flutter) + 0.05, math.deg(z))
local _, _, _, _, forward = run(s, 0.8, 1 / 60, function(t: number): number
	return math.max(0, T.FullSpeed - (t - 3.9) * 200)
end, 3.9)
check("stopping: it swings forward", forward > math.rad(15), math.deg(forward))
x, z = run(s, 4, 1 / 60, still, 4.7)
check("then it settles, hanging", math.abs(x) < math.rad(1) and math.abs(z) < math.rad(1), math.deg(math.sqrt(x * x + z * z)))

-- A turn ------------------------------------------------------------------------------------------------------------------

s = BagSwing.new()
run(s, 2, 1 / 60, function(): number
	return 20
end)
-- (now veer to the right: a sideways speed builds up, the pull is to the right, the bag goes out to the left)
local lx = run(s, 0.3, 1 / 60, function(): number
	return 20
end, 2, function(t: number): number
	return (t - 2) * 60
end)
check("a turn: it swings out the other way", lx < -math.rad(5), math.deg(lx))

-- Robust --------------------------------------------------------------------------------------------------------------

s = BagSwing.new()
local _, _, wild = run(s, 3, 1 / 60, function(t: number): number
	return if math.floor(t * 4) % 2 == 0 then T.FullSpeed else 0 -- (stop and go four times a second)
end)
check("stop and go: never over the limit", wild <= MAX + 1e-6, math.deg(wild))
s = BagSwing.new()
local _, _, slow = run(s, 3, 1 / 10, function(t: number): number
	return if t < 1.5 then T.FullSpeed else 0
end)
check("at 10 frames a second: steady, within the limit", slow <= MAX + 1e-6 and slow == slow, math.deg(slow))
s = BagSwing.new()
run(s, 1, 1 / 60, still)
local tx, tz = BagSwing.step(s, 1 / 60, { 500, 1, 500 }, { 0, 0, 0 }, T)
check("a teleport: no fling, it starts again", tx == 0 and tz == 0)
tx, tz = BagSwing.step(s, 1 / 60, { 500, 1, 500 }, { 0, 0, 0 }, T)
check("… and hangs on", math.abs(tx) < 1e-6 and math.abs(tz) < 1e-6)
tx, tz = BagSwing.step(s, 0 / 0, { 500, 1, 500 }, { 0, 0, 0 }, T)
check("a broken frame changes nothing", tx == tx and tz == tz and math.abs(tx) < 1e-6)
tx, tz = BagSwing.step(s, 1 / 60, { 0 / 0, 1, 500 }, { 0, 0, 0 }, T)
check("a broken position changes nothing", tx == tx and tz == tz)
check("its size", BagSwing.tilt(BagSwing.new()) == 0)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
