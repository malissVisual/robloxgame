--!strict
-- The game's HUD (its ScreenGui "ZombieDeliveryHud"; the other modules find it and its groups by these names):
--   * "Health": your health, a thick bar with a big plus and the number (green, red when low), in the left column
--     ("LeftStack": lower left on a computer, the chat is top left; top left on a touch screen, the thumbstick is
--     bottom left).
--   * "TopStack", the column at the top left: the other modules' panels in its slots (Hud.topSlot: the money block's
--     room, client/SandboxHud.luau's "sandbox" first, client/SandboxTasksUi.luau's chip there too, the loot's toasts,
--     client/LootStars.luau's "loot") and the toasts (Hud.toast, the newest last). At the left margin under Roblox's top
--     bar on a computer, under the native chat window while it is open; right of the left column on a touch screen.
--   * "Hint", the contextual action at the lower centre: one key in a square outline and the action in white caps,
--     only while you can press it ("G  PUT IT DOWN": a piece in your hands alone; a piece carried in two has the G
--     prompt on the piece itself). A touch screen drops the key (its PUT DOWN button says it).
--   * "HudButtons", an empty anchor at the top right (left of Roblox's player list on a computer, under the ADMIN
--     button while it shows): the key hints (client/KeyHints.luau) sit right under it.
--   * The touch buttons (client/TouchControls.luau: SPRINT and PUT DOWN, placed here from client/TouchLayout.luau's
--     boxes) and the breath bar over the action (client/Stamina.luau).
-- ESC (and Roblox's menu) closes the windows: Hud.closeWindows runs Hud.onCloseWindows (the client's Main closes every
-- module's window there; Hud.escaping is true while ESC does it).
-- The 3.8 contract look (client/HudContract.luau, P below): compact white type over the world on a localized charcoal
-- scrim, flat square shapes, fine lines and small red accents. Where everything sits: ── Layout ── below.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local TouchLayout = require(script.Parent.TouchLayout)
local P = require(script.Parent.HudContract) -- 3.8: the contract palette and its small pieces
local Hud = {}

local player = Players.LocalPlayer
local touchLayout = Ui.touchLayout()

local gui = Ui.make("ScreenGui", {
	Name = "ZombieDeliveryHud",
	ResetOnSpawn = false,
	ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- clear of a phone's notch, rounded corners and Roblox's top bar
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Enabled = false,
}, player:WaitForChild("PlayerGui"))

-- A panel placed by layout(): its own UIScale.
local function placed(frame: any): any
	Ui.make("UIScale", { Name = "LayoutScale" }, frame)
	return frame
end
local function setScale(frame: any, value: number)
	local s = frame:FindFirstChild("LayoutScale")
	if s and s:IsA("UIScale") and math.abs(s.Scale - value) > 0.001 then
		s.Scale = value
	end
end
-- Lays the HUD out again (defined in ── Layout ──; panels that change their size ask for it).
local layoutQueued = false
local layout: () -> () = function() end
local chatChanged: () -> boolean = function() -- (── Layout ──: the native chat window opened or closed since)
	return false
end
local function requestLayout()
	if layoutQueued then
		return
	end
	layoutQueued = true
	task.defer(function()
		layoutQueued = false
		layout()
	end)
end

-- ── Health ─────────────────────────────────────────────────────────────────

local LEFT_W, LEFT_H = 200, 44
local leftStack = placed(Ui.make("Frame", {
	Name = "LeftStack",
	Size = UDim2.fromOffset(LEFT_W, LEFT_H),
	Position = if touchLayout then UDim2.fromOffset(16, 16) else UDim2.new(0, 16, 1, -16),
	AnchorPoint = if touchLayout then Vector2.zero else Vector2.new(0, 1),
	BackgroundTransparency = 1,
}, gui))
local life: any = {} -- the row's live pieces
do
	local health = Ui.make("Frame", { Name = "Health", Size = UDim2.fromOffset(LEFT_W, LEFT_H), BackgroundTransparency = 1 }, leftStack)
	local row = Ui.make("Frame", { Name = "Life", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1 }, health)
	P.text(row, "+", UDim2.fromOffset(22, 26), { Font = Theme.HeadingFont, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center })
	local back
	back, life.fill = P.bar(row, UDim2.new(1, -80, 0, 12), P.good)
	back.Position = UDim2.new(0, 28, 0.5, 0)
	back.AnchorPoint = Vector2.new(0, 0.5)
	life.text = P.text(row, "100", UDim2.fromOffset(48, 26), {
		Position = UDim2.new(1, 0, 0, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.MonoFont,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	life.shown = -1 -- the health shown (the row redraws only when it changes)
end

-- ── Top stack ──────────────────────────────────────────────────────────────
-- The column at the top left, one column that grows downward (a UIListLayout: a hidden entry takes no room, so nothing
-- overlaps): the slots by their order (SLOT_ORDER; another name goes under the toasts), everything left-aligned.

local TOP_W = 380 -- the column's width at scale 1
local topStack = placed(Ui.make("Frame", {
	Name = "TopStack",
	Size = UDim2.fromOffset(TOP_W, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.fromOffset(16, 14),
	BackgroundTransparency = 1,
}, gui))
Ui.list(topStack, true, 8)
-- (a toast under the money block makes the column taller: lay out again for its real height)
topStack:GetPropertyChangedSignal("AbsoluteSize"):Connect(requestLayout)

local SLOT_ORDER: { [string]: number } = { toasts = 6 }
local slots: { [string]: Frame } = {}

-- A place in the column for another module's panel, by name. The slot is as wide as the column and as tall as what is
-- visible in it (its children top down by LayoutOrder, left-aligned). It is scaled with the column: the panels in it
-- take no UIScale of their own.
function Hud.topSlot(name: string): Frame
	local existing = slots[name]
	if existing then
		return existing
	end
	local count = 0
	for _ in slots do
		count += 1
	end
	local slot: Frame = Ui.make("Frame", {
		Name = `Slot_{name}`,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = SLOT_ORDER[name] or (10 + count),
	}, topStack)
	Ui.list(slot, true, 8)
	slots[name] = slot
	return slot
end

-- ── Toasts ─────────────────────────────────────────────────────────────────

do
	local toasts = Hud.topSlot("toasts")
	local MAX_TOASTS = if touchLayout then 2 else 3
	local toastOrder = 0

	-- A toast is a compact charcoal strip (a thin white rule on its left, white text) that fades in and, after 3 s,
	-- out again. No movement.
	function Hud.toast(text: string)
		-- Too many: the oldest goes (they never pile up down the screen).
		local shown: { any } = {}
		for _, child in toasts:GetChildren() do
			if child:GetAttribute("Toast") == true and child:GetAttribute("Leaving") ~= true then
				if child:GetAttribute("Text") == text then
					return -- 4.5.1: these words are on screen already (a repeated notice): no second strip fading in
				end
				table.insert(shown, child)
			end
		end
		table.sort(shown, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		for index = 1, #shown - MAX_TOASTS + 1 do
			shown[index]:Destroy()
		end
		toastOrder += 1
		local strip = Ui.make("CanvasGroup", {
			Name = "Toast",
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundColor3 = P.surface,
			BackgroundTransparency = 0.22,
			BorderSizePixel = 0,
			GroupTransparency = 1,
			LayoutOrder = toastOrder,
		}, toasts)
		strip:SetAttribute("Toast", true)
		strip:SetAttribute("Text", text)
		-- (the padding moves the children: the rule goes back out to the edge)
		Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 2, 1, 14), Position = UDim2.fromOffset(-14, -7), BackgroundColor3 = P.ink, BorderSizePixel = 0 }, strip)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, strip)
		local label = Ui.label(strip, text, UDim2.fromOffset(0, 0), {
			AutomaticSize = Enum.AutomaticSize.XY,
			TextSize = 14,
			Font = Theme.Font,
			TextColor3 = P.ink,
			TextWrapped = true,
		})
		-- 340: with the padding it stays inside the narrowest column.
		Ui.make("UISizeConstraint", { MaxSize = Vector2.new(340, math.huge) }, label)
		P.fade(strip, true, 0.18)
		task.delay(3, function()
			if not strip.Parent then
				return
			end
			strip:SetAttribute("Leaving", true)
			P.fade(strip, false, 0.3)
			task.wait(0.35)
			strip:Destroy()
		end)
	end
end

-- ── Windows ────────────────────────────────────────────────────────────────
-- The windows are the other modules' (the warehouse's, the book, the map …): the client's Main sets onCloseWindows.

Hud.escaping = false -- true while ESC / Roblox's menu closes the windows (a visitor's offer is declined only then)
Hud.onCloseWindows = nil :: (() -> ())?

