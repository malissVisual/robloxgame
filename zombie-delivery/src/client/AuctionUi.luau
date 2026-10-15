--!strict
-- 8.8 SANDBOX: the Auction House's window (design/auction/PLAN.md; shared/AuctionRules.luau, Config.Auction). Only while
-- Config.Auction.On: with it false (the default) start() does nothing at all, so nothing of the auction shows and
-- nothing is sent. The groundwork: the server's side of the "Auction" remote (the round, the lots, the bids, the
-- transfer, the payments) comes in the next step, so today this talks to a stub: a request nobody answers is given up
-- after a few seconds ("The Auction House didn't answer"), and without a view the window shows the round's schedule
-- (the same on every server: AuctionRules.phase). The remote:
--   client → server   { kind = "state" } | { kind = "consign", uid } | { kind = "withdraw" } | { kind = "bid", lot, amount }
--   server → client   { kind = "state", view } (AuctionRules.readView: the round, the lot on the podium, your piece, the
--                     results) after every change; { kind = "open", tab? } (the desk); { kind = "note", text } a toast
--                     (outbid, sold, bought)
-- THE WINDOW: a modal card "🔨 AUCTION HOUSE" (the round's line and your money under it, ✕) with three tabs:
--   LIVE LOT   the lot on the podium: its picture (the emoji on its rarity's colour), name, rarity, condition and $/min,
--              "📖 New for your book!" when it is, the seller; the current price, the leading bidder, the countdown (red in
--              its last 10 s), BID +$X · $Y (one step: { kind = "bid", lot, amount }; grey with why not: your piece, you
--              lead, NEED $X, SOLD), the lots after it. No lot: the round's line and CONSIGN A PIECE.
--   CONSIGN    the consignment picker: the next auction's countdown, the pieces of your stock that may go (rare, epic,
--              legendary, not broken: AuctionRules.consignable) as tiles (emoji, name, rarity and condition, $/min,
--              "Opens $X"); a tile tapped is picked, the button under them CONSIGN <name> · opens at $X
--              ({ kind = "consign", uid }) or why not; with a piece consigned already WITHDRAW <name>.
--   RESULTS    the last round's lots: who bought each and for how much, yours marked (sold: what you got after the fee;
--              bought).
-- The desk's "Consign a piece" prompt (server/SandboxWorld.luau: attribute AuctionDesk) opens it on CONSIGN. The stock
-- comes from the "Collection" remote's state (as client/WarehouseUi.luau's), the money from the State remote. The clock,
-- the price and the leader follow in place (no rebuild under a tap); a new lot, tab or piece draws it again. The Auction
-- House's sign ("Next auction in 12:34") and its lot display (the lot, the price, the leader, the clock) are painted here
-- from the same view, once a tick, only where the building stands.
-- ✕, ESC, the gamepad's B, the Roblox menu or a tap beside the card close it; modal (the mouse free), the gamepad's
-- selection kept inside; opening it closes the other sandbox windows (client/Main.client.luau: onOpen).
--   AuctionUi.start()                  listens (once; nothing when Config.Sandbox.On or Config.Auction.On is false)
--   AuctionUi.open(tab?) / close() / isOpen()
--   AuctionUi.state()                  the last view (AuctionRules.View; nil: none yet)
--   AuctionUi.view()                   { tab, selected }: the open tab, the consign tile picked (a uid)
--   AuctionUi.layout(W, H, touch)      the card on a W × H screen (px under Roblox's top bar)
--   AuctionUi.paint()                  the building's sign and lot display, now (the tick does it)
--   AuctionUi.notify / onOpen          hooks: the toasts, the window opened
-- Presentation only: every decision is the server's.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.AuctionRules)
local CollectionRules = require(Shared.CollectionRules)
local HouseLayout = require(Shared.AuctionHouseLayout)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)

local AuctionUi = {}

local K = Theme.Contract
local C = CardKit.Color
local WIN = Config.Auction.Window

export type Piece = { uid: string, item: string, name: string, condition: number, rarity: string, income: number, stand: number? }
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
	tabsY: number,
	tabsH: number,
	tabW: number,
	bodyY: number,
	bodyH: number,
	leftW: number, -- LIVE: the piece's column
	rightX: number, -- LIVE: the price's column
	rightW: number,
	picture: number, -- LIVE: the piece's picture's side
	button: number, -- BID's, CONSIGN's height
	gridY: number, -- CONSIGN: the tiles
	gridH: number,
	cols: number,
	tileW: number,
	tileH: number,
	gap: number,
	actionY: number, -- CONSIGN: the button under the tiles
}

