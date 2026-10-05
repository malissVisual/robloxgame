--!strict
-- Movers (Big Move Movers): cinematic facade, a corrugated shed with a framed loading door, a canopy with its lights,
-- guard posts and the quotes office; static decoration only, the loading door, receiving dock and board stay in World.
local Kit = require(script.Parent.Kit)

local CHARCOAL, CONCRETE, STEEL, RED = { 38, 43, 47 }, { 100, 104, 101 }, { 202, 205, 200 }, { 153, 49, 43 }
local LAMP, GLASS, SAFETY = { 156, 146, 122 }, { 28, 36, 38 }, { 196, 160, 52 }

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

-- The front: a deep fascia with a red line, steel corner columns, a concrete kerb either side of the door.
add({ name = "Fascia", position = { 0, 19, -25.55 }, size = { 80, 2, 1.1 }, color = CHARCOAL, material = "Metal" })
add({ name = "RedLine", position = { 0, 17.93, -26.16 }, size = { 80, 0.14, 0.12 }, color = RED, material = "Metal" })
pair({ name = "CornerColumn", position = { 39.4, 9, -25.5 }, size = { 1.2, 18, 1 }, color = CHARCOAL, material = "Metal" })
pair({ name = "Kerb", position = { 27.2, 0.5, -25.3 }, size = { 25.6, 1, 0.6 }, color = CONCRETE, material = "Concrete" })

-- The loading door: a steel frame, the canopy over it with two lights and its plate, yellow guard posts.
pair({ name = "DoorJamb", position = { 14.45, 7.5, -25.35 }, size = { 0.7, 15, 0.7 }, color = STEEL, material = "Metal" })
add({ name = "DoorHeader", position = { 0, 15.35, -25.35 }, size = { 29.6, 0.7, 0.7 }, color = STEEL, material = "Metal" })
add({ name = "LoadingCanopy", position = { 0, 16.4, -26.75 }, size = { 34, 0.45, 3.5 }, color = CHARCOAL, material = "Metal" })
add({ name = "CanopyRedEdge", position = { 0, 16.33, -28.56 }, size = { 34, 0.18, 0.12 }, color = RED, material = "Metal" })
pair({ name = "CanopyLight", position = { 8, 16.1, -26.8 }, size = { 8, 0.14, 0.6 }, color = LAMP, material = "Glass", night = true, beam = 26 })
add({ name = "LoadingPlate", position = { 0, 17.2, -28.5 }, size = { 10, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "LOADING  /  BAY 1" })
pair({ name = "GuardPost", position = { 15.6, 1.6, -26.2 }, size = { 0.8, 3.2, 0.8 }, color = SAFETY, material = "Metal" })

-- Corrugation ribs: a run on the left, two framing the office on the right.
for n, x in { 18.5, 22.5, 26.5, 30.5, 34.5 } do
	add({ name = `Rib-1_{n}`, position = { -x, 9, -25.18 }, size = { 0.25, 18, 0.35 }, color = CONCRETE, material = "Metal" })
end
add({ name = "Rib1_1", position = { 18.5, 9, -25.18 }, size = { 0.25, 18, 0.35 }, color = CONCRETE, material = "Metal" })
add({ name = "Rib1_2", position = { 36.5, 9, -25.18 }, size = { 0.25, 18, 0.35 }, color = CONCRETE, material = "Metal" })

-- The quotes office on the right: a window that glows at night, its lamp and plate.
add({ name = "OfficeWindow", position = { 27.5, 8, -25.15 }, size = { 12, 5, 0.3 }, color = GLASS, material = "Glass", transparency = 0.15, night = true })
add({ name = "OfficeCap", position = { 27.5, 10.7, -25.35 }, size = { 12.5, 0.35, 0.7 }, color = CHARCOAL, material = "Metal" })
add({ name = "OfficeSill", position = { 27.5, 5.3, -25.35 }, size = { 12.5, 0.35, 0.7 }, color = CONCRETE, material = "Concrete" })
add({ name = "OfficeLamp", position = { 27.5, 12, -25.4 }, size = { 1.2, 0.6, 0.8 }, color = LAMP, material = "Glass", night = true, beam = 18 })
add({ name = "OfficePlate", position = { 27.5, 3.6, -25.08 }, size = { 8, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "OFFICE  /  QUOTES" })

-- On the roof: two vents.
pair({ name = "RoofVent", position = { 24, 22.25, 12 }, size = { 6, 2.5, 4 }, color = CONCRETE, material = "Metal" })
pair({ name = "RoofVentCap", position = { 24, 23.65, 12 }, size = { 6.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })

return {
	id = "movers", width = 80, depth = 50, height = 20,
	details = details,
	entries = { { 0, 28, 15 } },
} :: Kit.Blueprint
