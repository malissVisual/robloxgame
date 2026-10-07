--!strict
-- 5.0: the worn kit and the phone in hand, the pure part (server/KitWear.luau builds them). Which pieces of Codex's
-- art (server/KitArt/Geometry.luau, server/PhoneArt/Geometry.luau) a player wears for their profile.kit, and how the
-- art, authored for a nominal block R15 body, is fitted to the body the character really has.
--
--   KitFit.outfit(kit, bag)      slot → art id: shoes (6.6: no backpack slot any more, one carrying item; 6.7: no
--                                jacket, retired);
--                                6.0: hand = "bag" (the plastic bag in the left hand; 6.4: `bag`, the active bag's id
--                                when given and owned: "tote", "thermal", "padded", "duffel"), vest = the best vest owned
--                                ("heavy", else "kevlar": stream 2's armour, Config.Kit; 6.0.1: else "hivis", the
--                                Courier Vest, the red reflective vest that is no longer part of the courier's body)
--   KitFit.factors(bone, size)   the x / y / z scale of a body part against its nominal size (clamped; a hand: one
--                                uniform factor so the phone keeps its shape)
--   KitFit.fit(pieces, scales)   copies of the pieces with their offsets and sizes scaled per their bone (a turned
--                                piece's size follows the scaled direction of each of its own axes); 6.7: on a hand
--                                smaller than the block one (the courier's fist) the art is held in the palm
--                                (KitFit.Palm: scaled by the hand's one factor, turned to face the way the palm does)
-- 6.4.1, the worn bag (server/KitWear.luau; tests/bagfill_test.luau):
--   KitFit.R6                    the R15 part a piece hangs on → its stand-in on an R6 body (the bag under "Left Arm",
--                                the straps and the bag's places on the "Torso"); KitFit.factors scales the art to it
--   KitFit.bagKey(id, place) / KitFit.parseBagKey(key)  the worn bag's slot key "id@place" and back: (id, place) or
--                                nil (6.6: no "+" for a backpack worn any more). Only the id is a KitArt look (6.4 asked KitArt for "bag@hand": the bag never showed)
--   KitFit.bagGrip(id, place, part, size)  where the bag's pivot hangs on that body part (`part` the R15 name it
--                                stands for, `size` the real part's): its offset { x, y, z } and turn (degrees).
--                                "hand": Config.Courier.Bag.Grip under the hand (HandOut[id] further out), else
--                                Config.Courier.BagPlaces[place] scaled to the part
--
-- Pure Luau (tests/kitfit_test.luau).

local Config = require(script.Parent.Config)

local KitFit = {}

KitFit.R6 = { UpperTorso = "Torso", LeftHand = "Left Arm", LeftUpperArm = "Left Arm", RightUpperArm = "Right Arm" } :: { [string]: string }

export type Kit = { [string]: boolean }
export type Scale = { number } -- x, y, z

-- The block R15 body the art is authored for (design/kit-models/README.md): the torso 2 wide, 1.6 high, 1 deep, the
-- feet 1 × .3 × 1.2, the upper arms and the hand of the block rig.
-- 6.7: the courier's realistic body (server/CharacterArt/Geometry.luau) is slimmer than this (the torso 1.24 x 1.58 x
-- 0.76, the upper arms 0.6 x 1.1 x 0.6, the feet 0.48 x 0.3 x 0.86, the hands 0.22 x 0.36 x 0.4): the art stays
-- authored on the block body and every piece is scaled onto the real one (the vests, the packs, the shoes, the bag
-- places). The pelvis and the left hand are measured too (art hung from them scales the same way).
KitFit.Nominal = {
	UpperTorso = { 2, 1.6, 1 },
	LowerTorso = { 2, 0.4, 1 }, -- 6.7
	LeftUpperArm = { 1, 1.17, 1 },
	RightUpperArm = { 1, 1.17, 1 },
	LeftFoot = { 1, 0.3, 1.2 },
	RightFoot = { 1, 0.3, 1.2 },
	RightHand = { 1, 0.3, 1 },
	LeftHand = { 1, 0.3, 1 }, -- 6.7
} :: { [string]: Scale }

-- Bones fitted with one factor for all three axes (the handset is a rigid device, not cloth).
local UNIFORM: { [string]: boolean } = { RightHand = true, LeftHand = true }

KitFit.Min = 0.5 -- a factor never goes below / above these (an odd mesh body: kept attached, not absurd)
KitFit.Max = 2
KitFit.HandMin = 0.45 -- 6.7: 0.7 before; the courier's fist (one factor 0.31) holds the phone at a real size
KitFit.HandMax = 1.3

-- 6.7: a hand smaller than the block one (its factor under SlabHand) holds the art IN ITS PALM: the art (authored on
-- the block hand's front, the phone's screen facing -Z) is scaled about `from` (its middle there), turned so it faces
-- the way the palm does (the palms face the body: the right one -X, the left +X) and set at `to` on the real hand, just
-- off the palm (KitFit.fit). The phone pose (client/ArmPose.luau) rolls the wrist so the palm and the screen face up.
KitFit.SlabHand = 0.8
KitFit.Palm = {
	RightHand = { from = { 0, -0.12, -0.3 }, to = { -0.135, -0.2, 0 }, turn = { 0, 90, 0 } },
	LeftHand = { from = { 0, -0.12, -0.3 }, to = { 0.135, -0.2, 0 }, turn = { 0, -90, 0 } },
} :: { [string]: { from: Scale, to: Scale, turn: Scale } }

-- What to wear: slot → the art id. (6.6: the backpacks and their parcel are gone: one carrying item, the bag.)
function KitFit.outfit(kit: Kit, bag: string?): { [string]: string }
	local out: { [string]: string } = {}
	if kit.shoes == true then
		out.shoes = "shoes"
	end
	-- (6.7: no jacket slot: the Thermal Jacket is retired, Config.RetiredKit; its KitArt stays unused)
	if bag ~= nil and kit[bag] == true then
		out.hand = bag -- 6.4: the active bag (shared/Transport.luau activeBag: server/KitWear.luau names it)
	elseif bag == nil and kit.bag == true then
		out.hand = "bag" -- 6.0 (server/KitWear.luau puts it away while the hands carry or push something)
	end
	-- 6.0.1: the Courier Vest ("hivis", the red reflective one, no armour) shows only without an armoured vest
	local vest = if kit.heavy == true then "heavy" elseif kit.kevlar == true then "kevlar" elseif kit.hivis == true then "hivis" else nil
	if vest then
		out.vest = vest -- 6.0: only the best one shows
	end
	return out
end

local function finite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

-- The scale of a body part of this size (x, y, z) against the nominal one. Unknown bones: 1.
function KitFit.factors(bone: string, size: Scale): Scale
	local nominal = KitFit.Nominal[bone]
	if not nominal then
		return { 1, 1, 1 }
	end
	local out: Scale = {}
	local raw: Scale = {}
	for i = 1, 3 do
		local f = (size[i] or 0) / nominal[i]
		raw[i] = if finite(f) and f > 0 then f else 1
		out[i] = math.clamp(raw[i], KitFit.Min, KitFit.Max)
	end
	if UNIFORM[bone] then
		-- (6.7: from the hand's own measure, so a fist smaller than Min still gets its own size, down to HandMin)
		local f = math.clamp((raw[1] + raw[3]) / 2, KitFit.HandMin, KitFit.HandMax)
		return { f, f, f }
	end
	return out
end

-- The unit axes of a piece turned by Euler degrees (CFrame.Angles(x, y, z): Rx · Ry · Rz), in its bone's space.
local function axes(turn: { number }?): { Scale }
	local r = turn or { 0, 0, 0 }
	local a, b, c = math.rad(r[1] or 0), math.rad(r[2] or 0), math.rad(r[3] or 0)
	local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
	return {
		{ cb * cc, ca * sc + sa * sb * cc, sa * sc - ca * sb * cc },
		{ -cb * sc, ca * cc - sa * sb * sc, sa * cc + ca * sb * sc },
		{ sb, -sa * cb, ca * cb },
	}
end

-- 6.7: Euler degrees (CFrame.Angles order, as `axes` reads them) of a rotation given by its three axes.
local function angles(x: Scale, y: Scale, z: Scale): Scale
	local b = math.asin(math.clamp(z[1], -1, 1))
	return { math.deg(math.atan2(-z[2], z[3])), math.deg(b), math.deg(math.atan2(-y[1], x[1])) }
end

-- 6.7: a piece held in a small hand's palm (KitFit.Palm): scaled by the hand's one factor `f` about the art's middle,
-- turned to face the way the palm does and set off the palm.
local function inPalm(piece: any, copy: any, palm: { from: Scale, to: Scale, turn: Scale }, f: number)
	local frame = axes(palm.turn)
	local function turned(v: Scale): Scale
		local out: Scale = {}
		for i = 1, 3 do
			out[i] = frame[1][i] * v[1] + frame[2][i] * v[2] + frame[3][i] * v[3]
		end
		return out
	end
	local at = turned({ (piece.at[1] - palm.from[1]) * f, (piece.at[2] - palm.from[2]) * f, (piece.at[3] - palm.from[3]) * f })
	copy.at = { at[1] + palm.to[1], at[2] + palm.to[2], at[3] + palm.to[3] }
	copy.size = { piece.size[1] * f, piece.size[2] * f, piece.size[3] * f }
	local own = axes(piece.turn)
	copy.turn = angles(turned(own[1]), turned(own[2]), turned(own[3]))
end

-- Copies of the pieces (Builder pieces: size, at, attach, turn?) fitted per bone; a bone not in `scales` is left as is.
-- The input is not changed. 6.7: on a hand smaller than the block one, in its palm (KitFit.Palm).
function KitFit.fit(pieces: { any }, scales: { [string]: Scale }): { any }
	local out: { any } = {}
	for _, piece in pieces do
		local s = scales[piece.attach]
		local copy = table.clone(piece)
		local palm = if s and UNIFORM[piece.attach] and s[1] < KitFit.SlabHand then KitFit.Palm[piece.attach] else nil
		if s and palm then
			inPalm(piece, copy, palm, s[1])
		elseif s then
			copy.at = { piece.at[1] * s[1], piece.at[2] * s[2], piece.at[3] * s[3] }
			local size: Scale = {}
			for i, axis in axes(piece.turn) do
				local x, y, z = axis[1] * s[1], axis[2] * s[2], axis[3] * s[3]
				size[i] = piece.size[i] * math.sqrt(x * x + y * y + z * z)
			end
			copy.size = size
		end
		table.insert(out, copy)
	end
	return out
end

-- 6.4.1: the worn bag's slot key and back.
function KitFit.bagKey(id: string, place: string): string
	return `{id}@{place}`
end

function KitFit.parseBagKey(key: string): (string?, string?)
	local id, place = string.match(key, "^([^@]+)@(%w+)$")
	if not id or not place then
		return nil, nil
	end
	return id, place
end

-- 6.4.1: the bag's pivot on its body part (see the header). `part` is the R15 name the place is authored for.
function KitFit.bagGrip(id: string, place: string, part: string, size: Scale): (Scale, Scale)
	local C = Config.Courier
	local spot = C.BagPlaces[place]
	if not spot then
		return { -(C.HandOut[id] or 0), -(size[2] or 0) / 2 - C.Bag.Grip, 0 }, { 0, 0, 0 }
	end
	local f = KitFit.factors(part, size)
	return { spot.at[1] * f[1], spot.at[2] * f[2], spot.at[3] * f[3] }, { spot.turn[1], spot.turn[2], spot.turn[3] }
end

return KitFit
