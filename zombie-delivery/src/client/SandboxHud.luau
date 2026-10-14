--!strict
-- 8.0 SANDBOX: the sandbox's HUD (design/sandbox/KONTRAKT.md, "ui"). The owner: "one house, one van you can walk in,
-- drive to your warehouse and put the things on show there": what is on show earns money every minute you play, and you
-- can sell it any time. A ScreenGui named "SandboxHud" (the sandbox guide's hint line at the top in the middle finds it
-- by that name and keeps clear of its top-left pieces) with the block at the top left, where client/Hud.luau's left
-- column starts: a spacer of the block's size is first in that column (Hud.topSlot "sandbox"), the block follows it
-- (its place and scale: under the native chat on a computer, beside the left column on a touch screen) and the HUD's
-- toasts flow under it:
--   * your money, big, in the money green, counting up (client/Juice.luau countMoney): the player's State (the State
--     remote's table, SandboxHud.setState from client/Main.client.luau, as the old HUD gets it), the player list's
--     leaderstats Money until then (boot-client hides the old money line, its level and XP in the sandbox)
--   * "+$X/min" in green under it while pieces are on show (the "Collection" remote's state: income; WarehouseUi.rate:
--     a tenth under $10, "+$0.4/min"); 8.3 economy: idle (the state's `idle`, server/Collection.luau's AFK share) what
--     they pay then, greyed, "+$2.5/min · idle"
--   * the chip "📦 N in stock" (the pieces not on show): a tap, or the key Config.SandboxHud.StockKey (B), opens the
--     STOCK list (client/WarehouseUi.luau; the key again closes it)
--   * 8.2: the chip "📖 BOOK" beside it (when client/CollectionBookUi.luau is there): a tap opens and closes the
--     collection book (its own key, Config.CollectionBook.Key: C, is the book's; shown on the chip on a computer)
--   * toasts: a piece sold ("Sold Grandpa's Clock · +$420", client/WarehouseUi.luau's "sold") and pieces brought home
--     ("+5 pieces in your warehouse", when a state's stock grew): Hud.toast; without client/Hud.luau a column of its own
--     at the top left with its own toasts in the same look
--   * 8.3: once after joining (and again when the market's day turns while you play) "🔥 Hot today: Old Globe, Jukebox,
--     Sofa (sell ×1.6, on show ×1.25)" (shared/Market.luau hotToast, the state's market), held back while the HUD is
--     hidden (the start screen) and told when it shows
-- Standing in Hud's column keeps it clear of what the HUD still shows in the sandbox: the toasts flow under it, the
-- health row (bottom left on a computer; on a touch screen the left column the column stands beside), MOUSE [ALT] and
-- the key hints at the top right, the move's blocks at the top in the middle (tools/phone-ui/sandbox.luau checks it).
-- A touch screen: the block is never smaller than Config.SandboxHud.TouchScale and its chip is a finger's size
-- (Ui.MinTouch screen px). SandboxHud.start() does nothing when Config.Sandbox.On is false; it also starts
-- client/WarehouseUi.luau (once).
-- 8.3, every device (shared/SandboxPad.luau, client/PadGlyph.luau): a chip's key outline shows its key on a computer
-- (B, C), the gamepad's D-pad glyph while a gamepad is used (← the STOCK list, → the book; drawn again when the device
-- changes), nothing on a touch screen; the D-pad's ← opens and closes the STOCK list (not while a window has the
-- gamepad's selection). The server's notices come through SandboxHud.notice (client/Main.client.luau): in this
-- device's words. It also starts the first-time hints (client/SandboxHintsUi.luau: their toasts are its toasts).
--   SandboxHud.start()         builds it and listens
--   SandboxHud.setState(state) the player's State (its money)
--   SandboxHud.toast(text)     a toast (SandboxHud.notify when set, else Hud.toast, else its own)
--   SandboxHud.notice(text)    8.3: a server's notice as a toast, in this device's words (SandboxPad.notice)
--   SandboxHud.block()         its frame (nil before start); SandboxHud.gui() its ScreenGui "SandboxHud"
-- Presentation only: the server decides the money and the collection.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local Juice = require(script.Parent.Juice)
local WarehouseUi = require(script.Parent.WarehouseUi)
local PadGlyph = require(script.Parent.PadGlyph) -- 8.3: the chips' keys on every device, the gamepad's D-pad
local Market = require(Shared.Market) -- 8.3: the market's toast

local SandboxHud = {}

SandboxHud.notify = nil :: ((text: string) -> ())?

local HUD = Config.SandboxHud
local K = Theme.Contract
local PAD_X, PAD_Y, GAP = 14, 8, 6
local COLUMN_W = 340 -- the own toasts' column (no client/Hud.luau): its width

local started = false
local parts: { [string]: any } = {}
local hudToast: ((string) -> ())? = nil
local money = 0
local income = 0
local idleShare: number? = nil -- 8.3 economy: the state's `idle` (nil: active)
local inStock = 0
local stockKey: Enum.KeyCode? = nil
local arrangeQueued = false
local toastOrder = 0
local marketTold: number? = nil -- 8.3: the market day the "Hot today" toast was for
local marketToast: string? = nil -- 8.3: … waiting for the HUD to show

local function sandboxOn(): boolean
	local sandbox = (Config :: any).Sandbox
	return type(sandbox) == "table" and sandbox.On == true
end

-- The scale the HUD's columns put on `object` (the UIScales above it multiplied, up to its ScreenGui).
local function scaleAbove(object: Instance): number
	local scale = 1
	local node = object.Parent
	while node and not node:IsA("PlayerGui") do
		for _, child in node:GetChildren() do
			if child:IsA("UIScale") then
				scale *= (child :: UIScale).Scale
			end
		end
		node = node.Parent
	end
	return scale
end

-- ── The layout ──────────────────────────────────────────────────────────────

-- Where the block goes: the spacer's place in client/Hud.luau's column and the column's scale there, else the top left
-- at the screen's scale (its own column).
local function anchor(): (number, number, number)
	local spacer = parts.spacer
	if spacer then
		local at = spacer.AbsolutePosition
		return at.X, at.Y, math.max(0.05, scaleAbove(spacer))
	end
	return 16, 14, Ui.screenScale()
end

local function arrange()
	local block = parts.block
	if not block then
		return
	end
	local touch = Ui.touchLayout()
	local x, y, unit = anchor()
	local scale = math.max(unit, if touch then HUD.TouchScale else 0.6)
	parts.scale.Scale = scale
	-- the money card: the money (as wide as its target) over "+$X/min"
	local moneyText = Ui.money(money)
	local moneyW = CardKit.width(moneyText, HUD.MoneySize, Theme.DisplayFont)
	local incomeText = if idleShare then `{WarehouseUi.rate(income * idleShare)} · idle` else WarehouseUi.rate(income)
	local incomeW = if income > 0 then CardKit.width(incomeText, HUD.IncomeSize, Theme.HeadingFont) else 0
	local cardW = math.ceil(math.max(moneyW, incomeW, 90)) + 2 * PAD_X
	local moneyH = HUD.MoneySize + 4
	local cardH = PAD_Y + moneyH + (if income > 0 then HUD.IncomeSize + 4 else 0) + PAD_Y
	parts.card.Size = UDim2.fromOffset(cardW, cardH)
	parts.money.Size = UDim2.fromOffset(cardW - 2 * PAD_X, moneyH)
	parts.income.Visible = income > 0
	parts.income.Text = incomeText
	parts.income.TextColor3 = if idleShare then K.secondary else K.good
	parts.income.Size = UDim2.fromOffset(cardW - 2 * PAD_X, HUD.IncomeSize + 4)
	-- the chip: "📦 N in stock" (and its key on a computer, 8.3: the D-pad's glyph with a gamepad), a finger's size on a
	-- touch screen
	local chip = parts.chip
	local chipText = `📦 {inStock} in stock`
	chip.Text = chipText
	local keyShown = PadGlyph.show(parts.key, "stock")
	local chipH = HUD.Chip
	local chipW = CardKit.width(chipText, HUD.ChipText, Theme.HeadingFont) + 24 + (if keyShown then 28 else 0)
	if touch then
		chipH = math.max(chipH, math.ceil(Ui.MinTouch / scale))
		chipW = math.max(chipW, math.ceil(Ui.MinTouch / scale))
	end
	chipW = math.ceil(chipW)
	chip.Size = UDim2.fromOffset(chipW, chipH)
	chip.Position = UDim2.fromOffset(0, cardH + GAP)
	parts.chipCorner.CornerRadius = UDim.new(0, math.floor(chipH / 2))
	-- 8.2: the "📖 BOOK" chip beside it, as tall (its key on a computer; 8.3: the D-pad's glyph with a gamepad)
	local rowW = chipW
	local book = parts.book
	if book then
		local bookKeyShown = PadGlyph.show(parts.bookKey, "book")
		local bookW = CardKit.width(book.Text, HUD.ChipText, Theme.HeadingFont) + 24 + (if bookKeyShown then 28 else 0)
		if touch then
			bookW = math.max(bookW, math.ceil(Ui.MinTouch / scale))
		end
		bookW = math.ceil(bookW)
		book.Size = UDim2.fromOffset(bookW, chipH)
		book.Position = UDim2.fromOffset(chipW + GAP, cardH + GAP)
		parts.bookCorner.CornerRadius = UDim.new(0, math.floor(chipH / 2))
		rowW = chipW + GAP + bookW
	end
	local blockW, blockH = math.max(cardW, rowW), cardH + GAP + chipH
	block.Size = UDim2.fromOffset(blockW, blockH)
	block.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	if parts.spacer then
		-- (the room it takes in Hud's column, in the column's own px: the toasts start under it)
		parts.spacer.Size = UDim2.fromOffset(math.ceil(blockW * scale / unit), math.ceil(blockH * scale / unit))
	end
	if parts.toasts then
		parts.toasts.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + blockH * scale + 8.5))
		parts.toastScale.Scale = scale
	end
end

local function queueArrange()
	if arrangeQueued then
		return
	end
	arrangeQueued = true
	task.delay(0.1, function()
		arrangeQueued = false
		arrange()
	end)
end

-- ── Toasts ──────────────────────────────────────────────────────────────────

local function fade(strip: Instance, to: number, seconds: number)
	TweenService:Create(strip, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = to }):Play()
end

-- Its own toast (no client/Hud.luau): Hud.toast's look, a charcoal strip with a thin white rule, under the block.
local function ownToast(text: string)
	local holder = parts.toasts
	if not holder then
		return
	end
	local shown: { any } = {}
	for _, child in holder:GetChildren() do
		if child:GetAttribute("Toast") == true and child:GetAttribute("Leaving") ~= true then
			if child:GetAttribute("Text") == text then
				return -- (these words are on screen already)
			end
			table.insert(shown, child)
		end
	end
	table.sort(shown, function(a: any, b: any): boolean
		return a.LayoutOrder < b.LayoutOrder
	end)
	for index = 1, #shown - HUD.MaxToasts + 1 do
		shown[index]:Destroy()
	end
	toastOrder += 1
	local strip = Ui.make("CanvasGroup", {
		Name = "Toast",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		GroupTransparency = 1,
		LayoutOrder = toastOrder,
	}, holder)
	strip:SetAttribute("Toast", true)
	strip:SetAttribute("Text", text)
	Ui.make("Frame", { Name = "Rule", Size = UDim2.new(0, 2, 1, 14), Position = UDim2.fromOffset(-14, -7), BackgroundColor3 = K.text, BorderSizePixel = 0 }, strip)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 7) }, strip)
	local label = Ui.label(strip, text, UDim2.fromOffset(0, 0), { Name = "Text", AutomaticSize = Enum.AutomaticSize.XY, TextSize = 14, Font = Theme.Font, TextColor3 = K.text, TextWrapped = true })
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(COLUMN_W - 28, math.huge) }, label)
	fade(strip, 0, 0.18)
	task.delay(HUD.Toast, function()
		if not strip.Parent then
			return
		end
		strip:SetAttribute("Leaving", true)
		fade(strip, 1, 0.3)
		task.delay(0.35, function()
			strip:Destroy()
		end)
	end)
