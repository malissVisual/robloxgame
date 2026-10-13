--!strict
-- 7.1, the Alps, step 1B (the owner: "make the map a smaller alpine valley, step by step"): the mountains round the map
-- and the forests in it, as plain numbers (Config.Alpine). Nothing you play on moves: the roads, the places, the lots
-- and the zones keep their coordinates; this only fills what is empty. server/Alpine.luau builds it, tools/alpine-preview
-- draws it, tests/alpine_test.luau checks it. Pure (no Roblox at its top level), deterministic (Map.lcg: the same on
-- every server, in the tests and in the preview).
--
--   The ring      two rows of mountains round Config.Alpine.Box (Map.Bounds today), just outside it: a front row of
--                 foothills (250 – 420 studs) whose feet stand Gap outside the box and overlap so the crest between
--                 two never drops under Seal, and a row of big peaks (480 – 700) behind it with lower shoulders. A
--                 mountain is a cone of terrain layers (Terrain:FillCylinder): grass at the foot (the forests climb
--                 it), rock above (striped with the other stone), snow over the snow line; north-west of the river, in
--                 the winter, snow with rock bands. Glacier tongues run down the tallest summer peaks, light scree
--                 fans lie at the foothills' feet. Where the river leaves the valley (north, south) the front row
--                 opens into a gorge that a big peak closes behind; the lake's far shore (east) rises out of the
--                 water. Where a road would leave the valley (Config.Alpine.Portals: the West Highway past the Old Farm)
--                 a cliff with a closed tunnel mouth.
--   Silhouettes   a square pyramid inside every big peak (Persistent parts): with streaming on, the client is sent
--                 the terrain near it only; the silhouettes stand in for the far mountains and hide inside the terrain
--                 when it is there.
--   The forests   alpine spruce and fir (a trunk and three tiers, three greens, snowy tops in the winter) on the open
--                 land between the districts and up the ring's lower slopes: in patches (two sizes of value noise),
--                 thinner near town, denser toward the mountains, meadows left open with wildflowers and a few hay
--                 barns and huts; never on a road (nor near a junction: the drivers' view), a district, a lot, a
--                 yard, a place, the water or a zone.
--
--   AlpineLayout.ring(box?)              the ring for this box (Config.Alpine.Box; cached for the default box)
--   AlpineLayout.layerAt(cone, i)        the middle of a cone's layer i (the lean moves it)
--   AlpineLayout.layerMaterial(cone, i, y)   that layer's terrain material
--   AlpineLayout.heightAt(ring, x, z)    the terrain's top there from the ring (-inf: none) and the cone that makes it
--   AlpineLayout.sealed(ring, cell, swim)   does the ring hold the box? (a flood from inside never gets out over ground
--                                        lower than Seal; swim: the water counts as a way out too)
--   AlpineLayout.boxDistance(box, x, z)  how far (x, z) is outside the box (≤ 0: inside)
--   AlpineLayout.forest(ring?)           the trees, the flower patches and the huts (cached for the default ring)
--   AlpineLayout.treeRule(x, z, canopy)  why a tree may not stand there in the valley (nil: it may)
--   AlpineLayout.roadEdge(x, z)          the distance to the nearest road's edge
--   AlpineLayout.treeParts(tree)         its parts (a trunk cylinder, three ellipsoid tiers) as plain numbers
--   AlpineLayout.hutParts(hut)           a hut's or a hay barn's parts as plain numbers
--   AlpineLayout.portalParts(portal)     a portal's parts and boards (the road, the barrier, the tunnel's portal)
--   AlpineLayout.waterfallParts(ring)    the waterfall's parts
--   AlpineLayout.chunkOf(x, z)           the forest chunk (one Atomic model) a point is in
--   AlpineLayout.volume(fills)           the studs³ the terrain fills hold (overlaps counted twice)
--   AlpineLayout.parts(ring, forest)     how many parts all of it builds

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)

local AlpineLayout = {}

local A = Config.Alpine
local LAYER = A.Layer
local TURN = 300 -- studs of the ring's parameter a corner of the box turns over (the edge point stays at the corner)
local CELL = 500 -- the cones' lookup grid

export type Box = { x0: number, z0: number, x1: number, z1: number }

export type Cone = {
	id: string,
	row: string, -- front | back | shoulder | closer (behind a gorge) | pass (over a portal)
	s: number, -- where round the box (the ring's parameter)
	x: number, -- the foot's middle (the bottom layer's)
	z: number,
	nx: number, -- outward, away from the box
	nz: number,
	floor: number, -- the bottom layer's foot
	height: number, -- the summit's profile height (the top layer ends at or under it)
	base: number, -- the radius at the floor
	profile: number,
	green: number, -- grass under this height
	snow: number, -- snow over this height (summer; math.huge: none)
	winter: boolean,
	stone: string, -- Rock | Limestone
	lean: number, -- 0 … 1: how far each layer's middle moves toward (lx, lz), as a share of what its radius shrinks
	lx: number, -- (a mountain leans: a steep face on one side, a long ridge on the other)
	lz: number,
	radii: { number }, -- each layer's radius, from the floor up (LAYER studs each)
	shift: { number }, -- each layer's middle this far from (x, z) toward (lx, lz) (every layer inside the one under it)
}

-- A cone's dice: its height, spread (the base's radius over the height), grass and snow lines, stone and lean.
export type Look = { height: number, spread: number, green: number, snow: number, stone: string, lean: number, angle: number }

export type Fill = {
	shape: string, -- cylinder (a: radius, b: height) | block (a, b, c: size) | ball (a: radius) | wedge (a, b, c: size) | air (a block of air)
	x: number,
	y: number,
	z: number,
	a: number,
	b: number,
	c: number,
	yaw: number, -- turned about Y, then …
	pitch: number, -- … about its own X (CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0))
	material: string,
}

-- A far look of a peak: a square pyramid (four corner wedges) Height high over Base, its corners Half × √2 from the
-- middle; a snow cap from CapY (math.huge: none) as a second, slightly bigger pyramid over it.
export type Silhouette = { x: number, z: number, yaw: number, base: number, half: number, height: number, winter: boolean, capY: number, capHalf: number, capHeight: number, cone: string }

