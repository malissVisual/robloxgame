--!strict
-- The geometry behind the city's traffic (server/Traffic.luau), as plain numbers: the lanes the civilian cars drive
-- and the sidewalks the pedestrians walk. Pure Luau (no Roblox types), so tests/traffic_test.luau runs it outside
-- Roblox.
--
-- Lanes. The road graph is built once from shared/Map.luau's centre lines, like shared/Roads.luau's, with one
-- difference: a road that stops on another road (a T-junction, a highway leaving a grid) is snapped onto that road's
-- centre line, so every junction is one node and no short link pieces are needed. Every edge has two directed
-- edges (one per direction); a car drives on the RIGHT of its directed edge (a quarter of the road width off the
-- centre line). A lane piece runs between the intersections (it stops `inset` before a node where roads meet), a
-- turn piece is a cubic Bézier from the end of one lane to the start of the next (straight on, left, right, or a
-- U-turn at a dead end). Pieces are cached on the graph, so a driving car allocates nothing.
--
-- No traffic in the winter, on the ice road or north of the mountain tunnel's south mouth (TrafficLanes.allowedAt):
-- those edges are kept in the graph (the junction shapes) but no car drives them, and a car that reaches the limit
-- turns around.
--
-- Sidewalks. Every district block (Map.Districts) is a raised slab; the pedestrians walk a ring SidewalkInset studs
-- inside its edge, corner to corner, and now and then cross the street to the next block's facing corner.

local Map = require(script.Parent.Map)

local TrafficLanes = {}

export type Graph = {
	x: { number }, -- node positions
	z: { number },
	out: { { number } }, -- per node: the directed edges leaving it
	inset: { number }, -- per node: how far before it the lanes stop (the junction's size)
	from: { number }, -- per directed edge
	to: { number },
	len: { number },
	dx: { number }, -- direction (unit)
	dz: { number },
	width: { number },
	kind: { string },
	allowed: { boolean }, -- traffic drives here
	reverse: { number }, -- the same edge the other way
	lanes: { number }, -- every allowed directed edge
	laneCache: { [number]: Piece },
	turnCache: { [number]: Piece },
}

export type Piece = {
	edge: number, -- a lane: its directed edge; a turn: the directed edge it turns onto
	from: number, -- a turn: the directed edge it comes from (a lane: its own edge)
	turn: boolean,
	uturn: boolean,
	length: number,
	speed: number, -- share of the car's cruise speed through this piece
	enter: number, -- a turn: how far into the lane it leads onto it ends (0 but for a turn-around mid-road)
	px: { number }, -- a lane: its two ends; a turn: the four Bézier control points
	pz: { number },
	cum: { number }, -- a turn: the arc length at each sample (SAMPLES + 1 of them)
}

-- A spot on a sidewalk: block (i, j) of district d, walking toward corner k (1 .. 4, see Corners).
export type Sidewalk = { d: Map.District, i: number, j: number, k: number, x: number, z: number }

local SNAP_SLACK = 3 -- a road end within its neighbour's half width + this is snapped onto it
local SAMPLES = 10 -- points along a turn (arc length table)
local INF = math.huge

-- Nothing drives north of this line (the tunnel, the winter, the frozen lake).
TrafficLanes.NorthLimit = Map.Mountain.tunnelZ1 + 60
-- The pedestrians' ring: this far inside a block's edge.
TrafficLanes.SidewalkInset = 4
-- The block corners in ring order (clockwise seen from above: NW, NE, SE, SW; -Z is north).
TrafficLanes.Corners = { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }

-- May traffic be here?
function TrafficLanes.allowedAt(x: number, z: number): boolean
	return z >= TrafficLanes.NorthLimit and not Map.isWinter(x, z) and not Map.onIce(x, z)
end

-- How far right of the centre line a car drives on a road this wide.
function TrafficLanes.laneOffset(width: number): number
	return width * 0.25
end

-- The cruise speed on a kind of road (share of Config.Traffic.CarSpeed).
function TrafficLanes.speedOf(kind: string): number
	if kind == "highway" then
		return 1.3
	elseif kind == "grid" then
		return 0.9
	end
	return 1
end

local function project(ax: number, az: number, bx: number, bz: number, x: number, z: number): (number, number, number, number)
	local dx, dz = bx - ax, bz - az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - ax) * dx + (z - az) * dz) / length2, 0, 1) else 0
	local px, pz = ax + dx * t, az + dz * t
	return px, pz, (x - px) ^ 2 + (z - pz) ^ 2, t
end

type Seg = { ax: number, az: number, bx: number, bz: number, width: number, kind: string }

