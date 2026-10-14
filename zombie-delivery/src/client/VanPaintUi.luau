--!strict
-- 8.3 SANDBOX: the PAINT shop's window (the owner: give players a way to make their van their own). The 🎨 Paint van
-- prompt on your own van, parked at your warehouse, opens it through the "VanPaint" remote; server/VanPaint.luau decides
-- every purchase (shared/VanPaintRules.luau, Config.VanPaint), this window only shows and asks:
--   { kind = "state", owned, worn, money, paid }   kept; an open window is drawn again only when what it shows changed
--   { kind = "open" }                              the prompt: THE WINDOW
--   { kind = "bought", id } / { kind = "worn", id } a toast ("Fire red is yours: on your van now.")
-- THE WINDOW: a modal card "🎨 PAINT SHOP" (your money under it, ✕). At its left your van in 3D
-- (client/VanPaintPreview.luau: a copy of your own van, in the colour and the stripes you look at), the swatch's name,
-- what it is for you (on your van, yours, its price, what unlocks it) and its one button: BUY $X (green with the
-- money; a grey NEED $X without it, a tap only says so), WEAR (yours: free), ✓ ON YOUR VAN, 🔒 LOCKED (a tap says what
-- unlocks it). At its right the tabs 🎨 PAINT / 🏁 LIVERY over a scrolling grid of swatches in Config's order (a colour
-- chip; a livery's chip is your body with its band; the name; ✓ ON VAN, OWNED, 🔒 LOCKED or the price; the premium ones
-- in a gold frame). A swatch tapped (A on a gamepad) is looked at: the picture shows it with what you wear of the other
-- kind (a colour and a livery together before you buy either). BUY sends { kind = "buy", id }, WEAR { kind = "wear", id }
-- (one request an item at most every 0.6 s). Your money follows the State remote, so the buttons light up while it is
-- open.
-- ✕, ESC, the gamepad's B, the Roblox menu or a tap beside the card close it. It is modal (the mouse free: a Modal
-- button; a touch screen's buttons under it) and keeps the gamepad's selection inside (a selection group). Opening it
-- closes the other sandbox windows (client/Main.client.luau: onOpen). Follows client/UpgradeUi.luau's kit.
--   VanPaintUi.start()                  listens (once; nothing when Config.Sandbox.On is false)
--   VanPaintUi.open() / close() / isOpen()
--   VanPaintUi.state()                  the last state ({ owned, worn, money, paid }; nil: none yet)
--   VanPaintUi.view()                   { tab, selected, pick }: the tab, the swatch looked at, what the picture shows
--   VanPaintUi.layout(W, H, touch)      the card on a W × H screen (px under Roblox's top bar)
--   VanPaintUi.notify / onOpen          hooks: the toasts, the window opened
-- Presentation only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.VanPaintRules)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)
local Preview = require(script.Parent.VanPaintPreview)

local VanPaintUi = {}

local K = Theme.Contract
local C = CardKit.Color
local WIN = Config.VanPaint.Window

export type State = { owned: { [string]: boolean }, worn: Rules.Worn, money: number, paid: { [string]: boolean } }
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
	leftW: number, -- the picture's column
	previewH: number,
	infoY: number,
	buttonY: number,
	button: number,
	tabsY: number,
	tabsH: number,
	tabW: number,
	gridX: number,
	gridY: number,
	gridW: number,
	gridH: number,
	cols: number,
	tileW: number,
	tileH: number,
	gap: number,
}

VanPaintUi.notify = nil :: ((text: string) -> ())?
VanPaintUi.onOpen = nil :: (() -> ())?

local HEADER = 52
local INFO = 38 -- the swatch's name and its line under the picture
local SCROLLBAR = 6
local TABS = { { "paint", "🎨 PAINT" }, { "livery", "🏁 LIVERY" } }

