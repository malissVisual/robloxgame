--!strict
-- CityHall (City Hall): cinematic facade behind the sandstone portico, a framed door, tall windows that glow at night,
-- soffit lights under the beam, the wings with piers, a cornice and the red line; static decoration only. The portico,
-- its steps, the clock tower, the fountain and the flags stay in World.
local Kit = require(script.Parent.Kit)

local CHARCOAL, CONCRETE, RED = { 38, 43, 47 }, { 100, 104, 101 }, { 153, 49, 43 }
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

-- The door on the portico (its floor 1.6 up): a charcoal architrave, a cornice over it and the plate above.
pair({ name = "DoorJamb", position = { 6.5, 8.3, -24.35 }, size = { 0.8, 13.4, 0.7 }, color = CHARCOAL, material = "Metal" })
add({ name = "DoorCornice", position = { 0, 14.6, -24.45 }, size = { 14.6, 0.8, 0.9 }, color = CHARCOAL, material = "Metal" })
add({ name = "DoorPlate", position = { 0, 16.3, -24.08 }, size = { 10, 1.2, 0.12 }, color = CHARCOAL, material = "Metal", label = "COUNCIL  ·  RECORDS" })

-- Tall windows behind the columns, two floors (the lower ones glow at night).
for n, x in { 14, 24 } do
	pair({ name = `Window{n}_`, position = { x, 7, -24.15 }, size = { 4.4, 8.6, 0.3 }, color = GLASS, material = "Glass", transparency = 0.15, night = true })
	pair({ name = `WindowCap{n}_`, position = { x, 11.6, -24.35 }, size = { 5, 0.4, 0.7 }, color = CHARCOAL, material = "Metal" })
	pair({ name = `WindowSill{n}_`, position = { x, 2.5, -24.35 }, size = { 5, 0.35, 0.7 }, color = CONCRETE, material = "Concrete" })
	pair({ name = `UpperWindow{n}_`, position = { x, 16.6, -24.15 }, size = { 4.4, 4.4, 0.3 }, color = GLASS, material = "Glass", transparency = 0.15 })
	pair({ name = `UpperCap{n}_`, position = { x, 19.2, -24.35 }, size = { 5, 0.4, 0.7 }, color = CHARCOAL, material = "Metal" })
end

-- Lights under the portico beam.
pair({ name = "SoffitLight", position = { 13.5, 19.85, -27 }, size = { 4, 0.14, 0.8 }, color = LAMP, material = "Glass", night = true, beam = 26 })

-- The wings beside the portico: piers, plinth, cornice with the red line, heads and sills on World's windows, plates.
pair({ name = "WingPier", position = { 34.6, 12, -24.45 }, size = { 1.1, 24, 0.9 }, color = CONCRETE, material = "Concrete" })
pair({ name = "CornerPier", position = { 42.45, 12, -24.45 }, size = { 1.1, 24, 0.9 }, color = CONCRETE, material = "Concrete" })
pair({ name = "WingPlinth", position = { 38.5, 0.6, -24.3 }, size = { 8.95, 1.2, 0.6 }, color = CONCRETE, material = "Concrete" })
pair({ name = "WingCornice", position = { 38.5, 23.5, -24.5 }, size = { 8.95, 0.8, 1 }, color = CHARCOAL, material = "Metal" })
pair({ name = "WingRedLine", position = { 38.5, 22.95, -25.06 }, size = { 8.95, 0.14, 0.12 }, color = RED, material = "Metal" })
pair({ name = "WingCap", position = { 38, 10.9, -24.35 }, size = { 4.6, 0.35, 0.7 }, color = CHARCOAL, material = "Metal" })
pair({ name = "WingSill", position = { 38, 3.3, -24.35 }, size = { 4.6, 0.35, 0.7 }, color = CONCRETE, material = "Concrete" })
pair({ name = "WingUpperCap", position = { 38, 20.9, -24.35 }, size = { 4.6, 0.35, 0.7 }, color = CHARCOAL, material = "Metal" })
pair({ name = "WingUpperSill", position = { 38, 13.3, -24.35 }, size = { 4.6, 0.35, 0.7 }, color = CONCRETE, material = "Concrete" })
add({ name = "PermitsPlate", position = { -38, 12.1, -24.08 }, size = { 4, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "PERMITS" })
add({ name = "TaxPlate", position = { 38, 12.1, -24.08 }, size = { 4, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "TAX OFFICE" })

-- On the roof, either side of the clock tower: two plant units.
pair({ name = "RoofUnit", position = { 30, 26.25, 14 }, size = { 6, 2.5, 5 }, color = CONCRETE, material = "Metal" })
pair({ name = "RoofUnitCap", position = { 30, 27.65, 14 }, size = { 6.6, 0.3, 5.6 }, color = CHARCOAL, material = "Metal" })

return {
	id = "cityhall", width = 86, depth = 48, height = 24,
	details = details,
	entries = { { 0, 12, 14 } },
} :: Kit.Blueprint
