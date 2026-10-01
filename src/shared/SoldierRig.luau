--!nonstrict
-- The designed classes (Soldier, Knight, Archer, Mage, Hunter, Berserker, Tank) as R15 characters: 9 designed stages
-- each (one per merge level), except the Knight, the Archer and the Mage, which have 30 (the R15 evolution models,
-- buildEvolution below). The Soldier comes from design/SoldierMerge_R15_Builder, the Mage from the purple mage
-- cards, the Hunter, the Berserker and the Tank from their card sheets. The gear is parts welded on the limbs of
-- the R15 base rig (Rig.base).
--   1 Recruit · 2 Private · 3 Corporal · 4 Sergeant · 5 Lieutenant · 6 Captain · 7 Major · 8 General · 9 Legend
-- Without the base rig (it could not be made, or it has not reached this client yet) the same design is built
-- on a body of plain blocks with the same limb names (a statue: no animations), so the look never falls back
-- to something else.

local Rig = require(script.Parent.Rig)
local Weapons = require(script.Parent.Weapons)
-- The Knight, the Archer and the Mage do not use their 9 cards below any more: their 30 merge levels are the R15
-- evolution models (design/KnightEvolution, ArcherEvolution, MageEvolution; generated into StageModels/<Class>Evolution), see
-- buildEvolution. `attack` / `hold` = the animations (Rig.animate); `holdFrom` = the level the weapon hand is
-- held up from (the Knight carries a weapon from level 3; the bow of the Archer hangs in the left hand).
local EVOLUTIONS = {
	-- (holdFrom = 99: the designs' rest pose is the grip; the "hold" animation would turn a hanging sword or a
	-- standing staff forward. The attack animation moves the hand, and the weapon follows it.)
	Knight = { data = require(script.Parent.StageModels.KnightEvolution), attack = "slash", holdFrom = 99 },
	Archer = { data = require(script.Parent.StageModels.ArcherEvolution), attack = "lunge", holdFrom = 99 },
	Mage = { data = require(script.Parent.StageModels.MageEvolution), attack = "none", holdFrom = 99 }, -- no swing: the hand with the staff is raised while the fireball charges (Rig.raise)
}

local C = Color3.fromRGB
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
local R = math.rad
local PLASTIC = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local FABRIC = Enum.Material.Fabric
local SKIN = C(245, 205, 48)

local RIG_SCALE = 0.95 -- the rig's size against the block soldier of the same level
local FEET = 2.4 -- the pivot is FEET * scale above the soles, like every other class (Soldier.lift)

-- How strong the designs' lights and sparkles come out (1 = as designed). Kept soft on purpose.
local AURA_RANGE = 0.6
local AURA_BRIGHTNESS = 0.45
local AURA_SPARKLES = 0.35

-- Set by SoldierRig.build for the gear functions below (they run right away, never yield).
local scale = 1
local static = false -- a bare preview: everything anchored, no lights / particles

-- A piece of gear on a limb: `offset` in the limb's space, in studs at scale 1.
local function mk(rig, limb, kind, size, offset, color, mat, extra)
	local host = rig:FindFirstChild(limb)
	if not host then
		return nil
	end
	local p
	if kind == "wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		p.Shape = (kind == "ball" and Enum.PartType.Ball) or (kind == "cyl" and Enum.PartType.Cylinder) or Enum.PartType.Block
	end
	p.Name = "Gear_" .. limb
	p.Size = size * scale
	p.Color = color
	p.Material = mat or PLASTIC
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = static
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = host.CFrame * CF(offset.Position * scale) * offset.Rotation
	p.Parent = rig
	if not static then
		local w = Instance.new("WeldConstraint")
		w.Part0 = host
		w.Part1 = p
		w.Parent = p
	end
	-- Lights and sparkles are kept soft (AURA_*): the designs ask for a lot of them, and at full strength
	-- the glow swallowed the characters standing next to each other.
	if extra and extra.light and not static then
		local l = Instance.new("PointLight")
		l.Color = extra.light
		l.Range = (extra.range or 10) * scale * AURA_RANGE
		l.Brightness = (extra.bright or 2) * AURA_BRIGHTNESS
		l.Shadows = false
		l.Parent = p
	end
	if extra and extra.sparkle and not static then
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(extra.sparkle)
		e.Rate = (extra.rate or 18) * AURA_SPARKLES
		e.Lifetime = NumberRange.new(0.8, 1.4)
		e.Speed = NumberRange.new(0.8, 2)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		e.LightEmission = 1
		e.Parent = p
	end
	return p
end

local function both(rig, limbs, ...)
	for _, l in ipairs(limbs) do
		mk(rig, l, ...)
	end
end

local function cap(r, col, brimCol)
	mk(r, "Head", "ball", V(1.45, 0.95, 1.45), CF(0, 0.5, 0.05), col, FABRIC)
	mk(r, "Head", "block", V(1.2, 0.1, 0.6), CF(0, 0.42, -0.72), brimCol or C(58, 85, 34), FABRIC)
end

local function helmet(r, col, strapCol)
	mk(r, "Head", "ball", V(1.55, 1.15, 1.55), CF(0, 0.48, 0.05), col, METAL)
	mk(r, "Head", "block", V(1.45, 0.14, 1.45), CF(0, 0.38, 0.03), col, METAL)
	mk(r, "Head", "block", V(0.08, 0.7, 0.1), CF(-0.62, -0.1, -0.05), strapCol or C(40, 32, 24), FABRIC)
	mk(r, "Head", "block", V(0.08, 0.7, 0.1), CF(0.62, -0.1, -0.05), strapCol or C(40, 32, 24), FABRIC)
end

local function belt(r, col, buckle)
	mk(r, "LowerTorso", "block", V(2.1, 0.32, 1.1), CF(0, 0, 0), col, FABRIC)
	mk(r, "LowerTorso", "block", V(0.55, 0.3, 0.12), CF(0, 0, -0.58), buckle, METAL)
end

local function boots(r, col)
	both(r, { "LeftFoot", "RightFoot" }, "block", V(1.1, 0.7, 1.25), CF(0, 0.2, -0.05), col, PLASTIC)
	both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(1.08, 0.45, 1.08), CF(0, -0.45, 0), col, PLASTIC)
end

local function gloves(r, col)
	both(r, { "LeftHand", "RightHand" }, "block", V(1.1, 0.5, 1.1), CF(0, -0.02, 0), col, FABRIC)
end

local function kneepads(r, col)
	both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.95, 0.6, 0.25), CF(0, 0.5, -0.55), col, PLASTIC)
end

local function chestPlate(r, col, trim)
	mk(r, "UpperTorso", "block", V(1.85, 1.35, 0.22), CF(0, 0.05, -0.58), col, METAL)
	mk(r, "UpperTorso", "block", V(1.85, 1.35, 0.22), CF(0, 0.05, 0.58), col, METAL)
	if trim then
		mk(r, "UpperTorso", "block", V(1.5, 0.08, 0.1), CF(0, 0.55, -0.7), trim, NEON)
		mk(r, "UpperTorso", "block", V(1.5, 0.08, 0.1), CF(0, -0.45, -0.7), trim, NEON)
	end
end

local function pauldrons(r, col, size)
	size = size or 1
	mk(r, "LeftUpperArm", "ball", V(1.35, 0.8, 1.35) * size, CF(0, 0.45, 0), col, METAL)
	mk(r, "RightUpperArm", "ball", V(1.35, 0.8, 1.35) * size, CF(0, 0.45, 0), col, METAL)
end

local function rifle(r, col, glow, size)
	size = size or 1
	mk(r, "RightHand", "block", V(0.3, 0.45, 2.3) * size, CF(0, -0.15, -1.0), col, METAL)
	mk(r, "RightHand", "block", V(0.14, 0.14, 1.3), CF(0, -0.05, -2.6), col, METAL)
	mk(r, "RightHand", "block", V(0.26, 0.75, 0.38), CF(0, -0.65, -0.7), col, METAL)
	if glow then
		mk(r, "RightHand", "block", V(0.08, 0.08, 1.8), CF(0, 0.12, -1.3), glow, NEON, { light = glow, range = 8 })
	end
end

local function sword(r, bladeCol, guardCol, neon)
	mk(r, "RightHand", "block", V(0.28, 0.28, 0.9), CF(0, -0.15, 0.1), C(70, 20, 25), PLASTIC)
	mk(r, "RightHand", "block", V(1.0, 0.22, 0.25), CF(0, -0.15, -0.4), guardCol, METAL)
	mk(r, "RightHand", "block", V(0.14, 0.34, 4.6), CF(0, -0.15, -2.8), bladeCol, neon and NEON or METAL, neon and { light = bladeCol, range = 14, bright = 3 } or nil)
end

-- ── The 9 levels ──
-- `top` = how high the name label floats over the head; `attack` / `hold` = the animations (Rig.animate).
local LEVELS = {}

LEVELS[1] = { name = "Recruit", torso = C(110, 143, 63), legs = C(78, 107, 44), top = 1.7, attack = "lunge", hold = false,
	build = function(r)
		cap(r, C(110, 143, 63), C(58, 85, 34))
		mk(r, "UpperTorso", "block", V(0.35, 0.5, 0.06), CF(0, 0.2, -0.53), C(207, 211, 214), METAL) -- dog tag
		mk(r, "UpperTorso", "block", V(0.7, 0.55, 0.1), CF(-0.55, 0.0, -0.53), C(95, 126, 53), FABRIC) -- pocket
		boots(r, C(59, 47, 34))
	end }

LEVELS[2] = { name = "Private", torso = C(94, 138, 51), legs = C(70, 105, 42), top = 1.8, attack = "lunge", hold = false,
	build = function(r)
		helmet(r, C(75, 107, 42))
		belt(r, C(90, 67, 38), C(213, 180, 74))
		mk(r, "LeftUpperArm", "block", V(0.1, 0.55, 0.75), CF(-0.54, 0.25, 0), C(201, 58, 58), FABRIC)
		mk(r, "UpperTorso", "block", V(0.6, 0.5, 0.1), CF(-0.5, 0.1, -0.53), C(79, 122, 43), FABRIC)
		mk(r, "UpperTorso", "block", V(0.6, 0.5, 0.1), CF(0.5, 0.1, -0.53), C(79, 122, 43), FABRIC)
		boots(r, C(46, 36, 26))
	end }

LEVELS[3] = { name = "Corporal", torso = C(88, 127, 50), legs = C(74, 107, 42), top = 1.8, attack = "lunge", hold = false,
	build = function(r)
		helmet(r, C(75, 107, 42))
		for i = 1, 5 do
			mk(r, "Head", "ball", V(0.35, 0.2, 0.35), CF(-0.55 + i * 0.18, 0.95, -0.2 + (i % 2) * 0.3), C(122, 160, 70), FABRIC)
		end
		mk(r, "UpperTorso", "block", V(0.28, 1.5, 1.1), CF(-0.65, 0.0, 0), C(42, 51, 32), FABRIC)
		mk(r, "UpperTorso", "block", V(0.28, 1.5, 1.1), CF(0.65, 0.0, 0), C(42, 51, 32), FABRIC)
		for i = -1, 1 do
			mk(r, "UpperTorso", "block", V(0.5, 0.58, 0.28), CF(i * 0.6, -0.35, -0.6), C(61, 74, 44), FABRIC)
		end
		belt(r, C(42, 33, 24), C(170, 176, 180))
		kneepads(r, C(42, 51, 32))
		mk(r, "RightUpperArm", "block", V(0.1, 0.14, 0.85), CF(0.54, 0.4, 0), C(224, 180, 58), METAL)
		mk(r, "RightUpperArm", "block", V(0.1, 0.14, 0.85), CF(0.54, 0.15, 0), C(224, 180, 58), METAL)
		gloves(r, C(45, 42, 36))
		boots(r, C(42, 33, 24))
	end }

LEVELS[4] = { name = "Sergeant", torso = C(76, 107, 43), legs = C(61, 90, 34), top = 1.8, attack = "lunge", hold = false,
	build = function(r)
		local ac = C(90, 169, 255)
		helmet(r, C(61, 90, 34), C(22, 24, 15))
		mk(r, "Head", "block", V(1.15, 0.28, 0.1), CF(0, 0.3, -0.75), C(27, 29, 26), PLASTIC)
		chestPlate(r, C(42, 51, 34), ac)
		mk(r, "UpperTorso", "ball", V(0.45, 0.45, 0.12), CF(0, 0.2, -0.72), ac, NEON)
		pauldrons(r, C(42, 51, 34))
		belt(r, C(31, 38, 26), C(138, 144, 136))
		kneepads(r, C(42, 51, 34))
		gloves(r, C(27, 29, 26))
		boots(r, C(31, 28, 23))
		rifle(r, C(38, 43, 36), ac)
	end }

LEVELS[5] = { name = "Lieutenant", torso = C(44, 58, 42), legs = C(38, 51, 31), top = 2.3, attack = "lunge", hold = false,
	build = function(r)
		local ac = C(194, 123, 255)
		helmet(r, C(38, 51, 31), C(14, 16, 16))
		mk(r, "Head", "block", V(1.3, 0.38, 0.28), CF(0, 0.35, -0.7), C(18, 21, 26), PLASTIC) -- night vision mount
		mk(r, "Head", "cyl", V(0.1, 0.42, 0.42), CF(-0.32, 0.35, -0.88) * ANG(0, R(90), 0), C(124, 255, 107), NEON, { light = C(124, 255, 107), range = 8 })
		mk(r, "Head", "cyl", V(0.1, 0.42, 0.42), CF(0.32, 0.35, -0.88) * ANG(0, R(90), 0), C(124, 255, 107), NEON, { light = C(124, 255, 107), range = 8 })
		chestPlate(r, C(29, 36, 32), ac)
		mk(r, "UpperTorso", "block", V(0.4, 0.4, 0.12), CF(0, 0.2, -0.72) * ANG(0, 0, R(45)), ac, NEON, { light = ac, range = 8 })
		mk(r, "UpperTorso", "block", V(0.28, 1.9, 0.14), CF(0, 0.05, -0.74) * ANG(0, 0, R(-48)), C(58, 63, 44), FABRIC) -- bandolier
		mk(r, "UpperTorso", "block", V(1.5, 1.7, 0.55), CF(0, -0.05, 0.85), C(22, 26, 20), FABRIC) -- backpack
		mk(r, "UpperTorso", "block", V(0.08, 2.4, 0.08), CF(0.7, 1.9, 0.9), C(34, 34, 34), METAL) -- antenna
		mk(r, "UpperTorso", "ball", V(0.22, 0.22, 0.22), CF(0.7, 3.12, 0.9), ac, NEON, { light = ac, range = 10 })
		pauldrons(r, C(29, 36, 32), 1.1)
		belt(r, C(20, 22, 26), C(214, 178, 74))
		kneepads(r, C(29, 36, 32))
		gloves(r, C(20, 22, 26))
		boots(r, C(20, 17, 15))
		rifle(r, C(29, 36, 32), ac)
		mk(r, "RightHand", "cyl", V(0.5, 0.3, 0.3), CF(0, 0.18, -1.0) * ANG(0, R(90), 0), C(17, 17, 17), METAL) -- scope
	end }

LEVELS[6] = { name = "Captain", torso = C(91, 107, 96), legs = C(76, 90, 80), top = 2.1, attack = "lunge", hold = false,
	build = function(r)
		local ac = C(255, 154, 46)
		local M = C(91, 107, 96)
		mk(r, "Head", "block", V(1.5, 1.45, 1.5), CF(0, 0.12, 0.02), M, METAL) -- full helmet
		mk(r, "Head", "block", V(1.05, 0.28, 0.12), CF(0, 0.22, -0.78), ac, NEON, { light = ac, range = 8 }) -- visor
		mk(r, "Head", "wedge", V(0.2, 0.55, 1.2), CF(0, 1.0, 0.0) * ANG(0, R(180), 0), C(61, 74, 66), METAL) -- crest
		mk(r, "Head", "block", V(0.6, 0.45, 0.2), CF(0, -0.35, -0.78), C(35, 42, 38), METAL)
		chestPlate(r, C(61, 74, 66), ac)
		mk(r, "UpperTorso", "cyl", V(0.18, 0.95, 0.95), CF(0, 0.15, -0.76) * ANG(0, R(90), 0), C(35, 42, 38), METAL)
		mk(r, "UpperTorso", "ball", V(0.6, 0.6, 0.4), CF(0, 0.15, -0.78), ac, NEON, { light = ac, range = 14, bright = 3 }) -- reactor
		for _, s in ipairs({ -1, 1 }) do
			local limb = s < 0 and "LeftUpperArm" or "RightUpperArm"
			mk(r, limb, "block", V(1.7, 0.5, 1.7), CF(s * 0.15, 0.6, 0), M, METAL)
			mk(r, limb, "wedge", V(0.5, 0.7, 0.5), CF(s * 0.65, 1.1, 0) * ANG(0, 0, R(s * -20)), C(61, 74, 66), METAL)
			mk(r, limb, "block", V(1.1, 0.12, 1.1), CF(0, 0.2, 0), ac, NEON)
		end
		belt(r, C(42, 49, 44), ac)
		for _, l in ipairs({ "LeftLowerLeg", "RightLowerLeg" }) do
			mk(r, l, "block", V(1.15, 0.75, 0.35), CF(0, 0.5, -0.55), C(61, 74, 66), METAL)
			mk(r, l, "block", V(0.9, 0.1, 0.1), CF(0, 0.5, -0.74), ac, NEON)
		end
		gloves(r, C(42, 49, 44))
		boots(r, C(42, 49, 44))
		rifle(r, C(42, 49, 44), ac, 1.4)
	end }

LEVELS[7] = { name = "Major", torso = C(223, 233, 230), legs = C(205, 217, 214), top = 2.5, attack = "lunge", hold = false,
	build = function(r)
		local ac = C(43, 232, 255)
		local W = C(223, 233, 230)
		mk(r, "Head", "block", V(1.55, 1.5, 1.55), CF(0, 0.12, 0.02), W, METAL)
		mk(r, "Head", "block", V(1.25, 0.9, 0.12), CF(0, 0.1, -0.78), C(8, 36, 48), Enum.Material.Glass)
		mk(r, "Head", "block", V(0.2, 0.2, 0.1), CF(-0.28, 0.2, -0.85), ac, NEON, { light = ac, range = 8 })
		mk(r, "Head", "block", V(0.2, 0.2, 0.1), CF(0.28, 0.2, -0.85), ac, NEON)
		mk(r, "Head", "block", V(0.08, 1.2, 0.08), CF(0.85, 1.0, 0), W, METAL)
		mk(r, "Head", "ball", V(0.2, 0.2, 0.2), CF(0.85, 1.65, 0), ac, NEON, { light = ac, range = 8 })
		mk(r, "UpperTorso", "block", V(1.9, 1.4, 0.3), CF(0, 0.05, -0.6), C(28, 43, 48), METAL)
		mk(r, "UpperTorso", "cyl", V(0.15, 0.85, 0.85), CF(0, 0.15, -0.78) * ANG(0, R(90), 0), C(11, 26, 32), METAL)
		mk(r, "UpperTorso", "ball", V(0.5, 0.5, 0.3), CF(0, 0.15, -0.8), ac, NEON, { light = ac, range = 14, bright = 3 })
		mk(r, "UpperTorso", "block", V(1.9, 0.08, 0.1), CF(0, -0.78, -0.65), ac, NEON)
		for _, l in ipairs({ "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg" }) do
			mk(r, l, "block", V(0.08, 1.1, 0.1), CF(0, 0, -0.52), ac, NEON)
			mk(r, l, "block", V(1.1, 0.7, 1.1), CF(0, 0.3, 0), C(28, 43, 48), METAL)
		end
		pauldrons(r, W, 1.15)
		belt(r, C(28, 43, 48), ac)
		gloves(r, C(22, 36, 42))
		boots(r, C(28, 43, 48))
		-- hover rings under the feet
		both(r, { "LeftFoot", "RightFoot" }, "cyl", V(0.1, 1.9, 1.9), CF(0, -0.35, 0) * ANG(0, 0, R(90)), ac, NEON, { light = ac, range = 8 })
		both(r, { "LeftFoot", "RightFoot" }, "cyl", V(0.08, 2.5, 2.5), CF(0, -0.6, 0) * ANG(0, 0, R(90)), ac, NEON)
		-- the drone
		mk(r, "UpperTorso", "ball", V(1.0, 1.0, 1.0), CF(-2.7, 1.5, 0.2), C(28, 43, 48), METAL)
		mk(r, "UpperTorso", "ball", V(0.45, 0.45, 0.45), CF(-2.7, 1.5, -0.3), ac, NEON, { light = ac, range = 10 })
		mk(r, "UpperTorso", "block", V(1.9, 0.1, 0.25), CF(-2.7, 1.5, 0.2), W, METAL)
		rifle(r, W, ac, 1.2)
	end }

