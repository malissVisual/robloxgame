--!strict
-- Bottom bar (Buy / Battle with price and timers), toast messages and keyboard input.
-- Everything else is 3D in the world.
--   E = buy a soldier (a popup asks first). A wave is started from the raised fight arena in Arena 1.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Balance = require(Shared:WaitForChild("Config"):WaitForChild("Balance"))
local Units = require(Shared:WaitForChild("Config"):WaitForChild("Units"))
local Levels = require(Shared:WaitForChild("Config"):WaitForChild("Levels"))
local Difficulties = require(Shared:WaitForChild("Config"):WaitForChild("Difficulties"))
local Maps = require(Shared:WaitForChild("Config"):WaitForChild("Maps"))
local Waves = require(Shared:WaitForChild("Config"):WaitForChild("Waves"))
local Enemies = require(Shared:WaitForChild("Config"):WaitForChild("Enemies"))
local Soldier = require(Shared:WaitForChild("Soldier"))
local Grid = require(Shared:WaitForChild("Grid"))
local Spells = require(Shared:WaitForChild("Config"):WaitForChild("Spells"))
local Sounds = require(Shared:WaitForChild("Config"):WaitForChild("Sounds"))
local Achievements = require(Shared:WaitForChild("Config"):WaitForChild("Achievements"))
local SoundService = game:GetService("SoundService")
local Synergy = require(Shared:WaitForChild("Synergy"))

local player = Players.LocalPlayer

local BG = Color3.fromRGB(24, 26, 36)
local BADGE = Color3.fromRGB(46, 50, 68)
local WHITE = Color3.new(1, 1, 1)
local MUTED = Color3.fromRGB(165, 170, 185)
local GOLD = Color3.fromRGB(255, 205, 90)
local RED = Color3.fromRGB(240, 100, 90)
local GREEN = Color3.fromRGB(80, 200, 120)
local ORANGE = Color3.fromRGB(235, 120, 80)

local state = {
	coins = 0,
	cost = 0,
	wave = 1,
	nextWaveIn = 0,
	selectedWave = 1,
	mapWaves = 15,
	map = Maps.First,
	difficulty = Difficulties.Default,
	unlocked = {} :: { [string]: boolean },
	rolling = false,
	battling = false,
	rollTime = 1.4,
	battleLimit = 60,
	board = {} :: { any }, -- the inventory (= merge board) by slot id: false or { class, tier }
	squad = {} :: { any }, -- the equipped soldiers
	boardSlots = 6,
	boardFree = 6,
	squadFree = 6,
	boardMax = 36,
	upgradeCost = 0,
	upgradeMaxed = false,
	startLevel = 1,
	startLevelMax = 5,
	levelCost = 0,
	tierUnlocked = {} :: { [string]: number }, -- per class: the highest merge level bought
	autoFight = false,
	spells = { owned = {} :: { [string]: boolean }, slots = { q = "meteor", e = "heal" } },
	saving = false,
	quests = {} :: { any },
	mapCleared = false,
	streak = 0,
	level = 1,
	xpInto = 0,
	xpNeeded = 60,
	stats = {} :: { [string]: number },
	achievements = {} :: { [string]: boolean },
	title = nil :: string?,
	settings = { volume = 1, numbers = true, arrows = true, music = true } :: { [string]: any },
	battleSpeed = 1,
	bestWave = 1,
	cleared = 0,
	isAdmin = false,
}
local rollStart, battleStart = 0, 0
local stateReceivedAt, cooldownTotal = 0, 1 -- for the next-wave timer in the battle panel

-- ── UI helpers ────────────────────────────────────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "MergeBlades"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

-- On small screens (phones) the whole UI shrinks a little so everything fits; on touch there is no SHIFT,
-- so the spells always aim themselves.
local IS_TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local guiScale = Instance.new("UIScale")
guiScale.Parent = gui
local function fitScreen()
	local size = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	guiScale.Scale = math.clamp(size.Y / 820, 0.6, 1)
end
fitScreen()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScreen)
end

-- Sounds (Config/Sounds.luau): `playSound(name)` plays one at the settings' volume. The server asks for
-- sounds too (the Sfx remote). Music loops when Sounds.Music is set.
local soundVolume = 1
local function playSound(name: string, pitch: number?)
	local def = Sounds.Defs[name]
	if not def or soundVolume <= 0 then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = def.id
	sound.Volume = def.volume * soundVolume
	sound.PlaybackSpeed = def.speed * (pitch or 1)
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(6, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, position: UDim2, size: UDim2, textSize: number, font: Enum.Font, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Position = position
	l.Size = size
	l.Text = text
	l.TextSize = textSize
	l.Font = font
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.ZIndex = 3
	l.Parent = parent
	return l
end

-- The panel look helpers live in ONE table: this script is close to Luau's limit of 200 locals in a chunk,
-- so every new file-level name counts (the same reason the big sections below are do-blocks).
local UI = {}
UI.DARK = Color3.fromRGB(16, 18, 26) -- the dark tiles inside the panel
UI.PAGE_TOP = 84 -- the pages of the left panel start under its title bar and tabs
UI.TAB_ACCENT = { Inventory = GOLD, Characters = Color3.fromRGB(90, 170, 255), Upgrades = Color3.fromRGB(170, 130, 255), Spells = ORANGE }
UI.PANEL_SCALE = 1.15 -- the left panel is drawn this much bigger than it is laid out
UI.panelScale = Instance.new("UIScale")
UI.tab = "Inventory" -- the open tab of the left panel
UI.collapsed = false -- the left panel folded to its title bar (the − / + button, or H)
UI.hidden = false -- the whole panel hidden (the inventory icon on the left edge shows it again)
UI.battleOpen = false -- the battle panel (wave, difficulty, START WAVE) is open: the PLAY button toggles it
UI.LAYOUT_VERSION = 3 -- a saved layout from an older version loses the panel / HUD positions (the defaults changed)
UI.adminHeight = 0 -- how much of the top right corner the admin tools take (the settings gear moves below)
UI.QUESTS = false -- the daily quests panel is switched off for now (the server still tracks them)
UI.ACHIEVEMENTS = false -- the achievements button and list are switched off for now (still tracked)
UI.setCollapsed = function(_on: boolean) end -- set below, once the panel exists

function UI.stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency or 0
	s.Parent = parent
	return s
end

-- A vertical (or rotated) two-color gradient over a frame's background.
function UI.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

-- A small rounded pill with a short text (a stat, a key, a tag).
function UI.chip(parent: Instance, text: string, position: UDim2, size: UDim2, background: Color3, color: Color3, textSize: number?): TextLabel
	local back = Instance.new("Frame")
	back.Position = position
	back.Size = size
	back.BackgroundColor3 = background
	back.BorderSizePixel = 0
	back.ZIndex = 3
	back.Parent = parent
	corner(back, math.floor(size.Y.Offset / 2))
	local text_ = label(back, text, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), textSize or 11, Enum.Font.GothamBold, color)
	text_.TextXAlignment = Enum.TextXAlignment.Center
	text_.ZIndex = 4
	return text_
end

-- The grip dots on a drag handle (the sign that the panel can be moved).
function UI.grip(parent: Instance, x: number, y: number, color: Color3)
	for row = 0, 1 do
		for col = 0, 2 do
			local dot = Instance.new("Frame")
			dot.Position = UDim2.fromOffset(x + col * 5, y + row * 5)
			dot.Size = UDim2.fromOffset(3, 3)
			dot.BackgroundColor3 = color
			dot.BorderSizePixel = 0
			dot.ZIndex = 3
			dot.Parent = parent
			corner(dot, 2)
		end
	end
end

-- A section heading inside a page: a short colored bar and a small caps title.
function UI.section(page: Instance, text: string, y: number, accent: Color3, x: number?)
	local left = x or 12
	local bar_ = Instance.new("Frame")
	bar_.Position = UDim2.fromOffset(left, y + 2)
	bar_.Size = UDim2.fromOffset(3, 12)
	bar_.BackgroundColor3 = accent
	bar_.BorderSizePixel = 0
	bar_.Parent = page
	corner(bar_, 2)
	label(page, text, UDim2.fromOffset(left + 8, y), UDim2.fromOffset(200, 16), 13, Enum.Font.GothamBold, MUTED)
end

-- ── Movable panels ────────────────────────────────────────────────────────
-- Any panel with a handle (its title bar) can be dragged anywhere on the screen. The positions are kept per
-- panel name, saved in the player's settings ("layout", a JSON string) and put back on the next join;
-- RESET LAYOUT in the settings puts every panel back where it started. (One table, see UI above.)

type Movable = { frame: GuiObject, anchor: Vector2, position: UDim2 }
local Layout = {
	movables = {} :: { [string]: Movable },
	saved = {} :: { [string]: any }, -- name → { x, y } in GUI (scaled) pixels, anchor 0,0; "collapsed" = the left panel is folded
	token = 0,
	applied = nil :: string?,
}

function Layout.save()
	Layout.token += 1
	local token = Layout.token
	task.delay(0.6, function()
		if token == Layout.token then
			Layout.saved.collapsed = if UI.collapsed then true else nil
			Layout.saved.hidden = if UI.hidden then true else nil
			Layout.saved.v = UI.LAYOUT_VERSION
			Net.get("SetSetting"):FireServer("layout", HttpService:JSONEncode(Layout.saved))
		end
	end)
end

-- Puts a panel at x, y (GUI pixels, after the UIScale), kept inside the screen.
function Layout.place(name: string, x: number, y: number)
	local movable = Layout.movables[name]
	if not movable then
		return
	end
	local scale = guiScale.Scale
	local screen = gui.AbsoluteSize / scale
	local size = movable.frame.AbsoluteSize / scale
	x = math.clamp(x, 0, math.max(0, screen.X - size.X))
	y = math.clamp(y, 0, math.max(0, screen.Y - size.Y))
	movable.frame.AnchorPoint = Vector2.zero
	movable.frame.Position = UDim2.fromOffset(x, y)
	Layout.saved[name] = { math.floor(x + 0.5), math.floor(y + 0.5) }
end

function Layout.reset()
	for name, movable in Layout.movables do
		movable.frame.AnchorPoint = movable.anchor
		movable.frame.Position = movable.position
		Layout.saved[name] = nil
	end
	Layout.save()
end

function Layout.make(name: string, frame: GuiObject, handle: GuiObject)
	Layout.movables[name] = { frame = frame, anchor = frame.AnchorPoint, position = frame.Position }
	local dragging = false
	local startPointer = Vector2.zero
	local startPosition = Vector2.zero
	handle.Active = true
	handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		startPointer = Vector2.new(input.Position.X, input.Position.Y)
		startPosition = (frame.AbsolutePosition - gui.AbsolutePosition) / guiScale.Scale
		-- From now on the panel is placed by its top-left corner, whatever anchor it had.
		frame.AnchorPoint = Vector2.zero
		frame.Position = UDim2.fromOffset(startPosition.X, startPosition.Y)
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch) then
			return
		end
		local delta = (Vector2.new(input.Position.X, input.Position.Y) - startPointer) / guiScale.Scale
		Layout.place(name, startPosition.X + delta.X, startPosition.Y + delta.Y)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			Layout.save()
		end
	end)
end

-- Puts the panels where the saved layout says (once, when the settings arrive).
function Layout.apply(saved: any)
	if type(saved) ~= "string" or saved == Layout.applied then
		return
	end
	Layout.applied = saved
	if saved == "" then
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, saved)
	if not ok or type(decoded) ~= "table" then
		return
	end
	if decoded.v ~= UI.LAYOUT_VERSION then
		decoded.Panel = nil -- the panel moved to the top of the screen, the HUD to the bottom left: old spots are dropped
		decoded.Hud = nil
	end
	for name, entry in decoded do
		if Layout.movables[name] and type(entry) == "table" and type(entry[1]) == "number" and type(entry[2]) == "number" then
			Layout.place(name, entry[1], entry[2])
		end
	end
	UI.hidden = decoded.hidden == true
end

-- ── Bottom bar ────────────────────────────────────────────────────────────

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -14 - 81 - 10) -- just above the HUD (70 px, drawn at 1.15)
bar.Size = UDim2.fromOffset(444, 64)
bar.BackgroundTransparency = 1
bar.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.Padding = UDim.new(0, 12)
layout.Parent = bar

type Button = { button: TextButton, sub: TextLabel, fill: Frame, title: TextLabel, key: TextLabel }

local function makeButton(keyText: string, titleText: string, accent: Color3, order: number): Button
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.fromOffset(208, 64)
	b.BackgroundColor3 = BG
	b.BackgroundTransparency = 0.1
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Text = ""
	b.ClipsDescendants = true
	b.Parent = bar
	corner(b, 12)

	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Transparency = 0.5
	stroke.Thickness = 1.5
	stroke.Parent = b

	-- Timer fill (grows left to right while something is running).
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = accent
	fill.BackgroundTransparency = 0.6
	fill.BorderSizePixel = 0
	fill.ZIndex = 1
	fill.Parent = b

	local badge = Instance.new("Frame")
	badge.Position = UDim2.fromOffset(12, 12)
	badge.Size = UDim2.fromOffset(40, 40)
	badge.BackgroundColor3 = BADGE
	badge.BorderSizePixel = 0
	badge.ZIndex = 2
	badge.Parent = b
	corner(badge, 8)
	local key = label(badge, keyText, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 24, Enum.Font.GothamBold, WHITE)
	key.TextXAlignment = Enum.TextXAlignment.Center

	local title = label(b, titleText, UDim2.fromOffset(64, 9), UDim2.fromOffset(150, 22), 16, Enum.Font.GothamBold, WHITE)
	local sub = label(b, "", UDim2.fromOffset(64, 32), UDim2.fromOffset(150, 22), 16, Enum.Font.GothamMedium, MUTED)
	return { button = b, sub = sub, fill = fill, title = title, key = key }
end

local buy = makeButton("E", "BUY CHARACTER", GREEN, 1)
local fight = makeButton(">", "FIGHT", ORANGE, 2)
local upgrade = makeButton("^", "MERGE SLOTS", Color3.fromRGB(170, 130, 255), 2)
local autoMerge = makeButton("»", "AUTO MERGE", Color3.fromRGB(90, 170, 255), 2)
local equipBest = makeButton("^", "EQUIP BEST", ORANGE, 3)

-- Top left HUD: the account level (with its experience bar) and the coins.
local hud = Instance.new("Frame")
hud.Name = "Hud"
hud.AnchorPoint = Vector2.new(0, 1)
hud.Position = UDim2.new(0, 14, 1, -14) -- the bottom left corner (the squad bar has the middle, PLAY the right)
hud.Size = UDim2.fromOffset(520, 70)
hud.BackgroundColor3 = BG
hud.BackgroundTransparency = 0.12
hud.BorderSizePixel = 0
hud.Active = true
hud.Parent = gui
local hudScale = Instance.new("UIScale")
hudScale.Scale = 1.15 -- level and coins, big enough to read at a glance
hudScale.Parent = hud
corner(hud, 12)
local hudStroke = Instance.new("UIStroke")
hudStroke.Color = BADGE
hudStroke.Thickness = 2
hudStroke.Parent = hud

local levelBadge = Instance.new("Frame")
levelBadge.Position = UDim2.fromOffset(9, 9)
levelBadge.Size = UDim2.fromOffset(48, 48)
levelBadge.BackgroundColor3 = BADGE
levelBadge.BorderSizePixel = 0
levelBadge.Parent = hud
corner(levelBadge, 10)
local levelBadgeStroke = Instance.new("UIStroke")
levelBadgeStroke.Color = GOLD
levelBadgeStroke.Thickness = 2
levelBadgeStroke.Parent = levelBadge
local levelTag = label(levelBadge, "LV", UDim2.fromOffset(0, 4), UDim2.new(1, 0, 0, 12), 10, Enum.Font.GothamBold, MUTED)
levelTag.TextXAlignment = Enum.TextXAlignment.Center
local levelNumber = label(levelBadge, "1", UDim2.fromOffset(0, 15), UDim2.new(1, 0, 0, 30), 24, Enum.Font.GothamBlack, WHITE)
levelNumber.TextXAlignment = Enum.TextXAlignment.Center

local xpText = label(hud, "", UDim2.fromOffset(70, 9), UDim2.fromOffset(436, 14), 12, Enum.Font.GothamMedium, MUTED)
Layout.make("Hud", hud, hud) -- grab it anywhere, it has no controls
local xpBack = Instance.new("Frame")
xpBack.Position = UDim2.fromOffset(70, 27)
xpBack.Size = UDim2.fromOffset(436, 9)
xpBack.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
xpBack.BorderSizePixel = 0
xpBack.Parent = hud
corner(xpBack, 4)
local xpFill = Instance.new("Frame")
xpFill.Size = UDim2.fromScale(0, 1)
xpFill.BackgroundColor3 = GREEN
xpFill.BorderSizePixel = 0
xpFill.Parent = xpBack
corner(xpFill, 4)

-- The coins (pill): a UIScale pulses it when a coin is picked up.
local pill = Instance.new("Frame")
pill.Position = UDim2.fromOffset(70, 41)
pill.Size = UDim2.fromOffset(436, 22)
pill.BackgroundTransparency = 1
pill.Parent = hud
local coinsLabel = label(pill, "", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 18, Enum.Font.GothamBold, GOLD)
local saveLabel = label(pill, "", UDim2.fromOffset(280, 0), UDim2.fromOffset(156, 22), 11, Enum.Font.GothamMedium, GREEN)
saveLabel.TextXAlignment = Enum.TextXAlignment.Right

-- The battle panel (opened by the PLAY button) is defined further down.
local renderBattlePanel: () -> () = function() end

local autoMergeKey: any = nil
local autoMergeSquad: any = nil

-- The highest merge level bought for a class (you cannot merge it further without the upgrade).
local function capOf(class: string): number
	return state.tierUnlocked[class] or 1
end

-- (The buy button is hidden: soldiers are summoned at the altars in the lobby.)
local function costText(): string
	if state.cost == 0 then
		return "FREE · 1 or 3"
	end
	return string.format("%d coins", state.cost)
end

local function render()
	local now = os.clock()
	local locked = state.rolling or state.battling

	coinsLabel.Text = string.format("Coins  %d", state.coins)
	saveLabel.Text = if state.saving then "progress saved" else "saving OFF"
	saveLabel.TextColor3 = if state.saving then GREEN else RED
	levelNumber.Text = tostring(state.level)
	xpText.Text = string.format("Account level %d · %d/%d XP", state.level, state.xpInto, state.xpNeeded)
	soundVolume = state.settings.volume or 1
	xpFill.Size = UDim2.fromScale(math.clamp(state.xpInto / math.max(1, state.xpNeeded), 0, 1), 1)

	-- Buy: price always visible; the fill runs while the roll animation plays.
	local canAfford = state.coins >= state.cost
	buy.title.TextTransparency = if locked then 0.5 else 0
	if state.rolling then
		buy.sub.Text = "Rolling…"
		buy.sub.TextColor3 = MUTED
		buy.fill.Size = UDim2.fromScale(math.clamp((now - rollStart) / state.rollTime, 0, 1), 1)
	else
		buy.fill.Size = UDim2.fromScale(0, 1)
		if state.battling then
			buy.sub.Text = costText()
			buy.sub.TextColor3 = MUTED
		else
			buy.sub.Text = costText()
			buy.sub.TextColor3 = if canAfford then GOLD else RED
		end
	end

	renderBattlePanel()

	-- Fight: the selected wave and difficulty, or why it cannot start right now.
	local waitLeft = state.nextWaveIn - (now - stateReceivedAt)
	fight.title.TextTransparency = if locked then 0.5 else 0
	if state.battling then
		fight.sub.Text = if state.autoFight then "Battle · AUTO" else "Battle running…"
		fight.sub.TextColor3 = WHITE
	elseif state.rolling then
		fight.sub.Text = "Rolling…"
		fight.sub.TextColor3 = MUTED
	elseif waitLeft > 0 then
		fight.sub.Text = string.format("Next wave in %ds%s", math.ceil(waitLeft), if state.autoFight then " · AUTO" else "")
		fight.sub.TextColor3 = MUTED
	else
		fight.sub.Text = if UI.battleOpen then "Close" else string.format("Wave %d · %s", state.selectedWave, Difficulties.Defs[state.difficulty].label)
		fight.sub.TextColor3 = WHITE
	end
	if locked then
		fight.button.BackgroundColor3 = GREEN:Lerp(BG, 0.6)
	elseif fight.button.BackgroundColor3 == GREEN:Lerp(BG, 0.6) then
		fight.button.BackgroundColor3 = GREEN
	end

	-- Auto merge: how many merges the board could do right now. Equip best: whether it would change anything.
	autoMerge.title.TextTransparency = if locked then 0.5 else 0
	equipBest.title.TextTransparency = if locked then 0.5 else 0
	if autoMergeKey ~= state.board or autoMergeSquad ~= state.squad then
		autoMergeKey = state.board
		autoMergeSquad = state.squad
		local seen: { [string]: number } = {}
		local pairsFound = 0
		local function count(unit: any)
			if unit and unit.tier < capOf(unit.class) then
				local key = unit.class .. "|" .. unit.tier
				seen[key] = (seen[key] or 0) + 1
			end
		end
		for id = 1, Balance.BoardSize do
			if Grid.isBoardUnlocked(id, state.boardSlots) then
				count(state.board[id])
			end
		end
		for i = 1, Balance.SquadSize do
			count(state.squad[i])
		end
		for _, count in seen do
			pairsFound += count // 2
		end
		autoMerge.sub.Text = if pairsFound > 0 then string.format("%d to merge", pairsFound) else "nothing to merge"
		autoMerge.sub.TextColor3 = if pairsFound > 0 then GOLD else MUTED
	end
	equipBest.sub.Text = "strongest squad"
	equipBest.sub.TextColor3 = MUTED

	-- Upgrade: how many merge slots you have, and what the next upgrade costs.
	upgrade.title.TextTransparency = if locked then 0.5 else 0
	upgrade.fill.Size = UDim2.fromScale(0, 1)
	if state.upgradeMaxed then
		upgrade.sub.Text = string.format("%d/%d  (max)", state.boardSlots, state.boardMax)
		upgrade.sub.TextColor3 = MUTED
	else
		upgrade.sub.Text = string.format("%d/%d · %d coins", state.boardSlots, state.boardMax, state.upgradeCost)
		upgrade.sub.TextColor3 = if state.coins >= state.upgradeCost then GOLD else RED
	end