local started = false
local remote: RemoteEvent? = nil
local current: State? = nil
local gui: any = nil
local opened = false
local shownKey = ""
local card: any = nil -- the shade over the screen (the window: card's VanPaint)
local sentAt: { [string]: number } = {}
local tab = "paint"
local selected: string? = nil -- the swatch looked at (its button's)
local pick: Rules.Worn = table.clone(Rules.Default) -- what the picture shows

-- ── The layout (pure) ───────────────────────────────────────────────────────

function VanPaintUi.layout(W: number, H: number, touch: boolean): Layout
	local margin = if touch then 8 else 16
	local scale = if touch
		then math.clamp(math.min(W / 860, H / 380), 0.8, Ui.MaxScale)
		else math.max(Ui.scaleFor(Vector2.new(W, H)), 0.7)
	local w = math.floor(math.min(WIN.Width, (W - 2 * margin) / scale))
	local h = math.floor(math.min(WIN.Height, (H - 2 * margin) / scale))
	local pad = if touch then 10 else 16
	local finger = math.ceil(Ui.MinTouch / scale)
	local button = if touch then math.max(44, finger) else 38
	local leftW = math.floor(w * WIN.Preview)
	local buttonY = h - pad - button
	local infoY = buttonY - 6 - INFO
	local tabsH = if touch then math.max(36, finger) else 30
	local gridX = pad + leftW + 12
	local gridW = w - gridX - pad
	local gridY = HEADER + tabsH + 8
	local gap = 8
	local area = gridW - SCROLLBAR - 2
	local least = if touch then WIN.TileTouch else WIN.Tile
	local cols = math.max(1, math.floor((area + gap) / (least + gap)))
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
		leftW = leftW,
		previewH = infoY - 6 - HEADER,
		infoY = infoY,
		buttonY = buttonY,
		button = button,
		tabsY = HEADER,
		tabsH = tabsH,
		tabW = math.min(130, math.floor((gridW - 8) / 2)),
		gridX = gridX,
		gridY = gridY,
		gridW = gridW,
		gridH = h - gridY - pad,
		cols = cols,
		tileW = math.floor((area - (cols - 1) * gap) / cols),
		tileH = math.max(WIN.TileHeight, finger),
		gap = gap,
	}
end

-- ── Sending, the toasts ─────────────────────────────────────────────────────

-- One request an item at most every 0.6 s (a double tap is one request).
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
	local notify = VanPaintUi.notify
	if notify then
		notify(text)
		return
	end
	pcall(function()
		require(script.Parent.Hud).toast(text)
	end)
end

-- ── What it shows ───────────────────────────────────────────────────────────

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function rowsOf(state: State?): { Rules.Row }
	if not state then
		return {}
	end
	return Rules.rows({ owned = state.owned, worn = state.worn }, state.money, state.paid, tab)
end

local function rowOf(id: string?): Rules.Row?
	local state = current
	local item = Rules.find(id)
	if not state or not item then
		return nil
	end
	for _, row in Rules.rows({ owned = state.owned, worn = state.worn }, state.money, state.paid, item.kind) do
		if row.id == item.id then
			return row
		end
	end
	return nil
end

-- The swatch's button: its words, its face ("good" / "shut") and whether a tap asks the server.
local function actionOf(row: Rules.Row): (string, string)
	if row.worn then
		return "✓ ON YOUR VAN", "shut"
	elseif row.owned then
		return "WEAR", "good"
	elseif row.locked then
		return "🔒 LOCKED", "shut"
	elseif row.can then
		return `BUY {Rules.money(row.price)}`, "good"
	end
	return `NEED {Rules.money(row.short)}`, "shut"
end

local function infoOf(row: Rules.Row): string
	if row.worn then
		return "On your van now"
	elseif row.owned then
		return "Yours: wear it for free"
	elseif row.locked then
		return `🔒 {row.lock}`
	end
	return `{Rules.money(row.price)} · yours for good once bought`
end

-- A swatch's last line: ✓ ON VAN, OWNED, 🔒 LOCKED or its price (green with the money).
local function statusOf(row: Rules.Row): (string, Color3)
	if row.worn then
		return "✓ ON VAN", C.money
	elseif row.owned then
		return "OWNED", K.secondary
	elseif row.locked then
		return "🔒 LOCKED", C.dim
	elseif row.price <= 0 then
		return "FREE", C.money
	end
	return Rules.money(row.price), if row.can then C.money else C.dim
end

local function subtitleOf(state: State?): string
	return if state then `Your money {Rules.money(state.money)} · colours and stripes for your van, for everybody to see` else "Loading your paint…"
end

-- ── The window ──────────────────────────────────────────────────────────────

local draw: (keepScroll: boolean) -> ()

local function ensureGui(): any
	if gui then
		return gui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.make("ScreenGui", {
		Name = "VanPaintUi",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7, -- (with the other sandbox windows: over the HUD and the touch buttons)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	return gui
end

function VanPaintUi.close()
	if not opened then
		return
	end
	opened = false
	Preview.clear()
	if card then
		Ui.gamepadRelease(gui)
		card:Destroy()
		card = nil
	end
	shownKey = ""
end

function VanPaintUi.isOpen(): boolean
	return opened
end

function VanPaintUi.state(): State?
	return current
end

function VanPaintUi.view(): { tab: string, selected: string?, pick: Rules.Worn }
	return { tab = tab, selected = selected, pick = table.clone(pick) }
end

local function stateKey(state: State?, layout: Layout): string
	local parts = { `{layout.w}x{layout.h}@{layout.scale}`, tab }
	if state then
		-- (only what changes a swatch: owned, worn, locked and which prices the money reaches; the money's line and a
		-- NEED's amount follow the money in place, so a payout never rebuilds the window under a tap)
		for _, row in rowsOf(state) do
			table.insert(parts, `{row.id}{if row.owned then "o" else ""}{if row.worn then "w" else ""}{if row.locked then "l" else ""}{if row.can then "c" else ""}`)
		end
	else
		table.insert(parts, "none")
	end
	return table.concat(parts, "|")
end

-- The picture: your van in what is picked.
local function showPicture()
	local frame = card and card:FindFirstChild("VanPaint")
	local holder = frame and frame:FindFirstChild("Picture")
	if holder then
		local ok, err = pcall(Preview.show, holder, Rules.look(pick))
		if not ok then
			warn(`[VanPaintUi] the picture: {err}`)
		end
	end
end

-- The swatch looked at: its frame lit, its name, its line and its button under the picture (no rebuild).
local function restyle()
	local frame = card and card:FindFirstChild("VanPaint")
	if not frame then
		return
	end
	local grid = frame:FindFirstChild("Grid")
	for _, row in rowsOf(current) do
		local tile = grid and grid:FindFirstChild(`Swatch_{row.id}`)
		local edge = tile and tile:FindFirstChild("Edge")
		if edge then
			local on = row.id == selected
			edge.Color = if on then K.text elseif row.worn then C.money elseif row.premium then C.gold else K.line
			edge.Thickness = if on then 2 else 1
			edge.Transparency = if on or row.worn or row.premium then 0.1 else 0.75
		end
	end
	local row = rowOf(selected)
	local name, info = frame:FindFirstChild("SelName"), frame:FindFirstChild("SelInfo")
	local action = frame:FindFirstChild("Action")
	if name then
		name.Text = if row then `{row.name} · {if row.kind == "paint" then "paint" else "livery"}` else ""
	end
	if info then
		info.Text = if row then infoOf(row) else ""
		info.TextColor3 = if row and row.locked then C.dim elseif row and (row.worn or row.owned) then C.money else K.secondary
	end
	if action then
		local text, kind = "…", "shut"
		if row then
			text, kind = actionOf(row)
		end
		action.Text = text
		action.Active = true
		CardKit.paint(action, kind)
	end
end

local function choose(id: string)
	local item = Rules.find(id)
	if not item then
		return
	end
	selected = item.id
	if item.kind == "paint" then
		pick.paint = item.id
	else
		pick.livery = item.id
	end
	restyle()
	showPicture()
end

-- The button under the picture: buy, wear, or say why not.
local function act()
	local row = rowOf(selected)
	if not row then
		return
	end
	local ask: string? = nil
	if row.worn then
		toast(`{row.name} is on your van already.`)
	elseif row.owned then
		ask = "wear"
	elseif row.locked then
		toast(`{row.name} unlocks with your {string.lower(row.lock)}.`)
	elseif row.can then
		ask = "buy"
	else
		toast(`{row.name}: you need {Rules.money(row.short)} more.`)
	end
	if ask and send({ kind = ask, id = row.id }) then
		local frame = card and card:FindFirstChild("VanPaint")
		local button = frame and frame:FindFirstChild("Action")
		if button then
			button.Text = "…"
			button.Active = false
		end
	end
end

-- What follows the money on an open window without a rebuild: the money's line and a NEED's amount.
local function followMoney()
	local frame = card and card:FindFirstChild("VanPaint")
	if not frame then
		return
	end
	local subtitle = frame:FindFirstChild("Subtitle")
	if subtitle then
		subtitle.Text = subtitleOf(current)
	end
	local row = rowOf(selected)
	local action = frame:FindFirstChild("Action")
	if row and action and action.Active ~= false then
		action.Text = actionOf(row)
	end
end

local function drawTile(parent: any, row: Rules.Row, index: number, layout: Layout)
	local col, line = (index - 1) % layout.cols, math.floor((index - 1) / layout.cols)
	local w, h = layout.tileW, layout.tileH
	local tile = Ui.make("TextButton", {
		Name = `Swatch_{row.id}`,
		Size = UDim2.fromOffset(w, h),
		Position = UDim2.fromOffset(col * (w + layout.gap), line * (h + layout.gap)),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = true, -- (the gamepad walks the grid; the grid scrolls to the swatch selected)
	}, parent)
	Ui.corner(tile, 8)
	Ui.make("UIStroke", { Name = "Edge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.75 }, tile)
	-- the chip: the colour (a livery: your body with its band)
	local chipH = h - 6 - 36
	local chip = Ui.make("Frame", { Name = "Chip", Size = UDim2.fromOffset(w - 12, chipH), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = rgb(row.body), BorderSizePixel = 0 }, tile)
	Ui.corner(chip, 5)
	Ui.make("UIStroke", { Name = "ChipEdge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.55 }, chip) -- (a dark colour on the dark card)
	if row.kind == "livery" then
		Ui.make("Frame", { Name = "Band", Size = UDim2.new(1, 0, 0, math.max(4, math.floor(chipH * 0.28))), Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = rgb(row.color), BorderSizePixel = 0 }, chip)
	end
	Ui.label(tile, row.name, UDim2.fromOffset(w - 12, 16), { Name = "ItemName", Position = UDim2.fromOffset(6, 6 + chipH + 2), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local status, ink = statusOf(row)
	Ui.label(tile, status, UDim2.fromOffset(w - 12, 14), { Name = "Status", Position = UDim2.fromOffset(6, h - 18), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = ink, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left })
	tile.Activated:Connect(function()
		CardKit.click()
		choose(row.id)
	end)
end

local function drawTabs(frame: any, layout: Layout)
	for index, entry in TABS do
		local id, words = entry[1], entry[2]
		local on = id == tab
		local button = Ui.make("TextButton", {
			Name = `Tab_{id}`,
			Size = UDim2.fromOffset(layout.tabW, layout.tabsH),
			Position = UDim2.fromOffset(layout.gridX + (index - 1) * (layout.tabW + 8), layout.tabsY),
			BackgroundColor3 = if on then K.raised else K.row,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = words,
			Font = Theme.HeadingFont,
			TextSize = 13,
			TextColor3 = if on then K.text else K.secondary,
		}, frame)
		Ui.corner(button, 8)
		if on then
			Ui.make("Frame", { Name = "Underline", Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 1, -2), BackgroundColor3 = K.red, BorderSizePixel = 0 }, button)
		end
		button.Activated:Connect(function()
			if tab ~= id then
				CardKit.click()
				tab = id
				selected = pick[id :: any]
				draw(false)
			end
		end)
	end
end

draw = function(keepScroll: boolean)
	if not opened then
		return
	end
	local size = Ui.screenSize()
	local layout = VanPaintUi.layout(size.X, size.Y, Ui.touchLayout())
	local key = stateKey(current, layout)
	if card and key == shownKey then
		followMoney()
		return -- (nothing else it shows changed: no redraw, a tap is never lost)
	end
	shownKey = key
	local old = card and card:FindFirstChild("VanPaint")
	local grid = old and old:FindFirstChild("Grid")
	local scroll = if keepScroll and grid then grid.CanvasPosition else Vector2.zero
	local held = Ui.gamepadSelection()
	local heldName = if card ~= nil and held ~= nil and held:IsDescendantOf(card) then held.Name else nil
	if card then
		Preview.release() -- (the van's copy kept for the new picture)
		card:Destroy()
	end
	local root = ensureGui()
	-- a shade over the world (the touch buttons too): a tap beside the card closes it; Modal frees the mouse
	card = Ui.make("TextButton", {
		Name = "PaintShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Modal = true,
	}, root)
	card.Activated:Connect(VanPaintUi.close)
	local frame = Ui.make("Frame", {
		Name = "VanPaint",
		Size = UDim2.fromOffset(layout.w, layout.h),
		Position = UDim2.fromOffset(layout.x, layout.y),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true,
		SelectionGroup = true, -- (the gamepad's selection stays in the window)
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, card)
	Ui.make("UIScale", { Name = "Scale", Scale = layout.scale }, frame)
	Ui.corner(frame, Config.UiKit.Corner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, frame)
	-- the header: the title, your money, the ✕
	local state = current
	local wide = layout.w - (layout.pad * 2 + layout.close + 8)
	Ui.label(frame, "🎨 PAINT SHOP", UDim2.fromOffset(wide, 24), { Name = "Title", Position = UDim2.fromOffset(layout.pad, 10), Font = Theme.HeadingFont, TextSize = 18, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.label(frame, subtitleOf(state), UDim2.fromOffset(wide, 16), { Name = "Subtitle", Position = UDim2.fromOffset(layout.pad, 33), TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local close = Ui.closeButton(frame, VanPaintUi.close)
	close.Size = UDim2.fromOffset(layout.close, layout.close)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.AnchorPoint = Vector2.new(1, 0)
	-- the left: the picture, the swatch's name and line, its button
	local picture = Ui.make("Frame", { Name = "Picture", Size = UDim2.fromOffset(layout.leftW, layout.previewH), Position = UDim2.fromOffset(layout.pad, layout.header), BackgroundColor3 = K.row, BorderSizePixel = 0, ClipsDescendants = true }, frame)
	Ui.corner(picture, 10)
	Ui.label(frame, "", UDim2.fromOffset(layout.leftW, 18), { Name = "SelName", Position = UDim2.fromOffset(layout.pad, layout.infoY), Font = Theme.HeadingFont, TextSize = 15, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.label(frame, "", UDim2.fromOffset(layout.leftW, 16), { Name = "SelInfo", Position = UDim2.fromOffset(layout.pad, layout.infoY + 20), TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local action = CardKit.bigButton(frame, { name = "Action", text = "…", kind = "shut", height = layout.button, textSize = 15, onClick = act })
	action.Size = UDim2.fromOffset(layout.leftW, layout.button)
	action.Position = UDim2.fromOffset(layout.pad, layout.buttonY)
	-- the right: the tabs, the swatches (a grid that scrolls)
	drawTabs(frame, layout)
	local rows = rowsOf(state)
	local lines = math.ceil(#rows / layout.cols)
	local tall = lines * (layout.tileH + layout.gap) - layout.gap
	local scrolls = tall > layout.gridH
	local gridFrame = Ui.make("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.fromOffset(layout.gridW, layout.gridH),
		Position = UDim2.fromOffset(layout.gridX, layout.gridY),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if scrolls then SCROLLBAR else 0,
		ScrollBarImageColor3 = K.line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, math.max(0, tall)),
		CanvasPosition = Vector2.new(0, math.clamp(scroll.Y, 0, math.max(0, tall - layout.gridH))),
		SelectionGroup = false,
	}, frame)
	for index, row in rows do
		drawTile(gridFrame, row, index, layout)
	end
	restyle()
	showPicture()
	local target = (if heldName then frame:FindFirstChild(heldName, true) else nil) or (if selected then gridFrame:FindFirstChild(`Swatch_{selected}`) else nil) or close
	if not keepScroll or heldName then
		Ui.gamepadFocus(target) -- (a redraw while open moves the gamepad only when its selection was inside)
	end
end

local function amount(value: any): number?
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else nil
end

local function setOf(list: any): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if type(list) == "table" then
		for _, id in list do
			if type(id) == "string" and #id <= 32 then
				out[id] = true
			end
		end
	end
	return out
end

local function setState(raw: any)
	local saved = Rules.clean({ owned = setOf(raw.owned), worn = raw.worn })
	local was = current
	current = { owned = saved.owned, worn = saved.worn, money = amount(raw.money) or (if was then was.money else 0), paid = setOf(raw.paid) }
	if opened then
		draw(true)
		restyle() -- (the server's answer to BUY or WEAR, a refusal too: the button is live again)
	end
end

function VanPaintUi.open()
	local was = opened
	opened = true
	shownKey = ""
	if not was then
		local state = current
		pick = if state then table.clone(state.worn) else table.clone(Rules.Default)
		tab = "paint"
		selected = pick.paint
		local onOpen = VanPaintUi.onOpen
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
		VanPaintUi.open()
	elseif kind == "bought" or kind == "worn" then
		local item = Rules.find(message.id)
		if item then
			toast(if kind == "bought" then `{item.name} is yours: on your van now.` else `On your van now: {item.name}.`)
		end
	end
end

-- The money from the player's State (a sale, the stands' income): the buttons follow it while open.
local function onMoney(state: any)
	local money = if type(state) == "table" then amount(state.money) else nil
	local now = current
	if money and now and money ~= now.money then
		current = { owned = now.owned, worn = now.worn, money = money, paid = now.paid }
		if opened then
			draw(true)
		end
	end
end

local function sandboxOn(): boolean
	local sandbox = (Config :: any).Sandbox
	return type(sandbox) == "table" and sandbox.On == true
end

function VanPaintUi.start()
	if started or not sandboxOn() then
		return
	end
	started = true
	-- ESC, the gamepad's B and the Roblox menu close it
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) and opened and not UserInputService:GetFocusedTextBox() then
			VanPaintUi.close()
		end
	end)
	GuiService.MenuOpened:Connect(VanPaintUi.close)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if opened then
				draw(true)
			end
		end)
	end
	task.spawn(function()
		local ok, found = pcall(Net.get, "VanPaint")
		if not ok then
			warn(`[VanPaintUi] no VanPaint remote: {found}`)
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

return VanPaintUi
