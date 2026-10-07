--!strict
-- 6.4.1, what is in the bag shows (the owner: "it would be good if it were more visible, and that there is something
-- in it"): the pure part. The pieces in a bag stick out of its opening as small simplified shapes of their looks, up to
-- its room, and the bag's body swells as it fills (Config.Courier.BagFill). server/KitWear.luau builds them with the
-- bag on you (again only when the BagCount / BagLooks attributes change: nothing per frame), server/Cargo.luau on the
-- bag set down on the ground. Every piece is a Builder piece on "BagPivot" (server/KitArt/Geometry.luau's frame: the
-- grip at the origin, the bag hanging -Y, its broad sides out along ±X, its length along Z).
--
--   BagFill.kind(look)                       the shape for a piece's look (Config.Cargo looks): "pizza", "bouquet",
--                                            "mail", "paper", "folder", "food", "bread", "cake", "medicine", "greens",
--                                            "gadget", else "parcel"
--   BagFill.layout(mouth, count, room, looks)  where each shown piece stands: { kind, x, y, z, scale, tilt } (the
--                                            shape's base centre on the pivot, its size × scale, leaning `tilt`
--                                            degrees about X). min(count, room, Max) of them; looks[i] is the i-th
--                                            piece's look (missing: a parcel). One row along the opening up to Rows,
--                                            then two side by side; each fits its share of the opening
--   BagFill.pieces(mouth, count, room, looks)  the Builder pieces of those shapes (names "Fill<n><part>")
--   BagFill.bulge(count, room)               the body's thickness factor: 1 empty .. 1 + Bulge full
--   BagFill.swell(pieces, mouth, count, room)  copies of a bag's art pieces with its body (everything under the
--                                            opening) swollen: × bulge across, × (1 + Swell × fill) along
--   BagFill.looks(text)                      the BagLooks attribute ("pizza,bouquet") as a list
--
-- Pure Luau (tests/bagfill_test.luau).

local Config = require(script.Parent.Config)
local KitFit = require(script.Parent.KitFit)

local BagFill = {}

export type Mouth = { y: number, x: number, z: number }
export type Spot = { kind: string, x: number, y: number, z: number, scale: number, tilt: number }
type Part = { name: string, size: { number }, at: { number }, finish: string, shape: string?, turn: { number }? }
type Shape = { x: number, z: number, h: number, parts: { Part } }

local F = Config.Courier.BagFill

-- The look of a piece → its shape.
local KINDS: { [string]: string } = {
	pizza = "pizza",
	bouquet = "bouquet",
	mail = "mail",
	newspaper = "paper",
	documents = "folder",
	burger = "food",
	noodles = "food",
	pastry = "food",
	icecream = "food",
	bread = "bread",
	cake = "cake",
	medicine = "medicine",
	groceries = "greens",
	plants = "greens",
	gadget = "gadget",
	parcel = "parcel",
}

