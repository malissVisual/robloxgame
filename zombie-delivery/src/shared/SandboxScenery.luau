--!strict
-- 8.0 SANDBOX, the map (design/sandbox/KONTRAKT.md): the small test world's dress as plain numbers, laid round
-- shared/SandboxMap.luau's fixed data (the plots, the yards, the house never move). server/SandboxWorld.luau builds it;
-- tests/sandboxworld_test.luau checks the numbers and the built world. Pure (no Roblox at its top level),
-- deterministic. 8.9: the Alps are gone; 9.4 the countryside's own dress (design/countryside/plan.py) is
-- shared/VillageScenery.luau's. 9.7 runs: no driving (design/lobby/plan.py, design/countryside/plan.py): Pražská,
-- Depot Row, the lanes, the turnaround, the markings, the street lamps and the signpost are gone; the asphalt is the run
-- zones' yards, where the trucks stand; the lobby's own dress is server/LobbyWorld.luau's. 10.8 the floating islands
-- (design/islands/plan.py, SandboxMap.Islands): no meadow under everything any more, the sky under them; each island's
-- grass is its ground, at its own height (its rock under it: shared/IslandLooks.luau).
--
--   The ground     10.8 every island's grass (Grass, 2 deep, its top at the island's top: SandboxMap.groundAt) over its
--                  top in a few tiles that leave out what has a ground of its own there: the plots' concrete pads, the
--                  farmstead's lawn, the lobby's plaza and the lawns (SandboxMap.Fields, Lawns: each flush with it, no two
--                  tops on one plane); cut in bands along z or along x, whichever takes fewer tiles
--   The yards      the asphalt (SandboxMap.Roads: each place's yard, its van parking) stands RoadTop - GroundTop over its
--                  island's grass; every edge drops back to it on a gravel shoulder, a slope Run studs wide (a wedge), a
--                  hip at a convex corner
--   The house      the curb-to-door Path, the garden's fence round its lot (decoration: nothing stops a mover), the
--                  gate with its THE OLD FARMSTEAD board, the mailbox, the flower boxes (the house itself is
--                  shared/ChaletLooks.luau's, on SandboxMap.House.house; 8.1: the owner's Blender house once imported)
--   Where things may grow   treeRule: 10.8 only on an island's grass (Clear.Edge in from its edge), never on a yard, a
--                  plot, a place to empty's lot or a truck's spot (the six places' lots and yards: a round's vans park
--                  there, SandboxMap.Houses, the farmstead's among them), 9.7 never in the lobby
--
--   SandboxScenery.tops()               10.8 the islands' grass tiles ({ island, top, rect }) round the holes
--   SandboxScenery.holes()              what has its own ground (the pads, the farmstead's lawn, the plaza, the fields, the lawns)
--   SandboxScenery.groundAt(x, z)       the ground's top there (10.8: its island's top, SandboxMap.groundAt)
--   SandboxScenery.asphalt()            the asphalt's slabs (a yard's name, rect and top), none over another
--   SandboxScenery.ramps()              the yards' shoulders (wedges as CurbShape's pieces: kind, middle, size, X axis)
--   SandboxScenery.shoulderAt(ramp, x, z)   a shoulder's top at (x, z) (nil: not over it)
--   SandboxScenery.treeRule(x, z, r)    why nothing r wide may grow there (nil: it may)
--   SandboxScenery.garden(), vanPaths()
--   SandboxScenery.outside(x, z)        how far (x, z) is outside the Bounds (≤ 0: inside)
--   SandboxScenery.rectDistance(r, x, z)   how far (x, z) is from a rect (0 inside)

local Config = require(script.Parent.Config)
local SandboxMap = require(script.Parent.SandboxMap)

local SandboxScenery = {}

