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

local K = Theme.Contract
local StyleApp = {}

local ACTION = "ZombieDeliveryStyleKeys"
local TABS: { { string } } = { { "courier", "COURIER" }, { "vehicle", "VEHICLE" } }

-- The open tab and the item previewed in each (StyleApp.pick[tab]: an id; nil: the worn one, else the first).
StyleApp.tab = "courier"
StyleApp.pick = {} :: { [string]: string }

type Host = PhoneApps.Host

local player = Players.LocalPlayer
local shown: { host: Host?, preview: Instance?, row: Instance?, cards: { [string]: Instance }, bound: boolean, key: string } = {
	host = nil,
	preview = nil,
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
	local caption = holder.Parent and holder.Parent:FindFirstChild("PreviewCaption")
	local ok, kind, note = pcall(StylePreview.show, holder, StyleApp.tab, def)
	local text = if def then string.upper(def.name) else ""
	if not ok or kind == "" then
		text = `{text}{if text ~= "" then " · " else ""}{if ok and type(note) == "string" then note else "No preview here."}`
	elseif type(note) == "string" and note ~= "" then
		text = `{text} · {note}`
	elseif def and shown.host and Style.state(wardrobe(shown.host.state()), def) == "sale" and not shopHere(def) then
		text = `{text} · {Style.say("sold", def)}` -- (tried away from its shop: who sells it)
	end
	if caption and caption:IsA("TextLabel") then
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

local function tabs(list: Instance)
	local row = Ui.make("Frame", { Name = "StyleTabs", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 1 }, list)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	for index, entry in TABS do
		local id = entry[1]
		local on = id == StyleApp.tab
		local tab = Ui.make("TextButton", {
			Name = `Tab_{id}`,
			Size = UDim2.fromOffset(0, 44),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = K.raised,
			BackgroundTransparency = if on then 0 else 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = entry[2],
			Font = Theme.HeadingFont,
			TextSize = 13,
			TextColor3 = if on then K.text else K.secondary,
			LayoutOrder = index,
		}, row)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, tab)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = if on then 0.5 else 0.8 }, tab)
		if on then
			Ui.make("Frame", { Name = "Underline", Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = K.red, BorderSizePixel = 0 }, tab)
		end
		tab.Activated:Connect(function()
			local sound = Ui.onClick
			if sound then
				sound()
			end
			switch(id)
		end)
	end
	if not Ui.touchLayout() then
		Ui.label(row, "TAB · ↑ ↓ · ENTER", UDim2.fromOffset(150, 44), { Name = "KeyHint", TextSize = 11, TextColor3 = K.secondary, LayoutOrder = 3, TextXAlignment = Enum.TextXAlignment.Left })
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
end

-- Two small squares of the item's colours.
local function swatch(parent: Instance, def: Config.CosmeticDef, order: number)
	local row = Ui.make("Frame", { Name = "Swatch", Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local colours: { { number } } = { def.color }
	if def.trim then
		table.insert(colours, def.trim)
	end
	for n, c in colours do
		local chip = Ui.make("Frame", { Name = `Colour{n}`, Size = UDim2.fromOffset(28, 14), BackgroundColor3 = color3(c), BorderSizePixel = 0, LayoutOrder = n }, row)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, chip)
	end
end

-- An item's card: its colours, its name and what it is to you, its line, TRY and the main action.
local function card(parent: Instance, def: Config.CosmeticDef, order: number, look: OrdersUi.Kit, host: Host, style: Style.Wardrobe, money: number, lvl: number, selected: boolean)
	local b = look.block(parent, order, selected)
	local frame = b.Parent
	if frame then
		frame.Name = `Style_{def.id}`
		shown.cards[def.id] = frame
	end
	swatch(b, def, 1)
	local now = Style.state(style, def)
	local locked = now == "sale" and lvl < (def.level or 1)
	local status = if now == "wearing" then "WEARING" elseif now == "owned" then "OWNED" elseif now == "reward" then "🏆 REWARD"
		elseif locked then `🔒 LEVEL {def.level}` else Style.money(def.price)
	look.row2(b, string.upper(def.name), status, 2, true)
	look.meta(b, def.description, 3)
	local row = Ui.make("Frame", { Name = "Actions", Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, LayoutOrder = 4 }, b)
	Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, row)
	local function half(index: number): Instance
		return Ui.make("Frame", { Name = `Half{index}`, Size = UDim2.new(0.5, -4, 1, 0), BackgroundTransparency = 1, LayoutOrder = index }, row)
	end
	local try = look.button(half(1), "TRY", "quiet", 1, function()
		pick(def, false)
	end)
	try.Name = "Try"
	local label, kind
	if now == "wearing" then
		label, kind = "TAKE OFF", "quiet"
	elseif now == "owned" then
		label, kind = "WEAR", "main"
	elseif now == "reward" then
		label, kind = "REWARD ONLY", "off"
	else
		local here = shopHere(def)
		if here or locked then
			local ok = Style.canBuyAt(style, def, money, lvl, here)
			label, kind = `BUY · {Style.money(def.price)}`, if ok then "main" else "off"
		else
			label, kind = Style.atLabel(def), "off" -- (sold at a shop: a press sets the GPS there)
		end
	end
	local main = look.button(half(2), label, kind, 1, function()
		act(def, host)
	end)
	main.Name = "Main"
	for _, button in { try, main } do
		if button.SelectionGained then
			button.SelectionGained:Connect(function()
				if StyleApp.pick[StyleApp.tab] ~= def.id then
					pick(def, false)
				end
			end)
		end
	end
end

-- The app in the phone's popup (`list`: its body; `wide`: two columns of cards).
function StyleApp.render(list: Instance, look: OrdersUi.Kit, host: Host, wide: boolean?)
	shown.host = host
	shown.cards = {}
	local state = host.state()
	local style = wardrobe(state)
	local money, lvl = moneyOf(state), level()
	local tab = StyleApp.tab
	local current = picked(tab, style)
	tabs(list)
	bind()
	-- the preview
	local b = look.block(list, 2)
	b.Name = "PreviewCard"
	local holder = Ui.make("Frame", { Name = "Preview", Size = UDim2.new(1, 0, 0, 200), BackgroundColor3 = K.charcoal, BorderSizePixel = 0, LayoutOrder = 1, ClipsDescendants = true }, b)
	Ui.label(b, "", UDim2.new(1, 0, 0, 18), { Name = "PreviewCaption", TextSize = 12, TextColor3 = K.secondary, LayoutOrder = 2 })
	shown.preview = holder
	look.meta(list, `Buy them from {Style.soldBy(tab)}; wear them from here, anywhere. `
		.. (if tab == "courier" then "Looks only: no item changes a number of the game; your own look stays under them."
			else "Looks only, on every vehicle of yours they fit; a lent company vehicle and a ZDC RIDE scooter keep theirs."), 3)
	local n = 4
	for _, slot in Style.slots(tab) do
		local worn = Style.worn(style, slot.id)
		look.section(list, `{slot.name} · {if worn then worn.name else "your own"}`, n)
		look.meta(list, slot.note, n + 1)
		local left, right = PhoneApps.columns(list, n + 2, wide == true)
		for index, def in Style.items(slot.id) do
			card(if index % 2 == 1 then left else right, def, n + 2 + index, look, host, style, money, lvl, def == current)
		end
		n += 3 + #Style.items(slot.id)
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
end

return StyleApp
