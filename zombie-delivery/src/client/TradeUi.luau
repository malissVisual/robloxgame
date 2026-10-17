--!strict
-- 8.7 SANDBOX, trading between players: one small window in three modes (server/PlayerTrade.luau decides everything;
-- shared/PlayerTradeRules.luau has the prices this window shows before it asks, Config.PlayerTrade the numbers):
--   * "offer", THE COMPOSER (another player's "Make an offer" prompt: the "PlayerTrade" remote's { kind = "compose" }):
--     the piece (its name in its rarity's colour; rarity, condition, its value, its $ a minute on YOUR stand), "📖 New
--     for your book!" when your book lacks it, its FOR SALE price when it has a sign, the price (− and + steps: about
--     10 % a tap; the presets 1×, 1.5×, 2×, 3× the value; always within the bounds, "×1.5 · $800 – $8,000" under it)
--     and SEND $X ({ kind = "offer", seller, uid, stand, price }; grey with less money than that: a tap says so). The
--     window closes on SEND; the server's Notices say the rest (sent, accepted, declined, run out).
--   * "price", THE PRICE PICKER (your "Set price" prompt: { kind = "pricing" }; or the STOCK list's 🏷 on a piece on
--     show: TradeUi.openPrice, client/WarehouseUi.luau): the same piece and price, "You get $X after the 8% ZDC fee",
--     SET $X ({ kind = "price", uid, price }) and, while it has a sign, TAKE OFF SALE ({ kind = "price", uid, price = 0 });
--     else CANCEL. Opened from the STOCK list, closing it goes back there (TradeUi.onBack).
--   * "buy", THE BUY QUESTION (another player's "Buy $X" prompt: { kind = "confirm" }): the piece, its price big,
--     "You have $X", CANCEL (the gamepad's selection starts there) and BUY $X ({ kind = "buy", seller, uid, stand,
--     price }: only at that price).
-- One window at a time (client/Main.client.luau registers it: onOpen, ESC); ✕, ESC, the gamepad's B, the Roblox menu
-- or a tap beside the card close it (nothing sent; ✕, CANCEL and a tap beside a picker from the STOCK list go back
-- to the list, ESC and another window opening do not). Modal: the mouse is free while it is open, a touch screen's buttons
-- are under it. On a touch screen every button is at least Ui.MinTouch; on a small phone the card shrinks (SHRINK at a
-- time) until it fits (TradeUi.layout, pure).
--   TradeUi.start()                       listens (nothing outside the sandbox)
--   TradeUi.openPrice(entry)              the price picker for a piece of your STOCK list's state on show (its View)
--   TradeUi.close() / isOpen() / showing()   "offer", "price", "buy" or nil
--   TradeUi.piece() / price()             the piece shown (PlayerTradeRules.Piece) and the price chosen now
--   TradeUi.layout(W, H, S, touch, mode, note) -> Layout   the card on a W × H screen (px under Roblox's top bar)
--   TradeUi.onOpen / onBack               hooks: the window opened (client/Main.client.luau: the others close), a
--                                         picker from the STOCK list closed (back to it)
-- Presentation only.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.PlayerTradeRules)
local WarehouseLayout = require(Shared.WarehouseLayout) -- ("+$0.2/min" as the stands' tags write it)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)

local TradeUi = {}

TradeUi.onOpen = nil :: (() -> ())?
TradeUi.onBack = nil :: (() -> ())?

export type Layout = {
	scale: number, -- the card's UIScale
	x: number, -- its top left on the screen (px)
	y: number,
	w: number, -- its size (unscaled)
	h: number,
	pad: number,
	close: number, -- the ✕'s side
	title: number, -- the title row's height (the ✕'s at least)
	button: number, -- the actions' height
	preset: number, -- the presets' height
	priceRow: number, -- the price row's height (− and + as tall and as wide)
	note: boolean, -- the note line (📖 New for your book!, 🏷 on sale)
	-- the rows' tops (unscaled px in the card)
	titleY: number,
	subY: number,
	nameY: number,
	factsY: number,
	noteY: number,
	priceY: number,
	rangeY: number,
	presetsY: number, -- (-1: none: the buy question)
	actionY: number,
	footY: number,
}

