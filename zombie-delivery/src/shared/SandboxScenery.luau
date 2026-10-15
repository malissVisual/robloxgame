--!strict
-- 8.0 SANDBOX, the map (design/sandbox/KONTRAKT.md): the small test world's dress as plain numbers, laid round
-- shared/SandboxMap.luau's fixed data (the plots, the roads, the turnaround, the house never move). server/SandboxWorld.luau
-- builds it; tests/sandboxworld_test.luau checks the numbers and the built world. Pure (no Roblox at its top level),
-- deterministic (its own small dice: the same world on every server, in the tests and in the preview).
--
--   The ground     a flat meadow (Grass, its top at SandboxMap.GroundTop) over the Bounds in a few tiles that leave
--                  out the plots' concrete pads and the house's lawn (each flush with it: no two tops on one plane),
--                  a few gentle mounds (the visible cap of a big buried ball) far from the roads and the plots
--   The roads      the asphalt (SandboxMap.Roads, the Turnaround) stands RoadTop over the meadow; every edge drops back
--                  to it on a gravel shoulder, a slope Run studs wide (a wedge: the cars' frictionless wheels roll up
--                  and down it anywhere, like the city's kerbs in shared/CurbShape.luau, only gentler), a hip at a
--                  convex corner, a ring of wedges round the turnaround; the white markings (a dashed centre line,
--                  the edge lines, the give-way line where Pražská meets Depot Row). Jinočany step 1: every road's
--                  edges the same way (ramps: none where another road's asphalt or the world's edge is), the
--                  village streets' markings not yet (the village's own look comes with its houses)
--   The house      the farmstead's (SandboxMap.House): the curb-to-door Path, the garden's fence round its lot
--                  (decoration: nothing stops a mover), the gate with its THE OLD FARMSTEAD board, the mailbox, the
--                  flower boxes (the house itself is shared/ChaletLooks.luau's, on SandboxMap.House.house; 8.1: the
--                  owner's Blender house once imported). Jinočany: the village's houses to empty are SandboxMap.Houses'
--                  (server/SandboxWorld.luau stands a stand-in on each)
--   The scenery    the alpine spruces (shared/AlpineLayout.luau's two-part trees) in copses and in rows round the
--                  8.0 map (OLD_EDGE: the plots, Pražská and the farmstead), never on a road, a plot, a house's lot or
--                  a van's way; wildflower patches; a rail fence round the edge (the invisible walls are at the
--                  Bounds); the street lamps along Pražská; the signpost at the crossroads
--   Far away       outside the Bounds only: the far meadow, a ring of green hills (buried balls) and a ring of rocky
--                  peaks with snow caps (four corner wedges each, as server/Alpine.luau's silhouettes), so the edge
--                  looks closed
--
--   SandboxScenery.meadow()             the meadow's tiles (Rects) and the holes they leave (holes(): the pads, the lawn)
--   SandboxScenery.mounds()             the mounds; SandboxScenery.groundAt(x, z): the ground's top there
--   SandboxScenery.ramps()              the road's shoulders (wedges as CurbShape's pieces: kind, middle, size, X axis)
--   SandboxScenery.shoulderAt(ramp, x, z)   a shoulder's top at (x, z) (nil: not over it)
--   SandboxScenery.markings()           the white lines (flat strips: middle, length, width, direction, the top under)
--   SandboxScenery.treeRule(x, z, r)    why nothing r wide may grow there (nil: it may)
--   SandboxScenery.trees()              the trees (AlpineLayout.Tree's fields: AlpineLayout.treeParts draws them)
--   SandboxScenery.flowers()            the wildflower patches
--   SandboxScenery.lamps(), fence(), garden(), signpost(), vanPaths(), farGround(), hills(), peaks()
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
-- A mound: the cap of a ball (radius `radius`, its middle `radius - height` under the ground) `base` wide at the ground.
export type Mound = { x: number, z: number, base: number, height: number, radius: number, color: { number } }
export type Tree = {
	x: number,
	y: number,
	z: number,
	height: number,
	variant: number,
	snowy: boolean,
	shadow: boolean,
	slope: boolean,
	chunk: string,
	canopy: number,
	yaw: number,
}
export type Flower = { x: number, y: number, z: number, size: number, color: { number } }
export type Lamp = { x: number, z: number, rx: number, rz: number } -- its arm reaches (rx, rz) out over the road
export type Segment = { ax: number, az: number, bx: number, bz: number }
export type Board = { text: string, back: string, dx: number, dz: number, y: number } -- points (dx, dz); `text` on its north/west face
export type Hill = { x: number, z: number, base: number, height: number, radius: number, color: { number } }
export type Peak = { x: number, z: number, yaw: number, base: number, half: number, height: number, capY: number, capHalf: number, capHeight: number }

local MAP = SandboxMap
local BOUNDS = MAP.Bounds
local HOUSE = MAP.House -- (the farmstead: its garden, path and gate are this module's)
local TURN = MAP.Turnaround
local OLD_EDGE = { x0 = -340, x1 = 340, z0 = -280, z1 = 640 } :: Rect -- (8.0 – 8.9's Bounds: the tree rows round them)

-- ── The numbers ────────────────────────────────────────────────────────────

SandboxScenery.Budget = 2500 -- parts in workspace.Sandbox at most
SandboxScenery.Run = 4 -- the shoulders: from the asphalt's top down to the meadow over this many studs (1 in 10)
SandboxScenery.RoadDepth = 1 -- the asphalt slabs' thickness (their bottom under the meadow's top)
SandboxScenery.TurnaroundTop = MAP.RoadTop - 0.02 -- (a hair under Pražská's slab where they overlap: no flicker)
SandboxScenery.RingPieces = 24 -- the turnaround's shoulder and edge line, in this many straight pieces
SandboxScenery.Shadow = { Long = 4, Wide = 1 } -- a part throws a shadow only this big (and RenderBudget's rule)
SandboxScenery.FenceInset = 4 -- the rail fence this far inside the Bounds (the invisible walls on them)
SandboxScenery.FencePost = 16 -- studs between two posts
SandboxScenery.WallHeight = 300
-- the chalet on House.house (its walls the box's height), its dice: "tyrol". 8.1: Pitch is the owner's Blender house's roof
-- (design/blender-house/house.py PITCH): dressed in it (server/HouseMesh.luau), the chalet's gable wedges are re-cut to
-- a gable this steep across the house, under that roof (tools/house-art/check.py checks it against the model). 8.2.1:
-- the big house's 31° (house.py TARGET "sandbox", the manifest's "pitch")
SandboxScenery.Chalet = { Seed = 1, Render = 2, Shade = 0, Pitch = 31 }
SandboxScenery.Path = { x0 = HOUSE.door.x - 3, x1 = HOUSE.door.x + 3, z0 = HOUSE.curb.z, z1 = HOUSE.door.z } :: Rect -- the curb to the door, kept clear
-- Jinočany: the village's houses to empty until their own look (server/SandboxWorld.luau standIn): the walls' render, the
-- red tile roof (its pitch, its eaves out of the walls), the front door (ChaletLooks' door: width, height, depth) and
-- the name board over it (its widest, its height, its middle over the ground) with its wood
SandboxScenery.StandIn = {
	Render = { 236, 226, 204 } :: { number },
	Roof = { 168, 70, 50 } :: { number },
	Door = { 96, 64, 44 } :: { number },
	Sign = { 150, 108, 66 } :: { number },
	Pitch = 35,
	Eaves = 0.8,
	DoorSize = { 4, 7, 0.4 } :: { number },
	Board = { 12, 1.4, 8.4 } :: { number },
}
SandboxScenery.Garden = { Front = HOUSE.lot.z0 + 6, Gate = 6, Inset = 1, Post = 8, Height = 3.2 } -- the lot's fence: its front line, the gate's half width
SandboxScenery.Clear = { Road = 12, Turnaround = 14, Plot = 8, Lot = 6, Sign = 8, Edge = 2, Trees = 0.85, Flowers = 2 }
SandboxScenery.Trees = { Height = { 28, 50 } :: { number }, Edge = { 24, 34 } :: { number }, Canopy = 0.19, Chunk = 128, Max = 120 }
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
	Far = { 88, 128, 56 } :: { number },
	Rock = { 118, 116, 112 } :: { number },
	Snow = { 242, 245, 248 } :: { number },
	Hills = { { 52, 80, 48 }, { 62, 92, 54 }, { 76, 106, 60 } } :: { { number } },
}

-- ── Small tools ────────────────────────────────────────────────────────────

-- The dice: a Lehmer generator, exact in doubles (48271 × 2³¹ < 2⁵³).
local function dice(seed: number): () -> number
	local state = math.floor(seed) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	return function(): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end
end

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

-- The holes in the meadow: the plots' pads and the house's lawn (each its own part, flush with the meadow).
function SandboxScenery.holes(): { Rect }
	local list: { Rect } = {}
	for _, plot in MAP.Plots do
		table.insert(list, plot.rect)
	end
	table.insert(list, HOUSE.lot)
	return list
end

-- The meadow's tiles: the Bounds less the holes, in bands along z (no two tiles overlap; none longer than a part may be).
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
				table.insert(tiles, { x0 = span[1], x1 = span[2], z0 = z0, z1 = z1 })
			end
		end
	end
	return tiles, holes
end

local MOUNDS: { { number } } = { -- x, z, base (the cap's radius at the ground), height (Jinočany: none on Mirešická)
	{ -205, 120, 44, 4.2 },
	{ -120, 250, 34, 3.2 },
	{ -170, 460, 48, 4.6 },
	{ 190, 140, 46, 4.4 },
	{ 110, 270, 32, 3 },
	{ 255, 380, 50, 5 },
	{ 230, 560, 38, 3.6 },
}

function SandboxScenery.mounds(): { Mound }
	local list: { Mound } = {}
	for n, m in MOUNDS do
		local base, height = m[3], m[4]
		local tone = SandboxScenery.Colors.Meadow
		local shade = (n % 3) * 3 - 3
		table.insert(list, {
			x = m[1],
			z = m[2],
			base = base,
			height = height,
			radius = (base * base + height * height) / (2 * height),
			color = { tone[1] + shade, tone[2] + shade * 2, tone[3] + shade },
		})
	end
	return list
end

-- The ground's top at (x, z) off the asphalt: the meadow, or a mound's cap.
function SandboxScenery.groundAt(x: number, z: number): number
	local top = MAP.GroundTop
	for _, m in SandboxScenery.mounds() do
		local d2 = (x - m.x) ^ 2 + (z - m.z) ^ 2
		if d2 < m.base * m.base then
			top = math.max(top, MAP.GroundTop + math.sqrt(m.radius * m.radius - d2) - (m.radius - m.height))
		end
	end
	return top
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

-- Pražská's shoulders stop here (the turnaround's ring takes over).
SandboxScenery.MainShoulderEnd = TURN.z - 30

-- Is (x, z) on a road's asphalt (SandboxMap.Roads' rects, their edges in)?
local function onRoads(x: number, z: number): boolean
	for _, r in MAP.Roads do
		if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
			return true
		end
	end
	return false
end

-- The stretches of road `index`'s edge with meadow beyond it: the edge runs along X (`alongX`) or Z from `a` to `b`,
-- across at `at`, the meadow `out` (±1) of it. Where another road's asphalt lies just beyond it (a junction), or the
-- world's edge, none.
local function openSpans(index: number, alongX: boolean, a: number, b: number, at: number, out: number): { { number } }
	local probe = at + out * 0.5
	if (alongX and (probe < BOUNDS.z0 or probe > BOUNDS.z1)) or (not alongX and (probe < BOUNDS.x0 or probe > BOUNDS.x1)) then
		return {}
	end
	local spans: { { number } } = { { a, b } }
	for j, other in MAP.Roads do
		local lo, hi = if alongX then other.x0 else other.z0, if alongX then other.x1 else other.z1
		local near, far = if alongX then other.z0 else other.x0, if alongX then other.z1 else other.x1
		if j ~= index and probe > near and probe < far then
			local left: { { number } } = {}
			for _, s in spans do
				if hi <= s[1] or lo >= s[2] then
					table.insert(left, s)
				else
					if lo > s[1] then
						table.insert(left, { s[1], lo })
					end
					if hi < s[2] then
						table.insert(left, { hi, s[2] })
					end
				end
			end
			spans = left
		end
	end
	return spans
end

-- Does one of `spans` start (or end, `atEnd`) at `v`?
local function spanAt(spans: { { number } }, v: number, atEnd: boolean): boolean
	for _, s in spans do
		if math.abs((if atEnd then s[2] else s[1]) - v) < 1e-6 then
			return true
		end
	end
	return false
end

function SandboxScenery.ramps(): { Ramp }
	local run, top = SandboxScenery.Run, MAP.RoadTop
	local list: { Ramp } = {}
	local depot = MAP.Roads[2]
	-- Every road but Pražská: each side where meadow lies beyond it, and a hip at each convex corner (both its sides
	-- open there, no asphalt past it). (A concave corner, where one road's side meets another's, as Depot Row's south
	-- side meets Pražská's, is two shoulders over the same square: their higher one is the ground there.)
	for index, r in MAP.Roads do
		if index == 1 then
			continue
		end
		local north = openSpans(index, true, r.x0, r.x1, r.z0, -1)
		local south = openSpans(index, true, r.x0, r.x1, r.z1, 1)
		local west = openSpans(index, false, r.z0, r.z1, r.x0, -1)
		local east = openSpans(index, false, r.z0, r.z1, r.x1, 1)
		for _, s in north do
			edge(list, s[1], s[2], r.z0 - run, r.z0, 0, -1, top)
		end
		for _, s in south do
			edge(list, s[1], s[2], r.z1, r.z1 + run, 0, 1, top)
		end
		for _, s in west do
			edge(list, r.x0 - run, r.x0, s[1], s[2], -1, 0, top)
		end
		for _, s in east do
			edge(list, r.x1, r.x1 + run, s[1], s[2], 1, 0, top)
		end
		for _, c in { { r.x0, r.z0, -1, -1 }, { r.x0, r.z1, -1, 1 }, { r.x1, r.z0, 1, -1 }, { r.x1, r.z1, 1, 1 } } do
			local cx, cz, sx, sz = c[1], c[2], c[3], c[4]
			local along = if sz < 0 then north else south -- (the side along X at this corner)
			local across = if sx < 0 then west else east
			local px, pz = cx + sx * 0.5, cz + sz * 0.5
			if spanAt(along, cx, sx > 0) and spanAt(across, cz, sz > 0) and not onRoads(px, pz)
				and px > BOUNDS.x0 and px < BOUNDS.x1 and pz > BOUNDS.z0 and pz < BOUNDS.z1 then
				corner(list, cx, cz, sx, sz, top)
			end
		end
	end
	-- Pražská: both sides from Depot Row to the turnaround (Jinočany: none where Mirešická comes in).
	local main = MAP.Roads[1]
	local stop = SandboxScenery.MainShoulderEnd
	for _, s in openSpans(1, false, depot.z1, stop, main.x0, -1) do
		edge(list, main.x0 - run, main.x0, s[1], s[2], -1, 0, top)
	end
	for _, s in openSpans(1, false, depot.z1, stop, main.x1, 1) do
		edge(list, main.x1, main.x1 + run, s[1], s[2], 1, 0, top)
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
	-- Pražská's, up to where they meet the turnaround's (a circle `inset` inside its edge)
	local r = TURN.r - inset
	local function meet(x: number): number
		return TURN.z - math.sqrt(r * r - (x - TURN.x) ^ 2)
	end
	local westX, eastX = main.x0 + inset, main.x1 - inset
	-- (Jinočany: the west one stops at a street coming in from the west, Mirešická, and goes on past it)
	local westFrom = depot.z1 - inset
	for index, road in MAP.Roads do
		if index > 2 and math.abs(road.x1 - main.x0) < 1e-6 and road.z0 > westFrom then
			strip(list, "EdgeLine", westX, westFrom, westX, road.z0 - inset, w, top)
			westFrom = road.z1 + inset
		end
	end
	strip(list, "EdgeLine", westX, westFrom, westX, meet(westX), w, top)
	strip(list, "EdgeLine", eastX, depot.z1 - inset, eastX, meet(eastX), w, top)
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

-- The vans' ways off the asphalt: each plot's apron from the van's spot to Depot Row, every house's curb (Jinočany:
-- SandboxMap.Houses', the farmstead's first).
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

-- Why something `r` wide (a tree's canopy, a flower) may not stand at (x, z): nil when it may.
function SandboxScenery.treeRule(x: number, z: number, r: number): string?
	local C = SandboxScenery.Clear
	local inset = SandboxScenery.FenceInset + C.Edge
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
	for _, h in MAP.Houses do -- (Jinočany: every house to empty, the farmstead first)
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

-- ── The trees ──────────────────────────────────────────────────────────────

-- The copses (x, z, radius, trees) on the meadows either side of Pražská, then the rows along the edges.
local COPSES: { { number } } = {
	{ -95, 40, 34, 5 },
	{ -215, 15, 40, 5 },
	{ -290, 170, 40, 5 },
	{ -150, 175, 30, 4 },
	{ -240, 270, 36, 5 },
	{ -95, 360, 34, 5 },
	{ -275, 470, 40, 5 },
	{ -150, 560, 36, 4 },
	{ 95, 60, 30, 4 },
	{ 250, 60, 40, 5 },
	{ 165, 230, 34, 5 },
	{ 290, 260, 34, 4 },
	{ 120, 420, 36, 5 },
	{ 275, 480, 40, 5 },
	{ 140, 575, 30, 4 },
}

local treeCache: { Tree }? = nil

function SandboxScenery.trees(): { Tree }
	if treeCache then
		return treeCache
	end
	local T = SandboxScenery.Trees
	local roll = dice(8011)
	local list: { Tree } = {}
	local function try(x: number, z: number, height: number): boolean
		if #list >= T.Max then
			return false
		end
		local canopy = height * T.Canopy
		if SandboxScenery.treeRule(x, z, canopy) then
			return false
		end
		for _, t in list do
			local apart = math.max(10, (t.canopy + canopy) * SandboxScenery.Clear.Trees)
			if (t.x - x) ^ 2 + (t.z - z) ^ 2 < apart * apart then
				return false
			end
		end
		table.insert(list, {
			x = x,
			y = SandboxScenery.groundAt(x, z) - 0.3,
			z = z,
			height = height,
			variant = 1 + math.floor(roll() * 3) % 3,
			snowy = false,
			shadow = true,
			slope = false,
			chunk = `{math.floor(x / T.Chunk)}_{math.floor(z / T.Chunk)}`,
			canopy = canopy,
			yaw = roll() * 2 * math.pi,
		})
		return true
	end
	-- the rows first (they close the edges): behind the warehouses, behind the house, beyond the outer plots (smaller
	-- trees: the strips are narrow)
	local function row(ax: number, az: number, bx: number, bz: number, step: number, jitter: number, keep: number)
		local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local count = math.floor(length / step)
		for i = 0, count do
			local t = i / math.max(count, 1)
			local x = lerp(ax, bx, t) + (roll() - 0.5) * 2 * jitter * (if ax == bx then 0.2 else 1)
			local z = lerp(az, bz, t) + (roll() - 0.5) * 2 * jitter * (if az == bz then 0.2 else 1)
			local height = lerp(T.Edge[1], T.Edge[2], roll())
			if roll() < keep then
				try(x, z, height)
			end
		end
	end
	-- (Jinočany: round the 8.0 map, OLD_EDGE, as before the Bounds grew: the village's own trees come with its look)
	local edge = OLD_EDGE
	row(edge.x0 + 18, edge.z0 + 22, edge.x1 - 18, edge.z0 + 22, 30, 9, 0.8)
	row(edge.x0 + 18, edge.z1 - 19, edge.x1 - 18, edge.z1 - 19, 32, 9, 0.75)
	row(edge.x0 + 36, -225, edge.x0 + 36, -85, 30, 6, 0.9)
	row(edge.x1 - 36, -225, edge.x1 - 36, -85, 30, 6, 0.9)
	-- then the copses on the meadows
	for _, copse in COPSES do
		local cx, cz, radius, count = copse[1], copse[2], copse[3], copse[4]
		local placed = 0
		for _ = 1, count * 12 do
			if placed >= count then
				break
			end
			local a, d = roll() * 2 * math.pi, math.sqrt(roll()) * radius
			if try(cx + math.cos(a) * d, cz + math.sin(a) * d, lerp(T.Height[1], T.Height[2], roll())) then
				placed += 1
			end
		end
	end
	treeCache = list
	return list
end

-- The wildflower patches: a dozen small blooms each, never under a tree's canopy.
local PATCHES: { { number } } = {
	{ -60, 120 },
	{ -185, 205 },
	{ -60, 470 },
	{ -205, 400 },
	{ 70, 160 },
	{ 215, 330 },
	{ 88, 520 },
	{ 200, -10 },
}
local BLOOMS: { { number } } = { { 250, 250, 245 }, { 246, 210, 60 }, { 170, 110, 210 }, { 230, 90, 120 }, { 110, 150, 235 } }

function SandboxScenery.flowers(): { Flower }
	local roll = dice(4242)
	local trees = SandboxScenery.trees()
	local list: { Flower } = {}
	for n, p in PATCHES do
		local tone = BLOOMS[(n - 1) % #BLOOMS + 1]
		local second = BLOOMS[n % #BLOOMS + 1]
		for _ = 1, 12 do
			local a, d = roll() * 2 * math.pi, math.sqrt(roll()) * 9
			local x, z = p[1] + math.cos(a) * d, p[2] + math.sin(a) * d
			local size = lerp(0.8, 1.3, roll())
			local clear = SandboxScenery.treeRule(x, z, SandboxScenery.Clear.Flowers) == nil
			for _, t in trees do
				if (t.x - x) ^ 2 + (t.z - z) ^ 2 < (t.canopy + 1) ^ 2 then
					clear = false
				end
			end
			if clear then
				table.insert(list, { x = x, y = SandboxScenery.groundAt(x, z) + size * 0.3, z = z, size = size, color = if roll() < 0.7 then tone else second })
			end
		end
	end
	return list
end

-- ── The lamps, the fences, the signpost ────────────────────────────────────

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

-- The rail fence round the world, FenceInset inside the Bounds. Jinočany: open where a road runs out to the world's
-- edge (Hornická, a stud clear of its asphalt either side; the invisible wall at the Bounds closes it).
function SandboxScenery.fence(): { Segment }
	local i = SandboxScenery.FenceInset
	local x0, x1, z0, z1 = BOUNDS.x0 + i, BOUNDS.x1 - i, BOUNDS.z0 + i, BOUNDS.z1 - i
	local list: { Segment } = {}
	-- one side from (ax, az) to (bx, bz), along X or Z, less the roads that cross it
	local function side(ax: number, az: number, bx: number, bz: number)
		local alongX = az == bz
		local lo, hi = if alongX then math.min(ax, bx) else math.min(az, bz), if alongX then math.max(ax, bx) else math.max(az, bz)
		local spans: { { number } } = { { lo, hi } }
		for _, r in MAP.Roads do
			local across0, across1 = if alongX then r.z0 else r.x0, if alongX then r.z1 else r.x1
			local at = if alongX then az else ax
			if at >= across0 and at <= across1 then
				local cut0, cut1 = (if alongX then r.x0 else r.z0) - 1, (if alongX then r.x1 else r.z1) + 1
				local left: { { number } } = {}
				for _, s in spans do
					if cut1 <= s[1] or cut0 >= s[2] then
						table.insert(left, s)
					else
						if cut0 > s[1] then
							table.insert(left, { s[1], cut0 })
						end
						if cut1 < s[2] then
							table.insert(left, { cut1, s[2] })
						end
					end
				end
				spans = left
			end
		end
		local forward = (if alongX then bx - ax else bz - az) > 0
		for k = 1, #spans do
			local s = spans[if forward then k else #spans + 1 - k]
			local a, b = if forward then s[1] else s[2], if forward then s[2] else s[1]
			table.insert(list, if alongX then { ax = a, az = az, bx = b, bz = bz } else { ax = ax, az = a, bx = bx, bz = b })
		end
	end
	side(x0, z0, x1, z0)
	side(x1, z0, x1, z1)
	side(x1, z1, x0, z1)
	side(x0, z1, x0, z0)
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

-- ── Far away (outside the Bounds) ──────────────────────────────────────────

SandboxScenery.FarReach = 1500 -- the far meadow reaches this far out of the Bounds

-- The far meadow round the Bounds: six tiles (none longer than a part may be).
function SandboxScenery.farGround(): { Rect }
	local b, f = BOUNDS, SandboxScenery.FarReach
	local midX = (b.x0 + b.x1) / 2
	return {
		{ x0 = b.x0 - f, x1 = midX, z0 = b.z0 - f, z1 = b.z0 },
		{ x0 = midX, x1 = b.x1 + f, z0 = b.z0 - f, z1 = b.z0 },
		{ x0 = b.x0 - f, x1 = midX, z0 = b.z1, z1 = b.z1 + f },
		{ x0 = midX, x1 = b.x1 + f, z0 = b.z1, z1 = b.z1 + f },
		{ x0 = b.x0 - f, x1 = b.x0, z0 = b.z0, z1 = b.z1 },
		{ x0 = b.x1, x1 = b.x1 + f, z0 = b.z0, z1 = b.z1 },
	}
end

-- A point `out` studs outside the Bounds at `s` (0 … 1) round them (their corners rounded), and the way out there.
local function around(s: number, out: number): (number, number, number, number)
	local b = BOUNDS
	local w, d = b.x1 - b.x0, b.z1 - b.z0
	local arc = math.pi / 2 * out
	local total = 2 * (w + d) + 4 * arc
	local t = (s % 1) * total
	local legs = {
		{ len = w, x = b.x0, z = b.z0, dx = 1, dz = 0, nx = 0, nz = -1 }, -- the north side, west to east
		{ len = arc, cx = b.x1, cz = b.z0, a = -math.pi / 2 },
		{ len = d, x = b.x1, z = b.z0, dx = 0, dz = 1, nx = 1, nz = 0 },
		{ len = arc, cx = b.x1, cz = b.z1, a = 0 },
		{ len = w, x = b.x1, z = b.z1, dx = -1, dz = 0, nx = 0, nz = 1 },
		{ len = arc, cx = b.x0, cz = b.z1, a = math.pi / 2 },
		{ len = d, x = b.x0, z = b.z1, dx = 0, dz = -1, nx = -1, nz = 0 },
		{ len = arc, cx = b.x0, cz = b.z0, a = math.pi },
	} :: { any }
	for _, leg in legs do
		if t <= leg.len or leg == legs[#legs] then
			if leg.cx then
				local a = leg.a + (t / math.max(leg.len, 1e-9)) * math.pi / 2
				local nx, nz = math.cos(a), math.sin(a)
				return leg.cx + nx * out, leg.cz + nz * out, nx, nz
			end
			return leg.x + leg.dx * t + leg.nx * out, leg.z + leg.dz * t + leg.nz * out, leg.nx, leg.nz
		end
		t -= leg.len
	end
	return b.x0, b.z0, 0, -1
end

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

-- The green hills just outside: buried balls whose caps (base wide, height high) overlap round the edge.
function SandboxScenery.hills(): { Hill }
	local roll = dice(5150)
	local list: { Hill } = {}
	local count = 20
	for i = 0, count - 1 do
		local base = lerp(170, 250, roll())
		local height = lerp(70, 140, roll())
		local x, z = around((i + 0.5 + (roll() - 0.5) * 0.3) / count, base + 30 + roll() * 40)
		table.insert(list, {
			x = x,
			z = z,
			base = base,
			height = height,
			radius = (base * base + height * height) / (2 * height),
			color = SandboxScenery.Colors.Hills[1 + math.floor(roll() * 3) % 3],
		})
	end
	return list
end

-- The rocky peaks behind them, each with its snow cap (the same slope, a little bigger: it covers the rock's top).
function SandboxScenery.peaks(): { Peak }
	local roll = dice(9091)
	local list: { Peak } = {}
	local count = 16
	for i = 0, count - 1 do
		local height = lerp(340, 560, roll())
		local half = height * lerp(0.72, 0.9, roll())
		local x, z = around((i + roll() * 0.4) / count, half * math.sqrt(2) + 140 + roll() * 220)
		local base, snow = -30, lerp(0.28, 0.38, roll())
		table.insert(list, {
			x = x,
			z = z,
			yaw = roll() * math.pi / 2,
			base = base,
			half = half,
			height = height,
			capY = base + height * (1 - snow),
			capHalf = half * snow * 1.05,
			capHeight = height * snow * 1.05,
		})
	end
	return list
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
