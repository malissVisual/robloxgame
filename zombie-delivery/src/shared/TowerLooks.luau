--!strict
-- 5.7, the towers' looks (Config.LivingCity.Towers), as plain numbers: every Downtown tower (Map.lots: a "tower" or an
-- "apartment") wears one of four looks over its plain box and window strips, picked from its lot's dice (the same on
-- every server): server/World.luau's tower() builds the pieces, tests/towerlooks_test.luau checks them. Pure Luau.
--
--   shopfront   a ground floor shop on one street wall: dark glass that glows warm at night, a charcoal fascia with a
--               thin red line, a canvas awning; an AC unit on the roof
--   rooftop     a parapet round the roof, a water tank on its slab, two AC units
--   fireescape  a fire escape on a street wall: a landing with its rail on each floor (four at most), the ladder down
--               the side; an AC unit on the roof
--   boarded     some windows boarded over with plywood, one or two broken (black holes)
--
-- At most Budget parts a tower. Nothing low on the sidewalk: what stands under the people's heads stays on the wall
-- (the walkers' lines and the groups: shared/TrafficLanes.luau); an awning or a landing reaches out only over head
-- height. Nothing within DoorClear of an apartment entrance's door below 12 studs (its piers and canopy), nothing within
-- LadderClear of a zip line's ladder, and a zip line's two towers keep their roofs bare but for their platform
-- (shared/ZipLines.luau); a roof's tanks and units stay RoofHeight low (the cables cross the other roofs above that).
--
--   TowerLooks.styleOf(lot)   the look's name
--   TowerLooks.look(lot)      { style, pieces } (the pieces relative to the tower's foot: its middle on the sidewalk)

local Config = require(script.Parent.Config)
local Map = require(script.Parent.Map)
local ZipLines = require(script.Parent.ZipLines)

local TowerLooks = {}

export type Piece = {
	name: string,
	size: { number }, -- along X, Y, Z (the world's axes: a tower is never turned)
	at: { number }, -- the middle, relative to the tower's foot (its middle, on the sidewalk's top)
	color: { number },
	material: string, -- an Enum.Material name
	cylinder: boolean?, -- an upright cylinder (size X = Z: its diameter, Y: its height)
	lit: { number }?, -- glows in this colour at night (DayNight.nightLight)
	roof: boolean?, -- stands on the roof
	face: { number }?, -- on the wall facing this way (x, z), nil on the roof
	along: number?, -- … this far along that wall from its middle (+X or +Z)
}
export type Look = { style: string, pieces: { Piece } }

TowerLooks.Styles = { "shopfront", "rooftop", "fireescape", "boarded" }

local GLASS = { 38, 48, 58 }
local SHOP_LIT = { 255, 206, 140 }
local CHARCOAL = { 36, 38, 42 }
local RED = { 196, 52, 48 }
local CONCRETE = { 96, 94, 90 }
local METAL = { 70, 72, 76 }
local RUST = { 92, 60, 46 }
local PLYWOOD = { 156, 124, 86 }
local HOLE = { 14, 14, 16 }
local AWNINGS = { { 150, 46, 40 }, { 46, 84, 70 }, { 60, 66, 92 }, { 120, 98, 60 } }

-- The windows (server/World.luau windowStrips): floor f at 9 f studs over the sidewalk, 3 tall, the wall's width less 4.
local function floorsOf(lot: Map.Lot): number
	return math.min(math.floor((lot.h - 4) / 9), 6)
end

-- The zip line ladders on this lot's tower (none: an empty list).
local function laddersOf(lot: Map.Lot): { ZipLines.Ladder }
	local list: { ZipLines.Ladder } = {}
	for _, line in ZipLines.lines() do
		for n, ends in { line.start, line.finish } do
			if ends.district == lot.district and ends.i == lot.i and ends.j == lot.j and ends.a == lot.a and ends.b == lot.b then
				table.insert(list, if n == 1 then line.ladderA else line.ladderB)
			end
		end
	end
	return list
end

-- Does the look of this lot stay off the roof (a zip line's tower)?
local function bareRoof(lot: Map.Lot): boolean
	return #laddersOf(lot) > 0
end

function TowerLooks.styleOf(lot: Map.Lot): string
	local rand = Map.lcg(lot.seed + 571)
	local style = TowerLooks.Styles[math.floor(rand() * #TowerLooks.Styles) + 1]
	if style == "rooftop" and bareRoof(lot) then
		style = "boarded" -- (a zip line's roof stays bare)
	end
	return style
end

-- A wall of the tower: its outward way, half the tower across it, its width and the way along it.
type Wall = { nx: number, nz: number, half: number, width: number, tx: number, tz: number }

local function wallOf(lot: Map.Lot, nx: number, nz: number): Wall
	if nx ~= 0 then
		return { nx = nx, nz = 0, half = lot.w / 2, width = lot.d, tx = 0, tz = 1 }
	end
	return { nx = 0, nz = nz, half = lot.d / 2, width = lot.w, tx = 1, tz = 0 }
end

-- The lot's two street walls (its outer sides): the entrance's first for an apartment building.
local function streetWalls(lot: Map.Lot): { Wall }
	local sx, sz = if lot.a == 0 then -1 else 1, if lot.b == 0 then -1 else 1
	local walls = { wallOf(lot, sx, 0), wallOf(lot, 0, sz) }
	if lot.home and lot.facing.z ~= 0 then
		walls = { walls[2], walls[1] }
	end
	return walls
end

function TowerLooks.look(lot: Map.Lot): Look
	local tuning = Config.LivingCity.Towers
	local rand = Map.lcg(lot.seed + 572)
	local style = TowerLooks.styleOf(lot)
	local pieces: { Piece } = {}
	local ladders = laddersOf(lot)
	local bare = #ladders > 0
	local h = lot.h
	local home = lot.home

	-- Is a piece on wall `wall`, `along` from its middle with `reach` either way, from y0 to y1, clear of the door and
	-- the ladders?
	local function clearOn(wall: Wall, along: number, reach: number, y0: number): boolean
		if home and wall.nx == home.facing.x and wall.nz == home.facing.z and y0 < 12 then
			local door = if wall.tx ~= 0 then home.door.x - lot.x else home.door.z - lot.z
			if math.abs(along - door) < reach + tuning.DoorClear then
				return false
			end
		end
		for _, ladder in ladders do
			if ladder.nx == wall.nx and ladder.nz == wall.nz then
				local at = if wall.tx ~= 0 then ladder.x - lot.x else ladder.z - lot.z
				if math.abs(along - at) < reach + tuning.LadderClear then
					return false
				end
			end
		end
		return true
	end
	-- A box on a wall: `along` from its middle, its middle `y` over the sidewalk and `out` from the wall's face; `wide`
	-- along the wall, `tall`, `deep` out of it.
	local function onWall(name: string, wall: Wall, along: number, y: number, out: number, wide: number, tall: number, deep: number, color: { number }, material: string, lit: { number }?): boolean
		if not clearOn(wall, along, wide / 2, y - tall / 2) then
			return false
		end
		local x = wall.nx * (wall.half + out) + wall.tx * along
		local z = wall.nz * (wall.half + out) + wall.tz * along
		local size = if wall.nx ~= 0 then { deep, tall, wide } else { wide, tall, deep }
		table.insert(pieces, { name = name, size = size, at = { x, y, z }, color = color, material = material, lit = lit, face = { wall.nx, wall.nz }, along = along })
		return true
	end
	-- A box on the roof, its foot on the roof, (x, z) from the tower's middle.
	local function onRoof(name: string, x: number, z: number, sx: number, sy: number, sz: number, color: { number }, material: string, cylinder: boolean?, lift: number?)
		if bare then
			return
		end
		table.insert(pieces, { name = name, size = { sx, sy, sz }, at = { x, h + (lift or 0) + sy / 2, z }, color = color, material = material, cylinder = cylinder, roof = true })
	end
	-- A spot on the roof for something `size` across, clear of the edges (and a parapet).
	local function roofSpot(size: number): (number, number)
		local rx, rz = math.max(0, lot.w / 2 - size / 2 - 2), math.max(0, lot.d / 2 - size / 2 - 2)
		return (rand() * 2 - 1) * rx, (rand() * 2 - 1) * rz
	end
	local function acUnit()
		local x, z = roofSpot(3)
		onRoof("RoofUnit", x, z, 3, 1.8, 2.4, METAL, "DiamondPlate")
	end

	local walls = streetWalls(lot)
	if style == "shopfront" then
		-- The shop on the street wall without the entrance (a plain tower: either).
		local wall = if home then walls[2] else walls[math.floor(rand() * 2) + 1]
		local width = wall.width
		local awning = AWNINGS[math.floor(rand() * #AWNINGS) + 1]
		onWall("ShopGlass", wall, 0, 2.95, 0.15, width - 8, 5.1, 0.3, GLASS, "Glass", SHOP_LIT)
		onWall("ShopFascia", wall, 0, 6.3, 0.3, width - 4, 1.4, 0.6, CHARCOAL, "Metal")
		onWall("ShopLine", wall, 0, 5.62, 0.62, width - 4, 0.16, 0.1, RED, "SmoothPlastic")
		onWall("Awning", wall, 0, 7.25, 1.3, width - 10, 0.3, 2.6, awning, "Fabric")
		acUnit()
	elseif style == "rooftop" then
		-- The parapet: a low wall round the roof's edge (the X walls run the whole depth, the Z walls fit between).
		onRoof("Parapet", -lot.w / 2 + 0.3, 0, 0.6, 1.2, lot.d, CONCRETE, "Concrete")
		onRoof("Parapet", lot.w / 2 - 0.3, 0, 0.6, 1.2, lot.d, CONCRETE, "Concrete")
		onRoof("Parapet", 0, -lot.d / 2 + 0.3, lot.w - 1.2, 1.2, 0.6, CONCRETE, "Concrete")
		onRoof("Parapet", 0, lot.d / 2 - 0.3, lot.w - 1.2, 1.2, 0.6, CONCRETE, "Concrete")
		local tx, tz = roofSpot(5)
		onRoof("TankSlab", tx, tz, 4.6, 0.6, 4.6, CONCRETE, "Concrete")
		onRoof("WaterTank", tx, tz, 4, 2.2, 4, RUST, "CorrodedMetal", true, 0.6)
		acUnit()
		acUnit()
	elseif style == "fireescape" then
		-- On a street wall (an apartment building: the other one, off its entrance), near one of its ends.
		local wall = if home then walls[2] else walls[math.floor(rand() * 2) + 1]
		local side = if rand() < 0.5 then -1 else 1
		local floors = math.min(floorsOf(lot), 4)
		local along = side * (wall.width / 2 - 6)
		local built = 0
		for f = 1, floors do
			local y = 9 * f - 1.7 -- under the floor's windows
			if onWall("Landing", wall, along, y, 1, 8, 0.25, 2, METAL, "Metal") then
				onWall("Railing", wall, along, y + 1.1, 1.9, 8, 0.15, 0.15, METAL, "Metal")
				built = f
			end
		end
		if built > 0 then
			-- The ladder down the landings' outer end, from the lowest to the highest.
			local top = 9 * built - 1.7
			local bottom = 9 - 1.7
			onWall("EscapeLadder", wall, along + side * 3.8, (top + bottom) / 2 + 0.6, 1.6, 0.4, top - bottom + 1.2, 0.4, METAL, "Metal")
		end
		acUnit()
	else
		-- Boards over a few windows, a broken one or two (on the street walls, now and then round the back).
		local floors = floorsOf(lot)
		local boards = 3 + math.floor(rand() * 3)
		local holes = 1 + math.floor(rand() * 2)
		local tries = 0
		while boards + holes > 0 and tries < 24 and floors > 0 do
			tries += 1
			local wall = walls[math.floor(rand() * 2) + 1]
			local f = math.floor(rand() * floors) + 1
			local room = wall.width / 2 - 6.5
			local along = (rand() * 2 - 1) * room
			if boards > 0 then
				local wide = 5 + rand() * 4
				if onWall("Boards", wall, along, 9 * f, 0.35, wide, 3.4, 0.2, PLYWOOD, "WoodPlanks") then
					boards -= 1
				end
			elseif onWall("BrokenWindow", wall, along, 9 * f, 0.31, 3, 2.6, 0.12, HOLE, "SmoothPlastic") then
				holes -= 1
			end
		end
	end
	return { style = style, pieces = pieces }
end

return TowerLooks
