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

-- ── 3.9: crosswalks and traffic lights (shared/Crossings.luau) ─────────────

local Config = require("./Config")
local Crossings = require("./Crossings")
local T = Config.Traffic

-- The light cycle: one axis at a time, amber after green, an all-red moment between them, the same every cycle.
do
	local cycle = Crossings.cycle()
	check("the cycle is green + amber + all red, twice", cycle == 2 * (T.LightGreen + T.LightAmber + T.LightAllRed), cycle)
	local s1 = Crossings.state(0, 0, 1)
	local s2 = Crossings.state(0, 0, 2)
	local a1 = Crossings.state(T.LightGreen + 0.5, 0, 1)
	local r1 = Crossings.state(T.LightGreen + T.LightAmber + 0.5, 0, 1)
	local g2 = Crossings.state(cycle / 2 + 0.5, 0, 2)
	check("axis 1 starts green while axis 2 is red", s1 == "green" and s2 == "red", `{s1} {s2}`)
	check("then amber, then red", a1 == "amber" and r1 == "red", `{a1} {r1}`)
	check("axis 2 is green in the second half", g2 == "green", g2)
	local conflict, allRed, walkWindow, walkWrong, badLeft = 0, 0, 0, 0, 0
	local greenTime = { 0, 0 }
	local step = 0.05
	for _, offset in { 0, 4, 13.5, cycle - 1 } do
		local t = 1000
		while t < 1000 + cycle do
			local a, leftA = Crossings.state(t, offset, 1)
			local b, leftB = Crossings.state(t, offset, 2)
			if a ~= "red" and b ~= "red" then
				conflict += 1
			end
			if a == "red" and b == "red" then
				allRed += step
			end
			if a == "green" then
				greenTime[1] += step
			end
			if b == "green" then
				greenTime[2] += step
			end
			-- The state lasts exactly as long as it says.
			local later = Crossings.state(t + leftA - 0.01, offset, 1)
			if later ~= a or leftA <= 0 or leftB <= 0 then
				badLeft += 1
			end
			-- Somebody may walk over the road along X only while its traffic (axis 1) is red long enough.
			if Crossings.walk(t, offset, true) then
				walkWindow += step
				if a ~= "red" or Crossings.state(t + T.CrossTime - 0.01, offset, 1) ~= "red" then
					walkWrong += 1
				end
			end
			t += step
		end
	end
	check("never green or amber both ways at once", conflict == 0, conflict)
	check("an all-red moment between the axes", math.abs(allRed / 4 - 2 * T.LightAllRed) < 0.2, allRed / 4)
	check("both axes get their green", math.abs(greenTime[1] / 4 - T.LightGreen) < 0.2 and math.abs(greenTime[2] / 4 - T.LightGreen) < 0.2, `{greenTime[1] / 4} {greenTime[2] / 4}`)
	check("a state lasts as long as it says", badLeft == 0, badLeft)
	check("people walk only on red for the traffic, with time to get over", walkWrong == 0, walkWrong)
	check("a walk window every cycle", walkWindow / 4 >= cycle / 2 - T.LightGreen - T.CrossTime, walkWindow / 4)
	check("the cycle repeats", Crossings.state(7, 3, 2) == Crossings.state(7 + cycle * 5, 3, 2))
end