end

function SandboxHud.toast(text: string)
	local notify: ((string) -> ())? = SandboxHud.notify or hudToast
	if notify then
		notify(text)
	elseif parts.toasts then
		ownToast(text)
	else
		pcall(function() -- (8.3: not built yet: the HUD's toast all the same, a notice is never lost)
			require(script.Parent.Hud).toast(text)
		end)
	end
end

-- 8.3: a server's notice (the Notice remote, client/Main.client.luau) in this device's words: a key in brackets goes on
-- a touch screen and with a gamepad, a chip's name gets this device's key ("📋 TASKS" → "📋 TASKS (J)").
function SandboxHud.notice(text: any)
	if type(text) == "string" then
		SandboxHud.toast(PadGlyph.words(text))
	end
end

-- ── Building ────────────────────────────────────────────────────────────────

-- The ScreenGui "SandboxHud"; the spacer first in client/Hud.luau's left column (its slot "sandbox"), the HUD's toasts
-- and its gui's Enabled followed; else (no client/Hud.luau) a column of its own toasts.
local function holder(): any
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.make("ScreenGui", { Name = "SandboxHud", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	parts.gui = gui
	local ok, hud = pcall(function(): any
		return require(script.Parent.Hud)
	end)
	if ok and type(hud) == "table" and type(hud.topSlot) == "function" then
		local made, slot = pcall(hud.topSlot, "sandbox")
		if made and slot then
			slot.LayoutOrder = 0 -- (first in the column: over the contract and the toasts)
			parts.spacer = Ui.make("Frame", { Name = "SandboxSpace", Size = UDim2.fromOffset(200, 90), BackgroundTransparency = 1, LayoutOrder = 0 }, slot)
			if type(hud.toast) == "function" then
				hudToast = hud.toast
			end
			-- shown with the HUD (not on the start screen)
			local hudGui = slot:FindFirstAncestorWhichIsA("ScreenGui")
			if hudGui then
				gui.Enabled = hudGui.Enabled
				hudGui:GetPropertyChangedSignal("Enabled"):Connect(function()
					gui.Enabled = hudGui.Enabled
				end)
			end
			return gui
		end
	end
	local toasts = Ui.make("Frame", { Name = "Toasts", Size = UDim2.fromOffset(COLUMN_W, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(16, 120), BackgroundTransparency = 1 }, gui)
	parts.toastScale = Ui.make("UIScale", { Name = "Scale" }, toasts)
	Ui.list(toasts, true, 8)
	parts.toasts = toasts
	return gui
end

-- A chip under the money's card (the stock's, 8.2: the book's): a pill with its key in a small outline at its right
-- (shown on a computer), raised under the mouse. → the chip, its corner, its key's label.
local function chipButton(block: any, name: string, key: string): (any, any, any)
	local chip = Ui.make("TextButton", {
		Name = name,
		BackgroundColor3 = K.row,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Font = Theme.HeadingFont,
		TextSize = HUD.ChipText,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, block)
	local corner = Ui.make("UICorner", { CornerRadius = UDim.new(0, 16) }, chip)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, chip)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12) }, chip)
	local keyLabel = Ui.label(chip, key, UDim2.fromOffset(20, 20), {
		Name = "Key",
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.4 }, keyLabel)
	Ui.corner(keyLabel, 4)
	chip.MouseEnter:Connect(function()
		chip.BackgroundColor3 = K.raised
	end)
	chip.MouseLeave:Connect(function()
		chip.BackgroundColor3 = K.row
	end)
	return chip, corner, keyLabel
end

-- 8.2: the collection book (client/CollectionBookUi.luau), nil while it is not in this build.
local function bookUi(): any
	local ok, found = pcall(function(): any
		return require(script.Parent.CollectionBookUi)
	end)
	return if ok and type(found) == "table" and type(found.toggle) == "function" then found else nil
end

local function build(parent: any)
	local block = Ui.make("Frame", { Name = "MoneyBlock", Size = UDim2.fromOffset(200, 90), Position = UDim2.fromOffset(16, 14), BackgroundTransparency = 1 }, parent)
	parts.block = block
	parts.scale = Ui.make("UIScale", { Name = "Scale", Scale = 1 }, block)
	local card = Ui.make("Frame", { Name = "MoneyCard", BackgroundColor3 = K.charcoal, BackgroundTransparency = K.scrim, BorderSizePixel = 0 }, block)
	Ui.corner(card, 10)
	parts.card = card
	parts.money = Ui.label(card, Ui.money(0), UDim2.fromOffset(100, HUD.MoneySize + 4), {
		Name = "Money",
		Position = UDim2.fromOffset(PAD_X, PAD_Y),
		Font = Theme.DisplayFont,
		TextSize = HUD.MoneySize,
		TextColor3 = CardKit.Color.money,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	parts.income = Ui.label(card, "", UDim2.fromOffset(100, HUD.IncomeSize + 4), {
		Name = "Income",
		Position = UDim2.fromOffset(PAD_X, PAD_Y + HUD.MoneySize + 4),
		Font = Theme.HeadingFont,
		TextSize = HUD.IncomeSize,
		TextColor3 = K.good,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
	})
	local chip, chipCorner, key = chipButton(block, "StockChip", HUD.StockKey)
	parts.chipCorner, parts.key = chipCorner, key
	chip.Activated:Connect(function()
		CardKit.click()
		WarehouseUi.openStock()
	end)
	parts.chip = chip
	-- 8.2: the 📖 BOOK chip beside it (the collection book), when the book is in this build
	local book = bookUi()
	if book then
		local bookChip, bookCorner, bookKey = chipButton(block, "BookChip", Config.CollectionBook.Key)
		bookChip.Text = "📖 BOOK"
		parts.bookCorner, parts.bookKey, parts.bookUi = bookCorner, bookKey, book
		bookChip.Activated:Connect(function()
			CardKit.click()
			book.toggle()
		end)
		parts.book = bookChip
	end
end

-- ── Updates ─────────────────────────────────────────────────────────────────

local function setMoney(value: any)
	if type(value) ~= "number" or value ~= value or not parts.money then
		return
	end
	money = value
	Juice.countMoney(parts.money, value)
	arrange()
end

-- The player's State (client/Main.client.luau passes the State remote's table, as the old HUD gets it): its money.
function SandboxHud.setState(state: any)
	if type(state) == "table" then
		setMoney(state.money)
	end
end

-- 8.3: the market's toast, once the HUD shows (not on the start screen).
local function tellMarket()
	local text = marketToast
	local screen = parts.gui
	if text and screen and screen.Enabled then
		marketToast = nil
		SandboxHud.toast(text)
	end
end

local function onState(state: WarehouseUi.State, previous: WarehouseUi.State?)
	local market = state.market
	if market and (marketTold == nil or market.day > marketTold) then
		marketTold = market.day
		marketToast = Market.hotToast(market)
		tellMarket()
	end
	income = state.income
	idleShare = state.idle
	local count = 0
	for _, entry in state.stock do
		if not entry.stand then
			count += 1
		end
	end
	inStock = count
	if previous and #state.stock > #previous.stock then
		local more = #state.stock - #previous.stock
		SandboxHud.toast(`+{more} {if more == 1 then "piece" else "pieces"} in your warehouse`)
	end
	arrange()
end

-- The money until the first State: the player list's (leaderstats "💰 $", 8.2 server/SandboxLeaders.luau's column;
-- the city's Money before it).
local function watchLeaderstats()
	local player = Players.LocalPlayer
	local stats = player:WaitForChild("leaderstats", 30)
	local leaders = (Config :: any).SandboxLeaders
	local name = if type(leaders) == "table" and type(leaders.Stats) == "table" and type(leaders.Stats.Money) == "string" then leaders.Stats.Money else "Money"
	local value = if stats then stats:FindFirstChild(name) or stats:FindFirstChild("Money") else nil
	if value and value:IsA("IntValue") then
		local intValue = value :: IntValue
		setMoney(intValue.Value)
		intValue:GetPropertyChangedSignal("Value"):Connect(function()
			setMoney(intValue.Value)
		end)
	end
end

function SandboxHud.block(): any
	return parts.block
end

function SandboxHud.gui(): any
	return parts.gui
end

function SandboxHud.start()
	if started or not sandboxOn() then
		return
	end
	started = true
	local ok, key = pcall(function(): any
		return (Enum.KeyCode :: any)[HUD.StockKey]
	end)
	stockKey = if ok then key else nil
	build(holder())
	parts.gui:GetPropertyChangedSignal("Enabled"):Connect(tellMarket) -- (8.3: the market's toast when the HUD shows)
	WarehouseUi.notify = SandboxHud.toast
	if parts.bookUi then
		parts.bookUi.notify = SandboxHud.toast -- (8.2: the collection book's toasts)
	end
	WarehouseUi.onState(onState)
	WarehouseUi.start()
	task.spawn(watchLeaderstats)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local pad = PadGlyph.pressed(input, processed, "stock") -- (8.3: the gamepad's D-pad ←)
		if not pad and (processed or input.KeyCode ~= stockKey or UserInputService:GetFocusedTextBox()) then
			return
		end
		local screen = parts.gui
		if screen and not screen.Enabled then
			return -- (the HUD is hidden: the start screen)
		end
		WarehouseUi.toggleStock()
	end)
	PadGlyph.watch(arrange) -- (8.3: a gamepad picked up or put down: the chips' keys again)
	-- 8.3: the first-time hints (their toasts are this HUD's)
	local hintsOk, hints = pcall(function(): any
		return require(script.Parent.SandboxHintsUi)
	end)
	if hintsOk and type(hints) == "table" then
		hints.notify = SandboxHud.toast
		local startedOk, why = pcall(hints.start)
		if not startedOk then
			warn(`[SandboxHud] the first-time hints did not start: {why}`)
		end
	end
	-- a new screen size, Hud's column moved (the chat opened or closed) or scaled again: laid out again
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(queueArrange)
	end
	local spacer = parts.spacer
	if spacer then
		spacer:GetPropertyChangedSignal("AbsolutePosition"):Connect(arrange)
		local node = spacer.Parent
		while node and not node:IsA("PlayerGui") do
			for _, child in node:GetChildren() do
				if child:IsA("UIScale") then
					child:GetPropertyChangedSignal("Scale"):Connect(queueArrange)
				end
			end
			node = node.Parent
		end
	end
	arrange()
end

return SandboxHud
