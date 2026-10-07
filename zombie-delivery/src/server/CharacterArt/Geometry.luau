--!strict
-- Native block R15 couriers and infected, based on the owner's approved loading-van thumbnail.
-- Pure data: 16 body parts, a connected 15-joint skeleton, and welded clothing/face pieces. No meshes or uploads.
local Geometry = {}

export type Triple = { number }
export type Piece = { name: string, attach: string, size: Triple, at: Triple, color: Triple, material: string?, turn: Triple?, shape: string? }
export type Bone = { name: string, size: Triple, at: Triple, color: Triple }
export type Joint = { name: string, parent: string, child: string, at: Triple }
export type Spec = { id: string, bones: { Bone }, joints: { Joint }, pieces: { Piece }, hipHeight: number, budget: number }

Geometry.ids = { "courier", "walker", "runner", "soldier", "brute" }
local SKIN = { 218, 166, 119 }
local BLACK = { 28, 31, 34 }
local RED = { 188, 39, 37 }
local SILVER = { 213, 218, 202 }
local INK = { 20, 24, 20 }
local CREAM = { 238, 224, 172 }

-- At rest the sole is 2.97 studs below the root. The kit's existing nominal R15 dimensions are preserved.
local BODY = {
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
local JOINTS = {
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

local function triple(a: Triple, scales: Triple): Triple
	return { a[1] * scales[1], a[2] * scales[2], a[3] * scales[3] }
end

-- Zombie palette arguments are the existing Config.Zombies data; no gameplay numbers are duplicated here.
function Geometry.spec(id: string, scale: number?, skin: Triple?, shirt: Triple?, pants: Triple?): Spec
	assert(table.find(Geometry.ids, id), `Unknown character art: {id}`)
	local courier = id == "courier"
	local s = if courier then 1 else scale or 1
	assert(s > 0 and s <= 4, "Invalid character scale")
	local factors = { s * (if id == "brute" then 1.3 else 1), s, s * (if id == "brute" then 1.2 else 1) }
	local colors: { [string]: Triple } = {
		root = BLACK, boot = BLACK,
		skin = if courier then SKIN else skin or { 120, 150, 100 },
		shirt = if courier then BLACK else shirt or { 90, 80, 70 },
		pants = if courier then { 40, 43, 47 } else pants or { 50, 55, 75 },
	}
	local spec: Spec = { id = id, bones = {}, joints = {}, pieces = {}, hipHeight = 1.97 * s, budget = 64 }
	-- Root stays 2*s high, so HipHeight remains the leg clearance for every scale.
	for _, b in BODY do
		table.insert(spec.bones, { name = b[1], size = triple(b[2], factors), at = triple(b[3], factors), color = table.clone(colors[b[4]]) })
	end
	for _, j in JOINTS do
		table.insert(spec.joints, { name = j[1], parent = j[2], child = j[3], at = triple(j[4], factors) })
	end
	local function add(name: string, bone: string, size: Triple, at: Triple, color: Triple, turn: Triple?, material: string?, shape: string?)
		table.insert(spec.pieces, { name = name, attach = bone, size = triple(size, factors), at = triple(at, factors), color = table.clone(color), turn = turn, material = material, shape = shape })
	end
	if courier then
		for _, side in { -1, 1 } do
			local suffix = if side < 0 then "L" else "R"
			add("Vest" .. suffix, "UpperTorso", { 0.83, 1.44, 0.07 }, { side * 0.535, -0.04, -0.535 }, RED, nil, "Fabric")
			add("Reflector" .. suffix, "UpperTorso", { 0.83, 0.17, 0.025 }, { side * 0.535, -0.22, -0.581 }, SILVER)
			add("Collar" .. suffix, "UpperTorso", { 0.25, 0.49, 0.06 }, { side * 0.29, 0.46, -0.585 }, RED, { 0, 0, side * -22 })
			add("Pocket" .. suffix, "UpperTorso", { 0.48, 0.3, 0.03 }, { side * 0.55, -0.53, -0.585 }, { 155, 32, 31 })
		end
		add("VestBack", "UpperTorso", { 1.96, 1.45, 0.06 }, { 0, -0.04, 0.53 }, RED, nil, "Fabric")
		add("BackReflector", "UpperTorso", { 1.88, 0.17, 0.025 }, { 0, -0.22, 0.578 }, SILVER)
		add("DispatchBadge", "UpperTorso", { 0.33, 0.2, 0.025 }, { -0.55, 0.21, -0.581 }, SILVER)
		add("CapBand", "Head", { 1.68, 0.2, 1.46 }, { 0, 0.605, 0 }, BLACK, nil, "Fabric")
		add("CapCrown", "Head", { 1.75, 0.55, 1.57 }, { 0, 0.74, 0 }, BLACK, nil, "Fabric", "Ball")
		add("CapBrimBack", "Head", { 1.27, 0.1, 0.58 }, { 0, 0.53, 0.89 }, BLACK)
		add("CapStrapFront", "Head", { 1.25, 0.12, 0.045 }, { 0, 0.47, -0.716 }, { 45, 48, 51 })
		add("CapBuckle", "Head", { 0.19, 0.11, 0.035 }, { 0.38, 0.47, -0.751 }, { 81, 85, 87 })
		-- Calm default expression: the fear in the thumbnail is a moment, not a permanently screaming player.
		for _, side in { -1, 1 } do
			local suffix = if side < 0 then "L" else "R"
			add("Eye" .. suffix, "Head", { 0.17, 0.27, 0.04 }, { side * 0.32, 0.07, -0.718 }, INK, nil, nil, "Ball")
			add("EyeGlint" .. suffix, "Head", { 0.055, 0.07, 0.02 }, { side * 0.32 - 0.022, 0.13, -0.743 }, SILVER, nil, nil, "Ball")
			add("Brow" .. suffix, "Head", { 0.3, 0.055, 0.035 }, { side * 0.32, 0.3, -0.721 }, BLACK, { 0, 0, side * -8 })
		end
		add("Mouth", "Head", { 0.38, 0.06, 0.025 }, { 0, -0.27, -0.715 }, INK)
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
