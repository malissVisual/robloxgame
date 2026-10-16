-- 9.0 Danny's way inside a house (shared/HouseRoute.luau; the owner, 8.9: "Danny can't walk around things logically. He
-- goes to take things through the wall: he can't get to the thing, he got stuck on the wall"), on the REAL plans
-- (shared/HouseLayout.luau on the recorder, tests/run_tests.py): the big house (The Old Farmstead, kind "big", 8.5.2
-- roomy) and the family house (the five houses of Jinočany, kind "house"), every layout of each (the back row's four
-- orders, mirrored or not: a seed for each).
--   * the cause, measured: 8.9's aim (server/MoveHelper.luau besidePiece: straight out of the piece toward where he came
--     in, half its size and 1.5 studs) put a fifth of the pieces' spots behind a wall (in the next room, in the wall,
--     out of the house), and many within the pathfinding's agent radius of a wall (no path: the straight line into it)
--   * now, from the front door (the big house's back door too, in two of its layouts) to every piece: a spot to take it from
--     (HouseRoute.reach) on an open cell, at arm's length (within Route.Stand of its footprint), its line to the
--     piece's middle through no wall; a way there (HouseRoute.path) whose every leg crosses no wall slab, keeps to the
--     rooms and the doorways and to open cells (his body clear of the walls, the fixtures and the pieces); and from
--     that spot a way back out of each door the same (two layouts of each kind)
--   * a piece boxed in by others: no spot (he can't get to it: refused); a spot never in a doorway's zone when asked
--   * a stuck nudge's snap: from inside a wall onto the nearest open cell, never into a wall
local Mk = require("./ItemMock")
local Vector3 = Mk.Vector3
local Config = require("./Config")
local HouseLayout = require("./HouseLayout")
local HouseRoute = require("./HouseRoute")
local FurnitureLooks = require("./FurnitureLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local R = Config.MoveHelper.Route
type Rect = HouseRoute.Rect

-- Every layout of a kind: a seed for each back-row order, mirrored or not (its plan kept: planned once). The seeds known
-- to give them first (a plan is costly), then on through the seeds while some layout is still missing.
local plans: { [number]: any } = {}
local KNOWN: { [string]: { number } } = { big = { 1, 2, 4, 5, 6, 10, 16, 18 }, house = { 1, 2, 4, 5, 6, 10, 18, 20 } }
local function variants(kind: string): { number }
	local found: { [string]: boolean } = {}
	local list: { number } = {}
	local tries = table.clone(KNOWN[kind])
	for seed = 1, 400 do
		table.insert(tries, seed)
	end
	for _, seed in tries do
		if plans[seed * 10 + (if kind == "big" then 1 else 0)] then
			continue
		end
		local plan = HouseLayout.plan(seed, kind)
		local back: { any } = {}
		local front = plan.rooms[1].max.Z -- (the hall's depth: the front row's)
		for _, room in plan.rooms do
			if room.min.Z > front + 1 and room.id ~= "corridor" then
				table.insert(back, room)
			end
		end
		table.sort(back, function(a: any, b: any): boolean
			return a.min.X < b.min.X
		end)
		local ids: { string } = {}
		for _, room in back do
			table.insert(ids, room.id)
		end
		local key = table.concat(ids, ",") .. (if plan.mirrored then " mirrored" else "")
		if not found[key] then
			found[key] = true
			table.insert(list, seed)
			plans[seed * 10 + (if kind == "big" then 1 else 0)] = plan
		end
		if #list == 8 then
			break -- (four orders, mirrored or not: all of them)
		end
	end
	return list
end

local function pieceRect(s: any): Rect
	local ex, ez = HouseLayout.extent(s.item, s.turn)
	local p = s.at.Position
	return { x0 = p.X - ex / 2, z0 = p.Z - ez / 2, x1 = p.X + ex / 2, z1 = p.Z + ez / 2 }
end

-- Does the leg from (ax, az) to (bx, bz) keep out of every wall slab, in the rooms and doorways, on open cells?
local function legBad(grid: HouseRoute.Grid, ax: number, az: number, bx: number, bz: number): string?
	for _, w in grid.walls do
		if HouseRoute.cuts(ax, az, bx, bz, w) then
			return "crosses a wall"
		end
	end
	local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local n = math.max(1, math.ceil(length / 0.5))
	for k = 0, n do
		local x, z = ax + (bx - ax) * k / n, az + (bz - az) * k / n
		if not HouseRoute.inside(grid, x, z) then
			return `leaves the rooms at ({math.floor(x)}, {math.floor(z)})`
		end
	end
	if not HouseRoute.clear(grid, ax, az, bx, bz) then
		return "not on open cells"
	end
	return nil
end

local function walkBad(grid: HouseRoute.Grid, fx: number, fz: number, points: { HouseRoute.Point }): string?
	local ax, az = fx, fz
	for index, p in points do
		-- (the first leg from a start off the open cells: onto the nearest one, a step; checked for walls only)
		local why = legBad(grid, ax, az, p.x, p.z)
		if why and not (index == 1 and why == "not on open cells") then
			return why
		end
		ax, az = p.x, p.z
	end
	return nil
end

-- ── The cause, measured: 8.9's aim on the real plans ────────────────────────

local oldBehind, oldNear, oldAll = 0, 0, 0
local kinds = { big = variants("big"), house = variants("house") }
check(`every layout: the big house's {#kinds.big}, the family house's {#kinds.house} (four orders, mirrored or not)`, #kinds.big == 8 and #kinds.house == 8,
	`{#kinds.big} {#kinds.house}`)
for kind, seeds in kinds do
	for _, seed in seeds do
		local plan = plans[seed * 10 + (if kind == "big" then 1 else 0)]
		local grid = HouseRoute.grid(plan) :: HouseRoute.Grid
		local look = (plan.entry * Vector3.new(0, 0, -1)) - plan.entry.Position
		local entry = plan.entry.Position + look * 1.5 -- (where he comes in: server/MoveHelper.luau transfer)
		for _, s in plan.spots do
			local def = FurnitureLooks.Items[s.item]
			local at = s.at.Position
			local half = math.max(def.size.X, def.size.Z) / 2
			local dx, dz = entry.X - at.X, entry.Z - at.Z
			local len = math.sqrt(dx * dx + dz * dz)
			local bx, bz = at.X + dx / len * (half + 1.5), at.Z + dz / len * (half + 1.5)
			oldAll += 1
			if not HouseRoute.sees(grid, bx, bz, at.X, at.Z) or not HouseRoute.inside(grid, bx, bz) then
				oldBehind += 1
			end
			for _, w in grid.walls do
				if HouseRoute.toRect(bx, bz, w) < Config.MoveHelper.PathRadius then
					oldNear += 1
					break
				end
			end
		end
	end
end
print(`(8.9's aim: {oldBehind} of {oldAll} pieces' spots behind a wall or out of the rooms, {oldNear} within the pathfinding's radius of a wall)`)
check("the cause: 8.9's aim (straight out of the piece toward the door) put many pieces' spots behind a wall, near walls", oldBehind > oldAll / 10
	and oldNear > oldAll / 5, `{oldBehind} {oldNear} of {oldAll}`)

-- ── Now: every way in, every piece, every layout ─────────────────────────────

for kind, seeds in kinds do
	local pieces, spots, bad = 0, 0, {} :: { string }
	local outBad = 0
	for _, seed in seeds do
		local plan = plans[seed * 10 + (if kind == "big" then 1 else 0)]
		local grid = HouseRoute.grid(plan) :: HouseRoute.Grid
		local rects: { Rect } = {}
		for _, s in plan.spots do
			table.insert(rects, pieceRect(s))
		end
		HouseRoute.block(grid, rects)
		local entries = HouseLayout.entries(plan)
		local exits = HouseLayout.exitsOf(plan)
		local first = seed == seeds[1] or seed == seeds[2] -- (the other ways in and the ways out: the first two layouts)
		for index, entryFrame in entries do
			if index > 1 and not first then
				continue
			end
			local look = (entryFrame * Vector3.new(0, 0, -1)) - entryFrame.Position
			local entry = entryFrame.Position + look * 1.5
			for _, s in plan.spots do
				pieces += 1
				local rect = pieceRect(s)
				local x, z = HouseRoute.reach(grid, entry.X, entry.Z, rect)
				if not x or not z then
					table.insert(bad, `{kind} {seed} way {index}: #{s.id} {s.item} no spot`)
					continue
				end
				spots += 1
				local mx, mz = (rect.x0 + rect.x1) / 2, (rect.z0 + rect.z1) / 2
				if not HouseRoute.open(grid, x, z) or HouseRoute.toRect(x, z, rect) > R.Stand + 1e-6 or not HouseRoute.sees(grid, x, z, mx, mz) then
					table.insert(bad, `{kind} {seed}: #{s.id} {s.item} its spot not beside it, or behind a wall`)
				end
				local points = HouseRoute.path(grid, entry.X, entry.Z, x, z)
				local why = if points then walkBad(grid, entry.X, entry.Z, points) else "no way"
				if why then
					table.insert(bad, `{kind} {seed} way {index}: #{s.id} {s.item}: {why}`)
				elseif math.abs(points[#points].x - x) > 1e-6 or math.abs(points[#points].z - z) > 1e-6 then
					table.insert(bad, `{kind} {seed}: #{s.id} {s.item}: the way ends off its spot`)
				end
				if index == 1 and first then
					-- (and back out of every door from there, as he carries it to the van)
					for _, exit in exits do
						local back = HouseRoute.path(grid, x, z, exit.X, exit.Z)
						if not back or walkBad(grid, x, z, back) then
							outBad += 1
						end
					end
				end
			end
		end
	end
	check(`{kind}: from the way in, every piece of every layout has a spot beside it (on an open cell, within Stand of it, no wall between)`,
		spots == pieces and #bad == 0, `{spots}/{pieces}: {bad[1]}`)
	check(`{kind}: …his way to each never crosses a wall, keeps to the rooms and doorways and to open cells (clear of the fixtures and pieces)`, #bad == 0, bad[1])
	check(`{kind}: …and his way from there out of every door the same (two layouts)`, outBad == 0, outBad)
end

-- ── A piece boxed in; the doorways; the snap ─────────────────────────────────

do
	local plan = plans[kinds.house[1] * 10]
	local grid = HouseRoute.grid(plan) :: HouseRoute.Grid
	local look = (plan.entry * Vector3.new(0, 0, -1)) - plan.entry.Position
	local entry = plan.entry.Position + look * 1.5
	-- a small piece in the middle of the living room, four slabs round it with gaps narrower than his body
	local living: any = nil
	for _, room in plan.rooms do
		if room.id == "living" then
			living = room
		end
	end
	local cx, cz = (living.min.X + living.max.X) / 2, (living.min.Z + living.max.Z) / 2
	local piece: Rect = { x0 = cx - 0.5, z0 = cz - 0.5, x1 = cx + 0.5, z1 = cz + 0.5 }
	local d = 1.6
	local box: { Rect } = {
		piece,
		{ x0 = cx - d - 0.6, z0 = cz + d, x1 = cx + d + 0.6, z1 = cz + d + 0.6 },
		{ x0 = cx - d - 0.6, z0 = cz - d - 0.6, x1 = cx + d + 0.6, z1 = cz - d },
		{ x0 = cx - d - 0.6, z0 = cz - d, x1 = cx - d, z1 = cz + d },
		{ x0 = cx + d, z0 = cz - d, x1 = cx + d + 0.6, z1 = cz + d },
	}
	HouseRoute.block(grid, {})
	local freeX = HouseRoute.reach(grid, entry.X, entry.Z, piece)
	HouseRoute.block(grid, box)
	local boxedX = HouseRoute.reach(grid, entry.X, entry.Z, piece)
	check("a piece in the open has a spot; boxed in by others (no gap his body fits through): none (he can't get to it)", freeX ~= nil and boxedX == nil)
	HouseRoute.block(grid, { piece })
	-- the doorways' zones avoided: a piece right beside the front door, asked to wait out of the doorways
	local front = plan.doors[1]
	local w = front.width / 2 + Config.MoveHelper.Aside.Margin
	local zone: Rect = { x0 = front.at.X - w, z0 = front.at.Z - Config.MoveHelper.Aside.Depth, x1 = front.at.X + w, z1 = front.at.Z + Config.MoveHelper.Aside.Depth }
	local near: Rect = { x0 = front.at.X + w + 0.2, z0 = 0.6, x1 = front.at.X + w + 1.2, z1 = 1.6 }
	HouseRoute.block(grid, { near })
	local x, z = HouseRoute.reach(grid, entry.X, entry.Z, near, nil, { zone })
	check("…asked to wait out of the doorways: his spot outside the doorway's zone", x ~= nil and z ~= nil
		and not (x >= zone.x0 and x <= zone.x1 and z >= zone.z0 and z <= zone.z1), `{x} {z}`)
	-- the snap (a stuck nudge's, a start off the open cells): from inside a wall onto the nearest open cell
	local wall = grid.walls[1]
	local wx, wz = (wall.x0 + wall.x1) / 2, (wall.z0 + wall.z1) / 2
	local sx, sz = HouseRoute.snap(grid, wx, wz)
	check("a spot inside a wall: snapped onto the nearest open cell (never into a wall), within Route.Snap", sx ~= nil and sz ~= nil
		and HouseRoute.open(grid, sx :: number, sz :: number) and math.sqrt(((sx :: number) - wx) ^ 2 + ((sz :: number) - wz) ^ 2) <= R.Snap + 1e-6, `{sx} {sz}`)
	local across = if wall.x1 - wall.x0 > wall.z1 - wall.z0 then HouseRoute.sees(grid, wx, wz - 2, wx, wz + 2) else HouseRoute.sees(grid, wx - 2, wz, wx + 2, wz)
	check("…a cell inside a wall slab is never open, a line across it sees nothing", not HouseRoute.open(grid, wx, wz) and not across)
	check("a plan without walls (a test's fake): no grid", HouseRoute.grid({ faces = {} }) == nil and HouseRoute.grid({}) == nil)
	local fp = HouseRoute.footprint(0, 0, 4, 2, math.pi / 2)
	check("a footprint turned a quarter: its sides swap", math.abs(fp.x1 - 1) < 1e-6 and math.abs(fp.z1 - 2) < 1e-6)
end

-- ── 9.0 the far end's holder walking backwards with your piece: along the walls, never through ────────────────────────
-- (the owner, 8.9.3: "When I want to walk forwards, Danny can't walk backwards"; server/MoveHelper.luau's hold slides
-- him: Config.MoveHelper.HoldWall.Clear off every wall slab)

do
	local clear = Config.MoveHelper.HoldWall.Clear
	-- one wall along X (z 10 … 11): straight at it he stops Clear before it; slanting at it he slides along its face
	local g: any = { walls = { { x0 = -50, z0 = 10, x1 = 50, z1 = 11 } } }
	local x, z, nx, nz = HouseRoute.slide(g, 0, 0, 0, 20, clear)
	check("9.0 slide: straight at a wall he stops Clear studs before it, held by its face (its way out: -Z)", math.abs(x) < 1e-6
		and math.abs(z - (10 - clear)) < 1e-3 and nx == 0 and nz == -1, `{x} {z} {nx} {nz}`)
	x, z, nx, nz = HouseRoute.slide(g, 0, 0, 6, 20, clear)
	check("…slanting at it: on along its face (the way along it kept), never through", math.abs(x - 6) < 1e-6 and math.abs(z - (10 - clear)) < 1e-3
		and nz == -1, `{x} {z}`)
	x, z, nx, nz = HouseRoute.slide(g, 0, 0, 3, 5, clear)
	check("…a way short of it: all of it, nothing held", x == 3 and z == 5 and nx == 0 and nz == 0)
	x, z = HouseRoute.slide(g, 0, 9.5, 2, 15, clear) -- (a start already within Clear of it)
	check("…from within Clear of it: never deeper in, along it as ever", z <= 9.5 + 1e-6 and math.abs(x - 2) < 1e-6, `{x} {z}`)
	x, z = HouseRoute.slide(g, 0, 9.5, 0, 0, clear)
	check("…and out of it freely", x == 0 and z == 0)
	-- the real plans: a thousand ways from open cells toward anywhere near; where he gets to is Clear off every slab
	-- and the line there crosses none
	local worst, crossed, ways = math.huge, 0, 0
	for _, kind in { "house", "big" } do
		for _, seed in kinds[kind] do
			local plan = plans[seed * 10 + (if kind == "big" then 1 else 0)]
			local grid = HouseRoute.grid(plan) :: HouseRoute.Grid
			HouseRoute.block(grid, {})
			math.randomseed(seed)
			local function between(a: number, b: number): number
				return a + (b - a) * math.random()
			end
			for _ = 1, 150 do
				local fx = between(plan.min.X, plan.max.X)
				local fz = between(plan.min.Z, plan.max.Z)
				if not HouseRoute.open(grid, fx, fz) then
					continue
				end
				local angle = between(0, 2 * math.pi)
				local reach = between(0.5, 6)
				local tx, tz = fx + math.cos(angle) * reach, fz + math.sin(angle) * reach
				local sx, sz = HouseRoute.slide(grid, fx, fz, tx, tz, clear)
				ways += 1
				for _, w in grid.walls do
					local dx = math.max(w.x0 - sx, 0, sx - w.x1)
					local dz = math.max(w.z0 - sz, 0, sz - w.z1)
					worst = math.min(worst, math.max(dx, dz))
				end
				if not HouseRoute.sees(grid, fx, fz, sx, sz) then
					crossed += 1
				end
			end
		end
	end
	check(`9.0 slide on every layout: {ways} ways, where he gets to Clear ({clear}) studs off every wall slab, never across one`,
		ways > 500 and worst >= clear - 1e-3 and crossed == 0, `{worst} off at least, {crossed} across`)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
