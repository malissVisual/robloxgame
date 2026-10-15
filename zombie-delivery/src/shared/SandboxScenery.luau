--!strict
-- 8.0 SANDBOX, the map (design/sandbox/KONTRAKT.md): the small test world's dress as plain numbers, laid round
-- shared/SandboxMap.luau's fixed data (the plots, the roads, the turnaround, the house never move). server/SandboxWorld.luau
-- builds it; tests/sandboxworld_test.luau checks the numbers and the built world. Pure (no Roblox at its top level),
-- deterministic. 8.9 Jinočany (design/jinocany/NAVRH.md): the Alps are gone (the spruces, the wildflowers, the rail
-- fence, the mounds, the green hills and the snowy peaks); the village's own dress is shared/VillageScenery.luau's.
--
--   The ground     a flat meadow (Grass, its top at SandboxMap.GroundTop) over the Bounds in a few tiles that leave
--                  out the plots' concrete pads, the house's lawn and 8.9 the village's fields and lawns
--                  (SandboxMap.Fields, Lawns: each flush with it, no two tops on one plane)
--   The roads      the asphalt (SandboxMap.Roads, the Turnaround) stands RoadTop over the meadow; every edge drops back
--                  to it on a gravel shoulder, a slope Run studs wide (a wedge: the cars' frictionless wheels roll up
--                  and down it anywhere, like the city's kerbs in shared/CurbShape.luau, only gentler), a hip at a
--                  convex corner, a ring of wedges round the turnaround; 8.9 every street's edges but where another
--                  street's asphalt goes on (a junction: no shoulder across it) or the Bounds end it (Hornická at the
--                  map's west edge); the white markings (a dashed centre line, the edge lines, the give-way line where
--                  Pražská meets Depot Row; Pražská's edge line open where Mirešická comes in; a village lane none)
--   The house      the curb-to-door Path, the garden's fence round its lot (decoration: nothing stops a mover), the
--                  gate with its THE OLD FARMSTEAD board, the mailbox, the flower boxes (the house itself is
--                  shared/ChaletLooks.luau's, on SandboxMap.House.house; 8.1: the owner's Blender house once imported)
--   The scenery    the street lamps along Pražská; the signpost at the crossroads; where a tree may stand (treeRule:
--                  never on a road, a plot, a house to empty's lot or a van's way: Jinočany's six houses' lots and
--                  curbs, SandboxMap.Houses, the farmstead's among them)
--
--   SandboxScenery.meadow()             the meadow's tiles (Rects) and the holes they leave (holes(): the pads, the
--                                       lawn, the fields, the village's lawns)
--   SandboxScenery.groundAt(x, z)       the ground's top there (8.9: flat, GroundTop everywhere)
--   SandboxScenery.asphalt()            8.9: the asphalt's slabs (a road's name and rect; Pražská's from Depot Row's
--                                       south edge: the junction is Depot Row's), none over another
--   SandboxScenery.ramps()              the roads' shoulders (wedges as CurbShape's pieces: kind, middle, size, X axis)
--   SandboxScenery.shoulderAt(ramp, x, z)   a shoulder's top at (x, z) (nil: not over it)
--   SandboxScenery.markings()           the white lines (flat strips: middle, length, width, direction, the top under)
--   SandboxScenery.treeRule(x, z, r)    why nothing r wide may grow there (nil: it may)
--   SandboxScenery.lamps(), garden(), signpost(), vanPaths()
--   SandboxScenery.circleOut(x, z)      how far (x, z) is outside the turnaround's asphalt (≤ 0: on it)
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
-- A road marking: a flat white strip `length` along (dx, dz), `width` across, its middle at (x, z) on a surface `top`.
export type Strip = { name: string, x: number, z: number, length: number, width: number, dx: number, dz: number, top: number }
-- 8.9: a slab of asphalt (a road's, SandboxMap.Roads' name; Pražská's from Depot Row's south edge)
export type Slab = { name: string, x0: number, x1: number, z0: number, z1: number }
export type Lamp = { x: number, z: number, rx: number, rz: number } -- its arm reaches (rx, rz) out over the road
export type Segment = { ax: number, az: number, bx: number, bz: number }
export type Board = { text: string, back: string, dx: number, dz: number, y: number } -- points (dx, dz); `text` on its north/west face

local MAP = SandboxMap
local BOUNDS = MAP.Bounds
local HOUSE = MAP.House
local TURN = MAP.Turnaround

-- ── The numbers ────────────────────────────────────────────────────────────

SandboxScenery.Budget = 2500 -- parts in workspace.Sandbox at most
SandboxScenery.Run = 4 -- the shoulders: from the asphalt's top down to the meadow over this many studs (1 in 10)
SandboxScenery.RoadDepth = 1 -- the asphalt slabs' thickness (their bottom under the meadow's top)
SandboxScenery.TurnaroundTop = MAP.RoadTop - 0.02 -- (a hair under Pražská's slab where they overlap: no flicker)
SandboxScenery.RingPieces = 24 -- the turnaround's shoulder and edge line, in this many straight pieces
SandboxScenery.Shadow = { Long = 4, Wide = 1 } -- a part throws a shadow only this big (and RenderBudget's rule)
SandboxScenery.WallHeight = 300 -- the invisible walls on the Bounds
-- the chalet on House.house (its walls the box's height), its dice: "tyrol". 8.1: Pitch is the owner's Blender house's roof
-- (design/blender-house/house.py PITCH): dressed in it (server/HouseMesh.luau), the chalet's gable wedges are re-cut to
-- a gable this steep across the house, under that roof (tools/house-art/check.py checks it against the model). 8.2.1:
-- the big house's 31° (house.py TARGET "sandbox", the manifest's "pitch")
SandboxScenery.Chalet = { Seed = 1, Render = 2, Shade = 0, Pitch = 31 }
SandboxScenery.Path = { x0 = HOUSE.door.x - 3, x1 = HOUSE.door.x + 3, z0 = HOUSE.curb.z, z1 = HOUSE.door.z } :: Rect -- the curb to the door, kept clear
SandboxScenery.Garden = { Front = HOUSE.lot.z0 + 6, Gate = 6, Inset = 1, Post = 8, Height = 3.2 } -- the lot's fence: its front line, the gate's half width
-- studs kept clear round a road (its shoulder in it), the turnaround, a plot, the house's lot, the signpost and inside the
-- Bounds (8.9: the edge's invisible walls; the rail fence that stood 4 in is gone), two trees' crowns this share of
-- their radii apart
SandboxScenery.Clear = { Road = 12, Turnaround = 14, Plot = 8, Lot = 6, Sign = 8, Edge = 6, Trees = 0.85 }
SandboxScenery.Light = Config.SandboxLight.Sky -- 8.3: the afternoon's light lives in Config with the rest of the light
SandboxScenery.Colors = {
	Meadow = { 96, 138, 60 } :: { number },
	Lawn = { 108, 152, 64 } :: { number },
	Pad = { 176, 174, 168 } :: { number },
	Asphalt = { 52, 52, 56 } :: { number },
	Shoulder = { 138, 130, 116 } :: { number },
	Line = { 236, 236, 228 } :: { number },
	Fence = { 120, 86, 56 } :: { number },
	Path = { 178, 168, 148 } :: { number },
	Sign = { 244, 244, 238 } :: { number }, -- 8.9: the signpost's boards (a Czech village's white direction signs)
	Ink = { 30, 30, 34 } :: { number },
}

-- ── Small tools ────────────────────────────────────────────────────────────

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function SandboxScenery.rectDistance(r: Rect, x: number, z: number): number
	local dx = math.max(r.x0 - x, 0, x - r.x1)
	local dz = math.max(r.z0 - z, 0, z - r.z1)
	return math.sqrt(dx * dx + dz * dz)
end
local rectDistance = SandboxScenery.rectDistance

function SandboxScenery.circleOut(x: number, z: number): number
	return math.sqrt((x - TURN.x) ^ 2 + (z - TURN.z) ^ 2) - TURN.r
end

-- ── The ground ─────────────────────────────────────────────────────────────

-- The holes in the meadow: the plots' pads, the house's lawn and 8.9 the village's fields and lawns (each its own part,
-- flush with the meadow).
function SandboxScenery.holes(): { Rect }
	local list: { Rect } = {}
	for _, plot in MAP.Plots do
		table.insert(list, plot.rect)
	end
	table.insert(list, HOUSE.lot)
	for _, f in MAP.Fields do
		table.insert(list, { x0 = f.x0, x1 = f.x1, z0 = f.z0, z1 = f.z1 })
	end
	for _, lawn in MAP.Lawns do
		table.insert(list, lawn)
	end
	return list
end

-- The meadow's tiles: the Bounds less the holes, in bands along z, 8.9 a tile joined to the one before it in z when
-- they meet edge to edge with the same sides (fewer parts round the fields); no two tiles overlap, none longer than a
-- part may be.
function SandboxScenery.meadow(): ({ Rect }, { Rect })
	local holes = SandboxScenery.holes()
	local cuts = { BOUNDS.z0, BOUNDS.z1 }
	for _, h in holes do
		table.insert(cuts, h.z0)
		table.insert(cuts, h.z1)
	end
	table.sort(cuts)
	local tiles: { Rect } = {}
	for i = 1, #cuts - 1 do
		local z0, z1 = cuts[i], cuts[i + 1]
		if z1 - z0 > 1e-6 then
			local open = { { BOUNDS.x0, BOUNDS.x1 } }
			for _, h in holes do
				if h.z0 < z1 - 1e-6 and h.z1 > z0 + 1e-6 then
					local next: { { number } } = {}
					for _, span in open do
						if h.x1 <= span[1] or h.x0 >= span[2] then
							table.insert(next, span)
						else
							if h.x0 > span[1] then
								table.insert(next, { span[1], h.x0 })
							end
							if h.x1 < span[2] then
								table.insert(next, { h.x1, span[2] })
							end
						end
					end
					open = next
				end
			end
			for _, span in open do
				local joined = false
				for _, t in tiles do
					if t.x0 == span[1] and t.x1 == span[2] and math.abs(t.z1 - z0) < 1e-6 then
						t.z1 = z1
						joined = true
						break
					end
				end
				if not joined then
					table.insert(tiles, { x0 = span[1], x1 = span[2], z0 = z0, z1 = z1 })
				end
			end
		end
	end
	return tiles, holes
end

-- The ground's top at (x, z) off the asphalt (8.9: flat everywhere, the Alps' mounds are gone).
function SandboxScenery.groundAt(x: number, z: number): number
	return MAP.GroundTop
