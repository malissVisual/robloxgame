--!strict
-- 8.1 SANDBOX: the UPGRADES desk's window (the owner: "the money players earn needs something to buy"). The desk in
-- your warehouse (server/Warehouse.luau) opens it through the "Upgrades" remote; server/Upgrades.luau decides every
-- purchase, this window only shows the cards and asks:
--   { kind = "state", levels, money }   kept; an open window is drawn again only when what it shows changed
--   { kind = "open" }                   the desk's prompt: THE WINDOW
--   { kind = "bought", id, level }      a toast "Showroom lights: level 2 · Income ×1.21" (UpgradeUi.notify, else
--                                       client/Hud.luau's toast)
-- THE WINDOW: a modal card "ZDC UPGRADES" (your money under it, ✕) over one card an upgrade (shared/UpgradeRules.luau
-- rows, Config.SandboxUpgrades' order): its picture (the emoji), its name and level (a segmented bar, "LV 1/4"), what
-- it gives now and what the next level gives, the next price (money green when you have it) and BUY. BUY sends
-- { kind = "buy", id, level } (the level it offers: a second click buys once); without the money the button is grey,
-- says how much is missing and a tap only says so; at the top level a gold MAX. Your money follows the State remote
-- (a sale, the stands' income) so the buttons light up while it is open.
-- ✕, ESC, the gamepad's B, the Roblox menu or a tap beside the card close it. It is modal: the mouse is free while it is
-- open (a Modal button), a touch screen's buttons are under it. Follows client/WarehouseUi.luau's kit (CardKit, Theme).
--   UpgradeUi.start()                  listens (once; nothing when Config.Sandbox.On is false)
--   UpgradeUi.open() / close() / isOpen()
--   UpgradeUi.state()                  { levels, money } the last state (nil: none yet)
--   UpgradeUi.layout(W, H, touch)      the card on a W × H screen (px under Roblox's top bar)
--   UpgradeUi.notify / onOpen          hooks: the toasts, the window opened
-- Presentation only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local UpgradeRules = require(Shared.UpgradeRules)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)

local UpgradeUi = {}

local K = Theme.Contract
local C = CardKit.Color

export type State = { levels: { [string]: number }, money: number }
export type Layout = {
	touch: boolean,
	scale: number, -- the card's UIScale
	x: number, -- the card's top left on the screen (px)
	y: number,
	w: number, -- the card's size (unscaled)
	h: number,
	pad: number,
	header: number,
	close: number, -- the ✕'s side
	listY: number,
	listH: number,
	rowW: number,
	rowH: number,
	gap: number,
	button: number, -- BUY's height
	buttonW: number,
	priceW: number,
}

UpgradeUi.notify = nil :: ((text: string) -> ())?
UpgradeUi.onOpen = nil :: (() -> ())?

local WIDTH = 680 -- the card's widest (unscaled px)
local HEADER = 52
local LIST_GAP = 4 -- under the header
local SCROLLBAR = 6

local started = false
local remote: RemoteEvent? = nil
local current: State? = nil
local gui: any = nil
local opened = false
local shownKey = ""
local card: any = nil -- the shade over the screen (the window: card's Upgrades)
local sentAt: { [string]: number } = {}

-- ── The layout (pure) ───────────────────────────────────────────────────────

function UpgradeUi.layout(W: number, H: number, touch: boolean): Layout
	local margin = if touch then 8 else 16
	local scale = if touch
		then math.clamp(math.min(W / 860, H / 380), 0.8, Ui.MaxScale)
		else math.max(Ui.scaleFor(Vector2.new(W, H)), 0.7)
	local pad = if touch then 10 else 16
	local gap = 6
	local finger = math.ceil(Ui.MinTouch / scale)
	local button = if touch then math.max(44, finger) else 36
	local rowH = math.max(if touch then 68 else 72, button + 16)
	local rows = #UpgradeRules.Order
	local want = HEADER + LIST_GAP + rows * rowH + (rows - 1) * gap + pad
	local w = math.floor(math.min(WIDTH, (W - 2 * margin) / scale))
	local h = math.floor(math.min(want, (H - 2 * margin) / scale))
	return {
		touch = touch,
		scale = scale,
		x = math.floor((W - w * scale) / 2),
		y = math.floor((H - h * scale) / 2),
		w = w,
		h = h,
		pad = pad,
		header = HEADER,
		close = if touch then math.max(40, finger) else 40,
		listY = HEADER + LIST_GAP,
		listH = h - HEADER - LIST_GAP - pad,
		rowW = w - 2 * pad,
		rowH = rowH,
		gap = gap,
		button = button,
		buttonW = if touch then 112 else 104,
		priceW = 92,
	}
end

-- ── Sending ─────────────────────────────────────────────────────────────────

-- One request an upgrade at most every 0.6 s (a double tap is one request).
local function send(message: { [string]: any }): boolean
	local key = `{message.kind}:{tostring(message.id)}`
	local now = os.clock()
	if sentAt[key] and now - sentAt[key] < 0.6 then
		return false
	end
	sentAt[key] = now
	local target = remote
	if target then
		target:FireServer(message)
	end
	return true
end

local function toast(text: string)
	local notify = UpgradeUi.notify
	if notify then
		notify(text)
		return
	end
	pcall(function()
		require(script.Parent.Hud).toast(text)
	end)
end

-- ── The window ──────────────────────────────────────────────────────────────

local draw: (keepScroll: boolean) -> ()

local function ensureGui(): any
	if gui then
		return gui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.make("ScreenGui", {
		Name = "UpgradeUi",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7, -- (with the warehouse's picker: over the HUD and the touch buttons)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	return gui
end

function UpgradeUi.close()
	if not opened then
		return
	end
	opened = false
	if card then
		Ui.gamepadRelease(gui)
		card:Destroy()
		card = nil
	end
	shownKey = ""
end

function UpgradeUi.isOpen(): boolean
	return opened
end

function UpgradeUi.state(): State?
	return current
end

local function stateKey(state: State?, layout: Layout): string
	local parts = { `{layout.w}x{layout.h}@{layout.scale}` }
	if state then
		for _, id in UpgradeRules.Order do
			table.insert(parts, `{id}={UpgradeRules.level(state.levels, id)}`)
		end
		-- (only what changes a card: which prices the money reaches; the money's line and a NEED's amount follow the
		-- money in place, so a payout never rebuilds the window under a tap or a gamepad's selection)
		for _, row in UpgradeRules.rows(state.levels, state.money) do
			table.insert(parts, if row.can then "1" else "0")
		end
	else
		table.insert(parts, "none")
	end
	return table.concat(parts, "|")
end

-- The level's segments (one a level, the bought ones lit) and "LV 1/4".
local function levelBar(parent: any, row: UpgradeRules.Row, x: number, y: number): number
	local seg, gap = 12, 3
	for n = 1, row.max do
		local on = n <= row.level
		local piece = Ui.make("Frame", {
			Name = `Level{n}`,
			Size = UDim2.fromOffset(seg, 5),
			Position = UDim2.fromOffset(x + (n - 1) * (seg + gap), y + 6),
			BackgroundColor3 = if on then (if row.level >= row.max then C.gold else C.money) else K.track,
			BorderSizePixel = 0,
		}, parent)
		Ui.corner(piece, 2)
	end
	local after = x + row.max * (seg + gap) + 4
	local text = `LV {row.level}/{row.max}`
	Ui.label(parent, text, UDim2.fromOffset(CardKit.width(text, 11, Theme.HeadingFont) + 4, 16), { Name = "Level", Position = UDim2.fromOffset(after, y), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = if row.level >= row.max then C.gold else K.secondary, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left })
	return after + CardKit.width(text, 11, Theme.HeadingFont) + 4
end

-- The row `id` for the money and the levels now (nil: no state yet).
local function liveRow(id: string): UpgradeRules.Row?
	local state = current
	if not state then
		return nil
	end
	for _, row in UpgradeRules.rows(state.levels, state.money) do
		if row.id == id then
			return row
		end
	end
	return nil
end

-- What follows the money on an open window without a rebuild: the money's line and each NEED's amount.
local function subtitleOf(state: State?): string
	return if state then `Your money {UpgradeRules.money(state.money)} · more stands, brighter lights, a faster van and Danny` else "Loading your upgrades…"
end

local function followMoney()
	local state = current
	local frame = card and card:FindFirstChild("Upgrades")
	if not (state and frame) then
		return
	end
	local subtitle = frame:FindFirstChild("Subtitle")
	if subtitle then
		subtitle.Text = subtitleOf(state)
	end
	local list = frame:FindFirstChild("List")
	if not list then
		return
	end
	for _, row in UpgradeRules.rows(state.levels, state.money) do
		local made = list:FindFirstChild(`Upgrade_{row.id}`)
		local buy = made and made:FindFirstChild("Buy")
		if buy and not row.can and row.price then
			buy.Text = `NEED {UpgradeRules.money(row.short)}`
		end
	end
end

local function drawRow(parent: any, row: UpgradeRules.Row, index: number, layout: Layout, rowW: number)
	local h = layout.rowH
	local frame = Ui.make("Frame", {
		Name = `Upgrade_{row.id}`,
		Size = UDim2.fromOffset(rowW, h),
		Position = UDim2.fromOffset(0, (index - 1) * (h + layout.gap)),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
	}, parent)
	Ui.corner(frame, Config.UiKit.RowCorner)
	local top = row.level >= row.max
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if top then C.gold elseif row.can then C.money else K.line, Thickness = 1, Transparency = if top or row.can then 0.45 else 0.8 }, frame)
	-- the picture: the upgrade's emoji on charcoal
	local side = h - 12
	local picture = Ui.make("Frame", { Name = "Picture", Size = UDim2.fromOffset(side, side), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = K.charcoal, BorderSizePixel = 0 }, frame)
	Ui.corner(picture, 8)
	Ui.label(picture, row.icon, UDim2.fromScale(1, 1), { Name = "Emoji", TextSize = math.floor(side * 0.55), TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
	-- the right: the price and BUY (at the top: MAX)
	local right = layout.buttonW + 10
	local buttonY = math.floor((h - layout.button) / 2)
	if top then
		local max = Ui.label(frame, "MAX", UDim2.fromOffset(layout.buttonW, layout.button), {
			Name = "Max",
			Position = UDim2.new(1, -right, 0, buttonY),
			BackgroundColor3 = C.gold,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 14,
			TextColor3 = C.goldInk,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Ui.corner(max, 8)
	else
		local price = row.price :: number
		Ui.label(frame, UpgradeRules.money(price), UDim2.fromOffset(layout.priceW, 24), {
			Name = "Price",
			Position = UDim2.new(1, -(right + 8), 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Font = Theme.DisplayFont,
			TextSize = 18,
			TextColor3 = if row.can then C.money else C.dim,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local words = if row.can then "BUY" else `NEED {UpgradeRules.money(row.short)}`
		local buy = CardKit.bigButton(frame, {
			name = "Buy",
			text = words,
			kind = if row.can then "good" else "shut",
			height = layout.button,
			textSize = if row.can then 15 elseif layout.touch then 12 else 11,
			onClick = function()
				if not row.can then
					local live = liveRow(row.id) -- (the money moved since the card was drawn)
					toast(`{row.name}: you need {UpgradeRules.money(if live then live.short else row.short)} more.`)
					return
				end
				if send({ kind = "buy", id = row.id, level = row.level + 1 }) then
					local button = frame:FindFirstChild("Buy")
					if button then
						button.Text = "…"
						button.Active = false
					end
				end
			end,
		})
		buy.Size = UDim2.fromOffset(layout.buttonW, layout.button)
		buy.Position = UDim2.new(1, -right, 0, buttonY)
	end
	-- the words: the name and its level, what it gives now, what the next level gives
	local x = 6 + side + 12
	local room = math.max(60, rowW - x - right - layout.priceW - 16)
	local nameW = math.min(room, CardKit.width(row.name, 15, Theme.HeadingFont) + 12) -- (a little slack: the name is never cut where it fits)
	local y = math.floor((h - 52) / 2)
	Ui.label(frame, row.name, UDim2.fromOffset(nameW, 18), { Name = "UpgradeName", Position = UDim2.fromOffset(x, y), Font = Theme.HeadingFont, TextSize = 15, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	levelBar(frame, row, x + nameW + 8, y + 1)
	Ui.label(frame, row.now, UDim2.fromOffset(room, 16), { Name = "Now", Position = UDim2.fromOffset(x, y + 20), TextSize = 13, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.label(frame, if row.next then `Next: {row.next}` else "Top level", UDim2.fromOffset(room, 14), { Name = "Next", Position = UDim2.fromOffset(x, y + 38), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = if row.next then C.money else C.gold, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
end

draw = function(keepScroll: boolean)
	if not opened then
		return
	end
	local size = Ui.screenSize()
	local layout = UpgradeUi.layout(size.X, size.Y, Ui.touchLayout())
	local key = stateKey(current, layout)
	if card and key == shownKey then
		followMoney()
		return -- (nothing else it shows changed: no redraw, a tap is never lost)
	end
	shownKey = key
	local list = card and card:FindFirstChild("Upgrades") and card:FindFirstChild("Upgrades"):FindFirstChild("List")
	local scroll = if keepScroll and list then list.CanvasPosition else Vector2.zero
	local selected = Ui.gamepadSelection()
	local heldInside = card ~= nil and selected ~= nil and selected:IsDescendantOf(card)
	if card then
		card:Destroy()
	end
	local root = ensureGui()
	-- a shade over the world (the touch buttons too): a tap beside the card closes it; Modal frees the mouse
	card = Ui.make("TextButton", {
		Name = "UpgradeShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Modal = true,
	}, root)
	card.Activated:Connect(UpgradeUi.close)
	local frame = Ui.make("Frame", {
		Name = "Upgrades",
		Size = UDim2.fromOffset(layout.w, layout.h),
		Position = UDim2.fromOffset(layout.x, layout.y),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true,
	}, card)
	Ui.make("UIScale", { Name = "Scale", Scale = layout.scale }, frame)
	Ui.corner(frame, Config.UiKit.Corner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, frame)
	-- the header: the title, your money, the ✕
	local state = current
	local wide = layout.w - (layout.pad * 2 + layout.close + 8)
	Ui.label(frame, "⬆ ZDC UPGRADES", UDim2.fromOffset(wide, 24), { Name = "Title", Position = UDim2.fromOffset(layout.pad, 10), Font = Theme.HeadingFont, TextSize = 18, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local subtitle = subtitleOf(state)
	Ui.label(frame, subtitle, UDim2.fromOffset(wide, 16), { Name = "Subtitle", Position = UDim2.fromOffset(layout.pad, 33), TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local close = Ui.closeButton(frame, UpgradeUi.close)
	close.Size = UDim2.fromOffset(layout.close, layout.close)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.AnchorPoint = Vector2.new(1, 0)
	-- the cards (a list that scrolls when the screen is short)
	local rows: { UpgradeRules.Row } = if state then UpgradeRules.rows(state.levels, state.money) else {}
	local tall = #rows * (layout.rowH + layout.gap) - layout.gap
	local scrolls = tall > layout.listH
	local listFrame = Ui.make("ScrollingFrame", {
		Name = "List",
		Size = UDim2.fromOffset(layout.rowW, layout.listH),
		Position = UDim2.fromOffset(layout.pad, layout.listY),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if scrolls then SCROLLBAR else 0,
		ScrollBarImageColor3 = K.line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, math.max(0, tall)),
		CanvasPosition = Vector2.new(0, math.clamp(scroll.Y, 0, math.max(0, tall - layout.listH))),
	}, frame)
	local rowW = layout.rowW - (if scrolls then SCROLLBAR + 2 else 0)
	for index, row in rows do
		drawRow(listFrame, row, index, layout, rowW)
	end
	local first: any = nil
	for _, row in rows do
		local made = listFrame:FindFirstChild(`Upgrade_{row.id}`)
		local buy = made and made:FindFirstChild("Buy")
		if buy and row.can then
			first = buy
			break
		end
	end
	if not keepScroll or heldInside then
		Ui.gamepadFocus(first or close) -- (a redraw while open moves the gamepad only when its selection went with it)
	end
end

local function amount(value: any): number?
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else nil
end

local function setState(raw: any)
	local levels: { [string]: number } = {}
	if type(raw.levels) == "table" then
		for _, id in UpgradeRules.Order do
			local level = UpgradeRules.level(raw.levels, id)
			if level > 0 then
				levels[id] = level
			end
		end
	end
	local was = current
	current = { levels = levels, money = amount(raw.money) or (if was then was.money else 0) }
	if opened then
		draw(true)
	end
end

function UpgradeUi.open()
	local was = opened
	opened = true
	shownKey = ""
	if not was then
		local onOpen = UpgradeUi.onOpen
		if onOpen then
			onOpen()
		end
	end
	draw(false)
	if not current and remote then
		send({ kind = "state" })
	end
end

local function onEvent(message: any)
	if type(message) ~= "table" then
		return
	end
	local kind = message.kind
	if kind == "state" then
		setState(message)
	elseif kind == "open" then
		UpgradeUi.open()
	elseif kind == "bought" then
		local def = UpgradeRules.def(message.id)
		local level = amount(message.level)
		if def and level then
			toast(`{def.name}: level {math.floor(level)} · {UpgradeRules.effect(message.id, level)}`)
		end
	end
end

-- The money from the player's State (a sale, the stands' income): the cards' BUY follow it while open.
local function onMoney(state: any)
	local money = if type(state) == "table" then amount(state.money) else nil
	local now = current
	if money and now and money ~= now.money then
		current = { levels = now.levels, money = money }
		if opened then
			draw(true)
		end
	end
end

local function sandboxOn(): boolean
	local sandbox = (Config :: any).Sandbox
	return type(sandbox) == "table" and sandbox.On == true
end

function UpgradeUi.start()
	if started or not sandboxOn() then
		return
	end
	started = true
	-- ESC, the gamepad's B and the Roblox menu close it
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) and opened and not UserInputService:GetFocusedTextBox() then
			UpgradeUi.close()
		end
	end)
	GuiService.MenuOpened:Connect(UpgradeUi.close)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if opened then
				draw(true)
			end
		end)
	end
	task.spawn(function()
		local ok, found = pcall(Net.get, "Upgrades")
		if not ok then
			warn(`[UpgradeUi] no Upgrades remote: {found}`)
			return
		end
		remote = found
		found.OnClientEvent:Connect(onEvent)
		found:FireServer({ kind = "state" })
		local hasState, state = pcall(Net.get, "State")
		if hasState then
			state.OnClientEvent:Connect(onMoney)
		end
	end)
end

return UpgradeUi
