--!strict
-- 8.0 SANDBOX: your warehouse's picker and your STOCK list (design/sandbox/KONTRAKT.md, "Collection"). The owner: one
-- house, one van and your warehouse, where what you bring home is put on show (it earns money every minute you play)
-- or sold any time. The server decides every value; this window only shows them and asks through the "Collection"
-- remote:
--   { kind = "state", stock, income, stands }   kept (WarehouseUi.state, WarehouseUi.onState); an open window is drawn
--                                               again only when what it shows changed (its scroll kept); 8.3 economy:
--                                               `idle` the share the stands pay while you are idle (else none)
--   { kind = "pick", stand }                    an empty display stand's prompt (Collection.openPicker): THE PICKER
--   { kind = "sold", name, money }              a toast "Sold Grandpa's Clock · +$420" (WarehouseUi.notify, else
--                                               client/Hud.luau's toast)
-- THE PICKER: a modal card "STAND 3 · CHOOSE A PIECE" over a scrolling grid of the pieces in your stock that are not on
-- show, the best earners first ($/min), rarity chips to filter (ALL and the rarities you have, with their counts). A
-- tile: the piece's picture (its 3D model, FurnitureLooks.build, in a ViewportFrame: only the tiles on screen get one,
-- at most Config.SandboxHud.MaxViews, each model built once a piece and variant; its emoji until then and as the
-- fallback), its rarity's colour (a bar under the picture, the word, the tile's edge), its condition, its name, the big
-- "+$X/min" (WarehouseUi.rate: as the stands' tags, to a tenth under $10, "+$0.2/min") and "Sell $Y"; DISPLAY sends
-- { kind = "display", uid, stand } (the picker closes), SELL asks
-- "SELL FOR $Y?" first (CANCEL / SELL), then sends { kind = "sell", uid }.
-- THE STOCK LIST (WarehouseUi.openStock: the HUD's stock chip and its key, client/SandboxHud.luau): the same grid of
-- everything you own, a piece on show marked ON STAND n, with TAKE DOWN ({ kind = "undisplay", uid }) and SELL.
-- ✕, ESC, the gamepad's B, the Roblox menu or a tap beside the card close it (an open question first). It is modal: the
-- mouse is free while it is open (a Modal button), a touch screen's buttons are under it.
-- The values (WarehouseUi.values): the entry's own (rarity, perMinute, sell) when the server sends them, else
-- shared/CollectionRules.luau's (RULES below: the function names asked, with the entry, then with item, condition,
-- variant), else Config.SandboxHud.Fallback's guess from the piece's catalogue value.
--   WarehouseUi.start()                  listens (once; nothing when Config.Sandbox.On is false)
--   WarehouseUi.openPicker(stand) / openStock() / toggleStock() / close() / isOpen() / showing() ("picker", "stock")
--   WarehouseUi.state()                  the last state (nil: none yet); WarehouseUi.onState(fn(state, previous))
--   WarehouseUi.values(entry)            { rarity, perMinute, sell } of a stock entry (perMinute as it is: the
--                                        best earners are sorted on it; sell a whole number)
--   WarehouseUi.rate(perMinute)          "+$0.2/min", "+$36/min" (shared/WarehouseLayout.luau's money: the tags')
--   WarehouseUi.layout(W, H, touch)      the card and its grid on a W × H screen (px under Roblox's top bar)
--   WarehouseUi.views()                  the 3D pictures alive now
--   WarehouseUi.notify / onOpen          hooks: the toasts (client/SandboxHud.luau sets it), the window opened
--   WarehouseUi.Rarity / Rarities        the rarities' colours (common grey, uncommon green, rare blue, epic purple,
--                                        legendary gold) and their order
-- 8.2, the warehouse's quality of life (which pieces: shared/StockPlan.luau, the rules server/Collection.luau decides
-- with, so what a button offers before it asks is what happens):
--   * THE PICKER greys a piece too big for this stand (an upgrade's small stand, WarehouseLayout.fits: the beds, the hay
--     wagon, the wheelbarrow): "Too big for this stand" over its picture, its DISPLAY a grey TOO BIG that says which
--     stands take it; the pieces that fit come first.
--   * THE STOCK LIST's header: ⭐ FILL BEST ({ kind = "fillbest" }: the best earners onto every free stand you have,
--     each where it fits), 💰 SELL… (a small menu: ALL COMMON, ALL BROKEN, DUPLICATES (keeps the best of each item),
--     each with how many and their price; each asks "SELL N PIECES FOR $Y?" first, then sends { kind = "sellmany",
--     filter }; nothing on show is sold) and ↩ TAKE ALL DOWN ({ kind = "undisplayall" }). A button with nothing to do
--     is grey; a tap says why. The server's { kind = "bulk", action, count, income? } and a sellmany's "sold" are toasts.
--   * Both windows: a sort toggle (SORT · $/MIN → VALUE → NEWEST → RARITY; kept while you play) at the chips' right,
--     the rarity chips as before and, on a computer, a 🔍 search box (every word in the piece's name; typing redraws
--     only the grid, the box keeps its focus; closing the window clears it).
--   WarehouseUi.sorting() / search()     the order and the search the windows use now
-- 8.3, the market (shared/Market.luau; the state's `market`, the player's View: today's hot and cold kinds and their
-- own demand; every price and $/min in the state is the market's already):
--   * both windows: a line under the title "Today's market: 🔥 Old Globe, Jukebox, Sofa · ❄ Wardrobe · new in 5 h"; a
--     tile of a hot kind "🔥 HOT ×1.4", of a cold one "❄ COLD", of a kind the player sold today "📉 −10%" (on its
--     picture, under ON STAND n)
--   * SELL's question says why the price is what it is ("Market: Vintage Radio −10% (you sold 2 today)", hot, cold)
--     and sends the price it showed ({ kind = "sell", uid, expect }); SELL…'s totals are the market's (StockPlan.price:
--     each next piece of a kind under the demand of the ones before it) and its SELL sends the total it showed
--     ({ kind = "sellmany", filter, expect }): the server sells only at that total (the prices moved: it says so and
--     sends the state again). Only prices the server sent are expected (a guessed one is never sent).
-- 8.3 (design/warehouse-levels/KONTRAKT.md): which stands are small depends on your warehouse's level (the player
-- attribute Config.SandboxUpgrades.WarehouseAttribute, 1 … 5, server/Upgrades.luau; 4 until the server sets it, as a
-- plain Plot): WarehouseLayout.fits and count ask with it, so TOO BIG and its words follow a level up.
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
local WarehouseLayout = require(Shared.WarehouseLayout) -- (8.0.1: the $/min as the stands' tags write it; 8.2: fits)
local StockPlan = require(Shared.StockPlan) -- 8.2: FILL BEST, SELL…, the sorts, the search
local Market = require(Shared.Market) -- 8.3: the market's line, tags and words
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)

local WarehouseUi = {}

local HUD = Config.SandboxHud
local PICK = HUD.Picker
local K = Theme.Contract
local C = CardKit.Color

export type Entry = {
	uid: any, -- (a string; kept as the server sent it)
	item: string,
	variant: number?,
	condition: number?,
	name: string?,
	stand: number?,
	got: number?,
}
export type State = {
	stock: { Entry },
	income: number,
	stands: number,
	market: Market.View?, -- 8.3: the player's market (nil: none sent)
	marketAt: number, -- 8.3: os.clock() it came (its `left` counts from then)
	idle: number?, -- 8.3 economy: idle, the share of `income` the stands pay (nil: active, all of it)
}
export type Values = { rarity: string, perMinute: number, sell: number }
export type Layout = {
	touch: boolean,
	scale: number, -- the card's UIScale
	x: number, -- the card's top left on the screen (px)
	y: number,
	w: number, -- the card's size (unscaled)
	h: number,
	pad: number,
	header: number, -- (8.2: on a touch screen high enough for the STOCK list's finger-sized buttons; 8.3: and the market)
	market: number, -- 8.3: the market's line (its top, under the title's line and the bulk buttons)
	chips: number, -- the filter chips' height
	close: number, -- the ✕'s side
	gridX: number,
	gridY: number,
	gridW: number,
	gridH: number,
	cols: number,
	tileW: number,
	tileH: number,
	picture: number,
	gap: number,
	button: number,
}