end

-- ── The roads' shoulders ───────────────────────────────────────────────────

local function edge(list: { Ramp }, x0: number, x1: number, z0: number, z1: number, nx: number, nz: number, top: number)
	-- the shoulder over the rect (x0 … x1, z0 … z1) of the meadow, falling away from the asphalt along (nx, nz)
	local along = if nx ~= 0 then z1 - z0 else x1 - x0
	local run = if nx ~= 0 then x1 - x0 else z1 - z0
	table.insert(list, {
		kind = "edge",
		x = (x0 + x1) / 2,
		y = MAP.GroundTop + (top - MAP.GroundTop) / 2,
		z = (z0 + z1) / 2,
		sx = along,
		sy = top - MAP.GroundTop,
		sz = run,
		rx = -nz,
		rz = nx,
	})
end

local function corner(list: { Ramp }, cx: number, cz: number, sx: number, sz: number, top: number)
	-- the hip at the asphalt's convex corner (cx, cz), out toward (sx, sz) (each ±1): CurbShape's corner piece
	local run = SandboxScenery.Run
	local d1x, d1z = if sz == -sx then sx else 0, if sz == -sx then 0 else sz
	table.insert(list, {
		kind = "corner",
		x = cx + sx * run / 2,
		y = MAP.GroundTop + (top - MAP.GroundTop) / 2,
		z = cz + sz * run / 2,
		sx = run,
		sy = top - MAP.GroundTop,
		sz = run,
		rx = -d1x,
		rz = -d1z,
	})
