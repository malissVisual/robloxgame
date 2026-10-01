--[[
	TRAINING ARENA 1 – props + ready-made arena
	Put this Script into ServerScriptService and press Play:
	it builds "TrainingArena1" in Workspace (floor, fence, entrance arch,
	16 fight slots, training dummies, archery targets, weapon rack, sandbags, hay, barrels,
	crates, banners and torches). Change ARENA_POSITION to move it.

	Every prop is its own Model, so you can also use the builder functions
	(Props.TrainingDummy() etc.) anywhere else.
]]

local ARENA_POSITION = Vector3.new(0, 0, -80)

local C = Color3.fromRGB
local WOOD = C(139, 90, 43)
local DARK_WOOD = C(92, 58, 28)
local STRAW = C(222, 184, 92)
local BURLAP = C(196, 164, 112)
local SAND = C(214, 190, 140)
local DARK_SAND = C(190, 162, 110)
local STONE = C(107, 114, 128)
local IRON = C(75, 85, 99)
local STEEL = C(203, 213, 225)
local RED = C(220, 38, 38)
local WHITE = C(245, 245, 244)
local GOLD = C(251, 191, 36)
local BLACK = C(17, 24, 39)

local M = Enum.Material

local function makePart(parent, size, cf, color, extra)
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = M.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if extra then
		for k, v in pairs(extra) do
			p[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function at(x, y, z)
	return CFrame.new(x, y, z)
end

local function newModel(name)
	local m = Instance.new("Model")
	m.Name = name
	return m
end

-- cylinder helpers (Roblox cylinders point along X)
local function cylY(x, y, z) -- standing up
	return CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.rad(90))
end
local function cylZ(x, y, z) -- facing front/back
	return CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(90), 0)
end
local CYL = { Shape = Enum.PartType.Cylinder }
local function cyl(extra)
	local t = { Shape = Enum.PartType.Cylinder }
	if extra then for k, v in pairs(extra) do t[k] = v end end
	return t
end

local Props = {}

-- Every prop: feet at (0,0,0), front faces -Z.

function Props.EntranceArch()
	local m = newModel("EntranceArch")
	for _, x in ipairs({ -7.5, 7.5 }) do
		makePart(m, Vector3.new(2.6, 1, 2.6), at(x, 0.5, 0), STONE, { Material = M.Slate })
		makePart(m, Vector3.new(1.5, 12, 1.5), at(x, 6.5, 0), DARK_WOOD, { Material = M.WoodPlanks })
	end
	makePart(m, Vector3.new(18, 1.5, 1.8), at(0, 12.2, 0), DARK_WOOD, { Material = M.WoodPlanks })
	local sign = makePart(m, Vector3.new(12, 3, 0.4), at(0, 9.6, -0.9), WOOD, { Material = M.WoodPlanks, Name = "Sign" })
	makePart(m, Vector3.new(12.4, 0.3, 0.45), at(0, 11.15, -0.9), GOLD, { Material = M.Metal })
	makePart(m, Vector3.new(12.4, 0.3, 0.45), at(0, 8.05, -0.9), GOLD, { Material = M.Metal })

	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.Parent = sign
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = GOLD
		label.TextStrokeTransparency = 0
		label.TextStrokeColor3 = BLACK
		label.Text = "TRAINING ARENA 1"
		label.Parent = gui
	end

	-- small red pennants hanging from the beam
	for _, x in ipairs({ -5.5, 5.5 }) do
		makePart(m, Vector3.new(1.4, 2.2, 0.1), at(x, 10.3, -0.1), RED, { Material = M.Fabric })
	end
	return m
end

