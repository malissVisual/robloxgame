--!strict
-- Clinic (City Clinic): cinematic facade, a white two-storey front with concrete fins, framed window bands, the red
-- cross panel set in a charcoal surround; static decoration only. The emergency canopy, the ambulance bay under it
-- (the centre 26 studs, kept clear up to the canopy) and the WORK HERE board stay in World.
local Kit = require(script.Parent.Kit)

local CHARCOAL, CONCRETE, STEEL, RED = { 38, 43, 47 }, { 100, 104, 101 }, { 202, 205, 200 }, { 153, 49, 43 }
local LAMP = { 156, 146, 122 }

local details: { Kit.Detail } = {}
local function add(detail: Kit.Detail)
	table.insert(details, detail)
end
-- A detail on both sides of the entrance (x and -x), named <name>-1 and <name>1; a light's beam only on the right one.
local function pair(detail: Kit.Detail)
	local left = table.clone(detail)
	left.name = detail.name .. "-1"
	left.position = { -detail.position[1], detail.position[2], detail.position[3] }
	left.beam = nil
	table.insert(details, left)
	detail.name ..= "1"
	table.insert(details, detail)
end

-- The front: cornice with the red line, corner fins, fins flanking the ambulance bay, a plinth.
add({ name = "Cornice", position = { 0, 25.4, -28.5 }, size = { 84, 1.2, 1 }, color = CONCRETE, material = "Concrete" })
add({ name = "RedLine", position = { 0, 24.73, -29.06 }, size = { 84, 0.14, 0.12 }, color = RED, material = "Metal" })
pair({ name = "CornerFin", position = { 41.45, 12.4, -28.5 }, size = { 1.1, 24.8, 1 }, color = CONCRETE, material = "Concrete" })
pair({ name = "BayFin", position = { 13.7, 12.4, -28.45 }, size = { 0.8, 24.8, 0.9 }, color = CONCRETE, material = "Concrete" })
pair({ name = "Plinth", position = { 27.7, 0.5, -28.3 }, size = { 26.6, 1, 0.6 }, color = CONCRETE, material = "Concrete" })

-- The window bands (World's glass): thin steel heads and sills, mullions.
pair({ name = "BandHead", position = { 26.55, 8.6, -28.8 }, size = { 24.9, 0.18, 0.6 }, color = STEEL, material = "Metal" })
pair({ name = "BandSill", position = { 26.55, 4.3, -28.8 }, size = { 24.9, 0.3, 0.6 }, color = CONCRETE, material = "Concrete" })
pair({ name = "UpperHead", position = { 26.55, 19.7, -28.8 }, size = { 24.9, 0.3, 0.6 }, color = STEEL, material = "Metal" })
pair({ name = "UpperSill", position = { 26.55, 15.4, -28.8 }, size = { 24.9, 0.16, 0.6 }, color = CONCRETE, material = "Concrete" })
for n, x in { 19.5, 32.5 } do
	pair({ name = `Mullion{n}_`, position = { x, 6.5, -28.77 }, size = { 0.18, 4, 0.14 }, color = STEEL, material = "Metal" })
	pair({ name = `UpperMullion{n}_`, position = { x, 17.5, -28.77 }, size = { 0.18, 4, 0.14 }, color = STEEL, material = "Metal" })
end
add({ name = "OverDoorHead", position = { 0, 21.2, -28.8 }, size = { 12.6, 0.3, 0.6 }, color = STEEL, material = "Metal" })
add({ name = "OverDoorSill", position = { 0, 16.8, -28.8 }, size = { 12.6, 0.3, 0.6 }, color = CONCRETE, material = "Concrete" })

-- The red cross panel in a charcoal surround; wall lights on the bay fins.
add({ name = "CrossSurround", position = { -36, 12, -28.25 }, size = { 8.4, 6.8, 0.5 }, color = CHARCOAL, material = "Metal" })
pair({ name = "FinLight", position = { 13.7, 11, -29.25 }, size = { 0.9, 0.6, 0.7 }, color = LAMP, material = "Glass", night = true, beam = 20 })
add({ name = "OutpatientsPlate", position = { 26, 11.2, -28.56 }, size = { 12, 1.2, 0.12 }, color = CHARCOAL, material = "Metal", label = "OUTPATIENTS  /  LAB" })

-- On the roof, clear of the helipad: two plant units.
pair({ name = "RoofPlant", position = { 33, 28.25, 14 }, size = { 7, 2.5, 5 }, color = CONCRETE, material = "Metal" })
pair({ name = "RoofPlantCap", position = { 33, 29.65, 14 }, size = { 7.6, 0.3, 5.6 }, color = CHARCOAL, material = "Metal" })

return {
	id = "clinic", width = 84, depth = 56, height = 26,
	details = details,
	-- The emergency entrance: the ambulance bay under the canopy (World: 26 wide, its trim from 12.65 up).
	entries = { { 0, 26, 12.6 } },
} :: Kit.Blueprint