LEVELS[8] = { name = "General", torso = C(42, 90, 44), legs = C(31, 74, 36), top = 1.9, attack = "slash", hold = true,
	build = function(r)
		local G = C(255, 211, 90)
		local GD = C(199, 154, 30)
		local RED = C(193, 18, 31)
		-- the cloak
		mk(r, "UpperTorso", "block", V(2.3, 3.4, 0.14), CF(0, -1.2, 0.68) * ANG(R(6), 0, 0), C(224, 54, 74), FABRIC)
		mk(r, "UpperTorso", "block", V(0.14, 3.4, 0.2), CF(-1.15, -1.2, 0.68) * ANG(R(6), 0, 0), G, METAL)
		mk(r, "UpperTorso", "block", V(0.14, 3.4, 0.2), CF(1.15, -1.2, 0.68) * ANG(R(6), 0, 0), G, METAL)
		-- the uniform
		mk(r, "UpperTorso", "block", V(0.8, 0.12, 0.1), CF(0, 0.75, -0.56), C(29, 74, 34), FABRIC)
		for _, x in ipairs({ -0.3, 0.3 }) do
			for _, y in ipairs({ 0.35, -0.05, -0.45 }) do
				mk(r, "UpperTorso", "ball", V(0.18, 0.18, 0.18), CF(x, y, -0.54), G, METAL)
			end
		end
		mk(r, "UpperTorso", "block", V(0.42, 2.3, 0.1), CF(0, 0.0, -0.58) * ANG(0, 0, R(-38)), RED, FABRIC) -- sash
		for i, col in ipairs({ C(90, 169, 255), G, C(255, 77, 94) }) do
			mk(r, "UpperTorso", "cyl", V(0.1, 0.3, 0.3), CF(-0.7 + i * 0.28 - 0.28, 0.4, -0.58) * ANG(0, R(90), 0), col, METAL)
		end
		for _, s in ipairs({ -1, 1 }) do
			local limb = s < 0 and "LeftUpperArm" or "RightUpperArm"
			mk(r, limb, "block", V(1.15, 0.2, 1.15), CF(0, 0.65, 0), G, METAL)
			mk(r, limb, "block", V(1.1, 0.3, 0.06), CF(0, 0.4, -0.6), G, METAL)
		end
		for _, l in ipairs({ "LeftUpperLeg", "RightUpperLeg" }) do
			mk(r, l, "block", V(0.12, 1.15, 1.1), CF(l == "LeftUpperLeg" and -0.5 or 0.5, 0, 0), G, METAL)
		end
		belt(r, C(23, 19, 15), G)
		gloves(r, C(245, 245, 245))
		boots(r, C(23, 19, 15))
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.1, 0.14, 1.25), CF(0, -0.02, -0.05), G, METAL)
		-- the officer's cap
		mk(r, "Head", "block", V(1.5, 0.75, 1.5), CF(0, 0.62, 0.02), C(47, 106, 49), FABRIC)
		mk(r, "Head", "block", V(1.6, 0.2, 1.6), CF(0, 0.38, 0.0), G, METAL)
		mk(r, "Head", "block", V(1.3, 0.1, 0.65), CF(0, 0.3, -0.9) * ANG(R(-8), 0, 0), C(14, 14, 14), PLASTIC)
		mk(r, "Head", "cyl", V(0.1, 0.4, 0.4), CF(0, 0.75, -0.78) * ANG(0, R(90), 0), GD, METAL)
		mk(r, "Head", "ball", V(0.18, 0.18, 0.1), CF(0, 0.75, -0.84), RED, NEON)
		sword(r, C(232, 237, 240), G, false)
	end }

LEVELS[9] = { name = "Legend", torso = C(23, 167, 107), legs = C(20, 147, 93), top = 3.1, attack = "slash", hold = true,
	build = function(r)
		local G = C(255, 216, 107)
		local GD = C(199, 154, 30)
		local E = C(43, 255, 168)
		-- the golden helmet with a crown
		mk(r, "Head", "ball", V(1.6, 1.2, 1.6), CF(0, 0.5, 0.04), G, METAL)
		mk(r, "Head", "block", V(0.3, 0.9, 1.5), CF(-0.68, 0.0, 0.04), G, METAL)
		mk(r, "Head", "block", V(0.3, 0.9, 1.5), CF(0.68, 0.0, 0.04), G, METAL)
		for i = -2, 2 do
			mk(r, "Head", "wedge", V(0.28, 0.85 - math.abs(i) * 0.15, 0.35), CF(i * 0.3, 1.2, 0.0) * ANG(0, R(180), 0), G, METAL)
		end
		mk(r, "Head", "ball", V(0.2, 0.2, 0.2), CF(0, 0.82, -0.66), E, NEON, { light = E, range = 12 })
		-- the halo
		for i = 0, 17 do
			local a = i / 18 * math.pi * 2
			mk(r, "Head", "block", V(0.4, 0.1, 0.2), CF(math.cos(a) * 1.15, 2.35, math.sin(a) * 1.15) * ANG(0, -a, 0), G, NEON, i == 0 and { light = G, range = 16, bright = 3 } or nil)
		end
		-- the golden armor
		mk(r, "UpperTorso", "block", V(1.8, 1.4, 0.3), CF(0, 0.05, -0.6), G, METAL)
		mk(r, "UpperTorso", "block", V(0.8, 0.8, 0.15), CF(0, 0.15, -0.8) * ANG(0, 0, R(45)), C(5, 42, 28), METAL)
		mk(r, "UpperTorso", "block", V(0.45, 0.45, 0.2), CF(0, 0.15, -0.88) * ANG(0, 0, R(45)), E, NEON, { light = E, range = 16, bright = 4, sparkle = E, rate = 25 })
		mk(r, "LowerTorso", "block", V(2.1, 0.34, 1.1), CF(0, 0, 0), GD, METAL)
		for _, s in ipairs({ -1, 1 }) do
			local limb = s < 0 and "LeftUpperArm" or "RightUpperArm"
			mk(r, limb, "block", V(1.7, 0.55, 1.7), CF(0, 0.55, 0), G, METAL)
			mk(r, limb, "wedge", V(0.4, 0.8, 0.4), CF(s * 0.2, 1.1, 0) * ANG(0, R(180), 0), G, METAL)
		end
		gloves(r, G)
		both(r, { "LeftLowerArm", "RightLowerArm" }, "block", V(1.15, 0.8, 1.15), CF(0, 0, 0), G, METAL)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(1.15, 0.9, 1.15), CF(0, 0.1, 0), G, METAL)
		both(r, { "LeftUpperLeg", "RightUpperLeg" }, "block", V(0.7, 0.6, 0.15), CF(0, 0.1, -0.56), E, NEON)
		boots(r, G)
		-- the wings of light
		for _, s in ipairs({ -1, 1 }) do
			for i = 1, 6 do
				local phi = R(-55 + i * 22)
				local L = 2.2 + math.sin(i * 0.55) * 1.7
				mk(r, "UpperTorso", "block", V(L, 0.1, 0.5), CF(s * (0.8 + math.cos(phi) * L / 2), 0.4 + math.sin(phi) * L / 2, 0.75 + i * 0.05) * ANG(0, 0, s * phi), i % 2 == 0 and C(255, 255, 255) or E, NEON, (i == 3) and { light = E, range = 14, bright = 2 } or nil)
			end
		end
		-- the energy sword
		mk(r, "RightHand", "block", V(0.28, 0.28, 0.9), CF(0, -0.15, 0.1), GD, METAL)
		mk(r, "RightHand", "block", V(1.1, 0.24, 0.28), CF(0, -0.15, -0.4), G, METAL)
		local glow = mk(r, "RightHand", "block", V(0.5, 0.5, 6.2), CF(0, -0.15, -3.7), E, NEON, { light = E, range = 20, bright = 4 })
		if glow then
			glow.Transparency = 0.55
		end
		mk(r, "RightHand", "block", V(0.16, 0.36, 6.0), CF(0, -0.15, -3.6), C(255, 255, 255), NEON)
		-- floating crystals
		local shards = { { -3.2, 2.2, 0.5 }, { 3.4, 3.0, -0.4 }, { -3.0, -0.6, -0.7 }, { 3.2, -0.2, 0.6 }, { -2.2, 4.2, 0.0 }, { 2.4, 4.6, 0.3 } }
		for _, p in ipairs(shards) do
			mk(r, "UpperTorso", "block", V(0.45, 0.45, 0.45), CF(p[1], p[2], p[3]) * ANG(R(45), 0, R(45)), E, NEON, { light = E, range = 8 })
		end
		-- the aura of sparkles
		local aura = mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.4), CF(0, 0, 0), G, NEON, { sparkle = G, rate = 40 })
		if aura then
			aura.Transparency = 1
		end
	end }

-- ── The Knight: 9 levels (design: the red knight cards) ──
--   1 Squire · 2 Footman · 3 Swordsman · 4 Knight · 5 Elite Knight · 6 Paladin · 7 Dragon Knight ·
--   8 Grandmaster · 9 Legend
local K_RED = C(190, 40, 55)
local K_DARK_RED = C(120, 28, 40)
local K_BROWN = C(110, 85, 60)
local K_LEATHER = C(70, 52, 38)
local K_WOOD = C(160, 120, 75)
local K_STEEL = C(175, 182, 194)
local K_IRON = C(108, 116, 128)
local K_GOLD = C(232, 185, 60)
local K_WHITE = C(240, 240, 240)
local K_BONE = C(238, 230, 205)
local K_BLACK = C(42, 36, 42)
local K_FIRE = C(255, 95, 30)
local K_FLAME = C(255, 200, 80)

-- A sword in the right hand (the blade lies along the hand's -Z).
local function blade(r, bladeCol, guardCol, gripCol, length, glow)
	mk(r, "RightHand", "block", V(0.26, 0.26, 0.9), CF(0, -0.15, 0.1), gripCol, PLASTIC)
	mk(r, "RightHand", "ball", V(0.36, 0.36, 0.36), CF(0, -0.15, 0.62), guardCol, METAL)
	mk(r, "RightHand", "block", V(1.05, 0.22, 0.25), CF(0, -0.15, -0.4), guardCol, METAL)
	mk(r, "RightHand", "block", V(0.14, 0.36, length), CF(0, -0.15, -0.5 - length / 2), bladeCol, glow and NEON or METAL, glow and { light = glow, range = 14, bright = 3 } or nil)
end

-- A round wooden shield on the left hand.
local function roundShield(r, col, cross)
	mk(r, "LeftHand", "cyl", V(0.18, 1.9, 1.9), CF(-0.35, 0.1, -0.7) * ANG(0, R(90), 0), col, Enum.Material.Wood)
	mk(r, "LeftHand", "ball", V(0.5, 0.5, 0.3), CF(-0.35, 0.1, -0.85), K_STEEL, METAL)
	if cross then
		mk(r, "LeftHand", "block", V(1.5, 0.16, 0.06), CF(-0.35, 0.1, -0.81), cross, PLASTIC)
		mk(r, "LeftHand", "block", V(0.16, 1.5, 0.06), CF(-0.35, 0.1, -0.81), cross, PLASTIC)
	end
end

-- A kite shield on the left hand: a plate with a point below, a trim and an emblem
-- ("cross" | "star" | "crown" | "flame").
local function kiteShield(r, col, trim, emblem, emblemCol)
	local at = CF(-0.4, -0.1, -0.75)
	mk(r, "LeftHand", "block", V(1.7, 1.3, 0.16), at * CF(0, 0.45, 0), trim, METAL)
	mk(r, "LeftHand", "block", V(1.2, 1.2, 0.16), at * CF(0, -0.2, 0) * ANG(0, 0, R(45)), trim, METAL)
	mk(r, "LeftHand", "block", V(1.45, 1.1, 0.18), at * CF(0, 0.45, -0.02), col, METAL)
	mk(r, "LeftHand", "block", V(1.0, 1.0, 0.18), at * CF(0, -0.2, -0.02) * ANG(0, 0, R(45)), col, METAL)
	local front = at * CF(0, 0.3, -0.13)
	if emblem == "cross" then
		mk(r, "LeftHand", "block", V(0.2, 1.3, 0.05), front * CF(0, -0.1, 0), emblemCol, PLASTIC)
		mk(r, "LeftHand", "block", V(0.8, 0.2, 0.05), front * CF(0, 0.2, 0), emblemCol, PLASTIC)
	elseif emblem == "star" then
		mk(r, "LeftHand", "block", V(0.55, 0.55, 0.05), front, emblemCol, METAL)
		mk(r, "LeftHand", "block", V(0.55, 0.55, 0.05), front * ANG(0, 0, R(45)), emblemCol, METAL)
	elseif emblem == "crown" then
		mk(r, "LeftHand", "block", V(0.9, 0.3, 0.05), front * CF(0, -0.1, 0), emblemCol, METAL)
		for _, x in ipairs({ -0.35, 0, 0.35 }) do
			mk(r, "LeftHand", "block", V(0.2, 0.45, 0.05), front * CF(x, 0.2, 0), emblemCol, METAL)
		end
	elseif emblem == "flame" then
		mk(r, "LeftHand", "ball", V(0.6, 0.8, 0.12), front * CF(0, -0.05, 0), emblemCol, NEON, { light = emblemCol, range = 8 })
		mk(r, "LeftHand", "ball", V(0.28, 0.42, 0.14), front * CF(0, -0.15, -0.02), K_FLAME, NEON)
	end
end

-- A closed great helm: a box with an eye slit, a ridge and two bands.
local function greatHelm(r, col, band, slit)
	mk(r, "Head", "block", V(1.5, 1.5, 1.5), CF(0, 0.1, 0.02), col, METAL)
	mk(r, "Head", "block", V(1.1, 0.2, 0.1), CF(0, 0.2, -0.76), slit or C(10, 10, 12), slit and NEON or PLASTIC)
	mk(r, "Head", "block", V(0.16, 1.3, 0.1), CF(0, 0.15, -0.78), col, METAL)
	if band then
		mk(r, "Head", "block", V(1.54, 0.12, 1.54), CF(0, 0.5, 0.02), band, METAL)
		mk(r, "Head", "block", V(1.54, 0.12, 1.54), CF(0, -0.15, 0.02), band, METAL)
	end
end

local function plume(r, col)
	mk(r, "Head", "block", V(0.22, 0.7, 1.2), CF(0, 1.05, 0.3) * ANG(R(-25), 0, 0), col, FABRIC)
end

local function horns(r, col, neon)
	for _, s in ipairs({ -1, 1 }) do
		mk(r, "Head", "block", V(0.7, 0.3, 0.3), CF(s * 1.0, 0.6, 0), col, neon and NEON or PLASTIC)
		mk(r, "Head", "block", V(0.26, 0.8, 0.26), CF(s * 1.35, 1.0, 0) * ANG(0, 0, R(s * -15)), col, neon and NEON or PLASTIC)
	end
end

local function cloak(r, col, trim, length)
	local at = CF(0, 0.7 - length / 2, 0.68) * ANG(R(6), 0, 0)
	mk(r, "UpperTorso", "block", V(2.4, length, 0.14), at, col, FABRIC)
	mk(r, "UpperTorso", "block", V(0.14, length, 0.2), at * CF(-1.2, 0, 0), trim, METAL)
	mk(r, "UpperTorso", "block", V(0.14, length, 0.2), at * CF(1.2, 0, 0), trim, METAL)
end

-- The cross on the chest.
local function chestCross(r, col)
	mk(r, "UpperTorso", "block", V(0.3, 1.3, 0.08), CF(0, 0, -0.54), col, PLASTIC)
	mk(r, "UpperTorso", "block", V(1.1, 0.3, 0.08), CF(0, 0.25, -0.54), col, PLASTIC)
end

local function spikedPauldrons(r, col, spikeCol, neon)
	for _, s in ipairs({ -1, 1 }) do
		local limb = s < 0 and "LeftUpperArm" or "RightUpperArm"
		mk(r, limb, "block", V(1.6, 0.5, 1.6), CF(s * 0.12, 0.6, 0), col, METAL)
		for _, x in ipairs({ -0.4, 0, 0.4 }) do
			mk(r, limb, "wedge", V(0.3, 0.6, 0.3), CF(s * 0.12 + x, 1.1, 0), spikeCol, neon and NEON or METAL)
		end
	end
end

local KNIGHT = {}

KNIGHT[1] = { name = "Squire", torso = K_RED, legs = K_BROWN, top = 1.7, attack = "slash", hold = true,
	build = function(r)
		cap(r, C(120, 82, 45), C(90, 60, 32))
		chestCross(r, K_WHITE)
		belt(r, C(205, 195, 150), C(160, 140, 90))
		boots(r, C(70, 62, 55))
		roundShield(r, K_WOOD, nil)
		blade(r, K_WOOD, C(120, 88, 55), C(120, 88, 55), 3.0, nil)
	end }

KNIGHT[2] = { name = "Footman", torso = K_RED, legs = K_BROWN, top = 1.8, attack = "slash", hold = true,
	build = function(r)
		mk(r, "Head", "ball", V(1.5, 1.1, 1.5), CF(0, 0.5, 0.03), K_STEEL, METAL) -- kettle hat
		mk(r, "Head", "cyl", V(0.12, 2.0, 2.0), CF(0, 0.38, 0.03) * ANG(0, 0, R(90)), K_STEEL, METAL)
		mk(r, "UpperTorso", "block", V(1.7, 1.5, 0.14), CF(0, 0, -0.55), C(140, 100, 62), FABRIC) -- leather vest
		mk(r, "UpperTorso", "block", V(0.06, 1.5, 0.05), CF(0, 0, -0.63), K_LEATHER, FABRIC)
		for _, y in ipairs({ 0.45, 0, -0.45 }) do
			mk(r, "UpperTorso", "ball", V(0.14, 0.14, 0.1), CF(-0.18, y, -0.63), K_STEEL, METAL)
			mk(r, "UpperTorso", "ball", V(0.14, 0.14, 0.1), CF(0.18, y, -0.63), K_STEEL, METAL)
		end
		belt(r, K_LEATHER, K_STEEL)
		gloves(r, K_LEATHER)
		boots(r, C(62, 52, 44))
		roundShield(r, K_WOOD, K_RED)
		blade(r, K_STEEL, K_GOLD, K_LEATHER, 3.6, nil)
	end }

KNIGHT[3] = { name = "Swordsman", torso = K_IRON, legs = K_LEATHER, top = 1.8, attack = "slash", hold = true,
	build = function(r)
		helmet(r, K_STEEL, K_IRON)
		mk(r, "Head", "block", V(0.18, 0.75, 0.1), CF(0, 0.2, -0.68), K_STEEL, METAL) -- nasal bar
		mk(r, "Head", "block", V(1.3, 0.4, 0.1), CF(0, -0.4, -0.62), K_IRON, METAL) -- mail over the chin
		mk(r, "UpperTorso", "block", V(2.04, 1.64, 1.06), CF(0, 0, 0), K_RED, FABRIC) -- tabard
		mk(r, "LowerTorso", "block", V(2.04, 0.7, 1.06), CF(0, -0.25, 0), K_RED, FABRIC)
		mk(r, "LowerTorso", "block", V(2.08, 0.12, 1.1), CF(0, -0.6, 0), K_GOLD, FABRIC)
		chestCross(r, K_WHITE)
		belt(r, K_LEATHER, K_GOLD)
		kneepads(r, K_IRON)
		gloves(r, K_LEATHER)
		boots(r, C(62, 52, 44))
		kiteShield(r, K_RED, K_STEEL, "cross", K_WHITE)
		blade(r, K_STEEL, K_GOLD, K_LEATHER, 4.0, nil)
	end }

KNIGHT[4] = { name = "Knight", torso = K_STEEL, legs = K_STEEL, top = 2.2, attack = "slash", hold = true,
	build = function(r)
		mk(r, "Head", "ball", V(1.6, 1.3, 1.6), CF(0, 0.45, 0.05), K_STEEL, METAL) -- open helm
		mk(r, "Head", "block", V(1.5, 0.5, 0.2), CF(0, 0.35, -0.68), C(30, 32, 38), METAL) -- visor
		plume(r, K_RED)
		chestPlate(r, K_STEEL, nil)
		mk(r, "UpperTorso", "block", V(0.8, 0.8, 0.1), CF(0, 0.1, -0.7) * ANG(0, 0, R(45)), K_RED, METAL)
		mk(r, "UpperTorso", "ball", V(0.3, 0.3, 0.12), CF(0, 0.1, -0.76), K_GOLD, METAL)
		pauldrons(r, K_STEEL)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.1, 0.1, 1.1), CF(0, 0.25, 0), K_RED, METAL)
		belt(r, K_DARK_RED, K_GOLD)
		kneepads(r, K_STEEL)
		gloves(r, K_IRON)
		boots(r, C(80, 86, 96))
		kiteShield(r, K_RED, K_STEEL, "star", K_GOLD)
		blade(r, K_STEEL, K_GOLD, K_LEATHER, 4.4, nil)
	end }

KNIGHT[5] = { name = "Elite Knight", torso = K_IRON, legs = K_IRON, top = 2.2, attack = "slash", hold = true,
	build = function(r)
		greatHelm(r, K_IRON, nil, nil)
		plume(r, K_RED)
		chestPlate(r, K_IRON, nil)
		mk(r, "UpperTorso", "block", V(1.7, 0.1, 0.1), CF(0, 0.6, -0.7), K_RED, METAL)
		mk(r, "UpperTorso", "block", V(0.75, 0.75, 0.1), CF(0, 0, -0.7) * ANG(0, 0, R(45)), K_RED, METAL)
		spikedPauldrons(r, K_IRON, K_RED, false)
		both(r, { "LeftLowerArm", "RightLowerArm" }, "block", V(1.1, 0.7, 1.1), CF(0, 0, 0), K_IRON, METAL)
		belt(r, C(60, 64, 72), K_RED)
		for _, l in ipairs({ "LeftLowerLeg", "RightLowerLeg" }) do
			mk(r, l, "block", V(1.1, 0.7, 0.3), CF(0, 0.5, -0.52), K_IRON, METAL)
			mk(r, l, "block", V(0.4, 0.4, 0.08), CF(0, 0.5, -0.7) * ANG(0, 0, R(45)), K_RED, METAL)
		end
		gloves(r, C(60, 64, 72))
		boots(r, C(60, 64, 72))
		kiteShield(r, K_DARK_RED, K_STEEL, "cross", K_WHITE)
		blade(r, K_STEEL, K_RED, K_LEATHER, 4.6, nil)
	end }

KNIGHT[6] = { name = "Paladin", torso = K_STEEL, legs = K_STEEL, top = 2.5, attack = "slash", hold = true,
	build = function(r)
		greatHelm(r, K_STEEL, K_GOLD, nil)
		horns(r, K_BONE, false)
		plume(r, K_RED)
		cloak(r, K_RED, K_GOLD, 4.2)
		chestPlate(r, K_STEEL, nil)
		mk(r, "UpperTorso", "block", V(1.9, 0.14, 0.1), CF(0, 0.65, -0.7), K_GOLD, METAL)
		mk(r, "UpperTorso", "block", V(1.9, 0.14, 0.1), CF(0, -0.6, -0.7), K_GOLD, METAL)
		mk(r, "UpperTorso", "cyl", V(0.12, 0.9, 0.9), CF(0, 0.05, -0.72) * ANG(0, R(90), 0), K_GOLD, METAL)
		mk(r, "UpperTorso", "cyl", V(0.14, 0.7, 0.7), CF(0, 0.05, -0.74) * ANG(0, R(90), 0), C(255, 244, 214), NEON, { light = K_GOLD, range = 10 })
		mk(r, "UpperTorso", "block", V(0.16, 0.48, 0.06), CF(0, 0.05, -0.83), K_RED, PLASTIC)
		mk(r, "UpperTorso", "block", V(0.48, 0.16, 0.06), CF(0, 0.05, -0.83), K_RED, PLASTIC)
		spikedPauldrons(r, K_GOLD, K_STEEL, false)
		belt(r, C(150, 115, 30), K_GOLD)
		kneepads(r, K_STEEL)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(1.0, 0.1, 0.1), CF(0, 0.75, -0.68), K_GOLD, METAL)
		gloves(r, K_GOLD)
		boots(r, K_GOLD)
		kiteShield(r, K_RED, K_GOLD, "crown", K_GOLD)
		blade(r, K_WHITE, K_GOLD, K_LEATHER, 5.0, nil)
	end }