-- Solid rock that is not a cone (the portal's cliff: a wedge, its upright face toward the valley) and what is cut out.
export type Solid = { x: number, z: number, nx: number, nz: number, width: number, depth: number, height: number }
export type Cut = { x0: number, z0: number, x1: number, z1: number, y0: number, y1: number }

export type Gorge = { x0: number, z0: number, x1: number, z1: number, side: string, x: number, z: number, nx: number, nz: number }

export type Portal = {
	id: string,
	name: string,
	x: number, -- where the road meets the box's edge
	z: number,
	nx: number, -- outward
	nz: number,
	width: number,
	from: number, -- the road starts at this x (or z) inside the box (a yard's edge)
	face: number, -- the cliff's face this far outside the box (the tunnel's mouth)
}

export type Ring = {
	box: Box,
	cones: { Cone },
	fills: { Fill },
	silhouettes: { Silhouette },
	solids: { Solid },
	cuts: { Cut },
	gorges: { Gorge },
	portals: { Portal },
	scree: { { x: number, y: number, z: number, r: number } },
	glaciers: { { cone: string, slabs: number } },
	waterfall: { points: { { number } }, width: number, nx: number, nz: number }?, -- foot (in the water) … top: { x, y, z }
	grid: { [string]: { Cone } },
	length: number,
}

export type Tree = {
	x: number,
	y: number, -- the ground under it (the ring's terrain, else 0)
	z: number,
	height: number,
	variant: number, -- 1 … #Trees.Colors
	snowy: boolean,
	shadow: boolean,
	slope: boolean, -- on the ring's slopes (outside the box)
	chunk: string,
	canopy: number, -- the widest tier's radius
	yaw: number,
}

export type Patch = { x: number, z: number, chunk: string, flowers: { { x: number, z: number, size: number, color: { number } } } }
export type Hut = { x: number, z: number, yaw: number, kind: string, w: number, d: number, h: number, chunk: string }
export type Forest = { trees: { Tree }, patches: { Patch }, huts: { Hut } }

export type PartSpec = {
	name: string,
	shape: string, -- cylinder (its axis up) | ellipsoid | block | wedge (a Part's Wedge: high at its +Z) | ball
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	yaw: number,
	color: { number },
	material: string,
	collide: boolean,
	pitch: number?, -- (after the yaw, about its own X)
	transparency: number?,
	glow: boolean?, -- a lamp: it glows at night (DayNight)
}

-- A plain board with its text (World's sign(): its front, -Z, toward the valley).
export type SignSpec = { text: string, x: number, y: number, z: number, w: number, h: number, yaw: number, color: { number }, background: { number }? }

-- ── Small tools ────────────────────────────────────────────────────────────

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- How far (x, z) is outside the box (≤ 0: inside; inside, minus the distance to the nearest edge).
function AlpineLayout.boxDistance(box: Box, x: number, z: number): number
	local dx = math.max(box.x0 - x, 0, x - box.x1)
	local dz = math.max(box.z0 - z, 0, z - box.z1)
	if dx > 0 or dz > 0 then
		return math.sqrt(dx * dx + dz * dz)
	end
	return -math.min(x - box.x0, box.x1 - x, z - box.z0, box.z1 - z)
end
local boxDistance = AlpineLayout.boxDistance

-- A hash of a lattice point, 0 … 1 (the same everywhere: plain doubles, exact under 2^53).
local function hash(ix: number, iz: number, salt: number): number
	local n = (ix * 1619 + iz * 31337 + salt * 6971 + 1013904223) % 2147483647
	n = (n * 48271) % 2147483647
	n = (n * 48271) % 2147483647
	return n / 2147483647
end

-- Smooth value noise, 0 … 1, with features about `size` studs across.
local function noise(x: number, z: number, size: number, salt: number): number
	local fx, fz = x / size, z / size
	local ix, iz = math.floor(fx), math.floor(fz)
	local tx, tz = fx - ix, fz - iz
	tx, tz = tx * tx * (3 - 2 * tx), tz * tz * (3 - 2 * tz)
	local a, b = hash(ix, iz, salt), hash(ix + 1, iz, salt)
	local c, d = hash(ix, iz + 1, salt), hash(ix + 1, iz + 1, salt)
	return lerp(lerp(a, b, tx), lerp(c, d, tx), tz)
end
AlpineLayout.noise = noise

local function segmentDistance(ax: number, az: number, bx: number, bz: number, x: number, z: number): number
	local dx, dz = bx - ax, bz - az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - ax) * dx + (z - az) * dz) / length2, 0, 1) else 0
	return math.sqrt((x - ax - dx * t) ^ 2 + (z - az - dz * t) ^ 2)
end

-- Is (x, z) in the water the world fills (server/World.luau buildGround: the river and the lake, 300 studs past
-- Map.Bounds north and south)?
local function inWater(x: number, z: number): boolean
	local b = Map.Bounds
	if z < b.z0 - 300 or z > b.z1 + 300 then
		return false
	end
	return (x > Map.River.x0 and x < Map.River.x1) or (x > Map.Sea.x0 and x < b.x1 + 250)
end
AlpineLayout.inWater = inWater

-- ── The ring's path ────────────────────────────────────────────────────────

-- The box's edge at s (clockwise from the north-west corner: the north edge eastward, the east edge southward, the
-- south edge westward, the west edge northward; at a corner the edge point stays put while the normal turns a quarter
-- over TURN studs of s): the edge point and its outward normal.
local function edgeAt(box: Box, s: number): (number, number, number, number)
	local w, h = box.x1 - box.x0, box.z1 - box.z0
	local total = 2 * (w + h) + 4 * TURN
	s %= total
	local quarter = math.pi / 2
	if s < w then
		return box.x0 + s, box.z0, 0, -1
	end
	s -= w
	if s < TURN then
		local a = s / TURN * quarter
		return box.x1, box.z0, math.sin(a), -math.cos(a)
	end
	s -= TURN
	if s < h then
		return box.x1, box.z0 + s, 1, 0
	end
	s -= h
	if s < TURN then
		local a = s / TURN * quarter
		return box.x1, box.z1, math.cos(a), math.sin(a)
	end
	s -= TURN
	if s < w then
		return box.x1 - s, box.z1, 0, 1
	end
	s -= w
	if s < TURN then
		local a = s / TURN * quarter
		return box.x0, box.z1, -math.sin(a), math.cos(a)
	end
	s -= TURN
	if s < h then
		return box.x0, box.z1 - s, -1, 0
	end
	s -= h
	local a = s / TURN * quarter
	return box.x0, box.z0, -math.cos(a), -math.sin(a)
end

local function perimeter(box: Box): number
	return 2 * ((box.x1 - box.x0) + (box.z1 - box.z0)) + 4 * TURN
end

-- ── Cones ──────────────────────────────────────────────────────────────────

local function radiusAt(c: Cone, y: number): number
	if y >= c.height then
		return 0
	end
	local t = (c.height - y) / (c.height - c.floor)
	return c.base * t ^ c.profile
end

