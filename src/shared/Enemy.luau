--!strict
-- 3D enemy models (the Training Camp's goblins). An enemy is an R15 character (a rig made once by
-- Players:CreateHumanoidModelFromDescription and cloned), painted in its skin color, with goblin ears, nose,
-- eyes, clothes and a weapon welded on, and it plays animations (idle, run, attack, cast, death; see
-- Rig.luau). If the rig cannot be made (server only, needs the
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
			description.HeadScale = 1.25 -- a goblin has a big head
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
	local look = def.look -- the model of the kind (several kinds share one)
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
	attach(lower, "Loincloth", Vector3.new(2.1, 0.75, 1.12), Vector3.new(0, -0.1, 0), CLOTH)
	attach(upper, "Strap", Vector3.new(0.3, 2.0, 1.1), Vector3.new(0, 0, 0), DARK_WOOD, nil, nil, Vector3.new(0, 0, 38))

	-- The weapon lies along the hand's -Z (the "hold" animation raises the forearm, so it points up).
	local topOffset = hy + 0.9
	local attack = "slash"
	if look == "Goblin" then
		attach(hand, "ClubHandle", Vector3.new(0.25, 0.25, 2.0), Vector3.new(0, -0.1, -0.7), WOOD)
		attach(hand, "ClubHead", Vector3.new(0.6, 0.6, 0.75), Vector3.new(0, -0.1, -1.85), DARK_WOOD)
	elseif look == "GoblinArcher" then
		attack = "lunge"
		attach(head, "Hood", Vector3.new(hx * 2 + 0.2, 0.5, hz * 2 + 0.2), Vector3.new(0, hy - 0.1, 0), CLOTH)
		attach(hand, "Bow", Vector3.new(0.15, 0.3, 2.6), Vector3.new(0, -0.1, -0.35), WOOD)
		attach(hand, "BowString", Vector3.new(0.04, 0.04, 2.5), Vector3.new(0, 0.25, -0.35), BONE)
		attach(upper, "Quiver", Vector3.new(0.4, 1.3, 0.4), Vector3.new(0.3, 0.2, 0.7), DARK_WOOD, nil, nil, Vector3.new(0, 0, -20))
		topOffset = hy + 1.2
	elseif look == "GoblinBrute" then
		attach(head, "BoneHelm", Vector3.new(hx * 2 + 0.25, 0.6, hz * 2 + 0.2), Vector3.new(0, hy - 0.1, 0), BONE)
		attach(head, "HornL", Vector3.new(0.25, 0.8, 0.25), Vector3.new(-hx * 0.8, hy + 0.5, 0), BONE, nil, nil, Vector3.new(0, 0, 18))
		attach(head, "HornR", Vector3.new(0.25, 0.8, 0.25), Vector3.new(hx * 0.8, hy + 0.5, 0), BONE, nil, nil, Vector3.new(0, 0, -18))
		attach(hand, "ClubHandle", Vector3.new(0.35, 0.35, 2.6), Vector3.new(0, -0.1, -0.9), WOOD)
		attach(hand, "ClubHead", Vector3.new(0.95, 0.95, 0.95), Vector3.new(0, -0.1, -2.4), DARK_WOOD)
		for _, offset in { Vector3.new(0.55, 0, 0), Vector3.new(-0.55, 0, 0), Vector3.new(0, 0.55, 0), Vector3.new(0, -0.55, 0) } do
			attach(hand, "Spike", Vector3.new(0.3, 0.3, 0.3), Vector3.new(0, -0.1, -2.4) + offset, STEEL, nil, Enum.Material.Metal)
		end
		attach(upper, "ChestPlate", Vector3.new(2.1, 1.0, 1.12), Vector3.new(0, 0.25, 0), DARK_WOOD)
		topOffset = hy + 1.7
	elseif look == "GoblinShaman" then
		attack = "cast"
		attach(upper, "Robe", Vector3.new(2.12, 1.7, 1.12), Vector3.new(0, 0, 0), C(110, 70, 150))
		attach(lower, "RobeSkirt", Vector3.new(2.2, 1.3, 1.2), Vector3.new(0, -0.45, 0), C(95, 60, 135))
		for i, x in { -0.4, 0, 0.4 } do
			attach(head, "Feather" .. i, Vector3.new(0.18, 0.9, 0.18), Vector3.new(x, hy + 0.4, 0), C(255, 120 + i * 40, 60), nil, nil, Vector3.new(0, 0, -x * 40))
		end
		attach(hand, "Staff", Vector3.new(0.2, 0.2, 3.2), Vector3.new(0, -0.1, -0.6), WOOD)
		attach(hand, "Orb", Vector3.new(0.75, 0.75, 0.75), Vector3.new(0, -0.1, -2.4), C(120, 255, 110), Enum.PartType.Ball, Enum.Material.Neon)
		topOffset = hy + 1.8
	elseif look == "GoblinChief" then
		local gold = C(230, 180, 40)
		attach(head, "Crown", Vector3.new(hx * 2 + 0.1, 0.3, hz * 2 + 0.1), Vector3.new(0, hy + 0.05, 0), gold, nil, Enum.Material.Metal)
		for _, x in { -0.5, -0.25, 0, 0.25, 0.5 } do
			attach(head, "CrownSpike", Vector3.new(0.18, 0.45, 0.18), Vector3.new(x, hy + 0.4, -hz + 0.1), gold, nil, Enum.Material.Metal)
		end
		attach(upper, "Cape", Vector3.new(2.0, 3.0, 0.12), Vector3.new(0, -0.7, 0.62), C(160, 30, 30), nil, nil, Vector3.new(-8, 0, 0))
		attach(upper, "Pauldrons", Vector3.new(3.4, 0.4, 1.2), Vector3.new(0, 0.75, 0), gold, nil, Enum.Material.Metal)
		attach(hand, "AxeHandle", Vector3.new(0.3, 0.3, 2.9), Vector3.new(0, -0.1, -0.9), WOOD)
		attach(hand, "AxeBlade", Vector3.new(0.2, 1.2, 1.3), Vector3.new(0, -0.75, -2.0), STEEL, nil, Enum.Material.Metal)
		attach(head, "WarPaintL", Vector3.new(0.15, 0.45, 0.06), Vector3.new(-hx * 0.75, -0.05, -hz + 0.02), C(180, 30, 30))
		attach(head, "WarPaintR", Vector3.new(0.15, 0.45, 0.06), Vector3.new(hx * 0.75, -0.05, -hz + 0.02), C(180, 30, 30))
		topOffset = hy + 1.7
	end

	-- Gear that grows with the enemy level.
	if level >= 3 then
		attach(limb("LeftUpperArm"), "SpikeL", Vector3.new(0.3, 0.6, 0.3), Vector3.new(0, 0.7, 0), BONE)
		attach(limb("RightUpperArm"), "SpikeR", Vector3.new(0.3, 0.6, 0.3), Vector3.new(0, 0.7, 0), BONE)
	end
	if level >= 5 then
		attach(lower, "Belt", Vector3.new(2.15, 0.25, 1.16), Vector3.new(0, 0.2, 0), STEEL, nil, Enum.Material.Metal)
	end
	if level >= 7 then
		attach(upper, "Aura", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, 0.2, 0.9), Levels.color(level), Enum.PartType.Ball, Enum.Material.Neon)
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
