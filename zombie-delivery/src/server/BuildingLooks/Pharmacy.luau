--!strict
-- Pharmacy (Corner Pharmacy): cinematic facade, a concrete cornice with the red line, framed shop windows under the
-- green awning, lights beneath it, wayfinding beside the name board; static decoration only, gameplay stays in World.
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

-- The front: cornice over the name board with its red line, corner piers.
add({ name = "Cornice", position = { 0, 14.75, -24.5 }, size = { 64, 0.5, 1 }, color = CONCRETE, material = "Concrete" })
add({ name = "RedLine", position = { 0, 14.62, -25.06 }, size = { 64, 0.14, 0.12 }, color = RED, material = "Metal" })
pair({ name = "CornerPier", position = { 31.45, 7.1, -24.45 }, size = { 1.1, 14.2, 0.9 }, color = CONCRETE, material = "Concrete" })

-- The shop windows (World's glass): steel heads, mullions, kick plates.
pair({ name = "WindowHead", position = { 19, 8.25, -24.8 }, size = { 20.6, 0.3, 0.6 }, color = STEEL, material = "Metal" })
pair({ name = "MullionA", position = { 12.4, 4.5, -24.76 }, size = { 0.16, 7, 0.12 }, color = STEEL, material = "Metal" })
pair({ name = "MullionB", position = { 25.6, 4.5, -24.76 }, size = { 0.16, 7, 0.12 }, color = STEEL, material = "Metal" })
pair({ name = "KickPlate", position = { 19, 0.5, -24.3 }, size = { 20.6, 1, 0.6 }, color = CHARCOAL, material = "Metal" })

-- The door: steel jambs and header.
pair({ name = "DoorJamb", position = { 5.35, 4.5, -24.3 }, size = { 0.5, 9, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "DoorHeader", position = { 0, 9.25, -24.3 }, size = { 11.2, 0.4, 0.6 }, color = STEEL, material = "Metal" })

-- Lights under the awning; wayfinding plates beside the name board.
pair({ name = "AwningLight", position = { 19, 9.5, -25.3 }, size = { 6, 0.14, 0.5 }, color = LAMP, material = "Glass", night = true, beam = 18 })
add({ name = "FirstAidPlate", position = { -24, 12, -24.56 }, size = { 9, 1.2, 0.12 }, color = CHARCOAL, material = "Metal", label = "FIRST AID" })
add({ name = "PrescriptionPlate", position = { 25, 12.6, -24.56 }, size = { 10, 1.4, 0.12 }, color = CHARCOAL, material = "Metal", label = "PRESCRIPTIONS" })

-- On the roof, beside the giant pill: two plant units.
add({ name = "RoofUnit-1", position = { -20, 17.25, 10 }, size = { 6, 2.5, 4 }, color = CONCRETE, material = "Metal" })
add({ name = "RoofUnitCap-1", position = { -20, 18.65, 10 }, size = { 6.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })
add({ name = "RoofUnit1", position = { 26, 17.25, 14 }, size = { 6, 2.5, 4 }, color = CONCRETE, material = "Metal" })
add({ name = "RoofUnitCap1", position = { 26, 18.65, 14 }, size = { 6.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })

return {
	id = "pharmacy", width = 64, depth = 48, height = 15,
	details = details,
	entries = { { 0, 10, 9 } },
} :: Kit.Blueprint
