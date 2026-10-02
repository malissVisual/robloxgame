--!strict
-- Player plot in the world: floor, grid pads, Buy / Battle buttons
-- and the soldiers on the pads. All 3D, no GUI except labels above objects.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Grid = require(Shared.Grid)
local Synergy = require(Shared.Synergy)
local Units = require(Shared.Config.Units)
local Waves = require(Shared.Config.Waves)
local Levels = require(Shared.Config.Levels)
local Maps = require(Shared.Config.Maps)

local Soldier = require(Shared.Soldier)
local Enemy = require(Shared.Enemy)
local Enemies = require(Shared.Config.Enemies)
local Mutators = require(Shared.Config.Mutators)
local ArenaDecor = require(script.Parent.ArenaDecor)
local RingAuras = require(script.Parent.DecorData.BattleRingAuras)
local FightArena = require(script.Parent.FightArena)

export type Plot = {
	index: number,
	map: Maps.Def,
	arena: FightArena.Arena, -- the raised fight arena (placeholder, see FightArena.luau)
	owner: Player,
	origin: Vector3, -- top surface of the floor, x = center of the plot
	folder: Folder,
	models: { [number]: Model }, -- by slot id
	rendered: { [number]: string }, -- what is drawn on each slot (class|tier)
	slotPads: { [number]: Part },
	-- Preview of the enemy wave: one row, left to right as seen from your side (models follow the same order).
	enemies: { Waves.Enemy },
	enemyModels: { Model },
	enemyPincer: boolean, -- the PINCER twist: the row stands in two groups with a gap in the middle
	previewFolder: Folder?,
	previewKey: string?, -- wave|difficulty of the current enemy preview
	arenaFloor: Part, -- the arena's floor, used to tell whether the player stands inside the arena
	upgradeZone: Part, -- invisible box over the lobby level-upgrade station
	battleZone: Part, -- invisible box over the raised fight arena: walking up onto it opens the battle panel
	waveLabel: TextLabel,
	respawn: SpawnLocation,
}

local ORIGIN_Y = 0.3 -- above a possible Baseplate (its top is y = 0)
local PAD_TOP = 0.6 -- how far a pad rises above the floor (the top of the designed fight slot)
local SLOT_COLOR = Color3.fromRGB(107, 114, 128) -- the ring of an empty slot
local LOCKED_COLOR = Color3.fromRGB(42, 44, 54) -- merge pads that are not bought yet
local SQUAD_COLOR = Color3.fromRGB(70, 150, 190) -- the holographic ring of an EMPTY squad pad (lit, but soft: "put someone here")
local SQUAD_TAKEN_COLOR = Color3.fromRGB(128, 134, 150) -- the ring once a soldier stands on the pad (grey: satisfied)

local ARENA_START = 30 -- z of the arena gate (a road leads from the lobby to it)

local Plots = {}
Plots.setRingAura = setRingAura -- (the designed rarity auras are not used on the squad pads right now; kept for later)

local root: Folder? = nil

local function rootFolder(): Folder
	if not root then
		local folder = Instance.new("Folder")
		folder.Name = "Plots"
		folder.Parent = workspace
		root = folder
	end
	return root :: Folder
end

