-- Test of the GPS routing (shared/Roads.luau) over the road network of shared/Map.luau, in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Map = require("./Map")
local Roads = require("./Roads")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function distance(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- Distance from a point to the centre line of a segment.
local function toSegment(s: any, x: number, z: number): number
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
	return distance(x, z, s.ax + dx * t, s.az + dz * t)
end

-- Is the point on the asphalt of a road (a little slack for the links where two roads only touch)?
local function onSomeRoad(x: number, z: number): boolean
	for _, s in Map.Segments do
		if toSegment(s, x, z) <= s.width / 2 + 3.5 then
			return true
		end
	end
	return false
end

-- Every step of the route between the snap points follows the roads.
local function continuous(route: { Roads.Point }): (boolean, string?)
	for k = 2, #route - 2 do
		local p, q = route[k], route[k + 1]
		local length = distance(p.x, p.z, q.x, q.z)
		local samples = math.max(1, math.ceil(length / 5))
		for n = 0, samples do
			local t = n / samples
			local x, z = p.x + (q.x - p.x) * t, p.z + (q.z - p.z) * t
			if not onSomeRoad(x, z) then
				return false, `off road at {math.floor(x)}, {math.floor(z)} (step {k})`
			end
		end
	end
	return true, nil
end

local nodes, edges = Roads.stats()
check("graph built", nodes > 100 and edges > nodes, `{nodes} nodes, {edges} edges`)

-- Every landmark is reachable from the depot by a sensible route.
for _, landmark in Map.Landmarks do
	local route = Roads.route(0, 0, landmark.x, landmark.z)
	local first, last = route[1], route[#route]
	local ends = first.x == 0 and first.z == 0 and last.x == landmark.x and last.z == landmark.z
	local length = Roads.length(route)
	local straight = distance(0, 0, landmark.x, landmark.z)
	local ok, why = continuous(route)
	check(`route to {landmark.id}`, ends and #route >= 2 and length < 3 * straight + 400 and ok, why or `{math.floor(length)} vs straight {math.floor(straight)}, {#route} points`)
end

-- Every named place too, and both directions.
for _, place in Map.Places do
	local there = Roads.route(0, 0, place.x, place.z)
	local back = Roads.route(place.x, place.z, 0, 0)
	local a, b = Roads.length(there), Roads.length(back)
	check(`route to and from {place.id}`, math.abs(a - b) < 0.1 * math.max(a, b) + 60 and (continuous(there)) and (continuous(back)), `{math.floor(a)} vs {math.floor(b)}`)
end

-- Across the river only over a bridge.
local bridgeZ: { number } = {}
for _, s in Map.Segments do
	if s.kind == "bridge" then
		table.insert(bridgeZ, s.az)
	end
end
check("two bridges", #bridgeZ >= 2, #bridgeZ)
local function crossesOnBridges(route: { Roads.Point }): (boolean, boolean)
	local crossed = false
	for k = 1, #route - 1 do
		local p, q = route[k], route[k + 1]
		local lo, hi = math.min(p.x, q.x), math.max(p.x, q.x)
		if hi > Map.River.x0 and lo < Map.River.x1 then
			crossed = true
			local onBridge = false
			for _, z in bridgeZ do
				if math.abs(p.z - z) < 1 and math.abs(q.z - z) < 1 then
					onBridge = true
				end
			end
			if not onBridge then
				return crossed, false
			end
		end
	end
	return crossed, true
end
for _, case in {
	{ "depot to docks", 0, 0, 1626, 0 },
	{ "north-west to harbor south", -500, -500, 1300, 400 },
	{ "suburbs to harbor north", 200, 1000, 1200, -400 },
	{ "harbor to farm", 1400, -300, -1880, 520 },
} do
	local route = Roads.route(case[2], case[3], case[4], case[5])
	local crossed, ok = crossesOnBridges(route)
	check(`{case[1]} crosses the river on a bridge`, crossed and ok)
end
-- Near the Old Bridge the route takes it, not the Rust Bridge.
do
	local route = Roads.route(500, -420, 1200, -420)
	local usesOld = false
	for k = 1, #route - 1 do
		local p, q = route[k], route[k + 1]
		local oldZ = -2.5 * Map.Cell
		if math.abs(p.z - oldZ) < 1 and math.abs(q.z - oldZ) < 1 and math.min(p.x, q.x) < Map.River.x0 and math.max(p.x, q.x) > Map.River.x1 then
			usesOld = true
		end
	end
	check("the Old Bridge when it is closer", usesOld)
end

-- To the Ski Lodge over the Lodge Road / the ice.
do
	local lodge
	for _, place in Map.Places do
		if place.id == "lodge" then
			lodge = place
		end
	end
	if lodge then
		local route = Roads.route(0, 0, lodge.x, lodge.z)
		local onLodgeRoad = false
		for k = 1, #route - 1 do
			local p, q = route[k], route[k + 1]
			if math.abs(p.z + 2200) < 1 and math.abs(q.z + 2200) < 1 and math.min(p.x, q.x) < Map.Lake.x1 then
				onLodgeRoad = true
			end
		end
		check("lodge route uses the Lodge Road and the ice", onLodgeRoad)
		check("lodge route goes up the North Highway", (function()
			for _, p in route do
				if math.abs(p.x - 300) < 1 and p.z < -2000 then
					return true
				end
			end
			return false
		end)())
	else
		check("lodge place exists", false)
	end
end

-- Inside the grid the route is close to the Manhattan distance.
do
	local route = Roads.route(-3 * Map.Cell - 30, -3.5 * Map.Cell, 3 * Map.Cell + 30, 3.5 * Map.Cell)
	local length = Roads.length(route)
	local manhattan = 6 * Map.Cell + 60 + 7 * Map.Cell
	check("grid route about the Manhattan distance", length <= manhattan + 2 and length >= manhattan * 0.9, `{length} vs {manhattan}`)
	check("grid route is simplified", #route <= 6, #route)
end

-- Same road piece, and the same point.
do
	local route = Roads.route(72, -100, 72, -300)
	check("straight along one road", #route == 2 and math.abs(Roads.length(route) - 200) < 0.01, #route)
	local here = Roads.route(10, 20, 10, 20)
	check("route to where you stand", #here >= 1 and Roads.length(here) < 200)
end

-- Roads.closest finds the point on the route.
do
	local route = Roads.route(0, 0, 1626, 0)
	local k, x, z, d = Roads.closest(route, route[2].x + 1, route[2].z + 1)
	check("closest point on the route", d < 2 and k >= 1 and k < #route, `{k} {x} {z} {d}`)
end

-- Fast enough to recompute a few times per second.
do
	local t0 = os.clock()
	local rand = Map.lcg(7)
	local B = Map.Bounds
	for _ = 1, 300 do
		Roads.route(B.x0 + rand() * (B.x1 - B.x0), B.z0 + rand() * (B.z1 - B.z0), B.x0 + rand() * (B.x1 - B.x0), B.z0 + rand() * (B.z1 - B.z0))
	end
	local each = (os.clock() - t0) / 300
	check(`a route takes under 2 ms ({math.floor(each * 1e6)} µs)`, each < 0.002)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