KNIGHT[7] = { name = "Dragon Knight", torso = K_DARK_RED, legs = K_DARK_RED, top = 2.8, attack = "slash", hold = true,
	build = function(r)
		local D = C(140, 38, 55)
		greatHelm(r, D, nil, K_FIRE)
		horns(r, K_BLACK, false)
		mk(r, "Head", "ball", V(0.4, 0.7, 0.4), CF(0, 1.3, 0), K_FIRE, NEON, { light = K_FIRE, range = 10 })
		mk(r, "Head", "ball", V(0.2, 0.4, 0.2), CF(0, 1.25, -0.05), K_FLAME, NEON)
		chestPlate(r, D, nil)
		for row = 0, 2 do -- scales
			for col = -2, 2 do
				mk(r, "UpperTorso", "ball", V(0.36, 0.3, 0.1), CF(col * 0.36 + (row % 2) * 0.18 - 0.09, 0.45 - row * 0.4, -0.7), K_DARK_RED, METAL)
			end
		end
		mk(r, "UpperTorso", "cyl", V(0.12, 0.8, 0.8), CF(0, 0.05, -0.74) * ANG(0, R(90), 0), K_BLACK, METAL)
		mk(r, "UpperTorso", "ball", V(0.4, 0.55, 0.2), CF(0, 0.05, -0.8), K_FIRE, NEON, { light = K_FIRE, range = 12, bright = 3 })
		spikedPauldrons(r, D, K_BLACK, false)
		for _, s in ipairs({ -1, 1 }) do -- small dragon wings
			mk(r, "UpperTorso", "block", V(2.0, 1.6, 0.1), CF(s * 1.9, 0.6, 0.7) * ANG(0, R(s * -25), R(s * 20)), K_DARK_RED, PLASTIC)
			mk(r, "UpperTorso", "block", V(2.0, 0.08, 0.12), CF(s * 1.9, 1.4, 0.7) * ANG(0, R(s * -25), R(s * 20)), K_FIRE, NEON)
		end
		belt(r, K_BLACK, K_FIRE)
		kneepads(r, D)
		gloves(r, K_BLACK)
		boots(r, K_BLACK)
		kiteShield(r, K_DARK_RED, K_FIRE, "flame", K_FIRE)
		blade(r, C(235, 220, 200), K_FIRE, K_LEATHER, 5.2, nil)
		mk(r, "RightHand", "block", V(0.3, 0.5, 5.2), CF(0, -0.15, -3.1), K_FIRE, NEON, { light = K_FIRE, range = 12 }).Transparency = 0.7
	end }

KNIGHT[8] = { name = "Grandmaster", torso = K_BLACK, legs = K_BLACK, top = 2.9, attack = "slash", hold = true,
	build = function(r)
		greatHelm(r, K_BLACK, K_GOLD, nil)
		mk(r, "Head", "block", V(0.2, 1.3, 0.5), CF(0, 1.4, 0.1), K_RED, FABRIC) -- red plume
		mk(r, "Head", "block", V(0.3, 1.0, 0.4), CF(-0.4, 1.25, 0) * ANG(0, 0, R(12)), K_GOLD, METAL) -- gold feathers
		mk(r, "Head", "block", V(0.3, 1.0, 0.4), CF(0.4, 1.25, 0) * ANG(0, 0, R(-12)), K_GOLD, METAL)
		cloak(r, K_RED, K_GOLD, 4.6)
		chestPlate(r, K_BLACK, nil)
		mk(r, "UpperTorso", "block", V(1.9, 0.14, 0.1), CF(0, 0.68, -0.7), K_GOLD, METAL)
		mk(r, "UpperTorso", "block", V(0.95, 0.95, 0.1), CF(0, 0.05, -0.7) * ANG(0, 0, R(45)), K_GOLD, METAL)
		mk(r, "UpperTorso", "block", V(0.75, 0.75, 0.1), CF(0, 0.05, -0.73) * ANG(0, 0, R(45)), K_RED, METAL)
		mk(r, "UpperTorso", "block", V(0.4, 0.22, 0.08), CF(0, 0.1, -0.8), K_GOLD, METAL)
		spikedPauldrons(r, K_BLACK, K_GOLD, false)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.3, 0.1, 1.3), CF(0, 0.3, 0), K_GOLD, METAL)
		belt(r, C(170, 130, 35), K_GOLD)
		kneepads(r, K_BLACK)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(1.0, 0.1, 0.1), CF(0, 0.75, -0.68), K_GOLD, METAL)
		gloves(r, K_GOLD)
		boots(r, K_BLACK)
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.1, 0.14, 1.25), CF(0, -0.02, -0.05), K_GOLD, METAL)
		kiteShield(r, K_BLACK, K_GOLD, "crown", K_GOLD)
		blade(r, K_STEEL, K_GOLD, K_DARK_RED, 5.8, nil)
		mk(r, "RightHand", "block", V(0.16, 0.1, 5.0), CF(0, -0.15, -3.2), K_RED, PLASTIC)
	end }

KNIGHT[9] = { name = "Legend", torso = C(70, 34, 44), legs = C(52, 28, 38), top = 3.4, attack = "slash", hold = true,
	build = function(r)
		local E = C(70, 34, 44)
		greatHelm(r, E, nil, nil)
		mk(r, "Head", "block", V(1.15, 0.5, 0.1), CF(0, 0.15, -0.76), C(12, 8, 10), PLASTIC) -- visor
		mk(r, "Head", "ball", V(0.26, 0.36, 0.1), CF(-0.28, 0.15, -0.82), C(255, 245, 200), NEON, { light = K_FLAME, range = 8 })
		mk(r, "Head", "ball", V(0.26, 0.36, 0.1), CF(0.28, 0.15, -0.82), C(255, 245, 200), NEON)
		horns(r, K_GOLD, false)
		for i = -2, 2 do -- the crown of flames
			mk(r, "Head", "ball", V(0.3, 0.9 - math.abs(i) * 0.15, 0.3), CF(i * 0.3, 1.25, 0), K_FIRE, NEON, i == 0 and { light = K_FIRE, range = 12, bright = 3 } or nil)
			mk(r, "Head", "ball", V(0.14, 0.45 - math.abs(i) * 0.08, 0.14), CF(i * 0.3, 1.15, -0.1), K_FLAME, NEON)
		end
		for i = 0, 17 do -- the halo
			local a = i / 18 * math.pi * 2
			mk(r, "Head", "block", V(0.4, 0.1, 0.2), CF(math.cos(a) * 1.15, 2.45, math.sin(a) * 1.15) * ANG(0, -a, 0), K_FLAME, NEON, i == 0 and { light = K_FLAME, range = 16, bright = 3 } or nil)
		end
		chestPlate(r, E, K_FIRE)
		mk(r, "UpperTorso", "cyl", V(0.12, 0.9, 0.9), CF(0, 0.1, -0.74) * ANG(0, R(90), 0), K_FLAME, NEON)
		mk(r, "UpperTorso", "ball", V(0.45, 0.65, 0.2), CF(0, 0.1, -0.82), K_FIRE, NEON, { light = K_FIRE, range = 16, bright = 4, sparkle = K_FIRE, rate = 25 })
		spikedPauldrons(r, E, K_FIRE, true)
		both(r, { "LeftLowerArm", "RightLowerArm" }, "block", V(1.12, 0.8, 1.12), CF(0, 0, 0), E, METAL)
		belt(r, C(40, 22, 28), K_FIRE)
		kneepads(r, E)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.6, 0.1, 0.08), CF(0, 0.5, -0.69) * ANG(0, 0, R(35)), K_FIRE, NEON)
		gloves(r, C(40, 22, 28))
		boots(r, C(36, 22, 28))
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.1, 0.12, 1.25), CF(0, -0.05, -0.05), K_FIRE, NEON)
		-- the wings of fire
		for _, s in ipairs({ -1, 1 }) do
			for i = 1, 6 do
				local phi = R(-55 + i * 22)
				local L = 2.2 + math.sin(i * 0.55) * 1.7
				mk(r, "UpperTorso", "block", V(L, 0.1, 0.5), CF(s * (0.8 + math.cos(phi) * L / 2), 0.4 + math.sin(phi) * L / 2, 0.75 + i * 0.05) * ANG(0, 0, s * phi), i % 2 == 0 and K_FLAME or K_FIRE, NEON, (i == 3) and { light = K_FIRE, range = 14, bright = 2 } or nil)
			end
		end
		kiteShield(r, E, K_FLAME, "flame", K_FIRE)
		-- the glowing sword
		mk(r, "RightHand", "block", V(0.28, 0.28, 0.9), CF(0, -0.15, 0.1), C(90, 40, 48), METAL)
		mk(r, "RightHand", "block", V(1.2, 0.26, 0.3), CF(0, -0.15, -0.4), K_GOLD, METAL)
		local glow = mk(r, "RightHand", "block", V(0.55, 0.55, 6.4), CF(0, -0.15, -3.8), K_FIRE, NEON, { light = K_FIRE, range = 20, bright = 4 })
		if glow then
			glow.Transparency = 0.55
		end
		mk(r, "RightHand", "block", V(0.18, 0.4, 6.2), CF(0, -0.15, -3.7), C(255, 245, 215), NEON)
		-- floating flames
		for _, p in ipairs({ { -3.2, 2.2, 0.5 }, { 3.4, 3.0, -0.4 }, { -3.0, -0.6, -0.7 }, { 3.2, -0.2, 0.6 }, { -2.2, 4.2, 0.0 }, { 2.4, 4.6, 0.3 } }) do
			mk(r, "UpperTorso", "ball", V(0.35, 0.6, 0.35), CF(p[1], p[2], p[3]), K_FIRE, NEON, { light = K_FIRE, range = 8 })
		end
		local aura = mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.4), CF(0, 0, 0), K_FLAME, NEON, { sparkle = K_FLAME, rate = 40 })
		if aura then
			aura.Transparency = 1
		end
	end }

-- ── The Archer: 9 levels (design: the green archer cards) ──
--   1 Apprentice · 2 Marksman · 3 Tracker · 4 Ranger · 5 Elven Archer · 6 Shadow Stalker · 7 Storm Archer ·
--   8 Royal Master · 9 Legend
local A_GREEN = C(104, 160, 88)
local A_DARK_GREEN = C(52, 96, 52)
local A_FOREST = C(30, 62, 34)
local A_BROWN = C(120, 90, 62)
local A_LEATHER = C(96, 66, 42)
local A_DARK = C(62, 48, 40)
local A_WOOD = C(176, 126, 78)
local A_SILVER = C(214, 220, 222)
local A_GOLD = C(240, 196, 80)
local A_MINT = C(110, 255, 170)
local A_LIME = C(120, 255, 100)
local A_CYAN = C(40, 220, 255)
local A_SHADOW = C(34, 44, 40)
local A_RED = C(200, 34, 50)
local A_SHAFT = C(222, 204, 160)

-- A bow in the left hand (it stands upright next to the hand, the string toward the body).
local function bow(r, col, length, stringCol, glow)
	local at = CF(-0.15, 0, -0.75)
	mk(r, "LeftHand", "block", V(0.3, 0.6, 0.34), at, A_LEATHER, FABRIC) -- grip
	mk(r, "LeftHand", "block", V(0.2, length * 0.24, 0.26), at * CF(0, length * 0.14, 0.03) * ANG(R(10), 0, 0), col, glow and NEON or Enum.Material.Wood)
	mk(r, "LeftHand", "block", V(0.2, length * 0.24, 0.26), at * CF(0, -length * 0.14, 0.03) * ANG(R(-10), 0, 0), col, glow and NEON or Enum.Material.Wood)
	mk(r, "LeftHand", "block", V(0.18, length * 0.26, 0.22), at * CF(0, length * 0.36, 0.2) * ANG(R(28), 0, 0), col, glow and NEON or Enum.Material.Wood, glow and { light = glow, range = 10 } or nil)
	mk(r, "LeftHand", "block", V(0.18, length * 0.26, 0.22), at * CF(0, -length * 0.36, 0.2) * ANG(R(-28), 0, 0), col, glow and NEON or Enum.Material.Wood)
	mk(r, "LeftHand", "block", V(0.05, length * 0.92, 0.05), at * CF(0, 0, 0.36), stringCol, glow and NEON or PLASTIC)
end

-- A quiver on the back with `count` arrows (their fletching in `fletch` / white).
local function quiver(r, col, fletch, count)
	local at = CF(0.45, 0.25, 0.78) * ANG(0, 0, R(-18))
	mk(r, "UpperTorso", "block", V(0.6, 1.6, 0.5), at, col, FABRIC)
	for i = 1, count do
		local x = (i - (count + 1) / 2) * 0.16
		mk(r, "UpperTorso", "block", V(0.07, 0.9, 0.07), at * CF(x, 1.1, 0), A_SHAFT, PLASTIC)
		mk(r, "UpperTorso", "wedge", V(0.1, 0.36, 0.3), at * CF(x, 1.6, 0), i % 2 == 0 and fletch or K_WHITE, PLASTIC)
	end
end

-- A hood around the head (the face stays open).
local function hood(r, col)
	mk(r, "Head", "block", V(1.6, 0.4, 1.55), CF(0, 0.75, 0.05), col, FABRIC)
	mk(r, "Head", "block", V(1.6, 1.6, 0.3), CF(0, 0.05, 0.72), col, FABRIC)
	mk(r, "Head", "block", V(0.24, 1.5, 1.35), CF(-0.72, 0.05, 0.08), col, FABRIC)
	mk(r, "Head", "block", V(0.24, 1.5, 1.35), CF(0.72, 0.05, 0.08), col, FABRIC)
end

local function bracers(r, col, trim)
	both(r, { "LeftLowerArm", "RightLowerArm" }, "block", V(1.1, 0.7, 1.1), CF(0, 0, 0), col, FABRIC)
	if trim then
		both(r, { "LeftLowerArm", "RightLowerArm" }, "block", V(0.8, 0.08, 0.08), CF(0, 0.1, -0.56), trim, NEON)
	end
end

local function shoulderPads(r, col, mat, trim)
	both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.5, 0.5, 1.4), CF(0, 0.55, 0), col, mat)
	if trim then
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.1, 0.08, 0.08), CF(0, 0.55, -0.72), trim, NEON)
	end
end

local function feather(r, col, stripe)
	mk(r, "Head", "block", V(0.12, 1.0, 0.4), CF(0.35, 1.3, 0.1) * ANG(R(-20), 0, R(-30)), col, FABRIC)
	if stripe then
		mk(r, "Head", "block", V(0.14, 0.8, 0.1), CF(0.35, 1.3, 0.1) * ANG(R(-20), 0, R(-30)), stripe, FABRIC)
	end
end

local function elfEars(r, col)
	mk(r, "Head", "block", V(0.7, 0.22, 0.12), CF(-0.9, 0.3, 0) * ANG(0, 0, R(-25)), col, PLASTIC)
	mk(r, "Head", "block", V(0.7, 0.22, 0.12), CF(0.9, 0.3, 0) * ANG(0, 0, R(25)), col, PLASTIC)
end

-- The leaf emblem on the chest: two leaves and a gem.
local function leaf(r, col, gem)
	mk(r, "UpperTorso", "ball", V(0.35, 0.8, 0.1), CF(-0.2, 0.15, -0.72) * ANG(0, 0, R(20)), col, PLASTIC)
	mk(r, "UpperTorso", "ball", V(0.35, 0.8, 0.1), CF(0.2, 0.15, -0.72) * ANG(0, 0, R(-20)), col, PLASTIC)
	if gem then
		mk(r, "UpperTorso", "ball", V(0.22, 0.22, 0.12), CF(0, -0.3, -0.74), gem, NEON, { light = gem, range = 8 })
	end
end

local ARCHER = {}

ARCHER[1] = { name = "Apprentice", torso = A_GREEN, legs = A_BROWN, top = 1.9, attack = "lunge", hold = false,
	build = function(r)
		cap(r, C(120, 82, 45), C(90, 60, 32))
		mk(r, "Head", "wedge", V(0.1, 0.5, 0.5), CF(0.55, 0.95, 0.1) * ANG(R(-30), 0, R(-25)), A_RED, FABRIC) -- red feather
		mk(r, "UpperTorso", "block", V(0.22, 2.2, 0.1), CF(0, 0, -0.55) * ANG(0, 0, R(42)), A_DARK, FABRIC) -- strap
		belt(r, A_DARK, A_GOLD)
		boots(r, C(70, 60, 54))
		quiver(r, A_LEATHER, A_RED, 3)
		bow(r, A_WOOD, 3.6, K_WHITE, nil)
	end }

ARCHER[2] = { name = "Marksman", torso = A_GREEN, legs = A_BROWN, top = 2.0, attack = "lunge", hold = false,
	build = function(r)
		hood(r, A_DARK_GREEN)
		mk(r, "UpperTorso", "block", V(1.7, 0.9, 0.14), CF(0, 0.3, -0.55), A_BROWN, FABRIC) -- leather chest piece
		for _, x in ipairs({ -0.4, 0, 0.4 }) do
			mk(r, "UpperTorso", "block", V(0.05, 0.8, 0.05), CF(x, 0.3, -0.63), A_DARK, FABRIC)
		end
		bracers(r, A_BROWN, nil)
		gloves(r, A_LEATHER)
		belt(r, A_DARK, A_GOLD)
		mk(r, "LowerTorso", "block", V(0.55, 0.5, 0.3), CF(-0.6, -0.15, -0.6), A_BROWN, FABRIC) -- pouch
		boots(r, C(70, 60, 54))
		quiver(r, A_LEATHER, A_RED, 4)
		bow(r, C(130, 84, 44), 3.8, K_WHITE, nil)
	end }

ARCHER[3] = { name = "Tracker", torso = A_DARK_GREEN, legs = A_LEATHER, top = 2.0, attack = "lunge", hold = false,
	build = function(r)
		hood(r, A_DARK_GREEN)
		cloak(r, A_FOREST, A_FOREST, 4.0)
		mk(r, "UpperTorso", "block", V(1.8, 1.5, 0.16), CF(0, 0, -0.55), C(150, 106, 66), FABRIC) -- leather armor
		mk(r, "UpperTorso", "block", V(0.16, 2.0, 0.06), CF(0, 0, -0.65) * ANG(0, 0, R(48)), A_DARK, FABRIC)
		mk(r, "UpperTorso", "block", V(0.16, 2.0, 0.06), CF(0, 0, -0.65) * ANG(0, 0, R(-48)), A_DARK, FABRIC)
		mk(r, "UpperTorso", "ball", V(0.26, 0.26, 0.12), CF(0, 0, -0.68), A_GOLD, METAL)
		shoulderPads(r, A_BROWN, FABRIC, nil)
		bracers(r, C(150, 106, 66), nil)
		gloves(r, A_DARK)
		belt(r, A_LEATHER, A_GOLD)
		kneepads(r, A_BROWN)
		boots(r, C(62, 52, 46))
		quiver(r, A_LEATHER, A_RED, 5)
		bow(r, C(120, 70, 36), 4.4, K_WHITE, nil)
	end }

ARCHER[4] = { name = "Ranger", torso = A_DARK_GREEN, legs = A_LEATHER, top = 2.6, attack = "lunge", hold = false,
	build = function(r)
		hood(r, A_DARK_GREEN)
		feather(r, K_WHITE, A_RED)
		cloak(r, A_FOREST, A_FOREST, 4.3)
		mk(r, "UpperTorso", "block", V(1.8, 1.55, 0.16), CF(0, 0, -0.55), A_LEATHER, FABRIC)
		leaf(r, C(70, 150, 60), nil)
		shoulderPads(r, C(128, 112, 100), FABRIC, nil) -- fur
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.55, 0.14, 1.45), CF(0, 0.85, 0), C(226, 216, 196), FABRIC)
		bracers(r, A_LEATHER, nil)
		both(r, { "LeftLowerArm", "RightLowerArm" }, "block", V(0.8, 0.1, 0.08), CF(0, 0.1, -0.56), C(70, 150, 60), FABRIC)
		gloves(r, A_DARK)
		belt(r, A_DARK, A_GOLD)
		boots(r, C(56, 46, 42))
		quiver(r, A_LEATHER, C(70, 150, 60), 5)
		bow(r, C(96, 58, 30), 4.6, K_WHITE, nil)
	end }

ARCHER[5] = { name = "Elven Archer", torso = A_SILVER, legs = C(66, 100, 80), top = 2.1, attack = "lunge", hold = false,
	build = function(r)
		mk(r, "Head", "ball", V(1.45, 0.8, 1.45), CF(0, 0.55, 0.08), C(200, 165, 80), FABRIC) -- hair
		mk(r, "Head", "block", V(1.3, 0.12, 0.1), CF(0, 0.5, -0.62), A_GOLD, METAL) -- diadem
		mk(r, "Head", "block", V(0.2, 0.2, 0.1), CF(0, 0.5, -0.66) * ANG(0, 0, R(45)), A_MINT, NEON, { light = A_MINT, range = 8 })
		elfEars(r, SKIN)
		cloak(r, C(40, 90, 66), C(40, 90, 66), 4.2)
		chestPlate(r, A_SILVER, nil)
		leaf(r, A_DARK_GREEN, A_MINT)
		shoulderPads(r, A_SILVER, METAL, A_MINT)
		bracers(r, A_SILVER, A_MINT)
		gloves(r, A_SILVER)
		belt(r, C(40, 70, 56), A_GOLD)
		kneepads(r, A_SILVER)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "ball", V(0.16, 0.4, 0.08), CF(0, 0.5, -0.69), A_MINT, NEON)
		boots(r, A_SILVER)
		quiver(r, C(60, 96, 76), A_MINT, 5)
		bow(r, C(236, 226, 196), 4.8, A_MINT, A_MINT)
	end }