end

RunService.RenderStepped:Connect(render)

-- ── Inventory panel (UI only) ─────────────────────────────────────────────
-- Bought soldiers and wave drops wait here. Drag a card into the 3D world (onto a merge pad or a
-- squad pad) to place it, or drag a soldier from the world back onto this panel to store it.

local pointer = Vector2.zero -- last pointer position (mouse or finger), GUI space

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0)
panel.Position = UDim2.new(0.5, 0, 0, 12) -- the top of the screen, in the middle: clear of the HUD, the dock and PLAY
panel.Size = UDim2.fromOffset(640, 420)
panel.BackgroundColor3 = BG
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel = 0
panel.Active = true -- clicks on the panel never reach the 3D world
panel.Parent = gui
corner(panel, 14)
UI.gradient(panel, Color3.fromRGB(36, 39, 54), Color3.fromRGB(18, 20, 28))
local panelStroke = UI.stroke(panel, Color3.fromRGB(70, 76, 100), 1.5)
-- Bigger: the panel is laid out at 384 x 650 and drawn scaled up (every text and tile grows with it).
UI.panelScale.Scale = UI.PANEL_SCALE
UI.panelScale.Parent = panel

-- The title bar: grab it to move the whole panel anywhere.
do
local header = Instance.new("Frame")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 38)
header.BackgroundColor3 = Color3.fromRGB(44, 48, 68)
header.BackgroundTransparency = 0.15
header.BorderSizePixel = 0
header.Parent = panel
corner(header, 14)
local headerBottom = Instance.new("Frame") -- squares off the bottom corners of the bar
headerBottom.Position = UDim2.new(0, 0, 0, 24)
headerBottom.Size = UDim2.new(1, 0, 0, 14)
headerBottom.BackgroundColor3 = Color3.fromRGB(44, 48, 68)
headerBottom.BackgroundTransparency = 0.15
headerBottom.BorderSizePixel = 0
headerBottom.Parent = header
local headerLine = Instance.new("Frame")
headerLine.Position = UDim2.new(0, 0, 1, 0)
headerLine.Size = UDim2.new(1, 0, 0, 1)
headerLine.BackgroundColor3 = Color3.fromRGB(70, 76, 100)
headerLine.BorderSizePixel = 0
headerLine.Parent = header
UI.grip(header, 14, 14, MUTED)
local headerTitle = label(header, "MERGE BLADES", UDim2.fromOffset(36, 0), UDim2.fromOffset(200, 38), 15, Enum.Font.GothamBlack, WHITE)
local headerHint = label(header, "drag to move · H hides it", UDim2.new(1, -140, 0, 0), UDim2.fromOffset(130, 38), 10, Enum.Font.GothamMedium, MUTED)
headerHint.TextXAlignment = Enum.TextXAlignment.Right
header.MouseEnter:Connect(function()
	headerTitle.TextColor3 = GOLD
	headerHint.TextColor3 = WHITE
end)
header.MouseLeave:Connect(function()
	headerTitle.TextColor3 = WHITE
	headerHint.TextColor3 = MUTED
end)
Layout.make("Panel", panel, header)
end

-- Tabs: Inventory (the squad and the merge board), Soldiers (the index of every class), Upgrades (merge
-- levels) and Spells. A segmented bar; the active tab is lit in its own color.
local TAB_NAMES = { "Inventory", "Characters", "Upgrades", "Spells" }
local pages: { [string]: Frame } = {}
local tabButtons: { [string]: TextButton } = {}

local function makePage(name: string): Frame
	local page = Instance.new("Frame")
	page.Name = name
	page.Position = UDim2.fromOffset(0, UI.PAGE_TOP)
	page.Size = UDim2.new(1, 0, 1, -UI.PAGE_TOP)
	page.BackgroundTransparency = 1
	page.Visible = false
	page.Parent = panel
	pages[name] = page
	return page
end

local function showTab(name: string)
	UI.tab = name
	for tabName, page in pages do
		page.Visible = tabName == name and not UI.collapsed
	end
	for tabName, button in tabButtons do
		local active = tabName == name
		button.BackgroundColor3 = UI.TAB_ACCENT[tabName]:Lerp(BG, 0.3)
		button.BackgroundTransparency = if active then 0 else 1
		button.TextColor3 = if active then WHITE else MUTED
	end
end

do
local tabBar = Instance.new("Frame")
tabBar.Name = "TabBar"
tabBar.Position = UDim2.fromOffset(10, 46)
tabBar.Size = UDim2.fromOffset(620, 32)
tabBar.BackgroundColor3 = UI.DARK
tabBar.BackgroundTransparency = 0.2
tabBar.BorderSizePixel = 0
tabBar.Parent = panel
corner(tabBar, 10)

for i, name in TAB_NAMES do
	local button = Instance.new("TextButton")
	button.Position = UDim2.fromOffset(4 + (i - 1) * 154, 3)
	button.Size = UDim2.fromOffset(152, 26)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.Text = string.upper(name)
	button.Parent = tabBar
	corner(button, 8)
	button.Activated:Connect(function()
		showTab(name)
	end)
	button.MouseEnter:Connect(function()
		if not pages[name].Visible then
			button.TextColor3 = WHITE
		end
	end)
	button.MouseLeave:Connect(function()
		if not pages[name].Visible then
			button.TextColor3 = MUTED
		end
	end)
	tabButtons[name] = button
end

-- Folding: only the title bar stays; the tabs and the open page hide. The panel keeps its top-left corner
-- (it is placed by that corner from then on) and is kept inside the screen when it grows back.
UI.setCollapsed = function(on: boolean)
	UI.collapsed = on
	local corner_ = (panel.AbsolutePosition - gui.AbsolutePosition) / guiScale.Scale
	panel.AnchorPoint = Vector2.zero
	panel.Position = UDim2.fromOffset(corner_.X, corner_.Y)
	tabBar.Visible = not on
	panel.Size = if on then UDim2.fromOffset(640, 38) else UDim2.fromOffset(640, 420)
	panel:SetAttribute("Collapsed", on)
	showTab(UI.tab)
	task.defer(function()
		Layout.place("Panel", corner_.X, corner_.Y) -- clamp (the size changed)
		Layout.save()
	end)
end
end

-- ── Battle squad bar (the bottom of the screen) ──────────────────────────
-- The six soldiers that fight, as they stand on their pads: 3 columns, 2 rows, the FRONT row (nearest to the
-- enemies) on top. Drag cards here from the inventory (or between the two rows) to arrange the squad; a card
-- dragged onto the main panel goes back to the inventory. The bar moves by the grip on top and steps aside
-- during a battle. (Laid out at 284 x 234 and drawn at UI.PANEL_SCALE, like the main panel.)
UI.squadBar = Instance.new("Frame")
UI.squadBar.Name = "SquadBar"
UI.squadBar.AnchorPoint = Vector2.new(0.5, 1)
UI.squadBar.Position = UDim2.new(0.5, 0, 1, -14)
UI.squadBar.Size = UDim2.fromOffset(284, 234)
UI.squadBar.BackgroundColor3 = BG
UI.squadBar.BackgroundTransparency = 0.04
UI.squadBar.BorderSizePixel = 0
UI.squadBar.Active = true
UI.squadBar.Parent = gui
corner(UI.squadBar, 14)
UI.gradient(UI.squadBar, Color3.fromRGB(36, 39, 54), Color3.fromRGB(18, 20, 28))
UI.squadStroke = UI.stroke(UI.squadBar, Color3.fromRGB(70, 76, 100), 1.5)
do
	local squadScale = Instance.new("UIScale")
	squadScale.Scale = UI.PANEL_SCALE
	squadScale.Parent = UI.squadBar
	local squadGrip = Instance.new("Frame")
	squadGrip.Size = UDim2.new(1, 0, 0, 18)
	squadGrip.BackgroundTransparency = 1
	squadGrip.Parent = UI.squadBar
	UI.grip(squadGrip, 142 - 7, 7, MUTED)
	Layout.make("Squad", UI.squadBar, squadGrip)
	local enemySide = label(UI.squadBar, "▲ ENEMIES", UDim2.fromOffset(16, 18), UDim2.fromOffset(252, 16), 12, Enum.Font.GothamBold, RED)
	enemySide.TextXAlignment = Enum.TextXAlignment.Center
	UI.section(UI.squadBar, "BATTLE SQUAD", 212, ORANGE, 16)
end
local squadCount = label(UI.squadBar, "0/6", UDim2.fromOffset(196, 212), UDim2.fromOffset(72, 16), 13, Enum.Font.GothamMedium, MUTED)
squadCount.TextXAlignment = Enum.TextXAlignment.Right
local squadStrip = Instance.new("Frame")
squadStrip.Position = UDim2.fromOffset(16, 38)
squadStrip.Size = UDim2.fromOffset(252, 166)
squadStrip.BackgroundTransparency = 1
squadStrip.Parent = UI.squadBar
local squadLayout = Instance.new("UIGridLayout")
squadLayout.CellSize = UDim2.fromOffset(80, 80)
squadLayout.CellPadding = UDim2.fromOffset(6, 6)
squadLayout.SortOrder = Enum.SortOrder.LayoutOrder
squadLayout.Parent = squadStrip

-- Inventory page: the inventory, full width (the squad has its own bar at the bottom of the screen). The
-- inventory IS the 3D merge board: the same soldiers stand on the pads in the lobby.
local inventoryPage = makePage("Inventory")

UI.section(inventoryPage, "INVENTORY", 0, GOLD, 16)
local inventoryCount = label(inventoryPage, "0/6", UDim2.fromOffset(556, 0), UDim2.fromOffset(72, 16), 13, Enum.Font.GothamMedium, MUTED)
inventoryCount.TextXAlignment = Enum.TextXAlignment.Right

local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(16, 20)
scroll.Size = UDim2.fromOffset(614, 200)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = MUTED
scroll.ScrollingDirection = Enum.ScrollingDirection.Y
scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
scroll.CanvasSize = UDim2.new()
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = inventoryPage

local gridLayout = Instance.new("UIGridLayout")
gridLayout.CellSize = UDim2.fromOffset(54, 54)
gridLayout.CellPadding = UDim2.fromOffset(6, 6)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.Parent = scroll

-- MERGE SLOTS lives here, under the inventory: it buys more usable pads of the merge board.
-- AUTO MERGE and EQUIP BEST sit side by side just under the inventory, MERGE SLOTS below them.
local function moveIntoInventory(b: Button, x: number, y: number, width: number, height: number, compact: boolean)
	b.button.Parent = inventoryPage
	b.button.Position = UDim2.fromOffset(x, y)
	b.button.Size = UDim2.fromOffset(width, height)
	if compact then
		local badge = b.key.Parent :: Frame
		badge.Visible = false
		b.title.Position = UDim2.fromOffset(8, 6)
		b.title.Size = UDim2.fromOffset(width - 12, 20)
		b.title.TextSize = 13
		b.sub.Position = UDim2.fromOffset(8, 27)
		b.sub.Size = UDim2.fromOffset(width - 12, 18)
		b.sub.TextSize = 11
	end
end
moveIntoInventory(autoMerge, 16, 230, 300, 44, true)
moveIntoInventory(equipBest, 330, 230, 300, 44, true)

-- ── The dock on the left edge of the screen ──────────────────────────────
-- Four square icons, one per tab of the panel. An icon opens the panel on its tab; the icon of the open tab
-- hides the panel again. The dock moves by the grip on top. (PLAY has its own dock on the right edge, below.)
do
local DOCK_TILE = 64
local DOCK_STEP = 72
local dock = Instance.new("Frame")
dock.Name = "Dock"
dock.AnchorPoint = Vector2.new(0, 0.5)
dock.Position = UDim2.new(0, 14, 0.5, 0)
dock.Size = UDim2.fromOffset(76, 18 + 4 * DOCK_STEP)
dock.BackgroundColor3 = BG
dock.BackgroundTransparency = 0.06
dock.BorderSizePixel = 0
dock.Active = true
dock.Parent = gui
corner(dock, 16)
UI.gradient(dock, Color3.fromRGB(36, 39, 54), Color3.fromRGB(18, 20, 28))
UI.stroke(dock, Color3.fromRGB(70, 76, 100), 1.5)
local dockGrip = Instance.new("Frame")
dockGrip.Size = UDim2.new(1, 0, 0, 18)
dockGrip.BackgroundTransparency = 1
dockGrip.Parent = dock
UI.grip(dockGrip, 31, 7, MUTED)
Layout.make("Dock", dock, dockGrip)

type DockIcon = { button: TextButton, stroke: UIStroke, parts: { Frame }, tag: TextLabel, accent: Color3 }
local icons: { [string]: DockIcon } = {}

-- A small drawing piece inside a tile.
local function piece(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, radius: number, rotation: number?): Frame
	local f = Instance.new("Frame")
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rotation or 0
	f.ZIndex = 2
	f.Parent = parent
	corner(f, radius)
	return f
end

-- One tile: `draw` returns the pieces that take the tab's color (the rest stays dark).
local function tile(index: number, name: string, tag: string, draw: (TextButton) -> { Frame })
	local accent = UI.TAB_ACCENT[name]
	local button = Instance.new("TextButton")
	button.Name = "Dock_" .. name
	button.Position = UDim2.fromOffset(6, 18 + (index - 1) * DOCK_STEP)
	button.Size = UDim2.fromOffset(DOCK_TILE, DOCK_TILE)
	button.BackgroundColor3 = UI.DARK
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = dock
	corner(button, 12)
	local buttonStroke = UI.stroke(button, accent, 2, 0.65)
	local parts = draw(button)
	local tagLabel = label(button, tag, UDim2.fromOffset(0, 47), UDim2.new(1, 0, 0, 13), 9, Enum.Font.GothamBlack, MUTED)
	tagLabel.TextXAlignment = Enum.TextXAlignment.Center
	button.MouseEnter:Connect(function()
		buttonStroke.Transparency = 0
	end)
	button.MouseLeave:Connect(function()
		buttonStroke.Transparency = if not UI.hidden and UI.tab == name then 0.1 else 0.65
	end)
	button.Activated:Connect(function()
		if UI.hidden or UI.tab ~= name then
			UI.hidden = false
			UI.battleOpen = false -- the panel and the battle panel are never open together
			showTab(name)
		else
			UI.hidden = true
		end
		Layout.save()
	end)
	icons[name] = { button = button, stroke = buttonStroke, parts = parts, tag = tagLabel, accent = accent }
end

tile(1, "Inventory", "INV", function(b) -- a bag
	local handle = piece(b, 26, 5, 12, 10, BG, 5)
	handle.BackgroundTransparency = 1
	local handleStroke = UI.stroke(handle, GOLD, 2)
	local flap = piece(b, 18, 13, 28, 10, GOLD, 4)
	local body = piece(b, 18, 21, 28, 22, GOLD, 6)
	piece(b, 29, 24, 6, 6, BG, 3)
	-- (the handle's stroke follows the body's color each frame, see below)
	handle:SetAttribute("StrokeOnly", true)
	return { flap, body, handle }
end)
tile(2, "Characters", "CHAR", function(b) -- a little figure
	local head = piece(b, 25, 7, 14, 14, GOLD, 7)
	local torso = piece(b, 22, 23, 20, 15, GOLD, 5)
	local legL = piece(b, 23, 39, 8, 6, GOLD, 2)
	local legR = piece(b, 33, 39, 8, 6, GOLD, 2)
	return { head, torso, legL, legR }
end)
tile(3, "Upgrades", "UPG", function(b) -- an arrow up
	local head = piece(b, 24, 9, 16, 16, GOLD, 3, 45)
	local stem = piece(b, 29, 22, 6, 22, GOLD, 3)
	piece(b, 24, 24, 16, 8, UI.DARK, 0) -- cuts the lower half of the rotated square into an arrow head
	return { head, stem }
end)
tile(4, "Spells", "SPELL", function(b) -- a diamond and two sparks
	local gem = piece(b, 22, 14, 20, 20, GOLD, 4, 45)
	piece(b, 28, 20, 8, 8, UI.DARK, 2, 45)
	local sparkA = piece(b, 13, 11, 5, 5, GOLD, 2, 45)
	local sparkB = piece(b, 47, 31, 5, 5, GOLD, 2, 45)
	return { gem, sparkA, sparkB }
end)

-- ── PLAY: the big green button on the right edge ─────────────────────────
-- The old FIGHT button, now a big green PLAY in its own little dock at the bottom right (a grip on top, so it
-- moves like the others). It opens the battle panel (wave, difficulty, START WAVE); the main panel hides while
-- that is open and comes back when it closes.
do
	local PLAY_W, PLAY_H = 176, 156
	local playDock = Instance.new("Frame")
	playDock.Name = "PlayDock"
	playDock.AnchorPoint = Vector2.new(1, 1)
	playDock.Position = UDim2.new(1, -14, 1, -14)
	playDock.Size = UDim2.fromOffset(PLAY_W + 12, 18 + PLAY_H + 6)
	playDock.BackgroundColor3 = BG
	playDock.BackgroundTransparency = 0.06
	playDock.BorderSizePixel = 0
	playDock.Active = true
	playDock.Parent = gui
	corner(playDock, 16)
	UI.gradient(playDock, Color3.fromRGB(36, 39, 54), Color3.fromRGB(18, 20, 28))
	UI.stroke(playDock, Color3.fromRGB(70, 76, 100), 1.5)
	local playGrip = Instance.new("Frame")
	playGrip.Size = UDim2.new(1, 0, 0, 18)
	playGrip.BackgroundTransparency = 1
	playGrip.Parent = playDock
	UI.grip(playGrip, (PLAY_W + 12) / 2 - 7, 7, MUTED)
	Layout.make("Play", playDock, playGrip)

	fight.button.Parent = playDock
	fight.button.Position = UDim2.fromOffset(6, 18)
	fight.button.Size = UDim2.fromOffset(PLAY_W, PLAY_H)
	fight.button.BackgroundColor3 = GREEN
	fight.button.BackgroundTransparency = 0
	local playStroke = fight.button:FindFirstChildOfClass("UIStroke")
	if playStroke then
		playStroke.Color = Color3.fromRGB(170, 245, 195)
		playStroke.Transparency = 0.15
		playStroke.Thickness = 2.5
	end
	fight.fill.BackgroundColor3 = WHITE
	fight.fill.BackgroundTransparency = 0.8
	-- A big ">" in a darker green square, PLAY under it, then the wave and difficulty.
	local badge = fight.key.Parent :: Frame
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, 12)
	badge.Size = UDim2.fromOffset(58, 58)
	badge.BackgroundColor3 = Color3.fromRGB(28, 110, 66)
	fight.key.TextSize = 40
	fight.title.Text = "PLAY"
	fight.title.Position = UDim2.fromOffset(0, 74)
	fight.title.Size = UDim2.new(1, 0, 0, 40)
	fight.title.TextSize = 34
	fight.title.Font = Enum.Font.GothamBlack
	fight.title.TextXAlignment = Enum.TextXAlignment.Center
	fight.sub.Position = UDim2.fromOffset(6, 116)
	fight.sub.Size = UDim2.new(1, -12, 0, 34)
	fight.sub.TextSize = 12
	fight.sub.TextWrapped = true
	fight.sub.TextXAlignment = Enum.TextXAlignment.Center
	fight.sub.TextYAlignment = Enum.TextYAlignment.Top
	fight.button.MouseEnter:Connect(function()
		if not (state.rolling or state.battling) then
			fight.button.BackgroundColor3 = Color3.fromRGB(110, 225, 150)
		end
	end)
	fight.button.MouseLeave:Connect(function()
		fight.button.BackgroundColor3 = if state.rolling or state.battling then GREEN:Lerp(BG, 0.6) else GREEN
	end)
end

RunService.RenderStepped:Connect(function()
	for name, icon in icons do
		local active = not UI.hidden and UI.tab == name
		local color = if active then icon.accent else MUTED
		icon.button.BackgroundColor3 = if active then icon.accent:Lerp(BG, 0.72) else UI.DARK
		icon.stroke.Color = icon.accent
		if not active then
			icon.stroke.Transparency = 0.65
		end
		icon.tag.TextColor3 = if active then WHITE else MUTED
		for _, part in icon.parts do
			if part:GetAttribute("StrokeOnly") then
				local s = part:FindFirstChildOfClass("UIStroke")
				if s then
					s.Color = color
				end
			else
				part.BackgroundColor3 = color
			end
		end
	end
end)
end
upgrade.button.Visible = false -- merge slots are bought with the "+" card at the end of the inventory

-- The "+" card after the last slot of the inventory: buys Balance.BoardUpgradeStep more merge slots.
local addSlotCard = Instance.new("TextButton")
addSlotCard.Name = "AddSlots"
addSlotCard.LayoutOrder = Balance.BoardSize + 1
addSlotCard.BackgroundColor3 = BG:Lerp(BADGE, 0.5)
addSlotCard.BorderSizePixel = 0
addSlotCard.AutoButtonColor = false
addSlotCard.Text = ""
addSlotCard.Parent = scroll
corner(addSlotCard, 8)
local addSlotStroke = Instance.new("UIStroke")
addSlotStroke.Color = Color3.fromRGB(170, 130, 255)
addSlotStroke.Thickness = 2
addSlotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
addSlotStroke.Parent = addSlotCard
local addSlotPlus = label(addSlotCard, "+", UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 40, Enum.Font.GothamBlack, Color3.fromRGB(190, 160, 255))
addSlotPlus.TextXAlignment = Enum.TextXAlignment.Center
addSlotPlus.TextYAlignment = Enum.TextYAlignment.Center
local addSlotAffordable = false
-- The "+" stands still. Hover: the card lights up in its violet, the plus turns white and the outline shows.
local function styleAddSlot(hovered: boolean)
	addSlotCard.BackgroundColor3 = if hovered then Color3.fromRGB(78, 62, 118) else BG:Lerp(BADGE, 0.5)
	addSlotStroke.Transparency = if hovered then 0 else 0.6
	addSlotPlus.TextColor3 = if hovered then Color3.new(1, 1, 1) elseif addSlotAffordable then Color3.fromRGB(190, 160, 255) else Color3.fromRGB(120, 110, 150)
