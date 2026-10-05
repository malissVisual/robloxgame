--[[
	SOLDIER MERGE – 9× R15 voják (3D) pro Roblox Studio
	----------------------------------------------------
	Jak použít:
	1) Otevři Roblox Studio (nový Baseplate).
	2) View > Command Bar (nebo vlož tento kód do Script v ServerScriptService a dej Play).
	3) Vlož celý skript do Command Baru a stiskni Enter.
	4) V Workspace vznikne složka "SoldierMerge_R15" s 9 modely v řadě (Level 1 až 9).
	5) Model: pravý klik > "Save to File..." (.rbxm) nebo "Save to Roblox".

	Každý model je plnohodnotný R15 rig (Humanoid, Motor6D, animace fungují).
	Výstroj jsou Party přivařené (WeldConstraint) k R15 končetinám.
	Pokud něco sedí o kousek vedle, uprav offsety (CFrame.new) v příslušném levelu.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

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

--------------------------------------------------------------------
-- Pomocné funkce
--------------------------------------------------------------------
local function weld(a, b)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- Vytvoří díl výstroje přivařený k končetině R15 rigu
local function mk(rig, limb, kind, size, offset, color, mat, extra)
	local host = rig:FindFirstChild(limb)
	if not host then return nil end
	local p
	if kind == "wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
		p.Shape = (kind == "ball" and Enum.PartType.Ball) or (kind == "cyl" and Enum.PartType.Cylinder) or Enum.PartType.Block
	end
	p.Name = "Gear_" .. limb
	p.Size = size
	p.Color = color
	p.Material = mat or PLASTIC
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.Anchored = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = host.CFrame * offset
	p.Parent = rig
	weld(host, p)
	if extra and extra.light then
		local l = Instance.new("PointLight")
		l.Color = extra.light
		l.Range = extra.range or 10
		l.Brightness = extra.bright or 2
		l.Parent = p
	end
	if extra and extra.sparkle then
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(extra.sparkle)
		e.Rate = extra.rate or 18
		e.Lifetime = NumberRange.new(1, 2)
		e.Speed = NumberRange.new(1, 3)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
		e.LightEmission = 1
		e.Parent = p
	end
	return p
end

local function both(rig, limbs, ...)
	for _, l in ipairs(limbs) do mk(rig, l, ...) end
end

-- Čepice / přilba
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

local function rifle(r, col, glow, scale)
	scale = scale or 1
	mk(r, "RightHand", "block", V(0.3, 0.45, 2.3) * scale, CF(0, -0.15, -1.0), col, METAL)
	mk(r, "RightHand", "block", V(0.14, 0.14, 1.3), CF(0, -0.05, -2.6), col, METAL)
	mk(r, "RightHand", "block", V(0.26, 0.75, 0.38), CF(0, -0.65, -0.7), col, METAL)
	if glow then
		mk(r, "RightHand", "block", V(0.08, 0.08, 1.8), CF(0, 0.12, -1.3), glow, NEON, { light = glow, range = 8 })
	end
end

local function sword(r, bladeCol, guardCol, neon)
	mk(r, "RightHand", "block", V(0.28, 0.28, 0.9), CF(0, -0.15, 0.1), C(70, 20, 25), PLASTIC)
	mk(r, "RightHand", "block", V(1.0, 0.22, 0.25), CF(0, -0.15, -0.4), guardCol, METAL)
	mk(r, "RightHand", "block", V(0.14, 0.34, 4.6), CF(0, -0.15, -2.8), bladeCol, neon and NEON or METAL,
		neon and { light = bladeCol, range = 14, bright = 3 } or nil)
end

--------------------------------------------------------------------
-- Definice 9 levelů
--------------------------------------------------------------------
local LEVELS = {}

LEVELS[1] = { name = "Rekrut", torso = C(110, 143, 63), legs = C(78, 107, 44),
	build = function(r)
		cap(r, C(110, 143, 63), C(58, 85, 34))
		mk(r, "UpperTorso", "block", V(0.35, 0.5, 0.06), CF(0, 0.2, -0.53), C(207, 211, 214), METAL) -- dog tag
		mk(r, "UpperTorso", "block", V(0.7, 0.55, 0.1), CF(-0.55, 0.0, -0.53), C(95, 126, 53), FABRIC) -- kapsa
		boots(r, C(59, 47, 34))
	end }

