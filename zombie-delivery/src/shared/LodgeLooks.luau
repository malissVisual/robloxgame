--!strict
-- 8.3 the lodge (the owner: "a udělej mi ten větší dům", make me the bigger house; then "the small chalet doesn't stay"):
-- The Alpine Lodge's outside as plain numbers, the sandbox's one house to empty (shared/SandboxMap.luau House, in The Old
-- Chalet's place). server/SandboxWorld.luau makes a part of each piece on the house's box (SandboxScenery.lodgeSpec),
-- tests/lodgelooks_test.luau checks them. Pure Luau, deterministic (no dice: one lodge).
-- The chalet's style (shared/ChaletLooks.luau: white render below, dark timber above, green shutters, red geraniums,
-- a carved balustrade, slate shingles) on a house twice its size and more: two full storeys, a balcony the whole width
-- of the front, deep eaves, a gable across the house and a cross gable over the entrance with the lodge's name, two
-- chimneys, the terrace door in its east wall with a deck.
--
-- The frame (ChaletLooks' house frame): its origin on the ground at the middle of the front wall (the front door), +X to
-- the right of somebody looking out of the door, +Y up, -Z out of it; the house stands from z = 0 back to z = d, from
-- x = -w / 2 to w / 2.
--
--   the body      the solid box (white render, Spec.h high), a stone plinth, the upper storey (from Spec.ground up) clad
--                 in dark timber, painted corners; the double front door in its painted surround (the part "Door": the
--                 doorway, the moves' front door; its two leaves shut in it, LodgeLooks.Leaves), a lantern either side; four ground-floor windows across the front between open
--                 shutters over boxes of geraniums, four upper ones behind the balcony and its door between them, two
--                 a floor on the west wall, the east wall's ground-floor window and two upper ones
--   the balcony   along the whole front on the ground floor's top: its floor on four struts, the carved balustrade, the
--                 hand rail, its sides, two long boxes of geraniums; two posts under it either side of the door
--   the roof      a gable across the house (its ridge along X): the two solid wedges of its volume (the timber triangles
--                 at its ends), two slate slabs with deep eaves (deepest over the balcony), the ridge cap; the cross
--                 gable over the entrance (a steeper roof from the front wall back into the main one, its face the lodge's
--                 name board and a carved sun); two chimneys through the back slope
--   the terrace   the terrace door (the part "TerraceDoor": the doorway, the moves' second way in; its leaf
--                 "TerraceLeaf") in its painted surround in the east wall Spec.terrace back from the front, a deck in front of it with a rail either side, firewood stacked
--                 by the west wall, a bench under a front window either side of the door
-- Only the body and the main roof's wedges are solid (Piece.solid); everything else is decoration: nothing on the
-- doors' ways out, nothing a mover with a sofa bumps into.
--
--   LodgeLooks.house(spec)   the pieces (shared/ChaletLooks.luau's Piece: name, size, at, color, material, turn?, shape?,
--                            solid?, window?)
--   LodgeLooks.roof(spec)    the gable's rise over the walls, the eaves' reach (front, back, sides), the pitch (degrees)
--   LodgeLooks.Budget        the most pieces it may have
--   LodgeLooks.Sign          the name on the cross gable's board (server/SandboxWorld.luau writes it on the "LodgeSign")

local ChaletLooks = require(script.Parent.ChaletLooks)

local LodgeLooks = {}

export type Piece = ChaletLooks.Piece
export type Spec = {
	w: number, -- the walls' box: wide (X), high (Y), deep (Z)
	h: number,
	d: number,
	ground: number, -- the ground floor's top (the balcony's floor, the timber's foot)
	terrace: number, -- the terrace door's middle, this far back from the front wall along the east wall (+X)
	doorWidth: number, -- the front door's width (its two leaves)
}

LodgeLooks.Budget = 96
-- The doors' leaves (shut in their doorways, each a piece of its own, apart from the wall): their door and the side of
-- the doorway they hang on (the house's frame turned to the map: its door looks north, so -X is west, +Z south).
-- server/SandboxWorld.luau sets them as the attributes DoorLeaf and Hinge (the doors' swing is the client's).
LodgeLooks.Leaves = {
	FrontLeafWest = { door = "front", hinge = "west" },
	FrontLeafEast = { door = "front", hinge = "east" },
	TerraceLeaf = { door = "terrace", hinge = "south" },
} :: { [string]: { door: string, hinge: string } }
LodgeLooks.Sign = "THE ALPINE LODGE"
LodgeLooks.Pitch = 32 -- the main roof's (degrees)
LodgeLooks.CrossPitch = 44 -- the cross gable's, steeper
LodgeLooks.Eaves = { Front = 4.2, Back = 2.2, Side = 2.2 } -- (the front's deep: over the balcony)
LodgeLooks.Balcony = 3.2 -- the balcony's depth out of the front wall

local RENDER = { 244, 240, 230 }
local STONE = { 132, 128, 120 }
local TIMBER = { 92, 62, 40 }
local LIGHT_WOOD = { 188, 146, 96 }
local DARK_WOOD = { 70, 48, 32 }
local SHUTTER = { 56, 100, 62 }
local TRIM = { 250, 248, 240 }
local ROOF = { 78, 58, 44 }
local DOOR = { 96, 60, 36 }
local GLASS = { 40, 50, 60 }
local GERANIUM = { 210, 38, 46 }
local LOGS = { 152, 108, 68 }
local SUN = { 214, 168, 70 }
local LANTERN = { 250, 214, 150 }
local BOARD = { 120, 80, 50 }

local function shade(c: { number }, by: number): { number }
	return { math.clamp(c[1] + by, 0, 255), math.clamp(c[2] + by, 0, 255), math.clamp(c[3] + by, 0, 255) }
end

function LodgeLooks.roof(spec: Spec): (number, { Front: number, Back: number, Side: number }, number)
	local pitch = LodgeLooks.Pitch
	return (spec.d / 2) * math.tan(math.rad(pitch)), LodgeLooks.Eaves, pitch
end

function LodgeLooks.house(spec: Spec): { Piece }
	local w, d, h, g = spec.w, spec.d, spec.h, spec.ground
	local half = w / 2
	local out: { Piece } = {}
	local function add(name: string, size: { number }, at: { number }, color: { number }, material: string, extra: { turn: { number }?, shape: string?, solid: boolean?, window: number? }?): Piece
		local p: Piece = { name = name, size = size, at = at, color = color, material = material }
		if extra then
			p.turn, p.shape, p.solid, p.window = extra.turn, extra.shape, extra.solid, extra.window
		end
		table.insert(out, p)
		return p
	end

	-- ── The body ────────────────────────────────────────────────────────────
	add("House", { w, h, d }, { 0, h / 2, d / 2 }, RENDER, "Plaster", { solid = true })
	add("Plinth", { w + 0.4, 1.2, d + 0.28 }, { 0, 0.6, d / 2 + 0.06 }, STONE, "Slate")
	add("Timber", { w + 0.3, h - g, d + 0.19 }, { 0, (g + h) / 2, d / 2 + 0.055 }, TIMBER, "WoodPlanks")
	for _, side in { -1, 1 } do
		add("PaintedCorner", { 1.6, g - 1.2, 0.12 }, { side * (half - 0.8), 1.2 + (g - 1.2) / 2, -0.06 }, TRIM, "Plaster")
	end
	-- the double front door in its surround, a lantern either side (lit at night by the world's first window die)
	local dw = spec.doorWidth
	add("DoorSurround", { dw + 1.8, 8.8, 0.12 }, { 0, 4.4, -0.06 }, TRIM, "Plaster")
	-- (the doorway: the moves' front door, hidden by server/SandboxWorld.luau; its two leaves shut in it, each hinged at its
	-- jamb: LodgeLooks.Leaves)
	add("Door", { dw, 7.8, 0.4 }, { 0, 3.9, -0.2 }, DOOR, "Wood", { solid = true })
	for _, side in { -1, 1 } do
		add(if side < 0 then "FrontLeafWest" else "FrontLeafEast", { dw / 2 - 0.06, 7.7, 0.3 }, { side * dw / 4, 3.85, -0.2 }, DOOR, "Wood")
	end
	for n, side in { -1, 1 } do
		add("Lantern", { 0.7, 1.1, 0.7 }, { side * (dw / 2 + 1.5), 6.6, -0.5 }, LANTERN, "Glass", { window = n })
	end
	-- the front's ground-floor windows: two either side of the door
	local columns = { -half + 4.5, -half + 11, half - 11, half - 4.5 }
	for n, x in columns do
		add("Shutters", { 5.6, 3.6, 0.12 }, { x, 5.2, -0.06 }, SHUTTER, "Wood")
		add("Window", { 3.4, 3.4, 0.3 }, { x, 5.2, -0.15 }, GLASS, "Glass", { window = 1 + n % 2 })
		add("Geraniums", { 4, 1.1, 0.8 }, { x, 3.4, -0.5 }, GERANIUM, "Grass")
	end
	-- the upper floor's front windows behind the balcony, its door in the middle
	for n, x in columns do
		add("UpperShutters", { 5, 3.4, 0.12 }, { x, g + 3.6, -0.21 }, SHUTTER, "Wood")
		add("UpperWindow", { 2.8, 3.2, 0.2 }, { x, g + 3.6, -0.3 }, GLASS, "Glass", { window = 2 - n % 2 })
	end
	add("BalconyDoor", { 3.4, 6.2, 0.2 }, { 0, g + 3.35, -0.2 }, GLASS, "Glass", { window = 2 })
	-- the side walls' windows: the west wall two a floor, the east wall one below (the terrace door beside it) and two up
	for n, z in { d * 0.3, d * 0.72 } do
		for _, y in { 5.2, g + 3.6 } do
			add("SideShutters", { 0.12, 3.4, 4.6 }, { -half - 0.21, y, z }, SHUTTER, "Wood")
			add("SideWindow", { 0.2, 3.2, 2.6 }, { -half - 0.3, y, z }, GLASS, "Glass", { window = n })
		end
	end
	for n, at in { { d * 0.28, 5.2 }, { d * 0.3, g + 3.6 }, { d * 0.72, g + 3.6 } } do
		add("SideShutters", { 0.12, 3.4, 4.6 }, { half + 0.21, at[2], at[1] }, SHUTTER, "Wood")
		add("SideWindow", { 0.2, 3.2, 2.6 }, { half + 0.3, at[2], at[1] }, GLASS, "Glass", { window = 1 + n % 2 })
	end

	-- ── The balcony ─────────────────────────────────────────────────────────
	local deep = LodgeLooks.Balcony
	local floor = g + 0.25
	local wb = w + 1.2
	add("BalconyFloor", { wb, 0.45, deep }, { 0, g + 0.025, -deep / 2 }, DARK_WOOD, "WoodPlanks")
	add("Balustrade", { wb, 2.4, 0.22 }, { 0, floor + 1.2, -deep + 0.11 }, LIGHT_WOOD, "WoodPlanks")
	add("Carving", { wb - 1, 0.55, 0.06 }, { 0, floor + 1.35, -deep - 0.03 }, shade(TIMBER, -10), "Wood")
	add("HandRail", { wb + 0.3, 0.3, 0.5 }, { 0, floor + 2.55, -deep + 0.05 }, DARK_WOOD, "Wood")
	-- the lodge's name on the balustrade's middle (read from the turnaround), a long box of geraniums either side of it
	add("LodgeSign", { 12, 1.6, 0.2 }, { 0, floor + 1.2, -deep - 0.12 }, BOARD, "WoodPlanks")
	for _, side in { -1, 1 } do
		add("BalconySide", { 0.22, 2.4, deep - 0.2 }, { side * (wb / 2 - 0.11), floor + 1.2, -deep / 2 }, LIGHT_WOOD, "WoodPlanks")
		add("BalconyGeraniums", { wb / 2 - 8, 1.45, 0.8 }, { side * (wb / 4 + 3), floor + 2.375, -deep - 0.45 }, GERANIUM, "Grass")
		for _, x in { half - 4, 9 } do
			-- (a strut from 1.6 under the floor at the wall out to the floor's front)
			add("BalconyStrut", { 0.45, 0.45, deep + 0.2 }, { side * x, g - 0.9, -deep / 2 }, DARK_WOOD, "Wood", { turn = { math.deg(math.atan2(1.6, deep)), 0, 0 } })
		end
		-- a post under the balcony's front either side of the door (clear of its way out)
		add("PorchPost", { 0.6, g, 0.6 }, { side * (dw / 2 + 3.2), g / 2, -deep + 0.4 }, DARK_WOOD, "Wood")
	end

	-- ── The roof: the gable across the house ────────────────────────────────
	local rise, eaves, pitchDeg = LodgeLooks.roof(spec)
	local pitch = math.rad(pitchDeg)
	local thick = 0.55
	-- its volume: two wedges, the front half's slope to the street, the back half's turned round (solid as the chalet's)
	add("Roof", { w, rise, d / 2 }, { 0, h + rise / 2, d / 4 }, TIMBER, "WoodPlanks", { shape = "Wedge", solid = true })
	add("Roof", { w, rise, d / 2 }, { 0, h + rise / 2, d * 3 / 4 }, TIMBER, "WoodPlanks", { shape = "Wedge", solid = true, turn = { 0, 180, 0 } })
	local along = w + 2 * eaves.Side
	for _, side in { -1, 1 } do
		-- (side -1: the front slope, from the ridge out over the front eave; 1: the back one)
		local reach = if side < 0 then eaves.Front else eaves.Back
		local length = (d / 2 + reach) / math.cos(pitch) + 0.1
		local z = d / 2 + side * ((length / 2) * math.cos(pitch) + (thick / 2) * math.sin(pitch))
		local y = h + rise - (length / 2) * math.sin(pitch) + (thick / 2) * math.cos(pitch)
		add("RoofShingles", { along, thick, length }, { 0, y, z }, ROOF, "Slate", { turn = { side * pitchDeg, 0, 0 } })
	end
	add("RoofRidge", { along + 0.2, 0.5, 0.9 }, { 0, h + rise + thick / math.cos(pitch) - 0.05, d / 2 }, shade(ROOF, -18), "Wood")

	-- ── The cross gable over the entrance ───────────────────────────────────
	-- (from the front wall back to where its ridge meets the main roof's front slope; its face: the name board, a sun)
	local cw = 14
	local crossPitch = math.rad(LodgeLooks.CrossPitch)
	local crossRise = (cw / 2) * math.tan(crossPitch)
	local back = crossRise / math.tan(pitch) -- (the main slope reaches its ridge's height there)
	for _, side in { -1, 1 } do
		add("CrossGable", { back, crossRise, cw / 2 }, { side * cw / 4, h + crossRise / 2, back / 2 }, TIMBER, "WoodPlanks", { shape = "Wedge", turn = { 0, -side * 90, 0 } })
		local length = (cw / 2 + 1.2) / math.cos(crossPitch) + 0.1
		local x = side * ((length / 2) * math.cos(crossPitch) + (thick / 2) * math.sin(crossPitch))
		local y = h + crossRise - (length / 2) * math.sin(crossPitch) + (thick / 2) * math.cos(crossPitch)
		add("CrossShingles", { length, thick, back + 1.6 }, { x, y, (back - 1.6) / 2 }, ROOF, "Slate", { turn = { 0, 0, -side * LodgeLooks.CrossPitch } })
	end
	add("CrossRidge", { 0.8, 0.45, back + 1.8 }, { 0, h + crossRise + thick / math.cos(crossPitch) - 0.05, (back - 1.6) / 2 }, shade(ROOF, -18), "Wood")
	add("GableSun", { 0.15, 2.4, 2.4 }, { 0, h + crossRise - 2.8, -0.09 }, SUN, "Wood", { shape = "Cylinder", turn = { 0, 90, 0 } })

	-- ── The chimneys (through the back slope) ───────────────────────────────
	for _, x in { -half + 8, half - 8 } do
		local z = d / 2 + 3.5
		local top = h + rise - 3.5 * math.tan(pitch) + 3.2 -- (3.2 over the slope there)
		local foot = h + rise - 3.5 * math.tan(pitch) - 1.5
		add("Chimney", { 2.4, top - foot, 2.4 }, { x, (top + foot) / 2, z }, STONE, "Slate")
		add("ChimneyCap", { 3.1, 0.45, 3.1 }, { x, top + 0.2, z }, shade(STONE, -30), "Slate")
	end

	-- ── The terrace door, the deck, the yard ────────────────────────────────
	local tz = spec.terrace
	add("TerraceSurround", { 0.12, 8.4, 5.6 }, { half + 0.06, 4.2, tz }, TRIM, "Plaster")
	add("TerraceDoor", { 0.4, 7.4, 4 }, { half + 0.2, 3.7, tz }, DOOR, "Wood", { solid = true }) -- (the doorway, hidden: its leaf shows it)
	add("TerraceLeaf", { 0.3, 7.3, 3.94 }, { half + 0.2, 3.65, tz }, DOOR, "Wood")
	local deck = 7
	add("TerraceDeck", { deck, 0.3, 11 }, { half + deck / 2, 0.15, tz }, LIGHT_WOOD, "WoodPlanks")
	for _, side in { -1, 1 } do
		add("TerraceRail", { deck - 0.6, 2.4, 0.2 }, { half + deck / 2 + 0.3, 1.5, tz + side * 5.4 }, LIGHT_WOOD, "WoodPlanks")
	end
	add("Firewood", { 1.8, 3.6, d * 0.2 }, { -half - 1.05, 1.8, d * 0.51 }, LOGS, "Wood") -- (the stack between the west wall's windows)
	for _, side in { -1, 1 } do
		add("Bench", { 5, 1.6, 1.2 }, { side * (half - 11), 0.8, -1.3 }, LIGHT_WOOD, "WoodPlanks") -- (under a front window)
	end
	return out
end

return LodgeLooks