end
styleAddSlot(false)
local addSlotHovered = false
addSlotCard.MouseEnter:Connect(function()
	addSlotHovered = true
	styleAddSlot(true)
end)
addSlotCard.MouseLeave:Connect(function()
	addSlotHovered = false
	styleAddSlot(false)
end)
-- A click asks first and shows the price (the popup exists further down: requestSlots is set there).
local requestSlots: () -> () = function() end
addSlotCard.Activated:Connect(function()
	playSound("click")
	requestSlots()
end)

-- The mouse wheel over the inventory always scrolls it (the camera must not zoom instead).
UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel or not scroll.Visible or not inventoryPage.Visible then
		return
	end
	local p, s = scroll.AbsolutePosition, scroll.AbsoluteSize
	local at = UserInputService:GetMouseLocation() - Vector2.new(0, 36) -- GUI inset of the top bar
	if at.X < p.X or at.X > p.X + s.X or at.Y < p.Y or at.Y > p.Y + s.Y then
		return
	end
	local maxY = math.max(0, scroll.AbsoluteCanvasSize.Y - s.Y)
	scroll.CanvasPosition = Vector2.new(0, math.clamp(scroll.CanvasPosition.Y - input.Position.Z * 60, 0, maxY))
end)

-- Is the pointer over `frame` (a visible one)?
local function pointerOver(frame: GuiObject): boolean
	if not frame.Visible then
		return false
	end
	local p, s = frame.AbsolutePosition, frame.AbsoluteSize
	return pointer.X >= p.X and pointer.X <= p.X + s.X and pointer.Y >= p.Y and pointer.Y <= p.Y + s.Y
end

-- Over the main panel (store a soldier) or the squad bar (equip it): both take dragged soldiers.
local function pointerOverPanel(): boolean
	return pointerOver(panel) or pointerOver(UI.squadBar)
end

local function setPanelHighlight(on: boolean)
	panelStroke.Color = if on and pointerOver(panel) then GOLD else BADGE
	UI.squadStroke.Color = if on and pointerOver(UI.squadBar) then GOLD else Color3.fromRGB(70, 76, 100)
end

-- A soldier card: a small 3D view of the soldier (ViewportFrame) on a dark tile with an outline
-- in the level color and the level.

-- Puts a 3D soldier into a ViewportFrame, seen from a three-quarter front angle.
local function fillViewport(view: ViewportFrame, unit: { class: string, tier: number }): Model
	for _, child in view:GetChildren() do
		if child:IsA("Model") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	local model = Soldier.build(unit.class, unit.tier, false, true, (unit :: any).ascended)
	model.Parent = view
	local scale = Soldier.scale(unit.tier)
	local target = Vector3.new(0, 2.7 * scale, 0)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(target + Vector3.new(4, 2, -10.5) * scale, target) -- the soldier's front is -Z
	camera.Parent = view
	view.CurrentCamera = camera
	return model
end

local function styleCard(card: Frame, unit: { class: string, tier: number })
	local levelColor = Levels.color(unit.tier)
	card.BackgroundColor3 = Units.Classes[unit.class].color:Lerp(BG, 0.65)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = levelColor
	end
	local ascended = (unit :: any).ascended == true
	local tier = card:FindFirstChild("Tier") :: TextLabel?
	if tier then
		tier.Text = if ascended then "★" else Levels.label(unit.tier)
		tier.TextColor3 = if ascended then Color3.fromRGB(255, 215, 90) else levelColor
	end
	if stroke and ascended then
		stroke.Color = Color3.fromRGB(255, 215, 90)
	end
	-- Rebuild the 3D view only when the soldier actually changed.
	local signature = string.format("%s|%d%s", unit.class, unit.tier, if ascended then "A" else "")
	if card:GetAttribute("Sig") ~= signature then
		card:SetAttribute("Sig", signature)
		local view = card:FindFirstChild("View") :: ViewportFrame?
		if view then
			fillViewport(view, unit)
		end
	end
end

local function makeCard(): Frame
	local card = Instance.new("Frame")
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	corner(card, 8)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Parent = card

	local view = Instance.new("ViewportFrame")
	view.Name = "View"
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(175, 175, 185)
	view.LightColor = Color3.new(1, 1, 1)
	view.ZIndex = 1
	view.Parent = card

	local tier = label(card, "", UDim2.new(0, 0, 1, -18), UDim2.new(1, -5, 0, 16), 13, Enum.Font.GothamBold, GOLD)
	tier.Name = "Tier"
	tier.TextXAlignment = Enum.TextXAlignment.Right
	return card
end

-- Slot ids: the inventory is the merge board (ids 1 … BoardSize); the equipped soldiers are the
-- squad (ids SquadOffset + 1 …). The board unlocks front row first, so the inventory grid is
-- ordered by that rank (Grid.boardRank) and only the first `boardSlots` tiles exist.
local rankToId: { [number]: number } = {}
for id = 1, Balance.BoardSize do
	rankToId[Grid.boardRank(id)] = id
end

local slotCards: { [number]: Frame } = {} -- one card (tile) per slot id, board and squad

local function unitAt(id: number): { class: string, tier: number }?
	local cell = if id > Balance.SquadOffset then state.squad[id - Balance.SquadOffset] else state.board[id]
	if cell then
		return cell
	end
	return nil
end

-- An empty tile: dark, no soldier.
local function styleEmptyCard(card: Frame)
	card.BackgroundColor3 = BG:Lerp(BADGE, 0.3)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = BADGE
		stroke.Thickness = 2
	end
	local tier = card:FindFirstChild("Tier") :: TextLabel?
	if tier then
		tier.Text = ""
	end
	if card:GetAttribute("Sig") ~= "" then
		card:SetAttribute("Sig", "")
		local view = card:FindFirstChild("View") :: ViewportFrame?
		if view then
			for _, child in view:GetChildren() do
				child:Destroy()
			end
		end
	end
end

-- Filled in below, after the 3D drag helpers exist.
local openCardPopup: (id: number) -> () = function() end
local beginCardDrag: (id: number, input: InputObject) -> () = function() end

local function ensureCard(id: number, parent: Instance, size: UDim2?, order: number): Frame
	local existing = slotCards[id]
	if existing then
		return existing
	end
	local card = makeCard()
	card.LayoutOrder = order
	if size then
		card.Size = size
	end
	card.Parent = parent
	card.Active = true
	-- Minimal hover: a thin light veil and a stronger outline (the outline keeps the card's own color: the level
	-- color of its soldier, or the bonus tint of a squad slot).
	local veil = Instance.new("Frame")
	veil.Name = "HoverVeil"
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Color3.new(1, 1, 1)
	veil.BackgroundTransparency = 1
	veil.BorderSizePixel = 0
	veil.ZIndex = 4
	veil.Parent = card
	corner(veil, 8)
	card.MouseEnter:Connect(function()
		veil.BackgroundTransparency = 0.9
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = 3
		end
	end)
	card.MouseLeave:Connect(function()
		veil.BackgroundTransparency = 1
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Thickness = 2
		end
	end)
	card.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginCardDrag(id, input) -- a click opens the equip popup, a drag merges
		end
	end)
	slotCards[id] = card
	return card
end

