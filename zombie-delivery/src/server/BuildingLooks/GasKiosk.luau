--!strict
-- Pure 24x18x10 station-shop decoration. Floor origin, front -Z; shell, door, ATM and shop behavior belong to Claude.
local Kit = require(script.Parent.Kit)
local DARK, RED, STEEL, WALL, GLASS, LAMP = { 35, 40, 43 }, { 153, 49, 43 }, { 166, 176, 174 }, { 80, 88, 86 }, { 43, 64, 70 }, { 184, 172, 146 }
local details: { Kit.Detail } = {}
local function add(name: string, at: { number }, size: { number }, color: { number }, material: string?, label: string?)
	table.insert(details, { name = name, position = at, size = size, color = color, material = material or "Metal", label = label })
end
add("Fascia", { 0, 9.3, -9.25 }, { 24, 1.15, .6 }, DARK)
add("RedRule", { 0, 8.68, -9.6 }, { 23.6, .1, .06 }, RED)
for _, side in { -1, 1 } do
	add("Shopfront" .. side, { side * 7.3, 4.7, -9.15 }, { 7.8, 6.4, .2 }, GLASS, "Glass")
	add("WindowSill" .. side, { side * 7.3, 1.4, -9.3 }, { 8, .2, .5 }, WALL, "Concrete")
	add("WindowHeader" .. side, { side * 7.3, 8, -9.3 }, { 8, .2, .5 }, STEEL)
	add("DoorJamb" .. side, { side * 3.2, 3.7, -9.2 }, { .2, 7.4, .5 }, STEEL)
	add("CornerPier" .. side, { side * 11.7, 4.2, -9.15 }, { .5, 8.4, .5 }, WALL, "Concrete")
end
add("DoorHeader", { 0, 7.6, -9.2 }, { 6.6, .35, .6 }, STEEL)
add("EntryCanopy", { 0, 8.15, -10 }, { 7.5, .2, 2.2 }, DARK)
table.insert(details, { name = "EntryLamp", position = { 0, 7.96, -10 }, size = { 2.5, .1, .4 }, color = LAMP, material = "Glass", night = true, beam = 16 })
add("Counter", { -5, 1.6, 0 }, { 9, 3.2, 2.5 }, DARK)
add("CounterTop", { -5, 3.3, 0 }, { 9.4, .15, 2.8 }, STEEL)
add("PayPlate", { -5, 2.2, -1.31 }, { 5, .65, .06 }, DARK, nil, "KIOSK  /  PAY HERE")
add("Till", { -3.2, 3.57, .1 }, { 1.4, .4, .8 }, DARK)
add("FridgeBody", { -9.1, 2.7, 5.5 }, { 3.8, 5.4, 2.5 }, STEEL)
add("FridgeGlass", { -9.1, 2.9, 4.18 }, { 3.3, 4.2, .08 }, GLASS, "Glass")
add("FridgeHandle", { -7.68, 2.9, 4.06 }, { .06, 1.4, .06 }, STEEL)
add("FridgeHeader", { -9.1, 5.22, 4.17 }, { 3.4, .25, .07 }, DARK, nil, "COLD DRINKS")
for n = 1, 3 do add("FridgeShelf" .. n, { -9.1, n * 1.2, 4.12 }, { 3.2, .05, .04 }, STEEL) end
add("ShelfUprightL", { 8.9, 2.75, 7.2 }, { .1, 5.5, .8 }, STEEL)
add("ShelfUprightR", { 8.9, 2.75, .8 }, { .1, 5.5, .8 }, STEEL)
for n = 1, 3 do
	add("ShopShelf" .. n, { 8.9, n * 1.35, 4 }, { 2, .1, 7.2 }, STEEL)
	add("ShelfStock" .. n, { 8.9, n * 1.35 + .36, 4 }, { 1.2, .58, 4 }, if n == 2 then RED else WALL, "SmoothPlastic")
end
add("ATMBody", { 7.1, 2.05, -6.6 }, { 1.8, 4.1, 1.4 }, DARK)
add("ATMScreen", { 7.1, 3, -7.36 }, { 1.24, .86, .06 }, GLASS, "Glass", "ATM")
add("ATMKeys", { 7.1, 2.11, -7.38 }, { 1.03, .38, .08 }, STEEL)
add("ATMReceipt", { 7.1, 1.7, -7.4 }, { .7, .05, .04 }, DARK)
add("RoofUnit", { 6, 10.7, 4 }, { 3.8, 1.4, 3 }, WALL)
return { id = "gaskiosk", width = 24, depth = 18, height = 10, details = details, entries = { { 0, 6, 7.3 } }, interior = true } :: Kit.Blueprint
