--!strict
-- 5.5, the city buses' lines and timetable (Config.Bus), as plain numbers: pure Luau (no Roblox types), so
-- tests/buslines_test.luau runs it outside Roblox, and the server (server/Buses.luau, server/BusStops.luau) and every
-- client (client/BusRide.luau) work out the very same buses from the same clock.
--
-- A line is a closed loop through the corners Config.Bus.Lines gives (road-centre points of Map's grid), driven
-- clockwise on the traffic's right-hand lanes (shared/TrafficLanes.luau): the lane pieces between the junctions and
-- the Bézier turns over them, straight on wherever a corner is not. Its stops come along the loop, one at least
-- StopGap after the one before (6.3: about every 4 blocks, see below), each in the middle of a block's lane where the
-- bus pulls in to the kerb (Map.CurbPark out on the road) with its front-right door by the shelter. Never on a special
-- block's side (the depot, the shops, the places have their own fronts), never by a lot that drives over the sidewalk
-- (a gas station, a house for sale, a storefront) and never within StopClear of a home's door, pile or park, a cargo
-- spot, a place or an employer's board; a blocked middle tries a little up or down the block. Two lines on the same lane
-- of the same block share the stop. A stop is named after its street and the nearer cross street ("Cedar St /
-- 6th Ave"; the streets between Downtown and the Suburbs take the nearer district's name).
--
-- The timetable. A bus drives Speed on the straights, TurnSpeed through a corner (Approach studs before and after it
-- at the speed between), speeds up from a stop and slows into the next over Ramp seconds and stands Dwell seconds at
-- every stop. One loop (its period) starts at the line's first stop; its `buses` drive it evenly spaced (headway =
-- period / buses), so bus b is where bus 0 was b × headway ago. Everything is a function of the server's clock
-- (workspace:GetServerTimeNow()): BusLines.position(line, bus, now), nextArrival(line, stop, now). A bus never stops
-- for a red light or the traffic (the timetable stays the same everywhere): the traffic gives way to it instead
-- (server/Traffic.luau) and it passes through people (no collisions: server/Buses.luau).
--
-- route(from, to): the best ride from here to there (the line, the stop to board and to leave, the stops ridden,
-- the walks), or nil when walking (Config.Movement.Walk) is as quick within RouteSaving seconds.
--
-- 6.3, express lines: a stop about every 4 blocks (StopGap) and at the key places. Every block's lane of the loop with
-- a clear kerb is a candidate, scored by the key places near its kerb (Map.Landmarks: the depot and the shops most,
-- the places and the employers, the storefronts a little; the districts' middles; KeyReach). The line's best lane is
-- its first stop; then round the loop each next stop is the best-scored lane from StopGap to StopGap + PickWindow
-- after the one before (the first lane past that when the window has none), the last at least LastGap before the
-- first. A stop within NameReach of a key place is named after it ("City Clinic", the depot "Depot"; each place names
-- one stop), else after its street as before. BusLines.mapLines gives the loops as short polylines for the maps.

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local TrafficLanes = require(script.Parent.TrafficLanes)

local BusLines = {}

local Tuning = Config.Bus

export type Stop = {
	id: number, -- in BusLines.allStops()
	name: string, -- "Cedar St / 6th Ave"
	street: string, -- the street the bus stands on
	x: number, -- where the bus stands (its middle), pulled in to the kerb
	z: number,
	hx: number, -- the way it faces there (unit)
	hz: number,
	kx: number, -- the kerb by the bus's door: the shelter stands here, you wait and get off here
	kz: number,
	nx: number, -- from the road toward the sidewalk (unit)
	nz: number,
	lines: { number }, -- the line ids that stop here
	landmark: string?, -- 6.3: the Map.Landmarks id it is named after (nil: named after its street)
}

type Segment = {
	piece: TrafficLanes.Piece,
	s0: number, -- along the piece
	s1: number,
	v: number, -- studs / s
	arc: number, -- along the loop at s0
	cruise: number, -- cruise seconds along the loop at s0 (no stops, no ramps)
}

export type Line = {
	id: number,
	name: string,
	short: string,
	color: { number },
	buses: number,
	length: number, -- studs round the loop
	segments: { Segment },
	cruiseTotal: number,
	stops: { Stop }, -- in the order the bus comes to them
	stopArc: { number }, -- along the loop
	stopCruise: { number },
	arrive: { number }, -- seconds into the loop it stands at each stop (the loop starts at stop 1: arrive[1] = 0)
	depart: { number },
	ramp: { number }, -- the ramp of the leg from each stop to the next
	legCruise: { number },
	period: number, -- seconds round the loop
	headway: number, -- seconds between two buses
}

export type Route = {
	line: Line,
	board: number, -- the stop's index in line.stops
	leave: number,
	boardStop: Stop,
	leaveStop: Stop,
	stops: number, -- stops ridden (the one you get off at counts)
	walkTo: number, -- studs (manhattan) to the board stop's kerb
	walkFrom: number,
	ride: number, -- seconds on the bus
	time: number, -- seconds in all (walks, the average wait, the ride)
	walkTime: number, -- seconds on foot all the way instead
}

local EPS = 1e-6

-- ── Names ──────────────────────────────────────────────────────────────────

-- The grid road through (x, z) running along X (alongX) or Z, by the district whose grid it belongs to (the nearest
-- one: a street between two districts takes the nearer one's name).
local function roadName(x: number, z: number, alongX: boolean): string?
	local best: string? = nil
	local bestD = math.huge
	for _, d in Map.Districts do
		local x0, x1, z0, z1 = Map.districtEdges(d)
		local names = if alongX then d.streets else d.avenues
		local lo = if alongX then d.j0 else d.i0
		local hi = if alongX then d.j1 else d.i1
		local origin = if alongX then d.oz else d.ox
		local across = if alongX then z else x
		for k = lo - 1, hi do
			if math.abs(origin + (k + 0.5) * Map.Cell - across) < 1 then
				-- How far the point is beyond the district's ends along the road (0: inside).
				local along = if alongX then x else z
				local a0, a1 = if alongX then x0 else z0, if alongX then x1 else z1
				local off = math.max(a0 - along, along - a1, 0)
				if off < bestD then
					bestD = off
					best = names[(k - lo + 1) % #names + 1]
				end
			end
		end
	end
	return best
end

-- 6.3, the key places the stops are drawn to and named after: the landmarks in town (Map.Landmarks; the depot, the
-- shops, the places and the employers weigh more than a storefront or a garage for sale) and the districts' middles
-- (they draw stops, they name none).
type KeyPlace = { id: string?, name: string?, x: number, z: number, weight: number }
local keyPlaces: { KeyPlace }? = nil

local function keys(): { KeyPlace }
	if keyPlaces then
		return keyPlaces
	end
	local list: { KeyPlace } = {}
	for _, landmark in Map.Landmarks do
		-- 6.11: the depot moved from the middle block to Map.Depot (the park is there now): it and its bag kiosk still
		-- draw from the middle of the safe zone, where they stood, and the park draws nothing of its own, so every line
		-- keeps its stops (the depot's own block and the blocks round it are special: no stop by them anyway)
		if landmark.id == Map.Park.id then
			continue
		end
		local yard = landmark.id == "depot" or landmark.id == "bags"
		local weight = if landmark.id == "depot" then 4
			elseif landmark.kind == "shop" then 3
			elseif landmark.kind == "venue" or string.sub(landmark.id, 1, 7) == "garage_" then 1
			else 2
		local name = if landmark.id == "depot" then "Depot" else landmark.name
		local x = if yard then landmark.x - Map.Depot.x + Map.Park.x else landmark.x
		local z = if yard then landmark.z - Map.Depot.z + Map.Park.z else landmark.z
		table.insert(list, { id = landmark.id, name = name, x = x, z = z, weight = weight })
	end
	for _, d in Map.Districts do
		table.insert(list, { id = nil, name = nil, x = d.ox + (d.i0 + d.i1) / 2 * Map.Cell, z = d.oz + (d.j0 + d.j1) / 2 * Map.Cell, weight = 1 })
	end
	keyPlaces = list
	return list
end

-- How much the key places draw a stop whose kerb is at (x, z).
local function keyScore(x: number, z: number): number
	local reach = Tuning.KeyReach
	local score = 0
	for _, place in keys() do
		local d = math.sqrt((place.x - x) ^ 2 + (place.z - z) ^ 2)
		if d < reach then
			score += place.weight * (1 - d / reach)
		end
	end
	return score
end

-- The key place a stop at (x, z) is named after: the weightiest within NameReach that names no stop yet (the nearer
-- of two as weighty), nil for none.
local named: { [string]: boolean } = {}
local function keyName(x: number, z: number): KeyPlace?
	local best: KeyPlace? = nil
	local bestD = math.huge
	for _, place in keys() do
		local id = place.id
		if not id or not place.name or named[id] then
			continue
		end
		local d = math.sqrt((place.x - x) ^ 2 + (place.z - z) ^ 2)
		if d <= Tuning.NameReach and (not best or place.weight > best.weight or (place.weight == best.weight and d < bestD)) then
			best, bestD = place, d
		end
	end
	return best
end

-- ── Building the lines ─────────────────────────────────────────────────────

local function nodeAt(g: TrafficLanes.Graph, x: number, z: number): number?
	for n = 1, #g.x do
		if math.abs(g.x[n] - x) < 1 and math.abs(g.z[n] - z) < 1 then
			return n
		end
	end
	return nil
end

-- The directed edges from corner a to corner b (a straight road between them), nil when there is none.
local function legEdges(g: TrafficLanes.Graph, ax: number, az: number, bx: number, bz: number): { number }?
	local node = nodeAt(g, ax, az)
	local goal = nodeAt(g, bx, bz)
	if not node or not goal then
		return nil
	end
	local dx, dz = bx - ax, bz - az
	local length = math.sqrt(dx * dx + dz * dz)
	dx, dz = dx / length, dz / length
	local list: { number } = {}
	local guard = 0
	while node ~= goal and guard < 200 do
		guard += 1
		local found: number? = nil
		for _, e in g.out[node :: number] do
			if g.dx[e] * dx + g.dz[e] * dz > 0.999 then
				found = e
				break
			end
		end
		if not found then
			return nil
		end
		table.insert(list, found)
		node = g.to[found]
	end
	return if node == goal then list else nil
end

-- Is the kerb here clear for a shelter (and the bus's door)?
local function kerbClear(kx: number, kz: number, nx: number, nz: number): boolean
	local clear2 = Tuning.StopClear * Tuning.StopClear
	local function near(p: { x: number, z: number }): boolean
		return (p.x - kx) ^ 2 + (p.z - kz) ^ 2 < clear2
	end
	if not Map.onRoad(kx - nx * 2.5, kz - nz * 2.5) then
		return false -- (not at a road's edge)
	end
	-- The block behind the kerb: an ordinary one, and its lot there neither a gas station, a house for sale nor a
	-- storefront.
	local d, i, j = Map.blockAt(kx + nx * 3, kz + nz * 3)
	if d then
		if Map.special(d.id, i, j) then
			return false
		end
		for _, lot in Map.lotsAt(d.id, i, j) do
			local half = lot.size / 2 + 12
			if math.abs(lot.x - kx) < half and math.abs(lot.z - kz) < half and (lot.kind == "gas" or lot.kind == "estate" or lot.kind == "venue") then
				return false
			end
		end
	end
	for _, home in Map.Homes do
		if near(home.door) or near(home.pile) or near(home.park) then
			return false
		end
	end
	for _, venue in Map.Venues do
		if near(venue.door) or near(venue.pile) or near(venue.park) then
			return false
		end
	end
	for _, spot in Map.CargoSpots do
		if near(spot.park) or near(spot.pile) then
			return false
		end
	end
	for _, spot in Map.EmployerSpots do
		if near(spot) then
			return false
		end
	end
	for _, place in Map.Places do
		if near(place) then
			return false
		end
	end
	for _, station in Map.GasStations do
		if (station.x - kx) ^ 2 + (station.z - kz) ^ 2 < 60 * 60 then
			return false
		end
	end
	for _, plot in Map.EstatePlots do
		if (plot.x - kx) ^ 2 + (plot.z - kz) ^ 2 < 70 * 70 then
			return false
		end
	end
	return true
end

-- The bus's lane offset to the kerb at a stop: it stands Map.CurbPark out from the curb.
local function pullIn(width: number): number
	return math.max(0, width / 2 - Map.CurbPark - TrafficLanes.laneOffset(width))
end

-- Where the bus's front-right door is: this far ahead of its middle (Vehicles' bus style: rideDoor at the front).
BusLines.DoorAhead = 9.6
BusLines.HalfWidth = 4 -- the bus is 8 wide
BusLines.HalfLength = 12

local allStops: { Stop } = {}
local stopByKey: { [string]: Stop } = {}

-- Where a stop on lane `e` of the graph, `s` studs along its lane piece, would be (nil: the kerb is not clear there).
type Spot = { e: number, x: number, z: number, hx: number, hz: number, kx: number, kz: number, rx: number, rz: number, cx: number, cz: number }
local function spotAt(g: TrafficLanes.Graph, e: number, piece: TrafficLanes.Piece, s: number): Spot?
	local x, z, hx, hz = TrafficLanes.at(piece, s)
	local width = g.width[e]
	local rx, rz = -hz, hx -- right of the way it goes (-Z is north)
	local cx, cz = x - rx * TrafficLanes.laneOffset(width), z - rz * TrafficLanes.laneOffset(width) -- the centre line
	local doorX, doorZ = cx + hx * BusLines.DoorAhead, cz + hz * BusLines.DoorAhead
	local kerb = width / 2 + 1.5 -- 1.5 studs onto the sidewalk
	local kx, kz = doorX + rx * kerb, doorZ + rz * kerb
	if not kerbClear(kx, kz, rx, rz) then
		return nil
	end
	local stand = width / 2 - Map.CurbPark
	return { e = e, x = cx + rx * stand, z = cz + rz * stand, hx = hx, hz = hz, kx = kx, kz = kz, rx = rx, rz = rz, cx = cx, cz = cz }
end

-- The stop at a spot for line `lineId` (two lines on the same lane of the same block share it).
local function makeStop(g: TrafficLanes.Graph, spot: Spot, lineId: number): Stop
	local e, cx, cz, hx, hz = spot.e, spot.cx, spot.cz, spot.hx, spot.hz
	local key = `{math.floor(spot.x + 0.5)},{math.floor(spot.z + 0.5)}`
	local existing = stopByKey[key]
	if existing then
		if not table.find(existing.lines, lineId) then
			table.insert(existing.lines, lineId)
		end
		return existing
	end
	local alongX = math.abs(hx) > math.abs(hz)
	local street = roadName(cx, cz, alongX) or "Main St"
	-- The nearer junction ahead or behind: its cross road's name.
	local ax, az = g.x[g.from[e]], g.z[g.from[e]]
	local ex, ez = g.x[g.to[e]], g.z[g.to[e]]
	local nearEnd = (ex - cx) ^ 2 + (ez - cz) ^ 2 < (ax - cx) ^ 2 + (az - cz) ^ 2
	local jx, jz = if nearEnd then ex else ax, if nearEnd then ez else az
	local cross = roadName(jx, jz, not alongX)
	-- 6.3: named after the key place by it, when there is one.
	local place = keyName(spot.kx, spot.kz)
	if place and place.id then
		named[place.id] = true
	end
	local stop: Stop = {
		id = #allStops + 1,
		name = if place and place.name then place.name elseif cross and cross ~= street then `{street} / {cross}` else street,
		street = street,
		x = spot.x,
		z = spot.z,
		hx = hx,
		hz = hz,
		kx = spot.kx,
		kz = spot.kz,
		nx = spot.rx,
		nz = spot.rz,
		lines = { lineId },
		landmark = if place then place.id else nil,
	}
	table.insert(allStops, stop)
	stopByKey[key] = stop
	return stop
end

-- Cruise seconds to arc along the loop (the segment it falls in).
local function segmentAtCruise(line: Line, c: number): Segment
	local list = line.segments
	local lo, hi = 1, #list
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if list[mid].cruise <= c then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return list[lo]
end

local function segmentAtArc(line: Line, arc: number): Segment
	local list = line.segments
	local lo, hi = 1, #list
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if list[mid].arc <= arc then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return list[lo]
end

local function cruiseAt(line: Line, arc: number): number
	local seg = segmentAtArc(line, arc)
	return seg.cruise + (arc - seg.arc) / seg.v
end

local function buildLine(g: TrafficLanes.Graph, def: Config.BusLineDef): Line
	-- 1. The directed edges round the loop.
	local edges: { number } = {}
	local corners = def.corners
	for n = 1, #corners do
		local a, b = corners[n], corners[n % #corners + 1]
		local leg = legEdges(g, a[1], a[2], b[1], b[2])
		assert(leg and #leg > 0, `BusLines: line {def.id} has no road from ({a[1]}, {a[2]}) to ({b[1]}, {b[2]})`)
		for _, e in leg do
			table.insert(edges, e)
		end
	end
	-- 2. The pieces (lane, turn, lane, turn …, closed) cut into segments by speed.
	local line: Line = {
		id = def.id,
		name = def.name,
		short = def.short,
		color = def.color,
		buses = math.max(1, def.buses),
		length = 0,
		segments = {},
		cruiseTotal = 0,
		stops = {},
		stopArc = {},
		stopCruise = {},
		arrive = {},
		depart = {},
		ramp = {},
		legCruise = {},
		period = 0,
		headway = 0,
	}
	local arc, cruise = 0, 0
	local function add(piece: TrafficLanes.Piece, s0: number, s1: number, v: number)
		if s1 - s0 <= EPS then
			return
		end
		table.insert(line.segments, { piece = piece, s0 = s0, s1 = s1, v = v, arc = arc, cruise = cruise })
		arc += s1 - s0
		cruise += (s1 - s0) / v
	end
	local fast, slow = Tuning.Speed, Tuning.TurnSpeed
	local between = (fast + slow) / 2
	local function isCorner(eIn: number, eOut: number): boolean
		return g.dx[eIn] * g.dx[eOut] + g.dz[eIn] * g.dz[eOut] < 0.95
	end
	local laneStart: { number } = {} -- the arc where each edge's lane starts
	for n, e in edges do
		local piece = TrafficLanes.lane(g, e)
		local before = edges[(n - 2) % #edges + 1]
		local after = edges[n % #edges + 1]
		local slowIn = math.min(if isCorner(before, e) then Tuning.Approach else 0, piece.length / 2)
		local slowOut = math.min(if isCorner(e, after) then Tuning.Approach else 0, piece.length / 2)
		laneStart[n] = arc
		add(piece, 0, slowIn, between)
		add(piece, slowIn, piece.length - slowOut, fast)
		add(piece, piece.length - slowOut, piece.length, between)
		local turn = TrafficLanes.turn(g, e, after)
		add(turn, 0, turn.length, if isCorner(e, after) then slow else fast)
	end
	line.length = arc
	line.cruiseTotal = cruise

	-- 3. The stops (6.3, express): every block's lane is a candidate where its kerb is clear (the middle, or a little
	-- up or down it), scored by the key places by it. The best one first, then round the loop the best within the
	-- window from StopGap after the last one on, and none closer than LastGap to the first one round the loop.
	local margin = BusLines.HalfLength + 3 -- the whole bus off the junction
	type Candidate = { at: number, spot: Spot, score: number }
	local candidates: { Candidate } = {}
	for n, e in edges do
		local piece = TrafficLanes.lane(g, e)
		if piece.length < 2 * margin + 10 then
			continue
		end
		local mid = piece.length / 2
		for _, shift in { 0, 22, -22, 36, -36 } do
			local s = math.clamp(mid + shift, margin, piece.length - margin)
			local spot = spotAt(g, e, piece, s)
			if spot then
				-- (the lane's segments run on from laneStart)
				table.insert(candidates, { at = laneStart[n] + s, spot = spot, score = keyScore(spot.kx, spot.kz) })
				break
			end
		end
	end
	local first: Candidate? = nil
	for _, c in candidates do
		if not first or c.score > first.score + EPS then
			first = c
		end
	end
	assert(first, `BusLines: line {def.id} has no stops`)
	local start = first.at
	local length = line.length
	local function ahead(c: Candidate): number
		return (c.at - start) % length
	end
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return ahead(a) < ahead(b)
	end)
	local picked: { Candidate } = { first }
	local last = 0
	while true do
		local best: Candidate? = nil
		local beyond: Candidate? = nil
		for _, c in candidates do
			local f = ahead(c)
			if f < last + Tuning.StopGap or length - f < Tuning.LastGap then
				continue
			end
			if f <= last + Tuning.StopGap + Tuning.PickWindow then
				if not best or c.score > best.score + EPS then
					best = c
				end
			elseif not beyond then
				beyond = c
			end
		end
		local pick = best or beyond
		if not pick then
			break
		end
		table.insert(picked, pick)
		last = ahead(pick)
	end
	-- Round the loop from its start (the timetable runs from the stop nearest it), each made (or shared) now.
	table.sort(picked, function(a: Candidate, b: Candidate): boolean
		return a.at < b.at
	end)
	for _, c in picked do
		table.insert(line.stops, makeStop(g, c.spot, def.id))
		table.insert(line.stopArc, c.at)
	end
	assert(#line.stops >= 2, `BusLines: line {def.id} has fewer than 2 stops`)

	-- 4. The timetable: from stop k a leg to stop k + 1 (the last back to the first), its cruise time stretched by the
	-- ramps (speeding up over `ramp` seconds covers half the cruise distance of that time: the leg takes ramp more).
	local count = #line.stops
	for k = 1, count do
		line.stopCruise[k] = cruiseAt(line, line.stopArc[k])
	end
	local t = 0
	for k = 1, count do
		local c0 = line.stopCruise[k]
		local c1 = if k < count then line.stopCruise[k + 1] else line.stopCruise[1] + line.cruiseTotal
		local legCruise = c1 - c0
		local ramp = math.min(Tuning.Ramp, legCruise)
		line.arrive[k] = t
		line.depart[k] = t + Tuning.Dwell
		line.legCruise[k] = legCruise
		line.ramp[k] = ramp
		t = line.depart[k] + legCruise + ramp
	end
	line.period = t
	line.headway = t / line.buses
	return line
end

local lines: { Line }? = nil

-- Every line (built on the first call).
function BusLines.lines(): { Line }
	local built = lines
	if built then
		return built
	end
	local g = TrafficLanes.graph()
	local list: { Line } = {}
	for _, def in Tuning.Lines do
		-- (a line that cannot be laid out, no road or no stops, is left out: tests/buslines_test.luau says so)
		local ok, line = pcall(buildLine, g, def)
		if ok then
			table.insert(list, line)
		else
			print(`[BusLines] line {def.id} left out: {line}`)
			for n = #allStops, 1, -1 do
				local stop = allStops[n]
				local at = table.find(stop.lines, def.id)
				if at then
					table.remove(stop.lines, at)
				end
				if #stop.lines == 0 then
					table.remove(allStops, n)
					stopByKey[`{math.floor(stop.x + 0.5)},{math.floor(stop.z + 0.5)}`] = nil
					if stop.landmark then
						named[stop.landmark] = nil
					end
				end
			end
			for n, stop in allStops do
				stop.id = n
			end
		end
	end
	lines = list
	return list
end

-- A line by its id (nil: none).
function BusLines.line(id: number): Line?
	for _, line in BusLines.lines() do
		if line.id == id then
			return line
		end
	end
	return nil
end

-- The stops of a line, in the order the bus comes to them.
function BusLines.stops(line: Line): { Stop }
	return line.stops
end

-- Every stop of every line (a shared stop once).
function BusLines.allStops(): { Stop }
	BusLines.lines()
	return allStops
end

-- ── The timetable ──────────────────────────────────────────────────────────

-- Seconds into its loop bus `bus` (0 … buses - 1) is at server time `now`.
local function loopTime(line: Line, bus: number, now: number): number
	return (now - bus * line.headway) % line.period
end

-- The leg (stop index) a loop time falls in: arrive[k] <= t < arrive[k + 1].
local function legAt(line: Line, t: number): number
	local arrive = line.arrive
	local lo, hi = 1, #arrive
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if arrive[mid] <= t then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return lo
end

-- Cruise seconds covered `t` seconds after leaving a stop on a leg of cruise time `legCruise` with ramp r (speeding
-- up over the first r seconds, slowing over the last r).
local function rampCruise(t: number, legCruise: number, r: number): number
	local total = legCruise + r
	if t <= 0 then
		return 0
	elseif t >= total then
		return legCruise
	end
	if r <= EPS then
		return t
	end
	if t < r then
		return t * t / (2 * r)
	elseif t <= total - r then
		return t - r / 2
	end
	local left = total - t
	return legCruise - left * left / (2 * r)
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Where bus `bus` (0-based) of the line is at server time `now`: its middle on the road (x, z), the way it faces
-- (hx, hz, unit), the stop it stands at (its index; 0 while it drives), the stop it comes to next (its index; while
-- it stands, the one after) and the seconds before it leaves (while it stands; else 0).
function BusLines.position(line: Line, bus: number, now: number): (number, number, number, number, number, number, number)
	local count = #line.stops
	local t = loopTime(line, bus, now)
	local k = legAt(line, t)
	local nextStop = k % count + 1
	if t < line.depart[k] then
		local stop = line.stops[k]
		return stop.x, stop.z, stop.hx, stop.hz, k, nextStop, line.depart[k] - t
	end
	local c = rampCruise(t - line.depart[k], line.legCruise[k], line.ramp[k])
	local cruise = (line.stopCruise[k] + c) % line.cruiseTotal
	local seg = segmentAtCruise(line, cruise)
	local along = (cruise - seg.cruise) * seg.v
	local x, z, hx, hz = TrafficLanes.at(seg.piece, math.min(seg.s0 + along, seg.s1))
	-- Pulling in to the kerb by a stop (and out again after it).
	local arc = seg.arc + along
	local fromLast = (arc - line.stopArc[k]) % line.length
	local toNext = (line.stopArc[nextStop] - arc) % line.length
	local near = math.min(fromLast, toNext)
	local width = Map.RoadWidth
	local shift = pullIn(width) * smooth(1 - near / 40)
	if shift > 0 then
		x += -hz * shift
		z += hx * shift
	end
	return x, z, hx, hz, 0, nextStop, 0
end

-- Seconds until a bus of the line stands at its stop `stopIndex` (0: one stands there now) and which bus (0-based).
function BusLines.nextArrival(line: Line, stopIndex: number, now: number): (number, number)
	local best, which = math.huge, 0
	local arrive, depart = line.arrive[stopIndex], line.depart[stopIndex]
	for bus = 0, line.buses - 1 do
		local t = loopTime(line, bus, now)
		local wait = if t >= arrive and t < depart then 0 else (arrive - t) % line.period
		if wait < best then
			best, which = wait, bus
		end
	end
	return best, which
end

-- Seconds from standing at stop `from` to standing at stop `to` (a later stop round the loop; the same stop: a whole
-- loop).
function BusLines.rideTime(line: Line, from: number, to: number): number
	local span = (line.arrive[to] - line.arrive[from]) % line.period
	return if span <= EPS then line.period else span
end

-- ── Finding stops and routes ───────────────────────────────────────────────

export type Near = { stop: Stop, distance: number }

-- The stops whose kerb is within `radius` of (x, z), nearest first.
function BusLines.stopsNear(x: number, z: number, radius: number): { Near }
	local list: { Near } = {}
	for _, stop in BusLines.allStops() do
		local d = math.sqrt((stop.kx - x) ^ 2 + (stop.kz - z) ^ 2)
		if d <= radius then
			table.insert(list, { stop = stop, distance = d })
		end
	end
	table.sort(list, function(a, b)
		return a.distance < b.distance
	end)
	return list
end

-- The index of a stop in a line (nil: the line does not stop there).
function BusLines.indexOf(line: Line, stop: Stop): number?
	return table.find(line.stops, stop)
end

-- The best bus ride from (fromX, fromZ) to (toX, toZ): walk to a stop, wait (half a headway on average), ride, walk
-- from the stop; nil when walking all the way is about as quick (within Config.Bus.RouteSaving). `walkSpeed`: how
-- fast you walk now (default Config.Movement.Walk; slower with a piece in your hands, which rides in the pack).
function BusLines.route(fromX: number, fromZ: number, toX: number, toZ: number, walkSpeed: number?): Route?
	local walk = math.max(1, walkSpeed or Config.Movement.Walk)
	local walkTime = Map.manhattan(fromX, fromZ, toX, toZ) / walk
	local reach = Tuning.RouteReach
	local best: Route? = nil
	for _, line in BusLines.lines() do
		for a, boardStop in line.stops do
			local walkTo = Map.manhattan(fromX, fromZ, boardStop.kx, boardStop.kz)
			if walkTo > reach then
				continue
			end
			for b, leaveStop in line.stops do
				if b == a then
					continue
				end
				local walkFrom = Map.manhattan(leaveStop.kx, leaveStop.kz, toX, toZ)
				if walkFrom > reach then
					continue
				end
				local ride = BusLines.rideTime(line, a, b)
				local time = (walkTo + walkFrom) / walk + line.headway / 2 + ride
				if not best or time < best.time then
					best = {
						line = line,
						board = a,
						leave = b,
						boardStop = boardStop,
						leaveStop = leaveStop,
						stops = (b - a) % #line.stops,
						walkTo = walkTo,
						walkFrom = walkFrom,
						ride = ride,
						time = time,
						walkTime = walkTime,
					}
				end
			end
		end
	end
	if best and best.time + Tuning.RouteSaving <= walkTime then
		return best
	end
	return nil
end

-- ── 6.3, the bus map ───────────────────────────────────────────────────────

export type MapPoint = { x: number, z: number }
export type MapStop = { id: number, x: number, z: number, name: string }
export type MapLine = { line: number, short: string, color: { number }, points: { MapPoint }, stops: { MapStop } }

-- How far the point b is off the straight line from a to c.
local function offLine(a: MapPoint, b: MapPoint, c: MapPoint): number
	local dx, dz = c.x - a.x, c.z - a.z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < EPS then
		return math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
	end
	return math.abs(dx * (b.z - a.z) - dz * (b.x - a.x)) / length
end

local mapCache: { [number]: { MapLine } } = {}

-- Every line for a map (client/MapView.luau, client/BusMapBoard.luau): its loop as a closed polyline of at most
-- `maxPoints` corners (the straight runs joined, the point that bends it least dropped first: few frames to draw),
-- and its stops in the order the bus comes to them (where the bus stands). Cached per maxPoints.
function BusLines.mapLines(maxPoints: number?): { MapLine }
	local most = math.max(4, maxPoints or 32)
	local cached = mapCache[most]
	if cached then
		return cached
	end
	local list: { MapLine } = {}
	for _, line in BusLines.lines() do
		local points: { MapPoint } = {}
		for _, seg in line.segments do
			local x, z = TrafficLanes.at(seg.piece, seg.s0)
			local prev = points[#points]
			if not prev or (prev.x - x) ^ 2 + (prev.z - z) ^ 2 > 1 then
				table.insert(points, { x = x, z = z })
			end
		end
		-- Drop the point that bends the loop least (it is closed: the neighbours wrap) while it is straight or too many.
		while #points > 4 do
			local count = #points
			local worst, at = math.huge, 0
			for n = 1, count do
				local off = offLine(points[(n - 2) % count + 1], points[n], points[n % count + 1])
				if off < worst then
					worst, at = off, n
				end
			end
			if worst > 0.5 and count <= most then
				break
			end
			table.remove(points, at)
		end
		local stops: { MapStop } = {}
		for _, stop in line.stops do
			table.insert(stops, { id = stop.id, x = stop.x, z = stop.z, name = stop.name })
		end
		table.insert(list, { line = line.id, short = line.short, color = line.color, points = points, stops = stops })
	end
	mapCache[most] = list
	return list
end

-- A line's colour as r, g, b (0 … 255).
function BusLines.rgb(line: Line): (number, number, number)
	return line.color[1], line.color[2], line.color[3]
end

-- "1:05" for a wait in seconds ("NOW" at 0).
function BusLines.clock(seconds: number): string
	if seconds <= 0.5 then
		return "NOW"
	end
	local s = math.ceil(seconds)
	return string.format("%d:%02d", s // 60, s % 60)
end

return BusLines
