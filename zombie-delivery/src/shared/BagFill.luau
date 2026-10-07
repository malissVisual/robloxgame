--!strict
-- 6.4.1, what is in the bag shows (the owner: "it would be good if it were more visible, and that there is something
-- in it"): the pure part. server/KitWear.luau builds the pieces with the bag on you (again only when the BagCount /
-- BagLooks attributes change: nothing per frame), server/Cargo.luau on the bag set down on the ground. Every piece is a
-- Builder piece on "BagPivot" (server/KitArt/Geometry.luau's frame: the grip at the origin, the bag hanging -Y, its
-- broad sides out along ±X, its length along Z).
-- 6.7, real sizes (the owner: "the bag is small, the things would never really fit in it"): the bags are real-size
-- now, and so is what is in them. Each piece is its real packed size (Config.Courier.BagFill.Packed: a pizza box
-- 33 × 4 × 33 cm, a parcel, a bouquet, a cake box …), packed the way a courier packs a bag: a lane along the bag's
-- length, the next lane beside it across its thickness, then a layer below. A piece is turned to fit the opening (a
-- pizza box lies flat in the thermal bag, stacked on the others, and stands on its edge in a plastic bag; a bouquet, a
-- cake, a take-out bag stay upright); one that fits no way round is shrunk, never under MinScale (never the 6.4.1
-- crumbs). The top layer sticks out of the opening by Proud of its height (a bouquet, a baguette by their own `proud`;
-- a flat stack of pizza boxes has its top box at the rim, seen through the open lid), the layers below sit under it,
-- never under the bag's bottom. The body swells with the load by up to the bag's own bulge.
--
--   BagFill.kind(look)                       the shape for a piece's look (Config.Cargo looks): "pizza", "bouquet",
--                                            "mail", "paper", "folder", "food", "bread", "cake", "medicine",
--                                            "groceries", "plants", "gadget", else "parcel"
--   BagFill.layout(mouth, count, room, looks)  where each shown piece is: { kind, x, y, z (its centre on the pivot),
--                                            sx, sy, sz (its size along the bag's axes), axes (which of its own packed
--                                            axes lies along the bag's x, y, z), scale, tilt (degrees about X), layer
--                                            (1: the top one), proud (its share out of the opening) }. min(count, room,
--                                            Max) of them; looks[i] is the i-th piece's look (missing: a parcel), the
--                                            last one packed first (it lies on top: the one you just put in)
--   BagFill.pieces(mouth, count, room, looks)  the Builder pieces of those shapes (names "Fill<n><part>")
--   BagFill.bulge(count, room, most?)        the body's thickness factor: 1 empty .. 1 + most (Bulge) full
--   BagFill.swell(pieces, mouth, count, room)  copies of a bag's art pieces with its body (everything under the
--                                            opening) swollen: × bulge across, × (1 + Swell × fill) along; a lying
--                                            cylinder (the duffel) stays round, its top where it was
--   BagFill.open(pieces, poses)              6.7: copies with the pieces named in `poses` (KitArt.open[bag]) moved to
--                                            their open place (the thermal bag's lid stands open while it holds
--                                            something)
--   BagFill.looks(text)                      the BagLooks attribute ("pizza,bouquet") as a list
--
-- Pure Luau (tests/bagfill_test.luau).

local Config = require(script.Parent.Config)
local KitFit = require(script.Parent.KitFit)

local BagFill = {}

export type Mouth = { y: number, x: number, z: number, d: number?, bulge: number? }
export type Spot = {
	kind: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	axes: { number },
	scale: number,
	tilt: number,
	layer: number,
	proud: number,
}
-- A shape's part: its size and its centre's offset from the piece's centre as shares of the packed size (on the
-- piece's own axes: x, y up, z), its finish; `axis` makes it a cylinder along that own axis (1, 2, 3).
type Part = { name: string, size: { number }, at: { number }, finish: string, axis: number? }
type Packing = { size: { number }, upright: boolean?, stack: boolean?, proud: number? }

