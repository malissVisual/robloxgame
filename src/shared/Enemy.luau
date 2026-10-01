--!strict
-- 3D enemy models: the 13 designed goblins of the sheet "Roblox R15 — Goblin NPC" (5 standard goblins, 3 minibosses,
-- 5 bosses; which kind uses which is in Enemies.luau). An enemy is an R15 character (a stocky rig made once by
-- Players:CreateHumanoidModelFromDescription and cloned), painted in its skin color, with goblin ears, nose, eyes
-- and fangs, and the design's clothes, armor and weapon welded on the right body parts, and it plays animations
-- (idle, run, attack, cast, death; see Rig.luau). If the rig cannot be made (server only, needs the
-- Roblox assets), the old model assembled from blocks is used. `Enemy.lift` is the distance from the pivot down
-- to the ground, and the enemy faces -Z. The label and HP bar are named like the soldier's, so the battle code
-- (Soldier.showBar / Soldier.setHp) works on enemies too.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enemies = require(Shared.Config.Enemies)
local Levels = require(Shared.Config.Levels)
local Rig = require(Shared.Rig)

local C = Color3.fromRGB
local WOOD = C(120, 85, 50)
local DARK_WOOD = C(80, 55, 35)
local BONE = C(235, 228, 205)
local STEEL = C(185, 190, 200)
local CLOTH = C(105, 70, 40)
local YELLOW = C(255, 220, 60)

local Enemy = {}

function Enemy.scale(kind: string, level: number): number
	return Enemies.Kinds[kind].size * (0.85 + 0.05 * (math.min(level, 9) - 1))
end

-- ── The R15 base rig (made once, then cloned) ──
local RIG_SCALE = 0.9 -- an R15 character is a bit taller than the old block goblin
local baseRig: Model? = nil
local baseLift = 3 -- pivot (HumanoidRootPart) down to the soles, at scale 1
local baseState = "none" -- none | loading | ready | failed

local function getBase(): Model?
	if baseState == "none" then
		baseState = "loading"
		local ok, result = pcall(function()
			local description = Instance.new("HumanoidDescription")
			-- A goblin: a big head on a short, stocky body.
			description.HeadScale = 1.35
			description.HeightScale = 0.92
			description.WidthScale = 1.15
			description.DepthScale = 1.1
			return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
		end)
		local rig = if ok then result :: Model else nil
		local root = rig and rig:FindFirstChild("HumanoidRootPart") :: BasePart?
		local foot = rig and rig:FindFirstChild("LeftFoot") :: BasePart?
		if rig and root and foot and rig:FindFirstChild("Head") and rig:FindFirstChild("RightHand") and rig:FindFirstChildOfClass("Humanoid") then
			for _, item in rig:GetDescendants() do
				if item:IsA("LuaSourceContainer") or item:IsA("BodyColors") or item:IsA("Decal") or item:IsA("Accessory") or item:IsA("Clothing") then
					item:Destroy()
				end
			end
			baseLift = root.Position.Y - (foot.Position.Y - foot.Size.Y / 2)
			rig.PrimaryPart = root
			baseRig = rig
			baseState = "ready"
		else
			warn("[Enemy] the R15 rig could not be made, block models are used:", if ok then "parts missing" else result)
			baseState = "failed"
		end
	end
	while baseState == "loading" do
		task.wait()
	end
	return baseRig
end

function Enemy.lift(kind: string, level: number): number
	if getBase() then
		return baseLift * RIG_SCALE * Enemy.scale(kind, level)
	end
	return 2.4 * Enemy.scale(kind, level)
end

