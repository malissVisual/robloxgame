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
--   * "+$X/min" in green under it while pieces are on show (the "Collection" remote's state: income)
--   * the chip "📦 N in stock" (the pieces not on show): a tap, or the key Config.SandboxHud.StockKey (B), opens the
--     STOCK list (client/WarehouseUi.luau; the key again closes it)
--   * toasts: a piece sold ("Sold Grandpa's Clock · +$420", client/WarehouseUi.luau's "sold") and pieces brought home
--     ("+5 pieces in your warehouse", when a state's stock grew): Hud.toast; without client/Hud.luau a column of its own
--     at the top left with its own toasts in the same look
-- Standing in Hud's column keeps it clear of what the HUD still shows in the sandbox: the toasts flow under it, the
-- health row (bottom left on a computer; on a touch screen the left column the column stands beside), MOUSE [ALT] and
-- the key hints at the top right, the move's blocks at the top in the middle (tools/phone-ui/sandbox.luau checks it).
-- A touch screen: the block is never smaller than Config.SandboxHud.TouchScale and its chip is a finger's size
-- (Ui.MinTouch screen px). SandboxHud.start() does nothing when Config.Sandbox.On is false; it also starts
-- client/WarehouseUi.luau (once).
--   SandboxHud.start()         builds it and listens
--   SandboxHud.setState(state) the player's State (its money)
--   SandboxHud.toast(text)     a toast (SandboxHud.notify when set, else Hud.toast, else its own)
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
local inStock = 0
local stockKey: Enum.KeyCode? = nil
local arrangeQueued = false
local toastOrder = 0

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
	local incomeText = `+{Ui.money(income)}/min`
	local incomeW = if income > 0 then CardKit.width(incomeText, HUD.IncomeSize, Theme.HeadingFont) else 0
	local cardW = math.ceil(math.max(moneyW, incomeW, 90)) + 2 * PAD_X
	local moneyH = HUD.MoneySize + 4
	local cardH = PAD_Y + moneyH + (if income > 0 then HUD.IncomeSize + 4 else 0) + PAD_Y
	parts.card.Size = UDim2.fromOffset(cardW, cardH)
	parts.money.Size = UDim2.fromOffset(cardW - 2 * PAD_X, moneyH)
	parts.income.Visible = income > 0
	parts.income.Text = incomeText
	parts.income.Size = UDim2.fromOffset(cardW - 2 * PAD_X, HUD.IncomeSize + 4)
	-- the chip: "📦 N in stock" (and its key on a computer), a finger's size on a touch screen
	local chip = parts.chip
	local chipText = `📦 {inStock} in stock`
	chip.Text = chipText
	local keyShown = not touch and stockKey ~= nil
	parts.key.Visible = keyShown
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
	local blockW, blockH = math.max(cardW, chipW), cardH + GAP + chipH
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
	else
		ownToast(text)
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
	local chip = Ui.make("TextButton", {
		Name = "StockChip",
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
	parts.chipCorner = Ui.make("UICorner", { CornerRadius = UDim.new(0, 16) }, chip)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, chip)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12) }, chip)
	parts.key = Ui.label(chip, HUD.StockKey, UDim2.fromOffset(20, 20), {
		Name = "Key",
		Position = UDim2.new(1, -8, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.4 }, parts.key)
	Ui.corner(parts.key, 4)
	chip.MouseEnter:Connect(function()
		chip.BackgroundColor3 = K.raised
	end)
	chip.MouseLeave:Connect(function()
		chip.BackgroundColor3 = K.row
	end)
	chip.Activated:Connect(function()
		CardKit.click()
		WarehouseUi.openStock()
	end)
	parts.chip = chip
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

local function onState(state: WarehouseUi.State, previous: WarehouseUi.State?)
	income = state.income
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

-- The money until the first State: the player list's (leaderstats Money).
local function watchLeaderstats()
	local player = Players.LocalPlayer
	local stats = player:WaitForChild("leaderstats", 30)
	local value = if stats then stats:FindFirstChild("Money") else nil
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
	WarehouseUi.notify = SandboxHud.toast
	WarehouseUi.onState(onState)
	WarehouseUi.start()
	task.spawn(watchLeaderstats)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or input.KeyCode ~= stockKey or UserInputService:GetFocusedTextBox() then
			return
		end
		local screen = parts.gui
		if screen and not screen.Enabled then
			return -- (the HUD is hidden: the start screen)
		end
		WarehouseUi.toggleStock()
	end)
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
