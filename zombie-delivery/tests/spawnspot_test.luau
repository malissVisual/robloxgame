-- 6.26: a vehicle never comes out into something (shared/SpawnSpot.luau, Config.SpawnSpot; server/Vehicles.luau
-- findRoom asks the world) in the standalone Luau CLI: the ground under the four wheels one plane or not (a crate under
-- a wheel, too steep; a hill road and a step are fine), the frame on it, the room the hull needs (over a step and the
-- road's paint), the spots tried (the one asked for first, a small spiral, never more than Tries, never far aside).
-- (10.6: no bike, no city car: the wheel spots are the van's own, server/Vehicles.luau wheelsOf.)
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local SpawnSpot = require("./SpawnSpot")
local SandboxMap = require("./SandboxMap")

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

local Cfg = Config.SpawnSpot
check("the numbers are there", Cfg.Tries >= 6 and Cfg.Tries <= 20 and Cfg.Gap > 0 and Cfg.Pad >= 0 and Cfg.Probe > 2
	and Cfg.Drop > 0 and Cfg.Drop < 1 and Cfg.Across >= 0 and Cfg.Across <= 2)
-- The step from the meadow up onto a yard's asphalt (SandboxMap.RoadTop over GroundTop; the old city's curb was 0.5)
-- and the road's paint stay under the room checked; the van's hull is not much below (its chassis 1.2 up).
check("the room starts over the asphalt's step", Cfg.Lift > SandboxMap.RoadTop - SandboxMap.GroundTop and Cfg.Lift <= 0.9)
check("a crate under one wheel is uneven", Cfg.Spread < 1.5)
check("the steepest road (14°) is fine, not much more", Cfg.Slope >= 14 and Cfg.Slope <= 20)

-- the four wheels' spots (front left, front right, back left, back right: the old Old Van's colliders, x ±3.1, z ±4.7)
local w = { { x = -3.1, z = -4.7 }, { x = 3.1, z = -4.7 }, { x = -3.1, z = 4.7 }, { x = 3.1, z = 4.7 } }
-- the degrees between two vectors
local function angleOf(a: { number }, b: { number }): number
	local dot = (a[1] * b[1] + a[2] * b[2] + a[3] * b[3]) / math.sqrt((a[1] ^ 2 + a[2] ^ 2 + a[3] ^ 2) * (b[1] ^ 2 + b[2] ^ 2 + b[3] ^ 2))
	return math.deg(math.acos(math.clamp(dot, -1, 1)))
end

-- plane: the ground under the four wheels (front left, front right, back left, back right)
local function at(heights: { number }, wheels: { any }?): { { number } }
	local list = {}
	local spots = wheels or w
	for n, h in heights do
		table.insert(list, { spots[n].x, h, spots[n].z })
	end
	return list
end
local function plane(heights: { number }, wheels: { any }?): (boolean, string, { number }?, { number }?)
	return SpawnSpot.plane(at(heights, wheels), Cfg.Spread, Cfg.Slope)
end
local ok, why, up, middle = plane({ 0.4, 0.4, 0.4, 0.4 })
check("flat road: one plane, straight up, its middle on the road", ok and up ~= nil and near(up[2], 1) and middle ~= nil and near(middle[2], 0.4))
ok = plane({ 0.4, 0.9, 0.4, 0.9 })
check("two wheels up the curb: one plane (a little rolled)", ok)
ok, why = plane({ 0.4, 0.4, 0.4, 0.4 + Cfg.Spread + 0.01 })
check("one wheel on something higher than Spread: uneven", not ok and why == "uneven ground", why)
ok = plane({ 0.4, 4.4, 0.4, 0.4 })
check("a wheel on a crate: uneven", not ok)
ok, why = plane({ 4.4, 4.4, 0.4, 0.4 })
check("both front wheels up on a crate: too steep (23°)", not ok and why == "ground too steep", why)
ok, why = plane({ 0.4, 4.4, 0.4, 4.4 })
check("both right wheels up on a crate: too steep", not ok and why == "ground too steep", why)
local rise = math.tan(math.rad(14)) * 9.4
ok, why, up, middle = plane({ rise + 3, rise + 3, 3, 3 })
check("a 14° hill road (a van's 9.4 wheelbase): one plane, its slope 14°, fine", ok and up ~= nil and near(angleOf(up, { 0, 1, 0 }), 14, 1e-4), why)
if up and middle then
	check("heightAt: the plane's height in the middle and under a wheel", near(SpawnSpot.heightAt(up, middle, 0, 0), 3 + rise / 2, 1e-6)
		and near(SpawnSpot.heightAt(up, middle, 3.1, -4.7), 3 + rise, 1e-6) and near(SpawnSpot.heightAt(up, middle, -3.1, 4.7), 3, 1e-6))
	local look, right, upOn = SpawnSpot.frame(up, 0, -1)
	check("frame on the hill road: facing up the climb, right level, up the plane's", near(math.deg(math.asin(look[2])), 14, 1e-4)
		and near(right[2], 0, 1e-9) and near(angleOf(upOn, up), 0, 1e-6))