local function makePart(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Position = position
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.Parent = parent
	return p
end

-- The look of a pad: the designed FIGHT SLOT (design/TrainingArena1.server.lua, FightSlot_Variants.rbxmx): a
-- stone base, a glowing ring, a wooden top, four posts with gold caps and a word on top. The "Slot<id>" part
-- itself stays an invisible block (the game uses its position and size); this builds the look as its
-- children, and calling it again only changes the state:
--   ringColor  the color of the ring (an empty pad is grey, a soldier's level color, gold for the maximum)
--   glow       the ring glows (Neon + a light) while a soldier stands on it
--   text       "+" on an empty pad, "LOCKED" on a pad that is not bought yet, "" while a soldier stands there
local SLOT_WOOD = Color3.fromRGB(139, 90, 43)
local SLOT_DARK_WOOD = Color3.fromRGB(92, 58, 28)
local SLOT_STONE = Color3.fromRGB(107, 114, 128)
local SLOT_IRON = Color3.fromRGB(75, 85, 99)
local SLOT_GOLD = Color3.fromRGB(251, 191, 36)

-- `minimal` = the merge board's pads: only a flat dark disc with a thin colored ring, no posts, no wood, no word.
local function decoratePad(pad: Part, ringColor: Color3, glow: boolean, text: string, locked: boolean, minimal: boolean?)
	pad.Transparency = 1
	local floorY = pad.Position.Y - pad.Size.Y / 2
	local x, z = pad.Position.X, pad.Position.Z

	local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
		local p = pad:FindFirstChild(name) :: Part?
		if not p then
			p = Instance.new("Part")
			local made = p :: Part
			made.Name = name
			made.Anchored = true
			made.CanCollide = false
			made.CanQuery = false
			made.CanTouch = false
			made.CastShadow = false
			made.TopSurface = Enum.SurfaceType.Smooth
			made.BottomSurface = Enum.SurfaceType.Smooth
			if shape then
				made.Shape = shape
			end
			made.Size = size
			made.CFrame = cf
			made.Parent = pad
		end
		local existing = p :: Part
		existing.Color = color
		existing.Material = material
		return existing
	end
	local function standing(px: number, py: number, pz: number): CFrame -- a cylinder standing up (its axis is X)
		return CFrame.new(px, floorY + py, pz) * CFrame.Angles(0, 0, math.rad(90))
	end

	if minimal then
		-- The merge board: as quiet as possible. A thin dark disc, a thin ring in the state's color and nothing else.
		part("Base", Vector3.new(0.24, 4.6, 4.6), standing(x, 0.12, z), if locked then Color3.fromRGB(34, 36, 44) else Color3.fromRGB(46, 48, 60), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		local ring = part("Ring", Vector3.new(0.3, 4.9, 4.9), standing(x, 0.15, z), ringColor, if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		ring.Transparency = if glow then 0.1 elseif locked then 0.7 else 0.45
		for _, name in { "Top", "Label", "Post0", "Post1", "Post2", "Post3", "Cap0", "Cap1", "Cap2", "Cap3" } do
			local extra = pad:FindFirstChild(name)
			if extra then
				extra:Destroy()
			end
		end
	else
		part("Base", Vector3.new(0.5, 5.4, 5.4), standing(x, 0.25, z), if locked then SLOT_IRON else SLOT_STONE, Enum.Material.Slate, Enum.PartType.Cylinder)
		part("Ring", Vector3.new(0.56, 4.8, 4.8), standing(x, 0.28, z), ringColor, if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		part("Top", Vector3.new(0.6, 4.2, 4.2), standing(x, 0.3, z), if locked then SLOT_DARK_WOOD else SLOT_WOOD, Enum.Material.WoodPlanks, Enum.PartType.Cylinder)
		for i = 0, 3 do
			local angle = math.rad(45 + i * 90)
			local px, pz = x + 2.45 * math.cos(angle), z + 2.45 * math.sin(angle)
			part("Post" .. i, Vector3.new(0.3, 1.1, 0.3), CFrame.new(px, floorY + 1.05, pz), SLOT_DARK_WOOD, Enum.Material.Wood)
			part("Cap" .. i, Vector3.new(0.4, 0.3, 0.4), CFrame.new(px, floorY + 1.7, pz), if locked then SLOT_IRON else SLOT_GOLD, Enum.Material.Metal)
		end

		-- The word on top (only there while there is something to say).
		local label = part("Label", Vector3.new(3, 0.05, 3), CFrame.new(x, floorY + 0.63, z), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		label.Transparency = 1
		local gui = label:FindFirstChild("SurfaceGui") :: SurfaceGui?
		if not gui then
			gui = Instance.new("SurfaceGui")
			local made = gui :: SurfaceGui
			made.Face = Enum.NormalId.Top
			made.Parent = label
			local words = Instance.new("TextLabel")
			words.Name = "Words"
			words.Size = UDim2.fromScale(1, 1)
			words.BackgroundTransparency = 1
			words.Font = Enum.Font.FredokaOne
			words.TextScaled = true
			words.TextTransparency = 0.15
			words.TextStrokeTransparency = 0.4
			words.Parent = made
		end
		local words = (gui :: SurfaceGui):FindFirstChild("Words") :: TextLabel
		words.Text = text
		words.TextColor3 = if locked then Color3.fromRGB(156, 163, 175) else Color3.new(1, 1, 1)
	end

	-- A light on the ring while it glows.
	local ring = pad:FindFirstChild("Ring") :: Part
	local light = ring:FindFirstChild("Glow") :: PointLight?
	if not light then
		light = Instance.new("PointLight")
		local made = light :: PointLight
		made.Name = "Glow"
		made.Brightness = 1.5
		made.Range = 8
		made.Parent = ring
	end
	local glowLight = light :: PointLight
	glowLight.Color = ringColor
	glowLight.Enabled = glow
end

-- ── The holographic ring of a squad pad ──
-- The six squad pads are no stone slots: each is a flat holographic ring on the floor. Empty, it glows bright
-- (a light, a soft disc inside, the client pulses it); with a soldier on it, it turns grey and quiet. The
-- "Slot<id>" part stays the invisible block the game uses (drag target, position); this builds its look.
local function holoPad(pad: Part, occupied: boolean)
	pad.Transparency = 1
	local floorY = pad.Position.Y - pad.Size.Y / 2
	local x, z = pad.Position.X, pad.Position.Z
	local color = if occupied then SQUAD_TAKEN_COLOR else SQUAD_COLOR
	local function disc(name: string, diameter: number, thickness: number, lift: number): Part
		local p = pad:FindFirstChild(name) :: Part?
		if not p then
			p = Instance.new("Part")
			local made = p :: Part
			made.Name = name
			made.Shape = Enum.PartType.Cylinder
			made.Anchored = true
			made.CanCollide = false
			made.CanQuery = false
			made.CanTouch = false
			made.CastShadow = false
			made.Size = Vector3.new(thickness, diameter, diameter)
			made.CFrame = CFrame.new(x, floorY + lift, z) * CFrame.Angles(0, 0, math.rad(90))
			made.Parent = pad
		end
		return p :: Part
	end
	for _, name in { "Base", "Top", "Label", "Post0", "Post1", "Post2", "Post3", "Cap0", "Cap1", "Cap2", "Cap3", "LevelAura" } do
		local old = pad:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	-- The ring (Neon), a thinner second ring inside it and a faint disc filling the middle.
	local ring = disc("HoloRing", 6.2, 0.22, 0.11)
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = if occupied then 0.6 else 0.3
	ring:SetAttribute("BaseTransparency", ring.Transparency)
	local inner = disc("HoloInner", 5.4, 0.2, 0.1)
	inner.Material = Enum.Material.Neon
	inner.Color = if occupied then Color3.fromRGB(40, 42, 52) else SQUAD_COLOR:Lerp(Color3.new(0, 0, 0), 0.55)
	inner.Transparency = if occupied then 0.8 else 0.55
	local fill = disc("HoloFill", 4.6, 0.18, 0.09)
	fill.Material = Enum.Material.Neon
	fill.Color = color
	fill.Transparency = if occupied then 0.95 else 0.88
	fill:SetAttribute("BaseTransparency", fill.Transparency)
	local light = ring:FindFirstChild("Glow") :: PointLight?
	if not light then
		light = Instance.new("PointLight")
		local made = light :: PointLight
		made.Name = "Glow"
		made.Range = 7
		made.Brightness = 0.5
		made.Shadows = false
		made.Parent = ring
	end
	local glow = light :: PointLight
	glow.Color = color
	glow.Enabled = not occupied
	pad:SetAttribute("Occupied", occupied)
end

-- ── The aura of a squad pad (design/BattleRing_Auras.rbxmx) ──
-- A soldier on a squad pad lights the pad up with the aura of its level's rarity: Common (Lv 1-2) a soft glow,
-- Uncommon (3-4) + sparks, Rare (5-6) + a light pillar, Epic (7) + a ring of runes, Legendary (8) + circling
-- orbs, Mythic (9 and Ascended) + a second rune ring and beams. The client spins the runes and orbs and pulses
-- the glow (the "Runes" / "RunesB" / "Orbs" groups, see Main.client).
local RARITY_BY_LEVEL = { "Common", "Common", "Uncommon", "Uncommon", "Rare", "Rare", "Epic", "Legendary", "Mythic" }

local function setRingAura(pad: Part, cell: Grid.Cell)
	local want = if cell then (if cell.ascended then "Mythic" else RARITY_BY_LEVEL[math.clamp(cell.tier, 1, #RARITY_BY_LEVEL)]) else ""
	local old = pad:FindFirstChild("LevelAura")
	if old and old:GetAttribute("Rarity") == want then
		return
	end
	if old then
		old:Destroy()
	end
	local parts = RingAuras[want]
	if not parts then
		return
	end
	local model = Instance.new("Model")
	model.Name = "LevelAura"
	model:SetAttribute("Rarity", want)
	local base = CFrame.new(pad.Position.X, pad.Position.Y - pad.Size.Y / 2, pad.Position.Z)
	local groups: { [string]: Model } = {}
	for _, data in parts do
		local parent: Instance = model
		if data.group ~= "" then
			local group = groups[data.group]
			if not group then
				group = Instance.new("Model")
				local made = group :: Model
				made.Name = data.group
				made.Parent = model
				groups[data.group] = made
			end
			parent = group :: Model
		end
		local p = Instance.new("Part")
		p.Name = data.name
		p.Size = data.size
		p.CFrame = base * data.cf
		p.Color = data.color
		p.Material = Enum.Material:FromValue(data.material) or Enum.Material.Neon
		p.Transparency = data.transparency or 0
		if data.shape then
			p.Shape = Enum.PartType:FromValue(data.shape) or Enum.PartType.Block
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p:SetAttribute("BaseTransparency", p.Transparency)
		if data.light then
			local light = Instance.new("PointLight")
			light.Color = data.light.color
			light.Brightness = data.light.brightness
			light.Range = data.light.range
			light.Parent = p
		end
		if data.emitter then
			local e = data.emitter
			local emitter = Instance.new("ParticleEmitter")
			emitter.Color = e.color
			emitter.Size = e.size
			emitter.Transparency = e.transparency
			emitter.Lifetime = e.lifetime
			emitter.Speed = e.speed
			emitter.Rate = e.rate
			emitter.LightEmission = e.lightEmission
			emitter.Texture = e.texture
			emitter.EmissionDirection = Enum.NormalId.Top
			emitter.Parent = p
		end
		p.Parent = parent
	end
	model.Parent = pad
end

-- Labels only show when you are close (`maxDistance` studs), never all the time.
local function makeLabel(part: BasePart, height: number, width: number, boxHeight: number?, maxDistance: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(width, boxHeight or 60)
	gui.StudsOffset = Vector3.new(0, height, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = maxDistance or 24
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Parent = gui
	return label
end

local function makeClick(part: BasePart, owner: Player, action: () -> ())
	local detector = Instance.new("ClickDetector")
	detector.MaxActivationDistance = 200
	detector.Parent = part
	detector.MouseClick:Connect(function(clicker)
		if clicker == owner then
			action()
		end
	end)
end

-- Slot id → ground position. Board (1 … BoardSize) is 6x6, the squad (SquadOffset + 1 …) is ONE row of six side
-- by side, its pads further apart (Balance.SquadSpacing). column = x (left to right), row = z (0 = back).
function Plots.slotGround(plot: Plot, id: number): Vector3
	local columns, start, index, spacing = Balance.BoardColumns, Balance.BoardStart, id, Balance.SlotSpacing
	if id > Balance.SquadOffset then
		columns, start, index, spacing = Balance.SquadColumns, Balance.SquadStart, id - Balance.SquadOffset, Balance.SquadSpacing
	end
	local col = (index - 1) % columns
	local row = (index - 1) // columns
	local x = (col - (columns - 1) / 2) * spacing
	return plot.origin + Vector3.new(x, PAD_TOP, start + row * spacing)
end

-- Where the `i`-th of `count` enemies stands: ONE row side by side at z = Balance.EnemyFront, centered on the plot
-- (left to right as seen from your side). A SWARM wave of 18 + a treasure goblin is 126 studs wide, well inside the
-- 160 wide plot. With the PINCER twist the row splits into two groups with a gap in the middle (they come from
-- the sides).
function Plots.enemyGround(plot: Plot, i: number, count: number): Vector3
	local x = (i - (count + 1) / 2) * Balance.SlotSpacing
	if plot.enemyPincer and count >= 2 then
		x += if i <= count / 2 then -Mutators.Defs.pincer.Gap / 2 else Mutators.Defs.pincer.Gap / 2
	end
	return plot.origin + Vector3.new(x, PAD_TOP, Balance.EnemyFront)
end

function Plots.create(index: number, owner: Player, mapId: string): Plot
	local map = Maps.Defs[mapId]
	-- Plots are laid out in a grid so many players fit close together.
	local column = (index - 1) % Balance.PlotsPerRow
	local row = (index - 1) // Balance.PlotsPerRow
	local origin = Vector3.new(column * Balance.PlotSpacingX, ORIGIN_Y, row * Balance.PlotSpacingZ)

	local folder = Instance.new("Folder")
	folder.Name = "Plot_" .. owner.UserId
	folder.Parent = rootFolder()

	-- Layout along z: lobby with spawn + merge board (zMin … -4) → road (-4 … ARENA_START) →
	-- arena with the squad's row, the big round fight platform and the enemies' row (… zMax).
	local zMin, zMax = -68, 228
	local width = 160
	local function floorStrip(name: string, z0: number, z1: number, color: Color3, material: Enum.Material): Part
		return makePart(folder, name, Vector3.new(width, 1, z1 - z0), origin + Vector3.new(0, -0.5, (z0 + z1) / 2), color, material)
	end
	floorStrip("LobbyFloor", zMin, -4, Color3.fromRGB(108, 110, 124), Enum.Material.Slate)
	floorStrip("RoadFloor", -4, ARENA_START, Color3.fromRGB(96, 128, 84), Enum.Material.Grass)
	local arenaFloor = floorStrip("ArenaFloor", ARENA_START, zMax, map.floorColor, map.floorMaterial)

	-- Worn road from the lobby to the arena gate (visual only).
	local road = makePart(folder, "Road", Vector3.new(10, 0.1, ARENA_START + 4), origin + Vector3.new(0, 0.05, (ARENA_START - 4) / 2), map.laneColor, map.laneMaterial)
	road.CanCollide = false

	-- Wooden fence around the plot.
	local function fence(name: string, size: Vector3, offset: Vector3)
		local p = makePart(folder, name, size, origin + offset, map.fenceColor, Enum.Material.Wood)
		p.CanQuery = false
	end
	for _, side in { -1, 1 } do
		fence("Rail", Vector3.new(0.5, 0.6, zMax - zMin), Vector3.new(side * (width / 2 - 0.25), 2.4, (zMin + zMax) / 2))
		for z = zMin, zMax, 14 do
			fence("Post", Vector3.new(0.9, 3.6, 0.9), Vector3.new(side * (width / 2 - 0.25), 1.8, z))
		end
	end
	fence("RailBack", Vector3.new(width, 0.6, 0.5), Vector3.new(0, 2.4, zMin + 0.25))
	fence("RailFront", Vector3.new(width, 0.6, 0.5), Vector3.new(0, 2.4, zMax - 0.25))

	local plot: Plot = {
		index = index,
		map = map,
		arena = nil :: any,
		owner = owner,
		origin = origin,
		folder = folder,
		models = {},
		rendered = {},
		slotPads = {},
		enemies = {},
		enemyModels = {},
		enemyPincer = false,
		previewFolder = nil,
		previewKey = nil,
		arenaFloor = arenaFloor,
		battleZone = nil :: any,
		upgradeZone = nil :: any,
		waveLabel = nil :: any,
		respawn = nil :: any,
	}

	-- The fight arena, one step up, between your squad and the enemies.
	plot.arena = FightArena.build(folder, origin, map.laneColor, map.laneMaterial)

	-- The designed look of the arena: the entrance arch over the gate, fences, torches, banners, training
	-- props at the sides and the ring marks on the fight platform.
	if map.decor then
		ArenaDecor.build(map.decor, folder, origin, plot.arena.center)
	end

	-- Walking up onto the fight arena opens the battle panel (difficulty, wave, start); the server only
	-- accepts a wave start or a wave / difficulty change from someone inside this invisible zone.
	plot.battleZone = plot.arena.zone

	-- Pads: the 6x6 merge board (designed slots) and the six squad pads (holographic rings). Soldiers are moved
	-- by dragging (handled on the client), so the pads have no click handlers.
	local function addPad(id: number, color: Color3): Part
		local ground = Plots.slotGround(plot, id)
		local pad = makePart(folder, "Slot" .. id, Vector3.new(5, PAD_TOP, 5), ground - Vector3.new(0, PAD_TOP / 2, 0), color)
		plot.slotPads[id] = pad
		return pad
	end
	for i = 1, Balance.BoardSize do
		decoratePad(addPad(i, SLOT_COLOR), SLOT_COLOR, false, "", false, true)
	end
	for i = 1, Balance.SquadSize do
		holoPad(addPad(Balance.SquadOffset + i, SQUAD_COLOR), false)
	end

	-- Small signs that show only when you are close.
	-- `station` = the sign of a station you use (altars, level upgrade): higher up, bigger, clear and seen from
	-- 60 studs, so you find them; the other signs are faint and only show from 16 studs.
	local function areaSign(name: string, x: number, z: number, text: string, station: boolean?)
		local part = makePart(folder, name, Vector3.one, origin + Vector3.new(x, 0.5, z), Color3.new(1, 1, 1))
		part.Transparency = 1
		part.CanCollide = false
		part.CanQuery = false
		local l = if station then makeLabel(part, 8.5, 300, 70, 60) else makeLabel(part, 3, 220, 50, 16)
		l.RichText = true
		l.TextTransparency = if station then 0 else 0.25
		l.TextStrokeTransparency = if station then 0.25 else 0.8
		l.Text = text
		if station then
			l.TextScaled = false
			l.TextSize = 26
		end
	end
	areaSign("BoardSign", 0, Balance.BoardStart - 7, '<font size="13" color="#9aa0aa">DRAG TO MERGE</font>\n<font size="26">MERGE BOARD</font>')
	areaSign("SquadSign", 42, Balance.SquadStart, '<font size="13" color="#9aa0aa">THESE SIX FIGHT</font>\n<font size="26">SQUAD</font>')

	-- No summoning altars and no level-upgrade station any more: characters come from wave drops (and the admin
	-- tools). The invisible UpgradeZone part is kept for the code that reads it, far below the ground.
	local upgradeZone = makePart(folder, "UpgradeZone", Vector3.new(1, 1, 1), origin + Vector3.new(0, -500, 0), Color3.new(1, 1, 1))
	upgradeZone.Transparency = 1
	upgradeZone.CanCollide = false
	upgradeZone.CanQuery = false
	upgradeZone.CanTouch = false
	plot.upgradeZone = upgradeZone

	-- Unobtrusive heading above the enemy grid (map, wave, count).
	local waveSign = makePart(folder, "WaveSign", Vector3.new(1, 1, 1), origin + Vector3.new(0, 0.5, Balance.EnemyFront + 2), Color3.new(1, 1, 1))
	waveSign.Transparency = 1
	waveSign.CanCollide = false
	waveSign.CanQuery = false
	plot.waveLabel = makeLabel(waveSign, 9, 200, 80, 45)
	plot.waveLabel.RichText = true
	plot.waveLabel.TextStrokeTransparency = 0.6

	-- Where the player spawns.
	local respawn = Instance.new("SpawnLocation")
	respawn.Name = "Respawn"
	respawn.Size = Vector3.new(6, 1, 6)
	respawn.Position = origin + Vector3.new(0, 0.5, -9) -- your own spawn, right next to the board
	respawn.Anchored = true
	respawn.Neutral = true
	respawn.Duration = 0
	respawn.Transparency = 0.7
	respawn.Color = Color3.fromRGB(240, 240, 240)
	respawn.TopSurface = Enum.SurfaceType.Smooth
	respawn.Parent = folder
	plot.respawn = respawn

	return plot
end

-- Draws the soldiers on the merge board and the squad. Only pads whose soldier changed are
-- rebuilt (a board can hold 36 soldiers). Every model carries its Slot / Class / Tier
-- as attributes, which the client uses for drag and drop.
function Plots.render(plot: Plot, board: Grid.Cells, squad: Grid.Cells, boardSlots: number)
	local function renderCell(id: number, cell: Grid.Cell, baseColor: Color3, locked: boolean, tierMix: number?)
		local pad = plot.slotPads[id]
		if id > Balance.SquadOffset then
			holoPad(pad, cell ~= false) -- a squad pad: bright ring while empty, grey once taken
			pad:SetAttribute("Locked", false)
		elseif locked then
			-- Not bought yet: a dark pad that cannot be used.
			decoratePad(pad, LOCKED_COLOR, false, "LOCKED", true, id <= Balance.BoardSize)
			pad:SetAttribute("Locked", true)
		else
			-- The ring shows the soldier's level color (gold at the maximum); an empty pad keeps its own color.
			local ring = if cell then (if cell.tier >= Units.maxTier(cell.class) then SLOT_GOLD else Levels.color(cell.tier)) else baseColor
			decoratePad(pad, ring, cell ~= false, if cell then "" else "+", false, id <= Balance.BoardSize)
			pad:SetAttribute("Locked", false)
		end

		local signature = if cell then string.format("%s|%d%s", cell.class, cell.tier, if cell.ascended then "A" else "") else ""
		if plot.rendered[id] == signature then
			return
		end
		plot.rendered[id] = signature
		local old = plot.models[id]
		if old then
			old:Destroy()
			plot.models[id] = nil
		end
		if not cell then
			return
		end

		local model = Soldier.build(cell.class, cell.tier, false, nil, cell.ascended)
		local p = Plots.slotGround(plot, id) + Vector3.new(0, Soldier.lift(cell.tier, cell.ascended), 0)
		model:PivotTo(CFrame.lookAt(p, p + Vector3.new(0, 0, 1))) -- facing the enemies
		model:SetAttribute("Slot", id)
		model:SetAttribute("Class", cell.class)
		model:SetAttribute("Tier", cell.tier)
		model:SetAttribute("Ascended", cell.ascended == true)
		model.Parent = plot.folder
		plot.models[id] = model
	end

	for i = 1, Balance.BoardSize do
		renderCell(i, board[i], SLOT_COLOR, not Grid.isBoardUnlocked(i, boardSlots))
	end
	for i = 1, Balance.SquadSize do
		local unit = squad[i]
		renderCell(Balance.SquadOffset + i, unit, SQUAD_COLOR, false, 0.7)
	end
end

-- Drops the squad's models so the next render rebuilds them (after a battle moved and
-- possibly destroyed them).
function Plots.resetSquad(plot: Plot)
	for i = 1, Balance.SquadSize do
		local id = Balance.SquadOffset + i
		local model = plot.models[id]
		if model then
			model:Destroy()
			plot.models[id] = nil
		end
		plot.rendered[id] = nil
	end
end

function Plots.clearEnemies(plot: Plot)
	if plot.previewFolder then
		plot.previewFolder:Destroy()
	end
	plot.previewFolder = nil
	plot.previewKey = nil
	plot.enemies = {}
	plot.enemyModels = {}
end

-- Builds the wave's enemies on their grid so you can see them before pressing Battle.
-- If the preview of this wave is already built, does nothing.
function Plots.showEnemies(plot: Plot, wave: number, difficulty: string)
	local key = wave .. "|" .. difficulty
	if plot.previewKey == key and plot.previewFolder and plot.previewFolder.Parent then
		return
	end
	Plots.clearEnemies(plot)

	local sorted = Waves.get(wave, plot.map)
	-- One row, seen from your side: the boss in the middle, melee and the strongest around it, the shooters on
	-- the flanks. (Sort from the strongest, then deal the slots out from the middle: right, left, right …)
	table.sort(sorted, function(a, b)
		local ka, kb = Enemies.Kinds[a.kind], Enemies.Kinds[b.kind]
		if (ka.boss == true) ~= (kb.boss == true) then
			return ka.boss == true
		end
		if ka.range ~= kb.range then
			return ka.range < kb.range
		end
		return a.tier > b.tier
	end)
	local enemies: { Waves.Enemy } = table.create(#sorted)
	local middle = (#sorted + 1) // 2
	for k, e in sorted do
		local offset = k // 2
		enemies[if k % 2 == 0 then middle + offset else middle - offset] = e
	end
	local twists = Mutators.forWave(wave, plot.map)
	plot.enemyPincer = Mutators.has(twists, "pincer") ~= nil

	local folder = Instance.new("Folder")
	folder.Name = "EnemyPreview"
	folder.Parent = plot.folder

	local models: { Model } = {}
	for i, e in enemies do
		local ground = Plots.enemyGround(plot, i, #enemies)
		local pad = makePart(folder, "EnemyPad", Vector3.new(5, PAD_TOP, 5), ground - Vector3.new(0, PAD_TOP / 2, 0), Color3.fromRGB(120, 55, 55))
		pad.CanQuery = false
		decoratePad(pad, Color3.fromRGB(200, 70, 70), true, "", false) -- the same designed slot, with a red ring

		local model = Enemy.build(e.kind, e.tier)
		local lift = Enemy.lift(e.kind, e.tier)
		if e.champion then
			-- The wave's CHAMPION (a twist): bigger, with a gold-red glow and a tag, so you see it before the fight.
			-- (The battle multiplies the lift the same way and skips the scaling when this attribute is set.)
			local size = Mutators.Defs.champion.Size
			pcall(function()
				model:ScaleTo(model:GetScale() * size)
			end)
			model:SetAttribute("ChampionScaled", true)
			lift *= size
			local glow = Instance.new("Highlight")
			glow.FillColor = Mutators.Defs.champion.color
			glow.FillTransparency = 0.7
			glow.OutlineColor = Color3.fromRGB(255, 90, 60)
			glow.OutlineTransparency = 0
			glow.Parent = model
			local tag = Instance.new("BillboardGui")
			tag.Name = "ChampionTag"
			tag.Size = UDim2.fromOffset(160, 26)
			tag.StudsOffset = Vector3.new(0, lift * 2.2, 0)
			tag.AlwaysOnTop = true
			tag.MaxDistance = 120
			tag.Parent = model.PrimaryPart or model
			local tagText = Instance.new("TextLabel")
			tagText.Size = UDim2.fromScale(1, 1)
			tagText.BackgroundTransparency = 1
			tagText.Font = Enum.Font.GothamBlack
			tagText.TextSize = 20
			tagText.TextColor3 = Mutators.Defs.champion.color
			tagText.TextStrokeTransparency = 0.2
			tagText.Text = "CHAMPION"
			tagText.Parent = tag
		end
		local p = ground + Vector3.new(0, lift, 0)
		model:PivotTo(CFrame.lookAt(p, p - Vector3.new(0, 0, 1))) -- facing the player
		model.Parent = folder
		table.insert(models, model)
	end

	plot.previewFolder = folder
	plot.previewKey = key
	plot.enemies = enemies
	plot.enemyModels = models

	-- Minimal heading: small map name, big wave number, small count, and the wave's twists (Config/Mutators.luau).
	local _, phase = Waves.phase(wave, plot.map)
	local twistLine = ""
	if #twists > 0 then
		local labels: { string } = {}
		for _, def in twists do
			table.insert(labels, def.label)
		end
		local bonus = math.floor(Mutators.coinBonus(twists) * 100 + 0.5)
		twistLine = string.format('\n<font size="13" color="#c9a7ff">TWIST: %s%s</font>', table.concat(labels, " + "), if bonus > 0 then string.format(" · +%d%% COINS", bonus) else "")
	end
	plot.waveLabel.Text = string.format(
		'<font size="13" color="#9aa0aa">%s</font>\n<font size="30">WAVE %d / %d</font>\n<font size="13" color="#9aa0aa">%d %s · %s</font>%s',
		string.upper(phase.name),
		wave,
		plot.map.waves,
		#enemies,
		plot.map.enemyName,
		string.upper(difficulty),
		twistLine
	)
end

local function easeOutBack(x: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

-- Merge effect. Phase 1: orbs stream from the source pad to the target pad in arcs.
-- Phase 2: white flash + colored core, expanding shockwave rings, a light pillar, sparks
-- flying in arcs, the new soldier popping in with an overshoot and a rising "MERGE! T3".
-- Everything gets stronger with the tier. Runs in its own thread; the caller has already
-- rendered the new soldier on `toSlot` (it is hidden until the burst).
function Plots.mergeEffect(plot: Plot, fromGround: Vector3, toSlot: number, tier: number)
	local folder = plot.folder
	local color = Levels.color(tier)
	local bright = color:Lerp(Color3.new(1, 1, 1), 0.55)
	local a = fromGround + Vector3.new(0, 2, 0)
	local ground = Plots.slotGround(plot, toSlot)
	local b = ground + Vector3.new(0, 2.5, 0)
	local strength = math.clamp(tier, 2, 9)
	local model = plot.models[toSlot]
	local lift = Soldier.lift(tier)
	local rng = Random.new()

	-- Keeps the model's feet on the ground while it scales.
	local function place(scale: number)
		if model and model.Parent then
			model:ScaleTo(scale)
			local p = ground + Vector3.new(0, lift * scale, 0)
			model:PivotTo(CFrame.lookAt(p, p + Vector3.new(0, 0, 1)))
		end
	end

	local function neon(shape: Enum.PartType, size: Vector3, position: Vector3, c: Color3, transparency: number): Part
		local p = Instance.new("Part")
		p.Shape = shape
		p.Size = size
		p.Position = position
		p.Color = c
		p.Material = Enum.Material.Neon
		p.Transparency = transparency
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
		return p
	end

	local function fade(part: Part, seconds: number, goal: { [string]: any })
		TweenService:Create(part, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
		Debris:AddItem(part, seconds + 0.1)
	end

	task.spawn(function()
		place(0.05) -- hide the result until the burst

		-- Phase 1: orbs fly in.
		local flyTime, orbCount = 0.3, 10
		local orbs: { Part } = {}
		local side = Vector3.new(-(b - a).Z, 0, (b - a).X)
		side = if side.Magnitude < 0.01 then Vector3.new(1, 0, 0) else side.Unit
		for i = 1, orbCount do
			orbs[i] = neon(Enum.PartType.Ball, Vector3.one * (0.7 + (i % 3) * 0.2), a, if i % 2 == 0 then color else bright, 0)
		end
		local start = os.clock()
		while folder.Parent do
			local elapsed = os.clock() - start
			if elapsed >= flyTime + orbCount * 0.02 then
				break
			end
			for i, orb in orbs do
				local t = math.clamp((elapsed - i * 0.02) / flyTime, 0, 1)
				local e = t * t * (3 - 2 * t)
				local arc = math.sin(math.pi * e)
				local wobble = (if i % 2 == 0 then 1 else -1) * arc * (1.5 + i * 0.15)
				orb.Position = a:Lerp(b, e) + Vector3.new(0, arc * 3, 0) + side * wobble
			end
			RunService.Heartbeat:Wait()
		end
		for _, orb in orbs do
			orb:Destroy()
		end
		if not folder.Parent then
			return
		end

		-- Phase 2: burst.
		fade(neon(Enum.PartType.Ball, Vector3.one * 2, b, Color3.new(1, 1, 1), 0), 0.35, {
			Size = Vector3.one * (8 + strength * 1.5),
			Transparency = 1,
		})
		fade(neon(Enum.PartType.Ball, Vector3.one * 1.5, b, color, 0.2), 0.5, {
			Size = Vector3.one * (5 + strength),
			Transparency = 1,
		})

		local pillar = neon(Enum.PartType.Block, Vector3.new(2.6, 60, 2.6), ground + Vector3.new(0, 30, 0), color, 0.35)
		fade(pillar, 0.7, { Size = Vector3.new(0.2, 60, 0.2), Transparency = 1 })

		for r = 1, 1 + strength // 3 do -- 2 to 3 shockwave rings
			task.delay((r - 1) * 0.09, function()
				if not folder.Parent then
					return
				end
				local ring = neon(Enum.PartType.Cylinder, Vector3.new(0.25, 2, 2), ground + Vector3.new(0, 0.35, 0), if r % 2 == 1 then bright else color, 0.15)
				ring.CFrame = CFrame.new(ring.Position) * CFrame.Angles(0, 0, math.rad(90)) -- lay the cylinder flat
				fade(ring, 0.55, { Size = Vector3.new(0.25, 12 + strength * 2, 12 + strength * 2), Transparency = 1 })
			end)
		end

		-- Rising text.
		local anchor = neon(Enum.PartType.Block, Vector3.one * 0.2, ground + Vector3.new(0, 4 + lift, 0), color, 1)
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(260, 50)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 150
		gui.Parent = anchor
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextSize = 24 + strength * 2
		text.TextColor3 = bright
		text.TextStrokeColor3 = color
		text.TextStrokeTransparency = 0.2
		text.Text = string.format("MERGE!  T%d", tier)
		text.Parent = gui
		TweenService:Create(gui, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 5, 0) }):Play()
		TweenService:Create(text, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}):Play()
		Debris:AddItem(anchor, 1.2)

		-- Sparks fly in arcs and the soldier pops in.
		local sparks: { { part: Part, vel: Vector3 } } = {}
		for i = 1, 12 + strength * 4 do
			local angle = rng:NextNumber() * math.pi * 2
			local speed = 10 + rng:NextNumber() * 12
			local sparkColor = if i % 3 == 0 then Color3.new(1, 1, 1) elseif i % 2 == 0 then color else bright
			sparks[i] = {
				part = neon(Enum.PartType.Ball, Vector3.one * (0.25 + rng:NextNumber() * 0.3), b, sparkColor, 0),
				vel = Vector3.new(math.cos(angle) * speed, 12 + rng:NextNumber() * 14, math.sin(angle) * speed),
			}
		end
		local burstStart = os.clock()
		local last = burstStart
		local life, popTime = 0.9, 0.4
		while folder.Parent do
			local now = os.clock()
			local elapsed = now - burstStart
			local dt = now - last
			last = now
			if elapsed >= life then
				break
			end
			for _, s in sparks do
				s.vel += Vector3.new(0, -45 * dt, 0)
				local pos = s.part.Position + s.vel * dt
				if pos.Y < ground.Y + 0.2 then
					pos = Vector3.new(pos.X, ground.Y + 0.2, pos.Z)
					s.vel = Vector3.zero
				end
				s.part.Position = pos
				s.part.Transparency = (elapsed / life) ^ 2
			end
			place(math.max(0.05, easeOutBack(math.clamp(elapsed / popTime, 0, 1))))
			RunService.Heartbeat:Wait()
		end
		place(1)
		for _, s in sparks do
			s.part:Destroy()
		end
	end)
end

-- Colored beam above the pad on a drop; level 4 and up is bigger and lasts longer.
function Plots.dropEffectAt(plot: Plot, ground: Vector3, level: number)
	local big = level >= 4
	local width = if big then 4 else 2
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(width, 60, width)
	beam.Position = ground + Vector3.new(0, 30, 0)
	beam.Color = Levels.color(level)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.3
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CanTouch = false
	beam.Parent = plot.folder

	local duration = if big then 2.5 else 1.2
	TweenService:Create(beam, TweenInfo.new(duration), { Transparency = 1, Size = Vector3.new(0.2, 60, 0.2) }):Play()
	Debris:AddItem(beam, duration + 0.1)
end

function Plots.dropEffect(plot: Plot, index: number, level: number)
	Plots.dropEffectAt(plot, Plots.slotGround(plot, index), level)
end

-- Is this world position inside the battle zone (up on the raised fight arena)? A wave can only be
-- started, and the wave / difficulty only changed, from there, so the game knows which arena is being
-- configured.
function Plots.isInBattleZone(plot: Plot, position: Vector3): boolean
	local offset = plot.battleZone.CFrame:PointToObjectSpace(position)
	local half = plot.battleZone.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

-- Is this world position inside the level-upgrade station's zone (in the lobby)?
function Plots.isInUpgradeZone(plot: Plot, position: Vector3): boolean
	local offset = plot.upgradeZone.CFrame:PointToObjectSpace(position)
	local half = plot.upgradeZone.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end

-- Is this world position inside the arena (past the gate)? The wave system uses it: you can only
-- change the wave and difficulty while you stand in the arena you are configuring.
function Plots.isInArena(plot: Plot, position: Vector3): boolean
	local offset = plot.arenaFloor.CFrame:PointToObjectSpace(position)
	local half = plot.arenaFloor.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Z) <= half.Z
end

function Plots.destroy(plot: Plot)
	plot.folder:Destroy()
end

return Plots
