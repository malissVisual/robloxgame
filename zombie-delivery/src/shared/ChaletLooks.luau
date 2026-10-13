--!strict
-- 7.1, the Alps step 1 (the owner: "Austria, mountains, and then lovely little houses where the players live, a little
-- village"): a Suburbs house (Map.Homes, kind "house") as an Austrian chalet, as plain numbers. server/Chalets.luau
-- makes a part of each piece (World's buildHouse hands it the house's lot and the world's dice); tests/chalet_test.luau
-- checks every house of the map: the body, the door and the windows where the house always had them, nothing on the
-- path from the door to the kerb or in the door's swing, everything on its own lot, clear of a moving day's dress
-- (shared/MoveSiteLooks.luau house) and within the part budget. Pure Luau. 7.1 review: about 32 parts a chalet (it
-- was 45): what stood together is one piece (the plinth, a fence and its rail, the firewood, a flower box and its
-- geraniums, the balcony's box with its flowers), the purlin ends are gone; the house, the door and the roof the same.
--
-- The frame is the house's door frame (World's buildHouse): its origin on the walk at the middle of the front wall
-- (the door), +X to the right of somebody looking out of the door, +Y up, -Z out to the street; the house stands from
-- z = 0 back to z = d, from x = -w / 2 to w / 2 (Map.Lot w, d, h: the same box, door and windows as before 7.1).
--
--   the body      the solid box (white or pastel render on the ground floor, the colour die the world always rolled),
--                 a stone plinth, the upper storey clad in dark timber (or silver-grey shingles), the door with its
--                 painted surround, the two ground-floor windows (lit at night by the world's two window dice) between
--                 open shutters over boxes of red geraniums; two small upper windows when the house is tall enough
--   the roof      a steep gable to the street (the ridge from the front to the back), the gable's triangle in timber
--                 (solid, as the old roof's wedges were), two shingle slabs with wide eaves (deepest over the front),
--                 the ridge cap
--   the balcony   across the gable over the front wall: its floor on two struts, a carved balustrade with a darker
--                 band, the hand rail, a long box of red geraniums on it, the balcony door behind it
--   the yard      stacked firewood under the side eave and a low wooden fence along the front of the lot either side of
--                 the path (decoration: nothing to stop a courier, a mover or a car)
-- Three looks (ChaletLooks.variantOf, from the lot's own dice, never the world's): "tyrol" (dark timber, green shutters,
-- a wide balcony), "salzburg" (honey timber, brown shutters, painted corners, a narrower balcony, a grey roof) and
-- "bregenz" (silver shingles over white render, red shutters, a carved sun in the gable).
--
-- (the windows, the upper windows and the balcony door glow at night when the world's window die for them said so)
--
--   ChaletLooks.house(spec)       the pieces of one chalet (spec: the lot's w, d, h, size and seed, the world's colour
--                                 die (1 … 5) and roof die (-30 … 30))
--   ChaletLooks.estate(layout)    a house for sale's chalet dress (see below)
--   ChaletLooks.variantOf(seed)   1 … 3 (ChaletLooks.Variants)
--   ChaletLooks.roof(w)           the gable's rise over the walls and the balcony's width for a house w wide
--   ChaletLooks.box(piece)        a piece's axis-aligned box in the house's frame: x0, x1, y0, y1, z0, z1
--   ChaletLooks.Budget            the most pieces a chalet may have

local ChaletLooks = {}

export type Piece = {
	name: string,
	size: { number }, -- along its own X, Y, Z
	at: { number }, -- its middle in the house's frame
	color: { number }, -- 0 … 255
	material: string, -- an Enum.Material name
	turn: { number }?, -- degrees about X, Y, Z (CFrame.Angles), after the move
	shape: string?, -- "Wedge" (its slope to its own -Z) | "Cylinder" (along its own X)
	solid: boolean?, -- it collides and is hit by rays (the body, the gable, the door); else decoration
	window: number?, -- a window (or the balcony door): which of the world's two window dice lights it at night
}
export type Spec = {
	w: number,
	d: number,
	h: number,
	lot: number, -- the lot's size (its front edge lot / 2 - Map.HouseFront out from the front wall)
	front: number, -- Map.HouseFront: the front wall this far forward of the lot's middle
	seed: number, -- the lot's own dice (Map.Lot seed)
	render: number, -- the world's colour die (1 … 5)
	shade: number, -- the world's roof die (-30 … 30)
}

ChaletLooks.Variants = { "tyrol", "salzburg", "bregenz" }
ChaletLooks.Budget = 36
ChaletLooks.Ground = 7.6 -- the ground floor's top: the render below, the timber above
ChaletLooks.Path = 2.6 -- half the path's width kept clear from the door to the lot's front edge (and the door's swing)

-- The renders (the world's colour die: the old five house colours, now an Austrian street's): white, cream, ochre,
-- pale pink, pale sage.
local RENDERS = { { 242, 238, 228 }, { 238, 226, 198 }, { 228, 200, 136 }, { 236, 212, 202 }, { 216, 222, 204 } }

type Look = {
	timber: { number },
	timberMaterial: string,
	shutter: { number },
	trim: { number },
	roof: { number },
	door: { number },
	balcony: number, -- the balcony's share of the width the gable allows
	corners: boolean,
	sun: boolean,
	firewood: number, -- the side the firewood stacks on (-1 left, 1 right)
	white: boolean, -- always white render
}
local LOOKS: { Look } = {
	{ timber = { 92, 62, 40 }, timberMaterial = "WoodPlanks", shutter = { 56, 100, 62 }, trim = { 250, 248, 240 }, roof = { 78, 58, 44 }, door = { 84, 54, 34 }, balcony = 1, corners = false, sun = false, firewood = -1, white = false },
	{ timber = { 146, 102, 60 }, timberMaterial = "WoodPlanks", shutter = { 112, 72, 44 }, trim = { 196, 186, 168 }, roof = { 86, 88, 94 }, door = { 64, 86, 60 }, balcony = 0.75, corners = true, sun = false, firewood = 1, white = false },
	{ timber = { 146, 138, 124 }, timberMaterial = "Slate", shutter = { 168, 50, 42 }, trim = { 230, 226, 216 }, roof = { 70, 56, 46 }, door = { 96, 64, 40 }, balcony = 1, corners = false, sun = true, firewood = -1, white = true },
}

local LIGHT_WOOD = { 188, 146, 96 }
local DARK_WOOD = { 70, 48, 32 }
local STONE = { 132, 128, 120 }
local GLASS = { 40, 50, 60 }
local GERANIUM = { 210, 38, 46 }
local LOGS = { 152, 108, 68 }
local FENCE = { 128, 92, 60 }
local SUN = { 214, 168, 70 }

local function shade(c: { number }, by: number): { number }
	return { math.clamp(c[1] + by, 0, 255), math.clamp(c[2] + by, 0, 255), math.clamp(c[3] + by, 0, 255) }
end

-- The lot's own dice: a small, steady hash (the same on every server, the world's random numbers untouched).
function ChaletLooks.variantOf(seed: number): number
	local n = math.floor(math.abs(seed)) % 1000003
	return (n * 7919 + 13) // 101 % #ChaletLooks.Variants + 1
end

-- The gable's rise over the walls (steep: 0.8 of the half width, 8 to 10.5) and the balcony's widest (its ends keep
-- 3.4 under the roof's verge: the balustrade and its rail fit under it) for a house `w` wide.
function ChaletLooks.roof(w: number): (number, number)
	local half = w / 2
	local rise = math.clamp(0.8 * half, 8, 10.5)
	return rise, 2 * half * (1 - 3.4 / rise)
end

function ChaletLooks.house(spec: Spec): { Piece }
	local w, d, h = spec.w, spec.d, spec.h
	local half = w / 2
	local look = LOOKS[ChaletLooks.variantOf(spec.seed)]
	local render = if look.white then RENDERS[1] else RENDERS[math.clamp(spec.render, 1, #RENDERS)]
	local roofColor = shade(look.roof, math.floor(spec.shade / 3))
	local g = ChaletLooks.Ground
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
	add("House", { w, h, d }, { 0, h / 2, d / 2 }, render, "Plaster", { solid = true })
	-- (the plinth and the timber stand out of the side and back walls; on the front only a hair: the wall's skin
	-- stays within 0.13 of it, the door's way out clear, and a moving day's MOVING DAY banner, MoveSiteLooks, hangs on
	-- the front wall over the door. 7.1 review: one plinth all round, its front 0.08 out, behind the door's surround)
	add("Plinth", { w + 0.4, 1, d + 0.28 }, { 0, 0.5, d / 2 + 0.06 }, STONE, "Slate")
	add("Timber", { w + 0.3, h - g, d + 0.19 }, { 0, (g + h) / 2, d / 2 + 0.055 }, look.timber, look.timberMaterial)
	if look.corners then
		for _, side in { -1, 1 } do
			add("PaintedCorner", { 1.4, g - 1, 0.12 }, { side * (half - 0.7), 1 + (g - 1) / 2, -0.06 }, look.trim, "Plaster")
		end
	end
	add("DoorSurround", { 5, 7.7, 0.12 }, { 0, 3.85, -0.06 }, look.trim, "Plaster")
	add("Door", { 4, 7, 0.4 }, { 0, 3.5, -0.2 }, look.door, "Wood", { solid = true })
	local column = math.max(half - 4.6, 5.8) -- the windows' middles either side of the door
	for n, side in { -1, 1 } do
		local x = side * column
		add("Shutters", { 5.6, 3.4, 0.12 }, { x, 5.3, -0.06 }, look.shutter, "Wood")
		add("Window", { 3.4, 3.2, 0.3 }, { x, 5.3, -0.15 }, GLASS, "Glass", { window = n })
		add("Geraniums", { 4, 1.1, 0.8 }, { x, 3.6, -0.5 }, GERANIUM, "Grass") -- (a box of them, one piece)
	end
	if h - g >= 4.8 then
		for n, side in { -1, 1 } do
			local x = side * column
			add("UpperShutters", { 4.6, 2.4, 0.12 }, { x, h - 1.9, -0.21 }, look.shutter, "Wood")
			add("UpperWindow", { 2.4, 2.2, 0.2 }, { x, h - 1.9, -0.3 }, GLASS, "Glass", { window = 3 - n })
		end
	end

	-- ── The roof ────────────────────────────────────────────────────────────
	local rise, widest = ChaletLooks.roof(w)
	local pitch = math.atan(rise / half)
	local eaveSide, eaveFront, eaveBack, thick = 1.8, 2.8, 1.6, 0.5
	for _, side in { -1, 1 } do
		-- the gable's half, a wedge whose slope faces out to this side (its own -Z turned to ±X)
		add("Roof", { d, rise, half }, { side * half / 2, h + rise / 2, d / 2 }, look.timber, look.timberMaterial, { shape = "Wedge", solid = true, turn = { 0, -side * 90, 0 } })
	end
	local length = (half + eaveSide) / math.cos(pitch) + 0.1
	local along = d + eaveFront + eaveBack
	local zMid = (d + eaveBack - eaveFront) / 2
	for _, side in { -1, 1 } do
		local x = side * ((length / 2) * math.cos(pitch) + (thick / 2) * math.sin(pitch))
		local y = h + rise - (length / 2) * math.sin(pitch) + (thick / 2) * math.cos(pitch)
		add("RoofShingles", { length, thick, along }, { x, y, zMid }, roofColor, "Slate", { turn = { 0, 0, -side * math.deg(pitch) } })
	end
	add("RoofRidge", { 0.8, 0.45, along + 0.2 }, { 0, h + rise + thick / math.cos(pitch) - 0.05, zMid }, shade(roofColor, -18), "Wood")
	local wb = math.floor(math.min(w - 3, widest) * look.balcony * 2 + 0.5) / 2

	-- ── The balcony ─────────────────────────────────────────────────────────
	local floor = h + 0.25
	add("BalconyFloor", { wb, 0.4, 2.8 }, { 0, h + 0.05, -1.4 }, DARK_WOOD, "WoodPlanks")
	add("Balustrade", { wb, 2.4, 0.22 }, { 0, floor + 1.2, -2.7 }, LIGHT_WOOD, "WoodPlanks")
	add("Carving", { wb - 0.8, 0.55, 0.06 }, { 0, floor + 1.35, -2.84 }, shade(look.timber, -10), "Wood")
	add("HandRail", { wb + 0.3, 0.3, 0.5 }, { 0, floor + 2.55, -2.65 }, DARK_WOOD, "Wood")
	for _, side in { -1, 1 } do
		add("BalconySide", { 0.22, 2.4, 2.6 }, { side * (wb / 2 - 0.11), floor + 1.2, -1.4 }, LIGHT_WOOD, "WoodPlanks")
		-- (from 1.4 under the floor at the wall out to the floor's front: clear of a MOVING DAY banner over the door)
		add("BalconyStrut", { 0.4, 0.4, 2.7 }, { side * (wb / 2 - 1), h - 0.775, -1.2 }, DARK_WOOD, "Wood", { turn = { math.deg(math.atan2(1.25, 2.4)), 0, 0 } })
	end
	add("BalconyDoor", { 3.2, 4.4, 0.2 }, { 0, floor + 2.2, -0.1 }, GLASS, "Glass", { window = 2 })
	add("BalconyGeraniums", { wb - 1.2, 1.45, 0.8 }, { 0, floor + 2.375, -3.2 }, GERANIUM, "Grass") -- (the box, its flowers hanging over the rail)
	if look.sun then
		add("GableSun", { 0.15, 2.2, 2.2 }, { 0, h + rise - 2.3, -0.09 }, SUN, "Wood", { shape = "Cylinder", turn = { 0, 90, 0 } })
	end

	-- ── The yard ────────────────────────────────────────────────────────────
	do
		local side = look.firewood
		local x = side * (half + 0.95)
		local z0, z1 = d * 0.3, d * 0.8
		add("Firewood", { 1.6, 3.4, z1 - z0 }, { x, 1.7, (z0 + z1) / 2 }, LOGS, "Wood") -- (the stack, one piece, under the side eave)
	end
	do
		local edge = -(spec.lot / 2 - spec.front) + 0.6 -- (the lot's front edge, a little in)
		local from, to = ChaletLooks.Path + 0.6, spec.lot / 2 - 1.5
		for _, side in { -1, 1 } do
			local x = side * (from + to) / 2
			add("Fence", { to - from + 0.3, 1.3, 0.16 }, { x, 0.95, edge }, FENCE, "WoodPlanks") -- (its boards and rail, one piece)
		end
	end
	return out
end

-- 7.1: a house for sale on a Suburbs lot (World's estateHouse: its walls with real openings, its rooms, its garage on
-- the right) dressed as a chalet, in the estate's frame (the same: +X right of somebody looking out, -Z the front):
-- a timber band round its walls under the eaves (front, back and the left: the garage stands on the right), open
-- shutters either side of each front window (its glass sits in the wall's opening: nothing over it) and a box of red
-- geraniums under it, firewood stacked by the left wall, and over a two-storey house's door a balcony along the
-- upper floor. Decoration only (the walls, the roof and the doors are World's). (7.1 review: the same one-piece flower
-- boxes, firewood and balcony box as a chalet's.)
export type EstateLayout = {
	x0: number, -- the house's walls (its garage beyond x1)
	x1: number,
	z0: number,
	z1: number,
	eaves: number, -- the ground floor's walls' top (the band under it)
	upper: boolean, -- a second storey: a balcony along the front over the door
	windows: { { at: number, width: number, bottom: number, top: number } }, -- the front windows (from the ground)
	door: { at: number, width: number }, -- the front door (no shutter over it)
}

function ChaletLooks.estate(layout: EstateLayout): { Piece }
	local out: { Piece } = {}
	local function add(name: string, size: { number }, at: { number }, color: { number }, material: string, turn: { number }?)
		table.insert(out, { name = name, size = size, at = at, color = color, material = material, turn = turn })
	end
	local x0, x1, z0, z1 = layout.x0, layout.x1, layout.z0, layout.z1
	local band, top = 8.6, layout.eaves
	local timber, shutter = LOOKS[1].timber, LOOKS[1].shutter
	add("TimberBand", { x1 - x0 + 0.3, top - band, 0.15 }, { (x0 + x1) / 2, (band + top) / 2, z0 - 0.075 }, timber, "WoodPlanks")
	add("TimberBand", { x1 - x0 + 0.3, top - band, 0.15 }, { (x0 + x1) / 2, (band + top) / 2, z1 + 0.075 }, timber, "WoodPlanks")
	add("TimberBand", { 0.15, top - band, z1 - z0 }, { x0 - 0.075, (band + top) / 2, (z0 + z1) / 2 }, timber, "WoodPlanks")
	local door = layout.door
	for _, window in layout.windows do
		local leaf = window.width * 0.35
		for _, side in { -1, 1 } do
			local x = window.at + side * (window.width / 2 + leaf / 2 + 0.05)
			-- (none over the door's opening beside it, none round the house's corner)
			if math.abs(x - door.at) >= door.width / 2 + leaf / 2 and x - leaf / 2 >= x0 and x + leaf / 2 <= x1 then
				add("Shutter", { leaf, window.top - window.bottom + 0.2, 0.12 }, { x, (window.bottom + window.top) / 2, z0 - 0.06 }, shutter, "Wood")
			end
		end
		add("Geraniums", { window.width, 1.1, 0.8 }, { window.at, window.bottom - 0.15, z0 - 0.45 }, GERANIUM, "Grass")
	end
	do
		local x = x0 - 0.95
		local a, b = z0 + 2.5, z1 - 2.5
		add("Firewood", { 1.6, 3.4, b - a }, { x, 1.7, (a + b) / 2 }, LOGS, "Wood")
	end
	if layout.upper then
		local wb, floor = x1 - x0 - 2, top + 0.25
		local mid = (x0 + x1) / 2
		add("BalconyFloor", { wb, 0.4, 2.8 }, { mid, top + 0.05, z0 - 1.4 }, DARK_WOOD, "WoodPlanks")
		add("Balustrade", { wb, 2.4, 0.22 }, { mid, floor + 1.2, z0 - 2.7 }, LIGHT_WOOD, "WoodPlanks")
		add("Carving", { wb - 0.8, 0.55, 0.06 }, { mid, floor + 1.35, z0 - 2.84 }, shade(timber, -10), "Wood")
		add("HandRail", { wb + 0.3, 0.3, 0.5 }, { mid, floor + 2.55, z0 - 2.65 }, DARK_WOOD, "Wood")
		for _, side in { -1, 1 } do
			add("BalconySide", { 0.22, 2.4, 2.6 }, { mid + side * (wb / 2 - 0.11), floor + 1.2, z0 - 1.4 }, LIGHT_WOOD, "WoodPlanks")
			add("BalconyStrut", { 0.4, 0.4, 3.1 }, { mid + side * (wb / 2 - 1), top - 1.15, z0 - 1.2 }, DARK_WOOD, "Wood", { math.deg(math.atan2(2.05, 2.4)), 0, 0 })
		end
		add("BalconyGeraniums", { wb - 1.2, 1.45, 0.8 }, { mid, floor + 2.375, z0 - 3.2 }, GERANIUM, "Grass")
	end
	return out
end

-- A piece's axis-aligned box in the house's frame (its turn taken into account): x0, x1, y0, y1, z0, z1.
function ChaletLooks.box(piece: Piece): (number, number, number, number, number, number)
	local turn = piece.turn or { 0, 0, 0 }
	local ax, ay, az = math.rad(turn[1]), math.rad(turn[2]), math.rad(turn[3])
	-- CFrame.Angles(x, y, z) = Rx * Ry * Rz: the rotation's rows
	local cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
	local rows = {
		{ cy * cz, -cy * sz, sy },
		{ cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy },
		{ sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy },
	}
	local reach = {}
	for i = 1, 3 do
		local r = rows[i]
		reach[i] = math.abs(r[1]) * piece.size[1] / 2 + math.abs(r[2]) * piece.size[2] / 2 + math.abs(r[3]) * piece.size[3] / 2
	end
	local p = piece.at
	return p[1] - reach[1], p[1] + reach[1], p[2] - reach[2], p[2] + reach[2], p[3] - reach[3], p[3] + reach[3]
end

return ChaletLooks