export type Rect = SandboxMap.Rect
-- A shoulder: an "edge" is a WedgePart (its high side at its +Z, against the asphalt, its low edge at its -Z on the
-- meadow), a "corner" a CornerWedgePart (its apex over its (+X, -Z) corner, the asphalt's corner); its middle, its size
-- along its own axes and its X axis on the ground (rx, rz; Y up, Z = X × Y). (shared/CurbShape.luau's convention.)
export type Ramp = { kind: string, x: number, y: number, z: number, sx: number, sy: number, sz: number, rx: number, rz: number }
-- 8.9: a slab of asphalt (a yard's, SandboxMap.Roads' name; 10.8 its top: its island's road level)
export type Slab = { name: string, x0: number, x1: number, z0: number, z1: number, top: number }
export type Segment = { ax: number, az: number, bx: number, bz: number }
-- 10.8: a tile of an island's grass (its island's id, its top's height, its rect)
export type Tile = { island: string, top: number, rect: Rect }

local MAP = SandboxMap
local BOUNDS = MAP.Bounds
local HOUSE = MAP.House

-- ── The numbers ────────────────────────────────────────────────────────────

SandboxScenery.Budget = 2500 -- parts in workspace.Sandbox at most
SandboxScenery.Run = 4 -- the shoulders: from the asphalt's top down to the meadow over this many studs (1 in 10)
SandboxScenery.RoadDepth = 1 -- the asphalt slabs' thickness (their bottom under the meadow's top)
SandboxScenery.Shadow = { Long = 4, Wide = 1 } -- a part throws a shadow only this big (and RenderBudget's rule)
SandboxScenery.Grass = Config.Islands.Body.Grass -- 10.8 an island's grass tiles' depth (its rock under them: shared/IslandLooks.luau)
-- the chalet on House.house (its walls the box's height), its dice: "tyrol". 8.1: Pitch is the owner's Blender house's roof
-- (design/blender-house/house.py PITCH): dressed in it (server/HouseMesh.luau), the chalet's gable wedges are re-cut to
-- a gable this steep across the house, under that roof (tools/house-art/check.py checks it against the model). 8.2.1:
-- the big house's 31° (house.py TARGET "sandbox", the manifest's "pitch")
SandboxScenery.Chalet = { Seed = 1, Render = 2, Shade = 0, Pitch = 31 }
SandboxScenery.Path = { x0 = HOUSE.door.x - 3, x1 = HOUSE.door.x + 3, z0 = HOUSE.curb.z, z1 = HOUSE.door.z } :: Rect -- the curb to the door, kept clear
SandboxScenery.Garden = { Front = HOUSE.lot.z0 + 6, Gate = 6, Inset = 1, Post = 8, Height = 3.2 } -- the lot's fence: its front line, the gate's half width
-- studs kept clear round a yard (its shoulder in it), a plot, the house's lot and inside the Bounds (8.9: the edge's
-- invisible walls), two trees' crowns this share of their radii apart
SandboxScenery.Clear = { Road = 12, Plot = 8, Lot = 6, Edge = 6, Trees = 0.85 }
SandboxScenery.Light = Config.SandboxLight.Sky -- 8.3: the afternoon's light lives in Config with the rest of the light
SandboxScenery.Colors = {
	Meadow = { 96, 138, 60 } :: { number },
	Lawn = { 108, 152, 64 } :: { number },
	Pad = { 176, 174, 168 } :: { number },
	Asphalt = { 52, 52, 56 } :: { number },
	Shoulder = { 138, 130, 116 } :: { number },
	Fence = { 120, 86, 56 } :: { number },
	Path = { 178, 168, 148 } :: { number },
	Ink = { 30, 30, 34 } :: { number },
}

-- ── Small tools ────────────────────────────────────────────────────────────

function SandboxScenery.rectDistance(r: Rect, x: number, z: number): number
	local dx = math.max(r.x0 - x, 0, x - r.x1)
	local dz = math.max(r.z0 - z, 0, z - r.z1)
	return math.sqrt(dx * dx + dz * dz)
end
local rectDistance = SandboxScenery.rectDistance

-- ── The ground ─────────────────────────────────────────────────────────────

-- The holes in the islands' grass: the plots' pads, the house's lawn, 9.7 the lobby's plaza and 8.9 the fields and the
-- lawns (each its own part, flush with the grass).
function SandboxScenery.holes(): { Rect }
	local list: { Rect } = {}
	for _, plot in MAP.Plots do
		table.insert(list, plot.rect)
	end
	table.insert(list, HOUSE.lot)
	local plaza = MAP.Lobby.plaza
	table.insert(list, { x0 = plaza.x0, x1 = plaza.x1, z0 = plaza.z0, z1 = plaza.z1 })
	for _, f in MAP.Fields do
		table.insert(list, { x0 = f.x0, x1 = f.x1, z0 = f.z0, z1 = f.z1 })
	end
	for _, lawn in MAP.Lawns do
		table.insert(list, { x0 = lawn.x0, x1 = lawn.x1, z0 = lawn.z0, z1 = lawn.z1 })
	end
	return list
end

-- A rect's tiles less the holes in it, in bands along one axis, a tile joined to the one before it in that band's
-- direction when they meet edge to edge with the same sides (fewer parts round the holes); 9.4 both ways (bands along
-- z, bands along x), the one with fewer tiles. No two tiles overlap, none longer than a part may be. (10.8: an island's
-- top, 8.9 – 10.5 the Bounds' meadow.)
local function sweep(area: Rect, holes: { Rect }, alongX: boolean): { Rect }
	-- (u: the axis the bands cut, v: across them; alongX swaps x and z)
	local function u0(r: Rect): number return if alongX then r.x0 else r.z0 end
	local function u1(r: Rect): number return if alongX then r.x1 else r.z1 end
	local function v0(r: Rect): number return if alongX then r.z0 else r.x0 end
	local function v1(r: Rect): number return if alongX then r.z1 else r.x1 end
	local cuts = { u0(area), u1(area) }
	for _, h in holes do
		table.insert(cuts, math.clamp(u0(h), u0(area), u1(area)))
		table.insert(cuts, math.clamp(u1(h), u0(area), u1(area)))
	end
	table.sort(cuts)
	local tiles: { { number } } = {} -- { v0, v1, u0, u1 }
	for i = 1, #cuts - 1 do
		local a, b = cuts[i], cuts[i + 1]
		if b - a > 1e-6 then
			local open = { { v0(area), v1(area) } }
			for _, h in holes do
				if u0(h) < b - 1e-6 and u1(h) > a + 1e-6 then
					local next: { { number } } = {}
					for _, span in open do
						if v1(h) <= span[1] or v0(h) >= span[2] then
							table.insert(next, span)
						else
							if v0(h) > span[1] then
								table.insert(next, { span[1], v0(h) })
							end
							if v1(h) < span[2] then
								table.insert(next, { v1(h), span[2] })
							end
						end
					end
					open = next
				end
			end
			-- (9.7: the Bounds reach round the lobby, wider than a part may be: a span that long cut in equal pieces)
			local cut: { { number } } = {}
			for _, span in open do
				local pieces = math.ceil((span[2] - span[1]) / 2048 - 1e-9)
				for k = 1, math.max(1, pieces) do
					local n = math.max(1, pieces)
					table.insert(cut, { span[1] + (span[2] - span[1]) * (k - 1) / n, span[1] + (span[2] - span[1]) * k / n })
				end
			end
			open = cut
			for _, span in open do
				local joined = false
				for _, t in tiles do
					if t[1] == span[1] and t[2] == span[2] and math.abs(t[4] - a) < 1e-6 and b - t[3] <= 2048 then
						t[4] = b
						joined = true
						break
					end
				end
				if not joined then
					table.insert(tiles, { span[1], span[2], a, b })
				end
			end
		end
	end
	local out: { Rect } = {}
	for _, t in tiles do
		table.insert(out, if alongX then { x0 = t[3], x1 = t[4], z0 = t[1], z1 = t[2] } else { x0 = t[1], x1 = t[2], z0 = t[3], z1 = t[4] })
	end
	return out
end

-- 10.8 every island's grass: its top less the holes on it, a tile list each (the island's id and top with each tile).
local topsCache: { Tile }? = nil
function SandboxScenery.tops(): { Tile }
	if topsCache then
		return topsCache
	end
	local all = SandboxScenery.holes()
	local list: { Tile } = {}
	for _, island in MAP.Islands do
		local r = island.rect
		local holes: { Rect } = {}
		for _, h in all do
			if h.x0 < r.x1 and h.x1 > r.x0 and h.z0 < r.z1 and h.z1 > r.z0 then
				table.insert(holes, h)
			end
		end
		local byZ, byX = sweep(r, holes, false), sweep(r, holes, true)
		for _, t in (if #byX < #byZ then byX else byZ) do
			table.insert(list, { island = island.id, top = island.top, rect = t })
		end
	end
	topsCache = list
	return list
end

-- The ground's top at (x, z) off the asphalt (8.9: flat, the Alps' mounds are gone; 10.8 its island's top).
function SandboxScenery.groundAt(x: number, z: number): number
	return MAP.groundAt(x, z)
end

-- ── The roads' shoulders ───────────────────────────────────────────────────

local function edge(list: { Ramp }, x0: number, x1: number, z0: number, z1: number, nx: number, nz: number, base: number, top: number)
	-- the shoulder over the rect (x0 … x1, z0 … z1) of the grass (its top `base`), falling away from the asphalt (its
	-- top `top`) along (nx, nz)
	local along = if nx ~= 0 then z1 - z0 else x1 - x0
	local run = if nx ~= 0 then x1 - x0 else z1 - z0
	table.insert(list, {
		kind = "edge",
		x = (x0 + x1) / 2,
		y = base + (top - base) / 2,
		z = (z0 + z1) / 2,
		sx = along,
		sy = top - base,
		sz = run,
		rx = -nz,
		rz = nx,
	})
end

local function corner(list: { Ramp }, cx: number, cz: number, sx: number, sz: number, base: number, top: number)
	-- the hip at the asphalt's convex corner (cx, cz), out toward (sx, sz) (each ±1): CurbShape's corner piece
	local run = SandboxScenery.Run
	local d1x, d1z = if sz == -sx then sx else 0, if sz == -sx then 0 else sz
	table.insert(list, {
		kind = "corner",
		x = cx + sx * run / 2,
		y = base + (top - base) / 2,
		z = cz + sz * run / 2,
		sx = run,
		sy = top - base,
		sz = run,
		rx = -d1x,
		rz = -d1z,
	})
end

-- 8.9: the asphalt's slabs: every road's rect (9.7: the yards), none over another; 10.8 each at its island's road level.
function SandboxScenery.asphalt(): { Slab }
	local list: { Slab } = {}
	for _, road in MAP.Roads do
		local top = MAP.roadAt((road.x0 + road.x1) / 2, (road.z0 + road.z1) / 2)
		table.insert(list, { name = road.name, x0 = road.x0, x1 = road.x1, z0 = road.z0, z1 = road.z1, top = top })
	end
	return list
end

-- The spans less the span a … b.
local function less(spans: { { number } }, a: number, b: number): { { number } }
	local out: { { number } } = {}
	for _, s in spans do
		if b <= s[1] or a >= s[2] then
			table.insert(out, s)
		else
			if a > s[1] then
				table.insert(out, { s[1], a })
			end
			if b < s[2] then
				table.insert(out, { b, s[2] })
			end
		end
	end
	return out
end

-- A slab's side: its line (at `c`, from `a` to `b` along x or z) and the way out of the asphalt (nx, nz).
type Side = { along: string, c: number, a: number, b: number, nx: number, nz: number }
local function sidesOf(r: Slab): { Side }
	return {
		{ along = "x", c = r.z0, a = r.x0, b = r.x1, nx = 0, nz = -1 }, -- north
		{ along = "x", c = r.z1, a = r.x0, b = r.x1, nx = 0, nz = 1 }, -- south
		{ along = "z", c = r.x0, a = r.z0, b = r.z1, nx = -1, nz = 0 }, -- west
		{ along = "z", c = r.x1, a = r.z0, b = r.z1, nx = 1, nz = 0 }, -- east
	}
end

-- The spans of a slab's side with the grass beyond it: the side less what another slab's asphalt holds just outside it
-- (a junction: the street goes on); none where its island (10.8; the Bounds before) ends the road (its shoulder would
-- be over the sky).
local function openSpans(slabs: { Slab }, r: Slab, side: Side, edgeOf: Rect): { { number } }
	local run = SandboxScenery.Run
	local spans = { { side.a, side.b } }
	local reach = side.c + (side.nx + side.nz) * run -- (the shoulder's foot)
	if side.along == "x" then
		if reach < edgeOf.z0 - 1e-6 or reach > edgeOf.z1 + 1e-6 then
			return {}
		end
		spans = less(less(spans, -math.huge, edgeOf.x0), edgeOf.x1, math.huge)
	else
		if reach < edgeOf.x0 - 1e-6 or reach > edgeOf.x1 + 1e-6 then
			return {}
		end
		spans = less(less(spans, -math.huge, edgeOf.z0), edgeOf.z1, math.huge)
	end
	local probe = side.c + (side.nx + side.nz) * 0.01 -- (just outside the side)
	for _, q in slabs do
		if q ~= r then
			if side.along == "x" and q.z0 <= probe and q.z1 >= probe then
				spans = less(spans, q.x0, q.x1)
			elseif side.along == "z" and q.x0 <= probe and q.x1 >= probe then
				spans = less(spans, q.z0, q.z1)
			end
		end
	end
	return spans
end

-- The yards' shoulders: every road of SandboxMap.Roads (9.7: the yards), each side but where another's asphalt goes on
-- or its island ends it, a hip at every convex corner; 10.8 each down to its island's grass from its own asphalt.
function SandboxScenery.ramps(): { Ramp }
	local run = SandboxScenery.Run
	local list: { Ramp } = {}
	local slabs = SandboxScenery.asphalt()
	for _, r in slabs do
		local top = r.top
		local base = top - (MAP.RoadTop - MAP.GroundTop)
		local island = MAP.islandAt((r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2)
		local edgeOf = if island then island.rect else BOUNDS
		local reached: { [string]: number } = {} -- (a corner's sides whose shoulder reaches it: "x0z0" …)
		for _, side in sidesOf(r) do
			local spans = openSpans(slabs, r, side, edgeOf)
			for _, s in spans do
				local lo, hi = s[1], s[2]
				if hi - lo > 1e-6 then
					local corners: { string } = {}
					if side.along == "x" then
						local z0 = if side.nz < 0 then side.c - run else side.c
						edge(list, lo, hi, z0, z0 + run, 0, side.nz, base, top)
						local zKey = if side.nz < 0 then "z0" else "z1"
						if math.abs(lo - r.x0) < 1e-6 then
							table.insert(corners, "x0" .. zKey)
						end
						if math.abs(hi - r.x1) < 1e-6 then
							table.insert(corners, "x1" .. zKey)
						end
					else
						local x0 = if side.nx < 0 then side.c - run else side.c
						edge(list, x0, x0 + run, lo, hi, side.nx, 0, base, top)
						local xKey = if side.nx < 0 then "x0" else "x1"
						if math.abs(lo - r.z0) < 1e-6 then
							table.insert(corners, xKey .. "z0")
						end
						if math.abs(hi - r.z1) < 1e-6 then
							table.insert(corners, xKey .. "z1")
						end
					end
					for _, key in corners do
						reached[key] = (reached[key] or 0) + 1
					end
				end
			end
		end
		-- the hips: where both sides' shoulders reach the corner and no other asphalt lies beyond it
		for _, c in { { key = "x0z0", sx = -1, sz = -1 }, { key = "x1z0", sx = 1, sz = -1 }, { key = "x0z1", sx = -1, sz = 1 }, { key = "x1z1", sx = 1, sz = 1 } } do
			if reached[c.key] == 2 then
				local sx, sz = c.sx, c.sz
				local cx, cz = if sx < 0 then r.x0 else r.x1, if sz < 0 then r.z0 else r.z1
				local mx, mz = cx + sx * run / 2, cz + sz * run / 2
				local free = true
				for _, q in slabs do
					free = free and not (mx > q.x0 and mx < q.x1 and mz > q.z0 and mz < q.z1)
				end
				if free then
					corner(list, cx, cz, sx, sz, base, top)
				end
			end
		end
	end
	return list
end

-- The ground's top at (x, z) from the shoulders alone (the grass under them): what a wheel rolls on.
function SandboxScenery.shoulderAt(ramp: Ramp, x: number, z: number): number?
	-- (in the piece's frame: X = (rx, rz), Z = X × Y = (-rz, rx))
	local dx, dz = x - ramp.x, z - ramp.z
	local u = dx * ramp.rx + dz * ramp.rz
	local w = dx * -ramp.rz + dz * ramp.rx
	if math.abs(u) > ramp.sx / 2 + 1e-6 or math.abs(w) > ramp.sz / 2 + 1e-6 then
		return nil
	end
	local base = ramp.y - ramp.sy / 2
	if ramp.kind == "edge" then
		return base + ramp.sy * (w + ramp.sz / 2) / ramp.sz -- (high at +Z)
	end
	-- a corner wedge: its apex over (+X, -Z), down toward -X and +Z
	local fx = (u + ramp.sx / 2) / ramp.sx
	local fz = (ramp.sz / 2 - w) / ramp.sz
	return base + ramp.sy * math.min(fx, fz)
end

-- ── Where things may grow ──────────────────────────────────────────────────

-- The trucks' spots: every house to empty's curb (SandboxMap.Houses', the farmstead's first; 9.7: no plot's apron, no
-- van drives home).
function SandboxScenery.vanPaths(): { Rect }
	local list: { Rect } = {}
	for _, h in MAP.Houses do
		local c = h.curb
		table.insert(list, { x0 = c.x - 14, x1 = c.x + 14, z0 = c.z - 14, z1 = c.z + 14 })
	end
	return list
end

-- Why something `r` wide (a tree's crown) may not stand at (x, z): nil when it may. (The places' boxes, the landmarks,
-- the stream and the clearings too: shared/VillageScenery.luau treeRule.)
function SandboxScenery.treeRule(x: number, z: number, r: number): string?
	local C = SandboxScenery.Clear
	local inset = C.Edge
	-- (10.8: on an island's grass, its crown Edge in from its edge: never over the sky)
	local island = MAP.islandAt(x, z)
	local edge = if island then island.rect else BOUNDS
	if not island or x - r < edge.x0 + inset or x + r > edge.x1 - inset or z - r < edge.z0 + inset or z + r > edge.z1 - inset then
		return "edge"
	end
	for _, road in MAP.Roads do
		if rectDistance(road :: any, x, z) < r + C.Road then
			return "road"
		end
	end
	if MAP.inLobby(x, z, r + C.Plot) then
		return "lobby" -- (9.7: the lobby's own trees are server/LobbyWorld.luau's)
	end
	for _, plot in MAP.Plots do
		if rectDistance(plot.rect, x, z) < r + C.Plot then
			return "plot"
		end
	end
	for _, h in MAP.Houses do -- (every place to empty's lot, the farmstead's first)
		if rectDistance(h.lot, x, z) < r + C.Lot then
			return "house"
		end
	end
	if rectDistance(SandboxScenery.Path, x, z) < r + C.Lot then
		return "path"
	end
	for _, way in SandboxScenery.vanPaths() do
		if rectDistance(way, x, z) < r + C.Plot then
			return "van"
		end
	end
	return nil
end

-- ── The garden's fence ─────────────────────────────────────────────────────

-- The garden's fence round the house's lot: its front a little in (clear of the turnaround's shoulder), the gate on
-- the path.
function SandboxScenery.garden(): { Segment }
	local G, lot = SandboxScenery.Garden, HOUSE.lot
	local x0, x1, z0, z1 = lot.x0 + G.Inset, lot.x1 - G.Inset, G.Front, lot.z1 - G.Inset
	local gx = HOUSE.door.x
	return {
		{ ax = x0, az = z0, bx = gx - G.Gate, bz = z0 },
		{ ax = gx + G.Gate, az = z0, bx = x1, bz = z0 },
		{ ax = x1, az = z0, bx = x1, bz = z1 },
		{ ax = x1, az = z1, bx = x0, bz = z1 },
		{ ax = x0, az = z1, bx = x0, bz = z0 },
	}
end

-- ── The Bounds ─────────────────────────────────────────────────────────────

-- How far (x, z) lies outside the Bounds (≤ 0: inside).
function SandboxScenery.outside(x: number, z: number): number
	local b = BOUNDS
	local dx = math.max(b.x0 - x, x - b.x1)
	local dz = math.max(b.z0 - z, z - b.z1)
	if dx > 0 and dz > 0 then
		return math.sqrt(dx * dx + dz * dz)
	end
	return math.max(dx, dz)
end

-- ── 8.3 walk-in doors: the big house's doors' leaves that swing ──────────────────────────────────────────────────────
-- The owner's Blender house (server/HouseMesh.luau, design/blender-house/house.py door("front"), door("back")) has its
-- doors in its model: they cannot move. Copied as door leaves (shared/DoorSwing.luau; server/SandboxWorld.luau
-- doorLeaves builds them once the house is dressed), standing just in front of the model's door (its leaves sit 0.22 to
-- 0.34 back in their pocket, its brass handles reach the wall's face: the copies' backs on the face cover all of it):
-- the front door's two each half the opening (they meet in the middle, no seam), the back door's one the whole of it;
-- each hinged at the opening's side (the back door's: the side away from its handle, as house.py hangs it), swinging
-- out of the house (8.5, was in: seen as they swing, the model's own door behind a dark doorway where they stood:
-- DoorDark; clear of its portal, lantern and bushes, over its step). Each leaf's parts in its door's
-- frame (its foot on the wall: House.door's, House.back's; +X right of somebody looking out, -Z out of the house), its
-- body first: the body, two cassettes, the glass, the grille's two bars, the brass knob (a cylinder along Z) and lever
-- (0.3 and 0.42 from its free end), as house.py draws them.
--   FrontDoor, BackDoor  the opening: Width × Height from Sill up; the leaf Tall, Thick. The back door's Hinge: its one
--                        leaf's (-1 its -X end); its Width is the back doorway's too (server/SandboxWorld.luau's BackDoor)
export type LeafPart = { name: string, finish: string, size: { number }, at: { number }, cylinder: boolean? }
export type FrontLeaf = { hinge: number, parts: { LeafPart } }
export type Opening = { Width: number, Height: number, Sill: number, Tall: number, Thick: number }
SandboxScenery.FrontDoor = { Width = 4, Height = 6.85, Sill = 0.15, Tall = 6.82, Thick = 0.12 }
SandboxScenery.BackDoor = { Width = 3, Height = 6.8, Sill = 0.15, Tall = 6.77, Thick = 0.12, Hinge = -1 }

-- One leaf `w` wide in the door `F`, its middle at `x`, hinged at its end `hinge` (its handle near the other end).
local function leafOf(F: Opening, x: number, w: number, hinge: number): FrontLeaf
	local y = F.Sill + F.Height / 2
	local face = -F.Thick -- (the leaf's front, out of the house)
	local free = x - hinge * w / 2 -- (its free end: the handle's)
	return {
		hinge = hinge,
		parts = {
			{ name = "DoorLeaf", finish = "door", size = { w, F.Tall, F.Thick }, at = { x, y, -F.Thick / 2 } },
			{ name = "Cassette", finish = "door", size = { w - 0.6, 2.3, 0.04 }, at = { x, F.Sill + 1.8, face - 0.02 } },
			{ name = "Cassette", finish = "door", size = { w - 0.6, 0.8, 0.04 }, at = { x, F.Sill + F.Height - 0.75, face - 0.02 } },
			{ name = "DoorGlass", finish = "glass", size = { w - 0.75, 1.9, 0.03 }, at = { x, F.Sill + 4.35, face - 0.005 } },
			{ name = "Grille", finish = "door", size = { 0.08, 1.9, 0.03 }, at = { x, F.Sill + 4.35, face - 0.035 } },
			{ name = "Grille", finish = "door", size = { w - 0.75, 0.08, 0.03 }, at = { x, F.Sill + 4.35, face - 0.035 } },
			{ name = "Knob", finish = "brass", size = { 0.22, 0.14, 0.14 }, at = { free + hinge * 0.3, F.Sill + 3.1, face - 0.11 }, cylinder = true },
			{ name = "Handle", finish = "brass", size = { 0.38, 0.07, 0.06 }, at = { free + hinge * 0.42, F.Sill + 3.1, face - 0.17 } },
		},
	}
end

-- The front door's two leaves (hinged at the opening's sides, their handles in the middle), in House.door's frame.
function SandboxScenery.frontLeaves(): { FrontLeaf }
	local F = SandboxScenery.FrontDoor
	local half = F.Width / 2
	return { leafOf(F, -half / 2, half, -1), leafOf(F, half / 2, half, 1) }
end

-- The back door's leaf (hinged at BackDoor.Hinge's side), in House.back's frame.
function SandboxScenery.backLeaves(): { FrontLeaf }
	local B = SandboxScenery.BackDoor
	return { leafOf(B, 0, B.Width, B.Hinge) }
end

return SandboxScenery