end

-- 8.9: the asphalt's slabs: every road's rect, Pražská's from Depot Row's south edge (their junction is Depot Row's
-- asphalt): none over another.
function SandboxScenery.asphalt(): { Slab }
	local main, depot = MAP.Roads[1], MAP.Roads[2]
	local list: { Slab } = {}
	for _, road in MAP.Roads do
		table.insert(list, { name = road.name, x0 = road.x0, x1 = road.x1, z0 = if road == main then depot.z1 else road.z0, z1 = road.z1 })
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

-- The spans of a slab's side with the meadow beyond it: the side less what another slab's asphalt holds just outside
-- it (a junction: the street goes on); none where the Bounds end the road (its shoulder would be outside them).
local function openSpans(slabs: { Slab }, r: Slab, side: Side): { { number } }
	local run = SandboxScenery.Run
	local spans = { { side.a, side.b } }
	local reach = side.c + (side.nx + side.nz) * run -- (the shoulder's foot)
	if side.along == "x" then
		if reach < BOUNDS.z0 - 1e-6 or reach > BOUNDS.z1 + 1e-6 then
			return {}
		end
		spans = less(less(spans, -math.huge, BOUNDS.x0), BOUNDS.x1, math.huge)
	else
		if reach < BOUNDS.x0 - 1e-6 or reach > BOUNDS.x1 + 1e-6 then
			return {}
		end
		spans = less(less(spans, -math.huge, BOUNDS.z0), BOUNDS.z1, math.huge)
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

-- Pražská's shoulders stop here (the turnaround's ring takes over).
SandboxScenery.MainShoulderEnd = TURN.z - 30