local K = Theme.Contract
local C = CardKit.Color
local CARD_W, PAD, GAP = 340, 14, 8
local TITLE_H, SUB_H, NAME_H, FACT_H, NOTE_H, RANGE_H, FOOT_H = 24, 16, 22, 16, 18, 14, 14
local PRICE_H, PRESET_H, ACTION_H, CLOSE = 40, 34, 40, 32
local BIG_PRICE = 44 -- the buy question's price line (no − or +)
local MARGIN = 8 -- px from the screen's edges
local SHRINK = 0.05
local TITLES: { [string]: string } = { offer = "🤝 MAKE AN OFFER", price = "🏷 FOR SALE SIGN", buy = "🛒 BUY" }

local player = Players.LocalPlayer
local remote: RemoteEvent? = nil
local started = false
local gui: any = nil
local shade: any = nil -- the shade over the screen (the window)
local card: any = nil
local mode: string? = nil
local shown: Rules.Piece? = nil
local price = 0
local fromStock = false -- the picker came from the STOCK list (closing goes back there)
local parts: { [string]: any } = {}

-- ── The layout (pure: the phone-ui check runs it) ───────────────────────────

-- The card's rows for a scale: its buttons a finger's height as drawn on a touch screen.
local function rows(scale: number, touch: boolean, kind: string, note: boolean): Layout
	local finger = if touch then math.ceil(Ui.MinTouch / scale - 1e-6) else 0
	local close = math.max(CLOSE, finger)
	local title = math.max(TITLE_H, close)
	local button = math.max(ACTION_H, finger)
	local preset = math.max(PRESET_H, finger)
	local priceRow = if kind == "buy" then BIG_PRICE else math.max(PRICE_H, finger)
	local y = PAD
	local out: any = { scale = scale, x = 0, y = 0, w = CARD_W, pad = PAD, close = close, title = title, note = note }
	out.titleY = y
	y += title + 2
	out.subY = y
	y += SUB_H + GAP
	out.nameY = y
	y += NAME_H
	out.factsY = y
	y += FACT_H
	out.noteY = y
	if note then
		y += NOTE_H
	end
	y += GAP
	out.priceY = y
	y += priceRow
	out.rangeY = y
	y += RANGE_H + GAP
	if kind == "buy" then
		out.presetsY = -1
	else
		out.presetsY = y
		y += preset + GAP
	end
	out.actionY = y
	y += button + 6
	out.footY = y
	y += FOOT_H + PAD
	out.h = y
	out.button = button
	out.preset = preset
	out.priceRow = priceRow
	return out :: Layout
end

function TradeUi.layout(W: number, H: number, S: number, touch: boolean, kind: string, note: boolean): Layout
	local top = if touch then math.max(S, 0.9) else math.max(S, 0.75)
	local least = 0.5
	local scale = top
	local plan = rows(scale, touch, kind, note)
	while scale - SHRINK >= least - 1e-6 and (plan.h * scale > H - 2 * MARGIN or CARD_W * scale > W - 2 * MARGIN) do
		scale -= SHRINK
		plan = rows(scale, touch, kind, note)
	end
	plan.x = math.floor((W - CARD_W * scale) / 2 + 0.5)
	plan.y = math.floor(math.max(MARGIN, (H - plan.h * scale) / 2) + 0.5)
	return plan
end

-- ── The words ───────────────────────────────────────────────────────────────

