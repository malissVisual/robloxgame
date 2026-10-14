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
--                  the edge lines, the give-way line where Main Street meets Depot Row)
--   The house      the curb-to-door Path, the garden's fence round its lot (decoration: nothing stops a mover), the
--                  gate with its THE ALPINE LODGE board, the mailbox, the flower boxes (8.3: the house itself is
--                  shared/LodgeLooks.luau's lodge, on SandboxMap.House.house; it took The Old Chalet's place)
--   The scenery    the alpine spruces (shared/AlpineLayout.luau's two-part trees) in copses and along the edges, never
--                  on a road, a plot, the house's lot or a van's way; wildflower patches; a rail fence round the edge
--                  (the invisible walls are at the Bounds); the street lamps along Main Street; the signpost at the
--                  crossroads
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
--   SandboxScenery.lodgeSpec()          8.3: the lodge's look's numbers (shared/LodgeLooks.luau Spec) on House.house;
--                                       Lodge.Ground its ground floor's top, TerracePath the terrace door's gravel path
--   SandboxScenery.circleOut(x, z)      how far (x, z) is outside the turnaround's asphalt (≤ 0: on it)
--   SandboxScenery.outside(x, z)        how far (x, z) is outside the Bounds (≤ 0: inside)
--   SandboxScenery.rectDistance(r, x, z)   how far (x, z) is from a rect (0 inside)

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
local HOUSE = MAP.House
local TURN = MAP.Turnaround

-- ── The numbers ────────────────────────────────────────────────────────────

SandboxScenery.Budget = 2500 -- parts in workspace.Sandbox at most
SandboxScenery.Run = 4 -- the shoulders: from the asphalt's top down to the meadow over this many studs (1 in 10)
SandboxScenery.RoadDepth = 1 -- the asphalt slabs' thickness (their bottom under the meadow's top)
SandboxScenery.TurnaroundTop = MAP.RoadTop - 0.02 -- (a hair under Main Street's slab where they overlap: no flicker)
SandboxScenery.RingPieces = 24 -- the turnaround's shoulder and edge line, in this many straight pieces
SandboxScenery.Shadow = { Long = 4, Wide = 1 } -- a part throws a shadow only this big (and RenderBudget's rule)
SandboxScenery.FenceInset = 4 -- the rail fence this far inside the Bounds (the invisible walls on them)
SandboxScenery.FencePost = 16 -- studs between two posts
SandboxScenery.WallHeight = 300
SandboxScenery.Path = { x0 = HOUSE.door.x - 3, x1 = HOUSE.door.x + 3, z0 = HOUSE.curb.z, z1 = HOUSE.door.z } :: Rect -- the curb to the door, kept clear
-- 8.3 the lodge: its ground floor's top (the balcony's floor) and the gravel path from its terrace door (the deck in front
-- of it, shared/LodgeLooks.luau) along the east side and the front to the front path (decoration, on the lot)
SandboxScenery.Lodge = { Ground = 10 }
SandboxScenery.TerracePath = {
	{ x0 = HOUSE.back.x + 4, x1 = HOUSE.back.x + 8, z0 = HOUSE.door.z - 8, z1 = HOUSE.back.z - 5.5 },
	{ x0 = HOUSE.door.x + 3, x1 = HOUSE.back.x + 8, z0 = HOUSE.door.z - 8, z1 = HOUSE.door.z - 4 },
} :: { Rect }
SandboxScenery.Garden = { Front = HOUSE.lot.z0 + 6, Gate = 6, Inset = 1, Post = 8, Height = 3.2 } -- the lot's fence: its front line, the gate's half width
SandboxScenery.Clear = { Road = 12, Turnaround = 14, Plot = 8, Lot = 6, Sign = 8, Edge = 2, Trees = 0.85, Flowers = 2 }
SandboxScenery.Trees = { Height = { 28, 50 } :: { number }, Edge = { 24, 34 } :: { number }, Canopy = 0.19, Chunk = 128, Max = 120 }
SandboxScenery.Light = {
	Clock = 15.4, -- a fixed afternoon (Lighting.ClockTime)
	Latitude = 47, -- the Alps
	Brightness = 2,
	Exposure = 0,
	Ambient = { 80, 74, 72 } :: { number },
	Outdoor = { 124, 118, 112 } :: { number },
	ShiftTop = { 64, 42, 16 } :: { number }, -- (the sun's warm tint)
	ShiftBottom = { 12, 10, 8 } :: { number },
	Diffuse = 0.55,
	Specular = 0.6,
	Softness = 0.3,
	Air = { 200, 204, 212 } :: { number },
	Decay = { 132, 136, 150 } :: { number },
	Density = 0.26,
	Offset = 0.12,
	Glare = 0.6,
	Haze = 1.3,
	Fog = { 1200, 4000 } :: { number }, -- (only when nothing else draws the air: an Atmosphere does)
	Tint = { 255, 246, 232 } :: { number },
	Saturation = 0.06,
	Contrast = 0.1,
	Lift = 0.01,
	Clouds = { Cover = 0.42, Density = 0.45, Color = { 255, 250, 242 } :: { number } },
	Sun = 12, -- the sun's size (degrees)
}
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

-- 8.3 the lodge's look on House.house (shared/LodgeLooks.luau's Spec): its walls' box, its ground floor, the terrace door
-- this far back along the east wall, the front door's width.
function SandboxScenery.lodgeSpec(): { w: number, h: number, d: number, ground: number, terrace: number, doorWidth: number }
	local box = HOUSE.house
	return { w = box.sx, h = box.sy, d = box.sz, ground = SandboxScenery.Lodge.Ground, terrace = HOUSE.back.z - HOUSE.door.z, doorWidth = HOUSE.doorWidth }
end

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

local MOUNDS: { { number } } = { -- x, z, base (the cap's radius at the ground), height
	{ -205, 120, 44, 4.2 },
	{ -120, 250, 34, 3.2 },
	{ -265, 330, 40, 4 },
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

-- Main Street's shoulders stop here (the turnaround's ring takes over).
SandboxScenery.MainShoulderEnd = TURN.z - 30

function SandboxScenery.ramps(): { Ramp }
	local run, top = SandboxScenery.Run, MAP.RoadTop
	local list: { Ramp } = {}
	local depot, main = MAP.Roads[2], MAP.Roads[1]
	-- Depot Row: the north side (to the plots' pads), the south side either side of Main Street, both ends and their hips.
	-- (A concave corner, where Depot Row's south side meets Main Street's, is two shoulders over the same square: their
	-- higher one is the ground there.)
	edge(list, depot.x0, depot.x1, depot.z0 - run, depot.z0, 0, -1, top)
	edge(list, depot.x0, main.x0, depot.z1, depot.z1 + run, 0, 1, top)
	edge(list, main.x1, depot.x1, depot.z1, depot.z1 + run, 0, 1, top)
	edge(list, depot.x0 - run, depot.x0, depot.z0, depot.z1, -1, 0, top)
	edge(list, depot.x1, depot.x1 + run, depot.z0, depot.z1, 1, 0, top)
	corner(list, depot.x0, depot.z0, -1, -1, top)
	corner(list, depot.x0, depot.z1, -1, 1, top)
	corner(list, depot.x1, depot.z0, 1, -1, top)
	corner(list, depot.x1, depot.z1, 1, 1, top)
	-- Main Street: both sides from Depot Row to the turnaround.
	local stop = SandboxScenery.MainShoulderEnd
	edge(list, main.x0 - run, main.x0, depot.z1, stop, -1, 0, top)
	edge(list, main.x1, main.x1 + run, depot.z1, stop, 1, 0, top)
	-- The turnaround: a ring of wedges (each on a chord just inside the asphalt's edge, wide enough to close the ring
	-- at its foot), none where Main Street comes in (its own asphalt there).
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
	-- Main Street's, up to where they meet the turnaround's (a circle `inset` inside its edge)
	local r = TURN.r - inset
	local function meet(x: number): number
		return TURN.z - math.sqrt(r * r - (x - TURN.x) ^ 2)
	end
	local westX, eastX = main.x0 + inset, main.x1 - inset
	strip(list, "EdgeLine", westX, depot.z1 - inset, westX, meet(westX), w, top)
	strip(list, "EdgeLine", eastX, depot.z1 - inset, eastX, meet(eastX), w, top)
	-- the give-way line across Main Street's northbound lane (the right-hand one) where it meets Depot Row
	strip(list, "GiveWay", main.x0 + (main.x1 - main.x0) / 2 + 0.6, depot.z1 + 1.2, eastX - 0.3, depot.z1 + 1.2, 0.6, top)
	-- the turnaround's, in straight pieces from Main Street's east edge line round the south to its west one
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

-- The vans' ways off the asphalt: each plot's apron from the van's spot to Depot Row, the house's curb.
function SandboxScenery.vanPaths(): { Rect }
	local list: { Rect } = {}
	local depot = MAP.Roads[2]
	for _, plot in MAP.Plots do
		local v = plot.vanSpot
		table.insert(list, { x0 = v.x - 14, x1 = v.x + 14, z0 = v.z - 14, z1 = depot.z0 })
	end
	local c = HOUSE.curb
	table.insert(list, { x0 = c.x - 14, x1 = c.x + 14, z0 = c.z - 14, z1 = c.z + 14 })
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
	if rectDistance(HOUSE.lot, x, z) < r + C.Lot then
		return "house"
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

-- The copses (x, z, radius, trees) on the meadows either side of Main Street, then the rows along the edges.
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
	row(BOUNDS.x0 + 18, BOUNDS.z0 + 22, BOUNDS.x1 - 18, BOUNDS.z0 + 22, 30, 9, 0.8)
	row(BOUNDS.x0 + 18, BOUNDS.z1 - 19, BOUNDS.x1 - 18, BOUNDS.z1 - 19, 32, 9, 0.75)
	row(BOUNDS.x0 + 36, -225, BOUNDS.x0 + 36, -85, 30, 6, 0.9)
	row(BOUNDS.x1 - 36, -225, BOUNDS.x1 - 36, -85, 30, 6, 0.9)
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

-- The street lamps along Main Street, either side in turn, off its shoulders, their arms out over the asphalt.
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

-- The rail fence round the world, FenceInset inside the Bounds.
function SandboxScenery.fence(): { Segment }
	local i = SandboxScenery.FenceInset
	local x0, x1, z0, z1 = BOUNDS.x0 + i, BOUNDS.x1 - i, BOUNDS.z0 + i, BOUNDS.z1 - i
	return {
		{ ax = x0, az = z0, bx = x1, bz = z0 },
		{ ax = x1, az = z0, bx = x1, bz = z1 },
		{ ax = x1, az = z1, bx = x0, bz = z1 },
		{ ax = x0, az = z1, bx = x0, bz = z0 },
	}
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
		{ text = "THE ALPINE LODGE →", back = "← THE ALPINE LODGE", dx = 0, dz = 1, y = 7.8 }, -- (south, down Main Street)
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

return SandboxScenery