WarehouseUi.Rarities = { "common", "uncommon", "rare", "epic", "legendary" }
WarehouseUi.Rarity = {
	common = Color3.fromRGB(158, 163, 170),
	uncommon = Color3.fromRGB(111, 207, 120),
	rare = Color3.fromRGB(86, 156, 255),
	epic = Color3.fromRGB(178, 108, 240),
	legendary = Color3.fromRGB(242, 201, 76),
} :: { [string]: Color3 }

-- shared/CollectionRules.luau's functions asked for each value, in order (the collection worker's names).
local RULES = {
	rarity = { "rarity", "rarityOf", "tier" },
	perMinute = { "incomePerMinute", "perMinute", "income" },
	sell = { "sellPrice", "sell", "price" },
}

WarehouseUi.notify = nil :: ((text: string) -> ())?
WarehouseUi.onOpen = nil :: (() -> ())?
WarehouseUi.Rules = nil :: any -- shared/CollectionRules.luau once found (start)

local TILE_TEXT = 100 -- a tile's height besides its picture and buttons (unscaled px)
local HEADER = 52
local MARKET_H = 18 -- 8.3: the market's line under the header
local HOT_FACE, HOT_INK = Color3.fromRGB(74, 32, 18), Color3.fromRGB(255, 156, 96) -- 8.3: a hot kind's tag, the line
local COLD_FACE, COLD_INK = Color3.fromRGB(22, 38, 58), Color3.fromRGB(150, 200, 255) -- 8.3: a cold kind's tag
local SEARCH_W = 170 -- 8.2: the search box (a computer)
local MAX_SEARCH = 40 -- its longest words
local SCROLLBAR = 6
local TILE_CORNER = Config.UiKit.RowCorner

