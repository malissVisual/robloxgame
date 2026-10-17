--!strict
-- 6.12: the courier phone's STYLE app (MORE → STYLE; client/Phone.luau draws it in its centred popup with the phone's
-- own kit, OrdersUi.Kit): the wardrobe of Config.Cosmetics' looks, bought from the clerks at the shops. Looks only, no
-- advantage.
--   * Two tabs: COURIER (hats, jackets, the Courier Vest's colour, the bag's colour) and VEHICLE (wraps for the cars,
--     vans and trucks, paint for the bikes and the E-Scooter, decals). Under them the live 3D preview
--     (client/StylePreview.luau: your courier or the vehicle you have out, the item you look at put on it), then a
--     section a slot (what you wear in it) and a card an item: its colours, its name, OWNED / WEARING / its price (or
--     🏆 REWARD: not for sale, given later by tasks, events, passes; 🔒 its level), a line about it, TRY (the preview)
--     and BUY · $price (at a shop that sells it; elsewhere where it is sold, "AT WRENCH GARAGE"), WEAR or TAKE OFF.
--   * BUY / WEAR / TAKE OFF ask the server (the Style remote: server/StyleWear.luau checks everything and takes the
--     money); what you can't do yet only says why (your level, your money, a reward). A purchase plays "cash" when the
--     state brings it back. The cards follow the state (StyleApp.changed: only what the app shows).
--   * The clerks (the owner: "things are bought only from the NPCs in the shops, for the vibe"): the phone is the
--     wardrobe. BUY · $price only while you stand at one of the item's shops (Style.shopAt, the server's test, on your
--     character); elsewhere an item for sale says where it is sold ("AT WRENCH GARAGE"): a press sets the GPS there
--     (the SHOP app's path, host.gps) and says who sells it. What you own is worn and taken off anywhere, TRY previews
--     anywhere. Where you stand is part of StyleApp.key: the phone's ticker (StyleApp.tick, twice a second while the
--     app shows) draws the cards again when you walk up to a shop or away. A clerk's "Style" prompt opens the app on
--     their tab (server/ShopClerks.luau → the Style remote's ("open", tab), client/Phone.luau; StyleApp.show).
--   * Keys while the app is open (bound with ContextActionService only then): TAB, the gamepad's L1 / R1 switch the
--     tab; ↑ / ↓ pick the item before / after (the preview follows, the list scrolls to it); ENTER does its main
--     action. A gamepad's selection moving over a card's buttons previews that card.
-- 6.18 wave 2, the UI kit's look (the owner: "I need it unified so the phone looks like that [6.17's JOBS], and the
-- other popups too"; design/ui-kit/README.md, client/CardKit.luau):
--   * the tabs are chips (Tab_courier, Tab_vehicle: the open one lit, its red Underline) in the popup's header strip
--     when they fit;
--   * the HERO is the look you try: the live 3D preview fills it, its name, its PRICE big (green while you can buy it
--     here; WEARING / OWNED / 🏆 REWARD), one line under it (the caption: who sells it away from its shop), and the one
--     big button: its main action (BUY · $X, WEAR, TAKE OFF, AT WRENCH GARAGE: the GPS, REWARD ONLY);
--   * beside it (a wide popup) or under it, a section a slot ("Hats · your own") and a compact row a look: its two
--     colours as the thumb, its name, one line, its price big, and a round action (BUY, WEAR, OFF, 📍 where it is sold;
--     the lock's words "🔒 LV 6", "🏆 REWARD" say why on a press); a tap on the row TRIES it (the hero follows);
--   * the keys and the gamepad as before (a row's selection tries it on).
-- Presentation only: the server decides every purchase and every look.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Style = require(Shared.Style)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local OrdersUi = require(script.Parent.OrdersUi)
local PhoneApps = require(script.Parent.PhoneApps)
local StylePreview = require(script.Parent.StylePreview)
local Sounds = require(script.Parent.Sounds)
local CardKit = require(script.Parent.CardKit) -- 6.18 wave 2: the UI kit

local K = Theme.Contract
local StyleApp = {}

local ACTION = "ZombieDeliveryStyleKeys"
local TABS: { { string } } = { { "courier", "COURIER" }, { "vehicle", "VEHICLE" } }

-- The open tab and the item previewed in each (StyleApp.pick[tab]: an id; nil: the worn one, else the first).
StyleApp.tab = "courier"
StyleApp.pick = {} :: { [string]: string }

type Host = PhoneApps.Host

local player = Players.LocalPlayer
local shown: { host: Host?, preview: Instance?, row: Instance?, cards: { [string]: Instance }, bound: boolean, key: string, hero: any, caption: any } = {
	host = nil,
	preview = nil,
	hero = nil, -- 6.18 wave 2: the hero card's parts (CardKit.hero), filled again when another look is tried
	caption = nil, -- its line under the price (PreviewCaption)
	row = nil, -- the tabs row drawn last (only its going frees the keys)
	cards = {},
	bound = false,
	key = "",
}
local bought: { [string]: boolean } = {} -- asked to buy, not owned yet (the "cash" sound when the state has it)

local function wardrobe(state: any): Style.Wardrobe
	return Style.sanitize(if type(state) == "table" then state.style else nil)
end

local function level(): number
	return math.max(1, math.floor(tonumber(player:GetAttribute("Level")) or 1))
end

local function moneyOf(state: any): number
	return if type(state) == "table" then tonumber(state.money) or 0 else 0
end

local function color3(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Every item of the open tab, in the app's order (↑ / ↓ go through them).
local function itemsOf(tab: string): { Config.CosmeticDef }
	local out: { Config.CosmeticDef } = {}
	for _, slot in Style.slots(tab) do
		for _, def in Style.items(slot.id) do
			table.insert(out, def)
		end
	end
	return out
end

-- The item previewed in the tab: the picked one, else the first worn one, else the first.
local function picked(tab: string, style: Style.Wardrobe): Config.CosmeticDef
	local def = Style.find(StyleApp.pick[tab])
	if def then
		return def
	end
	for _, slot in Style.slots(tab) do
		local worn = Style.worn(style, slot.id)
		if worn then
			return worn
		end
	end
	return itemsOf(tab)[1]
end

local function send(action: string, arg: string)
	Net.get("Style"):FireServer(action, arg)
end

-- Where your character stands (x, z), or nil without one.
local function spot(): (number?, number?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position.X, root.Position.Z
	end
	return nil, nil
end

-- The one of the item's (or the slot's) shops you stand at, or nil.
local function shopHere(item: Config.CosmeticDef | string): string?
	local x, z = spot()
	if x == nil or z == nil then
		return nil
	end
	return Style.shopAt(item, x, z)
end

-- The main action of an item (BUY, WEAR, TAKE OFF), or why it can't be done (a toast).
local function act(def: Config.CosmeticDef, host: Host)
	local state = host.state()
	local style = wardrobe(state)
	local now = Style.state(style, def)
	if now == "wearing" then
		send("unwear", def.slot)
	elseif now == "owned" then
		send("wear", def.id)
	else
		local ok, why = Style.canBuyAt(style, def, moneyOf(state), level(), shopHere(def))
		if not ok and why == "shop" then
			-- away from its shops: the GPS to the one that sells it (as the SHOP app's list), and who that is
			local _, shop = Style.counterFor(def)
			if shop then
				host.gps(shop)
			end
			host.notify(Style.say("where", def))
			return
		elseif not ok then
			host.notify(Style.say(why or "money", def))
			return
		end
		bought[def.id] = true
		send("buy", def.id)
	end
end

-- ── The preview ───────────────────────────────────────────────────────────

local function preview(def: Config.CosmeticDef?)
	local holder = shown.preview
	if not holder or not holder.Parent then
		return
	end
	local caption = shown.caption
	local ok, kind, note = pcall(StylePreview.show, holder, StyleApp.tab, def)
	local text = if def then string.upper(def.name) else ""
	if not ok or kind == "" then
		text = `{text}{if text ~= "" then " · " else ""}{if ok and type(note) == "string" then note else "No preview here."}`
	elseif type(note) == "string" and note ~= "" then
		text = `{text} · {note}`
	elseif def and shown.host and Style.state(wardrobe(shown.host.state()), def) == "sale" and not shopHere(def) then
		text = `{text} · {Style.say("sold", def)}` -- (tried away from its shop: who sells it)
	end
	if caption and caption.Parent then
		caption.Text = text
	end
end

-- Picks an item (TRY, ↑ / ↓, a gamepad's selection): the preview follows, the cards' accents too.
local function pick(def: Config.CosmeticDef, redraw: boolean)
	StyleApp.pick[StyleApp.tab] = def.id
	local host = shown.host
	if redraw and host then
		host.redraw()
		return
	end
	for id, card in shown.cards do
		local on = id == def.id
		local stroke = card:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = if on then 0.7 else 0.82
		end
		local accent = card:FindFirstChild("Accent")
		if on and not accent then
			accent = Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = K.red, BorderSizePixel = 0, ZIndex = 2 }, card)
		end
		if accent and accent:IsA("GuiObject") then
			accent.Visible = on
		end
	end
	local fill = StyleApp.fillHero
	if fill and host then
		fill(def, host)
	end
	preview(def)
end

-- The list scrolls to the picked card (the nearest ScrollingFrame over it).
local function scrollTo(card: Instance)
	task.defer(function()
		local scroller: Instance? = card.Parent
		while scroller and not scroller:IsA("ScrollingFrame") do
			scroller = scroller.Parent
		end
		if not scroller or not card:IsA("GuiObject") then
			return
		end
		local frame = scroller :: ScrollingFrame
		if typeof(frame.CanvasPosition) ~= "Vector2" then
			return
		end
		local top = (card :: GuiObject).AbsolutePosition.Y - frame.AbsolutePosition.Y + frame.CanvasPosition.Y
		local bottom = top + (card :: GuiObject).AbsoluteSize.Y
		local view = frame.AbsoluteSize.Y
		local at = frame.CanvasPosition.Y
		if top < at then
			frame.CanvasPosition = Vector2.new(0, math.max(0, top - 12))
		elseif bottom > at + view then
			frame.CanvasPosition = Vector2.new(0, bottom - view + 12)
		end
	end)
end

-- ── The keys ──────────────────────────────────────────────────────────────

local function switch(tab: string)
	if StyleApp.tab ~= tab then
		StyleApp.tab = tab
		local host = shown.host
		if host then
			host.redraw()
		end
	end
end

local function step(by: number)
	local host = shown.host
	if not host then
		return
	end
	local list = itemsOf(StyleApp.tab)
	local current = picked(StyleApp.tab, wardrobe(host.state()))
	local index = table.find(list, current) or 1
	local nextDef = list[math.clamp(index + by, 1, #list)]
	if nextDef and nextDef ~= current then
		pick(nextDef, false)
		local card = shown.cards[nextDef.id]
		if card then
			scrollTo(card)
		end
	end
end

local function onKey(_: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	local key = input.KeyCode
	if key == Enum.KeyCode.Tab or key == Enum.KeyCode.ButtonL1 or key == Enum.KeyCode.ButtonR1 then
		switch(if StyleApp.tab == "courier" then "vehicle" else "courier")
	elseif key == Enum.KeyCode.Up then
		step(-1)
	elseif key == Enum.KeyCode.Down then
		step(1)
	elseif key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter then
		local host = shown.host
		if host then
			act(picked(StyleApp.tab, wardrobe(host.state())), host)
		end
	end
	return Enum.ContextActionResult.Sink
end

local function bind()
	if shown.bound then
		return
	end
	shown.bound = true
	ContextActionService:BindActionAtPriority(ACTION, onKey, false, Enum.ContextActionPriority.High.Value + 6,
		Enum.KeyCode.Tab, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
end

local function unbind()
	if shown.bound then
		shown.bound = false
		ContextActionService:UnbindAction(ACTION)
	end
end

-- ── Drawing ───────────────────────────────────────────────────────────────

local function tabs(list: Instance, host: Host): number
	local row = Ui.make("Frame", { Name = "StyleTabs", Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 1 })
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, row)
	local strip, made = CardKit.tabs(row, { tabs = TABS, selected = StyleApp.tab, order = 1, onPick = function(id: string)
		switch(id)
	end })
	local width = 0
	for _, chip in made do
		width += chip.Size.X.Offset + 6
	end
	strip.Size = UDim2.new(0, width, 1, 0)
	if not Ui.touchLayout() then
		Ui.label(row, "TAB · ↑ ↓ · ENTER", UDim2.fromOffset(120, 28), { Name = "KeyHint", TextSize = 11, TextColor3 = K.secondary, LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Left })
		width += 128
	end
	-- the row goes with the app (another app, the popup closed): the keys are free again. Only the row drawn last
	-- does it: an older row going later (a redraw with deferred signals, the closing popup's tween while STYLE is
	-- opened again) must not free the keys of the app that shows.
	shown.row = row
	row.Destroying:Connect(function()
		if shown.row == row then
			shown.row = nil
			unbind()
		end
	end)
	-- (6.18 wave 2: in the popup's header strip when they fit, like JOBS' chips; else heading the body)
	local bar, room = host.bar()
	if bar and width <= (tonumber(room) or 0) then
		row.Size = UDim2.fromScale(1, 1)
		row.Parent = bar
		return 1
	end
	row.Parent = list
	return 2
end

-- An item's two colours as its row's thumb (Colour1, Colour2: what the checks find).
local function swatch(def: Config.CosmeticDef): (face: Instance, size: number) -> ()
	return function(slot: Instance, _: number)
		local colours: { { number } } = { def.color }
		if def.trim then
			table.insert(colours, def.trim)
		end
		for n, c in colours do
			local chip = Ui.make("Frame", {
				Name = `Colour{n}`,
				Size = UDim2.fromOffset(if #colours == 1 then 30 else 22, 30),
				Position = UDim2.new(0.5, if #colours == 1 then -15 else (n - 1) * 24 - 23, 0.5, -15),
				BackgroundColor3 = color3(c),
				BorderSizePixel = 0,
			}, slot)
			Ui.corner(chip, 6)
			Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, chip)
		end
	end
end

-- What a look is to you, and its main action's words (the hero's button) and short word (its row's round action).
local function actionOf(def: Config.CosmeticDef, style: Style.Wardrobe, money: number, lvl: number): (string, string, string, boolean)
	local now = Style.state(style, def)
	if now == "wearing" then
		return "TAKE OFF", "OFF", "shut", true
	elseif now == "owned" then
		return "WEAR", "WEAR", "good", true
	elseif now == "reward" then
		return "REWARD ONLY", "🏆 REWARD", "shut", false
	end
	local locked = lvl < (def.level or 1)
	local here = shopHere(def)
	if locked then
		return `BUY · {Style.money(def.price)}`, `🔒 LV {def.level}`, "shut", false
	elseif here then
		local ok = Style.canBuyAt(style, def, money, lvl, here)
		return `BUY · {Style.money(def.price)}`, "BUY", if ok then "primary" else "shut", true
	end
	return Style.atLabel(def), "📍", "shut", true -- (sold at a shop: a press sets the GPS there)
end

-- The big value of a look: WEARING, OWNED, 🏆 REWARD or its price (green while you can buy it here).
local function valueOf(def: Config.CosmeticDef, style: Style.Wardrobe, money: number, lvl: number): (string, Color3)
	local now = Style.state(style, def)
	if now == "wearing" then
		return "WEARING", CardKit.Color.money
	elseif now == "owned" then
		return "OWNED", CardKit.Color.money
	elseif now == "reward" then
		return "🏆 REWARD", CardKit.Color.gold
	end
	local ok = Style.canBuyAt(style, def, money, lvl, shopHere(def))
	return Style.money(def.price), if ok then CardKit.Color.money else CardKit.Color.dim
end

-- The hero shows another look (TRY, ↑ / ↓, a row's selection): its name, its value, its button.
function StyleApp.fillHero(def: Config.CosmeticDef, host: Host)
	local parts = shown.hero
	if not parts or not parts.card or not parts.card.Parent then
		return
	end
	local state = host.state()
	local style = wardrobe(state)
	local money, lvl = moneyOf(state), level()
	local label, _, kind = actionOf(def, style, money, lvl)
	local value, color = valueOf(def, style, money, lvl)
	parts.title.Text = string.upper(def.name)
	parts.value.Text = value
	parts.value.TextColor3 = color
	if parts.action then
		parts.action.Text = label
		CardKit.paint(parts.action, kind)
	end
end

-- A look's compact row (see the header): a tap tries it on.
local function itemRow(parent: Instance, def: Config.CosmeticDef, order: number, host: Host, style: Style.Wardrobe, money: number, lvl: number, selected: boolean)
	local now = Style.state(style, def)
	local _, short, _, on = actionOf(def, style, money, lvl)
	local value, color = valueOf(def, style, money, lvl)
	local locked = short == "🏆 REWARD" or string.sub(short, 1, #"🔒") == "🔒"
	local slot = Style.slot(def.slot)
	local made = CardKit.row(parent, {
		name = `Style_{def.id}`,
		order = order,
		accent = if now == "wearing" then K.good elseif now == "reward" then CardKit.Color.gold elseif locked then CardKit.Color.grey else K.line,
		picture = { glyph = swatch(def) },
		title = string.upper(def.name),
		facts = (if now == "wearing" then "✓ WEARING · " elseif now == "owned" then "✓ OWNED · " else "") .. (if slot then string.upper(slot.name) else ""),
		value = if now == "sale" then value else nil,
		valueColor = color,
		action = if locked then nil else short,
		lock = if locked then short else nil,
		actionFace = if short == "BUY" and on then K.red elseif short == "WEAR" then K.good else nil,
		onAction = function()
			act(def, host)
		end,
		silent = true,
		onOpen = function()
			CardKit.click()
			pick(def, false)
		end,
	})
	local row = made.row
	shown.cards[def.id] = row
	if made.action then
		made.action.Name = "Main"
	end
	if selected then
		Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 2, 1, 0), Position = UDim2.fromOffset(4, 0), BackgroundColor3 = K.red, BorderSizePixel = 0, ZIndex = 3 }, row)
	end
	row.SelectionGained:Connect(function()
		if StyleApp.pick[StyleApp.tab] ~= def.id then
			pick(def, false)
		end
	end)
end

-- The app in the phone's popup (`list`: its body; `wide`: the hero beside the rows).
function StyleApp.render(list: Instance, look: OrdersUi.Kit, host: Host, wide: boolean?)
	shown.host = host
	shown.cards = {}
	local state = host.state()
	local style = wardrobe(state)
	local money, lvl = moneyOf(state), level()
	local tab = StyleApp.tab
	local current = picked(tab, style)
	local order = tabs(list, host)
	bind()
	look.meta(list, `Buy them from {Style.soldBy(tab)}; wear them from here, anywhere. `
		.. (if tab == "courier" then "Looks only: no item changes a number of the game; your own look stays under them."
			else "Looks only, on every vehicle of yours they fit; a lent company vehicle and a ZDC RIDE scooter keep theirs."), order)
	-- the hero: the look you try, the live preview filling it
	local height = CardKit.Layout.heroHeight(host.room() - 40)
	local _, left, right = CardKit.columns(list, { name = "StyleCards", order = order + 1, side = wide == true, hero = true, heroHeight = height })
	local label, _, kind = actionOf(current, style, money, lvl)
	local value, color = valueOf(current, style, money, lvl)
	local parts = CardKit.hero(left, {
		name = "Hero",
		height = height,
		picture = { emoji = "" },
		title = string.upper(current.name),
		value = value,
		valueColor = color,
		facts = "",
		action = { name = "HeroMain", text = label, kind = kind, onClick = function()
			local live = shown.host
			if live then
				act(picked(StyleApp.tab, wardrobe(live.state())), live)
			end
		end },
	})
	shown.hero = parts
	parts.facts.Name = "PreviewCaption"
	parts.facts.TextSize = 12
	parts.facts.TextColor3 = K.secondary
	shown.caption = parts.facts
	local holder = Ui.make("Frame", { Name = "Preview", Size = UDim2.fromScale(1, 1), BackgroundColor3 = K.charcoal, BorderSizePixel = 0, ZIndex = 1, ClipsDescendants = true }, parts.card)
	CardKit.shade(parts.card, true) -- (the preview fills it: the words keep their dark foot)
	shown.preview = holder
	-- a section a slot, a row a look
	local n = 0
	for _, slot in Style.slots(tab) do
		local worn = Style.worn(style, slot.id)
		n += 1
		CardKit.sectionHeader(right, { name = `Slot_{slot.id}`, text = `{slot.name} · {if worn then worn.name else "your own"}`, order = n })
		for _, def in Style.items(slot.id) do
			n += 1
			itemRow(right, def, n, host, style, money, lvl, def == current)
		end
	end
	preview(current)
	local selectedCard = shown.cards[current.id]
	if selectedCard then
		scrollTo(selectedCard)
	end
	shown.key = StyleApp.key(state)
end

-- What the app shows of the state (the wardrobe, what you can afford, your level) and of where you stand (at which
-- slots' shops): a redraw only when it changes.
function StyleApp.key(state: any): string
	local style = wardrobe(state)
	local money, lvl = moneyOf(state), level()
	local parts: { string } = { Style.key(style, { "hat", "jacket", "vest", "bag", "wrap", "bikepaint", "decal" }), `lv{lvl}@` }
	for _, slot in Config.Cosmetics.Slots do
		table.insert(parts, if shopHere(slot.id) then "1" else "0")
	end
	for _, def in Config.Cosmetics.Items do
		local owned = style.owned[def.id] == true
		table.insert(parts, if owned then "o" elseif Style.canBuy(style, def, money, lvl) then "b" else "-")
	end
	return table.concat(parts, "")
end

-- The phone's ticker while STYLE shows (twice a second): you walked up to a shop or away, the cards follow.
function StyleApp.tick()
	local host = shown.host
	if host and shown.row and shown.row.Parent and StyleApp.key(host.state()) ~= shown.key then
		host.redraw()
	end
end

-- A clerk's "Style" prompt (the Style remote's ("open", tab), client/Phone.luau): the app opens on that tab.
function StyleApp.show(tab: any)
	if tab == "courier" or tab == "vehicle" then
		StyleApp.tab = tab
	end
end

-- A new state (Phone.setState): a purchase asked for here plays "cash" once it is yours; true when the open app
-- should be drawn again.
function StyleApp.changed(state: any): boolean
	local style = wardrobe(state)
	for id in bought do
		if style.owned[id] then
			bought[id] = nil
			pcall(function()
				local play = (Sounds :: any).play
				if play then
					play("cash")
				end
			end)
		end
	end
	return StyleApp.key(state) ~= shown.key
end

-- The app closed (the popup went, another app): the keys free, the preview's copy dropped.
function StyleApp.close()
	unbind()
	shown.row = nil
	local holder = shown.preview
	if holder then
		pcall(StylePreview.clear, holder)
	end
	shown.preview = nil
	shown.host = nil
	shown.cards = {}
	shown.hero = nil
	shown.caption = nil
end

return StyleApp