ARCHER[6] = { name = "Shadow Stalker", torso = A_SHADOW, legs = C(44, 46, 46), top = 2.1, attack = "lunge", hold = false,
	build = function(r)
		hood(r, C(26, 40, 34))
		mk(r, "Head", "block", V(1.24, 1.24, 0.1), CF(0, 0, -0.6), C(8, 12, 10), PLASTIC) -- the face in shadow
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(-0.25, 0.15, -0.66), A_LIME, NEON, { light = A_LIME, range = 8 })
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(0.25, 0.15, -0.66), A_LIME, NEON)
		cloak(r, C(18, 26, 22), C(18, 26, 22), 4.6)
		chestPlate(r, A_SHADOW, nil)
		mk(r, "UpperTorso", "block", V(0.45, 0.45, 0.1), CF(0, 0.05, -0.72) * ANG(0, 0, R(45)), A_LIME, NEON, { light = A_LIME, range = 10 })
		mk(r, "UpperTorso", "block", V(1.4, 0.06, 0.08), CF(0, -0.3, -0.71), A_LIME, NEON)
		mk(r, "UpperTorso", "block", V(0.8, 0.06, 0.08), CF(-0.35, 0.55, -0.71) * ANG(0, 0, R(18)), A_LIME, NEON)
		mk(r, "UpperTorso", "block", V(0.8, 0.06, 0.08), CF(0.35, 0.55, -0.71) * ANG(0, 0, R(-18)), A_LIME, NEON)
		shoulderPads(r, C(40, 52, 46), METAL, nil)
		bracers(r, C(40, 52, 46), A_LIME)
		gloves(r, C(30, 32, 32))
		belt(r, C(24, 28, 26), C(40, 52, 46))
		kneepads(r, C(40, 52, 46))
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.8, 0.07, 0.08), CF(0, 0.55, -0.69), A_LIME, NEON)
		boots(r, C(28, 30, 30))
		quiver(r, C(30, 40, 36), A_LIME, 5)
		mk(r, "UpperTorso", "block", V(0.5, 1.5, 0.45), CF(-0.5, 0.25, 0.78) * ANG(0, 0, R(18)), C(30, 40, 36), FABRIC) -- the second quiver
		bow(r, C(36, 48, 42), 5.0, A_LIME, nil)
		mk(r, "LeftHand", "block", V(0.06, 4.6, 0.06), CF(-0.15, 0, -0.39), A_LIME, NEON, { light = A_LIME, range = 8 })
	end }

ARCHER[7] = { name = "Storm Archer", torso = C(230, 236, 236), legs = C(54, 76, 86), top = 2.3, attack = "lunge", hold = false,
	build = function(r)
		mk(r, "Head", "ball", V(1.6, 1.2, 1.6), CF(0, 0.5, 0.06), C(230, 236, 236), METAL) -- helmet
		mk(r, "Head", "block", V(1.5, 0.42, 0.2), CF(0, 0.2, -0.66), C(16, 30, 44), PLASTIC) -- visor
		mk(r, "Head", "block", V(1.2, 0.16, 0.08), CF(0, 0.2, -0.78), A_CYAN, NEON, { light = A_CYAN, range = 10 })
		for _, s in ipairs({ -1, 1 }) do -- lightning fins
			mk(r, "Head", "wedge", V(0.12, 0.9, 0.5), CF(s * 0.85, 0.9, 0.1) * ANG(0, 0, R(s * -25)), A_CYAN, NEON)
		end
		chestPlate(r, C(230, 236, 236), nil)
		mk(r, "UpperTorso", "block", V(1.2, 0.07, 0.08), CF(0, 0.4, -0.71), A_CYAN, NEON)
		mk(r, "UpperTorso", "block", V(1.2, 0.07, 0.08), CF(0, 0, -0.71), A_CYAN, NEON)
		mk(r, "UpperTorso", "ball", V(0.26, 0.26, 0.12), CF(0, -0.4, -0.72), A_CYAN, NEON, { light = A_CYAN, range = 12, bright = 3 })
		shoulderPads(r, C(230, 236, 236), METAL, A_CYAN)
		bracers(r, C(230, 236, 236), A_CYAN)
		gloves(r, C(230, 236, 236))
		belt(r, C(30, 44, 52), C(54, 76, 86))
		kneepads(r, C(230, 236, 236))
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.8, 0.07, 0.08), CF(0, 0.55, -0.69), A_CYAN, NEON)
		boots(r, C(30, 44, 52))
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.12, 0.12, 1.27), CF(0, 0.15, -0.05), A_CYAN, NEON)
		both(r, { "LeftFoot", "RightFoot" }, "cyl", V(0.08, 2.4, 2.4), CF(0, -0.5, 0) * ANG(0, 0, R(90)), A_CYAN, NEON, { light = A_CYAN, range = 8 })
		quiver(r, C(54, 76, 86), A_CYAN, 5)
		bow(r, C(236, 240, 240), 5.2, A_CYAN, A_CYAN)
		for _, p in ipairs({ { -2.8, 2.4, 0.4 }, { 2.9, 2.9, -0.3 }, { -2.5, 0.2, -0.6 }, { 2.7, 0.6, 0.5 } }) do -- floating arrowheads
			mk(r, "UpperTorso", "wedge", V(0.12, 0.5, 0.4), CF(p[1], p[2], p[3]) * ANG(R(30), 0, R(40)), A_CYAN, NEON)
		end
	end }

ARCHER[8] = { name = "Royal Master", torso = A_DARK_GREEN, legs = C(40, 78, 52), top = 2.7, attack = "lunge", hold = false,
	build = function(r)
		mk(r, "Head", "ball", V(1.5, 1.0, 1.5), CF(0, 0.6, 0.05), C(40, 110, 60), FABRIC) -- the royal cap
		mk(r, "Head", "block", V(1.62, 0.2, 1.62), CF(0, 0.38, 0.02), A_GOLD, METAL)
		mk(r, "Head", "ball", V(0.3, 0.3, 0.14), CF(0, 0.75, -0.66), A_RED, NEON)
		feather(r, K_WHITE, A_RED)
		cloak(r, A_RED, A_GOLD, 4.6)
		chestPlate(r, C(56, 110, 70), nil)
		mk(r, "UpperTorso", "block", V(1.9, 0.12, 0.1), CF(0, 0.66, -0.7), A_GOLD, METAL)
		mk(r, "UpperTorso", "block", V(1.9, 0.12, 0.1), CF(0, -0.62, -0.7), A_GOLD, METAL)
		leaf(r, A_GOLD, A_RED)
		shoulderPads(r, C(56, 110, 70), METAL, nil)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.2, 0.08, 0.08), CF(0, 0.6, -0.72), A_GOLD, METAL)
		bracers(r, A_GOLD, nil)
		gloves(r, A_GOLD)
		belt(r, C(170, 130, 35), A_GOLD)
		kneepads(r, C(34, 34, 34))
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(1.0, 0.1, 0.1), CF(0, 0.75, -0.68), A_GOLD, METAL)
		boots(r, C(34, 34, 34))
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.1, 0.14, 1.25), CF(0, -0.02, -0.05), A_GOLD, METAL)
		quiver(r, C(120, 30, 40), A_GOLD, 5)
		bow(r, A_GOLD, 5.4, K_WHITE, nil)
		-- the fan of arrows behind the back
		for i = -4, 4 do
			local a = R(i * 20)
			mk(r, "UpperTorso", "block", V(0.08, 2.6, 0.08), CF(math.sin(a) * 2.6, 1.0 + math.cos(a) * 2.6, 0.95) * ANG(0, 0, -a), A_SHAFT, PLASTIC)
			mk(r, "UpperTorso", "block", V(0.3, 0.3, 0.1), CF(math.sin(a) * 4.0, 1.0 + math.cos(a) * 4.0, 0.95) * ANG(0, 0, -a + R(45)), A_GOLD, METAL)
			mk(r, "UpperTorso", "block", V(0.3, 0.4, 0.1), CF(math.sin(a) * 1.4, 1.0 + math.cos(a) * 1.4, 0.95) * ANG(0, 0, -a), A_RED, FABRIC)
		end
	end }

ARCHER[9] = { name = "Legend", torso = C(46, 160, 120), legs = C(38, 140, 104), top = 3.1, attack = "lunge", hold = false,
	build = function(r)
		local G = C(255, 216, 107)
		local GD = C(199, 154, 30)
		mk(r, "Head", "ball", V(1.5, 0.9, 1.5), CF(0, 0.5, 0.06), G, METAL) -- golden hair / crown base
		for i = -2, 2 do
			mk(r, "Head", "wedge", V(0.22, 1.0 - math.abs(i) * 0.15, 0.3), CF(i * 0.3, 1.25, 0.0) * ANG(0, R(180), 0), G, METAL)
		end
		elfEars(r, G)
		mk(r, "Head", "ball", V(0.16, 0.3, 0.08), CF(-0.26, 0.12, -0.62), A_MINT, NEON, { light = A_MINT, range = 8 })
		mk(r, "Head", "ball", V(0.16, 0.3, 0.08), CF(0.26, 0.12, -0.62), A_MINT, NEON)
		for i = 0, 17 do -- the halo
			local a = i / 18 * math.pi * 2
			mk(r, "Head", "block", V(0.4, 0.1, 0.2), CF(math.cos(a) * 1.15, 2.45, math.sin(a) * 1.15) * ANG(0, -a, 0), G, NEON, i == 0 and { light = G, range = 16, bright = 3 } or nil)
		end
		mk(r, "UpperTorso", "block", V(1.8, 1.4, 0.3), CF(0, 0.05, -0.6), G, METAL)
		mk(r, "UpperTorso", "block", V(0.8, 0.8, 0.15), CF(0, 0.15, -0.8) * ANG(0, 0, R(45)), C(5, 60, 44), METAL)
		mk(r, "UpperTorso", "block", V(0.45, 0.45, 0.2), CF(0, 0.15, -0.88) * ANG(0, 0, R(45)), A_MINT, NEON, { light = A_MINT, range = 16, bright = 4, sparkle = A_MINT, rate = 25 })
		for _, s in ipairs({ -1, 1 }) do
			local limb = s < 0 and "LeftUpperArm" or "RightUpperArm"
			mk(r, limb, "block", V(1.7, 0.55, 1.7), CF(0, 0.55, 0), G, METAL)
			mk(r, limb, "wedge", V(0.4, 0.8, 0.4), CF(s * 0.2, 1.1, 0) * ANG(0, R(180), 0), G, METAL)
		end
		bracers(r, G, nil)
		gloves(r, GD)
		belt(r, GD, G)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(1.15, 0.9, 1.15), CF(0, 0.1, 0), G, METAL)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.3, 0.3, 0.08), CF(0, 0.3, -0.6) * ANG(0, 0, R(45)), A_MINT, NEON)
		boots(r, G)
		-- the wings of light
		for _, s in ipairs({ -1, 1 }) do
			for i = 1, 6 do
				local phi = R(-55 + i * 22)
				local L = 2.2 + math.sin(i * 0.55) * 1.7
				mk(r, "UpperTorso", "block", V(L, 0.1, 0.5), CF(s * (0.8 + math.cos(phi) * L / 2), 0.4 + math.sin(phi) * L / 2, 0.75 + i * 0.05) * ANG(0, 0, s * phi), i % 2 == 0 and C(255, 255, 255) or A_MINT, NEON, (i == 3) and { light = A_MINT, range = 14, bright = 2 } or nil)
			end
		end
		quiver(r, GD, A_MINT, 5)
		bow(r, G, 5.6, C(255, 255, 255), A_MINT)
		mk(r, "LeftHand", "block", V(0.14, 0.14, 2.4), CF(-0.15, 0, -1.6), A_MINT, NEON, { light = A_MINT, range = 10 }) -- an arrow of light on the string
		for _, p in ipairs({ { -3.2, 2.2, 0.5 }, { 3.4, 3.0, -0.4 }, { -3.0, -0.6, -0.7 }, { 3.2, -0.2, 0.6 } }) do
			mk(r, "UpperTorso", "wedge", V(0.12, 0.45, 0.35), CF(p[1], p[2], p[3]) * ANG(R(30), 0, R(40)), C(255, 255, 255), NEON)
		end
		local aura = mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.4), CF(0, 0, 0), G, NEON, { sparkle = G, rate = 40 })
		if aura then
			aura.Transparency = 1
		end
	end }

-- ── The Mage: 9 levels (design: the purple mage cards) ──
--   1 Novice · 2 Sorcerer · 3 Wizard · 4 Mage · 5 Arcanist · 6 Archmage · 7 Cosmic Mage · 8 Grand Mage · 9 Legend
local M_TUNIC = C(122, 112, 146)
local M_TUNIC_DARK = C(82, 74, 100)
local M_PURPLE = C(120, 90, 172)
local M_PURPLE_DARK = C(78, 56, 118)
local M_NAVY = C(44, 42, 92)
local M_INDIGO = C(64, 66, 130)
local M_HAT = C(50, 40, 70)
local M_HAT_BROWN = C(62, 46, 72)
local M_GOLD = C(214, 170, 60)
local M_GOLD_LIGHT = C(240, 200, 70)
local M_GOLD_DARK = C(170, 128, 44)
local M_WOOD = C(72, 52, 40)
local M_WHITE = C(236, 236, 242)
local M_CRYSTAL = C(176, 150, 255)
local M_VIOLET = C(200, 150, 255)
local M_CYAN = C(130, 210, 255)
local M_BLUE = C(150, 205, 255)
local M_ORANGE = C(255, 160, 70)
local M_PINK = C(255, 130, 210)
local M_SKY = C(200, 218, 250)
local M_SILVER = C(222, 222, 236)
local M_PAGES = C(240, 226, 196)

-- A pointy hat: a brim, a band and a cone of shrinking cylinders whose tip leans back a little
-- (a straight cone looks like a gnome). `stars` = the color of the little stars on the cone, or nil.
-- Returns how high the tip is above the head's center.
local function pointyHat(r, col, band, height, stars, small)
	local brim = if small then 2.2 else 2.7
	mk(r, "Head", "cyl", V(0.16, brim, brim), CF(0, 0.68, 0.03) * ANG(0, 0, R(90)), col, FABRIC)
	mk(r, "Head", "cyl", V(0.3, 1.45, 1.45), CF(0, 0.9, 0.03) * ANG(0, 0, R(90)), band, FABRIC)
	local SEGMENTS = 5
	local y = 0.76
	local segH = height / SEGMENTS
	local lean = height * 0.16
	for i = 1, SEGMENTS do
		local f = (i - 1) / SEGMENTS
		local d = math.max(0.26, 1.5 * (1 - f))
		mk(r, "Head", "cyl", V(segH + 0.03, d, d), CF(0, y + segH / 2, 0.03 + lean * f * f) * ANG(0, 0, R(90)), col, FABRIC)
		y += segH
	end
	mk(r, "Head", "ball", V(0.26, 0.26, 0.26), CF(0, y, 0.03 + lean), band, NEON, { light = band, range = 6 })
	if stars then
		for k = 0, 4 do
			local f = 0.15 + k / 5 * 0.55
			local a = k * 2.4 + 0.6
			local rad = 0.75 * (1 - f) + 0.04
			mk(r, "Head", "block", V(0.14, 0.14, 0.14), CF(math.cos(a) * rad, 0.76 + f * height, 0.03 + math.sin(a) * rad + lean * f * f) * ANG(0, a, R(45)), stars, NEON)
		end
	end
	return y
end

-- The staff in the left hand (it stands upright next to the hand, the top above the head):
-- `topKind` = "crystal" | "orb" | "bigorb".
local function staff(r, woodCol, topKind, topCol, length, ringCol)
	local at = CF(-0.15, 0, -0.55)
	mk(r, "LeftHand", "cyl", V(length, 0.24, 0.24), at * CF(0, length * 0.28, 0) * ANG(0, 0, R(90)), woodCol, Enum.Material.Wood)
	local topY = length * 0.28 + length / 2 + 0.2
	if ringCol then
		mk(r, "LeftHand", "cyl", V(0.14, 0.4, 0.4), at * CF(0, topY - 0.55, 0) * ANG(0, 0, R(90)), ringCol, METAL)
	end
	if topKind == "crystal" then
		mk(r, "LeftHand", "block", V(0.42, 1.0, 0.42), at * CF(0, topY + 0.3, 0) * ANG(0, R(45), 0), topCol, NEON, { light = topCol, range = 10, bright = 2 })
	elseif topKind == "bigorb" then
		mk(r, "LeftHand", "ball", V(1.1, 1.1, 1.1), at * CF(0, topY + 0.4, 0), topCol, NEON, { light = topCol, range = 16, bright = 3 })
		local ring = mk(r, "LeftHand", "cyl", V(0.1, 1.6, 1.6), at * CF(0, topY + 0.4, 0) * ANG(R(20), 0, 0) * ANG(0, 0, R(90)), ringCol or M_GOLD, NEON)
		if ring then
			ring.Transparency = 0.3
		end
	else
		mk(r, "LeftHand", "ball", V(0.8, 0.8, 0.8), at * CF(0, topY + 0.25, 0), topCol, NEON, { light = topCol, range = 12, bright = 2 })
	end
end

-- The robe from the waist down: narrower at the hips, wider at the hem.
local function robe(r, col, hem)
	mk(r, "LowerTorso", "block", V(2.3, 1.1, 1.3), CF(0, -0.45, 0), col, FABRIC)
	mk(r, "LowerTorso", "block", V(2.9, 1.3, 1.7), CF(0, -1.5, 0), col, FABRIC)
	if hem then
		mk(r, "LowerTorso", "block", V(3.0, 0.14, 1.8), CF(0, -2.1, 0), hem, FABRIC)
	end
end

local function beard(r)
	mk(r, "Head", "block", V(0.76, 0.55, 0.3), CF(0, -0.7, -0.5), M_WHITE, PLASTIC)
	mk(r, "Head", "block", V(0.42, 0.5, 0.26), CF(0, -1.15, -0.48), M_WHITE, PLASTIC)
end

-- The rune circle on the ground: a glowing disc and six runes around it.
local function runeRing(r, col)
	local disc = mk(r, "LowerTorso", "cyl", V(0.08, 5.6, 5.6), CF(0, -2.12, 0) * ANG(0, 0, R(90)), col, NEON)
	if disc then
		disc.Transparency = 0.55
	end
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		mk(r, "LowerTorso", "block", V(0.3, 0.06, 0.3), CF(math.cos(a) * 2.4, -2.07, math.sin(a) * 2.4) * ANG(0, -a, 0), col, NEON)
	end
end

-- Floating glowing bits around the shoulders (orbs, crystals…): `spots` = { x, y, z } in the torso's space.
local function floating(r, kind, size, spots, col, rot)
	for _, p in ipairs(spots) do
		mk(r, "UpperTorso", kind, size, CF(p[1], p[2], p[3]) * (rot or CF()), col, NEON, { light = col, range = 7 })
	end
end

-- The emblem on the chest: "diamond" | "star" | "moon".
local function emblem(r, kind, col, backCol)
	if kind == "diamond" then
		mk(r, "UpperTorso", "block", V(0.5, 0.5, 0.1), CF(0, 0.1, -0.56) * ANG(0, 0, R(45)), col, NEON, { light = col, range = 8 })
	elseif kind == "star" then
		mk(r, "UpperTorso", "ball", V(0.8, 0.8, 0.1), CF(0, 0.1, -0.55), backCol or M_GOLD, NEON)
		mk(r, "UpperTorso", "ball", V(0.52, 0.52, 0.12), CF(0, 0.1, -0.6), col, NEON, { light = col, range = 10, bright = 2 })
	elseif kind == "moon" then
		mk(r, "UpperTorso", "ball", V(0.66, 0.66, 0.1), CF(0, 0.1, -0.55), col, NEON, { light = col, range = 8 })
		mk(r, "UpperTorso", "ball", V(0.56, 0.56, 0.12), CF(0.17, 0.17, -0.6), backCol or M_NAVY, PLASTIC)
	end
end

local MAGE = {}

MAGE[1] = { name = "Novice", torso = M_TUNIC, legs = M_TUNIC_DARK, top = 2.5, attack = "cast", hold = false,
	build = function(r)
		pointyHat(r, C(66, 56, 98), M_GOLD, 1.4, nil, true)
		belt(r, C(120, 90, 50), M_GOLD)
		boots(r, C(70, 60, 56))
		staff(r, C(150, 120, 70), "crystal", M_CRYSTAL, 5.2, nil)
	end }

MAGE[2] = { name = "Sorcerer", torso = M_PURPLE, legs = M_PURPLE_DARK, top = 3.0, attack = "cast", hold = false,
	build = function(r)
		pointyHat(r, M_HAT_BROWN, M_GOLD, 2.0, nil, false)
		robe(r, M_PURPLE_DARK, M_GOLD)
		belt(r, C(90, 67, 38), M_GOLD)
		mk(r, "LowerTorso", "block", V(0.5, 0.5, 0.3), CF(0.75, -0.2, -0.6), C(120, 82, 48), FABRIC) -- pouch
		boots(r, C(60, 50, 56))
		staff(r, M_WOOD, "orb", M_VIOLET, 5.4, nil)
	end }

MAGE[3] = { name = "Wizard", torso = C(110, 96, 160), legs = C(150, 120, 70), top = 3.4, attack = "cast", hold = false,
	build = function(r)
		pointyHat(r, C(40, 36, 78), M_GOLD, 2.4, M_GOLD, false)
		beard(r)
		robe(r, C(150, 120, 70), M_GOLD)
		for _, p in ipairs({ { -0.8, -0.6 }, { 0.6, -1.0 }, { -0.3, -1.5 }, { 0.9, -1.8 } }) do -- stars on the robe
			mk(r, "LowerTorso", "block", V(0.14, 0.14, 0.06), CF(p[1], p[2], -0.88) * ANG(0, 0, R(45)), M_GOLD_LIGHT, NEON)
		end
		belt(r, C(90, 67, 38), M_GOLD)
		mk(r, "LowerTorso", "block", V(0.3, 0.7, 0.55), CF(-1.2, -0.3, -0.1) * ANG(0, 0, R(8)), C(110, 70, 48), Enum.Material.Wood) -- spellbook
		mk(r, "LowerTorso", "block", V(0.22, 0.6, 0.46), CF(-1.26, -0.3, -0.1) * ANG(0, 0, R(8)), M_PAGES, PLASTIC)
		boots(r, C(60, 50, 56))
		staff(r, M_WOOD, "crystal", M_CYAN, 5.6, M_GOLD)
	end }