local function build(): Graph
	local g: Graph = {
		x = {},
		z = {},
		out = {},
		inset = {},
		from = {},
		to = {},
		len = {},
		dx = {},
		dz = {},
		width = {},
		kind = {},
		allowed = {},
		reverse = {},
		lanes = {},
		laneCache = {},
		turnCache = {},
	}
	local segs: { Seg } = {}
	for _, s in Map.Segments do
		table.insert(segs, { ax = s.ax, az = s.az, bx = s.bx, bz = s.bz, width = s.width, kind = s.kind })
	end

	-- 1. Road ends that stop on another road move onto its centre line.
	for i, s in segs do
		for side = 1, 2 do
			local ex = if side == 1 then s.ax else s.bx
			local ez = if side == 1 then s.az else s.bz
			local bestD, bestX, bestZ = INF, ex, ez
			for j, o in segs do
				if j ~= i then
					local px, pz, d2 = project(o.ax, o.az, o.bx, o.bz, ex, ez)
					local reach = o.width / 2 + SNAP_SLACK
					if d2 <= reach * reach and d2 < bestD then
						bestD, bestX, bestZ = d2, px, pz
					end
				end
			end
			if bestD < INF then
				if side == 1 then
					s.ax, s.az = bestX, bestZ
				else
					s.bx, s.bz = bestX, bestZ
				end
			end
		end
	end

	-- 2. Cut every road where another crosses or touches it, and where it crosses the north limit.
	local cuts: { { number } } = {}
	for i = 1, #segs do
		cuts[i] = { 0, 1 }
	end
	for i = 1, #segs do
		local s = segs[i]
		local rx, rz = s.bx - s.ax, s.bz - s.az
		for j = i + 1, #segs do
			local o = segs[j]
			local qx, qz = o.bx - o.ax, o.bz - o.az
			local denom = rx * qz - rz * qx
			if math.abs(denom) > 1e-9 then
				local wx, wz = o.ax - s.ax, o.az - s.az
				local t = (wx * qz - wz * qx) / denom
				local u = (wx * rz - wz * rx) / denom
				if t >= -1e-6 and t <= 1 + 1e-6 and u >= -1e-6 and u <= 1 + 1e-6 then
					table.insert(cuts[i], math.clamp(t, 0, 1))
					table.insert(cuts[j], math.clamp(u, 0, 1))
				end
			end
		end
		local limit = TrafficLanes.NorthLimit
		if (s.az - limit) * (s.bz - limit) < 0 then
			table.insert(cuts[i], (limit - s.az) / (s.bz - s.az))
		end
	end

	-- 3. Nodes (a half-stud grid merges the same junction found from two roads) and the edges between them.
	local index: { [string]: number } = {}
	local function node(x: number, z: number): number
		local key = `{math.floor(x * 2 + 0.5)},{math.floor(z * 2 + 0.5)}`
		local n = index[key]
		if not n then
			table.insert(g.x, x)
			table.insert(g.z, z)
			table.insert(g.out, {})
			n = #g.x
			index[key] = n
		end
		return n
	end
	local seen: { [string]: boolean } = {}
	local function edge(a: number, b: number, width: number, kind: string)
		if a == b then
			return
		end
		local key = if a < b then `{a}-{b}` else `{b}-{a}`
		if seen[key] then
			return
		end
		seen[key] = true
		local dx, dz = g.x[b] - g.x[a], g.z[b] - g.z[a]
		local length = math.sqrt(dx * dx + dz * dz)
		if length < 0.5 then
			return
		end
		local mx, mz = (g.x[a] + g.x[b]) / 2, (g.z[a] + g.z[b]) / 2
		local ok = kind ~= "ice"
			and TrafficLanes.allowedAt(g.x[a], g.z[a])
			and TrafficLanes.allowedAt(g.x[b], g.z[b])
			and TrafficLanes.allowedAt(mx, mz)
		local first = #g.from + 1
		for _, way in { { a, b, 1 }, { b, a, -1 } } do
			table.insert(g.from, way[1])
			table.insert(g.to, way[2])
			table.insert(g.len, length)
			table.insert(g.dx, dx / length * way[3])
			table.insert(g.dz, dz / length * way[3])
			table.insert(g.width, width)
			table.insert(g.kind, kind)
			table.insert(g.allowed, ok)
			table.insert(g.out[way[1]], #g.from)
			if ok then
				table.insert(g.lanes, #g.from)
			end
		end
		table.insert(g.reverse, first + 1)
		table.insert(g.reverse, first)
	end
	for i, s in segs do
		local list = cuts[i]
		table.sort(list)
		local previous: number? = nil
		for _, t in list do
			local n = node(s.ax + (s.bx - s.ax) * t, s.az + (s.bz - s.az) * t)
			if previous then
				edge(previous, n, s.width, s.kind)
			end
			previous = n
		end
	end

	-- 4. How big each junction is: where three or more roads meet the lanes stop at the widest one's edge; a bend
	-- rounds off; a dead end leaves room to turn around.
	for n = 1, #g.x do
		local list = g.out[n]
		local widest = 0
		for _, e in list do
			widest = math.max(widest, g.width[e])
		end
		local inset = 0
		if #list >= 3 then
			inset = widest / 2 + 1
		elseif #list == 1 then
			inset = 4
		elseif #list == 2 then
			local a, b = list[1], list[2]
			if g.dx[a] * g.dx[b] + g.dz[a] * g.dz[b] > -0.98 then
				inset = 10 -- not straight on: round the bend
			end
		end
		g.inset[n] = inset
	end
	return g
end

local cached: Graph? = nil

-- The lane graph (built on the first call).
function TrafficLanes.graph(): Graph
	local g = cached
	if g then
		return g
	end
	local built = build()
	cached = built
	return built
end

-- The insets at both ends of a directed edge (they never eat more than 80 % of a short edge).
local function insets(g: Graph, e: number): (number, number)
	local a, b = g.inset[g.from[e]], g.inset[g.to[e]]
	local room = g.len[e] * 0.8
	if a + b > room then
		local k = room / (a + b)
		a, b = a * k, b * k
	end
	return a, b
end

-- The lane of a directed edge: from just after its start junction to just before its end junction, on the right.
function TrafficLanes.lane(g: Graph, e: number): Piece
	local piece = g.laneCache[e]
	if piece then
		return piece
	end
	local a, b = insets(g, e)
	local dx, dz = g.dx[e], g.dz[e]
	local off = TrafficLanes.laneOffset(g.width[e])
	local rx, rz = -dz * off, dx * off -- right of the way it goes (-Z is north)
	local sx, sz = g.x[g.from[e]], g.z[g.from[e]]
	local ex, ez = g.x[g.to[e]], g.z[g.to[e]]
	local built: Piece = {
		edge = e,
		from = e,
		turn = false,
		uturn = false,
		length = math.max(g.len[e] - a - b, 0),
		speed = TrafficLanes.speedOf(g.kind[e]),
		enter = 0,
		px = { sx + dx * a + rx, ex - dx * b + rx },
		pz = { sz + dz * a + rz, ez - dz * b + rz },
		cum = {},
	}
	g.laneCache[e] = built
	return built
end

local function bezier(px: { number }, pz: { number }, u: number): (number, number)
	local v = 1 - u
	local a, b, c, d = v * v * v, 3 * v * v * u, 3 * v * u * u, u * u * u
	return a * px[1] + b * px[2] + c * px[3] + d * px[4], a * pz[1] + b * pz[2] + c * pz[3] + d * pz[4]
end

local function arcLengths(px: { number }, pz: { number }): { number }
	local cum = { 0 }
	local lastX, lastZ = px[1], pz[1]
	for n = 1, SAMPLES do
		local x, z = bezier(px, pz, n / SAMPLES)
		cum[n + 1] = cum[n] + math.sqrt((x - lastX) ^ 2 + (z - lastZ) ^ 2)
		lastX, lastZ = x, z
	end
	return cum
end

local function bezierTangent(px: { number }, pz: { number }, u: number): (number, number)
	local v = 1 - u
	local a, b, c = 3 * v * v, 6 * v * u, 3 * u * u
	return a * (px[2] - px[1]) + b * (px[3] - px[2]) + c * (px[4] - px[3]), a * (pz[2] - pz[1]) + b * (pz[3] - pz[2]) + c * (pz[4] - pz[3])
end

-- From the end of lane eIn to the start of lane eOut (eOut leaves the node eIn arrives at).
function TrafficLanes.turn(g: Graph, eIn: number, eOut: number): Piece
	local key = eIn * 65536 + eOut
	local piece = g.turnCache[key]
	if piece then
		return piece
	end
	local lin, lout = TrafficLanes.lane(g, eIn), TrafficLanes.lane(g, eOut)
	local x0, z0 = lin.px[2], lin.pz[2]
	local x3, z3 = lout.px[1], lout.pz[1]
	local d0x, d0z = g.dx[eIn], g.dz[eIn]
	local d1x, d1z = g.dx[eOut], g.dz[eOut]
	local uturn = eOut == g.reverse[eIn]
	local chord = math.sqrt((x3 - x0) ^ 2 + (z3 - z0) ^ 2)
	local k = if uturn then TrafficLanes.laneOffset(g.width[eIn]) * 1.4 + 2 else chord * 0.45
	local px = { x0, x0 + d0x * k, x3 - d1x * k, x3 }
	local pz = { z0, z0 + d0z * k, z3 - d1z * k, z3 }
	local cum = arcLengths(px, pz)
	local straight = d0x * d1x + d0z * d1z
	local built: Piece = {
		edge = eOut,
		from = eIn,
		turn = true,
		uturn = uturn,
		length = cum[SAMPLES + 1],
		speed = if uturn then 0.3 elseif straight > 0.95 then 1 elseif straight > 0.5 then 0.75 else 0.5,
		enter = 0,
		px = px,
		pz = pz,
		cum = cum,
	}
	g.turnCache[key] = built
	return built
end

-- A tight U-turn in the middle of lane e, `s` studs along it, onto the same spot of the lane the other way (a car
-- stuck behind something that does not move). Not cached: it is rare.
function TrafficLanes.turnAround(g: Graph, e: number, s: number): Piece
	local lane = TrafficLanes.lane(g, e)
	local back = g.reverse[e]
	local other = TrafficLanes.lane(g, back)
	local enter = math.clamp(other.length - s, 0, other.length)
	local x0, z0 = TrafficLanes.at(lane, s)
	local x3, z3 = TrafficLanes.at(other, enter)
	local k = TrafficLanes.laneOffset(g.width[e]) * 0.5
	local dx, dz = g.dx[e], g.dz[e]
	local px = { x0, x0 + dx * k, x3 + dx * k, x3 }
	local pz = { z0, z0 + dz * k, z3 + dz * k, z3 }
	local cum = arcLengths(px, pz)
	return {
		edge = back,
		from = e,
		turn = true,
		uturn = true,
		length = cum[SAMPLES + 1],
		speed = 0.3,
		enter = enter,
		px = px,
		pz = pz,
		cum = cum,
	}
end

-- Where on a piece a car is after `s` studs along it, and which way it faces (unit).
function TrafficLanes.at(piece: Piece, s: number): (number, number, number, number)
	local px, pz = piece.px, piece.pz
	if not piece.turn then
		local dx, dz = px[2] - px[1], pz[2] - pz[1]
		local length = math.sqrt(dx * dx + dz * dz)
		if length < 1e-6 then
			return px[1], pz[1], 0, 0
		end
		local t = math.clamp(s / length, 0, 1)
		return px[1] + dx * t, pz[1] + dz * t, dx / length, dz / length
	end
	local cum = piece.cum
	local u = 1
	if piece.length > 1e-6 then
		local target = math.clamp(s, 0, piece.length)
		u = 1
		for n = 1, SAMPLES do
			if cum[n + 1] >= target then
				local span = cum[n + 1] - cum[n]
				local f = if span > 1e-6 then (target - cum[n]) / span else 0
				u = (n - 1 + f) / SAMPLES
				break
			end
		end
	end
	local x, z = bezier(px, pz, u)
	local tx, tz = bezierTangent(px, pz, u)
	local length = math.sqrt(tx * tx + tz * tz)
	if length < 1e-6 then
		-- A degenerate turn (straight on through a point): the direction of the chord.
		tx, tz = px[4] - px[1], pz[4] - pz[1]
		length = math.sqrt(tx * tx + tz * tz)
		if length < 1e-6 then
			return x, z, 0, 0
		end
	end
	return x, z, tx / length, tz / length
end

-- Where a car on directed edge e goes next: one of the allowed roads leaving the junction ahead (straight on a bit
-- more likely than a turn; roll is 0 .. 1), a U-turn when there is no other way, nil if not even that.
function TrafficLanes.nextEdge(g: Graph, e: number, roll: number): number?
	local back = g.reverse[e]
	local choices: { number } = {}
	local weights: { number } = {}
	local total = 0
	for _, o in g.out[g.to[e]] do
		if o ~= back and g.allowed[o] then
			local straight = g.dx[e] * g.dx[o] + g.dz[e] * g.dz[o]
			local w = if straight > 0.95 then 1.6 else 1
			table.insert(choices, o)
			table.insert(weights, w)
			total += w
		end
	end
	if #choices == 0 then
		return if g.allowed[back] then back else nil
	end
	local pick = roll * total
	for n, o in choices do
		pick -= weights[n]
		if pick <= 0 then
			return o
		end
	end
	return choices[#choices]
end

-- A spot on a lane minD .. maxD studs from (px, pz): the directed edge, the distance along its lane and the point.
-- nil when no lane comes that close.
function TrafficLanes.spawnSpot(g: Graph, px: number, pz: number, minD: number, maxD: number, rand: () -> number): (number?, number, number, number)
	local candidates: { number } = {}
	for _, e in g.lanes do
		local a, b = g.from[e], g.to[e]
		local _, _, d2 = project(g.x[a], g.z[a], g.x[b], g.z[b], px, pz)
		if d2 > maxD * maxD then
			continue
		end
		local far = math.max((g.x[a] - px) ^ 2 + (g.z[a] - pz) ^ 2, (g.x[b] - px) ^ 2 + (g.z[b] - pz) ^ 2)
		if far >= minD * minD then
			table.insert(candidates, e)
		end
	end
	if #candidates == 0 then
		return nil, 0, 0, 0
	end
	for _ = 1, 8 do
		local e = candidates[math.floor(rand() * #candidates) + 1]
		local piece = TrafficLanes.lane(g, e)
		if piece.length < 4 then
			continue
		end
		for _ = 1, 6 do
			local s = rand() * piece.length
			local x, z = TrafficLanes.at(piece, s)
			local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
			if d >= minD and d <= maxD then
				return e, s, x, z
			end
		end
	end
	return nil, 0, 0, 0
end

-- ── Sidewalks ──────────────────────────────────────────────────────────────

-- Corner k (1 .. 4) of the ring around block (i, j) of district d.
function TrafficLanes.corner(d: Map.District, i: number, j: number, k: number): (number, number)
	local c = TrafficLanes.Corners[(k - 1) % 4 + 1]
	local half = Map.BlockSize / 2 - TrafficLanes.SidewalkInset
	return d.ox + i * Map.Cell + c[1] * half, d.oz + j * Map.Cell + c[2] * half
end

-- The next corner around the ring (dir +1 or -1).
function TrafficLanes.nextCorner(k: number, dir: number): number
	return (k - 1 + dir) % 4 + 1
end

local function cornerIndex(sx: number, sz: number): number
	for k, c in TrafficLanes.Corners do
		if c[1] == sx and c[2] == sz then
			return k
		end
	end
	return 1
end

-- Across the street from corner k of block (i, j): the facing corner of the next block, along X (alongX) or Z.
-- nil at the district's edge.
function TrafficLanes.across(d: Map.District, i: number, j: number, k: number, alongX: boolean): (number?, number, number)
	local c = TrafficLanes.Corners[(k - 1) % 4 + 1]
	local i2, j2, sx, sz = i, j, c[1], c[2]
	if alongX then
		i2, sx = i + c[1], -c[1]
	else
		j2, sz = j + c[2], -c[2]
	end
	if i2 < d.i0 or i2 > d.i1 or j2 < d.j0 or j2 > d.j1 then
		return nil, 0, 0
	end
	return cornerIndex(sx, sz), i2, j2
end

-- Keeps a point on the block (inside the pedestrians' ring).
function TrafficLanes.clampToBlock(d: Map.District, i: number, j: number, x: number, z: number): (number, number)
	local half = Map.BlockSize / 2 - TrafficLanes.SidewalkInset
	local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
	return math.clamp(x, cx - half, cx + half), math.clamp(z, cz - half, cz + half)
end

type Block = { d: Map.District, i: number, j: number }

-- A spot on a sidewalk ring minD .. maxD studs from (px, pz) (nil when no block is in reach).
function TrafficLanes.sidewalkSpot(px: number, pz: number, minD: number, maxD: number, rand: () -> number): Sidewalk?
	local blocks: { Block } = {}
	local slack = Map.BlockSize * 0.75
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
				local dist = math.sqrt((cx - px) ^ 2 + (cz - pz) ^ 2)
				if dist >= minD - slack and dist <= maxD + slack then
					table.insert(blocks, { d = d, i = i, j = j })
				end
			end
		end
	end
	if #blocks == 0 then
		return nil
	end
	for _ = 1, 12 do
		local b = blocks[math.floor(rand() * #blocks) + 1]
		local k = math.floor(rand() * 4) + 1 -- the side from corner k to corner k + 1
		local ax, az = TrafficLanes.corner(b.d, b.i, b.j, k)
		local bx, bz = TrafficLanes.corner(b.d, b.i, b.j, k + 1)
		local f = rand()
		local x, z = ax + (bx - ax) * f, az + (bz - az) * f
		local dist = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		if dist >= minD and dist <= maxD then
			return { d = b.d, i = b.i, j = b.j, k = TrafficLanes.nextCorner(k, 1), x = x, z = z }
		end
	end
	return nil
end

return TrafficLanes