local function rarityInk(rarity: string): Color3
	local tier = Config.Collection.Tiers[rarity]
	local c = if tier then tier.color else { 222, 224, 228 }
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- "RARE · 92% · worth $800 · +$6.4/min" (the $ a minute on the viewer's own stand: the buyer's, the owner's).
local function facts(piece: Rules.Piece): string
	local percent = math.floor(piece.condition * 100 + 0.5)
	return `{string.upper(piece.rarity)} · {percent}% · worth {Ui.money(piece.value)} · +{WarehouseLayout.money(piece.income)}/min`
end

local function noteOf(piece: Rules.Piece): string?
	local bits: { string } = {}
	if piece.isNew and piece.kind ~= "pricing" then
		table.insert(bits, "📖 New for your book!")
	end
	if piece.sale and piece.kind ~= "confirm" then
		table.insert(bits, if piece.kind == "pricing" then `🏷 On sale now at {Ui.money(piece.sale)}` else `🏷 For sale at {Ui.money(piece.sale)}`)
	end
	return if #bits > 0 then table.concat(bits, " · ") else nil
end

local function subOf(piece: Rules.Piece): string
	if piece.kind == "pricing" then
		return `Your warehouse · stand {piece.stand}`
	end
	return `{piece.sellerName}'s warehouse · stand {piece.stand}`
end

local function footOf(piece: Rules.Piece, at: number): string
	if piece.kind == "pricing" then
		return `You get {Ui.money(Rules.net(at))} after the {math.floor(Config.PlayerTrade.Fee * 100 + 0.5)}% Deliveros fee.`
	elseif piece.kind == "confirm" then
		return if piece.money then `You have {Ui.money(piece.money)} · it goes into your stock.` else "It goes into your stock."
	end
	return `{piece.sellerName} has {Config.PlayerTrade.Expire} s to answer.`
end

-- ── The window ──────────────────────────────────────────────────────────────

local function send(message: { [string]: any })
	local target = remote
	if target then
		target:FireServer(message)
	end
end

local function toast(text: string)
	pcall(function()
		require(script.Parent.Hud).toast(text)
	end)
end

-- Closes it; `back`: the player closed it here (✕, CANCEL, SET, a tap beside it), so a picker from the STOCK list goes
-- back there (never when another window, ESC or the Roblox menu closes it: TradeUi.close).
local function shut(back: boolean)
	if not mode then
		return
	end
	local stock = fromStock
	mode, shown, fromStock = nil, nil, false
	if shade then
		Ui.gamepadRelease(shade)
		shade:Destroy()
	end
	shade, card = nil, nil
	table.clear(parts)
	local onBack = TradeUi.onBack
	if back and stock and onBack then
		onBack()
	end
end

function TradeUi.close()
	shut(false)
end

local function done()
	shut(true)
end

function TradeUi.isOpen(): boolean
	return mode ~= nil
end

function TradeUi.showing(): string?
	return mode
end

function TradeUi.piece(): Rules.Piece?
	return shown
end

function TradeUi.price(): number
	return price
end

local function ensureGui(): any
	if gui and gui.Parent then
		return gui
	end
	local playerGui = player:WaitForChild("PlayerGui")
	gui = Ui.make("ScreenGui", {
		Name = "TradeUi",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 8, -- (over the warehouse's windows' 7, under the offer card's 9)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	return gui
end

-- The price and what follows it: the big number, its × and range, the SEND / SET / BUY words, the foot.
local function paintPrice()
	local piece = shown
	if not piece then
		return
	end
	if parts.price then
		parts.price.Text = Ui.money(price)
	end
	if parts.range then
		parts.range.Text = if piece.kind == "confirm" then `{Rules.times(price, piece.value)} its value`
			else `{Rules.times(price, piece.value)} · {Ui.money(piece.least)} – {Ui.money(piece.most)}`
	end
	local go = parts.go
	if go then
		if piece.kind == "compose" then
			go.Text = `SEND {Ui.money(price)}`
			local short = piece.money ~= nil and piece.money < price
			CardKit.paint(go, if short then "shut" else "primary")
			go:SetAttribute("Short", short)
		elseif piece.kind == "pricing" then
			go.Text = `SET {Ui.money(price)}`
		else
			go.Text = `BUY {Ui.money(price)}`
		end
	end
	if parts.foot then
		parts.foot.Text = footOf(piece, price)
	end
	for _, button in parts.presets or {} do
		local lit = button:GetAttribute("Price") == price
		button.BackgroundColor3 = if lit then K.raised else K.row
		local stroke = button:FindFirstChild("Edge")
		if stroke then
			stroke.Transparency = if lit then 0 else 0.7
		end
	end
end

local function setPrice(value: number)
	local piece = shown
	if not piece then
		return
	end
	price = Rules.clamp(value, piece.value)
	paintPrice()
end

-- The main action: SEND (the offer), SET (the sign), BUY (the sign's price).
local function go()
	local piece = shown
	if not piece then
		return
	end
	if piece.kind == "compose" then
		if piece.money ~= nil and piece.money < price then
			toast(`You have {Ui.money(piece.money)}: not enough for {Ui.money(price)}.`)
			return
		end
		send({ kind = "offer", seller = piece.seller, uid = piece.uid, stand = piece.stand, price = price })
	elseif piece.kind == "pricing" then
		send({ kind = "price", uid = piece.uid, price = price })
	else
		send({ kind = "buy", seller = piece.seller, uid = piece.uid, stand = piece.stand, price = price })
	end
	done()
end

-- The second action: TAKE OFF SALE (a sign on it) or CANCEL.
local function back()
	local piece = shown
	if piece and piece.kind == "pricing" and piece.sale then
		send({ kind = "price", uid = piece.uid, price = 0 })
	end
	done()
end

local function label(parent: any, name: string, text: string, y: number, height: number, size: number, font: Enum.Font, ink: Color3, align: Enum.TextXAlignment?, x: number?, width: number?): any
	return Ui.label(parent, text, UDim2.fromOffset(width or (CARD_W - 2 * PAD), height), {
		Name = name,
		Position = UDim2.fromOffset(x or PAD, y),
		Font = font,
		TextSize = size,
		TextColor3 = ink,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = align or Enum.TextXAlignment.Left,
	})
end

local function button(parent: any, name: string, text: string, kind: string, x: number, y: number, w: number, h: number, size: number, onClick: () -> ()): any
	local made = CardKit.bigButton(parent, { name = name, text = text, kind = kind, height = h, textSize = size, onClick = onClick })
	made.Size = UDim2.fromOffset(w, h)
	made.Position = UDim2.fromOffset(x, y)
	if kind == "shut" then
		made.TextColor3 = K.text -- (quiet: raised, white words)
	end
	return made
end

local function draw()
	local piece = shown
	if not piece then
		return
	end
	if shade then
		shade:Destroy()
	end
	table.clear(parts)
	local size = Ui.screenSize()
	local touch = Ui.touchLayout()
	local note = noteOf(piece)
	local kind = if piece.kind == "confirm" then "buy" elseif piece.kind == "pricing" then "price" else "offer"
	local plan = TradeUi.layout(size.X, size.Y, Ui.screenScale(), touch, kind, note ~= nil)
	local root = ensureGui()
	shade = Ui.make("TextButton", {
		Name = "TradeShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Modal = true,
	}, root)
	shade.Activated:Connect(done)
	card = Ui.make("Frame", {
		Name = "TradeCard",
		Size = UDim2.fromOffset(CARD_W, plan.h),
		Position = UDim2.fromOffset(plan.x, plan.y),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true,
		SelectionGroup = true, -- (the gamepad's selection stays in the card)
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, shade)
	Ui.make("UIScale", { Name = "Scale", Scale = plan.scale }, card)
	Ui.corner(card, Config.UiKit.Corner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if kind == "offer" then C.gold else K.rule, Thickness = if kind == "offer" then 2 else 1 }, card)
	local inner = CARD_W - 2 * PAD
	local titleW = inner - plan.close - 8
	label(card, "Title", TITLES[kind] or "", plan.titleY + (plan.title - TITLE_H) / 2, TITLE_H, 17, Theme.HeadingFont, if kind == "offer" then C.gold else K.text, nil, nil, titleW)
	local close = Ui.closeButton(card, done)
	close.Size = UDim2.fromOffset(plan.close, plan.close)
	close.Position = UDim2.new(1, -PAD + 4, 0, plan.titleY + (plan.title - plan.close) / 2)
	close.AnchorPoint = Vector2.new(1, 0)
	label(card, "Sub", subOf(piece), plan.subY, SUB_H, 12, Theme.Font, K.secondary)
	label(card, "PieceName", piece.name, plan.nameY, NAME_H, 18, Theme.HeadingFont, rarityInk(piece.rarity))
	label(card, "Facts", facts(piece), plan.factsY, FACT_H, 12, Theme.Font, K.secondary)
	if note then
		label(card, "Note", note, plan.noteY, NOTE_H, 13, Theme.HeadingFont, C.gold)
	end
	local textSize = if touch then 15 else 14
	if kind == "buy" then
		parts.price = label(card, "Price", "", plan.priceY, plan.priceRow, 32, Theme.DisplayFont, C.money, Enum.TextXAlignment.Center)
	else
		local side = plan.priceRow
		button(card, "Minus", "−", "shut", PAD, plan.priceY, side, side, 20, function()
			setPrice(Rules.nudge(price, piece.value, -1))
		end)
		button(card, "Plus", "+", "shut", CARD_W - PAD - side, plan.priceY, side, side, 20, function()
			setPrice(Rules.nudge(price, piece.value, 1))
		end)
		parts.price = label(card, "Price", "", plan.priceY, side, 28, Theme.DisplayFont, C.money, Enum.TextXAlignment.Center, PAD + side + 6, inner - 2 * side - 12)
		parts.price.TextTruncate = Enum.TextTruncate.None
	end
	parts.range = label(card, "Range", "", plan.rangeY, RANGE_H, 11, Theme.Font, C.faint, Enum.TextXAlignment.Center)
	if plan.presetsY >= 0 then
		local presets = Rules.presets(piece.value)
		local n = math.max(1, #presets)
		local w = math.floor((inner - (n - 1) * 6) / n)
		parts.presets = {}
		for index, preset in presets do
			local b = button(card, `Preset_{index}`, preset.label, "shut", PAD + (index - 1) * (w + 6), plan.presetsY, w, plan.preset, textSize, function()
				setPrice(preset.price)
			end)
			b.BackgroundColor3 = K.row
			b:SetAttribute("Price", preset.price)
			Ui.make("UIStroke", { Name = "Edge", ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = C.gold, Thickness = 1, Transparency = 0.7 }, b)
			table.insert(parts.presets, b)
		end
	end
	local half = math.floor((inner - 8) / 2)
	local first: any = nil
	if kind == "offer" then
		parts.go = button(card, "Send", "SEND", "primary", PAD, plan.actionY, inner, plan.button, textSize, go)
		first = parts.go
	else
		local onSale = kind == "price" and piece.sale ~= nil
		local secondWord = if onSale then "TAKE OFF SALE" else "CANCEL"
		parts.back = button(card, if onSale then "TakeOff" else "Cancel", secondWord, "shut", PAD, plan.actionY, half, plan.button, textSize, back)
		parts.go = button(card, if kind == "price" then "SetPrice" else "Buy", "", "good", PAD + half + 8, plan.actionY, inner - half - 8, plan.button, textSize, go)
		first = if kind == "buy" then parts.back else parts.go -- (a buy never on A by habit)
	end
	parts.foot = label(card, "Foot", "", plan.footY, FOOT_H, 11, Theme.Font, C.faint, Enum.TextXAlignment.Center)
	paintPrice()
	Ui.gamepadFocus(first)
end

local function open(piece: Rules.Piece, stock: boolean?)
	local was = mode ~= nil
	shown = piece
	mode = if piece.kind == "compose" then "offer" elseif piece.kind == "pricing" then "price" else "buy"
	fromStock = stock == true
	if piece.kind == "confirm" then
		price = piece.price or piece.sale or piece.least
	elseif piece.kind == "pricing" then
		price = Rules.clamp(piece.sale or piece.value * 2, piece.value)
	else
		local second = Rules.presets(piece.value)[2] -- (1.5 × to start: an offer a seller notices)
		price = Rules.clamp(piece.sale or (if second then second.price else piece.value), piece.value)
	end
	if not was then
		local onOpen = TradeUi.onOpen
		if onOpen then
			onOpen()
		end
	end
	draw()
end

-- The STOCK list's 🏷 on a piece on show (its View from the Collection remote's state): the price picker, here.
function TradeUi.openPrice(entry: any)
	if type(entry) ~= "table" or entry.stand == nil then
		return
	end
	local raw = {
		kind = "pricing",
		seller = player.UserId,
		sellerName = player.DisplayName,
		uid = entry.uid,
		stand = entry.stand,
		name = entry.name,
		item = entry.item,
		rarity = entry.rarity,
		condition = entry.condition,
		-- (the View's price without the market: CollectionRules.sell, PlayerTradeRules.value; worked out when not sent)
		value = if type(entry.base) == "number" then entry.base elseif type(entry.item) == "string" then Rules.value({ item = entry.item, condition = tonumber(entry.condition) or 1 }) else nil,
		income = entry.income,
		sale = entry.sale,
	}
	local piece = Rules.readPiece(raw)
	if piece then
		open(piece, true)
	end
end

local function onMessage(message: any)
	if type(message) ~= "table" then
		return
	end
	local piece = Rules.readPiece(message)
	if piece then
		open(piece, false)
	end
end

function TradeUi.start()
	if started then
		return
	end
	started = true
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if mode and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
			TradeUi.close()
		end
	end)
	GuiService.MenuOpened:Connect(TradeUi.close)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if mode then
				draw()
			end
		end)
	end
	task.spawn(function()
		local ok, found = pcall(Net.get, "PlayerTrade")
		if not ok then
			warn(`[TradeUi] no PlayerTrade remote: {found}`)
			return
		end
		remote = found
		found.OnClientEvent:Connect(onMessage)
	end)
end

return TradeUi
