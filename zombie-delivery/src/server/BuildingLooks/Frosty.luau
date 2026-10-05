--!strict
-- Frosty (Frosty's Ice Cream): cinematic facade, a charcoal fascia with a raspberry line over the wide glazed door,
-- two serving windows with pink awnings and steel counters; static decoration only, gameplay stays in World.
local Kit = require(script.Parent.Kit)

local CHARCOAL, CONCRETE, STEEL = { 38, 43, 47 }, { 100, 104, 101 }, { 202, 205, 200 }
local LAMP, GLASS = { 156, 146, 122 }, { 28, 36, 38 }
local RASPBERRY, PINK, CREAM = { 168, 62, 98 }, { 206, 146, 168 }, { 232, 224, 210 }

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

-- The front wall: fascia with the raspberry line, corner piers, a concrete plinth either side of the door.
add({ name = "Fascia", position = { 0, 17.2, -25.5 }, size = { 80, 1.6, 1 }, color = CHARCOAL, material = "Metal" })
add({ name = "RaspberryLine", position = { 0, 16.33, -26.06 }, size = { 80, 0.14, 0.12 }, color = RASPBERRY, material = "Metal" })
pair({ name = "CornerPier", position = { 39.45, 8.2, -25.45 }, size = { 1.1, 16.4, 0.9 }, color = CONCRETE, material = "Concrete" })
pair({ name = "Plinth", position = { 26.2, 0.5, -25.3 }, size = { 27.6, 1, 0.6 }, color = CONCRETE, material = "Concrete" })

-- The wide door: steel jambs and header, a slim canopy with two lights.
pair({ name = "DoorJamb", position = { 12.4, 7, -25.3 }, size = { 0.6, 14, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "DoorHeader", position = { 0, 14.3, -25.3 }, size = { 25.4, 0.5, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "DoorCanopy", position = { 0, 15, -26.75 }, size = { 30, 0.45, 3.5 }, color = CHARCOAL, material = "Metal" })
add({ name = "CanopyEdge", position = { 0, 14.95, -28.56 }, size = { 30, 0.18, 0.12 }, color = RASPBERRY, material = "Metal" })
pair({ name = "CanopyLight", position = { 7, 14.7, -26.8 }, size = { 6, 0.14, 0.6 }, color = LAMP, material = "Glass", night = true, beam = 22 })

-- The serving windows: glass that glows at night, mullions, a steel counter, a pink awning with a cream valance.
pair({ name = "ServingWindow", position = { 26, 7, -25.15 }, size = { 18, 6, 0.3 }, color = GLASS, material = "Glass", transparency = 0.15, night = true })
pair({ name = "MullionA", position = { 20, 7, -25.36 }, size = { 0.16, 6, 0.12 }, color = STEEL, material = "Metal" })
pair({ name = "MullionB", position = { 32, 7, -25.36 }, size = { 0.16, 6, 0.12 }, color = STEEL, material = "Metal" })
pair({ name = "ServingCounter", position = { 26, 3.8, -25.6 }, size = { 19, 0.35, 1.2 }, color = STEEL, material = "Metal" })
pair({ name = "Awning", position = { 26, 11.2, -26.5 }, size = { 19, 0.3, 3 }, color = PINK, material = "SmoothPlastic" })
pair({ name = "AwningValance", position = { 26, 10.8, -27.95 }, size = { 19, 0.5, 0.1 }, color = CREAM, material = "SmoothPlastic" })
pair({ name = "AwningLight", position = { 26, 10.98, -26.2 }, size = { 8, 0.12, 0.5 }, color = LAMP, material = "Glass", night = true })
add({ name = "OrderPlate", position = { -26, 12.3, -25.08 }, size = { 8, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "ORDER HERE" })
add({ name = "PickupPlate", position = { 26, 12.3, -25.08 }, size = { 8, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "PICK UP" })

-- On the roof, behind the big cone: two plant units.
pair({ name = "RoofUnit", position = { 26, 20.25, 14 }, size = { 6, 2.5, 4 }, color = CONCRETE, material = "Metal" })
pair({ name = "RoofUnitCap", position = { 26, 21.65, 14 }, size = { 6.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })

return {
	id = "icecream", width = 80, depth = 50, height = 18,
	details = details,
	entries = { { 0, 24, 14 } },
} :: Kit.Blueprint
