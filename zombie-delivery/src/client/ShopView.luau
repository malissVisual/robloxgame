--!strict
-- 6.18 wave 2, a list screen in the UI kit's look (the owner: "I need it unified so the phone looks like that [6.17's
-- JOBS], and the other popups too"; design/ui-kit/README.md): the shops' counters (client/ShopWindow.luau), the
-- phone's SHOP (client/ShopApp.luau), BAG & ITEMS (client/BagUi.luau), GARAGE (client/GarageUi.luau, PhoneApps) and
-- STYLE (client/StyleApp.luau) give it their items and it draws them the same way:
--   * on top the tabs as chips (CardKit.tabs: Tab_<id>) and the state chips (your cash, YOUR ROOM, the slots), in the
--     phone popup's header strip when they fit there (`bar`), else a row heading the body;
--   * the HERO card (shared/ShopPick.luau hero: the screen's current item, else the savings goal while this screen
--     sells it, else the best thing you can buy now, else the cheapest one to save up for): its picture or icon, the
--     name, the PRICE big (green: you can buy it now; dim: not yet, with a bar of your money toward it), one facts
--     line, a ribbon (★ YOUR GOAL, BEST BUY, SAVE UP) and the one big button (BUY $X, EQUIP, USE …; grey with its
--     words when it can't act: a tap says why);
--   * beside it (a body CardLayout.side wide) or under it, a compact row an item: its picture, name, one fact, the
--     price big (green, dim; "🔒 LV 9" in place of the action while locked; the locked ones last) and a round action
--     (its short word: BUY, USE, EQUIP …) or "›";
--   * a tap on a row (or the hero's ⓘ) opens the item's details: "‹ BACK", its hero card with its button, the stats
--     and the description, and its other actions as chips (BUY 5). A screen may make a row's tap pick the item
--     instead (onPick: GARAGE shows that car in the hero, STYLE tries the look on).
-- Returns the gamepad's first stop (the hero's button, else the first row). Presentation only: every action is the
-- caller's (its remote and its server path).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local CardLayout = require(Shared.CardLayout)
local ShopPick = require(Shared.ShopPick)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local CardKit = require(script.Parent.CardKit)

local K = Theme.Contract
local C = CardKit.Color
local KIT = Config.UiKit
local ShopView = {}

-- One action: its words on the big button (`text`), on a row's round action (`short`, default "BUY"), whether it works
-- now (`on`), the button's kind (CardKit.Buttons: primary, gold, good, warn, shut), what a press says while it can't
-- (`why`), what it does (`run`), and a name for its button (the checks find it by name).
export type Act = { text: string, short: string?, on: boolean, kind: string?, why: string?, run: (() -> ())?, name: string? }

-- One item of a screen (see the header). `price` is the big number in money; `value` another big value ("×2", "📦 4");
-- neither: no big number (a thing you own). `lock` the short words of a lock ("🔒 LV 9"). `lines` the details' words.
export type Item = {
	id: string,
	name: string,
	picture: CardKit.Picture,
	fact: string,
	price: number?,
	value: string?,
	valueColor: Color3?,
	lock: string?,
	accent: Color3?,
	tag: string?,
	owned: boolean?,
	current: boolean?,
	forSale: boolean?, -- sold here (BUY now, or once you have the money / stand at the counter)
	special: boolean?, -- a reward, an exclusive: gold
	act: Act?,
	more: { Act }?,
	lines: { string }?,
	ribbon: string?,
	rowName: string?, -- the row's name (default Item_<id>)
	actionName: string?, -- its round action's name (default Add)
	decorate: ((row: any) -> ())?,
}

-- A screen (see the header): its items and what heads them. `key` remembers the open details per screen; `side` the
-- hero beside the rows; `room` what shows of the body without scrolling (the hero's height); `hero` false: no hero.
export type Screen = {
	key: string,
	items: { Item },
	money: number,
	goal: string?, -- the savings goal's name (6.14 Readiness)
	hero: boolean?,
	side: boolean,
	room: number,
	order: number?,
	tabs: CardKit.Tabs?,
	chips: { CardKit.Chip }?,
	bar: (() -> (any, number))?, -- the phone popup's header strip and its room (PhonePopup.bar)
	note: string?, -- one short line over the cards ("Walk in to buy")
	noteColor: Color3?,
	section: string?, -- over the rows ("4 MORE")
	foot: string?, -- one short line under the rows
	empty: string?, -- no items: these words
	redraw: () -> (),
	toast: ((text: string) -> ())?,
	heroName: string?,
	heroArt: ((card: any, item: Item) -> ())?, -- draws on the hero (the garage's car, STYLE's preview)
	onPick: ((item: Item) -> ())?, -- a row's tap (instead of its details)
}

-- The item whose details show, per screen key.
ShopView.opened = {} :: { [string]: string }

-- Back to a screen's list (its details closed): a shop opened afresh.
function ShopView.home(key: string)
	ShopView.opened[key] = nil
end

local function run(act: Act, toast: ((text: string) -> ())?)
	if act.on and act.run then
		(act.run :: () -> ())()
	elseif act.why and toast then
		toast(act.why)
	end
end

local function entryOf(item: Item, money: number): ShopPick.Entry
	local act = item.act
	return {
		name = item.name,
		price = item.price,
		buyable = act ~= nil and act.on and item.price ~= nil and not item.owned,
		forSale = item.forSale,
		locked = item.lock ~= nil,
		owned = item.owned,
		current = item.current,
	}
end

-- The big value of an item and its colour (see the header).
local function valueOf(item: Item, money: number): (string?, Color3)
	local entry = entryOf(item, money)
	local tone = ShopPick.tone(entry, money)
	local color = if item.valueColor then item.valueColor
		elseif item.special then C.gold
		elseif tone == "money" then C.money
		elseif tone == "none" then C.money
		else C.dim
	if item.value then
		return item.value, color
	end
	if item.price and not item.owned then
		return Ui.money(item.price), color
	end
	return nil, color
end

-- A row's edge: owned / current green, a special gold, locked grey, buyable now red (the action), else amber (saving).
local function accentOf(item: Item, money: number): Color3
	if item.accent then
		return item.accent
	elseif item.special then
		return C.gold
	elseif item.lock then
		return C.grey
	elseif item.owned or item.current then
		return K.good
	end
	local tone = ShopPick.tone(entryOf(item, money), money)
	return if tone == "money" then K.red elseif tone == "dim" then K.warn else C.grey
end

local function find(items: { Item }, id: string): Item?
	for _, item in items do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- The tabs and the state chips (see the header). Returns the next layout order in the body.
local function head(list: Instance, screen: Screen, order: number): number
	local chips: { CardKit.Chip } = screen.chips or {}
	if screen.tabs == nil and #chips == 0 then
		return order
	end
	local row = Ui.make("Frame", { Name = "ShopHead", Size = UDim2.new(1, 0, 0, KIT.Chip + 4), BackgroundTransparency = 1, LayoutOrder = order })
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, row)
	local width = 0
	local tabs = screen.tabs
	if tabs then
		local spec = table.clone(tabs)
		spec.order = 1
		local strip, made = CardKit.tabs(row, spec)
		local tabsW = 0
		for _, chip in made do
			tabsW += chip.Size.X.Offset + 6
		end
		strip.Size = UDim2.new(0, tabsW, 1, 0)
		width += tabsW + 8
	end
	for index, chip in chips do
		local spec = table.clone(chip)
		spec.order = 10 + index
		local made = CardKit.chip(row, spec)
		width += made.Size.X.Offset + 8
	end
	local bar = screen.bar
	if bar then
		local strip, room = bar()
		if strip and width <= (tonumber(room) or 0) then
			row.Size = UDim2.fromScale(1, 1)
			row.Parent = strip
			return order
		end
	end
	row.Parent = list
	return order + 1
end

-- The hero card of an item (`inside`: the details' own card, no ⓘ). Returns its parts.
local function heroCard(parent: Instance, screen: Screen, item: Item, height: number, inside: boolean): CardKit.HeroParts
	local money = screen.money
	local value, color = valueOf(item, money)
	local act = item.act
	local entry = entryOf(item, money)
	local saving = item.price ~= nil and not item.owned and item.lock == nil and money < (item.price or 0)
	local ribbon = item.ribbon
	if ribbon == nil and not inside then
		if screen.goal and item.name == screen.goal and not item.owned then
			ribbon = "★ YOUR GOAL"
		elseif entry.buyable and ShopPick.tone(entry, money) == "money" then
			ribbon = "BEST BUY"
		elseif item.forSale and saving then
			ribbon = "SAVE UP"
		end
	end
	local function open()
		ShopView.opened[screen.key] = item.id
		screen.redraw()
	end
	local more = not inside and (item.lines ~= nil or item.more ~= nil)
	local parts = CardKit.hero(parent, {
		name = if inside then "ItemHero" else (screen.heroName or "Hero"),
		height = height,
		stroke = if item.special or ribbon == "★ YOUR GOAL" then C.gold else (item.accent or K.line),
		strong = item.special == true,
		picture = item.picture,
		shut = item.lock ~= nil,
		title = string.upper(item.name),
		tag = item.tag,
		value = value or "",
		valueColor = color,
		facts = item.fact,
		bar = if saving then { share = ShopPick.share(entry, money), color = C.money } else nil,
		action = if act then {
			name = act.name or "HeroAction",
			text = act.text,
			kind = if act.on then (act.kind or "primary") else "shut", -- (6.18 review: a button that only says why looks shut)
			onClick = function()
				run(act, screen.toast)
			end,
		} else nil,
		ribbon = if ribbon then { text = ribbon, face = if ribbon == "★ YOUR GOAL" then C.gold elseif ribbon == "BEST BUY" then K.good else K.raised, ink = if ribbon == "SAVE UP" then K.text else C.goldInk } else nil,
		onOpen = if more then open else nil,
		onDetails = if more then open else nil,
	})
	parts.card:SetAttribute("Item", item.id)
	if item.picture.face and not item.picture.image then
		CardKit.shade(parts.card, true) -- (a colour fills it: a paint's, a look's: the words keep their dark foot)
	end
	local art = screen.heroArt
	if art then
		art(parts.card, item)
	end
	return parts
end

-- One compact row (see the header).
local function itemRow(parent: Instance, screen: Screen, item: Item, order: number): CardKit.RowParts
	local money = screen.money
	local value, color = valueOf(item, money)
	local act = item.act
	local word = if act and act.on and item.lock == nil then (act.short or "BUY") else nil
	local made = CardKit.row(parent, {
		name = item.rowName or `Item_{item.id}`,
		order = order,
		accent = accentOf(item, money),
		picture = item.picture,
		emojiSize = 26,
		shut = item.lock ~= nil,
		tag = item.tag,
		title = string.upper(item.name),
		facts = item.fact,
		value = value,
		valueColor = color,
		action = if item.lock then nil elseif word then word else "›",
		lock = item.lock,
		onAction = if word and act then function()
			run(act, screen.toast)
		end else nil,
		decorate = item.decorate,
		onOpen = function()
			local pick = screen.onPick
			if pick then
				pick(item)
				return
			end
			ShopView.opened[screen.key] = item.id
			screen.redraw()
		end,
	})
	made.row:SetAttribute("Item", item.id)
	if item.actionName and made.action then
		made.action.Name = item.actionName
	end
	return made
end

local function line(parent: Instance, text: string, order: number, color: Color3?): any
	return Ui.label(parent, text, UDim2.new(1, 0, 0, 0), {
		Name = "Line",
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Font = Theme.Font,
		TextSize = 14,
		TextColor3 = color or K.secondary,
		TextWrapped = true,
	})
end

-- The details of an item (see the header). Returns the gamepad's first stop.
local function details(list: Instance, screen: Screen, item: Item, order: number): any
	local back = Ui.make("TextButton", {
		Name = "Back",
		Size = UDim2.fromOffset(110, 34),
		BackgroundColor3 = K.raised,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "‹ BACK",
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.text,
		LayoutOrder = order + 1,
	}, list)
	Ui.corner(back, 8)
	back.Activated:Connect(function()
		CardKit.click()
		ShopView.opened[screen.key] = nil
		screen.redraw()
	end)
	local height = CardLayout.heroHeight(screen.room - 44)
	local _, left, right = CardKit.columns(list, { name = "ItemDetails", order = order + 2, side = screen.side, hero = true, heroHeight = height })
	local parts = heroCard(left, screen, item, height, true)
	local n = 0
	local lines: { string } = item.lines or {}
	for _, text in lines do
		n += 1
		line(right, text, n)
	end
	local more = item.more
	if more and #more > 0 then
		local row = Ui.make("Frame", { Name = "More", Size = UDim2.new(1, 0, 0, KIT.Chip + 12), BackgroundTransparency = 1, LayoutOrder = n + 1 }, right)
		Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, row)
		for index, act in more do
			local chip = CardKit.chip(row, { name = act.name or `More{index}`, text = act.text, order = index, face = if act.on then K.raised else K.row, ink = if act.on then K.text else K.secondary, stroke = K.line, onClick = function()
				run(act, screen.toast)
			end })
			chip.Size = UDim2.fromOffset(chip.Size.X.Offset + 12, KIT.Chip + 10)
		end
	end
	return parts.action or back
end

-- Draws a screen into `list` (a vertical list; the caller cleared it) from layout order `screen.order` on. Returns
-- the gamepad's first stop (the hero's button, else the first row; nil without either).
function ShopView.draw(list: Instance, screen: Screen): any
	local order = head(list, screen, screen.order or 0)
	local opened = ShopView.opened[screen.key]
	if opened then
		local item = find(screen.items, opened)
		if item then
			return details(list, screen, item, order)
		end
		ShopView.opened[screen.key] = nil -- (it went: sold out of the list, another tab)
	end
	if screen.note then
		line(list, screen.note, order + 1, screen.noteColor).Name = "Note"
	end
	local items = screen.items
	if #items == 0 then
		line(list, screen.empty or "Nothing here yet.", order + 2).Name = "Empty"
		return nil
	end
	local money = screen.money
	local entries: { ShopPick.Entry } = {}
	for _, item in items do
		table.insert(entries, entryOf(item, money))
	end
	local heroAt = if screen.hero == false then nil else ShopPick.hero(entries, money, screen.goal)
	local height = CardLayout.heroHeight(screen.room - (if screen.note then 30 else 0) - (if order > (screen.order or 0) then KIT.Chip + 10 else 0))
	local _, left, right = CardKit.columns(list, { name = "ShopCards", order = order + 3, side = screen.side, hero = heroAt ~= nil, heroHeight = height })
	local focus: any = nil
	if heroAt then
		local parts = heroCard(left, screen, items[heroAt], height, false)
		focus = parts.action
	end
	local count = #items - (if heroAt then 1 else 0)
	if screen.section and count > 0 then
		CardKit.sectionHeader(right, { name = "MoreHead", text = screen.section, order = 0 })
	end
	local n = 0
	for _, index in ShopPick.order(entries) do
		if index == heroAt then
			continue
		end
		n += 1
		local item = items[index]
		local ok, made = pcall(itemRow, right, screen, item, n)
		if not ok then
			warn(`[ShopView] a row failed: {made}`)
		elseif focus == nil then
			focus = made.action or made.row
		end
	end
	if screen.foot then
		line(right, screen.foot, n + 1).Name = "Foot"
	end
	return focus
