--!strict
-- Gas (the Gas Station's shop): cinematic front on the kiosk facing the pumps, a fascia with the red line, a glazed
-- shopfront under a slim canopy, a propane cage; static decoration only. The pumps, the canopy over them, the fuel
-- filler with its cargo spot and the WORK HERE board stay in World. Frame: the shop's floor, -Z toward the pumps.
local Kit = require(script.Parent.Kit)

local CHARCOAL, CONCRETE, STEEL, RED = { 38, 43, 47 }, { 100, 104, 101 }, { 202, 205, 200 }, { 153, 49, 43 }
local LAMP, GLASS = { 156, 146, 122 }, { 28, 36, 38 }

local details: { Kit.Detail } = {}
local function add(detail: Kit.Detail)
	table.insert(details, detail)
end

add({ name = "Fascia", position = { 0, 11.3, -13.5 }, size = { 30, 1.4, 1 }, color = CHARCOAL, material = "Metal" })
add({ name = "RedLine", position = { 0, 10.53, -14.06 }, size = { 30, 0.14, 0.12 }, color = RED, material = "Metal" })
add({ name = "CornerPier-1", position = { -14.45, 5.3, -13.45 }, size = { 1.1, 10.6, 0.9 }, color = CONCRETE, material = "Concrete" })
add({ name = "CornerPier1", position = { 14.45, 5.3, -13.45 }, size = { 1.1, 10.6, 0.9 }, color = CONCRETE, material = "Concrete" })

-- The shopfront (glass that glows at night) under its canopy and light, the kiosk plate.
add({ name = "Shopfront", position = { -3, 5, -13.15 }, size = { 18, 6, 0.3 }, color = GLASS, material = "Glass", transparency = 0.15, night = true })
for n, x in { -9, -3, 3 } do
	add({ name = `Mullion{n}`, position = { x, 5, -13.36 }, size = { 0.16, 6, 0.12 }, color = STEEL, material = "Metal" })
end
add({ name = "ShopfrontHead", position = { -3, 8.2, -13.35 }, size = { 18.6, 0.3, 0.7 }, color = STEEL, material = "Metal" })
add({ name = "ShopfrontSill", position = { -3, 1.8, -13.35 }, size = { 18.6, 0.35, 0.7 }, color = CONCRETE, material = "Concrete" })
add({ name = "Canopy", position = { -3, 9.3, -14.5 }, size = { 21, 0.4, 3 }, color = CHARCOAL, material = "Metal" })
add({ name = "CanopyLight", position = { -3, 9.03, -14.6 }, size = { 6, 0.14, 0.5 }, color = LAMP, material = "Glass", night = true, beam = 20 })
add({ name = "KioskPlate", position = { -3, 10, -13.08 }, size = { 8, 0.8, 0.12 }, color = CHARCOAL, material = "Metal", label = "KIOSK  /  PAY HERE" })

-- The propane cage beside the shopfront, a wall light over the fuel filler side.
add({ name = "PropaneCage", position = { 10.5, 2.2, -14.2 }, size = { 3.6, 4.4, 2.2 }, color = CHARCOAL, material = "Metal", transparency = 0.55 })
add({ name = "PropaneTanks", position = { 10.5, 1.4, -14.2 }, size = { 2.8, 2.6, 1.4 }, color = { 150, 46, 40 }, material = "Metal" })
add({ name = "PropanePlate", position = { 10.5, 5, -15.36 }, size = { 3, 0.7, 0.1 }, color = CHARCOAL, material = "Metal", label = "PROPANE" })
add({ name = "FillerSideLight", position = { 15.35, 8.5, -8 }, size = { 0.7, 0.6, 1 }, color = LAMP, material = "Glass", night = true, beam = 22 })

-- On the roof: a plant unit.
add({ name = "RoofUnit", position = { 6, 13.25, 4 }, size = { 5, 2.5, 4 }, color = CONCRETE, material = "Metal" })
add({ name = "RoofUnitCap", position = { 6, 14.65, 4 }, size = { 5.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })

return {
	id = "gas", width = 30, depth = 26, height = 12,
	details = details,
	entries = {}, -- the shop is a closed kiosk (no doorway)
} :: Kit.Blueprint