function Props.TrainingDummy()
	local m = newModel("TrainingDummy")
	makePart(m, Vector3.new(3, 0.4, 3), at(0, 0.2, 0), WOOD, { Material = M.WoodPlanks })
	makePart(m, Vector3.new(0.5, 5.4, 0.5), at(0, 2.9, 0), DARK_WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(2, 2.6, 1.2), at(0, 3.6, 0), STRAW, { Material = M.Fabric })
	makePart(m, Vector3.new(2.05, 0.2, 1.25), at(0, 2.8, 0), DARK_WOOD)
	makePart(m, Vector3.new(2.05, 0.2, 1.25), at(0, 4.4, 0), DARK_WOOD)
	makePart(m, Vector3.new(4.8, 0.5, 0.5), at(0, 4.3, 0), WOOD, { Material = M.Wood }) -- arms
	makePart(m, Vector3.new(0.6, 0.7, 0.6), at(-2.4, 4.3, 0), STRAW, { Material = M.Fabric })
	makePart(m, Vector3.new(0.6, 0.7, 0.6), at(2.4, 4.3, 0), STRAW, { Material = M.Fabric })
	makePart(m, Vector3.new(1.4, 1.4, 1.4), at(0, 5.6, 0), BURLAP, { Material = M.Fabric }) -- head
	-- X eyes
	for _, x in ipairs({ -0.3, 0.3 }) do
		makePart(m, Vector3.new(0.4, 0.08, 0.05), CFrame.new(x, 5.75, -0.72) * CFrame.Angles(0, 0, math.rad(45)), BLACK)
		makePart(m, Vector3.new(0.4, 0.08, 0.05), CFrame.new(x, 5.75, -0.72) * CFrame.Angles(0, 0, math.rad(-45)), BLACK)
	end
	-- target on the chest
	makePart(m, Vector3.new(0.05, 1.3, 1.3), cylZ(0, 3.6, -0.62), RED, CYL)
	makePart(m, Vector3.new(0.05, 0.85, 0.85), cylZ(0, 3.6, -0.65), WHITE, CYL)
	makePart(m, Vector3.new(0.05, 0.4, 0.4), cylZ(0, 3.6, -0.68), RED, CYL)
	return m
end

function Props.ArcheryTarget()
	local m = newModel("ArcheryTarget")
	makePart(m, Vector3.new(0.3, 5.2, 0.3), CFrame.new(-1.3, 2.5, 0.2) * CFrame.Angles(0, 0, math.rad(-12)), DARK_WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(0.3, 5.2, 0.3), CFrame.new(1.3, 2.5, 0.2) * CFrame.Angles(0, 0, math.rad(12)), DARK_WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(0.3, 4.6, 0.3), CFrame.new(0, 2.2, 1.2) * CFrame.Angles(math.rad(25), 0, 0), DARK_WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(0.6, 4.2, 4.2), cylZ(0, 3.8, 0), STRAW, cyl({ Material = M.Fabric }))
	local rings = { { 3.6, WHITE }, { 2.8, RED }, { 2.0, WHITE }, { 1.2, RED }, { 0.5, GOLD } }
	for i, r in ipairs(rings) do
		makePart(m, Vector3.new(0.05, r[1], r[1]), cylZ(0, 3.8, -0.3 - i * 0.02), r[2], CYL)
	end
	-- two arrows stuck in it
	for _, a in ipairs({ Vector2.new(0.5, 0.3), Vector2.new(-0.8, -0.6) }) do
		makePart(m, Vector3.new(0.08, 0.08, 1.6), at(a.X, 3.8 + a.Y, -1.0), WOOD)
		makePart(m, Vector3.new(0.05, 0.3, 0.4), at(a.X, 3.8 + a.Y, -1.7), RED)
	end
	return m
end

function Props.WeaponRack()
	local m = newModel("WeaponRack")
	makePart(m, Vector3.new(6.4, 0.4, 1.6), at(0, 0.2, 0), WOOD, { Material = M.WoodPlanks })
	makePart(m, Vector3.new(0.45, 4.4, 0.45), at(-3, 2.4, 0.3), DARK_WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(0.45, 4.4, 0.45), at(3, 2.4, 0.3), DARK_WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(6.4, 0.4, 0.45), at(0, 4.4, 0.3), DARK_WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(6.4, 0.3, 0.3), at(0, 3.4, 0.1), DARK_WOOD, { Material = M.Wood })
	-- swords
	for _, x in ipairs({ -2.1, -1.1, -0.1 }) do
		makePart(m, Vector3.new(0.22, 0.7, 0.22), at(x, 0.75, -0.1), DARK_WOOD)
		makePart(m, Vector3.new(0.9, 0.18, 0.25), at(x, 1.15, -0.1), IRON, { Material = M.Metal })
		makePart(m, Vector3.new(0.35, 2.6, 0.12), at(x, 2.5, -0.1), STEEL, { Material = M.Metal })
	end
	-- spear
	makePart(m, Vector3.new(0.18, 4.6, 0.18), at(1.0, 2.7, -0.1), WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(0.35, 0.7, 0.1), at(1.0, 5.3, -0.1), STEEL, { Material = M.Metal })
	-- bow
	makePart(m, Vector3.new(0.18, 3.6, 0.18), at(2.2, 2.4, -0.2), WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(0.04, 3.4, 0.04), at(2.2, 2.4, 0.15), WHITE)
	return m
end

