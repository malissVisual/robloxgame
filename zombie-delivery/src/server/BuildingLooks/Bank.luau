--!strict
-- Bank (First Zombie Bank): cinematic facade behind the marble portico, charcoal hoods and security bars on the tall
-- windows, a framed vault door, the wings with an ATM and cameras; static decoration only. The portico, its steps
-- (and the package behind the last column), the armored-truck lane at the curb and the guard stay in World.
local Kit = require(script.Parent.Kit)

local CHARCOAL, CONCRETE, RED = { 38, 43, 47 }, { 100, 104, 101 }, { 153, 49, 43 }
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

-- The tall windows (World's glass, under the portico and on the wings): hoods, sills, two security bars each.
for n, x in { 17, 27 } do
	pair({ name = `WindowHood{n}_`, position = { x, 15.5, -28.8 }, size = { 6.2, 0.6, 0.8 }, color = CHARCOAL, material = "Metal" })
	pair({ name = `WindowSill{n}_`, position = { x, 2.6, -28.8 }, size = { 6.2, 0.4, 0.8 }, color = CONCRETE, material = "Concrete" })
	pair({ name = `BarA{n}_`, position = { x - 1.25, 9, -28.85 }, size = { 0.14, 12, 0.14 }, color = CHARCOAL, material = "Metal" })
	pair({ name = `BarB{n}_`, position = { x + 1.25, 9, -28.85 }, size = { 0.14, 12, 0.14 }, color = CHARCOAL, material = "Metal" })
end

-- The door: a charcoal frame and the plate over it.
pair({ name = "DoorJamb", position = { 6.45, 7, -28.35 }, size = { 0.7, 14, 0.7 }, color = CHARCOAL, material = "Metal" })
add({ name = "DoorHeader", position = { 0, 14.4, -28.35 }, size = { 13.6, 0.8, 0.7 }, color = CHARCOAL, material = "Metal" })
add({ name = "DoorPlate", position = { 0, 15.6, -28.08 }, size = { 8, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "TELLERS  ·  VAULT" })

-- The wings beside the portico: plinth, corner piers, cornice with a red line, lamps, cameras.
pair({ name = "WingPlinth", position = { 30.2, 0.6, -28.3 }, size = { 11.6, 1.2, 0.6 }, color = CONCRETE, material = "Concrete" })
pair({ name = "CornerPier", position = { 35.45, 12, -28.45 }, size = { 1.1, 24, 0.9 }, color = CONCRETE, material = "Concrete" })
pair({ name = "WingCornice", position = { 30.6, 23.4, -28.5 }, size = { 10.8, 0.8, 1 }, color = CHARCOAL, material = "Metal" })
pair({ name = "WingRedLine", position = { 30.6, 22.85, -29.06 }, size = { 10.8, 0.14, 0.12 }, color = RED, material = "Metal" })
pair({ name = "WingLamp", position = { 30.6, 17.5, -28.6 }, size = { 1, 0.6, 1.2 }, color = LAMP, material = "Glass", night = true, beam = 22 })
pair({ name = "Camera", position = { 34.6, 20.5, -29.6 }, size = { 0.8, 0.6, 1.4 }, color = CHARCOAL, material = "Metal" })

-- The ATM on the right wing (its screen glows at night), the safe-deposit plate on the left.
add({ name = "AtmBody", position = { 32.4, 4.6, -28.3 }, size = { 2.6, 3.6, 0.6 }, color = CHARCOAL, material = "Metal" })
add({ name = "AtmScreen", position = { 32.4, 5.4, -28.64 }, size = { 1.6, 1, 0.08 }, color = { 60, 80, 90 }, material = "Glass", night = true })
add({ name = "AtmPlate", position = { 32.4, 7, -28.66 }, size = { 2.6, 0.7, 0.1 }, color = RED, material = "Metal", label = "ATM" })
add({ name = "DepositPlate", position = { -32.4, 6.5, -28.06 }, size = { 2.6, 1.6, 0.12 }, color = CHARCOAL, material = "Metal", label = "SAFE  /  DEPOSIT" })

-- On the roof, beside the dome: two plant units.
pair({ name = "RoofUnit", position = { 26, 26.25, 16 }, size = { 6, 2.5, 5 }, color = CONCRETE, material = "Metal" })
pair({ name = "RoofUnitCap", position = { 26, 27.65, 16 }, size = { 6.6, 0.3, 5.6 }, color = CHARCOAL, material = "Metal" })

return {
	id = "bank", width = 72, depth = 56, height = 24,
	details = details,
	entries = { { 0, 12, 14 } },
} :: Kit.Blueprint
