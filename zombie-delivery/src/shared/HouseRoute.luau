--!strict
-- 9.0 Danny's way inside a house (the owner, 8.9: "Danny can't walk around things logically. He goes to take things
-- through the wall: he can't get to the thing, he got stuck on the wall because he can't walk around it"). Pure (no
-- Roblox at its top level: tests/houseroute_test.luau runs it in the standalone Luau on the real plans), the numbers
-- Config.MoveHelper.Route's.
-- The cause it answers (tests/houseroute_test.luau measures it): server/MoveHelper.luau aimed him at a point straight
-- out of the piece toward where he came in (half its size and a stud and a half), whatever stood between: in the real
-- plans a fifth of the pieces had a wall between that point and the piece (the point in the next room, in the wall
-- itself, out of the house), a third had it within the pathfinding's agent radius of a wall (no path: he walked the
-- straight line into the wall, and the stuck nudge put him on along it), and his take only asked how far the piece's
-- middle was (from the next room it was near enough: a take through the wall).
-- Now a house's plan (shared/HouseLayout.luau: its walls as slabs, cut at the doorways, its solid fixtures) is laid on
-- a grid of Route.Step studs. A cell is open when his body (Route.Radius) fits there: that far from every wall slab,
-- every solid fixture and every piece standing in the house (HouseRoute.block, again whenever they change). His way is
-- an A* path over the open cells (eight neighbours, never a corner cut), pulled straight where a straight line stays on
-- open cells: its corners only, every leg on open cells, so it goes through the doorways and round the furniture and
-- never into a wall. The spot he takes a piece from (HouseRoute.reach) is the nearest open cell by his way within
-- Route.Stand studs of its footprint (arm's length, on its near side) whose line to its middle crosses no wall; none:
-- he can't get to it (the server refuses it). Positions are the plan's own (local to its origin, X and Z along the
-- floor); a Rect is { x0, z0, x1, z1 }.
--
--   HouseRoute.grid(plan, radius?, step?)   the plan's grid (its walls and solid fixtures; every cell open until
--                                         HouseRoute.block), nil for a plan without walls (a test's fake)
--   HouseRoute.block(grid, pieces)        the pieces standing now ({ Rect }): every cell they leave his body no room in
--                                         is closed, the rest open again; returns the open cells' count
--   HouseRoute.open(grid, x, z)           is (x, z) on an open cell
--   HouseRoute.path(grid, fx, fz, tx, tz)   his way from (fx, fz) to (tx, tz): its points after the start ({ { x, z } },
--                                         the last one the goal's nearest open cell within Route.Snap; a start off
--                                         the open cells steps onto the nearest one first); nil: no way
--   HouseRoute.reach(grid, fx, fz, piece, stand?, avoid?)   where he stands to take `piece` (its footprint): (x, z,
--                                         studs on foot) or nil (no such spot he can walk to); `avoid`: rects he never
--                                         stands in (the doorways, where he would wait in your way)
--   HouseRoute.sees(grid, ax, az, bx, bz)   does the line cross no wall slab (the doorways' gaps are open)
--   HouseRoute.clear(grid, ax, az, bx, bz)  does the line keep to open cells (a leg he can walk)
--   HouseRoute.snap(grid, x, z, far?)     the nearest open cell's middle within `far` studs (Route.Snap): (x, z) or nil
--   HouseRoute.inside(grid, x, z)         is (x, z) in a room or a doorway (not in a wall, not out of the house)
--   HouseRoute.footprint(cx, cz, sx, sz, yaw)   a box sx × sz turned by `yaw` (radians about Y) at (cx, cz): the
--                                         Rect round it
--   HouseRoute.toRect(x, z, piece)        studs from (x, z) to a Rect (0 inside it)

local Config = require(script.Parent.Config)

local HouseRoute = {}

export type Rect = { x0: number, z0: number, x1: number, z1: number }
export type Point = { x: number, z: number }
export type Grid = {
	x0: number, -- the first cell's middle
	z0: number,
	nx: number,
	nz: number,
	step: number,
	radius: number,
	walls: { Rect }, -- the wall slabs (not the headers over the doorways): the sight lines'
	rooms: { Rect }, -- the rooms' clear insides and the doorways' openings (HouseRoute.inside)
	still: { number }, -- per cell: 1 when his body fits there by the walls and the fixtures alone, else 0
	open: { number }, -- per cell: 1 open now (still, and no piece within his radius), else 0
	-- (a search's scratch, kept: the stamp marks the cells this search has seen)
	stamp: number,
	seen: { number },
	shut: { number },
	cost: { number },
	from: { number },
	heap: { number },
	keys: { number },
}

local CAP = 6 -- studs: a wall or a fixture farther than this from a cell never matters to it

local function cfg(): any
	return (Config :: any).MoveHelper.Route
end

local function rect(x0: number, z0: number, x1: number, z1: number): Rect
	return { x0 = math.min(x0, x1), z0 = math.min(z0, z1), x1 = math.max(x0, x1), z1 = math.max(z0, z1) }
end

local function toRect(x: number, z: number, r: Rect): number
	local dx = math.max(r.x0 - x, 0, x - r.x1)
	local dz = math.max(r.z0 - z, 0, z - r.z1)
	return math.sqrt(dx * dx + dz * dz)
end
HouseRoute.toRect = toRect

function HouseRoute.footprint(cx: number, cz: number, sx: number, sz: number, yaw: number): Rect
	local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	local hx = (sx * c + sz * s) / 2
	local hz = (sx * s + sz * c) / 2
	return rect(cx - hx, cz - hz, cx + hx, cz + hz)
end

-- Does the segment (ax, az) → (bx, bz) cross the inside of the rect (Liang-Barsky: a piece of it left inside)?
local function cuts(ax: number, az: number, bx: number, bz: number, r: Rect): boolean
	local dx, dz = bx - ax, bz - az
	local t0, t1 = 0, 1
	local ps = { -dx, dx, -dz, dz }
	local qs = { ax - r.x0, r.x1 - ax, az - r.z0, r.z1 - az }
	for k = 1, 4 do
		local p, q = ps[k], qs[k]
		if math.abs(p) < 1e-12 then
			if q <= 0 then
				return false
			end
		else
			local t = q / p
			if p < 0 then
				t0 = math.max(t0, t)
			else
				t1 = math.min(t1, t)
			end
			if t0 >= t1 then
				return false
			end
		end
	end
	return t1 - t0 > 1e-9
end
HouseRoute.cuts = cuts

-- (the plan's turn of a fixture: its footprint along X and Z)
local function fixtureRect(f: any): Rect
	local turn = ((tonumber(f.turn) or 0) % 360 + 360) % 360
	local size: any = f.size
	local ex = if turn % 180 == 0 then size.X else size.Z
	local ez = if turn % 180 == 0 then size.Z else size.X
	local p: any = f.at.Position
	return rect(p.X - ex / 2, p.Z - ez / 2, p.X + ex / 2, p.Z + ez / 2)
end

-- Every cell's studs to the nearest of `list` (CAP at most) into `into` (min with what is there).
local function spread(g: Grid, list: { Rect }, into: { number })
	local step, nx, nz = g.step, g.nx, g.nz
	for _, r in list do
		local i0 = math.max(0, math.floor((r.x0 - CAP - g.x0) / step))
		local i1 = math.min(nx - 1, math.ceil((r.x1 + CAP - g.x0) / step))
		local j0 = math.max(0, math.floor((r.z0 - CAP - g.z0) / step))
		local j1 = math.min(nz - 1, math.ceil((r.z1 + CAP - g.z0) / step))
		for j = j0, j1 do
			local z = g.z0 + j * step
			for i = i0, i1 do
				local k = j * nx + i + 1
				local d = toRect(g.x0 + i * step, z, r)
				if d < into[k] then
					into[k] = d
				end
			end
		end
	end
end

function HouseRoute.grid(plan: any, radius: number?, step: number?): Grid?
	local faces = plan and plan.faces
	if type(faces) ~= "table" or #faces == 0 or plan.min == nil or plan.max == nil then
		return nil
	end
	local c = cfg()
	local cell = step or c.Step
	local walls: { Rect } = {}
	for _, f in faces do
		if not f.header then
			table.insert(walls, rect(f.min.X, f.min.Z, f.max.X, f.max.Z))
		end
	end
	local solids: { Rect } = {}
	for _, f in (plan.fixtures or {}) :: { any } do
		if f.solid then
			table.insert(solids, fixtureRect(f))
		end
	end
	local rooms: { Rect } = {}
	for _, room in (plan.rooms or {}) :: { any } do
		table.insert(rooms, rect(room.min.X, room.min.Z, room.max.X, room.max.Z))
	end
	local half = (tonumber(plan.wall) or 1) / 2
	for _, door in (plan.doors or {}) :: { any } do
		local w = (tonumber(door.width) or 4) / 2
		local at: any = door.at
		table.insert(rooms, if door.axis == "X" then rect(at.X - w, at.Z - half, at.X + w, at.Z + half) else rect(at.X - half, at.Z - w, at.X + half, at.Z + w))
	end
	local x0 = plan.min.X + cell / 2
	local z0 = plan.min.Z + cell / 2
	local nx = math.max(1, math.floor((plan.max.X - plan.min.X) / cell))
	local nz = math.max(1, math.floor((plan.max.Z - plan.min.Z) / cell))
	local n = nx * nz
	local g: Grid = {
		x0 = x0,
		z0 = z0,
		nx = nx,
		nz = nz,
		step = cell,
		radius = radius or c.Radius,
		walls = walls,
		rooms = rooms,
		still = table.create(n, 0),
		open = table.create(n, 0),
		stamp = 0,
		seen = table.create(n, 0),
		shut = table.create(n, 0),
		cost = table.create(n, 0),
		from = table.create(n, 0),
		heap = {},
		keys = {},
	}
	local near = table.create(n, CAP)
	spread(g, walls, near)
	spread(g, solids, near)
	for k = 1, n do
		local i, j = (k - 1) % nx, (k - 1) // nx
		local fits = near[k] >= g.radius
		if fits then
			fits = HouseRoute.inside(g, x0 + i * cell, z0 + j * cell) -- (never out of the house, never in a wall's gap)
		end
		g.still[k] = if fits then 1 else 0
		g.open[k] = g.still[k]
	end
	return g
end

function HouseRoute.inside(g: Grid, x: number, z: number): boolean
	for _, r in g.rooms do
		if x >= r.x0 - 1e-6 and x <= r.x1 + 1e-6 and z >= r.z0 - 1e-6 and z <= r.z1 + 1e-6 then
			return true
		end
	end
	return false
end

function HouseRoute.block(g: Grid, pieces: { Rect }): number
	local open, still = g.open, g.still
	table.move(still, 1, #still, 1, open)
	local step, nx, nz, r = g.step, g.nx, g.nz, g.radius
	for _, p in pieces do
		local i0 = math.max(0, math.floor((p.x0 - r - g.x0) / step))
		local i1 = math.min(nx - 1, math.ceil((p.x1 + r - g.x0) / step))
		local j0 = math.max(0, math.floor((p.z0 - r - g.z0) / step))
		local j1 = math.min(nz - 1, math.ceil((p.z1 + r - g.z0) / step))
		for j = j0, j1 do
			local z = g.z0 + j * step
			for i = i0, i1 do
				local k = j * nx + i + 1
				if open[k] == 1 and toRect(g.x0 + i * step, z, p) < r then
					open[k] = 0
				end
			end
		end
	end
	local count = 0
	for k = 1, #open do
		count += open[k]
	end
	return count
end

-- The cell under (x, z) (0: off the grid).
local function cellAt(g: Grid, x: number, z: number): number
	local i = math.floor((x - g.x0) / g.step + 0.5)
	local j = math.floor((z - g.z0) / g.step + 0.5)
	if i < 0 or j < 0 or i >= g.nx or j >= g.nz then
		return 0
	end
	return j * g.nx + i + 1
end

local function middle(g: Grid, k: number): (number, number)
	local i, j = (k - 1) % g.nx, (k - 1) // g.nx
	return g.x0 + i * g.step, g.z0 + j * g.step
end

function HouseRoute.open(g: Grid, x: number, z: number): boolean
	local k = cellAt(g, x, z)
	return k > 0 and g.open[k] == 1
end

function HouseRoute.sees(g: Grid, ax: number, az: number, bx: number, bz: number): boolean
	for _, w in g.walls do
		if cuts(ax, az, bx, bz, w) then
			return false
		end
	end
	return true
end

function HouseRoute.clear(g: Grid, ax: number, az: number, bx: number, bz: number): boolean
	local dx, dz = bx - ax, bz - az
	local length = math.sqrt(dx * dx + dz * dz)
	local samples = math.max(1, math.ceil(length / (g.step / 3)))
	for s = 0, samples do
		local t = s / samples
		local k = cellAt(g, ax + dx * t, az + dz * t)
		if k == 0 or g.open[k] ~= 1 then
			return false
		end
	end
	return true
end

-- ── The searches ─────────────────────────────────────────────────────────────

-- A binary heap of cells by their key (the scratch's heap and keys).
local function push(g: Grid, k: number, key: number)
	local heap, keys = g.heap, g.keys
	local n = #heap + 1
	heap[n], keys[n] = k, key
	while n > 1 do
		local up = n // 2
		if keys[up] <= keys[n] then
			break
		end
		heap[up], heap[n] = heap[n], heap[up]
		keys[up], keys[n] = keys[n], keys[up]
		n = up
	end
end

local function pop(g: Grid): number
	local heap, keys = g.heap, g.keys
	local top = heap[1]
	local n = #heap
	heap[1], keys[1] = heap[n], keys[n]
	heap[n], keys[n] = nil, nil
	n -= 1
	local at = 1
	while true do
		local l, r = at * 2, at * 2 + 1
		local small = at
		if l <= n and keys[l] < keys[small] then
			small = l
		end
		if r <= n and keys[r] < keys[small] then
			small = r
		end
		if small == at then
			break
		end
		heap[at], heap[small] = heap[small], heap[at]
		keys[at], keys[small] = keys[small], keys[at]
		at = small
	end
	return top
end

local DI = { 1, -1, 0, 0, 1, 1, -1, -1 }
local DJ = { 0, 0, 1, -1, 1, -1, 1, -1 }
local DIAGONAL = math.sqrt(2)

-- The nearest open cell to (x, z) within `far` studs (a breadth-first look over every cell): its index, 0 for none.
local function nearestOpen(g: Grid, x: number, z: number, far: number): number
	local start = cellAt(g, x, z)
	if start > 0 and g.open[start] == 1 then
		return start
	end
	-- (off the grid: the cell nearest it on the grid's edge)
	if start == 0 then
		local i = math.clamp(math.floor((x - g.x0) / g.step + 0.5), 0, g.nx - 1)
		local j = math.clamp(math.floor((z - g.z0) / g.step + 0.5), 0, g.nz - 1)
		start = j * g.nx + i + 1
	end
	local best, bestD = 0, math.huge
	local cells = math.ceil(far / g.step)
	local si, sj = (start - 1) % g.nx, (start - 1) // g.nx
	for j = math.max(0, sj - cells), math.min(g.nz - 1, sj + cells) do
		for i = math.max(0, si - cells), math.min(g.nx - 1, si + cells) do
			local k = j * g.nx + i + 1
			if g.open[k] == 1 then
				local cx, cz = middle(g, k)
				local d = (cx - x) * (cx - x) + (cz - z) * (cz - z)
				if d < bestD then
					best, bestD = k, d
				end
			end
		end
	end
	return if bestD <= far * far then best else 0
end

function HouseRoute.snap(g: Grid, x: number, z: number, far: number?): (number?, number?)
	local k = nearestOpen(g, x, z, far or cfg().Snap)
	if k == 0 then
		return nil, nil
	end
	return middle(g, k)
end

-- The search over the open cells from `start` (A*: `guess(k)` never more than the cost from k to the end) until
-- `done(k)` says a cell is the end: that cell (0: none) and its cost. The cells' `from` lead back to the start.
local function search(g: Grid, start: number, guess: (number) -> number, done: (number) -> boolean): (number, number)
	g.stamp += 1
	local stamp = g.stamp
	table.clear(g.heap)
	table.clear(g.keys)
	local seen, shut, cost, from, open = g.seen, g.shut, g.cost, g.from, g.open
	local nx, nz, step = g.nx, g.nz, g.step
	seen[start], cost[start], from[start] = stamp, 0, 0
	push(g, start, guess(start))
	while #g.heap > 0 do
		local k = pop(g)
		if shut[k] == stamp then
			continue
		end
		shut[k] = stamp
		if done(k) then
			return k, cost[k]
		end
		local i, j = (k - 1) % nx, (k - 1) // nx
		for d = 1, 8 do
			local ni, nj = i + DI[d], j + DJ[d]
			if ni < 0 or nj < 0 or ni >= nx or nj >= nz then
				continue
			end
			local nk = nj * nx + ni + 1
			if open[nk] ~= 1 or shut[nk] == stamp then
				continue
			end
			if d > 4 and (open[j * nx + ni + 1] ~= 1 or open[nj * nx + i + 1] ~= 1) then
				continue -- (never a corner cut: both sides of a diagonal open)
			end
			local c = cost[k] + (if d > 4 then DIAGONAL else 1) * step
			if seen[nk] ~= stamp or c < cost[nk] - 1e-9 then
				seen[nk], cost[nk], from[nk] = stamp, c, k
				push(g, nk, c + guess(nk))
			end
		end
	end
	return 0, math.huge
end

-- The cells from the start to `k` (the start left out), pulled straight: only the corners where a straight leg along
-- open cells has to turn, the last one `k` itself. (Its turns first: a run of cells one way is one leg already.)
local function pulled(g: Grid, k: number): { Point }
	local cells: { number } = {}
	while k ~= 0 do
		table.insert(cells, k)
		k = g.from[k]
	end
	local turns: { number } = { cells[#cells] }
	for n = #cells - 1, 2, -1 do
		if cells[n + 1] - cells[n] ~= cells[n] - cells[n - 1] then
			table.insert(turns, cells[n])
		end
	end
	if #cells > 1 then
		table.insert(turns, cells[1])
	end
	local out: { Point } = {}
	local anchor = 1
	while anchor < #turns do
		local ax, az = middle(g, turns[anchor])
		local reach = anchor + 1
		for n = anchor + 2, #turns do
			local bx, bz = middle(g, turns[n])
			if not HouseRoute.clear(g, ax, az, bx, bz) then
				break
			end
			reach = n
		end
		local x, z = middle(g, turns[reach])
		table.insert(out, { x = x, z = z })
		anchor = reach
	end
	return out
end

-- The octile distance between two cells (studs): the A* guess toward one cell.
local function octile(g: Grid, a: number, b: number): number
	local di = math.abs((a - 1) % g.nx - (b - 1) % g.nx)
	local dj = math.abs((a - 1) // g.nx - (b - 1) // g.nx)
	return (math.max(di, dj) + (DIAGONAL - 1) * math.min(di, dj)) * g.step
end

function HouseRoute.path(g: Grid, fx: number, fz: number, tx: number, tz: number): { Point }?
	local snap = cfg().Snap
	local start = nearestOpen(g, fx, fz, snap)
	local goal = nearestOpen(g, tx, tz, snap)
	if start == 0 or goal == 0 then
		return nil
	end
	local found = search(g, start, function(k: number): number
		return octile(g, k, goal)
	end, function(k: number): boolean
		return k == goal
	end)
	if found == 0 then
		return nil
	end
	local points = pulled(g, found)
	local sx, sz = middle(g, start)
	if (sx - fx) * (sx - fx) + (sz - fz) * (sz - fz) > (g.step * 0.75) ^ 2 or #points == 0 then
		table.insert(points, 1, { x = sx, z = sz }) -- (off the open cells: onto the nearest one first)
	end
	return points
end

function HouseRoute.reach(g: Grid, fx: number, fz: number, piece: Rect, stand: number?, avoid: { Rect }?): (number?, number?, number?)
	local far = stand or cfg().Stand
	local start = nearestOpen(g, fx, fz, cfg().Snap)
	if start == 0 then
		return nil, nil, nil
	end
	local mx, mz = (piece.x0 + piece.x1) / 2, (piece.z0 + piece.z1) / 2
	local found, cost = search(g, start, function(k: number): number
		local x, z = middle(g, k)
		return math.max(0, toRect(x, z, piece) - far) -- (never more than the way to a cell within `far` of it)
	end, function(k: number): boolean
		local x, z = middle(g, k)
		if toRect(x, z, piece) > far then
			return false
		end
		for _, r in avoid or {} do
			if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
				return false
			end
		end
		return HouseRoute.sees(g, x, z, mx, mz)
	end)
	if found == 0 then
		return nil, nil, nil
	end
	local x, z = middle(g, found)
	return x, z, cost
end

return HouseRoute
