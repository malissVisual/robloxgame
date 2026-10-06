--!strict
-- 5.0: the worn kit and the phone in hand, the pure part (server/KitWear.luau builds them). Which pieces of Codex's
-- art (server/KitArt/Geometry.luau, server/PhoneArt/Geometry.luau) a player wears for their profile.kit, and how the
-- art, authored for a nominal block R15 body, is fitted to the body the character really has.
--
--   KitFit.outfit(kit, loaded)   slot → art id: pack = "bigpack" (owned) or "backpack", load = the backpack the
--                                parcel sits on (only while `loaded`: the PackCount attribute > 0), shoes, jacket
--   KitFit.factors(bone, size)   the x / y / z scale of a body part against its nominal size (clamped; a hand: one
--                                uniform factor so the phone keeps its shape)
--   KitFit.fit(pieces, scales)   copies of the pieces with their offsets and sizes scaled per their bone (a turned
--                                piece's size follows the scaled direction of each of its own axes)
--
-- Pure Luau (tests/kitfit_test.luau).

local KitFit = {}

export type Kit = { [string]: boolean }
export type Scale = { number } -- x, y, z

-- The block R15 body the art is authored for (design/kit-models/README.md): the torso 2 wide, 1.6 high, 1 deep, the
-- feet 1 × .3 × 1.2, the upper arms and the hand of the block rig.
KitFit.Nominal = {
	UpperTorso = { 2, 1.6, 1 },
	LeftUpperArm = { 1, 1.17, 1 },
	RightUpperArm = { 1, 1.17, 1 },
	LeftFoot = { 1, 0.3, 1.2 },
	RightFoot = { 1, 0.3, 1.2 },
	RightHand = { 1, 0.3, 1 },
} :: { [string]: Scale }

-- Bones fitted with one factor for all three axes (the handset is a rigid device, not cloth).
local UNIFORM: { [string]: boolean } = { RightHand = true }

KitFit.Min = 0.5 -- a factor never goes below / above these (an odd mesh body: kept attached, not absurd)
KitFit.Max = 2
KitFit.HandMin = 0.7
KitFit.HandMax = 1.3

-- What to wear: slot → the art id. The best backpack only; the parcel rides on whichever backpack is worn.
function KitFit.outfit(kit: Kit, loaded: boolean): { [string]: string }
	local out: { [string]: string } = {}
	local pack = if kit.bigpack == true then "bigpack" elseif kit.backpack == true then "backpack" else nil
	if pack then
		out.pack = pack
		if loaded then
			out.load = pack
		end
	end
	if kit.shoes == true then
		out.shoes = "shoes"
	end
	if kit.jacket == true then
		out.jacket = "jacket"
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
	for i = 1, 3 do
		local f = (size[i] or 0) / nominal[i]
		out[i] = if finite(f) and f > 0 then math.clamp(f, KitFit.Min, KitFit.Max) else 1
	end
	if UNIFORM[bone] then
		local f = math.clamp((out[1] + out[3]) / 2, KitFit.HandMin, KitFit.HandMax)
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

-- Copies of the pieces (Builder pieces: size, at, attach, turn?) fitted per bone; a bone not in `scales` is left as is.
-- The input is not changed.
function KitFit.fit(pieces: { any }, scales: { [string]: Scale }): { any }
	local out: { any } = {}
	for _, piece in pieces do
		local s = scales[piece.attach]
		local copy = table.clone(piece)
		if s then
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

return KitFit
