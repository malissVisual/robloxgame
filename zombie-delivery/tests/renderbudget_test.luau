-- 6.13.1: the performance rules (shared/RenderBudget.luau, Config.Performance) in the standalone Luau CLI: which parts
-- throw a shadow, which night lights shine (nearest first, a vehicle's lights together, no blinking at the edge), the
-- phone's smaller light budget.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local RenderBudget = require("./RenderBudget")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local P = Config.Performance
check("the numbers are there", type(P.ShadowLong) == "number" and type(P.ShadowWide) == "number" and type(P.ShadowFlat) == "number" and type(P.ShadowFlatHeight) == "number")
check("a phone gets fewer lights, closer", P.Lite.MaxLights < P.MaxLights and P.Lite.LightRange < P.LightRange and P.Lite.MaxLights >= 8)
check("a phone's ranges shrink but stay", P.Lite.Range > 0.3 and P.Lite.Range < 1 and P.Lite.Count > 0.2 and P.Lite.Count <= 1)
check("the hold is a little more than the budget", P.LightHoldRange > 1 and P.LightHoldRange < 1.5 and P.LightHoldExtra >= 1 and P.LightFade > 0 and P.LightFade < 1)

-- Shadows: big things yes, small and thin things no, flat plates on the ground no.
local casts = RenderBudget.casts
check("a wall throws a shadow", casts(40, 22, 2, 0, 12))
check("a lamp pole (0.6 x 16 x 0.6) throws one", casts(0.6, 16, 0.6, 0, 9))
check("a street-light pole (0.5 x 12 x 0.5) throws one", casts(0.5, 12, 0.5, 0, 7))
check("a crate (3 x 3 x 3) throws one", casts(3, 3, 3, 0, 2))
check("a tree's leaves (a 7-stud ball) throw one", casts(7, 7, 7, 0, 12))
check("a roof slab (1 thick, lying) throws one", casts(82, 1, 42, 1, 23))
check("a bolt (0.3 x 0.3 x 0.3) does not", not casts(0.3, 0.3, 0.3, 0, 3))
check("a small box (1.5 x 1 x 1) does not", not casts(1.5, 1, 1, 0, 2))
check("a rail (0.2 x 0.2 x 12) does not", not casts(0.2, 0.2, 12, 0, 3))
check("a lamp arm (0.35 x 0.35 x 4.4) does not", not casts(0.35, 0.35, 4.4, 0, 16))
check("a road mark (0.05 thick, lying on the road) does not", not casts(0.6, 0.05, 10, 1, 0.55))
check("a lawn (0.1 thick, lying on the walk) does not", not casts(30, 0.1, 30, 1, 0.95))
check("a raised canopy (0.2 thick, lying, 9 up) still does", casts(12, 0.2, 8, 1, 9.5))
check("a palm's leaf high up (0.15 thick, lying) still does", casts(6, 0.15, 1.6, 0.95, 14))
check("a plate with no height known is taken as on the ground", not casts(8, 0.1, 8, 1))
check("a standing sign (6 x 2 x 0.2) still does", casts(6, 2, 0.2, 0, 3))
check("an awning tilted 15° (0.3 thick) still does", casts(30, 0.3, 4, math.cos(math.rad(15)), 9.4))
check("a thin plate tilted far up (0.2 thick, 60°) still does", casts(4, 0.2, 4, math.cos(math.rad(60)), 1))

-- shadowFor: the thinnest side's axis and the height from a CFrame (a stand-in with the axis vectors and Position).
local function frame(right: { number }, up: { number }, look: { number }, y: number): any
	return {
		RightVector = { X = right[1], Y = right[2], Z = right[3] },
		UpVector = { X = up[1], Y = up[2], Z = up[3] },
		LookVector = { X = look[1], Y = look[2], Z = look[3] },
		Position = { X = 0, Y = y, Z = 0 },
	}
end
local upright = frame({ 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, -1 }, 0.95)
local onItsSide = frame({ 0, 1, 0 }, { -1, 0, 0 }, { 0, 0, -1 }, 0.95) -- (the X side points up)
local raised = frame({ 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, -1 }, 10)
check("shadowFor: a lawn lying flat does not", not RenderBudget.shadowFor({ X = 30, Y = 0.1, Z = 30 } :: any, upright))
check("shadowFor: the same plate stood up on its edge does", RenderBudget.shadowFor({ X = 30, Y = 0.1, Z = 30 } :: any, onItsSide))
check("shadowFor: a sheet thin along X, X pointing up, does not", not RenderBudget.shadowFor({ X = 0.1, Y = 8, Z = 8 } :: any, onItsSide))
check("shadowFor: the lawn's plate 10 studs up (a canopy) does", RenderBudget.shadowFor({ X = 30, Y = 0.1, Z = 30 } :: any, raised))
check("shadowFor: a wall does", RenderBudget.shadowFor({ X = 40, Y = 20, Z = 1 } :: any, upright))

-- The lights that shine: RenderBudget.choose.
local function units(list: { { number } }): { RenderBudget.Unit }
	local out: { RenderBudget.Unit } = {}
	for _, u in list do
		table.insert(out, { distance = u[1], size = u[2] or 1, on = u[3] == 1 })
	end
	return out
end
local picked = RenderBudget.choose(units({ { 50 }, { 400 }, { 10 }, { 90 }, { 30 }, { 250 } }), 3, 300)
check("the three nearest in range shine", picked[3] and picked[5] and picked[1] and not picked[4], picked)
check("nothing out of range shines", not picked[2] and not picked[6])
local few = RenderBudget.choose(units({ { 500 }, { 20 } }), 10, 300)
check("fewer in range than allowed: all of those", few[2] == true and few[1] == nil)
check("no lights: none", next(RenderBudget.choose({}, 5, 300)) == nil)
-- A car's two headlights go together: both or neither.
local car = RenderBudget.choose(units({ { 10 }, { 20 }, { 30, 2 } }), 3, 300)
check("a car's pair does not fit in the last slot: neither shines", car[1] and car[2] and not car[3], car)
local roomy = RenderBudget.choose(units({ { 10 }, { 15, 2 }, { 20 } }), 3, 300)
check("a nearer car's pair that fits shines whole, the lamp behind it waits", roomy[1] and roomy[2] and not roomy[3], roomy)
-- Hysteresis at the range: one that shines keeps shining a little past it; one that does not waits for the range.
local edge = 300 * P.LightHoldRange
local held = RenderBudget.choose(units({ { 320, 1, 1 }, { 320, 1, 0 }, { edge + 1, 1, 1 } }), 10, 300)
check("a shining light just past the range stays on", held[1] == true)
check("a dark light just past the range stays dark", held[2] == nil)
check("a shining light past range × hold goes out", held[3] == nil)
-- Hysteresis at the count: a new nearer light takes its slot, the farthest shining one keeps its own for a while.
local list: { { number } } = {}
for n = 1, 10 do
	table.insert(list, { n * 10, 1, 1 }) -- ten shining
end
table.insert(list, { 5, 1, 0 }) -- a new one, nearest of all
local crowded = RenderBudget.choose(units(list), 10, 300)
check("the new nearest light shines", crowded[11] == true)
check("the farthest shining one is held (count + extra)", crowded[10] == true)
local many: { { number } } = {}
for n = 1, 10 do
	table.insert(many, { n * 10, 1, 1 })
end
for n = 1, P.LightHoldExtra + 1 do
	table.insert(many, { n * 0.5, 1, 0 }) -- more new ones than the hold allows
end
local full = RenderBudget.choose(units(many), 10, 300)
local shining = 0
for _ in full do
	shining += 1
end
check("never more than count + extra shine", shining <= 10 + P.LightHoldExtra, shining)
check("the farthest held one goes out once the extra is used up", full[10] == nil)
local maxLights, range = RenderBudget.numbers(false)
local liteLights, liteRange = RenderBudget.numbers(true)
check("the computer's numbers", maxLights == P.MaxLights and range == P.LightRange)
check("the phone's numbers", liteLights == P.Lite.MaxLights and liteRange == P.Lite.LightRange)
-- A dense street at night, nothing shining yet: 200 lamps 10 studs apart, the camera at one end.
local street: { { number } } = {}
for n = 1, 200 do
	street[n] = { n * 10 }
end
local inRange = math.floor(range / 10)
for _, budget in { { maxLights, "a computer" }, { liteLights, "a phone" } } do
	local most = budget[1] :: number
	local lit = RenderBudget.choose(units(street), most, range)
	local count, nearestOnly = 0, true
	for index in lit do
		count += 1
		nearestOnly = nearestOnly and index <= most
	end
	check(`a dense street on {budget[2]}: only the nearest shine`, nearestOnly)
	check(`a dense street on {budget[2]}: within its budget`, count == math.min(most, inRange), count)
end

if failures > 0 then
	print(`{failures} FAILED`)
else
	print("ALL CHECKS PASSED")
end
