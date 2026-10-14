--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md, "warehouse"): the ZDC warehouse on a player's plot as plain numbers (the pure
-- tests run it outside Roblox; server/Warehouse.luau builds it). The building is SandboxMap's plot.warehouse: 80 × 24
-- × 60 of corrugated metal under a low gable roof (its ridge north-south), its roller door (SandboxMap.DoorWidth wide,
-- kept open) in the middle of the south wall, which looks at the van's spot. Inside: a concrete floor with painted
-- lines, the receiving zone just inside the door, the display stands in rows behind it with aisles between them, the
-- hall's lights under the tie beams and the STOCK board on the back wall. Outside: the ZDC sign in the front gable, the
-- owner's sign over the door and the UNLOAD HERE bay painted round the van at its spot (the unloading itself is the
-- moves' work: the plot's unload circle). 8.0.1: the plot's concrete is at SandboxMap.GroundTop (flush with the
-- meadow; the asphalt's RoadTop is only the roads'): the bay's paint and the bollards stand on it, the hall's floor a
-- hair over it (no step at the door).
-- 8.1 (the upgrades): the hall holds Config.Warehouse.MaxStands stands (20). 1 … Stands (12) are the big grid; the
-- More stands upgrade opens the others two at a time, smaller podiums (Config.Warehouse.SmallStand) where the grid
-- leaves room: 13 – 16 in the front corners beside the receiving zone (the inner pair, then the outer pair; they look
-- north at the front row's aisle), 17 – 20 down the middle aisle from the front (looking south at the door). Until
-- one is bought its spot is painted on the floor ("STAND 13 · 🔒 UPGRADES": the podium covers the paint once it is
-- built). The UPGRADES desk stands at the back wall's middle under the STOCK board: a desk with a monitor (its prompt
-- is server/Warehouse.luau's) and an UPGRADES sign over it.
--
-- 8.3 (design/warehouse-levels/KONTRAKT.md): the warehouse has five levels (Config.Warehouse.Levels, the owner's
-- Blender ones: a Garage, a Workshop, a Storehouse, the Big Warehouse above, a Logistics Center), each its own building
-- on the plot: its front wall where every level's is (the door, the van's spot and the bay never move), going back
-- from it. A Site is a plot at a level (WarehouseLayout.site): its `warehouse` that level's box, its `level`; every
-- function below takes a Plot or a Site, and a plain Plot is level 4 (the building of 8.0 – 8.2). A level has its big
-- stands in a grid of its own (a Garage's 2 against its back wall … the Logistics Center's 24 in four rows), the More
-- stands' small spots from Config.Warehouse.MoreFrom on (level 4's and level 5's), its own door, its roof (the
-- Garage's shed: the front wall H, the back wall rise lower; the Logistics Center's barrel: a gable of rise under it),
-- its lamps and tie beams where the Blender model has its lamps and trusses (the model hides these; their lights
-- shine from just under the model's lamps), its STOCK board and UPGRADES sign where its walls have room (a Garage's
-- board on its west wall, over nothing).
--
-- World coordinates (studs) of one plot. Every warehouse looks south, so its own frame is only moved: x across (east
-- +), z to the door (south +), y up from the ground.
--   WarehouseLayout.FloorTop               the hall floor's top (a hair over the plot's concrete, SandboxMap.GroundTop)
--   WarehouseLayout.Levels                 8.3: how many levels there are (5)
--   WarehouseLayout.site(plot, level?)     8.3: the plot (a Plot or its id) at that level: a copy, its `warehouse` the
--                                          level's box (the front wall where it always is), its `level` (nil or out of
--                                          range: 4); nil for no such plot
--   WarehouseLayout.levelOf(plot)          8.3: a Plot's or a Site's level (a plain Plot: 4)
--   WarehouseLayout.level(n)               8.3: level n's Config entry (Config.Warehouse.Levels; out of range: clamped)
--   WarehouseLayout.grid(n)                8.3: level n's stand grid { columns, middle, aisle, side, front, gap,
--                                          receiving, walk }: the middle aisle's width, the walk between a half's
--                                          columns, the room kept along the side walls, the front row's front edge from
--                                          the front wall's inside, the walk between rows, the receiving zone's depth
--                                          and the least walk in front of a stand (and past the receiving zone)
--   WarehouseLayout.outline(plot)          the building's outer box { x0, x1, z0, z1, top } (top: the ridge's; a shed's
--                                          top is its front wall's)
--   WarehouseLayout.inside(plot)           the floor inside the walls (Rect)
--   WarehouseLayout.door(plot)             the roller door's opening { x, z (the wall's outer face), width, height } (8.3:
--                                          the level's door)
--   WarehouseLayout.receiving(plot)        the receiving zone (Rect): the door's width, Config.Warehouse.Receiving deep
--   WarehouseLayout.doorPath(plot)         the way in that stays clear (Rect): from the van's back through the door and
--                                          the receiving zone to an aisle's width past it
--   WarehouseLayout.count(level?)          how many big stands a warehouse has (Config.Warehouse.Stands; 8.3: the
--                                          level's, nil: level 4's 12)
--   WarehouseLayout.capacity(level?)       8.1: how many the hall holds (Config.Warehouse.MaxStands; the upgrades'; 8.3:
--                                          the level's big ones + the small spots from MoreFrom on: 2 … 20 … 32)
--   WarehouseLayout.stand(plot, i)         stand i's podium: { index, x, z (its middle), y (its top: where a piece
--                                          stands), sx, sz, yaw (the way a piece on it looks: 180, south to its aisle
--                                          and the door; 0 north), small (8.1: an upgrade's smaller podium) } (nil: no
--                                          such stand: 1 … capacity(level)). 1 … columns are the front row (nearest the
--                                          door) west to east, the next row behind them, and so on
--   WarehouseLayout.stands(plot, count?)   the plot's (a Plot or its id) first `count` stands (default: the start's,
--                                          count()), in stand-number order: the spots above (x, y, z plain numbers;
--                                          {} for no such plot)
--   WarehouseLayout.standAt(plot, x, z)    the stand whose podium holds the point (nil: none; any of the hall's)
--   WarehouseLayout.standSize(i, level?)   8.1: stand i's podium (sx, sz), nil for no such stand (the same on every plot;
--                                          8.3: of that level, nil: 4)
--   WarehouseLayout.fits(i, size, level?)  8.1: a piece of that size (its X × Z, a Vector3 or { X, Z }) stands on stand
--                                          i unturned (Fit studs to spare; 8.3: that level's stand i, nil: 4)
--   WarehouseLayout.terminal(plot)         8.1: the UPGRADES desk: { x, z (its middle), y (its top), sx, sz, yaw (the
--                                          way it faces: 180, south into the hall) }: against the back wall's middle on
--                                          every level (8.3: a Garage's a smaller one, between its two stands)
--   WarehouseLayout.bay(plot)              the UNLOAD HERE box in front of the door (Rect): Config.Warehouse.Bay, its
--                                          middle the van's (the plot's vanSpot: the van is centred on it)
--   WarehouseLayout.pieces(plot)           every part of the building as a Piece (below)
--   WarehouseLayout.bounds(piece)          a piece's box in the world, turned: x0, x1, y0, y1, z0, z1
--   WarehouseLayout.ownerLines(name?, id)  the owner's sign: "<Name>'s Warehouse" (nil: FOR RENT) and its small line
--   WarehouseLayout.stockLines(stock, perMinute, shown, stands)   the STOCK board's lines
--   WarehouseLayout.tagLines(name, rarity, perMinute)             a shown piece's tag: its name, "RARE · +$3/min"
--   WarehouseLayout.money(n)               "$1,234" (to a tenth under ten: "$2.5")
--   WarehouseLayout.rarityColor(rarity?)   a rarity's colour (Config.Warehouse.Rarity; unknown: common's)
--
-- A Piece: name (unique in a warehouse), group ("shell", "roof", "door", "inside", "paint", "sign", "stand", "bay",
-- 8.1: "terminal"),
-- at (its middle) and size (x, y, z), yaw / pitch / roll in degrees (its CFrame: CFrame.new(at) * Angles(0, yaw, 0) *
-- Angles(pitch, 0, roll)), color, material (an Enum.Material name), shape ("Wedge" | "Cylinder" | nil: a block), solid
-- (collides and is queried; the rest is decoration), shadow (casts one: the big parts only), transparency, words
-- (SurfaceGui text: face, lines { text, color, size (share of the face's height), font }, back (a panel colour), lit), light
-- (a PointLight: range, brightness, color) and stand (the stand it belongs to). 8.2: visual (only looks: the owner's
-- Blender model ZDCWarehouseArt draws it, so server/WarehouseMesh.luau hides it once imported; a solid one still collides,
-- a lamp's glow still has its light).

local Config = require(script.Parent.Config)
local SandboxMap = require(script.Parent.SandboxMap)

local T = Config.Warehouse

local WarehouseLayout = {}

export type Rect = SandboxMap.Rect
export type Stand = { index: number, x: number, y: number, z: number, sx: number, sz: number, yaw: number, small: boolean? }
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
local PLINTH = 1.4 -- the concrete base course's height
local GROUND = SandboxMap.GroundTop -- the plot's concrete pad (server/SandboxWorld.luau): flush with the meadow
local PAINT_LIFT = 0.01 -- the bay's paint this far over the pad (no flicker)
local FLOOR_TOP = GROUND + 0.05 -- the hall's floor: a hair over the pad (a 0.05 lip at the door, nothing to trip on)
local SMALL_SPOTS = 8 -- 8.1: the upgrade stands' spots the hall has (4 in the front corners, 4 down the middle aisle)
local FIT = 0.2 -- studs a piece keeps from its podium's edges
local DESK = { 6.4, 3.2, 2.8 } -- 8.1: the UPGRADES desk (its top included): across, high, deep
local LEVELS = 5 -- 8.3: Config.Warehouse.Levels
local PLAIN = 4 -- 8.3: a plain Plot's level (SandboxMap's plot.warehouse is its box)
WarehouseLayout.FloorTop = FLOOR_TOP
WarehouseLayout.Wall = WALL
WarehouseLayout.Fit = FIT
WarehouseLayout.Levels = LEVELS

local CLAD = { 188, 194, 200 }
local RIBS = { 160, 167, 175 }
local TRIM = { 42, 45, 50 }
local ORANGE = { 240, 132, 44 }
local CONCRETE = { 168, 166, 158 }
local FLOOR = { 150, 152, 150 }
local ROOF = { 118, 124, 132 }
local STEEL = { 74, 78, 86 }
local WHITE = { 238, 238, 232 }
local GREY = { 176, 180, 186 }
local INK = { 26, 27, 29 }
local PODIUM = { 50, 53, 58 }
local FELT = { 202, 196, 184 }
local PAINT = { 242, 198, 42 }
local GLOW = { 255, 244, 224 }

-- 8.3: each level's hall, fitted to the owner's Blender building (Config.Warehouse.Levels: its size and door). The
-- stands' grid (WarehouseLayout.grid; level 4's from Config, the warehouse of 8.0 – 8.2); `beams` and `lamps` are the
-- model's trusses and (some of) its lamps, in studs from the front wall's outer face (`lamps`: { x, in }); `board` and
-- `sign` the STOCK board and the UPGRADES sign ({ across, high, y (their middle) }, on the back wall's middle; `wall =
-- "west"`: on the west wall, `at` studs in from the front wall's inside); `desk` the UPGRADES desk's size.
type Hall = {
	columns: number,
	middle: number,
	aisle: number,
	side: number,
	front: number,
	gap: number,
	receiving: number,
	walk: number,
	beams: { number },
	lamps: { { number } },
	board: { number },
	boardWall: string?,
	boardAt: number?,
	sign: { number },
	desk: { number },
}
local HALLS: { [number]: Hall } = {
	{ -- Garage (26 × 22): its 2 stands against the back wall, either side of a narrow aisle with the small desk
		columns = 2, middle = 4, aisle = 0, side = 0, front = 10, gap = 0, receiving = 5, walk = 4,
		beams = { 11 }, lamps = { { 0, 11 } },
		board = { 6.4, 2.8, 6.2 }, boardWall = "west", boardAt = 4.2, sign = { 3.8, 1.3, 8.4 }, desk = { 3.6, 3.2, 2.4 },
	},
	{ -- Workshop (40 × 30): 2 × 2 against the side walls and the back wall, the door's width between them
		columns = 2, middle = 18, aisle = 0, side = 0, front = 4, gap = 4, receiving = 3, walk = 4,
		beams = { 10, 20 }, lamps = { { -5, 10 }, { 5, 10 }, { -5, 20 }, { 5, 20 } },
		board = { 14, 3.6, 12.4 }, sign = { 12, 2.4, 9 }, desk = DESK,
	},
	{ -- Storehouse (58 × 42): 4 × 2, the outer columns against the side walls
		columns = 4, middle = 8, aisle = 4, side = 0, front = 9, gap = 5, receiving = 5, walk = 4,
		beams = { 10.5, 21, 31.5 }, lamps = { { -7.25, 10.5 }, { 7.25, 10.5 }, { -21.75, 21 }, { 21.75, 21 }, { -7.25, 31.5 }, { 7.25, 31.5 } },
		board = { 22, 6, 13.5 }, sign = { 12, 2.4, 9 }, desk = DESK,
	},
	{ -- Big Warehouse (80 × 60): the warehouse of 8.0 – 8.2 (its grid from Config)
		columns = T.Columns, middle = T.MiddleAisle, aisle = T.Aisle, side = T.Aisle, front = T.Receiving + T.Aisle, gap = T.Aisle, receiving = T.Receiving, walk = T.Aisle,
		beams = { 11, 22, 33, 44, 55 }, lamps = { { -21.5, 22 }, { 0, 22 }, { 21.5, 22 }, { -21.5, 44 }, { 0, 44 }, { 21.5, 44 } },
		board = { 22, 6, 13.5 }, sign = { 12, 2.4, 9 }, desk = DESK,
	},
	{ -- Logistics Center (104 × 84): 6 × 4
		columns = 6, middle = 18, aisle = 4, side = 4, front = 14, gap = 5, receiving = 9, walk = 4,
		beams = { 10.5, 21, 31.5, 42, 52.5, 63, 73.5 },
		lamps = { { -39, 21 }, { -13, 21 }, { 13, 21 }, { 39, 21 }, { -39, 42 }, { -13, 42 }, { 13, 42 }, { 39, 42 }, { -39, 63 }, { -13, 63 }, { 13, 63 }, { 39, 63 } },
		board = { 22, 6, 13.5 }, sign = { 12, 2.4, 9 }, desk = DESK,
	},
}

local function clampLevel(n: any): number
	if type(n) ~= "number" or n ~= n then
		return PLAIN
	end
	local whole = math.floor(n)
	if whole < 1 or whole > LEVELS then
		return PLAIN
	end
	return whole
end

-- Level n's Config entry (Config.Warehouse.Levels; a level missing there: level 4's numbers of 8.0 – 8.2).
function WarehouseLayout.level(n: number?): Config.WarehouseLevelDef
	local at = clampLevel(n)
	local list = (T :: any).Levels
	local def = if type(list) == "table" then list[at] else nil
	if type(def) == "table" then
		return def
	end
	return { name = "Warehouse", size = { 80, 24, 60 }, door = { SandboxMap.DoorWidth, T.DoorHeight }, roof = "gable", rise = T.Ridge, stands = T.Stands }
end

function WarehouseLayout.levelOf(plot: SandboxMap.Plot): number
	return clampLevel((plot :: any).level)
end

function WarehouseLayout.grid(n: number?): Hall
	return HALLS[clampLevel(n)]
end

function WarehouseLayout.site(plot: SandboxMap.Plot | number, level: number?): SandboxMap.Plot?
	local found: SandboxMap.Plot? = if type(plot) == "number" then SandboxMap.Plots[plot] else plot
	if not found then
		return nil
	end
	local n = clampLevel(level)
	local def = WarehouseLayout.level(n)
	local w = found.warehouse
	local front = w.z + w.sz / 2 -- (the front wall's outer face: every level's)
	local copy: any = table.clone(found)
	copy.warehouse = { x = w.x, y = w.y, z = front - def.size[3] / 2, sx = def.size[1], sy = def.size[2], sz = def.size[3] }
	copy.level = n
	return copy :: SandboxMap.Plot
end

-- The building's middle, half sizes and wall height (a shed's: its front wall's).
local function frame(plot: SandboxMap.Plot): (number, number, number, number, number)
	local w = plot.warehouse
	return w.x, w.z, w.sx / 2, w.sz / 2, w.sy
end

-- The roof over the walls' top (a shed's top is its front wall's: 0).
local function ridgeOf(def: Config.WarehouseLevelDef): number
	return if def.roof == "shed" then 0 else def.rise
end

function WarehouseLayout.outline(plot: SandboxMap.Plot): { x0: number, x1: number, z0: number, z1: number, top: number }
	local x, z, hx, hz, h = frame(plot)
	return { x0 = x - hx, x1 = x + hx, z0 = z - hz, z1 = z + hz, top = h + ridgeOf(WarehouseLayout.level(WarehouseLayout.levelOf(plot))) }
end

function WarehouseLayout.inside(plot: SandboxMap.Plot): Rect
	local x, z, hx, hz = frame(plot)
	return { x0 = x - hx + WALL, x1 = x + hx - WALL, z0 = z - hz + WALL, z1 = z + hz - WALL }
end

function WarehouseLayout.door(plot: SandboxMap.Plot): { x: number, z: number, width: number, height: number }
	local x, z, _, hz = frame(plot)
	local def = WarehouseLayout.level(WarehouseLayout.levelOf(plot))
	return { x = x, z = z + hz, width = def.door[1], height = def.door[2] }
end

function WarehouseLayout.receiving(plot: SandboxMap.Plot): Rect
	local x, z, _, hz = frame(plot)
	local half = WarehouseLayout.door(plot).width / 2
	local back = z + hz - WALL
	return { x0 = x - half, x1 = x + half, z0 = back - WarehouseLayout.grid(WarehouseLayout.levelOf(plot)).receiving, z1 = back }
end

function WarehouseLayout.doorPath(plot: SandboxMap.Plot): Rect
	local r = WarehouseLayout.receiving(plot)
	local d = WarehouseLayout.door(plot)
	return { x0 = r.x0, x1 = r.x1, z0 = r.z0 - WarehouseLayout.grid(WarehouseLayout.levelOf(plot)).walk, z1 = d.z + SandboxMap.VanGap }
end

-- The big stands of a level (8.3: Config.Warehouse.Levels; nil: level 4's, Config.Warehouse.Stands).
function WarehouseLayout.count(level: number?): number
	if level == nil then
		return T.Stands
	end
	local stands = WarehouseLayout.level(level).stands
	return if type(stands) == "number" and stands >= 1 then math.floor(stands) else T.Stands
end

-- The upgrade stands' spots a level has (from Config.Warehouse.MoreFrom on: Config.Warehouse.MaxStands's room over the
-- start's, never more than the hall's SMALL_SPOTS).
local function smallSpots(level: number): number
	local from = (T :: any).MoreFrom
	if type(from) == "number" and level < from then
		return 0
	end
	local most = (T :: any).MaxStands
	if type(most) ~= "number" or most ~= most then
		return 0
	end
	return math.clamp(math.floor(most) - T.Stands, 0, SMALL_SPOTS)
end

-- 8.1: the stands the hall holds (the start's and the upgrades'): Config.Warehouse.MaxStands, never fewer than the
-- start's nor more than the hall has spots for. 8.3: a level's big stands and its small spots.
function WarehouseLayout.capacity(level: number?): number
	local n = clampLevel(level)
	return WarehouseLayout.count(if level == nil then nil else n) + smallSpots(n)
end

-- An upgrade stand's podium: { across, deep } (Config.Warehouse.SmallStand).
local function smallSize(): (number, number)
	local small = (T :: any).SmallStand
	if type(small) == "table" and type(small[1]) == "number" and type(small[2]) == "number" then
		return small[1], small[2]
	end
	return T.StandSize, T.StandSize
end

function WarehouseLayout.stand(plot: SandboxMap.Plot, i: number): Stand?
	local level = WarehouseLayout.levelOf(plot)
	local base = WarehouseLayout.count(level)
	if i ~= math.floor(i) or i < 1 or i > WarehouseLayout.capacity(level) then
		return nil
	end
	local hall = WarehouseLayout.grid(level)
	local x = frame(plot)
	local top = FLOOR_TOP + T.StandHeight
	local front = WarehouseLayout.inside(plot).z1 - hall.front -- the front row's front edge
	if i > base then
		-- 8.1, an upgrade stand: the front corners beside the receiving zone (the inner pair west and east, then the
		-- outer pair; looking north at the front row's aisle), then down the middle aisle from the front (looking south)
		local k = i - base
		local sw, sd = smallSize()
		if k <= 4 then
			local zone = WarehouseLayout.receiving(plot)
			local side = if k % 2 == 1 then -1 else 1
			local out = (k - 1) // 2
			local across = side * ((zone.x1 - zone.x0) / 2 + sw / 2 + out * (sw + T.Aisle))
			return { index = i, x = x + across, y = top, z = (zone.z0 + zone.z1) / 2, sx = sw, sz = sd, yaw = 0, small = true }
		end
		local z = front - sd / 2 - (k - 5) * (sd + T.Aisle)
		return { index = i, x = x, y = top, z = z, sx = sw, sz = sd, yaw = 180, small = true }
	end
	local columns = hall.columns
	local half = columns // 2
	local size = T.StandSize
	local row = (i - 1) // columns
	local column = (i - 1) % columns
	-- out from the middle aisle: the west half's columns from the middle out, the east half's likewise
	local side = if column < half then -1 else 1
	local out = if column < half then half - 1 - column else column - half
	local across = side * (hall.middle / 2 + size / 2 + out * (size + hall.aisle))
	local z = front - size / 2 - row * (size + hall.gap)
	return { index = i, x = x + across, y = top, z = z, sx = size, sz = size, yaw = 180 }
end

-- A plot's (the Plot or its id; 8.3: or a Site) first `count` stands (default: the start's, Config.Warehouse.Stands;
-- 8.3: the level's big ones; at most the hall's), in stand-number order (Collection entries' `stand`); {} for no such
-- plot.
function WarehouseLayout.stands(plot: SandboxMap.Plot | number, count: number?): { Stand }
	local found: SandboxMap.Plot? = if type(plot) == "number" then SandboxMap.Plots[plot] else plot
	local list: { Stand } = {}
	if not found then
		return list
	end
	local level = WarehouseLayout.levelOf(found)
	local most = if type(count) == "number" and count == count then math.clamp(math.floor(count), 0, WarehouseLayout.capacity(level)) else WarehouseLayout.count(level)
	for i = 1, most do
		list[i] = WarehouseLayout.stand(found, i) :: Stand
	end
	return list
end

-- 8.1: stand i's podium (the same on every plot), nil for no such stand. 8.3: that level's (nil: 4).
function WarehouseLayout.standSize(i: number, level: number?): (number?, number?)
	local site = WarehouseLayout.site(1, level)
	local s = if site then WarehouseLayout.stand(site, i) else nil
	if not s then
		return nil, nil
	end
	return s.sx, s.sz
end

-- 8.1: does a piece of `size` (its X across, its Z deep: a Vector3 or a table with X and Z) stand on stand i unturned?
-- 8.3: on that level's stand i (nil: 4).
function WarehouseLayout.fits(i: number, size: any, level: number?): boolean
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

-- 8.1: the UPGRADES desk at the back wall's middle, facing the hall (8.3: the level's desk).
function WarehouseLayout.terminal(plot: SandboxMap.Plot): { x: number, y: number, z: number, sx: number, sz: number, yaw: number }
	local x = frame(plot)
	local inside = WarehouseLayout.inside(plot)
	local desk = WarehouseLayout.grid(WarehouseLayout.levelOf(plot)).desk
	return { x = x, y = FLOOR_TOP + desk[2], z = inside.z0 + desk[3] / 2, sx = desk[1], sz = desk[3], yaw = 180 }
end

function WarehouseLayout.standAt(plot: SandboxMap.Plot, x: number, z: number): number?
	for i = 1, WarehouseLayout.capacity(WarehouseLayout.levelOf(plot)) do
		local s = WarehouseLayout.stand(plot, i)
		if s and math.abs(x - s.x) <= s.sx / 2 and math.abs(z - s.z) <= s.sz / 2 then
			return i
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

-- 8.1: an upgrade stand's painted spot until it is bought.
function WarehouseLayout.spotLines(i: number): { Line }
	return {
		line(`STAND {i}`, PAINT, 0.42, "Black"),
		line("🔒 UPGRADES", PAINT, 0.3, "Bold"),
	}
end

-- 8.1: the UPGRADES desk's monitor.
function WarehouseLayout.terminalLines(): { Line }
	return {
		line("ZDC UPGRADES", ORANGE, 0.36, "Black"),
		line("Warehouse · Stands · Lights · Van", WHITE, 0.2, "Bold"),
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

function WarehouseLayout.pieces(plot: SandboxMap.Plot): { Piece }
	local ox, oz, hx, hz, h = frame(plot)
	local level = WarehouseLayout.levelOf(plot)
	local def = WarehouseLayout.level(level)
	local hall = WarehouseLayout.grid(level)
	local base = WarehouseLayout.count(level)
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
	local doorInfo = WarehouseLayout.door(plot)
	local door, doorHigh = doorInfo.width, doorInfo.height
	local section = hx - door / 2 -- the front wall's width each side of the door
	-- 8.3: the roof. A shed (the Garage) slopes from the front wall (h) down to the back wall (back); a gable (and the
	-- game's own gable under a barrel) rises `ridge` over the walls to its ridge (north-south).
	local shed = def.roof == "shed"
	local ridge = if shed then 0 else def.rise
	local back = if shed then h - def.rise else h -- the back wall's height (and the side walls' at the back)
	local function wallTop(z: number): number -- the side walls' top at z (the building's frame)
		return back + (h - back) * (z + hz) / (2 * hz)
	end

	-- the floor: one slab under the whole building (and its doorway), from the pad up to a hair over it
	look(solid(add("Floor", "inside", { 2 * hx, FLOOR_TOP - GROUND, 2 * hz }, { 0, (GROUND + FLOOR_TOP) / 2, 0 }, FLOOR, "Concrete")))

	-- the walls: the back, the sides, the front each side of the door and the header over it (8.3: a shed's side walls
	-- under their slope: a block to the back wall's height and a wedge over it, its tall side at the front)
	look(solid(add("WallBack", "shell", { 2 * hx, back, WALL }, { 0, back / 2, -hz + WALL / 2 }, CLAD, "Metal"), true))
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "West" else "East"
		look(solid(add("Wall" .. tag, "shell", { WALL, back, 2 * hz - 2 * WALL }, { side * (hx - WALL / 2), back / 2, 0 }, CLAD, "Metal"), true))
		if shed then
			local slope = look(solid(add("WallSlope" .. tag, "shell", { WALL, h - back, 2 * hz }, { side * (hx - WALL / 2), back + (h - back) / 2, 0 }, CLAD, "Metal"), true))
			slope.shape = "Wedge" -- (a wedge's tall side is its +Z: the front, south)
		end
		look(solid(add("WallFront" .. tag, "shell", { section, h, WALL }, { side * (door / 2 + section / 2), h / 2, hz - WALL / 2 }, CLAD, "Metal"), true))
	end
	look(solid(add("Header", "shell", { door, h - doorHigh, WALL }, { 0, doorHigh + (h - doorHigh) / 2, hz - WALL / 2 }, CLAD, "Metal"), true))

	local overhang, thick = 1.2, 0.6
	local deep = 2 * hz + 2
	if shed then
		-- 8.3: the shed's roof: one slab just under the walls' slope (its top on their top: the Blender roof lies on
		-- it), overhanging a stud all round as the model's does, a gutter along its low back edge and its downpipes at
		-- the back corners
		local fall = math.atan((h - back) / (2 * hz))
		local eaves = 1
		local length = math.sqrt(4 * hz * hz + (h - back) * (h - back)) + 2 * eaves
		local roof = look(solid(add("Roof", "roof", { 2 * hx + 2 * eaves, thick, length }, { 0, (h + back) / 2 - math.cos(fall) * thick / 2, math.sin(fall) * thick / 2 }, ROOF, "Metal"), true))
		roof.pitch = -math.deg(fall) -- (its front, +Z, up)
		local eave = back - math.sin(fall) * eaves
		look(add("GutterBack", "roof", { 2 * hx + 2 * eaves, 0.8, 0.8 }, { 0, eave - 0.6, -hz - eaves + 0.3 }, TRIM, "Metal"))
		for _, side in { -1, 1 } do
			local pipe = look(add("Downpipe" .. (if side < 0 then "West" else "East"), "shell", { eave - 0.6, 0.6, 0.6 }, { side * (hx - 1.4), (eave - 0.6) / 2, -hz - 0.5 }, TRIM, "Metal"))
			pipe.shape, pipe.roll = "Cylinder", 90
		end
	else
		-- the gables (two wedges each, their tall side at the ridge) and the roof's two slopes, the ridge's cap
		local slope = math.atan(ridge / hx)
		local length = math.sqrt(hx * hx + ridge * ridge) + overhang
		for _, front in { -1, 1 } do
			local tag = if front > 0 then "Front" else "Back"
			for _, side in { -1, 1 } do
				local wedge = look(solid(add(`Gable{tag}{if side < 0 then "West" else "East"}`, "shell", { WALL, ridge, hx }, { side * hx / 2, h + ridge / 2, front * (hz - WALL / 2) }, CLAD, "Metal"), true))
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
			-- the barge boards along the gables' edges
			for _, front in { -1, 1 } do
				local barge = look(add(`Barge{if front > 0 then "Front" else "Back"}{tag}`, "roof", { length, 0.9, 0.3 }, { cx, cy - 0.15, front * (deep / 2 + 0.15) }, TRIM, "Metal"))
				barge.roll = roof.roll
			end
			-- the gutter under the eave and its downpipe at the front corner
			local eave = h + ridge - math.sin(slope) * (length - overhang / 2) -- (about the walls' top)
			look(add("Gutter" .. tag, "roof", { 0.8, 0.8, deep }, { side * (hx + 0.9), eave - 0.6, 0 }, TRIM, "Metal"))
			local pipe = look(add("Downpipe" .. tag, "shell", { eave - 0.6, 0.6, 0.6 }, { side * (hx + 0.5), (eave - 0.6) / 2, hz - 1.4 }, TRIM, "Metal"))
			pipe.shape, pipe.roll = "Cylinder", 90
		end
		look(add("RidgeCap", "roof", { 2, 0.4, deep }, { 0, h + ridge + thick + 0.15, 0 }, TRIM, "Metal"))
	end

	-- the cladding's ribs (outside, from the base course up to the wall's top; over the door only on the header)
	local function rib(name: string, x: number, z: number, bottom: number, top: number, alongX: boolean)
		local tall = top - bottom
		look(add(name, "shell", if alongX then { 0.5, tall, 0.3 } else { 0.3, tall, 0.5 }, { x, bottom + tall / 2, z }, RIBS, "Metal"))
	end
	local count = math.floor((2 * hx) / RIB)
	for k = 0, count - 1 do
		local x = -hx + RIB / 2 + k * RIB
		rib(`RibBack{k}`, x, -hz - 0.15, PLINTH, back, true)
		if math.abs(x) - 0.25 > door / 2 + 0.7 then
			rib(`RibFront{k}`, x, hz + 0.15, PLINTH, h, true)
		elseif math.abs(x) + 0.25 < door / 2 and h - doorHigh > 1.2 then
			rib(`RibHeader{k}`, x, hz + 0.15, doorHigh + 0.4, h, true)
		end
	end
	local along = math.floor((2 * hz) / RIB)
	for k = 0, along - 1 do
		local z = -hz + RIB / 2 + k * RIB
		local top = math.min(wallTop(z - 0.25), h) -- (under a shed's slope: its lower edge)
		rib(`RibWest{k}`, -hx - 0.15, z, PLINTH, top, false)
		rib(`RibEast{k}`, hx + 0.15, z, PLINTH, top, false)
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
	band("Plinth", PLINTH / 2, PLINTH, 0.4, CONCRETE, "Concrete")
	band("Stripe", 5.6, 0.8, 0.45, ORANGE, "SmoothPlastic")
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local tall = if sz > 0 then h else back
			look(add(`Corner{if sz > 0 then "Front" else "Back"}{if sx < 0 then "West" else "East"}`, "shell", { 1.1, tall, 1.1 }, { sx * hx, tall / 2, sz * hz }, TRIM, "Metal"))
		end
	end

	-- the roller door: rolled up (its bottom slats and bar in the opening's top), its rails, the drum's hood inside
	-- (8.3: under a low header, a lower hood), a bollard each side outside
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "West" else "East"
		look(add("DoorRail" .. tag, "door", { 0.7, doorHigh, 0.6 }, { side * (door / 2 + 0.35), doorHigh / 2, hz + 0.3 }, STEEL, "Metal"))
		local bollard = look(solid(add("Bollard" .. tag, "door", { 3.4, 1, 1 }, { side * (door / 2 + 1.8), GROUND + 1.7, hz + 1.4 }, PAINT, "SmoothPlastic")))
		bollard.shape, bollard.roll = "Cylinder", 90
	end
	look(add("DoorCurtain", "door", { door, 1.6, 0.3 }, { 0, doorHigh - 0.8, hz - WALL / 2 }, ORANGE, "Metal"))
	look(add("DoorBar", "door", { door, 0.3, 0.45 }, { 0, doorHigh - 1.75, hz - WALL / 2 }, INK, "Rubber"))
	local hood = if shed then math.min(2.6, h - doorHigh - 0.4) else 2.6
	look(add("DoorHood", "door", { door + 1.6, hood, 2.6 }, { 0, doorHigh + 0.2 + hood / 2, hz - WALL - 1.3 }, STEEL, "Metal"))

	-- the signs: ZDC in the front gable (8.3: as big as the gable holds; a shed has none), the owner's over the door
	-- (server/Warehouse.luau writes it; under a low header a lower one), STOCK inside
	if not shed then
		local zh = math.min(5, ridge * 0.625)
		local zw = math.min(20, 2 * hx * (1 - (zh + 0.5) / ridge) * 0.95)
		local zdc = look(add("ZdcSign", "sign", { zw, zh, 0.4 }, { 0, h + 0.5 + zh / 2, hz + 0.3 }, TRIM, "SmoothPlastic"))
		zdc.yaw = 180
		zdc.words = { { face = "Front", lit = true, lines = { line("ZDC", ORANGE, 0.6, "Black"), line("ZOMBIE DELIVERY CO.", WHITE, 0.24, "Bold") } } }
	end
	-- (8.3: its bottom clear of the door's frame, 0.4 over the opening, under a low header a lower one)
	local ownerHigh = math.min(3.6, h - doorHigh - 0.8)
	local ownerY = math.max(doorHigh + (h - doorHigh) / 2, doorHigh + 0.4 + ownerHigh / 2)
	local owner = add("OwnerSign", "sign", { math.min(24, door + 4), ownerHigh, 0.4 }, { 0, ownerY, hz + 0.5 }, TRIM, "SmoothPlastic")
	owner.yaw = 180
	owner.words = { { face = "Front", lit = true, lines = WarehouseLayout.ownerLines(nil, plot.id) } }
	local inner = hz - WALL
	local function wallSign(name: string, size: { number }, wall: string?, at: number?): Piece
		if wall == "west" then
			-- (on the west wall's inside, its words to the east; `at` studs in from the front wall's inside)
			local p = add(name, "sign", { size[1], size[2], 0.3 }, { -hx + WALL + 0.15, size[3], inner - (at or 0) }, TRIM, "SmoothPlastic")
			p.yaw = -90
			return p
		end
		local p = add(name, "sign", { size[1], size[2], 0.3 }, { 0, size[3], -hz + WALL + 0.15 }, TRIM, "SmoothPlastic")
		p.yaw = 180 -- (its front into the hall)
		return p
	end
	local board = wallSign("StockBoard", hall.board, hall.boardWall, hall.boardAt)
	board.words = { { face = "Front", lit = true, lines = WarehouseLayout.stockLines(0, 0, 0, base) } }

	-- inside: the tie beams on posts along the side walls (8.3: the Blender model's trusses: `beams`, from the front
	-- wall's outer face), the lamps hung under them (the model's lamps: `lamps`); under a shed at its back wall's height
	local hallTop = back -- (the hall's lowest ceiling: a gable's walls' top, a shed's back wall)
	local beamY = if shed then back - 0.35 else hallTop - 0.6 -- (a shed's beam: the model's wooden one)
	for n, y in hall.beams do
		local z = hz - y
		look(add(`Beam{n}`, "inside", { 2 * hx - 2 * WALL, 0.8, 0.8 }, { 0, beamY, z }, STEEL, "Metal"))
		for _, side in { -1, 1 } do
			local tall = hallTop - 1 - FLOOR_TOP
			look(add(`Post{n}{if side < 0 then "West" else "East"}`, "inside", { 0.8, tall, 0.8 }, { side * (hx - WALL - 0.4), FLOOR_TOP + tall / 2, z }, STEEL, "Metal"))
		end
	end
	-- (the model's lamps hang a stud under the walls' top, a shed's 0.85 under its back wall: the game's glow 0.77
	-- under theirs, its light shining from just under them)
	local glowY = if shed then back - 0.85 - 0.77 else h - 1.77
	for lamps, at in hall.lamps do
		local x, z = at[1], hz - at[2]
		local housing = look(add(`Lamp{lamps}`, "inside", { 0.7, 3.2, 3.2 }, { x, glowY + 0.42, z }, TRIM, "Metal"))
		housing.shape, housing.roll = "Cylinder", 90
		local glow = look(add(`LampGlow{lamps}`, "inside", { 0.14, 2.6, 2.6 }, { x, glowY, z }, GLOW, "Neon")) -- (its light stays)
		glow.shape, glow.roll = "Cylinder", 90
		glow.light = { range = T.Lamp.Range, brightness = T.Lamp.Brightness, color = T.Lamp.Color }
	end

	-- the floor's paint: the receiving zone's box and name, the middle aisle's edges
	local zone = hall.receiving
	local paintY = FLOOR_TOP + 0.02
	add("ReceivingBack", "paint", { door, 0.04, 0.4 }, { 0, paintY, inner - zone + 0.2 }, PAINT, "SmoothPlastic")
	add("ReceivingFront", "paint", { door, 0.04, 0.4 }, { 0, paintY, inner - 0.2 }, PAINT, "SmoothPlastic")
	for _, side in { -1, 1 } do
		add("Receiving" .. (if side < 0 then "West" else "East"), "paint", { 0.4, 0.04, zone }, { side * (door / 2 - 0.2), paintY, inner - zone / 2 }, PAINT, "SmoothPlastic")
		local run = inner - zone - (-inner)
		add("AisleLine" .. (if side < 0 then "West" else "East"), "paint", { 0.3, 0.04, run }, { side * (hall.middle / 2 - 0.5), paintY, -inner + run / 2 }, PAINT, "SmoothPlastic")
	end
	-- (lying flat: its Back face up, its text's top to the north: read from the door)
	local receiving = add("ReceivingText", "paint", { math.min(14, door - 2), math.min(2.6, zone - 0.9), 0.05 }, { 0, FLOOR_TOP + 0.03, inner - zone / 2 }, PAINT, "SmoothPlastic")
	receiving.pitch, receiving.transparency = -90, 1
	receiving.words = { { face = "Back", lines = { line("RECEIVING", PAINT, 0.9, "Black") } } }

	-- the display stands: a dark podium, its felt top and its number plate at the front (to the aisle: south, or north
	-- for the upgrade stands in the front corners). 8.1: an upgrade stand's spot is painted on the floor under it too
	-- (its outline and "STAND 13 · 🔒 UPGRADES", read from its aisle): server/Warehouse.luau shows its podium once it is
	-- bought, and the podium covers the paint.
	for i = 1, WarehouseLayout.capacity(level) do
		local s = WarehouseLayout.stand(plot, i) :: Stand
		local x, z = s.x - ox, s.z - oz
		local podiumHigh = T.StandHeight - 0.1
		local podium = solid(add(`Stand{i}`, "stand", { s.sx, podiumHigh, s.sz }, { x, FLOOR_TOP + podiumHigh / 2, z }, PODIUM, "SmoothPlastic"))
		podium.stand = i
		local top = solid(add(`StandTop{i}`, "stand", { s.sx - 0.6, 0.1, s.sz - 0.6 }, { x, s.y - 0.05, z }, FELT, "Fabric"))
		top.stand = i
		local facing = if s.yaw == 0 then -1 else 1 -- (+z: south)
		local plate = add(`Plate{i}`, "stand", { 1.6, 0.6, 0.1 }, { x, FLOOR_TOP + podiumHigh / 2, z + facing * (s.sz / 2 + 0.05) }, WHITE, "SmoothPlastic")
		plate.yaw, plate.stand = s.yaw, i
		plate.words = { { face = "Front", lines = { line(tostring(i), INK, 0.9, "Black") } } }
		if i > base then
			local edge, y = 0.3, FLOOR_TOP + 0.02
			add(`Spot{i}North`, "paint", { s.sx, 0.04, edge }, { x, y, z - s.sz / 2 + edge / 2 }, PAINT, "SmoothPlastic")
			add(`Spot{i}South`, "paint", { s.sx, 0.04, edge }, { x, y, z + s.sz / 2 - edge / 2 }, PAINT, "SmoothPlastic")
			add(`Spot{i}West`, "paint", { edge, 0.04, s.sz - 2 * edge }, { x - s.sx / 2 + edge / 2, y, z }, PAINT, "SmoothPlastic")
			add(`Spot{i}East`, "paint", { edge, 0.04, s.sz - 2 * edge }, { x + s.sx / 2 - edge / 2, y, z }, PAINT, "SmoothPlastic")
			-- (lying flat like RECEIVING: its Back face up, its words' top away from the aisle it looks at)
			local words = add(`SpotText{i}`, "paint", { s.sx - 1.2, s.sz - 1.2, 0.05 }, { x, FLOOR_TOP + 0.03, z }, PAINT, "SmoothPlastic")
			words.pitch, words.transparency = -90, 1
			words.yaw = if s.yaw == 0 then 180 else 0
			words.words = { { face = "Back", lines = WarehouseLayout.spotLines(i) } }
		end
	end

	-- 8.1: the UPGRADES desk at the back wall's middle (its prompt: server/Warehouse.luau), its monitor facing the
	-- hall, an UPGRADES sign on the wall over it (under the STOCK board; 8.3: the level's desk and sign)
	local desk = WarehouseLayout.terminal(plot)
	local dx, dz = desk.x - ox, desk.z - oz
	local body = desk.y - FLOOR_TOP - 0.2
	solid(add("TerminalDesk", "terminal", { desk.sx - 0.4, body, desk.sz - 0.4 }, { dx, FLOOR_TOP + body / 2, dz - 0.2 }, TRIM, "Metal"), true)
	solid(add("TerminalTop", "terminal", { desk.sx, 0.2, desk.sz }, { dx, desk.y - 0.1, dz }, GREY, "SmoothPlastic"))
	add("TerminalStripe", "terminal", { desk.sx - 0.4, 0.5, 0.06 }, { dx, FLOOR_TOP + body - 0.6, dz - 0.2 + (desk.sz - 0.4) / 2 + 0.03 }, ORANGE, "SmoothPlastic")
	add("TerminalNeck", "terminal", { 0.4, 0.7, 0.3 }, { dx, desk.y + 0.35, dz - 0.5 }, STEEL, "Metal")
	local screen = add("TerminalScreen", "terminal", { math.min(3.8, desk.sx - 0.4), 2.3, 0.3 }, { dx, desk.y + 0.7 + 1.15, dz - 0.35 }, INK, "SmoothPlastic")
	screen.yaw = 180 -- (its front into the hall)
	screen.words = { { face = "Front", lit = true, lines = WarehouseLayout.terminalLines() } }
	local sign = wallSign("UpgradeSign", hall.sign, nil, nil)
	sign.words = { { face = "Front", lit = true, lines = { line("⬆ UPGRADES", ORANGE, 0.62, "Black"), line("WAREHOUSE · STANDS · LIGHTS · VAN · DANNY", WHITE, 0.26, "Bold") } } }

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