-- The streets' shoulders: 8.9 every road of SandboxMap.Roads, each side but where another street goes on or the Bounds
-- end it (a concave corner, where a street meets another's side, is two shoulders over the same square: their higher
-- one is the ground there), a hip at every convex corner; Pražská's down to MainShoulderEnd, then the turnaround's
-- ring.
function SandboxScenery.ramps(): { Ramp }
	local run, top = SandboxScenery.Run, MAP.RoadTop
	local list: { Ramp } = {}
	local slabs = SandboxScenery.asphalt()
	local main = MAP.Roads[1]
	for _, r in slabs do
		local isMain = r.name == main.name
		local reached: { [string]: number } = {} -- (a corner's sides whose shoulder reaches it: "x0z0" …)
		for n, side in sidesOf(r) do
			if isMain and n == 2 then
				continue -- (Pražská's south end is the turnaround's)
			end
			local spans = openSpans(slabs, r, side)
			if isMain then
				spans = less(spans, SandboxScenery.MainShoulderEnd, math.huge)
			end
			for _, s in spans do
				local lo, hi = s[1], s[2]
				if hi - lo > 1e-6 then
					local corners: { string } = {}
					if side.along == "x" then
						local z0 = if side.nz < 0 then side.c - run else side.c
						edge(list, lo, hi, z0, z0 + run, 0, side.nz, top)
						local zKey = if side.nz < 0 then "z0" else "z1"
						if math.abs(lo - r.x0) < 1e-6 then
							table.insert(corners, "x0" .. zKey)
						end
						if math.abs(hi - r.x1) < 1e-6 then
							table.insert(corners, "x1" .. zKey)
						end
					else
						local x0 = if side.nx < 0 then side.c - run else side.c
						edge(list, x0, x0 + run, lo, hi, side.nx, 0, top)
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
					corner(list, cx, cz, sx, sz, top)
				end
			end
		end
	end
	-- The turnaround: a ring of wedges (each on a chord just inside the asphalt's edge, wide enough to close the ring
	-- at its foot), none where Pražská comes in (its own asphalt there).
	local n, r = SandboxScenery.RingPieces, TURN.r
	local ringTop = SandboxScenery.TurnaroundTop
	local inner = r * math.cos(math.pi / n)
	local width = 2 * (inner + run) * math.tan(math.pi / n)
	for k = 0, n - 1 do
		local a = (k + 0.5) * 2 * math.pi / n
		local nx, nz = math.cos(a), math.sin(a)
		local mx, mz = TURN.x + nx * (inner + run / 2), TURN.z + nz * (inner + run / 2)
		if not (mz < TURN.z and math.abs(mx - TURN.x) < main.x1 - 2) then
			table.insert(list, {
				kind = "edge",
				x = mx,
				y = MAP.GroundTop + (ringTop - MAP.GroundTop) / 2,
				z = mz,
				sx = width,
				sy = ringTop - MAP.GroundTop,
				sz = run,
				rx = -nz,
				rz = nx,
			})
		end
	end
	return list
end

-- The ground's top at (x, z) from the shoulders alone (the meadow under them): what a wheel rolls on.
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

-- ── The markings ───────────────────────────────────────────────────────────

local function strip(list: { Strip }, name: string, ax: number, az: number, bx: number, bz: number, width: number, top: number)
	local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	table.insert(list, { name = name, x = (ax + bx) / 2, z = (az + bz) / 2, length = length, width = width, dx = (bx - ax) / length, dz = (bz - az) / length, top = top })
end

local function dashes(list: { Strip }, ax: number, az: number, bx: number, bz: number, top: number)
	local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local dash, period = 8, 20
	local count = math.floor((length + period - dash) / period)
	local start = (length - (count * period - (period - dash))) / 2
	for i = 0, count - 1 do
		local t0, t1 = (start + i * period) / length, (start + i * period + dash) / length
		strip(list, "CentreLine", lerp(ax, bx, t0), lerp(az, bz, t0), lerp(ax, bx, t1), lerp(az, bz, t1), 0.5, top)
	end
end

function SandboxScenery.markings(): { Strip }
	local list: { Strip } = {}
	local top = MAP.RoadTop
	local depot, main = MAP.Roads[2], MAP.Roads[1]
	local mid = (depot.z0 + depot.z1) / 2
	local inset, w = 1.2, 0.45
	-- the dashed centre lines (none across the junction or into the turnaround)
	dashes(list, 0, depot.z1 + 6, 0, TURN.z - TURN.r - 4, top)
	dashes(list, depot.x0 + 4, mid, main.x0 - 6, mid, top)
	dashes(list, main.x1 + 6, mid, depot.x1 - 4, mid, top)
	-- the edge lines
	strip(list, "EdgeLine", depot.x0 + inset, depot.z0 + inset, depot.x1 - inset, depot.z0 + inset, w, top)
	strip(list, "EdgeLine", depot.x0 + inset, depot.z1 - inset, main.x0 - inset, depot.z1 - inset, w, top)
	strip(list, "EdgeLine", main.x1 + inset, depot.z1 - inset, depot.x1 - inset, depot.z1 - inset, w, top)
	-- Pražská's, up to where they meet the turnaround's (a circle `inset` inside its edge); 8.9 open where a street
	-- comes in from the side (Mirešická from the west)
	local r = TURN.r - inset
	local function meet(x: number): number
		return TURN.z - math.sqrt(r * r - (x - TURN.x) ^ 2)
	end
	local westX, eastX = main.x0 + inset, main.x1 - inset
	for _, side in { { x = westX, edge = main.x0, out = -1 }, { x = eastX, edge = main.x1, out = 1 } } do
		local spans = { { depot.z1 - inset, meet(side.x) } }
		local probe = side.edge + side.out * 0.01
		for _, q in SandboxScenery.asphalt() do
			if q.name ~= main.name and q.name ~= depot.name and q.x0 <= probe and q.x1 >= probe then
				spans = less(spans, q.z0, q.z1)
			end
		end
		for _, span in spans do
			strip(list, "EdgeLine", side.x, span[1], side.x, span[2], w, top)
		end
	end
	-- the give-way line across Pražská's northbound lane (the right-hand one) where it meets Depot Row
	strip(list, "GiveWay", main.x0 + (main.x1 - main.x0) / 2 + 0.6, depot.z1 + 1.2, eastX - 0.3, depot.z1 + 1.2, 0.6, top)
	-- the turnaround's, in straight pieces from Pražská's east edge line round the south to its west one
	local ringTop = SandboxScenery.TurnaroundTop
	local from = math.atan2(meet(eastX) - TURN.z, eastX - TURN.x)
	local to = math.atan2(meet(westX) - TURN.z, westX - TURN.x) + 2 * math.pi
	local pieces = math.max(4, math.ceil((to - from) / (2 * math.pi / SandboxScenery.RingPieces)))
	for k = 0, pieces - 1 do
		local a0, a1 = lerp(from, to, k / pieces), lerp(from, to, (k + 1) / pieces)
		strip(list, "EdgeLine", TURN.x + r * math.cos(a0), TURN.z + r * math.sin(a0), TURN.x + r * math.cos(a1), TURN.z + r * math.sin(a1), w, ringTop)
	end
	return list
end

-- ── Where things may grow ──────────────────────────────────────────────────

SandboxScenery.Signpost = { x = MAP.Roads[1].x0 - 12, z = MAP.Roads[2].z1 + 12 } -- the crossroads' south-west corner

-- The vans' ways off the asphalt: each plot's apron from the van's spot to Depot Row, every house to empty's curb
-- (Jinočany: SandboxMap.Houses', the farmstead's first).
function SandboxScenery.vanPaths(): { Rect }
	local list: { Rect } = {}
	local depot = MAP.Roads[2]
	for _, plot in MAP.Plots do
		local v = plot.vanSpot
		table.insert(list, { x0 = v.x - 14, x1 = v.x + 14, z0 = v.z - 14, z1 = depot.z0 })
	end
	for _, h in MAP.Houses do
		local c = h.curb
		table.insert(list, { x0 = c.x - 14, x1 = c.x + 14, z0 = c.z - 14, z1 = c.z + 14 })
	end
	return list
end

-- Why something `r` wide (a tree's crown) may not stand at (x, z): nil when it may. (8.9: the village's houses and
-- landmarks too: shared/VillageScenery.luau treeRule.)
function SandboxScenery.treeRule(x: number, z: number, r: number): string?
	local C = SandboxScenery.Clear
	local inset = C.Edge
	if x - r < BOUNDS.x0 + inset or x + r > BOUNDS.x1 - inset or z - r < BOUNDS.z0 + inset or z + r > BOUNDS.z1 - inset then
		return "edge"
	end
	for _, road in MAP.Roads do
		if rectDistance(road :: any, x, z) < r + C.Road then
			return "road"
		end
	end
	if SandboxScenery.circleOut(x, z) < r + C.Turnaround then
		return "turnaround"
	end
	for _, plot in MAP.Plots do
		if rectDistance(plot.rect, x, z) < r + C.Plot then
			return "plot"
		end
	end
	for _, h in MAP.Houses do -- (Jinočany: every house to empty's lot, the farmstead's first)
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
	local s = SandboxScenery.Signpost
	if math.sqrt((x - s.x) ^ 2 + (z - s.z) ^ 2) < r + C.Sign then
		return "signpost"
	end
	return nil
end

-- ── The lamps, the garden's fence, the signpost ───────────────────────────

-- The street lamps along Pražská, either side in turn, off its shoulders, their arms out over the asphalt.
function SandboxScenery.lamps(): { Lamp }
	local main = MAP.Roads[1]
	local list: { Lamp } = {}
	local out = SandboxScenery.Run + 1.5
	local z = MAP.Roads[2].z1 + 30
	local side = 1
	while z < TURN.z - TURN.r - 10 do
		local x = if side > 0 then main.x1 + out else main.x0 - out
		table.insert(list, { x = x, z = z, rx = -side, rz = 0 })
		side = -side
		z += 62
	end
	return list
end

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

-- The signpost's boards: where each points, its text on its north (or west) face and on the other.
function SandboxScenery.signpost(): { Board }
	return {
		{ text = "WAREHOUSES →", back = "← WAREHOUSES", dx = -1, dz = 0, y = 10.2 }, -- (west: plots 1 and 2)
		{ text = "← WAREHOUSES", back = "WAREHOUSES →", dx = 1, dz = 0, y = 9 }, -- (east: plots 3 and 4)
		{ text = "THE OLD FARMSTEAD →", back = "← THE OLD FARMSTEAD", dx = 0, dz = 1, y = 7.8 }, -- (south, down Pražská)
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
