--!strict
-- Police (Precinct 13): cinematic facade, a concrete station house with framed windows on two floors, pilasters
-- flanking the door above the steps, a plinth and floor band on the wings; static decoration only. The steps, the
-- lanterns, the patrol cars and the officer stay in World.
local Kit = require(script.Parent.Kit)

local CHARCOAL, CONCRETE, STEEL, RED = { 38, 43, 47 }, { 100, 104, 101 }, { 202, 205, 200 }, { 153, 49, 43 }
local LAMP = { 156, 146, 122 }

local details: { Kit.Detail } = {}
local function add(detail: Kit.Detail)
	table.insert(details, detail)
end
-- A detail on both sides of the door (x and -x), named <name>-1 and <name>1; a light's beam only on the right one.
local function pair(detail: Kit.Detail)
	local left = table.clone(detail)
	left.name = detail.name .. "-1"
	left.position = { -detail.position[1], detail.position[2], detail.position[3] }
	left.beam = nil
	table.insert(details, left)
	detail.name ..= "1"
	table.insert(details, detail)
end

-- The front: cornice with the red line, corner piers, plinth and floor band on the wings (clear of the steps).
add({ name = "Cornice", position = { 0, 17.6, -22.5 }, size = { 78, 0.8, 1 }, color = CONCRETE, material = "Concrete" })
add({ name = "RedLine", position = { 0, 17.13, -23.06 }, size = { 78, 0.14, 0.12 }, color = RED, material = "Metal" })
pair({ name = "CornerPier", position = { 38.45, 8.6, -22.45 }, size = { 1.1, 17.2, 0.9 }, color = CONCRETE, material = "Concrete" })
pair({ name = "Plinth", position = { 25, 0.6, -22.3 }, size = { 28, 1.2, 0.6 }, color = CONCRETE, material = "Concrete" })
pair({ name = "FloorBand", position = { 25, 9, -22.3 }, size = { 28, 0.4, 0.5 }, color = CONCRETE, material = "Concrete" })

-- The windows (World's glass, two floors): charcoal heads and concrete sills.
for n, x in { 18, 30 } do
	pair({ name = `WindowHead{n}_`, position = { x, 7.4, -22.8 }, size = { 6.6, 0.3, 0.6 }, color = CHARCOAL, material = "Metal" })
	pair({ name = `WindowSill{n}_`, position = { x, 3.6, -22.8 }, size = { 6.6, 0.3, 0.6 }, color = CONCRETE, material = "Concrete" })
	pair({ name = `UpperHead{n}_`, position = { x, 14.4, -22.8 }, size = { 6.6, 0.3, 0.6 }, color = CHARCOAL, material = "Metal" })
	pair({ name = `UpperSill{n}_`, position = { x, 10.6, -22.8 }, size = { 6.6, 0.3, 0.6 }, color = CONCRETE, material = "Concrete" })
end

-- The door at the top of the steps: steel jambs and header, concrete pilasters with caps beside the lanterns.
pair({ name = "DoorJamb", position = { 5.35, 5, -22.3 }, size = { 0.5, 8, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "DoorHeader", position = { 0, 9.22, -22.3 }, size = { 11.2, 0.36, 0.6 }, color = STEEL, material = "Metal" })
pair({ name = "DoorPilaster", position = { 9.4, 6.8, -22.6 }, size = { 1.4, 11.6, 1.2 }, color = CONCRETE, material = "Concrete" })
pair({ name = "PilasterCap", position = { 9.4, 12.8, -22.7 }, size = { 2, 0.4, 1.4 }, color = CHARCOAL, material = "Metal" })

-- Wall lights between the windows, small plates beside the door.
pair({ name = "WallLight", position = { 24, 12.5, -22.7 }, size = { 0.9, 1.2, 0.9 }, color = LAMP, material = "Glass", night = true, beam = 20 })
add({ name = "RecordsPlate", position = { -12.6, 5.5, -22.56 }, size = { 4.2, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "RECORDS" })
add({ name = "DeskPlate", position = { 12.6, 5.5, -22.56 }, size = { 4.2, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "24 HR DESK" })

-- On the roof, clear of the radio mast: two plant units.
add({ name = "RoofUnit-1", position = { -6, 20.25, 12 }, size = { 6, 2.5, 4 }, color = CONCRETE, material = "Metal" })
add({ name = "RoofUnitCap-1", position = { -6, 21.65, 12 }, size = { 6.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })
add({ name = "RoofUnit1", position = { 20, 20.25, 8 }, size = { 6, 2.5, 4 }, color = CONCRETE, material = "Metal" })
add({ name = "RoofUnitCap1", position = { 20, 21.65, 8 }, size = { 6.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })

return {
	id = "police", width = 78, depth = 44, height = 18,
	details = details,
	entries = { { 0, 10, 9 } },
} :: Kit.Blueprint
