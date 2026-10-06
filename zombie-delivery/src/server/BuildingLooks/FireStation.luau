--!strict
-- FireStation (Fire Station 9): cinematic facade, steel frames and headers on the three truck bays with their numbers,
-- a charcoal cornice with the red line, lamps between the bays and over the crew door; static decoration only. The
-- bays, roller doors, fire trucks, hydrant and flag stay in World.
-- The layout follows World's buildFireStation with its cargo pile on the +x side (Map.CargoSpots.firestation): the
-- bays at x = -30, -10, 10 (16 wide, 14 high), the crew door at x = 32 (4 wide, 7 high).
local Kit = require(script.Parent.Kit)

local CHARCOAL, CONCRETE, STEEL, RED = { 38, 43, 47 }, { 100, 104, 101 }, { 202, 205, 200 }, { 153, 49, 43 }
local LAMP = { 156, 146, 122 }
local BAYS = { -30, -10, 10 }
local DOOR = 32

local details: { Kit.Detail } = {}
local function add(detail: Kit.Detail)
	table.insert(details, detail)
end

-- The front: a charcoal cornice with the red line, corner piers.
add({ name = "Cornice", position = { 0, 19.6, -23.5 }, size = { 84, 0.8, 1 }, color = CHARCOAL, material = "Metal" })
add({ name = "RedLine", position = { 0, 19.35, -24.06 }, size = { 84, 0.14, 0.12 }, color = RED, material = "Metal" })
add({ name = "CornerPier-1", position = { -41.45, 9.6, -23.45 }, size = { 1.1, 19.2, 0.9 }, color = CONCRETE, material = "Concrete" })
add({ name = "CornerPier1", position = { 41.45, 9.6, -23.45 }, size = { 1.1, 19.2, 0.9 }, color = CONCRETE, material = "Concrete" })

-- The truck bays: steel jambs, a header over each opening, the bay number above it.
for n, x in BAYS do
	add({ name = `BayJambL{n}`, position = { x - 8.35, 7, -23.35 }, size = { 0.6, 14, 0.7 }, color = STEEL, material = "Metal" })
	add({ name = `BayJambR{n}`, position = { x + 8.35, 7, -23.35 }, size = { 0.6, 14, 0.7 }, color = STEEL, material = "Metal" })
	add({ name = `BayHeader{n}`, position = { x, 14.35, -23.35 }, size = { 17.3, 0.6, 0.7 }, color = STEEL, material = "Metal" })
	add({ name = `BayNumber{n}`, position = { x, 15.15, -23.76 }, size = { 2.6, 0.8, 0.1 }, color = CHARCOAL, material = "Metal", label = string.format("%02d", n) })
end

-- The crew door: jambs, header, a lamp over it and the office plate.
add({ name = "CrewDoorJambL", position = { DOOR - 2.35, 3.5, -23.3 }, size = { 0.5, 7, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "CrewDoorJambR", position = { DOOR + 2.35, 3.5, -23.3 }, size = { 0.5, 7, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "CrewDoorHeader", position = { DOOR, 7.25, -23.3 }, size = { 5.2, 0.4, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "CrewDoorLamp", position = { DOOR, 10.5, -23.5 }, size = { 1.4, 0.5, 0.8 }, color = LAMP, material = "Glass", night = true, beam = 18 })
add({ name = "OfficePlate", position = { DOOR, 12, -23.08 }, size = { 6, 1, 0.12 }, color = CHARCOAL, material = "Metal", label = "STATION OFFICE" })

-- Lamps on the piers between the bays (the beam over the apron).
add({ name = "BayLamp1", position = { -20, 12, -23.6 }, size = { 1.2, 0.6, 1 }, color = LAMP, material = "Glass", night = true })
add({ name = "BayLamp2", position = { 0, 12, -23.6 }, size = { 1.2, 0.6, 1 }, color = LAMP, material = "Glass", night = true, beam = 25 })

-- On the roof, either side of the siren: two plant units.
for n, x in { -22, 22 } do
	add({ name = `RoofUnit{n}`, position = { x, 22.25, 6 }, size = { 6, 2.5, 4 }, color = CONCRETE, material = "Metal" })
	add({ name = `RoofUnitCap{n}`, position = { x, 23.65, 6 }, size = { 6.6, 0.3, 4.6 }, color = CHARCOAL, material = "Metal" })
end

local entries: { { number } } = {}
for _, x in BAYS do
	table.insert(entries, { x, 16, 14 })
end
table.insert(entries, { DOOR, 4, 7 })

return {
	id = "firestation", width = 84, depth = 46, height = 20, interior = true,
	details = details,
	entries = entries,
} :: Kit.Blueprint
