--!strict
-- Native R15 couriers, people and infected. Pure data: 16 body parts, a connected 15-joint skeleton, and welded
-- clothing/face pieces. No meshes or uploads (a SpecialMesh sphere rounds the head and a few pieces: Roblox's own shape).
-- 6.0.1: the courier's red reflective vest is bought kit now (Geometry.hivis); the body wears a plain charcoal jacket.
-- 6.7, a more realistic body (the owner: "not blocks any more"): the courier and the people (id "person", server/Npcs.luau)
-- stand 5.9 studs tall with a head of 0.92 (1/6.4 of it), slim arms (0.6 / 0.52) and legs (0.7 / 0.6), longer forearms;
-- balls round the shoulders, the elbows and the knees on the joints (they turn with the limb, so a bent arm or knee has
-- no gap); a neck; hands of a palm, a thumb and curled fingers (a fist that holds), with a LeftGripAttachment /
-- RightGripAttachment where a handle sits in it (Geometry.Grip); an egg-shaped head with a jaw, eyes (whites and
-- irises: client/BodyLife.luau blinks them), brows, a nose, a mouth, ears, hair under the backwards cap; an open
-- jacket over a shirt, trousers with a belt, boots with round toes. The infected keep the 6.0 block body (BLOCK).
-- The R15 part, joint and attachment names are unchanged, so the stock animations, shared/Joints.luau and the kit
-- (shared/KitFit.luau fits Codex's art, authored on the block body, to these sizes) keep working.
local Geometry = {}

export type Triple = { number }
export type Piece = { name: string, attach: string, size: Triple, at: Triple, color: Triple, material: string?, turn: Triple?, shape: string?, paint: string? }
export type Bone = { name: string, size: Triple, at: Triple, color: Triple, shape: string?, paint: string? }
export type Joint = { name: string, parent: string, child: string, at: Triple }
export type Spec = { id: string, bones: { Bone }, joints: { Joint }, pieces: { Piece }, hipHeight: number, budget: number, grips: { [string]: Triple } }

Geometry.ids = { "courier", "person", "walker", "runner", "soldier", "brute" }
local SKIN = { 218, 166, 119 }
local BLACK = { 28, 31, 34 }
local RED = { 188, 39, 37 }
local SILVER = { 213, 218, 202 }
local INK = { 20, 24, 20 }
local CREAM = { 238, 224, 172 }
local JACKET = { 40, 43, 47 } -- 6.0.1: the work jacket, in the trousers' charcoal

-- 6.0: the block body (the infected). At rest the sole is 2.97 studs below the root.
local BLOCK = {
	{ "HumanoidRootPart", { 2, 2, 1 }, { 0, 0, 0 }, "root" },
	{ "LowerTorso", { 2, 0.4, 1 }, { 0, -0.75, 0 }, "pants" },
	{ "UpperTorso", { 2, 1.6, 1 }, { 0, 0.25, 0 }, "shirt" },
	{ "Head", { 1.6, 1.35, 1.4 }, { 0, 1.725, 0 }, "skin" },
	{ "LeftUpperArm", { 1, 1.17, 1 }, { -1.5, 0.465, 0 }, "shirt" },
	{ "RightUpperArm", { 1, 1.17, 1 }, { 1.5, 0.465, 0 }, "shirt" },
	{ "LeftLowerArm", { 1, 0.53, 1 }, { -1.5, -0.385, 0 }, "skin" },
	{ "RightLowerArm", { 1, 0.53, 1 }, { 1.5, -0.385, 0 }, "skin" },
	{ "LeftHand", { 1, 0.3, 1 }, { -1.5, -0.8, 0 }, "skin" },
	{ "RightHand", { 1, 0.3, 1 }, { 1.5, -0.8, 0 }, "skin" },
	{ "LeftUpperLeg", { 1, 0.95, 1 }, { -0.5, -1.425, 0 }, "pants" },
	{ "RightUpperLeg", { 1, 0.95, 1 }, { 0.5, -1.425, 0 }, "pants" },
	{ "LeftLowerLeg", { 1, 0.77, 1 }, { -0.5, -2.285, 0 }, "pants" },
	{ "RightLowerLeg", { 1, 0.77, 1 }, { 0.5, -2.285, 0 }, "pants" },
	{ "LeftFoot", { 1, 0.3, 1.2 }, { -0.5, -2.82, -0.1 }, "boot" },
	{ "RightFoot", { 1, 0.3, 1.2 }, { 0.5, -2.82, -0.1 }, "boot" },
} :: { { any } }
local BLOCK_JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso", { 0, -0.75, 0 } },
	{ "Waist", "LowerTorso", "UpperTorso", { 0, -0.55, 0 } },
	{ "Neck", "UpperTorso", "Head", { 0, 1.05, 0 } },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", { -1, 0.75, 0 } },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", { 1, 0.75, 0 } },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", { -1.5, -0.12, 0 } },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", { 1.5, -0.12, 0 } },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", { -1.5, -0.65, 0 } },
	{ "RightWrist", "RightLowerArm", "RightHand", { 1.5, -0.65, 0 } },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", { -0.5, -0.95, 0 } },
	{ "RightHip", "LowerTorso", "RightUpperLeg", { 0.5, -0.95, 0 } },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", { -0.5, -1.9, 0 } },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", { 0.5, -1.9, 0 } },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", { -0.5, -2.67, -0.1 } },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", { 0.5, -2.67, -0.1 } },
} :: { { any } }