function Hud.closeWindows()
	local cb = Hud.onCloseWindows
	if cb then
		cb()
	end
end

-- ── The top right ──────────────────────────────────────────────────────────
-- An empty anchor of a fixed size (layout() places it): the key hints sit under it.

local ROW_W, ROW_H = if touchLayout then 170 else 200, 44
local buttonGrid = placed(Ui.make("Frame", {
	Name = "HudButtons",
	Size = UDim2.fromOffset(ROW_W, ROW_H),
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 16),
	BackgroundTransparency = 1,
}, gui))

-- ── The contextual action ──────────────────────────────────────────────────
-- Lower centre (layout() places and scales it): one key in a square outline, the action in white caps, a short
-- instruction under it. The centre of the world stays clear. Hidden while it has nothing to say.

local hint: any, action: any
do
	hint = placed(Ui.make("Frame", {
		Name = "Hint",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = UDim2.new(0.5, 0, 1, -40),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, gui))
	Ui.make("UISizeConstraint", { Name = "Max", MaxSize = Vector2.new(480, math.huge) }, hint)
	-- 6.5: a pill (the approved mockup): a charcoal panel with a fine outline, the key box on its left.
	local glow = Ui.make("Frame", { Name = "Scrim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = P.surface, BackgroundTransparency = 0.22, BorderSizePixel = 0, ZIndex = 0 }, hint)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = P.line, Thickness = 1, Transparency = P.lineAlpha }, glow)
	local column = Ui.make("Frame", { Name = "Column", Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1 }, hint)
	Ui.list(column, true, 6)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 16), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, column)
	local row = Ui.make("Frame", { Name = "Row", Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, LayoutOrder = 1 }, column)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	action = {}
	action.key = P.keyBox(row, "G", 30, { LayoutOrder = 1, Visible = false })
	local words = Ui.make("Frame", { Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, LayoutOrder = 2 }, row)
	Ui.list(words, true, 2)
	action.main = P.text(words, "", UDim2.fromOffset(0, 0), {
		AutomaticSize = Enum.AutomaticSize.XY,
		Font = Theme.HeadingFont,
		TextSize = 17,
		TextWrapped = true,
		LayoutOrder = 1,
	})
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(360, math.huge) }, action.main)
	action.shown = ""
