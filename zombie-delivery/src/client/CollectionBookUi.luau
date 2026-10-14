--!strict
-- 8.2 SANDBOX: the collection book (Config.CollectionBook; its rules shared/CollectionBookRules.luau, the server
-- server/CollectionBook.luau). The owner: collectors want to know what they have found and what is still out there.
-- Every piece the sandbox house can hold (the ordinary furniture and the collectibles) has a card: unknown (a dark
-- silhouette, "???") until a move brings one home, then found (its name, its rarity's colour, how many came home, its
-- best condition and its value). The server decides everything; this window only shows it and asks through the
-- "CollectionBook" remote:
--   { kind = "state", book, paid, new }       kept (CollectionBookUi.state); an open book is drawn again only when what
--                                             it shows changed (its scroll kept); `new` pieces: a toast "📖 New in your
--                                             book: Jukebox" (several: "📖 3 new pieces in your book")
--   { kind = "milestone", id, name, money }   a toast "🏆 Found 10 pieces · +$250", the milestone ✔ at once
-- THE BOOK: a modal card "📖 COLLECTION BOOK". At its left the progress ("23 / 56 found", a bar, the furniture's and
-- the collectibles' counts) and the MILESTONES (✔ when paid, else how far: "7 / 10", and the reward); at its right
-- the tabs ALL / COLLECTIBLES / FURNITURE (each with its found / total) over a scrolling grid of cards in the book's
-- order (#1 …): a found piece's card shows its 3D model (FurnitureLooks.build in a ViewportFrame), an unknown one the
-- same model as a dark silhouette (the ViewportFrame tinted Config.CollectionBook.Silhouette) and "???". Only the cards
-- on screen get a 3D picture, at most Config.CollectionBook.MaxViews at once (client/WarehouseUi.luau's way: each model
-- built once, the oldest of MaxModels go); the others show the piece's emoji or a "?".
-- The HUD's 📖 BOOK chip (client/SandboxHud.luau) and the key Config.CollectionBook.Key (K, not while typing nor on the
-- start screen) open and close it; ✕, ESC, the gamepad's B, the Roblox menu or a tap beside the card close it. It is
-- modal: the mouse is free while it is open (a Modal button), a touch screen's buttons are under it. Opening it closes
-- the warehouse's picker and the UPGRADES window. Toasts wait while the HUD is hidden (the start screen).
--   CollectionBookUi.start()                 listens (once; nothing when Config.Sandbox.On is false)
--   CollectionBookUi.open() / close() / toggle() / isOpen()
--   CollectionBookUi.state()                 { book, paid } the last state (nil: none yet)
--   CollectionBookUi.layout(W, H, touch)     the card on a W × H screen (px under Roblox's top bar)
--   CollectionBookUi.views()                 the 3D pictures alive now
--   CollectionBookUi.notify / onOpen         hooks: the toasts (client/SandboxHud.luau sets it; else client/Hud.luau's),
--                                            the window opened
-- Presentation only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local FurnitureLooks = require(Shared.FurnitureLooks)
local ItemLooks = require(Shared.ItemLooks) -- (the 3/4 camera on a model's box: bounds, frame)
local Rules = require(Shared.CollectionBookRules)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)

local CollectionBookUi = {}

local BOOK = Config.CollectionBook
local WIN = BOOK.Window
local K = Theme.Contract
local C = CardKit.Color

export type Found = { n: number, best: number }
export type State = { book: { [string]: Found }, paid: { [string]: boolean } }
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
	sideX: number, -- the left column: the progress and the milestones
	sideY: number,
	sideW: number,
	sideH: number,
	rowH: number, -- a milestone's row
	tabsY: number, -- the tabs over the grid
	tabsH: number,
	gridX: number,
	gridY: number,
	gridW: number,
	gridH: number,
	cols: number,
	tileW: number,
	tileH: number,
	picture: number,
	gap: number,
}

CollectionBookUi.notify = nil :: ((text: string) -> ())?
CollectionBookUi.onOpen = nil :: (() -> ())?

local HEADER = 52
local SCROLLBAR = 6
local TILE_TEXT = 56 -- a card's height under its picture (unscaled px)
local MILESTONES_Y = 106 -- the first milestone's row in the left column
local CARD_CORNER = Config.UiKit.RowCorner
local TABS = { { id = "all", name = "ALL" }, { id = "collectibles", name = "COLLECTIBLES" }, { id = "furniture", name = "FURNITURE" } }
local UNKNOWN_FACE = K.track -- an unknown piece's picture: its silhouette on it
local SILHOUETTE = Color3.fromRGB(BOOK.Silhouette[1], BOOK.Silhouette[2], BOOK.Silhouette[3])

local started = false
local remote: RemoteEvent? = nil
local current: State? = nil
local gui: any = nil
local opened = false
local filter = "all"
local shownKey = ""
local card: any = nil -- the shade over the screen (the window: card's Book)
local grid: any = nil
local plan: Layout? = nil
local waiting: { string } = {} -- toasts while the HUD is hidden

type Card = { item: string, found: boolean, index: number, picture: any, mark: any, view: any }
local cards: { Card } = {}
local liveViews = 0
local refreshQueued = false

-- ── The pieces ──────────────────────────────────────────────────────────────

local function defOf(item: string): any
	return (FurnitureLooks.Items :: any)[item]
end

local function nameOf(item: string): string
	local def = defOf(item)
	return if def and type(def.name) == "string" then def.name else item
end

local function emojiOf(item: string): string
	local def = defOf(item)
	return if def and type(def.icon) == "string" then def.icon else "📦"
end

local function tierOf(item: string): any
	local tiers = Config.Collection.Tiers
	return tiers[Rules.rarityOf(item)] or tiers.common
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function listFor(id: string): { string }
	return if id == "collectibles" then Rules.Collectibles elseif id == "furniture" then Rules.Furniture else Rules.Pieces
end

-- ── Toasts ──────────────────────────────────────────────────────────────────

local function hudHidden(): boolean
	local playerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = if playerGui then playerGui:FindFirstChild("SandboxHud") else nil
	return hud ~= nil and hud:IsA("ScreenGui") and (hud :: ScreenGui).Enabled == false
end

local function show(text: string)
	local notify = CollectionBookUi.notify
	if notify then
		notify(text)
		return
	end
	pcall(function()
		require(script.Parent.Hud).toast(text)
	end)
end

local function toast(text: string)
	if hudHidden() then
		table.insert(waiting, text)
		while #waiting > 4 do
			table.remove(waiting, 1)
		end
		return
	end
	show(text)
end

local function flushToasts()
	if hudHidden() then
		return
	end
	local list = waiting
	waiting = {}
	for _, text in list do
		show(text)
	end
end

-- ── The layout (pure) ───────────────────────────────────────────────────────

function CollectionBookUi.layout(W: number, H: number, touch: boolean): Layout
	local margin = if touch then WIN.TouchMargin else WIN.Margin
	local scale = if touch
		then math.clamp(math.min(W / 860, H / 380), 0.8, Ui.MaxScale)
		else math.max(Ui.scaleFor(Vector2.new(W, H)), 0.7)
	local w = math.floor(math.min(WIN.Width, (W - 2 * margin) / scale))
	local h = math.floor(math.min(WIN.Height, (H - 2 * margin) / scale))
	local pad = if touch then 10 else 16
	local finger = math.ceil(Ui.MinTouch / scale)
	local sideW = math.min(if touch then WIN.SideTouch else WIN.Side, math.floor(w * 0.34))
	local sideH = h - HEADER - pad
	local count = #Rules.Milestones
	local rowH = math.clamp(math.floor((sideH - MILESTONES_Y - 4 * (count - 1)) / math.max(1, count)), 28, 40)
	local gap = WIN.Gap
	local gridX = pad + sideW + 12
	local gridW = w - gridX - pad
	local tabsH = if touch then finger else 30
	local gridY = HEADER + tabsH + 8
	local area = gridW - SCROLLBAR - 2
	local least = if touch then WIN.TileTouch else WIN.Tile
	local cols = math.max(1, math.floor((area + gap) / (least + gap)))
	local tileW = math.floor((area - (cols - 1) * gap) / cols)
	local picture = math.floor(tileW * (if touch then WIN.PictureTouch else WIN.Picture))
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
		sideX = pad,
		sideY = HEADER,
		sideW = sideW,
		sideH = sideH,
		rowH = rowH,
		tabsY = HEADER,
		tabsH = tabsH,
		gridX = gridX,
		gridY = gridY,
		gridW = gridW,
		gridH = h - gridY - pad,
		cols = cols,
		tileW = tileW,
		tileH = 4 + picture + TILE_TEXT,
		picture = picture,
		gap = gap,
	}
end

-- The cards (1-based, in order) a grid scrolled to `top` shows: the first and the last (partly shown counts).
local function visibleRange(layout: Layout, top: number): (number, number)
	local rowH = layout.tileH + layout.gap
	local first = math.max(0, math.floor(top / rowH))
	local last = math.max(first, math.floor((top + layout.gridH - 1) / rowH))
	return first * layout.cols + 1, (last + 1) * layout.cols
end

-- ── The 3D pictures ─────────────────────────────────────────────────────────

local models: { [string]: any } = {} -- a model a piece (false: its build failed)
local modelOrder: { string } = {}
local INERT = { "SurfaceGui", "BillboardGui", "Smoke", "ParticleEmitter", "Fire", "Sparkles", "Light", "Sound", "Attachment", "WeldConstraint", "Constraint", "JointInstance", "BaseScript", "ProximityPrompt" }

local function template(item: string): any
	local known = models[item]
	if known ~= nil then
		return if known == false then nil else known
	end
	local ok, made = pcall(FurnitureLooks.build, item, 1)
	if not ok or not made then
		warn(`[CollectionBookUi] {item}: {made}`)
		models[item] = false
		return nil
	end
	local model: any = made
	for _, obj in model:GetDescendants() do
		for _, class in INERT do
			if obj:IsA(class) then
				obj:Destroy()
				break
			end
		end
	end
	models[item] = model
	table.insert(modelOrder, item)
	while #modelOrder > BOOK.MaxModels do
		local oldest = table.remove(modelOrder, 1) :: string
		local gone = models[oldest]
		models[oldest] = nil
		if gone then
			gone:Destroy()
		end
	end
	return model
end

local function vec(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function mount(entry: Card)
	local model = template(entry.item)
	if not model then
		return
	end
	local look = Config.ItemModel
	local view = Ui.make("ViewportFrame", {
		Name = "Model",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = rgb(look.Ambient),
		LightColor = rgb(look.LightColor),
		LightDirection = vec(look.LightDirection),
		ImageColor3 = if entry.found then Color3.new(1, 1, 1) else SILHOUETTE, -- (an unknown piece: its silhouette)
		ZIndex = 2,
	}, entry.picture)
	view:SetAttribute("Emoji", emojiOf(entry.item))
	view:SetAttribute("Silhouette", not entry.found)
	local copy = model:Clone()
	copy.Parent = view
	local lo, hi = ItemLooks.bounds(copy)
	local size = entry.picture.Size
	local eye, centre = ItemLooks.frame(lo, hi, math.max(0.2, size.X.Offset / math.max(1, size.Y.Offset)), false)
	local camera = Ui.make("Camera", { FieldOfView = look.Fov }, view)
	camera.CFrame = CFrame.lookAt(vec(eye), vec(centre))
	view.CurrentCamera = camera
	entry.view = view
	entry.mark.Visible = false
	liveViews += 1
end

local function unmount(entry: Card)
	if entry.view then
		entry.view:Destroy()
		entry.view = nil
		entry.mark.Visible = true
		liveViews -= 1
	end
end

-- The cards on screen get their 3D picture (at most MaxViews at once), the others give theirs back.
local function refreshViews()
	local layout = plan
	if not (layout and grid) then
		return
	end
	local first, last = visibleRange(layout, grid.CanvasPosition.Y)
	for _, entry in cards do
		if entry.index < first or entry.index > last then
			unmount(entry)
		end
	end
	for _, entry in cards do
		if liveViews >= BOOK.MaxViews then
			break
		end
		if entry.index >= first and entry.index <= last and not entry.view then
			mount(entry)
		end
	end
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(0.1, function()
		refreshQueued = false
		refreshViews()
	end)
end

function CollectionBookUi.views(): number
	return liveViews
end

-- ── The window ──────────────────────────────────────────────────────────────

local draw: (keepScroll: boolean) -> ()

local function ensureGui(): any
	if gui then
		return gui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.make("ScreenGui", {
		Name = "CollectionBookUi",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7, -- (with the warehouse's picker: over the HUD and the touch buttons)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	return gui
end

local function clearCards()
	for _, entry in cards do
		unmount(entry)
	end
	table.clear(cards)
end

function CollectionBookUi.close()
	if not opened then
		return
	end
	opened = false
	clearCards()
	if card then
		Ui.gamepadRelease(gui)
		card:Destroy()
		card = nil
	end
	grid, plan = nil, nil
	shownKey = ""
end

function CollectionBookUi.isOpen(): boolean
	return opened
end

function CollectionBookUi.state(): State?
	return current
end

local function stateKey(state: State, layout: Layout): string
	local parts = { `{layout.w}x{layout.h}@{layout.scale}`, filter, if current then "on" else "loading" }
	for _, item in Rules.Pieces do
		local found = state.book[item]
		if found then
			table.insert(parts, `{item}:{found.n}:{found.best}`)
		end
	end
	for _, milestone in Rules.Milestones do
		table.insert(parts, if state.paid[milestone.id] then milestone.id else "-")
	end
	return table.concat(parts, "|")
end

local function percent(best: number): string
	return `{math.floor(math.clamp(best, 0, 1) * 100 + 0.5)}%`
end

-- The left column: the progress, the counts, the milestones (✔ paid, else how far) and a hint where there is room.
local function drawSide(frame: any, layout: Layout, state: State)
	local side = Ui.make("Frame", {
		Name = "Side",
		Size = UDim2.fromOffset(layout.sideW, layout.sideH),
		Position = UDim2.fromOffset(layout.sideX, layout.sideY),
		BackgroundTransparency = 1,
	}, frame)
	local w = layout.sideW
	local counts = Rules.counts(state.book)
	local left = Enum.TextXAlignment.Left
	Ui.label(side, `{counts.found} / {counts.total} found`, UDim2.fromOffset(w, 26), { Name = "Progress", Font = Theme.DisplayFont, TextSize = 22, TextColor3 = K.text, TextWrapped = false, TextXAlignment = left })
	local track = Ui.make("Frame", { Name = "ProgressBar", Size = UDim2.fromOffset(w, 8), Position = UDim2.fromOffset(0, 32), BackgroundColor3 = K.track, BorderSizePixel = 0 }, side)
	Ui.corner(track, 4)
	local share = counts.found / math.max(1, counts.total)
	local fill = Ui.make("Frame", { Name = "Fill", Size = UDim2.new(share, 0, 1, 0), BackgroundColor3 = C.gold, BorderSizePixel = 0, Visible = share > 0 }, track)
	Ui.corner(fill, 4)
	Ui.label(side, `Furniture {counts.furniture} / {counts.furnitureTotal}`, UDim2.fromOffset(w, 15), { Name = "FurnitureCount", Position = UDim2.fromOffset(0, 48), Font = Theme.Font, TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextXAlignment = left })
	Ui.label(side, `Collectibles {counts.collectibles} / {counts.collectiblesTotal}`, UDim2.fromOffset(w, 15), { Name = "CollectibleCount", Position = UDim2.fromOffset(0, 64), Font = Theme.Font, TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextXAlignment = left })
	Ui.label(side, "MILESTONES", UDim2.fromOffset(w, 14), { Name = "MilestonesTitle", Position = UDim2.fromOffset(0, 88), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = C.faint, TextWrapped = false, TextXAlignment = left })
	local y = MILESTONES_Y
	local rowH = layout.rowH
	for _, milestone in Rules.Milestones do
		local paid = state.paid[milestone.id] == true
		local have, need = Rules.progress(state.book, milestone)
		local row = Ui.make("Frame", {
			Name = `Milestone_{milestone.id}`,
			Size = UDim2.fromOffset(w, rowH),
			Position = UDim2.fromOffset(0, y),
			BackgroundColor3 = if paid then C.goodFace else K.row,
			BorderSizePixel = 0,
		}, side)
		row:SetAttribute("Paid", paid)
		Ui.corner(row, 8)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if paid then K.good else K.line, Thickness = 1, Transparency = if paid then 0.5 else 0.85 }, row)
		Ui.label(row, if paid then "✔" else "○", UDim2.fromOffset(20, rowH), { Name = "Check", Position = UDim2.fromOffset(6, 0), Font = Theme.HeadingFont, TextSize = 15, TextColor3 = if paid then K.good else C.faint, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
		local middle = math.floor(rowH / 2)
		local reward = Ui.money(milestone.reward)
		Ui.label(row, milestone.name, UDim2.fromOffset(w - 34, 15), { Name = "MilestoneName", Position = UDim2.fromOffset(28, middle - 15), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = left })
		Ui.label(row, if paid then `Paid · +{reward}` else `{have} / {need} · +{reward}`, UDim2.fromOffset(w - 34, 13), { Name = "Reward", Position = UDim2.fromOffset(28, middle + 1), Font = Theme.Font, TextSize = 11, TextColor3 = if paid then K.good else K.secondary, TextWrapped = false, TextXAlignment = left })
		y += rowH + 4
	end
	if layout.sideH - y >= 48 then
		Ui.label(side, "Every piece a move brings home goes into your book. The milestones pay once.", UDim2.fromOffset(w, 40), { Name = "Hint", Position = UDim2.fromOffset(0, y + 6), Font = Theme.Font, TextSize = 11, TextColor3 = C.faint, TextWrapped = true, TextXAlignment = left, TextYAlignment = Enum.TextYAlignment.Top })
	end
end

-- The tabs ALL / COLLECTIBLES / FURNITURE over the grid (each its found / total), the open one lit.
local function drawTabs(frame: any, layout: Layout, state: State): any
	local x = layout.gridX
	local lit: any = nil
	for _, tab in TABS do
		local id = tab.id
		local list = listFor(id)
		local found = 0
		for _, item in list do
			if state.book[item] then
				found += 1
			end
		end
		local on = id == filter
		local chip = CardKit.chip(frame, {
			name = `Tab_{id}`,
			text = `{tab.name} {found}/{#list}`,
			face = if on then K.raised else K.row,
			ink = if on then K.text else K.secondary,
			stroke = if on then C.gold else K.line,
			lit = on,
			faint = 0.8,
			onClick = function()
				if filter ~= id then
					filter = id
					draw(false)
				end
			end,
		})
		local size = if layout.touch then 13 else 12
		chip.TextSize = size
		local chipW = math.ceil(CardKit.width(chip.Text, size, Theme.HeadingFont) + 22)
		chip.Size = UDim2.fromOffset(if layout.touch then math.max(chipW, layout.tabsH) else chipW, layout.tabsH)
		chip.Position = UDim2.fromOffset(x, layout.tabsY)
		if on then
			Ui.make("Frame", { Name = "Underline", Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 1, -2), BackgroundColor3 = C.gold, BorderSizePixel = 0 }, chip)
			lit = chip
		end
		x += chip.Size.X.Offset + 6
	end
	return lit
end

local function drawCard(parent: any, item: string, index: number, layout: Layout, found: Found?)
	local col, line = (index - 1) % layout.cols, (index - 1) // layout.cols
	local tier = tierOf(item)
	local accent = rgb(tier.color)
	local w = layout.tileW
	local frame = Ui.make("Frame", {
		Name = `Card_{item}`,
		Size = UDim2.fromOffset(w, layout.tileH),
		Position = UDim2.fromOffset(col * (w + layout.gap), line * (layout.tileH + layout.gap)),
		BackgroundColor3 = if found then K.row else K.recessed,
		BorderSizePixel = 0,
	}, parent)
	frame:SetAttribute("Item", item)
	frame:SetAttribute("Found", found ~= nil)
	Ui.corner(frame, CARD_CORNER)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if found then accent else K.line, Thickness = 1, Transparency = if not found then 0.85 elseif tier.rank <= 1 then 0.75 else 0.4 }, frame)
	local picture = Ui.make("Frame", {
		Name = "Picture",
		Size = UDim2.fromOffset(w - 8, layout.picture),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = if found then K.charcoal else UNKNOWN_FACE,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, frame)
	Ui.corner(picture, 6)
	local mark = Ui.label(picture, if found then emojiOf(item) else "?", UDim2.fromScale(1, 1), {
		Name = if found then "Emoji" else "Unknown",
		Font = Theme.HeadingFont,
		TextSize = math.floor(layout.picture * (if found then 0.5 else 0.42)),
		TextColor3 = if found then K.text else SILHOUETTE,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 1,
	})
	Ui.label(picture, `#{Rules.number(item) or index}`, UDim2.fromOffset(40, 14), { Name = "Number", Position = UDim2.fromOffset(5, 3), Font = Theme.HeadingFont, TextSize = 10, TextColor3 = if found then C.faint else K.secondary, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	local inner = w - 16
	local y = 4 + layout.picture + 6
	local left, right = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
	if found then
		Ui.make("Frame", { Name = "RarityBar", Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -3), BackgroundColor3 = accent, BorderSizePixel = 0, ZIndex = 3 }, picture)
		Ui.label(frame, nameOf(item), UDim2.fromOffset(inner, 16), { Name = "PieceName", Position = UDim2.fromOffset(8, y), Font = Theme.HeadingFont, TextSize = 13, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = left })
		y += 17
		local count = if found.n > 999 then "×999+" else `×{found.n}`
		local countW = math.ceil(CardKit.width(count, 11, Theme.HeadingFont))
		Ui.label(frame, string.upper(tier.name), UDim2.fromOffset(inner - countW - 4, 13), { Name = "Rarity", Position = UDim2.fromOffset(8, y), Font = Theme.HeadingFont, TextSize = 10, TextColor3 = accent, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = left })
		Ui.label(frame, count, UDim2.fromOffset(countW, 13), { Name = "Count", Position = UDim2.new(1, -8, 0, y), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = K.secondary, TextWrapped = false, TextXAlignment = right })
		y += 16
		local value = Ui.money(Rules.valueOf(item))
		local valueW = math.ceil(CardKit.width(value, 12, Theme.HeadingFont))
		Ui.label(frame, `Best {percent(found.best)}`, UDim2.fromOffset(inner - valueW - 4, 14), { Name = "Best", Position = UDim2.fromOffset(8, y), Font = Theme.Font, TextSize = 11, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = left })
		Ui.label(frame, value, UDim2.fromOffset(valueW, 14), { Name = "Value", Position = UDim2.new(1, -8, 0, y), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = C.money, TextWrapped = false, TextXAlignment = right })
	else
		Ui.label(frame, "???", UDim2.fromOffset(inner, 16), { Name = "PieceName", Position = UDim2.fromOffset(8, y), Font = Theme.HeadingFont, TextSize = 13, TextColor3 = C.faint, TextWrapped = false, TextXAlignment = left })
		y += 17
		Ui.label(frame, "NOT FOUND YET", UDim2.fromOffset(inner, 13), { Name = "Hint", Position = UDim2.fromOffset(8, y), Font = Theme.HeadingFont, TextSize = 10, TextColor3 = C.dim, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = left })
	end
	table.insert(cards, { item = item, found = found ~= nil, index = index, picture = picture, mark = mark, view = nil })
end

draw = function(keepScroll: boolean)
	if not opened then
		return
	end
	local size = Ui.screenSize()
	local layout = CollectionBookUi.layout(size.X, size.Y, Ui.touchLayout())
	local state: State = current or { book = {}, paid = {} }
	local key = stateKey(state, layout)
	if card and key == shownKey then
		return -- (nothing it shows changed: no redraw, the scroll and the pictures stay)
	end
	shownKey = key
	local scroll = if keepScroll and grid then grid.CanvasPosition else Vector2.zero
	clearCards()
	if card then
		card:Destroy()
	end
	local root = ensureGui()
	plan = layout
	-- a shade over the world (the touch buttons too): a tap beside the card closes it; Modal frees the mouse
	card = Ui.make("TextButton", {
		Name = "BookShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Modal = true,
	}, root)
	card.Activated:Connect(CollectionBookUi.close)
	local frame = Ui.make("Frame", {
		Name = "Book",
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
	-- the header: the title, a line under it, the ✕
	local titleW = layout.w - (layout.pad * 2 + layout.close + 8)
	Ui.label(frame, "📖 COLLECTION BOOK", UDim2.fromOffset(titleW, 24), { Name = "Title", Position = UDim2.fromOffset(layout.pad, 10), Font = Theme.HeadingFont, TextSize = 18, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local subtitle = if not current then "Loading your book…" else "What your moves brought home, and what is still out there."
	Ui.label(frame, subtitle, UDim2.fromOffset(titleW, 16), { Name = "Subtitle", Position = UDim2.fromOffset(layout.pad, 33), Font = Theme.Font, TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local close = Ui.closeButton(frame, CollectionBookUi.close)
	close.Size = UDim2.fromOffset(layout.close, layout.close)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.AnchorPoint = Vector2.new(1, 0)
	drawSide(frame, layout, state)
	local lit = drawTabs(frame, layout, state)
	-- the cards, in the book's order
	local list = listFor(filter)
	local lines = math.ceil(#list / layout.cols)
	local height = math.max(0, lines * (layout.tileH + layout.gap) - layout.gap)
	grid = Ui.make("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.fromOffset(layout.gridW, layout.gridH),
		Position = UDim2.fromOffset(layout.gridX, layout.gridY),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = SCROLLBAR,
		ScrollBarImageColor3 = K.line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, height),
		CanvasPosition = Vector2.new(0, math.clamp(scroll.Y, 0, math.max(0, height - layout.gridH))),
	}, frame)
	for index, item in list do
		drawCard(grid, item, index, layout, state.book[item])
	end
	grid:GetPropertyChangedSignal("CanvasPosition"):Connect(queueRefresh)
	refreshViews()
	Ui.gamepadFocus(lit or close)
end

-- The window over everything: the warehouse's picker and the UPGRADES window close (one window at a time).
function CollectionBookUi.open()
	pcall(function()
		local other = require(script.Parent.WarehouseUi)
		if other.isOpen() then
			other.close()
		end
	end)
	pcall(function()
		local other = require(script.Parent.UpgradeUi)
		if other.isOpen() then
			other.close()
		end
	end)
	local was = opened
	opened = true
	shownKey = ""
	if not was then
		local onOpen = CollectionBookUi.onOpen
		if onOpen then
			onOpen()
		end
	end
	draw(false)
	local target = remote
	if not current and target then
		target:FireServer({ kind = "state" })
	end
end

function CollectionBookUi.toggle()
	if opened then
		CollectionBookUi.close()
	else
		CollectionBookUi.open()
	end
end

-- ── The remote ──────────────────────────────────────────────────────────────

local function setState(raw: any)
	local book: { [string]: Found } = {}
	if type(raw.book) == "table" then
		for _, item in Rules.Pieces do
			local found = raw.book[item]
			if type(found) == "table" and type(found.n) == "number" and found.n >= 1 and type(found.best) == "number" then
				book[item] = { n = math.floor(found.n), best = math.clamp(found.best, 0, 1) }
			end
		end
	end
	local paid: { [string]: boolean } = {}
	if type(raw.paid) == "table" then
		for _, milestone in Rules.Milestones do
			if table.find(raw.paid, milestone.id) then
				paid[milestone.id] = true
			end
		end
	end
	current = { book = book, paid = paid }
	local new: { string } = {}
	if type(raw.new) == "table" then
		for _, item in raw.new do
			if book[item] and not table.find(new, item) then
				table.insert(new, item)
			end
		end
	end
	if #new == 1 then
		toast(`📖 New in your book: {nameOf(new[1])}`)
	elseif #new > 1 then
		toast(`📖 {#new} new pieces in your book`)
	end
	if opened then
		draw(true)
	end
end

local function onEvent(message: any)
	if type(message) ~= "table" then
		return
	end
	if message.kind == "state" then
		setState(message)
	elseif message.kind == "milestone" then
		local milestone = Rules.milestone(message.id)
		if not milestone then
			return
		end
		local state = current
		if state then
			state.paid[milestone.id] = true -- (the ✔ at once: the next state says so too)
		end
		local money = if type(message.money) == "number" and message.money == message.money then message.money else milestone.reward
		toast(`🏆 {milestone.name} · +{Ui.money(money)}`)
		if opened then
			draw(true)
		end
	end
end

local function sandboxOn(): boolean
	local sandbox = (Config :: any).Sandbox
	return type(sandbox) == "table" and sandbox.On == true
end

function CollectionBookUi.start()
	if started or not sandboxOn() then
		return
	end
	started = true
	local ok, found = pcall(function(): any
		return (Enum.KeyCode :: any)[BOOK.Key]
	end)
	local bookKey: any = if ok then found else nil
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			CollectionBookUi.close()
		elseif bookKey and input.KeyCode == bookKey and not processed and not hudHidden() then
			CollectionBookUi.toggle()
		end
	end)
	GuiService.MenuOpened:Connect(CollectionBookUi.close)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if opened then
				draw(true)
			end
		end)
	end
	-- the toasts that waited for the HUD (the start screen) come when it shows
	task.spawn(function()
		local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("SandboxHud", 30)
		if hud and hud:IsA("ScreenGui") then
			hud:GetPropertyChangedSignal("Enabled"):Connect(flushToasts)
		end
	end)
	task.spawn(function()
		local okRemote, made = pcall(Net.get, "CollectionBook")
		if not okRemote then
			warn(`[CollectionBookUi] no CollectionBook remote: {made}`)
			return
		end
		remote = made
		made.OnClientEvent:Connect(onEvent)
		made:FireServer({ kind = "state" })
	end)
end

return CollectionBookUi
