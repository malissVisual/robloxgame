-- Test of the traffic geometry (shared/TrafficLanes.luau): the lanes the civilian cars drive and the sidewalks the
-- pedestrians walk, in the standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Map = require("./Map")
local TrafficLanes = require("./TrafficLanes")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function toSegment(s: any, x: number, z: number): number
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
	return math.sqrt((x - s.ax - dx * t) ^ 2 + (z - s.az - dz * t) ^ 2)
end

-- On the asphalt of some road (the bulge of a U-turn at a dead end may go a little past the road's end).
local function onSomeRoad(x: number, z: number, slack: number): boolean
	for _, s in Map.Segments do
		if toSegment(s, x, z) <= s.width / 2 + slack then
			return true
		end
	end
	return false
end

local g = TrafficLanes.graph()
check("graph built", #g.x > 100 and #g.from > #g.x and #g.lanes > 100, `{#g.x} nodes, {#g.from} directed edges, {#g.lanes} lanes`)
check("graph is cached", TrafficLanes.graph() == g)

-- Every directed edge has its reverse, the same length the other way.
do
	local ok = true
	for e = 1, #g.from do
		local r = g.reverse[e]
		if g.reverse[r] ~= e or g.from[r] ~= g.to[e] or math.abs(g.len[r] - g.len[e]) > 1e-6 then
			ok = false
		end
	end
	check("every edge has a reverse", ok)
end

-- No traffic in the winter, on the ice or past the tunnel; the city, the bridges and the highways have lanes.
do
	local bad = 0
	local kinds: { [string]: number } = {}
	for _, e in g.lanes do
		local a, b = g.from[e], g.to[e]
		for _, p in { { g.x[a], g.z[a] }, { g.x[b], g.z[b] } } do
			if Map.isWinter(p[1], p[2]) or Map.onIce(p[1], p[2]) or p[2] < TrafficLanes.NorthLimit then
				bad += 1
			end
		end
		if g.kind[e] == "ice" then
			bad += 1
		end
		kinds[g.kind[e]] = (kinds[g.kind[e]] or 0) + 1
	end
	check("no lane in the winter, on the ice or past the tunnel", bad == 0, bad)
	check("lanes on grids, bridges, highways and streets", (kinds.grid or 0) > 50 and (kinds.bridge or 0) >= 4 and (kinds.highway or 0) >= 6 and (kinds.street or 0) >= 4)
	check("the north limit is south of the tunnel", TrafficLanes.NorthLimit > Map.Mountain.tunnelZ1 and TrafficLanes.NorthLimit > Map.WinterZ)
end

-- The lanes are on the right side of the road, inside the asphalt.
do
	local wrongSide, offRoad = 0, 0
	for _, e in g.lanes do
		local piece = TrafficLanes.lane(g, e)
		local mx, mz = (piece.px[1] + piece.px[2]) / 2, (piece.pz[1] + piece.pz[2]) / 2
		local cx, cz = (g.x[g.from[e]] + g.x[g.to[e]]) / 2, (g.z[g.from[e]] + g.z[g.to[e]]) / 2
		-- right of the direction (dx, dz) with -Z north is (-dz, dx)
		local side = (mx - cx) * -g.dz[e] + (mz - cz) * g.dx[e]
		if side <= 0 then
			wrongSide += 1
		end
		if not onSomeRoad(mx, mz, 0) then
			offRoad += 1
		end
	end
	check("cars keep right", wrongSide == 0, wrongSide)
	check("lanes are on the asphalt", offRoad == 0, offRoad)
	local e = g.lanes[1]
	check("lane pieces are cached", TrafficLanes.lane(g, e) == TrafficLanes.lane(g, e))
end

-- Turns join the lanes without a jump, and nextEdge only picks allowed roads leaving the right junction.
do
	local jumps, wrongWay, disallowed = 0, 0, 0
	local rand = Map.lcg(11)
	for _, e in g.lanes do
		local nextE = TrafficLanes.nextEdge(g, e, rand())
		if nextE == nil then
			continue
		end
		if g.from[nextE] ~= g.to[e] then
			wrongWay += 1
		end
		if not g.allowed[nextE] then
			disallowed += 1
		end
		local turn = TrafficLanes.turn(g, e, nextE)
		local lin, lout = TrafficLanes.lane(g, e), TrafficLanes.lane(g, nextE)
		local x0, z0 = TrafficLanes.at(turn, 0)
		local x1, z1 = TrafficLanes.at(turn, turn.length)
		if math.abs(x0 - lin.px[2]) + math.abs(z0 - lin.pz[2]) > 0.01 or math.abs(x1 - lout.px[1]) + math.abs(z1 - lout.pz[1]) > 0.01 then
			jumps += 1
		end
	end
	check("turns start at the lane end and end at the next lane", jumps == 0, jumps)
	check("the next road leaves the junction the car reaches", wrongWay == 0, wrongWay)
	check("the next road is always allowed", disallowed == 0, disallowed)
end

-- A dead end turns around.
do
	local found = false
	for _, e in g.lanes do
		local others = 0
		for _, o in g.out[g.to[e]] do
			if o ~= g.reverse[e] and g.allowed[o] then
				others += 1
			end
		end
		if others == 0 then
			local nextE = TrafficLanes.nextEdge(g, e, 0.5)
			found = true
			check("a dead end makes a U-turn", nextE == g.reverse[e] and TrafficLanes.turn(g, e, g.reverse[e]).uturn)
			break
		end
	end
	check("the map has dead ends (the far places)", found)
end

-- Turning around in the middle of a lane (stuck behind a parked car) ends on the same spot the other way.
do
	local bad = 0
	for n = 1, #g.lanes, 7 do
		local e = g.lanes[n]
		local lane = TrafficLanes.lane(g, e)
		local s = lane.length * 0.4
		local piece = TrafficLanes.turnAround(g, e, s)
		local x0, z0 = TrafficLanes.at(piece, 0)
		local lx, lz = TrafficLanes.at(lane, s)
		local x1, z1, hx, hz = TrafficLanes.at(piece, piece.length)
		local back = TrafficLanes.lane(g, piece.edge)
		local bx, bz, bhx, bhz = TrafficLanes.at(back, piece.enter)
		if piece.edge ~= g.reverse[e] or math.abs(x0 - lx) + math.abs(z0 - lz) > 0.01 or math.abs(x1 - bx) + math.abs(z1 - bz) > 0.01 or hx * bhx + hz * bhz < 0.99 or not onSomeRoad(x1, z1, 0) then
			bad += 1
		end
	end
	check("turning around mid-road lands in the other lane", bad == 0, bad)
end

-- Cars driving at random for a long time stay on the roads, out of the winter, and keep moving.
do
	local rand = Map.lcg(5)
	local offRoad, winter, stuck = 0, 0, 0
	local maxStep = 0
	for car = 1, 12 do
		local e = g.lanes[math.floor(rand() * #g.lanes) + 1]
		local piece = TrafficLanes.lane(g, e)
		local s = 0
		local lastX, lastZ = TrafficLanes.at(piece, 0)
		for _ = 1, 4000 do
			s += 3.4 -- 34 studs/s at 10 Hz
			local guard = 0
			while s >= piece.length and guard < 8 do
				guard += 1
				s -= piece.length
				if piece.turn then
					piece = TrafficLanes.lane(g, piece.edge)
				else
					local nextE = TrafficLanes.nextEdge(g, piece.edge, rand())
					if not nextE then
						stuck += 1
						break
					end
					piece = TrafficLanes.turn(g, piece.edge, nextE)
				end
			end
			local x, z, hx, hz = TrafficLanes.at(piece, s)
			if not onSomeRoad(x, z, 12) then
				offRoad += 1
			end
			if not TrafficLanes.allowedAt(x, z + 12) then
				winter += 1
			end
			if math.abs(hx * hx + hz * hz - 1) > 0.01 then
				stuck += 1
			end
			maxStep = math.max(maxStep, math.sqrt((x - lastX) ^ 2 + (z - lastZ) ^ 2))
			lastX, lastZ = x, z
		end
		local _ = car
	end
	check("driving cars stay on the roads", offRoad == 0, offRoad)
	check("driving cars stay out of the winter", winter == 0, winter)
	check("driving cars always have a way and a heading", stuck == 0, stuck)
	check("driving cars never jump", maxStep < 6, maxStep)
end

-- Spawn spots are on a lane within the range.
do
	local rand = Map.lcg(3)
	local okAll = true
	local found = 0
	for _, p in { { 0, 0 }, { 400, -300 }, { 1200, 100 }, { 0, 1000 }, { -1100, 0 }, { 300, -1100 } } do
		for _ = 1, 10 do
			local e, s, x, z = TrafficLanes.spawnSpot(g, p[1], p[2], 120, 260, rand)
			if e then
				found += 1
				local d = math.sqrt((x - p[1]) ^ 2 + (z - p[2]) ^ 2)
				local lx, lz = TrafficLanes.at(TrafficLanes.lane(g, e), s)
				if d < 120 or d > 260 or not g.allowed[e] or math.abs(lx - x) + math.abs(lz - z) > 0.01 then
					okAll = false
				end
			end
		end
	end
	check("spawn spots are on lanes in range", okAll and found > 40, found)
	local none = TrafficLanes.spawnSpot(g, -600, -2600, 120, 260, rand)
	check("no spawn spot in the winter", none == nil)
end

-- Sidewalks: the corners are on the blocks (not the road, not a yard), crossings lead to the facing corner.
do
	local bad = 0
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				for k = 1, 4 do
					local x, z = TrafficLanes.corner(d, i, j, k)
					local block = Map.blockAt(x, z)
					if block ~= d or Map.onRoad(x, z) or Map.inYard(x, z) then
						bad += 1
					end
				end
			end
		end
	end
	check("sidewalk corners are on the blocks", bad == 0, bad)
	local d = Map.Districts[1]
	local k2, i2, j2 = TrafficLanes.across(d, 0, 0, 2, true) -- the NE corner, across to the east
	local ax, az = TrafficLanes.corner(d, 0, 0, 2)
	local bx, bz = 0, 0
	if k2 then
		bx, bz = TrafficLanes.corner(d, i2, j2, k2)
	end
	check("crossing goes straight over the street", k2 == 1 and i2 == 1 and j2 == 0 and math.abs(az - bz) < 1e-6 and math.abs(bx - ax - (Map.Cell - Map.BlockSize + 2 * TrafficLanes.SidewalkInset)) < 1e-6)
	check("no crossing out of the district", (TrafficLanes.across(d, d.i1, 0, 2, true)) == nil)
	check("the ring goes around", TrafficLanes.nextCorner(4, 1) == 1 and TrafficLanes.nextCorner(1, -1) == 4)
	local cx, cz = TrafficLanes.clampToBlock(d, 0, 0, 500, -3)
	check("fleeing stays on the block", cx == Map.BlockSize / 2 - TrafficLanes.SidewalkInset and cz == -3)
	local rand = Map.lcg(9)
	local spots = 0
	local okSpots = true
	for _ = 1, 30 do
		local spot = TrafficLanes.sidewalkSpot(100, 100, 70, 170, rand)
		if spot then
			spots += 1
			local dist = math.sqrt((spot.x - 100) ^ 2 + (spot.z - 100) ^ 2)
			if dist < 70 or dist > 170 or Map.blockAt(spot.x, spot.z) ~= spot.d then
				okSpots = false
			end
		end
	end
	check("sidewalk spots in range, on a block", okSpots and spots > 20, spots)
	check("no sidewalk far out of town", TrafficLanes.sidewalkSpot(-1880, 520, 70, 170, rand) == nil)
end

-- Fast: a car step is a lookup, a spawn spot well under a millisecond.
do
	local rand = Map.lcg(21)
	local t0 = os.clock()
	for _ = 1, 200 do
		TrafficLanes.spawnSpot(g, rand() * 1200 - 600, rand() * 1200 - 600, 120, 260, rand)
	end
	local each = (os.clock() - t0) / 200
	check(`a spawn spot takes under 1 ms ({math.floor(each * 1e6)} µs)`, each < 0.001)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