end

-- What you can press right now: G puts down what your hands hold alone (a piece carried in two, the character's
-- CarryPair, has its own G prompt on the piece for each of its holders: no second word for it here).
local function actionNow(): (string, string?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not humanoid or humanoid.Health <= 0 then
		return "", nil
	end
	local carrying = character:GetAttribute("Carrying")
	if type(carrying) ~= "string" or carrying == "" or character:GetAttribute("CarryPair") == true then
		return "", nil
	end
	return "Put it down", "G"
end

-- The pill's words and key (none on a touch screen: its PUT DOWN button is tapped); hidden with nothing to say.
local function setHint(main: string, key: string?)
	if touchLayout then
		key = nil
	end
	local signature = `{main}|{key}`
	if action.shown ~= signature then
		action.shown = signature
		action.main.Text = string.upper(main)
		action.key.Visible = key ~= nil
		action.key.Text = string.upper(key or "")
	end
	local visible = main ~= ""
	if hint.Visible ~= visible then
		hint.Visible = visible
	end
end

-- The touch buttons: SPRINT and PUT DOWN (a touch layout only; layout() places them).
require(script.Parent.TouchControls).build(gui)

-- ── Layout ─────────────────────────────────────────────────────────────────
-- Everything is placed from the size of the screen: the ScreenGui's area under Roblox's top bar, W × H pixels, and
-- one scale S = Ui.scaleFor(W × H) (1 at 1150 × 680, from 0.55 on phones to 1.1). It runs again when the screen
-- changes, the native chat window moves or resizes, players come and go (the player list grows) or the ADMIN button
-- comes or goes.
--   * Margins 16 px, gaps 8 px. The ADMIN button (client/AdminPanel.luau, 96 × 32 at 16 px from the right, 56 from the
--     top, unscaled) keeps the top right corner (down to ADMIN_BOTTOM) while it shows (admins, Studio).
--   * The left column (the health row, LEFT_W × LEFT_H × S): bottom left on a computer, top left on touch.
--   * The top left column: at the left margin under Roblox's top bar on a computer, under the native chat window while
--     it is open (its rectangle from TextChatService's ChatWindowConfiguration; a closed chat takes no room); right of
--     the left column on touch (under it when a screen held upright has no room beside it). TOP_W × S wide (narrower
--     down to TOP_MIN_W before it gets smaller) and as tall as the room over the lower pieces allows (TOP_EST_H).
--   * The top right anchor: a computer has Roblox's player list (leaderstats) top right: it sits left of it
--     (PLAYER_LIST_W), or under it when the screen is too narrow. On touch top right, under ADMIN.
--   * Touch: SPRINT and PUT DOWN left of Roblox's jump button (client/TouchLayout.luau's cluster), each at least 44 px.
--   * Lower centre: the contextual action, its bottom HINT_BOTTOM × S over the margin, between the left column (touch:
--     the thumbstick's corner) and the right edge (touch: the buttons); client/Stamina.luau's breath bar right over it.

do
	local MARGIN = 16
	local GAP = 8
	local ADMIN_BOTTOM = 96 -- client/AdminPanel.luau: the ADMIN button at (1, -16, 0, 56), 96 × 32, unscaled
	local TOUCH_BUTTON_MIN = 0.8
	local TOP_EST_H = 200 -- the top column's usual height (unscaled)
	local TOP_MIN_W = 300 -- a narrow span first makes the top column narrower (down to this), then smaller
	local PLAYER_LIST_W = 370 -- Roblox's player list with this game's leaderstats (px, not scaled by us)
	local HINT_BOTTOM = 18 -- the contextual action's bottom over the margin (unscaled)
	local HINT_W = 480 -- its widest (unscaled)

	type Box = TouchLayout.Box
	local box = TouchLayout.box

	-- The top edge of the highest box that starts at or under `y` and shares columns with x0 .. x1 (else `floor`).
	local function ceilingBelow(boxes: { Box }, x0: number, x1: number, y: number, floor: number): number
		local limit = floor
		for _, b in boxes do
			if b.y0 >= y and math.min(b.x1, x1) - math.max(b.x0, x0) > 0 then
				limit = math.min(limit, b.y0)
			end
		end
		return limit
	end

	local function screenArea(): Vector2
		local size = gui.AbsoluteSize
		if size.X < 2 or size.Y < 2 then
			return Ui.screenSize()
		end
		return size
	end

	-- The ADMIN button shows (the same rule as client/AdminPanel.luau).
	local function adminButtonShown(): boolean
		return player:GetAttribute("Admin") == true or (Config.Admin.InStudio and RunService:IsStudio())
	end

	-- Is a native Roblox interface on (StarterGui:GetCoreGuiEnabled; on when it cannot be asked)?
	local function coreOn(kind: Enum.CoreGuiType): boolean
		local ok, on = pcall(function()
			return game:GetService("StarterGui"):GetCoreGuiEnabled(kind)
		end)
		return not ok or on == true
	end

	-- 4.5.2: is the native chat window open (Roblox's chat button toggles it; StarterGui's "ChatActive")? Open when it
	-- cannot be asked. ChatWindowConfiguration keeps Enabled and its rectangle while the window is closed. Hud.start
	-- looks at it twice a second (there is no signal for it: chatChanged).
	local chatOpen = true
	local function chatShown(): boolean
		local ok, active = pcall(function()
			return game:GetService("StarterGui"):GetCore("ChatActive")
		end)
		return not ok or active ~= false
	end

	-- The native chat window's rectangle on a computer (TextChatService's ChatWindowConfiguration), in this HUD's
	-- coordinates; nil when there is none or it is closed.
	local function chatBox(): Box?
		chatOpen = chatShown()
		if touchLayout or not coreOn(Enum.CoreGuiType.Chat) or not chatOpen then
			return nil
		end
		local ok, found = pcall(function(): Box?
			local TextChatService = game:GetService("TextChatService")
			if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
				return box(0, 0, 400, 200) -- the legacy chat: top left, about this big
			end
			local config = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
			if not config or not config.Enabled then
				return nil
			end
			local position, size = config.AbsolutePosition - gui.AbsolutePosition, config.AbsoluteSize
			if size.X < 1 or size.Y < 1 then
				return nil
			end
			return box(position.X, position.Y, position.X + size.X, position.Y + size.Y)
		end)
		return if ok then found else nil
	end

	-- The chat window opened or closed since the last layout (Hud.start looks twice a second).
	chatChanged = function(): boolean
		return chatShown() ~= chatOpen
	end

	local topTall: number? = nil -- the top column's height followed (4.5.1: with hysteresis)

	layout = function()
		local size = screenArea()
		local W, H = size.X, size.Y
		local S = Ui.scaleFor(size)
		-- What the top column and the action must stay clear of.
		local below: { Box } = {}

		-- The left column: the health row.
		setScale(leftStack, S)
		local left: Box
		if touchLayout then
			leftStack.AnchorPoint = Vector2.zero
			leftStack.Position = UDim2.fromOffset(MARGIN, MARGIN)
			left = box(MARGIN, MARGIN, MARGIN + LEFT_W * S, MARGIN + LEFT_H * S)
		else
			leftStack.AnchorPoint = Vector2.new(0, 1)
			leftStack.Position = UDim2.new(0, MARGIN, 1, -MARGIN)
			left = box(MARGIN, H - MARGIN - LEFT_H * S, MARGIN + LEFT_W * S, H - MARGIN)
			table.insert(below, left)
		end

		-- Touch: SPRINT and PUT DOWN left of the jump button (client/TouchLayout.luau), clear of the thumbstick.
		local admin = adminButtonShown()
		local cluster: TouchLayout.Cluster? = nil
		local buttons: { Box } = {}
		if touchLayout then
			local c = TouchLayout.cluster(W, H, S)
			cluster = c
			local textSize = math.max(12, math.floor(14 * math.max(S, 0.8) + 0.5))
			require(script.Parent.TouchControls).place(c.sprint, c.act, textSize)
			buttons = { c.sprint, c.act }
			for _, b in buttons do
				table.insert(below, b)
			end
			table.insert(below, c.jump)
		end

		-- Lower centre: the contextual action, between the left column (or the thumbstick) and the right edge.
		setScale(hint, S)
		local hintX, hintBottom, hintW
		if cluster then
			hintX, hintBottom, hintW = TouchLayout.hint(cluster, buttons, W, H, S, nil)
		else
			local spanLeft, spanRight = left.x1 + 12, W - MARGIN - 12
			hintW = math.max(160, math.min(HINT_W * S, spanRight - spanLeft))
			hintX = math.clamp(W / 2, spanLeft + hintW / 2, math.max(spanLeft + hintW / 2, spanRight - hintW / 2))
			hintBottom = H - MARGIN - HINT_BOTTOM * S
		end
		-- The breath bar (client/Stamina.luau) right over the action.
		require(script.Parent.Stamina).place(hintX, hintBottom - 108 * S)
		local hintMax = hint:FindFirstChild("Max")
		if hintMax and hintMax:IsA("UISizeConstraint") then
			hintMax.MaxSize = Vector2.new(hintW / S, math.huge)
		end
		hint.AnchorPoint = Vector2.new(0.5, 1)
		hint.Position = UDim2.fromOffset(hintX, hintBottom)
		table.insert(below, box(hintX - hintW / 2, hintBottom - 96 * S, hintX + hintW / 2, hintBottom))

		-- The top right anchor (its Size is the unscaled row).
		local base = if touchLayout then math.max(S, TOUCH_BUTTON_MIN) else S
		local buttonScale = math.clamp(base, 0.45, base)
		setScale(buttonGrid, buttonScale)
		local rowW, rowH = ROW_W * buttonScale, ROW_H * buttonScale
		local rowRight, rowTop = W - MARGIN, if admin then ADMIN_BOTTOM else MARGIN
		if not touchLayout then
			rowTop = 4 -- (in line with the top of the chat and the player list)
			if coreOn(Enum.CoreGuiType.PlayerList) then
				if W - MARGIN - PLAYER_LIST_W - rowW >= MARGIN + TOP_MIN_W * S + 24 then
					rowRight = W - MARGIN - PLAYER_LIST_W -- left of the player list
				else
					-- Too narrow: under the player list (about 40 px a player and its header).
					local listBottom = math.min(H * 0.45, 52 + 40 * #Players:GetPlayers())
					rowTop = math.max(listBottom, if admin then ADMIN_BOTTOM else 0) + GAP
				end
			end
		end
		buttonGrid.AnchorPoint = Vector2.new(1, 0)
		buttonGrid.Position = UDim2.fromOffset(rowRight, rowTop)
		local grid = box(rowRight - rowW, rowTop, rowRight, rowTop + rowH)

		-- The column's real height (unscaled), with hysteresis (4.5.1: a fresh measurement each time made scale →
		-- height → scale chase each other, a flicker): it follows a real change only, taller by more than a few px or
		-- shorter by more than a toast or two.
		local stackScale = topStack:FindFirstChild("LayoutScale")
		local tall = topTall or TOP_EST_H
		if stackScale and stackScale:IsA("UIScale") and stackScale.Scale > 0.01 then
			local measured = math.max(TOP_EST_H, topStack.AbsoluteSize.Y / stackScale.Scale)
			if topTall == nil or measured > tall + 10 or measured < tall - 56 then
				tall = measured
			end
		end
		topTall = tall
		-- The top column: as big as the span (from x0 to x1 at y) and the room under it allow.
		local function fit(y: number, x0: number, x1: number): (number, number)
			local span = x1 - x0
			local width = math.clamp(span / S, TOP_MIN_W, TOP_W)
			local scale = math.min(S, span / width)
			local floor = ceilingBelow(below, x0, x0 + width * scale, y, H)
			scale = math.min(scale, (floor - GAP - y) / tall)
			return scale, width
		end
		-- Its right end: the anchor when it is beside it (else the screen's edge, or ADMIN).
		local function rightLimit(y: number): number
			local limit = W - MARGIN
			if grid.y1 > y and grid.y0 < y + tall * S then
				limit = math.min(limit, grid.x0 - GAP)
			end
			if admin then
				limit = math.min(limit, W - 16 - 96 - GAP)
			end
			return limit
		end
		-- 4.5.2: always at the left margin on a computer, under Roblox's top bar; an open chat window over it pushes it
		-- down, under the chat, still at the left. Little room under the chat makes it smaller instead.
		local topX, topY = MARGIN, 14
		if touchLayout then
			topX, topY = left.x1 + GAP, MARGIN
		end
		local chat = chatBox()
		if chat and chat.x0 < topX + TOP_W * S and chat.x1 > topX then
			if chat.y0 < H * 0.5 then
				if chat.y1 > topY then
					topY = chat.y1 + GAP -- under the chat window
				end
			else
				table.insert(below, chat) -- (a chat moved to the bottom: the column stays clear of it)
			end
		end
		local topScale, topWidth = fit(topY, topX, rightLimit(topY))
		if touchLayout and topScale < S * 0.8 then
			-- No room beside the left column and the anchor (upright): under them, the whole width.
			local y = math.max(left.y1, grid.y1) + GAP
			local scale, width = fit(y, MARGIN, W - MARGIN)
			if scale > topScale then
				topX, topY, topScale, topWidth = MARGIN, y, scale, width
			end
		end
		-- Never smaller than readable: rather overlap the lower pieces a little.
		topScale = math.max(topScale, 0.7 * S)
		setScale(topStack, topScale)
		topStack.Size = UDim2.fromOffset(topWidth, 0)
		topStack.Position = UDim2.fromOffset(topX, topY)
	end
end

-- ── Updates ────────────────────────────────────────────────────────────────

function Hud.setVisible(visible: boolean)
	gui.Enabled = visible
	if visible then
		requestLayout()
	end
end

local hintAt = 0
RunService.RenderStepped:Connect(function()
	if not gui.Enabled then
		return
	end
	-- Your health (the Humanoid's).
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local health = if humanoid then math.ceil(humanoid.Health) else 0
	if health ~= life.shown then
		life.shown = health
		local most = if humanoid then math.max(1, humanoid.MaxHealth) else 100
		life.text.Text = tostring(health)
		life.fill.Size = UDim2.fromScale(math.clamp(health / most, 0, 1), 1)
		life.fill.BackgroundColor3 = if health / most > 0.3 then P.good else P.danger
		life.text.TextColor3 = if health / most > 0.3 then P.ink else P.danger
	end
	-- The action at most 10 times a second.
	local now = os.clock()
	if now >= hintAt then
		hintAt = now + 0.1
		setHint(actionNow())
	end
end)

function Hud.start()
	layout()
	-- The layout follows the screen (a resized window, a phone turned), and the ADMIN button.
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(requestLayout)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(requestLayout)
	end
	player:GetAttributeChangedSignal("Admin"):Connect(requestLayout)
	-- 3.8: the top column follows the native chat window; the anchor follows the player list.
	pcall(function()
		local config = game:GetService("TextChatService"):FindFirstChildOfClass("ChatWindowConfiguration")
		if config then
			config:GetPropertyChangedSignal("AbsoluteSize"):Connect(requestLayout)
			config:GetPropertyChangedSignal("AbsolutePosition"):Connect(requestLayout)
			config:GetPropertyChangedSignal("Enabled"):Connect(requestLayout)
		end
	end)
	-- 4.5.2: the chat window opened or closed (Roblox's chat button; no signal for it): the column follows.
	task.spawn(function()
		while true do
			task.wait(0.5)
			if gui.Enabled and chatChanged() then
				requestLayout()
			end
		end
	end)
	Players.PlayerAdded:Connect(requestLayout)
	Players.PlayerRemoving:Connect(requestLayout)
	-- 3.6: ESC closes the open windows (Hud.onCloseWindows: the other modules'). Roblox's menu takes the Escape key
	-- itself, hence MenuOpened as well.
	local function escape()
		Hud.escaping = true
		Hud.closeWindows()
		Hud.escaping = false
	end
	game:GetService("GuiService").MenuOpened:Connect(escape)
	UserInputService.InputBegan:Connect(function(input)
		if not gui.Enabled or UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			escape()
		end
	end)
end

return Hud
