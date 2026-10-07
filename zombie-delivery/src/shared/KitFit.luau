--!strict
-- 5.0: the worn kit and the phone in hand, the pure part (server/KitWear.luau builds them). Which pieces of Codex's
-- art (server/KitArt/Geometry.luau, server/PhoneArt/Geometry.luau) a player wears for their profile.kit, and how the
-- art, authored for a nominal block R15 body, is fitted to the body the character really has.
--
--   KitFit.outfit(kit, loaded, bag)  slot → art id: pack = "bigpack" (owned) or "backpack", load = the backpack the
--                                parcel sits on (only while `loaded`: the PackCount attribute > 0), shoes, jacket;
--                                6.0: hand = "bag" (the plastic bag in the left hand; 6.4: `bag`, the active bag's id
--                                when given and owned: "tote", "thermal", "padded", "duffel"), vest = the best vest owned
--                                ("heavy", else "kevlar": stream 2's armour, Config.Kit; 6.0.1: else "hivis", the
--                                Courier Vest, the red reflective vest that is no longer part of the courier's body)
--   KitFit.factors(bone, size)   the x / y / z scale of a body part against its nominal size (clamped; a hand: one
--                                uniform factor so the phone keeps its shape)
--   KitFit.fit(pieces, scales)   copies of the pieces with their offsets and sizes scaled per their bone (a turned
--                                piece's size follows the scaled direction of each of its own axes)
-- 6.4.1, the worn bag (server/KitWear.luau; tests/bagfill_test.luau):
--   KitFit.R6                    the R15 part a piece hangs on → its stand-in on an R6 body (the bag under "Left Arm",
--                                the straps and the bag's places on the "Torso"); KitFit.factors scales the art to it
--   KitFit.bagKey(id, place, packed) / KitFit.parseBagKey(key)  the worn bag's slot key "id@place" ("+" at the end:
--                                a backpack is worn, a slung bag hangs behind it) and back: (id, place, packed) or nil.
--                                Only the id is a KitArt look (6.4 asked KitArt for "bag@hand": the bag never showed)
--   KitFit.bagGrip(id, place, part, size, packed)  where the bag's pivot hangs on that body part (`part` the R15 name
--                                it stands for, `size` the real part's): its offset { x, y, z } and turn (degrees).
--                                "hand": Config.Courier.Bag.Grip under the hand (HandOut[id] further out), else
--                                Config.Courier.BagPlaces[place] scaled to the part (PackPush further back when packed)
--
-- Pure Luau (tests/kitfit_test.luau).

local Config = require(script.Parent.Config)

local KitFit = {}

KitFit.R6 = { UpperTorso = "Torso", LeftHand = "Left Arm", LeftUpperArm = "Left Arm", RightUpperArm = "Right Arm" } :: { [string]: string }

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
function KitFit.outfit(kit: Kit, loaded: boolean, bag: string?): { [string]: string }
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

-- 6.4.1: the worn bag's slot key and back.
function KitFit.bagKey(id: string, place: string, packed: boolean): string
	return `{id}@{place}{if packed then "+" else ""}`
end

function KitFit.parseBagKey(key: string): (string?, string?, boolean)
	local id, place, packed = string.match(key, "^([^@]+)@(%w+)(%+?)$")
	if not id or not place then
		return nil, nil, false
	end
	return id, place, packed == "+"
end

-- 6.4.1: the bag's pivot on its body part (see the header). `part` is the R15 name the place is authored for.
function KitFit.bagGrip(id: string, place: string, part: string, size: Scale, packed: boolean): (Scale, Scale)
	local C = Config.Courier
	local spot = C.BagPlaces[place]
	if not spot then
		return { -(C.HandOut[id] or 0), -(size[2] or 0) / 2 - C.Bag.Grip, 0 }, { 0, 0, 0 }
	end
	local f = KitFit.factors(part, size)
	local back = if packed and (place == "back" or place == "hipBack") then C.PackPush else 0
	return { spot.at[1] * f[1], spot.at[2] * f[2], spot.at[3] * f[3] + back }, { spot.turn[1], spot.turn[2], spot.turn[3] }
end

return KitFit
