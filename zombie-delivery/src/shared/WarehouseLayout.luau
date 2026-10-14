--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md, "warehouse"): the ZDC warehouse on a player's plot as plain numbers (the pure
-- tests run it outside Roblox; server/Warehouse.luau builds it). 8.3: the building is its level's (Config.WarehouseLevels,
-- shared/WarehouseLevels.luau: the owner's five Blender levels, design/blender-warehouse): 1 the plastered Garage under
-- a shed roof falling to the back, 2 the corrugated Workshop, 3 the Warehouse on its concrete plinth, 4 the Big
-- warehouse (8.0's: 80 × 24 × 60, the ZDC stripe) and 5 the Logistics centre under its barrel roof. Every level's
-- roller door (kept open) is where the plot's door is (SandboxMap's plot.door: the middle of the south wall, which looks
-- at the van's spot); a bigger level grows back (north) and to the sides from it, so the van's bay, the unload circle,
-- the kiosk and the spawn never move. Inside: a concrete floor with painted lines, the receiving zone just inside the
-- door (the door's width), the display stands in rows behind it (or beside it: the Workshop's two columns stand either
-- side of a middle aisle wider than its door) with aisles between them, the hall's lights under the tie beams (where
-- warehouse.py hangs its own: the Blender model's lamps over them), the UPGRADES desk at the back wall's middle under
-- its sign and the STOCK board. Outside: the ZDC sign (the front gable; the garage's plate over its door), the owner's
-- sign over the door (the garage's beside it: its header is the shed roof's), the bollards (from level 3) and the
-- UNLOAD HERE bay painted round the van at its spot (the unloading itself is the moves' work: the plot's unload circle).
-- 8.0.1: the plot's concrete is at SandboxMap.GroundTop (flush with the meadow): the bay's paint and the bollards stand
-- on it, the hall's floor a hair over it (no step at the door).
-- 8.1, the UPGRADES desk: a desk with a monitor (its prompt is server/Warehouse.luau's) and an UPGRADES sign over it.
-- (8.1's small upgrade stands are gone: the levels hold their stands, all of one size a level.)
--
-- World coordinates (studs) of one plot. Every warehouse looks south, so its own frame is only moved: x across (east
-- +), z to the door (south +), y up from the ground. `level` is a warehouse level (1 … WarehouseLevels.Count; nil or junk:
-- WarehouseLevels.Start).
--   WarehouseLayout.FloorTop                    the hall floor's top (a hair over the plot's concrete, SandboxMap.GroundTop)
--   WarehouseLayout.level(level)                the level, checked (1 … Count)
--   WarehouseLayout.box(plot, level)            the building as SandboxMap's plot.warehouse is (its middle on the ground,
--                                               sx, sy (the walls), sz): the level's, its door on the plot's
--   WarehouseLayout.outline(plot, level)        the building's outer box { x0, x1, z0, z1, top } (top: the roof's over the
--                                               door: a gable's ridge, a barrel's crown, a shed's front wall)
--   WarehouseLayout.inside(plot, level)         the floor inside the walls (Rect)
--   WarehouseLayout.door(plot, level)           the roller door's opening { x, z (the wall's outer face), width, height }
--   WarehouseLayout.receiving(plot, level)      the receiving zone (Rect): the door's width, the level's receiving deep
--   WarehouseLayout.doorPath(plot, level)       the way in that stays clear (Rect): from the van's back through the door
--                                               and the receiving zone to an aisle's width past it
--   WarehouseLayout.count(level)                the level's display stands
--   WarehouseLayout.most()                      the most stands a level has (the last's)
--   WarehouseLayout.stand(plot, i, level)       stand i's podium: { index, x, z (its middle), y (its top: where a piece
--                                               stands), sx, sz, yaw (the way a piece on it looks: 180, south to its
--                                               aisle and the door) } (nil: no such stand at that level). 1 … columns
--                                               are the front row (nearest the door) west to east, the next row behind
--                                               them, and so on; a short last row stands in the columns nearest the
--                                               middle aisle
--   WarehouseLayout.stands(plot, level)         the plot's (a Plot or its id) stands at that level, in stand-number order:
--                                               the spots above (x, y, z plain numbers; {} for no such plot)
--   WarehouseLayout.standAt(plot, x, z, level)  the stand whose podium holds the point (nil: none)
--   WarehouseLayout.standSize(i, level)         stand i's podium (sx, sz), nil for no such stand (the same on every plot)
--   WarehouseLayout.fits(i, size, level)        a piece of that size (its X × Z, a Vector3 or { X, Z }) stands on stand
--                                               i unturned (Fit studs to spare)
--   WarehouseLayout.terminal(plot, level)       the UPGRADES desk: { x, z (its middle), y (its top), sx, sz, yaw (the way
--                                               it faces: 180, south into the hall) }
--   WarehouseLayout.headroom(level)             the height over the ground a piece on show and its tag stay under (the
--                                               hall's lamps, beams and roof above it)
--   WarehouseLayout.freeSpot(plot, level, x, z) 8.3: is a player standing at (x, z) caught by that level's walls, a stand
--                                               or the desk (as the warehouse is rebuilt round them)? nil: free; else a
--                                               free spot { x, y, z, yaw } in the receiving zone, looking into the hall
--   WarehouseLayout.bay(plot)                   the UNLOAD HERE box in front of the door (Rect): Config.Warehouse.Bay, its
--                                               middle the van's (the plot's vanSpot: the van is centred on it)
--   WarehouseLayout.pieces(plot, level)         every part of the building as a Piece (below)
--   WarehouseLayout.bounds(piece)               a piece's box in the world, turned: x0, x1, y0, y1, z0, z1
--   WarehouseLayout.ownerLines(name?, id)       the owner's sign: "<Name>'s Warehouse" (nil: FOR RENT) and its small line
--   WarehouseLayout.stockLines(stock, perMinute, shown, stands)   the STOCK board's lines
--   WarehouseLayout.tagLines(name, rarity, perMinute)             a shown piece's tag: its name, "RARE · +$3/min"
--   WarehouseLayout.money(n)                    "$1,234" (to a tenth under ten: "$2.5")
--   WarehouseLayout.rarityColor(rarity?)        a rarity's colour (Config.Warehouse.Rarity; unknown: common's)
--
-- A Piece: name (unique in a warehouse), group ("shell", "roof", "door", "inside", "paint", "sign", "stand", "bay",
-- 8.1: "terminal"), at (its middle) and size (x, y, z), yaw / pitch / roll in degrees (its CFrame: CFrame.new(at) *
-- Angles(0, yaw, 0) * Angles(pitch, 0, roll)), color, material (an Enum.Material name), shape ("Wedge" | "Cylinder" |
-- nil: a block), solid (collides and is queried; the rest is decoration), shadow (casts one: the big parts only),
-- transparency, words (SurfaceGui text: face, lines { text, color, size (share of the face's height), font }, back (a
-- panel colour), lit), light (a PointLight: range, brightness, color) and stand (the stand it belongs to). 8.2: visual
-- (only looks: the owner's Blender model ZDCWarehouseArt draws it, so server/WarehouseMesh.luau hides it once imported;
-- a solid one still collides, a lamp's glow still has its light).

local Config = require(script.Parent.Config)
local SandboxMap = require(script.Parent.SandboxMap)
local WarehouseLevels = require(script.Parent.WarehouseLevels)

local T = Config.Warehouse
local LEVELS = Config.WarehouseLevels.List

local WarehouseLayout = {}

export type Rect = SandboxMap.Rect
export type Stand = { index: number, x: number, y: number, z: number, sx: number, sz: number, yaw: number }
export type Line = { text: string, color: { number }, size: number, font: string? }
export type Words = { face: string, lines: { Line }, back: { number }?, lit: boolean? }
export type Light = { range: number, brightness: number, color: { number } }
export type Piece = {
	name: string,
	group: string,
	at: { number },
	size: { number },
	yaw: number?,
	pitch: number?,
	roll: number?,
	color: { number },
	material: string,
	shape: string?,
	solid: boolean?,
	shadow: boolean?,
	transparency: number?,
	words: { Words }?,
	light: Light?,
	stand: number?,
	visual: boolean?, -- 8.2: only looks (the Blender model draws it; server/WarehouseMesh.luau)
}

local WALL = 1 -- the walls' thickness
local RIB = 2.5 -- the cladding's ribs apart
local GROUND = SandboxMap.GroundTop -- the plot's concrete pad (server/SandboxWorld.luau): flush with the meadow
local PAINT_LIFT = 0.01 -- the bay's paint this far over the pad (no flicker)
local FLOOR_TOP = GROUND + 0.05 -- the hall's floor: a hair over the pad (a 0.05 lip at the door, nothing to trip on)
local FIT = 0.2 -- studs a piece keeps from its podium's edges
local DESK = { 6.4, 3.2, 2.8 } -- 8.1: the UPGRADES desk (its top included): across, high, deep
local BODY = 0.8 -- 8.3: how close a player's middle may be to a wall, a stand or the desk (freeSpot)
local ARC = 5 -- 8.3: a barrel roof's slabs each side
WarehouseLayout.FloorTop = FLOOR_TOP
WarehouseLayout.Wall = WALL
WarehouseLayout.Fit = FIT

local CLAD = { 188, 194, 200 }
local RIBS = { 160, 167, 175 }
local PLASTER = { 216, 212, 204 }
local TRIM = { 42, 45, 50 }
local ORANGE = { 240, 132, 44 }
local CONCRETE = { 168, 166, 158 }
local FLOOR = { 150, 152, 150 }
local ROOF = { 118, 124, 132 }
local STEEL = { 74, 78, 86 }
local WOOD = { 154, 117, 80 }
local WHITE = { 238, 238, 232 }
local GREY = { 176, 180, 186 }
local INK = { 26, 27, 29 }
local PODIUM = { 50, 53, 58 }
local FELT = { 202, 196, 184 }
local PAINT = { 242, 198, 42 }
local GLOW = { 255, 244, 224 }

-- 8.3: each level's looks, mirroring design/blender-warehouse/warehouse.py (depths: studs in from the front wall's
-- outer face; x across from the door's middle):
--   plinth (the base course's height), stripe (the ZDC band), ribs (the corrugated cladding), trusses (the tie beams:
--   warehouse.py's), posts (their posts along the side walls), lamps ({ x, depth }: under warehouse.py's lights; 8.3
--   review, the owner's "flashbang": about one a level 4's floor per lamp, 800 square studs, so a bigger hall is no
--   brighter: the Garage 1, the Workshop 2, the Warehouse 4, the Big warehouse 6, the Logistics centre 12; their
--   brightness and reach are Config's, Config.Warehouse.Lamp),
--   lampTop (a lamp's top: warehouse.py's light's underside), owner / board / sign ({ width, height, x, y } of the
--   owner's sign, the STOCK board, the UPGRADES sign; the last two on the back wall's middle), zdc ({ width, height, y }:
--   the ZDC sign in the front gable, the garage's plate over its door), bollards (warehouse.py's posts by the door)
type Looks = {
	plinth: number,
	stripe: boolean,
	ribs: boolean,
	trusses: { number },
	posts: boolean,
	lamps: { { number } },
	lampTop: number,
	owner: { number },
	board: { number },
	sign: { number },
	zdc: { number },
	bollards: boolean,
}
local LOOKS: { Looks } = {
	{ -- the Garage (its owner's sign beside the door: the shed roof's box comes down over the header)
		plinth = 0.9, stripe = false, ribs = false, trusses = { 11 }, posts = false, lamps = { { 0, 11 } }, lampTop = 8.65,
		owner = { 4.2, 2, 10.1, 5.4 }, board = { 11, 1.7, 0, 8.45 }, sign = { 6.4, 1.1, 0, 6.95 }, zdc = { 6, 1, 10.6 }, bollards = false,
	},
	{ -- the Workshop
		plinth = 0.6, stripe = false, ribs = true, trusses = { 10, 20 }, posts = true, lamps = { { -5, 10 }, { 5, 20 } }, lampTop = 14,
		owner = { 17, 1.9, 0, 13.65 }, board = { 16, 4, 0, 11.2 }, sign = { 10, 2, 0, 7.8 }, zdc = { 8, 2.6, 17 }, bollards = false,
	},
	{ -- the Warehouse
		plinth = 3, stripe = false, ribs = true, trusses = { 10.5, 21, 31.5 }, posts = true,
		lamps = { { -7.25, 10.5 }, { 7.25, 10.5 }, { -7.25, 31.5 }, { 7.25, 31.5 } }, lampTop = 18,
		owner = { 22, 3.2, 0, 16.4 }, board = { 18, 5, 0, 13.7 }, sign = { 12, 2.4, 0, 9 }, zdc = { 11, 4.4, 21.3 }, bollards = true,
	},
	{ -- the Big warehouse (8.0's)
		plinth = 1.4, stripe = true, ribs = true, trusses = { 11, 22, 33, 44, 55 }, posts = true,
		lamps = { { -21.5, 22 }, { 0, 22 }, { 21.5, 22 }, { -21.5, 44 }, { 0, 44 }, { 21.5, 44 } }, lampTop = 23,
		owner = { 24, 3.6, 0, 20 }, board = { 22, 6, 0, 13.5 }, sign = { 12, 2.4, 0, 9 }, zdc = { 20, 5, 27 }, bollards = true,
	},
	{ -- the Logistics centre
		plinth = 1.4, stripe = true, ribs = true, trusses = { 10.5, 21, 31.5, 42, 52.5, 63, 73.5 }, posts = true,
		lamps = { { -39, 21 }, { -13, 21 }, { 13, 21 }, { 39, 21 }, { -39, 42 }, { -13, 42 }, { 13, 42 }, { 39, 42 }, { -39, 63 }, { -13, 63 }, { 13, 63 }, { 39, 63 } },
		lampTop = 27,
		owner = { 24, 3.6, 0, 22.5 }, board = { 26, 7, 0, 15 }, sign = { 14, 2.8, 0, 9.4 }, zdc = { 16, 5, 32.5 }, bollards = true,
	},
}

-- A level without its own looks (one the owner adds to Config): ones made from its size.
local function looksOf(n: number): Looks
	local known = LOOKS[n]
	if known then
		return known
	end
	local def = LEVELS[n]
	local W, H, D = def.size[1], def.size[2], def.size[3]
	local trusses: { number } = {}
	for k = 1, math.max(1, math.floor(D / 11) - 1) do
		table.insert(trusses, k * D / (math.max(1, math.floor(D / 11) - 1) + 1))
	end
	local lampTop = if def.roof == "shed" then H - def.rise - 0.85 else H - 1
	return {
		plinth = 1.4, stripe = def.wall == "twotone", ribs = def.wall ~= "plaster", trusses = trusses, posts = def.roof ~= "shed",
		lamps = { { 0, trusses[1] } }, lampTop = lampTop,
		owner = { math.min(24, def.door[1] - 2), math.min(3.6, H - def.door[2] - 1), 0, def.door[2] + (H - def.door[2]) / 2 },
		board = { math.min(22, W / 3), 4, 0, math.min(lampTop - 3, def.door[2]) }, sign = { 10, 2, 0, DESK[2] + 4.5 },
		zdc = { math.min(20, W / 4), 3, H + def.rise / 3 }, bollards = W >= 58,
	}
end

-- ── The level's building on a plot ───────────────────────────────────────────

function WarehouseLayout.level(level: any): number
	return WarehouseLevels.clamp(if level == nil then WarehouseLevels.Start else level)
end

-- The building's middle (on the ground), half sizes, the front walls' height, the back wall's (a shed's lower) and the
-- level's def.
type Frame = { x: number, z: number, hx: number, hz: number, h: number, back: number, def: Config.WarehouseLevelDef, n: number }
local function frame(plot: SandboxMap.Plot, level: any): Frame
	local n = WarehouseLayout.level(level)
	local def = LEVELS[n]
	local W, H, D = def.size[1], def.size[2], def.size[3]
	return {
		x = plot.door.x,
		z = plot.door.z - D / 2,
		hx = W / 2,
		hz = D / 2,
		h = H,
		back = if def.roof == "shed" then H - def.rise else H,
		def = def,
		n = n,
	}
end

function WarehouseLayout.box(plot: SandboxMap.Plot, level: any): { x: number, y: number, z: number, sx: number, sy: number, sz: number }
	local f = frame(plot, level)
	return { x = f.x, y = 0, z = f.z, sx = 2 * f.hx, sy = f.h, sz = 2 * f.hz }
end

function WarehouseLayout.outline(plot: SandboxMap.Plot, level: any): { x0: number, x1: number, z0: number, z1: number, top: number }
	local f = frame(plot, level)
	return { x0 = f.x - f.hx, x1 = f.x + f.hx, z0 = f.z - f.hz, z1 = f.z + f.hz, top = if f.def.roof == "shed" then f.h else f.h + f.def.rise }
end

function WarehouseLayout.inside(plot: SandboxMap.Plot, level: any): Rect
	local f = frame(plot, level)
	return { x0 = f.x - f.hx + WALL, x1 = f.x + f.hx - WALL, z0 = f.z - f.hz + WALL, z1 = f.z + f.hz - WALL }
end

function WarehouseLayout.door(plot: SandboxMap.Plot, level: any): { x: number, z: number, width: number, height: number }
	local f = frame(plot, level)
	return { x = f.x, z = f.z + f.hz, width = f.def.door[1], height = f.def.door[2] }
end

function WarehouseLayout.receiving(plot: SandboxMap.Plot, level: any): Rect
	local f = frame(plot, level)
	local half = f.def.door[1] / 2
	local back = f.z + f.hz - WALL
	return { x0 = f.x - half, x1 = f.x + half, z0 = back - f.def.receiving, z1 = back }
end

function WarehouseLayout.doorPath(plot: SandboxMap.Plot, level: any): Rect
	local r = WarehouseLayout.receiving(plot, level)
	local d = WarehouseLayout.door(plot, level)
	return { x0 = r.x0, x1 = r.x1, z0 = r.z0 - LEVELS[WarehouseLayout.level(level)].aisle, z1 = d.z + SandboxMap.VanGap }
end

function WarehouseLayout.count(level: any): number
	return WarehouseLevels.stands(WarehouseLayout.level(level))
end

function WarehouseLayout.most(): number
	local most = 0
	for _, def in LEVELS do
		most = math.max(most, def.stands)
	end
	return most
end

function WarehouseLayout.headroom(level: any): number
	local n = WarehouseLayout.level(level)
	local def = LEVELS[n]
	local looks = looksOf(n)
	-- (under the lamps and the tie beams: a shed's beam hangs lower than its lamp's top)
	local beams = if def.roof == "shed" then def.size[2] - def.rise - 0.6 else def.size[2] - 0.6
	return math.min(looks.lampTop, beams) - 0.05
end

function WarehouseLayout.stand(plot: SandboxMap.Plot, i: number, level: any): Stand?
	local n = WarehouseLayout.level(level)
	local def = LEVELS[n]
	if type(i) ~= "number" or i ~= math.floor(i) or i < 1 or i > def.stands then
		return nil
	end
	local columns = def.columns
	local half = columns // 2
	local size = def.stand
	local full = def.stands // columns -- the full rows
	local row = (i - 1) // columns
	local column = (i - 1) % columns
	if row >= full then
		-- the short last row: its k stands in the columns nearest the middle aisle (the odd one west)
		local k = def.stands - full * columns
		column = half - (k + 1) // 2 + (i - 1 - full * columns)
	end
	-- out from the middle aisle: the west half's columns from the middle out, the east half's likewise
	local side = if column < half then -1 else 1
	local out = if column < half then half - 1 - column else column - half
	local across = side * (def.middle / 2 + size / 2 + out * (size + def.aisle))
	local z = plot.door.z - def.front - size / 2 - row * (size + def.aisle)
	return { index = i, x = plot.door.x + across, y = FLOOR_TOP + T.StandHeight, z = z, sx = size, sz = size, yaw = 180 }
end

-- A plot's (the Plot or its id) stands at that level, in stand-number order (Collection entries' `stand`); {} for no
-- such plot.
function WarehouseLayout.stands(plot: SandboxMap.Plot | number, level: any): { Stand }
	local found: SandboxMap.Plot? = if type(plot) == "number" then SandboxMap.Plots[plot] else plot
	local list: { Stand } = {}
	if found then
		for i = 1, WarehouseLayout.count(level) do
			list[i] = WarehouseLayout.stand(found, i, level) :: Stand
		end
	end
	return list
end

-- Stand i's podium at that level (the same on every plot), nil for no such stand.
function WarehouseLayout.standSize(i: number, level: any): (number?, number?)
	local s = WarehouseLayout.stand(SandboxMap.Plots[1], i, level)
	if not s then
		return nil, nil
	end
	return s.sx, s.sz
end

-- Does a piece of `size` (its X across, its Z deep: a Vector3 or a table with X and Z) stand on stand i unturned?
function WarehouseLayout.fits(i: number, size: any, level: any): boolean
	local sx, sz = WarehouseLayout.standSize(i, level)
	if not sx or not sz then
		return false
	end
	local ok, x, z = pcall(function(): (any, any)
		return size.X, size.Z
	end)
	if not ok or type(x) ~= "number" or type(z) ~= "number" then
		return true -- (a piece without a size: nothing to measure)
	end
	return x <= sx - FIT + 1e-9 and z <= sz - FIT + 1e-9
end

-- 8.1: the UPGRADES desk at the back wall's middle, facing the hall.
function WarehouseLayout.terminal(plot: SandboxMap.Plot, level: any): { x: number, y: number, z: number, sx: number, sz: number, yaw: number }
	local inside = WarehouseLayout.inside(plot, level)
	return { x = plot.door.x, y = FLOOR_TOP + DESK[2], z = inside.z0 + DESK[3] / 2, sx = DESK[1], sz = DESK[3], yaw = 180 }
end

function WarehouseLayout.standAt(plot: SandboxMap.Plot, x: number, z: number, level: any): number?
	for i = 1, WarehouseLayout.count(level) do
		local s = WarehouseLayout.stand(plot, i, level)
		if s and math.abs(x - s.x) <= s.sx / 2 and math.abs(z - s.z) <= s.sz / 2 then
			return i
		end
	end
	return nil
end

-- 8.3: what a player standing at (x, z) could be caught in at that level: its walls (the door's opening apart), its
-- stands and its desk (each a footprint Rect).
local function blockers(plot: SandboxMap.Plot, level: any): { Rect }
	local f = frame(plot, level)
	local list: { Rect } = {}
	local x0, x1, z0, z1 = f.x - f.hx, f.x + f.hx, f.z - f.hz, f.z + f.hz
	local half = f.def.door[1] / 2
	table.insert(list, { x0 = x0, x1 = x1, z0 = z0, z1 = z0 + WALL }) -- the back
	table.insert(list, { x0 = x0, x1 = x0 + WALL, z0 = z0, z1 = z1 }) -- the sides
	table.insert(list, { x0 = x1 - WALL, x1 = x1, z0 = z0, z1 = z1 })
	table.insert(list, { x0 = x0, x1 = f.x - half, z0 = z1 - WALL, z1 = z1 }) -- the front each side of the door
	table.insert(list, { x0 = f.x + half, x1 = x1, z0 = z1 - WALL, z1 = z1 })
	for _, s in WarehouseLayout.stands(plot, level) do
		table.insert(list, { x0 = s.x - s.sx / 2, x1 = s.x + s.sx / 2, z0 = s.z - s.sz / 2, z1 = s.z + s.sz / 2 })
	end
	local desk = WarehouseLayout.terminal(plot, level)
	table.insert(list, { x0 = desk.x - desk.sx / 2, x1 = desk.x + desk.sx / 2, z0 = desk.z - desk.sz / 2, z1 = desk.z + desk.sz / 2 })
	return list
end

function WarehouseLayout.freeSpot(plot: SandboxMap.Plot, level: any, x: number, z: number): { x: number, y: number, z: number, yaw: number }?
	for _, r in blockers(plot, level) do
		if x > r.x0 - BODY and x < r.x1 + BODY and z > r.z0 - BODY and z < r.z1 + BODY then
			local zone = WarehouseLayout.receiving(plot, level)
			return { x = (zone.x0 + zone.x1) / 2, y = FLOOR_TOP + 3, z = (zone.z0 + zone.z1) / 2, yaw = 0 }
		end
	end
	return nil
end

function WarehouseLayout.bay(plot: SandboxMap.Plot): Rect
	local v = plot.vanSpot
	local width, length = T.Bay[1], T.Bay[2]
	return { x0 = v.x - width / 2, x1 = v.x + width / 2, z0 = v.z - length / 2, z1 = v.z + length / 2 }
end

-- ── Texts ────────────────────────────────────────────────────────────────────

local function commas(n: number): string
	local digits = tostring(math.floor(n))
	local out = (string.gsub(string.reverse(digits), "(%d%d%d)", "%1,"))
	out = string.reverse(out)
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return out
end

function WarehouseLayout.money(n: number): string
	local amount = math.max(0, n)
	if amount < 10 then
		local tenth = math.floor(amount * 10 + 0.5) / 10
		if tenth == math.floor(tenth) then
			return "$" .. tostring(math.floor(tenth))
		end
		return string.format("$%.1f", tenth)
	end
	return "$" .. commas(math.floor(amount + 0.5))
end

function WarehouseLayout.rarityColor(rarity: string?): { number }
	local key = if rarity then string.lower(rarity) else "common"
	return T.Rarity[key] or T.Rarity.common
end

local function line(text: string, color: { number }, size: number, font: string): Line
	return { text = text, color = color, size = size, font = font }
end

function WarehouseLayout.ownerLines(name: string?, id: number): { Line }
	return {
		if name then line(`{name}'s Warehouse`, WHITE, 0.58, "Black") else line("FOR RENT", ORANGE, 0.58, "Black"),
		line(`ZDC STORAGE · PLOT {id}`, if name then ORANGE else GREY, 0.26, "Bold"),
	}
end

function WarehouseLayout.stockLines(stock: number, perMinute: number, shown: number, stands: number): { Line }
	return {
		line("STOCK", ORANGE, 0.34, "Black"),
		line(`📦 {stock} {if stock == 1 then "piece" else "pieces"} in stock · {WarehouseLayout.money(perMinute)}/min`, WHITE, 0.24, "Bold"),
		line(`{shown} of {stands} stands on show`, GREY, 0.17, "Medium"),
	}
end

-- 8.1: the UPGRADES desk's monitor.
function WarehouseLayout.terminalLines(): { Line }
	return {
		line("ZDC UPGRADES", ORANGE, 0.36, "Black"),
		line("Warehouse · Lights · Van · Danny", WHITE, 0.2, "Bold"),
		line("[E] OPEN", GREY, 0.18, "Medium"),
	}
end

function WarehouseLayout.tagLines(name: string, rarity: string?, perMinute: number): { Line }
	return {
		line(name, WarehouseLayout.rarityColor(rarity), 0.55, "Bold"),
		line(`{string.upper(rarity or "common")} · +{WarehouseLayout.money(perMinute)}/min`, WHITE, 0.4, "Bold"),
	}
end

-- ── Geometry ─────────────────────────────────────────────────────────────────

type Matrix = { number } -- 3 × 3, row by row

local function multiply(a: Matrix, b: Matrix): Matrix
	local out = table.create(9, 0)
	for i = 0, 2 do
		for j = 0, 2 do
			local sum = 0
			for k = 0, 2 do
				sum += a[i * 3 + k + 1] * b[k * 3 + j + 1]
			end
			out[i * 3 + j + 1] = sum
		end
	end
	return out
end

-- The piece's turn as Roblox makes it: Angles(0, yaw, 0) * Angles(pitch, 0, roll) = Ry * Rx * Rz.
local function turn(piece: Piece): Matrix
	local y, x, z = math.rad(piece.yaw or 0), math.rad(piece.pitch or 0), math.rad(piece.roll or 0)
	local ry = { math.cos(y), 0, math.sin(y), 0, 1, 0, -math.sin(y), 0, math.cos(y) }
	local rx = { 1, 0, 0, 0, math.cos(x), -math.sin(x), 0, math.sin(x), math.cos(x) }
	local rz = { math.cos(z), -math.sin(z), 0, math.sin(z), math.cos(z), 0, 0, 0, 1 }
	return multiply(ry, multiply(rx, rz))
end

function WarehouseLayout.bounds(piece: Piece): (number, number, number, number, number, number)
	local r = turn(piece)
	local s, at = piece.size, piece.at
	local half = {}
	for i = 0, 2 do
		half[i + 1] = (math.abs(r[i * 3 + 1]) * s[1] + math.abs(r[i * 3 + 2]) * s[2] + math.abs(r[i * 3 + 3]) * s[3]) / 2
	end
	return at[1] - half[1], at[1] + half[1], at[2] - half[2], at[2] + half[2], at[3] - half[3], at[3] + half[3]
end

-- ── The building ─────────────────────────────────────────────────────────────

function WarehouseLayout.pieces(plot: SandboxMap.Plot, level: any): { Piece }
	local f = frame(plot, level)
	local def, looks = f.def, looksOf(f.n)
	local ox, oz, hx, hz, h, back = f.x, f.z, f.hx, f.hz, f.h, f.back
	local roofKind = def.roof
	local list: { Piece } = {}
	-- one piece, `at` in the building's own frame (its middle on the ground)
	local function add(name: string, group: string, size: { number }, at: { number }, color: { number }, material: string): Piece
		local p: Piece = { name = name, group = group, size = size, at = { ox + at[1], at[2], oz + at[3] }, color = color, material = material }
		table.insert(list, p)
		return p
	end
	local function solid(p: Piece, shadow: boolean?): Piece
		p.solid = true
		p.shadow = shadow == true
		return p
	end
	-- 8.2: only looks (the owner's Blender warehouse draws it: server/WarehouseMesh.luau hides it once imported)
	local function look(p: Piece): Piece
		p.visual = true
		return p
	end
	-- a depth (studs in from the front wall's outer face) as the building's z
	local function depth(d: number): number
		return hz - d
	end
	local door, doorHigh = def.door[1], def.door[2]
	local section = hx - door / 2 -- the front wall's width each side of the door
	local plaster = def.wall == "plaster"
	local clad = if plaster then PLASTER else CLAD
	local cladMaterial = if plaster then "Concrete" else "Metal"

	-- the floor: one slab under the whole building (and its doorway), from the pad up to a hair over it
	look(solid(add("Floor", "inside", { 2 * hx, FLOOR_TOP - GROUND, 2 * hz }, { 0, (GROUND + FLOOR_TOP) / 2, 0 }, FLOOR, "Concrete")))

	-- the walls: the back, the sides, the front each side of the door and the header over it (a shed's back and sides
	-- as high as its back wall: the side gables over them rise to the front)
	look(solid(add("WallBack", "shell", { 2 * hx, back, WALL }, { 0, back / 2, -hz + WALL / 2 }, clad, cladMaterial), true))
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "West" else "East"
		look(solid(add("Wall" .. tag, "shell", { WALL, back, 2 * hz - 2 * WALL }, { side * (hx - WALL / 2), back / 2, 0 }, clad, cladMaterial), true))
		look(solid(add("WallFront" .. tag, "shell", { section, h, WALL }, { side * (door / 2 + section / 2), h / 2, hz - WALL / 2 }, clad, cladMaterial), true))
	end
	look(solid(add("Header", "shell", { door, h - doorHigh, WALL }, { 0, doorHigh + (h - doorHigh) / 2, hz - WALL / 2 }, clad, cladMaterial), true))

	-- the roof
	local thick = 0.6
	local eaves: { { number } } = {} -- the gutters: { x (its side), y (under the eave), along z } (gable roofs)
	if roofKind == "shed" then
		-- one slope from the front wall's top down to the back's; a side gable (a wedge, tall at the front) on each side
		-- wall; the parapet over the front, the cornice under it, the gutter and its downpipes at the back
		local rise = def.rise
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "West" else "East"
			local wedge = look(solid(add("Gable" .. tag, "shell", { WALL, rise, 2 * hz }, { side * (hx - WALL / 2), back + rise / 2, 0 }, clad, cladMaterial), true))
			wedge.shape = "Wedge" -- (its tall side is its +Z: the front, south)
		end
		local slope = math.atan(rise / (2 * hz))
		local run = 2 * hz + 2 -- (a stud over each end)
		local length = run / math.cos(slope)
		local sheet = 0.4 -- (warehouse.py's: the model's roof over the slabs)
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "West" else "East"
			local cx = side * (hx + 1) / 2
			local slab = look(solid(add("Roof" .. tag, "roof", { hx + 1, sheet, length }, { cx, (h + back) / 2 + sheet / 2, 0 }, ROOF, "Metal"), true))
			slab.pitch = -math.deg(slope) -- (its front end up)
		end
		look(add("Parapet", "roof", { 2 * hx + 2.2, 0.7, 0.3 }, { 0, h + 0.4, hz + 1 }, WHITE, "SmoothPlastic"))
		-- a garage's window in its west wall and its side door in the east one (warehouse.py's places)
		look(add("WindowFrame", "shell", { 0.2, 3.9, 4.4 }, { -hx - 0.1, 5.75, depth(11) }, WHITE, "SmoothPlastic"))
		look(add("Window", "shell", { 0.1, 3.5, 4 }, { -hx - 0.25, 5.75, depth(11) }, { 47, 66, 82 }, "Glass"))
		look(add("SideDoorFrame", "shell", { 0.1, 7.25, 3.8 }, { hx + 0.05, 3.775, depth(6.7) }, WHITE, "SmoothPlastic"))
		look(add("SideDoor", "shell", { 0.14, 7.05, 3.4 }, { hx + 0.12, 3.675, depth(6.7) }, GREY, "Metal"))
		look(add("Cornice", "shell", { 2 * hx + 0.4, 0.5, 0.5 }, { 0, h - 0.25, hz + 0.05 }, WHITE, "SmoothPlastic"))
		look(add("GutterBack", "roof", { 2 * hx + 2.2, 0.35, 0.35 }, { 0, back - 0.25, -hz - 1.2 }, TRIM, "Metal"))
		for _, side in { -1, 1 } do
			local pipe = look(add("DownpipeBack" .. (if side < 0 then "West" else "East"), "shell", { back - 0.7, 0.25, 0.25 }, { side * (hx - 0.5), (back - 0.7) / 2 + 0.3, -hz - 0.25 }, TRIM, "Metal"))
			pipe.shape, pipe.roll = "Cylinder", 90
		end
	elseif roofKind == "barrel" then
		-- a vault across the width (an arc through the walls' tops and the crown), its slabs ARC a side; the front and
		-- back gables filled up to it (a block and a wedge under each slab); the parapet round the walls' tops
		local rise = def.rise
		local r = (hx * hx + rise * rise) / (2 * rise)
		local cz = h + rise - r
		local a0 = math.asin(hx / r)
		local points: { { number } } = {}
		for k = 0, 2 * ARC do
			local a = -a0 + 2 * a0 * k / (2 * ARC)
			points[k + 1] = { r * math.sin(a), cz + r * math.cos(a) }
		end
		for k = 1, 2 * ARC do
			local p0, p1 = points[k], points[k + 1]
			local dx, dy = p1[1] - p0[1], p1[2] - p0[2]
			local angle = math.atan2(dy, dx)
			local west = k <= ARC
			local j = if west then k else 2 * ARC + 1 - k -- (1: at the eave, ARC: at the crown)
			local tag = `{if west then "West" else "East"}{j}`
			local mx, my = (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2
			local slab = look(solid(add("Roof" .. tag, "roof", { math.sqrt(dx * dx + dy * dy) + 0.3, thick, 2 * hz + 1.2 }, { mx - math.sin(angle) * thick / 2, my + math.cos(angle) * thick / 2, 0 }, ROOF, "Metal"), true))
			slab.roll = math.deg(angle)
			local low, high = math.min(p0[2], p1[2]), math.max(p0[2], p1[2])
			for _, front in { -1, 1 } do
				local z = front * (hz - WALL / 2)
				local where = if front > 0 then "Front" else "Back"
				if low - h > 0.01 then
					look(solid(add(`GableBlock{where}{tag}`, "shell", { math.abs(dx), low - h, WALL }, { mx, h + (low - h) / 2, z }, clad, cladMaterial)))  -- (no shadow: the vault's slabs cast it; perf)
				end
				local wedge = look(solid(add(`Gable{where}{tag}`, "shell", { WALL, math.max(high - low, 0.01), math.abs(dx) }, { mx, low + (high - low) / 2, z }, clad, cladMaterial)))
				wedge.shape = "Wedge"
				wedge.yaw = if west then 90 else -90 -- (a wedge's tall side is its +Z: turned to the crown)
			end
		end
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "West" else "East"
			look(add("Parapet" .. tag, "roof", { 0.8, 1.2, 2 * hz + 0.8 }, { side * hx, h + 0.6, 0 }, WHITE, "SmoothPlastic"))
		end
		for _, front in { -1, 1 } do
			look(add("Parapet" .. (if front > 0 then "Front" else "Back"), "roof", { 2 * hx + 0.8, 1.2, 0.4 }, { 0, h + 0.6, front * (hz + 0.2) }, WHITE, "SmoothPlastic"))
		end
	else
		-- a gable roof: the gables (two wedges each, their tall side at the ridge), the two slopes, the barge boards, the
		-- ridge's cap
		local ridge = def.rise
		local slope = math.atan(ridge / hx)
		local overhang = 1.2
		local length = math.sqrt(hx * hx + ridge * ridge) + overhang
		local deep = 2 * hz + 2
		for _, front in { -1, 1 } do
			local tag = if front > 0 then "Front" else "Back"
			for _, side in { -1, 1 } do
				local wedge = look(solid(add(`Gable{tag}{if side < 0 then "West" else "East"}`, "shell", { WALL, ridge, hx }, { side * hx / 2, h + ridge / 2, front * (hz - WALL / 2) }, clad, cladMaterial), true))
				wedge.shape = "Wedge"
				wedge.yaw = if side > 0 then -90 else 90 -- (a wedge's tall side is its +Z: turned to the ridge)
			end
		end
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "West" else "East"
			-- the slab's underside on the gables' slope (from the ridge down), its middle half its length down
			local cx = side * (math.cos(slope) * length / 2 + math.sin(slope) * thick / 2)
			local cy = h + ridge - math.sin(slope) * length / 2 + math.cos(slope) * thick / 2
			local roof = look(solid(add("Roof" .. tag, "roof", { length, thick, deep }, { cx, cy, 0 }, ROOF, "Metal"), true))
			roof.roll = -side * math.deg(slope)
			for _, front in { -1, 1 } do
				local barge = look(add(`Barge{if front > 0 then "Front" else "Back"}{tag}`, "roof", { length, 0.9, 0.3 }, { cx, cy - 0.15, front * (deep / 2 + 0.15) }, TRIM, "Metal"))
				barge.roll = roof.roll
			end
			table.insert(eaves, { side, h + ridge - math.sin(slope) * (length - overhang / 2), deep })
		end
		look(add("RidgeCap", "roof", { 2, 0.4, deep }, { 0, h + ridge + thick + 0.15, 0 }, TRIM, "Metal"))
	end
	-- the gutters under a gable roof's eaves and their downpipes at the front corners
	for _, eave in eaves do
		local side, y, deep = eave[1], eave[2], eave[3]
		local tag = if side < 0 then "West" else "East"
		look(add("Gutter" .. tag, "roof", { 0.8, 0.8, deep }, { side * (hx + 0.9), y - 0.6, 0 }, TRIM, "Metal"))
		local pipe = look(add("Downpipe" .. tag, "shell", { y - 0.6, 0.6, 0.6 }, { side * (hx + 0.5), (y - 0.6) / 2, hz - 1.4 }, TRIM, "Metal"))
		pipe.shape, pipe.roll = "Cylinder", 90
	end

	-- the cladding's ribs (outside, from the base course up; over the door only on the header)
	local plinth = looks.plinth
	if looks.ribs then
		local function rib(name: string, x: number, z: number, bottom: number, top: number, alongX: boolean)
			local tall = top - bottom
			look(add(name, "shell", if alongX then { 0.5, tall, 0.3 } else { 0.3, tall, 0.5 }, { x, bottom + tall / 2, z }, RIBS, "Metal"))
		end
		local count = math.floor((2 * hx) / RIB)
		for k = 0, count - 1 do
			local x = -hx + RIB / 2 + k * RIB
			rib(`RibBack{k}`, x, -hz - 0.15, plinth, back, true)
			if math.abs(x) - 0.25 > door / 2 + 0.7 then
				rib(`RibFront{k}`, x, hz + 0.15, plinth, h, true)
			elseif math.abs(x) + 0.25 < door / 2 and h - doorHigh > 1.4 then
				rib(`RibHeader{k}`, x, hz + 0.15, doorHigh + 0.4, h, true)
			end
		end
		local along = math.floor((2 * hz) / RIB)
		for k = 0, along - 1 do
			local z = -hz + RIB / 2 + k * RIB
			rib(`RibWest{k}`, -hx - 0.15, z, plinth, back, false)
			rib(`RibEast{k}`, hx + 0.15, z, plinth, back, false)
		end
	end

	-- the base course, the ZDC stripe and the corners' trims
	local function band(name: string, y: number, tall: number, out: number, color: { number }, material: string)
		look(add(name .. "Back", "shell", { 2 * hx, tall, out }, { 0, y, -hz - out / 2 }, color, material))
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "West" else "East"
			look(add(name .. tag, "shell", { out, tall, 2 * hz }, { side * (hx + out / 2), y, 0 }, color, material))
			look(add(name .. "Front" .. tag, "shell", { section, tall, out }, { side * (door / 2 + section / 2), y, hz + out / 2 }, color, material))
		end
	end
	band("Plinth", plinth / 2, plinth, 0.4, CONCRETE, "Concrete")
	if looks.stripe then
		band("Stripe", 5.6, 0.8, 0.45, ORANGE, "SmoothPlastic")
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local tall = if sz > 0 then h else back
			look(add(`Corner{if sz > 0 then "Front" else "Back"}{if sx < 0 then "West" else "East"}`, "shell", { 1.1, tall, 1.1 }, { sx * hx, tall / 2, sz * hz }, if plaster then WHITE else TRIM, if plaster then "SmoothPlastic" else "Metal"))
		end
	end

	-- the roller door: rolled up (its bottom slats and bar in the opening's top), its rails, the drum's hood inside (a
	-- garage's sectional door lies open under its ceiling instead); from level 3 a bollard each side outside
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "West" else "East"
		look(add("DoorRail" .. tag, "door", { 0.7, doorHigh, 0.6 }, { side * (door / 2 + 0.35), doorHigh / 2, hz + 0.3 }, STEEL, "Metal"))
		if looks.bollards then
			local bollard = look(solid(add("Bollard" .. tag, "door", { 3.4, 1, 1 }, { side * (door / 2 + 1.8), GROUND + 1.7, hz + 1.4 }, PAINT, "SmoothPlastic")))
			bollard.shape, bollard.roll = "Cylinder", 90
		end
	end
	if roofKind == "shed" then
		look(add("DoorPanel", "door", { door - 0.4, 0.25, doorHigh }, { 0, doorHigh + 0.32, hz - WALL - 0.3 - doorHigh / 2 }, GREY, "Metal"))
	else
		look(add("DoorCurtain", "door", { door, 1.6, 0.3 }, { 0, doorHigh - 0.8, hz - WALL / 2 }, ORANGE, "Metal"))
		look(add("DoorBar", "door", { door, 0.3, 0.45 }, { 0, doorHigh - 1.75, hz - WALL / 2 }, INK, "Rubber"))
		look(add("DoorHood", "door", { door + 1.6, 2.6, 2.6 }, { 0, doorHigh + 1.5, hz - WALL - 1.3 }, STEEL, "Metal"))
	end

	-- the signs: ZDC in the front gable (the garage's plate over its door), the owner's over the door (the garage's
	-- beside it; server/Warehouse.luau writes it), STOCK inside on the back wall
	local zdc = looks.zdc
	local zdcSign = look(add("ZdcSign", "sign", { zdc[1], zdc[2], 0.4 }, { 0, zdc[3], hz + 0.3 }, if plaster then ORANGE else TRIM, "SmoothPlastic"))
	zdcSign.yaw = 180
	zdcSign.words = { { face = "Front", lit = true, lines = if zdc[2] < 2 then { line("ZDC", WHITE, 0.8, "Black") } else { line("ZDC", ORANGE, 0.6, "Black"), line("ZOMBIE DELIVERY CO.", WHITE, 0.24, "Bold") } } }
	local o = looks.owner
	local owner = add("OwnerSign", "sign", { o[1], o[2], 0.4 }, { o[3], o[4], hz + 0.5 }, TRIM, "SmoothPlastic")
	owner.yaw = 180
	owner.words = { { face = "Front", lit = true, lines = WarehouseLayout.ownerLines(nil, plot.id) } }
	local b = looks.board
	local board = add("StockBoard", "sign", { b[1], b[2], 0.3 }, { b[3], b[4], -hz + WALL + 0.15 }, TRIM, "SmoothPlastic")
	board.yaw = 180 -- (its front into the hall)
	board.words = { { face = "Front", lit = true, lines = WarehouseLayout.stockLines(0, 0, 0, def.stands) } }

	-- inside: the tie beams (on posts along the side walls), the lamps hung under them (warehouse.py's places)
	for n, d in looks.trusses do
		local z = depth(d)
		if roofKind == "shed" then
			look(add(`Beam{n}`, "inside", { 2 * hx - 2 * WALL, 0.5, 0.6 }, { 0, back - 0.35, z }, WOOD, "Wood"))
		else
			look(add(`Beam{n}`, "inside", { 2 * hx - 2 * WALL, 0.8, 0.8 }, { 0, h - 0.6, z }, STEEL, "Metal"))
		end
		if looks.posts then
			for _, side in { -1, 1 } do
				local tall = h - 1 - FLOOR_TOP
				look(add(`Post{n}{if side < 0 then "West" else "East"}`, "inside", { 0.8, tall, 0.8 }, { side * (hx - WALL - 0.4), FLOOR_TOP + tall / 2, z }, STEEL, "Metal"))
			end
		end
	end
	local wide = if roofKind == "shed" then 2.2 else 3.2 -- (a lamp's housing across)
	for k, spot in looks.lamps do
		local housing = look(add(`Lamp{k}`, "inside", { 0.7, wide, wide }, { spot[1], looks.lampTop - 0.35, depth(spot[2]) }, TRIM, "Metal"))
		housing.shape, housing.roll = "Cylinder", 90
		local glow = look(add(`LampGlow{k}`, "inside", { 0.14, wide - 0.6, wide - 0.6 }, { spot[1], looks.lampTop - 0.77, depth(spot[2]) }, GLOW, "Neon")) -- (its light stays)
		glow.shape, glow.roll = "Cylinder", 90
		glow.light = { range = T.Lamp.Range, brightness = T.Lamp.Brightness, color = T.Lamp.Color }
	end

	-- the floor's paint: the receiving zone's box and name, the middle aisle's edges
	local inner = hz - WALL
	local zone = def.receiving
	local paintY = FLOOR_TOP + 0.02
	add("ReceivingBack", "paint", { door, 0.04, 0.4 }, { 0, paintY, inner - zone + 0.2 }, PAINT, "SmoothPlastic")
	add("ReceivingFront", "paint", { door, 0.04, 0.4 }, { 0, paintY, inner - 0.2 }, PAINT, "SmoothPlastic")
	for _, side in { -1, 1 } do
		add("Receiving" .. (if side < 0 then "West" else "East"), "paint", { 0.4, 0.04, zone }, { side * (door / 2 - 0.2), paintY, inner - zone / 2 }, PAINT, "SmoothPlastic")
		local run = inner - zone - (-inner)
		add("AisleLine" .. (if side < 0 then "West" else "East"), "paint", { 0.3, 0.04, run }, { side * (def.middle / 2 - 0.5), paintY, -inner + run / 2 }, PAINT, "SmoothPlastic")
	end
	-- (lying flat: its Back face up, its text's top to the north: read from the door)
	local receiving = add("ReceivingText", "paint", { math.min(14, door - 2), math.min(2.6, zone - 1.2), 0.05 }, { 0, FLOOR_TOP + 0.03, inner - zone / 2 }, PAINT, "SmoothPlastic")
	receiving.pitch, receiving.transparency = -90, 1
	receiving.words = { { face = "Back", lines = { line("RECEIVING", PAINT, 0.9, "Black") } } }

	-- the display stands: a dark podium, its felt top and its number plate at the front (to the aisle: south)
	for i = 1, def.stands do
		local s = WarehouseLayout.stand(plot, i, f.n) :: Stand
		local x, z = s.x - ox, s.z - oz
		local base = T.StandHeight - 0.1
		local podium = solid(add(`Stand{i}`, "stand", { s.sx, base, s.sz }, { x, FLOOR_TOP + base / 2, z }, PODIUM, "SmoothPlastic"))
		podium.stand = i
		local top = solid(add(`StandTop{i}`, "stand", { s.sx - 0.6, 0.1, s.sz - 0.6 }, { x, s.y - 0.05, z }, FELT, "Fabric"))
		top.stand = i
		local plate = add(`Plate{i}`, "stand", { 1.6, 0.6, 0.1 }, { x, FLOOR_TOP + base / 2, z + s.sz / 2 + 0.05 }, WHITE, "SmoothPlastic")
		plate.yaw, plate.stand = s.yaw, i
		plate.words = { { face = "Front", lines = { line(tostring(i), INK, 0.9, "Black") } } }
	end

	-- 8.1: the UPGRADES desk at the back wall's middle (its prompt: server/Warehouse.luau), its monitor facing the
	-- hall, an UPGRADES sign on the wall over it (under the STOCK board)
	local desk = WarehouseLayout.terminal(plot, f.n)
	local dx, dz = desk.x - ox, desk.z - oz
	local body = DESK[2] - 0.2
	solid(add("TerminalDesk", "terminal", { desk.sx - 0.4, body, desk.sz - 0.4 }, { dx, FLOOR_TOP + body / 2, dz - 0.2 }, TRIM, "Metal"), true)
	solid(add("TerminalTop", "terminal", { desk.sx, 0.2, desk.sz }, { dx, desk.y - 0.1, dz }, GREY, "SmoothPlastic"))
	add("TerminalStripe", "terminal", { desk.sx - 0.4, 0.5, 0.06 }, { dx, FLOOR_TOP + body - 0.6, dz - 0.2 + (desk.sz - 0.4) / 2 + 0.03 }, ORANGE, "SmoothPlastic")
	add("TerminalNeck", "terminal", { 0.4, 0.7, 0.3 }, { dx, desk.y + 0.35, dz - 0.5 }, STEEL, "Metal")
	local screen = add("TerminalScreen", "terminal", { 3.8, 2.3, 0.3 }, { dx, desk.y + 0.7 + 1.15, dz - 0.35 }, INK, "SmoothPlastic")
	screen.yaw = 180 -- (its front into the hall)
	screen.words = { { face = "Front", lit = true, lines = WarehouseLayout.terminalLines() } }
	local g = looks.sign
	local sign = add("UpgradeSign", "sign", { g[1], g[2], 0.3 }, { g[3], g[4], -hz + WALL + 0.15 }, TRIM, "SmoothPlastic")
	sign.yaw = 180
	sign.words = { { face = "Front", lit = true, lines = { line("⬆ UPGRADES", ORANGE, 0.62, "Black"), line("BIGGER WAREHOUSE · LIGHTS · VAN · DANNY", WHITE, 0.26, "Bold") } } }

	-- outside: the UNLOAD HERE bay round the van at its spot, its back to the door (the words in the room between the
	-- van's back and the bay's door end: seen with the van parked)
	local bay = WarehouseLayout.bay(plot)
	local bw, bl = bay.x1 - bay.x0, bay.z1 - bay.z0
	local bx, bz = (bay.x0 + bay.x1) / 2 - ox, (bay.z0 + bay.z1) / 2 - oz
	local bayY = GROUND + PAINT_LIFT + 0.03 -- (the lines 0.06 thick: their underside a hair over the pad)
	for _, side in { -1, 1 } do
		add("Bay" .. (if side < 0 then "West" else "East"), "bay", { 0.5, 0.06, bl }, { bx + side * (bw / 2 - 0.25), bayY, bz }, PAINT, "SmoothPlastic")
	end
	add("BayNorth", "bay", { bw, 0.06, 0.5 }, { bx, bayY, bay.z0 - oz + 0.25 }, PAINT, "SmoothPlastic")
	add("BaySouth", "bay", { bw, 0.06, 0.5 }, { bx, bayY, bay.z1 - oz - 0.25 }, PAINT, "SmoothPlastic")
	-- (the words between the north line and the parked van's back: Config.Sprinter.Length long, centred on vanSpot)
	local from, vanBack = bay.z0 + 0.5, plot.vanSpot.z - Config.Sprinter.Length / 2
	local words = math.clamp(vanBack - from - 0.4, 0.5, 3) -- (how deep the words are)
	local unload = add("BayText", "bay", { bw - 3, words, 0.05 }, { bx, bayY + 0.01, (from + vanBack) / 2 - oz }, PAINT, "SmoothPlastic")
	unload.pitch, unload.transparency = -90, 1
	unload.words = { { face = "Back", lines = { line("UNLOAD HERE", PAINT, 0.9, "Black") } } }

	return list
end

return WarehouseLayout