AuctionUi.notify = nil :: ((text: string) -> ())?
AuctionUi.onOpen = nil :: (() -> ())?

local HEADER = 52
local SCROLLBAR = 6
local WAIT = 4 -- s a request waits for the server's answer before it is given up (the stub: nobody answers yet)
local TABS = { { "live", "🔨 LIVE LOT" }, { "consign", "📦 CONSIGN" }, { "results", "🏁 RESULTS" } }

local started = false
local remote: RemoteEvent? = nil
local current: Rules.View? = nil -- the server's view (nil: none yet: the schedule alone)
local stock: { Piece }? = nil
local money = 0
local gui: any = nil
local card: any = nil -- the shade over the screen (the window: card's Auction)
local opened = false
local shownKey = ""
local tab = "live"
local selected: string? = nil -- the consign tile picked
local waiting: { kind: string, at: number }? = nil -- a request on its way
local sentAt: { [string]: number } = {}
local house: Instance? = nil -- the Auction House's model, once found

-- ── The layout (pure) ───────────────────────────────────────────────────────

function AuctionUi.layout(W: number, H: number, touch: boolean): Layout
	local margin = if touch then 8 else 16
	local scale = if touch
		then math.clamp(math.min(W / 860, H / 380), 0.8, Ui.MaxScale)
		else math.max(Ui.scaleFor(Vector2.new(W, H)), 0.7)
	local w = math.floor(math.min(WIN.Width, (W - 2 * margin) / scale))
	local h = math.floor(math.min(WIN.Height, (H - 2 * margin) / scale))
	local pad = if touch then 10 else 16
	local finger = math.ceil(Ui.MinTouch / scale)
	local button = if touch then math.max(44, finger) else 40
	local tabsH = if touch then math.max(36, finger) else 32
	local bodyY = HEADER + tabsH + 8
	local leftW = math.floor((w - 2 * pad - 12) * 0.48)
	local actionY = h - pad - button
	local gridY = bodyY + 24
	local gap = 8
	local area = w - 2 * pad - SCROLLBAR - 2
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
		tabsY = HEADER,
		tabsH = tabsH,
		tabW = math.min(160, math.floor((w - 2 * pad - 16) / 3)),
		bodyY = bodyY,
		bodyH = h - bodyY - pad,
		leftW = leftW,
		rightX = pad + leftW + 12,
		rightW = w - (pad + leftW + 12) - pad,
		picture = math.clamp(math.floor(leftW * 0.34), 64, 110),
		button = button,
		gridY = gridY,
		gridH = actionY - 8 - gridY,
		cols = cols,
		tileW = math.floor((area - (cols - 1) * gap) / cols),
		tileH = math.max(WIN.TileHeight, finger),
		gap = gap,
		actionY = actionY,
	}
end

-- ── The stub link, the toasts ───────────────────────────────────────────────

local function auctionOn(): boolean
	local sandbox, auction = (Config :: any).Sandbox, (Config :: any).Auction
	return type(sandbox) == "table" and sandbox.On == true and type(auction) == "table" and auction.On == true
end

-- One request a kind at most every 0.6 s (a double tap is one request); nothing while the auction is off.
local function send(message: { [string]: any }): boolean
	if not auctionOn() then
		return false
	end
	local key = `{message.kind}:{tostring(message.uid or message.lot)}`
	local now = os.clock()
	if sentAt[key] and now - sentAt[key] < 0.6 then
		return false
	end
	sentAt[key] = now
	local target = remote
	if not target then
		return false
	end
	target:FireServer(message)
	return true
end

local function toast(text: string)
	local notify = AuctionUi.notify
	if notify then
		notify(text)
		return
	end
	pcall(function()
		require(script.Parent.Hud).toast(text)
	end)
end