MAGE[4] = { name = "Mage", torso = M_INDIGO, legs = C(200, 160, 70), top = 3.5, attack = "cast", hold = false,
	build = function(r)
		pointyHat(r, M_HAT, M_GOLD, 2.6, M_GOLD, false)
		beard(r)
		cloak(r, C(70, 50, 110), M_GOLD, 4.2)
		robe(r, C(200, 160, 70), M_GOLD_LIGHT)
		for _, y in ipairs({ 0.45, 0.1, -0.25 }) do -- gold buttons
			mk(r, "UpperTorso", "block", V(0.7, 0.08, 0.06), CF(0, y, -0.54), M_GOLD, METAL)
		end
		shoulderPads(r, C(40, 34, 60), FABRIC, nil)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(0.28, 0.5, 0.28), CF(0, 0.95, 0) * ANG(0, R(45), 0), M_CRYSTAL, NEON)
		belt(r, C(40, 34, 60), M_WHITE)
		boots(r, C(40, 34, 60))
		staff(r, M_WOOD, "orb", M_BLUE, 5.6, M_GOLD)
		floating(r, "ball", V(0.42, 0.42, 0.42), { { -2.6, 1.0, 0.2 }, { 2.7, 0.4, -0.3 }, { -2.3, -0.6, -0.4 } }, M_BLUE)
		runeRing(r, M_BLUE)
	end }

MAGE[5] = { name = "Arcanist", torso = C(76, 54, 120), legs = C(200, 160, 70), top = 2.0, attack = "cast", hold = false,
	build = function(r)
		hood(r, C(30, 26, 40))
		mk(r, "Head", "block", V(1.24, 1.24, 0.1), CF(0, 0, -0.6), C(8, 6, 12), PLASTIC) -- the face in shadow
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(-0.25, 0.1, -0.66), M_VIOLET, NEON, { light = M_VIOLET, range = 8 })
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(0.25, 0.1, -0.66), M_VIOLET, NEON)
		mk(r, "Head", "block", V(0.22, 0.4, 0.1), CF(0, 0.75, -0.7) * ANG(0, 0, R(45)), M_VIOLET, NEON, { light = M_VIOLET, range = 6 }) -- the gem on the brow
		robe(r, C(200, 160, 70), M_GOLD_LIGHT)
		emblem(r, "diamond", M_VIOLET, nil)
		shoulderPads(r, C(120, 90, 60), FABRIC, nil)
		belt(r, C(40, 34, 60), M_GOLD)
		boots(r, C(40, 34, 60))
		staff(r, C(40, 32, 52), "orb", C(90, 50, 140), 5.6, M_GOLD)
		-- the floating grimoire and cards
		mk(r, "UpperTorso", "block", V(0.7, 0.9, 0.2), CF(-2.4, -0.4, -0.4) * ANG(R(10), R(25), R(15)), C(110, 70, 48), Enum.Material.Wood)
		mk(r, "UpperTorso", "block", V(0.62, 0.82, 0.08), CF(-2.4, -0.4, -0.55) * ANG(R(10), R(25), R(15)), M_PAGES, PLASTIC)
		for _, p in ipairs({ { 2.6, 0.6, 0.3 }, { 2.3, -0.5, -0.5 } }) do
			local card = mk(r, "UpperTorso", "block", V(0.5, 0.7, 0.06), CF(p[1], p[2], p[3]) * ANG(0, R(-20), R(12)), M_CRYSTAL, NEON, { light = M_VIOLET, range = 6 })
			if card then
				card.Transparency = 0.2
			end
		end
		floating(r, "ball", V(0.4, 0.4, 0.4), { { -2.8, 1.4, 0.4 }, { 2.9, 1.6, -0.2 }, { 0, 2.6, 0.6 } }, M_VIOLET)
		runeRing(r, M_VIOLET)
	end }

MAGE[6] = { name = "Archmage", torso = C(60, 50, 96), legs = C(222, 176, 60), top = 3.6, attack = "cast", hold = false,
	build = function(r)
		pointyHat(r, M_SKY, M_GOLD, 2.6, M_GOLD, false)
		beard(r)
		cloak(r, C(222, 176, 60), M_GOLD_LIGHT, 4.4)
		robe(r, C(222, 176, 60), M_GOLD_LIGHT)
		emblem(r, "star", M_ORANGE, M_GOLD)
		spikedPauldrons(r, C(40, 34, 60), M_VIOLET, true)
		belt(r, C(40, 34, 60), M_ORANGE)
		boots(r, C(40, 34, 60))
		staff(r, M_WOOD, "orb", C(50, 50, 120), 5.8, M_GOLD)
		mk(r, "LeftHand", "ball", V(1.1, 1.1, 1.1), CF(-0.15, 5.8 * 0.28 + 5.8 / 2 + 0.45, -0.55), M_ORANGE, NEON, { light = M_ORANGE, range = 14, bright = 2 }).Transparency = 0.6 -- the storm glow around the orb
		floating(r, "ball", V(0.42, 0.42, 0.42), { { -2.7, 1.2, 0.3 }, { 2.8, 0.6, -0.3 }, { -2.5, -0.5, -0.4 }, { 2.6, 1.9, 0.4 } }, M_ORANGE)
		for i, p in ipairs({ { -2.9, 0.5, 0 }, { -3.1, 0.0, 0 }, { -2.8, -0.5, 0 } }) do -- the lightning bolt
			mk(r, "UpperTorso", "block", V(0.12, 0.6, 0.08), CF(p[1], p[2], p[3]) * ANG(0, 0, R(if i % 2 == 0 then -35 else 35)), M_GOLD_LIGHT, NEON, { light = M_GOLD_LIGHT, range = 6 })
		end
		runeRing(r, M_ORANGE)
		local aura = mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.4), CF(0, 0, 0), M_ORANGE, NEON, { sparkle = M_ORANGE, rate = 16 })
		if aura then
			aura.Transparency = 1
		end
	end }

MAGE[7] = { name = "Cosmic Mage", torso = M_NAVY, legs = C(200, 160, 70), top = 2.3, attack = "cast", hold = false,
	build = function(r)
		local hat = C(172, 140, 222)
		mk(r, "Head", "ball", V(1.75, 1.75, 1.75), CF(0, 0.55, 0.03), hat, PLASTIC) -- the turban dome
		mk(r, "Head", "cyl", V(0.3, 1.85, 1.85), CF(0, 0.35, 0.03) * ANG(0, 0, R(90)), C(60, 50, 90), FABRIC)
		mk(r, "Head", "ball", V(0.42, 0.42, 0.14), CF(0, 0.95, -0.8), M_GOLD_LIGHT, NEON, { light = M_GOLD_LIGHT, range = 6 }) -- the crescent
		mk(r, "Head", "ball", V(0.36, 0.36, 0.16), CF(0.13, 1.02, -0.84), hat, PLASTIC)
		robe(r, C(200, 160, 70), M_CYAN)
		for _, p in ipairs({ { -0.7, -0.7 }, { 0.5, -1.1 }, { -0.2, -1.6 }, { 0.8, -1.9 }, { -0.9, -1.4 } }) do -- stars on the robe
			mk(r, "LowerTorso", "block", V(0.1, 0.1, 0.06), CF(p[1], p[2], -0.88), M_WHITE, NEON)
		end
		emblem(r, "moon", M_GOLD_LIGHT, M_NAVY)
		shoulderPads(r, C(60, 50, 100), FABRIC, M_CYAN)
		belt(r, C(40, 34, 60), M_CYAN)
		boots(r, C(40, 34, 60))
		staff(r, C(40, 32, 52), "orb", C(40, 40, 110), 5.6, M_GOLD)
		mk(r, "LeftHand", "ball", V(0.5, 0.5, 0.14), CF(-0.15, 5.6 * 0.28 + 5.6 / 2 + 0.95, -0.55), M_GOLD_LIGHT, NEON) -- the crescent over the orb
		-- the planets
		mk(r, "UpperTorso", "ball", V(0.7, 0.7, 0.7), CF(-2.8, 1.3, 0.3), M_ORANGE, NEON, { light = M_ORANGE, range = 7 })
		mk(r, "UpperTorso", "cyl", V(0.06, 1.3, 1.3), CF(-2.8, 1.3, 0.3) * ANG(R(25), 0, R(90)), M_GOLD_LIGHT, NEON)
		mk(r, "UpperTorso", "ball", V(0.55, 0.55, 0.55), CF(2.9, 0.2, -0.3), M_BLUE, NEON, { light = M_BLUE, range = 7 })
		mk(r, "UpperTorso", "ball", V(0.45, 0.45, 0.45), CF(2.4, 2.2, 0.4), M_VIOLET, NEON, { light = M_VIOLET, range = 7 })
		runeRing(r, M_CYAN)
		local aura = mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.4), CF(0, 0, 0), M_CYAN, NEON, { sparkle = M_CYAN, rate = 18 })
		if aura then
			aura.Transparency = 1
		end
	end }

MAGE[8] = { name = "Grand Mage", torso = M_GOLD_LIGHT, legs = C(200, 150, 50), top = 3.6, attack = "cast", hold = false,
	build = function(r)
		pointyHat(r, C(60, 45, 40), M_GOLD_LIGHT, 2.6, nil, false)
		for i = 0, 4 do -- the golden crown around the band
			local a = i / 5 * math.pi * 2 + math.pi / 2
			mk(r, "Head", "block", V(0.22, 0.6, 0.22), CF(math.cos(a) * 0.78, 1.2, 0.03 + math.sin(a) * 0.78) * ANG(0, -a, 0), M_GOLD_LIGHT, NEON)
		end
		beard(r)
		robe(r, C(200, 150, 50), M_PINK)
		emblem(r, "diamond", M_PINK, nil)
		mk(r, "UpperTorso", "cyl", V(0.1, 0.9, 0.9), CF(0, 0.1, -0.53) * ANG(0, R(90), 0), M_GOLD_DARK, METAL) -- the medallion behind the gem
		shoulderPads(r, C(50, 40, 60), FABRIC, nil)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(0.3, 0.3, 0.3), CF(0, 0.85, 0) * ANG(0, R(45), 0), M_PINK, NEON)
		belt(r, C(50, 40, 60), M_PINK)
		boots(r, C(50, 40, 60))
		staff(r, M_WOOD, "bigorb", M_BLUE, 5.8, M_GOLD_LIGHT)
		for i, p in ipairs({ { -2.7, 1.4, 0.3 }, { 2.9, 1.1, -0.3 }, { -2.5, -0.3, -0.5 }, { 2.6, -0.4, 0.5 } }) do -- the flying books
			local a = R(i * 55)
			mk(r, "UpperTorso", "block", V(0.65, 0.85, 0.18), CF(p[1], p[2], p[3]) * ANG(R(8), a, R(-10)), if i % 2 == 0 then M_PAGES else M_GOLD_LIGHT, PLASTIC)
			mk(r, "UpperTorso", "block", V(0.2, 0.2, 0.06), CF(p[1], p[2], p[3]) * ANG(R(8), a, R(-10)) * CF(0, 0, -0.1) * ANG(0, 0, R(45)), M_PINK, NEON)
		end
		floating(r, "ball", V(0.4, 0.4, 0.4), { { -3.1, 0.6, 0.0 }, { 3.2, 2.2, 0.2 } }, M_PINK)
		runeRing(r, M_GOLD_LIGHT)
		local aura = mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.4), CF(0, 0, 0), M_GOLD_LIGHT, NEON, { sparkle = M_GOLD_LIGHT, rate = 22 })
		if aura then
			aura.Transparency = 1
		end
	end }

MAGE[9] = { name = "Legend", torso = C(52, 42, 94), legs = C(210, 170, 70), top = 3.9, attack = "cast", hold = false,
	build = function(r)
		pointyHat(r, M_SILVER, M_GOLD_LIGHT, 2.6, M_GOLD_LIGHT, false)
		for i = 0, 17 do -- the halo above the hat
			local a = i / 18 * math.pi * 2
			mk(r, "Head", "block", V(0.4, 0.1, 0.2), CF(math.cos(a) * 1.15, 3.75, 0.3 + math.sin(a) * 1.15) * ANG(0, -a, 0), M_GOLD_LIGHT, NEON, i == 0 and { light = M_GOLD_LIGHT, range = 16, bright = 3 } or nil)
		end
		beard(r)
		robe(r, C(210, 170, 70), M_CYAN)
		mk(r, "UpperTorso", "block", V(1.9, 0.12, 0.1), CF(0, 0.68, -0.54), M_GOLD_LIGHT, METAL)
		mk(r, "UpperTorso", "block", V(1.9, 0.12, 0.1), CF(0, -0.68, -0.54), M_GOLD_LIGHT, METAL)
		mk(r, "UpperTorso", "block", V(0.62, 0.62, 0.1), CF(0, 0.05, -0.55) * ANG(0, 0, R(45)), M_GOLD_LIGHT, METAL)
		mk(r, "UpperTorso", "block", V(0.42, 0.42, 0.14), CF(0, 0.05, -0.6) * ANG(0, 0, R(45)), M_CYAN, NEON, { light = M_CYAN, range = 14, bright = 3, sparkle = M_CYAN, rate = 20 })
		shoulderPads(r, C(210, 170, 70), METAL, M_CYAN)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(0.3, 0.5, 0.3), CF(0, 0.95, 0) * ANG(0, R(45), 0), M_CYAN, NEON)
		belt(r, C(40, 34, 60), M_CYAN)
		boots(r, C(60, 50, 90))
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.1, 0.14, 1.25), CF(0, -0.02, -0.05), M_GOLD_LIGHT, METAL)
		staff(r, C(120, 100, 150), "bigorb", M_CYAN, 6.0, M_GOLD_LIGHT)
		-- the wings of light
		for _, s in ipairs({ -1, 1 }) do
			for i = 1, 6 do
				local phi = R(-55 + i * 22)
				local L = 2.2 + math.sin(i * 0.55) * 1.7
				mk(r, "UpperTorso", "block", V(L, 0.1, 0.5), CF(s * (0.8 + math.cos(phi) * L / 2), 0.4 + math.sin(phi) * L / 2, 0.75 + i * 0.05) * ANG(0, 0, s * phi), i % 2 == 0 and M_GOLD_LIGHT or M_CYAN, NEON, (i == 3) and { light = M_CYAN, range = 14, bright = 2 } or nil)
			end
		end
		-- the floating crystals
		for _, p in ipairs({ { -3.2, 2.2, 0.5 }, { 3.4, 3.0, -0.4 }, { -3.0, -0.6, -0.7 }, { 3.2, -0.2, 0.6 }, { 0, 4.6, 0.6 } }) do
			mk(r, "UpperTorso", "block", V(0.3, 0.75, 0.3), CF(p[1], p[2], p[3]) * ANG(0, R(45), 0), M_CYAN, NEON, { light = M_CYAN, range = 8 })
		end
		runeRing(r, M_CYAN)
		local aura = mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.4), CF(0, 0, 0), M_GOLD_LIGHT, NEON, { sparkle = M_GOLD_LIGHT, rate = 40 })
		if aura then
			aura.Transparency = 1
		end
	end }

-- ── Shared gear for the Hunter, the Berserker and the Tank (design: their card sheets) ──

-- A crossbow in the right hand: the stock along -Z, the bow across it near the front.
local function crossbow(r, stockCol, bowCol, boltCol, size)
	size = size or 1
	mk(r, "RightHand", "block", V(0.26, 0.4, 2.2) * size, CF(0, -0.15, -0.9 * size), stockCol, Enum.Material.Wood)
	mk(r, "RightHand", "block", V(2.2, 0.14, 0.2) * size, CF(0, -0.1, -1.6 * size), bowCol, Enum.Material.Wood)
	mk(r, "RightHand", "block", V(1.15, 0.05, 0.05) * size, CF(-0.55 * size, 0, -1.3 * size) * ANG(0, R(-28), 0), K_WHITE, PLASTIC)
	mk(r, "RightHand", "block", V(1.15, 0.05, 0.05) * size, CF(0.55 * size, 0, -1.3 * size) * ANG(0, R(28), 0), K_WHITE, PLASTIC)
	if boltCol then
		mk(r, "RightHand", "block", V(0.08, 0.08, 1.4) * size, CF(0, 0.08, -1.3 * size), boltCol, NEON, { light = boltCol, range = 8 })
	end
end

-- A long rifle with a scope (the Soldier's rifle plus the scope).
local function longRifle(r, col, glow, size)
	size = size or 1.2
	rifle(r, col, glow, size)
	mk(r, "RightHand", "cyl", V(0.6, 0.3, 0.3), CF(0, 0.2, -1.0 * size) * ANG(0, R(90), 0), C(20, 22, 24), METAL)
	if glow then
		mk(r, "RightHand", "ball", V(0.22, 0.22, 0.1), CF(0, 0.2, -1.32 * size), glow, NEON)
	end
end

-- An axe in a hand: a haft along -Z and a head near the end (`double` = a blade on both sides).
local function axe(r, limb, haftCol, headCol, edgeCol, size, double)
	size = size or 1
	mk(r, limb, "block", V(0.22, 0.22, 3.0) * size, CF(0, -0.15, -1.0 * size), haftCol, Enum.Material.Wood)
	mk(r, limb, "block", V(0.26, 0.5, 0.5) * size, CF(0, -0.15, 0.4 * size), C(70, 52, 40), PLASTIC)
	mk(r, limb, "block", V(0.3, 1.3, 0.9) * size, CF(0, 0.5 * size, -2.1 * size), headCol, METAL)
	if edgeCol then
		mk(r, limb, "block", V(0.34, 1.35, 0.14) * size, CF(0, 0.5 * size, -2.6 * size), edgeCol, NEON, { light = edgeCol, range = 8 })
	end
	if double then
		mk(r, limb, "block", V(0.3, 1.3, 0.9) * size, CF(0, -0.8 * size, -2.1 * size), headCol, METAL)
		if edgeCol then
			mk(r, limb, "block", V(0.34, 1.35, 0.14) * size, CF(0, -0.8 * size, -2.6 * size), edgeCol, NEON)
		end
	end
end

-- A tower shield on the left hand: a tall plate with a point below, a border and an emblem
-- ("cross" | "diamond" | "star" | "runes" | "none").
local function towerShield(r, col, trim, emblemKind, emblemCol, size)
	size = size or 1
	local at = CF(-0.4, -0.3, -0.75)
	mk(r, "LeftHand", "block", V(1.7, 3.0, 0.16) * size, at, trim, METAL)
	mk(r, "LeftHand", "block", V(1.2, 1.2, 0.16) * size, at * CF(0, -1.5 * size, 0) * ANG(0, 0, R(45)), trim, METAL)
	mk(r, "LeftHand", "block", V(1.45, 2.8, 0.18) * size, at * CF(0, 0, -0.02), col, METAL)
	mk(r, "LeftHand", "block", V(1.0, 1.0, 0.18) * size, at * CF(0, -1.5 * size, -0.02) * ANG(0, 0, R(45)), col, METAL)
	local front = at * CF(0, 0, -0.13)
	if emblemKind == "cross" then
		mk(r, "LeftHand", "block", V(0.22, 2.2, 0.05) * size, front, emblemCol, PLASTIC)
		mk(r, "LeftHand", "block", V(1.1, 0.22, 0.05) * size, front * CF(0, 0.5 * size, 0), emblemCol, PLASTIC)
	elseif emblemKind == "diamond" then
		mk(r, "LeftHand", "block", V(0.9, 0.9, 0.05) * size, front * ANG(0, 0, R(45)), emblemCol, METAL)
		mk(r, "LeftHand", "block", V(0.5, 0.5, 0.06) * size, front * CF(0, 0, -0.02) * ANG(0, 0, R(45)), trim, NEON, { light = trim, range = 8 })
	elseif emblemKind == "star" then
		mk(r, "LeftHand", "block", V(0.8, 0.8, 0.05) * size, front, emblemCol, METAL)
		mk(r, "LeftHand", "block", V(0.8, 0.8, 0.05) * size, front * ANG(0, 0, R(45)), emblemCol, METAL)
	elseif emblemKind == "runes" then
		mk(r, "LeftHand", "block", V(0.08, 2.4, 0.05) * size, front, emblemCol, NEON)
		mk(r, "LeftHand", "block", V(1.2, 0.08, 0.05) * size, front, emblemCol, NEON)
		mk(r, "LeftHand", "block", V(0.08, 2.0, 0.05) * size, front * ANG(0, 0, R(40)), emblemCol, NEON)
		mk(r, "LeftHand", "block", V(0.08, 2.0, 0.05) * size, front * ANG(0, 0, R(-40)), emblemCol, NEON)
		mk(r, "LeftHand", "ball", V(0.4, 0.4, 0.1) * size, front * CF(0, 0, -0.02), emblemCol, NEON, { light = emblemCol, range = 10 })
	end
end

-- A mace in the right hand: a haft and a ball head with spikes.
local function mace(r, haftCol, headCol, spikeCol)
	mk(r, "RightHand", "block", V(0.22, 0.22, 2.4), CF(0, -0.15, -1.0), haftCol, Enum.Material.Wood)
	mk(r, "RightHand", "ball", V(0.75, 0.75, 0.75), CF(0, -0.15, -2.3), headCol, METAL)
	for _, o in ipairs({ { 0.4, 0 }, { -0.4, 0 }, { 0, 0.4 }, { 0, -0.4 } }) do
		mk(r, "RightHand", "block", V(0.16, 0.16, 0.16), CF(o[1], -0.15 + o[2], -2.3), spikeCol or headCol, METAL)
	end
	mk(r, "RightHand", "block", V(0.16, 0.16, 0.3), CF(0, -0.15, -2.75), spikeCol or headCol, METAL)
end

-- A war hammer in the right hand.
local function warHammer(r, headCol, haftCol, glow, size)
	size = size or 1
	mk(r, "RightHand", "block", V(0.24, 0.24, 3.4) * size, CF(0, -0.15, -1.2 * size), haftCol, Enum.Material.Wood)
	mk(r, "RightHand", "block", V(1.5, 0.85, 0.85) * size, CF(0, -0.15, -2.7 * size), headCol, METAL)
	if glow then
		mk(r, "RightHand", "block", V(1.52, 0.12, 0.3) * size, CF(0, -0.15, -2.7 * size), glow, NEON, { light = glow, range = 10 })
	end
end

local function club(r, col)
	mk(r, "RightHand", "block", V(0.26, 0.26, 2.2), CF(0, -0.15, -0.9), col, Enum.Material.Wood)
	mk(r, "RightHand", "block", V(0.6, 0.6, 1.0), CF(0, -0.15, -2.2), col, Enum.Material.Wood)
end

-- The fur kilt from the waist down.
local function furKilt(r, col, hemCol)
	mk(r, "LowerTorso", "block", V(2.3, 1.1, 1.3), CF(0, -0.5, 0), col, FABRIC)
	for _, x in ipairs({ -0.8, -0.27, 0.27, 0.8 }) do
		mk(r, "LowerTorso", "wedge", V(0.5, 0.4, 0.3), CF(x, -1.2, -0.55) * ANG(R(180), 0, 0), hemCol or col, FABRIC)
	end
end

local function furShoulders(r, col)
	both(r, { "LeftUpperArm", "RightUpperArm" }, "ball", V(1.45, 0.9, 1.45), CF(0, 0.5, 0), col, FABRIC)
end

-- War tattoos: zigzags on the arms and the chest.
local function tattoos(r, col, neon)
	local mat = neon and NEON or PLASTIC
	for _, limb in ipairs({ "LeftUpperArm", "RightUpperArm" }) do
		mk(r, limb, "block", V(0.08, 0.7, 0.08), CF(0, 0.25, -0.52) * ANG(0, 0, R(30)), col, mat)
		mk(r, limb, "block", V(0.08, 0.7, 0.08), CF(0, -0.25, -0.52) * ANG(0, 0, R(-30)), col, mat)
	end
	mk(r, "UpperTorso", "block", V(0.08, 0.8, 0.08), CF(-0.6, 0.35, -0.53) * ANG(0, 0, R(28)), col, mat)
	mk(r, "UpperTorso", "block", V(0.08, 0.8, 0.08), CF(-0.6, -0.35, -0.53) * ANG(0, 0, R(-28)), col, mat)
	mk(r, "UpperTorso", "block", V(0.08, 0.8, 0.08), CF(0.6, 0.35, -0.53) * ANG(0, 0, R(-28)), col, mat)
	mk(r, "UpperTorso", "block", V(0.08, 0.8, 0.08), CF(0.6, -0.35, -0.53) * ANG(0, 0, R(28)), col, mat)
end

local function wristWraps(r, col)
	both(r, { "LeftLowerArm", "RightLowerArm" }, "block", V(1.08, 0.5, 1.08), CF(0, -0.1, 0), col, FABRIC)
end

-- Antlers on the head.
local function antlers(r, col)
	for _, s in ipairs({ -1, 1 }) do
		mk(r, "Head", "block", V(0.14, 1.2, 0.14), CF(s * 0.5, 1.2, 0) * ANG(0, 0, R(s * -20)), col, METAL)
		mk(r, "Head", "block", V(0.12, 0.6, 0.12), CF(s * 0.78, 1.5, 0) * ANG(0, 0, R(s * -55)), col, METAL)
		mk(r, "Head", "block", V(0.12, 0.5, 0.12), CF(s * 0.62, 1.85, 0) * ANG(0, 0, R(s * 15)), col, METAL)
	end
end

-- Floating targeting reticles around the shoulders.
local function reticles(r, col, spots)
	for _, p in ipairs(spots) do
		local at = CF(p[1], p[2], p[3])
		local ring = mk(r, "UpperTorso", "cyl", V(0.08, 0.9, 0.9), at * ANG(0, R(90), 0), col, NEON, { light = col, range = 7 })
		if ring then
			ring.Transparency = 0.35
		end
		mk(r, "UpperTorso", "block", V(0.06, 1.2, 0.06), at, col, NEON)
		mk(r, "UpperTorso", "block", V(1.2, 0.06, 0.06), at, col, NEON)
	end
end

-- The wings of light (the Legend pattern), in two colors.
local function lightWings(r, colA, colB)
	for _, s in ipairs({ -1, 1 }) do
		for i = 1, 6 do
			local phi = R(-55 + i * 22)
			local L = 2.2 + math.sin(i * 0.55) * 1.7
			mk(r, "UpperTorso", "block", V(L, 0.1, 0.5), CF(s * (0.8 + math.cos(phi) * L / 2), 0.4 + math.sin(phi) * L / 2, 0.75 + i * 0.05) * ANG(0, 0, s * phi), i % 2 == 0 and colA or colB, NEON, (i == 3) and { light = colB, range = 14, bright = 2 } or nil)
		end
	end
end

-- The halo over the head (the Legend pattern).
local function halo(r, col, height)
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2
		mk(r, "Head", "block", V(0.4, 0.1, 0.2), CF(math.cos(a) * 1.15, height, math.sin(a) * 1.15) * ANG(0, -a, 0), col, NEON, i == 0 and { light = col, range = 16, bright = 3 } or nil)
	end
end

local function sparkleAura(r, col, rate)
	local aura = mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.4), CF(0, 0, 0), col, NEON, { sparkle = col, rate = rate })
	if aura then
		aura.Transparency = 1
	end