local F = Config.Courier.BagFill

-- The look of a piece → its shape (and its packed size: F.Packed has one per shape).
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
	groceries = "groceries",
	plants = "plants",
	gadget = "gadget",
	parcel = "parcel",
}

-- Each shape's parts (a few blocks each). 6.7: shares of its packed size, so the shape is the real size whatever way it
-- is turned in the bag.
local SHAPES: { [string]: { Part } } = {
	pizza = {
		{ name = "Box", size = { 1, 1, 1 }, at = { 0, 0, 0 }, finish = "kraft" },
		{ name = "Logo", size = { 0.42, 0.2, 0.42 }, at = { 0, 0.45, 0 }, finish = "red" },
	},
	parcel = {
		{ name = "Box", size = { 1, 1, 1 }, at = { 0, 0, 0 }, finish = "parcel" },
		{ name = "Tape", size = { 0.24, 1.03, 1.03 }, at = { 0, 0, 0 }, finish = "paper" },
		{ name = "Label", size = { 0.34, 0.3, 0.04 }, at = { 0.24, 0.12, -0.5 }, finish = "white" },
	},
	bouquet = {
		{ name = "Wrap", size = { 0.7, 0.62, 0.7 }, at = { 0, -0.19, 0 }, finish = "kraft" },
		{ name = "Leaves", size = { 1, 0.24, 1 }, at = { 0, 0.17, 0 }, finish = "leaf" },
		{ name = "Bloom", size = { 0.82, 0.22, 0.82 }, at = { 0, 0.38, 0 }, finish = "bloom" },
	},
	cake = {
		{ name = "Box", size = { 1, 1, 1 }, at = { 0, 0, 0 }, finish = "white" },
		{ name = "Ribbon", size = { 0.16, 1.02, 1.02 }, at = { 0, 0, 0 }, finish = "red" },
		{ name = "Ribbon2", size = { 1.02, 1.02, 0.16 }, at = { 0, 0, 0 }, finish = "red" },
	},
	groceries = {
		{ name = "Bag", size = { 1, 0.8, 1 }, at = { 0, -0.1, 0 }, finish = "kraft" },
		{ name = "Leaves", size = { 0.5, 0.36, 0.42 }, at = { -0.2, 0.36, 0.18 }, finish = "leaf" },
		{ name = "Apple", size = { 0.34, 0.3, 0.26 }, at = { 0.2, 0.32, -0.2 }, finish = "red" },
	},
	gadget = {
		{ name = "Box", size = { 1, 1, 1 }, at = { 0, 0, 0 }, finish = "charcoal" },
		{ name = "Picture", size = { 1.04, 0.5, 0.6 }, at = { 0, 0.05, 0 }, finish = "screen" },
	},
	medicine = {
		{ name = "Box", size = { 1, 1, 1 }, at = { 0, 0, 0 }, finish = "white" },
		{ name = "Cross", size = { 1.03, 0.16, 0.56 }, at = { 0, 0.08, 0 }, finish = "red" },
		{ name = "Cross2", size = { 1.03, 0.56, 0.16 }, at = { 0, 0.08, 0 }, finish = "red" },
	},
	mail = {
		{ name = "Letters", size = { 1, 1, 1 }, at = { 0, 0, 0 }, finish = "white" },
		{ name = "Letter2", size = { 0.5, 0.9, 0.86 }, at = { 0.3, 0.12, 0.04 }, finish = "paper" },
		{ name = "Band", size = { 1.12, 1.03, 0.08 }, at = { 0, 0, 0 }, finish = "red" },
	},
	paper = {
		{ name = "Roll", size = { 1, 1, 1 }, at = { 0, 0, 0 }, finish = "paper", axis = 2 },
		{ name = "Band", size = { 1.06, 0.08, 1.06 }, at = { 0, 0.16, 0 }, finish = "red", axis = 2 },
	},
	folder = {
		{ name = "Folder", size = { 1, 1, 1 }, at = { 0, 0, 0 }, finish = "kraft" },
		{ name = "Clip", size = { 1.2, 0.12, 0.2 }, at = { 0, 0.4, 0 }, finish = "steel" },
	},
	food = {
		{ name = "Bag", size = { 1, 0.85, 1 }, at = { 0, -0.075, 0 }, finish = "kraft" },
		{ name = "Fold", size = { 1.02, 0.15, 0.7 }, at = { 0, 0.42, 0 }, finish = "parcel" },
		{ name = "Mark", size = { 1.03, 0.22, 0.42 }, at = { 0, 0.06, 0 }, finish = "red" },
	},
	bread = {
		{ name = "Loaf", size = { 1, 1, 1 }, at = { 0, 0, 0 }, finish = "crust", axis = 2 },
		{ name = "Sleeve", size = { 1.1, 0.45, 1.1 }, at = { 0, -0.27, 0 }, finish = "paper" },
	},
	plants = {
		{ name = "Tray", size = { 1, 0.3, 1 }, at = { 0, -0.35, 0 }, finish = "charcoal" },
		{ name = "Leaves", size = { 0.9, 0.7, 0.9 }, at = { 0, 0.15, 0 }, finish = "leaf" },
	},
}
BagFill.Kinds = KINDS
BagFill.Shapes = SHAPES

