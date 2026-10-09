--!strict
-- 6.11, the shops' rooftop set pieces (the owner: "the pizza place has a big slice over it, the gun shop a big GUN STORE
-- and a cartridge ..."): pure native geometry (blocks, wedges, cylinders, balls; no meshes, no uploaded assets), so a
-- player remembers each shop of the safe zone by what stands on its roof. server/ShopProps.luau builds them with
-- PolishArt.Builder. Every prop is drawn in its own roof frame: the origin in the middle of the roof's top (y = 0 is the
-- roof surface), -Z toward the street, so +X is the LEFT hand of someone on the street looking at the shop (the text
-- reads from +X to -X on the street side and the other way round on the back).
--   guns      Lead & Co.: GUN STORE in 3D block letters on a double-sided marquee (bulbs along it, readable from both
--             sides) and a giant brass cartridge with its copper bullet standing at the end of the line
--   pizza     Luigi's Pizza (every pizzeria venue): a giant slice leaning to the street, pepperoni, basil, cheese drips
--   gearvest  the gear stall's GEAR counter (Last Stop Supplies, server/GearStall.luau): 6.11's giant hi-vis courier
--             vest from Last Stop's old roof at half size, on a hanger turning on a pole (6.12.6; the shoe is gone)
--   zdcbag    the gear stall's BAGS counter (ZDC Bags): a giant red ZDC insulated delivery bag on a turntable, the ZDC
--             logo front and back, a reflective strip round it, two straps up to a padded grip (6.12.6)
--   bikes     Spoke & Chain Cycles: a giant bicycle on a pylon (spoked wheels, chain, saddle), a parcel in its basket
--   dealer    Dead End Motors: a two-tone 50s car tipped up on a pylon, bunting down to the roof
--   mechanic  Wrench Garage: a giant wrench across a big tyre standing in chocks
--   depot     the ZDC depot: a giant parcel on a pallet, packing tape, the red ZDC logo front and back, a label
--   bank      First Zombie Bank: a giant gold coin with a $ on both faces, on the dome (it spins on the clients)
--   clinic    City Clinic: a big 3D red cross with a white rim, neon inner stripes and a heartbeat line under it
-- A piece's `night`/`lit`: it glows in that colour at night (DayNight.nightLight; ShopProps hands the colour over),
-- `light`: a warm PointLight in it at night (one at most per prop), `moves`: the prop's one moving group (Art.Motion,
-- animated by client/ShopPropMotion.luau). Only big pieces cast shadows. Art.Mounts: where each stands on its building
-- (the World builder's frame; the stall's two: GearStall's frame); tools/polish-art/check.py shops proves the fit: on
-- the roof, behind the name board, clear of the roof units, every part inside Art.Envelopes (and the stall's: over
-- their counters, sized to the stall, clear of the depot hall and the JOBS booth, through the real GearStall.build).
local Art = {}

export type Triple = { number }
export type Piece = {
	name: string, size: Triple, at: Triple, color: Triple, material: string, rotation: Triple?, shape: string?,
	night: boolean?, lit: Triple?, light: number?, shadow: boolean?, moves: boolean?,
}
export type Motion = { kind: string, pivot: Triple, rate: number?, amplitude: number?, period: number?, sway: number? }
-- at: the roof frame in the building's frame (World's `frame` of that building, GearStall's for the stall; y = the
-- roof's top over it);
-- roof: the surface it stands on { x0, z0, x1, z1 }; sign: the name board { its back face's z, its top over the roof };
-- avoid: what already stands there (roof units, a chimney, the helipad) { x0, z0, x1, z1 } each.
export type Mount = { at: Triple, roof: { number }, sign: { number }?, avoid: { { number } } }

-- (6.12.6: "supplies", the vest and the shoe on Last Stop's old roof, is gone: its vest stands over the gear stall's
-- GEAR counter as "gearvest", the ZDC bag over BAGS as "zdcbag"; that roof is bare.)
Art.ids = { "guns", "pizza", "gearvest", "zdcbag", "bikes", "dealer", "mechanic", "depot", "bank", "clinic" }
Art.Budgets = { guns = 160, pizza = 120, gearvest = 60, zdcbag = 60, bikes = 120, dealer = 120, mechanic = 120, depot = 120, bank = 120, clinic = 120 }
-- The box each prop stays in (moving pieces included, through their whole motion): x within ±W/2, y 0 … H, z within ±D/2.
Art.Envelopes = {
	guns = { 49.6, 20, 9.4 }, pizza = { 17.2, 17, 8.6 }, gearvest = { 7, 10.2, 7 }, zdcbag = { 7, 10, 7 }, bikes = { 23.2, 19, 6.4 },
	dealer = { 25.2, 17.2, 13.8 }, mechanic = { 20.8, 18.8, 8.4 }, depot = { 21.2, 19, 18.6 }, bank = { 13.4, 18, 13.4 },
	clinic = { 14.8, 20, 10.6 },
}
Art.Motion = {
	pizza = { kind = "bob", pivot = { 0.4, 8.2, 0 }, amplitude = 0.35, period = 3.2, sway = 2.5 },
	bank = { kind = "spin", pivot = { 0, 11, 0 }, rate = 0.6 },
	gearvest = { kind = "spin", pivot = { 0, 3.2, 0 }, rate = 0.5 }, -- (about 13 s a turn)
	zdcbag = { kind = "spin", pivot = { 0, 3.4, 0 }, rate = 0.4 }, -- (about 16 s: the two never turn in step)
} :: { [string]: Motion }
Art.Mounts = {
	-- Lead & Co. (World buildGuns: 60 × 46 × 16); its board LEAD & CO. GUNS on the roof's front edge.
	guns = { at = { 0, 17, -17 }, roof = { -31, -24, 31, 24 }, sign = { -22.75, 6 }, avoid = { { 17, 7, 23, 13 } } },
	-- Luigi's (World buildVenue: Map.VenueSize 30 × 24 × 12). (6.11: the look's little RoofPizza disc, BuildingLooks/
	-- VenuePizzeria, is gone: the slice took its place.)
	pizza = { at = { 1, 13, -7 }, roof = { -16, -13, 16, 13 }, sign = { -13.05, 2.8 }, avoid = { { 7, 5.5, 11, 8.5 }, { 7.7, 7.7, 10.3, 10.3 } } },
	-- The gear stall at the spawn (server/GearStall.luau, Config.GearStall: 26 × 9 × 10, its roof 27 × 10 and 0.5 thick,
	-- the board LAST STOP SUPPLIES · ZDC BAGS 3.2 tall on its front edge, its back face at -D/2 + 0.8): one prop over each
	-- counter (±Config.GearStall.Counter; GEAR at +X, the south), just behind the board, clear of each other.
	gearvest = { at = { 6.5, 10.5, 0.3 }, roof = { -13.5, -5, 13.5, 5 }, sign = { -3.7, 3.2 }, avoid = { { -10, -3.2, -3, 3.8 } } },
	zdcbag = { at = { -6.5, 10.5, 0.3 }, roof = { -13.5, -5, 13.5, 5 }, sign = { -3.7, 3.2 }, avoid = { { 3, -3.2, 10, 3.8 } } },
	-- Spoke & Chain (World buildBikeShop: 60 × 40 × 16; its board 0.8 in front of the front wall).
	bikes = { at = { 0, 17, -16 }, roof = { -31, -21, 31, 21 }, sign = { -20.55, 5.2 }, avoid = {} },
	-- Dead End Motors (World buildDealer: 84 × 52 × 18).
	dealer = { at = { 0, 19, -18.5 }, roof = { -43, -27, 43, 27 }, sign = { -25.75, 7 }, avoid = { { 23, 8.5, 33, 15.5 }, { -33, 8.5, -23, 15.5 } } },
	-- Wrench Garage (World buildMechanic: 70 × 60 × 20).
	mechanic = { at = { 0, 21, -24.5 }, roof = { -36, -31, 36, 31 }, sign = { -29.75, 6 }, avoid = { { 21, 9, 29, 15 }, { -29, 9, -21, 15 } } },
	-- The depot (World buildDepot: 80 × 40 × 22, its roof 2 thick; the frame of its Kit: turned to face the street).
	depot = { at = { 0, 24, -7.8 }, roof = { -40, -20, 40, 20 }, sign = { -17.5, 8 }, avoid = { { 23.5, 6.5, 32.5, 13.5 }, { -32.5, 6.5, -23.5, 13.5 } } },
	-- First Zombie Bank (World buildBank: 72 × 56 × 24): on the top of the copper dome (a Ball 16 at h + 8.7, z 6),
	-- sunk 0.4 into it. (On the flat roof instead: { -22, 25, -16 }.)
	bank = { at = { 0, 40.3, 6 }, roof = { -8, -2, 8, 14 }, avoid = {} },
	-- City Clinic (World buildClinic: 84 × 56 × 26): where the old flat roof cross stood (6.11: World took out its
	-- CrossPost, CrossSign and red cross), behind the CITY CLINIC board at x -28, clear of the helipad. (At the board's
	-- other end instead: { 30, 27, -20 }.)
	clinic = { at = { -28, 27, -22 }, roof = { -43, -29, 43, 29 }, sign = { -27.75, 5.5 }, avoid = { { -3, -7, 23, 19 }, { 29.2, 11.2, 36.8, 16.8 }, { -36.8, 11.2, -29.2, 16.8 } } },
} :: { [string]: Mount }

-- ── Frames ─────────────────────────────────────────────────────────────────
-- A rotation is a row-major 3 × 3 matrix; a Group a frame (origin, rotation, scale) that pieces and other groups are
-- put in (a scaled group draws its pieces in its own units: positions and sizes times s).
-- Euler angles are Builder's (degrees, CFrame.Angles: R = Rx · Ry · Rz).
type M3 = { number }
type Group = { o: Triple, m: M3, s: number }

local function rot(r: Triple): M3
	local x, y, z = math.rad(r[1]), math.rad(r[2]), math.rad(r[3])
	local sx, cx, sy, cy, sz, cz = math.sin(x), math.cos(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
	return { cy * cz, -cy * sz, sy, cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy, sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy }
end

local function mul(a: M3, b: M3): M3
	local out: M3 = table.create(9, 0)
	for i = 0, 2 do
		for j = 0, 2 do
			out[i * 3 + j + 1] = a[i * 3 + 1] * b[j + 1] + a[i * 3 + 2] * b[j + 4] + a[i * 3 + 3] * b[j + 7]
		end
	end
	return out
end

local function apply(m: M3, v: Triple): Triple
	return { m[1] * v[1] + m[2] * v[2] + m[3] * v[3], m[4] * v[1] + m[5] * v[2] + m[6] * v[3], m[7] * v[1] + m[8] * v[2] + m[9] * v[3] }
end

local function round(x: number): number
	local r = math.round(x * 10000) / 10000
	return if r == 0 then 0 else r -- (no -0 in the data)
end

local function euler(m: M3): Triple
	local sy = math.clamp(m[3], -1, 1)
	if math.abs(sy) > 0.99999 then -- (straight up or down: the turn about Z folds into X)
		local rx = if sy > 0 then math.atan2(m[4], m[5]) else math.atan2(-m[4], m[5])
		return { round(math.deg(rx)), if sy > 0 then 90 else -90, 0 }
	end
	return { round(math.deg(math.atan2(-m[6], m[9]))), round(math.deg(math.asin(sy))), round(math.deg(math.atan2(-m[2], m[1]))) }
end

local ORIGIN: Group = { o = { 0, 0, 0 }, m = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, s = 1 }

-- A frame inside a frame: at `at` of g, turned by r (Euler degrees) on top of g's turn, its units `scale` times g's.
local function child(g: Group, at: Triple, r: Triple?, scale: number?): Group
	local o = apply(g.m, { at[1] * g.s, at[2] * g.s, at[3] * g.s })
	return { o = { g.o[1] + o[1], g.o[2] + o[2], g.o[3] + o[3] }, m = if r then mul(g.m, rot(r)) else g.m, s = g.s * (scale or 1) }
end

-- The prop being drawn (Art.pieces fills it; one at a time).
local list: { Piece } = {}
local moving = false

local function put(g: Group, name: string, size: Triple, at: Triple, color: Triple, material: string, shape: string?, r: Triple?): Piece
	local spot = child(g, at, r)
	local turn = euler(spot.m)
	size = { size[1] * g.s, size[2] * g.s, size[3] * g.s }
	local sorted = table.clone(size)
	table.sort(sorted)
	local piece: Piece = {
		name = name,
		size = size,
		at = { round(spot.o[1]), round(spot.o[2]), round(spot.o[3]) },
		color = color,
		material = material,
		shape = shape,
		rotation = if turn[1] == 0 and turn[2] == 0 and turn[3] == 0 then nil else turn,
		shadow = if sorted[3] >= 4 and sorted[2] >= 3 then true else nil, -- only the big pieces
		moves = if moving then true else nil,
	}
	table.insert(list, piece)
	return piece
end

local function glow(piece: Piece, lit: Triple): Piece
	piece.night = true
	piece.lit = lit
	return piece
end

-- An upright cylinder (Roblox's cylinders lie along X): `height` tall, its middle at `at`.
local function upright(g: Group, name: string, height: number, diameter: number, at: Triple, color: Triple, material: string): Piece
	return put(g, name, { height, diameter, diameter }, at, color, material, "Cylinder", { 0, 0, 90 })
end

-- A disc facing the street (its axis along Z).
local function disc(g: Group, name: string, thickness: number, diameter: number, at: Triple, color: Triple, material: string): Piece
	return put(g, name, { thickness, diameter, diameter }, at, color, material, "Cylinder", { 0, 90, 0 })
end

-- A round bar (a tube) from a to b in g's XY plane at depth z.
local function tube(g: Group, name: string, a: { number }, b: { number }, z: number, diameter: number, color: Triple, material: string): Piece
	local dx, dy = b[1] - a[1], b[2] - a[2]
	return put(g, name, { math.sqrt(dx * dx + dy * dy), diameter, diameter }, { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, z }, color, material, "Cylinder", { 0, 0, math.deg(math.atan2(dy, dx)) })
end

-- A square bar from a to b in g's XY plane (thickness × depth across it).
local function bar(g: Group, name: string, a: { number }, b: { number }, z: number, thickness: number, depth: number, color: Triple, material: string): Piece
	local dx, dy = b[1] - a[1], b[2] - a[2]
	return put(g, name, { math.sqrt(dx * dx + dy * dy), thickness, depth }, { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, z }, color, material, nil, { 0, 0, math.deg(math.atan2(dy, dx)) })
end

-- ── Block letters ──────────────────────────────────────────────────────────
-- Strokes in a 3.6 × 5 cell (u to the reader's right, v up; the corners of the round letters left out, the way a pixel
-- font draws them, so an S never reads as a 5): a rectangle { u0, v0, u1, v1 } or a slanted bar
-- { ua, va, ub, vb, width } (its middle line from a to b; a hair proud, so it never flickers where it crosses).
local GLYPHS: { [string]: { { number } } } = {
	G = { { 0, 1, 1, 4 }, { 1, 4, 3.6, 5 }, { 1, 0, 3.6, 1 }, { 2.6, 1, 3.6, 2.6 }, { 1.8, 1.8, 2.6, 2.6 } },
	U = { { 0, 1, 1, 5 }, { 2.6, 1, 3.6, 5 }, { 1, 0, 2.6, 1 } },
	N = { { 0, 0, 1, 5 }, { 2.6, 0, 3.6, 5 }, { 1.05, 4.75, 2.55, 0.25, 1.05 } },
	S = { { 1, 4, 3.6, 5 }, { 0, 3, 1, 4 }, { 1, 2, 2.6, 3 }, { 2.6, 1, 3.6, 2 }, { 0, 0, 2.6, 1 } },
	T = { { 0, 4, 3.6, 5 }, { 1.3, 0, 2.3, 4 } },
	O = { { 0, 1, 1, 4 }, { 2.6, 1, 3.6, 4 }, { 1, 4, 2.6, 5 }, { 1, 0, 2.6, 1 } },
	R = { { 0, 0, 1, 5 }, { 1, 4, 3, 5 }, { 2.6, 2.9, 3.6, 4.3 }, { 1, 2, 3, 3 }, { 2, 1.95, 3.1, 0.3, 1 } },
	E = { { 0, 0, 1, 5 }, { 1, 4, 3.6, 5 }, { 1, 2, 3, 3 }, { 1, 0, 3.6, 1 } },
	Z = { { 0, 4, 3.6, 5 }, { 0, 0, 3.6, 1 }, { 2.75, 3.95, 0.85, 1.05, 1.1 } },
	D = { { 0, 0, 1, 5 }, { 1, 4, 2.7, 5 }, { 1, 0, 2.7, 1 }, { 2.6, 0.8, 3.6, 4.2 } },
	C = { { 0, 0.8, 1, 4.2 }, { 0.7, 4, 3.6, 5 }, { 0.7, 0, 3.6, 1 } },
	["$"] = { { 1, 4, 3.6, 5 }, { 0, 3, 1, 4 }, { 1, 2, 2.6, 3 }, { 2.6, 1, 3.6, 2 }, { 0, 0, 2.6, 1 }, { 1.4, 5, 2.2, 5.8 }, { 1.4, -0.8, 2.2, 0 } },
}
local GLYPH_W, GLYPH_H, GLYPH_GAP, GLYPH_SPACE = 3.6, 5, 0.7, 2.2

local function textWidth(s: string): number
	local width = 0
	for i = 1, #s do
		width += if string.sub(s, i, i) == " " then GLYPH_SPACE else GLYPH_W
		if i < #s then
			width += GLYPH_GAP
		end
	end
	return width
end

-- A line of letters in g: g's origin is the middle of the line on the face they stand on, g's +X the reading direction,
-- +Z toward the reader (the letters stand `depth` out of the face).
local function text(g: Group, name: string, s: string, scale: number, depth: number, color: Triple, material: string, lit: Triple?)
	local u = -textWidth(s) * scale / 2
	for i = 1, #s do
		local char = string.sub(s, i, i)
		if char ~= " " then
			for n, stroke in assert(GLYPHS[char], "No block letter for this character") do
				local cu, cv = (stroke[1] + stroke[3]) / 2 * scale, ((stroke[2] + stroke[4]) / 2 - GLYPH_H / 2) * scale
				local piece: Piece
				if #stroke == 4 then
					piece = put(g, `{name}{i}_{n}`, { (stroke[3] - stroke[1]) * scale, (stroke[4] - stroke[2]) * scale, depth }, { u + cu, cv, depth / 2 }, color, material)
				else
					local du, dv = (stroke[3] - stroke[1]) * scale, (stroke[4] - stroke[2]) * scale
					piece = put(g, `{name}{i}_{n}`, { math.sqrt(du * du + dv * dv), stroke[5] * scale, depth + 0.06 }, { u + cu, cv, (depth + 0.06) / 2 }, color, material, nil, { 0, 0, math.deg(math.atan2(dv, du)) })
				end
				if lit then
					glow(piece, lit)
				end
			end
		end
		u += ((if char == " " then GLYPH_SPACE else GLYPH_W) + GLYPH_GAP) * scale
	end
end

-- Two wedges making a flat triangle in g's XY plane (thickness along Z, its middle at z): the apex at (0, apexV), the
-- base from (-half, baseV) to (half, baseV), baseV above apexV.
local function triangle(g: Group, name: string, half: number, apexV: number, baseV: number, z: number, thickness: number, color: Triple, material: string)
	local length, middle = baseV - apexV, (apexV + baseV) / 2
	put(g, name .. "R", { thickness, half, length }, { half / 2, middle, z }, color, material, "Wedge", { -90, 0, -90 })
	put(g, name .. "L", { thickness, half, length }, { -half / 2, middle, z }, color, material, "Wedge", { -90, 0, 90 })
end

-- ── The colours ────────────────────────────────────────────────────────────
local DARK, STEEL, CHROME = { 34, 36, 40 }, { 86, 90, 96 }, { 204, 208, 214 }
local WARM = { 255, 226, 170 } -- (a lamp's glow)
local ZDC_RED = { 215, 74, 70 } -- the company's red square (World's name boards)
local CARDBOARD = { 198, 152, 98 }

-- A little floodlight on the roof in front of a prop: a dark housing whose face glows, its warm light at night.
local function floodlight(g: Group, at: Triple, range: number)
	local lamp = put(g, "Floodlight", { 1.4, 0.5, 0.9 }, at, { 70, 72, 76 }, "Metal")
	glow(lamp, WARM).light = range
end

-- ── The props ──────────────────────────────────────────────────────────────

local function guns()
	local px, py = 3.2, 11.35 -- the marquee's middle
	local panel = child(ORIGIN, { px, py, 0 })
	local scale = 1.1
	local width = textWidth("GUN STORE") * scale + 2.4
	put(panel, "Marquee", { width, 7.5, 0.6 }, { 0, 0, 0 }, { 30, 32, 36 }, "Metal")
	-- The letters on both faces (a dark spine between them), a red pinstripe over and under them, bulbs on both edges.
	local letter, letterLit = { 242, 190, 62 }, { 255, 214, 110 }
	text(child(panel, { 0, 0, -0.3 }, { 0, 180, 0 }), "Front", "GUN STORE", scale, 0.7, letter, "SmoothPlastic", letterLit)
	text(child(panel, { 0, 0, 0.3 }), "Back", "GUN STORE", scale, 0.7, letter, "SmoothPlastic", letterLit)
	for _, side in { -1, 1 } do
		for n, y in { -3.25, 3.25 } do
			put(panel, `Pinstripe{side}{n}`, { width - 2, 0.3, 0.1 }, { 0, y, side * 0.35 }, { 186, 44, 38 }, "SmoothPlastic")
		end
	end
	for row, y in { 3.95, -3.95 } do
		for n = -6, 6 do
			glow(put(panel, `Bulb{row}_{n + 7}`, { 0.7, 0.7, 0.7 }, { n * 3.3, y, 0 }, { 236, 226, 196 }, "Glass", "Ball"), { 255, 236, 176 })
		end
	end
	-- Two posts, braces back to the roof, feet.
	for n, side in { -1, 1 } do
		local x = px + side * 14.85
		put(ORIGIN, `Post{n}`, { 0.9, 7.9, 0.9 }, { x, 3.95, 0 }, STEEL, "Metal")
		put(ORIGIN, `Foot{n}`, { 2, 0.3, 2 }, { x, 0.15, 0 }, DARK, "Metal")
		put(ORIGIN, `Brace{n}`, { 0.5, 7.16, 0.5 }, { x, 3.35, 2.325 }, STEEL, "Metal", nil, { -31.6, 0, 0 })
	end
	-- The cartridge at the end of the line (the reader's right), 19.5 tall: a rifle round standing on its base, brass case,
	-- extractor groove and rim, a stepped shoulder, the copper bullet, a shine down its front.
	local cx = px - width / 2 - 3.6
	local case = child(ORIGIN, { cx, 0, 0 }, nil, 1.15) -- (taller than the marquee)
	local brass, brassDark, copper = { 222, 174, 74 }, { 184, 136, 56 }, { 196, 104, 58 }
	upright(case, "CaseStand", 0.5, 5, { 0, 0.25, 0 }, DARK, "Metal")
	upright(case, "CaseRim", 0.6, 4.7, { 0, 0.8, 0 }, brassDark, "Metal")
	upright(case, "CaseGroove", 0.5, 4, { 0, 1.35, 0 }, { 150, 108, 44 }, "Metal")
	upright(case, "CaseBody", 8.6, 4.5, { 0, 5.9, 0 }, brass, "Metal")
	upright(case, "Shoulder1", 0.5, 4, { 0, 10.45, 0 }, brass, "Metal")
	upright(case, "Shoulder2", 0.5, 3.4, { 0, 10.95, 0 }, brass, "Metal")
	upright(case, "Shoulder3", 0.5, 2.8, { 0, 11.45, 0 }, brass, "Metal")
	upright(case, "CaseNeck", 1.5, 2.5, { 0, 12.45, 0 }, brass, "Metal")
	upright(case, "Crimp", 0.25, 2.6, { 0, 13.1, 0 }, brassDark, "Metal")
	upright(case, "Bullet1", 1.2, 2.4, { 0, 13.8, 0 }, copper, "Metal")
	upright(case, "Bullet2", 0.8, 2.2, { 0, 14.8, 0 }, copper, "Metal")
	upright(case, "Bullet3", 0.7, 1.85, { 0, 15.55, 0 }, copper, "Metal")
	upright(case, "Bullet4", 0.6, 1.4, { 0, 16.2, 0 }, copper, "Metal")
	put(case, "BulletTip", { 1, 1, 1 }, { 0, 16.5, 0 }, copper, "Metal", "Ball")
	put(case, "CaseShine", { 0.35, 7.6, 0.12 }, { 0.9, 5.9, -2.08 }, { 255, 236, 170 }, "SmoothPlastic")
	put(case, "BulletShine", { 0.25, 2.2, 0.1 }, { 0.5, 14.3, -1.08 }, { 240, 168, 120 }, "SmoothPlastic")
	floodlight(case, { 0, 0.25, -3.4 }, 14)
end

local function pizza()
	-- The slice in its own plane (u across, v from the tip up to the crust, -Z its face), leaning 12° to the street and
	-- turned 14° (the tip to the reader's left); everything on it moves together (it bobs).
	moving = true
	local slice = child(ORIGIN, { 0.4, 8.2, 0 }, { -12, 0, 14 })
	local cheese, crust = { 252, 196, 64 }, { 204, 136, 64 }
	triangle(slice, "Bread", 5.6, -6, 6, 0.35, 0.7, { 222, 170, 96 }, "SmoothPlastic")
	triangle(slice, "Cheese", 5.25, -5.3, 6, -0.225, 0.45, cheese, "SmoothPlastic")
	-- The crust along the wide end: an arc of three rolls with round joints and ends.
	put(slice, "CrustMid", { 4.6, 2.3, 2.3 }, { 0, 6.5, 0.15 }, crust, "SmoothPlastic", "Cylinder")
	for n, side in { -1, 1 } do
		put(slice, `CrustSide{n}`, { 3.75, 2.3, 2.3 }, { side * 4.15, 6.2, 0.15 }, crust, "SmoothPlastic", "Cylinder", { 0, 0, -side * 9.2 })
		put(slice, `CrustJoint{n}`, { 2.3, 2.3, 2.3 }, { side * 2.3, 6.5, 0.15 }, crust, "SmoothPlastic", "Ball")
		put(slice, `CrustEnd{n}`, { 2.3, 2.3, 2.3 }, { side * 6, 5.9, 0.15 }, crust, "SmoothPlastic", "Ball")
	end
	-- Toppings on the cheese: pepperoni, basil, melted bubbles.
	for n, p in { { -2.2, 2.9, 2.3 }, { 2.4, 3.8, 2.2 }, { 0.2, 0, 2 }, { -0.15, -2.9, 1.1 } } do
		disc(slice, `Pepperoni{n}`, 0.3, p[3], { p[1], p[2], -0.6 }, { 170, 40, 32 }, "SmoothPlastic")
	end
	for n, p in { { 1.6, 1.6, 35 }, { -3.4, 4.6, -25 } } do
		put(slice, `Basil{n}`, { 1.2, 0.6, 0.12 }, { p[1], p[2], -0.52 }, { 60, 132, 52 }, "SmoothPlastic", nil, { 0, 0, p[3] })
	end
	for n, p in { { 0.9, -1.4 }, { -1, 1 }, { 0.6, 4.9 } } do
		put(slice, `Bubble{n}`, { 0.8, 0.8, 0.8 }, { p[1], p[2], -0.45 }, { 255, 220, 120 }, "SmoothPlastic", "Ball")
	end
	-- Cheese dripping straight down from the tip and from the lower edge.
	for n, from in { { 0, -5.2, -0.25, 2, 0.55, 0.95 }, { -2.55, 0.5, -0.25, 1.5, 0.6, 1 } } do
		local o = child(slice, { from[1], from[2], from[3] }).o
		upright(ORIGIN, `Drip{n}`, from[4], from[5], { o[1], o[2] - from[4] / 2 + 0.1, o[3] }, cheese, "SmoothPlastic")
		put(ORIGIN, `DripDrop{n}`, { from[6], from[6], from[6] }, { o[1], o[2] - from[4] + 0.1, o[3] }, cheese, "SmoothPlastic", "Ball")
	end
	moving = false
	-- The stand behind it (the arm runs into the bread, so the bob never shows a gap).
	upright(ORIGIN, "Post", 7.3, 0.9, { 0.4, 3.65, 2.6 }, STEEL, "Metal")
	put(ORIGIN, "Arm", { 0.7, 0.7, 2.3 }, { 0.4, 7.6, 1.65 }, STEEL, "Metal")
	put(ORIGIN, "Base", { 3, 0.3, 3 }, { 0.4, 0.15, 2.6 }, DARK, "Metal")
	floodlight(ORIGIN, { 0.4, 0.25, -2.6 }, 14)
end

-- The hi-vis courier vest in g (its hem at g's origin, 12.15 tall, 11.1 across, front -Z; 6.11's rooftop vest over Last
-- Stop): two front panels zipped in the middle, shoulder straps with the V of the neck and the armholes, the back, the
-- sides, the ZDC badge on the chest, reflective stripes over the shoulders and round it (6.12.6: round the sides too, it
-- turns now), all glowing at night.
local function courierVest(vest: Group)
	local orange, silver, silverLit = { 255, 112, 28 }, { 206, 210, 214 }, { 236, 242, 248 }
	for n, side in { -1, 1 } do
		put(vest, `FrontLower{n}`, { 5.4, 6.6, 0.5 }, { side * 2.7, 3.3, -1.4 }, orange, "Fabric")
		put(vest, `FrontUpper{n}`, { 2.8, 5.2, 0.5 }, { side * 2.8, 9.2, -1.4 }, orange, "Fabric")
		put(vest, `Neck{n}`, { 0.5, 2.6, 1.4 }, { side * 0.7, 7.9, -1.4 }, orange, "Fabric", "Wedge", { 0, side * 90, 0 })
		put(vest, `Armhole{n}`, { 0.5, 2, 1.2 }, { side * 4.8, 7.6, -1.4 }, orange, "Fabric", "Wedge", { 0, -side * 90, 0 })
		put(vest, `Side{n}`, { 0.5, 6.6, 2.8 }, { side * 5.15, 3.3, 0 }, orange, "Fabric")
		put(vest, `BackStrap{n}`, { 2.8, 1, 0.5 }, { side * 2.8, 11.3, 1.4 }, orange, "Fabric")
		put(vest, `Shoulder{n}`, { 2.8, 0.4, 3.3 }, { side * 2.8, 11.95, 0 }, orange, "Fabric")
		for k, y in { 1.7, 4.6 } do
			glow(put(vest, `SideStripe{n}_{k}`, { 0.15, 0.9, 2.9 }, { side * 5.47, y, 0 }, silver, "Metal"), silverLit)
		end
		for k, z in { -1.78, 1.78 } do
			glow(put(vest, `StripeUp{n}_{k}`, { 0.9, 6.85, 0.15 }, { side * 2.8, 8.475, z }, silver, "Metal"), silverLit)
		end
	end
	put(vest, "Zip", { 0.3, 6.6, 0.2 }, { 0, 3.3, -1.7 }, { 60, 60, 64 }, "Metal")
	put(vest, "BackLower", { 10.8, 6.6, 0.5 }, { 0, 3.3, 1.4 }, orange, "Fabric")
	put(vest, "BackUpper", { 8.4, 4.2, 0.5 }, { 0, 8.7, 1.4 }, orange, "Fabric")
	for k, y in { 1.7, 4.6 } do
		for n, z in { -1.78, 1.78 } do
			glow(put(vest, `StripeRound{k}_{n}`, { 10.9, 0.9, 0.15 }, { 0, y, z }, silver, "Metal"), silverLit)
		end
	end
	put(vest, "CourierBadge", { 1.2, 1.2, 0.08 }, { 3, 3.15, -1.7 }, ZDC_RED, "SmoothPlastic")
end

local function gearvest()
	-- The vest at half size (6 tall, 5.5 across) on a hanger: a bar inside its shoulders, the hook out of the neck. The
	-- hanger and the vest turn (Art.Motion) about the pole they stand on (its top hidden inside the vest, under the V of
	-- the neck), its foot on the stall's roof; the hem 3.2 up, level with the top of the stall's board, the hook's top
	-- 10 up. A floodlight behind the board lights it at night.
	put(ORIGIN, "Foot", { 2.2, 0.3, 2.2 }, { 0, 0.15, 0 }, DARK, "Metal")
	upright(ORIGIN, "Pole", 5.9, 0.35, { 0, 3.25, 0 }, STEEL, "Metal")
	moving = true
	local vest = child(ORIGIN, { 0, 3.2, 0 }, nil, 0.5)
	courierVest(vest)
	put(vest, "HangerBar", { 8, 0.3, 0.3 }, { 0, 11.6, 0 }, CHROME, "Metal")
	upright(vest, "HookStem", 1.4, 0.3, { 0, 12.4, 0 }, CHROME, "Metal")
	tube(vest, "HookArc", { 0, 13.1 }, { 0.7, 13.45 }, 0, 0.3, CHROME, "Metal")
	put(vest, "HookBend", { 0.3, 0.3, 0.3 }, { 0.7, 13.45, 0 }, CHROME, "Metal", "Ball")
	tube(vest, "HookTip", { 0.7, 13.45 }, { 1.1, 13 }, 0, 0.3, CHROME, "Metal")
	moving = false
	floodlight(ORIGIN, { 0, 0.25, -3 }, 10)
end

local function zdcbag()
	-- The shop's Thermal Delivery Bag (server/KitArt/Geometry.luau "thermal") 5 studs wide: red nylon, black piping down
	-- its corners, a black base and a black zip-round lid; the ZDC logo on the front and the back (the red square and ZDC
	-- in white block letters on a black patch, as on the name boards), a reflective strip round it under the logo (the
	-- logo and the strip glow at night), two straps from the lid up to a padded grip. It turns on a turntable on a short
	-- post (Art.Motion); its bottom 3.4 over the stall's roof, just over the top of the board (3.2: the strip and the logo
	-- in sight from the spawn), the grip's top 9.6.
	put(ORIGIN, "Foot", { 2.4, 0.3, 2.4 }, { 0, 0.15, 0 }, DARK, "Metal")
	upright(ORIGIN, "Post", 2.85, 0.8, { 0, 1.725, 0 }, STEEL, "Metal")
	moving = true
	upright(ORIGIN, "Turntable", 0.25, 4.8, { 0, 3.275, 0 }, DARK, "Metal")
	local bag = child(ORIGIN, { 0, 3.4, 0 })
	local red, black, silver, silverLit = { 196, 38, 34 }, { 30, 31, 34 }, { 206, 210, 214 }, { 236, 242, 248 }
	put(bag, "Base", { 5.16, 0.35, 4.16 }, { 0, 0.175, 0 }, black, "Fabric")
	put(bag, "Body", { 5, 4, 4 }, { 0, 2.35, 0 }, red, "Fabric")
	put(bag, "Zip", { 5.08, 0.12, 4.08 }, { 0, 4.41, 0 }, { 150, 152, 156 }, "Metal")
	put(bag, "Lid", { 5.16, 0.45, 4.16 }, { 0, 4.695, 0 }, black, "Fabric")
	for k, corner in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		put(bag, `Piping{k}`, { 0.14, 4, 0.14 }, { corner[1] * 2.5, 2.35, corner[2] * 2 }, black, "Fabric")
	end
	for n, side in { -1, 1 } do
		glow(put(bag, `Strip{n}`, { 5.16, 0.4, 0.08 }, { 0, 1.35, side * 2.04 }, silver, "Metal"), silverLit)
		glow(put(bag, `StripSide{n}`, { 0.08, 0.4, 4 }, { side * 2.54, 1.35, 0 }, silver, "Metal"), silverLit)
	end
	-- The logo (front: n = 1 at -Z, read from there; back: n = 2): the patch, the red square, ZDC beside it.
	local redLit, white, whiteLit = { 255, 70, 60 }, { 248, 246, 240 }, { 255, 255, 255 }
	local letters = textWidth("ZDC") * 0.24
	local start = -(1.25 + 0.25 + letters) / 2
	for n, side in { -1, 1 } do
		local face = child(bag, { 0, 2.85, side * 2 }, if side < 0 then { 0, 180, 0 } else nil)
		put(face, `LogoPatch{n}`, { 4.6, 1.9, 0.08 }, { 0, 0, 0.04 }, black, "SmoothPlastic")
		glow(put(face, `LogoSquare{n}`, { 1.25, 1.25, 0.06 }, { start + 0.625, 0, 0.11 }, ZDC_RED, "SmoothPlastic"), redLit)
		text(child(face, { start + 1.5 + letters / 2, 0, 0.08 }), `Logo{n}_`, "ZDC", 0.24, 0.1, white, "SmoothPlastic", whiteLit)
	end
	-- The straps and the grip.
	for n, side in { -1, 1 } do
		bar(bag, `Strap{n}`, { side * 2.1, 4.85 }, { side * 0.75, 5.85 }, 0, 0.22, 0.9, black, "Fabric")
	end
	put(bag, "Grip", { 1.7, 0.6, 0.6 }, { 0, 5.9, 0 }, black, "Rubber", "Cylinder")
	moving = false
	floodlight(ORIGIN, { 0, 0.25, -3 }, 10)
end

local function bikes()
	-- A city bike in the XY plane (its front to the reader's right), hubs 9.9 over the roof, on a pylon under its
	-- bottom bracket. Wheels: a tyre of 16 pieces, a rim of 12, six spokes through the hub.
	local bike = child(ORIGIN, { 0, 9.9, 0 })
	local frame, silver, black = { 232, 86, 62 }, { 190, 192, 196 }, { 30, 30, 32 }
	local r = 4.4
	for w, hub in { { -6.5, 0 }, { 6.5, 0 } } do
		for k = 1, 16 do
			local a = math.rad((k - 0.5) * 22.5)
			put(bike, `Tyre{w}_{k}`, { 2 * r * math.tan(math.rad(11.25)) + 0.1, 0.7, 0.7 }, { hub[1] + r * math.cos(a), hub[2] + r * math.sin(a), 0 }, black, "Rubber", nil, { 0, 0, (k - 0.5) * 22.5 + 90 })
		end
		for k = 1, 12 do
			local a = math.rad((k - 0.5) * 30)
			put(bike, `Rim{w}_{k}`, { 2 * 3.85 * math.tan(math.rad(15)) + 0.08, 0.3, 0.45 }, { hub[1] + 3.85 * math.cos(a), hub[2] + 3.85 * math.sin(a), 0 }, silver, "Metal", nil, { 0, 0, (k - 0.5) * 30 + 90 })
		end
		for k = 0, 5 do
			put(bike, `Spoke{w}_{k + 1}`, { 7.4, 0.15, 0.15 }, { hub[1], hub[2], 0 }, silver, "Metal", nil, { 0, 0, k * 30 + 15 })
		end
		disc(bike, `Hub{w}`, 1, 0.9, { hub[1], hub[2], 0 }, silver, "Metal")
	end
	-- The frame.
	local bb, seat, headLow, headTop = { 1.1, -0.9 }, { 3, 5.3 }, { -4.9, 4.9 }, { -4.34, 6.65 }
	tube(bike, "TopTube", { -4.48, 6.2 }, seat, 0, 0.55, frame, "Metal")
	tube(bike, "DownTube", { -4.8, 5.2 }, bb, 0, 0.6, frame, "Metal")
	tube(bike, "SeatTube", bb, seat, 0, 0.55, frame, "Metal")
	tube(bike, "HeadTube", headLow, headTop, 0, 0.75, frame, "Metal")
	for n, side in { -1, 1 } do
		tube(bike, `SeatStay{n}`, { 2.95, 5.1 }, { 6.5, 0 }, side * 0.4, 0.4, frame, "Metal")
		tube(bike, `ChainStay{n}`, bb, { 6.5, 0 }, side * 0.4, 0.4, frame, "Metal")
		tube(bike, `Fork{n}`, headLow, { -6.5, 0 }, side * 0.45, 0.45, frame, "Metal")
		put(bike, `Grip{n}`, { 1.2, 0.6, 0.6 }, { -4.7, 7.6, side * 2.3 }, black, "Rubber", "Cylinder", { 0, 90, 0 })
	end
	put(bike, "ForkCrown", { 0.8, 0.45, 1.4 }, { -4.9, 4.75, 0 }, frame, "Metal")
	tube(bike, "SeatPost", seat, { 3.4, 6.7 }, 0, 0.4, silver, "Metal")
	put(bike, "Saddle", { 2.4, 0.55, 1.4 }, { 3.75, 6.95, 0 }, { 96, 62, 40 }, "Leather")
	put(bike, "SaddleNose", { 1.4, 0.45, 0.7 }, { 2.3, 7, 0 }, { 96, 62, 40 }, "Leather")
	tube(bike, "Stem", headTop, { -4.6, 7.55 }, 0, 0.45, silver, "Metal")
	put(bike, "Handlebar", { 5, 0.4, 0.4 }, { -4.7, 7.6, 0 }, silver, "Metal", "Cylinder", { 0, 90, 0 })
	-- The drive side faces the street: chainring, cranks and pedals, the chain to the rear cog.
	disc(bike, "Chainring", 0.2, 2.6, { bb[1], bb[2], -0.75 }, silver, "Metal")
	disc(bike, "Cog", 0.2, 1, { 6.5, 0, -0.75 }, silver, "Metal")
	bar(bike, "ChainTop", { bb[1], bb[2] + 1.3 }, { 6.5, 0.5 }, -0.75, 0.16, 0.16, { 50, 50, 54 }, "Metal")
	bar(bike, "ChainBottom", { bb[1], bb[2] - 1.3 }, { 6.5, -0.5 }, -0.75, 0.16, 0.16, { 50, 50, 54 }, "Metal")
	for n, side in { -1, 1 } do
		local a = math.rad(-55 + (if side > 0 then 180 else 0))
		local tip = { bb[1] + 1.9 * math.cos(a), bb[2] + 1.9 * math.sin(a) }
		bar(bike, `Crank{n}`, bb, tip, side * 0.95, 0.4, 0.25, silver, "Metal")
		put(bike, `Pedal{n}`, { 1, 0.3, 1 }, { tip[1], tip[2], side * 1.55 }, black, "Metal")
	end
	-- The delivery basket on the front with a parcel in it, the lamps.
	put(bike, "Basket", { 2.8, 2, 3 }, { -6.9, 6.7, 0 }, { 164, 120, 66 }, "WoodPlanks")
	put(bike, "BasketBracket", { 1.4, 0.3, 0.6 }, { -5.05, 6.3, 0 }, silver, "Metal")
	put(bike, "Parcel", { 2, 1.5, 2 }, { -6.9, 7.9, 0 }, CARDBOARD, "Cardboard")
	put(bike, "ParcelTape", { 0.4, 1.55, 2.05 }, { -6.9, 7.9, 0 }, ZDC_RED, "SmoothPlastic")
	glow(put(bike, "HeadLamp", { 0.5, 0.7, 0.7 }, { -8.55, 6.4, 0 }, { 230, 226, 210 }, "Glass", "Cylinder"), { 255, 244, 200 })
	glow(put(bike, "TailLamp", { 0.3, 0.6, 0.6 }, { 3.55, 5.9, 0 }, { 170, 30, 30 }, "Glass"), { 255, 40, 30 })
	-- The pylon.
	upright(ORIGIN, "Pylon", 9, 1, { bb[1], 4.5, 0 }, STEEL, "Metal")
	upright(ORIGIN, "PylonCollar", 0.6, 1.5, { bb[1], 8.6, 0 }, DARK, "Metal")
	put(ORIGIN, "PylonBase", { 4, 0.4, 3 }, { bb[1], 0.2, 0 }, DARK, "Metal")
	floodlight(ORIGIN, { bb[1], 0.25, -2.35 }, 16)
end

local function dealer()
	-- A 50s two-door (20 long), cherry red with a cream roof, tipped nose up 10° and turned 15° to the street on a
	-- pylon. Car frame (1.3 studs a unit): nose to -X, y from the bottom of its body.
	local car = child(ORIGIN, { 0, 11, 0 }, { 0, -15, -10 }, 1.3)
	local paint, cream, glass = { 190, 28, 36 }, { 238, 232, 216 }, { 44, 58, 68 }
	put(car, "Body", { 15, 2, 6.2 }, { 0, 1, 0 }, paint, "SmoothPlastic")
	put(car, "Cabin", { 6, 1.9, 5.2 }, { 0.8, 2.95, 0 }, glass, "Glass")
	put(car, "Roof", { 5.6, 0.35, 5.6 }, { 1, 4.075, 0 }, cream, "SmoothPlastic")
	put(car, "Windscreen", { 5.2, 1.9, 1.3 }, { -2.85, 2.95, 0 }, { 120, 160, 180 }, "Glass", "Wedge", { 0, 90, 0 })
	put(car, "RearWindow", { 5.2, 1.9, 1.3 }, { 4.45, 2.95, 0 }, { 120, 160, 180 }, "Glass", "Wedge", { 0, -90, 0 })
	put(car, "Pillar", { 0.45, 1.9, 5.3 }, { 0.6, 2.95, 0 }, paint, "SmoothPlastic")
	put(car, "Grille", { 0.2, 0.9, 3 }, { -7.55, 1.2, 0 }, { 170, 174, 180 }, "Metal")
	put(car, "HoodOrnament", { 0.7, 0.35, 0.2 }, { -6.4, 2.15, 0 }, CHROME, "Metal")
	for n, side in { -1, 1 } do
		put(car, `Bumper{n}`, { 0.6, 0.7, 6.4 }, { side * 7.75, 0.4, 0 }, CHROME, "Metal")
		put(car, `Fin{n}`, { 0.5, 1.2, 4.4 }, { 5.6, 2.6, side * 2.85 }, paint, "SmoothPlastic", "Wedge", { 0, 90, 0 })
		glow(put(car, `TailLight{n}`, { 0.2, 0.6, 0.5 }, { 7.75, 2.75, side * 2.85 }, { 200, 30, 30 }, "Glass"), { 255, 40, 30 })
		glow(put(car, `HeadLight{n}`, { 0.3, 1, 1 }, { -7.55, 1.35, side * 2.2 }, { 240, 236, 210 }, "Glass", "Cylinder"), { 255, 244, 200 })
		put(car, `Spear{n}`, { 9, 0.18, 0.1 }, { 0.6, 1.55, side * 3.13 }, CHROME, "Metal")
		for k, x in { -4.9, 4.9 } do
			disc(car, `Tyre{n}_{k}`, 1.1, 3, { x, 0.4, side * 2.75 }, { 26, 26, 28 }, "Rubber")
			disc(car, `Whitewall{n}_{k}`, 0.1, 2.3, { x, 0.4, side * 3.36 }, { 240, 240, 236 }, "SmoothPlastic")
			disc(car, `Hubcap{n}_{k}`, 0.14, 1.2, { x, 0.4, side * 3.43 }, CHROME, "Metal")
		end
	end
	put(car, "Cradle", { 6, 0.4, 2.6 }, { 0, -0.2, 0 }, STEEL, "Metal")
	-- The pylon, a floodlight, bunting from the pylon down to the roof on both sides.
	upright(ORIGIN, "Pylon", 10.6, 1.4, { 0, 5.3, 0 }, STEEL, "Metal")
	upright(ORIGIN, "PylonCollar", 0.6, 2.2, { 0, 10.3, 0 }, DARK, "Metal")
	put(ORIGIN, "PylonBase", { 4.4, 0.5, 4.4 }, { 0, 0.25, 0 }, DARK, "Metal")
	floodlight(ORIGIN, { 0, 0.25, -2.9 }, 16)
	local flags = { { 220, 60, 50 }, { 240, 240, 236 }, { 250, 200, 60 }, { 220, 60, 50 } }
	for n, side in { -1, 1 } do
		local from, to = { side * 0.7, 9.8 }, { side * 12.4, 0.6 }
		bar(ORIGIN, `Bunting{n}`, from, to, 0.8, 0.1, 0.1, { 60, 60, 64 }, "Metal")
		local dx, dy = to[1] - from[1], to[2] - from[2]
		local angle = math.deg(math.atan2(dy * side, dx * side)) -- (along the string, its "up" always up)
		for k = 1, 4 do
			local t = k / 5
			-- a pennant under the string: its top edge along it, hanging 1 down (wedge: the right angle at the top)
			local along = child(ORIGIN, { from[1] + dx * t, from[2] + dy * t, 0.8 }, { 0, 0, angle })
			local hang = child(along, { 0, -0.55, 0 }, { 0, 90, 0 })
			put(hang, `Pennant{n}_{k}`, { 0.06, 1, 0.9 }, { 0, 0, 0 }, flags[k], "Fabric", "Wedge", { 0, 0, 180 })
		end
	end
end

local function mechanic()
	-- A big tyre facing the street (axis along Z) in two yellow chocks on a riser, a chrome wrench across its face.
	local tyre = child(ORIGIN, { 0, 10.6, 0 })
	disc(tyre, "Tyre", 4.4, 13.6, { 0, 0, 0 }, { 32, 32, 34 }, "Rubber")
	for k = 0, 17 do
		local a = k * 20
		put(tyre, `Tread{k + 1}`, { 1.4, 0.55, 3.4 }, { 7 * math.cos(math.rad(a)), 7 * math.sin(math.rad(a)), if k % 2 == 0 then 0.35 else -0.35 }, { 44, 44, 46 }, "Rubber", nil, { 0, 0, a + 90 })
	end
	disc(tyre, "Sidewall", 0.1, 12.4, { 0, 0, -2.25 }, { 56, 56, 60 }, "Rubber")
	disc(tyre, "Rim", 0.3, 8.2, { 0, 0, -2.4 }, { 196, 200, 206 }, "Metal")
	disc(tyre, "RimDish", 0.3, 6, { 0, 0, -2.5 }, { 120, 124, 130 }, "Metal")
	glow(disc(tyre, "HubCap", 0.4, 2.6, { 0, 0, -2.7 }, { 70, 150, 210 }, "Metal"), { 120, 200, 255 })
	for k = 0, 4 do
		local a = math.rad(90 + k * 72)
		disc(tyre, `LugNut{k + 1}`, 0.4, 0.55, { 1.95 * math.cos(a), 1.95 * math.sin(a), -2.75 }, CHROME, "Metal")
	end
	disc(tyre, "RimBack", 0.3, 8.2, { 0, 0, 2.4 }, { 196, 200, 206 }, "Metal")
	disc(tyre, "HubBack", 0.4, 2.6, { 0, 0, 2.6 }, { 70, 150, 210 }, "Metal")
	-- The wrench: the ring end down-right (the reader's), the open end up-left (two jaws, the sky between them), 32°.
	local wrench = child(tyre, { 0, 0, -3.3 }, { 0, 0, 32 })
	put(wrench, "Handle", { 10.6, 1.6, 0.7 }, { 0, 0, 0 }, CHROME, "Metal")
	for n, z in { -0.38, 0.38 } do
		put(wrench, `Groove{n}`, { 8, 0.6, 0.1 }, { 0, 0, z }, { 150, 156, 164 }, "Metal")
	end
	put(wrench, "RingNeck", { 1.6, 2.3, 0.7 }, { -6, 0, 0 }, CHROME, "Metal")
	disc(wrench, "Ring", 0.8, 4.4, { -8, 0, 0 }, CHROME, "Metal")
	disc(wrench, "RingHole", 0.9, 2.2, { -8, 0, 0 }, { 24, 24, 26 }, "Metal")
	put(wrench, "OpenNeck", { 1.4, 2.3, 0.7 }, { 6, 0, 0 }, CHROME, "Metal")
	local head = child(wrench, { 7.6, 0, 0 }, { 0, 0, 15 })
	disc(head, "OpenHead", 0.8, 4.2, { -0.6, 0, 0 }, CHROME, "Metal")
	for n, side in { -1, 1 } do
		put(head, `Jaw{n}`, { 1.6, 1.7, 0.8 }, { 1.3, side * 1.5, 0 }, CHROME, "Metal")
		disc(head, `JawTip{n}`, 0.8, 1.7, { 2.1, side * 1.5, 0 }, CHROME, "Metal")
	end
	-- The riser, the chocks on it, a floodlight.
	put(ORIGIN, "Riser", { 12, 2.2, 5.6 }, { 0, 1.1, 0 }, DARK, "Metal")
	for n, side in { -1, 1 } do
		put(ORIGIN, `Chock{n}`, { 4.6, 2.4, 2.4 }, { side * 3.2, 3.4, 0 }, { 230, 180, 40 }, "SmoothPlastic", "Wedge", { 0, -side * 90, 0 })
	end
	floodlight(ORIGIN, { 0, 0.25, -3.6 }, 16)
end

local function depot()
	-- A parcel 17 × 14 × 13 on a pallet on a dock riser (over the depot's tall board), turned 15° (its left end to the
	-- street too): packing tape over the top and down the ends, the ZDC logo (the red square, ZDC in white block
	-- letters) on the front and the back, a shipping label with a barcode, THIS WAY UP arrows on the end.
	local dock = child(ORIGIN, { 0, 0, 0 }, { 0, 15, 0 })
	put(dock, "Riser", { 16, 3.4, 12 }, { 0, 1.7, 0 }, { 60, 64, 70 }, "DiamondPlate")
	local box = child(dock, { 0, 3.4, 0 })
	local wood = { 176, 140, 92 }
	for n, x in { -7.9, 0, 7.9 } do
		put(box, `Stringer{n}`, { 1.4, 0.9, 14 }, { x, 0.45, 0 }, wood, "WoodPlanks")
	end
	for n, z in { -5.4, 0, 5.4 } do
		put(box, `Deck{n}`, { 17.8, 0.3, 3.2 }, { 0, 1.05, z }, wood, "WoodPlanks")
	end
	put(box, "Parcel", { 17, 14, 13 }, { 0, 8.2, 0 }, CARDBOARD, "Cardboard")
	local tape = { 176, 128, 70 }
	put(box, "TapeTop", { 17.1, 0.1, 2.6 }, { 0, 15.25, 0 }, tape, "SmoothPlastic")
	for n, side in { -1, 1 } do
		put(box, `TapeEnd{n}`, { 0.1, 3.6, 2.6 }, { side * 8.55, 13.4, 0 }, tape, "SmoothPlastic")
	end
	local redLit, white = { 255, 70, 60 }, { 248, 246, 240 }
	for n, side in { -1, 1 } do
		-- (front: n = 1 at -Z, its letters read from +X; back: n = 2)
		local face = child(box, { -side * 3.6, 8.6, side * 6.56 })
		glow(put(face, `Logo{n}`, { 7, 7, 0.12 }, { 0, 0, 0 }, ZDC_RED, "SmoothPlastic"), redLit)
		text(child(face, { 0, 0, side * 0.06 }, if side < 0 then { 0, 180, 0 } else nil), `ZDC{n}_`, "ZDC", 0.5, 0.24, white, "SmoothPlastic", { 255, 255, 255 })
	end
	-- The label on the front (the reader's right).
	put(box, "Label", { 4.4, 3.2, 0.1 }, { -4.6, 9.8, -6.55 }, { 236, 234, 226 }, "SmoothPlastic")
	put(box, "LabelStripe", { 4.4, 0.55, 0.12 }, { -4.6, 11.12, -6.56 }, ZDC_RED, "SmoothPlastic")
	for n, line in { { -5.3, 10.5 }, { -5.3, 10.15 } } do
		put(box, `LabelLine{n}`, { 2.2, 0.18, 0.05 }, { line[1], line[2], -6.62 }, { 120, 120, 124 }, "SmoothPlastic")
	end
	for n, b in { { -5.8, 0.22 }, { -5.3, 0.4 }, { -4.85, 0.16 }, { -4.35, 0.34 }, { -3.85, 0.2 }, { -3.4, 0.42 } } do
		put(box, `Barcode{n}`, { b[2], 1.3, 0.05 }, { b[1], 9.25, -6.62 }, { 30, 30, 32 }, "SmoothPlastic")
	end
	-- THIS WAY UP: two arrows on the left end (the face toward +X).
	for n, along in { -1.8, 1.8 } do
		local arrow = child(box, { 8.5, 7.4, along }, { 0, 90, 0 })
		put(arrow, `ArrowStem{n}`, { 0.5, 2, 0.1 }, { 0, 0, 0.05 }, { 34, 34, 36 }, "SmoothPlastic")
		put(arrow, `ArrowHead{n}R`, { 0.1, 1, 0.8 }, { 0.4, 1.5, 0.05 }, { 34, 34, 36 }, "SmoothPlastic", "Wedge", { 0, -90, 0 })
		put(arrow, `ArrowHead{n}L`, { 0.1, 1, 0.8 }, { -0.4, 1.5, 0.05 }, { 34, 34, 36 }, "SmoothPlastic", "Wedge", { 0, 90, 0 })
	end
	floodlight(ORIGIN, { 0, 0.25, -8.6 }, 22)
end

local function bank()
	-- A finial on the dome (a gold ball, a pedestal, a glowing ring, a spindle), the coin on it: 13 across, a raised
	-- rim (the darker field inside), a reeded edge, a $ on both faces. The coin turns (Art.Motion).
	local gold, goldDark = { 222, 176, 58 }, { 196, 150, 46 }
	put(ORIGIN, "Finial", { 2.2, 2.2, 2.2 }, { 0, 1.1, 0 }, gold, "Metal", "Ball")
	upright(ORIGIN, "Pedestal", 1.6, 1.4, { 0, 2.8, 0 }, gold, "Metal")
	local ring = glow(upright(ORIGIN, "PedestalRing", 0.4, 2.4, { 0, 3.8, 0 }, gold, "Metal"), { 255, 220, 140 })
	ring.light = 18
	upright(ORIGIN, "Spindle", 1, 0.5, { 0, 4.4, 0 }, DARK, "Metal")
	moving = true
	local coin = child(ORIGIN, { 0, 11, 0 })
	disc(coin, "CoinBody", 2, 13, { 0, 0, 0 }, gold, "Metal")
	disc(coin, "CoinField", 2.1, 10.6, { 0, 0, 0 }, goldDark, "Metal")
	for k = 0, 23 do
		local a = k * 15
		put(coin, `CoinReed{k + 1}`, { 0.28, 0.2, 1.9 }, { 6.45 * math.cos(math.rad(a)), 6.45 * math.sin(math.rad(a)), 0 }, { 176, 132, 40 }, "Metal", nil, { 0, 0, a + 90 })
	end
	local bright, brightLit = { 255, 214, 96 }, { 255, 224, 130 }
	text(child(coin, { 0, 0, -1.05 }, { 0, 180, 0 }), "CoinDollarFront", "$", 1.2, 0.4, bright, "Metal", brightLit)
	text(child(coin, { 0, 0, 1.05 }), "CoinDollarBack", "$", 1.2, 0.4, bright, "Metal", brightLit)
	moving = false
end

local function clinic()
	-- The cross: 13 across, red, 2.8 thick, a white rim behind it all round, a neon stripe down the middle of each
	-- face; a dark plaque under it with a green heartbeat line; posts and braces.
	local red, redLit, white = { 206, 32, 38 }, { 255, 46, 50 }, { 244, 244, 240 }
	local stripe, stripeLit = { 255, 150, 140 }, { 255, 196, 186 }
	local y = 12.5
	glow(put(ORIGIN, "CrossUp", { 4.4, 13, 2.8 }, { 0, y, 0 }, red, "SmoothPlastic"), redLit)
	put(ORIGIN, "RimUp", { 5.6, 14.2, 2.4 }, { 0, y, 0 }, white, "SmoothPlastic")
	for n, side in { -1, 1 } do
		glow(put(ORIGIN, `CrossArm{n}`, { 4.3, 4.4, 2.8 }, { side * 4.35, y, 0 }, red, "SmoothPlastic"), redLit)
		put(ORIGIN, `RimArm{n}`, { 4.3, 5.6, 2.4 }, { side * 4.95, y, 0 }, white, "SmoothPlastic")
		local z = side * 1.45
		glow(put(ORIGIN, `StripeUp{n}`, { 1.5, 10.2, 0.14 }, { 0, y, z }, stripe, "SmoothPlastic"), stripeLit)
		for k, arm in { -1, 1 } do
			glow(put(ORIGIN, `StripeArm{n}_{k}`, { 4.35, 1.5, 0.14 }, { arm * 2.925, y, z }, stripe, "SmoothPlastic"), stripeLit)
		end
		put(ORIGIN, `Post{n}`, { 0.8, 6.2, 0.8 }, { side * 1.4, 3.1, 0 }, STEEL, "Metal")
		put(ORIGIN, `Brace{n}`, { 0.5, 9.36, 0.5 }, { side * 1.4, 4.7, 3.15 }, STEEL, "Metal", nil, { -23.3, 0, 0 })
	end
	put(ORIGIN, "Base", { 6, 0.4, 4 }, { 0, 0.2, 0 }, DARK, "Metal")
	put(ORIGIN, "Plaque", { 11.6, 2.6, 0.4 }, { 0, 4.1, -0.75 }, { 28, 32, 36 }, "Metal")
	-- The heartbeat, read from the street (from +X): flat, a dip, the spike, the fall, flat.
	local beat = child(ORIGIN, { 0, 4.1, -0.95 }, { 0, 180, 0 })
	local line = { { -5.4, -0.15 }, { -1.6, -0.15 }, { -0.9, -0.75 }, { -0.2, 1.05 }, { 0.6, -1.05 }, { 1.3, -0.15 }, { 5.4, -0.15 } }
	for n = 1, #line - 1 do
		glow(bar(beat, `Heartbeat{n}`, line[n], line[n + 1], 0.06, 0.26, 0.12, { 90, 220, 120 }, "SmoothPlastic"), { 120, 255, 150 })
	end
end

local BUILDERS: { [string]: () -> () } = {
	guns = guns, pizza = pizza, gearvest = gearvest, zdcbag = zdcbag, bikes = bikes, dealer = dealer, mechanic = mechanic,
	depot = depot, bank = bank, clinic = clinic,
}

-- The pieces of one prop in its roof frame (fresh tables every call).
function Art.pieces(id: string): { Piece }
	local build = assert(BUILDERS[id], "Unknown shop prop")
	list, moving = {}, false
	build()
	local out = list
	list = {}
	local seen: { [string]: boolean } = {}
	for _, piece in out do
		assert(not seen[piece.name], "Two shop prop pieces with one name")
		seen[piece.name] = true
	end
	return out
end

-- A PolishArt.Builder spec (its model is named ShopProp_<id>).
function Art.spec(id: string): { id: string, pieces: { Piece } }
	return { id = "ShopProp_" .. id, pieces = Art.pieces(id) }
end

return Art