local function renderInventory()
	-- The inventory (merge board) tiles, in unlock order.
	local filled = 0
	for rank = 1, Balance.BoardSize do
		local id = rankToId[rank]
		if rank <= state.boardSlots then
			local card = ensureCard(id, scroll, nil, rank)
			local unit = unitAt(id)
			if unit then
				filled += 1
				styleCard(card, unit)
			else
				styleEmptyCard(card)
			end
			card.BackgroundTransparency = 0
		elseif slotCards[id] then
			slotCards[id]:Destroy()
			slotCards[id] = nil
		end
	end
	inventoryCount.Text = string.format("%d/%d", filled, state.boardSlots)
	addSlotCard.Visible = not state.upgradeMaxed
	if not state.upgradeMaxed then
		addSlotAffordable = state.coins >= state.upgradeCost
		styleAddSlot(addSlotHovered)
	end

	-- The equipped squad.
	local equipped = 0
	for i = 1, Balance.SquadSize do
		local id = Balance.SquadOffset + i
		-- The front row (the last one) is drawn on top, like looking at the arena from your side.
		local row = (i - 1) // Balance.SquadColumns
		local order = (Balance.SquadSize // Balance.SquadColumns - 1 - row) * Balance.SquadColumns + (i - 1) % Balance.SquadColumns + 1
		local card = ensureCard(id, squadStrip, nil, order)
		local unit = unitAt(id)
		if unit then
			equipped += 1
			styleCard(card, unit)
		else
			styleEmptyCard(card)
		end
		card.BackgroundTransparency = 0
	end
	squadCount.Text = string.format("%d/%d", equipped, Balance.SquadSize)
end

-- The card under the pointer (a merge target), optionally not counting `exceptId`.
local function cardIdAtPointer(exceptId: number?): number?
	for id, card in slotCards do
		if id ~= exceptId and card.Parent then
			local p, s = card.AbsolutePosition, card.AbsoluteSize
			if pointer.X >= p.X and pointer.X <= p.X + s.X and pointer.Y >= p.Y and pointer.Y <= p.Y + s.Y then
				if card.Parent == scroll then
					-- inventory tiles are clipped by the scroll frame
					local sp, ss = scroll.AbsolutePosition, scroll.AbsoluteSize
					if pointer.Y < sp.Y or pointer.Y > sp.Y + ss.Y then
						continue
					end
				end
				return id
			end
		end
	end
	return nil
end

-- Marks the card that a drop would land on (gold = merge, blue = swap, white = move).
local markedCardId: number? = nil
local function markCard(id: number?, color: Color3)
	if markedCardId and markedCardId ~= id then
		local previous = slotCards[markedCardId]
		local stroke = previous and previous:FindFirstChildOfClass("UIStroke")
		if stroke then
			local unit = unitAt(markedCardId)
			stroke.Color = if unit then Levels.color(unit.tier) else BADGE
			stroke.Thickness = 2
		end
		markedCardId = nil
	end
	if id then
		local card = slotCards[id]
		local stroke = card and card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = color
			stroke.Thickness = 4
		end
		markedCardId = id
	end
end

-- The Soldiers and Upgrades sections below live in do-blocks (a Luau function may hold only 200 local
-- variables); these two are filled in there and called from the state handler.
local renderSoldiers: () -> () = function() end
local renderLevels: () -> () = function() end
local renderSpells: () -> () = function() end

-- ── Soldiers tab: the index of every class (unlocked ones and how to unlock the rest) ────
do

local soldiersPage = makePage("Characters")
UI.section(soldiersPage, "YOUR CHARACTERS", 0, UI.TAB_ACCENT.Characters)
local unlockedCount = label(soldiersPage, "", UDim2.fromOffset(552, 0), UDim2.fromOffset(72, 16), 13, Enum.Font.GothamMedium, MUTED)
unlockedCount.TextXAlignment = Enum.TextXAlignment.Right

local soldiersScroll = Instance.new("ScrollingFrame")
soldiersScroll.Position = UDim2.fromOffset(10, 24)
soldiersScroll.Size = UDim2.new(1, -20, 1, -34)
soldiersScroll.BackgroundTransparency = 1
soldiersScroll.BorderSizePixel = 0
soldiersScroll.ScrollBarThickness = 4
soldiersScroll.ScrollBarImageColor3 = MUTED
soldiersScroll.CanvasSize = UDim2.new()
soldiersScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
soldiersScroll.Parent = soldiersPage

local soldiersLayout = Instance.new("UIGridLayout") -- two columns of class cards
soldiersLayout.CellSize = UDim2.fromOffset(308, 86)
soldiersLayout.CellPadding = UDim2.fromOffset(8, 6)
soldiersLayout.SortOrder = Enum.SortOrder.LayoutOrder
soldiersLayout.Parent = soldiersScroll

type SoldierRow = { frame: Frame, stroke: UIStroke, overlay: Frame, status: TextLabel }
local soldierRows: { [string]: SoldierRow } = {}

-- One row per class: the 3D soldier on a dark tile, the name, the stats as pills, the passive and whether
-- the class is unlocked. A locked class is dimmed with LOCKED over its tile.
for i, class in Units.ClassList do
	local def = Units.Classes[class]
	local row = Instance.new("Frame")
	row.LayoutOrder = i
	row.Size = UDim2.fromOffset(308, 86)
	row.BackgroundColor3 = def.color:Lerp(BG, 0.8)
	row.BorderSizePixel = 0
	row.Parent = soldiersScroll
	corner(row, 10)
	local rowStroke = UI.stroke(row, def.color, 1.5, 0.4)

	local accentBar = Instance.new("Frame")
	accentBar.Position = UDim2.fromOffset(0, 10)
	accentBar.Size = UDim2.fromOffset(4, 66)
	accentBar.BackgroundColor3 = def.color
	accentBar.BorderSizePixel = 0
	accentBar.Parent = row
	corner(accentBar, 2)

	local tile = Instance.new("Frame")
	tile.Position = UDim2.fromOffset(12, 10)
	tile.Size = UDim2.fromOffset(66, 66)
	tile.BackgroundColor3 = UI.DARK
	tile.BorderSizePixel = 0
	tile.Parent = row
	corner(tile, 8)
	local view = Instance.new("ViewportFrame")
	view.Size = UDim2.fromScale(1, 1)
	view.BackgroundTransparency = 1
	view.Ambient = Color3.fromRGB(175, 175, 185)
	view.LightColor = Color3.new(1, 1, 1)
	view.Parent = tile
	fillViewport(view, { class = class, tier = 1 })

	-- A dark veil over the 3D view while the class is still locked.
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 2
	overlay.Parent = tile
	corner(overlay, 8)
	local locked = label(overlay, "LOCKED", UDim2.new(0, 0, 1, -18), UDim2.new(1, 0, 0, 14), 9, Enum.Font.GothamBlack, MUTED)
	locked.TextXAlignment = Enum.TextXAlignment.Center

	label(row, def.label, UDim2.fromOffset(88, 7), UDim2.fromOffset(160, 20), 16, Enum.Font.GothamBold, WHITE)
	UI.chip(row, string.format("HP %d", def.hp), UDim2.fromOffset(88, 30), UDim2.fromOffset(56, 18), UI.DARK, GREEN, 12)
	UI.chip(row, string.format("DMG %d", def.damage), UDim2.fromOffset(148, 30), UDim2.fromOffset(62, 18), UI.DARK, ORANGE, 12)
	UI.chip(row, string.format("RNG %d", def.range), UDim2.fromOffset(214, 30), UDim2.fromOffset(58, 18), UI.DARK, Color3.fromRGB(120, 180, 255), 12)
	local passive = label(row, Units.passiveText(class), UDim2.fromOffset(88, 52), UDim2.fromOffset(212, 14), 11, Enum.Font.GothamMedium, GOLD)
	passive.TextScaled = true
	local status = label(row, "", UDim2.fromOffset(88, 67), UDim2.fromOffset(212, 14), 12, Enum.Font.GothamBold, GREEN)
	soldierRows[class] = { frame = row, stroke = rowStroke, overlay = overlay, status = status }
end

renderSoldiers = function()
	local unlocked = 0
	for _, class in Units.ClassList do
		local row = soldierRows[class]
		local isUnlocked = state.unlocked[class] == true
		if isUnlocked then
			unlocked += 1
		end
		row.overlay.Visible = not isUnlocked
		row.frame.BackgroundTransparency = if isUnlocked then 0 else 0.35
		row.stroke.Transparency = if isUnlocked then 0.4 else 0.75
		local unlock = Units.Classes[class].unlock
		if isUnlocked then
			row.status.Text = "Unlocked"
			row.status.TextColor3 = GREEN
		elseif unlock then
			if unlock.legendary then
				row.status.Text = string.format("LEGENDARY · lucky drop, wave %d+", unlock.wave)
				row.status.TextColor3 = Levels.color(8)
			else
				row.status.Text = string.format("Lucky drop from wave %d", unlock.wave)
				row.status.TextColor3 = GOLD
			end
		end
	end
	unlockedCount.Text = string.format("%d/%d", unlocked, #Units.ClassList)
end
end

-- ── Battle panel ──────────────────────────────────────────────────────────
-- The PLAY button opens this panel: choose the difficulty and the wave, then START WAVE.

local function findPlot(): Instance?
	local plotsFolder = workspace:FindFirstChild("Plots")
	return plotsFolder and plotsFolder:FindFirstChild("Plot_" .. player.UserId)
end

-- Is your character inside your battle zone (up on the fight arena)?
local function computeInZone(zoneName: string): boolean
	local plot = findPlot()
	local zone = plot and plot:FindFirstChild(zoneName)
	local root = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
	if not zone or not root or not zone:IsA("BasePart") or not root:IsA("BasePart") then
		return false
	end
	local offset = zone.CFrame:PointToObjectSpace(root.Position)
	local half = zone.Size / 2
	return math.abs(offset.X) <= half.X and math.abs(offset.Y) <= half.Y and math.abs(offset.Z) <= half.Z
end
-- The battle panel is opened with the PLAY button (UI.battleOpen); while it is open the main panel steps aside.

local battlePanel = Instance.new("Frame")
battlePanel.Name = "BattlePanel"
battlePanel.AnchorPoint = Vector2.new(0.5, 0.5)
battlePanel.Position = UDim2.fromScale(0.5, 0.5)
battlePanel.Size = UDim2.fromOffset(560, 292)
battlePanel.BackgroundColor3 = BG
battlePanel.BackgroundTransparency = 0.05
battlePanel.BorderSizePixel = 0
battlePanel.Active = true -- clicks on the panel never reach the 3D world
battlePanel.Visible = false
battlePanel.Parent = gui
corner(battlePanel, 14)
do -- bigger and wider: laid out at 560 x 292, drawn at 1.3x (every text and button grows with it)
	local battleScale = Instance.new("UIScale")
	battleScale.Scale = 1.3
	battleScale.Parent = battlePanel
end
local battleStroke = Instance.new("UIStroke")
battleStroke.Color = ORANGE
battleStroke.Thickness = 3
battleStroke.Parent = battlePanel

local function battleText(text: string, x: number, y: number, width: number, height: number, size: number, font: Enum.Font, color: Color3): TextLabel
	local l = label(battlePanel, text, UDim2.fromOffset(x, y), UDim2.fromOffset(width, height), size, font, color)
	l.TextWrapped = true
	l.TextYAlignment = Enum.TextYAlignment.Top
	return l
end

local function battleButton(text: string, x: number, y: number, width: number, height: number): TextButton
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(width, height)
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.BackgroundColor3 = BADGE
	b.TextColor3 = WHITE
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.Text = text
	b.Parent = battlePanel
	corner(b, 8)
	return b
end

local battleClose = battleButton("X", 522, 8, 30, 30)
battleClose.BackgroundColor3 = BADGE
battleClose.Activated:Connect(function()
	UI.battleOpen = false
end)

local battleTitle = battleText("BATTLE", 0, 8, 560, 30, 26, Enum.Font.GothamBlack, ORANGE)
battleTitle.TextXAlignment = Enum.TextXAlignment.Center
local battleMapLabel = battleText("", 0, 40, 560, 16, 12, Enum.Font.Gotham, MUTED)
battleMapLabel.TextXAlignment = Enum.TextXAlignment.Center

battleText("DIFFICULTY", 14, 68, 250, 16, 12, Enum.Font.GothamBold, MUTED)
local difficultyButtons: { [string]: TextButton } = {}
for i, key in Difficulties.Order do
	local button = battleButton(Difficulties.Defs[key].label, 14 + ((i - 1) % 2) * 128, 86 + ((i - 1) // 2) * 36, 122, 32) -- 2 x 2
	button.Activated:Connect(function()
		Net.get("SetDifficulty"):FireServer(key)
	end)
	difficultyButtons[key] = button
end
local difficultyInfo = battleText("", 14, 158, 262, 34, 12, Enum.Font.Gotham, MUTED)
-- The squad's synergies (Synergy.luau) and the row bonuses.
local synergyLabel = battleText("", 14, 196, 268, 32, 12, Enum.Font.GothamMedium, GOLD)

-- AUTO FIGHT: after a win the next wave starts by itself (a defeat stops it).
local autoFightButton = battleButton("AUTO: OFF", 404, 8, 112, 30)

-- SPEED: cycles the battle speed (1x / 2x), also while a battle runs.
local speedButton = battleButton("SPEED 1x", 296, 8, 100, 30)
speedButton.TextSize = 13
speedButton.Activated:Connect(function()
	Net.get("BattleSpeed"):FireServer()
end)

autoFightButton.TextSize = 13
autoFightButton.Activated:Connect(function()
	Net.get("AutoFight"):FireServer(not state.autoFight)
end)

battleText("WAVE TO FIGHT", 296, 68, 250, 16, 12, Enum.Font.GothamBold, MUTED)
local waveMinus = battleButton("<", 296, 86, 44, 40)
local wavePlus = battleButton(">", 502, 86, 44, 40)
local waveText = battleText("", 344, 86, 154, 40, 22, Enum.Font.GothamBold, WHITE)
waveText.TextXAlignment = Enum.TextXAlignment.Center
waveText.TextYAlignment = Enum.TextYAlignment.Center
local waveInfo = battleText("", 296, 130, 250, 64, 12, Enum.Font.Gotham, MUTED)

local startButton = battleButton("START WAVE", 14, 234, 532, 48)
startButton.TextSize = 18
startButton.Font = Enum.Font.GothamBlack

waveMinus.Activated:Connect(function()
	if state.selectedWave > 1 then
		Net.get("SetWave"):FireServer(state.selectedWave - 1)
	end
end)
wavePlus.Activated:Connect(function()
	if state.selectedWave < state.wave then
		Net.get("SetWave"):FireServer(state.selectedWave + 1)
	end
end)
startButton.Activated:Connect(function()
	Net.get("Battle"):FireServer()
	UI.battleOpen = false
end)

-- The texts that only change with the selection are rebuilt when it changes (not every frame).
local battleInfoKey = ""

renderBattlePanel = function()
	if state.battling then
		UI.battleOpen = false
	end
	local visible = UI.battleOpen
	battlePanel.Visible = visible
	if not visible then
		return
	end

	speedButton.Text = string.format("SPEED %dx", state.battleSpeed)
	speedButton.BackgroundColor3 = if state.battleSpeed > 1 then ORANGE:Lerp(BG, 0.3) else BADGE
	autoFightButton.Text = if state.autoFight then "AUTO: ON" else "AUTO: OFF"
	autoFightButton.BackgroundColor3 = if state.autoFight then GREEN:Lerp(BG, 0.3) else BADGE
	local synergy = Synergy.compute(state.squad)
	if #synergy.lines > 0 then
		synergyLabel.Text = "Synergy: " .. table.concat(synergy.lines, " · ")
		synergyLabel.TextColor3 = GOLD
	else
		synergyLabel.Text = "No synergy yet: 2 Frontline = +HP, 2 Ranged = +damage, 4 classes = both"
		synergyLabel.TextColor3 = MUTED
	end

	local map = Maps.Defs[state.map]
	local key = string.format("%s|%d|%d|%s", state.map, state.selectedWave, state.wave, state.difficulty)
	if key ~= battleInfoKey then
		battleInfoKey = key
		battleMapLabel.Text = string.format("%s · %s", map.arena, string.upper(map.label))

		local difficulty = Difficulties.Defs[state.difficulty]
		difficultyInfo.Text = string.format("Enemies x%.1f power · coins x%.1f · XP x%.1f%s · lucky drop %d%%", difficulty.enemyPower, difficulty.rewardMultiplier, difficulty.xpMultiplier, if difficulty.extraDrops > 0 then string.format(" · +%d drop", difficulty.extraDrops) else "", math.floor(difficulty.luckyDropChance * 100 + 0.5))
		for difficultyKey, button in difficultyButtons do
			button.BackgroundColor3 = if state.difficulty == difficultyKey then GREEN:Lerp(BG, 0.35) else BADGE
		end

		waveText.Text = string.format("Wave %d / %d", state.selectedWave, map.waves)
		local _, phase = Waves.phase(state.selectedWave, map)
		local enemies = Waves.get(state.selectedWave, map)
		local lines = { string.format("%s · %d %s", phase.name, #enemies, map.enemyName) }
		if state.selectedWave % Balance.PhaseLength == 0 then
			table.insert(lines, string.format("BOSS WAVE: %s", Enemies.Kinds[phase.boss].label))
		end
		table.insert(lines, string.format("Reached wave %d. %s", state.wave, if state.selectedWave < state.wave then "Repeating gives coins and a drop, no progress." else "Clear it to move on."))
		waveInfo.Text = table.concat(lines, "\n")
	end

	-- The start button follows the timers every frame.
	local remaining = math.max(0, state.nextWaveIn - (os.clock() - stateReceivedAt))
	if remaining > 0 then
		startButton.Text = string.format("Next wave in %ds", math.ceil(remaining))
		startButton.BackgroundColor3 = BADGE
		startButton.TextTransparency = 0.4
	elseif state.rolling then
		startButton.Text = "Rolling…"
		startButton.BackgroundColor3 = BADGE
		startButton.TextTransparency = 0.4
	else
		startButton.Text = string.format("START WAVE %d", state.selectedWave)
		startButton.BackgroundColor3 = ORANGE:Lerp(BG, 0.15)
		startButton.TextTransparency = 0
	end
	local canEdit = remaining <= 0 and not state.rolling
	waveMinus.TextTransparency = if canEdit and state.selectedWave > 1 then 0 else 0.6
	wavePlus.TextTransparency = if canEdit and state.selectedWave < state.wave then 0 else 0.6
end

-- ── Level upgrade panel ───────────────────────────────────────────────────
-- The lobby station: stand on it and this panel opens. Bought soldiers start at the level you buy here.
do

local upgradeOpen = false -- true while you stand on the level station

local levelPanel = Instance.new("Frame")
levelPanel.Name = "LevelPanel"
levelPanel.AnchorPoint = Vector2.new(0.5, 0.5)
levelPanel.Position = UDim2.fromScale(0.5, 0.5)
levelPanel.Size = UDim2.fromOffset(420, 190)
levelPanel.BackgroundColor3 = BG
levelPanel.BackgroundTransparency = 0.05
levelPanel.BorderSizePixel = 0
levelPanel.Active = true
levelPanel.Visible = false
levelPanel.Parent = gui
corner(levelPanel, 14)
local levelStroke = Instance.new("UIStroke")
levelStroke.Color = Color3.fromRGB(170, 130, 255)
levelStroke.Thickness = 3
levelStroke.Parent = levelPanel

local levelTitle = label(levelPanel, "LEVEL UPGRADE", UDim2.fromOffset(0, 10), UDim2.fromOffset(420, 30), 26, Enum.Font.GothamBlack, Color3.fromRGB(190, 160, 255))
levelTitle.TextXAlignment = Enum.TextXAlignment.Center
local levelCurrent = label(levelPanel, "", UDim2.fromOffset(0, 50), UDim2.fromOffset(420, 26), 20, Enum.Font.GothamBold, WHITE)
levelCurrent.TextXAlignment = Enum.TextXAlignment.Center
local levelInfo = label(levelPanel, "", UDim2.fromOffset(20, 82), UDim2.fromOffset(380, 36), 13, Enum.Font.Gotham, MUTED)
levelInfo.TextXAlignment = Enum.TextXAlignment.Center
levelInfo.TextWrapped = true
levelInfo.TextYAlignment = Enum.TextYAlignment.Top

local levelButton = Instance.new("TextButton")
levelButton.Position = UDim2.fromOffset(20, 128)
levelButton.Size = UDim2.fromOffset(380, 48)
levelButton.BorderSizePixel = 0
levelButton.AutoButtonColor = false
levelButton.Font = Enum.Font.GothamBlack
levelButton.TextSize = 18
levelButton.TextColor3 = WHITE
levelButton.Parent = levelPanel
corner(levelButton, 8)
levelButton.Activated:Connect(function()
	Net.get("UpgradeLevel"):FireServer()
end)

RunService.RenderStepped:Connect(function()
	local visible = upgradeOpen and not state.battling
	levelPanel.Visible = visible
	if not visible then
		return
	end
	levelCurrent.Text = string.format("Bought characters start at level %d", state.startLevel)
	if state.levelCost == 0 then
		levelInfo.Text = "That is the highest start level."
		levelButton.Text = "MAX LEVEL"
		levelButton.BackgroundColor3 = BADGE
		levelButton.TextTransparency = 0.4
	else
		levelInfo.Text = string.format("Upgrade so new characters start at level %d (never above the level you bought for that character in the UPGRADES tab).", state.startLevel + 1)
		levelButton.Text = string.format("UPGRADE TO LEVEL %d  ·  %d coins", state.startLevel + 1, state.levelCost)
		local canAfford = state.coins >= state.levelCost
		levelButton.BackgroundColor3 = if canAfford then Color3.fromRGB(140, 100, 230) else BADGE
		levelButton.TextTransparency = if canAfford then 0 else 0.4
	end
end)

-- Checking the zone a few times a second is enough.
local padCheckTimer = 0
RunService.Heartbeat:Connect(function(dt)
	padCheckTimer += dt
	if padCheckTimer < 0.15 then
		return
	end
	padCheckTimer = 0
	upgradeOpen = computeInZone("UpgradeZone")
end)

-- Upgrades page: the merge level of every soldier class is bought separately. Without the upgrade
-- two soldiers of a class cannot be merged past the level bought so far.
local upgradesPage = makePage("Upgrades")
UI.section(upgradesPage, "MERGE LEVEL PER CHARACTER", 0, UI.TAB_ACCENT.Upgrades)
label(upgradesPage, "the dots are the 9 merge levels: lit = bought", UDim2.fromOffset(12, 16), UDim2.fromOffset(340, 14), 10, Enum.Font.GothamMedium, MUTED)
type UpgradeRow = { frame: Frame, stroke: UIStroke, sub: TextLabel, dots: { Frame }, button: TextButton, buttonStroke: UIStroke }
local upgradeRows: { [string]: UpgradeRow } = {}
for i, class in Units.ClassList do
	local def = Units.Classes[class]
	local row = Instance.new("Frame")
	row.Position = UDim2.fromOffset(8 + ((i - 1) % 2) * 316, 36 + ((i - 1) // 2) * 60) -- two columns
	row.Size = UDim2.fromOffset(308, 54)
	row.BackgroundColor3 = def.color:Lerp(BG, 0.8)
	row.BorderSizePixel = 0
	row.Parent = upgradesPage
	corner(row, 10)
	local rowStroke = UI.stroke(row, def.color, 1.5, 0.4)
	local accentBar = Instance.new("Frame")
	accentBar.Position = UDim2.fromOffset(0, 8)
	accentBar.Size = UDim2.fromOffset(4, 38)
	accentBar.BackgroundColor3 = def.color
	accentBar.BorderSizePixel = 0
	accentBar.Parent = row
	corner(accentBar, 2)
	label(row, def.label, UDim2.fromOffset(14, 5), UDim2.fromOffset(150, 18), 14, Enum.Font.GothamBold, WHITE)
	local sub = label(row, "", UDim2.fromOffset(14, 23), UDim2.fromOffset(190, 14), 12, Enum.Font.Gotham, MUTED)
	-- The merge levels as dots (lit in the level color up to the bought level): 9 for most classes, 30 for the
	-- Knight, squeezed into the same width.
	local dots = {}
	local maxTier = Units.maxTier(class)
	local step = math.min(14, math.floor(280 / maxTier))
	for k = 1, maxTier do
		local dot = Instance.new("Frame")
		dot.Position = UDim2.fromOffset(14 + (k - 1) * step, 41)
		dot.Size = UDim2.fromOffset(math.max(3, step - 3), 5)
		dot.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
		dot.BorderSizePixel = 0
		dot.Parent = row
		corner(dot, 2)
		dots[k] = dot
	end
	local button = Instance.new("TextButton")
	button.Position = UDim2.fromOffset(212, 9)
	button.Size = UDim2.fromOffset(88, 36)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.TextColor3 = WHITE
	button.Parent = row
	corner(button, 8)
	local buttonStroke = UI.stroke(button, GREEN, 1.5, 1)
	button.Activated:Connect(function()
		Net.get("UnlockTier"):FireServer(class)
	end)
	upgradeRows[class] = { frame = row, stroke = rowStroke, sub = sub, dots = dots, button = button, buttonStroke = buttonStroke }
end

renderLevels = function()
	for _, class in Units.ClassList do
		local row = upgradeRows[class]
		local cap = if state.unlocked[class] == true then capOf(class) else 0
		for k, dot in row.dots do
			if k <= cap then
				dot.BackgroundColor3 = Levels.color(k)
				dot.BackgroundTransparency = 0
			elseif k == cap + 1 and cap > 0 then
				dot.BackgroundColor3 = Levels.color(k)
				dot.BackgroundTransparency = 0.6 -- the next one to buy
			else
				dot.BackgroundColor3 = Color3.fromRGB(40, 44, 60)
				dot.BackgroundTransparency = 0
			end
		end
		if state.unlocked[class] ~= true then
			row.sub.Text = "Not unlocked yet"
			row.button.Visible = false
			row.frame.BackgroundTransparency = 0.5
			row.stroke.Transparency = 0.8
		else
			row.frame.BackgroundTransparency = 0
			row.stroke.Transparency = 0.4
			row.button.Visible = true
			local nextTier = cap + 1
			if nextTier > Units.maxTier(class) then
				row.sub.Text = string.format("Merges up to Lv %d (max)", cap)
				row.button.Text = "MAX"
				row.button.BackgroundColor3 = UI.DARK
				row.button.TextTransparency = 0.4
				row.buttonStroke.Transparency = 1
			else
				local def = Balance.TierUnlocks[nextTier]
				row.sub.Text = if cap <= 1 then "Cannot merge yet" else string.format("Merges up to Lv %d", cap)
				if state.cleared < def.wave then
					row.button.Text = string.format("Lv %d\nwave %d", nextTier, def.wave)
				else
					row.button.Text = string.format("Lv %d\n%d coins", nextTier, def.cost)
				end
				local ready = state.cleared >= def.wave and state.coins >= def.cost
				row.button.BackgroundColor3 = if ready then GREEN:Lerp(BG, 0.25) else UI.DARK
				row.button.TextTransparency = if ready then 0 else 0.35
				row.buttonStroke.Transparency = if ready then 0.2 else 1
			end
		end
	end
end

showTab("Inventory")
end

-- Spells page: the two spells you carry (Q and E) and every spell of the game. A spell you do not own yet
-- is found only by grinding: it can drop after a won wave from its wave on (Config/Spells.luau).
do
	local page = makePage("Spells")
	UI.section(page, "YOU CARRY TWO SPELLS", 0, UI.TAB_ACCENT.Spells)
	-- The two slots on top: the key in a badge and the spell's name, outlined in the spell's color.
	type SlotBox = { text: TextLabel, stroke: UIStroke, icon: Frame }
	local slotBoxes: { [string]: SlotBox } = {}
	for i, slot in { "q", "e" } do
		local box = Instance.new("Frame")
		box.Position = UDim2.fromOffset(8 + (i - 1) * 316, 20)
		box.Size = UDim2.fromOffset(308, 40)
		box.BackgroundColor3 = UI.DARK
		box.BorderSizePixel = 0
		box.Parent = page
		corner(box, 10)
		local boxStroke = UI.stroke(box, BADGE, 1.5, 0.3)
		local key = Instance.new("Frame")
		key.Position = UDim2.fromOffset(6, 7)
		key.Size = UDim2.fromOffset(26, 26)
		key.BackgroundColor3 = BADGE
		key.BorderSizePixel = 0
		key.Parent = box
		corner(key, 7)
		local keyText = label(key, string.upper(slot), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 14, Enum.Font.GothamBlack, WHITE)
		keyText.TextXAlignment = Enum.TextXAlignment.Center
		local icon = Instance.new("Frame")
		icon.Position = UDim2.fromOffset(40, 14)
		icon.Size = UDim2.fromOffset(12, 12)
		icon.BackgroundColor3 = BADGE
		icon.BorderSizePixel = 0
		icon.Parent = box
		corner(icon, 6)
		local text = label(box, "", UDim2.fromOffset(58, 0), UDim2.new(1, -62, 1, 0), 13, Enum.Font.GothamBold, WHITE)
		slotBoxes[slot] = { text = text, stroke = boxStroke, icon = icon }
	end

	type SpellRow = { frame: Frame, stroke: UIStroke, status: TextLabel, buttons: { [string]: TextButton } }
	local rows: { [string]: SpellRow } = {}
	for i, id in Spells.Order do
		local def = Spells.Defs[id]
		local row = Instance.new("Frame")
		row.Position = UDim2.fromOffset(8 + ((i - 1) % 2) * 316, 70 + ((i - 1) // 2) * 60) -- two columns
		row.Size = UDim2.fromOffset(308, 54)
		row.BackgroundColor3 = def.color:Lerp(BG, 0.82)
		row.BorderSizePixel = 0
		row.Parent = page
		corner(row, 10)
		local rowStroke = UI.stroke(row, def.color, 1.5, 0.45)
		-- The spell's icon: a disc in its color with its first letter.
		local icon = Instance.new("Frame")
		icon.Position = UDim2.fromOffset(9, 9)
		icon.Size = UDim2.fromOffset(36, 36)
		icon.BackgroundColor3 = def.color
		icon.BorderSizePixel = 0
		icon.Parent = row
		corner(icon, 18)
		UI.gradient(icon, Color3.new(1, 1, 1):Lerp(def.color, 0.55), def.color)
		local letter = label(icon, string.upper(string.sub(def.label, 1, 1)), UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), 17, Enum.Font.GothamBlack, def.color:Lerp(Color3.new(0, 0, 0), 0.7))
		letter.TextXAlignment = Enum.TextXAlignment.Center
		label(row, def.label, UDim2.fromOffset(54, 5), UDim2.fromOffset(160, 18), 14, Enum.Font.GothamBold, WHITE)
		local description = label(row, def.description, UDim2.fromOffset(54, 23), UDim2.fromOffset(176, 28), 11, Enum.Font.Gotham, MUTED)
		description.TextWrapped = true
		description.TextYAlignment = Enum.TextYAlignment.Top
		local status = label(row, string.format("Drops after\nwave %d", def.dropWave or 0), UDim2.fromOffset(232, 8), UDim2.fromOffset(68, 38), 10, Enum.Font.GothamMedium, GOLD)
		status.TextWrapped = true
		status.TextXAlignment = Enum.TextXAlignment.Right
		status.TextYAlignment = Enum.TextYAlignment.Center
		local buttons: { [string]: TextButton } = {}
		for b, slot in { "q", "e" } do
			local button = Instance.new("TextButton")
			button.Position = UDim2.fromOffset(236 + (b - 1) * 36, 12)
			button.Size = UDim2.fromOffset(30, 30)
			button.BorderSizePixel = 0
			button.AutoButtonColor = false
			button.Font = Enum.Font.GothamBold
			button.TextSize = 14
			button.Text = string.upper(slot)
			button.Parent = row
			corner(button, 8)
			button.Activated:Connect(function()
				Net.get("EquipSpell"):FireServer(id, slot)
			end)
			buttons[slot] = button
		end
		rows[id] = { frame = row, stroke = rowStroke, status = status, buttons = buttons }
	end

	renderSpells = function()
		for slot, box in slotBoxes do
			local id = (state.spells.slots :: { [string]: string })[slot]
			local def = Spells.Defs[id]
			if def then
				box.text.Text = def.label
				box.text.TextColor3 = WHITE
				box.stroke.Color = def.color
				box.icon.BackgroundColor3 = def.color
			else
				box.text.Text = "empty"
				box.text.TextColor3 = MUTED
				box.stroke.Color = BADGE
				box.icon.BackgroundColor3 = BADGE
			end
		end
		for id, row in rows do
			local owned = state.spells.owned[id] == true
			local def = Spells.Defs[id]
			row.status.Visible = not owned
			row.frame.BackgroundTransparency = if owned then 0 else 0.5
			row.stroke.Transparency = if owned then 0.45 else 0.8
			for slot, button in row.buttons do
				button.Visible = owned
				local equipped = (state.spells.slots :: { [string]: string })[slot] == id
				button.BackgroundColor3 = if equipped then def.color:Lerp(BG, 0.2) else UI.DARK
				button.TextColor3 = if equipped then WHITE else MUTED
			end
		end
	end
end

-- ── State from the server ─────────────────────────────────────────────────

Net.get("State").OnClientEvent:Connect(function(new)
	local now = os.clock()
	if new.rolling and not state.rolling then
		rollStart = now
	end
	if new.battling and not state.battling then
		battleStart = now
	end
	local remainingBefore = state.nextWaveIn - (now - stateReceivedAt)
	if new.nextWaveIn > 0 and remainingBefore <= 0 then
		cooldownTotal = new.nextWaveIn -- a new pause started: remember its full length for the fill
	end
	stateReceivedAt = now
	state = new
	Layout.apply(state.settings and state.settings.layout)
	renderInventory()
	renderSoldiers()
	renderLevels()
	renderSpells()
end)

-- (showToast is set in the Toast section below and also used by later sections.)
local showToast: (string, number) -> () = function() end

-- ── Toast ─────────────────────────────────────────────────────────────────
do

local toast = Instance.new("TextLabel")
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 24)
toast.AutomaticSize = Enum.AutomaticSize.XY
toast.BackgroundColor3 = BG
toast.BackgroundTransparency = 1
toast.TextTransparency = 1
toast.TextColor3 = WHITE
toast.Font = Enum.Font.GothamBold
toast.TextSize = 20
toast.Text = ""
toast.Parent = gui

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 16)
padding.PaddingRight = UDim.new(0, 16)
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 8)
padding.Parent = toast
corner(toast, 8)

local toastId = 0

showToast = function(text: string, seconds: number)
	toastId += 1
	local id = toastId
	toast.Text = text
	TweenService:Create(toast, TweenInfo.new(0.15), { BackgroundTransparency = 0.2, TextTransparency = 0 }):Play()
	task.delay(seconds, function()
		if id == toastId then -- a newer message keeps the toast alive
			TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
		end
	end)
end

Net.get("Notice").OnClientEvent:Connect(function(text: string)
	showToast(text, 3)
end)

-- One-time hint shortly after joining.
task.delay(3, function()
	showToast("Summon characters at the green altar (E), drag cards onto each other to merge, equip your squad, then press PLAY", 9)
end)
end

-- ── Drag & drop ───────────────────────────────────────────────────────────
-- Grab one of your soldiers with the mouse (or a finger) and drop it on another pad.
-- While dragging, the target lights up: gold = these two will merge, blue = swap,
-- white = move. The server decides the result (Interact remote).

local camera = workspace.CurrentCamera
local INDICATOR_GOLD = Color3.fromRGB(255, 215, 90)
local INDICATOR_SWAP = Color3.fromRGB(90, 150, 255)
local INDICATOR_MOVE = Color3.fromRGB(235, 240, 250)

type Drag = {
	slot: number,
	model: Model,
	home: CFrame,
	groundY: number,
	lift: number,
	hovered: number?,
	shown: number?,
	glow: Highlight,
	targetGlow: Highlight?,
	padColors: { [number]: Color3 },
}
local drag: Drag? = nil

local function getPlot(): Instance?
	local plots = workspace:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Plot_" .. player.UserId)
end

-- Slot ids: the merge board is 1 … BoardSize, the squad is SquadOffset + 1 … SquadOffset + SquadSize (six).
local slotIds: { number } = {}
for i = 1, Balance.BoardSize do
	table.insert(slotIds, i)
end
for i = 1, Balance.SquadSize do
	table.insert(slotIds, Balance.SquadOffset + i)
end

local padCache: { [number]: BasePart } = {}

local function padOf(slot: number): BasePart?
	local cached = padCache[slot]
	if cached and cached.Parent then
		return cached
	end
	local plot = getPlot()
	local pad = plot and plot:FindFirstChild("Slot" .. slot)
	if pad and pad:IsA("BasePart") then
		padCache[slot] = pad
		return pad
	end
	return nil
end

local function modelAt(slot: number): Model?
	local plot = getPlot()
	if not plot then
		return nil
	end
	for _, child in plot:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("Slot") == slot then
			return child
		end
	end
	return nil
end

local function pointerRay(): Ray
	return camera:ScreenPointToRay(pointer.X, pointer.Y)
end

local function groundPoint(groundY: number): Vector3?
	local ray = pointerRay()
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local t = (groundY - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

local function nearestSlot(point: Vector3): number?
	local best, bestDistance = nil, 4.2
	for _, id in slotIds do
		local pad = padOf(id)
		if pad and not pad:GetAttribute("Locked") then
			local d = ((pad.Position - point) * Vector3.new(1, 0, 1)).Magnitude
			if d < bestDistance then
				best, bestDistance = id, d
			end
		end
	end
	return best
end

-- Your soldier under the pointer. You do not have to hit the soldier itself: pointing anywhere
-- at its pad works too (enemies and decorations have no Slot attribute, so they never match).
local function soldierUnderPointer(): Model?
	local plot = getPlot()
	if not plot then
		return nil
	end

	-- 1) The soldier's body under the pointer.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { plot }
	local ray = pointerRay()
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
	if model and model:GetAttribute("Slot") then
		return model
	end

	-- 2) Otherwise the pad under the pointer: whoever stands on it is picked up.
	local firstPad = padOf(1)
	local point = firstPad and groundPoint(firstPad.Position.Y + firstPad.Size.Y / 2)
	local slot = point and nearestSlot(point)
	return if slot then modelAt(slot) else nil
end

local function canMerge(a: Model, b: Model): boolean
	return a:GetAttribute("Class") == b:GetAttribute("Class")
		and a:GetAttribute("Tier") == b:GetAttribute("Tier")
		and (a:GetAttribute("Tier") :: number) < math.min(Units.maxTier(a:GetAttribute("Class") :: string), capOf(a:GetAttribute("Class") :: string))
end

local function glide(model: Model, goal: CFrame, duration: number)
	local start = model:GetPivot()
	local t0 = os.clock()
	task.spawn(function()
		while model.Parent do
			local a = (os.clock() - t0) / duration
			if a >= 1 then
				model:PivotTo(goal)
				return
			end
			model:PivotTo(start:Lerp(goal, 1 - (1 - a) ^ 3))
			RunService.Heartbeat:Wait()
		end
	end)
end

local function makeGlow(parent: Instance, color: Color3): Highlight
	local h = Instance.new("Highlight")
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.7
	h.OutlineTransparency = 0
	h.Parent = parent
	return h
end

-- ── Hover effect ──────────────────────────────────────────────────────────
-- A calm, minimal hover (client-side only, other players never see it): a thin glowing ring that takes the
-- shape of the pad under the pointer (the size of its own ring) and a color that fits it: the soldier's level
-- color, or the pad's own ring color when it is empty. No pulsing; the soldier only rises a little.

local HOVER_SOLDIER = Color3.fromRGB(255, 235, 170) -- (fallbacks when a pad has no ring)
local HOVER_EMPTY = Color3.fromRGB(200, 210, 230)
local HOVER_LIFT = 0.3

local disc = Instance.new("Part")
disc.Name = "HoverDisc"
disc.Anchored = true
disc.CanCollide = false
disc.CanQuery = false
disc.CanTouch = false
disc.CastShadow = false
disc.Material = Enum.Material.Neon
disc.Shape = Enum.PartType.Cylinder -- round like the pads
disc.Size = Vector3.new(0.06, 5, 5)

local function setDisc(slot: number?, color: Color3?)
	local pad = if slot then padOf(slot) else nil
	if not pad or not color then
		disc.Parent = nil
		return
	end
	-- The size of the pad's own ring (the board's thin ring or the squad's fight slot).
	local ring = pad:FindFirstChild("Ring")
	local diameter = if ring and ring:IsA("BasePart") then ring.Size.Y + 0.3 else 5
	disc.Color = color
	disc.Transparency = 0.45
	disc.Size = Vector3.new(0.06, diameter, diameter)
	local top = if ring and ring:IsA("BasePart") then ring.Position.Y + ring.Size.X / 2 else pad.Position.Y + pad.Size.Y / 2
	disc.CFrame = CFrame.new(pad.Position.X, top + 0.05, pad.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = workspace
end

-- The hover color of a pad: the soldier's level color, or the pad's own ring color (lighter) when empty.
local function hoverColor(slot: number, model: Model?): Color3
	if model then
		local tier = model:GetAttribute("Tier")
		return if type(tier) == "number" then Levels.color(tier):Lerp(Color3.new(1, 1, 1), 0.25) else HOVER_SOLDIER
	end
	local pad = padOf(slot)
	local ring = pad and pad:FindFirstChild("Ring")
	return if ring and ring:IsA("BasePart") then ring.Color:Lerp(Color3.new(1, 1, 1), 0.45) else HOVER_EMPTY
end

type Lifted = { home: CFrame, offset: number, target: number, glow: Highlight? }
local lifted: { [Model]: Lifted } = {}
local hoveredModel: Model? = nil

local function liftModel(model: Model, up: boolean)
	local entry = lifted[model]
	if not entry then
		if not up then
			return
		end
		entry = { home = model:GetPivot(), offset = 0, target = 0, glow = nil }
		lifted[model] = entry
	end
	entry.target = if up then HOVER_LIFT else 0
	if up and not entry.glow then
		local tier = model:GetAttribute("Tier")
		local color = if type(tier) == "number" then Levels.color(tier) else HOVER_SOLDIER
		local glow = makeGlow(model, color)
		glow.FillTransparency = 0.9 -- a soft outline in the soldier's own color, hardly any fill
		entry.glow = glow
	end
end

local function updateHover(dt: number)
	-- Animate the lifts (including soldiers that are settling back down).
	for model, entry in lifted do
		if not model.Parent then
			lifted[model] = nil
		else
			entry.offset += (entry.target - entry.offset) * math.min(1, dt * 14)
			if entry.target == 0 and entry.offset < 0.02 then
				model:PivotTo(entry.home)
				if entry.glow then
					entry.glow:Destroy()
				end
				lifted[model] = nil
			else
				model:PivotTo(entry.home + Vector3.new(0, entry.offset, 0))
			end
		end
	end

	if drag then
		return -- while dragging, updateDrag owns the disc
	end
	local idle = UserInputService.MouseEnabled and not state.rolling and not state.battling
	local model = if idle then soldierUnderPointer() else nil
	if model ~= hoveredModel then
		if hoveredModel then
			liftModel(hoveredModel, false)
		end
		hoveredModel = model
		if model then
			liftModel(model, true)
		end
	end

	if not idle then
		setDisc(nil)
		return
	end
	local slot: number? = nil
	if model then
		slot = model:GetAttribute("Slot") :: number
	else
		local pad = padOf(1)
		local point = pad and groundPoint(pad.Position.Y + pad.Size.Y / 2)
		slot = point and nearestSlot(point)
	end
	setDisc(slot, if slot then hoverColor(slot, model) else nil)
end

local function clearIndicator(d: Drag)
	for slot, color in d.padColors do
		local pad = padOf(slot)
		if pad then
			local ring = pad:FindFirstChild("Ring") :: BasePart? -- the designed slot's ring
			if ring then
				ring.Color = color
			else
				pad.Color = color
			end
		end
	end
	table.clear(d.padColors)
	if d.targetGlow then
		d.targetGlow:Destroy()
		d.targetGlow = nil
	end
	d.glow.FillTransparency = 0.7
	d.glow.FillColor = INDICATOR_MOVE
	d.glow.OutlineColor = INDICATOR_MOVE
end

local function beginDrag()
	if drag or state.rolling or state.battling then
		return
	end
	local model = soldierUnderPointer()
	if not model then
		return
	end
	local slot = model:GetAttribute("Slot") :: number
	local pad = padOf(slot)
	if not pad then
		return
	end
	-- Undo the hover lift so the drag starts from the true home position.
	local entry = lifted[model]
	if entry then
		model:PivotTo(entry.home)
		if entry.glow then
			entry.glow:Destroy()
		end
		lifted[model] = nil
	end
	if hoveredModel == model then
		hoveredModel = nil
	end
	local groundY = pad.Position.Y + pad.Size.Y / 2
	local home = model:GetPivot()
	drag = {
		slot = slot,
		model = model,
		home = home,
		groundY = groundY,
		lift = home.Position.Y - groundY,
		hovered = nil,
		shown = nil,
		glow = makeGlow(model, INDICATOR_MOVE),
		targetGlow = nil,
		padColors = {},
	}
end

local function updateDrag(dt: number)
	local d = drag
	if not d then
		return
	end
	if not d.model.Parent then
		drag = nil -- the server re-rendered the plot
		return
	end

	local point = groundPoint(d.groundY)
	if point then
		-- Follow the pointer, hovering a little above the ground.
		local goal = Vector3.new(point.X, d.groundY + d.lift + 2.2, point.Z)
		local current = d.model:GetPivot()
		local position = current.Position:Lerp(goal, math.min(1, dt * 18))
		d.model:PivotTo(CFrame.new(position) * (d.home - d.home.Position))
		d.hovered = nearestSlot(point)
	else
		d.hovered = nil
	end
	-- Over the inventory panel the panel is the target (store the soldier), not a pad.
	local overPanel = pointerOverPanel()
	setPanelHighlight(overPanel)
	if overPanel then
		d.hovered = nil
		-- The card under the pointer is the target (gold = merge, blue = swap, white = move).
		local targetId = cardIdAtPointer(d.slot)
		local target = if targetId then unitAt(targetId) else nil
		local same = target ~= nil
			and target.class == d.model:GetAttribute("Class")
			and target.tier == d.model:GetAttribute("Tier")
			and target.tier < math.min(Units.maxTier(target.class), capOf(target.class))
		markCard(targetId, if same then INDICATOR_GOLD elseif target then INDICATOR_SWAP else INDICATOR_MOVE)
	else
		markCard(nil, INDICATOR_MOVE)
	end

	local hovered = if d.hovered ~= d.slot then d.hovered else nil
	if d.shown ~= hovered then
		clearIndicator(d)
		d.shown = hovered
	end
	if not hovered then
		setDisc(nil)
		return
	end

	local pad = padOf(hovered)
	local target = modelAt(hovered)
	local mergeable = target ~= nil and canMerge(d.model, target)
	local color = if mergeable then INDICATOR_GOLD elseif target then INDICATOR_SWAP else INDICATOR_MOVE
	if pad then
		local ring = pad:FindFirstChild("Ring") :: BasePart? -- the designed slot's ring
		if ring then
			d.padColors[hovered] = d.padColors[hovered] or ring.Color
			ring.Color = color
		else
			d.padColors[hovered] = d.padColors[hovered] or pad.Color
			pad.Color = color
		end
	end
	setDisc(hovered, color)
	d.glow.FillColor = color
	d.glow.OutlineColor = color
	if mergeable and target then
		if not d.targetGlow then
			d.targetGlow = makeGlow(target, INDICATOR_GOLD)
		end
		local pulse = 0.35 + 0.3 * (0.5 + 0.5 * math.sin(os.clock() * 10))
		d.glow.FillTransparency = pulse
		;(d.targetGlow :: Highlight).FillTransparency = pulse
	end
end

local function endDrag()
	local d = drag
	if not d then
		return
	end
	drag = nil
	setDisc(nil)
	local overPanel = pointerOverPanel()
	setPanelHighlight(false)
	markCard(nil, INDICATOR_MOVE)
	local to = d.hovered
	clearIndicator(d)
	d.glow:Destroy()
	if overPanel then
		local targetCard = cardIdAtPointer(d.slot)
		if targetCard then
			Net.get("Interact"):FireServer(d.slot, targetCard) -- merge / swap with that card
		elseif d.slot > Balance.SquadOffset and pointerOver(panel) then
			Net.get("Unequip"):FireServer(d.slot) -- a squad soldier dropped on the panel goes back to the inventory
		end
		task.delay(0.5, function()
			if d.model.Parent then
				glide(d.model, d.home, 0.15)
			end
		end)
	elseif to and to ~= d.slot then
		Net.get("Interact"):FireServer(d.slot, to)
		-- On success the server re-renders the plot; if nothing changed, glide back home.
		task.delay(0.5, function()
			if d.model.Parent then
				glide(d.model, d.home, 0.15)
			end
		end)
	else
		glide(d.model, d.home, 0.15)
	end
end

RunService.RenderStepped:Connect(updateDrag)
RunService.RenderStepped:Connect(updateHover)

-- ── Inventory cards: click = equip / unequip, drag = merge ────────────────
-- Click a card: a small popup with EQUIP (or UNEQUIP for an equipped soldier).
-- Drag a card: a 3D soldier follows the cursor. Drop it on another card in the panel, or on a pad
-- in the 3D world, to merge (same class and level), swap or move it. The server decides
-- (Interact), so merging works right in the UI inventory and in the 3D room alike.

local cardPopup: Frame? = nil

local function closeCardPopup()
	if cardPopup then
		cardPopup:Destroy()
		cardPopup = nil
	end
end

openCardPopup = function(id: number)
	local unit = unitAt(id)
	local card = slotCards[id]
	if not unit or not card or state.rolling or state.battling then
		return
	end
	closeCardPopup()
	local equipped = id > Balance.SquadOffset

	local popup = Instance.new("Frame")
	popup.AnchorPoint = Vector2.new(0, 0.5)
	local container: GuiObject = if equipped then UI.squadBar else panel
	popup.Position = UDim2.fromOffset(
		container.AbsolutePosition.X + container.AbsoluteSize.X + 10,
		math.clamp(card.AbsolutePosition.Y + card.AbsoluteSize.Y / 2, 80, math.max(80, gui.AbsoluteSize.Y - 80))
	)
	popup.Size = UDim2.fromOffset(220, 168)
	popup.BackgroundColor3 = BG
	popup.BackgroundTransparency = 0.05
	popup.BorderSizePixel = 0
	popup.Active = true -- clicks on the popup never reach the 3D world
	popup.ZIndex = 40
	popup.Parent = gui
	corner(popup, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Levels.color(unit.tier)
	stroke.Thickness = 2
	stroke.Parent = popup

	local title = label(popup, string.format("%s · %s", Units.Classes[unit.class].label, Levels.label(unit.tier)), UDim2.fromOffset(10, 6), UDim2.fromOffset(200, 20), 16, Enum.Font.GothamBold, WHITE)
	title.ZIndex = 41
	local hint = label(popup, Units.passiveText(unit.class, (unit :: any).ascended), UDim2.fromOffset(10, 28), UDim2.fromOffset(200, 16), 11, Enum.Font.Gotham, MUTED)
	hint.TextScaled = true
	hint.ZIndex = 41

	local free = if equipped then state.boardFree else state.squadFree
	local button = Instance.new("TextButton")
	button.Position = UDim2.fromOffset(10, 62)
	button.Size = UDim2.fromOffset(200, 42)
	button.BackgroundColor3 = if equipped then Color3.fromRGB(90, 100, 135) else GREEN:Lerp(BG, 0.3)
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = WHITE
	button.TextTransparency = if free > 0 then 0 else 0.55
	button.Text = string.format("%s  ·  %d free", if equipped then "UNEQUIP" else "EQUIP", free)
	button.ZIndex = 41
	button.Parent = popup
	corner(button, 8)
	button.Activated:Connect(function()
		closeCardPopup()
		Net.get(if equipped then "Unequip" else "Equip"):FireServer(id)
	end)
	-- SELL: the soldier goes for coins.
	local sell = Instance.new("TextButton")
	sell.Position = UDim2.fromOffset(10, 114)
	sell.Size = UDim2.fromOffset(200, 42)
	sell.BackgroundColor3 = Color3.fromRGB(140, 85, 60)
	sell.BorderSizePixel = 0
	sell.AutoButtonColor = false
	sell.Font = Enum.Font.GothamBold
	sell.TextSize = 16
	sell.TextColor3 = WHITE
	sell.Text = string.format("SELL  ·  +%d coins", Levels.sellValue(unit.tier, (unit :: any).ascended))
	sell.ZIndex = 41
	sell.Parent = popup
	corner(sell, 8)
	sell.Activated:Connect(function()
		closeCardPopup()
		Net.get("Sell"):FireServer(id)
	end)
	cardPopup = popup
end

type CardDrag = {
	id: number,
	ghost: Frame,
	ghostModel: Model?,
	world: Model,
	worldGlow: Highlight,
	groundY: number,
	lift: number,
	placed: boolean,
	spin: number,
	startPointer: Vector2,
	moved: boolean,
}
local cardDrag: CardDrag? = nil

-- The pad under the pointer (unlocked board pads and squad pads only) and its indicator color.
local function padForUnit(unit: { class: string, tier: number }): (number?, Color3)
	local pad = padOf(1)
	local point = pad and groundPoint(pad.Position.Y + pad.Size.Y / 2)
	local slot = point and nearestSlot(point)
	if not slot then
		return nil, INDICATOR_MOVE
	end
	local target = modelAt(slot)
	if not target then
		return slot, INDICATOR_MOVE
	end
	local mergeable = target:GetAttribute("Class") == unit.class
		and target:GetAttribute("Tier") == unit.tier
		and unit.tier < math.min(Units.maxTier(unit.class), capOf(unit.class))
	return slot, if mergeable then INDICATOR_GOLD else INDICATOR_SWAP
end

beginCardDrag = function(id: number, input: InputObject)
	if cardDrag or drag or state.rolling or state.battling then
		return
	end
	local unit = unitAt(id)
	local pad = padOf(1)
	if not unit or not pad then
		return
	end
	closeCardPopup()
	pointer = Vector2.new(input.Position.X, input.Position.Y)

	-- 3D preview that follows the cursor while it is over the panel.
	local ghost = makeCard()
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.fromOffset(96, 96)
	ghost.Position = UDim2.fromOffset(pointer.X, pointer.Y)
	ghost.BackgroundTransparency = 1
	ghost.Visible = false
	local ghostStroke = ghost:FindFirstChildOfClass("UIStroke")
	if ghostStroke then
		ghostStroke.Enabled = false
	end
	styleCard(ghost, unit)
	for _, child in ghost:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = 21
		end
	end
	ghost.ZIndex = 20
	ghost.Parent = gui
	local ghostView = ghost:FindFirstChild("View") :: ViewportFrame
	local ghostModel = ghostView:FindFirstChildOfClass("Model")

	-- The real 3D soldier that appears in the world once the cursor leaves the panel.
	local world = Soldier.build(unit.class, unit.tier, false, nil, (unit :: any).ascended)

	if slotCards[id] then
		slotCards[id].BackgroundTransparency = 0.6 -- the card stays as a dimmed placeholder
	end
	cardDrag = {
		id = id,
		ghost = ghost,
		ghostModel = ghostModel,
		world = world,
		worldGlow = makeGlow(world, INDICATOR_MOVE),
		groundY = pad.Position.Y + pad.Size.Y / 2,
		lift = Soldier.lift(unit.tier),
		placed = false,
		spin = 0,
		startPointer = pointer,
		moved = false,
	}
end

local function updateCardDrag(dt: number)
	local d = cardDrag
	if not d then
		return
	end
	if not d.moved then
		if (pointer - d.startPointer).Magnitude < 6 then
			return -- still a click
		end
		d.moved = true
	end

	local unit = unitAt(d.id)
	local over = pointerOverPanel()

	d.ghost.Visible = over
	d.ghost.Position = UDim2.fromOffset(pointer.X, pointer.Y)
	d.spin += dt * 2.5
	if d.ghostModel and d.ghostModel.Parent then
		d.ghostModel:PivotTo(CFrame.new(0, d.lift, 0) * CFrame.Angles(0, d.spin, 0))
	end

	if not unit or over then
		d.world.Parent = nil
		d.placed = false
		setDisc(nil)
		if unit then
			-- Over the panel: the card under the pointer is the merge target.
			local targetId = cardIdAtPointer(d.id)
			local target = if targetId then unitAt(targetId) else nil
			local same = target ~= nil and target.class == unit.class and target.tier == unit.tier and unit.tier < math.min(Units.maxTier(unit.class), capOf(unit.class))
			markCard(targetId, if same then INDICATOR_GOLD elseif target then INDICATOR_SWAP else INDICATOR_MOVE)
		end
		return
	end
	markCard(nil, INDICATOR_MOVE)

	-- In the world: the soldier hovers over the ground point under the cursor.
	local point = groundPoint(d.groundY)
	if point then
		local goal = Vector3.new(point.X, d.groundY + d.lift + 2.2, point.Z)
		local current = if d.placed then d.world:GetPivot().Position else goal
		local position = current:Lerp(goal, math.min(1, dt * 18))
		d.world:PivotTo(CFrame.lookAt(position, position + Vector3.new(0, 0, 1)))
		d.placed = true
	end
	d.world.Parent = if d.placed then workspace else nil

	local slot, color = padForUnit(unit)
	setDisc(slot, if slot then color else nil)
	d.worldGlow.FillColor = color
	d.worldGlow.OutlineColor = color
end

local function endCardDrag()
	local d = cardDrag
	if not d then
		return
	end
	cardDrag = nil
	d.ghost:Destroy()
	setDisc(nil)
	markCard(nil, INDICATOR_MOVE)
	if slotCards[d.id] then
		slotCards[d.id].BackgroundTransparency = 0
	end

	if not d.moved then
		d.world:Destroy()
		openCardPopup(d.id) -- a plain click: EQUIP / UNEQUIP
		return
	end

	local unit = unitAt(d.id)
	if not unit then
		d.world:Destroy()
		return
	end
	if pointerOverPanel() then
		local target = cardIdAtPointer(d.id)
		if target then
			Net.get("Interact"):FireServer(d.id, target) -- merge / swap with that card
		end
		d.world:Destroy()
		return
	end

	local slot = padForUnit(unit)
	local pad = if slot then padOf(slot) else nil
	if slot and slot ~= d.id and pad and d.world.Parent then
		Net.get("Interact"):FireServer(d.id, slot)
		-- The soldier settles on the pad; the server's own model takes over right after.
		local home = pad.Position + Vector3.new(0, pad.Size.Y / 2 + d.lift, 0)
		glide(d.world, CFrame.lookAt(home, home + Vector3.new(0, 0, 1)), 0.12)
		task.delay(0.35, function()
			d.world:Destroy()
		end)
	else
		d.world:Destroy()
	end
end

RunService.RenderStepped:Connect(updateCardDrag)

-- ── Countdown before the battle ───────────────────────────────────────────
-- "3, 2, 1, FIGHT!" in the middle of the screen (the server counts, the client shows it).
do

local countdownLabel = Instance.new("TextLabel")
countdownLabel.AnchorPoint = Vector2.new(0.5, 0.5)
countdownLabel.Position = UDim2.fromScale(0.5, 0.3)
countdownLabel.Size = UDim2.fromOffset(500, 130)
countdownLabel.BackgroundTransparency = 1
countdownLabel.Font = Enum.Font.GothamBlack
countdownLabel.TextSize = 96
countdownLabel.TextColor3 = WHITE
countdownLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
countdownLabel.TextTransparency = 1
countdownLabel.TextStrokeTransparency = 1
countdownLabel.Text = ""
countdownLabel.Parent = gui
local countdownScale = Instance.new("UIScale")
countdownScale.Parent = countdownLabel
local countdownId = 0

Net.get("Countdown").OnClientEvent:Connect(function(n: number)
	countdownId += 1
	local id = countdownId
	countdownLabel.Text = if n > 0 then tostring(n) else "FIGHT!"
	countdownLabel.TextColor3 = if n > 0 then WHITE else ORANGE
	countdownLabel.TextTransparency = 0
	countdownLabel.TextStrokeTransparency = 0.3
	countdownScale.Scale = 1.7
	TweenService:Create(countdownScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(if n > 0 then 0.8 else 0.9, function()
		if id == countdownId then
			TweenService:Create(countdownLabel, TweenInfo.new(0.2), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end)

-- A boss wave is announced with a big red banner while the countdown runs.
local bossBanner = Instance.new("TextLabel")
bossBanner.AnchorPoint = Vector2.new(0.5, 0.5)
bossBanner.Position = UDim2.fromScale(0.5, 0.16)
bossBanner.Size = UDim2.fromOffset(700, 110)
bossBanner.BackgroundTransparency = 1
bossBanner.Font = Enum.Font.GothamBlack
bossBanner.RichText = true
bossBanner.TextSize = 46
bossBanner.TextColor3 = Color3.fromRGB(255, 90, 80)
bossBanner.TextStrokeColor3 = Color3.new(0, 0, 0)
bossBanner.TextStrokeTransparency = 0.3
bossBanner.TextTransparency = 1
bossBanner.Text = ""
bossBanner.ZIndex = 15
bossBanner.Parent = gui
local bossScale = Instance.new("UIScale")
bossScale.Parent = bossBanner
local bossId = 0

Net.get("BossIntro").OnClientEvent:Connect(function(name: string)
	bossId += 1
	local id = bossId
	if name == "ELITE WAVE" then
		bossBanner.Text = '<font size="24" color="#ffe9a8">GOLDEN ENEMIES · DOUBLE REWARDS</font>\nELITE WAVE'
		bossBanner.TextColor3 = Color3.fromRGB(255, 200, 60)
	else
		bossBanner.Text = string.format('<font size="24" color="#ffc4b8">BOSS WAVE</font>\n%s', string.upper(name))
		bossBanner.TextColor3 = Color3.fromRGB(255, 90, 80)
	end
	bossBanner.TextTransparency = 0
	bossBanner.TextStrokeTransparency = 0.3
	bossScale.Scale = 1.6
	TweenService:Create(bossScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(2.8, function()
		if id == bossId then
			TweenService:Create(bossBanner, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end)
end

-- ── Wave result: the rewards drop in at the top ────────────────────────────
-- No result box: after a wave the title, the coins and every drop (soldier cards, lucky drop, new spell)
-- pop in one after another at the top of the screen, and the drops go straight into the inventory.
do

local resultId = 0
local resultFrame: Frame? = nil

local function closeResult(id: number)
	if id ~= resultId then
		return
	end
	local frame = resultFrame
	resultFrame = nil
	if not frame then
		return
	end
	local scale = frame:FindFirstChildOfClass("UIScale")
	if scale then
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.6 }):Play()
	end
	task.delay(0.25, function()
		frame:Destroy()
	end)
end

-- Small colored dots that fly up from `position` and fade (celebration for a lucky drop).
local function confettiPop(parent: Instance, position: UDim2, spread: number)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Size = UDim2.fromOffset(10, 10)
	dot.Position = position
	dot.BackgroundColor3 = Levels.color(math.random(1, #Levels.Colors))
	dot.BorderSizePixel = 0
	dot.ZIndex = 5
	dot.Parent = parent
	corner(dot, 5)
	local dx = (math.random() - 0.5) * spread
	local goal = UDim2.new(position.X.Scale, position.X.Offset + dx, position.Y.Scale, position.Y.Offset - 40 - math.random() * 50)
	TweenService:Create(dot, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = goal, BackgroundTransparency = 1 }):Play()
	task.delay(0.65, function()
		dot:Destroy()
	end)
end

-- A copy of `card` flies from the result screen into the inventory panel; `done` runs on landing.
local function flyToInventory(card: Frame, unit: { class: string, tier: number }, done: () -> ())
	local ghost = makeCard()
	ghost.AnchorPoint = Vector2.new(0.5, 0.5)
	ghost.Size = UDim2.fromOffset(card.AbsoluteSize.X, card.AbsoluteSize.Y)
	ghost.Position = UDim2.fromOffset(card.AbsolutePosition.X + card.AbsoluteSize.X / 2, card.AbsolutePosition.Y + card.AbsoluteSize.Y / 2)
	styleCard(ghost, unit)
	for _, child in ghost:GetDescendants() do
		if child:IsA("GuiObject") then
			child.ZIndex = 31
		end
	end
	ghost.ZIndex = 30
	ghost.Parent = gui

	local target = panel.AbsolutePosition + panel.AbsoluteSize / 2
	local tween = TweenService:Create(ghost, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromOffset(target.X, target.Y),
		Size = UDim2.fromOffset(48, 48),
	})
	tween.Completed:Connect(function()
		ghost:Destroy()
		done()
	end)
	tween:Play()
end

-- After a wave there is no result box: the rewards drop in one after another at the top of the screen (a
-- small line each, a little 3D card for a soldier), and the drops go straight into the inventory.
local rewardFeed = Instance.new("Frame")
rewardFeed.Name = "RewardFeed"
rewardFeed.AnchorPoint = Vector2.new(0.5, 0)
rewardFeed.Position = UDim2.new(0.5, 0, 0, 66)
rewardFeed.Size = UDim2.fromOffset(380, 0)
rewardFeed.AutomaticSize = Enum.AutomaticSize.Y
rewardFeed.BackgroundTransparency = 1
rewardFeed.Parent = gui
local rewardLayout = Instance.new("UIListLayout")
rewardLayout.Padding = UDim.new(0, 5)
rewardLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rewardLayout.SortOrder = Enum.SortOrder.LayoutOrder
rewardLayout.Parent = rewardFeed
local rewardOrder = 0

-- One reward line: text (rich), an optional soldier card, an accent color. It pops in and fades after a while.
local function pushReward(text: string, accent: Color3, unit: { class: string, tier: number }?, stay: number)
	rewardOrder += 1
	local pill = Instance.new("Frame")
	pill.LayoutOrder = rewardOrder
	pill.Size = UDim2.fromOffset(0, 34)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = BG
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.Parent = rewardFeed
	corner(pill, 17)
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 2
	stroke.Parent = pill
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, if unit then 4 else 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = pill
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 8)
	row.Parent = pill
	if unit then
		local card = makeCard()
		card.Size = UDim2.fromOffset(28, 28)
		card.Parent = pill
		styleCard(card, unit)
		local tier = card:FindFirstChild("Tier")
		if tier then
			tier:Destroy()
		end
	end
	local line = Instance.new("TextLabel")
	line.Size = UDim2.fromOffset(0, 34)
	line.AutomaticSize = Enum.AutomaticSize.X
	line.BackgroundTransparency = 1
	line.Font = Enum.Font.GothamBold
	line.TextSize = 15
	line.TextColor3 = WHITE
	line.RichText = true
	line.Text = text
	line.Parent = pill

	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = pill
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(stay, function()
		if not pill.Parent then
			return
		end
		local fade = TweenInfo.new(0.35)
		TweenService:Create(pill, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(line, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
		TweenService:Create(scale, fade, { Scale = 0.85 }):Play()
		task.delay(0.4, function()
			pill:Destroy()
		end)
	end)
end

local function unitText(unit: any): string
	return string.format("%s %s", Units.Classes[unit.class].label, Levels.label(unit.tier))
end

local function showResult(result: any)
	-- The drops go straight into the inventory (no waiting for a result screen).
	if result.won then
		Net.get("CollectDrops"):FireServer()
	end

	local entries: { { text: string, accent: Color3, unit: any? } } = {}
	if result.won then
		local title = if result.mapCleared then string.format("%s CLEARED!", string.upper(result.mapLabel)) elseif result.elite then string.format("ELITE WAVE %d CLEARED", result.wave) elseif result.boss then string.format("BOSS WAVE %d CLEARED", result.wave) else string.format("WAVE %d CLEARED", result.wave)
		table.insert(entries, { text = string.format('<font color="#ffcd5a">%s</font>', title), accent = GOLD })
		table.insert(entries, { text = string.format('<font color="#ffcd5a">+%d coins</font>%s', result.coins or 0, if (result.streak or 0) > 1 then string.format("  ·  streak x%d", result.streak) else ""), accent = GOLD })
		local drop = result.drop
		if drop then
			table.insert(entries, { text = unitText(drop) .. (if drop.bonus then '  <font color="#ffcd5a">BONUS LEVEL</font>' else "") .. (if drop.stored then "" else '  <font color="#a5aab9">(inventory full: sold)</font>'), accent = Levels.color(drop.tier), unit = drop })
		end
		for _, extra in result.extraDrops or {} do
			table.insert(entries, { text = "+ " .. unitText(extra) .. (if extra.stored then "" else '  <font color="#a5aab9">(sold)</font>'), accent = Levels.color(extra.tier), unit = extra })
		end
		if result.luckyResult then
			table.insert(entries, { text = string.format('<font color="#7ee08a">LUCKY DROP: %s unlocked!</font>', Units.Classes[result.luckyResult].label), accent = GREEN, unit = { class = result.luckyResult, tier = 1 } })
		end
		if result.spellDrop then
			table.insert(entries, { text = string.format('<font color="#96c8ff">NEW SPELL: %s</font>', Spells.Defs[result.spellDrop].label), accent = Spells.Defs[result.spellDrop].color })
		end
	else
		table.insert(entries, { text = string.format('<font color="#f0645a">DEFEAT</font>  ·  wave %d  ·  <font color="#ffcd5a">+%d coins</font>', result.wave, result.coins or 0), accent = RED })
	end

	-- One after another, like loot dropping in.
	task.spawn(function()
		for i, entry in entries do
			pushReward(entry.text, entry.accent, entry.unit, 3.6 + (#entries - i) * 0.25)
			task.wait(0.35)
		end
	end)
end

Net.get("WaveResult").OnClientEvent:Connect(showResult)

-- ── Roll animation (UI only) ──────────────────────────────────────────────
-- Buying a soldier plays its roll in a popup in the middle of the screen, not in the 3D world.
-- `playRollAnimation` is generic (the pool of classes it flickers through and the classes it lands
-- on, one or three cards at the same time), so a future shop can reuse it for any roll. When the soldier's card has flown into the
-- inventory panel it calls `onLanded` (the server then delivers the soldier).

local rollFrame: Frame? = nil
local rollId = 0

-- `classes` = the classes it lands on (1 or 3 cards roll side by side at the same time), `tiers` = their levels.
local function playRollAnimation(pool: { string }, classes: { string }, tiers: { number }, onLanded: () -> ())
	rollId += 1
	local id = rollId
	if rollFrame then
		rollFrame:Destroy()
		rollFrame = nil
	end

	local count = #classes
	local single = count == 1
	local spacing = 130
	local centerY = 130
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.42, 0)
	frame.Size = UDim2.fromOffset(if single then 300 else spacing * count + 40, 270)
	frame.BackgroundColor3 = BG
	frame.BackgroundTransparency = 0.05
	frame.BorderSizePixel = 0
	frame.Active = true
	frame.Parent = gui
	corner(frame, 16)
	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = GREEN
	frameStroke.Thickness = 3
	frameStroke.Parent = frame
	local frameScale = Instance.new("UIScale")
	frameScale.Scale = 0.6
	frameScale.Parent = frame
	rollFrame = frame
	TweenService:Create(frameScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local title = label(frame, "SUMMONING…", UDim2.fromOffset(0, 14), UDim2.new(1, 0, 0, 30), 22, Enum.Font.GothamBlack, WHITE)
	title.TextXAlignment = Enum.TextXAlignment.Center

	-- One roll slot per soldier: a card with a ring of colored dots around it and a name under it.
	local dotCount = if single then 12 else 8
	local ringStart = if single then 86 else 60
	local ringEnd = if single then 28 else 22
	local burst = if single then 140 else 84
	type RollSlot = { card: Frame, scale: UIScale, stroke: UIStroke?, dots: { Frame }, name: TextLabel, cx: number, classColor: Color3 }
	local slots: { RollSlot } = {}
	for i, class in classes do
		local cx = (i - (count + 1) / 2) * spacing
		local card = makeCard()
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Position = UDim2.new(0.5, cx, 0, centerY)
		card.Size = UDim2.fromOffset(104, 104)
		card.Parent = frame
		local cardScale = Instance.new("UIScale")
		cardScale.Parent = card
		local dots: { Frame } = {}
		for d = 1, dotCount do
			local dot = Instance.new("Frame")
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Size = UDim2.fromOffset(10, 10)
			dot.BorderSizePixel = 0
			dot.ZIndex = 5
			dot.Parent = frame
			corner(dot, 5)
			dots[d] = dot
		end
		local name = label(frame, "", UDim2.new(0.5, cx - 65, 0, centerY + 64), UDim2.fromOffset(130, 24), if single then 18 else 15, Enum.Font.GothamBold, WHITE)
		name.TextXAlignment = Enum.TextXAlignment.Center
		slots[i] = { card = card, scale = cardScale, stroke = card:FindFirstChildOfClass("UIStroke"), dots = dots, name = name, cx = cx, classColor = Units.Classes[class].color }
	end

	task.spawn(function()
		local function alive(): boolean
			return id == rollId and frame.Parent ~= nil
		end

		-- Swirl: the spin accelerates, the rings tighten, the cards flicker through the classes.
		local startTime = os.clock()
		local nextSwap = 0
		while alive() do
			local t = (os.clock() - startTime) / Balance.RollTime
			if t >= 1 then
				break
			end
			local spin = 5 * math.pi * t * (1 + 1.5 * t)
			local radius = ringStart - (ringStart - ringEnd) * t
			for i, slot in slots do
				for d, dot in slot.dots do
					local angle = spin * (if i % 2 == 0 then -1 else 1) + (d / dotCount) * math.pi * 2
					dot.Position = UDim2.new(0.5, slot.cx + math.cos(angle) * radius, 0, centerY + math.sin(angle) * radius)
					dot.BackgroundColor3 = if t > 0.8 then slot.classColor else Levels.color((d + i + math.floor(t * 30)) % #Levels.Colors + 1)
				end
			end
			if t >= nextSwap then
				for _, slot in slots do
					styleCard(slot.card, { class = pool[math.random(1, #pool)], tier = math.random(1, 4) })
				end
				nextSwap = t + 0.07 + 0.1 * t -- swaps slow down
			end
			RunService.RenderStepped:Wait()
		end
		if not alive() then
			return
		end

		-- Reveal (all cards at once).
		title.Text = if single then "NEW SOLDIER" else string.format("%d NEW SOLDIERS", count)
		title.TextColor3 = GOLD
		local units: { { class: string, tier: number } } = {}
		for i, slot in slots do
			local unit = { class = classes[i], tier = tiers[i] or 1 }
			units[i] = unit
			styleCard(slot.card, unit)
			if slot.stroke then
				slot.stroke.Color = slot.classColor
				slot.stroke.Thickness = 4
			end
			slot.name.Text = string.format("%s · %s", Units.Classes[unit.class].label, Levels.label(unit.tier))
			slot.scale.Scale = 0.6
			TweenService:Create(slot.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			for d, dot in slot.dots do
				local angle = (d / dotCount) * math.pi * 2
				TweenService:Create(dot, TweenInfo.new(Balance.RollReveal, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.new(0.5, slot.cx + math.cos(angle) * burst, 0, centerY + math.sin(angle) * burst),
					BackgroundTransparency = 1,
				}):Play()
			end
			for _ = 1, if single then 10 else 5 do
				confettiPop(frame, UDim2.new(0.5, slot.cx, 0, centerY), 200)
			end
		end
		task.wait(Balance.RollReveal + 0.4)
		if not alive() then
			return
		end

		-- The cards fly into the inventory panel one after another; when the last one lands the server
		-- delivers the soldiers.
		local landed = 0
		for i, slot in slots do
			task.delay((i - 1) * 0.12, function()
				flyToInventory(slot.card, units[i], function()
					landed += 1
					if landed == count then
						setPanelHighlight(true)
						task.delay(0.25, function()
							setPanelHighlight(false)
						end)
						onLanded()
					end
				end)
				slot.card.Visible = false
				slot.name.Visible = false
			end)
		end
		task.delay(0.55 + (count - 1) * 0.12, function()
			if id == rollId and rollFrame then
				local f = rollFrame
				rollFrame = nil
				TweenService:Create(frameScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.6 }):Play()
				task.delay(0.25, function()
					f:Destroy()
				end)
			end
		end)
	end)
end

-- Summoning has no roll to wait for: the soldiers are already on the board, a short message says what came out.
-- A quick reveal instead: the altar flashes, the cards pop in one after another (a rising chime each, a
-- brighter one for a high level), stay a moment and drop away. All of it is over in about a second and
-- never blocks the next summon (a new reveal replaces the old one).
local revealFrame: Frame? = nil
local function altarBurst()
	local plot = findPlot()
	local character = player.Character
	if not plot or not character then
		return
	end
	local altar: BasePart? = nil
	for _, name in { "SummonAltar", "BetterAltar" } do
		local part = plot:FindFirstChild(name)
		if part and part:IsA("BasePart") and (not altar or (part.Position - character:GetPivot().Position).Magnitude < (altar.Position - character:GetPivot().Position).Magnitude) then
			altar = part
		end
	end
	if not altar then
		return
	end
	local color = if altar.Name == "BetterAltar" then Color3.fromRGB(255, 205, 90) else Color3.fromRGB(150, 120, 255)
	local top = altar.Position + Vector3.new(0, altar.Size.Y / 2 + 0.15, 0)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 2, 2)
	ring.CFrame = CFrame.new(top) * CFrame.Angles(0, 0, math.rad(90))
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.25
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = workspace
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, 15, 15), Transparency = 1 }):Play()
	local pillar = Instance.new("Part")
	pillar.Size = Vector3.new(2.2, 1, 2.2)
	pillar.Position = top
	pillar.Material = Enum.Material.Neon
	pillar.Color = color:Lerp(Color3.new(1, 1, 1), 0.4)
	pillar.Transparency = 0.2
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Parent = workspace
	TweenService:Create(pillar, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.3, 22, 0.3), Position = top + Vector3.new(0, 11, 0), Transparency = 1 }):Play()
	task.delay(0.5, function()
		ring:Destroy()
		pillar:Destroy()
	end)
end

Net.get("RollResult").OnClientEvent:Connect(function(_pool: { string }, classes: { string }, tiers: { number })
	if revealFrame then
		revealFrame:Destroy()
	end
	local count = #classes
	local SIZE, GAP = 92, 14
	local frame = Instance.new("Frame")
	frame.Name = "SummonReveal"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.36, 0)
	frame.Size = UDim2.fromOffset(count * SIZE + (count - 1) * GAP, SIZE + 26)
	frame.BackgroundTransparency = 1
	frame.ZIndex = 40
	frame.Parent = gui
	revealFrame = frame

	playSound("summonStart")
	altarBurst()

	for i, class in classes do
		local tier = tiers[i] or 1
		local color = Levels.color(tier)
		task.delay((i - 1) * 0.09, function()
			if not frame.Parent then
				return
			end
			local x = (i - 1) * (SIZE + GAP)
			-- A flash behind the card.
			local flash = Instance.new("Frame")
			flash.AnchorPoint = Vector2.new(0.5, 0.5)
			flash.Position = UDim2.fromOffset(x + SIZE / 2, SIZE / 2)
			flash.Size = UDim2.fromOffset(SIZE * 0.6, SIZE * 0.6)
			flash.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.5)
			flash.BackgroundTransparency = 0.15
			flash.BorderSizePixel = 0
			flash.Parent = frame
			corner(flash, 60)
			TweenService:Create(flash, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(SIZE * 2, SIZE * 2), BackgroundTransparency = 1 }):Play()

			local card = makeCard()
			card.Position = UDim2.fromOffset(x, 0)
			card.Size = UDim2.fromOffset(SIZE, SIZE)
			card.Parent = frame
			styleCard(card, { class = class, tier = tier })
			local scale = Instance.new("UIScale")
			scale.Scale = 0.2
			scale.Parent = card
			card.Rotation = if i % 2 == 0 then 14 else -14
			TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 }):Play()

			local name = label(frame, string.format("%s %s", Units.Classes[class].label, Levels.label(tier)), UDim2.fromOffset(x - 20, SIZE + 4), UDim2.fromOffset(SIZE + 40, 18), 13, Enum.Font.GothamBold, color:Lerp(Color3.new(1, 1, 1), 0.35))
			name.TextXAlignment = Enum.TextXAlignment.Center
			name.TextStrokeTransparency = 0.4

			-- The chime climbs with every card; a high level rings brighter.
			playSound(if tier >= 4 then "summonRare" else "summonCard", 1 + (i - 1) * 0.12)

			-- Away: the card drops toward the inventory and fades.
			task.delay(0.85, function()
				if not card.Parent then
					return
				end
				local out = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				TweenService:Create(card, out, { Position = UDim2.fromOffset(x, 46), BackgroundTransparency = 1 }):Play()
				TweenService:Create(scale, out, { Scale = 0.5 }):Play()
				TweenService:Create(name, out, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			end)
		end)
	end
	task.delay(1.1 + count * 0.09, function()
		if revealFrame == frame then
			revealFrame = nil
		end
		frame:Destroy()
	end)
end)
end

-- ── XP orbs on the ground ─────────────────────────────────────────────────
-- Killed enemies drop XP orbs (the coins go straight to your balance): they pop out, bounce and lie
-- on the ground. Walk close and they fly to you smoothly (or they fly to you on their own after
-- Balance.CoinLifetime seconds). These are local visuals only (nobody else sees your orbs); the
-- server gives the XP when the client reports the pickup, and gives leftovers itself after a while.
do

type Coin = {
	id: number,
	part: Part,
	position: Vector3,
	velocity: Vector3,
	groundY: number,
	state: string, -- "fall" | "idle" | "fly"
	born: number,
	spin: number,
	speed: number,
	paid: boolean, -- the server already paid it (a new battle collected everything): do not report
}
local coins: { [number]: Coin } = {}
local COIN_GRAVITY = -70

local pillScale = Instance.new("UIScale")
pillScale.Parent = levelBadge -- the level badge pulses when XP is picked up
local function pulseCoins()
	pillScale.Scale = 1.2
	TweenService:Create(pillScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- A lucky kill (bonus multiplier > 1) drops bigger orbs (and more coins) and shows a floating "BONUS xN!".
local BONUS_COLORS = { [2] = Color3.fromRGB(255, 215, 90), [3] = Color3.fromRGB(255, 150, 60), [5] = Color3.fromRGB(255, 90, 140) }

local function bonusPopup(position: Vector3, multiplier: number)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.one * 0.2
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Position = position + Vector3.new(0, 5, 0)
	anchor.Parent = workspace
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(260, 44)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 300
	billboard.Parent = anchor
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.TextSize = 22 + multiplier * 3
	text.TextColor3 = BONUS_COLORS[multiplier] or GOLD
	text.TextStrokeColor3 = Color3.fromRGB(90, 50, 0)
	text.TextStrokeTransparency = 0.2
	text.Text = string.format("BONUS x%d!", multiplier)
	text.Parent = billboard
	TweenService:Create(billboard, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(text, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.4, function()
		anchor:Destroy()
	end)
end

local function makeCoinPart(multiplier: number): Part
	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball -- a glowing XP orb
	local size = 1 + 0.12 * (multiplier - 1)
	part.Size = Vector3.one * 1.3 * size
	local xpColor = Color3.fromRGB(90, 225, 255)
	part.Color = if multiplier > 1 then (BONUS_COLORS[multiplier] or GOLD):Lerp(xpColor, 0.4) else xpColor
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	return part
end

Net.get("CoinDrop").OnClientEvent:Connect(function(list: { { id: number, value: number } }, position: Vector3, multiplier: number)
	if multiplier > 1 then
		bonusPopup(position, multiplier)
	end
	for _, entry in list do
		local part = makeCoinPart(multiplier)
		local angle = math.random() * math.pi * 2
		local horizontal = 1.5 + math.random() * 3.5 -- a small scatter: the coins land close to each other
		local coin: Coin = {
			id = entry.id,
			part = part,
			position = position + Vector3.new(0, 3, 0),
			velocity = Vector3.new(math.cos(angle) * horizontal, 13 + math.random() * 8, math.sin(angle) * horizontal),
			groundY = position.Y + 0.9,
			state = "fall",
			born = os.clock(),
			spin = math.random() * 6,
			speed = 0,
			paid = false,
		}
		part.CFrame = CFrame.new(coin.position)
		part.Parent = workspace
		coins[entry.id] = coin
	end
end)

-- A new battle started: the server already paid every coin still lying around, so they just
-- fly to the player and vanish.
Net.get("CoinsClear").OnClientEvent:Connect(function()
	for _, coin in coins do
		coin.state = "fly"
		coin.paid = true
	end
end)

local function collectCoin(coin: Coin)
	coins[coin.id] = nil
	coin.part:Destroy()
	if not coin.paid then
		Net.get("CollectCoin"):FireServer(coin.id)
	end
	pulseCoins()
end

RunService.RenderStepped:Connect(function(dt)
	if next(coins) == nil then
		return
	end
	local root = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
	local target = if root and root:IsA("BasePart") then root.Position + Vector3.new(0, 1.5, 0) else nil
	local now = os.clock()

	for _, coin in coins do
		coin.spin += dt * 6
		if coin.state == "fall" then
			coin.velocity += Vector3.new(0, COIN_GRAVITY * dt, 0)
			coin.position += coin.velocity * dt
			if coin.position.Y <= coin.groundY and coin.velocity.Y < 0 then
				coin.position = Vector3.new(coin.position.X, coin.groundY, coin.position.Z)
				if -coin.velocity.Y < 6 then
					coin.velocity = Vector3.zero
					coin.state = "idle" -- settled on the ground
				else
					-- Bounce: lose some height and slide a bit less.
					coin.velocity = Vector3.new(coin.velocity.X * 0.45, -coin.velocity.Y * 0.45, coin.velocity.Z * 0.45)
				end
			end
		elseif coin.state == "idle" then
			local expired = now - coin.born > Balance.CoinLifetime
			if expired or (target and (target - coin.position).Magnitude <= Balance.CoinMagnetRadius) then
				coin.state = "fly"
			end
		else
			-- Flying to the player: starts slowly and accelerates, so the pickup looks smooth.
			if target then
				local toTarget = target - coin.position
				local distance = toTarget.Magnitude
				if distance < 3.8 then
					collectCoin(coin)
					continue
				end
				coin.speed = math.min(coin.speed + 170 * dt, 100)
				coin.position += toTarget.Unit * math.min(distance, (16 + coin.speed) * dt)
			end
		end
		local bob = if coin.state == "idle" then math.sin(now * 4 + coin.id) * 0.15 else 0
		coin.part.CFrame = CFrame.new(coin.position + Vector3.new(0, bob, 0)) * CFrame.Angles(0, coin.spin, 0)
	end
end)
end

-- ── Confirmation popups ───────────────────────────────────────────────────
-- Buying a soldier and starting a wave are done with the mouse on the bottom bar (no hotkeys),
-- and both ask first: "Buy another soldier?" and "Start this wave on this difficulty?".

local confirmLayer: GuiObject? = nil
-- Optional confirm hotkey of the open popup: pressing the same key again confirms (buying: E, E).
local confirmKeyCode: Enum.KeyCode? = nil
local confirmCallback: (() -> ())? = nil

local function closeConfirm()
	if confirmLayer then
		confirmLayer:Destroy()
		confirmLayer = nil
	end
	confirmKeyCode = nil
	confirmCallback = nil
end

local function askConfirm(title: string, lines: { string }, confirmText: string, accent: Color3, onConfirm: () -> (), confirmKey: Enum.KeyCode?, extraText: string?, onExtra: (() -> ())?)
	closeConfirm()
	confirmKeyCode = confirmKey
	confirmCallback = onConfirm

	-- A dim layer over the whole screen: it blocks the 3D world, and clicking it cancels.
	local layer = Instance.new("TextButton")
	layer.Size = UDim2.fromScale(1, 1)
	layer.BackgroundColor3 = Color3.new(0, 0, 0)
	layer.BackgroundTransparency = 0.55
	layer.BorderSizePixel = 0
	layer.AutoButtonColor = false
	layer.Text = ""
	layer.ZIndex = 60
	layer.Parent = gui
	layer.Activated:Connect(closeConfirm)
	confirmLayer = layer

	local dialog = Instance.new("Frame")
	dialog.AnchorPoint = Vector2.new(0.5, 0.5)
	dialog.Position = UDim2.fromScale(0.5, 0.5)
	dialog.Size = UDim2.fromOffset(360, 118 + 22 * #lines)
	dialog.BackgroundColor3 = BG
	dialog.BorderSizePixel = 0
	dialog.Active = true -- clicks on the dialog do not cancel
	dialog.ZIndex = 61
	dialog.Parent = layer
	corner(dialog, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = accent
	stroke.Thickness = 3
	stroke.Parent = dialog
	local scale = Instance.new("UIScale")
	scale.Scale = 0.7
	scale.Parent = dialog
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local function text(value: string, y: number, size: number, font: Enum.Font, color: Color3): TextLabel
		local l = label(dialog, value, UDim2.fromOffset(16, y), UDim2.new(1, -32, 0, size + 6), size, font, color)
		l.ZIndex = 62
		l.TextXAlignment = Enum.TextXAlignment.Center
		return l
	end
	text(title, 14, 22, Enum.Font.GothamBlack, WHITE)
	for i, line in lines do
		text(line, 44 + (i - 1) * 22, 15, if i == 1 then Enum.Font.GothamBold else Enum.Font.Gotham, if i == 1 then WHITE else MUTED)
	end

	local buttonWidth = if extraText then 104 else 150
	local function button(caption: string, x: number, color: Color3, action: () -> ())
		local b = Instance.new("TextButton")
		b.Position = UDim2.new(0, x, 1, -54)
		b.Size = UDim2.fromOffset(buttonWidth, 40)
		b.BackgroundColor3 = color
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold
		b.TextSize = if extraText then 14 else 16
		b.TextColor3 = WHITE
		b.Text = caption
		b.ZIndex = 62
		b.Parent = dialog
		corner(b, 10)
		b.Activated:Connect(action)
	end
	local keyHint = if confirmKey then string.format("  [%s]", confirmKey.Name) else ""
	if extraText and onExtra then
		button(confirmText .. keyHint, 16, accent:Lerp(BG, 0.25), function()
			closeConfirm()
			onConfirm()
		end)
		button(extraText, 128, accent:Lerp(BG, 0.25), function()
			closeConfirm()
			onExtra()
		end)
		button("CANCEL", 240, BADGE, closeConfirm)
	else
		button(confirmText .. keyHint, 20, accent:Lerp(BG, 0.25), function()
			closeConfirm()
			onConfirm()
		end)
		button("CANCEL", 190, BADGE, closeConfirm)
	end
end

-- The "+" card of the inventory: asks first, with the price.
requestSlots = function()
	if state.rolling or state.battling or state.upgradeMaxed then
		return
	end
	askConfirm("More merge slots?", {
		string.format("+%d slots for %d coins", Balance.BoardUpgradeStep, state.upgradeCost),
		string.format("You have %d coins · slots %d/%d", state.coins, state.boardSlots, state.boardMax),
	}, "BUY", Color3.fromRGB(170, 130, 255), function()
		Net.get("Upgrade"):FireServer()
	end)
end

local function requestBuy()
	if state.rolling or state.battling then
		return
	end
	if state.boardFree <= 0 then
		Net.get("Buy"):FireServer() -- the server says why it is not possible (full inventory)
		return
	end
	askConfirm("Get a character?", {
		"Characters are FREE",
		string.format("Free places in your inventory: %d", state.boardFree),
		"A random character goes to your inventory (the merge room).",
	}, "GET", GREEN, function()
		Net.get("Buy"):FireServer(1)
	end, Enum.KeyCode.E) -- E opens this popup, E again confirms
end

-- PLAY: opens / closes the battle panel (wave, difficulty and START WAVE) in the middle of the screen.
local function requestFight()
	if state.rolling or state.battling then
		return
	end
	UI.battleOpen = not UI.battleOpen
end

-- ── Spells: Q and E (the two spells you carry) ──────────────────────────
-- During a battle press Q or E (or click the buttons) to cast the spell you carry in that slot. They aim
-- themselves (auto aim: the biggest group of enemies, the group that needs healing ...); hold SHIFT to aim
-- with the mouse (a ring shows where). Which two spells you carry is chosen in the SPELLS tab of the left
-- panel. Every slot has its own cooldown (the server owns it and tells the client).

-- Set below; called from the key handler at the end of the file (Q / E).
local castSpell: (string) -> () = function() end

do
	type SpellButton = { slot: string, key: string, readyAt: number, cooldown: number, fill: Frame, titleLabel: TextLabel, subLabel: TextLabel, button: TextButton, stroke: UIStroke }
	local buttons: { [string]: SpellButton } = {}
	local width = 150

	for i, slot in { "q", "e" } do
		local button = Instance.new("TextButton")
		button.Name = "Spell_" .. slot
		button.AnchorPoint = Vector2.new(1, 1)
		button.Position = UDim2.new(1, -18 - (2 - i) * (width + 8), 1, -18)
		button.Size = UDim2.fromOffset(width, 64)
		button.BackgroundColor3 = BG
		button.BackgroundTransparency = 0.1
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Text = ""
		button.ClipsDescendants = true
		button.Visible = false
		button.Parent = gui
		corner(button, 12)
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Parent = button
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundTransparency = 0.7
		fill.BorderSizePixel = 0
		fill.Parent = button
		local titleLabel = label(button, "", UDim2.fromOffset(0, 8), UDim2.new(1, 0, 0, 24), 16, Enum.Font.GothamBlack, WHITE)
		titleLabel.TextXAlignment = Enum.TextXAlignment.Center
		local subLabel = label(button, "", UDim2.fromOffset(0, 34), UDim2.new(1, 0, 0, 18), 12, Enum.Font.GothamMedium, GOLD)
		subLabel.TextXAlignment = Enum.TextXAlignment.Center
		buttons[slot] = { slot = slot, key = string.upper(slot), readyAt = 0, cooldown = 1, fill = fill, titleLabel = titleLabel, subLabel = subLabel, button = button, stroke = stroke }
	end

	-- The spell in a slot (nil-safe).
	local function spellOf(slot: string): (string?, Spells.Def?)
		local id = (state.spells.slots :: { [string]: string })[slot]
		return id, Spells.Defs[id]
	end

	-- Where the mouse points on the arena floor (nil when it points at the sky).
	local function aimPoint(): Vector3?
		local plot = findPlot()
		local arena = if plot then plot:FindFirstChild("FightArena") else nil
		if not arena or not arena:IsA("BasePart") then
			return nil
		end
		return groundPoint(arena.Position.Y + arena.Size.Y / 2)
	end

	local function shiftHeld(): boolean
		return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	end

	castSpell = function(slot: string)
		local spell = buttons[slot]
		local _, def = spellOf(slot)
		if not spell or not def or not state.battling or confirmLayer or os.clock() < spell.readyAt then
			return
		end
		-- Auto aim: the server picks the target. Hold SHIFT to aim with the mouse instead.
		if def.aimed and shiftHeld() then
			local point = aimPoint()
			if point then
				Net.get("Ability"):FireServer(slot, point)
			end
		else
			Net.get("Ability"):FireServer(slot)
		end
	end

	for slot, spell in buttons do
		spell.button.Activated:Connect(function()
			castSpell(slot)
		end)
	end
	Net.get("Ability").OnClientEvent:Connect(function(slot: string, cooldown: number)
		local spell = buttons[slot]
		if spell then
			spell.cooldown = cooldown
			spell.readyAt = os.clock() + cooldown
		end
	end)

	-- A small hint above the buttons.
	local hint = label(gui, "Spells aim themselves · hold SHIFT to aim with the mouse", UDim2.new(1, -18 - 2 * (width + 8) + 8, 1, -90), UDim2.fromOffset(2 * (width + 8) - 8, 16), 12, Enum.Font.GothamMedium, MUTED)
	hint.TextXAlignment = Enum.TextXAlignment.Right
	hint.Visible = false

	-- The ring on the floor that shows where an aimed spell would land (only while SHIFT is held).
	local ring = Instance.new("Part")
	ring.Name = "SpellRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = Color3.fromRGB(255, 190, 120)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.7
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false

	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		hint.Visible = state.battling and not IS_TOUCH
		local aimedRadius: number? = nil
		local aimedColor = Color3.fromRGB(255, 190, 120)
		for slot, spell in buttons do
			local _, def = spellOf(slot)
			spell.button.Visible = state.battling and def ~= nil
			if def then
				spell.titleLabel.Text = string.format("[%s] %s", spell.key, string.upper(def.label))
				spell.stroke.Color = def.color
				spell.fill.BackgroundColor3 = def.color
				if def.aimed and def.radius then
					aimedRadius, aimedColor = def.radius, def.color
				end
				if state.battling then
					local left = spell.readyAt - now
					if left > 0 then
						spell.subLabel.Text = string.format("%ds", math.ceil(left))
						spell.subLabel.TextColor3 = MUTED
						spell.fill.Size = UDim2.fromScale(math.clamp(1 - left / spell.cooldown, 0, 1), 1)
						spell.titleLabel.TextTransparency = 0.5
					else
						spell.subLabel.Text = def.hint
						spell.subLabel.TextColor3 = GOLD
						spell.fill.Size = UDim2.fromScale(1, 1)
						spell.titleLabel.TextTransparency = 0
					end
				else
					spell.readyAt = 0 -- every wave starts with the spells ready
				end
			end
		end
		if state.battling and aimedRadius and shiftHeld() then
			local point = aimPoint()
			if point then
				ring.Size = Vector3.new(0.15, aimedRadius * 2, aimedRadius * 2)
				ring.Color = aimedColor
				ring.CFrame = CFrame.new(point + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
				ring.Parent = workspace
			else
				ring.Parent = nil
			end
		else
			ring.Parent = nil
		end
	end)
end

-- ── Admin tools (only for the owner / in Studio) ─────────────────────────
do

-- A small red ADMIN button in the top right corner; a click opens the test tools under it: progress, coins,
-- the wave, spawning any character at any level into the inventory, clearing the inventory, a reset.
local PANEL_W = 236
local PANEL_H = 318
local adminOpen = false
local adminClass = 1 -- index into Units.ClassList
local adminTier = 1

local toggle = Instance.new("TextButton")
toggle.Name = "AdminToggle"
toggle.AnchorPoint = Vector2.new(1, 0)
toggle.Position = UDim2.new(1, -14, 0, 14)
toggle.Size = UDim2.fromOffset(92, 30)
toggle.BackgroundColor3 = BG
toggle.BackgroundTransparency = 0.15
toggle.BorderSizePixel = 0
toggle.AutoButtonColor = false
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 12
toggle.TextColor3 = RED
toggle.Text = "ADMIN  ▾"
toggle.Visible = false
toggle.Parent = gui
corner(toggle, 8)
UI.stroke(toggle, RED, 1.5, 0.3)
toggle.Activated:Connect(function()
	adminOpen = not adminOpen
	toggle.Text = if adminOpen then "ADMIN  ▴" else "ADMIN  ▾"
end)

local adminPanel = Instance.new("Frame")
adminPanel.Name = "AdminPanel"
adminPanel.AnchorPoint = Vector2.new(1, 0)
adminPanel.Position = UDim2.new(1, -14, 0, 50)
adminPanel.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
adminPanel.BackgroundColor3 = BG
adminPanel.BackgroundTransparency = 0.08
adminPanel.BorderSizePixel = 0
adminPanel.Active = true
adminPanel.Visible = false
adminPanel.Parent = gui
corner(adminPanel, 10)
UI.stroke(adminPanel, RED, 1.5, 0.3)

local function section(text: string, y: number)
	label(adminPanel, text, UDim2.fromOffset(10, y), UDim2.fromOffset(PANEL_W - 20, 14), 10, Enum.Font.GothamBold, MUTED)
end

local function adminButton(text: string, x: number, y: number, w: number, color: Color3, action: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(x, y)
	b.Size = UDim2.fromOffset(w, 28)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.TextColor3 = WHITE
	b.Text = text
	b.Parent = adminPanel
	corner(b, 7)
	b.Activated:Connect(action)
	return b
end

local function command(name: string, a: any?, b: any?)
	Net.get("AdminCommand"):FireServer(name, a, b)
end

-- Progress
section("PROGRESS", 8)
adminButton("+ PROGRESS", 10, 24, 104, GREEN:Lerp(BG, 0.3), function()
	Net.get("AdminProgress"):FireServer()
end)
adminButton("UNLOCK ALL", 122, 24, 104, GOLD:Lerp(BG, 0.45), function()
	Net.get("AdminUnlock"):FireServer()
end)

-- Coins
section("COINS", 60)
for i, amount in { 1000, 10000, 100000 } do
	adminButton(string.format("+%dk", amount // 1000), 10 + (i - 1) * 74, 76, 68, GOLD:Lerp(BG, 0.55), function()
		command("coins", amount)
	end)
end

-- Wave
local waveTitle = label(adminPanel, "WAVE", UDim2.fromOffset(10, 112), UDim2.fromOffset(PANEL_W - 20, 14), 10, Enum.Font.GothamBold, MUTED)
adminButton("−5", 10, 128, 68, BADGE, function()
	command("wave", state.wave - 5)
end)
adminButton("+5", 84, 128, 68, BADGE, function()
	command("wave", state.wave + 5)
end)
adminButton("MAX", 158, 128, 68, BADGE, function()
	command("wave", state.mapWaves)
end)

-- Spawn: a class (cycled with the arrows) at a level (− / +), one of it or all nine levels.
section("SPAWN INTO THE INVENTORY", 164)
local classLabel = label(adminPanel, "", UDim2.fromOffset(40, 180), UDim2.fromOffset(PANEL_W - 80, 28), 13, Enum.Font.GothamBold, WHITE)
classLabel.TextXAlignment = Enum.TextXAlignment.Center
adminButton("<", 10, 180, 26, BADGE, function()
	adminClass = (adminClass - 2) % #Units.ClassList + 1
	adminTier = math.min(adminTier, Units.maxTier(Units.ClassList[adminClass]))
end)
adminButton(">", PANEL_W - 36, 180, 26, BADGE, function()
	adminClass = adminClass % #Units.ClassList + 1
	adminTier = math.min(adminTier, Units.maxTier(Units.ClassList[adminClass]))
end)
local tierLabel = label(adminPanel, "", UDim2.fromOffset(40, 212), UDim2.fromOffset(PANEL_W - 80, 28), 13, Enum.Font.GothamBold, GOLD)
tierLabel.TextXAlignment = Enum.TextXAlignment.Center
adminButton("−", 10, 212, 26, BADGE, function()
	adminTier = math.max(1, adminTier - 1)
end)
adminButton("+", PANEL_W - 36, 212, 26, BADGE, function()
	adminTier = math.min(Units.maxTier(Units.ClassList[adminClass]), adminTier + 1)
end)
adminButton("SPAWN 1", 10, 246, 104, GREEN:Lerp(BG, 0.3), function()
	command("spawn", Units.ClassList[adminClass], adminTier)
end)
adminButton("SPAWN ALL LVS", 122, 246, 104, GREEN:Lerp(BG, 0.45), function()
	command("spawnall", Units.ClassList[adminClass])
end)

-- Inventory and reset
adminButton("CLEAR INVENTORY", 10, 280, 104, BADGE, function()
	command("clear")
end)
adminButton("ALL SLOTS", 122, 280, 48, BADGE, function()
	command("slots")
end)
adminButton("RESET", 178, 280, 48, RED:Lerp(BG, 0.4), function()
	askConfirm("Reset everything?", {
		"Admin reset",
		"Coins, characters, waves and unlocks are wiped",
		"(the saved data too). This cannot be undone.",
	}, "RESET", RED, function()
		Net.get("AdminReset"):FireServer()
	end)
end)

RunService.RenderStepped:Connect(function()
	toggle.Visible = state.isAdmin
	adminPanel.Visible = state.isAdmin and adminOpen
	UI.adminHeight = if not state.isAdmin then 0 elseif adminOpen then 36 + PANEL_H else 30
	if not adminPanel.Visible then
		return
	end
	waveTitle.Text = string.format("WAVE  ·  now %d of %d", state.wave, state.mapWaves)
	local class = Units.ClassList[adminClass]
	classLabel.Text = Units.Classes[class].label
	classLabel.TextColor3 = Units.Classes[class].color
	tierLabel.Text = string.format("Level %d", adminTier)
	tierLabel.TextColor3 = Levels.color(adminTier)
end)
end

-- ── Squad pad rings (animation) ────────────────────────────────────────────
-- The server builds the holographic ring of every squad pad (Plots, holoPad). Here an EMPTY ring breathes
-- (its glow comes and goes) so it asks for a soldier; a taken ring stays grey and still. Only on the client.
do
	local time = 0
	RunService.RenderStepped:Connect(function(dt)
		time += dt
		local plot = findPlot()
		if not plot then
			return
		end
		for i = 1, Balance.SquadSize do
			local pad = plot:FindFirstChild("Slot" .. (Balance.SquadOffset + i))
			if not pad or pad:GetAttribute("Occupied") ~= false then
				continue
			end
			local wave = (math.sin(time * 2.2 + i * 1.1) + 1) / 2 -- 0 … 1
			for _, name in { "HoloRing", "HoloFill" } do
				local part = pad:FindFirstChild(name)
				if part and part:IsA("BasePart") then
					local base = part:GetAttribute("BaseTransparency")
					if type(base) == "number" then
						part.Transparency = base + wave * 0.22
					end
				end
			end
			local ring = pad:FindFirstChild("HoloRing")
			local glow = ring and ring:FindFirstChild("Glow")
			if glow and glow:IsA("PointLight") then
				glow.Brightness = 0.8 + (1 - wave) * 0.9
			end
		end
	end)
end

-- ── Arena holograms ────────────────────────────────────────────────────────
-- The see-through copies of your squad on the arena floor (built by the server, see `Plots.renderHolograms`)
-- float gently here, each with its own timing, and disappear while a battle runs. Every part
-- is moved on its own from the CFrame it arrived with (and a marker is only used when all its parts have
-- arrived), so an arrow can never jump somewhere else while it is still being replicated.
do
	type Piece = { part: BasePart, cf: CFrame }
	type Marker = { model: Model, phase: number, pieces: { Piece } }
	local markers: { Marker } = {}
	local known: { [Model]: boolean } = {}

	task.spawn(function()
		while true do
			local plot = findPlot()
			local folder = if plot then plot:FindFirstChild("ArenaSlots") else nil
			if folder then
				for _, child in folder:GetChildren() do
					if child:IsA("Model") and not known[child] then
						local expected = child:GetAttribute("Parts")
						local pieces: { Piece } = {}
						for _, part in child:GetChildren() do
							if part:IsA("BasePart") then
								table.insert(pieces, { part = part, cf = part.CFrame })
							end
						end
						if type(expected) == "number" and #pieces == expected then
							known[child] = true
							table.insert(markers, { model = child, phase = child:GetAttribute("Phase") or 0, pieces = pieces })
						end
					end
				end
			end
			task.wait(1)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local time = os.clock()
		local hidden = if state.battling or state.settings.arrows == false then 1 else 0
		for _, marker in markers do
			if marker.model.Parent then
				local offset = Vector3.new(0, 0.3 + math.sin(time * 2 + marker.phase) * 0.25, 0)
				for _, piece in marker.pieces do
					piece.part.CFrame = piece.cf + offset
					piece.part.LocalTransparencyModifier = hidden
				end
			end
		end
	end)
end

-- ── Summoning altars (lobby) ──────────────────────────────────────────────
-- The first altar summons 3 soldiers for coins (E); the gold BETTER altar next to it needs wave 10 of
-- Training Camp and gives better levels. Both have a cooldown after a summon. The prompts are made here
-- (on the client) so only their owner sees them on his own plot.
do
	local prompts: { [string]: ProximityPrompt } = {}
	local readyAt: { [string]: number } = { SummonAltar = 0, BetterAltar = 0 }
	task.spawn(function()
		while true do

			local plot = findPlot()
			for name, action in { SummonAltar = "Summon characters", BetterAltar = "Better summon" } do
				local part = if plot then plot:FindFirstChild(name) else nil
				local prompt = prompts[name]
				if part and (not prompt or not prompt.Parent) then
					local made = Instance.new("ProximityPrompt")
					made.ActionText = action
					made.KeyboardKeyCode = Enum.KeyCode.E
					made.GamepadKeyCode = Enum.KeyCode.ButtonX
					made.HoldDuration = 0
					made.MaxActivationDistance = 9
					made.RequiresLineOfSight = false
					made.Parent = part
					made.Triggered:Connect(function()
						if os.clock() < readyAt[name] then
							return -- too soon: no spamming
						end
						readyAt[name] = os.clock() + Balance.SummonCooldown
						Net.get("Buy"):FireServer(if name == "BetterAltar" then "better" else 1)
					end)
					prompts[name] = made
					prompt = made
				end
				if prompt then
					prompt.Enabled = not (state.rolling or state.battling)
					local left = readyAt[name] - os.clock()
					if left > 0 then
						prompt.ObjectText = string.format("Ready in %ds", math.ceil(left))
					elseif name == "BetterAltar" then
						prompt.ObjectText = if state.cleared >= Balance.BetterSummonWave then string.format("%d coins · %d characters · better levels", Balance.BetterSummonCost, Balance.SummonCount) else string.format("Locked · clear wave %d", Balance.BetterSummonWave)
					else
						prompt.ObjectText = string.format("%d coins · %d characters", Balance.SummonCost, Balance.SummonCount)
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

-- ── Daily quests ──────────────────────────────────────────────────────────
-- Three small goals a day (Balance.Quests); a finished one pays coins and XP. Above the HUD.
do
	local questPanel = Instance.new("Frame")
	questPanel.Name = "Quests"
	questPanel.AnchorPoint = Vector2.new(1, 0.5)
	questPanel.Position = UDim2.new(1, -14, 0.5, 0) -- right side
	questPanel.Size = UDim2.fromOffset(214, 82)
	questPanel.BackgroundColor3 = BG
	questPanel.BackgroundTransparency = 0.25
	questPanel.BorderSizePixel = 0
	questPanel.Visible = false
	questPanel.Parent = gui
	corner(questPanel, 10)
	UI.stroke(questPanel, Color3.fromRGB(70, 76, 100), 1.5, 0.3)
	label(questPanel, "DAILY QUESTS", UDim2.fromOffset(10, 4), UDim2.fromOffset(150, 14), 11, Enum.Font.GothamBold, MUTED)
	UI.grip(questPanel, 190, 6, MUTED)
	if UI.QUESTS then
		Layout.make("Quests", questPanel, questPanel) -- grab it anywhere, it has no controls
	end

	local rows: { { text: TextLabel, count: TextLabel } } = {}
	for i = 1, 3 do
		local y = 22 + (i - 1) * 18
		local text = label(questPanel, "", UDim2.fromOffset(10, y), UDim2.fromOffset(150, 16), 12, Enum.Font.GothamMedium, WHITE)
		local count = label(questPanel, "", UDim2.fromOffset(150, y), UDim2.fromOffset(56, 16), 12, Enum.Font.GothamBold, GOLD)
		count.TextXAlignment = Enum.TextXAlignment.Right
		rows[i] = { text = text, count = count }
	end

	RunService.RenderStepped:Connect(function()
		questPanel.Visible = UI.QUESTS and #state.quests > 0 and not state.battling -- the fight needs the room
		for i, row in rows do
			local quest = state.quests[i]
			if quest then
				row.text.Text = quest.label
				if quest.done then
					row.count.Text = "DONE"
					row.count.TextColor3 = GREEN
					row.text.TextColor3 = MUTED
				else
					row.count.Text = string.format("%d/%d", quest.progress, quest.target)
					row.count.TextColor3 = GOLD
					row.text.TextColor3 = WHITE
				end
			else
				row.text.Text = ""
				row.count.Text = ""
			end
		end
	end)
end

-- ── Sounds from the server, music ──────────────────────────────────────
do
	Net.get("Sfx").OnClientEvent:Connect(function(name: string)
		playSound(name)
	end)
	if Sounds.Music ~= "" then
		local music = Instance.new("Sound")
		music.Name = "Music"
		music.SoundId = Sounds.Music
		music.Looped = true
		music.Volume = Sounds.MusicVolume
		music.Parent = SoundService
		music:Play()
		RunService.RenderStepped:Connect(function()
			music.Volume = if state.settings.music == false then 0 else Sounds.MusicVolume * soundVolume
		end)
	end
end

-- ── During a battle ────────────────────────────────────────────────────────
-- The camera stays yours (the server puts you into the arena for your spells); only the main panel steps
-- aside while the battle runs, so the fight is not covered. It also steps aside while the battle panel (PLAY)
-- is open, so the two never lie over each other, and comes back when that closes.
do
	RunService.RenderStepped:Connect(function()
		panel.Visible = not state.battling and not UI.hidden and not UI.battleOpen
		UI.squadBar.Visible = not state.battling
	end)
end

-- ── Welcome back popup (offline income) ────────────────────────────────────
do
	Net.get("WelcomeBack").OnClientEvent:Connect(function(reward: any)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.new(0.5, 0, 0.36, 0)
		frame.Size = UDim2.fromOffset(380, 0)
		frame.AutomaticSize = Enum.AutomaticSize.Y
		frame.BackgroundColor3 = BG
		frame.BackgroundTransparency = 0.05
		frame.BorderSizePixel = 0
		frame.Active = true
		frame.ZIndex = 45
		frame.Parent = gui
		corner(frame, 14)
		local stroke = Instance.new("UIStroke")
		stroke.Color = GOLD
		stroke.Thickness = 3
		stroke.Parent = frame
		local padding = Instance.new("UIPadding")
		padding.PaddingTop = UDim.new(0, 12)
		padding.PaddingBottom = UDim.new(0, 14)
		padding.Parent = frame
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 6)
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
		list.Parent = frame
		local function line(text: string, size: number, font: Enum.Font, color: Color3)
			local l = Instance.new("TextLabel")
			l.Size = UDim2.new(1, -24, 0, size + 6)
			l.BackgroundTransparency = 1
			l.Font = font
			l.TextSize = size
			l.TextColor3 = color
			l.TextWrapped = true
			l.Text = text
			l.ZIndex = 46
			l.Parent = frame
		end
		line("WELCOME BACK", 24, Enum.Font.GothamBlack, GOLD)
		line(string.format("While you were away (%.1f h) your camp earned", reward.hours), 14, Enum.Font.GothamMedium, WHITE)
		line(string.format("+%d coins", reward.coins), 20, Enum.Font.GothamBlack, GREEN)
		line("(click to close)", 11, Enum.Font.Gotham, MUTED)
		frame.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				frame:Destroy()
			end
		end)
		task.delay(8, function()
			if frame.Parent then
				frame:Destroy()
			end
		end)
	end)
end

-- ── Achievements list ──────────────────────────────────────────────────────
-- A button under the daily quests opens the list of every achievement with its progress.
do
	local open = false
	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, -14, 0.5, 56)
	button.Size = UDim2.fromOffset(214, 26)
	button.BackgroundColor3 = BG
	button.BackgroundTransparency = 0.25
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.TextSize = 12
	button.TextColor3 = GOLD
	button.Text = "ACHIEVEMENTS"
	button.Parent = gui
	corner(button, 8)

	local panel = Instance.new("ScrollingFrame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(440, 420)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.ScrollBarThickness = 5
	panel.CanvasSize = UDim2.new()
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.Active = true
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = gui
	corner(panel, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 3
	stroke.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = panel
	local heading = Instance.new("TextLabel")
	heading.LayoutOrder = 0
	heading.Size = UDim2.new(1, -20, 0, 30)
	heading.BackgroundTransparency = 1
	heading.Font = Enum.Font.GothamBlack
	heading.TextSize = 22
	heading.TextColor3 = GOLD
	heading.Text = "ACHIEVEMENTS  (click to close)"
	heading.ZIndex = 31
	heading.Parent = panel

	type Row = { frame: Frame, progress: TextLabel }
	local rows: { [string]: Row } = {}
	for i, def in Achievements.List do
		local row = Instance.new("Frame")
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -24, 0, 46)
		row.BackgroundColor3 = BADGE
		row.BorderSizePixel = 0
		row.ZIndex = 31
		row.Parent = panel
		corner(row, 8)
		local name = label(row, string.format("★ %s", def.label), UDim2.fromOffset(10, 4), UDim2.fromOffset(300, 18), 14, Enum.Font.GothamBold, WHITE)
		name.ZIndex = 32
		local text = label(row, string.format("%s · +%d coins%s", def.text, def.coins, if def.xp > 0 then string.format(" · +%d XP", def.xp) else ""), UDim2.fromOffset(10, 24), UDim2.fromOffset(320, 16), 11, Enum.Font.Gotham, MUTED)
		text.ZIndex = 32
		local progress = label(row, "", UDim2.fromOffset(320, 0), UDim2.fromOffset(90, 46), 13, Enum.Font.GothamBold, GOLD)
		progress.TextXAlignment = Enum.TextXAlignment.Right
		progress.ZIndex = 32
		rows[def.id] = { frame = row, progress = progress }
	end

	button.Activated:Connect(function()
		open = not open
		playSound("click")
	end)
	panel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			open = false
		end
	end)

	local function statValue(key: string): number
		if key == "level" then
			return state.level
		end
		return state.stats[key] or 0
	end

	RunService.RenderStepped:Connect(function()
		local done = 0
		for _, def in Achievements.List do
			if state.achievements[def.id] then
				done += 1
			end
		end
		button.Visible = UI.ACHIEVEMENTS and not state.battling
		button.Text = string.format("ACHIEVEMENTS  %d/%d%s", done, #Achievements.List, if state.title then "  ·  ★ " .. state.title else "")
		panel.Visible = UI.ACHIEVEMENTS and open and not state.battling
		if not panel.Visible then
			return
		end
		for _, def in Achievements.List do
			local row = rows[def.id]
			local finished = state.achievements[def.id] == true
			row.frame.BackgroundTransparency = if finished then 0 else 0.4
			row.progress.Text = if finished then "DONE" else string.format("%d/%d", math.min(statValue(def.stat), def.target), def.target)
			row.progress.TextColor3 = if finished then GREEN else GOLD
		end
	end)
end

-- ── Settings (gear button, top right) ──────────────────────────────────────
do
	local open = false
	local gear = Instance.new("TextButton")
	gear.AnchorPoint = Vector2.new(1, 0)
	gear.Position = UDim2.new(1, -14, 0, 160)
	gear.Size = UDim2.fromOffset(40, 40)
	gear.BackgroundColor3 = BG
	gear.BackgroundTransparency = 0.15
	gear.BorderSizePixel = 0
	gear.AutoButtonColor = false
	gear.Font = Enum.Font.GothamBlack
	gear.TextSize = 22
	gear.TextColor3 = MUTED
	gear.Text = "⚙"
	gear.Parent = gui
	corner(gear, 10)

	local panel = Instance.new("Frame")
	panel.Name = "SettingsPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -60, 0, 160)
	panel.Size = UDim2.fromOffset(250, 250)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.05
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	UI.stroke(panel, Color3.fromRGB(70, 76, 100), 1.5)
	-- The title bar is the drag handle.
	local titleBar = Instance.new("Frame")
	titleBar.Size = UDim2.new(1, 0, 0, 34)
	titleBar.BackgroundTransparency = 1
	titleBar.Parent = panel
	UI.grip(titleBar, 12, 12, MUTED)
	local title = label(titleBar, "SETTINGS", UDim2.fromOffset(0, 6), UDim2.new(1, 0, 0, 22), 16, Enum.Font.GothamBlack, WHITE)
	title.TextXAlignment = Enum.TextXAlignment.Center
	Layout.make("Settings", panel, titleBar)

	-- RESET LAYOUT: every movable panel goes back where it started.
	local resetButton = Instance.new("TextButton")
	resetButton.Position = UDim2.fromOffset(14, 208)
	resetButton.Size = UDim2.new(1, -28, 0, 28)
	resetButton.BackgroundColor3 = BADGE
	resetButton.BorderSizePixel = 0
	resetButton.AutoButtonColor = false
	resetButton.Font = Enum.Font.GothamBold
	resetButton.TextSize = 12
	resetButton.TextColor3 = WHITE
	resetButton.Text = "RESET LAYOUT  (panel positions)"
	resetButton.Parent = panel
	corner(resetButton, 8)
	resetButton.Activated:Connect(function()
		Layout.reset()
	end)

	-- Volume: - and +.
	label(panel, "Volume", UDim2.fromOffset(14, 40), UDim2.fromOffset(120, 24), 13, Enum.Font.GothamMedium, WHITE)
	local volumeText = label(panel, "", UDim2.fromOffset(150, 40), UDim2.fromOffset(40, 24), 13, Enum.Font.GothamBold, GOLD)
	volumeText.TextXAlignment = Enum.TextXAlignment.Center
	local function volumeButton(text: string, x: number, delta: number)
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(x, 40)
		b.Size = UDim2.fromOffset(26, 24)
		b.BackgroundColor3 = BADGE
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.TextColor3 = WHITE
		b.Text = text
		b.Parent = panel
		corner(b, 6)
		b.Activated:Connect(function()
			Net.get("SetSetting"):FireServer("volume", math.clamp((state.settings.volume or 1) + delta, 0, 1))
			playSound("click")
		end)
	end
	volumeButton("-", 122, -0.1)
	volumeButton("+", 192, 0.1)

	-- On / off switches.
	local toggles: { [string]: TextButton } = {}
	local names = { { "numbers", "Damage numbers" }, { "arrows", "Arena holograms" }, { "music", "Music" } }
	for i, entry in names do
		local key, text = entry[1], entry[2]
		local y = 74 + (i - 1) * 32
		label(panel, text, UDim2.fromOffset(14, y), UDim2.fromOffset(150, 24), 13, Enum.Font.GothamMedium, WHITE)
		local b = Instance.new("TextButton")
		b.Position = UDim2.fromOffset(168, y)
		b.Size = UDim2.fromOffset(68, 24)
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Font = Enum.Font.GothamBold
		b.TextSize = 12
		b.TextColor3 = WHITE
		b.Parent = panel
		corner(b, 6)
		b.Activated:Connect(function()
			Net.get("SetSetting"):FireServer(key, not (state.settings[key] ~= false))
			playSound("click")
		end)
		toggles[key] = b
	end

	gear.Activated:Connect(function()
		open = not open
		playSound("click")
	end)
	RunService.RenderStepped:Connect(function()
		-- Under the admin tools when there are any (they take UI.adminHeight of the corner).
		local top = 14 + (if UI.adminHeight > 0 then UI.adminHeight + 10 else 0)
		gear.Position = UDim2.new(1, -14, 0, top)
		if not Layout.saved.Settings then -- unless the player moved it somewhere
			panel.AnchorPoint = Vector2.new(1, 0)
			panel.Position = UDim2.new(1, -60, 0, top)
		end
		panel.Visible = open
		if not open then
			return
		end
		volumeText.Text = string.format("%d%%", math.floor((state.settings.volume or 1) * 100 + 0.5))
		for key, b in toggles do
			local on = state.settings[key] ~= false
			b.Text = if on then "ON" else "OFF"
			b.BackgroundColor3 = if on then GREEN:Lerp(BG, 0.3) else BADGE
		end
	end)
end

-- ── Input (clicking / tapping the bar and dragging in the world) ─────────

buy.button.Visible = false -- soldiers are summoned at the altar in the lobby (E), not from the UI
fight.button.Activated:Connect(requestFight)
autoMerge.button.Activated:Connect(function()
	Net.get("AutoMerge"):FireServer()
end)
equipBest.button.Activated:Connect(function()
	Net.get("EquipBest"):FireServer()
end)
upgrade.button.Activated:Connect(function()
	Net.get("Upgrade"):FireServer()
end)

local function isPointerPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return -- typing in chat, clicking the bottom bar etc.
	end
	if input.KeyCode == Enum.KeyCode.Escape then
		closeConfirm()
		UI.battleOpen = false
	elseif input.KeyCode == Enum.KeyCode.E then
		-- E summons at the altar (a ProximityPrompt); inside a popup that uses E it confirms; in a battle it heals.
		if confirmLayer then
			local callback = confirmCallback
			if confirmKeyCode == Enum.KeyCode.E and callback then
				closeConfirm()
				callback()
			end
		else
			castSpell("e")
		end
	elseif input.KeyCode == Enum.KeyCode.Q then
		castSpell("q") -- METEOR at the cursor (only in a battle)
	elseif input.KeyCode == Enum.KeyCode.H then
		UI.hidden = not UI.hidden -- hide / show the panel (same as its icon in the dock)
		if not UI.hidden then
			UI.battleOpen = false
		end
		Layout.save()
	elseif isPointerPress(input) then
		pointer = Vector2.new(input.Position.X, input.Position.Y)
		closeCardPopup() -- a click in the world closes the popup
		beginDrag()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		pointer = Vector2.new(input.Position.X, input.Position.Y)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if isPointerPress(input) then
		endDrag() -- runs even if the release happened over the UI
		endCardDrag()
	end
end)

Net.get("RequestState"):FireServer()
render()