function Props.WoodenFence()
	local m = newModel("WoodenFence")
	for _, x in ipairs({ -4.75, 0, 4.75 }) do
		makePart(m, Vector3.new(0.5, 3.6, 0.5), at(x, 1.8, 0), DARK_WOOD, { Material = M.Wood })
	end
	makePart(m, Vector3.new(10, 0.35, 0.25), at(0, 1.2, -0.3), WOOD, { Material = M.WoodPlanks })
	makePart(m, Vector3.new(10, 0.35, 0.25), at(0, 2.7, -0.3), WOOD, { Material = M.WoodPlanks })
	return m
end

function Props.SandbagWall()
	local m = newModel("SandbagWall")
	local bag = C(170, 150, 110)
	local rows = { { -2.4, -0.8, 0.8, 2.4 }, { -1.6, 0, 1.6 }, { -0.8, 0.8 } }
	for r, xs in ipairs(rows) do
		for i, x in ipairs(xs) do
			local shade = (i + r) % 2 == 0 and bag or C(158, 138, 98)
			makePart(m, Vector3.new(1.55, 0.7, 1.1), at(x, 0.35 + (r - 1) * 0.68, 0), shade, { Material = M.Fabric })
		end
	end
	return m
end

function Props.HayBale()
	local m = newModel("HayBale")
	makePart(m, Vector3.new(3, 1.8, 1.8), at(0, 0.9, 0), STRAW, { Material = M.Fabric })
	makePart(m, Vector3.new(0.12, 1.85, 1.85), at(-0.8, 0.9, 0), DARK_WOOD)
	makePart(m, Vector3.new(0.12, 1.85, 1.85), at(0.8, 0.9, 0), DARK_WOOD)
	return m
end

function Props.Barrel()
	local m = newModel("Barrel")
	makePart(m, Vector3.new(3, 2.2, 2.2), cylY(0, 1.5, 0), WOOD, cyl({ Material = M.WoodPlanks }))
	makePart(m, Vector3.new(0.25, 2.3, 2.3), cylY(0, 0.5, 0), IRON, cyl({ Material = M.Metal }))
	makePart(m, Vector3.new(0.25, 2.3, 2.3), cylY(0, 2.5, 0), IRON, cyl({ Material = M.Metal }))
	return m
end

function Props.Crate()
	local m = newModel("Crate")
	makePart(m, Vector3.new(2.5, 2.5, 2.5), at(0, 1.25, 0), WOOD, { Material = M.WoodPlanks })
	for _, z in ipairs({ -1.28, 1.28 }) do
		makePart(m, Vector3.new(2.55, 0.3, 0.1), at(0, 0.15, z), DARK_WOOD)
		makePart(m, Vector3.new(2.55, 0.3, 0.1), at(0, 2.35, z), DARK_WOOD)
		makePart(m, Vector3.new(0.3, 3.2, 0.1), CFrame.new(0, 1.25, z) * CFrame.Angles(0, 0, math.rad(45)), DARK_WOOD)
	end
	return m
end

function Props.BannerFlag()
	local m = newModel("BannerFlag")
	makePart(m, Vector3.new(1.4, 0.5, 1.4), at(0, 0.25, 0), STONE, { Material = M.Slate })
	makePart(m, Vector3.new(0.4, 12, 0.4), at(0, 6.3, 0), IRON, { Material = M.Metal })
	makePart(m, Vector3.new(0.8, 0.8, 0.8), at(0, 12.6, 0), GOLD, { Shape = Enum.PartType.Ball, Material = M.Metal })
	makePart(m, Vector3.new(3.4, 0.25, 0.25), at(0, 11.2, -0.3), IRON, { Material = M.Metal })
	makePart(m, Vector3.new(3, 5, 0.1), at(0, 8.6, -0.35), RED, { Material = M.Fabric })
	makePart(m, Vector3.new(3, 0.3, 0.12), at(0, 6.25, -0.35), GOLD)
	makePart(m, Vector3.new(1.3, 1.3, 0.05), CFrame.new(0, 8.8, -0.42) * CFrame.Angles(0, 0, math.rad(45)), GOLD) -- emblem
	makePart(m, Vector3.new(0.6, 0.6, 0.06), CFrame.new(0, 8.8, -0.43) * CFrame.Angles(0, 0, math.rad(45)), RED)
	return m
end

