--!strict
-- Market (FreshMart Supermarket): cinematic facade, a long cornice with the red line, an entrance canopy under the
-- slogan, mullioned shop windows, department plates and wall lights; static decoration only. The car park, the cart
-- corral, the delivery bay and its receiving dock (Map.ReceivingDocks.market) stay in World, well out in front.
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

-- The front: cornice with the red line, corner piers.
add({ name = "Cornice", position = { 0, 15.6, -22.5 }, size = { 96, 0.8, 1 }, color = CONCRETE, material = "Concrete" })
add({ name = "RedLine", position = { 0, 15.13, -23.06 }, size = { 96, 0.14, 0.12 }, color = RED, material = "Metal" })
pair({ name = "CornerPier", position = { 47.45, 7.6, -22.45 }, size = { 1.1, 15.2, 0.9 }, color = CONCRETE, material = "Concrete" })

-- The entrance: a canopy between the green band and the slogan, its light, steel jambs.
add({ name = "EntranceCanopy", position = { 0, 12.2, -24 }, size = { 24, 0.5, 4 }, color = CHARCOAL, material = "Metal" })
add({ name = "CanopyRedEdge", position = { 0, 12.1, -25.94 }, size = { 24, 0.22, 0.12 }, color = RED, material = "Metal" })
add({ name = "CanopyLight", position = { 0, 11.88, -24.2 }, size = { 8, 0.14, 0.6 }, color = LAMP, material = "Glass", night = true, beam = 24 })
pair({ name = "DoorJamb", position = { 7.4, 4.9, -22.3 }, size = { 0.6, 9.8, 0.6 }, color = STEEL, material = "Metal" })

-- The shop windows (World's glass): mullions and kick plates.
for n, x in { 19, 27, 35 } do
	pair({ name = `Mullion{n}_`, position = { x, 5, -22.76 }, size = { 0.18, 8, 0.12 }, color = STEEL, material = "Metal" })
end
pair({ name = "KickPlate", position = { 27, 0.5, -22.3 }, size = { 32.6, 1, 0.6 }, color = CHARCOAL, material = "Metal" })

-- Department plates either side of the slogan, wall lights at the corners (the beam on the delivery side).
add({ name = "DeptPlate-1", position = { -35, 13.4, -22.56 }, size = { 12, 1.4, 0.12 }, color = CHARCOAL, material = "Metal", label = "PRODUCE  ·  DAIRY" })
add({ name = "DeptPlate1", position = { 35, 13.4, -22.56 }, size = { 12, 1.4, 0.12 }, color = CHARCOAL, material = "Metal", label = "BAKERY  ·  DELI" })
add({ name = "WallLight-1", position = { -45, 13.2, -22.7 }, size = { 1.2, 0.6, 1 }, color = LAMP, material = "Glass", night = true, beam = 26 })
add({ name = "WallLight1", position = { 45, 13.2, -22.7 }, size = { 1.2, 0.6, 1 }, color = LAMP, material = "Glass", night = true })

-- On the roof, behind the parapet: three plant units.
for n, at in { { -30, 8 }, { 0, 10 }, { 30, 8 } } do
	add({ name = `RoofUnit{n}`, position = { at[1], 18.25, at[2] }, size = { 6, 2.5, 4 }, color = CONCRETE, material = "Metal" })
	add({ name = `RoofUnitCap{n}`, position = { at[1], 19.65, at[2] }, size = { 6.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })
end

return {
	id = "market", width = 96, depth = 44, height = 16,
	details = details,
	entries = { { 0, 14, 10 } },
} :: Kit.Blueprint
