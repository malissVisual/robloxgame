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
	local rand = Map.lcg(9)
	local spots = 0
	local okSpots = true
	for _ = 1, 30 do
		local spot = TrafficLanes.sidewalkSpot(100, 100, 70, 170, rand)
		if spot then
			spots += 1
			local dist = math.sqrt((spot.x - 100) ^ 2 + (spot.z - 100) ^ 2)
			local path = TrafficLanes.sidePath(spot.d, spot.i, spot.j, spot.side)
			local onLine = false
			if path then
				for m = 1, #path - 2, 2 do
					local seg = { ax = path[m], az = path[m + 1], bx = path[m + 2], bz = path[m + 3] }
					if toSegment(seg, spot.x, spot.z) < 1e-6 then
						onLine = true
					end
				end
			end
			if dist < 70 or dist > 170 or Map.blockAt(spot.x, spot.z) ~= spot.d or not onLine or spot.k ~= TrafficLanes.nextCorner(spot.side, 1) then
				okSpots = false
			end
		end
	end
	check("sidewalk spots in range, on a block, on its side's walk line", okSpots and spots > 20, spots)
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

-- ── 3.10: the walk lines (people stay on the sidewalk) ────────────────────

do
	TrafficLanes.forgetSurveys()
	local body = TrafficLanes.Body
	local inset = TrafficLanes.SidewalkInset
	local half = Map.RoadWidth / 2

	-- What stands on the city's sidewalks that the shared modules know: the street lamps (server/World.luau: on a
	-- corner of every junction, ROAD / 2 + 2 in from both curbs), the light poles (Crossings.PoleCorner, or nearer the
	-- tip of the corner when that is taken), the towers and the buildings of the homes and garages on the blocks.
	type Post = { x: number, z: number, r: number }
	type Box = { x0: number, z0: number, x1: number, z1: number, id: string }
	local posts: { Post } = {}
	for _, d in Map.Districts do
		for kx = d.i0 - 1, d.i1 do
			for kz = d.j0 - 1, d.j1 do
				table.insert(posts, { x = d.ox + (kx + 0.5) * Map.Cell + half + 2, z = d.oz + (kz + 0.5) * Map.Cell + half + 2, r = 0.3 })
			end
		end
	end
	for _, j in Crossings.junctions() do
		for _, c in { Crossings.PoleCorner, half + 0.6 } do
			table.insert(posts, { x = j.x + c, z = j.z - c, r = 0.25 })
			table.insert(posts, { x = j.x - c, z = j.z + c, r = 0.25 })
		end
	end
	local boxes: { Box } = {}
	for id, tower in Map.Towers do
		local w = tower.w / 2
		table.insert(boxes, { x0 = tower.x - w, z0 = tower.z - w, x1 = tower.x + w, z1 = tower.z + w, id = id })
	end
	for id, plot in Map.EstatePlots do
		if not plot.tower and Map.blockAt(plot.x, plot.z) then
			local ax, az = Map.plotPoint(plot, -plot.w / 2, -plot.front)
			local bx, bz = Map.plotPoint(plot, plot.w / 2, plot.back)
			table.insert(boxes, { x0 = math.min(ax, bx), z0 = math.min(az, bz), x1 = math.max(ax, bx), z1 = math.max(az, bz), id = id })
		end
	end
	check("the footprints to keep clear of are there", #posts > 400 and #boxes >= 5, `{#posts} posts, {#boxes} buildings`)

	-- The posts and buildings near a block (the checks below only look at those).
	local nearPosts: { Post } = {}
	local nearBoxes: { Box } = {}
	local function around(cx: number, cz: number)
		table.clear(nearPosts)
		table.clear(nearBoxes)
		local reach = Map.Cell
		for _, p in posts do
			if math.abs(p.x - cx) < reach and math.abs(p.z - cz) < reach then
				table.insert(nearPosts, p)
			end
		end
		for _, b in boxes do
			if b.x1 > cx - reach and b.x0 < cx + reach and b.z1 > cz - reach and b.z0 < cz + reach then
				table.insert(nearBoxes, b)
			end
		end
	end
	-- How close a point comes to them (a post by its edge).
	local function clearance(x: number, z: number): (number, string)
		local best, what = math.huge, ""
		for _, p in nearPosts do
			local d = math.sqrt((p.x - x) ^ 2 + (p.z - z) ^ 2) - p.r
			if d < best then
				best, what = d, `a pole at {p.x}, {p.z}`
			end
		end
		for _, b in nearBoxes do
			local dx = math.max(b.x0 - x, 0, x - b.x1)
			local dz = math.max(b.z0 - z, 0, z - b.z1)
			local d = math.sqrt(dx * dx + dz * dz)
			if d < best then
				best, what = d, b.id
			end
		end
		return best, what
	end
	local function lineClearance(ax: number, az: number, bx: number, bz: number): (number, string)
		local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local steps = math.max(1, math.ceil(length / 0.5))
		local best, what = math.huge, ""
		for n = 0, steps do
			local t = n / steps
			local d, w = clearance(ax + (bx - ax) * t, az + (bz - az) * t)
			if d < best then
				best, what = d, w
			end
		end
		return best, what
	end
	-- Somebody standing at (x, z): clear of the lamps and poles (first), and of the buildings (second: false when a
	-- building is there, which the probe in the game finds; then no group stands there).
	local function standClear(x: number, z: number, r: number): (boolean, boolean)
		for _, p in nearPosts do
			if math.sqrt((p.x - x) ^ 2 + (p.z - z) ^ 2) - p.r < r then
				return false, false
			end
		end
		for _, b in nearBoxes do
			local dx = math.max(b.x0 - x, 0, x - b.x1)
			local dz = math.max(b.z0 - z, 0, z - b.z1)
			if math.sqrt(dx * dx + dz * dz) < r then
				return true, false
			end
		end
		return true, true
	end
	-- How far in from the curb of side s a point is.
	local function depthOf(d: Map.District, i: number, j: number, s: number, x: number, z: number): number
		local nx, nz = TrafficLanes.inward(s)
		local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
		return Map.BlockSize / 2 + (x - cx) * nx + (z - cz) * nz
	end

	-- The ring's geometry: the side toward a corner ends there, `inward` points to the block's middle.
	local geometryOk = true
	for k = 1, 4 do
		for _, dir in { 1, -1 } do
			local s = TrafficLanes.sideOf(k, dir)
			if (dir == 1 and TrafficLanes.nextCorner(s, 1) ~= k) or (dir == -1 and s ~= k) then
				geometryOk = false
			end
		end
		local d = Map.Districts[1]
		local ax, az = TrafficLanes.corner(d, 0, 0, k)
		local bx, bz = TrafficLanes.corner(d, 0, 0, k + 1)
		local nx, nz, tx, tz = TrafficLanes.inward(k)
		local mx, mz = (ax + bx) / 2, (az + bz) / 2
		local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		if (mx + nx) ^ 2 + (mz + nz) ^ 2 >= mx * mx + mz * mz or math.abs((bx - ax) / length - tx) > 1e-9 or math.abs((bz - az) / length - tz) > 1e-9 then
			geometryOk = false
		end
		if math.abs(depthOf(d, 0, 0, k, mx, mz) - inset) > 1e-9 then
			geometryOk = false
		end
	end
	check("sides, corners and the way in agree", geometryOk)

	-- Every walk line, every corner, every crossing and every curb spot keeps a person's width off the lamps, the
	-- light poles and the buildings Map knows; every spot where people stand still stays off the walk lines (the
	-- walkers pass them by) and inside the strip an ordinary block keeps free (Frontage).
	local badLine, badCross, badCurb, badStand, worst, worstWhat = 0, 0, 0, 0, math.huge, ""
	local byHomes, homeBlocks = 0, {} :: { [string]: boolean }
	local standing = 1 -- half the width of somebody standing
	local inner, outer = inset + standing - 1e-6, TrafficLanes.Frontage + 1e-6 -- (a walker on the line: standing wide too)
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				around(d.ox + i * Map.Cell, d.oz + j * Map.Cell)
				for s = 1, 4 do
					local path = TrafficLanes.sidePath(d, i, j, s)
					if not path then
						badLine += 1
						continue
					end
					for m = 1, #path - 2, 2 do
						local c, what = lineClearance(path[m], path[m + 1], path[m + 2], path[m + 3])
						if c < worst then
							worst, worstWhat = c, `{d.id} {i},{j} side {s}: {what}`
						end
						if c < body then
							badLine += 1
						end
					end
					for _, alongX in { true, false } do
						local k2, i2, j2 = TrafficLanes.across(d, i, j, s, alongX)
						local ax, az = TrafficLanes.corner(d, i, j, s)
						local cx, cz = TrafficLanes.curbSpot(d, i, j, s, alongX)
						if k2 then
							local bx, bz = TrafficLanes.corner(d, i2, j2, k2)
							if lineClearance(ax, az, bx, bz) < body then
								badCross += 1
							end
							-- the curb spot: on the crossing's line, between the corner and the street
							local t = ((cx - ax) * (bx - ax) + (cz - az) * (bz - az)) / ((bx - ax) ^ 2 + (bz - az) ^ 2)
							local off = math.abs((cx - ax) * (bz - az) - (cz - az) * (bx - ax)) / math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
							if t <= 0 or t >= 0.2 or off > 1e-6 then
								badCurb += 1
							end
						end
						if clearance(cx, cz) < standing or Map.blockAt(cx, cz) ~= d or Map.onRoad(cx, cz) then
							badCurb += 1
						end
					end
					-- A group along the side (an oval) and two who stop for a word, anywhere along it.
					local ra, rc = TrafficLanes.GroupRadius.along, TrafficLanes.GroupRadius.across
					local nx, nz, tx, tz = TrafficLanes.inward(s)
					for f = 0.15, 0.851, 0.05 do
						local gx, gz = TrafficLanes.sideSpot(d, i, j, s, f, TrafficLanes.GroupDepth)
						for a = 0, 11 do
							local angle = a * math.pi / 6
							local px = gx + tx * math.cos(angle) * ra + nx * math.sin(angle) * rc
							local pz = gz + tz * math.cos(angle) * ra + nz * math.sin(angle) * rc
							local dp = depthOf(d, i, j, s, px, pz)
							local poles, buildings = standClear(px, pz, standing)
							if dp - standing < inner or dp + standing > outer or not poles then
								badStand += 1
							elseif not buildings then
								byHomes += 1
								homeBlocks[`{d.id} {i},{j}`] = true
							end
						end
						local mx, mz = TrafficLanes.sideSpot(d, i, j, s, f, TrafficLanes.MeetDepth)
						for _, side in { 1.3, -1.3 } do
							local px, pz = mx + tx * side, mz + tz * side
							local dp = depthOf(d, i, j, s, px, pz)
							local poles, buildings = standClear(px, pz, standing)
							if dp - standing < inner or dp + standing > outer or not poles then
								badStand += 1
							elseif not buildings then
								byHomes += 1
								homeBlocks[`{d.id} {i},{j}`] = true
							end
						end
					end
					-- A group on the corner: off both walk lines.
					local gx, gz = TrafficLanes.cornerSpot(d, i, j, s, TrafficLanes.CornerGroupDepth)
					for a = 0, 11 do
						local angle = a * math.pi / 6
						local px, pz = gx + math.cos(angle) * 1.6, gz + math.sin(angle) * 1.6
						for _, side in { s, TrafficLanes.nextCorner(s, -1) } do
							if depthOf(d, i, j, side, px, pz) - standing < inner then
								badStand += 1
							end
						end
						local poles, buildings = standClear(px, pz, standing)
						if not poles or not buildings then
							badStand += 1
						end
					end
				end
			end
		end
	end
	check("every walk line keeps a person's width off the lamps, light poles and buildings", badLine == 0, `{badLine}; closest {math.floor(worst * 100) / 100} studs: {worstWhat}`)
	check("the walk lines pass the lamps and light poles with room to spare", worst >= body + 0.3, worst)
	check("every crossing line too", badCross == 0, badCross)
	check("people wait to cross on the crossing's line, a step toward the street, on the block", badCurb == 0, badCurb)
	check("groups and people talking stand off the walk lines, inside the free strip, clear of the poles", badStand == 0, badStand)
	-- A home on a Suburbs lot reaches 8 studs from the curb on its lot's side: there the probe in the game finds its
	-- wall and no group stands (nothing else in Map comes that close).
	local blocks, elsewhere = 0, 0
	for key in homeBlocks do
		blocks += 1
		if string.sub(key, 1, 8) ~= "suburbs " then
			elsewhere += 1
		end
	end
	check("only the Suburbs homes come near a standing spot (the probe keeps groups off them)", elsewhere == 0 and blocks <= 4, `{byHomes} spots on {blocks} blocks`)

	-- A survey with something on a line: a flag pole on the north side's line of an ordinary block, a wall across
	-- the whole sidewalk of its south side.
	local d = Map.Districts[1]
	local bi, bj = 3, -3
	local cx, cz = d.ox + bi * Map.Cell, d.oz + bj * Map.Cell
	local pole = { x = cx, z = cz - (Map.BlockSize / 2 - inset), r = 0.3 }
	local wall = { x0 = cx - 1, z0 = cz + Map.BlockSize / 2 - 14, x1 = cx + 1, z1 = cz + Map.BlockSize / 2 }
	local function free(ax: number, az: number, bx: number, bz: number): boolean
		local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local steps = math.max(1, math.ceil(length / 0.25))
		for n = 0, steps do
			local x, z = ax + (bx - ax) * n / steps, az + (bz - az) * n / steps
			if math.sqrt((x - pole.x) ^ 2 + (z - pole.z) ^ 2) - pole.r < body then
				return false
			end
			local dx = math.max(wall.x0 - x, 0, x - wall.x1)
			local dz = math.max(wall.z0 - z, 0, z - wall.z1)
			if math.sqrt(dx * dx + dz * dz) < body then
				return false
			end
		end
		return true
	end
	local open = TrafficLanes.survey(d, bi, bj, free)
	local north, east, south, west = TrafficLanes.sideInset(d, bi, bj, 1), TrafficLanes.sideInset(d, bi, bj, 2), TrafficLanes.sideInset(d, bi, bj, 3), TrafficLanes.sideInset(d, bi, bj, 4)
	check("a survey: the blocked side takes a detour, the walled one is closed, the others stay", open == 3 and north ~= nil and north ~= inset and east == inset and south == nil and west == inset, `{open} open: {north} {east} {south} {west}`)
	local northPath = TrafficLanes.sidePath(d, bi, bj, 1)
	local detourOk = northPath ~= nil and #northPath == 8
	if northPath then
		for m = 1, #northPath - 2, 2 do
			if not free(northPath[m], northPath[m + 1], northPath[m + 2], northPath[m + 3]) then
				detourOk = false
			end
		end
	end
	check("the detour goes round the pole, from corner to corner", detourOk)
	-- Routes along the detour: from the corner, from its middle, both ways; a step back onto the line first when off it.
	local c1x, c1z = TrafficLanes.corner(d, bi, bj, 1)
	local c2x, c2z = TrafficLanes.corner(d, bi, bj, 2)
	local fromCorner = TrafficLanes.route(d, bi, bj, 2, 1, c1x, c1z)
	local mx, mz = TrafficLanes.sideSpot(d, bi, bj, 1, 0.5, north or 0)
	local east1 = TrafficLanes.route(d, bi, bj, 2, 1, mx, mz)
	local west1 = TrafficLanes.route(d, bi, bj, 1, -1, mx, mz)
	local ends = function(r: { number }?, x: number, z: number): boolean
		return r ~= nil and #r >= 2 and math.abs(r[#r - 1] - x) < 1e-6 and math.abs(r[#r] - z) < 1e-6
	end
	check("a route from the corner follows the whole detour", fromCorner ~= nil and #fromCorner == 6 and ends(fromCorner, c2x, c2z), if fromCorner then #fromCorner else "nil")
	check("a route from the middle goes on to the corner it heads for", east1 ~= nil and #east1 == 4 and ends(east1, c2x, c2z) and west1 ~= nil and #west1 == 4 and ends(west1, c1x, c1z))
	local ox, oz = TrafficLanes.sideSpot(d, bi, bj, 2, 0.5, inset + 4) -- pushed 4 studs in off the east side's line
	local back = TrafficLanes.route(d, bi, bj, 3, 1, ox, oz)
	local bx, bz = TrafficLanes.sideSpot(d, bi, bj, 2, 0.5, inset)
	check("off the line: a step back onto it, then on to the corner", back ~= nil and #back == 4 and math.abs(back[1] - bx) < 1e-6 and math.abs(back[2] - bz) < 1e-6 and ends(back, TrafficLanes.corner(d, bi, bj, 3)))
	local onLine = TrafficLanes.route(d, bi, bj, 3, 1, bx, bz)
	check("on the line: straight on", onLine ~= nil and #onLine == 2)
	check("no route along a closed side", TrafficLanes.route(d, bi, bj, 4, 1, cx, cz + 50) == nil and TrafficLanes.route(d, bi, bj, 3, -1, cx, cz + 50) == nil)
	local s3 = TrafficLanes.nearestSide(d, bi, bj, cx, cz + 60)
	check("the nearest side is never a closed one", s3 ~= nil and s3 ~= 3, s3)
	local onClosed = 0
	local rand = Map.lcg(77)
	for _ = 1, 400 do
		local spot = TrafficLanes.sidewalkSpot(cx, cz, 0, 60, rand)
		if spot and spot.d == d and spot.i == bi and spot.j == bj and spot.side == 3 then
			onClosed += 1
		end
	end
	check("nobody spawns on a closed side", onClosed == 0, onClosed)
	TrafficLanes.forgetSurveys()
	check("forgotten: the straight lines again", TrafficLanes.sideInset(d, bi, bj, 3) == inset)
	local everywhere = TrafficLanes.survey(d, bi, bj, function()
		return true
	end)
	check("a clear block keeps its four straight lines", everywhere == 4 and #(TrafficLanes.sidePath(d, bi, bj, 1) or {}) == 4)
	TrafficLanes.forgetSurveys()
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