-- Lays the cone's layers (their radii from the floor up, until a layer would be thinner than 4 studs across, and how
-- far each one's middle has moved with the lean: a layer moves at most `lean` × what its radius shrank, so it always
-- stays inside the one under it).
local function shape(c: Cone): Cone
	local radii: { number }, shift: { number } = {}, {}
	local y = c.floor
	while true do
		local r = radiusAt(c, y + LAYER / 2)
		if r < 2 then
			break
		end
		local below = radii[#radii]
		if below then
			-- (crags: a layer a little wider or narrower than the profile, never wider than the one under it)
			r = math.min(r * (1 + A.Rough * (hash(#radii, math.floor(c.base), math.floor(c.height)) - 0.5)), below)
		end
		table.insert(shift, if below then shift[#shift] + c.lean * (below - r) else 0)
		table.insert(radii, r)
		y += LAYER
	end
	c.radii, c.shift = radii, shift
	return c
end

-- Layer i's middle.
local function layerAt(c: Cone, i: number): (number, number)
	local s = c.shift[i] or 0
	return c.x + c.lx * s, c.z + c.lz * s
end
AlpineLayout.layerAt = layerAt

-- The terrain's top over (x, z) from this cone (-inf: off it). The layers nest (each inside the one under it), so the
-- ones over a point are the bottom ones up to the last that still covers it.
local function coneTop(c: Cone, x: number, z: number): number
	local radii = c.radii
	local n = #radii
	if n == 0 or (x - c.x) ^ 2 + (z - c.z) ^ 2 > radii[1] * radii[1] then
		return -math.huge
	end
	local lo, hi = 1, n
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		local mx, mz = layerAt(c, mid)
		if (x - mx) ^ 2 + (z - mz) ^ 2 <= radii[mid] * radii[mid] then
			lo = mid
		else
			hi = mid - 1
		end
	end
	return c.floor + lo * LAYER
end

-- The cone's reach round its foot's middle at the seal's height (where two neighbours must overlap): the layer's
-- radius less its lean, whichever way it leans.
local function sealRadius(c: Cone): number
	for i, r in c.radii do
		if c.floor + i * LAYER > A.Seal then
			return r - (c.shift[i] or 0)
		end
	end
	return 0
end

-- The layer's material (`i` from 1 at the floor, `y` its middle).
function AlpineLayout.layerMaterial(c: Cone, i: number, y: number): string
	local other = if c.stone == "Rock" then "Limestone" else "Rock"
	if c.winter then
		if y > c.height * 0.3 and y < c.height * 0.62 and i % 3 ~= 0 then
			return if hash(i, math.floor(c.height), 5) < A.Strata then other else c.stone
		end
		return "Snow"
	end
	if y < c.green then
		return "Grass"
	elseif y >= c.snow then
		return "Snow"
	end
	return if hash(i, math.floor(c.height), 5) < A.Strata then other else c.stone
end

local function isWinter(x: number, z: number): boolean
	return z < Map.WinterZ and x < Map.River.x0
end

-- Does a circle (x, z, r) reach into the rectangle?
local function circleInRect(x: number, z: number, r: number, x0: number, z0: number, x1: number, z1: number): boolean
	local dx = math.max(x0 - x, 0, x - x1)
	local dz = math.max(z0 - z, 0, z - z1)
	return dx * dx + dz * dz < r * r
end

-- Does the cone's foot reach into the water (its floor then the river's or the lake's bed)?
local function wetFoot(x: number, z: number, r: number): boolean
	local b = Map.Bounds
	local z0, z1 = b.z0 - 300, b.z1 + 300
	return circleInRect(x, z, r, Map.River.x0, z0, Map.River.x1, z1) or circleInRect(x, z, r, Map.Sea.x0, z0, b.x1 + 250, z1)
end

-- ── The ring ───────────────────────────────────────────────────────────────

local ringCache: Ring? = nil

local function sameBox(a: Box, b: Box): boolean
	return a.x0 == b.x0 and a.z0 == b.z0 and a.x1 == b.x1 and a.z1 == b.z1
end

function AlpineLayout.ring(boxIn: Box?): Ring
	local box = boxIn or A.Box
	if ringCache and sameBox(ringCache.box, box) then
		return ringCache
	end
	local rand = Map.lcg(A.Seed)
	local function between(range: { number }): number
		return lerp(range[1], range[2], rand())
	end
	local total = perimeter(box)
	local cones: { Cone } = {}
	local count = 0

	-- The gorges: where the river crosses the box's north and south edges (nothing of the front row there).
	local gorges: { Gorge } = {}
	local reach = A.Gap + A.Gorge
	if Map.River.x0 > box.x0 and Map.River.x1 < box.x1 then
		local margin = 30
		local mid = (Map.River.x0 + Map.River.x1) / 2
		table.insert(gorges, { side = "north", x0 = Map.River.x0 - margin, x1 = Map.River.x1 + margin, z0 = box.z0 - reach, z1 = box.z0, x = mid, z = box.z0, nx = 0, nz = -1 })
		table.insert(gorges, { side = "south", x0 = Map.River.x0 - margin, x1 = Map.River.x1 + margin, z0 = box.z1, z1 = box.z1 + reach, x = mid, z = box.z1, nx = 0, nz = 1 })
	end

	-- The portals: where a road would leave the valley (a cliff with a closed tunnel mouth).
	local portals: { Portal } = {}
	for _, p in A.Portals do
		local x, z = p.x, p.z
		-- (on the box's own edge, wherever the box is: the side the outward normal says)
		if p.nx < 0 then
			x = box.x0
		elseif p.nx > 0 then
			x = box.x1
		elseif p.nz < 0 then
			z = box.z0
		else
			z = box.z1
		end
		table.insert(portals, { id = p.id, name = p.name, x = x, z = z, nx = p.nx, nz = p.nz, width = p.width, from = p.from, face = A.Gap })
	end
	-- The portal's corridor (the road from the box's edge to the mouth, a margin round it): no cone's foot in it.
	local function portalBox(p: Portal, margin: number, out: number): (number, number, number, number)
		local half = p.width / 2 + margin
		local ax, az = p.x, p.z
		local bx, bz = p.x + p.nx * out, p.z + p.nz * out
		if p.nx ~= 0 then
			return math.min(ax, bx), p.z - half, math.max(ax, bx), p.z + half
		end
		return p.x - half, math.min(az, bz), p.x + half, math.max(az, bz)
	end

	local function newCone(row: string, s: number, offset: number, look: Look, profile: number): Cone
		local ex, ez, nx, nz = edgeAt(box, s)
		local base = look.height * look.spread
		local c: Cone = {
			id = row,
			row = row,
			s = s,
			x = 0,
			z = 0,
			nx = nx,
			nz = nz,
			floor = A.Floor,
			height = look.height,
			base = base,
			profile = profile,
			green = look.green,
			snow = look.snow,
			winter = false,
			stone = look.stone,
			lean = look.lean,
			lx = math.cos(look.angle),
			lz = math.sin(look.angle),
			radii = {},
			shift = {},
		}
		shape(c)
		-- its foot `offset` studs out from the box (the floor's radius: nothing of it reaches nearer)
		local out = offset + (c.radii[1] or base)
		c.x, c.z = ex + nx * out, ez + nz * out
		return c
	end
	local function add(c: Cone)
		count += 1
		c.id = `{c.row}{count}`
		table.insert(cones, c)
	end
	-- Settle a cone where it stands: its floor (a wet foot from the bed), the winter, the snow line.
	local function settle(c: Cone): Cone
		if wetFoot(c.x, c.z, c.radii[1] or c.base) then
			c.floor = A.WetFloor
			shape(c)
		end
		c.winter = isWinter(c.x, c.z)
		if not c.winter and c.height < c.snow + 24 then
			c.snow = math.huge -- (too low for snow: rock to the top)
		end
		return c
	end
	local function blocked(c: Cone): boolean
		local r = c.radii[1] or c.base
		for _, g in gorges do
			if circleInRect(c.x, c.z, r, g.x0, g.z0, g.x1, g.z1) then
				return true
			end
		end
		for _, p in portals do
			local x0, z0, x1, z1 = portalBox(p, 24, A.Gap + A.Portal.Depth + 10)
			if circleInRect(c.x, c.z, r, x0, z0, x1, z1) then
				return true
			end
		end
		return false
	end
	local function distance(a: Cone, b: Cone): number
		return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
	end

	-- A cone's own dice (its height, spread, grass and snow lines, stone, lean), always drawn the same way.
	local function dice(def: { Height: { number }, Spread: { number } }): Look
		return {
			height = between(def.Height),
			spread = between(def.Spread),
			green = between(A.Green),
			snow = between(A.Snow),
			stone = if rand() < 0.35 then "Limestone" else "Rock",
			lean = between(A.Lean),
			angle = rand() * math.pi * 2,
		}
	end
	local function want(a: Cone, b: Cone): number
		return A.Spacing * (sealRadius(a) + sealRadius(b))
	end

	-- A row round the box: each next cone as far along as the seal allows (Spacing × both radii at Seal height); over
	-- a gorge or a portal's corridor the first free spot past it (the gap is the gorge's or the cliff's to close). The
	-- last one closes on the first (one more in between when the gap is too wide).
	local function row(name: string, def: { Height: { number }, Spread: { number }, Profile: number }, offset: number): { Cone }
		local list: { Cone } = {}
		local t = 0
		while t < total do
			local look = dice(def)
			local prev = list[#list]
			local placed: Cone? = nil
			while t < total do
				local here = newCone(name, t, offset, look, def.Profile)
				if not blocked(here) and (prev == nil or distance(prev, here) >= want(prev, here)) then
					placed = here
					break
				end
				t += 4
			end
			if placed == nil then
				break
			end
			settle(placed)
			add(placed)
			table.insert(list, placed)
			t += 4
		end
		-- Round again: is the last one near enough the first?
		local first, last = list[1], list[#list]
		if first and last and first ~= last and distance(first, last) > want(first, last) then
			local mid = newCone(name, (last.s + total) / 2, offset, dice(def), def.Profile)
			if not blocked(mid) then
				settle(mid)
				add(mid)
				table.insert(list, mid)
			end
		end
		return list
	end

	local front = row("front", A.Front, A.Gap)
	local back = row("back", A.Back, A.Gap + A.Back.Behind)

	-- Shoulders: one or two lower summits beside a big peak, along the ring.
	for _, b in back do
		for _, side in { -1, 1 } do
			local roll, f1, f2, f3, f4 = rand(), rand(), rand(), rand(), rand()
			local look = dice(A.Back)
			if roll >= A.Back.Shoulders then
				continue
			end
			look.height = b.height * lerp(0.58, 0.78, f1)
			look.spread = b.base / b.height * lerp(0.75, 0.95, f2)
			look.green, look.snow, look.stone = b.green, b.snow, b.stone
			local c = newCone("shoulder", b.s, 0, look, b.profile)
			local tx, tz = -b.nz * side, b.nx * side -- along the ring
			local along, out = b.base * lerp(0.32, 0.45, f3), b.base * lerp(0.0, 0.15, f4)
			c.x, c.z = b.x + tx * along + b.nx * out, b.z + tz * along + b.nz * out
			-- (never nearer the box than the front row's feet, never into a gorge or a portal)
			if boxDistance(box, c.x, c.z) - c.radii[1] < A.Gap or blocked(c) then
				continue
			end
			settle(c)
			add(c)
		end
	end

	-- A big peak behind every gorge: the river comes out of the mountains, not out of a hole.
	for _, g in gorges do
		local look = dice(A.Back)
		look.spread, look.stone = A.Back.Spread[1], "Rock"
		local c = newCone("closer", 0, 0, look, A.Back.Profile)
		c.nx, c.nz = g.nx, g.nz
		c.floor = A.WetFloor
		shape(c)
		local out = reach + c.radii[1]
		c.x, c.z = g.x + g.nx * out, g.z + g.nz * out
		settle(c)
		add(c)
	end

	-- A big peak over every portal: the cliff's mountain (its foot may reach the corridor: the mouth is cut out of it).
	for _, p in portals do
		local look = dice(A.Back)
		look.spread = A.Back.Spread[1]
		local c = newCone("pass", 0, 0, look, A.Back.Profile)
		c.nx, c.nz = p.nx, p.nz
		local out = A.Gap + c.radii[1]
		c.x, c.z = p.x + p.nx * out, p.z + p.nz * out
		settle(c)
		add(c)
	end

	-- The lookup grid (a cone in every cell its foot reaches).
	local grid: { [string]: { Cone } } = {}
	for _, c in cones do
		local r = c.radii[1] or 0
		for gx = math.floor((c.x - r) / CELL), math.floor((c.x + r) / CELL) do
			for gz = math.floor((c.z - r) / CELL), math.floor((c.z + r) / CELL) do
				local key = `{gx},{gz}`
				local list = grid[key]
				if not list then
					list = {}
					grid[key] = list
				end
				table.insert(list, c)
			end
		end
	end

	local ring: Ring = {
		box = box,
		cones = cones,
		fills = {},
		silhouettes = {},
		solids = {},
		cuts = {},
		gorges = gorges,
		portals = portals,
		scree = {},
		glaciers = {},
		waterfall = nil,
		grid = grid,
		length = total,
	}

	-- The portals' cliffs (a wedge: its upright face toward the valley, sloping down away from it) and the mouths.
	for _, p in portals do
		local P = A.Portal
		local depth = 140
		local width = p.width + 40
		local fx, fz = p.x + p.nx * p.face, p.z + p.nz * p.face
		table.insert(ring.solids, { x = fx, z = fz, nx = p.nx, nz = p.nz, width = width, depth = depth, height = P.Cliff })
		local x0, z0, x1, z1 = portalBox(p, 2, p.face + P.Depth)
		table.insert(ring.cuts, { x0 = x0, z0 = z0, x1 = x1, z1 = z1, y0 = Map.RoadTop, y1 = P.Height + 2 })
		-- (the road's way up to the mouth, wider, in case a foot reaches it)
		local ax0, az0, ax1, az1 = portalBox(p, 12, p.face + 2)
		table.insert(ring.cuts, { x0 = ax0, z0 = az0, x1 = ax1, z1 = az1, y0 = Map.RoadTop, y1 = 60 })
	end

	-- ── The fills ──
	local fills = ring.fills
	local order = { back = 1, shoulder = 2, closer = 3, pass = 3, front = 4 }
	local sorted = table.clone(cones)
	table.sort(sorted, function(a: Cone, b: Cone): boolean
		if order[a.row] ~= order[b.row] then
			return order[a.row] < order[b.row]
		end
		return a.id < b.id
	end)
	for _, c in sorted do
		for i, r in c.radii do
			local y = c.floor + (i - 0.5) * LAYER
			local x, z = layerAt(c, i)
			table.insert(fills, { shape = "cylinder", x = x, y = y, z = z, a = r, b = LAYER + 0.5, c = 0, yaw = 0, pitch = 0, material = AlpineLayout.layerMaterial(c, i, y) })
		end
	end

	-- Glacier tongues down the inner flanks of the tallest summer peaks, spread round the ring.
	local candidates = {}
	for _, c in back do
		if not c.winter and c.snow < c.height - 60 then
			table.insert(candidates, c)
		end
	end
	table.sort(candidates, function(a: Cone, b: Cone): boolean
		return a.height > b.height
	end)
	local G = A.Glaciers
	local chosen: { Cone } = {}
	for _, c in candidates do
		if #chosen >= G.Count then
			break
		end
		local apart = true
		for _, other in chosen do
			local ds = math.abs(c.s - other.s)
			if math.min(ds, total - ds) < total / (G.Count * 1.6) then
				apart = false
				break
			end
		end
		if apart then
			table.insert(chosen, c)
		end
	end
	for _, c in chosen do
		-- Down the slope toward the box, from the snow line to the first saddle (or the grass).
		local dx, dz = -c.nx, -c.nz
		local points: { { number } } = {}
		local last = math.huge
		for d = 0, c.radii[1], 12 do
			local x, z = c.x + dx * d, c.z + dz * d
			local h = AlpineLayout.heightAt(ring, x, z)
			if h <= c.snow + 30 then
				if h > last + 6 or h < math.max(c.green + 40, 160) or boxDistance(box, x, z) < A.Gap + 60 then
					break
				end
				table.insert(points, { x, h, z, d })
				last = math.min(last, h)
			end
		end
		local slabs = 0
		local n = #points
		local step = 3
		local k = 1
		while k + step <= n do
			local a, b = points[k], points[k + step]
			local t = (k - 1) / math.max(n - 1, 1)
			local width = lerp(G.Width[1], G.Width[2], t)
			local run = b[4] - a[4]
			local drop = a[2] - b[2]
			local length = math.sqrt(run * run + drop * drop)
			local pitch = -math.atan2(drop, run)
			local yaw = math.atan2(-dx, -dz)
			local sink = G.Thick / 2 - G.Protrude
			table.insert(fills, {
				shape = "block",
				x = (a[1] + b[1]) / 2,
				y = (a[2] + b[2]) / 2 - sink * math.cos(pitch),
				z = (a[3] + b[3]) / 2,
				a = width,
				b = G.Thick,
				c = length + 8,
				yaw = yaw,
				pitch = pitch,
				material = "Glacier",
			})
			slabs += 1
			k += step
		end
		if slabs > 0 then
			table.insert(ring.glaciers, { cone = c.id, slabs = slabs })
		end
	end

	-- Scree fans at the foothills' feet, toward the valley (light stone, half buried).
	for _, c in front do
		if c.winter then
			continue
		end
		for _ = 1, A.Scree.Count do
			local turn = (rand() - 0.5) * 1.4
			local ix, iz = -c.nx, -c.nz
			local dx, dz = ix * math.cos(turn) - iz * math.sin(turn), ix * math.sin(turn) + iz * math.cos(turn)
			local r = between(A.Scree.Radius)
			local at = (c.radii[1] or c.base) * 0.94
			local x, z = c.x + dx * at, c.z + dz * at
			local y = -0.45 * r
			if boxDistance(box, x, z) - r * 0.9 < 8 or inWater(x, z) then
				continue
			end
			local clear = true
			for _, g in gorges do
				if circleInRect(x, z, r, g.x0, g.z0, g.x1, g.z1) then
					clear = false
				end
			end
			for _, p in portals do
				local x0, z0, x1, z1 = portalBox(p, 40, A.Gap + 80)
				if circleInRect(x, z, r, x0, z0, x1, z1) then
					clear = false
				end
			end
			if clear then
				table.insert(ring.scree, { x = x, y = y, z = z, r = r })
				table.insert(fills, { shape = "ball", x = x, y = y, z = z, a = r, b = 0, c = 0, yaw = 0, pitch = 0, material = "Limestone" })
			end
		end
	end

	-- The portals: the cliff, then the mouth and the road's way cut out of whatever stands there.
	for _, s in ring.solids do
		-- A FillWedge is high at its +Z: its +Z toward the valley (-normal), so it slopes down away from it.
		local yaw = math.atan2(-s.nx, -s.nz)
		table.insert(fills, {
			shape = "wedge",
			x = s.x + s.nx * s.depth / 2,
			y = A.Floor + (s.height - A.Floor) / 2,
			z = s.z + s.nz * s.depth / 2,
			a = s.width,
			b = s.height - A.Floor,
			c = s.depth,
			yaw = yaw,
			pitch = 0,
			material = "Rock",
		})
	end
	for _, cut in ring.cuts do
		table.insert(fills, {
			shape = "air",
			x = (cut.x0 + cut.x1) / 2,
			y = (cut.y0 + cut.y1) / 2,
			z = (cut.z0 + cut.z1) / 2,
			a = cut.x1 - cut.x0,
			b = cut.y1 - cut.y0,
			c = cut.z1 - cut.z0,
			yaw = 0,
			pitch = 0,
			material = "Air",
		})
	end

	-- The waterfall: where the river comes out of the north gorge, down the closing peak's face.
	if A.Waterfall then
		for _, g in gorges do
			if g.side ~= "north" then
				continue
			end
			-- Up the river's middle from the gorge: the foot (the first rock), the top (150 high), a point between.
			local samples: { { number } } = {}
			local footAt, topAt = 0, 0
			for d = A.Gap, A.Gap + 900, 6 do
				local x, z = g.x + g.nx * d, g.z + g.nz * d
				local h = AlpineLayout.heightAt(ring, x, z)
				if footAt == 0 and h > 2 then
					footAt = #samples + 1
				end
				table.insert(samples, { x, h, z })
				if footAt > 0 and h >= 150 then
					topAt = #samples
					break
				end
			end
			if footAt > 0 and topAt > footAt + 1 then
				local foot, top = samples[footAt], samples[topAt]
				local mid = samples[(footAt + topAt) // 2]
				ring.waterfall = {
					points = {
						{ foot[1] - g.nx * 3, Map.WaterLevel - 1, foot[3] - g.nz * 3 },
						{ mid[1], mid[2] + 1.5, mid[3] },
						{ top[1], top[2] + 1.5, top[3] },
					},
					width = 24,
					nx = g.nx,
					nz = g.nz,
				}
			end
		end
	end

	-- The silhouettes: a square pyramid inside every big peak (Margin studs inside its layers everywhere).
	local S = A.Silhouettes
	for _, c in cones do
		local top = c.floor + #c.radii * LAYER
		if top < S.MinHeight then
			continue
		end
		local base = if c.floor < A.Floor then Map.WaterLevel - 1 else 0
		local height = (top - base) * S.Lower
		-- Upright over the middle of a layer a little under half way up (the lean moves the layers off it); every
		-- layer's room round that middle is its radius less how far its own middle moved, less the Margin.
		local m = math.max(1, math.floor(#c.radii * 0.45))
		local px, pz = layerAt(c, m)
		local function room(i: number): number
			return c.radii[i] - math.abs((c.shift[i] or 0) - (c.shift[m] or 0)) - S.Margin
		end
		-- (no higher than the last layer still 2 studs of room)
		for i in c.radii do
			local y0 = c.floor + (i - 1) * LAYER
			if room(i) < 2 and y0 < base + height then
				height = math.max(0, y0 - base)
				break
			end
		end
		local hd = math.huge
		for i in c.radii do
			local y0 = math.max(c.floor + (i - 1) * LAYER, base) - base
			if y0 < height and c.floor + i * LAYER > base then
				hd = math.min(hd, room(i) / (1 - y0 / height))
			end
		end
		if hd == math.huge or hd < 40 or height < 100 then
			continue
		end
		local half = hd / math.sqrt(2)
		local capY = if c.winter or c.snow == math.huge or c.snow > base + height - 30 then math.huge else c.snow
		local capHalf, capHeight = 0, 0
		if capY < math.huge then
			-- (the same apex, its foot 1.5 studs wider than the rock's there: over it everywhere, inside the margin)
			local hdCap = hd * (1 - (capY - base) / height) + 1.5
			capHalf = hdCap / math.sqrt(2)
			capHeight = base + height - capY
		end
		table.insert(ring.silhouettes, {
			x = px,
			z = pz,
			yaw = hash(math.floor(c.x), math.floor(c.z), 77) * math.pi / 2,
			base = base,
			half = half,
			height = height,
			winter = c.winter,
			capY = capY,
			capHalf = capHalf,
			capHeight = capHeight,
			cone = c.id,
		})
	end

	if boxIn == nil or sameBox(box, A.Box) then
		ringCache = ring
	end
	return ring
end

-- The terrain's top over (x, z) from the ring (the cones, the cliffs, minus the cuts) and the cone that makes it.
function AlpineLayout.heightAt(ring: Ring, x: number, z: number): (number, Cone?)
	local best, which = -math.huge, nil :: Cone?
	local list = ring.grid[`{math.floor(x / CELL)},{math.floor(z / CELL)}`]
	if list then
		for _, c in list do
			local h = coneTop(c, x, z)
			if h > best then
				best, which = h, c
			end
		end
	end
	for _, s in ring.solids do
		local u = (x - s.x) * s.nx + (z - s.z) * s.nz -- out from the face
		local v = math.abs((x - s.x) * s.nz - (z - s.z) * s.nx) -- along it
		if u >= 0 and u <= s.depth and v <= s.width / 2 then
			best = math.max(best, A.Floor + (s.height - A.Floor) * (1 - u / s.depth))
		end
	end
	for _, cut in ring.cuts do
		if x > cut.x0 and x < cut.x1 and z > cut.z0 and z < cut.z1 and best > cut.y0 then
			best = cut.y0 -- (a car drives in under what is left over it)
		end
	end
	return best, which
end

-- Does the ring hold the box? A flood over a grid of `cell` studs, from every cell inside the box, over ground lower
-- than Seal (and not the water, unless `swim`), must never reach the grid's edge (past the outermost foot). Returns
-- whether it held and, if not, where it got out.
function AlpineLayout.sealed(ring: Ring, cell: number, swim: boolean): (boolean, number?, number?)
	local box = ring.box
	local reach = 0
	for _, c in ring.cones do
		reach = math.max(reach, boxDistance(box, c.x, c.z) + (c.radii[1] or 0))
	end
	reach += 2 * cell
	local x0, z0 = box.x0 - reach, box.z0 - reach
	local nx = math.ceil((box.x1 - box.x0 + 2 * reach) / cell)
	local nz = math.ceil((box.z1 - box.z0 + 2 * reach) / cell)
	local open: { boolean } = table.create(nx * nz, false)
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x, z = x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell
			local h = AlpineLayout.heightAt(ring, x, z)
			open[j * nx + i + 1] = h < A.Seal and (swim or not inWater(x, z))
		end
	end
	local seen: { boolean } = table.create(nx * nz, false)
	local queue: { number } = {}
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x, z = x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell
			local k = j * nx + i + 1
			if open[k] and boxDistance(box, x, z) < 0 then
				seen[k] = true
				table.insert(queue, k)
			end
		end
	end
	local head = 1
	while head <= #queue do
		local k = queue[head]
		head += 1
		local i, j = (k - 1) % nx, (k - 1) // nx
		if i == 0 or j == 0 or i == nx - 1 or j == nz - 1 then
			return false, x0 + (i + 0.5) * cell, z0 + (j + 0.5) * cell
		end
		for _, step in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local n = (j + step[2]) * nx + (i + step[1]) + 1
			if open[n] and not seen[n] then
				seen[n] = true
				table.insert(queue, n)
			end
		end
	end
	return true, nil, nil
end

-- ── The forests' rules ─────────────────────────────────────────────────────

type Rect = { x0: number, z0: number, x1: number, z1: number }
type Rules = {
	segments: { [string]: { Map.Segment } },
	ends: { { number } },
	districts: { Rect },
	yards: { Rect },
	plots: { Rect },
	keep: { Rect },
	points: { { number } }, -- x, z, radius
}
local RULE_CELL = 250
local rulesCache: Rules? = nil

local function rules(): Rules
	if rulesCache then
		return rulesCache
	end
	local T = A.Trees
	local reach = 80 -- (the farthest a road rule looks)
	local segments: { [string]: { Map.Segment } } = {}
	for _, s in Map.Segments do
		local pad = s.width / 2 + reach
		for gx = math.floor((math.min(s.ax, s.bx) - pad) / RULE_CELL), math.floor((math.max(s.ax, s.bx) + pad) / RULE_CELL) do
			for gz = math.floor((math.min(s.az, s.bz) - pad) / RULE_CELL), math.floor((math.max(s.az, s.bz) + pad) / RULE_CELL) do
				local key = `{gx},{gz}`
				local list = segments[key]
				if not list then
					list = {}
					segments[key] = list
				end
				table.insert(list, s)
			end
		end
	end
	-- The roads' ends and bends (the junctions, the dead ends at the yards): the drivers' view stays clear there.
	local ends: { { number } } = {}
	for _, s in Map.Connectors do
		table.insert(ends, { s.ax, s.az })
		table.insert(ends, { s.bx, s.bz })
	end
	local districts: { Rect } = {}
	for _, d in Map.Districts do
		local x0, x1, z0, z1 = Map.districtEdges(d)
		local pad = Map.RoadWidth / 2 + T.TownClear
		table.insert(districts, { x0 = x0 - pad, z0 = z0 - pad, x1 = x1 + pad, z1 = z1 + pad })
	end
	local yards: { Rect } = {}
	for _, y in Map.Yards do
		table.insert(yards, { x0 = y.x0 - T.YardClear, z0 = y.z0 - T.YardClear, x1 = y.x1 + T.YardClear, z1 = y.z1 + T.YardClear })
	end
	for _, y in Map.Clearings do
		table.insert(yards, { x0 = y.x0 - 14, z0 = y.z0 - 14, x1 = y.x1 + 14, z1 = y.z1 + 14 })
	end
	local hills = Map.SunsetHills
	table.insert(yards, { x0 = hills.x0 - 140, z0 = hills.z0 - 140, x1 = hills.x1 + 140, z1 = hills.z1 + 140 })
	local lake = Map.Lake
	local wet = T.WaterClear + 10
	table.insert(yards, { x0 = lake.x0 - wet, z0 = lake.z0 - wet, x1 = lake.x1 + wet, z1 = lake.z1 + wet })
	-- The homes' lots out of the districts (Map.EstatePlots; World's own rule, nearAnyLot): the house, its garden, its drive.
	local plots: { Rect } = {}
	for _, plot in Map.EstatePlots do
		local m = T.LotClear
		local ax, az = Map.plotPoint(plot, -plot.w / 2 - m, -plot.front - m - 20)
		local bx, bz = Map.plotPoint(plot, plot.w / 2 + m, plot.back + m)
		table.insert(plots, { x0 = math.min(ax, bx), z0 = math.min(az, bz), x1 = math.max(ax, bx), z1 = math.max(az, bz) })
	end
	local keep: { Rect } = {}
	for _, k in T.Keep do
		table.insert(keep, k)
	end
	-- The portals' roads (from the yard's edge to the box's edge) and the barrier in front of the mouth.
	for _, p in A.Portals do
		local half = p.width / 2 + 34
		if p.nx ~= 0 then
			local edge = if p.nx < 0 then A.Box.x0 else A.Box.x1
			table.insert(keep, { x0 = math.min(p.from, edge) - 60, z0 = p.z - half, x1 = math.max(p.from, edge) + 60, z1 = p.z + half })
		else
			local edge = if p.nz < 0 then A.Box.z0 else A.Box.z1
			table.insert(keep, { x0 = p.x - half, z0 = math.min(p.from, edge) - 60, x1 = p.x + half, z1 = math.max(p.from, edge) + 60 })
		end
	end
	local points: { { number } } = {}
	for _, place in Map.Places do
		table.insert(points, { place.x, place.z, T.PlaceClear })
	end
	for _, spot in Map.CargoSpots do
		table.insert(points, { spot.park.x, spot.park.z, 30 })
		table.insert(points, { spot.pile.x, spot.pile.z, 30 })
	end
	for _, spot in Map.EmployerSpots do
		table.insert(points, { spot.x, spot.z, 30 })
	end
	for _, secret in Map.Secrets do
		table.insert(points, { secret.x, secret.z, 20 })
	end
	local m = Map.Mountain
	table.insert(points, { m.x, m.z, m.radius + 60 })
	table.insert(points, { Map.VanSeller.x, Map.VanSeller.z, 60 })
	local made: Rules = { segments = segments, ends = ends, districts = districts, yards = yards, plots = plots, keep = keep, points = points }
	rulesCache = made
	return made
end

local function inRects(list: { Rect }, x: number, z: number, margin: number): boolean
	for _, r in list do
		if x > r.x0 - margin and x < r.x1 + margin and z > r.z0 - margin and z < r.z1 + margin then
			return true
		end
	end
	return false
end

-- The distance from (x, z) to the nearest road's edge (as far as the rules look: 80 studs; farther: 80+).
function AlpineLayout.roadEdge(x: number, z: number): number
	local list = rules().segments[`{math.floor(x / RULE_CELL)},{math.floor(z / RULE_CELL)}`]
	local best = math.huge
	if list then
		for _, s in list do
			best = math.min(best, segmentDistance(s.ax, s.az, s.bx, s.bz, x, z) - s.width / 2)
		end
	end
	return best
end
local roadEdge = AlpineLayout.roadEdge

-- Why a tree with this canopy (its widest tier's radius) may not stand at (x, z) in the valley (nil: it may).
function AlpineLayout.treeRule(x: number, z: number, canopy: number): string?
	local T = A.Trees
	local R = rules()
	local box = A.Box
	if x < box.x0 + 8 or x > box.x1 - 8 or z < box.z0 + 8 or z > box.z1 - 8 then
		return "box"
	end
	local wet = T.WaterClear + canopy
	if (x > Map.River.x0 - wet and x < Map.River.x1 + wet) or x > Map.Sea.x0 - wet then
		return "water"
	end
	if inRects(R.districts, x, z, canopy) then
		return "town"
	end
	if inRects(R.yards, x, z, canopy) then
		return "yard"
	end
	if inRects(R.plots, x, z, canopy) then
		return "lot"
	end
	if inRects(R.keep, x, z, canopy) then
		return "keep"
	end
	for _, p in R.points do
		local r = p[3] + canopy
		if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 < r * r then
			return "place"
		end
	end
	if roadEdge(x, z) < math.max(T.RoadClear, canopy + 4) then
		return "road"
	end
	local j = T.JunctionClear
	for _, e in R.ends do
		if (x - e[1]) ^ 2 + (z - e[2]) ^ 2 < j * j then
			return "junction"
		end
	end
	return nil
end

-- How near the town (0 far … 1 at a district's edge) and how near the box's edge (1 at it … 0 Edge studs in).
local function townness(x: number, z: number): number
	local best = math.huge
	for _, d in Map.Districts do
		local x0, x1, z0, z1 = Map.districtEdges(d)
		local dx = math.max(x0 - x, 0, x - x1)
		local dz = math.max(z0 - z, 0, z - z1)
		best = math.min(best, math.sqrt(dx * dx + dz * dz))
	end
	return 1 - math.clamp(best / A.Trees.TownFade, 0, 1)
end
local function edgeness(box: Box, x: number, z: number): number
	return 1 - math.clamp(-boxDistance(box, x, z) / A.Trees.Edge, 0, 1)
end

-- ── The trees' and the huts' looks ─────────────────────────────────────────

-- A spruce or a fir: a trunk and three tiers, each a squashed ellipsoid, narrower and taller toward the top.
function AlpineLayout.treeParts(t: Tree): { PartSpec }
	local T = A.Trees
	local h = t.height
	local green = T.Colors[t.variant] or T.Colors[1]
	local function shade(f: number): { number }
		return { math.floor(green[1] * f), math.floor(green[2] * f), math.floor(green[3] * f) }
	end
	local trunk = 1.3 + h * 0.024
	local parts: { PartSpec } = {
		{ name = "Trunk", shape = "cylinder", x = t.x, y = t.y + h * 0.27 - 1, z = t.z, sx = trunk, sy = h * 0.54 + 2, sz = trunk, yaw = 0, color = T.Trunk, material = "Wood", collide = true },
	}
	local tiers = { { 0.36, 0.38, 0.42, 0.86 }, { 0.58, 0.28, 0.36, 1.0 }, { 0.80, 0.16, 0.40, 1.12 } } -- middle, width, height, shade
	for n, tier in tiers do
		local color = shade(tier[4])
		if t.snowy and n == 3 then
			color = T.Snowy
		elseif t.snowy then
			color = { math.floor(lerp(color[1], T.Snowy[1], 0.22)), math.floor(lerp(color[2], T.Snowy[2], 0.22)), math.floor(lerp(color[3], T.Snowy[3], 0.22)) }
		end
		local w = h * tier[2]
		table.insert(parts, {
			name = "Needles",
			shape = "ellipsoid",
			x = t.x,
			y = t.y + h * tier[1],
			z = t.z,
			sx = w,
			sy = h * tier[3],
			sz = w * 0.94,
			yaw = t.yaw,
			color = color,
			material = if t.snowy and n == 3 then "Snow" else "Grass",
			collide = false,
		})
	end
	return parts
end

-- A hay barn (an open front with hay) or a hut (a door and a window): dark weathered wood, a gable roof.
function AlpineLayout.hutParts(hut: Hut): { PartSpec }
	local wood = { 96, 68, 46 }
	local dark = { 62, 44, 32 }
	local roof = { 74, 64, 60 }
	local c, s = math.cos(hut.yaw), math.sin(hut.yaw)
	-- (local right r, up y, back b → world: the hut's front faces its yaw's -Z, CFrame.Angles(0, yaw, 0))
	local function at(r: number, b: number): (number, number)
		return hut.x + r * c + b * s, hut.z - r * s + b * c
	end
	local parts: { PartSpec } = {}
	local function add(name: string, shape: string, r: number, y: number, b: number, sx: number, sy: number, sz: number, yaw: number, color: { number }, material: string, collide: boolean)
		local x, z = at(r, b)
		table.insert(parts, { name = name, shape = shape, x = x, y = y, z = z, sx = sx, sy = sy, sz = sz, yaw = hut.yaw + yaw, color = color, material = material, collide = collide })
	end
	local w, d, h = hut.w, hut.d, hut.h
	add("Walls", "block", 0, h / 2, 0, w, h, d, 0, wood, "WoodPlanks", true)
	add("Base", "block", 0, 0.3, 0, w + 1, 0.6, d + 1, 0, { 120, 116, 108 }, "Cobblestone", true)
	local rise = d * 0.42
	-- the roof: two wedges, the ridge along the hut's width (high at their +Z, which meets the ridge)
	add("Roof", "wedge", 0, h + rise / 2, -d / 4 - 0.5, w + 2, rise, d / 2 + 1, 0, roof, "WoodPlanks", true)
	add("Roof", "wedge", 0, h + rise / 2, d / 4 + 0.5, w + 2, rise, d / 2 + 1, math.pi, roof, "WoodPlanks", true)
	if hut.kind == "barn" then
		add("Opening", "block", 0, h * 0.42, -d / 2 - 0.05, w * 0.55, h * 0.8, 0.3, 0, dark, "Wood", false)
		add("Hay", "block", 0, 1.6, -d / 2 - 2.2, w * 0.5, 3.2, 3.6, 0.1, { 214, 186, 104 }, "Grass", true)
	else
		add("Door", "block", -w * 0.2, 3.4, -d / 2 - 0.05, 3.6, 6.8, 0.3, 0, dark, "Wood", false)
		add("Window", "block", w * 0.22, h * 0.58, -d / 2 - 0.05, 3, 2.4, 0.3, 0, { 40, 50, 60 }, "Glass", false)
	end
	return parts
end

-- ── The forests ────────────────────────────────────────────────────────────

local forestCache: Forest? = nil

local function chunkOf(x: number, z: number): string
	local size = A.Trees.Chunk
	return `{math.floor(x / size)}_{math.floor(z / size)}`
end
AlpineLayout.chunkOf = chunkOf

function AlpineLayout.forest(ringIn: Ring?): Forest
	if forestCache and ringIn == nil then
		return forestCache
	end
	local ring = ringIn or AlpineLayout.ring()
	local box = ring.box
	local T = A.Trees
	local rand = Map.lcg(A.Seed + 17)
	local spacing, jitter = T.Spacing, T.Jitter
	local slopeMax = math.floor(T.Max * T.Slope + 0.5)
	local valleyMax = T.Max - slopeMax
	type Candidate = { x: number, z: number, y: number, score: number, copse: number, height: number, slope: boolean, winter: boolean, taken: boolean? }

	-- The valley: a jittered grid over the box, every candidate scored: the forests' (the patches' noise, the edge,
	-- less near town) and, near town, the copses' (the noise alone).
	local valley: { Candidate } = {}
	for gx = box.x0 + spacing / 2, box.x1, spacing do
		for gz = box.z0 + spacing / 2, box.z1, spacing do
			local x = gx + (rand() - 0.5) * 2 * jitter
			local z = gz + (rand() - 0.5) * 2 * jitter
			local roll = rand()
			local big, small = noise(x, z, T.Noise.Big, 1), noise(x, z, T.Noise.Small, 2)
			local edge, town = edgeness(box, x, z), townness(x, z)
			local score = 0.62 * big + 0.28 * small + 0.3 * edge - 0.42 * town + 0.05 * roll
			local copse = if town >= 0.25 then 0.55 * big + 0.45 * small else 0
			if score < 0.35 and copse < 0.55 then
				continue -- (a meadow for sure: skip the rules)
			end
			local height = lerp(T.Height[1], T.Height[2], math.clamp(0.25 + 0.6 * edge - 0.3 * town + 0.4 * (roll - 0.5), 0, 1))
			if AlpineLayout.treeRule(x, z, height * 0.19) == nil then
				table.insert(valley, { x = x, z = z, y = 0, score = score, copse = copse, height = height, slope = false, winter = isWinter(x, z) })
			end
		end
	end
	table.sort(valley, function(a: Candidate, b: Candidate): boolean
		return a.score > b.score
	end)
	-- (the copses near town: the best by their own score of what the forests left)
	local copseMax = math.floor(valleyMax * T.Copses + 0.5)
	local forestMax = valleyMax - copseMax
	for n, c in valley do
		c.taken = n <= forestMax
	end
	local copses: { Candidate } = {}
	for _, c in valley do
		if not c.taken and c.copse > 0 then
			table.insert(copses, c)
		end
	end
	table.sort(copses, function(a: Candidate, b: Candidate): boolean
		return a.copse > b.copse
	end)

	-- The slopes: a jittered grid round the box, on the ring's grass under the tree line.
	local slopes: { Candidate } = {}
	local band = 900
	for gx = box.x0 - band, box.x1 + band, spacing do
		for gz = box.z0 - band, box.z1 + band, spacing do
			local x = gx + (rand() - 0.5) * 2 * jitter
			local z = gz + (rand() - 0.5) * 2 * jitter
			local roll = rand()
			if boxDistance(box, x, z) < A.Gap then
				continue
			end
			local h, cone = AlpineLayout.heightAt(ring, x, z)
			if cone == nil or h < 4 or inWater(x, z) and h < 6 then
				continue
			end
			local line = lerp(T.Treeline[1], T.Treeline[2], noise(x, z, 300, 5))
			if h > line or (not cone.winter and h > cone.green + 18) then
				continue
			end
			local score = 0.7 * noise(x, z, T.Noise.Big * 0.8, 3) + 0.25 * (1 - h / line) + 0.05 * roll
			if score < 0.42 then
				continue
			end
			local clear = true
			for _, s in ring.scree do
				if (x - s.x) ^ 2 + (z - s.z) ^ 2 < (s.r + 8) ^ 2 then
					clear = false
					break
				end
			end
			for _, p in ring.portals do
				local d = math.max(math.abs((x - p.x) * p.nz - (z - p.z) * p.nx) - p.width / 2, 0)
				if d < 90 and (x - p.x) * p.nx + (z - p.z) * p.nz < A.Gap + A.Portal.Depth + 260 then
					clear = false
				end
			end
			if clear then
				local height = lerp(T.Height[1] + 6, T.Height[2], math.clamp(0.4 + 0.5 * (roll - 0.5) + 0.3 * (1 - h / line), 0, 1))
				local candidate: Candidate = { x = x, z = z, y = h, score = score, copse = 0, height = height, slope = true, winter = cone.winter }
				table.insert(slopes, candidate)
			end
		end
	end
	table.sort(slopes, function(a: Candidate, b: Candidate): boolean
		return a.score > b.score
	end)

	local trees: { Tree } = {}
	local function take(list: { Candidate }, max: number)
		local n = 0
		for _, c in list do
			if n >= max then
				break
			end
			n += 1
			local shadow = not c.slope and roadEdge(c.x, c.z) < T.ShadowNear
			table.insert(trees, {
				x = c.x,
				y = c.y,
				z = c.z,
				height = c.height,
				variant = 1 + math.floor(hash(math.floor(c.x * 7), math.floor(c.z * 7), 9) * #T.Colors) % #T.Colors,
				snowy = c.winter,
				shadow = shadow,
				slope = c.slope,
				chunk = chunkOf(c.x, c.z),
				canopy = c.height * 0.19,
				yaw = hash(math.floor(c.x * 3), math.floor(c.z * 3), 11) * math.pi * 2,
			})
		end
	end
	take(valley, forestMax)
	take(copses, valleyMax - #trees)
	take(slopes, T.Max - #trees)

	-- A lookup of the trees (meadows and huts keep away from them).
	local near: { [string]: { Tree } } = {}
	for _, t in trees do
		local key = `{math.floor(t.x / 60)},{math.floor(t.z / 60)}`
		local list = near[key]
		if not list then
			list = {}
			near[key] = list
		end
		table.insert(list, t)
	end
	local function treeWithin(x: number, z: number, r: number): boolean
		for gx = math.floor((x - r) / 60), math.floor((x + r) / 60) do
			for gz = math.floor((z - r) / 60), math.floor((z + r) / 60) do
				local list = near[`{gx},{gz}`]
				if list == nil then
					continue
				end
				for _, t in list do
					if (t.x - x) ^ 2 + (t.z - z) ^ 2 < (r + t.canopy) ^ 2 then
						return true
					end
				end
			end
		end
		return false
	end

	-- Open spots in the meadows near the roads (seen from them), scored by a hash, picked apart from each other.
	local function meadowSpots(cell: number, radius: number, road: { number }, gap: number, max: number, salt: number): { { number } }
		local spots: { { number } } = {}
		for gx = box.x0 + cell / 2, box.x1, cell do
			for gz = box.z0 + cell / 2, box.z1, cell do
				local x = gx + (hash(math.floor(gx), math.floor(gz), salt) - 0.5) * cell * 0.6
				local z = gz + (hash(math.floor(gz), math.floor(gx), salt + 1) - 0.5) * cell * 0.6
				if isWinter(x, z) then
					continue
				end
				local edge = roadEdge(x, z)
				if edge < road[1] or edge > road[2] or AlpineLayout.treeRule(x, z, radius) ~= nil or treeWithin(x, z, radius + 4) then
					continue
				end
				table.insert(spots, { x, z, hash(math.floor(x), math.floor(z), salt + 2) })
			end
		end
		table.sort(spots, function(a: { number }, b: { number }): boolean
			return a[3] > b[3]
		end)
		local picked: { { number } } = {}
		for _, s in spots do
			if #picked >= max then
				break
			end
			local free = true
			for _, p in picked do
				if (p[1] - s[1]) ^ 2 + (p[2] - s[2]) ^ 2 < gap * gap then
					free = false
					break
				end
			end
			if free then
				table.insert(picked, s)
			end
		end
		return picked
	end

	local H = A.Huts
	local huts: { Hut } = {}
	for n, s in meadowSpots(50, 16, H.Road, H.Gap, H.Count, 21) do
		local x, z = s[1], s[2]
		-- its front toward the nearest road
		local list: { Map.Segment } = rules().segments[`{math.floor(x / RULE_CELL)},{math.floor(z / RULE_CELL)}`] or {}
		local fx, fz, best = 0, -1, math.huge
		for _, seg in list do
			local dx, dz = seg.bx - seg.ax, seg.bz - seg.az
			local length2 = dx * dx + dz * dz
			local t = if length2 > 0 then math.clamp(((x - seg.ax) * dx + (z - seg.az) * dz) / length2, 0, 1) else 0
			local px, pz = seg.ax + dx * t, seg.az + dz * t
			local d = math.sqrt((px - x) ^ 2 + (pz - z) ^ 2)
			if d < best and d > 0 then
				best, fx, fz = d, (px - x) / d, (pz - z) / d
			end
		end
		local barn = n % 2 == 1
		table.insert(huts, {
			x = x,
			z = z,
			yaw = math.atan2(-fx, -fz),
			kind = if barn then "barn" else "hut",
			w = if barn then 18 else 13,
			d = if barn then 13 else 10,
			h = if barn then 9 else 7.5,
			chunk = chunkOf(x, z),
		})
	end
	local function nearHut(x: number, z: number, r: number): boolean
		for _, hut in huts do
			if (hut.x - x) ^ 2 + (hut.z - z) ^ 2 < (r + 16) ^ 2 then
				return true
			end
		end
		return false
	end

	local M = A.Meadows
	local patches: { Patch } = {}
	for _, s in meadowSpots(40, 10, M.Road, M.Gap, M.Patches + #huts, 31) do
		if #patches >= M.Patches or nearHut(s[1], s[2], 10) then
			continue
		end
		local flowers = {}
		for k = 1, M.Flowers do
			local a = hash(math.floor(s[1]) + k, math.floor(s[2]), 41) * math.pi * 2
			local r = 1.5 + hash(math.floor(s[2]) + k, math.floor(s[1]), 43) * 6.5
			local color = M.Colors[1 + math.floor(hash(k, math.floor(s[1] + s[2]), 47) * #M.Colors) % #M.Colors]
			table.insert(flowers, { x = s[1] + math.cos(a) * r, z = s[2] + math.sin(a) * r, size = 0.7 + hash(k, math.floor(s[1]), 49) * 0.6, color = color })
		end
		table.insert(patches, { x = s[1], z = s[2], chunk = chunkOf(s[1], s[2]), flowers = flowers })
	end

	local forest = { trees = trees, patches = patches, huts = huts }
	if ringIn == nil then
		forestCache = forest
	end
	return forest
end

-- ── Budgets ────────────────────────────────────────────────────────────────

function AlpineLayout.volume(fills: { Fill }): number
	local total = 0
	for _, f in fills do
		if f.shape == "cylinder" then
			total += math.pi * f.a * f.a * f.b
		elseif f.shape == "block" then
			total += f.a * f.b * f.c
		elseif f.shape == "wedge" then
			total += f.a * f.b * f.c / 2
		elseif f.shape == "ball" then
			total += 4 / 3 * math.pi * f.a ^ 3
		end
	end
	return total
end

-- ── The portals and the waterfall ──────────────────────────────────────────

-- A portal: the road from the yard's edge into the mouth, the ROAD CLOSED barrier (jersey barriers, two amber lamps,
-- the board on two posts) just inside the box, the tunnel's portal (pillars, a beam with the name, walls and a ceiling
-- in the mouth) and the closed steel shutter at its back. In the portal's frame: u out from the box's edge, v along it.
function AlpineLayout.portalParts(p: Portal): ({ PartSpec }, { SignSpec })
	local P = A.Portal
	local vx, vz = -p.nz, p.nx
	local yaw = math.atan2(p.nx, p.nz) -- (its front, -Z, toward the valley)
	local parts: { PartSpec } = {}
	local function at(u: number, v: number): (number, number)
		return p.x + p.nx * u + vx * v, p.z + p.nz * u + vz * v
	end
	local function add(name: string, u: number, v: number, y: number, sv: number, sy: number, su: number, color: { number }, material: string, collide: boolean, glow: boolean?)
		local x, z = at(u, v)
		table.insert(parts, { name = name, shape = "block", x = x, y = y, z = z, sx = sv, sy = sy, sz = su, yaw = yaw, color = color, material = material, collide = collide, glow = glow })
	end
	local w = p.width
	local from = if p.nx ~= 0 then (p.from - p.x) * p.nx else (p.from - p.z) * p.nz
	local inner = p.face + P.Depth
	local concrete = { 130, 128, 120 }
	local top = Map.RoadTop
	add("PassRoad", (from + inner) / 2, 0, top - 0.2, w, 0.4, inner - from, { 46, 46, 50 }, "Asphalt", true)
	add("PassLine", (from + inner) / 2, 0, top + 0.03, 0.6, 0.06, inner - from - 4, { 200, 170, 60 }, "SmoothPlastic", false)
	for _, v in { -15, -5, 5, 15 } do
		add("Barrier", -12, v, top + 1.6, 9.6, 3.2, 2.4, { 196, 192, 184 }, "Concrete", true)
	end
	for _, v in { -15, 15 } do
		add("BarrierLamp", -12, v, top + 3.6, 0.8, 0.8, 0.8, { 255, 170, 40 }, "Neon", false, true)
	end
	for _, v in { -9, 9 } do
		add("SignPost", -16, v, top + 5, 0.6, 10, 0.6, { 90, 92, 96 }, "Metal", true)
	end
	for _, side in { -1, 1 } do
		add("PortalPillar", p.face, side * (w / 2 + 4), 16, 6, 32, 6, concrete, "Concrete", true)
		add("TunnelWall", p.face + P.Depth / 2, side * (w / 2 + 1), P.Height / 2 + 1, 2, P.Height + 2, P.Depth, concrete, "Concrete", true)
	end
	add("PortalBeam", p.face, 0, 31, w + 14, 6, 6, concrete, "Concrete", true)
	add("TunnelCeiling", p.face + P.Depth / 2, 0, P.Height + 2.5, w + 4, 2, P.Depth, concrete, "Concrete", true)
	add("Shutter", inner - 1.5, 0, P.Height / 2 + 1, w + 2, P.Height + 2, 1, { 110, 96, 80 }, "CorrodedMetal", true)
	local bx, bz = at(-16.4, 0)
	local nx, nz = at(p.face - 3.2, 0)
	local signs: { SignSpec } = {
		{ text = P.Text, x = bx, y = top + 8.6, z = bz, w = 17, h = 3.2, yaw = yaw, color = { 245, 245, 240 }, background = { 176, 32, 28 } },
		{ text = `{p.name} TUNNEL · CLOSED`, x = nx, y = 31, z = nz, w = w + 4, h = 3.6, yaw = yaw, color = { 255, 220, 120 }, background = nil },
	}
	return parts, signs
end

-- The waterfall down the gorge's closing peak: a sheet of water from point to point (glass, see-through) and the foam
-- where it meets the river.
function AlpineLayout.waterfallParts(ring: Ring): { PartSpec }
	local fall = ring.waterfall
	if not fall then
		return {}
	end
	local parts: { PartSpec } = {}
	local yaw = math.atan2(fall.nx, fall.nz) -- (its front toward the valley)
	local pts = fall.points
	for i = 1, #pts - 1 do
		local low, high = pts[i], pts[i + 1]
		local run = math.sqrt((high[1] - low[1]) ^ 2 + (high[3] - low[3]) ^ 2)
		local drop = high[2] - low[2]
		table.insert(parts, {
			name = "Waterfall",
			shape = "block",
			x = (low[1] + high[1]) / 2,
			y = (low[2] + high[2]) / 2,
			z = (low[3] + high[3]) / 2,
			sx = fall.width - (i - 1) * 6,
			sy = 1.2,
			sz = math.sqrt(run * run + drop * drop) + 6,
			yaw = yaw,
			pitch = -math.atan2(drop, run),
			color = { 196, 228, 242 },
			material = "Glass",
			collide = false,
			transparency = 0.3,
		})
	end
	local foot = pts[1]
	table.insert(parts, {
		name = "WaterfallFoam",
		shape = "block",
		x = foot[1] - fall.nx * 6,
		y = Map.WaterLevel + 0.3,
		z = foot[3] - fall.nz * 6,
		sx = fall.width + 12,
		sy = 1,
		sz = 16,
		yaw = yaw,
		color = { 240, 248, 250 },
		material = "SmoothPlastic",
		collide = false,
		transparency = 0.25,
	})
	return parts
end

-- The parts the builder makes: the trees, the flowers, the huts, the silhouettes (4 corner wedges, 4 more for a
-- cap), the portals (their parts and boards) and the waterfall.
function AlpineLayout.parts(ring: Ring, forest: Forest): number
	local n = #forest.trees * A.Trees.Parts
	for _, p in forest.patches do
		n += #p.flowers
	end
	for _, hut in forest.huts do
		n += #AlpineLayout.hutParts(hut)
	end
	for _, s in ring.silhouettes do
		n += if s.capY < math.huge then 8 else 4
	end
	for _, p in ring.portals do
		local parts, signs = AlpineLayout.portalParts(p)
		n += #parts + #signs
	end
	n += #AlpineLayout.waterfallParts(ring)
	return n
end

return AlpineLayout