function Props.Torch()
	local m = newModel("Torch")
	makePart(m, Vector3.new(1.4, 0.6, 1.4), at(0, 0.3, 0), STONE, { Material = M.Slate })
	makePart(m, Vector3.new(0.5, 5, 0.5), at(0, 3.1, 0), DARK_WOOD, { Material = M.Wood })
	makePart(m, Vector3.new(1.3, 0.6, 1.3), at(0, 5.8, 0), IRON, { Material = M.Metal })
	local flame = makePart(m, Vector3.new(0.9, 1.0, 0.9), CFrame.new(0, 6.55, 0) * CFrame.Angles(0, math.rad(45), 0),
		C(249, 115, 22), { Material = M.Neon, CanCollide = false, Name = "Flame" })
	makePart(m, Vector3.new(0.5, 0.9, 0.5), at(0, 7.0, 0), C(253, 224, 71), { Material = M.Neon, CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = C(251, 146, 60)
	light.Brightness = 3
	light.Range = 16
	light.Parent = flame
	return m
end

function Props.ArenaFloor()
	local m = newModel("ArenaFloor")
	makePart(m, Vector3.new(46, 1, 46), at(0, 0.5, 0), SAND, { Material = M.Sand })
	return m
end


------------------------------------------------------------------
-- FIGHT SLOTS
------------------------------------------------------------------
-- state: "Empty" | "Occupied" | "Selected" | "MergeReady" | "Locked" | "Max"
local RARITY_COLORS = {
	Common = C(156, 163, 175), Uncommon = C(74, 222, 128), Rare = C(96, 165, 250),
	Epic = C(192, 132, 252), Legendary = C(251, 146, 60), Mythic = C(248, 113, 113),
}
local SLOT_STYLE = {
	Empty      = { ring = C(107, 114, 128), glow = false, text = nil },
	Occupied   = { ring = RARITY_COLORS.Common, glow = true, text = nil },
	Selected   = { ring = WHITE, glow = true, text = nil },
	MergeReady = { ring = C(74, 222, 128), glow = true, text = "MERGE" },
	Locked     = { ring = C(55, 65, 81), glow = false, text = "LOCKED" },
	Max        = { ring = GOLD, glow = true, text = "MAX" },
}
Props.RARITY_COLORS = RARITY_COLORS

function Props.FightSlot(state, number, rarity, price)
	state = state or "Empty"
	local style = SLOT_STYLE[state]
	local ringColor = style.ring
	if state == "Occupied" and rarity then ringColor = RARITY_COLORS[rarity] end
	local locked = state == "Locked"

	local m = newModel("FightSlot_" .. (number or state))
	makePart(m, Vector3.new(0.5, 5.4, 5.4), cylY(0, 0.25, 0), locked and C(75, 85, 99) or STONE, cyl({ Material = M.Slate, Name = "Base" }))
	local ring = makePart(m, Vector3.new(0.56, 4.8, 4.8), cylY(0, 0.28, 0), ringColor,
		cyl({ Material = style.glow and M.Neon or M.SmoothPlastic, Name = "Ring" }))
	makePart(m, Vector3.new(0.6, 4.2, 4.2), cylY(0, 0.3, 0), locked and DARK_WOOD or WOOD, cyl({ Material = M.WoodPlanks, Name = "Top" }))

	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local x, z = 2.45 * math.cos(a), 2.45 * math.sin(a)
		makePart(m, Vector3.new(0.3, 1.1, 0.3), at(x, 1.05, z), DARK_WOOD, { Material = M.Wood })
		makePart(m, Vector3.new(0.4, 0.3, 0.4), at(x, 1.7, z), locked and IRON or GOLD, { Material = M.Metal })
	end

	-- big number / word painted on top
	local label = makePart(m, Vector3.new(3, 0.05, 3), at(0, 0.63, 0), WHITE, { Transparency = 1, CanCollide = false, Name = "Label" })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.Parent = label
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, 0, 1, 0)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = locked and C(156, 163, 175) or WHITE
	text.TextTransparency = 0.15
	text.TextStrokeTransparency = 0.4
	text.Text = style.text or (state == "Empty" and "+" or tostring(number or ""))
	text.Parent = gui

	if style.glow then
		local light = Instance.new("PointLight")
		light.Color = ringColor
		light.Brightness = 1.5
		light.Range = 8
		light.Parent = ring
	end

	if locked then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 150, 0, 40)
		bb.StudsOffset = Vector3.new(0, 3, 0)
		bb.MaxDistance = 60
		bb.Parent = label
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, 0, 1, 0)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = GOLD
		t.TextStrokeTransparency = 0.2
		t.Text = "UNLOCK $" .. tostring(price or 250)
		t.Parent = bb
	end
	return m
end