local function serverNow(): number
	local ok, now = pcall(function(): number
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(now) == "number" then now else os.time()
end

-- ── What it shows ───────────────────────────────────────────────────────────

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function rarityColor(id: string): Color3
	local tier = Config.Collection.Tiers[id]
	return if tier then rgb(tier.color) else K.secondary
end

local function iconOf(item: string): string
	local def = CollectionRules.defOf(item) :: any
	return if def and type(def.icon) == "string" then def.icon else "📦"
end

local function rate(perMinute: number): string
	return if perMinute < 10 then string.format("+$%.1f/min", perMinute) else `+{Rules.money(math.floor(perMinute + 0.5))}/min`
end

-- The pieces of the stock that may go to auction, the best first.
local function consignable(): { Piece }
	local list: { Piece } = {}
	for _, piece in stock or {} do
		if Rules.consignable(piece) then
			table.insert(list, piece)
		end
	end
	table.sort(list, function(a: Piece, b: Piece): boolean
		local va, vb = Rules.worthOf(a), Rules.worthOf(b)
		return if va ~= vb then va > vb else a.uid < b.uid
	end)
	return list
end

local function pieceOf(uid: string?): Piece?
	for _, piece in stock or {} do
		if piece.uid == uid then
			return piece
		end
	end
	return nil
end

local function phaseName(now: number): string
	local view = current
	return if view then view.phase else Rules.phase(now).name
end

local function subtitleOf(now: number): string
	return `{Rules.phaseLine(current, now)} · your money {Rules.money(money)}`
end

-- The CONSIGN button: its words, its face and what a tap does (nil: it only says why).
local function consignAction(now: number): (string, string, (() -> ())?)
	local view = current
	local mine = view and view.mine
	if mine then
		return `WITHDRAW {mine.name}`, "warn", function()
			if send({ kind = "withdraw" }) then
				waiting = { kind = "withdraw", at = os.clock() }
			end
		end
	end
	local piece = pieceOf(selected)
	if not piece then
		return if #consignable() > 0 then "PICK A PIECE ABOVE" else "NOTHING TO CONSIGN", "shut", nil
	end
	local p = phaseName(now)
	if p ~= "consign" then
		local _, why = Rules.canConsign({}, 0, piece, p)
		return if p == "live" then "THE AUCTION IS ON" else "CONSIGNMENTS CLOSED", "shut", function()
			toast(why or "Consignments are closed.")
		end
	end
	local opening = Rules.opening(Rules.worthOf(piece))
	return `CONSIGN {piece.name} · opens at {Rules.money(opening)}`, "good", function()
		if send({ kind = "consign", uid = piece.uid }) then
			waiting = { kind = "consign", at = os.clock() }
		end
	end
end

-- ── The window ──────────────────────────────────────────────────────────────

local draw: (keepScroll: boolean) -> ()

local function ensureGui(): any
	if gui then
		return gui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.make("ScreenGui", {
		Name = "AuctionUi",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7, -- (with the other sandbox windows: over the HUD and the touch buttons)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	return gui
end

function AuctionUi.close()
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

function AuctionUi.isOpen(): boolean
	return opened
end

function AuctionUi.state(): Rules.View?
	return current
end

function AuctionUi.view(): { tab: string, selected: string? }
	return { tab = tab, selected = selected }
end

local function stateKey(layout: Layout, now: number): string
	local parts = { `{layout.w}x{layout.h}@{layout.scale}`, tab, phaseName(now), selected or "-" }
	local view = current
	if view then
		local lot = view.lot
		table.insert(parts, if lot then `lot{lot.id}:{lot.item}:{if lot.mine then 1 else 0}{if lot.fresh then 1 else 0}` else "nolot")
		table.insert(parts, if view.mine then view.mine.uid else "-")
		table.insert(parts, `r{#view.results}:{view.round}`)
		table.insert(parts, `u{#view.upcoming}`)
	end
	if tab == "consign" then
		for _, piece in consignable() do
			table.insert(parts, piece.uid)
		end
	end
	if waiting then
		table.insert(parts, "wait")
	end
	return table.concat(parts, "|")
end

local function line(parent: any, name: string, text: string, x: number, y: number, w: number, h: number, size: number, color: Color3, font: Enum.Font?, align: Enum.TextXAlignment?, cut: boolean?): any
	return Ui.label(parent, text, UDim2.fromOffset(w, h), {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Font = font or Theme.Font,
		TextSize = size,
		TextColor3 = color,
		TextWrapped = false,
		TextTruncate = if cut == false then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		TextXAlignment = align or Enum.TextXAlignment.Left,
	})
end

local function picture(parent: any, item: string, rarity: string, x: number, y: number, side: number): any
	local face = Ui.make("Frame", { Name = "Picture", Size = UDim2.fromOffset(side, side), Position = UDim2.fromOffset(x, y), BackgroundColor3 = K.charcoal, BorderSizePixel = 0 }, parent)
	Ui.corner(face, 8)
	Ui.make("UIStroke", { Name = "RarityEdge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = rarityColor(rarity), Thickness = 2 }, face)
	Ui.label(face, iconOf(item), UDim2.fromScale(1, 1), { Name = "Emoji", TextSize = math.floor(side * 0.55), TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
	return face
end

local function drawTabs(frame: any, layout: Layout)
	for index, entry in TABS do
		local id, words = entry[1], entry[2]
		local on = id == tab
		local button = Ui.make("TextButton", {
			Name = `Tab_{id}`,
			Size = UDim2.fromOffset(layout.tabW, layout.tabsH),
			Position = UDim2.fromOffset(layout.pad + (index - 1) * (layout.tabW + 8), layout.tabsY),
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
				draw(false)
			end
		end)
	end
end

-- LIVE LOT: the piece on the left, the price, the leader, the clock and BID on the right; no lot: the round's line.
local function drawLive(frame: any, layout: Layout, now: number): any
	local view = current
	local lot = view and view.lot
	local x, y = layout.pad, layout.bodyY
	if not lot then
		local inner = layout.w - 2 * layout.pad
		line(frame, "Empty", "No lot on the podium", x, y + 20, inner, 26, 20, K.text, Theme.HeadingFont, Enum.TextXAlignment.Center)
		line(frame, "Round", Rules.phaseLine(view, now), x, y + 52, inner, 18, 13, K.secondary, nil, Enum.TextXAlignment.Center)
		local go = CardKit.bigButton(frame, { name = "GoConsign", text = "📦 CONSIGN A PIECE", kind = "good", height = layout.button, textSize = 15, onClick = function()
			tab = "consign"
			draw(false)
		end })
		local goW = math.min(inner, 300)
		go.Size = UDim2.fromOffset(goW, layout.button)
		go.Position = UDim2.fromOffset(math.floor((layout.w - goW) / 2), y + 86)
		return go
	end
	-- the piece
	local side = layout.picture
	picture(frame, lot.item, lot.rarity, x, y, side)
	local tx, tw = x + side + 10, layout.leftW - side - 10
	line(frame, "PieceName", lot.name, tx, y + 2, tw, 20, 16, K.text, Theme.HeadingFont)
	line(frame, "Rarity", string.upper(Rules.rarityName(lot.rarity)) .. (if lot.market == "hot" then " · 🔥 HOT" elseif lot.market == "cold" then " · ❄ COLD" else ""), tx, y + 26, tw, 16, 12, rarityColor(lot.rarity), Theme.HeadingFont)
	line(frame, "Facts", `{Rules.percent(lot.condition)} condition · {rate(lot.income)}`, tx, y + 46, tw, 16, 12, K.secondary)
	line(frame, "Seller", if lot.mine then "Your piece" else `From {lot.seller}`, tx, y + 66, tw, 16, 12, K.secondary)
	line(frame, "Fresh", if lot.fresh then Rules.Fresh else "", x, y + side + 10, layout.leftW, 18, 14, C.gold, Theme.HeadingFont)
	line(frame, "Worth", `Worth {Rules.money(lot.worth)} · opened at {Rules.money(lot.opening)}`, x, y + side + 32, layout.leftW, 16, 12, K.secondary)
	-- the price, the leader, the clock, BID
	local rx, rw = layout.rightX, layout.rightW
	line(frame, "PriceLabel", if lot.price > 0 then "CURRENT PRICE" else "OPENING PRICE", rx, y, rw, 14, 11, K.secondary, Theme.HeadingFont)
	line(frame, "Price", Rules.money(if lot.price > 0 then lot.price else lot.opening), rx, y + 16, rw - 92, 36, 30, C.gold, Theme.DisplayFont, nil, false)
	line(frame, "Clock", Rules.clock(lot.endsAt - now), rx + rw - 90, y + 16, 90, 36, 30, K.text, Theme.DisplayFont, Enum.TextXAlignment.Right, false)
	line(frame, "Leader", Rules.leaderLine(lot), rx, y + 58, rw, 18, 14, if lot.leaderMe then C.money else K.text, Theme.HeadingFont)
	local words, kind = Rules.bidButton(lot, money, now)
	local bid = CardKit.bigButton(frame, { name = "Bid", text = words, kind = kind, height = layout.button, textSize = 16, onClick = function()
		local live = current and current.lot
		if not live then
			return
		end
		local _, _, why = Rules.bidButton(live, money, serverNow())
		if why then
			toast(why)
			return
		end
		if send({ kind = "bid", lot = live.id, amount = live.next }) then
			waiting = { kind = "bid", at = os.clock() }
			local button = card and card:FindFirstChild("Auction") and card:FindFirstChild("Auction"):FindFirstChild("Bid")
			if button then
				button.Text = "…"
				button.Active = false
			end
		end
	end })
	bid.Size = UDim2.fromOffset(rw, layout.button)
	bid.Position = UDim2.fromOffset(rx, y + 84)
	local after: { string } = {}
	for _, u in (view :: Rules.View).upcoming do
		table.insert(after, `{iconOf(u.item)} {u.name}`)
	end
	line(frame, "Upcoming", if #after > 0 then `Next: {table.concat(after, " · ")}` else "The last lot of this round", rx, y + 92 + layout.button, rw, 16, 12, K.secondary)
	return bid
end

local function drawTile(parent: any, piece: Piece, index: number, layout: Layout)
	local col, row = (index - 1) % layout.cols, math.floor((index - 1) / layout.cols)
	local w, h = layout.tileW, layout.tileH
	local tile = Ui.make("TextButton", {
		Name = `Tile_{piece.uid}`,
		Size = UDim2.fromOffset(w, h),
		Position = UDim2.fromOffset(col * (w + layout.gap), row * (h + layout.gap)),
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = true,
	}, parent)
	Ui.corner(tile, 8)
	local on = piece.uid == selected
	Ui.make("UIStroke", { Name = "Edge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if on then K.text else rarityColor(piece.rarity), Thickness = if on then 2 else 1, Transparency = if on then 0.1 else 0.5 }, tile)
	local side = 36
	local face = Ui.make("Frame", { Name = "Thumb", Size = UDim2.fromOffset(side, side), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = K.charcoal, BorderSizePixel = 0 }, tile)
	Ui.corner(face, 6)
	Ui.label(face, iconOf(piece.item), UDim2.fromScale(1, 1), { Name = "Emoji", TextSize = 22, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
	local tx, tw = 6 + side + 6, w - (6 + side + 6) - 6
	line(tile, "ItemName", piece.name, tx, 6, tw, 16, 13, K.text, Theme.HeadingFont)
	line(tile, "Rarity", `{Rules.rarityName(piece.rarity)} · {Rules.percent(piece.condition)}`, tx, 24, tw, 14, 11, rarityColor(piece.rarity), Theme.HeadingFont)
	line(tile, "Income", if piece.stand then `{rate(piece.income)} · on show` else rate(piece.income), 6, h - 38, w - 12, 14, 11, K.secondary)
	line(tile, "Opens", `Opens at {Rules.money(Rules.opening(Rules.worthOf(piece)))}`, 6, h - 21, w - 12, 15, 12, C.money, Theme.HeadingFont)
	tile.Activated:Connect(function()
		CardKit.click()
		if current and current.mine then
			toast(`One piece a round: withdraw your {current.mine.name} first.`)
			return
		end
		selected = piece.uid
		draw(true)
	end)
end

-- CONSIGN: the countdown and the rules, your stock's pieces that may go, the button under them.
local function drawConsign(frame: any, layout: Layout, now: number, scroll: Vector2): any
	local view = current
	local mine = view and view.mine
	local info = if mine
		then `Your {mine.name} goes under the hammer · opens at {Rules.money(mine.opening)}`
		else `One piece a round · {Rules.rarityWords()} · the house keeps {math.floor(Rules.feeRate() * 100 + 0.5)}% of a sale`
	line(frame, "Info", info, layout.pad, layout.bodyY, layout.w - 2 * layout.pad, 18, 13, if mine then C.gold else K.secondary, Theme.HeadingFont)
	local list = consignable()
	if selected and not pieceOf(selected) then
		selected = nil
	end
	local lines = math.ceil(#list / layout.cols)
	local tall = math.max(0, lines * (layout.tileH + layout.gap) - layout.gap)
	local scrolls = tall > layout.gridH
	local grid = Ui.make("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.fromOffset(layout.w - 2 * layout.pad, layout.gridH),
		Position = UDim2.fromOffset(layout.pad, layout.gridY),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if scrolls then SCROLLBAR else 0,
		ScrollBarImageColor3 = K.line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, tall),
		CanvasPosition = Vector2.new(0, math.clamp(scroll.Y, 0, math.max(0, tall - layout.gridH))),
		SelectionGroup = false,
	}, frame)
	for index, piece in list do
		drawTile(grid, piece, index, layout)
	end
	if #list == 0 then
		line(grid, "Empty", if stock == nil then "Loading your stock…" else `No piece to consign yet: bring home a {Rules.rarityWords()} piece.`, 0, 8, layout.w - 2 * layout.pad, 18, 13, K.secondary)
	end
	local words, kind = consignAction(now)
	local action = CardKit.bigButton(frame, { name = "Action", text = if waiting then "…" else words, kind = if waiting then "shut" else kind, height = layout.button, textSize = 15, onClick = function()
		if waiting then
			return
		end
		local _, _, live = consignAction(serverNow())
		if live then
			live()
			draw(true)
		else
			toast(if #consignable() > 0 then "Tap a piece above first." else `Bring home a {Rules.rarityWords()} piece to consign.`)
		end
	end })
	action.Size = UDim2.fromOffset(layout.w - 2 * layout.pad, layout.button)
	action.Position = UDim2.fromOffset(layout.pad, layout.actionY)
	local first = if selected then grid:FindFirstChild(`Tile_{selected}`) else nil
	return first or (if #list > 0 then grid:FindFirstChild(`Tile_{list[1].uid}`) else action)
end

-- RESULTS: the last round's lots, yours marked.
local function drawResults(frame: any, layout: Layout, now: number): any
	local view = current
	local results = if view then view.results else {}
	local rowH, gap = 44, 6
	local tall = math.max(0, #results * (rowH + gap) - gap)
	local list = Ui.make("ScrollingFrame", {
		Name = "Results",
		Size = UDim2.fromOffset(layout.w - 2 * layout.pad, layout.bodyH),
		Position = UDim2.fromOffset(layout.pad, layout.bodyY),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = if tall > layout.bodyH then SCROLLBAR else 0,
		ScrollBarImageColor3 = K.line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, tall),
		Selectable = true,
	}, frame)
	local w = layout.w - 2 * layout.pad - (if tall > layout.bodyH then SCROLLBAR + 2 else 0)
	for index, r in results do
		local row = Ui.make("Frame", { Name = `Result_{index}`, Size = UDim2.fromOffset(w, rowH), Position = UDim2.fromOffset(0, (index - 1) * (rowH + gap)), BackgroundColor3 = K.row, BorderSizePixel = 0 }, list)
		Ui.corner(row, 8)
		if r.sold or r.won then
			Ui.make("UIStroke", { Name = "Yours", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if r.won then C.money else C.gold, Thickness = 1, Transparency = 0.3 }, row)
		end
		Ui.label(row, iconOf(r.item), UDim2.fromOffset(32, 32), { Name = "Emoji", Position = UDim2.fromOffset(6, 6), TextSize = 20, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
		local priceW = 96
		line(row, "ItemName", `{r.name} · {Rules.rarityName(r.rarity)}`, 44, 4, w - 44 - priceW - 12, 18, 13, K.text, Theme.HeadingFont)
		line(row, "Outcome", Rules.resultLine(r), 44, 23, w - 44 - priceW - 12, 16, 12, if r.won then C.money elseif r.sold then C.gold else K.secondary)
		line(row, "Price", Rules.money(r.price), w - priceW - 8, 12, priceW, 20, 16, C.gold, Theme.DisplayFont, Enum.TextXAlignment.Right, false)
	end
	if #results == 0 then
		line(list, "Empty", `No results yet · {Rules.phaseLine(view, now)}`, 0, 8, w, 18, 13, K.secondary)
	end
	return list
end

-- What follows the clock, the price and the money in place (no rebuild): the subtitle, LIVE's price, leader, clock
-- and BID, a request that got no answer.
local function follow()
	local now = serverNow()
	if waiting and os.clock() - waiting.at > WAIT then
		waiting = nil
		toast("The Auction House didn't answer: try again in a moment.")
		if opened then
			draw(true)
		end
	end
	local frame = card and card:FindFirstChild("Auction")
	if not frame then
		return
	end
	local subtitle = frame:FindFirstChild("Subtitle")
	if subtitle then
		subtitle.Text = subtitleOf(now)
	end
	local lot = current and current.lot
	if tab == "live" and lot then
		local clock, price, leader, bid = frame:FindFirstChild("Clock"), frame:FindFirstChild("Price"), frame:FindFirstChild("Leader"), frame:FindFirstChild("Bid")
		local left = lot.endsAt - now
		if clock then
			clock.Text = Rules.clock(left)
			clock.TextColor3 = if left <= 10 then K.red else K.text
		end
		if price then
			price.Text = Rules.money(if lot.price > 0 then lot.price else lot.opening)
		end
		if leader then
			leader.Text = Rules.leaderLine(lot)
			leader.TextColor3 = if lot.leaderMe then C.money else K.text
		end
		if bid and not waiting then
			local words, kind = Rules.bidButton(lot, money, now)
			bid.Text = words
			bid.Active = true
			CardKit.paint(bid, kind)
		end
	end
end

draw = function(keepScroll: boolean)
	if not opened then
		return
	end
	local now = serverNow()
	local size = Ui.screenSize()
	local layout = AuctionUi.layout(size.X, size.Y, Ui.touchLayout())
	local key = stateKey(layout, now)
	if card and key == shownKey then
		follow()
		return -- (nothing else it shows changed: no redraw, a tap is never lost)
	end
	shownKey = key
	local old = card and card:FindFirstChild("Auction")
	local oldGrid = old and old:FindFirstChild("Grid")
	local scroll = if keepScroll and oldGrid then oldGrid.CanvasPosition else Vector2.zero
	local held = Ui.gamepadSelection()
	local heldName = if card ~= nil and held ~= nil and held:IsDescendantOf(card) then held.Name else nil
	if card then
		card:Destroy()
	end
	local root = ensureGui()
	-- a shade over the world (the touch buttons too): a tap beside the card closes it; Modal frees the mouse
	card = Ui.make("TextButton", {
		Name = "AuctionShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Modal = true,
	}, root)
	card.Activated:Connect(AuctionUi.close)
	local frame = Ui.make("Frame", {
		Name = "Auction",
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
	-- the header: the title, the round's line and your money, the ✕
	local wide = layout.w - (layout.pad * 2 + layout.close + 8)
	line(frame, "Title", "🔨 AUCTION HOUSE", layout.pad, 10, wide, 24, 18, K.text, Theme.HeadingFont)
	line(frame, "Subtitle", subtitleOf(now), layout.pad, 33, wide, 16, 12, K.secondary)
	local close = Ui.closeButton(frame, AuctionUi.close)
	close.Size = UDim2.fromOffset(layout.close, layout.close)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.AnchorPoint = Vector2.new(1, 0)
	drawTabs(frame, layout)
	local target: any = nil
	if tab == "consign" then
		target = drawConsign(frame, layout, now, scroll)
	elseif tab == "results" then
		target = drawResults(frame, layout, now)
	else
		target = drawLive(frame, layout, now)
	end
	follow()
	local back = if heldName then frame:FindFirstChild(heldName, true) else nil
	if not keepScroll or heldName then
		Ui.gamepadFocus(back or target or close) -- (a redraw while open moves the gamepad only when its selection was inside)
	end
end

-- ── The building's sign and lot display ─────────────────────────────────────

local function setText(words: Instance?, name: string, text: string)
	local label = words and words:FindFirstChild(name)
	if label and (label :: any).Text ~= text then
		(label :: any).Text = text
	end
end

function AuctionUi.paint()
	local found = house
	if not found or not found.Parent then
		local world = workspace:FindFirstChild("Sandbox")
		found = world and world:FindFirstChild("AuctionHouse")
		house = found
	end
	if not found then
		return
	end
	local now = serverNow()
	local sign = found:FindFirstChild("AuctionSign")
	local view = current
	local lot = view and view.lot
	setText(sign and sign:FindFirstChild("Words"), HouseLayout.SignLabels[2], if lot then `LIVE NOW · lot {(view :: Rules.View).index} of {(view :: Rules.View).count}` else Rules.phaseLine(view, now))
	local screen = found:FindFirstChild("AuctionScreen")
	local words = screen and screen:FindFirstChild("Words")
	if not words then
		return
	end
	local names = HouseLayout.ScreenLabels -- Title, Piece, Facts, Price, Leader, Clock
	if lot then
		setText(words, names[1], `LOT {(view :: Rules.View).index} OF {(view :: Rules.View).count}`)
		setText(words, names[2], `{iconOf(lot.item)} {lot.name}`)
		setText(words, names[3], `{string.upper(Rules.rarityName(lot.rarity))} · {Rules.percent(lot.condition)} · {rate(lot.income)}`)
		setText(words, names[4], Rules.money(if lot.price > 0 then lot.price else lot.opening))
		setText(words, names[5], if lot.leader then `{lot.leader} leads` else "No bids yet")
		setText(words, names[6], Rules.clock(lot.endsAt - now))
	else
		setText(words, names[1], "AUCTION HOUSE")
		setText(words, names[2], "No lot on the podium")
		setText(words, names[3], Rules.phaseLine(view, now))
		setText(words, names[4], "")
		setText(words, names[5], "")
		setText(words, names[6], "")
	end
end

-- ── The state ───────────────────────────────────────────────────────────────

local function readStock(raw: any): { Piece }?
	if type(raw) ~= "table" then
		return nil
	end
	local list: { Piece } = {}
	for _, e in raw do
		if type(e) == "table" and type(e.uid) == "string" and type(e.item) == "string" and #e.uid <= 40 and #e.item <= 40 then
			local def = CollectionRules.defOf(e.item)
			local condition = if type(e.condition) == "number" and e.condition == e.condition then math.clamp(e.condition, 0, 1) else 0
			table.insert(list, {
				uid = e.uid,
				item = e.item,
				name = if type(e.name) == "string" and #e.name <= 60 then e.name elseif def then def.name else e.item,
				condition = condition,
				rarity = if type(e.rarity) == "string" and Config.Collection.Tiers[e.rarity] then e.rarity else CollectionRules.rarityOf(def),
				income = if type(e.income) == "number" and e.income == e.income and e.income >= 0 then e.income else 0,
				stand = if type(e.stand) == "number" then e.stand else nil,
			})
		end
	end
	return list
end

function AuctionUi.open(which: string?)
	local was = opened
	opened = true
	shownKey = ""
	if which == "live" or which == "consign" or which == "results" then
		tab = which
	elseif not was then
		tab = if current and current.lot then "live" elseif current and #current.results > 0 and current.phase == "results" then "results" else "consign"
	end
	if not was then
		local onOpen = AuctionUi.onOpen
		if onOpen then
			onOpen()
		end
	end
	draw(false)
	send({ kind = "state" })
	if stock == nil and auctionOn() then
		pcall(function()
			Net.get("Collection"):FireServer({ kind = "state" })
		end)
	end
end

local function onEvent(message: any)
	if type(message) ~= "table" then
		return
	end
	local kind = message.kind
	if kind == "state" then
		current = Rules.readView(message.view)
		waiting = nil
		if opened then
			draw(true)
		end
		AuctionUi.paint()
	elseif kind == "open" then
		AuctionUi.open(if type(message.tab) == "string" then message.tab else "consign")
	elseif kind == "note" and type(message.text) == "string" and #message.text <= 200 then
		toast(message.text)
	end
end

local function onCollection(message: any)
	if type(message) == "table" and message.kind == "state" then
		local read = readStock(message.stock)
		if read then
			stock = read
			if opened and tab == "consign" then
				draw(true)
			end
		end
	end
end

local function onMoney(state: any)
	local value = if type(state) == "table" then state.money else nil
	if type(value) == "number" and value == value and value >= 0 and value ~= money then
		money = value
		if opened then
			draw(true)
		end
	end
end

function AuctionUi.start()
	if started or not auctionOn() then
		return -- (8.8: the auction off, nothing of it shows and nothing is sent)
	end
	started = true
	-- ESC, the gamepad's B and the Roblox menu close it
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) and opened and not UserInputService:GetFocusedTextBox() then
			AuctionUi.close()
		end
	end)
	GuiService.MenuOpened:Connect(AuctionUi.close)
	-- the desk's "Consign a piece" (server/SandboxWorld.luau: AuctionDesk) opens the window on CONSIGN
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if player == Players.LocalPlayer and prompt:GetAttribute("AuctionDesk") == true then
			AuctionUi.open("consign")
		end
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if opened then
				draw(true)
			end
		end)
	end
	task.spawn(function()
		local ok, found = pcall(Net.get, "Auction")
		if not ok then
			warn(`[AuctionUi] no Auction remote: {found}`)
			return
		end
		remote = found
		found.OnClientEvent:Connect(onEvent)
		found:FireServer({ kind = "state" })
		local hasCollection, collection = pcall(Net.get, "Collection")
		if hasCollection then
			collection.OnClientEvent:Connect(onCollection)
		end
		local hasState, state = pcall(Net.get, "State")
		if hasState then
			state.OnClientEvent:Connect(onMoney)
		end
	end)
	-- the clock: the window's countdown, a request given up, the building's sign and display (four times a second)
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ok, err = pcall(function()
				if opened then
					draw(true) -- (the same view: only what follows the clock, in place; a new phase: drawn again)
				elseif waiting then
					follow()
				end
				AuctionUi.paint()
			end)
			if not ok then
				warn(`[AuctionUi] {err}`)
			end
		end
	end)
end

return AuctionUi
