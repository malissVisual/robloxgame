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
--   HouseRoute.path(grid, fx, fz, tx, tz, far?)   his way from (fx, fz) to (tx, tz): its points after the start
--                                         ({ { x, z } }, the last one the goal's nearest open cell within `far` studs,
--                                         Route.Snap by default; a start off the open cells steps onto the nearest one
--                                         first; 9.5 so does one whose first leg from where he stands would come
--                                         nearer than the grid's `clear` to anything); nil: no way
--   HouseRoute.reach(grid, fx, fz, piece, stand?, avoid?)   where he stands to take `piece` (its footprint): (x, z,
--                                         studs on foot) or nil (no such spot he can walk to); `avoid`: rects he never
--                                         stands in (the doorways, where he would wait in your way)
--   HouseRoute.sees(grid, ax, az, bx, bz)   does the line cross no wall slab (the doorways' gaps are open)
--   HouseRoute.clear(grid, ax, az, bx, bz)  does the line keep to open cells (a leg he can walk)
--   HouseRoute.slide(grid, fx, fz, tx, tz, clear)   9.0 the far end's holder from (fx, fz) toward (tx, tz), his body
--                                         `clear` studs off the wall slabs, along them, never through: (x, z, nx, nz),
--                                         where he gets to and the way out of the last slab that held him (0, 0: none)
--   HouseRoute.snap(grid, x, z, far?)     the nearest open cell's middle within `far` studs (Route.Snap): (x, z) or nil
--   HouseRoute.inside(grid, x, z)         is (x, z) in a room or a doorway (not in a wall, not out of the house)
--   HouseRoute.footprint(cx, cz, sx, sz, yaw)   a box sx × sz turned by `yaw` (radians about Y) at (cx, cz): the
--                                         Rect round it
--   HouseRoute.toRect(x, z, piece)        studs from (x, z) to a Rect (0 inside it)
-- 9.3 (the owner, 8.9.5: "Danny still annoys me. He takes it completely like a robot. He runs for 2 seconds and then on
-- the spot he somehow teleports around"; tests/movehelper_stuck_runtime_test.luau sweeps his body along his ways in the
-- six real houses, their built parts): the grid's ways kept 1.09 studs off every wall at least, but his walk turned to
-- the next corner a stud before it, cutting it: 1,130 swept steps within his body's half width (1 stud) of a wall's
-- end, 0.35 studs at the closest, and from there the next leg ran into that wall's end (blocked, a stuck spell, the
-- nudge on the spot). Now his walk is aimed at a point a few studs ahead along his way whose straight line from him
-- keeps a clearance off everything, measured exactly (HouseRoute.ahead), and the grid knows the built interior's parts
-- the plan does not (HouseRoute.solid: a garage door's leaf):
--   HouseRoute.grid(plan, radius?, step?, clear?)   `clear`: the studs his legs keep off the walls, the solids and the
--                                         pieces exactly (each leg of a way pulled straight only that far off them; his
--                                         body's half diagonal and a margin, Config.MoveHelper.Walk.Clear); nil: legs
--                                         on open cells only (8.9.5's)
--   HouseRoute.solid(grid, rects)         more obstacles that stay (the built interior's collidable parts in his body's
--                                         height: server/MoveHelper.luau reads them off its model): their cells closed
--                                         for good, kept for the exact clearance; returns the cells it closed
--   HouseRoute.gap(grid, ax, az, bx, bz)  studs from the segment to the nearest wall slab, solid or piece standing now
--                                         (exact; CAP at most)
--   HouseRoute.free(grid, ax, az, bx, bz, clear)   does the segment keep `clear` studs off them all (a leg his body walks
--                                         untouched)
--   HouseRoute.ahead(grid?, points, index, x, z, reach, clear, cut?)   where to aim him from (x, z) along his way
--                                         (`points` { { x, z } }, the next one points[index]): the farthest point of
--                                         the way within `reach` studs of walking whose straight line from him keeps
--                                         `clear` studs off everything (with a grid; never nearer than he is now) or cuts
--                                         the way's corners `cut` studs at most (no grid: the street's ways); (x, z,
--                                         the index of the next point still ahead, studs of way left from him)
-- 10.x danger (a run's locked doorways and its hazards, server/RunDanger.luau; tests/danger_test.luau):
--   HouseRoute.shut(grid, walls, floors, key)   what is shut on the grid now, all of it (a new call replaces the last
--                                         one's): `walls` count as wall slabs (a locked doorway's leaf: closed cells, no
--                                         sight through it, the slides stop at it), `floors` only close their cells (a
--                                         hazard he walks round); `key` names the set: the same key again does nothing.
--                                         Whatever was shut before and is not now opens again (a door unlocked). True
--                                         when it changed anything

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
	solids: { Rect }, -- 9.3 the solid fixtures and the built parts that stay (HouseRoute.solid): the exact clearance's
	pieces: { Rect }, -- 9.3 the pieces standing now (HouseRoute.block's)
	clear: number?, -- 9.3 the studs a leg keeps off them all exactly (nil: open cells only)
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

function HouseRoute.grid(plan: any, radius: number?, step: number?, clear: number?): Grid?
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
		solids = solids,
		pieces = {},
		clear = clear,
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
	g.pieces = pieces -- (9.3 the exact clearance's)
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

-- 9.3 more obstacles that stay (the built interior's parts): every cell his body has no room in by one of them closed
-- for good (still and open), the rects kept with the solids (the exact clearance). The cells it closed.
function HouseRoute.solid(g: Grid, rects: { Rect }): number
	local step, nx, nz, r = g.step, g.nx, g.nz, g.radius
	local closed = 0
	for _, p in rects do
		table.insert(g.solids, p)
		local i0 = math.max(0, math.floor((p.x0 - r - g.x0) / step))
		local i1 = math.min(nx - 1, math.ceil((p.x1 + r - g.x0) / step))
		local j0 = math.max(0, math.floor((p.z0 - r - g.z0) / step))
		local j1 = math.min(nz - 1, math.ceil((p.z1 + r - g.z0) / step))
		for j = j0, j1 do
			local z = g.z0 + j * step
			for i = i0, i1 do
				local k = j * nx + i + 1
				if g.still[k] == 1 and toRect(g.x0 + i * step, z, p) < r then
					g.still[k], g.open[k] = 0, 0
					closed += 1
				end
			end
		end
	end
	return closed
end

-- 9.3 studs from the point (px, pz) to the segment (ax, az)-(bx, bz).
local function toSegment(ax: number, az: number, bx: number, bz: number, px: number, pz: number): number
	local dx, dz = bx - ax, bz - az
	local l2 = dx * dx + dz * dz
	local t = if l2 > 1e-12 then math.clamp(((px - ax) * dx + (pz - az) * dz) / l2, 0, 1) else 0
	local qx, qz = ax + dx * t - px, az + dz * t - pz
	return math.sqrt(qx * qx + qz * qz)
end

-- 9.3 studs from a segment to a rect (0: it crosses it).
local function segmentToRect(ax: number, az: number, bx: number, bz: number, r: Rect): number
	if cuts(ax, az, bx, bz, r) then
		return 0
	end
	local least = math.min(toRect(ax, az, r), toRect(bx, bz, r))
	least = math.min(least, toSegment(ax, az, bx, bz, r.x0, r.z0), toSegment(ax, az, bx, bz, r.x1, r.z0))
	return math.min(least, toSegment(ax, az, bx, bz, r.x0, r.z1), toSegment(ax, az, bx, bz, r.x1, r.z1))
end

-- (the least of `least` and the segment's studs to the rects of `list` near it)
local function nearestOf(list: { Rect }, ax: number, az: number, bx: number, bz: number, least: number): number
	local x0, x1 = math.min(ax, bx) - least, math.max(ax, bx) + least
	local z0, z1 = math.min(az, bz) - least, math.max(az, bz) + least
	for _, r in list do
		if r.x1 < x0 or r.x0 > x1 or r.z1 < z0 or r.z0 > z1 then
			continue
		end
		local d = segmentToRect(ax, az, bx, bz, r)
		if d < least then
			least = d
			if d <= 0 then
				return 0
			end
		end
	end
	return least
end

function HouseRoute.gap(g: Grid, ax: number, az: number, bx: number, bz: number): number
	local least = nearestOf(g.walls, ax, az, bx, bz, CAP)
	if least > 0 then
		least = nearestOf(g.solids, ax, az, bx, bz, least)
	end
	if least > 0 then
		least = nearestOf(g.pieces, ax, az, bx, bz, least)
	end
	return least
end

function HouseRoute.free(g: Grid, ax: number, az: number, bx: number, bz: number, clear: number): boolean
	return HouseRoute.gap(g, ax, az, bx, bz) >= clear - 1e-6
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

-- 9.0 the far end's holder inside the house (server/MoveHelper.luau's hold: Danny walking backwards with your piece, the
-- owner: "When I want to walk forwards, Danny can't walk backwards"): from (fx, fz) toward (tx, tz) with his body `clear`
-- studs off every wall slab (each slab grown by it; the doorways' gaps open): the first slab the way meets stops it
-- there and the rest of the way slides along that slab's face, again for the next one (Slides passes at most). A start
-- already within `clear` of a slab moves out of it or along it, never deeper in. Returns where he gets to and the face's
-- way out of the last slab that held him (nx, nz: a unit along X or Z; 0, 0 when none did).
local SLIDES = 4
function HouseRoute.slide(g: Grid, fx: number, fz: number, tx: number, tz: number, clear: number): (number, number, number, number)
	local x, z = fx, fz
	local mx, mz = tx - fx, tz - fz
	local nx, nz = 0, 0
	local pad = math.max(clear, 0)
	for _ = 1, SLIDES do
		if mx * mx + mz * mz < 1e-12 then
			break
		end
		-- (a slab he stands within already: nothing of the way deeper into it, through its nearest face)
		for _, w in g.walls do
			local x0, x1, z0, z1 = w.x0 - pad, w.x1 + pad, w.z0 - pad, w.z1 + pad
			if x > x0 and x < x1 and z > z0 and z < z1 then
				local least = math.min(x - x0, x1 - x, z - z0, z1 - z)
				local ox, oz = 0, 0
				if least == x - x0 then
					ox = -1
				elseif least == x1 - x then
					ox = 1
				elseif least == z - z0 then
					oz = -1
				else
					oz = 1
				end
				local into = mx * ox + mz * oz
				if into < 0 then
					mx, mz = mx - ox * into, mz - oz * into
					nx, nz = ox, oz
				end
			end
		end
		-- (the first slab the way goes into: where, by which face)
		local first, fox, foz = 1, 0, 0
		for _, w in g.walls do
			local x0, x1, z0, z1 = w.x0 - pad, w.x1 + pad, w.z0 - pad, w.z1 + pad
			if not (x > x0 and x < x1 and z > z0 and z < z1) then
				local enter, leave, ox, oz = -math.huge, math.huge, 0, 0
				local blocked = false
				if math.abs(mx) < 1e-12 then
					blocked = x <= x0 or x >= x1
				else
					local a, b = (x0 - x) / mx, (x1 - x) / mx
					if a > b then
						a, b = b, a
					end
					if a > enter then
						enter, ox, oz = a, if mx > 0 then -1 else 1, 0
					end
					leave = math.min(leave, b)
				end
				if not blocked and math.abs(mz) < 1e-12 then
					blocked = z <= z0 or z >= z1
				elseif not blocked then
					local a, b = (z0 - z) / mz, (z1 - z) / mz
					if a > b then
						a, b = b, a
					end
					if a > enter then
						enter, ox, oz = a, 0, if mz > 0 then -1 else 1
					end
					leave = math.min(leave, b)
				end
				if not blocked and enter >= 0 and enter < leave and enter < first and (ox ~= 0 or oz ~= 0) then
					first, fox, foz = enter, ox, oz
				end
			end
		end
		if fox == 0 and foz == 0 then
			x, z = x + mx, z + mz
			break
		end
		x, z = x + mx * first + fox * 1e-4, z + mz * first + foz * 1e-4 -- (a hair off its face)
		local restX, restZ = mx * (1 - first), mz * (1 - first)
		local into = restX * fox + restZ * foz
		mx, mz = restX - fox * into, restZ - foz * into
		nx, nz = fox, foz
	end
	return x, z, nx, nz
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
-- open cells has to turn, the last one `k` itself. (Its turns first: a run of cells one way is one leg already.) 9.3 a
-- grid with `clear`: a leg also keeps that many studs off every wall, solid and piece exactly (the open cells alone let
-- a leg pass a cell's half diagonal nearer than the radius).
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
	local clear = g.clear
	while anchor < #turns do
		local ax, az = middle(g, turns[anchor])
		local reach = anchor + 1
		for n = anchor + 2, #turns do
			local bx, bz = middle(g, turns[n])
			if not HouseRoute.clear(g, ax, az, bx, bz) or (clear and not HouseRoute.free(g, ax, az, bx, bz, clear)) then
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

function HouseRoute.path(g: Grid, fx: number, fz: number, tx: number, tz: number, far: number?): { Point }?
	local snap = cfg().Snap
	local start = nearestOpen(g, fx, fz, snap)
	local goal = nearestOpen(g, tx, tz, far or snap)
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
	local here = cellAt(g, fx, fz)
	local clear = g.clear
	if (sx - fx) * (sx - fx) + (sz - fz) * (sz - fz) > (g.step * 0.75) ^ 2 or #points == 0 or here == 0 or g.open[here] ~= 1
		or (clear and not HouseRoute.free(g, fx, fz, points[1].x, points[1].z, clear)) then
		-- (off the open cells: onto the nearest one first; 9.3 even a hair off them: a corner cut by his walk, the first
		-- leg from there along a wall's end would run into it; 9.5 and whenever the first leg from where he really
		-- stands comes nearer than `clear` to anything: the way was pulled straight from his cell's middle, and he may
		-- stand up to its half diagonal off it: The Forest Lodge's leg from where the door puts him, pulled past a
		-- doorway's jamb 1.25 off from the middle, passed it 1.09 off from him)
		table.insert(points, 1, { x = sx, z = sz })
	end
	return points
end

-- 9.3 where to aim him along his way (see the header): the corners already behind him dropped (one he can see past
-- with the clearance, or within `pass` studs of him), then the way's point `reach` studs of walking ahead, drawn back
-- toward him until his straight line to it is clear (a grid: `clear` studs off everything, never nearer to anything
-- than he is now; else its corners cut `cut` studs at most). (x, z, index of the next point, studs of way left).
local PASS = 0.6
function HouseRoute.ahead(g: Grid?, points: { Point }, index: number, x: number, z: number, reach: number, clear: number, cut: number?): (number, number, number, number)
	local n = #points
	if n == 0 then
		return x, z, 1, 0
	end
	index = math.clamp(index, 1, n)
	local need = clear
	if g then
		need = math.min(clear, HouseRoute.gap(g, x, z, x, z) - 1e-3) -- (never nearer than he is: off the margin, out of it)
	end
	local function sees(px: number, pz: number): boolean
		if g then
			return HouseRoute.gap(g, x, z, px, pz) >= need
		end
		return true
	end
	-- the corners behind him (with a grid: only once he sees past one with the clearance; a corner he came within PASS
	-- of but can't see past yet is still his way: dropped, his straight line at the next one ran into its wall's end;
	-- without one: within PASS of it, or as near the next point as it is: passed between two looks, never walked back to)
	while index < n do
		local p, q = points[index], points[index + 1]
		local dx, dz = p.x - x, p.z - z
		local passed = dx * dx + dz * dz < PASS * PASS or (q.x - x) ^ 2 + (q.z - z) ^ 2 <= (q.x - p.x) ^ 2 + (q.z - p.z) ^ 2
		if (g ~= nil and sees(q.x, q.z)) or (g == nil and passed) then
			index += 1
		else
			break
		end
	end
	-- the way from him: (x, z) → points[index] → …, its length left and the candidates along it every half stud
	local left = 0
	do
		local ax, az = x, z
		for k = index, n do
			local p = points[k]
			left += math.sqrt((p.x - ax) ^ 2 + (p.z - az) ^ 2)
			ax, az = p.x, p.z
		end
	end
	local function along(d: number): (number, number, number)
		local ax, az = x, z
		for k = index, n do
			local p = points[k]
			local l = math.sqrt((p.x - ax) ^ 2 + (p.z - az) ^ 2)
			if d <= l then
				local t = if l > 1e-9 then d / l else 0
				return ax + (p.x - ax) * t, az + (p.z - az) * t, k
			end
			d -= l
			ax, az = p.x, p.z
		end
		return points[n].x, points[n].z, n
	end
	-- (the corners it cuts: the way's points between him and the candidate, each that many studs off his line at most)
	local function cutsCorner(px: number, pz: number, upto: number): boolean
		if not cut then
			return false
		end
		for k = index, upto - 1 do
			local p = points[k]
			if toSegment(x, z, px, pz, p.x, p.z) > cut then
				return true
			end
		end
		return false
	end
	local d = math.min(reach, left)
	local bx, bz, best = points[index].x, points[index].z, -math.huge
	while d > 1e-6 do
		local px, pz, k = along(d)
		if sees(px, pz) and not cutsCorner(px, pz, k) then
			return px, pz, index, left
		end
		if g then
			local gap = HouseRoute.gap(g, x, z, px, pz)
			if gap > best + 1e-6 then
				bx, bz, best = px, pz, gap
			end
		end
		d -= 0.5
	end
	-- (none clear: the one that comes nearest to nothing, else straight at the next point as before; a stuck spell sees
	-- to the rest)
	return bx, bz, index, left
end

function HouseRoute.reach(g: Grid, fx: number, fz: number, piece: Rect, stand: number?, avoid: { Rect }?): (number?, number?, number?)
	local far = stand or cfg().Stand
	if not stand and cfg().StandFar then
		-- 9.3 (the owner: "the piece comes to his hands at the bend, not gliding from far away"): Stand studs off it first
		-- (his hands on it as he bends), StandFar where no such spot is
		local x, z, cost = HouseRoute.reach(g, fx, fz, piece, far, avoid)
		if x then
			return x, z, cost
		end
		far = cfg().StandFar
	end
	local start = nearestOpen(g, fx, fz, cfg().Snap)
	if start == 0 then
		return nil, nil, nil
	end
	local mx, mz = (piece.x0 + piece.x1) / 2, (piece.z0 + piece.z1) / 2
	local zones: { Rect } = avoid or {}
	local found, cost = search(g, start, function(k: number): number
		local x, z = middle(g, k)
		return math.max(0, toRect(x, z, piece) - far) -- (never more than the way to a cell within `far` of it)
	end, function(k: number): boolean
		local x, z = middle(g, k)
		if toRect(x, z, piece) > far then
			return false
		end
		for _, r in zones do
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

-- ── 10.x danger: what a run shuts ────────────────────────────────────────────

-- (the grid's own record of it: the rects it put into its walls and solids, the cells it closed, the set's key)
type Shut = { key: string, walls: { Rect }, floors: { Rect }, cells: { number } }
local shuts: { [Grid]: Shut } = setmetatable({}, { __mode = "k" }) :: any

local function without(list: { Rect }, gone: { Rect })
	for _, r in gone do
		local at = table.find(list, r)
		if at then
			table.remove(list, at)
		end
	end
end

function HouseRoute.shut(g: Grid, walls: { Rect }, floors: { Rect }, key: string): boolean
	local was = shuts[g]
	if was and was.key == key then
		return false
	end
	local step, nx, nz, r = g.step, g.nx, g.nz, g.radius
	if was then
		-- (open again what it closed, unless one of the solids that stay closes it: one added since)
		without(g.walls, was.walls)
		without(g.solids, was.floors)
		for _, k in was.cells do
			local i, j = (k - 1) % nx, (k - 1) // nx
			local x, z = g.x0 + i * step, g.z0 + j * step
			local free = true
			for _, p in g.solids do
				if toRect(x, z, p) < r then
					free = false
					break
				end
			end
			if free then
				g.still[k] = 1
			end
		end
	end
	local now: Shut = { key = key, walls = table.clone(walls), floors = table.clone(floors), cells = {} }
	for _, list in { now.walls, now.floors } do
		for _, p in list do
			local i0 = math.max(0, math.floor((p.x0 - r - g.x0) / step))
			local i1 = math.min(nx - 1, math.ceil((p.x1 + r - g.x0) / step))
			local j0 = math.max(0, math.floor((p.z0 - r - g.z0) / step))
			local j1 = math.min(nz - 1, math.ceil((p.z1 + r - g.z0) / step))
			for j = j0, j1 do
				local z = g.z0 + j * step
				for i = i0, i1 do
					local k = j * nx + i + 1
					if g.still[k] == 1 and toRect(g.x0 + i * step, z, p) < r then
						g.still[k] = 0
						table.insert(now.cells, k)
					end
				end
			end
		end
	end
	for _, p in now.walls do
		table.insert(g.walls, p)
	end
	for _, p in now.floors do
		table.insert(g.solids, p)
	end
	shuts[g] = now
	HouseRoute.block(g, g.pieces) -- (the open cells again: what is still, less the pieces standing)
	return true
end

return HouseRoute