end

-- Flames (balls of fire) at the given spots on a limb.
local function flames(r, limb, spots, size)
	for _, p in ipairs(spots) do
		mk(r, limb, "ball", V(size, size * 1.5, size), CF(p[1], p[2], p[3]), K_FIRE, NEON, { light = K_FIRE, range = 6 })
		mk(r, limb, "ball", V(size * 0.5, size * 0.9, size * 0.5), CF(p[1], p[2] + size * 0.2, p[3] - 0.05), K_FLAME, NEON)
	end
end

-- ── The Hunter: 9 levels (design: the teal hunter cards) ──
--   1 Scout · 2 Trapper · 3 Tracker · 4 Sharpshooter · 5 Nightstalker · 6 Hawkeye · 7 Phantom Ranger ·
--   8 Royal Huntsman · 9 Legend
local H_TEAL = C(70, 200, 200)
local H_CYAN = C(110, 220, 255)
local H_LEATHER = C(122, 90, 58)
local H_DARK_LEATHER = C(90, 64, 40)
local H_GREEN = C(111, 138, 82)
local H_FOREST = C(79, 122, 74)
local H_DARK_FOREST = C(35, 64, 42)
local H_SLATE = C(58, 90, 86)
local H_INK = C(28, 36, 36)
local H_GOLD = C(200, 165, 70)
local H_WHITE = C(240, 236, 228)
local H_CRIMSON = C(138, 42, 58)
local H_ORANGE = C(250, 150, 70)

local HUNTER = {}

HUNTER[1] = { name = "Scout", torso = H_GREEN, legs = C(90, 70, 50), top = 1.8, attack = "lunge", hold = false,
	build = function(r)
		cap(r, H_LEATHER, H_DARK_LEATHER)
		belt(r, C(74, 56, 38), H_GOLD)
		mk(r, "LowerTorso", "block", V(0.55, 0.6, 0.35), CF(0.7, -0.2, -0.55), H_LEATHER, FABRIC) -- satchel
		boots(r, C(70, 60, 56))
		crossbow(r, H_LEATHER, H_DARK_LEATHER, nil, 0.9)
	end }

HUNTER[2] = { name = "Trapper", torso = H_FOREST, legs = C(74, 58, 42), top = 1.9, attack = "lunge", hold = false,
	build = function(r)
		hood(r, H_DARK_FOREST)
		mk(r, "UpperTorso", "block", V(1.7, 1.0, 0.14), CF(0, 0.25, -0.55), H_LEATHER, FABRIC) -- leather vest
		belt(r, C(46, 36, 24), H_GOLD)
		mk(r, "LowerTorso", "block", V(0.55, 0.5, 0.3), CF(-0.7, -0.15, -0.6), H_LEATHER, FABRIC) -- pouch
		gloves(r, H_DARK_LEATHER)
		boots(r, C(46, 36, 24))
		quiver(r, H_DARK_LEATHER, K_WHITE, 3)
		crossbow(r, H_DARK_LEATHER, C(60, 42, 24), nil, 1.0)
	end }

HUNTER[3] = { name = "Tracker", torso = C(138, 106, 68), legs = C(74, 58, 42), top = 2.4, attack = "lunge", hold = false,
	build = function(r)
		hood(r, H_DARK_FOREST)
		feather(r, K_WHITE, C(200, 60, 60))
		cloak(r, H_DARK_FOREST, H_DARK_FOREST, 4.0)
		mk(r, "UpperTorso", "block", V(0.16, 2.0, 0.06), CF(0, 0, -0.62) * ANG(0, 0, R(48)), C(60, 42, 24), FABRIC) -- crossed straps
		mk(r, "UpperTorso", "block", V(0.16, 2.0, 0.06), CF(0, 0, -0.62) * ANG(0, 0, R(-48)), C(60, 42, 24), FABRIC)
		mk(r, "UpperTorso", "ball", V(0.28, 0.28, 0.12), CF(0, 0, -0.66), H_GOLD, METAL)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.1, 1.0, 1.1), CF(0, 0.3, 0), H_DARK_FOREST, FABRIC)
		bracers(r, H_LEATHER, nil)
		gloves(r, C(60, 42, 24))
		belt(r, C(46, 36, 24), H_GOLD)
		kneepads(r, H_LEATHER)
		boots(r, C(46, 36, 24))
		quiver(r, H_DARK_LEATHER, H_TEAL, 4)
		crossbow(r, C(60, 42, 24), C(42, 28, 16), H_TEAL, 1.05)
	end }

HUNTER[4] = { name = "Sharpshooter", torso = H_SLATE, legs = C(46, 58, 58), top = 2.0, attack = "lunge", hold = false,
	build = function(r)
		cap(r, C(38, 58, 56), H_INK)
		mk(r, "Head", "block", V(1.25, 0.26, 0.1), CF(0, 0.55, -0.7), H_INK, PLASTIC) -- the goggle strap
		mk(r, "Head", "cyl", V(0.12, 0.4, 0.4), CF(-0.3, 0.6, -0.78) * ANG(0, R(90), 0), H_TEAL, NEON, { light = H_TEAL, range = 6 })
		mk(r, "Head", "cyl", V(0.12, 0.4, 0.4), CF(0.3, 0.6, -0.78) * ANG(0, R(90), 0), H_TEAL, NEON)
		chestPlate(r, C(38, 58, 56), H_TEAL)
		mk(r, "UpperTorso", "block", V(0.3, 2.2, 0.12), CF(0, 0, -0.72) * ANG(0, 0, R(-45)), H_DARK_LEATHER, FABRIC) -- bandolier
		for i = -1, 1 do
			mk(r, "UpperTorso", "block", V(0.12, 0.3, 0.1), CF(i * 0.45, i * 0.45, -0.8) * ANG(0, 0, R(-45)), H_GOLD, METAL)
		end
		pauldrons(r, C(38, 58, 56))
		belt(r, H_INK, H_TEAL)
		kneepads(r, H_TEAL)
		gloves(r, H_INK)
		boots(r, H_INK)
		longRifle(r, C(38, 58, 56), H_TEAL, 1.2)
	end }

HUNTER[5] = { name = "Nightstalker", torso = C(38, 50, 54), legs = H_INK, top = 2.3, attack = "lunge", hold = false,
	build = function(r)
		hood(r, C(20, 28, 30))
		mk(r, "Head", "block", V(1.24, 1.24, 0.1), CF(0, 0, -0.6), C(8, 12, 14), PLASTIC) -- the face in shadow
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(-0.25, 0.1, -0.66), H_TEAL, NEON, { light = H_TEAL, range = 8 })
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(0.25, 0.1, -0.66), H_TEAL, NEON)
		mk(r, "Head", "block", V(1.1, 0.3, 0.3), CF(0, 0.75, -0.6), C(14, 18, 20), PLASTIC) -- night vision mount
		mk(r, "Head", "cyl", V(0.1, 0.34, 0.34), CF(-0.3, 0.75, -0.78) * ANG(0, R(90), 0), C(124, 255, 107), NEON, { light = C(124, 255, 107), range = 6 })
		mk(r, "Head", "cyl", V(0.1, 0.34, 0.34), CF(0.3, 0.75, -0.78) * ANG(0, R(90), 0), C(124, 255, 107), NEON)
		cloak(r, C(26, 36, 38), C(26, 36, 38), 4.4)
		chestPlate(r, C(20, 28, 30), nil)
		emblem(r, "diamond", H_TEAL, nil)
		pauldrons(r, C(20, 28, 30))
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.1, 0.08, 1.1), CF(0, 0.2, 0), H_TEAL, NEON)
		belt(r, C(14, 18, 20), C(200, 140, 255))
		kneepads(r, C(46, 58, 58))
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.8, 0.06, 0.08), CF(0, 0.5, -0.69), H_TEAL, NEON)
		gloves(r, C(14, 18, 20))
		boots(r, C(14, 18, 20))
		longRifle(r, C(20, 28, 30), C(200, 140, 255), 1.25)
	end }

HUNTER[6] = { name = "Hawkeye", torso = C(74, 58, 46), legs = C(46, 42, 38), top = 2.2, attack = "lunge", hold = false,
	build = function(r)
		cap(r, C(74, 58, 46), H_GOLD)
		mk(r, "Head", "block", V(1.5, 0.12, 1.5), CF(0, 0.44, 0.03), H_GOLD, METAL)
		mk(r, "Head", "wedge", V(0.1, 0.6, 0.5), CF(0.55, 0.95, 0.1) * ANG(R(-30), 0, R(-25)), H_ORANGE, FABRIC)
		mk(r, "Head", "cyl", V(0.12, 0.5, 0.5), CF(0.25, 0.12, -0.66) * ANG(0, R(90), 0), C(46, 42, 38), METAL) -- the mechanical eye
		mk(r, "Head", "cyl", V(0.14, 0.32, 0.32), CF(0.25, 0.12, -0.68) * ANG(0, R(90), 0), H_TEAL, NEON, { light = H_TEAL, range = 8 })
		chestPlate(r, C(46, 42, 38), H_GOLD)
		emblem(r, "star", H_TEAL, H_GOLD)
		pauldrons(r, H_GOLD)
		bracers(r, C(46, 42, 38), H_GOLD)
		gloves(r, C(46, 42, 38))
		belt(r, C(46, 42, 38), H_ORANGE)
		kneepads(r, H_GOLD)
		boots(r, H_GOLD)
		-- the hawk on the left shoulder
		mk(r, "LeftUpperArm", "ball", V(0.6, 0.5, 0.8), CF(-0.2, 1.05, 0), C(122, 90, 58), FABRIC)
		mk(r, "LeftUpperArm", "ball", V(0.36, 0.36, 0.36), CF(-0.2, 1.4, -0.3), C(122, 90, 58), FABRIC)
		mk(r, "LeftUpperArm", "wedge", V(0.14, 0.16, 0.26), CF(-0.2, 1.38, -0.56) * ANG(R(90), 0, 0), H_GOLD, PLASTIC)
		mk(r, "LeftUpperArm", "ball", V(0.1, 0.1, 0.1), CF(-0.3, 1.46, -0.44), K_WHITE, NEON)
		crossbow(r, C(46, 42, 38), H_GOLD, H_TEAL, 1.1)
		mk(r, "RightHand", "block", V(2.3, 0.06, 0.06), CF(0, 0.05, -1.75), H_TEAL, NEON) -- the energy bow string
	end }

HUNTER[7] = { name = "Phantom Ranger", torso = C(42, 58, 82), legs = C(30, 42, 62), top = 2.4, attack = "lunge", hold = false,
	build = function(r)
		hood(r, C(220, 232, 240))
		mk(r, "Head", "block", V(1.24, 1.24, 0.1), CF(0, 0, -0.6), C(10, 16, 32), PLASTIC)
		mk(r, "Head", "block", V(0.9, 0.22, 0.1), CF(0, 0.12, -0.66), H_CYAN, NEON, { light = H_CYAN, range = 8 }) -- the visor
		local ghost = mk(r, "UpperTorso", "block", V(2.5, 3.6, 0.14), CF(0, -1.1, 0.7) * ANG(R(6), 0, 0), H_CYAN, NEON)
		if ghost then
			ghost.Transparency = 0.6
		end
		chestPlate(r, C(14, 20, 32), nil)
		mk(r, "UpperTorso", "cyl", V(0.1, 0.8, 0.8), CF(0, 0.1, -0.72) * ANG(0, R(90), 0), H_CYAN, NEON, { light = H_CYAN, range = 10 })
		mk(r, "UpperTorso", "cyl", V(0.12, 0.6, 0.6), CF(0, 0.1, -0.72) * ANG(0, R(90), 0), C(14, 20, 32), PLASTIC)
		mk(r, "UpperTorso", "ball", V(0.22, 0.22, 0.14), CF(0, 0.1, -0.8), H_CYAN, NEON)
		pauldrons(r, C(220, 232, 240))
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.1, 0.06, 1.1), CF(0, 0.2, 0), H_CYAN, NEON)
		belt(r, C(14, 20, 32), H_CYAN)
		gloves(r, C(14, 20, 32))
		boots(r, C(14, 20, 32))
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.12, 0.1, 1.27), CF(0, 0.5, -0.05), H_CYAN, NEON)
		reticles(r, H_CYAN, { { -2.8, 1.4, 0.2 }, { 2.9, -0.4, -0.3 }, { 2.4, 2.4, 0.4 } })
		longRifle(r, C(220, 232, 240), H_CYAN, 1.3)
		sparkleAura(r, H_CYAN, 14)
	end }

HUNTER[8] = { name = "Royal Huntsman", torso = H_WHITE, legs = C(42, 42, 52), top = 3.0, attack = "lunge", hold = false,
	build = function(r)
		cap(r, C(42, 42, 52), H_GOLD)
		mk(r, "Head", "block", V(1.5, 0.14, 1.5), CF(0, 0.44, 0.03), H_GOLD, METAL)
		antlers(r, H_GOLD)
		cloak(r, H_CRIMSON, H_GOLD, 4.4)
		mk(r, "UpperTorso", "block", V(0.14, 1.6, 0.06), CF(0, 0, -0.54), H_GOLD, METAL) -- the coat seam and buttons
		for _, y in ipairs({ 0.45, 0.1, -0.25 }) do
			mk(r, "UpperTorso", "ball", V(0.16, 0.16, 0.1), CF(-0.35, y, -0.55), H_GOLD, METAL)
			mk(r, "UpperTorso", "ball", V(0.16, 0.16, 0.1), CF(0.35, y, -0.55), H_GOLD, METAL)
		end
		mk(r, "UpperTorso", "block", V(0.4, 2.2, 0.08), CF(0, 0, -0.58) * ANG(0, 0, R(-40)), H_CRIMSON, FABRIC) -- the sash
		pauldrons(r, H_GOLD)
		bracers(r, H_WHITE, H_GOLD)
		gloves(r, H_GOLD)
		belt(r, C(42, 42, 52), H_GOLD)
		kneepads(r, H_GOLD)
		boots(r, H_GOLD)
		-- the floating golden arrows
		for _, p in ipairs({ { -2.8, 0.6, 0.3, 25 }, { 3.0, 1.6, -0.3, -30 } }) do
			mk(r, "UpperTorso", "block", V(0.08, 1.6, 0.08), CF(p[1], p[2], p[3]) * ANG(0, 0, R(p[4])), K_WHITE, PLASTIC)
			mk(r, "UpperTorso", "block", V(0.3, 0.3, 0.1), CF(p[1], p[2], p[3]) * ANG(0, 0, R(p[4])) * CF(0, 0.95, 0) * ANG(0, 0, R(45)), H_GOLD, METAL)
		end
		longRifle(r, H_GOLD, K_WHITE, 1.3)
	end }

HUNTER[9] = { name = "Legend", torso = H_WHITE, legs = C(42, 42, 64), top = 3.6, attack = "lunge", hold = false,
	build = function(r)
		hood(r, H_WHITE)
		mk(r, "Head", "block", V(1.64, 0.14, 1.6), CF(0, 0.6, 0.05), H_GOLD, METAL)
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(-0.25, 0.12, -0.62), H_CYAN, NEON, { light = H_CYAN, range = 8 })
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(0.25, 0.12, -0.62), H_CYAN, NEON)
		halo(r, H_GOLD, 2.45)
		mk(r, "Head", "block", V(0.08, 2.9, 0.08), CF(0, 2.45, 0), H_GOLD, NEON) -- the reticle lines across the halo
		mk(r, "Head", "block", V(2.9, 0.08, 0.08), CF(0, 2.45, 0), H_GOLD, NEON)
		mk(r, "UpperTorso", "block", V(1.8, 1.4, 0.3), CF(0, 0.05, -0.6), H_GOLD, METAL)
		mk(r, "UpperTorso", "cyl", V(0.12, 1.0, 1.0), CF(0, 0.1, -0.78) * ANG(0, R(90), 0), H_CYAN, NEON, { light = H_CYAN, range = 14, bright = 3, sparkle = H_CYAN, rate = 20 })
		mk(r, "UpperTorso", "cyl", V(0.14, 0.76, 0.76), CF(0, 0.1, -0.78) * ANG(0, R(90), 0), H_GOLD, METAL)
		mk(r, "UpperTorso", "ball", V(0.3, 0.3, 0.16), CF(0, 0.1, -0.88), H_CYAN, NEON)
		pauldrons(r, H_GOLD, 1.1)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.2, 0.06, 1.2), CF(0, 0.2, 0), H_CYAN, NEON)
		bracers(r, H_GOLD, H_CYAN)
		gloves(r, H_GOLD)
		belt(r, C(42, 42, 64), H_CYAN)
		kneepads(r, H_GOLD)
		boots(r, H_GOLD)
		lightWings(r, H_GOLD, H_CYAN)
		for _, p in ipairs({ { -3.2, 2.2, 0.5 }, { 3.4, 3.0, -0.4 }, { -3.0, -0.6, -0.7 } }) do
			mk(r, "UpperTorso", "block", V(0.3, 0.75, 0.3), CF(p[1], p[2], p[3]) * ANG(0, R(45), 0), H_CYAN, NEON, { light = H_CYAN, range = 8 })
		end
		longRifle(r, H_GOLD, H_CYAN, 1.4)
		local beam = mk(r, "RightHand", "block", V(0.3, 0.3, 4.0), CF(0, 0.12, -3.6), H_CYAN, NEON, { light = H_CYAN, range = 12 })
		if beam then
			beam.Transparency = 0.5
		end
		sparkleAura(r, H_GOLD, 30)
	end }

-- ── The Berserker: 9 levels (design: the orange berserker cards) ──
--   1 Brawler · 2 Raider · 3 Marauder · 4 Berserker · 5 Bloodrager · 6 Warlord · 7 Firebrand · 8 Warchief ·
--   9 Legend
local B_FUR = C(110, 90, 70)
local B_FUR_DARK = C(74, 56, 38)
local B_LEATHER = C(74, 56, 38)
local B_STEEL = C(184, 192, 204)
local B_IRON = C(110, 118, 128)
local B_RED = C(200, 60, 60)
local B_BLOOD = C(255, 60, 60)
local B_ORANGE = C(235, 130, 50)
local B_GOLD = C(250, 220, 80)
local B_BLACK = C(30, 26, 36)
local B_BONE = C(232, 224, 200)
local B_WOOD = C(122, 90, 58)

