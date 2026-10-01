--!strict
-- 3D soldier assembled from blocks. The model's pivot is the center of the body;
-- `lift` is its height above the ground, so a soldier can stand on any point of the floor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Units = require(Shared.Config.Units)
local Levels = require(Shared.Config.Levels)
local Rig = require(script.Parent.Rig)
local SoldierRig = require(script.Parent.SoldierRig)

-- The server makes the R15 base rig right away (the Soldier class and the client's previews clone it).
if game:GetService("RunService"):IsServer() then
	task.spawn(Rig.base)
end

-- Classes whose look comes from a designed model with one stage per merge level (9 stages). The data
-- modules are generated from the design files by tools/stages_from_rbxmx.py (see src/shared/StageModels).
local STAGE_MODELS: { [string]: { stages: { any } } } = {
	Knight = require(script.Parent.StageModels.Knight),
	Archer = require(script.Parent.StageModels.Archer),
}

local SKIN = Color3.fromRGB(245, 220, 185)
local DARK = Color3.fromRGB(55, 58, 70)
local WOOD = Color3.fromRGB(120, 85, 50)
local STEEL = Color3.fromRGB(200, 205, 215)
local ENEMY_TINT = Color3.fromRGB(210, 60, 60)
-- How much the body is tinted toward the level color (level 1 … 9).
local LEVEL_TINT = { 0, 0.12, 0.22, 0.3, 0.38, 0.45, 0.52, 0.6, 0.68 }

local Soldier = {}

-- How big a character is at a merge level. Gentle: a level 9 is a quarter bigger than a level 1, so the
-- squad and the board stay readable (a 2x level 9 crowded its neighbours and hid the pads).
function Soldier.scale(tier: number): number
	return 0.9 + 0.045 * (tier - 1)
end

function Soldier.lift(tier: number, ascended: boolean?): number
	return 2.4 * Soldier.scale(tier) * (if ascended then 1.1 else 1)
end

-- ── The Soldier class: 9 stages of gear ───────────────────────────────────
-- Designed in Claude Design (project "soldier-merge"): one character, 9 stages, the gear is
-- cumulative. Stage = merge level (1 … 9). Feet are at y = -FEET below the model's pivot, the
-- soldier faces -Z.

local C = Color3.fromRGB
local OLIVE = C(77, 93, 51)
local DARK_GUN = C(55, 65, 81)
local GUN_GRAY = C(107, 114, 128)
local GOLD = C(212, 160, 23)
local BRIGHT_GOLD = C(234, 179, 8)
local SHIRT = C(95, 122, 62)
local PANTS = C(74, 94, 48)
local BLACK = C(17, 24, 39)
local BROWN = C(107, 68, 35)
local VEST = C(63, 74, 60)
local SOLDIER_SKIN = C(242, 194, 145)
local FEET = 2.4 -- distance from the pivot down to the feet (Soldier.lift is FEET * scale)

type StageDef = {
	name: string, -- what this stage adds
	head: string, -- "cap" | "helmet"
	hat: Color3,
	weapon: string, -- "pistol" | "rifle" | "minigun"
	gun: Color3,
	vest: boolean?,
	shades: boolean?,
	medals: boolean?,
	aura: boolean?,
	shiny: boolean?,
	cape: boolean?,
}

local SOLDIER_STAGES: { StageDef } = {
	{ name = "Starting gear", head = "cap", hat = OLIVE, weapon = "pistol", gun = GUN_GRAY },
	{ name = "Combat helmet", head = "helmet", hat = OLIVE, weapon = "pistol", gun = GUN_GRAY },
	{ name = "Assault rifle", head = "helmet", hat = OLIVE, weapon = "rifle", gun = DARK_GUN },
	{ name = "Tactical vest", head = "helmet", hat = OLIVE, weapon = "rifle", gun = DARK_GUN, vest = true },
	{ name = "Shades", head = "helmet", hat = OLIVE, weapon = "rifle", gun = DARK_GUN, vest = true, shades = true },
	{ name = "Minigun", head = "helmet", hat = OLIVE, weapon = "minigun", gun = DARK_GUN, vest = true, shades = true },
	{ name = "Medals & aura", head = "helmet", hat = OLIVE, weapon = "minigun", gun = DARK_GUN, vest = true, shades = true, medals = true, aura = true },
	{ name = "Golden gear", head = "helmet", hat = GOLD, weapon = "minigun", gun = GOLD, vest = true, shades = true, medals = true, aura = true, shiny = true },
	{ name = "Hero cape", head = "helmet", hat = BRIGHT_GOLD, weapon = "minigun", gun = BRIGHT_GOLD, vest = true, shades = true, medals = true, aura = true, shiny = true, cape = true },
}

-- Builds the whole Soldier (body, face, gear of the stage) into `model` and returns its head.
local function buildStageSoldier(model: Model, s: number, tier: number, enemy: boolean, bare: boolean?): Part
	local stage = SOLDIER_STAGES[math.clamp(tier, 1, #SOLDIER_STAGES)]
	local function tint(color: Color3): Color3
		return if enemy then color:Lerp(ENEMY_TINT, 0.45) else color
	end

	local function part(size: Vector3, position: Vector3, color: Color3, options: { name: string?, shape: Enum.PartType?, reflectance: number?, rotation: CFrame?, transparency: number? }?): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.Size = size * s
		p.CFrame = CFrame.new((position - Vector3.new(0, FEET, 0)) * s) * (if options and options.rotation then options.rotation else CFrame.identity)
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if options then
			if options.name then
				p.Name = options.name
			end
			if options.shape then
				p.Shape = options.shape
			end
			if options.reflectance then
				p.Reflectance = options.reflectance
			end
			if options.transparency then
				p.Transparency = options.transparency
			end
		end
		p.Parent = model
		return p
	end

	-- The model's pivot: an invisible part (the pivot is FEET above the ground, like the other classes).
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Size = Vector3.one * 0.2
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pivot.Parent = model
	model.PrimaryPart = pivot

	-- An invisible box around the soldier: easy to point at with the mouse.
	part(Vector3.new(3.2, 6.6, 3), Vector3.new(0, 3.3, 0), BLACK, { name = "Hitbox", transparency = 1 })

	-- Body.
	part(Vector3.new(1, 2, 1), Vector3.new(-0.5, 1, 0), tint(PANTS))
	part(Vector3.new(1, 2, 1), Vector3.new(0.5, 1, 0), tint(PANTS))
	part(Vector3.new(1.05, 0.35, 1.1), Vector3.new(-0.5, 0.18, -0.03), BLACK) -- boots
	part(Vector3.new(1.05, 0.35, 1.1), Vector3.new(0.5, 0.18, -0.03), BLACK)
	local torso = part(Vector3.new(2, 2, 1), Vector3.new(0, 3, 0), tint(SHIRT), { name = "Torso" })
	part(Vector3.new(1, 2, 1), Vector3.new(-1.5, 3, 0), tint(SHIRT))
	part(Vector3.new(1, 2, 1), Vector3.new(1.5, 3, 0), tint(SHIRT))
	part(Vector3.new(0.9, 0.4, 0.9), Vector3.new(-1.5, 1.8, 0), SOLDIER_SKIN) -- hands
	part(Vector3.new(0.9, 0.4, 0.9), Vector3.new(1.5, 1.8, 0), SOLDIER_SKIN)
	part(Vector3.new(2.05, 0.3, 1.05), Vector3.new(0, 2.15, 0), BROWN) -- belt
	part(Vector3.new(0.35, 0.3, 0.05), Vector3.new(0, 2.15, -0.55), GOLD) -- buckle

	-- Head and face.
	local head = part(Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 4.6, 0), SOLDIER_SKIN, { name = "Head" })
	part(Vector3.new(0.16, 0.25, 0.05), Vector3.new(-0.25, 4.72, -0.62), BLACK)
	part(Vector3.new(0.16, 0.25, 0.05), Vector3.new(0.25, 4.72, -0.62), BLACK)
	part(Vector3.new(0.5, 0.08, 0.05), Vector3.new(0, 4.35, -0.62), BLACK)

	-- Head gear: a cap at stage 1, a combat helmet from stage 2 (golden from stage 8).
	local shine = if stage.shiny then 0.25 else nil
	if stage.head == "cap" then
		part(Vector3.new(1.3, 0.35, 1.3), Vector3.new(0, 5.37, 0), tint(stage.hat))
		part(Vector3.new(1.2, 0.1, 0.5), Vector3.new(0, 5.25, -0.85), tint(stage.hat))
	else
		part(Vector3.new(1.5, 0.65, 1.5), Vector3.new(0, 5.4, 0), tint(stage.hat), { reflectance = shine })
		part(Vector3.new(1.75, 0.12, 1.75), Vector3.new(0, 5.1, 0), tint(stage.hat), { reflectance = shine })
	end

	if stage.shades then
		part(Vector3.new(1.05, 0.28, 0.08), Vector3.new(0, 4.72, -0.65), BLACK, { reflectance = 0.3 })
	end

	if stage.vest then
		part(Vector3.new(2.15, 1.6, 1.15), Vector3.new(0, 3.15, 0), tint(VEST))
		for _, x in { -0.6, 0, 0.6 } do
			part(Vector3.new(0.5, 0.5, 0.15), Vector3.new(x, 2.65, -0.64), C(44, 53, 41)) -- pouches
		end
	end

	if stage.medals then
		for _, x in { -0.55, -0.2 } do
			part(Vector3.new(0.3, 0.3, 0.3), Vector3.new(x, 3.55, -0.62), BRIGHT_GOLD, { shape = Enum.PartType.Ball, reflectance = 0.2 })
		end
	end

	if stage.cape then
		part(Vector3.new(2.1, 3.2, 0.12), Vector3.new(0, 2.5, 0.64), tint(C(185, 28, 28)))
	end

	-- The weapon in the right hand.
	if stage.weapon == "pistol" then
		part(Vector3.new(0.25, 0.3, 0.9), Vector3.new(1.5, 1.9, -0.75), stage.gun, { reflectance = shine })
		part(Vector3.new(0.22, 0.45, 0.25), Vector3.new(1.5, 1.7, -0.4), stage.gun, { reflectance = shine })
	elseif stage.weapon == "rifle" then
		part(Vector3.new(0.3, 0.35, 2.6), Vector3.new(1.5, 2.0, -1.1), stage.gun, { reflectance = shine })
		part(Vector3.new(0.25, 0.55, 0.3), Vector3.new(1.5, 1.65, -1.2), stage.gun, { reflectance = shine })
		part(Vector3.new(0.2, 0.2, 0.6), Vector3.new(1.5, 2.28, -1.0), BLACK) -- scope
	else -- minigun
		part(Vector3.new(0.9, 0.9, 1.6), Vector3.new(1.5, 2.0, -0.9), stage.gun, { reflectance = shine })
		for _, offset in { Vector2.new(0, 0.22), Vector2.new(-0.2, -0.12), Vector2.new(0.2, -0.12) } do
			part(Vector3.new(1.4, 0.2, 0.2), Vector3.new(1.5 + offset.X, 2.0 + offset.Y, -2.3), stage.gun, {
				shape = Enum.PartType.Cylinder,
				reflectance = shine or 0,
				rotation = CFrame.Angles(0, math.rad(90), 0), -- the barrel points forward
			})
		end
	end

	-- The aura of the high stages: a soft glow in the level color (not in UI previews). No sparkles: they
	-- drowned the character.
	if stage.aura and not bare and not enemy then
		local light = Instance.new("PointLight")
		light.Color = Levels.color(tier)
		light.Brightness = 0.8
		light.Range = 6
		light.Parent = torso
	end

	return head
end

-- What the given class adds at the given level, e.g. "Combat helmet" (only the Soldier has named gear).
local function gearName(class: string, tier: number): string?
	if not SoldierRig.has(class) then
		return nil
	end
	return SoldierRig.name(tier, class) -- the rank of the level (Recruit … Legend, Squire … Legend)
end

-- Builds a class whose look is data (generated from a designed model, one entry per merge stage).
-- Returns the head (it carries the name label) and how high the label floats above it.
local function buildStageFromData(model: Model, s: number, tier: number, bare: boolean?, stages: { any }): (Part, number)
	local stage = stages[math.clamp(tier, 1, #stages)]

	-- The model's pivot: an invisible part, FEET above the ground like the other classes.
	local pivot = Instance.new("Part")
	pivot.Name = "Pivot"
	pivot.Size = Vector3.one * 0.2
	pivot.Transparency = 1
	pivot.Anchored = true
	pivot.CanCollide = false
	pivot.CanQuery = false
	pivot.CanTouch = false
	pivot.Parent = model
	model.PrimaryPart = pivot

	local head: Part = pivot
	local torso: Part? = nil
	for _, data in stage.parts do
		local p = Instance.new("Part")
		p.Name = data.name or "Part"
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.Size = data.size * s
		p.CFrame = CFrame.new((data.position - Vector3.new(0, FEET, 0)) * s)
		p.Color = data.color
		p.Material = Enum.Material:FromValue(data.material) or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		if data.reflectance then
			p.Reflectance = data.reflectance
		end
		if data.transparency then
			p.Transparency = data.transparency
		end
		if data.shape then
			p.Shape = Enum.PartType:FromValue(data.shape) or Enum.PartType.Block
		end
		p.Parent = model
		if p.Name == "Head" then
			head = p
		elseif p.Name == "Torso" then
			torso = p
		end
	end

	-- The aura of the high stages: a soft glow in the level color (not in UI previews).
	if stage.aura and not bare and torso then
		local light = Instance.new("PointLight")
		light.Color = Levels.color(tier)
		light.Brightness = 0.8
		light.Range = 6
		light.Parent = torso
	end

	return head, stage.top
end

-- Adds the name / level / HP label and the glow outline, and puts the model in its standing pose.
local function finishModel(model: Model, head: Part, topOffset: number, s: number, def: Units.ClassDef, tier: number, enemy: boolean, levelColor: Color3, bare: boolean?, ascended: boolean?): Model
	-- Tier label + hidden HP bar (shown in battle).
	local gui = Instance.new("BillboardGui")
	gui.Name = "Info"
	gui.Size = UDim2.fromOffset(170, 30)
	gui.StudsOffset = Vector3.new(0, topOffset * s, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 40 -- the name / level label only when you are near (Soldier.showBar widens it for a battle)
	gui.Adornee = head
	gui.Parent = head

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 20)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = if enemy then Color3.fromRGB(255, 230, 120) else levelColor
	label.TextStrokeTransparency = 0.3
	label.Text = string.format("%s%s · %s", if ascended then "★ " else "", def.label, if ascended then "ASCENDED" else Levels.label(tier)) -- e.g. "Archer · Lv 3"
	if ascended then
		label.TextColor3 = Color3.fromRGB(255, 225, 120)
	end
	label.Parent = gui

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Position = UDim2.fromOffset(0, 22)
	back.Size = UDim2.new(1, 0, 0, 7)
	back.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	back.BorderSizePixel = 0
	back.Visible = false
	back.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BorderSizePixel = 0
	bar.BackgroundColor3 = Color3.fromRGB(80, 220, 90)
	bar.Parent = back

	-- From level 5 on, your characters get a thin outline in the level color (kept faint: the gear
	-- itself shows the level).
	if not enemy and tier >= 5 then
		local glow = Instance.new("Highlight")
		glow.Name = "LevelGlow"
		glow.FillTransparency = 1
		glow.OutlineColor = levelColor
		glow.OutlineTransparency = 0.5
		glow.Parent = model
	end

	-- An ASCENDED soldier (two level 9 merged): a golden halo ring over the head and golden sparkles.
	if ascended then
		local halo = Instance.new("Part")
		halo.Name = "AscendedHalo"
		halo.Shape = Enum.PartType.Cylinder
		halo.Size = Vector3.new(0.12, 2.2 * s, 2.2 * s)
		halo.CFrame = head.CFrame * CFrame.new(0, (0.95 + 0.4) * s, 0) * CFrame.Angles(0, 0, math.rad(90))
		halo.Color = Color3.fromRGB(255, 215, 90)
		halo.Material = Enum.Material.Neon
		halo.Anchored = true
		halo.CanCollide = false
		halo.CanQuery = false
		halo.CanTouch = false
		halo.CastShadow = false
		halo.Parent = model
		if not bare then
			local sparkles = Instance.new("Sparkles")
			sparkles.SparkleColor = Color3.fromRGB(255, 215, 90)
			sparkles.Parent = head
			local glow = model:FindFirstChild("LevelGlow") :: Highlight?
			if glow then
				glow.OutlineColor = Color3.fromRGB(255, 215, 90)
				glow.FillColor = Color3.fromRGB(255, 215, 90)
				glow.FillTransparency = 0.85
			end
		end
	end

	if bare then
		gui:Destroy()
		local glow = model:FindFirstChild("LevelGlow")
		if glow then
			glow:Destroy()
		end
	end

	model:PivotTo(CFrame.new(0, Soldier.lift(tier), 0))
	return model
end

-- `bare` = only the body (no level / HP label, no glow): used for the 3D previews in the UI.
-- `ascended` = two level 9 soldiers merged into one (a golden halo, a little bigger).
function Soldier.build(class: string, tier: number, enemy: boolean, bare: boolean?, ascended: boolean?): Model
	local def = Units.Classes[class]
	local s = Soldier.scale(tier) * (if ascended then 1.1 else 1)
	local main = if enemy then def.color:Lerp(ENEMY_TINT, 0.55) else def.color

	-- The merge level changes the whole look: body tint, cape, plates, belt, orbs, armor, wings,
	-- halo… Enemies get the same gear, tinted red.
	local levelColor = Levels.color(tier)
	local accent = if enemy then levelColor:Lerp(ENEMY_TINT, 0.5) else levelColor
	main = main:Lerp(accent, LEVEL_TINT[math.clamp(tier, 1, #LEVEL_TINT)])

	local model = Instance.new("Model")
	model.Name = def.label

	if SoldierRig.has(class) then
		-- The Soldier and the Knight are R15 characters with 9 designed stages (SoldierRig.luau). Without the base rig
		-- (it could not be made, or it has not reached this client yet) the block soldier below is built.
		local rig, rigHead, rigTop = SoldierRig.build(tier, s, bare, class)
		if rig and rigHead and rigTop then
			rig.Name = def.label
			return finishModel(rig, rigHead :: any, rigTop, s, def, tier, enemy, levelColor, bare, ascended)
		end
	end
	if class == "Soldier" then
		local soldierHead = buildStageSoldier(model, s, tier, enemy, bare)
		return finishModel(model, soldierHead, 2.4, s, def, tier, enemy, levelColor, bare, ascended)
	end

	-- Classes with a designed model (Knight, Archer): the stage of the level, straight from the design data.
	local stageData = STAGE_MODELS[class]
	if stageData then
		local stageHead, stageTop = buildStageFromData(model, s, tier, bare, stageData.stages)
		return finishModel(model, stageHead, stageTop, s, def, tier, enemy, levelColor, bare, ascended)
	end

	-- In all offsets -Z is "forward" (where the soldier looks).
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

	local body = add("Body", Vector3.new(2, 2, 1), Vector3.zero, main)
	model.PrimaryPart = body
	add("LegL", Vector3.new(0.8, 1.4, 0.8), Vector3.new(-0.5, -1.7, 0), DARK)
	add("LegR", Vector3.new(0.8, 1.4, 0.8), Vector3.new(0.5, -1.7, 0), DARK)
	add("ArmL", Vector3.new(0.7, 1.6, 0.7), Vector3.new(-1.4, 0.1, 0), main)
	add("ArmR", Vector3.new(0.7, 1.6, 0.7), Vector3.new(1.4, 0.1, 0), main)
	local head = add("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0), SKIN)

	local topOffset = 2.4
	if class == "Archer" then
		add("Hood", Vector3.new(1.4, 0.55, 1.4), Vector3.new(0, 2.25, 0), Color3.fromRGB(40, 90, 50))
		add("Bow", Vector3.new(0.2, 2.6, 0.4), Vector3.new(1.5, 0.3, -0.8), WOOD)
	elseif class == "Tank" then
		add("Helmet", Vector3.new(1.5, 0.8, 1.5), Vector3.new(0, 2.35, 0), STEEL, nil, Enum.Material.Metal)
		add("Crest", Vector3.new(0.2, 0.6, 1.2), Vector3.new(0, 2.95, 0), Color3.fromRGB(190, 50, 50))
		add("Shield", Vector3.new(0.35, 2.6, 2.0), Vector3.new(-1.9, 0.2, -0.5), Color3.fromRGB(150, 110, 50), nil, Enum.Material.Metal)
		add("ShieldBoss", Vector3.new(0.5, 0.7, 0.7), Vector3.new(-2.15, 0.2, -0.5), STEEL, Enum.PartType.Ball, Enum.Material.Metal)
		add("Mace", Vector3.new(0.3, 1.8, 0.3), Vector3.new(1.4, 0.7, -0.9), WOOD)
		add("MaceHead", Vector3.new(0.8, 0.8, 0.8), Vector3.new(1.4, 1.8, -0.9), STEEL, Enum.PartType.Ball, Enum.Material.Metal)
		topOffset = 3.4
	elseif class == "Berserker" then
		add("HornL", Vector3.new(0.3, 0.9, 0.3), Vector3.new(-0.55, 2.55, 0), Color3.fromRGB(240, 235, 215))
		add("HornR", Vector3.new(0.3, 0.9, 0.3), Vector3.new(0.55, 2.55, 0), Color3.fromRGB(240, 235, 215))
		add("Headband", Vector3.new(1.3, 0.3, 1.3), Vector3.new(0, 1.85, 0), Color3.fromRGB(170, 40, 40))
		add("AxeHandle", Vector3.new(0.25, 3.0, 0.25), Vector3.new(1.5, 0.6, -0.9), WOOD)
		add("AxeHead", Vector3.new(0.3, 1.2, 1.4), Vector3.new(1.5, 1.9, -1.3), STEEL, nil, Enum.Material.Metal)
		topOffset = 3.2
	elseif class == "Hunter" then
		add("Cap", Vector3.new(1.4, 0.5, 1.4), Vector3.new(0, 2.2, 0), Color3.fromRGB(50, 110, 110))
		add("Visor", Vector3.new(1.3, 0.2, 0.7), Vector3.new(0, 2.05, -0.9), Color3.fromRGB(50, 110, 110))
		add("Rifle", Vector3.new(0.3, 0.3, 3.6), Vector3.new(1.3, 0.5, -1.6), DARK, nil, Enum.Material.Metal)
		add("Scope", Vector3.new(0.3, 0.3, 1.0), Vector3.new(1.3, 0.85, -1.2), def.color:Lerp(Color3.new(1, 1, 1), 0.3), nil, Enum.Material.Neon)
	else
		add("HatBrim", Vector3.new(1.9, 0.2, 1.9), Vector3.new(0, 2.05, 0), Color3.fromRGB(70, 40, 100))
		add("HatTop", Vector3.new(1.0, 1.3, 1.0), Vector3.new(0, 2.7, 0), Color3.fromRGB(90, 55, 130))
		add("Staff", Vector3.new(0.25, 3.4, 0.25), Vector3.new(1.5, 0.4, -0.8), WOOD)
		add("Orb", Vector3.new(0.9, 0.9, 0.9), Vector3.new(1.5, 2.3, -0.8), def.color:Lerp(Color3.new(1, 1, 1), 0.4), Enum.PartType.Ball, Enum.Material.Neon)
		topOffset = 3.4
	end

	-- Gear by merge level. Every level adds to the previous one:
	--   Lv 2: cape
	--   Lv 3: + metal shoulder plates
	--   Lv 4: + glowing belt and shoulder spikes
	--   Lv 5: + two floating orbs and a glow outline
	--   Lv 6: + metal armor
	--   Lv 7: + neon wings
	--   Lv 8: + a halo
	--   Lv 9: the cape becomes a long red hero cape
	local rc = accent
	local function tilt(part: Part, x: number, y: number, z: number)
		part.CFrame = part.CFrame * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	end
	if tier >= 2 then
		local heroCape = tier >= 9
		add(
			"Cape",
			Vector3.new(1.8, if heroCape then 3.1 else 2.5, 0.15),
			Vector3.new(0, if heroCape then -0.4 else -0.1, 0.65),
			if heroCape then Color3.fromRGB(185, 28, 28) else rc:Lerp(Color3.new(0, 0, 0), 0.3)
		)
	end
	if tier >= 3 then
		add("ShoulderL", Vector3.new(1.0, 0.5, 1.2), Vector3.new(-1.4, 1.05, 0), rc:Lerp(STEEL, 0.55), nil, Enum.Material.Metal)
		add("ShoulderR", Vector3.new(1.0, 0.5, 1.2), Vector3.new(1.4, 1.05, 0), rc:Lerp(STEEL, 0.55), nil, Enum.Material.Metal)
	end
	if tier >= 4 then
		add("Belt", Vector3.new(2.1, 0.3, 1.1), Vector3.new(0, -0.85, 0), rc, nil, Enum.Material.Neon)
		add("SpikeL", Vector3.new(0.3, 0.9, 0.3), Vector3.new(-1.4, 1.6, 0), rc, nil, Enum.Material.Neon)
		add("SpikeR", Vector3.new(0.3, 0.9, 0.3), Vector3.new(1.4, 1.6, 0), rc, nil, Enum.Material.Neon)
	end
	if tier >= 5 then
		add("OrbL", Vector3.new(0.7, 0.7, 0.7), Vector3.new(-2.2, 2.0, 0.2), rc, Enum.PartType.Ball, Enum.Material.Neon)
		add("OrbR", Vector3.new(0.7, 0.7, 0.7), Vector3.new(2.2, 2.0, 0.2), rc, Enum.PartType.Ball, Enum.Material.Neon)
	end
	if tier >= 6 then
		body.Material = Enum.Material.Metal
		for _, name in { "ArmL", "ArmR" } do
			(model:FindFirstChild(name) :: Part).Material = Enum.Material.Metal
		end
	end
	if tier >= 7 then
		tilt(add("WingL", Vector3.new(0.2, 2.8, 1.7), Vector3.new(-1.4, 0.7, 0.9), rc, nil, Enum.Material.Neon), 0, 35, 12)
		tilt(add("WingR", Vector3.new(0.2, 2.8, 1.7), Vector3.new(1.4, 0.7, 0.9), rc, nil, Enum.Material.Neon), 0, -35, -12)
	end
	if tier >= 8 then
		local halo = add("Halo", Vector3.new(0.15, 2.4, 2.4), Vector3.new(0, topOffset + 0.2, 0), rc, Enum.PartType.Cylinder, Enum.Material.Neon)
		tilt(halo, 0, 0, 90) -- lay the cylinder flat above the head
		topOffset += 0.9
	end

	return finishModel(model, head, topOffset, s, def, tier, enemy, levelColor, bare, ascended)
end

-- What this level adds to a class, e.g. "Combat helmet" for a Lv 2 Soldier (only the Soldier has named gear).
function Soldier.gearName(class: string, tier: number): string?
	return gearName(class, tier)
end

-- Locked look on a pedestal: gray and semi-transparent.
function Soldier.lock(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Color = Color3.fromRGB(70, 72, 84)
			part.Material = Enum.Material.SmoothPlastic
			part.Transparency = 0.45
		end
	end
end

function Soldier.showBar(model: Model, friendly: boolean)
	local back = model:FindFirstChild("Back", true) :: Frame?
	local bar = model:FindFirstChild("Bar", true) :: Frame?
	if back and bar then
		back.Visible = true
		bar.BackgroundColor3 = if friendly then Color3.fromRGB(80, 220, 90) else Color3.fromRGB(230, 70, 70)
		local gui = back:FindFirstAncestorOfClass("BillboardGui")
		if gui then
			-- In a battle the label becomes a slim HP bar only: sized in studs (so it shrinks with the distance and
			-- never covers the fight), without the name, just over the head, and not drawn over everything.
			gui.MaxDistance = 170
			gui.Size = UDim2.fromScale(2.6, 0.28)
			gui.StudsOffset = Vector3.new(0, gui.StudsOffset.Y * 0.55, 0)
			gui.AlwaysOnTop = false
			gui.LightInfluence = 0
			for _, child in gui:GetChildren() do
				if child:IsA("TextLabel") then
					child.Visible = false
				end
			end
			back.Position = UDim2.fromScale(0, 0)
			back.Size = UDim2.fromScale(1, 1)
			back.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
			back.BackgroundTransparency = 0.25
			if not back:FindFirstChildOfClass("UICorner") then
				local round = Instance.new("UICorner")
				round.CornerRadius = UDim.new(0.5, 0)
				round.Parent = back
				local roundBar = Instance.new("UICorner")
				roundBar.CornerRadius = UDim.new(0.5, 0)
				roundBar.Parent = bar
			end
		end
	end
end

function Soldier.setHp(model: Model, fraction: number)
	local bar = model:FindFirstChild("Bar", true) :: Frame?
	if bar then
		bar.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	end
end

return Soldier