-- 6.7: the human body. Heights from the sole (the root's middle is G over it, HipHeight = G - 1):
--   sole 0 · ankle 0.3 · knee 1.55 · hip 2.8 · waist 3.2 · elbow 3.5 · shoulder 4.48 · neck 4.78 · chin 4.98 · crown 5.9
--   wrist 2.6, the fingertips about 2.0 (mid-thigh). The shoulder joints at x ±ARM, the hips at ±LEG.
local G = 3.2
local ARM = 0.89
local LEG = 0.35
local function Y(height: number): number
	return height - G
end
local HUMAN = {
	{ "HumanoidRootPart", { 2, 2, 1 }, { 0, 0, 0 }, "root" },
	{ "LowerTorso", { 1.24, 0.6, 0.78 }, { 0, Y(2.92), 0 }, "pants" },
	{ "UpperTorso", { 1.24, 1.58, 0.76 }, { 0, Y(3.99), 0 }, "shirt" },
	{ "Head", { 0.8, 0.92, 0.86 }, { 0, Y(5.44), -0.02 }, "skin", "Ellipsoid" },
	{ "LeftUpperArm", { 0.6, 1.1, 0.6 }, { -ARM, Y(4.03), 0 }, "sleeve" },
	{ "RightUpperArm", { 0.6, 1.1, 0.6 }, { ARM, Y(4.03), 0 }, "sleeve" },
	{ "LeftLowerArm", { 0.52, 0.94, 0.52 }, { -ARM, Y(3.07), 0 }, "forearm" },
	{ "RightLowerArm", { 0.52, 0.94, 0.52 }, { ARM, Y(3.07), 0 }, "forearm" },
	{ "LeftHand", { 0.22, 0.36, 0.4 }, { -ARM, Y(2.42), 0 }, "skin" },
	{ "RightHand", { 0.22, 0.36, 0.4 }, { ARM, Y(2.42), 0 }, "skin" },
	{ "LeftUpperLeg", { 0.64, 1.31, 0.8 }, { -LEG, Y(2.205), 0 }, "pants" },
	{ "RightUpperLeg", { 0.64, 1.31, 0.8 }, { LEG, Y(2.205), 0 }, "pants" },
	{ "LeftLowerLeg", { 0.56, 1.28, 0.68 }, { -LEG, Y(0.94), 0 }, "shin" },
	{ "RightLowerLeg", { 0.56, 1.28, 0.68 }, { LEG, Y(0.94), 0 }, "shin" },
	{ "LeftFoot", { 0.52, 0.3, 0.86 }, { -LEG, Y(0.15), -0.12 }, "boot" },
	{ "RightFoot", { 0.52, 0.3, 0.86 }, { LEG, Y(0.15), -0.12 }, "boot" },
} :: { { any } }
local HUMAN_JOINTS = {
	{ "Root", "HumanoidRootPart", "LowerTorso", { 0, Y(2.92), 0 } },
	{ "Waist", "LowerTorso", "UpperTorso", { 0, Y(3.2), 0 } },
	{ "Neck", "UpperTorso", "Head", { 0, Y(4.78), 0 } },
	{ "LeftShoulder", "UpperTorso", "LeftUpperArm", { -ARM, Y(4.48), 0 } },
	{ "RightShoulder", "UpperTorso", "RightUpperArm", { ARM, Y(4.48), 0 } },
	{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", { -ARM, Y(3.5), 0 } },
	{ "RightElbow", "RightUpperArm", "RightLowerArm", { ARM, Y(3.5), 0 } },
	{ "LeftWrist", "LeftLowerArm", "LeftHand", { -ARM, Y(2.6), 0 } },
	{ "RightWrist", "RightLowerArm", "RightHand", { ARM, Y(2.6), 0 } },
	{ "LeftHip", "LowerTorso", "LeftUpperLeg", { -LEG, Y(2.8), 0 } },
	{ "RightHip", "LowerTorso", "RightUpperLeg", { LEG, Y(2.8), 0 } },
	{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", { -LEG, Y(1.55), 0 } },
	{ "RightKnee", "RightUpperLeg", "RightLowerLeg", { LEG, Y(1.55), 0 } },
	{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", { -LEG, Y(0.3), 0 } },
	{ "RightAnkle", "RightLowerLeg", "RightFoot", { LEG, Y(0.3), 0 } },
} :: { { any } }

-- 6.7: where a handle sits in each fist (the R15 LeftGripAttachment / RightGripAttachment, in the hand's frame): just
-- under the palm, inside the curled fingers (the palms face the body: the right one -X, the left +X).
Geometry.Grip = { LeftHand = { 0.03, -0.28, 0 }, RightHand = { -0.03, -0.28, 0 } } :: { [string]: Triple }

local function triple(a: Triple, scales: Triple): Triple
	return { a[1] * scales[1], a[2] * scales[2], a[3] * scales[3] }
end

-- 6.0.1: the red reflective courier vest (Codex's pieces, unchanged) is no longer part of the body: a new courier starts
-- in plain workwear and buys it at Last Stop Supplies (Config.Kit "hivis", the Courier Vest). Its pieces on the nominal
-- UpperTorso, with their own colours and cloth; server/KitWear.luau welds them on in the kit's `vest` slot
-- (shared/KitFit.luau: a Kevlar or heavy vest is worn instead). Fresh tables on every call.
-- 6.7: still authored on the nominal block torso (2 x 1.6 x 1): KitFit scales it onto the slimmer torso like all kit.
function Geometry.hivis(): { Piece }
	local out: { Piece } = {}
	local function add(name: string, size: Triple, at: Triple, color: Triple, turn: Triple?, material: string?)
		table.insert(out, { name = name, attach = "UpperTorso", size = size, at = at, color = table.clone(color), turn = turn, material = material })
	end
	for _, side in { -1, 1 } do
		local suffix = if side < 0 then "L" else "R"
		add("Vest" .. suffix, { 0.83, 1.44, 0.07 }, { side * 0.535, -0.04, -0.535 }, RED, nil, "Fabric")
		add("Reflector" .. suffix, { 0.83, 0.17, 0.025 }, { side * 0.535, -0.22, -0.581 }, SILVER)
		add("Collar" .. suffix, { 0.25, 0.49, 0.06 }, { side * 0.29, 0.46, -0.585 }, RED, { 0, 0, side * -22 })
		add("Pocket" .. suffix, { 0.48, 0.3, 0.03 }, { side * 0.55, -0.53, -0.585 }, { 155, 32, 31 })
	end
	add("VestBack", { 1.96, 1.45, 0.06 }, { 0, -0.04, 0.53 }, RED, nil, "Fabric")
	add("BackReflector", { 1.88, 0.17, 0.025 }, { 0, -0.22, 0.578 }, SILVER)
	add("DispatchBadge", { 0.33, 0.2, 0.025 }, { -0.55, 0.21, -0.581 }, SILVER)
	return out
end

-- 6.7: the head's front surface (its ellipsoid: half sizes 0.4, 0.46, 0.43) at x, y in the head's frame.
local function face(x: number, y: number): number
	local k = 1 - (x / 0.4) ^ 2 - (y / 0.46) ^ 2
	return -0.43 * math.sqrt(math.max(k, 0))
end

-- 6.7: the human body's pieces (`courier`: the ZDC uniform and the cap; else a person, dressed by server/Npcs.luau,
-- every piece's `paint` naming the colour it takes there).
local function humanPieces(add: (string, string, Triple, Triple, Triple, Triple?, string?, string?, string?) -> (), courier: boolean, colors: { [string]: Triple })
	local skin, sleeve, forearm, shin, boot = colors.skin, colors.sleeve, colors.forearm, colors.shin, colors.boot
	local hair = { 52, 38, 28 }
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local limb = if side < 0 then "Left" else "Right"
		-- The joints rounded: each ball sits on its joint and turns about its own middle with the limb.
		add("Shoulder" .. s, limb .. "UpperArm", { 0.62, 0.62, 0.62 }, { 0, 0.45, 0 }, sleeve, nil, "Fabric", "Ball", "sleeve")
		add("Elbow" .. s, limb .. "LowerArm", { 0.54, 0.54, 0.54 }, { 0, 0.43, 0 }, forearm, nil, "Fabric", "Ball", "forearm")
		add("Knee" .. s, limb .. "LowerLeg", { 0.6, 0.6, 0.6 }, { 0, 0.61, 0 }, shin, nil, "Fabric", "Ball", "shin")
		-- The fist: the four fingers curled toward the palm (the palm faces the body: -side), the thumb across in front.
		add("Fingers" .. s, limb .. "Hand", { 0.21, 0.22, 0.35 }, { -side * 0.035, -0.27, 0 }, skin, { 0, 0, -side * 18 }, nil, nil, "skin")
		add("Thumb" .. s, limb .. "Hand", { 0.11, 0.22, 0.11 }, { -side * 0.07, -0.16, -0.17 }, skin, { -18, 0, -side * 24 }, nil, nil, "skin")
		-- The boots' round toes.
		add("Toe" .. s, limb .. "Foot", { 0.52, 0.3, 0.4 }, { 0, 0, -0.42 }, boot, nil, nil, "Ellipsoid", "boot")
		-- The face: eye whites (an iris on each, the courier's), brows, ears.
		add("Eye" .. s, "Head", if courier then { 0.15, 0.085, 0.05 } else { 0.1, 0.08, 0.04 }, { side * 0.14, 0.05, face(0.14, 0.05) + 0.005 }, if courier then { 236, 232, 222 } else INK, nil, nil, "Ellipsoid")
		add("Brow" .. s, "Head", { 0.15, 0.035, 0.04 }, { side * 0.145, 0.135, face(0.145, 0.135) - 0.005 }, hair, { 0, 0, side * -6 }, nil, nil, "hair")
		add("Ear" .. s, "Head", { 0.08, 0.2, 0.13 }, { side * 0.395, 0, 0.03 }, skin, nil, nil, "Ellipsoid", "skin")
		if courier then
			add("Iris" .. s, "Head", { 0.07, 0.075, 0.03 }, { side * 0.14, 0.048, face(0.14, 0.05) - 0.02 }, { 58, 40, 28 }, nil, nil, "Ellipsoid")
		end
	end
	add("NeckSkin", "Head", { 0.34, 0.4, 0.4 }, { 0, -0.5, 0.04 }, skin, { 0, 0, 90 }, nil, "Cylinder", "skin")
	add("Jaw", "Head", { 0.56, 0.36, 0.52 }, { 0, -0.27, -0.1 }, skin, nil, nil, "Ellipsoid", "skin")
	add("Nose", "Head", { 0.1, 0.18, 0.12 }, { 0, -0.04, face(0, -0.04) - 0.015 }, skin, nil, nil, "Ellipsoid", "skin")
	add("Mouth", "Head", { 0.15, 0.022, 0.03 }, { 0, -0.2, -0.388 }, { 150, 92, 78 })
	if not courier then
		return
	end
	-- The courier's uniform: the backwards black cap (its strap over the forehead) on short hair, an open charcoal jacket
	-- over a grey shirt (the red Courier Vest is bought kit: KitFit-scaled, its panels cover the jacket's), trousers
	-- with a belt, black cuffs. 52 parts: worn with the vest's 11, within the 64.
	add("Hair", "Head", { 0.84, 0.66, 0.9 }, { 0, 0.15, 0.05 }, hair, nil, nil, "Ellipsoid")
	add("CapCrown", "Head", { 0.85, 0.6, 0.91 }, { 0, 0.24, 0.03 }, BLACK, nil, "Fabric", "Ellipsoid")
	add("CapBrimBack", "Head", { 0.5, 0.04, 0.36 }, { 0, 0.2, 0.55 }, BLACK, { -8, 0, 0 })
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		add("Jacket" .. s, "UpperTorso", { 0.5, 1.4, 0.02 }, { side * 0.33, -0.04, -0.392 }, { 46, 49, 54 }, nil, "Fabric")
		add("PocketFlap" .. s, "UpperTorso", { 0.28, 0.05, 0.02 }, { side * 0.34, -0.36, -0.405 }, BLACK, nil, "Fabric")
		add("Cuff" .. s, (if side < 0 then "Left" else "Right") .. "LowerArm", { 0.56, 0.1, 0.56 }, { 0, -0.42, 0 }, BLACK, nil, "Fabric")
	end
	add("Shirt", "UpperTorso", { 0.15, 1.38, 0.02 }, { 0, -0.03, -0.388 }, { 84, 90, 98 }, nil, "Fabric")
	add("Collar", "UpperTorso", { 0.6, 0.12, 0.54 }, { 0, 0.81, 0.02 }, { 34, 37, 41 }, nil, "Fabric")
	add("Belt", "LowerTorso", { 1.27, 0.1, 0.8 }, { 0, 0.25, 0 }, { 24, 24, 26 })
end

-- Zombie palette arguments are the existing Config.Zombies data; no gameplay numbers are duplicated here.
-- 6.7: "person" (the people of server/Npcs.luau) takes `scale` too (a kid is smaller).
function Geometry.spec(id: string, scale: number?, skin: Triple?, shirt: Triple?, pants: Triple?): Spec
	assert(table.find(Geometry.ids, id), `Unknown character art: {id}`)
	local courier = id == "courier"
	local human = courier or id == "person"
	local s = if courier then 1 else scale or 1
	assert(s > 0 and s <= 4, "Invalid character scale")
	local factors = { s * (if id == "brute" then 1.3 else 1), s, s * (if id == "brute" then 1.2 else 1) }
	local colors: { [string]: Triple }
	if courier then
		colors = { root = BLACK, boot = BLACK, skin = SKIN, shirt = JACKET, sleeve = JACKET, forearm = JACKET, pants = { 44, 48, 56 }, shin = { 44, 48, 56 } }
	elseif human then
		-- (server/Npcs.luau paints every part for the person's look)
		local cloth = shirt or { 90, 110, 140 }
		local legs = pants or { 60, 60, 66 }
		colors = { root = BLACK, boot = { 46, 38, 32 }, skin = skin or { 241, 194, 160 }, shirt = cloth, sleeve = cloth, forearm = cloth, pants = legs, shin = legs }
	else
		colors = {
			root = BLACK, boot = BLACK,
			skin = skin or { 120, 150, 100 },
			shirt = shirt or { 90, 80, 70 },
			pants = pants or { 50, 55, 75 },
		}
	end
	local spec: Spec = { id = id, bones = {}, joints = {}, pieces = {}, hipHeight = (if human then G - 1 else 1.97) * s, budget = 64, grips = {} }
	-- Root stays 2*s high, so HipHeight remains the leg clearance for every scale.
	local body: { { any } } = if human then HUMAN else BLOCK
	local joints: { { any } } = if human then HUMAN_JOINTS else BLOCK_JOINTS
	for _, b in body do
		table.insert(spec.bones, { name = b[1], size = triple(b[2], factors), at = triple(b[3], factors), color = table.clone(colors[b[4]]), shape = b[5], paint = if human then b[4] else nil })
	end
	for _, j in joints do
		table.insert(spec.joints, { name = j[1], parent = j[2], child = j[3], at = triple(j[4], factors) })
	end
	if human then
		for hand, at in Geometry.Grip do
			spec.grips[hand] = triple(at, factors)
		end
	else
		spec.grips.RightHand = { 0, -0.15 * s, 0 } -- (the 6.0 block hand's bottom)
	end
	local function add(name: string, bone: string, size: Triple, at: Triple, color: Triple, turn: Triple?, material: string?, shape: string?, paint: string?)
		table.insert(spec.pieces, { name = name, attach = bone, size = triple(size, factors), at = triple(at, factors), color = table.clone(color), turn = turn, material = material, shape = shape, paint = paint })
	end
	if human then
		humanPieces(add, courier, colors)
	else
		for _, side in { -1, 1 } do
			local suffix = if side < 0 then "L" else "R"
			add("EyeSocket" .. suffix, "Head", { 0.38, 0.34, 0.035 }, { side * 0.34, 0.11, -0.72 }, INK, { 0, 0, side * -15 })
			add("Eye" .. suffix, "Head", { 0.14, 0.15, 0.04 }, { side * 0.34, 0.08, -0.755 }, CREAM, nil, "Neon", "Ball")
			add("AngryBrow" .. suffix, "Head", { 0.48, 0.09, 0.045 }, { side * 0.35, 0.3, -0.737 }, { 59, 71, 45 }, { 0, 0, side * 21 })
			add("Lapels" .. suffix, "UpperTorso", { 0.3, 0.72, 0.06 }, { side * 0.38, 0.35, -0.54 }, { 68, 60, 47 }, { 0, 0, side * -18 }, "Fabric")
			add("RaggedHem" .. suffix, "UpperTorso", { 0.4, 0.3, 0.06 }, { side * 0.73, -0.74, -0.54 }, colors.shirt, { 0, 0, side * 16 }, "Fabric", "Wedge")
		end
		add("OpenMouth", "Head", { 0.66, 0.34, 0.04 }, { 0, -0.3, -0.725 }, INK)
		for i = 1, 4 do
			add("Tooth" .. i, "Head", { 0.1, 0.11, 0.025 }, { (i - 2.5) * 0.14, -0.19 - (i % 2) * 0.035, -0.762 }, CREAM, { 0, 0, (i % 2) * 13 })
		end
		add("LowerTooth", "Head", { 0.16, 0.07, 0.025 }, { 0.17, -0.43, -0.762 }, CREAM)
		add("CheekScar", "Head", { 0.24, 0.04, 0.028 }, { -0.59, -0.22, -0.72 }, { 78, 88, 53 }, { 0, 0, -27 })
		add("ForeheadScar", "Head", { 0.19, 0.045, 0.028 }, { 0.06, 0.46, -0.72 }, { 78, 88, 53 }, { 0, 0, 56 })
		add("TornShirt", "UpperTorso", { 0.65, 0.58, 0.035 }, { 0, 0.23, -0.522 }, { 157, 139, 102 }, { 0, 0, 5 }, "Fabric")
		add("ShirtHole", "UpperTorso", { 0.27, 0.19, 0.025 }, { -0.09, 0.32, -0.555 }, colors.skin, { 0, 0, -19 })
		add("SleeveRip", "LeftUpperArm", { 0.32, 0.47, 0.028 }, { -0.18, -0.27, -0.514 }, colors.skin, { 0, 0, -15 })
		add("RightSleeveRip", "RightUpperArm", { 0.29, 0.26, 0.028 }, { 0.22, -0.43, -0.514 }, colors.skin, { 0, 0, 23 })
		add("KneeRip", "LeftLowerLeg", { 0.45, 0.27, 0.028 }, { 0, 0.2, -0.514 }, colors.skin, { 0, 0, 13 })
		add("TrouserPatch", "RightUpperLeg", { 0.38, 0.33, 0.028 }, { 0.16, -0.19, -0.514 }, { 67, 63, 51 }, { 0, 0, -8 })
		add("Belt", "LowerTorso", { 1.95, 0.14, 0.05 }, { 0, 0.07, -0.526 }, BLACK)
		add("Buckle", "LowerTorso", { 0.26, 0.19, 0.027 }, { 0.1, 0.07, -0.565 }, { 160, 145, 103 })
		if id == "soldier" then
			add("Helmet", "Head", { 1.72, 0.28, 1.51 }, { 0, 0.62, 0 }, { 66, 76, 46 })
			add("ChestPlate", "UpperTorso", { 1.34, 0.62, 0.13 }, { 0, -0.28, -0.59 }, { 53, 66, 44 })
		elseif id == "brute" then
			add("ShoulderPlate", "LeftUpperArm", { 1.05, 0.34, 1.07 }, { 0, 0.45, 0 }, { 85, 77, 61 })
			add("BackSeam", "UpperTorso", { 0.13, 1.5, 0.025 }, { 0.38, 0, 0.518 }, { 104, 93, 76 })
		end
	end
	assert(#spec.bones + #spec.pieces <= spec.budget, "Character part budget exceeded")
	return spec
end

return Geometry