-- Each shape on its base (the bottom at y = 0, centred): its footprint (x thick, z long), its height and its parts.
-- Small and simple: a few blocks each (1 stud ≈ 35 cm of the courier).
local SHAPES: { [string]: Shape } = {
	pizza = { x = 0.08, z = 0.44, h = 0.44, parts = {
		{ name = "Box", size = { 0.07, 0.44, 0.44 }, at = { 0, 0.22, 0 }, finish = "kraft" },
		{ name = "Stripe", size = { 0.08, 0.06, 0.44 }, at = { 0, 0.33, 0 }, finish = "red" },
	} },
	bouquet = { x = 0.3, z = 0.3, h = 0.46, parts = {
		{ name = "Wrap", size = { 0.16, 0.3, 0.16 }, at = { 0, 0.15, 0 }, finish = "paper" },
		{ name = "Leaves", size = { 0.3, 0.06, 0.12 }, at = { 0, 0.3, 0 }, finish = "leaf", turn = { 0, 30, 0 } },
		{ name = "Bloom", size = { 0.24, 0.16, 0.24 }, at = { 0, 0.38, 0 }, finish = "bloom", turn = { 0, 45, 0 } },
	} },
	mail = { x = 0.1, z = 0.26, h = 0.34, parts = {
		{ name = "Letter", size = { 0.03, 0.34, 0.24 }, at = { -0.02, 0.17, 0 }, finish = "white" },
		{ name = "Letter2", size = { 0.03, 0.28, 0.22 }, at = { 0.03, 0.14, 0.02 }, finish = "paper" },
	} },
	paper = { x = 0.14, z = 0.14, h = 0.5, parts = {
		{ name = "Roll", size = { 0.5, 0.13, 0.13 }, at = { 0, 0.25, 0 }, finish = "paper", shape = "Cylinder", turn = { 0, 0, 90 } },
		{ name = "Band", size = { 0.05, 0.14, 0.14 }, at = { 0, 0.32, 0 }, finish = "red", shape = "Cylinder", turn = { 0, 0, 90 } },
	} },
	folder = { x = 0.06, z = 0.3, h = 0.38, parts = {
		{ name = "Folder", size = { 0.05, 0.36, 0.3 }, at = { 0, 0.18, 0 }, finish = "kraft" },
		{ name = "Clip", size = { 0.06, 0.05, 0.1 }, at = { 0, 0.34, 0 }, finish = "steel" },
	} },
	food = { x = 0.24, z = 0.27, h = 0.24, parts = {
		{ name = "Box", size = { 0.22, 0.2, 0.26 }, at = { 0, 0.1, 0 }, finish = "kraft" },
		{ name = "Lid", size = { 0.23, 0.04, 0.27 }, at = { 0, 0.21, 0 }, finish = "red" },
	} },
	bread = { x = 0.12, z = 0.12, h = 0.56, parts = {
		{ name = "Loaf", size = { 0.56, 0.11, 0.11 }, at = { 0, 0.28, 0 }, finish = "crust", shape = "Cylinder", turn = { 0, 0, 90 } },
	} },
	cake = { x = 0.31, z = 0.31, h = 0.27, parts = {
		{ name = "Box", size = { 0.3, 0.26, 0.3 }, at = { 0, 0.13, 0 }, finish = "white" },
		{ name = "Ribbon", size = { 0.31, 0.04, 0.31 }, at = { 0, 0.2, 0 }, finish = "red" },
	} },
	medicine = { x = 0.13, z = 0.17, h = 0.2, parts = {
		{ name = "Box", size = { 0.12, 0.2, 0.16 }, at = { 0, 0.1, 0 }, finish = "white" },
		{ name = "Cross", size = { 0.13, 0.05, 0.17 }, at = { 0, 0.12, 0 }, finish = "red" },
	} },
	greens = { x = 0.26, z = 0.26, h = 0.34, parts = {
		{ name = "Stems", size = { 0.1, 0.18, 0.1 }, at = { 0, 0.09, 0 }, finish = "kraft" },
		{ name = "Leaves", size = { 0.24, 0.18, 0.24 }, at = { 0, 0.25, 0 }, finish = "leaf", turn = { 0, 45, 0 } },
	} },
	gadget = { x = 0.09, z = 0.24, h = 0.3, parts = {
		{ name = "Box", size = { 0.08, 0.3, 0.24 }, at = { 0, 0.15, 0 }, finish = "charcoal" },
		{ name = "Label", size = { 0.085, 0.12, 0.16 }, at = { 0, 0.18, 0 }, finish = "screen" },
	} },
	parcel = { x = 0.27, z = 0.27, h = 0.27, parts = {
		{ name = "Box", size = { 0.26, 0.26, 0.26 }, at = { 0, 0.13, 0 }, finish = "parcel" },
		{ name = "Tape", size = { 0.27, 0.04, 0.27 }, at = { 0, 0.2, 0 }, finish = "paper" },
	} },
}
BagFill.Kinds = KINDS
BagFill.Shapes = SHAPES

