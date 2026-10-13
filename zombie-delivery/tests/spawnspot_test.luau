-- 6.26: a vehicle never comes out into something (shared/SpawnSpot.luau, Config.SpawnSpot; server/Vehicles.luau
-- findRoom asks the world) in the standalone Luau CLI: the four wheel spots match the factory's colliders, the ground
-- under them even or not, the room the hull needs (over a curb and the road's paint), the spots tried (the one asked for
-- first, a small spiral, never more than Tries, never up onto the sidewalk).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local SpawnSpot = require("./SpawnSpot")
local Map = require("./Map")

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
-- The curb (Map.WalkTop over Map.RoadTop) and the road's paint stay under the room checked; the lowest hull of any
-- vehicle (a scooter's chassis 0.3 … the cars' 0.6 and more: tools/vehicle-preview/ground-check.luau) is not much below.
check("the room starts over the curb", Cfg.Lift > Map.WalkTop - Map.RoadTop and Cfg.Lift <= 0.9)
check("a car straddling the curb is even enough, a crate under a wheel is not", Cfg.Spread >= Map.WalkTop - Map.RoadTop and Cfg.Spread < 1.5)

-- wheels: the Old Van's (13 × 6.6, wheel 1.3, 1 wide): the colliders at x ±3.1, z ±4.7 (Vehicles build)
local w = SpawnSpot.wheels(6.6, 13, 1.3, 1)
check("four wheels", #w == 4)
check("front left, front right, back left, back right", near(w[1].x, -3.1) and near(w[1].z, -4.7) and near(w[2].x, 3.1) and near(w[2].z, -4.7)
	and near(w[3].x, -3.1) and near(w[3].z, 4.7) and near(w[4].x, 3.1) and near(w[4].z, 4.7))

-- level
local ok, base = SpawnSpot.level({ 0.4, 0.4, 0.4, 0.4 }, Cfg.Spread)
check("flat road: even, stands on it", ok and near(base, 0.4))
ok, base = SpawnSpot.level({ 0.4, 0.9, 0.4, 0.9 }, Cfg.Spread)
check("two wheels up the curb: even enough, stands on the highest", ok and near(base, 0.9))
ok = SpawnSpot.level({ 0.4, 0.4, 0.4, 0.4 + Cfg.Spread + 0.01 }, Cfg.Spread)
check("a wheel on something higher than Spread: uneven", not ok)
ok = SpawnSpot.level({ 0.4, 4.4, 0.4, 0.4 }, Cfg.Spread)
check("a wheel on a crate: uneven", not ok)
local rise = math.tan(math.rad(14)) * 9.4
ok = SpawnSpot.level({ rise, rise, 0, 0 }, Cfg.Spread)
check("along a 14° ramp (a van's 9.4 wheelbase): uneven, not a spot", not ok)
ok = SpawnSpot.level({}, Cfg.Spread)
check("no ground at all: no spot", not ok)

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