end
local steep = math.tan(math.rad(Cfg.Slope + 2)) * 9.4
local steepUp
ok, why, steepUp = plane({ steep, steep, 0, 0 })
check("steeper than Slope: no spot, but its plane all the same (to stand it on when nothing is free)",
	not ok and why == "ground too steep" and steepUp ~= nil and near(angleOf(steepUp :: any, { 0, 1, 0 }), Cfg.Slope + 2, 1e-4), why)
check("Steepest: past Slope, short of a wall", Cfg.Steepest > Cfg.Slope and Cfg.Steepest < 60)
local leaning = { 0.4 + 0.5, 0.4, 0.4 + 0.5, 0.4 } -- (a road that leans across: the left wheels higher)
ok, why, up = plane(leaning)
check("ground that leans across: one plane", ok and up ~= nil, why)
if up then
	local _, _, upOn = SpawnSpot.frame(up, 0, -1)
	check("…the van stands with that roll (on its four wheels)", math.abs(upOn[1]) > 0.01)
end
ok, why = SpawnSpot.plane(at({ 0.4, 0.4, 0.4 }), Cfg.Spread, Cfg.Slope)
check("a wheel with no ground: no spot", not ok and why == "no ground under a wheel", why)

-- box
local sx, sy, sz, cy = SpawnSpot.box(6.6, 13, 7.1, Cfg.Lift, Cfg.Pad)
check("the room: padded all round, from Lift to the hull's top", near(sx, 6.6 + 2 * Cfg.Pad) and near(sz, 13 + 2 * Cfg.Pad)
	and near(cy - sy / 2, Cfg.Lift) and near(cy + sy / 2, 7.1))
sx, sy = SpawnSpot.box(2, 4, 0.3, Cfg.Lift, 0)
check("a hull lower than Lift still has some room", sy > 0)

-- steps and candidates
local along, across = SpawnSpot.steps(6.6, 13, Cfg.Gap)
check("steps: a length and a width apart (+ Gap)", near(along, 13 + Cfg.Gap) and near(across, 6.6 + Cfg.Gap))
local list = SpawnSpot.candidates(Cfg.Tries, along, across, Cfg.Across)
check("Tries spots", #list == Cfg.Tries, #list)
check("the one asked for first", list[1].along == 0 and list[1].across == 0)
check("then straight ahead, then behind (its lane, the kerb)", near(list[2].along, along) and list[2].across == 0
	and near(list[3].along, -along) and list[3].across == 0)
check("then to the right, then to the left", list[4].along == 0 and near(list[4].across, across) and list[5].along == 0 and near(list[5].across, -across))
local seen, ring, worst = {}, 0, 0
local unique, spiral = true, true
for _, c in list do
	local key = `{c.along}:{c.across}`
	unique = unique and not seen[key]
	seen[key] = true
	local r = math.max(math.abs(c.along / along), math.abs(c.across / across))
	spiral = spiral and r >= ring - 1e-9
	ring = math.max(ring, r)
	worst = math.max(worst, math.abs(c.across / across))
end
check("each spot once", unique)
check("a spiral outward: never back to a nearer ring", spiral)
check("never more than Across to either side (not up onto the sidewalk)", worst <= Cfg.Across + 1e-9)
check("the first ring is all there (8 spots round it)", #list >= 9 and (function(): boolean
	for n = 2, 9 do
		if math.max(math.abs(list[n].along / along), math.abs(list[n].across / across)) > 1 + 1e-9 then
			return false
		end
	end
	return true
end)())
local only = SpawnSpot.candidates(5, along, across, 0)
check("sides 0: only along the way it faces", #only == 5 and only[2].across == 0 and only[4].across == 0 and near(only[4].along, 2 * along))
check("one try: the spot asked for alone", #SpawnSpot.candidates(1, along, across, 1) == 1)

if failures > 0 then
	print(`{failures} FAILED`)
else
	print("ALL CHECKS PASSED")
end