function BagFill.kind(look: string?): string
	return if look and KINDS[look] then KINDS[look] else "parcel"
end

function BagFill.looks(text: any): { string }
	local out: { string } = {}
	if type(text) == "string" then
		for look in string.gmatch(text, "[^,]+") do
			table.insert(out, look)
		end
	end
	return out
end

local function shown(count: number, room: number): number
	return math.clamp(math.floor(count), 0, math.max(0, math.min(math.floor(room), F.Max)))
end

function BagFill.layout(mouth: Mouth, count: number, room: number, looks: { string }?): { Spot }
	local out: { Spot } = {}
	local n = shown(count, room)
	if n == 0 then
		return out
	end
	local rows = if n > F.Rows then 2 else 1
	for i = 1, n do
		local row = if rows == 2 then (i - 1) % 2 else 0
		local col = if rows == 2 then (i - 1) // 2 else i - 1
		local inRow = if rows == 2 then (if row == 0 then (n + 1) // 2 else n // 2) else n
		local long = mouth.z / inRow -- (this piece's share of the opening's length …)
		local thick = mouth.x / rows -- (… and of its thickness)
		local kind = BagFill.kind(if looks then looks[i] else nil)
		local shape = SHAPES[kind]
		local scale = math.min(1, 0.92 * long / shape.z, 0.92 * thick / shape.x)
		table.insert(out, {
			kind = kind,
			x = if rows == 2 then (row - 0.5) * thick else 0,
			y = mouth.y - F.Sink * shape.h * scale,
			z = (col + 0.5) * long - mouth.z / 2,
			scale = scale,
			tilt = if i % 2 == 0 then F.Tilt else -F.Tilt,
		})
	end
	return out
end

function BagFill.pieces(mouth: Mouth, count: number, room: number, looks: { string }?): { any }
	local out: { any } = {}
	for n, spot in BagFill.layout(mouth, count, room, looks) do
		local s = spot.scale
		local tilt = math.rad(spot.tilt)
		local c, sn = math.cos(tilt), math.sin(tilt)
		for _, part in SHAPES[spot.kind].parts do
			-- the offset from the shape's base, scaled and leaned about X (CFrame.Angles is Rx · Ry · Rz: the lean adds
			-- to the part's own X turn)
			local ax, ay, az = part.at[1] * s, part.at[2] * s, part.at[3] * s
			local turn = part.turn or { 0, 0, 0 }
			table.insert(out, {
				name = `Fill{n}{part.name}`,
				size = { part.size[1] * s, part.size[2] * s, part.size[3] * s },
				at = { spot.x + ax, spot.y + ay * c - az * sn, spot.z + ay * sn + az * c },
				attach = "BagPivot",
				finish = part.finish,
				shape = part.shape,
				turn = { turn[1] + spot.tilt, turn[2], turn[3] },
			})
		end
	end
	return out
end

function BagFill.bulge(count: number, room: number): number
	local fill = if room > 0 then math.clamp(count / room, 0, 1) else 0
	return 1 + F.Bulge * fill
end

function BagFill.swell(pieces: { any }, mouth: Mouth, count: number, room: number): { any }
	local fill = if room > 0 then math.clamp(count / room, 0, 1) else 0
	if fill <= 0 then
		return pieces
	end
	local body: { any } = {}
	local out: { any } = {}
	for _, piece in pieces do
		if piece.at[2] < mouth.y then
			table.insert(body, piece)
		end
	end
	local fitted = KitFit.fit(body, { BagPivot = { BagFill.bulge(count, room), 1, 1 + F.Swell * fill } })
	local index = 0
	for _, piece in pieces do
		if piece.at[2] < mouth.y then
			index += 1
			table.insert(out, fitted[index])
		else
			table.insert(out, piece)
		end
	end
	return out
end

return BagFill
