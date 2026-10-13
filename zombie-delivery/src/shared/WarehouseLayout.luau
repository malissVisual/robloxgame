--!strict
-- 8.0 SANDBOX (design/sandbox/KONTRAKT.md, "warehouse"): the ZDC warehouse on a player's plot as plain numbers (the pure
-- tests run it outside Roblox; server/Warehouse.luau builds it). The building is SandboxMap's plot.warehouse: 80 × 24
-- × 60 of corrugated metal under a low gable roof (its ridge north-south), its roller door (SandboxMap.DoorWidth wide,
-- kept open) in the middle of the south wall, which looks at the van's spot. Inside: a concrete floor with painted
-- lines, the receiving zone just inside the door, the display stands in rows behind it with aisles between them, the
-- hall's lights under the tie beams and the STOCK board on the back wall. Outside: the ZDC sign in the front gable, the
-- owner's sign over the door and the UNLOAD HERE bay painted where the van parks (the unloading itself is the moves'
-- work: the plot's unload circle).
--
-- World coordinates (studs) of one plot. Every warehouse looks south, so its own frame is only moved: x across (east
-- +), z to the door (south +), y up from the ground.
--   WarehouseLayout.FloorTop               the hall floor's top (a hair over the plot's concrete, SandboxMap.RoadTop)
--   WarehouseLayout.outline(plot)          the building's outer box { x0, x1, z0, z1, top } (top: the ridge's)
--   WarehouseLayout.inside(plot)           the floor inside the walls (Rect)
--   WarehouseLayout.door(plot)             the roller door's opening { x, z (the wall's outer face), width, height }
--   WarehouseLayout.receiving(plot)        the receiving zone (Rect): the door's width, Config.Warehouse.Receiving deep
--   WarehouseLayout.doorPath(plot)         the way in that stays clear (Rect): from the van's back through the door and
--                                          the receiving zone to an aisle's width past it
--   WarehouseLayout.count()                how many stands (Config.Warehouse.Stands)
--   WarehouseLayout.stand(plot, i)         stand i's podium: { index, x, z (its middle), y (its top: where a piece
--                                          stands), sx, sz, yaw (the way a piece on it looks: 180, south to its aisle
--                                          and the door) } (nil: no such stand). 1 … Columns are the front row (nearest
--                                          the door) west to east, the next row behind them, and so on
--   WarehouseLayout.stands(plot)           every stand of the plot (a Plot or its id), in stand-number order: the
--                                          spots above (x, y, z plain numbers; {} for no such plot)
--   WarehouseLayout.standAt(plot, x, z)    the stand whose podium holds the point (nil: none)
--   WarehouseLayout.bay(plot)              the UNLOAD HERE box in front of the door (Rect)
--   WarehouseLayout.pieces(plot)           every part of the building as a Piece (below)
--   WarehouseLayout.bounds(piece)          a piece's box in the world, turned: x0, x1, y0, y1, z0, z1
--   WarehouseLayout.ownerLines(name?, id)  the owner's sign: "<Name>'s Warehouse" (nil: FOR RENT) and its small line
--   WarehouseLayout.stockLines(stock, perMinute, shown, stands)   the STOCK board's lines
--   WarehouseLayout.tagLines(name, rarity, perMinute)             a shown piece's tag: its name, "RARE · +$3/min"
--   WarehouseLayout.money(n)               "$1,234" (to a tenth under ten: "$2.5")
--   WarehouseLayout.rarityColor(rarity?)   a rarity's colour (Config.Warehouse.Rarity; unknown: common's)
--
-- A Piece: name (unique in a warehouse), group ("shell", "roof", "door", "inside", "paint", "sign", "stand", "bay"),
-- at (its middle) and size (x, y, z), yaw / pitch / roll in degrees (its CFrame: CFrame.new(at) * Angles(0, yaw, 0) *
-- Angles(pitch, 0, roll)), color, material (an Enum.Material name), shape ("Wedge" | "Cylinder" | nil: a block), solid
-- (collides and is queried; the rest is decoration), shadow (casts one: the big parts only), transparency, words
-- (SurfaceGui text: face, lines { text, color, size (share of the face's height), font }, back (a panel colour), lit), light
-- (a PointLight: range, brightness, color) and stand (the stand it belongs to).

local Config = require(script.Parent.Config)
local SandboxMap = require(script.Parent.SandboxMap)

local T = Config.Warehouse

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
}

local WALL = 1 -- the walls' thickness
local RIB = 2.5 -- the cladding's ribs apart
local PLINTH = 1.4 -- the concrete base course's height
local FLOOR_TOP = SandboxMap.RoadTop + 0.1
WarehouseLayout.FloorTop = FLOOR_TOP
WarehouseLayout.Wall = WALL

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

-- The building's middle, half sizes and wall height.
local function frame(plot: SandboxMap.Plot): (number, number, number, number, number)
	local w = plot.warehouse
	return w.x, w.z, w.sx / 2, w.sz / 2, w.sy
end

function WarehouseLayout.outline(plot: SandboxMap.Plot): { x0: number, x1: number, z0: number, z1: number, top: number }
	local x, z, hx, hz, h = frame(plot)
	return { x0 = x - hx, x1 = x + hx, z0 = z - hz, z1 = z + hz, top = h + T.Ridge }
end

function WarehouseLayout.inside(plot: SandboxMap.Plot): Rect
	local x, z, hx, hz = frame(plot)
	return { x0 = x - hx + WALL, x1 = x + hx - WALL, z0 = z - hz + WALL, z1 = z + hz - WALL }
end

function WarehouseLayout.door(plot: SandboxMap.Plot): { x: number, z: number, width: number, height: number }
	local x, z, _, hz = frame(plot)
	return { x = x, z = z + hz, width = SandboxMap.DoorWidth, height = T.DoorHeight }
end

function WarehouseLayout.receiving(plot: SandboxMap.Plot): Rect
	local x, z, _, hz = frame(plot)
	local half = SandboxMap.DoorWidth / 2
	local back = z + hz - WALL
	return { x0 = x - half, x1 = x + half, z0 = back - T.Receiving, z1 = back }
end

function WarehouseLayout.doorPath(plot: SandboxMap.Plot): Rect
	local r = WarehouseLayout.receiving(plot)
	local d = WarehouseLayout.door(plot)
	return { x0 = r.x0, x1 = r.x1, z0 = r.z0 - T.Aisle, z1 = d.z + SandboxMap.VanGap }
end

function WarehouseLayout.count(): number
	return T.Stands
end

function WarehouseLayout.stand(plot: SandboxMap.Plot, i: number): Stand?
	if i ~= math.floor(i) or i < 1 or i > T.Stands then
		return nil
	end
	local x = frame(plot)
	local columns = T.Columns
	local half = columns // 2
	local size = T.StandSize
	local row = (i - 1) // columns
	local column = (i - 1) % columns
	-- out from the middle aisle: the west half's columns from the middle out, the east half's likewise
	local side = if column < half then -1 else 1
	local out = if column < half then half - 1 - column else column - half
	local across = side * (T.MiddleAisle / 2 + size / 2 + out * (size + T.Aisle))
	local front = WarehouseLayout.receiving(plot).z0 - T.Aisle -- the front row's front edge: an aisle behind the zone
	local z = front - size / 2 - row * (size + T.Aisle)
	return { index = i, x = x + across, y = FLOOR_TOP + T.StandHeight, z = z, sx = size, sz = size, yaw = 180 }
end

-- Every stand of a plot (the Plot or its id), in stand-number order (Collection entries' `stand`); {} for no such plot.
function WarehouseLayout.stands(plot: SandboxMap.Plot | number): { Stand }
	local found: SandboxMap.Plot? = if type(plot) == "number" then SandboxMap.Plots[plot] else plot
	local list: { Stand } = {}
	if found then
		for i = 1, T.Stands do
			list[i] = WarehouseLayout.stand(found, i) :: Stand
		end
	end
	return list
end

function WarehouseLayout.standAt(plot: SandboxMap.Plot, x: number, z: number): number?
	for i = 1, T.Stands do
		local s = WarehouseLayout.stand(plot, i)
		if s and math.abs(x - s.x) <= s.sx / 2 and math.abs(z - s.z) <= s.sz / 2 then
			return i
		end
	end
	return nil
end

function WarehouseLayout.bay(plot: SandboxMap.Plot): Rect
	local d = WarehouseLayout.door(plot)
	local width, length = T.Bay[1], T.Bay[2]
	return { x0 = d.x - width / 2, x1 = d.x + width / 2, z0 = d.z + 1.5, z1 = d.z + 1.5 + length }
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
	local door, doorHigh = SandboxMap.DoorWidth, T.DoorHeight
	local section = hx - door / 2 -- the front wall's width each side of the door
	local ridge = T.Ridge

	-- the floor: one slab under the whole building (and its doorway)
	solid(add("Floor", "inside", { 2 * hx, FLOOR_TOP, 2 * hz }, { 0, FLOOR_TOP / 2, 0 }, FLOOR, "Concrete"))

	-- the walls: the back, the sides, the front each side of the door and the header over it
	solid(add("WallBack", "shell", { 2 * hx, h, WALL }, { 0, h / 2, -hz + WALL / 2 }, CLAD, "Metal"), true)
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "West" else "East"
		solid(add("Wall" .. tag, "shell", { WALL, h, 2 * hz - 2 * WALL }, { side * (hx - WALL / 2), h / 2, 0 }, CLAD, "Metal"), true)
		solid(add("WallFront" .. tag, "shell", { section, h, WALL }, { side * (door / 2 + section / 2), h / 2, hz - WALL / 2 }, CLAD, "Metal"), true)
	end
	solid(add("Header", "shell", { door, h - doorHigh, WALL }, { 0, doorHigh + (h - doorHigh) / 2, hz - WALL / 2 }, CLAD, "Metal"), true)

	-- the gables (two wedges each, their tall side at the ridge) and the roof's two slopes, the ridge's cap
	local slope = math.atan(ridge / hx)
	local overhang, thick = 1.2, 0.6
	local length = math.sqrt(hx * hx + ridge * ridge) + overhang
	local deep = 2 * hz + 2
	for _, front in { -1, 1 } do
		local tag = if front > 0 then "Front" else "Back"
		for _, side in { -1, 1 } do
			local wedge = solid(add(`Gable{tag}{if side < 0 then "West" else "East"}`, "shell", { WALL, ridge, hx }, { side * hx / 2, h + ridge / 2, front * (hz - WALL / 2) }, CLAD, "Metal"), true)
			wedge.shape = "Wedge"
			wedge.yaw = if side > 0 then -90 else 90 -- (a wedge's tall side is its +Z: turned to the ridge)
		end
	end
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "West" else "East"
		-- the slab's underside on the gables' slope (from the ridge down), its middle half its length down
		local cx = side * (math.cos(slope) * length / 2 + math.sin(slope) * thick / 2)
		local cy = h + ridge - math.sin(slope) * length / 2 + math.cos(slope) * thick / 2
		local roof = solid(add("Roof" .. tag, "roof", { length, thick, deep }, { cx, cy, 0 }, ROOF, "Metal"), true)
		roof.roll = -side * math.deg(slope)
		-- the barge boards along the gables' edges
		for _, front in { -1, 1 } do
			local barge = add(`Barge{if front > 0 then "Front" else "Back"}{tag}`, "roof", { length, 0.9, 0.3 }, { cx, cy - 0.15, front * (deep / 2 + 0.15) }, TRIM, "Metal")
			barge.roll = roof.roll
		end
		-- the gutter under the eave and its downpipe at the front corner
		local eave = h + ridge - math.sin(slope) * (length - overhang / 2) -- (about the walls' top)
		add("Gutter" .. tag, "roof", { 0.8, 0.8, deep }, { side * (hx + 0.9), eave - 0.6, 0 }, TRIM, "Metal")
		local pipe = add("Downpipe" .. tag, "shell", { eave - 0.6, 0.6, 0.6 }, { side * (hx + 0.5), (eave - 0.6) / 2, hz - 1.4 }, TRIM, "Metal")
		pipe.shape, pipe.roll = "Cylinder", 90
	end
	add("RidgeCap", "roof", { 2, 0.4, deep }, { 0, h + ridge + thick + 0.15, 0 }, TRIM, "Metal")

	-- the cladding's ribs (outside, from the base course up; over the door only on the header)
	local function rib(name: string, x: number, z: number, bottom: number, alongX: boolean)
		local tall = h - bottom
		add(name, "shell", if alongX then { 0.5, tall, 0.3 } else { 0.3, tall, 0.5 }, { x, bottom + tall / 2, z }, RIBS, "Metal")
	end
	local count = math.floor((2 * hx) / RIB)
	for k = 0, count - 1 do
		local x = -hx + RIB / 2 + k * RIB
		rib(`RibBack{k}`, x, -hz - 0.15, PLINTH, true)
		if math.abs(x) - 0.25 > door / 2 + 0.7 then
			rib(`RibFront{k}`, x, hz + 0.15, PLINTH, true)
		elseif math.abs(x) + 0.25 < door / 2 then
			rib(`RibHeader{k}`, x, hz + 0.15, doorHigh + 0.4, true)
		end
	end
	local along = math.floor((2 * hz) / RIB)
	for k = 0, along - 1 do
		local z = -hz + RIB / 2 + k * RIB
		rib(`RibWest{k}`, -hx - 0.15, z, PLINTH, false)
		rib(`RibEast{k}`, hx + 0.15, z, PLINTH, false)
	end

	-- the base course, the ZDC stripe and the corners' trims
	local function band(name: string, y: number, tall: number, out: number, color: { number }, material: string)
		add(name .. "Back", "shell", { 2 * hx, tall, out }, { 0, y, -hz - out / 2 }, color, material)
		for _, side in { -1, 1 } do
			local tag = if side < 0 then "West" else "East"
			add(name .. tag, "shell", { out, tall, 2 * hz }, { side * (hx + out / 2), y, 0 }, color, material)
			add(name .. "Front" .. tag, "shell", { section, tall, out }, { side * (door / 2 + section / 2), y, hz + out / 2 }, color, material)
		end
	end
	band("Plinth", PLINTH / 2, PLINTH, 0.4, CONCRETE, "Concrete")
	band("Stripe", 5.6, 0.8, 0.45, ORANGE, "SmoothPlastic")
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			add(`Corner{if sz > 0 then "Front" else "Back"}{if sx < 0 then "West" else "East"}`, "shell", { 1.1, h, 1.1 }, { sx * hx, h / 2, sz * hz }, TRIM, "Metal")
		end
	end

	-- the roller door: rolled up (its bottom slats and bar in the opening's top), its rails, the drum's hood inside,
	-- a bollard each side outside
	for _, side in { -1, 1 } do
		local tag = if side < 0 then "West" else "East"
		add("DoorRail" .. tag, "door", { 0.7, doorHigh, 0.6 }, { side * (door / 2 + 0.35), doorHigh / 2, hz + 0.3 }, STEEL, "Metal")
		local bollard = solid(add("Bollard" .. tag, "door", { 3.4, 1, 1 }, { side * (door / 2 + 1.8), SandboxMap.RoadTop + 1.7, hz + 1.4 }, PAINT, "SmoothPlastic"))
		bollard.shape, bollard.roll = "Cylinder", 90
	end
	add("DoorCurtain", "door", { door, 1.6, 0.3 }, { 0, doorHigh - 0.8, hz - WALL / 2 }, ORANGE, "Metal")
	add("DoorBar", "door", { door, 0.3, 0.45 }, { 0, doorHigh - 1.75, hz - WALL / 2 }, INK, "Rubber")
	add("DoorHood", "door", { door + 1.6, 2.6, 2.6 }, { 0, doorHigh + 1.5, hz - WALL - 1.3 }, STEEL, "Metal")

	-- the signs: ZDC in the front gable, the owner's over the door (server/Warehouse.luau writes it), STOCK inside
	local zdc = add("ZdcSign", "sign", { 20, 5, 0.4 }, { 0, h + 0.5 + 2.5, hz + 0.3 }, TRIM, "SmoothPlastic")
	zdc.yaw = 180
	zdc.words = { { face = "Front", lit = true, lines = { line("ZDC", ORANGE, 0.6, "Black"), line("ZOMBIE DELIVERY CO.", WHITE, 0.24, "Bold") } } }
	local owner = add("OwnerSign", "sign", { 24, 3.6, 0.4 }, { 0, doorHigh + (h - doorHigh) / 2, hz + 0.5 }, TRIM, "SmoothPlastic")
	owner.yaw = 180
	owner.words = { { face = "Front", lit = true, lines = WarehouseLayout.ownerLines(nil, plot.id) } }
	local board = add("StockBoard", "sign", { 22, 6, 0.3 }, { 0, 13.5, -hz + WALL + 0.15 }, TRIM, "SmoothPlastic")
	board.yaw = 180 -- (its front into the hall)
	board.words = { { face = "Front", lit = true, lines = WarehouseLayout.stockLines(0, 0, 0, T.Stands) } }

	-- inside: the tie beams on posts along the side walls, the lamps hung from two of them over the aisles
	local beams = { -25, -14, -3, 8, 19 }
	for n, z in beams do
		add(`Beam{n}`, "inside", { 2 * hx - 2 * WALL, 0.8, 0.8 }, { 0, h - 0.6, z }, STEEL, "Metal")
		for _, side in { -1, 1 } do
			local tall = h - 1 - FLOOR_TOP
			add(`Post{n}{if side < 0 then "West" else "East"}`, "inside", { 0.8, tall, 0.8 }, { side * (hx - WALL - 0.4), FLOOR_TOP + tall / 2, z }, STEEL, "Metal")
		end
	end
	local aisle = T.MiddleAisle / 2 + T.StandSize + T.Aisle / 2 -- (the side aisles' middles)
	local lamps = 0
	for _, z in { beams[2], beams[4] } do
		for _, x in { -aisle, 0, aisle } do
			lamps += 1
			local housing = add(`Lamp{lamps}`, "inside", { 0.7, 3.2, 3.2 }, { x, h - 1.35, z }, TRIM, "Metal")
			housing.shape, housing.roll = "Cylinder", 90
			local glow = add(`LampGlow{lamps}`, "inside", { 0.14, 2.6, 2.6 }, { x, h - 1.77, z }, GLOW, "Neon")
			glow.shape, glow.roll = "Cylinder", 90
			glow.light = { range = T.Lamp.Range, brightness = T.Lamp.Brightness, color = T.Lamp.Color }
		end
	end

	-- the floor's paint: the receiving zone's box and name, the middle aisle's edges
	local inner = hz - WALL
	local zone = T.Receiving
	local paintY = FLOOR_TOP + 0.02
	add("ReceivingBack", "paint", { door, 0.04, 0.4 }, { 0, paintY, inner - zone + 0.2 }, PAINT, "SmoothPlastic")
	add("ReceivingFront", "paint", { door, 0.04, 0.4 }, { 0, paintY, inner - 0.2 }, PAINT, "SmoothPlastic")
	for _, side in { -1, 1 } do
		add("Receiving" .. (if side < 0 then "West" else "East"), "paint", { 0.4, 0.04, zone }, { side * (door / 2 - 0.2), paintY, inner - zone / 2 }, PAINT, "SmoothPlastic")
		local run = inner - zone - (-inner)
		add("AisleLine" .. (if side < 0 then "West" else "East"), "paint", { 0.3, 0.04, run }, { side * (T.MiddleAisle / 2 - 0.5), paintY, -inner + run / 2 }, PAINT, "SmoothPlastic")
	end
	-- (lying flat: its Back face up, its text's top to the north: read from the door)
	local receiving = add("ReceivingText", "paint", { 14, 2.6, 0.05 }, { 0, FLOOR_TOP + 0.03, inner - zone / 2 }, PAINT, "SmoothPlastic")
	receiving.pitch, receiving.transparency = -90, 1
	receiving.words = { { face = "Back", lines = { line("RECEIVING", PAINT, 0.9, "Black") } } }

	-- the display stands: a dark podium, its felt top and its number plate at the front (to the aisle)
	for i = 1, T.Stands do
		local s = WarehouseLayout.stand(plot, i) :: Stand
		local x, z = s.x - ox, s.z - oz
		local base = T.StandHeight - 0.1
		local podium = solid(add(`Stand{i}`, "stand", { s.sx, base, s.sz }, { x, FLOOR_TOP + base / 2, z }, PODIUM, "SmoothPlastic"))
		podium.stand = i
		local top = solid(add(`StandTop{i}`, "stand", { s.sx - 0.6, 0.1, s.sz - 0.6 }, { x, s.y - 0.05, z }, FELT, "Fabric"))
		top.stand = i
		local plate = add(`Plate{i}`, "stand", { 1.6, 0.6, 0.1 }, { x, FLOOR_TOP + base / 2, z + s.sz / 2 + 0.05 }, WHITE, "SmoothPlastic")
		plate.yaw, plate.stand = 180, i
		plate.words = { { face = "Front", lines = { line(tostring(i), INK, 0.9, "Black") } } }
	end

	-- outside: the UNLOAD HERE bay where the van parks, its back to the door
	local bay = WarehouseLayout.bay(plot)
	local bw, bl = bay.x1 - bay.x0, bay.z1 - bay.z0
	local bz = (bay.z0 + bay.z1) / 2 - oz
	local bayY = SandboxMap.RoadTop + 0.03
	for _, side in { -1, 1 } do
		add("Bay" .. (if side < 0 then "West" else "East"), "bay", { 0.5, 0.06, bl }, { side * (bw / 2 - 0.25), bayY, bz }, PAINT, "SmoothPlastic")
	end
	add("BayNorth", "bay", { bw, 0.06, 0.5 }, { 0, bayY, bay.z0 - oz + 0.25 }, PAINT, "SmoothPlastic")
	add("BaySouth", "bay", { bw, 0.06, 0.5 }, { 0, bayY, bay.z1 - oz - 0.25 }, PAINT, "SmoothPlastic")
	local unload = add("BayText", "bay", { bw - 3, 3, 0.05 }, { 0, bayY + 0.01, bay.z0 - oz + 3.5 }, PAINT, "SmoothPlastic")
	unload.pitch, unload.transparency = -90, 1
	unload.words = { { face = "Back", lines = { line("UNLOAD HERE", PAINT, 0.9, "Black") } } }

	return list
end

return WarehouseLayout