local function buildBlocks(kind: string, level: number): Model
	local def = Enemies.Kinds[kind]
	-- The block fallback knows only the five old shapes: pick one by the archetype.
	local look = ({ Grunt = "Goblin", Archer = "GoblinArcher", Brute = "GoblinBrute", Shaman = "GoblinShaman", Chief = "GoblinChief" })[def.archetype] or "Goblin"
	local s = Enemy.scale(kind, level)
	-- A higher level darkens the skin a little toward its level color.
	local skin = def.color:Lerp(Levels.color(level), 0.1 * math.min(level - 1, 4) / 4 + (if level >= 5 then 0.05 else 0))

	local model = Instance.new("Model")
	model.Name = def.label

	local function add(name: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * s
		p.CFrame = CFrame.new(offset * s)
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Anchored = true
		p.CanCollide = false
		p.Parent = model
		return p
	end
	local function tilt(part: Part, x: number, y: number, z: number)
		part.CFrame = part.CFrame * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	end

	-- Body: a hunched green goblin with a loincloth, a big head, long ears and a pointy nose.
	local body = add("Body", Vector3.new(1.6, 1.8, 0.9), Vector3.zero, skin)
	model.PrimaryPart = body
	add("LegL", Vector3.new(0.5, 1.4, 0.5), Vector3.new(-0.4, -1.7, 0), skin:Lerp(Color3.new(0, 0, 0), 0.15))
	add("LegR", Vector3.new(0.5, 1.4, 0.5), Vector3.new(0.4, -1.7, 0), skin:Lerp(Color3.new(0, 0, 0), 0.15))
	add("ArmL", Vector3.new(0.45, 1.5, 0.45), Vector3.new(-1.05, 0.1, 0), skin)
	add("ArmR", Vector3.new(0.45, 1.5, 0.45), Vector3.new(1.05, 0.1, 0), skin)
	add("Loincloth", Vector3.new(1.7, 0.7, 1.0), Vector3.new(0, -0.75, 0), CLOTH)
	local head = add("Head", Vector3.new(1.6, 1.3, 1.4), Vector3.new(0, 1.55, 0), skin)
	tilt(add("EarL", Vector3.new(0.9, 0.25, 0.15), Vector3.new(-1.2, 1.75, 0), skin), 0, 0, 22)
	tilt(add("EarR", Vector3.new(0.9, 0.25, 0.15), Vector3.new(1.2, 1.75, 0), skin), 0, 0, -22)
	add("Nose", Vector3.new(0.25, 0.4, 0.55), Vector3.new(0, 1.45, -0.95), skin:Lerp(Color3.new(0, 0, 0), 0.2))
	add("EyeL", Vector3.new(0.3, 0.22, 0.1), Vector3.new(-0.4, 1.78, -0.72), YELLOW, nil, Enum.Material.Neon)
	add("EyeR", Vector3.new(0.3, 0.22, 0.1), Vector3.new(0.4, 1.78, -0.72), YELLOW, nil, Enum.Material.Neon)
	add("FangL", Vector3.new(0.12, 0.22, 0.08), Vector3.new(-0.25, 1.15, -0.72), BONE)
	add("FangR", Vector3.new(0.12, 0.22, 0.08), Vector3.new(0.25, 1.15, -0.72), BONE)

	local topOffset = 2.3
	if look == "Goblin" then
		add("ClubHandle", Vector3.new(0.25, 1.9, 0.25), Vector3.new(1.1, 0.4, -0.8), WOOD)
		add("ClubHead", Vector3.new(0.6, 0.7, 0.6), Vector3.new(1.1, 1.5, -0.8), DARK_WOOD)
	elseif look == "GoblinArcher" then
		add("Hood", Vector3.new(1.75, 0.5, 1.55), Vector3.new(0, 2.15, 0), CLOTH)
		add("Bow", Vector3.new(0.15, 2.3, 0.3), Vector3.new(1.25, 0.3, -0.7), WOOD)
		add("Quiver", Vector3.new(0.4, 1.2, 0.4), Vector3.new(0.3, 0.4, 0.65), DARK_WOOD)
	elseif look == "GoblinBrute" then
		add("BoneHelm", Vector3.new(1.8, 0.6, 1.55), Vector3.new(0, 2.15, 0), BONE)
		add("HornL", Vector3.new(0.25, 0.8, 0.25), Vector3.new(-0.75, 2.6, 0), BONE)
		add("HornR", Vector3.new(0.25, 0.8, 0.25), Vector3.new(0.75, 2.6, 0), BONE)
		add("ClubHandle", Vector3.new(0.35, 2.5, 0.35), Vector3.new(1.2, 0.5, -0.85), WOOD)
		add("ClubHead", Vector3.new(0.95, 0.95, 0.95), Vector3.new(1.2, 1.9, -0.85), DARK_WOOD)
		for _, offset in { Vector3.new(0.55, 0, 0), Vector3.new(-0.55, 0, 0), Vector3.new(0, 0.55, 0) } do
			add("Spike", Vector3.new(0.3, 0.3, 0.3), Vector3.new(1.2, 1.9, -0.85) + offset, STEEL, nil, Enum.Material.Metal)
		end
		topOffset = 3.0
	elseif look == "GoblinShaman" then
		add("Robe", Vector3.new(1.9, 1.5, 1.1), Vector3.new(0, -0.25, 0), C(110, 70, 150))
		for i, x in { -0.5, 0, 0.5 } do
			add("Feather" .. i, Vector3.new(0.18, 0.9, 0.18), Vector3.new(x, 2.5, 0), C(255, 120 + i * 40, 60))
		end
		add("Staff", Vector3.new(0.2, 3.1, 0.2), Vector3.new(1.25, 0.6, -0.7), WOOD)
		add("Orb", Vector3.new(0.75, 0.75, 0.75), Vector3.new(1.25, 2.3, -0.7), C(120, 255, 110), Enum.PartType.Ball, Enum.Material.Neon)
		topOffset = 3.1
	elseif look == "GoblinChief" then
		add("Crown", Vector3.new(1.5, 0.3, 1.4), Vector3.new(0, 2.3, 0), C(230, 180, 40), nil, Enum.Material.Metal)
		for _, x in { -0.6, -0.3, 0, 0.3, 0.6 } do
			add("CrownSpike", Vector3.new(0.18, 0.45, 0.18), Vector3.new(x, 2.7, 0), C(230, 180, 40), nil, Enum.Material.Metal)
		end
		add("Cape", Vector3.new(1.8, 2.6, 0.12), Vector3.new(0, 0, 0.55), C(160, 30, 30))
		add("AxeHandle", Vector3.new(0.3, 2.7, 0.3), Vector3.new(1.2, 0.6, -0.85), WOOD)
		add("AxeBlade", Vector3.new(0.2, 1.3, 1.1), Vector3.new(1.2, 1.9, -1.15), STEEL, nil, Enum.Material.Metal)
		add("WarPaintL", Vector3.new(0.15, 0.5, 0.08), Vector3.new(-0.55, 1.5, -0.72), C(180, 30, 30))
		add("WarPaintR", Vector3.new(0.15, 0.5, 0.08), Vector3.new(0.55, 1.5, -0.72), C(180, 30, 30))
		topOffset = 3.4
	end

	-- Gear that grows with the enemy level.
	if level >= 3 then
		add("SpikeL", Vector3.new(0.3, 0.6, 0.3), Vector3.new(-1.05, 1.0, 0), BONE)
		add("SpikeR", Vector3.new(0.3, 0.6, 0.3), Vector3.new(1.05, 1.0, 0), BONE)
	end
	if level >= 5 then
		add("Belt", Vector3.new(1.75, 0.25, 0.95), Vector3.new(0, -0.35, 0), STEEL, nil, Enum.Material.Metal)
	end
	if level >= 7 then
		add("Aura", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, 0.2, 0.7), Levels.color(level), Enum.PartType.Ball, Enum.Material.Neon)
	end

	-- Name + level label and a hidden HP bar (Soldier.showBar / Soldier.setHp find "Back" and "Bar").
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(190, 30)
	gui.StudsOffset = Vector3.new(0, topOffset * s, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 40 -- near only (Soldier.showBar widens it for a battle)
	gui.Adornee = head
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = C(255, 230, 120)
	label.TextStrokeTransparency = 0.3
	label.Text = string.format("%s · %s", def.label, Levels.label(level))
	label.Parent = gui

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Position = UDim2.fromOffset(0, 22)
	back.Size = UDim2.new(1, 0, 0, 7)
	back.BackgroundColor3 = C(35, 35, 35)
	back.BorderSizePixel = 0
	back.Visible = false
	back.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = C(230, 70, 70)
	bar.Parent = back

	model:PivotTo(CFrame.new(0, Enemy.lift(kind, level), 0))
	return model
end

-- ── The R15 enemy ──
function Enemy.build(kind: string, level: number): Model
	local base = getBase()
	if not base then
		return buildBlocks(kind, level)
	end
	local def = Enemies.Kinds[kind]
	local look = def.look
	local s = Enemy.scale(kind, level) * RIG_SCALE
	local skin = def.color:Lerp(Levels.color(level), 0.1 * math.min(level - 1, 4) / 4 + (if level >= 5 then 0.05 else 0))
	local dark = skin:Lerp(Color3.new(0, 0, 0), 0.18)

	local model = base:Clone()
	model.Name = def.label
	model:ScaleTo(s)
	local root = model.PrimaryPart :: BasePart
	root.Anchored = true -- the battle moves the model (PivotTo); the limbs follow and are animated

	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.EvaluateStateMachine = false
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	if not humanoid:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = humanoid
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.Massless = true
			if part ~= root then
				part.Color = if string.find(part.Name, "Leg") or string.find(part.Name, "Foot") then dark else skin
				part.Material = Enum.Material.SmoothPlastic
			end
		end
	end

	-- A part welded on a limb: `offset` in the limb's space (studs at scale 1), `angles` in degrees.
	local function attach(limb: BasePart, name: string, size: Vector3, offset: Vector3, color: Color3, shape: Enum.PartType?, material: Enum.Material?, angles: Vector3?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size * s
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		local turn = if angles then CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z)) else CFrame.identity
		p.CFrame = limb.CFrame * CFrame.new(offset * s) * turn
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = limb
		weld.Part1 = p
		weld.Parent = p
		p.Parent = model
		return p
	end
	local function limb(name: string): BasePart
		return model:FindFirstChild(name) :: BasePart
	end

	local head = limb("Head")
	local upper, lower = limb("UpperTorso"), limb("LowerTorso")
	local hand = limb("RightHand")
	-- The head's half sizes at scale 1 (the head has its own scale).
	local hx, hy, hz = head.Size.X / 2 / s, head.Size.Y / 2 / s, head.Size.Z / 2 / s

	-- The goblin face: long ears, a pointy nose, glowing eyes, fangs.
	attach(head, "EarL", Vector3.new(0.9, 0.3, 0.15), Vector3.new(-hx - 0.3, 0.15, 0), skin, nil, nil, Vector3.new(0, 0, 22))
	attach(head, "EarR", Vector3.new(0.9, 0.3, 0.15), Vector3.new(hx + 0.3, 0.15, 0), skin, nil, nil, Vector3.new(0, 0, -22))
	attach(head, "Nose", Vector3.new(0.22, 0.32, 0.5), Vector3.new(0, -0.08, -hz - 0.15), dark)
	attach(head, "EyeL", Vector3.new(0.28, 0.2, 0.1), Vector3.new(-hx * 0.45, 0.2, -hz + 0.02), YELLOW, nil, Enum.Material.Neon, Vector3.new(0, 0, -12))
	attach(head, "EyeR", Vector3.new(0.28, 0.2, 0.1), Vector3.new(hx * 0.45, 0.2, -hz + 0.02), YELLOW, nil, Enum.Material.Neon, Vector3.new(0, 0, 12))
	attach(head, "FangL", Vector3.new(0.1, 0.2, 0.08), Vector3.new(-0.2, -hy * 0.55, -hz + 0.02), BONE)
	attach(head, "FangR", Vector3.new(0.1, 0.2, 0.08), Vector3.new(0.2, -hy * 0.55, -hz + 0.02), BONE)
	-- A box around a body part (its size at scale 1 plus `grow`, and always a bit thicker than the part so it
	-- reads as a piece of clothing or armor), for clothes, armor and hoods.
	local function cover(part: BasePart, name: string, grow: Vector3, offset: Vector3, color: Color3, material: Enum.Material?): Part
		-- (the layer stays thin: the body part itself is painted in the outfit's color, see paint; a thick box
		-- around every limb made the goblins look like stacks of crates)
		return attach(part, name, part.Size / s + grow * 0.6 + Vector3.new(0.08, 0, 0.08), offset, color, nil, material)
	end
	-- The outfit: the body parts themselves take the clothes' colors (torso, arms, legs, feet); the head and the
	-- hands keep the skin. Without this every goblin is a green body with a thing on its head.
	local function paint(torsoColor: Color3, armColor: Color3, legColor: Color3, footColor: Color3)
		for _, item in model:GetChildren() do
			if item:IsA("BasePart") then
				local n = item.Name
				if n == "UpperTorso" or n == "LowerTorso" then
					item.Color = torsoColor
				elseif n == "LeftUpperArm" or n == "RightUpperArm" or n == "LeftLowerArm" or n == "RightLowerArm" then
					item.Color = armColor
				elseif n == "LeftFoot" or n == "RightFoot" then
					item.Color = footColor
				elseif string.find(n, "Leg") then
					item.Color = legColor
				end
			end
		end
	end
	local leftHand = limb("LeftHand")
	local leftArm = limb("LeftUpperArm")
	local rightArm = limb("RightUpperArm")
	local leftLeg, rightLeg = limb("LeftUpperLeg"), limb("RightUpperLeg")
	local leftShin, rightShin = limb("LeftLowerLeg"), limb("RightLowerLeg")
	local leftFoot, rightFoot = limb("LeftFoot"), limb("RightFoot")
	local METAL = Enum.Material.Metal
	local NEON = Enum.Material.Neon
	local LEATHER = C(120, 80, 45)
	local DARK_LEATHER = C(80, 52, 30)
	local IRON = C(120, 125, 135)
	local DARK_IRON = C(70, 74, 84)
	local GOLD = C(230, 185, 50)
	local RED = C(170, 40, 40)
	local PURPLE = C(95, 50, 150)
	local DARK_PURPLE = C(55, 30, 90)
	local CREAM = C(238, 232, 215)
	local FOREST = C(45, 85, 50)
	local DARK_GREEN = C(32, 60, 38)
	local TEAL = C(45, 110, 120)
	local POISON = C(130, 255, 60)
	local VIOLET_GLOW = C(190, 110, 255)
	local CYAN_GLOW = C(90, 220, 255)
	local EMBER = C(255, 140, 40)
	local ux, uy, uz = upper.Size.X / 2 / s, upper.Size.Y / 2 / s, upper.Size.Z / 2 / s
	local lx, lz = lower.Size.X / 2 / s, lower.Size.Z / 2 / s

	-- Pieces several designs share.
	-- Headwear that leaves the FACE OPEN (a box around the whole head hid the face and the ears): a cap on top, a
	-- panel behind the head and one on each side.
	local function headwear(name: string, color: Color3, material: Enum.Material?, capHeight: number?)
		attach(head, name .. "Top", Vector3.new(hx * 2 + 0.3, capHeight or 0.35, hz * 2 + 0.3), Vector3.new(0, hy + 0.08, 0.02), color, nil, material)
		attach(head, name .. "Back", Vector3.new(hx * 2 + 0.3, hy * 2 + 0.1, 0.26), Vector3.new(0, -0.02, hz + 0.13), color, nil, material)
		attach(head, name .. "L", Vector3.new(0.26, hy * 2 + 0.1, hz * 2 + 0.1), Vector3.new(-(hx + 0.13), -0.02, 0.05), color, nil, material)
		attach(head, name .. "R", Vector3.new(0.26, hy * 2 + 0.1, hz * 2 + 0.1), Vector3.new(hx + 0.13, -0.02, 0.05), color, nil, material)
	end
	local function hood(color: Color3, tall: number?) -- a hood: open in front, a flap down the back
		headwear("Hood", color, nil, tall or 0.35)
		attach(head, "HoodBack", Vector3.new(hx * 2 + 0.1, hy * 1.4, 0.3), Vector3.new(0, -hy * 0.25, hz + 0.3), color)
	end
	local function pointedHat(color: Color3, brim: Color3)
		attach(head, "HatBrim", Vector3.new(hx * 2 + 0.9, 0.12, hz * 2 + 0.9), Vector3.new(0, hy + 0.02, 0), brim)
		attach(head, "HatCone1", Vector3.new(hx * 1.6, 0.6, hz * 1.6), Vector3.new(0, hy + 0.35, 0), color)
		attach(head, "HatCone2", Vector3.new(hx * 1.1, 0.6, hz * 1.1), Vector3.new(0.05, hy + 0.9, -0.03), color, nil, nil, Vector3.new(0, 0, 8))
		attach(head, "HatCone3", Vector3.new(hx * 0.6, 0.6, hz * 0.6), Vector3.new(0.14, hy + 1.4, -0.05), color, nil, nil, Vector3.new(0, 0, 16))
	end
	local function belt(color: Color3, buckle: Color3?)
		attach(lower, "Belt", Vector3.new(lx * 2 + 0.2, 0.22, lz * 2 + 0.2), Vector3.new(0, 0.1, 0), color)
		if buckle then
			attach(lower, "Buckle", Vector3.new(0.3, 0.3, 0.08), Vector3.new(0, 0.1, -lz - 0.14), buckle, nil, METAL)
		end
	end
	local function robe(color: Color3, trim: Color3, skirtDrop: number)
		cover(upper, "Robe", Vector3.new(0.14, 0.1, 0.14), Vector3.zero, color)
		attach(lower, "RobeSkirt", Vector3.new(lx * 2 + 0.25, skirtDrop, lz * 2 + 0.25), Vector3.new(0, -skirtDrop / 2 + 0.1, 0), color)
		attach(upper, "RobeTrim", Vector3.new(0.3, uy * 2 + 0.1, 0.06), Vector3.new(0, 0, -uz - 0.1), trim)
		belt(trim)
	end
	local function staff(crystal: Color3, size: number?) -- in the right hand, along -Z (held up)
		attach(hand, "Staff", Vector3.new(0.2, 0.2, 3.4), Vector3.new(0, -0.1, -0.9), WOOD)
		local k = size or 0.55
		attach(hand, "Crystal", Vector3.new(k, k * 1.6, k), Vector3.new(0, -0.1, -2.75), crystal, nil, NEON, Vector3.new(90, 45, 0))
	end
	local function shield(face: Color3, emblem: Color3, emblemName: string) -- on the left forearm
		local forearm = limb("LeftLowerArm")
		attach(forearm, "Shield", Vector3.new(0.18, 1.6, 1.3), Vector3.new(-0.5, 0, -0.1), face, nil, METAL)
		attach(forearm, "ShieldRim", Vector3.new(0.12, 1.75, 1.45), Vector3.new(-0.46, 0, -0.1), IRON, nil, METAL)
		attach(forearm, emblemName, Vector3.new(0.1, 0.7, 0.45), Vector3.new(-0.6, 0.05, -0.1), emblem)
	end
	local function pauldrons(color: Color3, material: Enum.Material?, spikes: boolean?)
		for _, arm in { leftArm, rightArm } do
			local ay = arm.Size.Y / 2 / s
			attach(arm, "Pauldron", Vector3.new(arm.Size.X / s + 0.55, 0.6, arm.Size.Z / s + 0.55), Vector3.new(0, ay - 0.05, 0), color, nil, material)
			if spikes then
				attach(arm, "PauldronSpike", Vector3.new(0.22, 0.6, 0.22), Vector3.new(0, ay + 0.35, 0), STEEL, nil, METAL)
			end
		end
	end
	local function boots(color: Color3)
		cover(leftFoot, "Boot", Vector3.new(0.14, 0.14, 0.14), Vector3.zero, color)
		cover(rightFoot, "Boot", Vector3.new(0.14, 0.14, 0.14), Vector3.zero, color)
	end
	local function legWear(color: Color3)
		for _, part in { leftLeg, rightLeg, leftShin, rightShin } do
			cover(part, "LegWear", Vector3.new(0.1, 0.02, 0.1), Vector3.zero, color)
		end
	end
	local function vial(part: BasePart, name: string, offset: Vector3, glow: Color3)
		attach(part, name, Vector3.new(0.22, 0.34, 0.22), offset, glow, nil, NEON)
		attach(part, name .. "Cap", Vector3.new(0.14, 0.1, 0.14), offset + Vector3.new(0, 0.22, 0), DARK_WOOD)
	end

	-- The weapon lies along the hand's -Z (the "hold" animation raises the forearm, so it points up).
	local topOffset = hy + 0.9
	local attack = "slash"
	if look == "Prcek" then
		-- The small scout: a brown hood, a leather vest with a belt, a short dagger.
		paint(DARK_LEATHER, skin, LEATHER, DARK_LEATHER)
		hood(LEATHER)
		cover(upper, "Vest", Vector3.new(0.12, -0.2, 0.12), Vector3.new(0, -0.05, 0), DARK_LEATHER)
		belt(DARK_LEATHER, IRON)
		attach(hand, "DaggerGrip", Vector3.new(0.16, 0.16, 0.5), Vector3.new(0, -0.1, -0.2), DARK_WOOD)
		attach(hand, "DaggerGuard", Vector3.new(0.45, 0.12, 0.12), Vector3.new(0, -0.1, -0.5), IRON, nil, METAL)
		attach(hand, "DaggerBlade", Vector3.new(0.14, 0.42, 1.3), Vector3.new(0, -0.1, -1.2), STEEL, nil, METAL)
		topOffset = hy + 1.0
	elseif look == "Rubac" then
		-- The warrior: grey plate, pauldrons, a sword and a red shield with a white bolt.
		paint(IRON, IRON, DARK_IRON, DARK_IRON)
		cover(upper, "ChestPlate", Vector3.new(0.2, 0.05, 0.2), Vector3.zero, IRON, METAL)
		attach(upper, "ChestLine", Vector3.new(0.12, uy * 2 - 0.3, 0.06), Vector3.new(0, 0, -uz - 0.13), DARK_IRON, nil, METAL)
		pauldrons(IRON, METAL)
		legWear(DARK_IRON)
		boots(DARK_IRON)
		belt(DARK_LEATHER, GOLD)
		shield(RED, CREAM, "Bolt")
		attach(hand, "SwordGrip", Vector3.new(0.18, 0.18, 0.6), Vector3.new(0, -0.1, -0.25), DARK_WOOD)
		attach(hand, "SwordGuard", Vector3.new(0.7, 0.14, 0.14), Vector3.new(0, -0.1, -0.6), IRON, nil, METAL)
		attach(hand, "SwordBlade", Vector3.new(0.14, 0.4, 1.9), Vector3.new(0, -0.1, -1.6), STEEL, nil, METAL)
		topOffset = hy + 1.1
	elseif look == "Lucistnik" then
		-- The archer: a dark green hood and tunic, a bow and a quiver of red-fletched arrows.
		attack = "lunge"
		paint(FOREST, FOREST, DARK_GREEN, DARK_LEATHER)
		hood(FOREST)
		cover(upper, "Tunic", Vector3.new(0.12, 0.06, 0.12), Vector3.zero, FOREST)
		belt(DARK_LEATHER, IRON)
		legWear(DARK_GREEN)
		boots(DARK_LEATHER)
		attach(hand, "Bow", Vector3.new(0.15, 0.3, 2.8), Vector3.new(0, -0.1, -0.5), WOOD)
		attach(hand, "BowString", Vector3.new(0.04, 0.04, 2.7), Vector3.new(0, 0.25, -0.5), BONE)
		attach(upper, "Quiver", Vector3.new(0.45, 1.4, 0.45), Vector3.new(0.35, 0.2, uz + 0.25), DARK_LEATHER, nil, nil, Vector3.new(0, 0, -18))
		for i, x in { -0.12, 0, 0.12 } do
			attach(upper, "Arrow" .. i, Vector3.new(0.08, 0.5, 0.08), Vector3.new(0.35 + x + (i - 2) * 0.1, 1.05, uz + 0.25), RED, nil, nil, Vector3.new(0, 0, -18))
		end
		topOffset = hy + 1.3
	elseif look == "Mag" then
		-- The mage: a purple robe with gold trim, a pointed hat, a staff with a purple crystal.
		attack = "cast"
		paint(PURPLE, PURPLE, DARK_PURPLE, DARK_PURPLE)
		robe(PURPLE, GOLD, 1.3)
		pointedHat(PURPLE, DARK_PURPLE)
		staff(VIOLET_GLOW)
		topOffset = hy + 2.1
	elseif look == "Lecitel" then
		-- The healer: a cream robe with green trim, a white hood, a staff with a green crystal, a pouch.
		attack = "cast"
		paint(CREAM, CREAM, CREAM, LEATHER)
		robe(CREAM, C(95, 150, 70), 1.3)
		hood(CREAM, 0.35)
		attach(lower, "Pouch", Vector3.new(0.4, 0.4, 0.3), Vector3.new(-lx - 0.1, -0.1, 0), LEATHER)
		staff(POISON)
		topOffset = hy + 1.4
	elseif look == "ZeleznyTesak" then
		-- Miniboss: dark red heavy armor with spiked steel pauldrons, a horned spiked helmet, a serrated cleaver and
		-- a red skull shield.
		paint(C(150, 40, 40), DARK_IRON, C(120, 35, 35), DARK_IRON)
		cover(upper, "ChestPlate", Vector3.new(0.3, 0.1, 0.3), Vector3.zero, C(150, 40, 40), METAL)
		attach(upper, "ChestStrap", Vector3.new(0.35, uy * 2, 0.08), Vector3.new(0, 0, -uz - 0.18), DARK_IRON, nil, METAL)
		pauldrons(DARK_IRON, METAL, true)
		legWear(C(120, 35, 35))
		boots(DARK_IRON)
		belt(DARK_IRON, IRON)
		headwear("Helm", DARK_IRON, METAL, 0.3)
		attach(head, "NoseGuard", Vector3.new(0.2, hy * 1.1, 0.12), Vector3.new(0, -0.05, -hz - 0.08), DARK_IRON, nil, METAL)
		for _, x in { -0.5, 0, 0.5 } do
			attach(head, "HelmSpike", Vector3.new(0.2, 0.6, 0.2), Vector3.new(x * hx, hy + 0.4, 0), STEEL, nil, METAL, Vector3.new(0, 0, -x * 25))
		end
		attach(head, "HornL", Vector3.new(0.25, 0.9, 0.25), Vector3.new(-hx - 0.1, hy, 0), STEEL, nil, METAL, Vector3.new(0, 0, 35))
		attach(head, "HornR", Vector3.new(0.25, 0.9, 0.25), Vector3.new(hx + 0.1, hy, 0), STEEL, nil, METAL, Vector3.new(0, 0, -35))
		shield(RED, CREAM, "Skull")
		attach(hand, "CleaverGrip", Vector3.new(0.2, 0.2, 0.8), Vector3.new(0, -0.1, -0.3), DARK_WOOD)
		attach(hand, "CleaverBlade", Vector3.new(0.16, 1.0, 2.2), Vector3.new(0, -0.45, -1.9), STEEL, nil, METAL)
		for i = 0, 3 do
			attach(hand, "CleaverTooth", Vector3.new(0.16, 0.3, 0.3), Vector3.new(0, -1.0, -1.1 - i * 0.5), STEEL, nil, METAL, Vector3.new(45, 0, 0))
		end
		topOffset = hy + 1.8
	elseif look == "JedovyStopar" then
		-- Miniboss: a dark green hooded cloak, a crossbow and glowing poison vials on the belt.
		attack = "lunge"
		paint(DARK_GREEN, DARK_GREEN, DARK_GREEN, DARK_LEATHER)
		hood(DARK_GREEN, 0.35)
		cover(upper, "Cloak", Vector3.new(0.2, 0.1, 0.2), Vector3.zero, DARK_GREEN)
		attach(upper, "CloakBack", Vector3.new(ux * 2 + 0.1, 2.4, 0.12), Vector3.new(0, -0.8, uz + 0.1), DARK_GREEN, nil, nil, Vector3.new(-6, 0, 0))
		belt(DARK_LEATHER, IRON)
		legWear(DARK_GREEN)
		boots(DARK_LEATHER)
		for i, x in { -0.45, -0.15, 0.15 } do
			vial(lower, "Vial" .. i, Vector3.new(x, -0.35, -lz - 0.15), POISON)
		end
		attach(hand, "CrossbowStock", Vector3.new(0.22, 0.3, 2.2), Vector3.new(0, -0.1, -0.9), DARK_WOOD)
		attach(hand, "CrossbowBow", Vector3.new(2.0, 0.12, 0.2), Vector3.new(0, 0, -1.8), WOOD)
		attach(hand, "CrossbowString", Vector3.new(1.9, 0.04, 0.04), Vector3.new(0, 0, -1.55), BONE)
		attach(hand, "CrossbowBolt", Vector3.new(0.08, 0.08, 1.2), Vector3.new(0, 0.12, -1.3), STEEL, nil, METAL)
		attach(upper, "Quiver", Vector3.new(0.45, 1.3, 0.45), Vector3.new(0.4, 0.2, uz + 0.25), DARK_LEATHER, nil, nil, Vector3.new(0, 0, -18))
		topOffset = hy + 1.4
	elseif look == "RunovySaman" then
		-- Miniboss: a skull headdress with antlers, a teal tunic, a bone necklace, a skull staff and glowing runes.
		attack = "cast"
		paint(TEAL, skin, TEAL, DARK_LEATHER)
		cover(upper, "Tunic", Vector3.new(0.14, 0.08, 0.14), Vector3.zero, TEAL)
		attach(lower, "TunicSkirt", Vector3.new(lx * 2 + 0.2, 0.9, lz * 2 + 0.2), Vector3.new(0, -0.35, 0), TEAL)
		belt(DARK_LEATHER, BONE)
		for i, x in { -0.45, -0.25, 0, 0.25, 0.45 } do
			attach(upper, "Tooth" .. i, Vector3.new(0.1, 0.3, 0.1), Vector3.new(x, uy - 0.35 - math.abs(x) * 0.3, -uz - 0.1), BONE)
		end
		attach(head, "SkullCap", Vector3.new(hx * 2 + 0.3, hy + 0.2, hz * 2 + 0.2), Vector3.new(0, hy * 0.6, -0.05), BONE)
		attach(head, "SkullEyeL", Vector3.new(0.3, 0.3, 0.1), Vector3.new(-hx * 0.4, hy * 0.9, -hz - 0.1), C(40, 40, 40))
		attach(head, "SkullEyeR", Vector3.new(0.3, 0.3, 0.1), Vector3.new(hx * 0.4, hy * 0.9, -hz - 0.1), C(40, 40, 40))
		for _, side in { -1, 1 } do
			attach(head, "Antler", Vector3.new(0.2, 1.3, 0.2), Vector3.new(side * (hx + 0.1), hy + 0.7, 0), BONE, nil, nil, Vector3.new(0, 0, -side * 28))
			attach(head, "AntlerTine", Vector3.new(0.16, 0.6, 0.16), Vector3.new(side * (hx + 0.45), hy + 1.25, 0), BONE, nil, nil, Vector3.new(0, 0, side * 20))
		end
		attach(hand, "Staff", Vector3.new(0.2, 0.2, 3.2), Vector3.new(0, -0.1, -0.9), WOOD)
		attach(hand, "StaffSkull", Vector3.new(0.6, 0.6, 0.6), Vector3.new(0, -0.1, -2.7), BONE)
		for i, offset in { Vector3.new(0.5, 0.3, -2.4), Vector3.new(-0.5, 0.2, -2.9), Vector3.new(0.3, -0.5, -3.1) } do
			attach(hand, "Rune" .. i, Vector3.new(0.22, 0.22, 0.22), offset, CYAN_GLOW, nil, NEON, Vector3.new(30 * i, 45, 0))
		end
		topOffset = hy + 2.3
	elseif look == "KralGrubnak" then
		-- Boss: a gold crown with a red gem, black armor with gold trim, a red cape and a great double axe.
		local BLACK = C(45, 45, 52)
		paint(BLACK, BLACK, BLACK, C(35, 35, 40))
		cover(upper, "ChestPlate", Vector3.new(0.3, 0.1, 0.3), Vector3.zero, BLACK, METAL)
		attach(upper, "ChestTrim", Vector3.new(ux * 2 + 0.32, 0.18, 0.08), Vector3.new(0, uy - 0.2, -uz - 0.18), GOLD, nil, METAL)
		pauldrons(BLACK, METAL)
		attach(upper, "Cape", Vector3.new(ux * 2 + 0.3, 3.2, 0.14), Vector3.new(0, -1.0, uz + 0.12), RED, nil, nil, Vector3.new(-8, 0, 0))
		attach(upper, "CapeCollar", Vector3.new(ux * 2 + 0.5, 0.35, uz * 2 + 0.4), Vector3.new(0, uy, 0), RED)
		legWear(BLACK)
		boots(C(35, 35, 40))
		belt(C(35, 35, 40), GOLD)
		attach(head, "Crown", Vector3.new(hx * 2 + 0.1, 0.35, hz * 2 + 0.1), Vector3.new(0, hy + 0.1, 0), GOLD, nil, METAL)
		for _, x in { -0.6, -0.3, 0, 0.3, 0.6 } do
			attach(head, "CrownSpike", Vector3.new(0.18, 0.45, 0.18), Vector3.new(x * hx, hy + 0.5, -hz + 0.08), GOLD, nil, METAL)
		end
		attach(head, "CrownGem", Vector3.new(0.3, 0.3, 0.12), Vector3.new(0, hy + 0.25, -hz - 0.06), C(220, 40, 60), nil, NEON, Vector3.new(0, 0, 45))
		attach(hand, "AxeHandle", Vector3.new(0.28, 0.28, 3.4), Vector3.new(0, -0.1, -1.1), DARK_WOOD)
		attach(hand, "AxeBand", Vector3.new(0.34, 0.34, 0.5), Vector3.new(0, -0.1, -2.0), GOLD, nil, METAL)
		attach(hand, "AxeBladeL", Vector3.new(0.18, 1.5, 1.4), Vector3.new(-0.8, -0.1, -2.5), STEEL, nil, METAL)
		attach(hand, "AxeBladeR", Vector3.new(0.18, 1.5, 1.4), Vector3.new(0.8, -0.1, -2.5), STEEL, nil, METAL)
		topOffset = hy + 1.9
	elseif look == "KovarMorg" then
		-- Boss: a brown and iron smith with a glowing forge in his chest, an iron helmet and a huge ember hammer.
		local BROWN = C(110, 70, 40)
		paint(BROWN, skin, BROWN, DARK_IRON)
		cover(upper, "ChestPlate", Vector3.new(0.3, 0.1, 0.3), Vector3.zero, BROWN, METAL)
		attach(upper, "ForgeGlow", Vector3.new(1.0, 0.9, 0.1), Vector3.new(0, -0.05, -uz - 0.17), EMBER, nil, NEON)
		for _, x in { -0.3, 0, 0.3 } do
			attach(upper, "ForgeBar", Vector3.new(0.12, 1.0, 0.1), Vector3.new(x, -0.05, -uz - 0.2), DARK_IRON, nil, METAL)
		end
		pauldrons(IRON, METAL)
		legWear(BROWN)
		boots(DARK_IRON)
		belt(DARK_IRON, IRON)
		headwear("Helm", IRON, METAL, 0.3)
		attach(head, "HelmRidge", Vector3.new(0.2, 0.3, hz * 2 + 0.4), Vector3.new(0, hy + 0.25, 0), DARK_IRON, nil, METAL)
		attach(hand, "HammerHandle", Vector3.new(0.3, 0.3, 3.2), Vector3.new(0, -0.1, -1.0), DARK_WOOD)
		attach(hand, "HammerHead", Vector3.new(1.3, 1.1, 1.1), Vector3.new(0, -0.1, -2.6), DARK_IRON, nil, METAL)
		attach(hand, "HammerEmber", Vector3.new(1.34, 0.4, 0.4), Vector3.new(0, -0.1, -2.6), EMBER, nil, NEON)
		topOffset = hy + 1.8
	elseif look == "MorovaMatka" then
		-- Boss: the plague mother: a dark green robe, antlers with hanging vials, a skull on the belt, a staff with a
		-- poison crystal and dripping green bottles.
		attack = "cast"
		paint(DARK_GREEN, DARK_GREEN, DARK_GREEN, DARK_GREEN)
		robe(DARK_GREEN, C(70, 120, 60), 1.5)
		hood(DARK_GREEN, 0.35)
		for _, side in { -1, 1 } do
			attach(head, "Antler", Vector3.new(0.18, 1.3, 0.18), Vector3.new(side * (hx + 0.1), hy + 0.6, 0.1), DARK_WOOD, nil, nil, Vector3.new(0, 0, -side * 30))
			attach(head, "AntlerTine", Vector3.new(0.14, 0.6, 0.14), Vector3.new(side * (hx + 0.5), hy + 1.15, 0.1), DARK_WOOD, nil, nil, Vector3.new(0, 0, side * 15))
			vial(head, "AntlerVial", Vector3.new(side * (hx + 0.75), hy + 0.65, 0.1), POISON)
		end
		attach(lower, "BeltSkull", Vector3.new(0.45, 0.45, 0.35), Vector3.new(0, -0.2, -lz - 0.3), BONE)
		vial(lower, "VialL", Vector3.new(-0.55, -0.4, -lz - 0.2), POISON)
		vial(lower, "VialR", Vector3.new(0.55, -0.4, -lz - 0.2), POISON)
		staff(POISON, 0.7)
		topOffset = hy + 2.3
	elseif look == "ArcimagVex" then
		-- Boss: the archmage: a dark purple robe with gold trim, a tall hat, a glowing book in the left hand and
		-- purple crystals floating about.
		attack = "cast"
		paint(DARK_PURPLE, DARK_PURPLE, DARK_PURPLE, DARK_PURPLE)
		robe(DARK_PURPLE, GOLD, 1.6)
		attach(upper, "Collar", Vector3.new(ux * 2 + 0.5, 0.5, uz * 2 + 0.4), Vector3.new(0, uy + 0.1, 0), DARK_PURPLE)
		pointedHat(DARK_PURPLE, GOLD)
		attach(head, "HatBand", Vector3.new(hx * 1.7, 0.16, hz * 1.7), Vector3.new(0, hy + 0.22, 0), GOLD, nil, METAL)
		attach(leftHand, "Book", Vector3.new(0.8, 0.12, 1.0), Vector3.new(0, -0.2, -0.3), C(70, 40, 110))
		attach(leftHand, "BookGlow", Vector3.new(0.6, 0.14, 0.8), Vector3.new(0, -0.14, -0.3), VIOLET_GLOW, nil, NEON)
		for i, offset in { Vector3.new(-0.7, 0.4, -0.6), Vector3.new(0.5, 0.9, -0.8), Vector3.new(-0.2, 1.3, -0.3) } do
			attach(leftHand, "FloatCrystal" .. i, Vector3.new(0.25, 0.4, 0.25), offset, VIOLET_GLOW, nil, NEON, Vector3.new(20 * i, 45, 15))
		end
		staff(VIOLET_GLOW, 0.7)
		topOffset = hy + 2.5
	elseif look == "HoubovyTitan" then
		-- Boss: the mushroom titan: bark plates on the body, moss, red-capped mushrooms on the head and shoulders,
		-- and a mushroom club.
		local BARK = C(110, 75, 45)
		local MOSS = C(90, 140, 60)
		local CAP = C(200, 50, 50)
		paint(BARK, BARK, BARK, DARK_WOOD)
		local function mushroom(part: BasePart, name: string, offset: Vector3, size: number)
			attach(part, name .. "Stem", Vector3.new(size * 0.45, size * 0.7, size * 0.45), offset, CREAM)
			attach(part, name .. "Cap", Vector3.new(size * 1.2, size * 0.5, size * 1.2), offset + Vector3.new(0, size * 0.5, 0), CAP)
			attach(part, name .. "Dot", Vector3.new(size * 0.3, size * 0.1, size * 0.3), offset + Vector3.new(size * 0.25, size * 0.78, -size * 0.2), CREAM)
		end
		cover(upper, "BarkChest", Vector3.new(0.4, 0.2, 0.4), Vector3.zero, BARK, Enum.Material.Wood)
		attach(upper, "Moss", Vector3.new(ux * 2 + 0.5, 0.35, uz * 2 + 0.5), Vector3.new(0, uy + 0.05, 0), MOSS, nil, Enum.Material.Grass)
		pauldrons(BARK, Enum.Material.Wood)
		for _, part in { leftArm, rightArm, leftLeg, rightLeg, leftShin, rightShin } do
			cover(part, "Bark", Vector3.new(0.2, 0.02, 0.2), Vector3.zero, BARK, Enum.Material.Wood)
		end
		boots(DARK_WOOD)
		mushroom(head, "HeadShroomA", Vector3.new(-0.2, hy + 0.3, 0.1), 0.9)
		mushroom(head, "HeadShroomB", Vector3.new(0.45, hy + 0.1, -0.15), 0.6)
		mushroom(leftArm, "ShoulderShroom", Vector3.new(-0.1, leftArm.Size.Y / 2 / s + 0.3, 0), 0.7)
		mushroom(rightArm, "ShoulderShroom", Vector3.new(0.15, rightArm.Size.Y / 2 / s + 0.3, 0.1), 0.5)
		attach(hand, "Club", Vector3.new(0.4, 0.4, 3.2), Vector3.new(0, -0.1, -1.0), BARK, nil, Enum.Material.Wood)
		attach(hand, "ClubKnot", Vector3.new(0.7, 0.7, 0.9), Vector3.new(0, -0.1, -2.5), DARK_WOOD, nil, Enum.Material.Wood)
		mushroom(hand, "ClubShroomA", Vector3.new(0.2, 0.3, -2.4), 0.6)
		mushroom(hand, "ClubShroomB", Vector3.new(-0.25, 0.25, -1.6), 0.45)
		topOffset = hy + 2.4
	elseif look == "RiftKing" then
		-- FINAL BOSS: Grubnak — The Rift King. Black plate with gold trim and purple rift crystals, a gold crown with
		-- crystal spikes, a red cape, a purple orb in the left hand and a giant crystal-powered hammer in the right.
		-- Crystals carry the attribute "RiftCrystal" and the armor plates "RiftArmor": the fight (RiftKing.luau)
		-- brightens the crystals and cracks the armor when the boss is enraged.
		local BLACK = C(38, 38, 46)
		local CRYSTAL = C(185, 90, 255)
		paint(BLACK, BLACK, BLACK, BLACK)
		local function crystal(part: BasePart, name: string, offset: Vector3, size: number, angles: Vector3?): Part
			local shard = attach(part, name, Vector3.new(size * 0.55, size, size * 0.55), offset, CRYSTAL, nil, NEON, angles or Vector3.new(0, 45, 0))
			shard:SetAttribute("RiftCrystal", true)
			return shard
		end
		local function plate(part: BasePart, name: string, grow: Vector3, offset: Vector3): Part
			local armor = cover(part, name, grow, offset, BLACK, METAL)
			armor:SetAttribute("RiftArmor", true)
			return armor
		end
		-- The face: purple glowing eyes, big tusks.
		for _, eyeName in { "EyeL", "EyeR" } do
			local eye = model:FindFirstChild(eyeName) :: BasePart?
			if eye then
				eye.Color = CRYSTAL
			end
		end
		attach(head, "TuskL", Vector3.new(0.16, 0.42, 0.14), Vector3.new(-0.28, -hy * 0.5, -hz - 0.02), BONE, nil, nil, Vector3.new(0, 0, 8))
		attach(head, "TuskR", Vector3.new(0.16, 0.42, 0.14), Vector3.new(0.28, -hy * 0.5, -hz - 0.02), BONE, nil, nil, Vector3.new(0, 0, -8))
		-- Armor: chest and back plates with a gold frame and a purple gem, pauldrons with crystal spikes,
		-- gauntlets, leg plates, boots with gold caps.
		plate(upper, "ChestPlate", Vector3.new(0.4, 0.15, 0.4), Vector3.zero)
		attach(upper, "ChestFrame", Vector3.new(ux * 2 + 0.44, 0.2, 0.08), Vector3.new(0, uy - 0.15, -uz - 0.23), GOLD, nil, METAL)
		attach(upper, "ChestFrameLow", Vector3.new(ux * 2 + 0.44, 0.2, 0.08), Vector3.new(0, -uy + 0.15, -uz - 0.23), GOLD, nil, METAL)
		attach(upper, "ChestBeltL", Vector3.new(0.18, uy * 2 - 0.2, 0.08), Vector3.new(-ux * 0.55, 0, -uz - 0.23), GOLD, nil, METAL)
		attach(upper, "ChestBeltR", Vector3.new(0.18, uy * 2 - 0.2, 0.08), Vector3.new(ux * 0.55, 0, -uz - 0.23), GOLD, nil, METAL)
		crystal(upper, "ChestGem", Vector3.new(0, 0, -uz - 0.3), 0.7, Vector3.new(0, 0, 45))
		attach(upper, "ChestGemFrame", Vector3.new(0.95, 0.95, 0.06), Vector3.new(0, 0, -uz - 0.24), GOLD, nil, METAL, Vector3.new(0, 0, 45))
		for _, arm in { leftArm, rightArm } do
			local ay = arm.Size.Y / 2 / s
			local side = if arm == leftArm then -1 else 1
			plate(arm, "Pauldron", Vector3.new(0.6, -0.2, 0.6), Vector3.new(side * 0.15, ay - 0.25, 0))
			attach(arm, "PauldronRim", Vector3.new(arm.Size.X / s + 0.75, 0.16, arm.Size.Z / s + 0.75), Vector3.new(side * 0.15, ay + 0.05, 0), GOLD, nil, METAL)
			crystal(arm, "PauldronCrystalA", Vector3.new(side * 0.35, ay + 0.55, 0), 0.9, Vector3.new(0, 45, -side * 15))
			crystal(arm, "PauldronCrystalB", Vector3.new(side * 0.05, ay + 0.45, -0.3), 0.6, Vector3.new(-20, 45, 0))
			crystal(arm, "PauldronCrystalC", Vector3.new(side * 0.1, ay + 0.4, 0.3), 0.5, Vector3.new(20, 45, 0))
		end
		for _, forearm in { limb("LeftLowerArm"), limb("RightLowerArm") } do
			plate(forearm, "Gauntlet", Vector3.new(0.3, 0.05, 0.3), Vector3.zero)
			attach(forearm, "GauntletRim", Vector3.new(forearm.Size.X / s + 0.42, 0.14, forearm.Size.Z / s + 0.42), Vector3.new(0, forearm.Size.Y / 2 / s - 0.05, 0), GOLD, nil, METAL)
		end
		for _, part in { leftLeg, rightLeg, leftShin, rightShin } do
			plate(part, "LegPlate", Vector3.new(0.22, 0.02, 0.22), Vector3.zero)
		end
		boots(BLACK)
		attach(leftFoot, "BootCap", Vector3.new(leftFoot.Size.X / s + 0.2, 0.3, 0.3), Vector3.new(0, 0, -leftFoot.Size.Z / s / 2), GOLD, nil, METAL)
		attach(rightFoot, "BootCap", Vector3.new(rightFoot.Size.X / s + 0.2, 0.3, 0.3), Vector3.new(0, 0, -rightFoot.Size.Z / s / 2), GOLD, nil, METAL)
		belt(BLACK, GOLD)
		crystal(lower, "BeltGem", Vector3.new(0, 0.1, -lz - 0.3), 0.45, Vector3.new(0, 0, 45))
		-- The red cape with a high collar.
		attach(upper, "Cape", Vector3.new(ux * 2 + 0.5, 3.4, 0.16), Vector3.new(0, -1.1, uz + 0.2), RED, nil, nil, Vector3.new(-7, 0, 0))
		attach(upper, "CapeCollar", Vector3.new(ux * 2 + 0.8, 0.45, uz * 2 + 0.6), Vector3.new(0, uy + 0.1, 0), RED)
		-- The crown: a gold band, five gold points and a purple crystal on every point.
		attach(head, "Crown", Vector3.new(hx * 2 + 0.2, 0.4, hz * 2 + 0.2), Vector3.new(0, hy + 0.1, 0), GOLD, nil, METAL)
		for i, x in { -0.75, -0.38, 0, 0.38, 0.75 } do
			local tall = if i == 3 then 0.7 elseif i == 2 or i == 4 then 0.55 else 0.4
			attach(head, "CrownPoint" .. i, Vector3.new(0.2, tall, 0.2), Vector3.new(x * hx, hy + 0.3 + tall / 2, -hz * 0.35), GOLD, nil, METAL)
			crystal(head, "CrownCrystal" .. i, Vector3.new(x * hx, hy + 0.45 + tall, -hz * 0.35), 0.45 + (if i == 3 then 0.25 else 0))
		end
		-- The left hand: a glowing rift orb.
		local orb = attach(leftHand, "RiftOrb", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, -0.3, -0.7), CRYSTAL, Enum.PartType.Ball, NEON)
		orb:SetAttribute("RiftCrystal", true)
		local orbLight = Instance.new("PointLight")
		orbLight.Color = CRYSTAL
		orbLight.Range = 10
		orbLight.Brightness = 1.2
		orbLight.Parent = orb
		-- The right hand: the giant hammer. A long dark handle with gold bands, a black block head framed in gold,
		-- crystals set in its faces and a crystal spike on top.
		attach(hand, "HammerHandle", Vector3.new(0.34, 0.34, 4.6), Vector3.new(0, -0.1, -1.6), DARK_IRON, nil, METAL)
		for _, z in { -0.5, -1.4, -2.6 } do
			attach(hand, "HammerBand", Vector3.new(0.44, 0.44, 0.3), Vector3.new(0, -0.1, z), GOLD, nil, METAL)
		end
		local hammerHead = attach(hand, "HammerHead", Vector3.new(2.2, 1.5, 1.5), Vector3.new(0, -0.1, -3.9), BLACK, nil, METAL)
		hammerHead:SetAttribute("RiftArmor", true)
		attach(hand, "HammerFrameA", Vector3.new(2.3, 0.2, 1.6), Vector3.new(0, 0.6, -3.9), GOLD, nil, METAL)
		attach(hand, "HammerFrameB", Vector3.new(2.3, 0.2, 1.6), Vector3.new(0, -0.8, -3.9), GOLD, nil, METAL)
		attach(hand, "HammerFrameC", Vector3.new(2.3, 1.6, 0.2), Vector3.new(0, -0.1, -3.2), GOLD, nil, METAL)
		attach(hand, "HammerFrameD", Vector3.new(2.3, 1.6, 0.2), Vector3.new(0, -0.1, -4.6), GOLD, nil, METAL)
		crystal(hand, "HammerCrystalL", Vector3.new(-1.2, -0.1, -3.9), 0.8, Vector3.new(0, 0, 90))
		crystal(hand, "HammerCrystalR", Vector3.new(1.2, -0.1, -3.9), 0.8, Vector3.new(0, 0, 90))
		crystal(hand, "HammerCrystalFront", Vector3.new(0, -0.1, -4.75), 0.6, Vector3.new(90, 0, 0))
		crystal(hand, "HammerCrystalTop", Vector3.new(0, 0.95, -3.9), 1.1)
		local hammerLight = Instance.new("PointLight")
		hammerLight.Color = CRYSTAL
		hammerLight.Range = 9
		hammerLight.Brightness = 0.8
		hammerLight.Parent = hammerHead
		topOffset = hy + 2.8
	else
		-- Unknown look: a bare goblin with a club.
		belt(DARK_LEATHER)
		attach(hand, "ClubHandle", Vector3.new(0.25, 0.25, 2.0), Vector3.new(0, -0.1, -0.7), WOOD)
		attach(hand, "ClubHead", Vector3.new(0.6, 0.6, 0.75), Vector3.new(0, -0.1, -1.85), DARK_WOOD)
	end

	-- A soft aura in the level color from level 7 on (the only thing the level adds to the designed look).
	if level >= 7 then
		attach(upper, "Aura", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, 0.2, uz + 0.5), Levels.color(level), Enum.PartType.Ball, NEON)
	end

	-- Name + level label and a hidden HP bar (Soldier.showBar / Soldier.setHp find "Back" and "Bar").
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(190, 30)
	gui.StudsOffset = Vector3.new(0, topOffset * s, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 40 -- near only (Soldier.showBar widens it for a battle)
	gui.Adornee = head
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = C(255, 230, 120)
	label.TextStrokeTransparency = 0.3
	label.Text = string.format("%s · %s", def.label, Levels.label(level))
	label.Parent = gui

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Position = UDim2.fromOffset(0, 22)
	back.Size = UDim2.new(1, 0, 0, 7)
	back.BackgroundColor3 = C(35, 35, 35)
	back.BorderSizePixel = 0
	back.Visible = false
	back.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = C(230, 70, 70)
	bar.Parent = back

	model:PivotTo(CFrame.new(0, Enemy.lift(kind, level), 0))

	Rig.animate(model, attack, true) -- idle / run / attack / death (Rig.luau)
	return model
end

return Enemy