-- The ways a piece may be turned to go in (which of its own axes lies along the bag's x, y, z), the likeliest first:
-- as it is, turned flat about its upright, then (unless it must stay upright) on its edge or its side.
local UPRIGHT: { { number } } = { { 1, 2, 3 }, { 3, 2, 1 } }
local ANY: { { number } } = { { 1, 2, 3 }, { 3, 2, 1 }, { 2, 1, 3 }, { 2, 3, 1 }, { 1, 3, 2 }, { 3, 1, 2 } }

function BagFill.kind(look: string?): string
	return if look and KINDS[look] then KINDS[look] else "parcel"
end

-- A shape's packed size and rules.
function BagFill.packing(kind: string): Packing
	return (F.Packed :: { [string]: Packing })[kind] or (F.Packed :: { [string]: Packing }).parcel
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

-- The packing, a layer at a time: lanes along the opening's length (z), side by side across it (x). A lane's spots
-- start at its `z`; a flat stack (a column) is one spot with more on it.
type Lane = { x0: number, w: number, z: number, spots: { Spot } }
type Column = { spot: Spot, kind: string, height: number, above: { Spot } }
type Layer = { lanes: { Lane }, columns: { Column } }

function BagFill.layout(mouth: Mouth, count: number, room: number, looks: { string }?): { Spot }
	local out: { Spot } = {}
	local n = shown(count, room)
	if n == 0 then
		return out
	end
	local mx, mz = math.max(0.05, mouth.x), math.max(0.05, mouth.z)
	local depth = math.max(0.1, mouth.d or 1)
	local gap = F.Gap
	local layers: { Layer } = { { lanes = {}, columns = {} } }
	local function spotOf(kind: string, size: { number }, axes: { number }, scale: number, proud: number): Spot
		return {
			kind = kind,
			x = 0,
			y = 0,
			z = 0,
			sx = size[axes[1]] * scale,
			sy = size[axes[2]] * scale,
			sz = size[axes[3]] * scale,
			axes = axes,
			scale = scale,
			tilt = 0,
			layer = #layers,
			proud = proud,
		}
	end
	local function put(lane: Lane, spot: Spot)
		spot.x = lane.x0 -- (the lane's left edge for now: centred once the layer is done)
		spot.z = lane.z + spot.sz / 2
		lane.z += spot.sz + gap
		lane.w = math.max(lane.w, spot.sx)
		table.insert(lane.spots, spot)
		table.insert(out, spot)
	end
	for i = n, 1, -1 do
		-- (the last one put in first: it lies on top, where you see it go in)
		local kind = BagFill.kind(if looks then looks[i] else nil)
		local rule = BagFill.packing(kind)
		local size = rule.size
		local turns: { { number } } = if rule.upright then UPRIGHT else ANY
		local proud = rule.proud or F.Proud
		local layer = layers[#layers]
		local done = false
		-- a flat one onto a stack of its kind in this layer (a pizza box on the others)
		if rule.stack and size[1] <= mx and size[3] <= mz then
			for _, column in layer.columns do
				if column.kind == kind and column.height + size[2] <= depth then
					local spot = spotOf(kind, size, column.spot.axes, 1, proud)
					table.insert(column.above, spot)
					column.height += size[2]
					table.insert(out, spot)
					done = true
					break
				end
			end
		end
		-- else on along the current lane, then a lane beside it, then a layer below (each: the first way it fits)
		for stage = 1, 3 do
			if done then
				break
			end
			if stage == 3 then
				if #layer.lanes == 0 then
					continue -- (a fresh layer it does not fit either)
				end
				table.insert(layers, { lanes = {}, columns = {} })
				layer = layers[#layers]
			end
			local lanes = layer.lanes
			local lane = lanes[#lanes]
			for _, axes in turns do
				local sx, sz = size[axes[1]], size[axes[3]]
				local fits: boolean
				local x0 = 0
				if stage == 1 then
					fits = lane ~= nil and lane.z + sz <= mz + 1e-9 and lane.x0 + math.max(lane.w, sx) <= mx + 1e-9
				else
					x0 = if lane then lane.x0 + lane.w + gap else 0
					fits = x0 + sx <= mx + 1e-9 and sz <= mz + 1e-9
				end
				if fits then
					if stage > 1 then
						lane = { x0 = x0, w = 0, z = 0, spots = {} }
						table.insert(lanes, lane :: Lane)
					end
					local spot = spotOf(kind, size, axes, 1, proud)
					put(lane :: Lane, spot)
					if rule.stack and axes[2] == 2 then
						table.insert(layer.columns, { spot = spot, kind = kind, height = size[2], above = {} })
					end
					done = true
					break
				end
			end
		end
		if not done then
			-- no way round it fits: the way it fits best, shrunk to the opening (never under MinScale), alone in a lane
			local best, most = turns[1], math.huge
			for _, axes in turns do
				local over = math.max(size[axes[1]] / mx, size[axes[3]] / mz)
				if over < most then
					best, most = axes, over
				end
			end
			local scale = math.clamp(1 / most, F.MinScale, 1)
			if #layer.lanes > 0 then
				table.insert(layers, { lanes = {}, columns = {} })
				layer = layers[#layers]
			end
			local lane: Lane = { x0 = 0, w = 0, z = 0, spots = {} }
			table.insert(layer.lanes, lane)
			put(lane, spotOf(kind, size, best, scale, proud))
		end
	end
	-- Centre each layer's lanes across the opening and each lane's spots along it; then the heights, the top layer
	-- first: its pieces stick out by their share (a stack: its top piece), each layer below under the one above, none
	-- under the bottom.
	local floor = mouth.y - depth
	local under = mouth.y
	local lean = 0
	for index, layer in layers do
		local wide = 0
		for _, lane in layer.lanes do
			wide = math.max(wide, lane.x0 + lane.w)
		end
		local low = math.huge
		for _, lane in layer.lanes do
			local long = math.max(0, lane.z - gap)
			for _, spot in lane.spots do
				spot.x = lane.x0 + lane.w / 2 - wide / 2
				spot.z -= long / 2
				local stack: Column? = nil
				for _, column in layer.columns do
					if column.spot == spot then
						stack = column
					end
				end
				local pile: { Spot } = { spot }
				if stack then
					for _, above in stack.above do
						table.insert(pile, above)
					end
				end
				-- the pile's top (its top piece sticks out by its share in the top layer), then each piece under it
				local top = pile[#pile]
				local high = if index == 1 then mouth.y + top.proud * top.sy else under - gap
				for k = #pile, 1, -1 do
					local piece = pile[k]
					piece.x, piece.z = spot.x, spot.z
					piece.y = high - piece.sy / 2
					high -= piece.sy
				end
				-- (one shrunk wider than the bag: still within it as far as it goes)
				for _, piece in pile do
					local bottom = piece.y - piece.sy / 2
					if bottom < floor then
						piece.y += floor - bottom
					end
					low = math.min(low, piece.y - piece.sy / 2)
					piece.layer = index
				end
				if not stack and index == 1 then
					lean += 1
					spot.tilt = if lean % 2 == 0 then F.Tilt else -F.Tilt
				end
			end
		end
		under = if low < math.huge then low else under
	end
	return out
end

function BagFill.pieces(mouth: Mouth, count: number, room: number, looks: { string }?): { any }
	local out: { any } = {}
	for n, spot in BagFill.layout(mouth, count, room, looks) do
		local size = BagFill.packing(spot.kind).size
		local s = spot.scale
		local a = spot.axes
		local tilt = math.rad(spot.tilt)
		local c, sn = math.cos(tilt), math.sin(tilt)
		for _, part in SHAPES[spot.kind] do
			-- its size and offset on its own axes, then onto the bag's (a[k]: the own axis along the bag's k)
			local own = { part.size[1] * size[1] * s, part.size[2] * size[2] * s, part.size[3] * size[3] * s }
			local off = { part.at[1] * size[1] * s, part.at[2] * size[2] * s, part.at[3] * size[3] * s }
			local dims = { own[a[1]], own[a[2]], own[a[3]] }
			local x, y, z = off[a[1]], off[a[2]], off[a[3]]
			local turn = { 0, 0, 0 }
			local axis = part.axis
			if axis then
				-- a cylinder (its length along Builder's X): along the bag's axis its own axis went to
				local k = if a[1] == axis then 1 elseif a[2] == axis then 2 else 3
				local across = math.min(dims[if k == 1 then 2 else 1], dims[if k == 3 then 2 else 3])
				dims = { dims[k], across, across }
				turn = if k == 1 then { 0, 0, 0 } elseif k == 2 then { 0, 0, 90 } else { 0, 90, 0 }
			end
			-- leaned about X with the piece (CFrame.Angles is Rx · Ry · Rz: the lean goes first in its X)
			table.insert(out, {
				name = `Fill{n}{part.name}`,
				size = dims,
				at = { spot.x + x, spot.y + y * c - z * sn, spot.z + y * sn + z * c },
				attach = "BagPivot",
				finish = part.finish,
				shape = if axis then "Cylinder" else nil,
				turn = { turn[1] + spot.tilt, turn[2], turn[3] },
			})
		end
	end
	return out
end

function BagFill.bulge(count: number, room: number, most: number?): number
	local fill = if room > 0 then math.clamp(count / room, 0, 1) else 0
	return 1 + (most or F.Bulge) * fill
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
	local fitted = KitFit.fit(body, { BagPivot = { BagFill.bulge(count, room, mouth.bulge), 1, 1 + F.Swell * fill } })
	local index = 0
	for _, piece in pieces do
		if piece.at[2] < mouth.y then
			index += 1
			local made = fitted[index]
			if made.shape == "Cylinder" then
				-- (6.7: a cylinder stays round: as wide as it swelled, its top where it was)
				local round = math.max(made.size[2], made.size[3])
				made.at = { made.at[1], made.at[2] - (round - made.size[2]) / 2, made.at[3] }
				made.size = { made.size[1], round, round }
			end
			table.insert(out, made)
		else
			table.insert(out, piece)
		end
	end
	return out
end

function BagFill.open(pieces: { any }, poses: { [string]: { at: { number }, turn: { number } } }?): { any }
	if not poses then
		return pieces
	end
	local out: { any } = {}
	for _, piece in pieces do
		local pose = poses[piece.name]
		if pose then
			local copy = table.clone(piece)
			copy.at = table.clone(pose.at)
			copy.turn = table.clone(pose.turn)
			table.insert(out, copy)
		else
			table.insert(out, piece)
		end
	end
	return out
end

return BagFill