local BERSERKER = {}

BERSERKER[1] = { name = "Brawler", torso = SKIN, legs = SKIN, top = 1.7, attack = "slash", hold = true,
	build = function(r)
		mk(r, "Head", "block", V(1.26, 0.22, 1.26), CF(0, 0.35, 0), C(138, 42, 42), FABRIC) -- the headband
		furKilt(r, B_FUR, B_FUR_DARK)
		belt(r, B_LEATHER, B_IRON)
		wristWraps(r, C(138, 42, 42))
		boots(r, B_LEATHER)
		axe(r, "RightHand", B_WOOD, B_IRON, nil, 1.0, false)
	end }

BERSERKER[2] = { name = "Raider", torso = SKIN, legs = B_LEATHER, top = 2.2, attack = "slash", hold = true,
	build = function(r)
		cap(r, B_FUR, B_IRON)
		horns(r, B_BONE, false)
		mk(r, "UpperTorso", "block", V(0.5, 1.6, 1.06), CF(-0.75, 0, 0), B_FUR, FABRIC) -- the fur vest
		mk(r, "UpperTorso", "block", V(0.5, 1.6, 1.06), CF(0.75, 0, 0), B_FUR, FABRIC)
		furKilt(r, B_FUR, B_FUR_DARK)
		belt(r, B_LEATHER, B_IRON)
		bracers(r, B_LEATHER, nil)
		boots(r, C(46, 36, 24))
		axe(r, "RightHand", B_WOOD, B_IRON, nil, 1.0, false)
		axe(r, "LeftHand", B_WOOD, B_IRON, nil, 1.0, false)
	end }

BERSERKER[3] = { name = "Marauder", torso = SKIN, legs = B_LEATHER, top = 2.3, attack = "slash", hold = true,
	build = function(r)
		cap(r, B_FUR, B_IRON)
		horns(r, B_BONE, false)
		mk(r, "Head", "block", V(1.24, 0.18, 0.06), CF(0, 0.15, -0.62), B_RED, PLASTIC) -- war paint across the eyes
		furShoulders(r, B_FUR)
		tattoos(r, B_RED, false)
		wristWraps(r, C(90, 70, 50))
		furKilt(r, C(90, 70, 54), B_FUR_DARK)
		belt(r, C(46, 36, 24), C(200, 165, 70))
		boots(r, C(46, 36, 24))
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(1.1, 0.3, 1.1), CF(0, -0.15, 0), B_FUR, FABRIC)
		axe(r, "RightHand", C(90, 64, 40), B_STEEL, nil, 1.1, false)
		axe(r, "LeftHand", C(90, 64, 40), B_STEEL, nil, 1.1, false)
		both(r, { "LeftHand", "RightHand" }, "block", V(0.34, 0.2, 0.9), CF(0, 1.1, -2.3), C(138, 42, 42), PLASTIC) -- the red band on the heads
	end }

BERSERKER[4] = { name = "Berserker", torso = SKIN, legs = C(58, 46, 38), top = 2.4, attack = "slash", hold = true,
	build = function(r)
		helmet(r, B_IRON, C(46, 42, 42))
		horns(r, B_BONE, false)
		mk(r, "Head", "block", V(0.14, 0.9, 1.2), CF(0, 0.95, 0), C(74, 82, 92), METAL) -- the crest
		mk(r, "Head", "block", V(1.1, 0.14, 0.06), CF(0, -0.1, -0.62), C(30, 26, 36), PLASTIC) -- a scar
		tattoos(r, B_RED, false)
		mk(r, "UpperTorso", "block", V(0.1, 1.2, 0.06), CF(0.2, 0.1, -0.54) * ANG(0, 0, R(-20)), C(138, 42, 42), PLASTIC) -- the chest scar
		pauldrons(r, B_IRON)
		bracers(r, B_IRON, nil)
		furKilt(r, C(90, 70, 54), B_FUR_DARK)
		mk(r, "LowerTorso", "block", V(2.34, 0.14, 1.34), CF(0, -0.95, 0), B_IRON, METAL)
		belt(r, C(46, 36, 24), B_STEEL)
		boots(r, B_IRON)
		axe(r, "RightHand", C(58, 46, 38), B_STEEL, B_RED, 1.15, false)
		axe(r, "LeftHand", C(58, 46, 38), B_STEEL, B_RED, 1.15, false)
	end }

BERSERKER[5] = { name = "Bloodrager", torso = SKIN, legs = C(42, 32, 36), top = 2.4, attack = "slash", hold = true,
	build = function(r)
		helmet(r, C(74, 82, 92), C(30, 26, 36))
		horns(r, B_BLACK, false)
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(-0.25, 0.12, -0.64), B_BLOOD, NEON, { light = B_BLOOD, range = 8 })
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(0.25, 0.12, -0.64), B_BLOOD, NEON)
		mk(r, "Head", "block", V(0.08, 0.5, 0.06), CF(-0.3, -0.25, -0.62) * ANG(0, 0, R(15)), B_RED, PLASTIC)
		tattoos(r, B_ORANGE, true)
		-- the chains across the chest and the medallion
		for i = -2, 2 do
			mk(r, "UpperTorso", "block", V(0.14, 0.26, 0.1), CF(i * 0.4, i * 0.4, -0.58) * ANG(0, 0, R(45)), B_IRON, METAL)
			mk(r, "UpperTorso", "block", V(0.14, 0.26, 0.1), CF(i * 0.4, -i * 0.4, -0.58) * ANG(0, 0, R(-45)), B_IRON, METAL)
		end
		mk(r, "UpperTorso", "cyl", V(0.1, 0.5, 0.5), CF(0, 0, -0.64) * ANG(0, R(90), 0), C(74, 82, 92), METAL)
		mk(r, "UpperTorso", "ball", V(0.26, 0.26, 0.1), CF(0, 0, -0.7), B_BLOOD, NEON, { light = B_BLOOD, range = 8 })
		spikedPauldrons(r, C(74, 82, 92), B_STEEL, false)
		bracers(r, C(74, 82, 92), nil)
		furKilt(r, C(58, 42, 42), C(42, 32, 36))
		mk(r, "LowerTorso", "block", V(2.34, 0.14, 1.34), CF(0, -0.95, 0), B_IRON, METAL)
		belt(r, C(42, 32, 36), B_BLOOD)
		boots(r, C(74, 82, 92))
		axe(r, "RightHand", C(30, 26, 36), B_STEEL, B_BLOOD, 1.2, false)
		axe(r, "LeftHand", C(30, 26, 36), B_STEEL, B_BLOOD, 1.2, false)
	end }

BERSERKER[6] = { name = "Warlord", torso = SKIN, legs = C(42, 32, 36), top = 2.8, attack = "slash", hold = true,
	build = function(r)
		helmet(r, C(74, 82, 92), C(30, 26, 36))
		mk(r, "Head", "block", V(1.56, 0.14, 1.56), CF(0, 0.38, 0.03), C(200, 165, 70), METAL)
		horns(r, B_BONE, false)
		mk(r, "Head", "block", V(0.14, 1.2, 1.3), CF(0, 1.05, 0), C(200, 165, 70), METAL) -- the gold crest
		mk(r, "UpperTorso", "block", V(2.06, 0.8, 1.08), CF(0, 0.4, 0), C(74, 82, 92), METAL) -- the chest harness
		mk(r, "UpperTorso", "block", V(2.08, 0.12, 1.1), CF(0, 0.0, 0), C(200, 165, 70), METAL)
		tattoos(r, B_ORANGE, true)
		spikedPauldrons(r, C(74, 82, 92), C(200, 165, 70), false)
		bracers(r, C(200, 165, 70), nil)
		furKilt(r, C(74, 48, 48), C(42, 32, 36))
		mk(r, "LowerTorso", "block", V(2.34, 0.14, 1.34), CF(0, -0.95, 0), C(200, 165, 70), METAL)
		belt(r, C(42, 32, 36), C(200, 165, 70))
		-- the skull trophies on the belt
		for _, x in ipairs({ -0.7, 0.7 }) do
			mk(r, "LowerTorso", "block", V(0.36, 0.4, 0.3), CF(x, -0.4, -0.58), B_BONE, PLASTIC)
			mk(r, "LowerTorso", "block", V(0.08, 0.1, 0.05), CF(x - 0.08, -0.35, -0.74), B_BLACK, PLASTIC)
			mk(r, "LowerTorso", "block", V(0.08, 0.1, 0.05), CF(x + 0.08, -0.35, -0.74), B_BLACK, PLASTIC)
		end
		boots(r, C(74, 82, 92))
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.1, 0.12, 1.25), CF(0, 0.5, -0.05), C(200, 165, 70), METAL)
		axe(r, "RightHand", C(30, 26, 36), B_STEEL, B_ORANGE, 1.5, true)
		mk(r, "RightHand", "block", V(0.34, 2.6, 0.2), CF(0, -0.15, -2.9), C(200, 165, 70), METAL)
	end }

BERSERKER[7] = { name = "Firebrand", torso = SKIN, legs = C(42, 26, 26), top = 2.6, attack = "slash", hold = true,
	build = function(r)
		flames(r, "Head", { { -0.4, 0.9, 0.1 }, { 0, 1.1, 0 }, { 0.4, 0.9, 0.1 }, { -0.2, 1.3, -0.1 }, { 0.25, 1.35, 0.05 } }, 0.5)
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(-0.25, 0.12, -0.64), K_FLAME, NEON, { light = K_FIRE, range = 8 })
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(0.25, 0.12, -0.64), K_FLAME, NEON)
		tattoos(r, K_FIRE, true)
		mk(r, "UpperTorso", "block", V(0.08, 1.5, 0.06), CF(0, 0, -0.54), K_FIRE, NEON)
		spikedPauldrons(r, C(42, 26, 26), K_FIRE, true)
		bracers(r, C(42, 26, 26), K_FIRE)
		furKilt(r, C(58, 32, 32), C(42, 26, 26))
		mk(r, "LowerTorso", "block", V(2.34, 0.14, 1.34), CF(0, -0.95, 0), B_ORANGE, NEON)
		belt(r, C(42, 26, 26), K_FIRE)
		boots(r, C(42, 26, 26))
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.1, 0.1, 1.25), CF(0, 0.5, -0.05), B_ORANGE, NEON)
		axe(r, "RightHand", C(42, 26, 26), K_FIRE, K_FLAME, 1.2, false)
		axe(r, "LeftHand", C(42, 26, 26), K_FIRE, K_FLAME, 1.2, false)
		flames(r, "RightHand", { { 0, 1.2, -2.5 }, { 0, 1.5, -2.2 } }, 0.4)
		flames(r, "LeftHand", { { 0, 1.2, -2.5 }, { 0, 1.5, -2.2 } }, 0.4)
		runeRing(r, B_ORANGE)
		sparkleAura(r, K_FIRE, 16)
	end }

BERSERKER[8] = { name = "Warchief", torso = B_BLACK, legs = B_BLACK, top = 3.0, attack = "slash", hold = true,
	build = function(r)
		helmet(r, B_BLACK, C(20, 18, 24))
		mk(r, "Head", "block", V(1.56, 0.14, 1.56), CF(0, 0.38, 0.03), B_GOLD, METAL)
		horns(r, B_GOLD, false)
		mk(r, "Head", "block", V(0.14, 1.3, 1.1), CF(0, 1.1, 0.05), B_GOLD, METAL)
		mk(r, "Head", "block", V(0.2, 0.7, 0.6), CF(0, 1.75, 0.1), B_RED, FABRIC) -- the red plume
		mk(r, "Head", "block", V(0.3, 0.1, 0.06), CF(-0.42, -0.1, -0.62), B_RED, PLASTIC) -- face stripes
		mk(r, "Head", "block", V(0.3, 0.1, 0.06), CF(0.42, -0.1, -0.62), B_RED, PLASTIC)
		cloak(r, C(110, 118, 128), C(74, 82, 92), 4.6)
		mk(r, "UpperTorso", "ball", V(2.3, 0.7, 1.4), CF(0, 0.85, 0.2), C(140, 148, 160), FABRIC) -- the wolf pelt collar
		chestPlate(r, C(42, 32, 36), B_GOLD)
		mk(r, "UpperTorso", "block", V(0.7, 0.7, 0.1), CF(0, 0.05, -0.72) * ANG(0, 0, R(45)), B_GOLD, METAL)
		mk(r, "UpperTorso", "block", V(0.4, 0.4, 0.12), CF(0, 0.05, -0.76) * ANG(0, 0, R(45)), B_RED, NEON)
		spikedPauldrons(r, B_GOLD, B_BLACK, false)
		bracers(r, B_GOLD, nil)
		mk(r, "LowerTorso", "block", V(2.3, 1.1, 1.3), CF(0, -0.5, 0), C(42, 32, 36), FABRIC)
		mk(r, "LowerTorso", "block", V(2.34, 0.14, 1.34), CF(0, -0.95, 0), B_GOLD, METAL)
		belt(r, C(42, 32, 36), B_GOLD)
		gloves(r, B_GOLD)
		boots(r, B_GOLD)
		axe(r, "RightHand", B_BLACK, B_GOLD, nil, 1.7, true)
		mk(r, "RightHand", "block", V(0.36, 3.0, 0.2), CF(0, -0.15, -3.1), C(255, 240, 160), METAL)
		mk(r, "RightHand", "block", V(0.38, 3.2, 0.1), CF(0, -0.15, -2.4), B_RED, PLASTIC)
	end }

BERSERKER[9] = { name = "Legend", torso = SKIN, legs = C(42, 26, 26), top = 3.6, attack = "slash", hold = true,
	build = function(r)
		mk(r, "Head", "block", V(1.26, 0.2, 1.26), CF(0, 0.5, 0), C(240, 200, 90), METAL) -- the gold band
		horns(r, K_FIRE, true)
		for _, s in ipairs({ -1, 1 }) do
			mk(r, "Head", "block", V(0.2, 0.6, 0.2), CF(s * 1.4, 1.5, 0) * ANG(0, 0, R(s * -15)), K_FLAME, NEON)
		end
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(-0.25, 0.12, -0.64), C(255, 240, 160), NEON, { light = K_FLAME, range = 8 })
		mk(r, "Head", "ball", V(0.3, 0.16, 0.1), CF(0.25, 0.12, -0.64), C(255, 240, 160), NEON)
		mk(r, "Head", "block", V(0.08, 0.5, 0.06), CF(-0.32, -0.25, -0.62) * ANG(0, 0, R(15)), K_FIRE, NEON)
		mk(r, "Head", "block", V(0.08, 0.5, 0.06), CF(0.32, -0.25, -0.62) * ANG(0, 0, R(-15)), K_FIRE, NEON)
		halo(r, K_FLAME, 2.5)
		tattoos(r, K_FIRE, true)
		mk(r, "UpperTorso", "block", V(0.08, 1.5, 0.06), CF(0, 0, -0.54) * ANG(0, 0, R(8)), K_FLAME, NEON)
		mk(r, "UpperTorso", "cyl", V(0.1, 0.6, 0.6), CF(0, 0.05, -0.56) * ANG(0, R(90), 0), C(240, 200, 90), METAL)
		mk(r, "UpperTorso", "ball", V(0.3, 0.3, 0.12), CF(0, 0.05, -0.62), K_FIRE, NEON, { light = K_FIRE, range = 12, bright = 3 })
		spikedPauldrons(r, C(240, 200, 90), K_FIRE, true)
		bracers(r, C(240, 200, 90), K_FIRE)
		furKilt(r, C(58, 32, 32), C(42, 26, 26))
		mk(r, "LowerTorso", "block", V(2.34, 0.14, 1.34), CF(0, -0.95, 0), C(240, 200, 90), METAL)
		belt(r, C(42, 26, 26), K_FIRE)
		boots(r, C(240, 200, 90))
		lightWings(r, K_FLAME, K_FIRE)
		axe(r, "RightHand", C(42, 26, 26), K_FIRE, K_FLAME, 1.5, true)
		axe(r, "LeftHand", C(42, 26, 26), K_FIRE, K_FLAME, 1.5, true)
		flames(r, "RightHand", { { 0, 1.6, -2.6 }, { 0, -1.9, -2.6 }, { 0, 2.0, -2.1 } }, 0.5)
		flames(r, "LeftHand", { { 0, 1.6, -2.6 }, { 0, -1.9, -2.6 }, { 0, 2.0, -2.1 } }, 0.5)
		runeRing(r, K_FIRE)
		sparkleAura(r, K_FLAME, 40)
	end }

-- ── The Tank: 9 levels (design: the golden tank cards) ──
--   1 Guard · 2 Shieldbearer · 3 Defender · 4 Bulwark · 5 Juggernaut · 6 Ironwall · 7 Titan · 8 Colossus · 9 Legend
local T_LEATHER = C(138, 106, 68)
local T_WOOD = C(160, 122, 74)
local T_STEEL = C(154, 163, 175)
local T_IRON = C(110, 118, 128)
local T_DARK_IRON = C(74, 62, 58)
local T_BLUE = C(74, 90, 140)
local T_SKY = C(120, 200, 255)
local T_ICE = C(220, 232, 240)
local T_GOLD = C(200, 165, 70)
local T_GOLD_LIGHT = C(250, 220, 80)
local T_CREAM = C(255, 240, 160)
local T_CRIMSON = C(138, 42, 58)
local T_CYAN = C(110, 220, 255)
local T_NAVY = C(42, 58, 82)
local T_ORANGE = C(250, 150, 70)

local TANK = {}

TANK[1] = { name = "Guard", torso = T_LEATHER, legs = C(90, 70, 50), top = 1.7, attack = "slash", hold = true,
	build = function(r)
		cap(r, C(110, 82, 52), C(90, 64, 40))
		mk(r, "UpperTorso", "block", V(1.7, 1.4, 0.14), CF(0, 0, -0.55), C(110, 82, 52), FABRIC) -- the leather vest
		mk(r, "UpperTorso", "block", V(0.1, 1.4, 0.05), CF(0, 0, -0.63), C(90, 64, 40), FABRIC)
		belt(r, C(74, 56, 38), T_STEEL)
		boots(r, C(60, 50, 40))
		roundShield(r, T_WOOD, nil)
		club(r, C(122, 90, 58))
	end }

TANK[2] = { name = "Shieldbearer", torso = T_IRON, legs = C(74, 58, 42), top = 1.9, attack = "slash", hold = true,
	build = function(r)
		helmet(r, T_STEEL, T_IRON)
		mk(r, "Head", "block", V(0.14, 0.5, 1.2), CF(0, 0.95, 0), T_STEEL, METAL)
		chestPlate(r, T_STEEL, nil)
		mk(r, "UpperTorso", "block", V(0.5, 0.5, 0.1), CF(0, 0.1, -0.72) * ANG(0, 0, R(45)), T_GOLD, METAL)
		belt(r, C(74, 56, 38), T_GOLD)
		gloves(r, C(74, 56, 38))
		boots(r, T_IRON)
		roundShield(r, T_STEEL, T_IRON)
		mk(r, "LeftHand", "ball", V(0.5, 0.5, 0.3), CF(-0.35, 0.1, -0.86), T_GOLD, METAL)
		mace(r, C(90, 64, 40), T_STEEL, nil)
	end }

TANK[3] = { name = "Defender", torso = T_IRON, legs = T_IRON, top = 2.0, attack = "slash", hold = true,
	build = function(r)
		helmet(r, T_STEEL, T_IRON)
		mk(r, "Head", "block", V(0.18, 0.75, 0.1), CF(0, 0.2, -0.68), T_STEEL, METAL) -- the nasal bar
		mk(r, "Head", "block", V(1.3, 0.4, 0.1), CF(0, -0.4, -0.62), T_IRON, METAL) -- mail over the chin
		mk(r, "Head", "block", V(0.14, 0.5, 1.2), CF(0, 0.95, 0), T_STEEL, METAL)
		mk(r, "UpperTorso", "block", V(1.85, 1.4, 0.2), CF(0, 0.05, -0.58), T_BLUE, METAL)
		chestCross(r, K_WHITE)
		pauldrons(r, T_STEEL)
		belt(r, C(74, 56, 38), T_GOLD)
		kneepads(r, T_STEEL)
		gloves(r, T_IRON)
		boots(r, T_IRON)
		towerShield(r, T_BLUE, T_IRON, "cross", K_WHITE, 1.0)
		mace(r, C(90, 64, 40), T_STEEL, T_STEEL)
	end }

TANK[4] = { name = "Bulwark", torso = T_STEEL, legs = T_STEEL, top = 2.1, attack = "slash", hold = true,
	build = function(r)
		helmet(r, T_STEEL, T_IRON)
		mk(r, "Head", "block", V(1.56, 0.12, 1.56), CF(0, 0.38, 0.03), T_GOLD, METAL)
		mk(r, "Head", "block", V(0.14, 0.6, 1.2), CF(0, 1.0, 0), T_STEEL, METAL)
		mk(r, "Head", "block", V(1.3, 0.4, 0.1), CF(0, -0.4, -0.62), T_IRON, METAL)
		chestPlate(r, T_IRON, T_GOLD)
		mk(r, "UpperTorso", "block", V(0.7, 0.7, 0.1), CF(0, 0.05, -0.72) * ANG(0, 0, R(45)), T_GOLD, METAL)
		spikedPauldrons(r, T_IRON, T_STEEL, false)
		bracers(r, T_IRON, nil)
		belt(r, C(74, 82, 92), T_GOLD)
		kneepads(r, T_IRON)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.9, 0.08, 0.1), CF(0, 0.5, -0.68), T_GOLD, METAL)
		gloves(r, T_IRON)
		boots(r, T_IRON)
		towerShield(r, T_STEEL, T_GOLD, "diamond", T_BLUE, 1.05)
		warHammer(r, T_STEEL, C(74, 56, 38), nil, 1.0)
	end }

