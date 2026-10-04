--!strict
-- The road network as a graph (from shared/Map.luau's segments: the district grids, bridges, highways, the ice road)
-- and the shortest drive between two points along it, for the GPS route on the maps (like GTA). Pure Luau (no
-- Roblox types), so tests/roads_test.luau runs it outside Roblox.
--
-- The graph is built once: a node at both ends of every segment, where two segments cross, and where the end of one
-- segment meets another (a T-junction or a connector stopping at the edge of a grid; the roads only have to touch
-- within half a road width, then a short link joins them). Edges run along the segments between their nodes.
-- Roads.route snaps both ends to the nearest point on a road and runs A* (a binary heap, the straight distance to
-- the goal as the estimate, a small extra cost per turn so it does not zigzag through a grid); a route takes well
-- under a millisecond.

local Map = require(script.Parent.Map)

local Roads = {}

export type Point = { x: number, z: number }

type Graph = {
	x: { number }, -- node positions
	z: { number },
	out: { { number } }, -- per node: the directed edges leaving it
	dirTo: { number }, -- per directed edge: where it goes, its length and its direction (unit)
	dirLen: { number },
	dirX: { number },
	dirZ: { number },
	edgeA: { number }, -- every edge (for snapping a point to the nearest road)
	edgeB: { number },
	edgeKind: { string },
}

local LINK_SLACK = 3 -- a road end counts as touching another road within its half width + this
local TURN_COST = 30 -- studs added for every turn, so of two equally long ways the route takes the one with fewer turns
local INF = math.huge

local cached: Graph? = nil

local function project(ax: number, az: number, bx: number, bz: number, x: number, z: number): (number, number, number, number)
	local dx, dz = bx - ax, bz - az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - ax) * dx + (z - az) * dz) / length2, 0, 1) else 0
	local px, pz = ax + dx * t, az + dz * t
	return px, pz, (x - px) ^ 2 + (z - pz) ^ 2, t
end