LEVELS[2] = { name = "Vojin", torso = C(94, 138, 51), legs = C(70, 105, 42),
	build = function(r)
		helmet(r, C(75, 107, 42))
		belt(r, C(90, 67, 38), C(213, 180, 74))
		mk(r, "LeftUpperArm", "block", V(0.1, 0.55, 0.75), CF(-0.54, 0.25, 0), C(201, 58, 58), FABRIC)
		mk(r, "UpperTorso", "block", V(0.6, 0.5, 0.1), CF(-0.5, 0.1, -0.53), C(79, 122, 43), FABRIC)
		mk(r, "UpperTorso", "block", V(0.6, 0.5, 0.1), CF(0.5, 0.1, -0.53), C(79, 122, 43), FABRIC)
		boots(r, C(46, 36, 26))
	end }

LEVELS[3] = { name = "Desatnik", torso = C(88, 127, 50), legs = C(74, 107, 42),
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

LEVELS[4] = { name = "Serzant", torso = C(76, 107, 43), legs = C(61, 90, 34),
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

LEVELS[5] = { name = "Poruchik", torso = C(44, 58, 42), legs = C(38, 51, 31),
	build = function(r)
		local ac = C(194, 123, 255)
		helmet(r, C(38, 51, 31), C(14, 16, 16))
		mk(r, "Head", "block", V(1.3, 0.38, 0.28), CF(0, 0.35, -0.7), C(18, 21, 26), PLASTIC) -- NVG držák
		mk(r, "Head", "cyl", V(0.1, 0.42, 0.42), CF(-0.32, 0.35, -0.88) * ANG(0, R(90), 0), C(124, 255, 107), NEON, { light = C(124, 255, 107), range = 8 })
		mk(r, "Head", "cyl", V(0.1, 0.42, 0.42), CF(0.32, 0.35, -0.88) * ANG(0, R(90), 0), C(124, 255, 107), NEON, { light = C(124, 255, 107), range = 8 })
		chestPlate(r, C(29, 36, 32), ac)
		mk(r, "UpperTorso", "block", V(0.4, 0.4, 0.12), CF(0, 0.2, -0.72) * ANG(0, 0, R(45)), ac, NEON, { light = ac, range = 8 })
		mk(r, "UpperTorso", "block", V(0.28, 1.9, 0.14), CF(0, 0.05, -0.74) * ANG(0, 0, R(-48)), C(58, 63, 44), FABRIC) -- bandolír
		mk(r, "UpperTorso", "block", V(1.5, 1.7, 0.55), CF(0, -0.05, 0.85), C(22, 26, 20), FABRIC) -- batoh
		mk(r, "UpperTorso", "block", V(0.08, 2.4, 0.08), CF(0.7, 1.9, 0.9), C(34, 34, 34), METAL) -- anténa
		mk(r, "UpperTorso", "ball", V(0.22, 0.22, 0.22), CF(0.7, 3.12, 0.9), ac, NEON, { light = ac, range = 10 })
		pauldrons(r, C(29, 36, 32), 1.1)
		belt(r, C(20, 22, 26), C(214, 178, 74))
		kneepads(r, C(29, 36, 32))
		gloves(r, C(20, 22, 26))
		boots(r, C(20, 17, 15))
		rifle(r, C(29, 36, 32), ac)
		mk(r, "RightHand", "cyl", V(0.5, 0.3, 0.3), CF(0, 0.18, -1.0) * ANG(0, R(90), 0), C(17, 17, 17), METAL) -- zaměřovač
	end }

LEVELS[6] = { name = "Kapitan", torso = C(91, 107, 96), legs = C(76, 90, 80),
	build = function(r)
		local ac = C(255, 154, 46)
		local M = C(91, 107, 96)
		mk(r, "Head", "block", V(1.5, 1.45, 1.5), CF(0, 0.12, 0.02), M, METAL) -- plná přilba
		mk(r, "Head", "block", V(1.05, 0.28, 0.12), CF(0, 0.22, -0.78), ac, NEON, { light = ac, range = 8 }) -- hledí
		mk(r, "Head", "wedge", V(0.2, 0.55, 1.2), CF(0, 1.0, 0.0) * ANG(0, R(180), 0), C(61, 74, 66), METAL) -- hřeben
		mk(r, "Head", "block", V(0.6, 0.45, 0.2), CF(0, -0.35, -0.78), C(35, 42, 38), METAL)
		chestPlate(r, C(61, 74, 66), ac)
		mk(r, "UpperTorso", "cyl", V(0.18, 0.95, 0.95), CF(0, 0.15, -0.76) * ANG(0, R(90), 0), C(35, 42, 38), METAL)
		mk(r, "UpperTorso", "ball", V(0.6, 0.6, 0.4), CF(0, 0.15, -0.78), ac, NEON, { light = ac, range = 14, bright = 3 }) -- reaktor
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

LEVELS[7] = { name = "Major", torso = C(223, 233, 230), legs = C(205, 217, 214),
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
		-- hover kroužky pod nohama
		both(r, { "LeftFoot", "RightFoot" }, "cyl", V(0.1, 1.9, 1.9), CF(0, -0.35, 0) * ANG(0, 0, R(90)), ac, NEON, { light = ac, range = 8 })
		both(r, { "LeftFoot", "RightFoot" }, "cyl", V(0.08, 2.5, 2.5), CF(0, -0.6, 0) * ANG(0, 0, R(90)), ac, NEON)
		-- dron
		mk(r, "UpperTorso", "ball", V(1.0, 1.0, 1.0), CF(-2.7, 1.5, 0.2), C(28, 43, 48), METAL)
		mk(r, "UpperTorso", "ball", V(0.45, 0.45, 0.45), CF(-2.7, 1.5, -0.3), ac, NEON, { light = ac, range = 10 })
		mk(r, "UpperTorso", "block", V(1.9, 0.1, 0.25), CF(-2.7, 1.5, 0.2), W, METAL)
		rifle(r, W, ac, 1.2)
	end }

LEVELS[8] = { name = "General", torso = C(42, 90, 44), legs = C(31, 74, 36),
	build = function(r)
		local G = C(255, 211, 90)
		local GD = C(199, 154, 30)
		local RED = C(193, 18, 31)
		-- plášť
		mk(r, "UpperTorso", "block", V(2.3, 3.4, 0.14), CF(0, -1.2, 0.68) * ANG(R(6), 0, 0), C(224, 54, 74), FABRIC)
		mk(r, "UpperTorso", "block", V(0.14, 3.4, 0.2), CF(-1.15, -1.2, 0.68) * ANG(R(6), 0, 0), G, METAL)
		mk(r, "UpperTorso", "block", V(0.14, 3.4, 0.2), CF(1.15, -1.2, 0.68) * ANG(R(6), 0, 0), G, METAL)
		-- uniforma
		mk(r, "UpperTorso", "block", V(0.8, 0.12, 0.1), CF(0, 0.75, -0.56), C(29, 74, 34), FABRIC)
		for _, x in ipairs({ -0.3, 0.3 }) do
			for _, y in ipairs({ 0.35, -0.05, -0.45 }) do
				mk(r, "UpperTorso", "ball", V(0.18, 0.18, 0.18), CF(x, y, -0.54), G, METAL)
			end
		end
		mk(r, "UpperTorso", "block", V(0.42, 2.3, 0.1), CF(0, 0.0, -0.58) * ANG(0, 0, R(-38)), RED, FABRIC) -- šerpa
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
		-- důstojnická čepice
		mk(r, "Head", "block", V(1.5, 0.75, 1.5), CF(0, 0.62, 0.02), C(47, 106, 49), FABRIC)
		mk(r, "Head", "block", V(1.6, 0.2, 1.6), CF(0, 0.38, 0.0), G, METAL)
		mk(r, "Head", "block", V(1.3, 0.1, 0.65), CF(0, 0.3, -0.9) * ANG(R(-8), 0, 0), C(14, 14, 14), PLASTIC)
		mk(r, "Head", "cyl", V(0.1, 0.4, 0.4), CF(0, 0.75, -0.78) * ANG(0, R(90), 0), GD, METAL)
		mk(r, "Head", "ball", V(0.18, 0.18, 0.1), CF(0, 0.75, -0.84), RED, NEON)
		sword(r, C(232, 237, 240), G, false)
	end }

LEVELS[9] = { name = "Legenda", torso = C(23, 167, 107), legs = C(20, 147, 93),
	build = function(r)
		local G = C(255, 216, 107)
		local GD = C(199, 154, 30)
		local E = C(43, 255, 168)
		-- zlatá helma s korunou
		mk(r, "Head", "ball", V(1.6, 1.2, 1.6), CF(0, 0.5, 0.04), G, METAL)
		mk(r, "Head", "block", V(0.3, 0.9, 1.5), CF(-0.68, 0.0, 0.04), G, METAL)
		mk(r, "Head", "block", V(0.3, 0.9, 1.5), CF(0.68, 0.0, 0.04), G, METAL)
		for i = -2, 2 do
			mk(r, "Head", "wedge", V(0.28, 0.85 - math.abs(i) * 0.15, 0.35), CF(i * 0.3, 1.2, 0.0) * ANG(0, R(180), 0), G, METAL)
		end
		mk(r, "Head", "ball", V(0.2, 0.2, 0.2), CF(0, 0.82, -0.66), E, NEON, { light = E, range = 12 })
		-- svatozář
		for i = 0, 17 do
			local a = i / 18 * math.pi * 2
			mk(r, "Head", "block", V(0.4, 0.1, 0.2), CF(math.cos(a) * 1.15, 2.35, math.sin(a) * 1.15) * ANG(0, -a, 0), G, NEON,
				i == 0 and { light = G, range = 16, bright = 3 } or nil)
		end
		-- zlatá výzbroj
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
		-- světelná křídla
		for _, s in ipairs({ -1, 1 }) do
			for i = 1, 6 do
				local phi = R(-55 + i * 22)
				local L = 2.2 + math.sin(i * 0.55) * 1.7
				mk(r, "UpperTorso", "block", V(L, 0.1, 0.5),
					CF(s * (0.8 + math.cos(phi) * L / 2), 0.4 + math.sin(phi) * L / 2, 0.75 + i * 0.05) * ANG(0, 0, s * phi),
					i % 2 == 0 and C(255, 255, 255) or E, NEON,
					(i == 3) and { light = E, range = 14, bright = 2 } or nil)
			end
		end
		-- energetický meč
		mk(r, "RightHand", "block", V(0.28, 0.28, 0.9), CF(0, -0.15, 0.1), GD, METAL)
		mk(r, "RightHand", "block", V(1.1, 0.24, 0.28), CF(0, -0.15, -0.4), G, METAL)
		mk(r, "RightHand", "block", V(0.5, 0.5, 6.2), CF(0, -0.15, -3.7), E, NEON, { light = E, range = 20, bright = 4 }).Transparency = 0.55
		mk(r, "RightHand", "block", V(0.16, 0.36, 6.0), CF(0, -0.15, -3.6), C(255, 255, 255), NEON)
		-- plovoucí krystaly
		local shards = { { -3.2, 2.2, 0.5 }, { 3.4, 3.0, -0.4 }, { -3.0, -0.6, -0.7 }, { 3.2, -0.2, 0.6 }, { -2.2, 4.2, 0.0 }, { 2.4, 4.6, 0.3 } }
		for _, p in ipairs(shards) do
			mk(r, "UpperTorso", "block", V(0.45, 0.45, 0.45), CF(p[1], p[2], p[3]) * ANG(R(45), 0, R(45)), E, NEON, { light = E, range = 8 })
		end
		-- aura jiskřiček
		mk(r, "UpperTorso", "ball", V(0.4, 0.4, 0.4), CF(0, 0, 0), G, NEON, { sparkle = G, rate = 40 }).Transparency = 1
	end }

--------------------------------------------------------------------
-- Sestavení rigu
--------------------------------------------------------------------
local folder = Workspace:FindFirstChild("SoldierMerge_R15") or Instance.new("Folder")
folder.Name = "SoldierMerge_R15"
folder.Parent = Workspace
folder:ClearAllChildren()

for i, def in ipairs(LEVELS) do
	local desc = Instance.new("HumanoidDescription")
	desc.HeadColor = SKIN
	desc.TorsoColor = def.torso
	desc.LeftArmColor = def.torso
	desc.RightArmColor = def.torso
	desc.LeftLegColor = def.legs
	desc.RightLegColor = def.legs

	local rig = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	rig.Name = string.format("Soldier_Lv%d_%s", i, def.name)
	rig.Parent = folder
	rig:PivotTo(CF((i - 1) * 8, 4, 0))
	rig:SetAttribute("MergeLevel", i)

	local hum = rig:FindFirstChildOfClass("Humanoid")
	if hum then hum.DisplayName = string.format("Lv.%d %s", i, def.name) end

	local ok, err = pcall(def.build, rig)
	if not ok then warn("Level " .. i .. " build error: " .. tostring(err)) end

	local root = rig:FindFirstChild("HumanoidRootPart")
	if root then root.Anchored = true end -- model stojí na místě; pro hru anchor zruš
end

print("Hotovo: 9 R15 vojáků ve složce Workspace/SoldierMerge_R15")
