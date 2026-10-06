--!strict
-- Spoke & Chain: decorative 60x40x16 shop blueprint, floor origin, front -Z; Claude supplies shell and 12-wide door.
local Kit = require(script.Parent.Kit)
local DARK, RED, STEEL, WALL, GLASS, LAMP = { 35, 40, 43 }, { 153, 49, 43 }, { 166, 176, 174 }, { 80, 88, 86 }, { 43, 64, 70 }, { 184, 172, 146 }
local details: { Kit.Detail } = {}
local function add(name: string, at: { number }, size: { number }, color: { number }, material: string?, rotation: { number }?, label: string?, shape: string?)
	table.insert(details, { name = name, position = at, size = size, color = color, material = material or "Metal", rotation = rotation, label = label, shape = shape })
end
-- The name board is an integration slot at y=17.2; keep decoration below y=16.8 at the front plane.
add("Fascia", { 0, 13.3, -20.4 }, { 60, 1.25, .7 }, DARK)
add("RedRule", { 0, 12.63, -20.83 }, { 59.5, .12, .1 }, RED)
for _, side in { -1, 1 } do
	add("ShopWindow" .. side, { side * 17.5, 5.8, -20.1 }, { 18, 8, .2 }, GLASS, "Glass")
	add("WindowSill" .. side, { side * 17.5, 1.7, -20.35 }, { 18.6, .3, .7 }, WALL, "Concrete")
	add("WindowHeader" .. side, { side * 17.5, 9.97, -20.35 }, { 18.6, .25, .5 }, STEEL)
	add("DoorJamb" .. side, { side * 6.45, 5.1, -20.15 }, { .35, 10.2, .5 }, STEEL)
	add("CornerPier" .. side, { side * 29.3, 6.2, -20.1 }, { 1.1, 12.4, .6 }, WALL, "Concrete")
	add("WindowMullion" .. side, { side * 17.5, 5.8, -20.25 }, { .1, 8, .1 }, STEEL)
end
add("DoorHeader", { 0, 10.5, -20.1 }, { 13.25, .45, .6 }, STEEL)
add("Canopy", { 0, 11.35, -21 }, { 15, .28, 2.7 }, DARK)
table.insert(details, { name = "DoorLamp", position = { 0, 11.11, -21 }, size = { 4, .12, .4 }, color = LAMP, material = "Glass", night = true, beam = 20 })
add("Counter", { -15, 2, -5 }, { 12, 4, 3.5 }, DARK)
add("CounterTop", { -15, 4.13, -5 }, { 12.5, .2, 4 }, STEEL)
add("CounterPlate", { -15, 2.4, -6.81 }, { 9, .7, .08 }, DARK, nil, nil, "RENT  /  BUY  /  REPAIR")
add("PartsPegboard", { -29.25, 7, 8 }, { .2, 7, 14 }, DARK)
add("RepairStandBase", { 13, .2, -4 }, { 3.1, .3, 2.3 }, DARK)
add("RepairStandPost", { 13, 2.15, -4 }, { 4, .16, .16 }, STEEL, nil, { 0, 0, 90 }, nil, "Cylinder")
add("RepairStandClamp", { 13.6, 4.1, -4 }, { 1.2, .18, .18 }, RED)
add("ToolChest", { 24, 2, 9 }, { 7, 4, 3 }, DARK)
for n = 1, 3 do add("DrawerPull" .. n, { 24, 1 + n * .8, 7.43 }, { 4.9, .08, .06 }, STEEL) end
-- Three wall-mounted low-detail bicycle silhouettes, separated from the gameplay/display-bike floor area.
for n, x in { -18, 0, 18 } do
	add("WallRack" .. n, { x, 8.5, 19.05 }, { 9, .1, .28 }, STEEL)
	for _, side in { -1, 1 } do
		add("HangingWheel" .. n .. side, { x + side * 2, 7.2, 18.45 }, { .15, 2.6, 2.6 }, DARK, "Rubber", { 0, 90, 0 }, nil, "Cylinder")
		add("HangingRim" .. n .. side, { x + side * 2, 7.2, 18.31 }, { .08, 2, 2 }, STEEL, nil, { 0, 90, 0 }, nil, "Cylinder")
	end
	add("HangingTopTube" .. n, { x, 8.2, 18.2 }, { 3.4, .1, .1 }, RED)
	add("HangingDownTube" .. n, { x - .45, 7.75, 18.2 }, { 2.3, .1, .1 }, RED, nil, { 0, 0, 30 })
	add("HangingSeatTube" .. n, { x + .2, 7.8, 18.2 }, { .1, 1.7, .1 }, RED)
	add("HangingSaddle" .. n, { x + .25, 8.75, 18.2 }, { .9, .13, .5 }, DARK)
end
for n = 1, 3 do add("SpareTyre" .. n, { -28.5, 2 + n * 1.65, 7.2 }, { .22, 1.4, 1.4 }, DARK, "Rubber", nil, nil, "Cylinder") end
-- Outside rack is to the right of the opening; its door corridor and sign plane remain clear.
add("SidewalkRackBase", { 20, .13, -22.6 }, { 10, .12, 1.1 }, STEEL)
for n = 1, 4 do
	for _, side in { -1, 1 } do add("SidewalkRackPost" .. n .. side, { 15 + n * 2.1, .87, -22.6 + side * .4 }, { 1.6, .075, .075 }, STEEL, nil, { 0, 0, 90 }, nil, "Cylinder") end
	add("SidewalkRackTop" .. n, { 15 + n * 2.1, 1.7, -22.6 }, { .8, .075, .075 }, STEEL, nil, { 0, 90, 0 }, nil, "Cylinder")
end
return { id = "bikeshop", width = 60, depth = 40, height = 16, details = details, entries = { { 0, 12, 10 } }, interior = true } :: Kit.Blueprint