local function build(): Graph
	local g: Graph = { x = {}, z = {}, out = {}, dirTo = {}, dirLen = {}, dirX = {}, dirZ = {}, edgeA = {}, edgeB = {}, edgeKind = {} }
	local index: { [string]: number } = {}
	local function node(x: number, z: number): number
		-- half-stud grid, so the same junction found from two segments is one node
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
	local function edge(a: number, b: number, kind: string)
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
		for _, way in { { a, b, 1 }, { b, a, -1 } } do
			table.insert(g.dirTo, way[2])
			table.insert(g.dirLen, length)
			table.insert(g.dirX, dx / length * way[3])
			table.insert(g.dirZ, dz / length * way[3])
			table.insert(g.out[way[1]], #g.dirTo)
		end
		table.insert(g.edgeA, a)
		table.insert(g.edgeB, b)
		table.insert(g.edgeKind, kind)
	end

	local segments = Map.Segments
	local cuts: { { number } } = {} -- per segment: the positions (0..1 along it) of its nodes
	for i = 1, #segments do
		cuts[i] = { 0, 1 }
	end
	type Link = { ax: number, az: number, bx: number, bz: number, kind: string }
	local links: { Link } = {}

	for i = 1, #segments do
		local s = segments[i]
		local rx, rz = s.bx - s.ax, s.bz - s.az
		for j = i + 1, #segments do
			-- Two roads crossing each other.
			local o = segments[j]
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
		-- The ends of this road meeting another road (T-junctions, connectors stopping at a grid's edge road).
		for _, endpoint in { { s.ax, s.az }, { s.bx, s.bz } } do
			local ex, ez = endpoint[1], endpoint[2]
			for j = 1, #segments do
				if j ~= i then
					local o = segments[j]
					local px, pz, d2, t = project(o.ax, o.az, o.bx, o.bz, ex, ez)
					local reach = o.width / 2 + LINK_SLACK
					if d2 <= reach * reach then
						table.insert(cuts[j], t)
						if d2 > 0.25 then
							table.insert(links, { ax = ex, az = ez, bx = px, bz = pz, kind = o.kind })
						end
					end
				end
			end
		end
	end

	for i = 1, #segments do
		local s = segments[i]
		local list = cuts[i]
		table.sort(list)
		local previous: number? = nil
		for _, t in list do
			local n = node(s.ax + (s.bx - s.ax) * t, s.az + (s.bz - s.az) * t)
			if previous then
				edge(previous, n, s.kind)
			end
			previous = n
		end
	end
	for _, link in links do
		edge(node(link.ax, link.az), node(link.bx, link.bz), link.kind)
	end
	return g
end

-- The road graph (built on the first call).
local function graph(): Graph
	local g = cached
	if g then
		return g
	end
	local built = build()
	cached = built
	return built
end

function Roads.stats(): (number, number)
	local g = graph()
	return #g.x, #g.edgeA
end

-- The closest point on any road: the edge and the point.
local function snap(g: Graph, x: number, z: number): (number, number, number)
	local best, bestX, bestZ, bestD = 0, x, z, INF
	for e = 1, #g.edgeA do
		local a, b = g.edgeA[e], g.edgeB[e]
		local px, pz, d2 = project(g.x[a], g.z[a], g.x[b], g.z[b], x, z)
		if d2 < bestD then
			best, bestX, bestZ, bestD = e, px, pz, d2
		end
	end
	return best, bestX, bestZ
end

-- Drops repeated points and points in the middle of a straight line.
local function simplify(points: { Point }): { Point }
	local out: { Point } = {}
	for _, p in points do
		local n = #out
		if n == 0 then
			table.insert(out, p)
			continue
		end
		local last: Point = out[n]
		if (p.x - last.x) ^ 2 + (p.z - last.z) ^ 2 < 0.25 then
			continue
		end
		if n >= 2 then
			local a: Point = out[n - 1]
			local ux, uz = last.x - a.x, last.z - a.z
			local vx, vz = p.x - last.x, p.z - last.z
			local cross = ux * vz - uz * vx
			local dot = ux * vx + uz * vz
			local lengths = math.sqrt((ux * ux + uz * uz) * (vx * vx + vz * vz))
			if dot > 0 and math.abs(cross) <= 0.005 * lengths then
				out[n] = p -- `last` was on the straight line from a to p
				continue
			end
		end
		table.insert(out, p)
	end
	return out
end

-- Scratch arrays for the search, reused between calls (a stamp tells this call's entries from older ones). The
-- search runs over states "arrived at a node along a directed edge", so a turn can cost extra; the two states past
-- the last directed edge are the first moves from the start point onto the road.
local gScore: { number } = {}
local cameFrom: { number } = {}
local stamp: { number } = {}
local closed: { number } = {}
local search = 0
local heapF: { number } = {}
local heapN: { number } = {}

local function push(size: number, f: number, n: number): number
	size += 1
	local i = size
	while i > 1 do
		local parent = i // 2
		if heapF[parent] <= f then
			break
		end
		heapF[i], heapN[i] = heapF[parent], heapN[parent]
		i = parent
	end
	heapF[i], heapN[i] = f, n
	return size
end

local function pop(size: number): (number, number, number)
	local f, n = heapF[1], heapN[1]
	local lastF, lastN = heapF[size], heapN[size]
	size -= 1
	local i = 1
	while true do
		local child = i * 2
		if child > size then
			break
		end
		if child < size and heapF[child + 1] < heapF[child] then
			child += 1
		end
		if heapF[child] >= lastF then
			break
		end
		heapF[i], heapN[i] = heapF[child], heapN[child]
		i = child
	end
	if size >= 1 then
		heapF[i], heapN[i] = lastF, lastN
	end
	return size, f, n
end

-- The drive from (fromX, fromZ) to (toX, toZ) along the roads: points from where you are to the target (the last
-- bits off the road are straight lines). Just the two ends if there is no way.
function Roads.route(fromX: number, fromZ: number, toX: number, toZ: number): { Point }
	local g = graph()
	if #g.edgeA == 0 then
		return { { x = fromX, z = fromZ }, { x = toX, z = toZ } }
	end
	local startEdge, sx, sz = snap(g, fromX, fromZ)
	local goalEdge, tx, tz = snap(g, toX, toZ)

	-- Both on the same piece of road: straight along it (the search below may still find nothing shorter).
	local best = if startEdge == goalEdge then math.sqrt((sx - tx) ^ 2 + (sz - tz) ^ 2) else INF
	local bestState = 0

	search += 1
	local current = search
	local size = 0
	local edges = #g.dirTo
	local stateNode: { number } = {} -- the node of the two start states (the others: dirTo)
	local stateX: { number } = {}
	local stateZ: { number } = {}
	local function nodeOf(state: number): number
		return if state > edges then stateNode[state - edges] else g.dirTo[state]
	end
	local function open(state: number, cost: number, from: number)
		if stamp[state] ~= current or cost < gScore[state] then
			stamp[state] = current
			gScore[state] = cost
			cameFrom[state] = from
			local n = nodeOf(state)
			size = push(size, cost + math.sqrt((g.x[n] - tx) ^ 2 + (g.z[n] - tz) ^ 2), state)
		end
	end
	for k, n in { g.edgeA[startEdge], g.edgeB[startEdge] } do
		local dx, dz = g.x[n] - sx, g.z[n] - sz
		local length = math.sqrt(dx * dx + dz * dz)
		stateNode[k] = n
		stateX[k] = if length > 0 then dx / length else 0
		stateZ[k] = if length > 0 then dz / length else 0
		open(edges + k, length, 0)
	end
	local goalA, goalB = g.edgeA[goalEdge], g.edgeB[goalEdge]

	while size > 0 do
		local f, state
		size, f, state = pop(size)
		if f >= best then
			break
		end
		if closed[state] == current then
			continue
		end
		closed[state] = current
		local cost = gScore[state]
		local n = nodeOf(state)
		if n == goalA or n == goalB then
			local total = cost + math.sqrt((g.x[n] - tx) ^ 2 + (g.z[n] - tz) ^ 2)
			if total < best then
				best, bestState = total, state
			end
		end
		local inX = if state > edges then stateX[state - edges] else g.dirX[state]
		local inZ = if state > edges then stateZ[state - edges] else g.dirZ[state]
		for _, d in g.out[n] do
			if closed[d] ~= current then
				local straight = inX * g.dirX[d] + inZ * g.dirZ[d]
				open(d, cost + g.dirLen[d] + (if straight < 0.95 then TURN_COST else 0), state)
			end
		end
	end

	local points: { Point } = { { x = fromX, z = fromZ }, { x = sx, z = sz } }
	if bestState ~= 0 then
		local chain: { number } = {}
		local state = bestState
		while state ~= 0 do
			table.insert(chain, nodeOf(state))
			state = cameFrom[state]
		end
		for k = #chain, 1, -1 do
			table.insert(points, { x = g.x[chain[k]], z = g.z[chain[k]] })
		end
	elseif best == INF then
		return { { x = fromX, z = fromZ }, { x = toX, z = toZ } }
	end
	table.insert(points, { x = tx, z = tz })
	table.insert(points, { x = toX, z = toZ })
	return simplify(points)
end

-- The length of a polyline.
function Roads.length(points: { Point }): number
	local total = 0
	for k = 2, #points do
		total += math.sqrt((points[k].x - points[k - 1].x) ^ 2 + (points[k].z - points[k - 1].z) ^ 2)
	end
	return total
end

-- The closest point on a polyline to (x, z), looking from step `first` on (step k = points k to k + 1):
-- the step, the point and the distance.
function Roads.closest(points: { Point }, x: number, z: number, first: number?): (number, number, number, number)
	local bestK, bestX, bestZ, bestD = math.max(first or 1, 1), x, z, INF
	for k = math.max(first or 1, 1), #points - 1 do
		local p, q = points[k], points[k + 1]
		local px, pz, d2 = project(p.x, p.z, q.x, q.z, x, z)
		if d2 < bestD then
			bestK, bestX, bestZ, bestD = k, px, pz, d2
		end
	end
	if bestD == INF then
		local p = points[#points]
		return #points, p.x, p.z, math.sqrt((p.x - x) ^ 2 + (p.z - z) ^ 2)
	end
	return bestK, bestX, bestZ, math.sqrt(bestD)
end

return Roads
