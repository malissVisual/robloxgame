--!strict
-- School (Sunny Hill School): cinematic facade, brick with concrete bands, a classroom window grid, the entrance
-- canopy and a wall clock; static decoration only, gameplay (the WORK HERE board, the school gate) stays in World.
local Kit = require(script.Parent.Kit)

local CHARCOAL, CONCRETE, STEEL, RED = { 38, 43, 47 }, { 100, 104, 101 }, { 202, 205, 200 }, { 153, 49, 43 }
local LAMP, GLASS = { 156, 146, 122 }, { 28, 36, 38 }

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

-- The front wall: a concrete cornice with a red line, a plinth, a floor band between the storeys, corner piers.
add({ name = "Cornice", position = { 0, 17.4, -25.45 }, size = { 80, 1.2, 0.9 }, color = CONCRETE, material = "Concrete" })
add({ name = "RedCourse", position = { 0, 16.72, -25.96 }, size = { 80, 0.14, 0.12 }, color = RED, material = "Metal" })
pair({ name = "Plinth", position = { 23.35, 0.6, -25.3 }, size = { 33.3, 1.2, 0.6 }, color = CONCRETE, material = "Concrete" })
pair({ name = "FloorBand", position = { 23.35, 9.4, -25.25 }, size = { 33.3, 0.5, 0.5 }, color = CONCRETE, material = "Concrete" })
pair({ name = "CornerPier", position = { 39.45, 9, -25.45 }, size = { 1.1, 18, 0.9 }, color = CONCRETE, material = "Concrete" })

-- Classroom windows, two storeys (the ground floor glows at night).
for n, x in { 16, 30 } do
	pair({ name = `Window{n}_`, position = { x, 5, -25.15 }, size = { 8, 5, 0.3 }, color = GLASS, material = "Glass", transparency = 0.15, night = true })
	pair({ name = `WindowCap{n}_`, position = { x, 7.7, -25.35 }, size = { 8.5, 0.35, 0.7 }, color = CHARCOAL, material = "Metal" })
	pair({ name = `WindowSill{n}_`, position = { x, 2.3, -25.35 }, size = { 8.5, 0.35, 0.7 }, color = CONCRETE, material = "Concrete" })
	pair({ name = `UpperWindow{n}_`, position = { x, 13.4, -25.15 }, size = { 8, 4.4, 0.3 }, color = GLASS, material = "Glass", transparency = 0.15 })
	pair({ name = `UpperCap{n}_`, position = { x, 15.8, -25.35 }, size = { 8.5, 0.35, 0.7 }, color = CHARCOAL, material = "Metal" })
	pair({ name = `UpperSill{n}_`, position = { x, 11, -25.35 }, size = { 8.5, 0.35, 0.7 }, color = CONCRETE, material = "Concrete" })
end

-- The entrance: steel jambs and lintel, a canopy over the steps with its light, the plate on its edge.
pair({ name = "DoorJamb", position = { 6.4, 5, -25.3 }, size = { 0.5, 10, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "DoorLintel", position = { 0, 10.3, -25.3 }, size = { 13.3, 0.4, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "EntranceCanopy", position = { 0, 11, -26.75 }, size = { 18, 0.5, 3.5 }, color = CHARCOAL, material = "Metal" })
add({ name = "CanopyRedEdge", position = { 0, 10.92, -28.56 }, size = { 18, 0.16, 0.12 }, color = RED, material = "Metal" })
add({ name = "CanopyLight", position = { 0, 10.68, -26.6 }, size = { 6, 0.14, 0.6 }, color = LAMP, material = "Glass", night = true, beam = 22 })
add({ name = "EntrancePlate", position = { 0, 11.75, -28.45 }, size = { 9, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "MAIN ENTRANCE" })
add({ name = "OfficePlate", position = { -10.5, 6.2, -25.08 }, size = { 4.4, 1.1, 0.12 }, color = CHARCOAL, material = "Metal", label = "OFFICE" })
add({ name = "HallPlate", position = { 10.5, 6.2, -25.08 }, size = { 4.4, 1.1, 0.12 }, color = CHARCOAL, material = "Metal", label = "GYM  /  HALL" })

-- The school clock over the canopy (a square dial in a steel frame; its face glows at night).
add({ name = "ClockRim", position = { 0, 14.2, -25.12 }, size = { 3.6, 3.6, 0.24 }, color = CHARCOAL, material = "Metal" })
add({ name = "ClockFace", position = { 0, 14.2, -25.3 }, size = { 3, 3, 0.12 }, color = { 226, 222, 208 }, material = "SmoothPlastic", night = true })
add({ name = "ClockHourHand", position = { 0, 14.6, -25.4 }, size = { 0.16, 0.9, 0.06 }, color = CHARCOAL, material = "Metal" })
add({ name = "ClockMinuteHand", position = { 0.55, 14.2, -25.4 }, size = { 1.1, 0.12, 0.06 }, color = CHARCOAL, material = "Metal" })

-- On the roof: two plant units.
pair({ name = "RoofUnit", position = { 24, 20.25, 12 }, size = { 6, 2.5, 4 }, color = CONCRETE, material = "Metal" })
pair({ name = "RoofUnitCap", position = { 24, 21.65, 12 }, size = { 6.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })

return {
	id = "school", width = 80, depth = 50, height = 18,
	details = details,
	entries = { { 0, 12, 10 } },
} :: Kit.Blueprint