-- The junctions with lights: the four-way crossings inside the districts, each one node of the lane graph.
do
	local junctions = Crossings.junctions()
	local expected = 0
	for _, d in Map.Districts do
		expected += (d.i1 - d.i0) * (d.j1 - d.j0)
	end
	check(`traffic lights at every four-way junction inside the districts ({#junctions})`, #junctions == expected and expected >= 80, expected)
	local lights = Crossings.nodeLights(g)
	local mapped = 0
	for _ in lights do
		mapped += 1
	end
	check("every light junction is a four-way node of the lane graph", mapped == #junctions, mapped)
	local offRoad, offsets = 0, {}
	for index, j in junctions do
		if not Map.onRoad(j.x, j.z) or Crossings.junctionAt(j.x, j.z) ~= index or j.offset < 0 or j.offset >= Crossings.cycle() then
			offRoad += 1
		end
		offsets[j.offset] = true
	end
	local kinds = 0
	for _ in offsets do
		kinds += 1
	end
	check("junctions on the roads, found by position, offsets in the cycle", offRoad == 0, offRoad)
	check("not every light switches at once", kinds >= 4, kinds)
	-- Every lane into a light junction stops before the crosswalk.
	local tooClose = 0
	for n, _ in lights do
		for _, e in g.out[n] do
			local inbound = g.reverse[e]
			local piece = TrafficLanes.lane(g, inbound)
			local ex, ez = TrafficLanes.at(piece, piece.length - T.StopBack)
			local d = math.max(math.abs(ex - g.x[n]), math.abs(ez - g.z[n]))
			if d < Crossings.Distance + Crossings.Width / 2 or piece.length < T.StopBack + 20 then
				tooClose += 1
			end
		end
	end
	check("the stop lines are before the crosswalks", tooClose == 0, tooClose)
	-- The poles stand on the block corners, off the road and off the people's path.
	local badPole = 0
	for _, j in junctions do
		for _, side in { 1, -1 } do
			local px, pz = j.x + side * Crossings.PoleCorner, j.z - side * Crossings.PoleCorner
			local ring = Crossings.Distance
			if Map.blockAt(px, pz) == nil or Map.onRoad(px, pz) or math.abs(math.abs(px - j.x) - ring) < 2 or math.abs(math.abs(pz - j.z) - ring) < 2 then
				badPole += 1
			end
		end
	end
	check("light poles on the block corners, clear of the walkers", badPole == 0, badPole)
end

-- The crosswalks: on the road next to a junction, just outside its box, where every pedestrian crossing goes over.
do
	local list = Crossings.crosswalks()
	local bad, inBox, wrongLight, onSpot = 0, 0, 0, 0
	local half = Map.RoadWidth / 2
	for _, c in list do
		-- across the whole road, on the asphalt at both curbs
		local ax, az = if c.alongX then c.x else c.x - half + 1, if c.alongX then c.z - half + 1 else c.z
		local bx, bz = if c.alongX then c.x else c.x + half - 1, if c.alongX then c.z + half - 1 else c.z
		if not Map.onRoad(c.x, c.z) or not Map.onRoad(ax, az) or not Map.onRoad(bx, bz) then
			bad += 1
		end
		-- next to its junction, along its road, outside the junction box
		local along = if c.alongX then math.abs(c.x - c.jx) else math.abs(c.z - c.jz)
		local beside = if c.alongX then math.abs(c.z - c.jz) else math.abs(c.x - c.jx)
		if math.abs(along - Crossings.Distance) > 1e-6 or beside > 1e-6 then
			bad += 1
		end
		if along - Crossings.Width / 2 <= half then
			inBox += 1
		end
		if c.light ~= (Crossings.junctionAt(c.jx, c.jz) or 0) then
			wrongLight += 1
		end
		for _, spot in Map.CargoSpots do
			for _, p in { spot.park, spot.pile } do
				if math.abs(p.x - c.x) < half and math.abs(p.z - c.z) < half then
					onSpot += 1
				end
			end
		end
	end
	check(`crosswalks over the whole road, next to a junction ({#list})`, bad == 0 and #list > 300, bad)
	check("crosswalks outside the junction box", inBox == 0, inBox)
	check("a crosswalk at a light junction has its light", wrongLight == 0, wrongLight)
	check("no crosswalk on a cargo spot", onSpot == 0, onSpot)
	local lit = 0
	for _, c in list do
		if c.light > 0 then
			lit += 1
		end
	end
	check("most crosswalks have lights", lit > #list / 2, lit)
	-- the stripes stay on the road, clear of the centre line
	local stripesOk = true
	for _, x in Crossings.Stripes do
		if math.abs(x) + Crossings.StripeWidth / 2 > half - 1 or math.abs(x) - Crossings.StripeWidth / 2 < 0.4 then
			stripesOk = false
		end
	end
	check("the stripes are on the road, off the centre line", stripesOk)
	-- every crossing from a corner over the street goes over a crosswalk (bar the few by a cargo spot)
	local crossings, missing = 0, 0
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				for k = 1, 4 do
					for _, alongX in { true, false } do
						local k2, i2, j2 = TrafficLanes.across(d, i, j, k, alongX)
						if k2 then
							crossings += 1
							local ax, az = TrafficLanes.corner(d, i, j, k)
							local bx, bz = TrafficLanes.corner(d, i2, j2, k2)
							local c = Crossings.at((ax + bx) / 2, (az + bz) / 2)
							if not c or c.alongX ~= (math.abs(bz - az) > math.abs(bx - ax)) then
								missing += 1
							end
						end
					end
				end
			end
		end
	end
	check(`every street crossing has its crosswalk ({crossings} crossings)`, missing <= 8 and crossings == 2 * #list + 2 * missing, `{missing} missing`)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