-- 4x4 fight-slot grid: slots 1-12 open, 13-16 locked
local LOCK_PRICES = { [13] = 250, [14] = 500, [15] = 1000, [16] = 2500 }
function Props.FightSlots()
	local m = newModel("FightSlots")
	local spacing = 5.8
	for i = 1, 16 do
		local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
		local state = LOCK_PRICES[i] and "Locked" or "Empty"
		local slot = Props.FightSlot(state, i, nil, LOCK_PRICES[i])
		slot.WorldPivot = CFrame.new()
		slot:PivotTo(CFrame.new((col - 1.5) * spacing, 0, (row - 1.5) * spacing))
		slot.Parent = m
	end
	-- wooden border around the grid
	local e = 11.9
	makePart(m, Vector3.new(2 * e + 0.5, 0.4, 0.5), at(0, 0.2, -e), DARK_WOOD, { Material = M.WoodPlanks })
	makePart(m, Vector3.new(2 * e + 0.5, 0.4, 0.5), at(0, 0.2, e), DARK_WOOD, { Material = M.WoodPlanks })
	makePart(m, Vector3.new(0.5, 0.4, 2 * e + 0.5), at(-e, 0.2, 0), DARK_WOOD, { Material = M.WoodPlanks })
	makePart(m, Vector3.new(0.5, 0.4, 2 * e + 0.5), at(e, 0.2, 0), DARK_WOOD, { Material = M.WoodPlanks })
	return m
end

------------------------------------------------------------------
-- ASSEMBLED ARENA
------------------------------------------------------------------
local LAYOUT = {
	-- { prop, x, z, turn (degrees) }   floor top is at y = 1
	{ "ArenaFloor", 0, 0, 0, 0 },
	{ "EntranceArch", 0, -23, 0 },
	{ "WoodenFence", -15, -22.5, 0 }, { "WoodenFence", 15, -22.5, 0 },
	{ "WoodenFence", -15, 22.5, 0 }, { "WoodenFence", -5, 22.5, 0 }, { "WoodenFence", 5, 22.5, 0 }, { "WoodenFence", 15, 22.5, 0 },
	{ "WoodenFence", -22.5, -15, 90 }, { "WoodenFence", -22.5, -5, 90 }, { "WoodenFence", -22.5, 5, 90 }, { "WoodenFence", -22.5, 15, 90 },
	{ "WoodenFence", 22.5, -15, 90 }, { "WoodenFence", 22.5, -5, 90 }, { "WoodenFence", 22.5, 5, 90 }, { "WoodenFence", 22.5, 15, 90 },
	{ "FightSlots", 0, 0, 0 },
	{ "TrainingDummy", -17, -5, -90 }, { "TrainingDummy", -17, 0, -90 }, { "TrainingDummy", -17, 5, -90 },
	{ "ArcheryTarget", 8, 17, 0 }, { "ArcheryTarget", 13, 17, 0 }, { "ArcheryTarget", 18, 17, 0 },
	{ "HayBale", 4, 18, 0 }, { "HayBale", 19.5, 12, 90 },
	{ "WeaponRack", -19.5, -12, -90 },
	{ "SandbagWall", 16, -2, 0 }, { "SandbagWall", 18, -10, 90 },
	{ "Barrel", -19, 12, 0 }, { "Barrel", -16.5, 13, 0 },
	{ "Crate", -18.5, 18.5, 0 }, { "Crate", -15.5, 18.5, 20 },
	{ "BannerFlag", -20, -19, 0 }, { "BannerFlag", 20, -19, 0 },
	{ "Torch", -10, -26, 0 }, { "Torch", 10, -26, 0 }, { "Torch", -20, 20, 0 }, { "Torch", 20, 20, 0 },
}

local function buildArena()
	local arena = newModel("TrainingArena1")
	for _, item in ipairs(LAYOUT) do
		local name, x, z, turn = item[1], item[2], item[3], item[4]
		local y = (name == "ArenaFloor") and 0 or 1
		if name == "Torch" and z < -22.5 then y = 0 end -- outside, on the ground
		local prop = Props[name]()
		prop.WorldPivot = CFrame.new() -- props are built around their feet
		prop:PivotTo(CFrame.new(ARENA_POSITION + Vector3.new(x, y, z)) * CFrame.Angles(0, math.rad(turn), 0))
		prop.Parent = arena
	end
	return arena
end

-- when run inside Roblox, build it
if workspace then
	buildArena().Parent = workspace
end

-- The game script can find slot N as workspace.TrainingArena1.FightSlots.FightSlot_N
-- and recolor its "Ring" part when the state changes (see SLOT_STYLE above).

