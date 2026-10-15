--!strict
-- 8.9 SANDBOX, Jinočany (design/jinocany/NAVRH.md, plan.json): the village's art kit as plain numbers, the way
-- shared/ChaletLooks.luau and shared/AuctionHouseLayout.luau give theirs. Pure (no Roblox at its top level:
-- tests/villagelooks_test.luau runs it in the Luau CLI, tools/village/preview.py draws it). Not on the map yet:
-- server/SandboxWorld.luau will build the village from plan.json's entries with it (each one's kind, box, yaw and
-- VillageLooks.seedOf(id)). Its colours, budgets and tuning are Config.Village's; nothing alpine (no spruce, no snow).
--
-- A house or a landmark comes in its own frame (VillageLooks.frame): its origin on the ground in the middle of its box,
-- +Y up, +Z out of its front door (to its street), +X to the right of somebody facing it from the street; its width w
-- along X, its depth d along Z (plan.json's box, turned with its yaw). The builder turns it by the entry's yaw:
--   CFrame.new(frame.x, GroundTop, frame.z) * CFrame.Angles(0, math.rad(frame.turn), 0), frame.turn = yaw + 180
-- (SandboxMap's yaw: the way the door looks, 0 north, 90 west); VillageLooks.place does it in numbers. Trees, field
-- tiles and the far view come on the map (their frame the map's, yaw 0). A piece's CFrame in its frame:
--   CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3]))
-- y is from the ground's top (SandboxMap.GroundTop). Every piece of a house or a landmark is inside its box, nothing
-- under the ground, nothing floating (it stands on the ground or on a piece that does).
--
--   The houses (plan.json houses' kinds; the body's front wall Config.Village.Front in from the box's front edge (its
--   eaves over the gap), the door in its middle just behind plan.json's door (VillageLooks.doorSpots); the garden behind
--   the body, in the box):
--     "old"      a Czech family house: a rendered body (cream, ochre, light grey, pale yellow, apricot) on a grey plinth,
--                a red or brown clay tile gable roof (its eaves to the street, or its gable), a chimney (brick or
--                rendered), the door, two windows in white or brown frames, the street fence on one side of the body
--                and the gate on the other
--     "row"      terraced houses: one body for the group (its width / RowUnit houses: plan.json's four in a row are one
--                call, VillageLooks.rowGroups), each house's door (unit 1 … n from -X), window, upper window and a
--                window to its garden, a party wall between two, a chimney for each two
--     "modern"   a new build: a white or grey box, a flat roof or a low mono-pitch, big windows in anthracite frames,
--                larch cladding, a window to its garden, a concrete fence and a slatted gate
--     rich       (opts.rich: one of the six houses to empty; a row's opts.richUnit) a little more: the doorstep, the
--                door's surround or canopy, a side and a gable window, the garden's fence round the back, the mailbox
--   The landmarks (VillageLooks.landmark; plan.json landmarks' kinds, each in its rect, Config.Village.Facing):
--     "chapel"   the green's chapel: a rendered nave (white or Maria Theresa yellow) with a slate gable, a round apse, the
--                tower at its front with the round-arched door, the bell opening, a green copper or slate spire, the cross
--     "green"    the chapel green round it (opts.chapel: the chapel's rect on the map): the gravel path to the chapel, the
--                wayside cross on its pedestal, six lindens, three benches, the contracts noticeboard (tag "contracts")
--     "pond"     the Little Pond: the water a hair under its grassy rim (Rim, Water), reeds, a jetty, two willows
--     "shop"     the Corner Drugstore (fictional, no real brand): a white box, a flat roof, the teal sign (tag "sign"),
--                the glass front, the entrance and its canopy, a car park with its bays, a lamp, a bike rack
--     "motorway" the D5's edge: the embankment, the two carriageways with their lines, the barrier in the middle, the
--                noise wall on the village's side (chunk "far")
--     "barrier"  Hornická's end: the red and white barrier across the road, its lamp, the no-entry sign, ROAD CLOSED
--     "hardware" (step 2) Stavebniny Sýkorka: the steel hall with its sign, door and roller door, an open timber shed,
--                pallets of bricks, blocks, tiles and bags, sand and gravel heaps, the yard's mesh fence
--   Trees (VillageLooks.tree): "linden", "oak", "birch", "poplar", "willow", "fruit": a trunk and one round crown
--   Field tiles (VillageLooks.field): "rapeseed", "wheat", "ploughed", "young": the ground in the crop's colour (its top
--   at the ground's: it is the ground, ground = true) and its rows
--   The far view (VillageLooks.horizon): outside the Bounds only: far fields, tree lines, a power line on pylons, the D5
--   going on, far roofs and a church tower
--
--   VillageLooks.house(kind, box, yaw, seed, opts?)      a house's pieces in its frame (opts: rich, units, richUnit)
--   VillageLooks.landmark(kind, box, yaw, seed, opts?)   a landmark's pieces in its frame (opts: chapel, for the green)
--   VillageLooks.tree(kind, x, z, seed, chunk?)          a tree's two pieces on the map (in its place's chunk)
--   VillageLooks.treeSize(kind, seed)                    its height and its crown's radius (the room a rule keeps)
--   VillageLooks.lineTrees(points, kind, seed)           the trees along a plan.json tree line ({ Spot }; the builder
--                                                        keeps them off its roads, lots and van ways)
--   VillageLooks.orchard(rect, seed)                     the orchard's fruit trees in rows ({ Spot })
--   VillageLooks.field(kind, rect, seed)                 a field tile and its rows on the map
--   VillageLooks.horizon(bounds, seed)                   the far view round the Bounds
--   VillageLooks.rowGroups(houses)                       plan.json's terraced houses in their groups (one body each)
--   VillageLooks.barrierAt(road)                         the barrier's box and yaw at a road's west end
--   VillageLooks.frame(box, yaw), turnOf(yaw)            a box's frame; place(pieces, box, yaw): its pieces on the map
--   VillageLooks.doorSpots(pieces, box, yaw)             the front doors on the map: outside each, looking out (a Spot)
--   VillageLooks.box(piece)                              a piece's axis-aligned box in its frame: x0, x1, y0, y1, z0, z1
--   VillageLooks.budget(kind, units?, rich?)             the most parts a call may give
--   VillageLooks.census(plan, step)                      the parts it gives a step's village of plan.json (by kind)
--   VillageLooks.seedOf(id), chunkOf(x, z)               a plan entry's dice; a place's chunk

local Config = require(script.Parent.Config)

local VillageLooks = {}

export type Box = { x0: number, x1: number, z0: number, z1: number }
export type Piece = {
	name: string,
	shape: string, -- "Block" | "Wedge" (high at its +Z, its slope down to its -Z) | "CornerWedge" (a CornerWedgePart: its apex over its (+X, -Z) corner) | "Cylinder" (along its own X) | "Ball" | "Ellipsoid" (a Block with a SpecialMesh Sphere)
	size: { number }, -- along its own X, Y, Z
	at: { number }, -- its middle in its frame (placed: on the map)
	yaw: number, -- degrees about Y before its turn: 0 in a frame (place: the frame's turn)
	turn: { number }?, -- degrees about X, Y, Z (CFrame.Angles), after the yaw
	color: { number },
	material: string, -- an Enum.Material's name (VillageLooks.Materials)
	solid: boolean, -- it collides and stops rays; else decoration
	alpha: number?, -- its transparency (nil: 0)
	tag: string?, -- a role the builder dresses: "door" (a front door), "sign" (a name board), "contracts" (the noticeboard)
	text: string?, -- the words on its +Z face (Enum.NormalId.Back)
	unit: number?, -- a terraced row's house (1 … n from -X) the piece belongs to
	ground: boolean?, -- the ground itself (a field tile: its top at the ground's top)
	chunk: string, -- its streaming chunk (Config.Village.Chunk; "ground", "far")
}
export type Frame = { x: number, z: number, turn: number, w: number, d: number }
export type Options = { rich: boolean?, units: number?, richUnit: number?, chapel: Box? }
export type Spot = { x: number, z: number, kind: string, seed: number }
export type DoorSpot = { x: number, y: number, z: number, yaw: number, unit: number? }
export type Group = { box: Box, yaw: number, ids: { string }, richUnit: number?, step: number, seed: number }
export type PlanHouse = { id: string, kind: string, box: Box, yaw: number, step: number?, enter: boolean?, street: string? }
-- plan.json's entries as census reads them (lines: plan.json's treeLines)
export type Plan = {
	houses: { PlanHouse },
	landmarks: { { id: string, kind: string, rect: Box, step: number } },
	roads: { { name: string, rect: Box, step: number } },
	fields: { { kind: string, rect: Box } },
	lines: { { kind: string, points: { { x: number, z: number } } } },
	bounds: Box,
}
export type Census = { houses: number, rows: number, landmarks: number, trees: number, fields: number, far: number, total: number }

local V = Config.Village
local P = V.Palette

VillageLooks.Budget = V.Budget
VillageLooks.Houses = { "old", "row", "modern" }
VillageLooks.Landmarks = { "chapel", "green", "pond", "shop", "motorway", "barrier", "hardware" }
VillageLooks.Trees = { "linden", "oak", "birch", "poplar", "willow", "fruit" }
VillageLooks.Fields = { "rapeseed", "wheat", "ploughed", "young" }
VillageLooks.Shapes = { "Block", "Wedge", "CornerWedge", "Cylinder", "Ball", "Ellipsoid" }
-- the materials it uses (each one of Enum.Material's)
VillageLooks.Materials = { "Plaster", "ClayRoofTiles", "Concrete", "Slate", "Brick", "Wood", "WoodPlanks", "Glass", "SmoothPlastic", "Grass", "LeafyGrass", "Ground", "Metal", "Asphalt", "Pebble", "Granite", "Neon", "Sand" }

-- The house's numbers (studs): the windows and the door, a roof's overhangs and its slabs, the plinth.
local DOOR = { 4, 7.2, 0.3 } -- (as the farmstead's front doorway, SandboxScenery.FrontDoor: 4 wide)
local WINDOW = { 3.6, 4.6 } -- an old house's window frame (the glass 0.8 less), its middle WINDOW_Y up
local WINDOW_Y = 5.4
local EAVE, VERGE, SLAB = 0.9, 0.7, 0.45
local PLINTH = 1.4
local FENCE_H, GATE_H = 3.6, 4.2

-- ── Small tools ────────────────────────────────────────────────────────────

local M = 2147483647

-- The dice: a Lehmer generator, exact in doubles (48271 × 2³¹ < 2⁵³), stirred first so near seeds part ways.
local function dice(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % (M - 1) + 1
	for _ = 1, 3 do
		state = (state * 48271) % M
	end
	return function(): number
		state = (state * 48271) % M
		return (state - 1) / (M - 1)
	end
end

local function pick<T>(roll: () -> number, list: { T }): T
	return list[math.floor(roll() * #list) % #list + 1]
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function shade(c: { number }, by: number): { number }
	return { math.clamp(c[1] + by, 0, 255), math.clamp(c[2] + by, 0, 255), math.clamp(c[3] + by, 0, 255) }
end

-- A plan entry's dice from its id (plan.json's "Hlavní_n_5": the same on every server).
function VillageLooks.seedOf(id: string): number
	local h = 7
	for i = 1, #id do
		h = (h * 31 + string.byte(id, i)) % M
	end
	return h + 1
end

function VillageLooks.chunkOf(x: number, z: number): string
	return `{math.floor(x / V.Chunk)}_{math.floor(z / V.Chunk)}`
end

-- ── The frame ──────────────────────────────────────────────────────────────

-- The frame's turn about Y (degrees) for SandboxMap's yaw (the way the door looks): local +Z out of the door.
function VillageLooks.turnOf(yaw: number): number
	return (yaw + 180) % 360
end

function VillageLooks.frame(box: Box, yaw: number): Frame
	local turn = VillageLooks.turnOf(yaw)
	local across = math.floor(turn / 90 + 0.5) % 2 == 1 -- (a quarter turn: its width along the map's z)
	local ex, ez = box.x1 - box.x0, box.z1 - box.z0
	return { x = (box.x0 + box.x1) / 2, z = (box.z0 + box.z1) / 2, turn = turn, w = if across then ez else ex, d = if across then ex else ez }
end

-- A point of the frame on the map.
local function toWorld(f: Frame, lx: number, lz: number): (number, number)
	local a = math.rad(f.turn)
	return f.x + math.cos(a) * lx + math.sin(a) * lz, f.z - math.sin(a) * lx + math.cos(a) * lz
end

-- A point of the map in the frame.
local function toLocal(f: Frame, x: number, z: number): (number, number)
	local a = math.rad(f.turn)
	local dx, dz = x - f.x, z - f.z
	return math.cos(a) * dx - math.sin(a) * dz, math.sin(a) * dx + math.cos(a) * dz
end

-- The pieces of a frame on the map (copies: at on the map, yaw the frame's turn).
function VillageLooks.place(pieces: { Piece }, box: Box, yaw: number): { Piece }
	local f = VillageLooks.frame(box, yaw)
	local out: { Piece } = {}
	for _, p in pieces do
		local x, z = toWorld(f, p.at[1], p.at[3])
		local q = table.clone(p)
		q.at = { x, p.at[2], z }
		q.yaw = (p.yaw + f.turn) % 360
		table.insert(out, q)
	end
	return out
end

-- The front doors (tag "door") on the map: on the ground just outside each, looking out (SandboxMap's yaw).
function VillageLooks.doorSpots(pieces: { Piece }, box: Box, yaw: number): { DoorSpot }
	local f = VillageLooks.frame(box, yaw)
	local out: { DoorSpot } = {}
	for _, p in pieces do
		if p.tag == "door" then
			local x, z = toWorld(f, p.at[1], p.at[3] + p.size[3] / 2)
			table.insert(out, { x = x, y = 0, z = z, yaw = (f.turn + 180) % 360, unit = p.unit })
		end
	end
	return out
end

-- A piece's axis-aligned box in its frame (its yaw and its turn taken into account): x0, x1, y0, y1, z0, z1.
function VillageLooks.box(piece: Piece): (number, number, number, number, number, number)
	local turn = piece.turn or { 0, 0, 0 }
	local ax, ay, az = math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3])
	-- CFrame.Angles(x, y, z) = Rx * Ry * Rz, after the yaw about Y: rows of Ryaw * Rx * Ry * Rz
	local cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
	local r = {
		{ cy * cz, -cy * sz, sy },
		{ cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy },
		{ sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy },
	}
	local yaw = math.rad(piece.yaw)
	local c, s = math.cos(yaw), math.sin(yaw)
	local rows = {
		{ c * r[1][1] + s * r[3][1], c * r[1][2] + s * r[3][2], c * r[1][3] + s * r[3][3] },
		r[2],
		{ -s * r[1][1] + c * r[3][1], -s * r[1][2] + c * r[3][2], -s * r[1][3] + c * r[3][3] },
	}
	local reach = {}
	for i = 1, 3 do
		local row = rows[i]
		reach[i] = math.abs(row[1]) * piece.size[1] / 2 + math.abs(row[2]) * piece.size[2] / 2 + math.abs(row[3]) * piece.size[3] / 2
	end
	local p = piece.at
	return p[1] - reach[1], p[1] + reach[1], p[2] - reach[2], p[2] + reach[2], p[3] - reach[3], p[3] + reach[3]
end

-- The most parts a call may give: a house (a row: each of its houses), one to empty a little more (Budget.Rich), a
-- landmark, a tree or a field tile.
function VillageLooks.budget(kind: string, units: number?, rich: boolean?): number
	local B = V.Budget
	local extra = if rich then B.Rich - (B[kind] or B.Rich) else 0
	if kind == "row" then
		return B.row * (units or 1) + extra
	end
	return (B[kind] or 0) + extra
end

-- ── The pieces ─────────────────────────────────────────────────────────────

type More = { shape: string?, turn: { number }?, solid: boolean?, alpha: number?, tag: string?, text: string?, unit: number?, ground: boolean? }
type Kit = { out: { Piece }, chunk: string }

local function put(k: Kit, name: string, size: { number }, at: { number }, color: { number }, material: string, more: More?): Piece
	local m: More = more or {}
	local p: Piece = {
		name = name,
		shape = m.shape or "Block",
		size = size,
		at = at,
		yaw = 0,
		turn = m.turn,
		color = color,
		material = material,
		solid = m.solid == true,
		alpha = m.alpha,
		tag = m.tag,
		text = m.text,
		unit = m.unit,
		ground = m.ground,
		chunk = k.chunk,
	}
	table.insert(k.out, p)
	return p
end

local SOLID: More = { solid = true }

-- A window on a wall: its frame proud of the wall, the glass in front of the frame's middle (a frame round dark
-- glass). `face`: the wall's outer face (z, or x when `side` turns it onto a side wall: -1 / 1 the wall at -X / +X).
local function window(k: Kit, name: string, x: number, y: number, face: number, w: number, h: number, frame: { number }, side: number?, unit: number?)
	if side then
		local turn = { 0, 90, 0 }
		put(k, name .. "Frame", { w, h, 0.2 }, { face + side * 0.1, y, x }, frame, "Wood", { turn = turn, unit = unit })
		put(k, name, { w - 0.8, h - 0.8, 0.12 }, { face + side * 0.24, y, x }, P.Glass, "Glass", { turn = turn, unit = unit })
	else
		put(k, name .. "Frame", { w, h, 0.2 }, { x, y, face + 0.1 }, frame, "Wood", { unit = unit })
		put(k, name, { w - 0.8, h - 0.8, 0.12 }, { x, y, face + 0.24 }, P.Glass, "Glass", { unit = unit })
	end
end

-- A gable roof over a body W wide (X) and D deep (Z), its walls h high, its middle at z = zc: the two attic wedges in
-- the walls' render (the gables), the two clay tile slabs (EAVE over the walls, VERGE over the gables) and the ridge
-- cap. along "x": the ridge along X (the eaves to the street); "z": from the front to the back (the gable to the
-- street). Returns the rise over the walls.
local function gableRoof(k: Kit, W: number, D: number, h: number, zc: number, along: string, pitch: number, render: { number }, tiles: { number }): number
	local half = if along == "x" then D / 2 else W / 2
	local rise = half * math.tan(pitch)
	local deg = math.deg(pitch)
	local L = (half + EAVE) / math.cos(pitch)
	local y = h + rise - (L / 2) * math.sin(pitch) + (SLAB / 2) * math.cos(pitch)
	local out = (L / 2) * math.cos(pitch) + (SLAB / 2) * math.sin(pitch)
	local top = h + rise + SLAB * math.cos(pitch) + 0.2 -- (the ridge cap's middle: on the slabs' upper corners, over the notch)
	if along == "x" then
		put(k, "Gable", { W, rise, half }, { 0, h + rise / 2, zc + half / 2 }, render, "Plaster", { shape = "Wedge", turn = { 0, 180, 0 }, solid = true })
		put(k, "Gable", { W, rise, half }, { 0, h + rise / 2, zc - half / 2 }, render, "Plaster", { shape = "Wedge", solid = true })
		for _, s in { 1, -1 } do
			put(k, "Roof", { W + 2 * VERGE, SLAB, L }, { 0, y, zc + s * out }, tiles, "ClayRoofTiles", { turn = { s * deg, 0, 0 }, solid = true })
		end
		put(k, "Ridge", { W + 2 * VERGE + 0.2, 0.5, 1 }, { 0, top, zc }, shade(tiles, -22), "ClayRoofTiles")
	else
		for _, s in { 1, -1 } do
			put(k, "Gable", { D, rise, half }, { s * half / 2, h + rise / 2, zc }, render, "Plaster", { shape = "Wedge", turn = { 0, -s * 90, 0 }, solid = true })
		end
		for _, s in { 1, -1 } do
			put(k, "Roof", { L, SLAB, D + 2 * VERGE }, { s * out, y, zc }, tiles, "ClayRoofTiles", { turn = { 0, 0, -s * deg }, solid = true })
		end
		put(k, "Ridge", { 1, 0.5, D + 2 * VERGE + 0.2 }, { 0, top, zc }, shade(tiles, -22), "ClayRoofTiles")
	end
	return rise
end

-- A fence run along the street line or round the garden: one piece (its boards and rails), from (ax, az) to (bx, bz)
-- along X or Z.
local function fenceRun(k: Kit, name: string, ax: number, az: number, bx: number, bz: number, height: number, color: { number }, material: string)
	local along = math.abs(bx - ax) >= math.abs(bz - az)
	local length = if along then math.abs(bx - ax) else math.abs(bz - az)
	local size = if along then { length, height, 0.25 } else { 0.25, height, length }
	put(k, name, size, { (ax + bx) / 2, height / 2, (az + bz) / 2 }, color, material)
end

-- A square pyramid of four corner wedges (each one's apex over its (+X, -Z) corner, all at the middle): its foot's
-- middle at (x, y, z), `half` its half side, `height` high (server/SandboxWorld.luau's far peaks are made the same way).
local function pyramid(k: Kit, name: string, x: number, y: number, z: number, half: number, height: number, color: { number }, material: string)
	for q = 0, 3 do
		local a = math.rad(q * 90)
		local ox, oz = -half / 2, half / 2
		put(k, name, { half, height, half }, { x + math.cos(a) * ox + math.sin(a) * oz, y + height / 2, z - math.sin(a) * ox + math.cos(a) * oz }, color, material, { shape = "CornerWedge", turn = { 0, q * 90, 0 } })
	end
end

-- ── The houses ─────────────────────────────────────────────────────────────

-- "old": a Czech family house (15 parts; rich 25).
local function oldHouse(k: Kit, f: Frame, roll: () -> number, rich: boolean)
	local w, d = f.w, f.d
	local along = if roll() < 0.5 then "x" else "z"
	-- (a gable to the street: narrower and deeper; the eaves to the street: wider)
	local W = math.min(w * (if along == "x" then pick(roll, { 0.68, 0.72, 0.76 }) else pick(roll, { 0.58, 0.62 })), w - 7)
	local D = math.min(d * (if along == "x" then pick(roll, { 0.6, 0.64 }) else pick(roll, { 0.68, 0.72 })), d - 4)
	local h = pick(roll, { 10.5, 11.5, 12.5 })
	local pitch = math.rad(pick(roll, { 38, 42, 45 }))
	local render = pick(roll, P.Render)
	local tiles = pick(roll, P.Tiles)
	local frame = pick(roll, P.Frames)
	local doorColor = pick(roll, P.Doors)
	local fence = pick(roll, P.Fences)
	local gate = if roll() < 0.5 then -1 else 1 -- (the gate's side; the fence on the other)
	local brick = roll() < 0.5
	local zf = d / 2 - V.Front
	local zc = zf - D / 2

	put(k, "House", { W, h, D }, { 0, h / 2, zc }, render, "Plaster", SOLID)
	put(k, "Plinth", { W + 0.3, PLINTH, D + 0.3 }, { 0, PLINTH / 2, zc }, P.Plinth, "Concrete", SOLID)
	local rise = gableRoof(k, W, D, h, zc, along, pitch, render, tiles)
	-- the chimney: through the back slope (or a side slope), its top over the ridge
	local top = h + rise + 1.8
	local cx, cz = if along == "x" then gate * W / 4 else -gate * W / 4, if along == "x" then zc - D / 4 else zc - D / 6
	put(k, "Chimney", { 1.8, top - (h - 0.5), 1.8 }, { cx, (top + h - 0.5) / 2, cz }, if brick then P.Brick else shade(render, -14), if brick then "Brick" else "Plaster", SOLID)
	put(k, "Door", DOOR, { 0, DOOR[2] / 2, zf + DOOR[3] / 2 }, doorColor, "Wood", { tag = "door", solid = true })
	local xw = math.clamp(W / 4 + 0.9, 4.6, W / 2 - 2.6)
	for _, side in { -1, 1 } do
		window(k, "Window", side * xw, WINDOW_Y, zf, WINDOW[1], WINDOW[2], frame)
	end
	-- the street line beside the body: the fence on one side, the gate on the other
	local from, to = W / 2 + 0.15, w / 2 - 0.15
	fenceRun(k, "Fence", -gate * from, zf, -gate * to, zf, FENCE_H, fence, "WoodPlanks")
	fenceRun(k, "Gate", gate * from, zf, gate * to, zf, GATE_H, P.Gate, "Wood")
	if not rich then
		return
	end
	-- rich: the doorstep, the door's surround, a side window and a gable window (both on the gate's side when the eaves
	-- face the street), the garden's fence round the back, the mailbox on the street fence
	put(k, "Step", { DOOR[1] + 1.2, 0.4, 1.2 }, { 0, 0.2, zf + 0.6 }, P.Concrete, "Concrete", SOLID)
	put(k, "DoorSurround", { DOOR[1] + 1.4, DOOR[2] + 1, 0.12 }, { 0, (DOOR[2] + 1) / 2, zf + 0.06 }, P.Trim, "Plaster")
	window(k, "SideWindow", zc + D / 6, WINDOW_Y, gate * W / 2, WINDOW[1], WINDOW[2], frame, gate)
	if along == "z" then
		window(k, "GableWindow", 0, h + 2.2, zf, 2.6, 3, frame)
	else
		window(k, "GableWindow", zc, h + 1.9, gate * W / 2, 2.4, 2.6, frame, gate)
	end
	local back = -d / 2 + 0.15
	for _, side in { -1, 1 } do
		fenceRun(k, "GardenFence", side * to, zf, side * to, back, FENCE_H, fence, "WoodPlanks")
	end
	fenceRun(k, "GardenFence", -to, back, to, back, FENCE_H, fence, "WoodPlanks")
	put(k, "Mailbox", { 1.4, 1.2, 0.6 }, { -gate * (from + 1.4), 3, zf + 0.425 }, P.Mailbox, "Metal")
end

-- "row": one terraced body of `n` houses (each RowUnit wide in the plan), each its door (unit j), window, upper window
-- and back window; the party walls between them, a chimney for each two. richUnit: that house a little more.
local function rowHouses(k: Kit, f: Frame, roll: () -> number, n: number, richUnit: number?)
	local w, d = f.w, f.d
	local U = w / n
	local W = w - 2 * VERGE - 0.2
	local D = math.min(16, d - 6)
	local h = pick(roll, { 14.5, 15.5 })
	local pitch = math.rad(pick(roll, { 34, 38, 42 }))
	local render = pick(roll, P.Render)
	local tiles = pick(roll, P.Tiles)
	local frame = pick(roll, P.Frames)
	local mirror = roll() < 0.5
	local zf = d / 2 - V.Front
	local zc = zf - D / 2

	put(k, "Row", { W, h, D }, { 0, h / 2, zc }, render, "Plaster", SOLID)
	put(k, "Plinth", { W + 0.3, PLINTH, D + 0.3 }, { 0, PLINTH / 2, zc }, P.Plinth, "Concrete", SOLID)
	local rise = gableRoof(k, W, D, h, zc, "x", pitch, render, tiles)
	local top = h + rise + 1.8
	for c = 1, math.ceil(n / 2) do
		-- (on the party wall between houses 2c - 1 and 2c; a last house alone: over its middle)
		local x = if 2 * c <= n then -w / 2 + U * (2 * c - 1) else -w / 2 + U * (2 * c - 1.5)
		put(k, "Chimney", { 2, top - (h - 0.5), 2.4 }, { x, (top + h - 0.5) / 2, zc - 1.6 }, P.Brick, "Brick", SOLID)
	end
	for j = 1, n - 1 do
		put(k, "PartyWall", { 0.6, h - PLINTH, 0.3 }, { -w / 2 + U * j, PLINTH + (h - PLINTH) / 2, zf + 0.15 }, shade(render, -16), "Plaster")
	end
	for j = 1, n do
		local cx = -w / 2 + U * (j - 0.5)
		local side = if mirror == (j % 2 == 0) then 1 else -1 -- (each two houses mirrored)
		local wx = cx + side * math.clamp(U / 4 + 0.6, 4.4, U / 2 - 2.4)
		put(k, "Door", { 3.6, DOOR[2], DOOR[3] }, { cx, DOOR[2] / 2, zf + DOOR[3] / 2 }, pick(roll, P.Doors), "Wood", { tag = "door", unit = j, solid = true })
		window(k, "Window", wx, 5.3, zf, 3.4, 4.4, frame, nil, j)
		window(k, "UpperWindow", cx, h - 3.6, zf, 4.6, 3.8, frame, nil, j)
		put(k, "BackWindow", { 3.4, 3.6, 0.12 }, { cx, 5.3, zf - D - 0.06 }, P.Glass, "Glass", { unit = j }) -- (the garden's side)
		if richUnit == j then
			-- the doorstep, a canopy over the door, the mailbox by it, a flower box under the window, the garden's
			-- fence round the house's own strip at the back
			put(k, "Step", { 4.8, 0.4, 1.2 }, { cx, 0.2, zf + 0.6 }, P.Concrete, "Concrete", { unit = j, solid = true })
			put(k, "Canopy", { 5.6, 0.4, 1.4 }, { cx, DOOR[2] + 0.8, zf + 0.7 }, P.Anthracite, "Metal", { unit = j })
			put(k, "Mailbox", { 1.2, 1.4, 0.5 }, { cx - side * 2.7, 4.4, zf + 0.25 }, P.Mailbox, "Metal", { unit = j })
			put(k, "FlowerBox", { 3.6, 0.8, 0.9 }, { wx, 2.5, zf + 0.45 }, P.Hedge, "Grass", { unit = j })
			local zb, back = zf - D, -d / 2 + 0.15
			local fence = pick(roll, P.Fences)
			for _, s in { -1, 1 } do
				fenceRun(k, "GardenFence", cx + s * (U / 2 - 0.15), zb, cx + s * (U / 2 - 0.15), back, FENCE_H, fence, "WoodPlanks")
			end
			fenceRun(k, "GardenFence", cx - U / 2 + 0.15, back, cx + U / 2 - 0.15, back, FENCE_H, fence, "WoodPlanks")
		end
	end
end

-- "modern": a new build (at most 15; rich more).
local function modernHouse(k: Kit, f: Frame, roll: () -> number, rich: boolean)
	local w, d = f.w, f.d
	local W = math.min(w - 7, 22)
	local D = math.min(d - 6, 15)
	local tall = roll() < 0.5 -- (two storeys)
	local h = if tall then 16.5 else 10.5
	local mono = roll() < 0.5
	local wall = pick(roll, P.Modern)
	local gate = if roll() < 0.5 then -1 else 1
	local zf = d / 2 - V.Front
	local zc = zf - D / 2

	put(k, "House", { W, h, D }, { 0, h / 2, zc }, wall, "Plaster", SOLID)
	if mono then
		-- a low mono-pitch: up to the back, a thin dark slab on the wedge
		local rise = D * math.tan(math.rad(10))
		local a = math.atan(rise / D)
		put(k, "RoofWedge", { W, rise, D }, { 0, h + rise / 2, zc }, wall, "Plaster", { shape = "Wedge", turn = { 0, 180, 0 }, solid = true })
		local L = D / math.cos(a) + 1.2
		put(k, "Roof", { W + 1.2, 0.4, L }, { 0, h + rise / 2 + 0.2 * math.cos(a), zc + 0.2 * math.sin(a) }, P.FlatRoof, "Slate", { turn = { math.deg(a), 0, 0 }, solid = true })
	else
		put(k, "Roof", { W + 1.2, 0.8, D + 1.2 }, { 0, h + 0.4, zc }, P.FlatRoof, "Concrete", SOLID)
	end
	put(k, "Door", { 3.6, 7.4, DOOR[3] }, { 0, 3.7, zf + DOOR[3] / 2 }, P.Anthracite, "Metal", { tag = "door", solid = true })
	put(k, "Canopy", { 6, 0.5, 1.4 }, { 0, 8.6, zf + 0.7 }, P.Concrete, "Concrete")
	-- the living room's big window on one side, larch cladding with a narrow window on the other
	local wx = -gate * (W / 4 + 1.2)
	put(k, "BigWindowFrame", { 7.6, 6.6, 0.2 }, { wx, 4, zf + 0.1 }, P.Anthracite, "Metal")
	put(k, "BigWindow", { 7, 6, 0.12 }, { wx, 4, zf + 0.24 }, P.Glass, "Glass")
	local c0, c1 = 2.6, W / 2
	put(k, "Cladding", { c1 - c0, h, 0.15 }, { gate * (c0 + c1) / 2, h / 2, zf + 0.075 }, P.Larch, "WoodPlanks")
	put(k, "SlotWindow", { 1.4, 6.4, 0.12 }, { gate * (c0 + c1) / 2, 4.2, zf + 0.21 }, P.Glass, "Glass")
	if tall then
		put(k, "UpperWindowFrame", { 12, 3.6, 0.2 }, { -gate * 2, h - 4, zf + 0.1 }, P.Anthracite, "Metal")
		put(k, "UpperWindow", { 11.4, 3, 0.12 }, { -gate * 2, h - 4, zf + 0.24 }, P.Glass, "Glass")
	end
	put(k, "BackWindow", { 8, 6, 0.12 }, { gate * 3, 4.4, zf - D - 0.06 }, P.Glass, "Glass") -- (the garden's side)
	local from, to = W / 2 + 0.15, w / 2 - 0.15
	put(k, "Wall", { to - from, 2.6, 0.5 }, { -gate * (from + to) / 2, 1.3, zf }, P.Concrete, "Concrete")
	fenceRun(k, "Gate", gate * from, zf, gate * to, zf, 4, P.Anthracite, "Metal")
	if not rich then
		return
	end
	put(k, "Step", { 5, 0.3, 1.2 }, { 0, 0.15, zf + 0.6 }, P.Concrete, "Concrete", SOLID)
	window(k, "SideWindow", zc, 4, gate * W / 2, 5, 3.6, P.Anthracite, gate)
	local back = -d / 2 + 0.15
	for _, side in { -1, 1 } do
		fenceRun(k, "GardenFence", side * to, zf, side * to, back, 3.2, P.Anthracite, "Metal")
	end
	fenceRun(k, "GardenFence", -to, back, to, back, 3.2, P.Anthracite, "Metal")
	put(k, "Mailbox", { 1.4, 1.2, 0.6 }, { -gate * (from + 2), 3.2, zf + 0.55 }, P.Anthracite, "Metal")
end

-- A house's pieces in its frame (VillageLooks.frame(box, yaw)). kind: "old" | "row" | "modern"; seed: its dice
-- (VillageLooks.seedOf(id): the same house every time); opts.rich: one of the six houses to empty (a row's richUnit:
-- which house of it); opts.units: a row's houses (default its width / RowUnit).
function VillageLooks.house(kind: string, box: Box, yaw: number, seed: number, opts: Options?): { Piece }
	local o: Options = opts or {}
	local f = VillageLooks.frame(box, yaw)
	local k: Kit = { out = {}, chunk = VillageLooks.chunkOf(f.x, f.z) }
	local roll = dice(seed)
	if kind == "old" then
		oldHouse(k, f, roll, o.rich == true)
	elseif kind == "row" then
		local n = o.units or math.max(1, math.floor(f.w / V.RowUnit + 0.5))
		rowHouses(k, f, roll, n, if o.rich then o.richUnit or 1 else nil)
	elseif kind == "modern" then
		modernHouse(k, f, roll, o.rich == true)
	else
		error(`VillageLooks.house: no house kind "{kind}"`)
	end
	return k.out
end

-- plan.json's terraced houses ("row") in their groups: houses of one street side next to each other, at most four
-- (plan.py's ROW_GROUP), one body each. ids from the body's -X (unit 1) on; richUnit: the one to empty.
function VillageLooks.rowGroups(houses: { PlanHouse }): { Group }
	local rows: { { h: PlanHouse, u: number, v: number } } = {}
	for _, h in houses do
		if h.kind == "row" then
			local turn = math.rad(VillageLooks.turnOf(h.yaw))
			local x, z = (h.box.x0 + h.box.x1) / 2, (h.box.z0 + h.box.z1) / 2
			-- u along the body's +X on the map, v across (out of the door)
			table.insert(rows, { h = h, u = math.cos(turn) * x - math.sin(turn) * z, v = math.sin(turn) * x + math.cos(turn) * z })
		end
	end
	table.sort(rows, function(a, b)
		if a.h.yaw ~= b.h.yaw then
			return a.h.yaw < b.h.yaw
		end
		if math.abs(a.v - b.v) > 0.01 then
			return a.v < b.v
		end
		return a.u < b.u
	end)
	local groups: { Group } = {}
	local current: Group? = nil
	local last: { h: PlanHouse, u: number, v: number }? = nil
	for _, r in rows do
		local h = r.h
		local width = math.min(h.box.x1 - h.box.x0, h.box.z1 - h.box.z0)
		local joins = current ~= nil and last ~= nil and last.h.yaw == h.yaw and math.abs(last.v - r.v) < 0.01
			and math.abs(r.u - last.u - width) < 0.01 and #(current :: Group).ids < 4
		if joins and current then
			local b = current.box
			b.x0, b.x1, b.z0, b.z1 = math.min(b.x0, h.box.x0), math.max(b.x1, h.box.x1), math.min(b.z0, h.box.z0), math.max(b.z1, h.box.z1)
			table.insert(current.ids, h.id)
		else
			current = { box = { x0 = h.box.x0, x1 = h.box.x1, z0 = h.box.z0, z1 = h.box.z1 }, yaw = h.yaw, ids = { h.id }, step = h.step or 1, seed = VillageLooks.seedOf(h.id) }
			table.insert(groups, current :: Group)
		end
		if h.enter and current then
			current.richUnit = #current.ids
		end
		last = r
	end
	return groups
end

-- ── The trees ──────────────────────────────────────────────────────────────

-- A tree's height and its crown's radius (the room a rule keeps round it).
function VillageLooks.treeSize(kind: string, seed: number): (number, number)
	local T = V.Trees[kind]
	assert(T, `VillageLooks: no tree kind "{kind}"`)
	local roll = dice(seed)
	local height = lerp(T.Height[1], T.Height[2], roll())
	return height, height * T.Wide / 2
end

-- A tree on the map: the trunk (a cylinder standing up, solid) into one round crown (an ellipsoid, decoration).
function VillageLooks.tree(kind: string, x: number, z: number, seed: number, chunk: string?): { Piece }
	local T = V.Trees[kind]
	local look = P.Trees[kind]
	local height, radius = VillageLooks.treeSize(kind, seed)
	local roll = dice(seed + 7)
	local k: Kit = { out = {}, chunk = chunk or VillageLooks.chunkOf(x, z) }
	local tall = height * T.Tall
	local foot = height - tall -- (the crown's lowest point)
	local trunk = foot + tall * 0.35
	local thick = math.max(0.8, height * T.Trunk)
	put(k, "Trunk", { trunk, thick, thick }, { x, trunk / 2, z }, look.Trunk, "Wood", { shape = "Cylinder", turn = { 0, 0, 90 }, solid = true })
	put(k, "Crown", { 2 * radius, tall, 2 * radius * lerp(0.86, 1, roll()) }, { x, height - tall / 2, z }, pick(roll, look.Crowns), "Grass", { shape = "Ellipsoid", turn = { 0, if roll() < 0.5 then 90 else 0, 0 } })
	return k.out
end

-- The trees along a plan.json tree line: "windbreak" (Lines.Mix's kinds, Lines.Windbreak apart) or "alley" (fruit
-- trees, Lines.Alley apart), a little off the line each.
function VillageLooks.lineTrees(points: { { x: number, z: number } }, kind: string, seed: number): { Spot }
	local roll = dice(seed)
	local alley = kind == "alley"
	local step = if alley then V.Lines.Alley else V.Lines.Windbreak
	local out: { Spot } = {}
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local length = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local n = math.max(1, math.floor(length / step + 0.5))
		local dx, dz = (b.x - a.x) / length, (b.z - a.z) / length
		for j = if i == 1 then 0 else 1, n do
			local t = j / n
			local along, off = (roll() - 0.5) * (if alley then 2 else 8), (roll() - 0.5) * (if alley then 1 else 4)
			local tree = if alley then "fruit" else pick(roll, V.Lines.Mix)
			table.insert(out, { x = lerp(a.x, b.x, t) + dx * along - dz * off, z = lerp(a.z, b.z, t) + dz * along + dx * off, kind = tree, seed = math.floor(roll() * 999983) + 1 })
		end
	end
	return out
end

-- The orchard's fruit trees in rows (Lines.Orchard apart, Lines.Edge in from its rect).
function VillageLooks.orchard(rect: Box, seed: number): { Spot }
	local roll = dice(seed)
	local sx, sz, edge = V.Lines.Orchard[1], V.Lines.Orchard[2], V.Lines.Edge
	local nx = math.floor((rect.x1 - rect.x0 - 2 * edge) / sx) + 1
	local nz = math.floor((rect.z1 - rect.z0 - 2 * edge) / sz) + 1
	local x0 = (rect.x0 + rect.x1) / 2 - (nx - 1) * sx / 2
	local z0 = (rect.z0 + rect.z1) / 2 - (nz - 1) * sz / 2
	local out: { Spot } = {}
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			table.insert(out, { x = x0 + i * sx + (roll() - 0.5) * 3, z = z0 + j * sz + (roll() - 0.5) * 3, kind = "fruit", seed = math.floor(roll() * 999983) + 1 })
		end
	end
	return out
end

-- ── The landmarks ──────────────────────────────────────────────────────────

-- A bench (seat, back, two legs) at (x, z) looking `facing` degrees about Y from +Z.
local function bench(k: Kit, x: number, z: number, facing: number)
	local a = math.rad(facing)
	local function at(u: number, y: number, v: number): { number }
		return { x + math.cos(a) * u + math.sin(a) * v, y, z - math.sin(a) * u + math.cos(a) * v }
	end
	local turn = { 0, facing, 0 }
	put(k, "BenchSeat", { 6, 0.35, 1.6 }, at(0, 1.9, 0), P.Bench, "WoodPlanks", { turn = turn, solid = true })
	put(k, "BenchBack", { 6, 1.5, 0.25 }, at(0, 2.8, -0.75), P.Bench, "WoodPlanks", { turn = turn })
	for _, s in { -1, 1 } do
		put(k, "BenchLeg", { 0.35, 2, 1.5 }, at(s * 2.6, 1, -0.05), P.Iron, "Metal", { turn = turn })
	end
end

-- A small tree of a landmark (its two pieces in the landmark's frame).
local function landmarkTree(k: Kit, kind: string, x: number, z: number, seed: number)
	for _, p in VillageLooks.tree(kind, x, z, seed, k.chunk) do
		table.insert(k.out, p)
	end
end

-- "chapel": the nave, its apse, the tower with its spire and cross at the front (the door in its base).
local function chapel(k: Kit, f: Frame, roll: () -> number)
	local d = f.d
	local wall = pick(roll, P.Chapel)
	local spire = pick(roll, P.Spire)
	local zf = d / 2 - V.Front
	local T, HT = 7, 24 -- the tower: its side, its walls' top
	local W, D, h = math.min(14, f.w - 4), math.min(24, d - 16), 11 -- the nave
	local zn = zf - 5 -- (the nave's front: the tower stands 5 out of it)
	local zc = zn - D / 2
	put(k, "Tower", { T, HT, T }, { 0, HT / 2, zf - T / 2 }, wall, "Plaster", SOLID)
	pyramid(k, "Spire", 0, HT, zf - T / 2, T / 2 + 0.4, 8, spire, "Slate")
	put(k, "CrossShaft", { 0.3, 3.2, 0.3 }, { 0, HT + 8 + 1.5, zf - T / 2 }, P.Gold, "Metal")
	put(k, "CrossArm", { 1.6, 0.3, 0.3 }, { 0, HT + 8 + 2.2, zf - T / 2 }, P.Gold, "Metal")
	put(k, "BellOpening", { 2.4, 3.6, 0.2 }, { 0, HT - 5, zf + 0.1 }, P.Iron, "Wood")
	put(k, "Door", { 3.6, 6.4, 0.3 }, { 0, 3.2, zf + 0.15 }, P.DarkWood, "Wood", { tag = "door", solid = true })
	put(k, "DoorArch", { 0.3, 3.6, 3.6 }, { 0, 6.4, zf + 0.15 }, P.DarkWood, "Wood", { shape = "Cylinder", turn = { 0, 90, 0 } })
	put(k, "Step", { 6, 0.4, 1.4 }, { 0, 0.2, zf + 0.7 }, P.Stone, "Granite", SOLID)
	put(k, "Nave", { W, h, D }, { 0, h / 2, zc }, wall, "Plaster", SOLID)
	put(k, "Plinth", { W + 0.3, 1.2, D + 0.3 }, { 0, 0.6, zc }, P.Stone, "Granite", SOLID)
	gableRoof(k, W, D, h, zc, "z", math.rad(50), wall, P.Slate)
	for _, side in { -1, 1 } do
		for _, z in { zc - D / 4, zc + D / 4 } do
			put(k, "ChapelWindow", { 0.2, 5, 2.2 }, { side * (W / 2 + 0.1), 6, z }, P.Glass, "Glass")
		end
	end
	-- the apse: a half round at the back (a cylinder standing on the back wall), its half dome a ball
	local zb = zn - D
	put(k, "Apse", { 9, 10, 10 }, { 0, 4.5, zb }, wall, "Plaster", { shape = "Cylinder", turn = { 0, 0, 90 }, solid = true })
	put(k, "ApseRoof", { 10, 10, 10 }, { 0, 9, zb }, P.Slate, "Slate", { shape = "Ball" })
end

-- "green": the chapel green (the chapel's own rect, opts.chapel, on the map; else in its middle at the back).
local function green(k: Kit, f: Frame, roll: () -> number, chapelRect: Box?)
	local w, d = f.w, f.d
	local cx, front = 0, -d / 2 + 55
	if chapelRect then
		local ax, az = toLocal(f, chapelRect.x0, chapelRect.z0)
		local bx, bz = toLocal(f, chapelRect.x1, chapelRect.z1)
		cx, front = (ax + bx) / 2, math.max(az, bz)
	end
	-- the gravel path from the road to the chapel's step
	local z0, z1 = front + 1.5, d / 2 - 0.5
	put(k, "Path", { 5, 0.06, z1 - z0 }, { cx, 0.03, (z0 + z1) / 2 }, P.Gravel, "Pebble")
	-- the wayside cross on its stone pedestal in a low box hedge, near the road
	local xc, zc = cx - 10, math.min(front + 30, d / 2 - 8)
	put(k, "CrossHedge", { 6.5, 0.5, 6.5 }, { xc, 0.25, zc }, P.Hedge, "LeafyGrass")
	put(k, "CrossBase", { 3.6, 1.2, 3.6 }, { xc, 0.6, zc }, P.Stone, "Granite", SOLID)
	put(k, "CrossPedestal", { 1.8, 3, 1.8 }, { xc, 2.7, zc }, P.Stone, "Granite", SOLID)
	put(k, "CrossShaft", { 0.6, 9, 0.6 }, { xc, 8.7, zc }, P.Iron, "Metal")
	put(k, "CrossArm", { 3.6, 0.6, 0.6 }, { xc, 11.2, zc }, P.Iron, "Metal")
	-- the lindens: two before the chapel, four at the green's corners
	local spots = { { cx - 13, front + 13 }, { cx + 13, front + 13 }, { -w / 2 + 16, d / 2 - 16 }, { w / 2 - 16, d / 2 - 16 }, { -w / 2 + 16, -d / 2 + 16 }, { w / 2 - 16, -d / 2 + 16 } }
	for n, s in spots do
		landmarkTree(k, "linden", s[1], s[2], math.floor(roll() * 999983) + n)
	end
	bench(k, cx - 13, front + 19, 0)
	bench(k, cx + 13, front + 19, 0)
	bench(k, w / 2 - 30, d / 2 - 12, 0)
	-- the noticeboard by the road (the move contracts: tag "contracts"), facing it
	local xb, zb = cx + 11, d / 2 - 4
	for _, s in { -1, 1 } do
		put(k, "NoticePost", { 0.4, 7.4, 0.4 }, { xb + s * 3.2, 3.7, zb }, P.DarkWood, "Wood", SOLID)
	end
	put(k, "Noticeboard", { 6.8, 4, 0.3 }, { xb, 4.6, zb }, P.Notice, "Wood", { tag = "contracts", text = "MOVING CONTRACTS", solid = true })
	put(k, "NoticeRoof", { 7.8, 0.3, 1.4 }, { xb, 7.55, zb }, P.DarkWood, "WoodPlanks")
end

-- "pond": the water (a long middle and two round ends) a hair under its grassy rim (the rim: two long sides, the
-- round ends in straight pieces), reeds, a jetty, two willows in the corners.
local function pond(k: Kit, f: Frame, roll: () -> number)
	local longX = f.w >= f.d
	local L, S = math.max(f.w, f.d), math.min(f.w, f.d)
	local RW, RH = 4, 0.8 -- the rim's width and its top
	local Ro = S / 2 - 1
	local r = Ro - RW / 2 -- (the rim's middle line round the ends)
	local a0 = L / 2 - 1 - Ro -- (the ends' middles at ±a0 along the pond)
	local K = 6 -- (the round ends in K - 1 straight pieces, the long sides reaching round to the first)
	local tanH = math.tan(math.pi / (2 * K))
	local Rw = r + 0.5 -- the water's radius: under the rim all round
	local function at(a: number, y: number, b: number): { number }
		return if longX then { a, y, b } else { b, y, a }
	end
	local function axis(ta: number, tb: number): { number }
		-- the turn that lays a piece's own X along (ta, tb) (a along the pond, b across it)
		local tx, tz = if longX then ta else tb, if longX then tb else ta
		return { 0, math.deg(math.atan2(-tz, tx)), 0 }
	end
	local side = 2 * (a0 + (r + RW / 2) * tanH)
	for _, s in { -1, 1 } do
		put(k, "Rim", { side, RH, RW }, at(0, RH / 2, s * r), P.Bank, "Grass", { turn = axis(1, 0), solid = true })
	end
	local seg = 2 * (r + RW / 2) * tanH + 0.4
	for _, e in { -1, 1 } do
		for i = 1, K - 1 do
			local th = -math.pi / 2 + i * math.pi / K
			local ca, sb = math.cos(th), math.sin(th)
			put(k, "Rim", { seg, RH, RW }, at(e * (a0 + r * ca), RH / 2, r * sb), P.Bank, "Grass", { turn = axis(-e * sb, ca), solid = true })
		end
	end
	local top = RH - 0.05 -- (a hair under the rim)
	put(k, "Water", { 2 * a0, top, 2 * Rw }, at(0, top / 2, 0), P.Water, "Glass", { turn = axis(1, 0) })
	for _, e in { -1, 1 } do
		put(k, "Water", { top, 2 * Rw, 2 * Rw }, at(e * a0, top / 2, 0), P.Water, "Glass", { shape = "Cylinder", turn = { 0, 0, 90 } })
	end
	-- reeds on the rim at the far end, a jetty out from one long side, two willows in the corners
	for _, th in { -40, 40 } do
		local a = math.rad(th)
		put(k, "Reeds", { 3, 3.4, 3 }, at(-(a0 + r * math.cos(a)), RH + 1.5, r * math.sin(a)), P.Reeds, "LeafyGrass", { shape = "Ellipsoid" })
	end
	local ja = a0 * 0.4
	put(k, "Jetty", { 4, 0.3, 10 }, at(ja, RH + 0.25, r - 3), P.Bench, "WoodPlanks", { turn = axis(1, 0), solid = true })
	for _, s in { -1, 1 } do
		put(k, "JettyPost", { 0.5, RH + 0.1, 0.5 }, at(ja + s * 1.5, (RH + 0.1) / 2, r - 7.5), P.DarkWood, "Wood")
	end
	local willow = V.Trees.willow
	local inset = willow.Height[2] * willow.Wide / 2 + 1.5 -- (the biggest willow's crown inside the box)
	for n, c in { { 1, 1 }, { -1, -1 } } do
		local p = at(c[1] * (L / 2 - inset), 0, c[2] * (S / 2 - inset))
		landmarkTree(k, "willow", p[1], p[3], math.floor(roll() * 999983) + n)
	end
end

-- "shop": the Corner Drugstore (fictional): the store at the back of its rect, its car park in front.
local function shop(k: Kit, f: Frame, roll: () -> number)
	local w, d = f.w, f.d
	local S = P.Shop
	local W, D, h = math.min(48, w - 8), math.min(28, d - 24), 12
	local zb = -d / 2 + 1.5
	local zf = zb + D
	local zc = (zb + zf) / 2
	put(k, "Store", { W, h, D }, { 0, h / 2, zc }, S.Wall, "Plaster", SOLID)
	put(k, "Roof", { W + 0.4, 1.2, D + 0.4 }, { 0, h + 0.6, zc }, P.Concrete, "Concrete", SOLID)
	put(k, "Sign", { W - 8, 3, 0.4 }, { 0, h - 1.9, zf + 0.2 }, S.Sign, "SmoothPlastic", { tag = "sign", text = "CORNER DRUGSTORE" })
	put(k, "ShopfrontFrame", { W - 10, 7.6, 0.2 }, { 1, 4.4, zf + 0.1 }, P.Anthracite, "Metal")
	put(k, "Shopfront", { W - 11, 6.8, 0.12 }, { 1, 4.4, zf + 0.24 }, S.Glass, "Glass")
	local ex = -(W / 2 - 6) -- (the entrance by the corner)
	put(k, "Door", { 6, 7.2, 0.3 }, { ex, 3.6, zf + 0.15 }, S.Door, "Glass", { tag = "door", solid = true })
	put(k, "Canopy", { 10, 0.5, 4 }, { ex, 8.4, zf + 2 }, S.Canopy, "SmoothPlastic")
	-- the car park in front, its bays across it
	local p0, p1 = zf + 3, d / 2 - 1
	put(k, "CarPark", { w - 4, 0.08, p1 - p0 }, { 0, 0.04, (p0 + p1) / 2 }, P.Asphalt, "Asphalt")
	local bay = 10
	local count = math.min(6, math.floor((w - 12) / bay))
	for i = 0, count - 1 do
		put(k, "BayLine", { 0.3, 0.02, 9 }, { (i - (count - 1) / 2) * bay, 0.09, p0 + 5 }, P.Line, "SmoothPlastic")
	end
	local lx = w / 2 - 4
	put(k, "LampPost", { 0.5, 12, 0.5 }, { lx, 6, p1 - 2 }, P.Iron, "Metal", SOLID)
	put(k, "Lamp", { 2.4, 0.4, 1 }, { lx - 0.95, 12.2, p1 - 2 }, P.Iron, "Metal")
	put(k, "BikeRack", { 4, 1.6, 0.3 }, { W / 2 - 3, 0.8, zf + 1.6 }, P.Iron, "Metal")
end

-- "motorway": the D5's edge, along its frame's X (w long), the village at +Z: the embankment's slopes, its body
-- (grass between the carriageways), the two carriageways and their edge lines, the barrier in the middle, the noise
-- wall on the village's side in six panels.
local function motorway(k: Kit, f: Frame, roll: () -> number)
	local w, d = f.w, f.d
	local E = 5 -- the road's top over the fields
	local run = 9
	local body = d / 2 - run
	put(k, "Embankment", { w, E, run }, { 0, E / 2, body + run / 2 }, P.Grass, "Grass", { shape = "Wedge", turn = { 0, 180, 0 }, solid = true })
	put(k, "Embankment", { w, E, run }, { 0, E / 2, -body - run / 2 }, P.Grass, "Grass", { shape = "Wedge", solid = true })
	put(k, "MotorwayBody", { w, E, 2 * body }, { 0, E / 2, 0 }, P.Grass, "Grass", SOLID)
	for _, s in { -1, 1 } do
		put(k, "Carriageway", { w, 0.2, 15 }, { 0, E + 0.1, s * 9.5 }, P.Asphalt, "Asphalt", SOLID)
		for _, e in { 2.6, 16.4 } do
			put(k, "EdgeLine", { w, 0.04, 0.35 }, { 0, E + 0.22, s * e }, P.Line, "SmoothPlastic")
		end
	end
	put(k, "CrashBarrier", { w, 1.2, 0.5 }, { 0, E + 0.6, 0 }, P.Rail, "Metal", SOLID)
	local panels = 6
	for i = 0, panels - 1 do
		put(k, "NoiseWall", { w / panels, 9, 0.6 }, { -w / 2 + (i + 0.5) * w / panels, E + 4.5, body - 1 }, P.NoiseWall[i % 2 + 1], "Concrete", SOLID)
	end
end

-- "barrier": the end of Hornická (its box across the road, the signs looking +Z).
local function barrier(k: Kit, f: Frame, roll: () -> number)
	local w = f.w
	local B = P.Barrier
	local span = w - 2
	for _, s in { -1, 1 } do
		put(k, "BarrierPost", { 0.5, 4.4, 0.5 }, { s * span / 2, 2.2, 0 }, B.Post, "Metal", SOLID)
	end
	put(k, "BarrierBoard", { span, 1.4, 0.2 }, { 0, 3.4, 0.35 }, B.White, "SmoothPlastic", SOLID)
	local bands = 5
	for i = 0, bands - 1 do
		put(k, "BarrierStripe", { span / (2 * bands - 1), 1.4, 0.06 }, { -span / 2 + (2 * i + 0.5) * span / (2 * bands - 1), 3.4, 0.48 }, B.Red, "SmoothPlastic")
	end
	put(k, "WarningLamp", { 0.9, 0.9, 0.9 }, { span / 2 - 1.5, 4.55, 0.35 }, B.Lamp, "Neon")
	put(k, "SignPost", { 0.4, 11, 0.4 }, { 0, 5.5, -1.4 }, B.Post, "Metal", SOLID)
	put(k, "ClosedBoard", { 8, 2.4, 0.2 }, { 0, 6.4, -1.1 }, B.Red, "SmoothPlastic", { tag = "sign", text = "ROAD CLOSED" })
	-- the no-entry sign: a red disc, a white one in front of it
	put(k, "NoEntry", { 0.12, 3, 3 }, { 0, 9.4, -1.14 }, B.Red, "SmoothPlastic", { shape = "Cylinder", turn = { 0, 90, 0 } })
	put(k, "NoEntryWhite", { 0.06, 2.2, 2.2 }, { 0, 9.4, -1.05 }, B.White, "SmoothPlastic", { shape = "Cylinder", turn = { 0, 90, 0 } })
end

-- "hardware" (step 2): Stavebniny Sýkorka's yard (its front +Z to the car park): the steel hall at the back on the
-- left, its sign, door, canopy and roller door, the open timber shed on the right, the pallets and heaps in the yard,
-- the mesh fence round the sides and the back.
local function hardware(k: Kit, f: Frame, roll: () -> number)
	local w, d = f.w, f.d
	local H = P.Hardware
	local W, D, h = math.min(60, w * 0.45), math.min(30, d * 0.4), 14
	local x0 = -w / 2 + 4
	local hx, zb = x0 + W / 2, -d / 2 + 3
	local zf = zb + D
	local zc = (zb + zf) / 2
	put(k, "Hall", { W, h, D }, { hx, h / 2, zc }, H.Hall, "Metal", SOLID)
	local rise = 3.5
	put(k, "HallRoof", { W + 1, rise, D / 2 + 0.5 }, { hx, h + rise / 2, zc + D / 4 + 0.25 }, H.Roof, "Metal", { shape = "Wedge", turn = { 0, 180, 0 }, solid = true })
	put(k, "HallRoof", { W + 1, rise, D / 2 + 0.5 }, { hx, h + rise / 2, zc - D / 4 - 0.25 }, H.Roof, "Metal", { shape = "Wedge", solid = true })
	put(k, "Sign", { W * 0.7, 3.4, 0.4 }, { hx, h - 2.4, zf + 0.2 }, H.Sign, "SmoothPlastic", { tag = "sign", text = "SÝKORKA BUILDING SUPPLIES" })
	put(k, "Door", { 5, 7.2, 0.3 }, { hx - W / 4, 3.6, zf + 0.15 }, P.Glass, "Glass", { tag = "door", solid = true })
	put(k, "Canopy", { 8, 0.5, 3.4 }, { hx - W / 4, 8.4, zf + 1.7 }, H.Sign, "SmoothPlastic")
	put(k, "RollerDoor", { 12, 9, 0.3 }, { hx + W / 4, 4.5, zf + 0.15 }, H.Door, "Metal")
	-- the open timber shed: four posts, its roof; timber stacked under it
	local sx0, sx1 = x0 + W + 10, w / 2 - 6
	local sz0, sz1 = zb, zb + 16
	local sh = 9
	for _, c in { { sx0, sz0 }, { sx1, sz0 }, { sx0, sz1 }, { sx1, sz1 } } do
		put(k, "ShedPost", { 0.8, sh, 0.8 }, { c[1], sh / 2, c[2] }, P.DarkWood, "Wood", SOLID)
	end
	put(k, "ShedRoof", { sx1 - sx0 + 2, 0.6, sz1 - sz0 + 2 }, { (sx0 + sx1) / 2, sh + 0.3, (sz0 + sz1) / 2 }, H.Roof, "Metal")
	for i, x in { sx0 + (sx1 - sx0) * 0.3, sx0 + (sx1 - sx0) * 0.7 } do
		put(k, "Timber", { (sx1 - sx0) * 0.32, 2.6 + i * 0.6, 7 }, { x, (2.6 + i * 0.6) / 2, (sz0 + sz1) / 2 }, H.Timber, "WoodPlanks")
	end
	-- the pallets of bricks, concrete blocks, roof tiles and cement bags in a row in the yard
	local goods: { { color: { number }, material: string } } = {
		{ color = H.Bricks, material = "Brick" },
		{ color = H.Blocks, material = "Concrete" },
		{ color = H.Tiles, material = "ClayRoofTiles" },
		{ color = H.Bags, material = "SmoothPlastic" },
	}
	local py = zf + 10
	for i, g in goods do
		local x = x0 + 6 + (i - 1) * 9
		put(k, "Pallet", { 5, 0.6, 5 }, { x, 0.3, py }, H.Pallet, "WoodPlanks")
		put(k, "Goods", { 4.4, 3.2, 4.4 }, { x, 0.6 + 1.6, py }, g.color, g.material)
	end
	-- the sand and gravel heaps: two wedges back to back each
	local heaps: { { color: { number }, material: string } } = { { color = H.Sand, material = "Sand" }, { color = H.Gravel, material = "Pebble" } }
	for i, c in heaps do
		local x = sx0 + 4 + (i - 1) * 16
		local z = sz1 + 12
		put(k, "Heap", { 12, 4, 5 }, { x, 2, z + 2.5 }, c.color, c.material, { shape = "Wedge", turn = { 0, 180, 0 } })
		put(k, "Heap", { 12, 4, 5 }, { x, 2, z - 2.5 }, c.color, c.material, { shape = "Wedge" })
	end
	-- the mesh fence round the sides and the back
	local e = 0.4
	fenceRun(k, "YardFence", -w / 2 + e, -d / 2 + e, w / 2 - e, -d / 2 + e, 6, H.Mesh, "Metal")
	for _, s in { -1, 1 } do
		fenceRun(k, "YardFence", s * (w / 2 - e), -d / 2 + e, s * (w / 2 - e), d / 2 - e, 6, H.Mesh, "Metal")
	end
end

-- A landmark's pieces in its frame (VillageLooks.frame(box, yaw); plan.json's rect, Config.Village.Facing's yaw).
-- opts.chapel: the green's chapel's rect on the map (nothing of the green there).
function VillageLooks.landmark(kind: string, box: Box, yaw: number, seed: number, opts: Options?): { Piece }
	local o: Options = opts or {}
	local f = VillageLooks.frame(box, yaw)
	local far = kind == "motorway"
	local k: Kit = { out = {}, chunk = if far then "far" else VillageLooks.chunkOf(f.x, f.z) }
	local roll = dice(seed)
	if kind == "chapel" then
		chapel(k, f, roll)
	elseif kind == "green" then
		green(k, f, roll, o.chapel)
	elseif kind == "pond" then
		pond(k, f, roll)
	elseif kind == "shop" then
		shop(k, f, roll)
	elseif kind == "motorway" then
		motorway(k, f, roll)
	elseif kind == "barrier" then
		barrier(k, f, roll)
	elseif kind == "hardware" then
		hardware(k, f, roll)
	else
		error(`VillageLooks.landmark: no landmark kind "{kind}"`)
	end
	return k.out
end

-- Hornická's barrier: its box (Barrier.Deep deep, Barrier.Inset in from the road's west end, across it) and its yaw.
function VillageLooks.barrierAt(road: Box): (Box, number)
	local B = V.Barrier
	local x0 = road.x0 + B.Inset
	return { x0 = x0, x1 = x0 + B.Deep, z0 = road.z0, z1 = road.z1 }, B.Yaw
end

-- ── The ground ─────────────────────────────────────────────────────────────

-- A field tile on the map: the ground in the crop's colour (its top at the ground's, 2 deep: it is the ground) and its
-- rows along its long side (Fields.Rows apart, at most Fields.MaxRows).
function VillageLooks.field(kind: string, rect: Box, seed: number): { Piece }
	local crop = P.Crops[kind]
	assert(crop, `VillageLooks.field: no crop "{kind}"`)
	local k: Kit = { out = {}, chunk = "ground" }
	local sx, sz = rect.x1 - rect.x0, rect.z1 - rect.z0
	local mx, mz = (rect.x0 + rect.x1) / 2, (rect.z0 + rect.z1) / 2
	put(k, "Field", { sx, 2, sz }, { mx, -1, mz }, crop, if kind == "ploughed" then "Ground" else "Grass", { ground = true, solid = true })
	local longX = sx >= sz
	local across = if longX then sz else sx
	local count = math.min(V.Fields.MaxRows, math.floor(across / V.Fields.Rows) - 1)
	local gap = across / (count + 1)
	for i = 1, count do
		local off = -across / 2 + i * gap
		local size = if longX then { sx - 4, 0.06, 0.9 } else { 0.9, 0.06, sz - 4 }
		put(k, "CropRow", size, if longX then { mx, 0.03, mz + off } else { mx + off, 0.03, mz }, P.Rows[kind], if kind == "ploughed" then "Ground" else "Grass")
	end
	return k.out
end

-- ── The far view ───────────────────────────────────────────────────────────

-- A far house: its body, a gable of two tile wedges (its ridge along X, turned `yaw`).
local function farHouse(k: Kit, x: number, z: number, w: number, d: number, h: number, yaw: number)
	local a = math.rad(yaw)
	local function at(u: number, y: number, v: number): { number }
		return { x + math.cos(a) * u + math.sin(a) * v, y, z - math.sin(a) * u + math.cos(a) * v }
	end
	local rise = d * 0.45
	put(k, "FarHouse", { w, h, d }, at(0, h / 2, 0), P.Far.Wall, "Plaster", { turn = { 0, yaw, 0 } })
	put(k, "FarRoof", { w, rise, d / 2 }, at(0, h + rise / 2, d / 4), P.Far.Roof, "ClayRoofTiles", { shape = "Wedge", turn = { 0, yaw + 180, 0 } })
	put(k, "FarRoof", { w, rise, d / 2 }, at(0, h + rise / 2, -d / 4), P.Far.Roof, "ClayRoofTiles", { shape = "Wedge", turn = { 0, yaw, 0 } })
end

-- The far view round the Bounds (all of it outside them, chunk "far"): the far fields (a patchwork, Far.Reach out),
-- tree lines, a power line on pylons in the north, the D5 going on north and south, the roofs of two far villages
-- and a church tower.
function VillageLooks.horizon(bounds: Box, seed: number): { Piece }
	local roll = dice(seed)
	local k: Kit = { out = {}, chunk = "far" }
	local b, R = bounds, V.Far.Reach
	local crops = { P.Crops.wheat, P.Crops.young, P.Far.Meadow, P.Crops.rapeseed, P.Crops.ploughed }
	local n = 0
	local function tile(x0: number, x1: number, z0: number, z1: number)
		n += 1
		local c = crops[(n - 1) % #crops + 1]
		put(k, "FarField", { x1 - x0, 2, z1 - z0 }, { (x0 + x1) / 2, -1, (z0 + z1) / 2 }, c, if c == P.Crops.ploughed then "Ground" else "Grass", { ground = true, solid = true })
	end
	local wide = (b.x1 - b.x0 + 2 * R) / 4
	for i = 0, 3 do
		tile(b.x0 - R + i * wide, b.x0 - R + (i + 1) * wide, b.z0 - R, b.z0)
		tile(b.x0 - R + i * wide, b.x0 - R + (i + 1) * wide, b.z1, b.z1 + R)
	end
	local mid = (b.z0 + b.z1) / 2
	for _, z in { { b.z0, mid }, { mid, b.z1 } } do
		tile(b.x0 - R, b.x0, z[1], z[2])
		tile(b.x1, b.x1 + R, z[1], z[2])
	end
	-- the D5 going on north and south (its embankment and asphalt, out of the Bounds)
	local d5x, out = 360, 900
	for _, s in { -1, 1 } do
		local z = if s < 0 then b.z0 - out / 2 else b.z1 + out / 2
		put(k, "FarMotorway", { 42, 5, out }, { d5x, 2.5, z }, P.Grass, "Grass")
		put(k, "FarCarriageway", { 34, 0.2, out }, { d5x, 5.1, z }, P.Asphalt, "Asphalt")
	end
	-- tree lines: four big round crowns in a row each (a far copse), round the Bounds 120 to 520 out
	for i = 0, 7 do
		local side = i % 4
		local out2 = lerp(120, 520, roll())
		local t = (math.floor(i / 4) + 0.5 + (roll() - 0.5) * 0.4) / 2
		local along = side % 2 == 0 -- (the north and the south: along x)
		local x = if side == 0 or side == 2 then lerp(b.x0, b.x1, t) elseif side == 1 then b.x1 + out2 else b.x0 - out2
		local z = if side == 1 or side == 3 then lerp(b.z0, b.z1, t) elseif side == 0 then b.z0 - out2 else b.z1 + out2
		if side == 1 and math.abs(x - d5x) < 60 then
			x += 120 -- (off the D5's line)
		end
		for j = -1.5, 1.5 do
			local height = lerp(28, 38, roll())
			local crown = lerp(46, 58, roll())
			local u = j * 40 + (roll() - 0.5) * 8
			put(k, "FarTrees", { crown, height, crown * 0.8 }, { x + (if along then u else 0), height / 2, z + (if along then 0 else u) }, shade(P.Far.Trees, math.floor((roll() - 0.5) * 16)), "Grass", { shape = "Ellipsoid", turn = { 0, if along then 0 else 90, 0 } })
		end
	end
	-- the power line in the north: pylons (two legs, two arms), a wire from each arm's end to the next pylon's
	local pz = b.z0 - 300
	local px0, px1 = b.x0 - 500, b.x1 + 500
	local count = 7
	local span = (px1 - px0) / (count - 1)
	for i = 0, count - 1 do
		local x = px0 + i * span
		for _, s in { -1, 1 } do
			-- (its foot 6.2 out of the line, its top 2: leaning 4° in; its lowest corner on the ground)
			local lean = math.rad(4)
			put(k, "PylonLeg", { 1.2, 60, 1.2 }, { x, 30 * math.cos(lean) + 0.6 * math.sin(lean), pz + s * (2 + 30 * math.sin(lean)) }, P.Far.Pylon, "Metal", { turn = { -s * 4, 0, 0 } })
		end
		put(k, "PylonArm", { 1.2, 1, 26 }, { x, 52, pz }, P.Far.Pylon, "Metal")
		put(k, "PylonArm", { 1.2, 1, 18 }, { x, 42, pz }, P.Far.Pylon, "Metal")
		if i < count - 1 then
			for _, s in { -1, 1 } do
				put(k, "Wire", { span, 0.3, 0.3 }, { x + span / 2, 51.35, pz + s * 12.4 }, P.Far.Wire, "Metal")
			end
		end
	end
	-- far roofs: a village in the south (with its church tower) and one in the west
	for v, c in { { -260, b.z1 + 420, 8 }, { b.x0 - 430, -60, 6 } } do
		for i = 1, c[3] do
			local a = roll() * 2 * math.pi
			local dist = math.sqrt(roll()) * 110
			farHouse(k, c[1] + math.cos(a) * dist, c[2] + math.sin(a) * dist, lerp(14, 20, roll()), lerp(10, 13, roll()), lerp(8, 10, roll()), if roll() < 0.5 then 0 else 90)
		end
		if v == 1 then
			put(k, "FarChurch", { 9, 36, 9 }, { c[1] + 30, 18, c[2] - 30 }, P.Far.Wall, "Plaster")
			pyramid(k, "FarSpire", c[1] + 30, 36, c[2] - 30, 4.8, 14, P.Slate, "Slate")
		end
	end
	return k.out
end

-- ── The census ─────────────────────────────────────────────────────────────

-- The parts VillageLooks gives a step of plan.json's village (each entry of that step or before, as the builder will
-- call it: a house with its id's seed, the ones to empty rich; the terraced rows in their groups; the landmarks
-- Config.Village.Facing knows, the green round its chapel, the barrier on Barrier.Road; the tree lines and the orchard
-- (before the builder's rules drop any); the fields; the far view). tests/villagelooks_test.luau and
-- tools/perf/sandbox_count.py count with it.
function VillageLooks.census(plan: Plan, step: number): Census
	local c: Census = { houses = 0, rows = 0, landmarks = 0, trees = 0, fields = 0, far = 0, total = 0 }
	for _, h in plan.houses do
		if (h.step or 1) <= step and h.kind ~= "row" then
			c.houses += #VillageLooks.house(h.kind, h.box, h.yaw, VillageLooks.seedOf(h.id), { rich = h.enter == true })
		end
	end
	for _, g in VillageLooks.rowGroups(plan.houses) do
		if g.step <= step then
			c.rows += #VillageLooks.house("row", g.box, g.yaw, g.seed, { rich = g.richUnit ~= nil, richUnit = g.richUnit })
		end
	end
	local chapel: Box? = nil
	for _, l in plan.landmarks do
		if l.kind == "chapel" then
			chapel = l.rect
		end
	end
	for _, l in plan.landmarks do
		if l.step <= step and V.Facing[l.kind] then
			c.landmarks += #VillageLooks.landmark(l.kind, l.rect, V.Facing[l.kind], VillageLooks.seedOf(l.id), { chapel = chapel })
		elseif l.step <= step and l.kind == "orchard" then
			c.trees += V.Budget.tree * #VillageLooks.orchard(l.rect, VillageLooks.seedOf(l.id))
		end
	end
	for _, r in plan.roads do
		if r.step <= step and r.name == V.Barrier.Road then
			local box, yaw = VillageLooks.barrierAt(r.rect)
			c.landmarks += #VillageLooks.landmark("barrier", box, yaw, VillageLooks.seedOf(r.name))
		end
	end
	for n, line in plan.lines do
		c.trees += V.Budget.tree * #VillageLooks.lineTrees(line.points, line.kind, n)
	end
	for n, field in plan.fields do
		c.fields += #VillageLooks.field(field.kind, field.rect, n)
	end
	c.far = #VillageLooks.horizon(plan.bounds, 1)
	c.total = c.houses + c.rows + c.landmarks + c.trees + c.fields + c.far
	return c
end

return VillageLooks
