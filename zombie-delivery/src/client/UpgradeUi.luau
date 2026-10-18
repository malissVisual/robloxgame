--!strict
-- 8.1 SANDBOX: the UPGRADES desk's window (the owner: "the money players earn needs something to buy"). The desk in
-- your warehouse (server/Warehouse.luau) opens it through the "Upgrades" remote; server/Upgrades.luau decides every
-- purchase, this window only shows the tree and asks:
--   { kind = "state", levels, money }   kept; an open window is drawn again only when what it shows changed
--   { kind = "open" }                   the desk's prompt: THE WINDOW
--   { kind = "bought", id, level }      a toast "Hall spotlights: rank 2 · Income ×1.21" (UpgradeUi.notify, else
--                                       client/Hud.luau's toast; the trunk: "Deliveros Warehouse: tier 2 · Workshop ·
--                                       4 stands")
-- 10.4 THE UPGRADE TREE (the owner: "not a skill tree, but an upgrade tree … well thought-out"; shared/UpgradeRules.luau,
-- Config.SandboxUpgrades): a full-screen window in the contract look (client/Theme.luau), "⬆ DELIVEROS UPGRADES" with
-- your money and the branches' legend over two parts:
--   * THE TREE (a ScrollingFrame both ways: drag it, a phone's finger too; − / + zoom it, Config's Window.Zooms): the
--     trunk across its middle row, the warehouse's tiers 1 … 5 (Garage … Logistics Center, each its tile "Tier_n": its
--     building, its stands, OWNED or its price), and the branches in their lanes (each lane's name at its left, in its
--     colour): LOOKS over the HALL over the trunk, the SHOWROOM, RUNS and the CREW under it. A node ("Node_<id>") shows
--     its icon, its name, what its next rank gives (or, at its top, what it gives), its cost (or MAX, 🔒, SOON) and its
--     ranks' pips; its edge says its state: gold MAX, green (the money buys it), its branch's colour (it could be bought:
--     the money is missing), grey (locked: its parents or its tier; SOON). Lines join a node to its parents (its branch's
--     colour, faint until the parent has the rank it needs) or, a branch's first node, to the trunk's tier it needs.
--   * THE DETAILS (the selected node; at the right): its icon and name, its branch, "RANK 2/5" and its pips, what it
--     does (its blurb), NOW and NEXT, the next rank's checklist (✓ / ✗: its parents, its tier), its price and BUY (green
--     with the money; grey "NEED $X" without, a tap only says so; "🔒 <why>" locked, a tap says it; a gold MAX; SOON).
-- A tap (a click, the gamepad's A) on a node selects it; BUY sends { kind = "buy", id, level } (the rank it offers: a
-- second tap buys once). Your money follows the State remote (a sale, the hall's income): the details' NEED follow it in
-- place, the tree is drawn again only when a node's state changes. ✕, ESC, the gamepad's B, the Roblox menu or a tap on
-- the shade close it; modal: the mouse is free while it is open (a Modal button), a touch screen's buttons are under it.
--   UpgradeUi.start()                  listens (once; nothing when Config.Sandbox.On is false)
--   UpgradeUi.open() / close() / isOpen()
--   UpgradeUi.state()                  { levels, money } the last state (nil: none yet)
--   UpgradeUi.select(id) / selected()  the details' node (an unknown id: nothing)
--   UpgradeUi.zoom(step?)              the tree's zoom step (1 … #Window.Zooms; nil: the step now) → the zoom
--   UpgradeUi.layout(W, H, touch)      the window on a W × H screen (px under Roblox's top bar)
--   UpgradeUi.place(at, zoom, layout?) a grid cell's box in the tree's canvas { x, y, w, h } (pure: the tests')
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
local W = Config.SandboxUpgrades.Window

export type State = { levels: { [string]: number }, money: number }
export type Layout = {
	touch: boolean,
	scale: number, -- the window's UIScale
	x: number, -- the window's top left on the screen (px)
	y: number,
	w: number, -- the window's size (unscaled)
	h: number,
	pad: number,
	header: number,
	close: number, -- the ✕'s side
	button: number, -- a button's height (BUY, − / +)
	treeX: number, -- the tree's view in the window
	treeY: number,
	treeW: number,
	treeH: number,
	panelX: number, -- the details
	panelW: number,
	zoom: number, -- the zoom step a fresh window starts at
}
export type Box = { x: number, y: number, w: number, h: number }

UpgradeUi.notify = nil :: ((text: string) -> ())?
UpgradeUi.onOpen = nil :: (() -> ())?

local LANE = 112 -- the lanes' names' column (unscaled, at zoom 1)
local SCROLLBAR = 6

local started = false
local remote: RemoteEvent? = nil
local current: State? = nil
local gui: any = nil
local opened = false
local shownKey = ""
local card: any = nil -- the shade over the screen (the window: card's Upgrades)
local sentAt: { [string]: number } = {}
local chosen: string? = nil -- the details' node
local step: number? = nil -- the zoom step (nil: the layout's)
local dragging: { at: Vector2, from: Vector2 }? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function branchColor(id: string): Color3
	local b = UpgradeRules.branch(id)
	return if b then rgb(b.color) else K.line
end

-- ── The layout (pure) ───────────────────────────────────────────────────────

function UpgradeUi.layout(width: number, height: number, touch: boolean): Layout
	local margin = if touch then 6 else 16
	local scale = if touch
		then math.clamp(math.min(width / 860, height / 380), W.TouchScale, Ui.MaxScale)
		else math.max(Ui.scaleFor(Vector2.new(width, height)), 0.7)
	local finger = math.ceil(Ui.MinTouch / scale)
	local pad = if touch then 8 else 14
	local button = if touch then math.max(40, finger) else 36
	local header = if touch then math.max(W.Header - 8, button + 8) else W.Header
	local w = math.floor((width - 2 * margin) / scale)
	local h = math.floor((height - 2 * margin) / scale)
	local panelW = if touch then math.min(W.Panel - 60, math.floor(w * 0.34)) else math.min(W.Panel, math.floor(w * 0.3))
	local treeW = w - panelW - 3 * pad
	local zooms = W.Zooms :: { number }
	-- (a fresh window: the closest zoom step whose tree is as wide as the view, never under DefaultZoom's: the words
	-- stay readable, the tree scrolls)
	local fit = 1
	local full = UpgradeUi.canvasSize(1)
	for n, z in zooms do
		if full.X * z <= treeW then
			fit = n
		end
	end
	fit = math.clamp(math.max(fit, W.DefaultZoom), 1, #zooms)
	return {
		touch = touch,
		scale = scale,
		x = math.floor((width - w * scale) / 2),
		y = math.floor((height - h * scale) / 2),
		w = w,
		h = h,
		pad = pad,
		header = header,
		close = if touch then math.max(40, finger) else 40,
		button = button,
		treeX = pad,
		treeY = header,
		treeW = treeW,
		treeH = h - header - pad,
		panelX = pad + treeW + pad,
		panelW = panelW,
		zoom = fit,
	}
end

-- The grid's cell `at` = { column, row } in the canvas at zoom z: its node's box. A column is half a node and its gap
-- wide (the nodes on the even columns, the trunk's tiers on the odd ones between them: a tier's line down to a branch
-- runs in the gap between two nodes).
function UpgradeUi.place(at: { number }, zoom: number): Box
	local nodeW, nodeH = W.Node[1] * zoom, W.Node[2] * zoom
	local gx, gy = W.Gap[1] * zoom, W.Gap[2] * zoom
	return {
		x = W.Pad * zoom + LANE * zoom + (at[1] - 1) * (nodeW + gx) / 2,
		y = W.Pad * zoom + (at[2] - 1) * (nodeH + gy),
		w = nodeW,
		h = nodeH,
	}
end

-- The canvas's size at zoom z (the grid's columns and rows, the lanes' column, the margins).
function UpgradeUi.canvasSize(zoom: number): Vector2
	local grid = Config.SandboxUpgrades.Grid
	local last = UpgradeUi.place({ grid.Columns, grid.Rows }, zoom)
	return Vector2.new(math.ceil(last.x + last.w + W.Pad * zoom), math.ceil(last.y + last.h + W.Pad * zoom))
end

-- ── Sending, toasts ─────────────────────────────────────────────────────────

-- One request a node at most every 0.6 s (a double tap is one request).
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
	dragging = nil
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

function UpgradeUi.selected(): string?
	return chosen
end

local function rowsNow(): { UpgradeRules.Row }
	local state = current
	return if state then UpgradeRules.rows(state.levels, state.money) else {}
end

local function rowOf(id: string): UpgradeRules.Row?
	for _, row in rowsNow() do
		if row.id == id then
			return row
		end
	end
	return nil
end

-- The node a fresh window shows: the cheapest one the money buys, else the trunk's next tier, else the trunk.
local function firstPick(rows: { UpgradeRules.Row }): string
	local best: UpgradeRules.Row? = nil
	for _, row in rows do
		if row.status == "buy" and row.price and (best == nil or row.price < (best.price :: number)) then
			best = row
		end
	end
	return if best then best.id else "warehouse"
end

function UpgradeUi.select(id: string)
	if not UpgradeRules.def(id) then
		return
	end
	chosen = id
	if opened then
		draw(true)
	end
end

local function zoomOf(layout: Layout): number
	local zooms = W.Zooms :: { number }
	return zooms[math.clamp(step or layout.zoom, 1, #zooms)]
end

function UpgradeUi.zoom(want: number?): number
	local zooms = W.Zooms :: { number }
	if want then
		step = math.clamp(math.floor(want), 1, #zooms)
		if opened then
			draw(true)
		end
	end
	local size = Ui.screenSize()
	return zoomOf(UpgradeUi.layout(size.X, size.Y, Ui.touchLayout()))
end

local function stateKey(state: State?, layout: Layout, zoom: number): string
	local parts = { `{layout.w}x{layout.h}@{layout.scale}:{zoom}:{chosen or "-"}` }
	if state then
		-- (only what changes a node: its rank and its state; the money's line and NEED follow the money in place, so a
		-- payout never rebuilds the window under a tap or a gamepad's selection)
		for _, row in UpgradeRules.rows(state.levels, state.money) do
			table.insert(parts, `{row.id}={row.level}{string.sub(row.status, 1, 1)}`)
		end
	else
		table.insert(parts, "none")
	end
	return table.concat(parts, "|")
end

local function subtitleOf(state: State?): string
	return if state then `Your money {UpgradeRules.money(state.money)} · pick a node for its details` else "Loading your upgrades…"
end

-- What follows the money on an open window without a rebuild: the money's line and the details' NEED.
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
	local panel = frame:FindFirstChild("Details")
	local buy = panel and panel:FindFirstChild("Buy")
	local row = if chosen then rowOf(chosen) else nil
	if buy and row and row.status == "short" then
		buy.Text = `NEED {UpgradeRules.money(row.short)}`
	end
end

-- A line of the tree: one thin bar (a box in the canvas).
local function bar(parent: any, name: string, x0: number, y0: number, x1: number, y1: number, thick: number, color: Color3, lit: boolean)
	local x, y = math.min(x0, x1), math.min(y0, y1)
	local w, h = math.max(thick, math.abs(x1 - x0)), math.max(thick, math.abs(y1 - y0))
	Ui.make("Frame", {
		Name = name,
		Size = UDim2.fromOffset(math.floor(w + 0.5), math.floor(h + 0.5)),
		Position = UDim2.fromOffset(math.floor(x - (if x0 == x1 then thick / 2 else 0) + 0.5), math.floor(y - (if y0 == y1 then thick / 2 else 0) + 0.5)),
		BackgroundColor3 = color,
		BackgroundTransparency = if lit then 0.1 else 0.7,
		BorderSizePixel = 0,
		ZIndex = 1,
	}, parent)
end

-- A node's pips: one a rank, the owned ones lit.
local function pips(parent: any, rank: number, max: number, x: number, y: number, zoom: number, color: Color3)
	if max <= 1 then
		return
	end
	local seg, gap = math.max(4, math.floor(9 * zoom)), math.max(2, math.floor(3 * zoom))
	for n = 1, max do
		local piece = Ui.make("Frame", {
			Name = `Pip{n}`,
			Size = UDim2.fromOffset(seg, math.max(3, math.floor(4 * zoom))),
			Position = UDim2.fromOffset(x + (n - 1) * (seg + gap), y),
			BackgroundColor3 = if n <= rank then color else K.track,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, parent)
		Ui.corner(piece, 2)
	end
end

-- The edge a node's state gives it: gold at the top, green when the money buys it, its branch's colour when it could
-- be bought, grey when locked or not sold yet.
local function edgeOf(row: UpgradeRules.Row): (Color3, number)
	if row.status == "max" then
		return C.gold, 0.1
	elseif row.status == "buy" then
		return C.money, 0.1
	elseif row.status == "short" then
		return branchColor(row.branch), 0.35
	end
	return K.line, 0.75
end

local function costText(row: UpgradeRules.Row): (string, Color3)
	if row.status == "max" then
		return "MAX", C.gold
	elseif row.status == "soon" then
		return "SOON", C.dim
	elseif row.status == "locked" then
		return `🔒 {UpgradeRules.money(row.price or 0)}`, C.dim
	end
	return UpgradeRules.money(row.price or 0), if row.status == "buy" then C.money else K.secondary
end

local function drawNode(canvas: any, row: UpgradeRules.Row, zoom: number)
	local b = UpgradeUi.place(row.at, zoom)
	local edge, edgeT = edgeOf(row)
	local dim = row.status == "locked" or row.status == "soon"
	local node = Ui.make("TextButton", {
		Name = `Node_{row.id}`,
		Size = UDim2.fromOffset(math.floor(b.w), math.floor(b.h)),
		Position = UDim2.fromOffset(math.floor(b.x), math.floor(b.y)),
		BackgroundColor3 = if chosen == row.id then K.raised else K.row,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
	}, canvas)
	node:SetAttribute("Status", row.status)
	Ui.corner(node, math.max(6, math.floor(10 * zoom)))
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if chosen == row.id then K.text else edge, Thickness = if chosen == row.id then 2 else 1.5, Transparency = if chosen == row.id then 0 else edgeT }, node)
	local color = branchColor(row.branch)
	Ui.make("Frame", { Name = "Bar", Size = UDim2.new(0, math.max(3, math.floor(5 * zoom)), 1, -math.floor(14 * zoom)), Position = UDim2.fromOffset(math.floor(4 * zoom), math.floor(7 * zoom)), BackgroundColor3 = color, BackgroundTransparency = if dim then 0.6 else 0, BorderSizePixel = 0, ZIndex = 3 }, node)
	local icon = math.floor(30 * zoom)
	local left = math.floor(14 * zoom)
	Ui.label(node, row.icon, UDim2.fromOffset(icon, icon), { Name = "Icon", Position = UDim2.fromOffset(left, math.floor(8 * zoom)), TextSize = math.floor(24 * zoom), TextTransparency = if dim then 0.5 else 0, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	local textX = left + icon + math.floor(6 * zoom)
	local room = math.floor(b.w - textX - 8 * zoom)
	Ui.label(node, row.name, UDim2.fromOffset(room, math.floor(17 * zoom)), { Name = "NodeName", Position = UDim2.fromOffset(textX, math.floor(9 * zoom)), Font = Theme.HeadingFont, TextSize = math.max(8, math.floor(13 * zoom)), TextColor3 = if dim then K.secondary else K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	local effect = if row.status == "max" then row.now elseif row.next then `→ {row.next}` else row.now
	Ui.label(node, effect, UDim2.fromOffset(math.floor(b.w - left - 8 * zoom), math.floor(15 * zoom)), { Name = "Effect", Position = UDim2.fromOffset(left, math.floor(42 * zoom)), TextSize = math.max(7, math.floor(11 * zoom)), TextColor3 = if dim then C.dim else K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
	local cost, ink = costText(row)
	Ui.label(node, cost, UDim2.fromOffset(math.floor(b.w * 0.5), math.floor(16 * zoom)), { Name = "Cost", Position = UDim2.new(1, -math.floor(8 * zoom), 0, math.floor(b.h - 22 * zoom)), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = math.max(8, math.floor(12 * zoom)), TextColor3 = ink, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	pips(node, row.level, row.max, left, math.floor(b.h - 16 * zoom), zoom, if row.status == "max" then C.gold else color)
	node.Activated:Connect(function()
		UpgradeUi.select(row.id)
	end)
	node.SelectionGained:Connect(function()
		if chosen ~= row.id then
			task.defer(UpgradeUi.select, row.id)
		end
	end)
	return node
end

-- The trunk's tiles: the warehouse's tiers, owned or priced (a tile selects the trunk's node). → the next tier's tile
-- (the top one's once every tier is owned: where a gamepad lands when the trunk is selected).
local function drawTrunk(canvas: any, row: UpgradeRules.Row, zoom: number): any
	local levels = Config.Warehouse.Levels
	local tier = 1 + row.level
	local color = branchColor("warehouse")
	local focus: any = nil
	for n = 1, #levels do
		local b = UpgradeUi.place(UpgradeRules.trunkAt(n), zoom)
		local owned = n <= tier
		local nextOne = n == tier + 1
		local tile = Ui.make("TextButton", {
			Name = `Tier_{n}`,
			Size = UDim2.fromOffset(math.floor(b.w), math.floor(b.h)),
			Position = UDim2.fromOffset(math.floor(b.x), math.floor(b.y)),
			BackgroundColor3 = if chosen == "warehouse" and nextOne then K.raised elseif owned then Color3.fromRGB(46, 34, 20) else K.row,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 2,
		}, canvas)
		tile:SetAttribute("Owned", owned)
		Ui.corner(tile, math.max(6, math.floor(10 * zoom)))
		local edge = if owned then color elseif nextOne and row.status == "buy" then C.money elseif nextOne then color else K.line
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if chosen == "warehouse" and nextOne then K.text else edge, Thickness = if owned or nextOne then 2 else 1, Transparency = if owned or nextOne then 0 else 0.7 }, tile)
		local def = levels[n]
		local left = math.floor(10 * zoom)
		Ui.label(tile, `🏭 TIER {n}`, UDim2.fromOffset(math.floor(b.w - 2 * left), math.floor(14 * zoom)), { Name = "Tier", Position = UDim2.fromOffset(left, math.floor(7 * zoom)), Font = Theme.HeadingFont, TextSize = math.max(7, math.floor(10 * zoom)), TextColor3 = color, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
		Ui.label(tile, def.name, UDim2.fromOffset(math.floor(b.w - 2 * left), math.floor(18 * zoom)), { Name = "NodeName", Position = UDim2.fromOffset(left, math.floor(23 * zoom)), Font = Theme.HeadingFont, TextSize = math.max(8, math.floor(14 * zoom)), TextColor3 = if owned or nextOne then K.text else K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
		local show = (Config.Showroom.Levels[n] or { Stands = 0 }).Stands
		Ui.label(tile, `{def.stands} hall · {show} showroom`, UDim2.fromOffset(math.floor(b.w - 2 * left), math.floor(14 * zoom)), { Name = "Effect", Position = UDim2.fromOffset(left, math.floor(44 * zoom)), TextSize = math.max(7, math.floor(11 * zoom)), TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
		local price = UpgradeRules.price("warehouse", n - 2)
		local text = if owned then "OWNED" elseif price then UpgradeRules.money(price) else ""
		Ui.label(tile, text, UDim2.fromOffset(math.floor(b.w - 2 * left), math.floor(16 * zoom)), { Name = "Cost", Position = UDim2.new(1, -left, 0, math.floor(b.h - 22 * zoom)), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = math.max(8, math.floor(12 * zoom)), TextColor3 = if owned then color elseif nextOne and row.status == "buy" then C.money else K.secondary, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
		tile.Activated:Connect(function()
			UpgradeUi.select("warehouse")
		end)
		if nextOne or (n == #levels and focus == nil) then
			focus = tile
		end
	end
	return focus
end

-- The lines: the trunk's tiers in a row, a branch's first node to the trunk's tier it needs, a node to its parents.
local function drawLines(canvas: any, rows: { UpgradeRules.Row }, levels: { [string]: number }, zoom: number)
	local thick = math.max(2, math.floor(3 * zoom))
	local byId: { [string]: UpgradeRules.Row } = {}
	for _, row in rows do
		byId[row.id] = row
	end
	local tier = UpgradeRules.warehouseLevel(levels)
	local trunk = branchColor("warehouse")
	for n = 1, #Config.Warehouse.Levels - 1 do
		local a, b = UpgradeUi.place(UpgradeRules.trunkAt(n), zoom), UpgradeUi.place(UpgradeRules.trunkAt(n + 1), zoom)
		bar(canvas, `Trunk{n}`, a.x + a.w, a.y + a.h / 2, b.x, b.y + b.h / 2, thick + 2, trunk, n + 1 <= tier)
	end
	for n, link in UpgradeRules.links() do
		local to = byId[link.to]
		if to then
			local b = UpgradeUi.place(to.at, zoom)
			local color = branchColor(to.branch)
			local tx, ty = b.x, b.y + b.h / 2
			if link.from == "warehouse" then
				local t = UpgradeUi.place(UpgradeRules.trunkAt(link.tier), zoom)
				local cx = t.x + t.w / 2
				local edgeY = if ty < t.y then t.y else t.y + t.h
				local lit = tier >= link.tier
				bar(canvas, `Line{n}a`, cx, edgeY, cx, ty, thick, color, lit)
				bar(canvas, `Line{n}b`, cx, ty, tx, ty, thick, color, lit)
			else
				local from = byId[link.from]
				if from then
					local a = UpgradeUi.place(from.at, zoom)
					local ax, ay = a.x + a.w, a.y + a.h / 2
					local lit = from.level >= link.rank
					if math.abs(ay - ty) < 1 then
						bar(canvas, `Line{n}a`, ax, ay, tx, ty, thick, color, lit)
					else
						local mx = tx - W.Gap[1] * zoom / 2
						bar(canvas, `Line{n}a`, ax, ay, mx, ay, thick, color, lit)
						bar(canvas, `Line{n}b`, mx, ay, mx, ty, thick, color, lit)
						bar(canvas, `Line{n}c`, mx, ty, tx, ty, thick, color, lit)
					end
				end
			end
		end
	end
end

-- The lanes' names at the left of their rows.
local function drawLanes(canvas: any, zoom: number)
	for _, branch in UpgradeRules.branches() do
		local b = UpgradeUi.place({ 1, branch.row }, zoom)
		Ui.label(canvas, branch.name, UDim2.fromOffset(math.floor((LANE - 10) * zoom), math.floor(b.h)), {
			Name = `Lane_{branch.id}`,
			Position = UDim2.fromOffset(math.floor(W.Pad * zoom), math.floor(b.y)),
			Font = Theme.HeadingFont,
			TextSize = math.max(7, math.floor(11 * zoom)),
			TextColor3 = rgb(branch.color),
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 2,
		})
	end
end

-- THE DETAILS of the selected node.
local function drawDetails(frame: any, layout: Layout, row: UpgradeRules.Row)
	local w = layout.panelW
	local panel = Ui.make("Frame", {
		Name = "Details",
		Size = UDim2.fromOffset(w, layout.treeH),
		Position = UDim2.fromOffset(layout.panelX, layout.treeY),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
	}, frame)
	Ui.corner(panel, Config.UiKit.RowCorner)
	local color = branchColor(row.branch)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = color, Thickness = 1, Transparency = 0.5 }, panel)
	local pad = if layout.touch then 8 else 12
	local inner = w - 2 * pad
	local y = pad
	local branch = UpgradeRules.branch(row.branch)
	local trunk = row.id == "warehouse"
	Ui.label(panel, row.icon, UDim2.fromOffset(36, 36), { Name = "Icon", Position = UDim2.fromOffset(pad, y), TextSize = 28, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
	Ui.label(panel, row.name, UDim2.fromOffset(inner - 42, 20), { Name = "NodeName", Position = UDim2.fromOffset(pad + 42, y), Font = Theme.HeadingFont, TextSize = 16, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.label(panel, if branch then branch.name else "", UDim2.fromOffset(inner - 42, 14), { Name = "Branch", Position = UDim2.fromOffset(pad + 42, y + 21), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = color, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	y += 42
	local rank = if trunk then `TIER {1 + row.level}/{1 + row.max}` else `RANK {row.level}/{row.max}`
	Ui.label(panel, rank, UDim2.fromOffset(CardKit.width(rank, 11, Theme.HeadingFont) + 4, 14), { Name = "Rank", Position = UDim2.fromOffset(pad, y), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = if row.status == "max" then C.gold else K.secondary, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left })
	pips(panel, if trunk then row.level + 1 else row.level, if trunk then row.max + 1 else row.max, pad + CardKit.width(rank, 11, Theme.HeadingFont) + 10, y + 5, 1, if row.status == "max" then C.gold else color)
	y += 20
	local blurbH = if layout.touch then 42 else 50
	Ui.label(panel, row.blurb, UDim2.fromOffset(inner, blurbH), { Name = "Blurb", Position = UDim2.fromOffset(pad, y), TextSize = if layout.touch then 11 else 12, TextColor3 = K.secondary, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	y += blurbH + 4
	Ui.label(panel, `Now: {row.now}`, UDim2.fromOffset(inner, 16), { Name = "Now", Position = UDim2.fromOffset(pad, y), TextSize = 12, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	y += 17
	local nextText = if row.status == "max" then "Top rank" elseif row.next then `Next: {row.next}` else ""
	Ui.label(panel, nextText, UDim2.fromOffset(inner, 16), { Name = "Next", Position = UDim2.fromOffset(pad, y), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = if row.status == "max" then C.gold elseif row.status == "locked" or row.status == "soon" then C.dim else C.money, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	y += 20
	-- the next rank's checklist: its parents, its tier
	for n, need in row.needs do
		Ui.label(panel, `{if need.ok then "✓" else "✗"} {need.text}`, UDim2.fromOffset(inner, 15), { Name = `Need{n}`, Position = UDim2.fromOffset(pad, y), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = if need.ok then K.good else K.red, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
		y += 16
	end
	-- the price and BUY at the bottom
	local by = layout.treeH - pad - layout.button
	if row.price and row.status ~= "soon" then
		Ui.label(panel, UpgradeRules.money(row.price), UDim2.fromOffset(inner, 24), { Name = "Price", Position = UDim2.fromOffset(pad, by - 28), Font = Theme.DisplayFont, TextSize = 20, TextColor3 = if row.status == "buy" then C.money else K.secondary, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left })
	end
	local button: any
	if row.status == "max" then
		button = Ui.label(panel, "MAX", UDim2.fromOffset(inner, layout.button), { Name = "Max", Position = UDim2.fromOffset(pad, by), BackgroundColor3 = C.gold, BackgroundTransparency = 0, Font = Theme.HeadingFont, TextSize = 15, TextColor3 = C.goldInk, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center, Selectable = true })
		Ui.corner(button, 8)
	elseif row.status == "soon" or row.status == "locked" then
		local why = row.locked or "Not yet"
		button = CardKit.bigButton(panel, { name = "Locked", text = if row.status == "soon" then `⏳ {why}` else `🔒 {why}`, kind = "shut", height = layout.button, textSize = 12, onClick = function()
			toast(`{row.name}: {if row.status == "soon" then "⏳" else "🔒"} {why}`) -- (only says it: nothing is bought)
		end })
		button.TextWrapped = true
	else
		local can = row.status == "buy"
		button = CardKit.bigButton(panel, { name = "Buy", text = if can then "BUY" else `NEED {UpgradeRules.money(row.short)}`, kind = if can then "good" else "shut", height = layout.button, textSize = if can then 16 else 12, onClick = function()
			local live = rowOf(row.id) -- (the money moved since it was drawn)
			if not live or live.status ~= "buy" then
				toast(`{row.name}: you need {UpgradeRules.money(if live then live.short else row.short)} more.`)
				return
			end
			if send({ kind = "buy", id = row.id, level = live.level + 1 }) then
				local made = panel:FindFirstChild("Buy")
				if made then
					made.Text = "…"
					made.Active = false
				end
			end
		end })
	end
	button.Size = UDim2.fromOffset(inner, layout.button)
	button.Position = UDim2.fromOffset(pad, by)
	return panel
end

-- The header's zoom buttons and the branches' legend.
local function drawHeader(frame: any, layout: Layout, state: State?)
	local wide = layout.w - (layout.pad * 2 + layout.close + 8)
	Ui.label(frame, "⬆ DELIVEROS UPGRADES", UDim2.fromOffset(math.min(wide, 280), 24), { Name = "Title", Position = UDim2.fromOffset(layout.pad, if layout.touch then 4 else 8), Font = Theme.HeadingFont, TextSize = 18, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.label(frame, subtitleOf(state), UDim2.fromOffset(math.min(wide, 360), 16), { Name = "Subtitle", Position = UDim2.fromOffset(layout.pad, if layout.touch then 26 else 32), TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local close = Ui.closeButton(frame, UpgradeUi.close)
	close.Size = UDim2.fromOffset(layout.close, layout.close)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.AnchorPoint = Vector2.new(1, 0)
	-- − / + (the tree's zoom), left of the ✕
	local side = if layout.touch then layout.close else 32
	local zx = layout.w - 6 - layout.close - 10 - 2 * side - 6
	local zooms = W.Zooms :: { number }
	local now = math.clamp(step or layout.zoom, 1, #zooms)
	for n, spec in { { name = "ZoomOut", text = "−", by = -1 }, { name = "ZoomIn", text = "+", by = 1 } } do
		local target = math.clamp(now + spec.by, 1, #zooms)
		local made = CardKit.bigButton(frame, { name = spec.name, text = spec.text, kind = "shut", height = side, textSize = 18, onClick = function()
			UpgradeUi.zoom(target)
		end })
		made.Size = UDim2.fromOffset(side, side)
		made.Position = UDim2.fromOffset(zx + (n - 1) * (side + 6), math.floor((layout.header - side) / 2))
		made.TextColor3 = if target == now then C.dim else K.text
	end
	-- the legend: each branch's colour and name (a computer's: room enough)
	if not layout.touch then
		local x = layout.pad + 380
		for _, branch in UpgradeRules.branches() do
			local text = branch.name
			local width = CardKit.width(text, 11, Theme.HeadingFont) + 22
			if x + width > zx - 10 then
				break
			end
			CardKit.chip(frame, { name = `Legend_{branch.id}`, text = text, face = K.row, ink = rgb(branch.color), stroke = rgb(branch.color), faint = 0.5, static = true }).Position = UDim2.fromOffset(x, math.floor((layout.header - 24) / 2))
			x += width + 6
		end
	end
end

draw = function(keepScroll: boolean)
	if not opened then
		return
	end
	local size = Ui.screenSize()
	local layout = UpgradeUi.layout(size.X, size.Y, Ui.touchLayout())
	local zoom = zoomOf(layout)
	local state = current
	local rows: { UpgradeRules.Row } = if state then UpgradeRules.rows(state.levels, state.money) else {}
	if chosen == nil and #rows > 0 then
		chosen = firstPick(rows)
	end
	local key = stateKey(state, layout, zoom)
	if card and key == shownKey then
		followMoney()
		return -- (nothing else it shows changed: no redraw, a tap is never lost)
	end
	shownKey = key
	local oldTree = card and card:FindFirstChild("Upgrades") and card:FindFirstChild("Upgrades"):FindFirstChild("Tree")
	local scroll = if keepScroll and oldTree then oldTree.CanvasPosition else nil
	local selected = Ui.gamepadSelection()
	local heldInside = card ~= nil and selected ~= nil and selected:IsDescendantOf(card)
	if card then
		card:Destroy()
	end
	local root = ensureGui()
	-- a shade over the world (the touch buttons too): a tap on it closes; Modal frees the mouse
	card = Ui.make("TextButton", {
		Name = "UpgradeShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
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
		SelectionGroup = true, -- (the gamepad's selection stays in the window)
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, card)
	Ui.make("UIScale", { Name = "Scale", Scale = layout.scale }, frame)
	Ui.corner(frame, Config.UiKit.Corner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, frame)
	drawHeader(frame, layout, state)
	-- THE TREE: a canvas that scrolls both ways (a finger drags it; a mouse drags it too, below)
	local canvasSize = UpgradeUi.canvasSize(zoom)
	local tree = Ui.make("ScrollingFrame", {
		Name = "Tree",
		Size = UDim2.fromOffset(layout.treeW, layout.treeH),
		Position = UDim2.fromOffset(layout.treeX, layout.treeY),
		BackgroundColor3 = K.recessed,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		ScrollBarThickness = SCROLLBAR,
		ScrollBarImageColor3 = K.line,
		ScrollingDirection = Enum.ScrollingDirection.XY,
		CanvasSize = UDim2.fromOffset(canvasSize.X, canvasSize.Y),
		ClipsDescendants = true,
		Selectable = false,
	}, frame)
	Ui.corner(tree, Config.UiKit.RowCorner)
	local most = Vector2.new(math.max(0, canvasSize.X - layout.treeW), math.max(0, canvasSize.Y - layout.treeH))
	local start = scroll
	if start == nil then
		-- (a fresh view: the selected node in it with as little a scroll as it takes, the lanes' names at the left when
		-- it allows; its row in the middle when the tree is taller than the view)
		local tierNext = math.min(#Config.Warehouse.Levels, UpgradeRules.warehouseLevel(if state then state.levels else {}) + 1)
		local focus = if chosen and chosen ~= "warehouse" then (UpgradeRules.def(chosen) :: any).at else UpgradeRules.trunkAt(tierNext)
		local b = UpgradeUi.place(focus, zoom)
		start = Vector2.new(b.x + b.w + W.Pad * zoom - layout.treeW, b.y + b.h / 2 - layout.treeH / 2)
	end
	tree.CanvasPosition = Vector2.new(math.clamp(start.X, 0, most.X), math.clamp(start.Y, 0, most.Y))
	drawLanes(tree, zoom)
	if state then
		drawLines(tree, rows, state.levels, zoom)
	end
	local focusNode: any = nil
	for _, row in rows do
		if row.id == "warehouse" then
			local tile = drawTrunk(tree, row, zoom)
			if chosen == "warehouse" then
				focusNode = tile
			end
		else
			local made = drawNode(tree, row, zoom)
			if row.id == chosen then
				focusNode = made
			end
		end
	end
	-- THE DETAILS
	local detail = if chosen then rowOf(chosen) else nil
	local panel = if detail then drawDetails(frame, layout, detail) else nil
	local buy = panel and (panel:FindFirstChild("Buy") or panel:FindFirstChild("Locked") or panel:FindFirstChild("Max"))
	if not keepScroll or heldInside then
		Ui.gamepadFocus(focusNode or buy or frame:FindFirstChild("Close")) -- (a redraw moves the gamepad only when its selection went with it)
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
		chosen = nil -- (a fresh window shows the best node to buy)
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
			-- (what it gives with the levels after it: the state may come after the toast; the trunk's tier 1 … 5)
			local id: string = message.id
			local at = math.floor(level)
			local levels = table.clone(if current then current.levels else {})
			levels[id] = at
			local words = UpgradeRules.words(id, at, levels)
			toast(if id == "warehouse" then `{def.name}: tier {at + 1} · {words}` else `{def.name}: rank {at} · {words}`)
		end
	end
end

-- The money from the player's State (a sale, the hall's income): the details' BUY follows it while open.
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

-- A mouse drags the tree (a touch screen's finger scrolls it by itself).
local function onDrag(input: InputObject)
	local drag = dragging
	if not drag or not opened or input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local tree = card and card:FindFirstChild("Upgrades") and card:FindFirstChild("Upgrades"):FindFirstChild("Tree")
	if not tree then
		return
	end
	local scale = UpgradeUi.layout(Ui.screenSize().X, Ui.screenSize().Y, Ui.touchLayout()).scale
	local dx, dy = (input.Position.X - drag.at.X) / scale, (input.Position.Y - drag.at.Y) / scale
	tree.CanvasPosition = Vector2.new(drag.from.X - dx, drag.from.Y - dy)
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
	-- ESC, the gamepad's B and the Roblox menu close it; a mouse's left button held on the tree drags it
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) and opened and not UserInputService:GetFocusedTextBox() then
			UpgradeUi.close()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 and opened then
			local tree = card and card:FindFirstChild("Upgrades") and card:FindFirstChild("Upgrades"):FindFirstChild("Tree")
			if tree then
				local p, s = tree.AbsolutePosition, tree.AbsoluteSize
				local at = Vector2.new(input.Position.X, input.Position.Y)
				if at.X >= p.X and at.Y >= p.Y and at.X <= p.X + s.X and at.Y <= p.Y + s.Y then
					dragging = { at = at, from = tree.CanvasPosition }
				end
			end
		end
	end)
	local ended = (UserInputService :: any).InputEnded
	if ended then
		ended:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = nil
			end
		end)
	end
	local changed = (UserInputService :: any).InputChanged
	if changed then
		changed:Connect(onDrag)
	end
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