local started = false
local remote: RemoteEvent? = nil
local current: State? = nil
local listeners: { (State, State?) -> () } = {}
local gui: any = nil
local mode: { stand: number? }? = nil -- nil: closed; { stand = n } the picker; { stand = nil } the stock list
local filter = "all"
local sortBy = "income" -- 8.2: the sort toggle's order (StockPlan.Sorts), kept while you play
local search = "" -- 8.2: the search box's words (a computer)
local shownKey = ""
local card: any = nil -- the shade over the screen (the window: card's Picker)
local panel: any = nil -- the card itself (Picker)
local question: any = nil
local questionFrom: any = nil -- 8.3: what the gamepad had selected when the question opened (selected again after it)
local grid: any = nil
local plan: Layout? = nil
local listed: Listed? = nil -- 8.2: what the grid lists (draw keeps it, fillGrid reads it)
local actionButtons: { [string]: any } = {} -- 8.2: the open STOCK list's FILL BEST, SELL… and TAKE ALL DOWN

type Tile = { entry: Entry, index: number, picture: any, emoji: any, view: any, buttons: { any } }
local tiles: { Tile } = {}
local liveViews = 0
local refreshQueued = false

-- ── The values ──────────────────────────────────────────────────────────────

local function rarityName(value: any): string?
	if type(value) == "number" then
		return WarehouseUi.Rarities[math.clamp(math.floor(value), 1, #WarehouseUi.Rarities)]
	end
	if type(value) == "table" then
		value = value.id or value.name or value.rarity
	end
	if type(value) == "string" then
		local key = string.lower(value)
		if WarehouseUi.Rarity[key] then
			return key
		end
	end
	return nil
end

local function amount(value: any): number?
	if type(value) == "number" and value == value and value >= 0 and value < math.huge then
		return value
	end
	return nil
end

-- shared/CollectionRules.luau's answer for one value: the first of `names` that answers, with the entry, else with the
-- piece's item, condition and variant (a call that fails or answers nonsense is skipped).
local function ask(names: { string }, entry: Entry, accept: (any) -> any): any
	local rules = WarehouseUi.Rules
	if type(rules) ~= "table" then
		return nil
	end
	for _, name in names do
		local fn = rules[name]
		if type(fn) == "function" then
			local ok, answer = pcall(fn, entry)
			local found = if ok then accept(answer) else nil
			if found == nil then
				ok, answer = pcall(fn, entry.item, entry.condition or 1, entry.variant or 1)
				found = if ok then accept(answer) else nil
			end
			if found ~= nil then
				return found
			end
		end
	end
	return nil
end

local function catalogue(item: string): any
	return (FurnitureLooks.Items :: any)[item]
end

-- Config.SandboxHud.Fallback's guess (until shared/CollectionRules.luau answers): from the catalogue's value.
local function guess(entry: Entry): Values
	local F = HUD.Fallback
	local def = catalogue(entry.item)
	local value = if def and type(def.value) == "number" then def.value else 50
	local condition = math.clamp(tonumber(entry.condition) or 1, 0, 1)
	local sell = math.floor(value * (F.Sell[1] + (F.Sell[2] - F.Sell[1]) * condition) + 0.5)
	local rarity = if def then rarityName(def.rarity) else nil
	if not rarity then
		rarity = "common"
		for index, from in F.Rarity do
			if value >= from then
				rarity = WarehouseUi.Rarities[index + 1]
			end
		end
	end
	return { rarity = rarity :: string, perMinute = math.max(1, math.floor(sell * F.IncomeShare + 0.5)), sell = sell }
end

function WarehouseUi.values(entry: Entry): Values
	local e: any = entry
	local fallback: Values? = nil
	local function fallen(): Values
		if not fallback then
			fallback = guess(entry)
		end
		return fallback :: Values
	end
	local rarity = rarityName(e.rarity) or ask(RULES.rarity, entry, rarityName) or fallen().rarity
	-- (8.0 merge: the server's state entries carry `income` and `price`: server/Collection.luau, CollectionRules.view)
	local perMinute = amount(e.perMinute) or amount(e.income) or ask(RULES.perMinute, entry, amount) or fallen().perMinute
	local sell = amount(e.sell) or amount(e.price) or ask(RULES.sell, entry, amount) or fallen().sell
	-- (8.0.1: the $/min as it is: a cheap piece's $0.2 no longer rounded to $0, and the best earners sorted on it)
	return { rarity = rarity, perMinute = perMinute, sell = math.floor(sell + 0.5) }
end

-- "+$0.2/min": a piece's (or the stock's) $ a minute as the stands' tags write it (a tenth under $10).
function WarehouseUi.rate(perMinute: number): string
	return `+{WarehouseLayout.money(perMinute)}/min`
end

local function nameOf(entry: Entry): string
	if type(entry.name) == "string" and entry.name ~= "" then
		return entry.name
	end
	local def = catalogue(entry.item)
	return if def then def.name else entry.item
end

local function emojiOf(entry: Entry): string
	local def = catalogue(entry.item)
	return if def and type(def.icon) == "string" then def.icon else "📦"
end

local function percent(entry: Entry): string
	return `{math.floor(math.clamp(tonumber(entry.condition) or 1, 0, 1) * 100 + 0.5)}%`
end

-- ── The layout (pure) ───────────────────────────────────────────────────────

function WarehouseUi.layout(W: number, H: number, touch: boolean): Layout
	local margin = if touch then PICK.TouchMargin else PICK.Margin
	local scale = if touch
		then math.clamp(math.min(W / 860, H / 380), 0.8, Ui.MaxScale)
		else math.max(Ui.scaleFor(Vector2.new(W, H)), 0.7)
	local w = math.floor(math.min(PICK.Width, (W - 2 * margin) / scale))
	local h = math.floor(math.min(PICK.Height, (H - 2 * margin) / scale))
	local pad = if touch then 10 else 16
	local finger = math.ceil(Ui.MinTouch / scale)
	local chips = if touch then finger else 30
	local gap = PICK.Gap
	local button = if touch then math.max(PICK.Button, finger) else PICK.Button
	local top = if touch then math.max(HEADER, button + 8) else HEADER -- (8.2: FILL BEST & co. a finger's size)
	local header = top + MARKET_H -- (8.3: the market's line under them)
	local gridY = header + chips + 8
	local gridW = w - 2 * pad
	local area = gridW - SCROLLBAR - 2
	local least = if touch then PICK.TileTouch else PICK.Tile
	local cols = math.max(1, math.floor((area + gap) / (least + gap)))
	local tileW = math.floor((area - (cols - 1) * gap) / cols)
	local picture = math.floor(tileW * (if touch then PICK.PictureTouch else PICK.Picture))
	return {
		touch = touch,
		scale = scale,
		x = math.floor((W - w * scale) / 2),
		y = math.floor((H - h * scale) / 2),
		w = w,
		h = h,
		pad = pad,
		header = header,
		market = top,
		chips = chips,
		close = if touch then math.max(40, finger) else 40,
		gridX = pad,
		gridY = gridY,
		gridW = gridW,
		gridH = h - gridY - pad,
		cols = cols,
		tileW = tileW,
		tileH = picture + TILE_TEXT + button,
		picture = picture,
		gap = gap,
		button = button,
	}
end

-- The tiles (1-based, in order) a grid scrolled to `top` shows: the first and the last (partly shown counts).
local function visibleRange(layout: Layout, top: number): (number, number)
	local rowH = layout.tileH + layout.gap
	local first = math.max(0, math.floor(top / rowH))
	local last = math.max(first, math.floor((top + layout.gridH - 1) / rowH))
	return first * layout.cols + 1, (last + 1) * layout.cols
end

-- ── The 3D pictures ─────────────────────────────────────────────────────────

local models: { [string]: any } = {} -- a model a piece and variant (false: its build failed)
local modelOrder: { string } = {}
local INERT = { "SurfaceGui", "BillboardGui", "Smoke", "ParticleEmitter", "Fire", "Sparkles", "Light", "Sound", "Attachment", "WeldConstraint", "Constraint", "JointInstance", "BaseScript", "ProximityPrompt" }

local function template(entry: Entry): any
	local key = `{entry.item}#{math.max(1, math.floor(tonumber(entry.variant) or 1))}`
	local known = models[key]
	if known ~= nil then
		return if known == false then nil else known
	end
	local ok, made = pcall(FurnitureLooks.build, entry.item, tonumber(entry.variant) or 1)
	if not ok or not made then
		warn(`[WarehouseUi] {key}: {made}`)
		models[key] = false
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
	models[key] = model
	table.insert(modelOrder, key)
	while #modelOrder > HUD.MaxModels do
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

local function mount(tile: Tile)
	local model = template(tile.entry)
	if not model then
		return
	end
	local look = Config.ItemModel
	local view = Ui.make("ViewportFrame", {
		Name = "Model",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(look.Ambient[1], look.Ambient[2], look.Ambient[3]),
		LightColor = Color3.fromRGB(look.LightColor[1], look.LightColor[2], look.LightColor[3]),
		LightDirection = vec(look.LightDirection),
		ZIndex = 2,
	}, tile.picture)
	view:SetAttribute("Emoji", emojiOf(tile.entry))
	local copy = model:Clone()
	copy.Parent = view
	local lo, hi = ItemLooks.bounds(copy)
	local size = tile.picture.Size
	local eye, centre = ItemLooks.frame(lo, hi, math.max(0.2, size.X.Offset / math.max(1, size.Y.Offset)), false)
	local camera = Ui.make("Camera", { FieldOfView = look.Fov }, view)
	camera.CFrame = CFrame.lookAt(vec(eye), vec(centre))
	view.CurrentCamera = camera
	tile.view = view
	tile.emoji.Visible = false
	liveViews += 1
end

local function unmount(tile: Tile)
	if tile.view then
		tile.view:Destroy()
		tile.view = nil
		tile.emoji.Visible = true
		liveViews -= 1
	end
end

-- The tiles on screen get their 3D picture (at most MaxViews at once), the others give theirs back.
local function refreshViews()
	local layout = plan
	if not (layout and grid) then
		return
	end
	local first, last = visibleRange(layout, grid.CanvasPosition.Y)
	for _, tile in tiles do
		if tile.index < first or tile.index > last then
			unmount(tile)
		end
	end
	if HUD.Models == false then
		return
	end
	for _, tile in tiles do
		if liveViews >= HUD.MaxViews then
			break
		end
		if tile.index >= first and tile.index <= last and not tile.view then
			mount(tile)
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

function WarehouseUi.views(): number
	return liveViews
end

-- ── Sending ─────────────────────────────────────────────────────────────────

local sentAt: { [string]: number } = {}

-- One request a piece at most every 0.6 s (a double tap is one request).
local function send(message: { [string]: any }): boolean
	local key = `{message.kind}:{tostring(message.uid)}`
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
	local notify = WarehouseUi.notify
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
local fillGrid: (scrollY: number) -> () -- 8.2: the grid alone (draw's last step)
local refill: () -> () -- 8.2: only the grid again (the search box's typing)

local function screen(): (number, number)
	local size = Ui.screenSize()
	return size.X, size.Y
end

local function ensureGui(): any
	if gui then
		return gui
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = Ui.make("ScreenGui", {
		Name = "WarehouseUi",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		DisplayOrder = 7, -- (with the move's cards: over the HUD and the touch buttons)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)
	return gui
end

local function closeQuestion()
	if question then
		question:Destroy()
		question = nil
		local from = questionFrom -- (8.3: the gamepad's selection back on what asked, not lost with the question)
		questionFrom = nil
		if from and from.Parent and not Ui.gamepadSelection() then
			Ui.gamepadFocus(from)
		end
	end
end

function WarehouseUi.close()
	if not mode then
		return
	end
	mode = nil
	closeQuestion()
	for _, tile in tiles do
		unmount(tile)
	end
	table.clear(tiles)
	if card then
		Ui.gamepadRelease(gui)
		card:Destroy()
		card = nil
	end
	grid, plan, panel, listed = nil, nil, nil, nil
	table.clear(actionButtons)
	search = "" -- (8.2: the search ends with the window; the sort stays)
	shownKey = ""
end

function WarehouseUi.isOpen(): boolean
	return mode ~= nil
end

function WarehouseUi.showing(): string?
	local open = mode
	return if not open then nil elseif open.stand then "picker" else "stock"
end

-- 8.3: your warehouse's level (the player attribute, 1 … 5); 4 until the server sets it (a plain Plot's: the stands
-- of before 8.3).
local function warehouseLevel(): number
	local level = Players.LocalPlayer:GetAttribute(Config.SandboxUpgrades.WarehouseAttribute)
	return if type(level) == "number" then level else 4
end

-- 8.2: does a piece of this item stand on stand i (an upgrade's small stand holds no bed)? As the server's
-- Collection.display asks it (a piece without a catalogue entry: yes); each stand and item asked once (8.3: a level).
local fitsKnown: { [string]: boolean } = {}
local function fitsStand(stand: number, item: string): boolean
	local level = warehouseLevel()
	local key = `{level}|{stand}|{item}`
	local known = fitsKnown[key]
	if known == nil then
		local def = catalogue(item)
		local ok, yes = pcall(WarehouseLayout.fits, stand, if def then def.size else nil, level)
		known = def == nil or (ok and yes == true)
		fitsKnown[key] = known
	end
	return known :: boolean
end

-- 8.2: a stock entry as shared/StockPlan.luau reads it (its values: the server's, else the rules', else the guess).
local function pieceOf(entry: Entry, values: Values): StockPlan.Piece
	local e: any = entry
	local condition = math.clamp(tonumber(entry.condition) or 1, 0, 1)
	local broken = if type(e.broken) == "boolean" then e.broken else condition <= Config.Collection.BrokenAt + 1e-6
	return { uid = entry.uid, item = entry.item, stand = entry.stand, got = tonumber(entry.got) or 0, rarity = values.rarity, income = values.perMinute, price = values.sell, broken = broken, condition = condition, base = amount(e.base) }
end

-- 8.3: the market the window shows (nil: none sent yet).
local function marketNow(): Market.View?
	local state = current
	return if state then state.market else nil
end

-- 8.3: the price the server sent for a piece (only that one is sent back as `expect`; nil for a guessed one).
local function served(entry: Entry): number?
	local price = amount((entry :: any).price)
	return if price then math.floor(price + 0.5) else nil
end

-- What the open window lists: the pieces (the picker: not on show), each with its values; in the sort toggle's order
-- (8.2; the best earners first unless you chose another), in the picker the pieces too big for its stand last.
type Row = { entry: Entry, values: Values, piece: StockPlan.Piece, fits: boolean }
-- What the open window's grid lists (draw keeps it for fillGrid): the rows, the picker's stand, the empty words' counts.
type Listed = { rows: { Row }, stand: number?, total: number, onShow: number, loaded: boolean }
local function rows(state: State, stand: number?): { Row }
	local list: { Row } = {}
	for _, entry in state.stock do
		if not (stand and entry.stand) then
			local values = WarehouseUi.values(entry)
			table.insert(list, { entry = entry, values = values, piece = pieceOf(entry, values), fits = stand == nil or fitsStand(stand, entry.item) })
		end
	end
	local order = StockPlan.order(sortBy)
	table.sort(list, function(a: Row, b: Row): boolean
		if a.fits ~= b.fits then
			return a.fits
		end
		return order(a.piece, b.piece)
	end)
	return list
end

-- The pieces of a list (StockPlan's).
local function piecesOf(list: { Row }): { StockPlan.Piece }
	local out: { StockPlan.Piece } = table.create(#list)
	for _, row in list do
		table.insert(out, row.piece)
	end
	return out
end

local function pieces(n: number): string
	return `{n} {if n == 1 then "piece" else "pieces"}`
end

-- A question's shade over the card (a tap on it closes the question) and its box in the middle (boxW × boxH).
local function questionBox(name: string, boxW: number, boxH: number): (any, any)
	local shade = Ui.make("TextButton", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		ZIndex = 20,
	}, panel)
	Ui.corner(shade, Config.UiKit.Corner)
	shade.Activated:Connect(closeQuestion)
	local box = Ui.make("Frame", {
		Name = `{name}Box`,
		Size = UDim2.fromOffset(boxW, boxH),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 21,
		SelectionGroup = true, -- (8.3: the gamepad's selection stays in the question)
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, shade)
	questionFrom = Ui.gamepadSelection()
	Ui.corner(box, 12)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, box)
	question = shade
	return shade, box
end

-- A SELL question over the card: the question ("SELL FOR $Y?"), what (one line), a hint, CANCEL and SELL (onYes).
type Ask = { question: string, what: string, hint: string, onYes: () -> () }
local function confirm(ask: Ask)
	closeQuestion()
	local layout = plan
	if not (panel and layout) then
		return
	end
	local boxW = math.min(400, layout.w - 2 * layout.pad)
	local _, box = questionBox("Confirm", boxW, 108 + layout.button)
	Ui.label(box, ask.question, UDim2.new(1, -32, 0, 26), { Name = "Question", Position = UDim2.fromOffset(16, 16), Font = Theme.HeadingFont, TextSize = 20, TextColor3 = K.text, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	Ui.label(box, ask.what, UDim2.new(1, -32, 0, 18), { Name = "What", Position = UDim2.fromOffset(16, 46), TextSize = 13, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	Ui.label(box, ask.hint, UDim2.new(1, -32, 0, 16), { Name = "Hint", Position = UDim2.fromOffset(16, 66), TextSize = 12, TextColor3 = C.faint, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	local half = math.floor((boxW - 32 - 8) / 2)
	local cancel = CardKit.bigButton(box, { name = "Cancel", text = "CANCEL", kind = "shut", height = layout.button, textSize = 14, z = 22, onClick = closeQuestion })
	cancel.Size = UDim2.fromOffset(half, layout.button)
	cancel.Position = UDim2.new(0, 16, 1, -(16 + layout.button))
	local onYes = ask.onYes
	local sell = CardKit.bigButton(box, { name = "ConfirmSell", text = "SELL", kind = "primary", height = layout.button, textSize = 14, z = 22, onClick = function()
		closeQuestion()
		onYes()
	end })
	sell.Size = UDim2.fromOffset(half, layout.button)
	sell.Position = UDim2.new(0, 24 + half, 1, -(16 + layout.button))
	Ui.gamepadFocus(sell)
end

-- 8.3: why the market prices a piece of this kind as it does now (nil: it doesn't touch it).
local function marketHint(entry: Entry): string?
	local market = marketNow()
	local line = Market.demandLine(market, entry.item, nameOf(entry))
	if line then
		return line
	end
	local tag = Market.tag(market, entry.item)
	if tag == "hot" then
		return `🔥 Hot today: it sells for {Market.factor(Config.Market.HotSell)}, earns {Market.factor(Config.Market.HotIncome)} on show.`
	elseif tag == "cold" then
		return `❄ Cold today: it sells for {Market.factor(Config.Market.ColdSell)}. Keep it on show till tomorrow?`
	end
	return nil
end

-- SELL's question for one piece: "SELL FOR $Y?", the piece, CANCEL and SELL (8.3: the price it showed sent with it).
local function askSell(row: Row)
	local values, entry = row.values, row.entry
	confirm({
		question = `SELL FOR {Ui.money(values.sell)}?`,
		what = `{nameOf(entry)} · {string.upper(values.rarity)} · {percent(entry)}`,
		hint = marketHint(entry) or (if entry.stand then "It comes off its stand." else `On show it would earn {WarehouseUi.rate(values.perMinute)}.`),
		onYes = function()
			send({ kind = "sell", uid = entry.uid, expect = served(entry) })
			for _, tile in tiles do
				if tile.entry == entry then
					for _, button in tile.buttons do
						button.Text = "…"
						button.Active = false
						button.AutoButtonColor = false
					end
				end
			end
		end,
	})
end

-- ── 8.2: the STOCK list's bulk buttons ──────────────────────────────────────

local FILTER_WORDS: { [string]: { line: string, none: string, hint: string } } = {
	common = { line = "every Common piece", none = "No Common piece in your stock", hint = "Pieces on show stay on their stands." },
	broken = { line = "they earn nothing on show", none = "No broken piece in your stock", hint = "Broken pieces sell for scrap. Pieces on show stay." },
	duplicates = { line = "keeps the best of each item", none = "One of each: no duplicates", hint = "The best of each item stays. Pieces on show stay." },
}

-- A bulk button waits for the server's answer (the next state draws it again; 8.2 review: no answer in a moment, a
-- request the remote's limit dropped, and it is drawn again anyway: never stuck at "…").
local function waiting(name: string)
	local button = actionButtons[name]
	if button then
		button.Text = "…"
		button.Active = false
		button.AutoButtonColor = false
		task.delay(2.5, function()
			if mode and actionButtons[name] == button and button.Parent and button.Text == "…" then
				shownKey = ""
				draw(true)
			end
		end)
	end
end

-- The names of a few pieces ("Chair, Kitchen Radio +3 more") for a question's line.
local function someNames(list: { StockPlan.Piece }, byUid: { [any]: Entry }): string
	local names: { string } = {}
	for index, piece in list do
		if index > 3 then
			break
		end
		local entry = byUid[piece.uid]
		table.insert(names, if entry then nameOf(entry) else tostring(piece.item))
	end
	local more = #list - #names
	return table.concat(names, ", ") .. (if more > 0 then ` +{more} more` else "")
end

-- 💰 SELL…'s menu over the card: ALL COMMON, ALL BROKEN, DUPLICATES (how many, their price), CANCEL; each asks first.
local function sellMenu()
	closeQuestion()
	local layout, state = plan, current
	if not (panel and layout and state) then
		return
	end
	local all = rows(state, nil)
	local list = piecesOf(all)
	local byUid: { [any]: Entry } = {}
	for _, row in all do
		byUid[row.entry.uid] = row.entry
	end
	local market = state.market -- (8.3: the totals at the market's prices)
	local optionH = math.max(layout.button, 40) + 8
	local boxW = math.min(420, layout.w - 2 * layout.pad)
	local boxH = 16 + 26 + 24 + #StockPlan.Filters * (optionH + 8) + layout.button + 16
	local _, box = questionBox("Menu", boxW, boxH)
	Ui.label(box, "SELL…", UDim2.new(1, -32, 0, 26), { Name = "Question", Position = UDim2.fromOffset(16, 16), Font = Theme.HeadingFont, TextSize = 20, TextColor3 = K.text, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	Ui.label(box, "Many pieces at once. Pieces on show stay.", UDim2.new(1, -32, 0, 16), { Name = "Hint", Position = UDim2.fromOffset(16, 44), TextSize = 12, TextColor3 = C.faint, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22 })
	local y = 16 + 26 + 24
	local first: any = nil
	for _, id in StockPlan.Filters do
		local chosen = StockPlan.toSell(list, id)
		local total = StockPlan.price(chosen, market)
		local words = FILTER_WORDS[id]
		-- 8.3: the total the server will pay is sent with the request (only when every price in it is the server's)
		local expect: number? = total
		for _, piece in chosen do
			local entry = byUid[piece.uid]
			if not (entry and served(entry)) then
				expect = nil
			end
		end
		local hint = if market and total < StockPlan.price(chosen) then `Market: each next piece of a kind sells {math.floor(Config.Market.Drop * 100 + 0.5)}% lower.` else words.hint
		local some = #chosen > 0
		local option = Ui.make("TextButton", {
			Name = `Sell_{id}`,
			Size = UDim2.fromOffset(boxW - 32, optionH),
			Position = UDim2.fromOffset(16, y),
			BackgroundColor3 = K.row,
			BackgroundTransparency = if some then 0 else 0.5, -- (nothing to sell: faint)
			BorderSizePixel = 0,
			AutoButtonColor = some,
			Text = "",
			ZIndex = 22,
		}, box)
		Ui.corner(option, TILE_CORNER)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.7 }, option)
		local inner = boxW - 32 - 24
		local priceText = if some then Ui.money(total) else ""
		local priceW = if some then CardKit.width(priceText, 16, Theme.DisplayFont) + 4 else 0
		Ui.label(option, StockPlan.filterName(id), UDim2.fromOffset(inner - priceW - 8, 18), { Name = "What", Position = UDim2.new(0, 12, 0.5, -18), Font = Theme.HeadingFont, TextSize = 14, TextColor3 = if some then K.text else K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23 })
		Ui.label(option, if some then `{pieces(#chosen)} · {words.line}` else words.none, UDim2.fromOffset(inner - priceW - 8, 16), { Name = "Count", Position = UDim2.new(0, 12, 0.5, 2), TextSize = 12, TextColor3 = if some then K.secondary else C.faint, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23 })
		if some then
			Ui.label(option, priceText, UDim2.fromOffset(priceW, 22), { Name = "Price", Position = UDim2.new(1, -12, 0.5, -11), AnchorPoint = Vector2.new(1, 0), Font = Theme.DisplayFont, TextSize = 16, TextColor3 = C.money, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 23 })
			first = first or option
		end
		option.Activated:Connect(function()
			if not some then
				return
			end
			CardKit.click()
			confirm({
				question = `SELL {string.upper(pieces(#chosen))} FOR {Ui.money(total)}?`,
				what = someNames(chosen, byUid),
				hint = hint,
				onYes = function()
					-- (8.4 review: + the pieces it listed: the server sells exactly those, or nothing if the stock changed)
					local uids = table.create(#chosen)
					for _, piece in chosen do
						table.insert(uids, piece.uid)
					end
					if send({ kind = "sellmany", filter = id, expect = expect, uids = uids }) then
						waiting("SellMenu")
					end
				end,
			})
		end)
		y += optionH + 8
	end
	local cancel = CardKit.bigButton(box, { name = "Cancel", text = "CANCEL", kind = "shut", height = layout.button, textSize = 14, z = 22, onClick = closeQuestion })
	cancel.Size = UDim2.fromOffset(boxW - 32, layout.button)
	cancel.Position = UDim2.new(0, 16, 1, -(16 + layout.button))
	Ui.gamepadFocus(first or cancel)
end

-- Why ⭐ FILL BEST has nothing to do (the server would say the same).
local function fillWhy(list: { StockPlan.Piece }, stands: number): string
	if #StockPlan.free(list, stands) == 0 then
		return "Every display stand you have already shows a piece."
	end
	for _, piece in list do
		if piece.stand == nil and piece.broken ~= true and piece.income > 0 then
			return "What's in your stock is too big for your free small stands."
		end
	end
	return "Nothing in your stock would earn on a stand. Bring more home from a move!"
end

-- The STOCK list's header buttons, right of the title (left of ✕): ⭐ FILL BEST, 💰 SELL…, ↩ TAKE ALL DOWN; grey with
-- nothing to do (a tap says why). Returns the left edge they leave the title.
local ACTIONS = {
	{ name = "FillBest", text = "⭐ FILL BEST", short = "⭐ BEST" },
	{ name = "SellMenu", text = "💰 SELL…", short = "💰 SELL…" },
	{ name = "TakeAllDown", text = "↩ TAKE ALL DOWN", short = "↩ ALL DOWN" },
}
local TITLE_ROOM = 200 -- px the title keeps at least (else the buttons' short words)
local function drawActions(frame: any, layout: Layout, state: State, all: { Row }): number
	local list = piecesOf(all)
	local shown, inStock = 0, 0
	for _, piece in list do
		if piece.stand ~= nil then
			shown += 1
		else
			inStock += 1
		end
	end
	local canFill = #StockPlan.fill(list, state.stands, fitsStand) > 0
	local live: { [string]: boolean } = { FillBest = canFill, SellMenu = inStock > 0, TakeAllDown = shown > 0 }
	local why: { [string]: string } = {
		FillBest = fillWhy(list, state.stands),
		SellMenu = "Your stock is empty: nothing to sell.",
		TakeAllDown = "Nothing is on show.",
	}
	local size = if layout.touch then 13 else 12
	local right = layout.w - 6 - layout.close - 8
	local function widths(short: boolean): ({ number }, number)
		local out: { number } = {}
		local total = 0
		for index, action in ACTIONS do
			local w = CardKit.width(if short then action.short else action.text, size, Theme.HeadingFont) + 20
			if layout.touch then
				w = math.max(w, layout.button)
			end
			out[index] = w
			total += w + (if index > 1 then 6 else 0)
		end
		return out, total
	end
	local short = false
	local sizes, total = widths(false)
	if right - total < layout.pad + TITLE_ROOM then
		short = true
		sizes, total = widths(true)
	end
	local x = right - total
	local y = math.max(4, 6 + (layout.close - layout.button) / 2)
	for index, action in ACTIONS do
		local name = action.name
		local on = live[name]
		local button = CardKit.bigButton(frame, {
			name = name,
			text = if short then action.short else action.text,
			kind = if on and name == "FillBest" then "good" else "shut",
			height = layout.button,
			textSize = size,
			onClick = function()
				if not on then
					toast(why[name])
				elseif name == "FillBest" then
					if send({ kind = "fillbest" }) then
						waiting(name)
					end
				elseif name == "SellMenu" then
					sellMenu()
				elseif send({ kind = "undisplayall" }) then
					waiting(name)
				end
			end,
		})
		button.Size = UDim2.fromOffset(sizes[index], layout.button)
		button.Position = UDim2.fromOffset(x, y)
		button.AutoButtonColor = on
		if on and name ~= "FillBest" then
			button.TextColor3 = K.text -- (quiet: raised, white words)
		elseif not on then
			button.TextTransparency = 0.45 -- (nothing to do: grey, a tap says why)
		end
		button:SetAttribute("Live", on)
		actionButtons[name] = button
		x += sizes[index] + 6
	end
	return right - total
end

-- A tile's button: kind a CardKit face ("good": DISPLAY), or "quiet" (SELL, TAKE DOWN: raised, white words).
local function tileButton(parent: any, name: string, text: string, kind: string, layout: Layout, onClick: () -> ()): any
	local quiet = kind == "quiet"
	local button = CardKit.bigButton(parent, { name = name, text = text, kind = if quiet then "shut" else kind, height = layout.button, textSize = if layout.touch then 14 else 12, z = 3, onClick = onClick })
	if quiet then
		button.TextColor3 = K.text
	end
	return button
end

local function drawTile(parent: any, row: Row, index: number, layout: Layout, stand: number?)
	local entry, values = row.entry, row.values
	local tooBig = stand ~= nil and not row.fits -- 8.2: greyed, "Too big for this stand"
	local dim = if tooBig then 0.45 else 0 -- (its words' transparency)
	local col, line = (index - 1) % layout.cols, (index - 1) // layout.cols
	local accent = WarehouseUi.Rarity[values.rarity] or WarehouseUi.Rarity.common
	local w = layout.tileW
	local frame = Ui.make("Frame", {
		Name = `Tile_{tostring(entry.uid)}`,
		Size = UDim2.fromOffset(w, layout.tileH),
		Position = UDim2.fromOffset(col * (w + layout.gap), line * (layout.tileH + layout.gap)),
		BackgroundColor3 = K.row,
		BackgroundTransparency = if tooBig then 0.5 else 0,
		BorderSizePixel = 0,
	}, parent)
	frame:SetAttribute("Uid", tostring(entry.uid))
	frame:SetAttribute("TooBig", tooBig)
	Ui.corner(frame, TILE_CORNER)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = if tooBig then K.line else accent, Thickness = 1, Transparency = if tooBig or values.rarity == "common" then 0.8 else 0.45 }, frame)
	local picture = Ui.make("Frame", {
		Name = "Picture",
		Size = UDim2.fromOffset(w - 12, layout.picture),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = K.charcoal,
		BorderSizePixel = 0,
		ClipsDescendants = true,
	}, frame)
	Ui.corner(picture, 8)
	local emoji = Ui.label(picture, emojiOf(entry), UDim2.fromScale(1, 1), { Name = "Emoji", TextSize = math.floor(layout.picture * 0.55), TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 1 })
	Ui.make("Frame", { Name = "RarityBar", Size = UDim2.new(1, 0, 0, 4), Position = UDim2.new(0, 0, 1, -4), BackgroundColor3 = accent, BorderSizePixel = 0, ZIndex = 3 }, picture)
	if entry.stand then
		local on = `ON STAND {entry.stand}`
		local ribbon = Ui.label(picture, on, UDim2.fromOffset(CardKit.width(on, 11, Theme.HeadingFont) + 16, 20), {
			Name = "OnStand",
			Position = UDim2.fromOffset(6, 6),
			BackgroundColor3 = C.rushFace,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextColor3 = C.rushInk,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
		Ui.corner(ribbon, 10)
	end
	-- 8.3: the market's tags on the picture, under ON STAND n: 🔥 HOT ×1.4 / ❄ COLD, 📉 −10% (the player's demand)
	local tagY = if entry.stand then 30 else 6
	local market = marketNow()
	local tags: { { string } } = {}
	local badge = Market.badge(market, entry.item)
	if badge then
		table.insert(tags, { "MarketTag", badge, Market.tag(market, entry.item) or "" })
	end
	local down = Market.percent(market, entry.item)
	if down > 0 then
		table.insert(tags, { "DemandTag", `📉 −{down}%`, "drop" })
	end
	for _, tag in tags do
		local hot, cold = tag[3] == "hot", tag[3] == "cold"
		local pill = Ui.label(picture, tag[2], UDim2.fromOffset(CardKit.width(tag[2], 11, Theme.HeadingFont) + 14, 20), {
			Name = tag[1],
			Position = UDim2.fromOffset(6, tagY),
			BackgroundColor3 = if hot then HOT_FACE elseif cold then COLD_FACE else K.charcoal,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextColor3 = if hot then HOT_INK elseif cold then COLD_INK else K.warn,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		})
		Ui.corner(pill, 10)
		tagY += 24
	end
	local inner = w - 20
	if tooBig then
		-- 8.2: a veil over its picture and the words (wrapped: they fit a narrow tile too)
		local veil = Ui.make("Frame", { Name = "TooBig", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 5 }, picture)
		Ui.label(veil, "Too big for this stand", UDim2.new(1, -16, 1, -12), { Name = "TooBigWords", Position = UDim2.fromOffset(8, 6), Font = Theme.HeadingFont, TextSize = 13, TextColor3 = K.text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 })
	end
	local y = 6 + layout.picture + 6
	Ui.label(frame, string.upper(values.rarity), UDim2.fromOffset(math.floor(inner * 0.55), 14), { Name = "Rarity", Position = UDim2.fromOffset(10, y), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = accent, TextTransparency = dim, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left })
	Ui.label(frame, percent(entry), UDim2.fromOffset(math.floor(inner * 0.45), 14), { Name = "Condition", Position = UDim2.new(1, -10, 0, y), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = K.secondary, TextTransparency = dim, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right })
	y += 16
	Ui.label(frame, nameOf(entry), UDim2.fromOffset(inner, 18), { Name = "PieceName", Position = UDim2.fromOffset(10, y), Font = Theme.HeadingFont, TextSize = 14, TextColor3 = K.text, TextTransparency = dim, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	y += 20
	-- the one big number: what it earns a minute on show; the price under it
	Ui.label(frame, WarehouseUi.rate(values.perMinute), UDim2.fromOffset(inner, 22), { Name = "PerMinute", Position = UDim2.fromOffset(10, y), Font = Theme.DisplayFont, TextSize = 18, TextColor3 = if tooBig then K.secondary else C.money, TextTransparency = dim, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	y += 22
	Ui.label(frame, `Sell {Ui.money(values.sell)}`, UDim2.fromOffset(inner, 16), { Name = "SellPrice", Position = UDim2.fromOffset(10, y), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = K.secondary, TextTransparency = dim, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	-- the buttons: DISPLAY / SELL (the picker), TAKE DOWN / SELL (a piece on show), SELL (the stock list)
	local buttons: { any } = {}
	local first: any = nil
	local by = layout.tileH - 8 - layout.button
	if stand and tooBig then
		-- 8.2: TOO BIG instead of DISPLAY, grey; a tap says where it goes
		first = tileButton(frame, "Display", "TOO BIG", "shut", layout, function()
			toast(`Your {nameOf(entry)} is too big for small stand {stand}: show it on stands 1 – {WarehouseLayout.count(warehouseLevel())}.`)
		end)
		first.AutoButtonColor = false
		first.TextTransparency = 0.3
	elseif stand then
		first = tileButton(frame, "Display", "DISPLAY", "good", layout, function()
			if send({ kind = "display", uid = entry.uid, stand = stand }) then
				WarehouseUi.close()
			end
		end)
	elseif entry.stand then
		first = tileButton(frame, "TakeDown", "TAKE DOWN", "quiet", layout, function()
			if send({ kind = "undisplay", uid = entry.uid }) then
				for _, button in buttons do
					button.Text = "…"
					button.Active = false
				end
			end
		end)
	end
	local sell = tileButton(frame, "Sell", "SELL", "quiet", layout, function()
		askSell(row)
	end)
	if first then
		-- (the first as wide as its words need, at least its share; SELL keeps room for its own)
		local size = if layout.touch then 14 else 12
		local need = CardKit.width(first.Text, size, Theme.HeadingFont) + 18
		local sellNeed = CardKit.width("SELL", size, Theme.HeadingFont) + 16
		local firstW = math.floor(math.clamp(need, (inner - 6) * 0.5, inner - 6 - sellNeed))
		first.Size = UDim2.fromOffset(firstW, layout.button)
		first.Position = UDim2.fromOffset(10, by)
		sell.Size = UDim2.fromOffset(inner - 6 - firstW, layout.button)
		sell.Position = UDim2.fromOffset(16 + firstW, by)
		table.insert(buttons, first)
	else
		sell.Size = UDim2.fromOffset(inner, layout.button)
		sell.Position = UDim2.fromOffset(10, by)
	end
	table.insert(buttons, sell)
	table.insert(tiles, { entry = entry, index = index, picture = picture, emoji = emoji, view = nil, buttons = buttons })
end

-- The filter chips: ALL and each rarity you have (with its count), the open one lit.
local function drawChips(parent: any, list: { Row }, layout: Layout)
	local counts: { [string]: number } = {}
	for _, row in list do
		counts[row.values.rarity] = (counts[row.values.rarity] or 0) + 1
	end
	local chips: { { string } } = { { "all", `ALL {#list}` } }
	for _, name in WarehouseUi.Rarities do
		if counts[name] then
			table.insert(chips, { name, `{string.upper(name)} {counts[name]}` })
		end
	end
	local x = layout.pad
	for _, pair in chips do
		local id, text = pair[1], pair[2]
		local on = id == filter
		local ink = if id == "all" then K.text else WarehouseUi.Rarity[id]
		local chip = CardKit.chip(parent, {
			name = `Filter_{id}`,
			text = text,
			face = if on then K.raised else K.row,
			ink = if on then K.text else ink,
			stroke = if on then ink else K.line,
			lit = on,
			faint = 0.8,
			onClick = function()
				filter = id
				draw(false)
			end,
		})
		local chipW = chip.Size.X.Offset + 10
		chip.Size = UDim2.fromOffset(if layout.touch then math.max(chipW, layout.chips) else chipW, layout.chips)
		chip.Position = UDim2.fromOffset(x, layout.header)
		chip.TextSize = if layout.touch then 13 else 12
		if on then
			Ui.make("Frame", { Name = "Underline", Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 1, -2), BackgroundColor3 = K.red, BorderSizePixel = 0 }, chip)
		end
		x += chip.Size.X.Offset + 6
	end
	-- 8.2: the sort toggle at the right ($/MIN → VALUE → NEWEST → RARITY), the search box left of it (a computer)
	local textSize = if layout.touch then 13 else 12
	local sortText = `SORT · {StockPlan.sortLabel(sortBy)}`
	local sortW = math.max(CardKit.width(`SORT · {StockPlan.sortLabel("rarity")}`, textSize, Theme.HeadingFont), CardKit.width(sortText, textSize, Theme.HeadingFont)) + 20
	if layout.touch then
		sortW = math.max(sortW, layout.chips)
	end
	local right = layout.w - layout.pad
	local sort = CardKit.chip(parent, {
		name = "Sort",
		text = sortText,
		face = K.row,
		ink = K.text,
		stroke = K.line,
		faint = 0.6,
		onClick = function()
			sortBy = StockPlan.nextSort(sortBy)
			draw(false)
		end,
	})
	sort.Size = UDim2.fromOffset(sortW, layout.chips)
	sort.Position = UDim2.fromOffset(right - sortW, layout.header)
	sort.TextSize = textSize
	right -= sortW + 8
	if not layout.touch and right - SEARCH_W >= x + 2 then
		local box = Ui.make("TextBox", {
			Name = "Search",
			Size = UDim2.fromOffset(SEARCH_W, layout.chips),
			Position = UDim2.fromOffset(right - SEARCH_W, layout.header),
			BackgroundColor3 = K.row,
			BorderSizePixel = 0,
			ClearTextOnFocus = false,
			Text = search,
			PlaceholderText = "🔍 Search",
			PlaceholderColor3 = C.faint,
			Font = Theme.Font,
			TextSize = 13,
			TextColor3 = K.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClipsDescendants = true,
		}, parent)
		Ui.corner(box, layout.chips // 2)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, box)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			local text = box.Text
			if #text > MAX_SEARCH then
				box.Text = string.sub(text, 1, MAX_SEARCH)
				return
			end
			if text ~= search then
				search = text
				refill()
			end
		end)
	end
end

local function emptyWords(stand: number?, total: number, shown: number): string
	if string.match(search, "%S") then
		return `No piece here matches "{search}".`
	elseif filter ~= "all" then
		return `No {string.upper(filter)} pieces here.`
	elseif total == 0 then
		return "Your stock is empty. Bring things home from a move: unload your van at your warehouse."
	elseif stand and shown == total then
		return "Every piece you own is on show. Bring more home from a move."
	end
	return "Nothing here."
end

local function stateKey(state: State?, layout: Layout): string
	local parts = { `{layout.w}x{layout.h}@{layout.scale}`, filter, sortBy, search }
	local open = mode
	table.insert(parts, if open then tostring(open.stand) else "-")
	if state then
		for _, entry in state.stock do
			table.insert(parts, `{tostring(entry.uid)}:{entry.item}:{tostring(entry.variant)}:{tostring(entry.condition)}:{tostring(entry.stand)}:{tostring(entry.name)}`)
		end
		table.insert(parts, tostring(state.income))
		table.insert(parts, tostring(state.stands)) -- (8.2: FILL BEST's free stands)
		local market = state.market
		if market then
			-- 8.3: the day's kinds and the player's demand (the tags, the prices' reasons)
			table.insert(parts, `{market.day}:{table.concat(market.hot, ",")}:{table.concat(market.cold, ",")}`)
			local kinds: { string } = {}
			for item, demand in market.demand do
				table.insert(kinds, `{item}={demand.n}/{demand.sold}`)
			end
			table.sort(kinds)
			table.insert(parts, table.concat(kinds, ","))
		end
	else
		table.insert(parts, "none")
	end
	return table.concat(parts, "|")
end

draw = function(keepScroll: boolean)
	local open = mode
	if not open then
		return
	end
	local W, H = screen()
	local layout = WarehouseUi.layout(W, H, Ui.touchLayout())
	if filter ~= "all" and current then
		local has = false
		for _, entry in current.stock do
			if not (open.stand and entry.stand) and WarehouseUi.values(entry).rarity == filter then
				has = true
				break
			end
		end
		if not has then
			filter = "all" -- (the last piece of that rarity went: back to ALL)
		end
	end
	local key = stateKey(current, layout)
	if card and key == shownKey then
		return -- (nothing it shows changed: no redraw, a tap is never lost)
	end
	shownKey = key
	local scroll = if keepScroll and grid then grid.CanvasPosition else Vector2.zero
	local selected = Ui.gamepadSelection() -- (8.3: the gamepad's selection, selected again once drawn)
	local heldName, heldTile = nil, nil
	if card and selected and selected:IsDescendantOf(card) then
		local parent = selected.Parent
		heldName = selected.Name
		heldTile = if parent and string.sub(parent.Name, 1, 5) == "Tile_" then parent.Name else nil
	end
	closeQuestion()
	for _, tile in tiles do
		unmount(tile)
	end
	table.clear(tiles)
	if card then
		card:Destroy()
	end
	grid = nil
	local root = ensureGui()
	plan = layout
	-- a shade over the world (the touch buttons too): a tap beside the card closes it; Modal frees the mouse
	card = Ui.make("TextButton", {
		Name = "WarehouseShade",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Selectable = false,
		Modal = true,
	}, root)
	card.Activated:Connect(WarehouseUi.close)
	local frame = Ui.make("Frame", {
		Name = "Picker",
		Size = UDim2.fromOffset(layout.w, layout.h),
		Position = UDim2.fromOffset(layout.x, layout.y),
		BackgroundColor3 = K.charcoal,
		BackgroundTransparency = Theme.WindowTransparency,
		BorderSizePixel = 0,
		Active = true,
		SelectionGroup = true, -- (8.3: the gamepad's selection stays in the window)
		SelectionBehaviorUp = Enum.SelectionBehavior.Stop,
		SelectionBehaviorDown = Enum.SelectionBehavior.Stop,
		SelectionBehaviorLeft = Enum.SelectionBehavior.Stop,
		SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
	}, card)
	panel = frame
	Ui.make("UIScale", { Name = "Scale", Scale = layout.scale }, frame)
	Ui.corner(frame, Config.UiKit.Corner)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.rule, Thickness = 1 }, frame)
	-- the header: the title, a line under it, the ✕
	local stand = open.stand
	local state = current
	local title = if stand then `STAND {stand} · CHOOSE A PIECE` else "YOUR STOCK"
	Ui.label(frame, title, UDim2.new(1, -(layout.pad * 2 + layout.close + 8), 0, 24), { Name = "Title", Position = UDim2.fromOffset(layout.pad, 10), Font = Theme.HeadingFont, TextSize = 18, TextColor3 = K.text, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local all: { Row } = if state then rows(state, nil) else {}
	local onShow = 0
	for _, row in all do
		if row.entry.stand then
			onShow += 1
		end
	end
	local earning = if state then state.income else 0
	local subtitle = if not state then "Loading your stock…"
		elseif stand then "On show it earns money every minute you play."
		else `{#all} {if #all == 1 then "piece" else "pieces"} · {onShow} on show{if earning > 0 then ` · {WarehouseUi.rate(earning)}` else ""}`
	Ui.label(frame, subtitle, UDim2.new(1, -(layout.pad * 2 + layout.close + 8), 0, 16), { Name = "Subtitle", Position = UDim2.fromOffset(layout.pad, 33), TextSize = 12, TextColor3 = K.secondary, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	local market = if state then state.market else nil
	if state and market then
		-- 8.3: "Today's market: 🔥 … · ❄ … · new in 5 h" under the title's line and the bulk buttons
		local left = market.left - (os.clock() - state.marketAt)
		Ui.label(frame, Market.line(market, left), UDim2.new(1, -layout.pad * 2, 0, 16), { Name = "Market", Position = UDim2.fromOffset(layout.pad, layout.market), Font = Theme.HeadingFont, TextSize = 12, TextColor3 = HOT_INK, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left })
	end
	local close = Ui.closeButton(frame, WarehouseUi.close)
	close.Size = UDim2.fromOffset(layout.close, layout.close)
	close.Position = UDim2.new(1, -6, 0, 6)
	close.AnchorPoint = Vector2.new(1, 0)
	-- 8.2: the STOCK list's bulk buttons in the header (the title and its line keep the room left of them)
	table.clear(actionButtons)
	if state and not stand then
		local left = drawActions(frame, layout, state, all)
		local room = math.max(40, left - 8 - layout.pad)
		for _, name in { "Title", "Subtitle" } do
			local label = frame:FindFirstChild(name)
			if label then
				label.Size = UDim2.fromOffset(room, label.Size.Y.Offset)
			end
		end
	end
	-- the pieces, the chips over them, the grid
	local list: { Row } = if state and stand then rows(state, stand) else all
	listed = { rows = list, stand = stand, total = #all, onShow = onShow, loaded = state ~= nil }
	drawChips(frame, list, layout)
	fillGrid(scroll.Y)
	local firstTile = tiles[1]
	local again: any = nil -- (8.3: the same tile's button, or the header's, chip or sort)
	if heldName then
		local tile = if heldTile then grid and grid:FindFirstChild(heldTile) else nil
		again = if heldTile then (if tile then tile:FindFirstChild(heldName) else nil) else frame:FindFirstChild(heldName)
	end
	Ui.gamepadFocus(again or (if firstTile then firstTile.buttons[1] else close))
end

-- The grid (and its empty words) for what the window lists now: the rarity chip's, the search's (8.2: typing in the
-- search box draws only this again, so the box keeps its focus).
fillGrid = function(scrollY: number)
	local layout, frame, now = plan, panel, listed
	if not (layout and frame and now) then
		return
	end
	for _, tile in tiles do
		unmount(tile)
	end
	table.clear(tiles)
	if grid then
		grid:Destroy()
		grid = nil
	end
	local empty = frame:FindFirstChild("Empty")
	if empty then
		empty:Destroy()
	end
	local shown: { Row } = {}
	for _, row in now.rows do
		if (filter == "all" or row.values.rarity == filter) and StockPlan.matches(nameOf(row.entry), search) then
			table.insert(shown, row)
		end
	end
	local lines = math.ceil(#shown / layout.cols)
	local made = Ui.make("ScrollingFrame", {
		Name = "Grid",
		Size = UDim2.fromOffset(layout.gridW, layout.gridH),
		Position = UDim2.fromOffset(layout.gridX, layout.gridY),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = SCROLLBAR,
		ScrollBarImageColor3 = K.line,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		CanvasSize = UDim2.fromOffset(0, math.max(0, lines * (layout.tileH + layout.gap) - layout.gap)),
		CanvasPosition = Vector2.new(0, math.clamp(scrollY, 0, math.max(0, lines * (layout.tileH + layout.gap) - layout.gap - layout.gridH))),
	}, frame)
	grid = made
	for index, row in shown do
		drawTile(made, row, index, layout, now.stand)
	end
	if now.loaded and #shown == 0 then
		Ui.label(frame, emptyWords(now.stand, now.total, now.onShow), UDim2.fromOffset(layout.gridW - 40, 60), { Name = "Empty", Position = UDim2.fromOffset(layout.gridX + 20, layout.gridY + 30), TextSize = 15, TextColor3 = K.secondary, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
	end
	made:GetPropertyChangedSignal("CanvasPosition"):Connect(queueRefresh)
	refreshViews()
end

refill = function()
	if not (mode and plan) then
		return
	end
	shownKey = stateKey(current, plan :: Layout) -- (what it shows now: a state that changes nothing draws nothing)
	fillGrid(0)
end

local function setState(raw: any)
	local stock: { Entry } = {}
	if type(raw.stock) == "table" then
		for _, entry in raw.stock do
			if type(entry) == "table" and (type(entry.uid) == "string" or type(entry.uid) == "number") and type(entry.item) == "string" then
				table.insert(stock, entry)
			end
		end
	end
	local previous = current
	local idle = amount(raw.idle) -- (8.3 economy: idle, the stands' share)
	local state: State = { stock = stock, income = amount(raw.income) or 0, stands = amount(raw.stands) or 0, market = Market.readView(raw.market), marketAt = os.clock(), idle = if idle and idle < 1 then idle else nil }
	current = state
	for _, fn in listeners do
		task.spawn(fn, state, previous)
	end
	if mode then
		draw(true)
	end
end

local function open(stand: number?)
	local was = mode ~= nil
	mode = { stand = stand }
	shownKey = ""
	closeQuestion()
	if not was then
		local onOpen = WarehouseUi.onOpen
		if onOpen then
			onOpen()
		end
	end
	draw(false)
	if not current and remote then
		send({ kind = "state" })
	end
end

function WarehouseUi.openPicker(stand: number)
	if type(stand) ~= "number" then
		return
	end
	open(math.floor(stand))
end

function WarehouseUi.openStock()
	open(nil)
end

function WarehouseUi.toggleStock()
	if WarehouseUi.showing() == "stock" then
		WarehouseUi.close()
	else
		WarehouseUi.openStock()
	end
end

function WarehouseUi.state(): State?
	return current
end

function WarehouseUi.sorting(): string
	return sortBy
end

function WarehouseUi.search(): string
	return search
end

function WarehouseUi.onState(fn: (State, State?) -> ())
	table.insert(listeners, fn)
end

local function onEvent(message: any)
	if type(message) ~= "table" then
		return
	end
	local kind = message.kind
	if kind == "state" then
		setState(message)
	elseif kind == "pick" then
		local stand = tonumber(message.stand)
		if stand then
			WarehouseUi.openPicker(stand)
		end
	elseif kind == "sold" then
		local money = amount(message.money) or 0
		toast(`Sold {if type(message.name) == "string" then message.name else "a piece"} · +{Ui.money(money)}`)
	elseif kind == "bulk" then
		-- 8.2: FILL BEST's and TAKE ALL DOWN's answer
		local n = math.floor(amount(message.count) or 0)
		if message.action == "fillbest" and n > 0 then
			local income = amount(message.income)
			toast(`⭐ {pieces(n)} put on show{if income and income > 0 then ` · {WarehouseUi.rate(income)}` else ""}`)
		elseif message.action == "undisplayall" and n > 0 then
			toast(`↩ {pieces(n)} back in your stock`)
		end
	end
end

local function sandboxOn(): boolean
	local sandbox = (Config :: any).Sandbox
	return type(sandbox) == "table" and sandbox.On == true
end

local function findRules(): any
	local ok, found = pcall(function(): any
		local module = Shared:FindFirstChild("CollectionRules") :: ModuleScript?
		return if module then require(module) :: any else nil
	end)
	return if ok then found else nil
end

function WarehouseUi.start()
	if started or not sandboxOn() then
		return
	end
	started = true
	if WarehouseUi.Rules == nil then
		WarehouseUi.Rules = findRules()
	end
	-- ESC, the gamepad's B and the Roblox menu: the question first, then the window
	local function back()
		if question then
			closeQuestion()
		elseif mode then
			WarehouseUi.close()
		end
	end
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) and not UserInputService:GetFocusedTextBox() then
			back()
		end
	end)
	GuiService.MenuOpened:Connect(back)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if mode then
				draw(true)
			end
		end)
	end
	task.spawn(function()
		local ok, found = pcall(Net.get, "Collection")
		if not ok then
			warn(`[WarehouseUi] no Collection remote: {found}`)
			return
		end
		remote = found
		found.OnClientEvent:Connect(onEvent)
		found:FireServer({ kind = "state" })
	end)
end

return WarehouseUi