TANK[5] = { name = "Juggernaut", torso = T_IRON, legs = T_IRON, top = 2.3, attack = "slash", hold = true,
	build = function(r)
		greatHelm(r, T_IRON, T_STEEL, T_SKY)
		mk(r, "Head", "block", V(0.16, 0.7, 1.3), CF(0, 1.05, 0), T_STEEL, METAL)
		chestPlate(r, T_IRON, T_SKY)
		mk(r, "UpperTorso", "cyl", V(0.12, 0.8, 0.8), CF(0, 0.05, -0.72) * ANG(0, R(90), 0), T_STEEL, METAL)
		mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.2), CF(0, 0.05, -0.78), T_SKY, NEON, { light = T_SKY, range = 10 })
		pauldrons(r, T_IRON, 1.2)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.3, 0.08, 1.3), CF(0, 0.2, 0), T_SKY, NEON)
		bracers(r, T_IRON, nil)
		belt(r, C(42, 42, 52), T_SKY)
		kneepads(r, T_IRON)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.9, 0.08, 0.1), CF(0, 0.5, -0.68), T_SKY, NEON)
		gloves(r, T_IRON)
		boots(r, T_IRON)
		towerShield(r, T_IRON, T_SKY, "diamond", T_SKY, 1.15)
		warHammer(r, T_IRON, C(42, 42, 52), T_SKY, 1.15)
	end }

TANK[6] = { name = "Ironwall", torso = T_DARK_IRON, legs = C(46, 42, 42), top = 2.3, attack = "slash", hold = true,
	build = function(r)
		greatHelm(r, T_DARK_IRON, nil, T_ORANGE)
		mk(r, "Head", "block", V(0.6, 0.3, 0.3), CF(-0.95, 0.5, 0), T_DARK_IRON, METAL) -- the short horns
		mk(r, "Head", "block", V(0.6, 0.3, 0.3), CF(0.95, 0.5, 0), T_DARK_IRON, METAL)
		chestPlate(r, T_DARK_IRON, nil)
		mk(r, "UpperTorso", "block", V(0.08, 1.2, 0.06), CF(0, 0.05, -0.72), T_ORANGE, NEON)
		for _, s in ipairs({ -1, 1 }) do
			mk(r, "UpperTorso", "block", V(0.08, 0.6, 0.06), CF(s * 0.5, 0.35, -0.72) * ANG(0, 0, R(s * 30)), T_ORANGE, NEON)
			mk(r, "UpperTorso", "block", V(0.08, 0.6, 0.06), CF(s * 0.5, -0.25, -0.72) * ANG(0, 0, R(s * -30)), T_ORANGE, NEON)
		end
		mk(r, "UpperTorso", "ball", V(0.3, 0.3, 0.14), CF(0, 0.05, -0.76), T_ORANGE, NEON, { light = T_ORANGE, range = 12 })
		pauldrons(r, T_DARK_IRON, 1.2)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(0.08, 0.5, 0.08), CF(-0.2, 0.55, -0.6) * ANG(0, 0, R(30)), T_ORANGE, NEON)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(0.08, 0.5, 0.08), CF(0.2, 0.55, -0.6) * ANG(0, 0, R(-30)), T_ORANGE, NEON)
		bracers(r, T_DARK_IRON, T_ORANGE)
		belt(r, C(30, 26, 26), T_ORANGE)
		kneepads(r, T_DARK_IRON)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.4, 0.08, 0.08), CF(-0.2, 0.5, -0.69) * ANG(0, 0, R(35)), T_ORANGE, NEON)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.4, 0.08, 0.08), CF(0.2, 0.5, -0.69) * ANG(0, 0, R(-35)), T_ORANGE, NEON)
		gloves(r, T_DARK_IRON)
		boots(r, C(30, 26, 26))
		both(r, { "LeftFoot", "RightFoot" }, "block", V(1.1, 0.08, 1.25), CF(0, 0.5, -0.05), T_ORANGE, NEON)
		towerShield(r, T_DARK_IRON, C(46, 42, 42), "runes", T_ORANGE, 1.15)
		-- the armored fist
		mk(r, "RightHand", "block", V(1.5, 1.2, 1.5), CF(0, -0.25, -0.1), T_DARK_IRON, METAL)
		for _, x in ipairs({ -0.4, 0, 0.4 }) do
			mk(r, "RightHand", "block", V(0.22, 0.5, 0.1), CF(x, -0.2, -0.86), T_ORANGE, NEON, x == 0 and { light = T_ORANGE, range = 8 } or nil)
		end
	end }

TANK[7] = { name = "Titan", torso = T_NAVY, legs = T_NAVY, top = 2.7, attack = "slash", hold = true,
	build = function(r)
		greatHelm(r, T_ICE, nil, T_CYAN)
		mk(r, "Head", "block", V(0.3, 0.9, 0.3), CF(0, 1.2, 0) * ANG(0, R(45), 0), T_CYAN, NEON, { light = T_CYAN, range = 8 }) -- the crest crystal
		chestPlate(r, T_ICE, nil)
		mk(r, "UpperTorso", "block", V(0.9, 0.9, 0.1), CF(0, 0.05, -0.72) * ANG(0, 0, R(45)), T_NAVY, METAL)
		mk(r, "UpperTorso", "block", V(0.5, 0.5, 0.14), CF(0, 0.05, -0.76) * ANG(0, 0, R(45)), T_CYAN, NEON, { light = T_CYAN, range = 12, bright = 2 })
		spikedPauldrons(r, T_ICE, T_CYAN, true)
		bracers(r, T_ICE, T_CYAN)
		belt(r, T_NAVY, T_CYAN)
		kneepads(r, T_ICE)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.3, 0.3, 0.08), CF(0, 0.5, -0.7) * ANG(0, 0, R(45)), T_CYAN, NEON)
		gloves(r, T_ICE)
		boots(r, T_ICE)
		-- the energy barrier: two arcs of light beside the body
		for _, s in ipairs({ -1, 1 }) do
			for i = -2, 2 do
				local a = R(i * 18)
				local p = mk(r, "UpperTorso", "block", V(0.12, 0.9, 0.6), CF(s * 2.8 * math.cos(a), math.sin(a) * 2.8 - 0.3, 0) * ANG(0, 0, R(-i * 18 * s)), T_CYAN, NEON, i == 0 and { light = T_CYAN, range = 10 } or nil)
				if p then
					p.Transparency = 0.45
				end
			end
		end
		towerShield(r, T_ICE, T_NAVY, "diamond", T_CYAN, 1.2)
		warHammer(r, T_ICE, T_NAVY, T_CYAN, 1.2)
	end }

TANK[8] = { name = "Colossus", torso = T_GOLD_LIGHT, legs = C(42, 42, 52), top = 2.6, attack = "slash", hold = true,
	build = function(r)
		greatHelm(r, T_GOLD_LIGHT, T_CRIMSON, nil)
		for i = -2, 2 do -- the crest fan
			mk(r, "Head", "wedge", V(0.22, 0.9 - math.abs(i) * 0.15, 0.3), CF(i * 0.3, 1.2, 0.0) * ANG(0, R(180), 0), T_CREAM, METAL)
		end
		mk(r, "UpperTorso", "block", V(1.9, 1.45, 0.3), CF(0, 0.05, -0.6), T_CREAM, METAL)
		mk(r, "UpperTorso", "block", V(1.6, 1.15, 0.1), CF(0, 0.05, -0.76), T_CRIMSON, METAL)
		mk(r, "UpperTorso", "block", V(0.7, 0.7, 0.06), CF(0, 0.05, -0.82), T_GOLD_LIGHT, METAL)
		mk(r, "UpperTorso", "block", V(0.7, 0.7, 0.06), CF(0, 0.05, -0.82) * ANG(0, 0, R(45)), T_GOLD_LIGHT, METAL)
		spikedPauldrons(r, T_GOLD_LIGHT, T_CREAM, false)
		both(r, { "LeftUpperArm", "RightUpperArm" }, "block", V(1.64, 0.1, 1.64), CF(0, 0.5, 0), T_CRIMSON, METAL)
		bracers(r, T_CREAM, nil)
		belt(r, C(42, 42, 52), T_CRIMSON)
		kneepads(r, T_GOLD_LIGHT)
		gloves(r, T_GOLD_LIGHT)
		boots(r, T_GOLD_LIGHT)
		-- the banner on the back
		mk(r, "UpperTorso", "block", V(0.1, 5.2, 0.1), CF(0.9, 1.6, 0.75), C(74, 56, 38), Enum.Material.Wood)
		mk(r, "UpperTorso", "block", V(0.08, 2.0, 1.5), CF(0.9, 3.1, 1.55), T_CRIMSON, FABRIC)
		mk(r, "UpperTorso", "block", V(0.1, 2.06, 0.1), CF(0.9, 3.1, 2.3), T_GOLD_LIGHT, METAL)
		mk(r, "UpperTorso", "block", V(0.06, 0.6, 0.6), CF(0.85, 3.1, 1.55) * ANG(R(45), 0, 0), T_GOLD_LIGHT, METAL)
		towerShield(r, T_CRIMSON, T_GOLD_LIGHT, "star", T_GOLD_LIGHT, 1.25)
		warHammer(r, T_GOLD_LIGHT, C(42, 42, 52), T_CREAM, 1.2)
	end }

TANK[9] = { name = "Legend", torso = T_GOLD_LIGHT, legs = C(42, 42, 64), top = 3.5, attack = "slash", hold = true,
	build = function(r)
		greatHelm(r, T_CREAM, T_GOLD_LIGHT, T_CYAN)
		for _, x in ipairs({ -0.4, 0, 0.4 }) do
			mk(r, "Head", "wedge", V(0.26, 0.8, 0.3), CF(x, 1.15, 0) * ANG(0, R(180), 0), T_GOLD_LIGHT, METAL)
		end
		halo(r, T_GOLD_LIGHT, 2.4)
		mk(r, "UpperTorso", "block", V(1.9, 1.45, 0.3), CF(0, 0.05, -0.6), T_CREAM, METAL)
		mk(r, "UpperTorso", "block", V(1.6, 1.15, 0.1), CF(0, 0.05, -0.76), C(42, 42, 64), METAL)
		mk(r, "UpperTorso", "block", V(0.8, 0.8, 0.08), CF(0, 0.05, -0.82) * ANG(0, 0, R(45)), T_GOLD_LIGHT, METAL)
		mk(r, "UpperTorso", "block", V(0.45, 0.45, 0.14), CF(0, 0.05, -0.88) * ANG(0, 0, R(45)), T_CYAN, NEON, { light = T_CYAN, range = 16, bright = 4, sparkle = T_CYAN, rate = 25 })
		spikedPauldrons(r, T_CREAM, T_CYAN, true)
		bracers(r, T_CREAM, T_CYAN)
		belt(r, C(42, 42, 64), T_CYAN)
		kneepads(r, T_GOLD_LIGHT)
		both(r, { "LeftLowerLeg", "RightLowerLeg" }, "block", V(0.3, 0.3, 0.08), CF(0, 0.5, -0.7) * ANG(0, 0, R(45)), T_CYAN, NEON)
		gloves(r, T_GOLD_LIGHT)
		boots(r, T_GOLD_LIGHT)
		lightWings(r, T_GOLD_LIGHT, T_CYAN)
		towerShield(r, C(42, 42, 64), T_GOLD_LIGHT, "diamond", T_CYAN, 1.3)
		warHammer(r, T_CREAM, T_GOLD_LIGHT, T_CYAN, 1.25)
		mk(r, "RightHand", "block", V(0.3, 0.3, 0.7), CF(0, -0.15, -4.15) * ANG(0, R(45), 0), T_CYAN, NEON, { light = T_CYAN, range = 10 })
		sparkleAura(r, T_GOLD_LIGHT, 40)
	end }

-- The classes that have a design here.
local CLASSES = { Soldier = LEVELS, Knight = KNIGHT, Archer = ARCHER, Mage = MAGE, Hunter = HUNTER, Berserker = BERSERKER, Tank = TANK }

-- The block body: the R15 limbs as plain parts (name, size, center; the soles are at y = 0, scale 1).
local BLOCK_LIMBS = {
	{ "HumanoidRootPart", V(2, 2, 1), V(0, 3, 0) },
	{ "LeftFoot", V(1, 0.3, 1), V(-0.5, 0.15, 0) },
	{ "RightFoot", V(1, 0.3, 1), V(0.5, 0.15, 0) },
	{ "LeftLowerLeg", V(1, 1.2, 1), V(-0.5, 0.9, 0) },
	{ "RightLowerLeg", V(1, 1.2, 1), V(0.5, 0.9, 0) },
	{ "LeftUpperLeg", V(1, 1.0, 1), V(-0.5, 1.7, 0) },
	{ "RightUpperLeg", V(1, 1.0, 1), V(0.5, 1.7, 0) },
	{ "LowerTorso", V(2, 0.4, 1), V(0, 2.2, 0) },
	{ "UpperTorso", V(2, 1.6, 1), V(0, 3.2, 0) },
	{ "LeftUpperArm", V(1, 1.2, 1), V(-1.5, 3.4, 0) },
	{ "RightUpperArm", V(1, 1.2, 1), V(1.5, 3.4, 0) },
	{ "LeftLowerArm", V(1, 0.8, 1), V(-1.5, 2.6, 0) },
	{ "RightLowerArm", V(1, 0.8, 1), V(1.5, 2.6, 0) },
	{ "LeftHand", V(1, 0.3, 1), V(-1.5, 2.15, 0) },
	{ "RightHand", V(1, 0.3, 1), V(1.5, 2.15, 0) },
	{ "Head", V(1.2, 1.2, 1.2), V(0, 4.6, 0) },
}

local function blockBody(rs: number): Model
	local model = Instance.new("Model")
	for _, limb in BLOCK_LIMBS do
		local p = Instance.new("Part")
		p.Name = limb[1]
		p.Size = limb[2] * rs
		p.CFrame = CF(limb[3] * rs)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
	end
	local root = model.HumanoidRootPart
	root.Transparency = 1
	root.CanQuery = false
	-- The face: two eyes and a smile.
	local function face(size, offset)
		local p = Instance.new("Part")
		p.Name = "Face"
		p.Size = size * rs
		p.CFrame = CF((V(0, 4.6, 0) + offset) * rs)
		p.Color = C(20, 20, 20)
		p.Material = PLASTIC
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Parent = model
	end
	face(V(0.16, 0.25, 0.05), V(-0.25, 0.12, -0.61))
	face(V(0.16, 0.25, 0.05), V(0.25, 0.12, -0.61))
	face(V(0.5, 0.08, 0.05), V(0, -0.25, -0.61))
	return model
end

-- ---------------------------------------------------------------------------------------------------------
-- The Knight and the Archer: 30 merge levels each, every level a complete R15 character of its own (own body
-- proportions, joints and gear) from the evolution models. Nothing comes from the base rig here: the body
-- parts, the 15 Motor6D joints and the welded gear are all built from the data, at the scale asked for.
local MATERIAL: { [number]: Enum.Material } = {}
for _, item in Enum.Material:GetEnumItems() do
	MATERIAL[item.Value] = item
end
local PART_TYPE: { [number]: Enum.PartType } = {}
for _, item in Enum.PartType:GetEnumItems() do
	PART_TYPE[item.Value] = item
end

-- `cf` with its position scaled by `k` (the rotation stays).
local function scaledCF(cf: CFrame, k: number): CFrame
	return CFrame.new(cf.Position * k) * cf.Rotation
end

local function evolutionPart(entry, k: number, static: boolean): BasePart
	local extra = entry[6]
	local p: BasePart
	if extra and extra.wedge then
		p = Instance.new("WedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = (extra and extra.shape and PART_TYPE[extra.shape]) or Enum.PartType.Block
		p = part
	end
	p.Size = entry[3] * k
	p.Color = entry[4]
	p.Material = MATERIAL[entry[5]] or PLASTIC
	p.Transparency = (extra and extra.t) or 0
	p.Reflectance = (extra and extra.r) or 0
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.Anchored = static
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- Builds the character of the level; same contract as SoldierRig.build. Returns nil when the class has no
-- evolution or the level no data.
local function buildEvolution(class: string, tier: number, s: number, bare: boolean?): (Model?, BasePart?, number?)
	local evolution = EVOLUTIONS[class]
	local data = evolution and evolution.data.level(math.clamp(tier, 1, evolution.data.Count))
	if not data then
		return nil
	end
	local rs = s * RIG_SCALE
	local isStatic = bare == true
	local model = Instance.new("Model")
	model.Name = "Soldier"

	-- The body: the 16 R15 parts, in model space (feet on y = 0, facing -Z).
	local parts: { [string]: BasePart } = {}
	local soleY = math.huge
	for _, entry in data.body do
		local p = evolutionPart(entry, rs, isStatic)
		p.Name = entry[1]
		p.CFrame = scaledCF(entry[2], rs)
		p.CanQuery = true
		p.CastShadow = p.Name ~= "HumanoidRootPart"
		p.Parent = model
		parts[p.Name] = p
		if string.find(p.Name, "Foot") then
			soleY = math.min(soleY, p.Position.Y - p.Size.Y / 2)
		end
	end
	local root = parts.HumanoidRootPart
	local head = parts.Head
	if not root or not head then
		model:Destroy()
		return nil
	end
	root.Anchored = true
	model.PrimaryPart = root
	if soleY == math.huge then
		soleY = root.Position.Y - 2.95 * rs
	end
	-- The pivot sits FEET * s above the soles (Soldier.lift), like every other class.
	root.PivotOffset = CFrame.new(0, FEET * s - (root.Position.Y - soleY), 0)

	-- The gear, welded on the body part it belongs to.
	for _, entry in data.gear do
		local host = parts[entry[1]]
		if host then
			local p = evolutionPart(entry, rs, isStatic)
			p.Name = "Gear_" .. entry[1]
			p.CFrame = host.CFrame * scaledCF(entry[2], rs)
			p.Parent = model
			if not isStatic then
				local w = Instance.new("WeldConstraint")
				w.Part0 = host
				w.Part1 = p
				w.Parent = p
				-- A light the design put on the part (a crystal, an orb): kept soft like the other auras.
				local lightData = entry[6] and entry[6].light
				if lightData then
					local l = Instance.new("PointLight")
					l.Color = Color3.fromRGB(lightData[1], lightData[2], lightData[3])
					l.Range = lightData[4] * rs * AURA_RANGE
					l.Brightness = lightData[5] * AURA_BRIGHTNESS
					l.Shadows = false
					l.Parent = p
				end
			end
		end
	end

	-- What the hands hold: separate, swappable models gripped by the hands (Weapons.luau).
	Weapons.equip(model, "RightHand", data.weapon, rs, isStatic)
	Weapons.equip(model, "LeftHand", data.offhand, rs, isStatic)

	if isStatic then
		-- A statue (UI previews, holograms): every part anchored in place, no joints, no Humanoid.
		return model, head, data.top * RIG_SCALE
	end

	-- The 15 Motor6D joints (parented to Part1, as Roblox rigs are), then the Humanoid that animates them.
	for _, joint in data.joints do
		local part0, part1 = parts[joint[2]], parts[joint[3]]
		if part0 and part1 then
			local m = Instance.new("Motor6D")
			m.Name = joint[1]
			m.Part0 = part0
			m.Part1 = part1
			m.C0 = scaledCF(joint[4], rs)
			m.C1 = scaledCF(joint[5], rs)
			m.Parent = part1
		end
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = (root.Position.Y - root.Size.Y / 2) - soleY
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.EvaluateStateMachine = false
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutomaticScalingEnabled = false
	Instance.new("Animator").Parent = humanoid
	humanoid.Parent = model
	Rig.animate(model, evolution.attack, tier >= evolution.holdFrom)
	return model, head, data.top * RIG_SCALE
end

local SoldierRig = {}

function SoldierRig.has(class: string): boolean
	return CLASSES[class] ~= nil
end

function SoldierRig.name(tier: number, class: string?): string
	local evolution = EVOLUTIONS[class or ""]
	if evolution then
		local data = evolution.data.level(math.clamp(tier, 1, evolution.data.Count))
		if data then
			return data.name
		end
	end
	local levels = CLASSES[class or "Soldier"] or LEVELS
	return levels[math.clamp(tier, 1, #levels)].name
end

-- Builds the Soldier of the level at the block scale `s` (Soldier.scale × the Ascended bonus). `bare` = a
-- still statue (UI previews, holograms): everything anchored, no Humanoid, no lights. Returns the model, its
-- head and how high the label floats over it (in studs at scale 1), or nil when there is no base rig.
function SoldierRig.build(tier: number, s: number, bare: boolean?, class: string?): (Model?, BasePart?, number?)
	if class and EVOLUTIONS[class] then
		-- The 30-level evolution (no base rig needed); the 9 cards below are only the fallback without data.
		local model, head, top = buildEvolution(class, tier, s, bare)
		if model then
			return model, head, top
		end
	end
	local base = Rig.base()
	local levels = CLASSES[class or "Soldier"] or LEVELS
	local def = levels[math.clamp(tier, 1, #levels)]
	local rs = s * RIG_SCALE
	local model = if base then base:Clone() else blockBody(rs)
	model.Name = "Soldier"
	if base then
		model:ScaleTo(rs)
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not head or (base and not humanoid) then
		model:Destroy()
		return nil
	end
	model.PrimaryPart = root
	root.Anchored = true
	-- The pivot sits FEET * s above the soles (Soldier.lift), a bit below the root's center.
	root.PivotOffset = CFrame.new(0, FEET * s - ((base and base:GetAttribute("Lift")) or 3) * rs, 0)

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.Massless = true
			if part ~= root then
				part.Material = PLASTIC
				part.Color = if part.Name == "Face" then part.Color elseif part == head or string.find(part.Name, "Hand") then SKIN elseif string.find(part.Name, "Leg") or string.find(part.Name, "Foot") then def.legs else def.torso
			end
		end
	end

	scale = rs
	static = bare == true or not humanoid
	local ok, err = pcall(def.build, model)
	if not ok then
		warn("[SoldierRig] level " .. tier .. " gear error: " .. tostring(err))
	end

	if not humanoid then
		-- The block body is a statue already (everything anchored).
	elseif bare then
		-- A statue: no joints, no Humanoid, every part anchored (it is moved part by part or with PivotTo).
		for _, item in model:GetDescendants() do
			if item:IsA("JointInstance") or item:IsA("WeldConstraint") then
				item:Destroy()
			elseif item:IsA("BasePart") then
				item.Anchored = true
			end
		end
		humanoid:Destroy()
	else
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.EvaluateStateMachine = false
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
		Rig.animate(model, def.attack, def.hold)
	end
	return model, head, def.top * RIG_SCALE
end

return SoldierRig