end

-- A vehicle's picture (Config.Cars id): a bike's icon once uploaded, else an emoji of its kind.
local VEHICLE_EMOJI: { [string]: string } = {
	boxtruck = "🚚", movingtruck = "🚚", livestock = "🚚", fueltruck = "🚚", freighttruck = "🚛", armored = "🚚", armorvan = "🚐",
	pickup = "🛻", monster = "🛻", muscle = "🏎️", courier = "🚗", bus = "🚌", ambulance = "🚑", icecream = "🍦",
	bike = "🚲", cargobike = "🚲", scooter = "🛴",
}
function ShopView.vehicle(def: Config.CarDef?): CardKit.Picture
	if def == nil then
		return { emoji = "🚶" }
	end
	local emoji = if def.stand then "🛴" else (VEHICLE_EMOJI[def.style or ""] or (if def.bike then "🚲" else "🚐"))
	return { icon = Icons.bike(def.id), emoji = emoji }
end

-- The body's size at the window's design scale (a Hud window's scrolling body under its UIScale), else the fallback.
function ShopView.measure(body: Instance, fallback: Vector2): Vector2
	local size = (body :: any).AbsoluteSize
	if typeof(size) ~= "Vector2" or size.X <= 0 then
		return fallback
	end
	local scale = 1
	local node: Instance? = body
	while node do
		local found = node:FindFirstChildOfClass("UIScale")
		if found then
			scale *= (found :: UIScale).Scale
		end
		node = node.Parent
	end
	return Vector2.new(size.X / math.max(scale, 0.01), size.Y / math.max(scale, 0.01))
end

return ShopView
