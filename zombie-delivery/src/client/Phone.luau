--!strict
-- Approved courier phone UI: charcoal rectangular surfaces, white glyphs, red accents (design/phone-ui/).
-- Q / gamepad down opens it after Marge gives it. The same server-authoritative orders, messages, board,
-- career, shopping GPS, bike/car switch, tow and PhoneHold lifecycle remain in use. Home shows the live focused
-- contract and eight apps; ORDERS adds a discovered-only road preview. BANK displays existing cash (no banking
-- transactions); SETTINGS uses the existing sound cycle. Home scrolls; short viewports use a slightly smaller,
-- shorter upright device (it never turns sideways). Hardware alone has modest corner rounding.
-- PhoneContract draws art, PhoneLayout computes sizing/payload text, PhoneRoute draws the actual route.
-- No new gameplay remotes, currencies or prices. Phone does not change character joints.
-- 5.5, the HUD MENU in the phone (client/PhoneApps.luau, client/PhoneMotion.luau):
--   * The MENU's actions are apps under the first eight: MISSIONS, CREW, TOP, ESTATE (the phone closes and their window
--     opens: Phone.onMissions / onCrew / onTop / onEstate), BAG (in the phone), GARAGE (BRING MY CAR, MY BIKE, CALL
--     CAR, TOW). GIVE UP sits at the bottom of ORDERS (a second press within 4 s, CancelJob). SETTINGS lists every key
--     and the version; BANK adds what you earned since you joined. The HUD's MENU opens the phone once you have one
--     (Main: Hud.onMenu); before Marge it keeps its list.
--   * BOARD: the job board in the phone (ACCEPT / + ADD ORDER fire AcceptJob; FULL BOARD opens the Dispatch board).
--   * New messages and new boards drop a banner from the top of the open phone (a tap opens MESSAGES or BOARD).
-- 6.0.1, the owner's wish: the phone never turns sideways (5.5's turn for BOARD / CAREER / SHOP / BAG is gone). Every
--   app opens in a centred popup over the game (client/PhonePopup.luau: a dim, lightly blurred backdrop, a ZDC panel
--   with Ui.window's header, the app in a scrolling body; it grows from the tapped tile). The phone stays at its place
--   under the backdrop, on its home screen; closing the app (✕, the backdrop, Q, ESC, gamepad B) returns to it, and Q /
--   ESC / B again put the phone away. A wide popup shows BOARD, CAREER and SHOP in two columns. MISSIONS, CREW, TOP,
--   ESTATE, MAP and FULL BOARD still put the phone away and open their windows. The right-mouse camera
--   (CameraRig.freeLook, Main) is off while an app is open: the mouse is needed.

local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Career = require(Shared.Career)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Transport = require(Shared.Transport)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local P = require(script.Parent.HudContract)
local MapView = require(script.Parent.MapView)
local KitShop = require(script.Parent.KitShop)
local CareerUi = require(script.Parent.CareerUi)
local OrdersUi = require(script.Parent.OrdersUi) -- 5.2: every order of your run

local K = Theme.Contract
local Phone = {}

-- Set by Main.
Phone.onOpen = nil :: (() -> ())? -- the phone opens: close the other windows (Hud.closeWindows)
Phone.onBoard = nil :: (() -> ())? -- FULL BOARD: DispatchUi.open
Phone.onMissions = nil :: (() -> ())? -- 5.5, the MENU's apps: MissionsUi.toggle
Phone.onCrew = nil :: (() -> ())? -- CrewPanel.toggle
Phone.onTop = nil :: (() -> ())? -- Leaderboard.toggle
Phone.onEstate = nil :: (() -> ())? -- EstateUi.toggleList
Phone.onSound = nil :: (() -> ())? -- Sounds.cycle
Phone.onCareer = nil :: (() -> ())? -- FULL CAREER: CareerUi.open
Phone.boardOpen = nil :: (() -> boolean)? -- is the Dispatch board open (DispatchUi.isOpen): no "new runs" then
Phone.blocked = nil :: (() -> boolean)? -- the NEW PHONE pop-up waits while this says so (Marge's dialog, a result)
Phone.notify = nil :: ((string) -> ())? -- a toast (Hud.toast)

local player = Players.LocalPlayer
local KEY = Enum.KeyCode.Q -- 5.4.1 (was O; the weapon wheel moved to T)
local PAD_KEY = Enum.KeyCode.DPadDown
local BEZEL = 9
local SLIDE = TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local SLIDE_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local MAX_MESSAGES = 30

-- The phone's own surfaces around the contract tokens: the body a step lighter than charcoal (it reads as a device),
-- the screen nearly black, the app tiles raised.
local BODY = Color3.fromRGB(36, 40, 47)
local BODY_EDGE = Color3.fromRGB(70, 75, 83)
local SCREEN = Color3.fromRGB(10, 12, 15)
local TILE = Color3.fromRGB(27, 31, 37)
local TILE_HOVER = Color3.fromRGB(40, 45, 53)

type Message = { from: string, text: string, time: string, unread: boolean, kind: string }
-- 5.5: `window` opens a window of its own (the phone closes first); the others open in the popup (6.0.1).
type AppDef = { id: string, name: string, glyph: string, window: boolean? }

local APPS: { AppDef } = {
	{ id = "orders", name = "Orders", glyph = "📦" },
	{ id = "board", name = "Board", glyph = "📋" },
	{ id = "career", name = "Career", glyph = "🎖" },
	{ id = "shop", name = "Shop", glyph = "🛒" },
	{ id = "map", name = "Map", glyph = "🗺️", window = true },
	{ id = "messages", name = "Messages", glyph = "💬" },
	{ id = "bank", name = "Bank", glyph = "$" },
	{ id = "settings", name = "Settings", glyph = "⚙" },
	-- 5.5: the HUD MENU's actions
	{ id = "missions", name = "Missions", glyph = "⭐", window = true },
	{ id = "bag", name = "Bag", glyph = "🎒" },
	{ id = "garage", name = "Garage", glyph = "🚗" },
	{ id = "crew", name = "Crew", glyph = "👥", window = true },
	{ id = "top", name = "Top", glyph = "🏆", window = true },
	{ id = "estate", name = "Estate", glyph = "🏠", window = true },
}

local state: any = nil
local job: any = nil
local gui: ScreenGui? = nil
local refs: { [string]: any } = {} -- the instances (one table: few locals)
refs.design = require(script.Parent.PhoneContract)
refs.layout = require(script.Parent.PhoneLayout)
refs.routes = require(script.Parent.PhoneRoute)
refs.apps = require(script.Parent.PhoneApps) -- 5.5: BOARD, BAG, GARAGE, the keys
refs.motion = require(script.Parent.PhoneMotion) -- 5.5: the banner
refs.popup = require(script.Parent.PhonePopup) -- 6.0.1: the apps' centred popup
local tiles: { [string]: any } = {} -- the app tiles' badges by app id
local isOpen = false
local app = "home"
local messages: { Message } = {}
local boardNew = 0 -- runs pushed while the board was closed
local lastRefreshAt: number? = nil
local phoneBefore: boolean? = nil -- the state's phone at the last state (nil before the first state)
local momentShown = false
local seeded = false
local shownLevel: number? = nil

-- ── What the phone knows ───────────────────────────────────────────────────

local function hasPhone(): boolean
	return state ~= nil and state.phone == true
end

local function myXp(): number
	local xp = tonumber(player:GetAttribute("Xp"))
	if xp == nil and state and type(state.xp) == "number" then
		xp = state.xp
	end
	return xp or 0
end

local function myLevel(): number
	return Levels.levelFor(myXp())
end

local function money(): number
	return if state then tonumber(state.money) or 0 else 0
end

local function kit(): Transport.Kit
	return KitShop.owned(state)
end

-- "18:42" from the game's clock.
local function clockText(): string
	local hour = Lighting.ClockTime % 24
	local h = math.floor(hour)
	local m = math.floor((hour - h) * 60)
	return string.format("%02d:%02d", h, m)
end

local function shiftText(): string
	if Map.isNight(Lighting.ClockTime) then
		return `NIGHT SHIFT · JOBS PAY ×{Config.DayNight.NightPay}`
	end
	return "DAY SHIFT · THE BOARD IS OPEN"
end

-- How you get around: "ON FOOT · HANDS 2 / BACKPACK 3" or the vehicle's name (5.1: 🚲 a bike).
local function transportText(): string
	if state and type(state.car) == "string" then
		local def = Economy.findCar(state.car)
		return `{if def and def.stand then "🛴" elseif def and def.bike then "🚲" else "🚐"} {string.upper(if def then def.name else state.car)}`
	end
	return `🚶 ON FOOT · {KitShop.roomText(kit(), if state and type(state.bag) == "string" then state.bag else nil)}` -- (6.4: the bag in use)
end

-- The first vehicles you can own (dealer cars, not bikes), the earliest first.
local function vehicles(): { Config.CarDef }
	local list: { Config.CarDef } = {}
	for _, def in Config.Cars do
		if not def.company and not def.bike then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a: Config.CarDef, b: Config.CarDef): boolean
		if (a.level or 1) ~= (b.level or 1) then
			return (a.level or 1) < (b.level or 1)
		end
		return a.price < b.price
	end)
	return list
end

-- The cheapest piece of kit with this effect ("room", "speed", "warm").
local function cheapestKit(field: string): Config.KitDef?
	local best: Config.KitDef? = nil
	for _, def in Config.Kit do
		local b = best
		if (def :: any)[field] ~= nil and (b == nil or def.price < b.price) then
			best = def
		end
	end
	return best
end

-- Marge's tips: what a level opens, in her words, all from Config. Level 1 has two.
local function margeTips(level: number): { string }
	local tips: { string } = {}
	if level == 1 then
		table.insert(tips, "Welcome to Dead End Dispatch. No wheels yet, so you walk: letters, medicine, pizza, parcels. Take the ON FOOT runs on the board (J). Be quick and they tip.")
		local pack, shoes = cheapestKit("room"), cheapestKit("speed")
		if pack then
			table.insert(tips, `Your hands hold {Config.Cargo.HandsMax}. A {pack.name} at Last Stop Supplies holds {pack.room} ({Career.money(pack.price)}){if shoes then `, and {shoes.name} get you there faster ({Career.money(shoes.price)})` else ""}. The SHOP app says what you can afford.`)
		end
	end
	-- (5.1: the bike shop at Career.BIKE_LEVEL is Marge's own text from the server, with the GPS: server/Tutorial.luau)
	local first = vehicles()[1]
	if first and (first.level or 1) == level and level > 1 then
		local private = first.id == Config.VanQuest.Car -- (5.0: Earl sells it, not the dealer)
		table.insert(tips, `Level {level}: the {first.name} is yours to buy {if private then `from {Config.VanQuest.Seller} at {Config.VanQuest.Place}, far out west` else "at Dead End Motors"} ({Career.money(first.price)}). With a vehicle the car jobs open, and the missions.`)
	end
	for _, tier in Config.Jobs.Tiers do
		if tier.level == level and level > 1 then
			table.insert(tips, `{string.rep("★", tier.stars)} {tier.name} jobs are on the board from now on{if state and type(state.car) ~= "string" then ", once you have a vehicle" else ""}.`)
		end
	end
	return tips
end

-- ── Messages ───────────────────────────────────────────────────────────────

local refreshBadges: () -> () = function() end
local renderApp: () -> () = function() end
local setApp: (id: string) -> () = function() end -- (── Showing ──)
local placeButton: () -> () = function() end -- (the PHONE action's place, ── The PHONE action ──)

local function unreadCount(): number
	local count = 0
	for _, message in messages do
		if message.unread then
			count += 1
		end
	end
	return count
end

local function addMessage(from: string, text: string, kind: string, unread: boolean)
	table.insert(messages, { from = from, text = text, time = clockText(), unread = unread, kind = kind })
	while #messages > MAX_MESSAGES do
		table.remove(messages, 1)
	end
	refreshBadges()
	if isOpen and (app == "messages" or app == "home") then
		renderApp()
	end
	-- 5.5: a banner drops from the top of the open phone (a tap opens BOARD for a new board, else MESSAGES); 6.0.1: from
	-- the top of the open app's popup.
	local target = if kind == "board" then "board" else "messages"
	if isOpen and unread and app ~= target and refs.screen then
		local panel = refs.popup.panel()
		refs.motion.banner(panel or refs.screen, if panel then 0 else refs.statusH or 30, from, text, function()
			setApp(target)
		end)
	end
end

-- The first state: Marge's tips up to your level are already in the phone (read).
local function seed()
	if seeded or not state then
		return
	end
	seeded = true
	local level = myLevel()
	shownLevel = level
	for n = 1, level do
		for _, tip in margeTips(n) do
			addMessage("Marge", tip, "marge", false)
		end
	end
end

-- ── Small pieces ───────────────────────────────────────────────────────────
-- 5.4, the phone's type and spacing scale (every app): a section label caps 11 secondary; a title HeadingFont 16 – 18;
-- the body Font 14; meta Font 12 secondary. Gaps of 4, 8, 12 and 16.

local function text(parent: Instance, value: string, size: UDim2, props: { [string]: any }?): any
	local label = Ui.label(parent, value, size, { TextColor3 = K.text, Font = Theme.Font, TextSize = 14, TextWrapped = true })
	if props then
		for key, v in props do
			label[key] = v
		end
	end
	return label
end

local function caps(parent: Instance, value: string, order: number, color: Color3?): any
	return P.caps(parent, value, UDim2.new(1, 0, 0, 16), { LayoutOrder = order, TextStrokeTransparency = 1, TextColor3 = color or K.secondary })
end

local function click()
	local sound = Ui.onClick
	if sound then
		sound()
	end
end

-- A square contract surface with a fine outline; the automatic inner Body owns the layout.
-- Selected contracts carry a narrow red left rule. Returns the Body.
local function block(parent: Instance, order: number, selected: boolean?): any
	local card = Ui.make("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = K.row,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = if selected then 0.7 else 0.82 }, card)
	local body = Ui.make("Frame", { Name = "Body", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, card)
	Ui.list(body, true, 4)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, if selected then 15 else 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12) }, body)
	if selected then
		Ui.make("Frame", { Name = "Accent", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = K.red, BorderSizePixel = 0, ZIndex = 2 }, card)
	end
	return body
end

-- A thin bar in a list (share 0 … 1).
local function bar(parent: Instance, share: number, color: Color3, order: number)
	local holder = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 8), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local back, fill = P.bar(holder, UDim2.new(1, 0, 0, 4), color)
	back.Position = UDim2.fromOffset(0, 2)
	Ui.corner(back, 2)
	Ui.corner(fill, 2)
	fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
end

-- Keep the hover marker inside a square phone button.
local function squareButton(made: any): any
	local edge = made:FindFirstChild("Edge")
	if edge and edge:IsA("GuiObject") then
		edge.Size = UDim2.new(0, 2, 1, 0)
		edge.Position = UDim2.fromOffset(0, 0)
	end
	return made
end

-- A window action inside the phone (P.button), full width.
local function button(parent: Instance, label: string, kind: P.ButtonKind, order: number, onClick: () -> ()): any
	local made = squareButton(P.button(parent, label, UDim2.new(1, 0, 0, 54), kind, onClick))
	made.LayoutOrder = order
	made.TextSize = 13
	if kind == "main" then
		refs.design.primary(made)
	end
	return made
end

-- 5.4: the rest of the kit, in one table (Phone sits near the register limit: no new top-level locals). OrdersUi.Kit
-- names the same pieces; OrdersUi draws with them too.
local look: OrdersUi.Kit
do
	local TextService = game:GetService("TextService")

	-- How wide a line of text is (unscaled pixels).
	local function width(value: string, size: number, font: Enum.Font): number
		local ok, bounds = pcall(function(): Vector2
			return TextService:GetTextSize(value, size, font, Vector2.new(1000, 100))
		end)
		return if ok then math.ceil(bounds.X) + 2 else #value * size * 0.6
	end

	local function section(list: Instance, label: string, order: number): any
		local holder = Ui.make("Frame", { Name = "Section", Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = order }, list)
		P.caps(holder, label, UDim2.new(1, -4, 0, 14), {
			Position = UDim2.new(0, 2, 1, -2),
			AnchorPoint = Vector2.new(0, 1),
			TextSize = 11,
			TextColor3 = K.secondary,
			TextStrokeTransparency = 1,
		})
		return holder
	end

	local function meta(parent: Instance, value: string, order: number, color: Color3?): any
		return text(parent, value, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, TextSize = 12, TextColor3 = color or K.secondary })
	end

	local function chip(parent: Instance, value: string, color: Color3?): any
		local tint = color or K.secondary
		local made = Ui.label(parent, string.upper(value), UDim2.fromOffset(0, 22), {
			Name = "Chip",
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = K.raised,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextColor3 = tint,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = tint, Thickness = 1, Transparency = 0.72 }, made)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, made)
		return made
	end

	local function chipRow(parent: Instance, order: number): any
		local row = Ui.make("Frame", { Name = "Chips", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
		local layout = Ui.make("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}, row)
		pcall(function()
			layout.Wraps = true -- (long rule lines go to a second line)
		end)
		return row
	end

	local function row2(parent: Instance, leftText: string, rightText: string, order: number, strong: boolean?): (any, any, any)
		local font = if strong then Theme.HeadingFont else Theme.Font
		local size = if strong then 14 else 12
		local w = width(rightText, size, font)
		local row = Ui.make("Frame", { Name = "Row2", Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = order }, parent)
		local right = text(row, rightText, UDim2.new(0, w, 1, 0), {
			Position = UDim2.fromScale(1, 0),
			AnchorPoint = Vector2.new(1, 0),
			Font = font,
			TextSize = size,
			TextColor3 = if strong then K.text else K.secondary,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local left = text(row, leftText, UDim2.new(1, -(w + 8), 1, 0), { TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		return row, left, right
	end

	local function emptyState(list: Instance, glyph: string, title: string, sub: string?, order: number): any
		local box = Ui.make("Frame", { Name = "Empty", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, list)
		Ui.list(box, true, 8, Enum.HorizontalAlignment.Center)
		Ui.make("UIPadding", { PaddingTop = UDim.new(0, 24), PaddingBottom = UDim.new(0, 16) }, box)
		local circle = Ui.make("Frame", { Size = UDim2.fromOffset(64, 64), BackgroundColor3 = K.row, BorderSizePixel = 0, LayoutOrder = 1 }, box)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.8 }, circle)
		text(circle, glyph, UDim2.fromScale(1, 1), { TextSize = 30, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
		text(box, title, UDim2.new(1, -24, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Font = Theme.HeadingFont, TextSize = 17, TextXAlignment = Enum.TextXAlignment.Center })
		if sub then
			text(box, sub, UDim2.new(1, -32, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, TextSize = 12, TextColor3 = K.secondary, TextXAlignment = Enum.TextXAlignment.Center })
		end
		return box
	end

	local function stepper(parent: Instance, stops: { any }, order: number): any
		local holder = Ui.make("Frame", { Name = "Stops", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
		Ui.list(holder, true, 4)
		local count = #stops
		for index, stop in stops do
			if type(stop) ~= "table" then
				continue
			end
			local done, current, open = stop.done == true, stop.current == true, stop.open == true
			local mark = if done then "✓" elseif current then "▶" elseif open then "●" else "○"
			local color = if done then K.secondary elseif current then K.red elseif open then K.text else K.secondary
			local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = index }, holder)
			Ui.make("UISizeConstraint", { MinSize = Vector2.new(0, 18) }, row)
			text(row, mark, UDim2.fromOffset(16, 18), { Font = Theme.HeadingFont, TextSize = if current then 10 else 12, TextColor3 = color, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = if done then 0.3 else 0 })
			if index < count then
				-- (a hairline down to the next stop's dot)
				Ui.make("Frame", { Size = UDim2.new(0, 1, 1, -14), Position = UDim2.fromOffset(8, 18), BackgroundColor3 = K.line, BackgroundTransparency = 0.7, BorderSizePixel = 0 }, row)
			end
			local label = tostring(stop.label or (if stop.kind == "pickup" then "Pick up" else "Deliver"))
			text(row, label, UDim2.new(1, -24, 0, 0), {
				Position = UDim2.fromOffset(24, 1),
				AutomaticSize = Enum.AutomaticSize.Y,
				Font = if current then Theme.HeadingFont else Theme.Font,
				TextSize = 13,
				TextColor3 = if current or open then K.text else K.secondary,
				TextTransparency = if done then 0.3 else 0,
			})
		end
		return holder
	end

	local function pill(parent: Instance, value: string, onClick: () -> (), accent: boolean?): any
		local hit = Ui.make("TextButton", {
			Name = "Pill",
			Size = UDim2.fromOffset(0, 54), -- at least 44 physical px on a 320 px touch screen
			AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ZIndex = 3,
		}, parent)
		if parent:IsA("GuiObject") and parent.Name == "Head" then
			parent.Size = UDim2.new(parent.Size.X.Scale, parent.Size.X.Offset, 0, 54)
		end
		local tint = if accent then K.red else K.line
		local face = Ui.label(hit, string.upper(value), UDim2.fromOffset(0, 24), {
			AutomaticSize = Enum.AutomaticSize.X,
			Position = UDim2.fromScale(0, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = K.raised,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextColor3 = if accent then K.red else K.text,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
		})
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = tint, Thickness = 1, Transparency = if accent then 0.35 else 0.6 }, face)
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, face)
		local function lit(on: boolean)
			face.BackgroundColor3 = if on then TILE_HOVER else K.raised
		end
		hit.MouseEnter:Connect(function()
			lit(true)
		end)
		hit.MouseLeave:Connect(function()
			lit(false)
		end)
		hit.SelectionGained:Connect(function()
			lit(true)
		end)
		hit.SelectionLost:Connect(function()
			lit(false)
		end)
		hit.Activated:Connect(function()
			click()
			onClick()
		end)
		return hit
	end

	look = {
		block = block,
		caps = caps,
		text = text,
		button = button,
		section = section,
		meta = meta,
		chip = chip,
		chipRow = chipRow,
		row2 = row2,
		emptyState = emptyState,
		stepper = stepper,
		pill = pill,
		width = width,
	}
end

-- The GPS to one of Map.Shops or a landmark (5.0: "earl", Earl's Used Wheels) (the white route on both maps, the HUD's
-- beam and label).
local function gpsTo(shopId: string)
	local shop = Map.Shops[shopId]
	local landmark: Map.Landmark? = nil
	for _, entry in Map.Landmarks do
		if entry.id == shopId then
			landmark = entry
		end
	end
	local x = if shop then shop.x elseif landmark then landmark.x else nil
	local z = if shop then shop.z elseif landmark then landmark.z else nil
	if x == nil or z == nil then
		return
	end
	MapView.setWaypoint(Vector3.new(x, Map.RoadTop, z))
	pcall(function()
		MapView.onWaypoint(landmark or { id = shopId, name = if shop then shop.name else shopId, icon = "🛒", x = x, z = z, kind = "shop", description = "" })
	end)
end

-- ── The apps ───────────────────────────────────────────────────────────────

-- "&", "<", ">" for RichText.
local function rich(value: string): string
	return (string.gsub(string.gsub(string.gsub(value, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

local function ordersApp(list: Instance)
	local bag = require(script.Parent.BagUi)
	local function openBoard()
		setApp("board") -- 5.5: the board in the phone
	end
	local function openBag()
		setApp("bag") -- 5.5: the bag in the phone
	end
	if not job then
		look.emptyState(list, "📦", "No active orders", "Grab a job from the board, on foot from level 1.", 1)
		button(list, "OPEN BOARD", "main", 2, openBoard)
		button(list, "🎒 BAG", "quiet", 3, openBag)
		return
	end
	local orders = if type(job.orders) == "table" then job.orders else {}
	local focused = OrdersUi.focused(job)
	-- The hero: the focused order.
	local b = block(list, 1, true)
	local head = Ui.make("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
	P.caps(head, `{if #orders > 1 then `Now · order {job.focus or "?"}` else "Now · active order"}{if job.mission then " · mission" else ""}`, UDim2.new(1, -96, 1, 0), {
		TextSize = 11,
		TextColor3 = K.red,
		TextStrokeTransparency = 1,
	})
	if #orders > 1 and focused then
		OrdersUi.pinPill(head, focused, look)
	end
	text(b, string.upper(tostring(job.stopLabel or job.customer or "ACTIVE DELIVERY")), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Font = Theme.HeadingFont, TextSize = 17 })
	look.meta(b, `{job.address or "?"}{if job.district then `, {job.district}` else ""}`, 3)
	refs.route = refs.spareRoute or refs.routes.create(b, if typeof(job.position) == "Vector3" then job.position else nil, 4, function() return isOpen and app == "orders" end)
	refs.spareRoute = nil
	refs.route.holder.Parent = b
	refs.route.update()
	-- The clock (ticked by the open loop) and the pay, their captions under them.
	local line = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 5 }, b)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 7) }, line)
	refs.timer = text(line, if type(job.endsAt) == "number" then Ui.clock(math.max(0, job.endsAt - workspace:GetServerTimeNow())) else "", UDim2.new(0.5, 0, 1, 0), { Font = Theme.HeadingFont, TextSize = 24, TextWrapped = false })
	text(line, Ui.money(tonumber(job.pay) or 0), UDim2.new(0.5, 0, 1, 0), { Position = UDim2.fromScale(0.5, 0), Font = Theme.HeadingFont, TextSize = 22, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right })
	local labels = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, LayoutOrder = 6 }, b)
	P.caps(labels, "Time left", UDim2.fromScale(0.5, 1), { TextStrokeTransparency = 1, TextSize = 11 })
	P.caps(labels, "Pay", UDim2.fromScale(0.5, 1), { Position = UDim2.fromScale(0.5, 0), TextStrokeTransparency = 1, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right })
	local gap = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1, LayoutOrder = 7 }, b)
	P.rule(gap, UDim2.new(1, 0, 0, 1), { Position = UDim2.fromOffset(0, 5), BackgroundTransparency = 0.75 })
	-- The stops: the focused order's own (the stepper), else "Stop 1 / 3"; then what to do now.
	if focused and type(focused.stops) == "table" and #focused.stops > 0 then
		look.stepper(b, focused.stops, 8)
	else
		caps(b, `Stop {tonumber(job.stopIndex) or 1} / {tonumber(job.stopCount) or 1} · {if job.stage == "pickup" then "pick up" else "deliver"}`, 8).TextSize = 11
	end
	if type(job.step) == "string" and job.step ~= "" then
		text(b, job.step, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 9, TextSize = 14 })
	end
	-- Chips: how it travels, what rides with you (5.0: the backpack; the PackCount attribute is live), the condition, the
	-- cargo's rules.
	local chips = look.chipRow(b, 10)
	look.chip(chips, if job.mode == "foot" then "🚶 On foot" elseif job.mode == "bike" then "🚲 By bike" else string.rep("★", math.max(1, tonumber(job.stars) or 1)))
	local packRoom = tonumber(job.packRoom) or tonumber(player:GetAttribute("PackRoom")) or 0
	if (job.mode == "foot" or job.mode == "bike") and packRoom > 0 then
		local packed = tonumber(player:GetAttribute("PackCount")) or tonumber(job.pack) or 0
		look.chip(chips, `{if job.mode == "bike" then "🚲 Bike" else "🎒 Backpack"} {packed} / {packRoom}`, if packed >= packRoom then K.red else nil)
	end
	local condition = tonumber(job.condition)
	if condition and condition < 0.999 then
		look.chip(chips, `Condition {math.floor(condition * 100 + 0.5)}%`, if condition < 0.5 then K.red else K.warn)
	end
	if type(job.ruleLine) == "string" and job.ruleLine ~= "" then
		for part in string.gmatch(job.ruleLine .. " · ", "(.-) · ") do
			if part ~= "" then
				look.chip(chips, part)
			end
		end
	end
	-- The pieces delivered.
	local total = tonumber(job.total) or 0
	if total > 0 then
		local done = tonumber(job.deliveredTotal) or 0
		local _, left = look.row2(b, `{done} / {total} {if total == 1 then (job.piece or "piece") else (job.pieces or "pieces")} delivered`, if (tonumber(job.lost) or 0) > 0 then `{job.lost} lost` else "", 11)
		left.TextSize = 12
		left.TextColor3 = K.secondary
		bar(b, done / total, K.text, 12)
	end
	-- 5.2: the other orders of the run (their stops, clocks, pay, PIN), then the actions.
	local n = OrdersUi.render(list, job, look, 2)
	local map = button(list, "SHOW ROUTE", "main", n, function()
		Phone.close()
		if not MapView.isOpen() then MapView.toggle() end
	end)
	map.Name = "ShowRoute"
	-- Preserve the full bag and stack actions beneath the route button.
	local carried = bag.line(job)
	local pack = button(list, `BAG · {if carried then rich(string.sub(carried, 6)) else "EMPTY"}`, "quiet", n + 1, openBag)
	pack.RichText = true
	pack.TextTruncate = Enum.TextTruncate.AtEnd
	local stack = job.stack
	button(list, if type(stack) == "table" and stack.can == true then "OPEN BOARD · + ADD ORDER" else "OPEN BOARD", "quiet", n + 2, openBoard)
	-- 5.5: GIVE UP (the MENU's), quiet and red at the bottom; a second press within 4 s gives the delivery up.
	local giveUp: any = nil
	giveUp = button(list, "GIVE UP THIS DELIVERY", "quiet", n + 3, function()
		local now = os.clock()
		if now - (refs.giveUpAt or 0) > 4 then
			refs.giveUpAt = now
			giveUp.Text = "PRESS AGAIN TO GIVE IT UP"
			local notify = Phone.notify
			if notify then
				notify("Give up this delivery? Press again.")
			end
			task.delay(4, function()
				if giveUp.Parent and os.clock() - (refs.giveUpAt or 0) >= 4 then
					giveUp.Text = "GIVE UP THIS DELIVERY"
				end
			end)
			return
		end
		refs.giveUpAt = 0
		Net.get("CancelJob"):FireServer()
	end)
	giveUp.Name = "GiveUp"
	giveUp.TextColor3 = K.red
	local outline = giveUp:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Color = K.red
	end
end

local function careerApp(list: Instance, wide: boolean)
	local xp = myXp()
	local level = myLevel()
	local road = Career.road()
	-- 5.5, a wide popup (6.0.1): the current level on the left, the next steps on the right.
	local here, ahead = refs.apps.columns(list, 1, wide)
	look.section(here, "Dead End Dispatch · your career", 1)
	local b = block(here, 2, true)
	text(b, string.upper(Levels.rank(level)), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Font = Theme.DisplayFont, TextSize = 22 })
	local chips = look.chipRow(b, 2)
	look.chip(chips, `Level {level} of {Config.Levels.MaxLevel}`, K.text)
	look.chip(chips, `{string.sub(Career.money(xp), 2)} XP`)
	bar(b, Levels.progress(xp), K.text, 3)
	local nextStep = road[level + 1]
	if nextStep then
		local left = math.max(0, nextStep.xp - xp)
		look.section(here, "Next goal", 3)
		local g = block(here, 4)
		caps(g, `Level {nextStep.level}{if nextStep.newRank then ` · {nextStep.rank}` else ""}`, 1, K.red).TextSize = 11
		text(g, `{string.sub(Career.money(left), 2)} XP to go: about {CareerUi.toGo(left, level)}.`, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextSize = 14 })
		local opens: { string } = {}
		for _, unlock in nextStep.unlocks do
			if unlock.kind ~= "stage" or (state and type(state.cars) == "table" and state.cars[unlock.car or ""]) then
				table.insert(opens, CareerUi.unlockText(unlock))
			end
		end
		if #opens > 0 then
			look.meta(g, table.concat(opens, "\n", 1, math.min(#opens, 5)), 3)
		end
		local parts = Career.rewardParts(nextStep.reward)
		if #parts > 0 then
			look.section(g, "Reward", 4)
			local row = look.chipRow(g, 5)
			for _, part in parts do
				look.chip(row, part, K.good)
			end
		end
	end
	-- The next few levels of the road.
	look.section(ahead, "The road ahead", 5)
	local r = block(ahead, 6)
	local layout = r:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, 8) -- (a step more air between the levels)
	end
	local shown = 0
	for n = level + 2, Config.Levels.MaxLevel do
		local step = road[n]
		if not step or shown >= 3 then
			break
		end
		shown += 1
		local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = shown }, r)
		Ui.make("UISizeConstraint", { MinSize = Vector2.new(0, 24) }, row)
		local stone = Ui.label(row, tostring(n), UDim2.fromOffset(24, 24), { BackgroundColor3 = K.raised, BackgroundTransparency = 0, Font = Theme.HeadingFont, TextSize = 12, TextColor3 = K.secondary, TextXAlignment = Enum.TextXAlignment.Center })
		Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, stone)
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, stone)
		local summary = Career.summary(step.unlocks, 3, if state and type(state.cars) == "table" then state.cars else {})
		text(row, if summary ~= "" then summary else "better pay and harder roads", UDim2.new(1, -34, 0, 0), { Position = UDim2.fromOffset(34, 4), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = K.secondary, TextSize = 13 })
	end
	if shown == 0 then
		look.meta(r, "The top of the road is close.", 1)
	end
	button(ahead, if Ui.touchLayout() then "FULL CAREER" else "FULL CAREER  [C]", "main", 7, function()
		local cb = Phone.onCareer
		if cb then
			cb()
		end
	end)
end

-- One thing to save up for: its icon, name, where, and what is missing (the level, the money: a bar to its price).
local function goal(parent: Instance, order: number, icon: string, name: string, where: string, price: number, level: number, soon: string?)
	local b = block(parent, order)
	local mine = money()
	local status: string, color: Color3
	if soon then
		status, color = soon, K.secondary
	elseif myLevel() < level then
		status, color = `🔒 Level {level}`, K.warn
	elseif mine >= price then
		status, color = "✓ Afford it", K.good
	else
		status, color = `{Ui.money(price - mine)} to go`, K.secondary
	end
	local head = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
	local tag = look.chip(head, status, color)
	tag.AnchorPoint = Vector2.new(1, 0.5)
	tag.Position = UDim2.new(1, 0, 0.5, 0)
	local w = look.width(string.upper(status), 11, Theme.HeadingFont) + 18
	text(head, `{icon}  {name}`, UDim2.new(1, -(w + 8), 1, 0), { Font = Theme.HeadingFont, TextSize = 15, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	look.meta(b, if price > 0 then `{where} · {Ui.money(price)} · level {level}` else `{where} · level {level}`, 2)
	if not soon then
		bar(b, if price > 0 then mine / price else 1, if mine >= price and myLevel() >= level then K.good else K.text, 3)
	end
end

-- A shop's section label in the SHOP app with SET GPS.
local function shopHeader(parent: Instance, order: number, shopId: string, title: string)
	local row = Ui.make("Frame", { Name = "Section", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	P.caps(row, title, UDim2.new(1, -110, 0, 14), { Position = UDim2.new(0, 2, 1, -11), AnchorPoint = Vector2.new(0, 1), TextSize = 11, TextStrokeTransparency = 1, TextColor3 = K.secondary })
	local gps = look.pill(row, "📍 Set GPS", function()
		gpsTo(shopId)
		local notify = Phone.notify
		local shop = Map.Shops[shopId]
		if notify then
			notify(`GPS: {if shop then shop.name elseif shopId == "earl" then Config.VanQuest.Place else title}`)
		end
	end)
	gps.Position = UDim2.new(1, 0, 1, 0)
	gps.AnchorPoint = Vector2.new(1, 1)
end

local function shopApp(list: Instance, wide: boolean)
	local level = myLevel()
	-- 5.5, a wide popup (6.0.1): what's next and the kit on the left, the bikes and the vehicles on the right.
	local gear, rides = refs.apps.columns(list, 1, wide)
	local top = block(gear, 1, true)
	caps(top, "What's next", 1, K.red).TextSize = 11
	local chips = look.chipRow(top, 2)
	look.chip(chips, `{Ui.money(money())} in your pocket`, K.good)
	look.chip(chips, `Level {level}`, K.text)
	look.meta(top, "Personal gear is yours for good; a vehicle opens the car jobs.", 3)
	local order = 1
	-- The personal gear still worth buying (Config.Kit), the cheapest first.
	local owned = kit()
	local wanted: { Config.KitDef } = {}
	for _, def in Config.Kit do
		local outgrown = def.room ~= nil and def.speed == nil and def.warm == nil and def.room <= Transport.backpackRoom(owned)
		if not owned[def.id] and not outgrown then
			table.insert(wanted, def)
		end
	end
	table.sort(wanted, function(a: Config.KitDef, b: Config.KitDef): boolean
		return a.price < b.price
	end)
	if #wanted > 0 then
		order += 1
		shopHeader(gear, order, "supplies", "Last Stop Supplies · kit")
		for _, def in wanted do
			order += 1
			goal(gear, order, def.icon, def.name, "Last Stop Supplies", def.price, def.level)
		end
	end
	-- 5.1: the bikes at Spoke & Chain you do not own yet (two of them, the cheapest first), SET GPS to the shop.
	local cars = if state and type(state.cars) == "table" then state.cars else {}
	local bikesShown = 0
	for _, def in Config.Cars do
		if not def.bike or cars[def.id] or bikesShown >= 2 then
			continue
		end
		bikesShown += 1
		order += 1
		if bikesShown == 1 then
			shopHeader(rides, order, "bikes", "Spoke & Chain · bikes")
			order += 1
		end
		goal(rides, order, if def.stand then "🛴" else "🚲", def.name, `Spoke & Chain, {Config.BikeShop.Street}`, def.price, def.level or 1)
	end
	-- The first vehicles you do not own yet (two of them). 5.0: the Old Van comes from Earl (Marge's quest), SET GPS
	-- to him; the others from Dead End Motors.
	local count = 0
	local dealerShown = false
	for _, def in vehicles() do
		if cars[def.id] or count >= 2 then
			continue
		end
		count += 1
		order += 1
		if def.id == Config.VanQuest.Car then
			local quest = if state and state.vanQuest == "open" then "open" else nil
			shopHeader(rides, order, "earl", `{Config.VanQuest.Place} · {def.name}`)
			order += 1
			goal(rides, order, "🚐", def.name, if quest then `{Config.VanQuest.Seller}, far out west` else "Marge's quest", def.price, def.level or 1)
			continue
		end
		if not dealerShown then
			dealerShown = true
			shopHeader(rides, order, "dealer", "Dead End Motors · vehicles")
			order += 1
		end
		goal(rides, order, "🚐", def.name, "Dead End Motors", def.price, def.level or 1)
	end
end

-- A chat list: one card, a row per message (newest first) split by hairlines: the round avatar, the name and the time,
-- the text under them (muted once read), a red dot at the right edge while unread.
local function messagesApp(list: Instance)
	if #messages == 0 then
		look.emptyState(list, "✉️", "No messages yet", nil, 1)
		return
	end
	look.section(list, "Recent", 1)
	local card = block(list, 2)
	local layout = card:FindFirstChildOfClass("UIListLayout")
	if layout then
		layout.Padding = UDim.new(0, 0)
	end
	local padding = card:FindFirstChildOfClass("UIPadding")
	if padding then
		padding.PaddingTop = UDim.new(0, 0)
		padding.PaddingBottom = UDim.new(0, 0)
	end
	local order = 0
	for index = #messages, 1, -1 do
		local message = messages[index]
		order += 1
		if order > 1 then
			local hair = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundTransparency = 1, LayoutOrder = order * 2 - 1 }, card)
			Ui.make("Frame", { Size = UDim2.new(1, -48, 1, 0), Position = UDim2.fromOffset(48, 0), BackgroundColor3 = K.line, BackgroundTransparency = 0.8, BorderSizePixel = 0 }, hair)
		end
		local row = Ui.make("Frame", { Name = "Message", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order * 2 }, card)
		Ui.make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }, row)
		local avatar = Ui.label(row, string.upper(string.sub(message.from, 1, 1)), UDim2.fromOffset(36, 36), {
			BackgroundColor3 = if message.kind == "marge" then K.red elseif message.kind == "level" then K.text else K.charcoal,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 15,
			TextColor3 = if message.kind == "level" then K.charcoal else K.text,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		if message.kind ~= "marge" and message.kind ~= "level" then
			Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, avatar)
		end
		local content = Ui.make("Frame", { Size = UDim2.new(1, -64, 0, 0), Position = UDim2.fromOffset(48, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, row)
		Ui.list(content, true, 2)
		local _, name = look.row2(content, message.from, message.time, 1)
		name.Font = Theme.HeadingFont
		text(content, message.text, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextSize = 14, TextColor3 = if message.unread then K.text else K.secondary })
		if message.unread then
			local dot = Ui.make("Frame", { Name = "Unread", Size = UDim2.fromOffset(8, 8), Position = UDim2.new(1, 0, 0, 18), AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = K.red, BorderSizePixel = 0 }, row)
			Ui.make("UICorner", { CornerRadius = UDim.new(0.5, 0) }, dot)
		end
	end
	-- Read now (the badge goes; the dots stay until the app is drawn again).
	for _, message in messages do
		message.unread = false
	end
	refreshBadges()
end

-- ── Building ───────────────────────────────────────────────────────────────

-- 6.0.1: `from` (the tapped tile or card) is where the app's popup grows from.
local function launch(id: string, from: GuiObject?)
	click()
	if from then
		local at, size = from.AbsolutePosition, from.AbsoluteSize
		refs.from = Vector2.new(at.X + size.X / 2, at.Y + size.Y / 2)
		refs.lastTile = from
	end
	if id == "board" then
		boardNew = 0
		refreshBadges()
	end
	-- MAP and the MENU's windows (5.5): the phone closes, their window opens.
	if id == "map" then
		Phone.close()
		if not MapView.isOpen() then
			MapView.toggle()
		end
		return
	end
	if id == "missions" or id == "crew" or id == "top" or id == "estate" then
		Phone.close()
		local open: (() -> ())? = if id == "missions" then Phone.onMissions elseif id == "crew" then Phone.onCrew elseif id == "top" then Phone.onTop else Phone.onEstate
		if open then
			open()
		else
			local notify = Phone.notify
			if notify then
				notify(`The {id} window is not ready yet.`)
			end
		end
		return
	end
	setApp(id)
end

-- A square outline with a white glyph, a label and a red unread/count badge.
local function tile(parent: Instance, def: AppDef, order: number): any
	local cell = Ui.make("TextButton", {
		Name = `{def.id}App`,
		Size = UDim2.fromOffset(80, 88),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
	}, parent)
	local face = Ui.make("Frame", {
		Size = UDim2.fromOffset(58, 58),
		Position = UDim2.new(0.5, 0, 0, 2),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = TILE,
		BorderSizePixel = 0,
	}, cell)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, face)
	-- (uploaded shared/Icons app art, otherwise native monochrome line glyphs)
	refs.design.glyph(face, def.id, 30)
	local name = P.caps(cell, def.name, UDim2.new(1, 0, 0, 16), { Position = UDim2.fromOffset(0, 66), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 1, TextSize = 11 })
	local underline = Ui.make("Frame", { Size = UDim2.new(0, 22, 0, 1), Position = UDim2.new(0.5, -11, 0, 84), BackgroundColor3 = K.red, BackgroundTransparency = 1, BorderSizePixel = 0 }, cell)
	P.hover(cell :: any, underline, name)
	cell.MouseEnter:Connect(function()
		face.BackgroundColor3 = TILE_HOVER
	end)
	cell.MouseLeave:Connect(function()
		face.BackgroundColor3 = TILE
	end)
	cell.SelectionGained:Connect(function()
		face.BackgroundColor3 = TILE_HOVER
	end)
	cell.SelectionLost:Connect(function()
		face.BackgroundColor3 = TILE
	end)
	local badge = Ui.label(face, "", UDim2.fromOffset(18, 18), {
		Name = "Badge",
		Position = UDim2.new(1, 5, 0, -5),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = K.red,
		BackgroundTransparency = 0,
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		ZIndex = 3,
	})
	tiles[def.id] = badge
	cell.Activated:Connect(function()
		launch(def.id, cell)
	end)
	return cell
end

-- The status bar: the time, the camera's pill in the middle, the signal and the battery.
local function statusBar(screen: Instance, height: number)
	local bar0 = Ui.make("Frame", { Name = "Status", Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, ZIndex = 4 }, screen)
	refs.statusTime = text(bar0, clockText(), UDim2.new(0, 60, 1, 0), { Position = UDim2.fromOffset(22, 0), Font = Theme.HeadingFont, TextSize = 13, TextWrapped = false, ZIndex = 4 })
	local pill = Ui.make("Frame", { Size = UDim2.fromOffset(64, 16), Position = UDim2.new(0.5, 0, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, ZIndex = 5 }, bar0)
	Ui.corner(pill, 8)
	Ui.make("Frame", { Size = UDim2.fromOffset(5, 5), Position = UDim2.new(1, -11, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(28, 32, 44), BorderSizePixel = 0, ZIndex = 6 }, pill)
	-- The signal: four bars, three lit.
	for n = 1, 4 do
		local h = 3 + n * 2
		Ui.make("Frame", {
			Size = UDim2.fromOffset(3, h),
			Position = UDim2.new(1, -78 + n * 5, 0.5, 5 - h),
			BackgroundColor3 = K.text,
			BackgroundTransparency = if n <= 3 then 0 else 0.7,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, bar0)
	end
	-- The battery: an outline, a fill, the nub.
	local battery = Ui.make("Frame", { Size = UDim2.fromOffset(22, 11), Position = UDim2.new(1, -46, 0.5, -5), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4 }, bar0)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.text, Thickness = 1, Transparency = 0.3 }, battery)
	Ui.corner(battery, 3)
	local fill = Ui.make("Frame", { Size = UDim2.new(0.78, -3, 1, -4), Position = UDim2.fromOffset(2, 2), BackgroundColor3 = K.text, BorderSizePixel = 0, ZIndex = 4 }, battery)
	Ui.corner(fill, 1)
	Ui.make("Frame", { Size = UDim2.fromOffset(2, 4), Position = UDim2.new(1, 2, 0.5, -2), BackgroundColor3 = K.text, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 4 }, battery)
end

-- Home: depot brand, courier ID, focused contract and newest unread message.
local function homeWidgets(parent: Instance)
	local brand = refs.design.brand(parent, 1)
	refs.shift = P.caps(brand, shiftText(), UDim2.new(1, -24, 0, 14), { Position = UDim2.fromOffset(12, 70), TextStrokeTransparency = 1, TextSize = 10 })
	-- The courier ID.
	local card = block(parent, 2)
	local nameRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 2 }, card)
	text(nameRow, player.DisplayName, UDim2.new(1, -84, 1, 0), { Font = Theme.HeadingFont, TextSize = 16, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	refs.idMoney = text(nameRow, "", UDim2.fromOffset(84, 22), { Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = 15, TextColor3 = K.text, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right })
	refs.idRank = caps(card, "", 3, K.text)
	local holder = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = 4 }, card)
	local back, fill = P.bar(holder, UDim2.new(1, 0, 0, 3), K.text)
	back.Position = UDim2.fromOffset(0, 2)
	refs.idXp = fill
	refs.idTransport = caps(card, "", 5)
	-- 5.1: the quick switch (fillHome shows it when you own a bike): MY BIKE, and CALL CAR with a car of your own too.
	local switch = Ui.make("Frame", { Name = "Switch", Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, LayoutOrder = 6, Visible = false }, card)
	Ui.list(switch, false, 6)
	local function switchButton(label: string, order: number, how: string): any
		local made = P.button(switch, label, UDim2.new(0.5, -3, 1, 0), "quiet", function()
			Net.get("Equip"):FireServer(how)
			Phone.close()
		end)
		made.LayoutOrder = order
		made.TextSize = 12
		squareButton(made)
		return made
	end
	refs.switch = switch
	refs.rideBike = switchButton("🚲 MY BIKE", 1, "ride")
	refs.callCar = switchButton("🚐 CALL CAR", 2, "drive")
	-- 5.4: TOW, while your own car's tank is empty (fillHome and the ticker show it).
	refs.tow = button(card, `⛽ TOW  {Ui.money(Config.Fuel.TowPrice)}`, "main", 7, function()
		Net.get("Fuel"):FireServer("tow")
		Phone.close()
	end)
	refs.tow.Visible = false
	refs.towShown = function(): boolean
		local cars = workspace:FindFirstChild("Cars")
		for _, car in if cars then cars:GetChildren() else {} do
			if car:GetAttribute("OwnerId") == player.UserId then
				local tank, fuel = car:GetAttribute("Tank"), car:GetAttribute("Fuel")
				return type(tank) == "number" and tank > 0 and type(fuel) == "number" and fuel <= 1e-3
			end
		end
		return false
	end
	refs.homeContract = refs.design.card(parent, function()
		launch(if job then "orders" else "board", refs.homeContract.hit)
	end, 3)
	-- The newest unread message, like a notification (a tap opens MESSAGES).
	local note = Ui.make("TextButton", {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = K.row,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = 6,
		Visible = false,
	}, parent)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.82 }, note)
	Ui.list(note, true, 2)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 8) }, note)
	refs.noteFrom = caps(note, "", 1, K.text)
	refs.noteText = text(note, "", UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextSize = 12, TextColor3 = K.secondary, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 64) }, refs.noteText)
	refs.note = note
	note.Activated:Connect(function()
		launch("messages", note)
	end)
end

-- Fills the home widgets with the state right now.
local function fillHome()
	if not refs.idMoney then
		return
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local pos = if root and root:IsA("BasePart") then root.Position else nil
	refs.design.updateCard(refs.homeContract, refs.layout.summary(job, workspace:GetServerTimeNow(), if pos then pos.X else nil, if pos then pos.Z else nil))
	local level = myLevel()
	refs.idMoney.Text = Ui.money(money())
	refs.idRank.Text = `{string.upper(Levels.rank(level))} · LEVEL {level}`
	refs.idXp.Size = UDim2.fromScale(Levels.progress(myXp()), 1)
	refs.idTransport.Text = transportText()
	-- 5.1: the quick switch: which of a bike and a car of your own you have.
	local hasBike, hasCar = false, false
	for _, def in Config.Cars do
		if state and type(state.cars) == "table" and state.cars[def.id] and not def.company then
			hasBike = hasBike or def.bike == true
			hasCar = hasCar or not def.bike
		end
	end
	refs.switch.Visible = hasBike
	refs.callCar.Visible = hasCar
	refs.rideBike.Size = if hasCar then UDim2.new(0.5, -3, 1, 0) else UDim2.new(1, 0, 1, 0)
	refs.tow.Visible = refs.towShown() -- 5.4
	local newest: Message? = nil
	for _, message in messages do
		if message.unread then
			newest = message
		end
	end
	refs.note.Visible = newest ~= nil
	if newest then
		refs.noteFrom.Text = `💬 {string.upper(newest.from)} · {newest.time}`
		refs.noteText.Text = newest.text
	end
end

-- The phone: its body, the screen, the status bar and the home screen (6.0.1: always upright; the apps open in the
-- popup, client/PhonePopup.luau).
local function buildBody()
	local made = gui :: ScreenGui
	refs.route = nil
	refs.spareRoute = nil
	if refs.body then
		refs.body:Destroy()
	end
	table.clear(tiles)
	refs.idMoney = nil
	local size = refs.fit or refs.layout.fit(1150, 680, false, 1)
	local body = Ui.make("Frame", {
		Name = "Phone",
		Size = UDim2.fromOffset(size.width, size.height),
		BackgroundColor3 = BODY,
		BorderSizePixel = 0,
		Visible = false,
		Active = true, -- (clicks on the phone do not reach the world)
	}, made)
	refs.body = body
	Ui.corner(body, 18)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = BODY_EDGE, Thickness = 1.5 }, body)
	refs.scale = Ui.make("UIScale", {}, body)
	-- The side keys (power on the right, the volume on the left).
	Ui.make("Frame", { Size = UDim2.fromOffset(3, 60), Position = UDim2.new(1, 0, 0, 120), BackgroundColor3 = BODY_EDGE, BorderSizePixel = 0 }, body)
	Ui.make("Frame", { Size = UDim2.fromOffset(3, 36), Position = UDim2.new(0, -3, 0, 100), BackgroundColor3 = BODY_EDGE, BorderSizePixel = 0 }, body)
	Ui.make("Frame", { Size = UDim2.fromOffset(3, 36), Position = UDim2.new(0, -3, 0, 144), BackgroundColor3 = BODY_EDGE, BorderSizePixel = 0 }, body)
	local screen = Ui.make("Frame", {
		Name = "Screen",
		Size = UDim2.new(1, -BEZEL * 2, 1, -BEZEL * 2),
		Position = UDim2.fromOffset(BEZEL, BEZEL),
		BackgroundColor3 = SCREEN,
		BorderSizePixel = 0,
		ClipsDescendants = true, -- (5.5: the banner drops in from above the screen)
	}, body)
	Ui.corner(screen, 12)
	refs.screen = screen
	local STATUS_H = 30
	refs.statusH = STATUS_H
	statusBar(screen, STATUS_H)
	-- The NEW PHONE ribbon (the moment Marge gives it).
	refs.ribbon = P.tag(screen, "New phone", K.red)
	refs.ribbon.AnchorPoint = Vector2.new(0.5, 0)
	refs.ribbon.Position = UDim2.new(0.5, 0, 0, STATUS_H + 2)
	refs.ribbon.ZIndex = 6
	refs.ribbon.Visible = false
	-- The home bar at the bottom: it puts the phone away (6.0.1: the apps close in their popup).
	local homeBar = Ui.make("TextButton", {
		Name = "HomeBar",
		Size = UDim2.new(0, 196, 0, 54),
		Position = UDim2.new(0.5, 0, 1, -2),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "CLOSE",
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.secondary,
		ZIndex = 5,
	}, screen)
	local pill = Ui.make("Frame", { Size = UDim2.fromOffset(104, 2), Position = UDim2.new(.5,0,1,-5), AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = K.text, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 5 }, homeBar)
	Ui.corner(pill, 2)
	homeBar.MouseEnter:Connect(function()
		pill.BackgroundTransparency = 0
	end)
	homeBar.MouseLeave:Connect(function()
		pill.BackgroundTransparency = 0.25
	end)
	homeBar.Activated:Connect(function()
		click()
		Phone.close()
	end)
	refs.homeBar = homeBar
	local BOTTOM = 56
	-- Scrollable home: cards and launcher never overlap, even with transport/tow actions or long messages.
	local home = Ui.make("ScrollingFrame", {
		Name = "Home", Size = UDim2.new(1, -24, 1, -(STATUS_H + BOTTOM)), Position = UDim2.fromOffset(12, STATUS_H),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 2, ScrollBarImageColor3 = K.line, AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(), ClipsDescendants = true,
	}, screen)
	refs.home = home
	local widgets = Ui.make("Frame", {
		Name = "Widgets", Size = UDim2.new(1, -4, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
	}, home)
	Ui.list(widgets, true, 8)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 16) }, widgets)
	homeWidgets(widgets)
	local grid = Ui.make("Frame", {
		-- (5.5: four to a row, as many rows as the apps need; home scrolls)
		Name = "Apps", Size = UDim2.new(1, 0, 0, math.ceil(#APPS / 4) * 96 - 8),
		BackgroundTransparency = 1, LayoutOrder = 5,
	}, widgets)
	Ui.make("UIGridLayout", {
		CellSize = UDim2.new(.25, -6, 0, 88), CellPadding = UDim2.fromOffset(8, 8), FillDirectionMaxCells = 4,
		HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	for order, def in APPS do
		local cell = tile(grid, def, order)
		if order == 1 then refs.firstTile = cell end
	end
end

-- ── Showing ────────────────────────────────────────────────────────────────

local APP_TITLES: { [string]: string } = { orders = "ORDERS", career = "CAREER", shop = "SHOP", messages = "MESSAGES", bank = "BALANCE", settings = "SETTINGS", board = "JOB BOARD", bag = "BAG", garage = "GARAGE" }

-- Home in the phone, or (6.0.1) the app in its centred popup over the phone (client/PhonePopup.luau).
renderApp = function()
	if not refs.body then
		return
	end
	refs.timer = nil
	local previousRoute = refs.route
	refs.route = nil
	if previousRoute then
		if app == "orders" and job and previousRoute.destination == job.position then
			-- Keep the road/fog instances when only cargo or the countdown changed in another Job payload.
			previousRoute.holder.Parent = nil
			refs.spareRoute = previousRoute
		else
			previousRoute.holder:Destroy()
		end
	end
	OrdersUi.clear()
	if app == "home" then
		refs.popup.hide()
		fillHome()
		local back = refs.lastTile
		Ui.gamepadFocus(if back and back.Parent and back.Visible then back else refs.firstTile)
		return
	end
	local list, wide = refs.popup.show(app, APP_TITLES[app] or string.upper(app), refs.from)
	refs.from = nil
	local ok, err = pcall(function()
		if app == "orders" then
			ordersApp(list)
		elseif app == "career" then
			careerApp(list, wide)
		elseif app == "shop" then
			shopApp(list, wide)
		elseif app == "messages" then
			messagesApp(list)
		elseif app == "bank" then
			local balance = block(list, 1)
			caps(balance, "AVAILABLE CASH", 1)
			text(balance, Ui.money(money()), UDim2.new(1, 0, 0, 44), { Font = Theme.DisplayFont, TextSize = 32, LayoutOrder = 2 })
			look.meta(balance, "Your current courier balance. Earn money by completing deliveries.", 3)
			look.row2(balance, "Earned since you joined", `+{Ui.money(refs.earned or 0)}`, 4, true) -- 5.5
			button(list, "FIND A DELIVERY", "main", 2, function() launch("board") end)
		elseif app == "settings" then
			local controls = block(list, 1)
			caps(controls, "PHONE CONTROLS", 1)
			look.meta(controls, if Ui.touchLayout() then "Tap an app to open it. The ✕ or a tap beside it returns to the phone; the bottom bar puts the phone away." else "Q opens the phone; Q, ESC or the ✕ close an app, then the phone. T opens the weapon wheel. Hold right mouse to turn the camera while only the phone is open.", 2)
			look.meta(controls, "Sound cycles: everything on → music off → all off. The selected mode is shown in the game's notification.", 3)
			button(list, "CYCLE SOUND MODE", "quiet", 2, function()
				local cycle = Phone.onSound -- 5.5 (Main: Sounds.cycle)
				if cycle then
					cycle()
				else
					require(script.Parent.Sounds).cycle()
				end
			end)
			button(list, "PUT PHONE AWAY", "main", 3, Phone.close)
			refs.apps.keys(list, look, 4) -- 5.5: every key, the version
		elseif app == "board" then
			refs.apps.board(list, look, refs.host, wide) -- 5.5; 6.0.1: two columns in a wide popup
		elseif app == "bag" then
			refs.apps.bag(list, look, refs.host)
		elseif app == "garage" then
			refs.apps.garage(list, look, refs.host)
		end
	end)
	if refs.spareRoute then
		refs.spareRoute.holder:Destroy()
		refs.spareRoute = nil
	end
	if not ok then
		warn(`[Phone] the {app} app failed: {err}`)
	end
	refs.popup.focus()
end

-- Can anything in the SHOP app be bought right now (your level, your money)?
local function affordable(): boolean
	local owned = kit()
	local level = myLevel()
	for _, def in Config.Kit do
		local outgrown = def.room ~= nil and def.speed == nil and def.warm == nil and def.room <= Transport.backpackRoom(owned)
		if not owned[def.id] and not outgrown and level >= def.level and money() >= def.price then
			return true
		end
	end
	return false
end

refreshBadges = function()
	local unread = unreadCount()
	local function set(id: string, count: number, word: string?)
		local badge = tiles[id]
		if badge then
			badge.Visible = count > 0 or word ~= nil
			badge.Text = word or (if count > 9 then "9+" else tostring(count))
			badge.Size = UDim2.fromOffset(if (word or "") ~= "" or count > 9 then 24 else 18, 18)
		end
	end
	set("messages", unread)
	set("board", boardNew)
	local open = 0 -- 5.2: the orders on the go
	if job then
		open = 1
		if type(job.orders) == "table" then
			open = 0
			for _, entry in job.orders do
				if type(entry) == "table" and entry.state == "open" then
					open += 1
				end
			end
		end
	end
	set("orders", open)
	set("shop", 0, if affordable() then "$" else nil)
	set("garage", 0, if refs.apps.towDue() then "!" else nil) -- 5.5: the tank ran dry: TOW
	local dot = refs.buttonDot
	if dot then
		local total = unread + (if boardNew > 0 then 1 else 0)
		dot.Visible = total > 0
		dot.Text = if unread > 9 then "9+" elseif unread > 1 then tostring(unread) else ""
		dot.Size = UDim2.fromOffset(if unread > 9 then 20 else 14, 14)
	end
	if isOpen and app == "home" then
		fillHome()
	end
end

-- The phone's scale for this screen (6.0.1: always upright; a short screen gets a shorter body that scrolls).
local function fit(): number
	local screen = Ui.screenSize()
	local cap = if Ui.touchLayout() then 1 else math.clamp(Ui.screenScale() * 0.95, 0.85, 1)
	refs.fit = refs.layout.fit(screen.X, screen.Y, Ui.touchLayout(), cap)
	return refs.fit.scale
end

-- Where the phone rests (and where it slides from).
local function restPosition(): (UDim2, UDim2)
	return UDim2.new(1, -24, 1, -16), UDim2.new(1, -24, 1, 40)
end

local function hudOn(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	return hud ~= nil and hud:IsA("ScreenGui") and hud.Enabled
end

-- Shows an app (6.0.1: in the centred popup) or home (the popup closes).
setApp = function(id: string)
	if not refs.body then
		return
	end
	app = id
	renderApp()
end

-- The clock, the timer and the shift while the phone is open (twice a second).
local ticking = false
local function startTicker()
	if ticking then
		return
	end
	ticking = true
	task.spawn(function()
		local lastErr: string? = nil
		while isOpen do
			-- 5.7: one bad tick (a missing ref, an app's error) is warned once and skipped: the loop never dies, so
			-- `ticking` never sticks on true with no clock running.
			local ok, err = pcall(function()
				local now = clockText()
				if refs.statusTime then
					refs.statusTime.Text = now
				end
				if refs.shift then refs.shift.Text = shiftText() end
				if app == "home" then fillHome() end
				local timer = refs.timer
				if timer and job and type(job.endsAt) == "number" then
					local left = job.endsAt - workspace:GetServerTimeNow()
					timer.Text = Ui.clock(math.max(0, left))
					timer.TextColor3 = if left < 30 then K.red else K.text
				end
				if app == "orders" then
					OrdersUi.tick() -- 5.2: every order's clock
					if refs.route then refs.route.update() end
				end
				if refs.tow and refs.idMoney then
					refs.tow.Visible = refs.towShown() -- 5.4: the tank ran dry (or the tow came)
				end
				local due = refs.apps.towDue() -- 5.5: GARAGE's badge and its TOW
				if due ~= refs.towDue then
					refs.towDue = due
					refreshBadges()
					if app == "garage" then
						renderApp()
					end
				end
			end)
			if not ok and tostring(err) ~= lastErr then
				lastErr = tostring(err)
				warn(`[Phone] ticker: {err}`)
			end
			task.wait(0.5)
		end
		ticking = false
	end)
end

function Phone.isOpen(): boolean
	return isOpen
end

-- 6.0.1: is an app open in its popup over the phone? (Main: no right-mouse camera then, the mouse is needed.)
function Phone.appOpen(): boolean
	return isOpen and refs.popup.isOpen()
end

-- 6.0.1: Q, ESC and the gamepad's B: an open app closes first (back to the phone's home), then the phone. (ESC can
-- arrive twice, as the Roblox menu and as the key: the menu that just closed an app leaves the phone open.)
function Phone.back()
	if not isOpen then
		return
	end
	if refs.popup.isOpen() then
		setApp("home")
	elseif os.clock() - (refs.menuAt or -1) > 0.3 then
		Phone.close()
	end
end

-- 5.5: does the player have the phone (Marge gave it)? The HUD's MENU opens it then (Main: Hud.onMenu).
function Phone.has(): boolean
	return hasPhone()
end

function Phone.close()
	if not isOpen then
		return
	end
	isOpen = false
	app = "home"
	-- 6.0.1: an open app goes with it (its popup, its route chart, its timers).
	local route = refs.route
	refs.route = nil
	refs.timer = nil
	refs.from = nil
	if route then
		route.holder:Destroy()
	end
	OrdersUi.clear()
	refs.popup.hide()
	Net.get("PhoneHold"):FireServer(false) -- (5.0: the phone leaves your hand: server/KitWear.luau)
	local body = refs.body
	if body then
		Ui.gamepadRelease(body)
		if refs.motion.reducedMotion() then
			body.Visible = false
		else
			local _, hidden = restPosition()
			local tween = TweenService:Create(body, SLIDE_OUT, { Position = hidden })
			tween.Completed:Connect(function()
				if not isOpen then
					body.Visible = false
				end
			end)
			tween:Play()
		end
	end
	if refs.buttonLine then
		refs.buttonLine.BackgroundTransparency = 1
	end
	task.delay(0.2, placeButton)
end

local openPhone: (startApp: string?) -> ()

-- 5.4.1: a phone that fails to open says why in the Output (it was a silent no-op) and is put away cleanly.
function Phone.open(startApp: string?)
	local ok, err = pcall(function()
		openPhone(startApp)
	end)
	if not ok then
		warn(`[Phone] it failed to open: {err}`)
		if isOpen then
			Net.get("PhoneHold"):FireServer(false)
		end
		isOpen = false
		if refs.body then
			refs.body.Visible = false
		end
	end
end

openPhone = function(startApp: string?)
	if not gui then
		warn("[Phone] not built yet")
		return
	end
	if not hasPhone() then
		local tell = Phone.notify
		if tell then
			tell("No phone yet: Marge by the job board gives you one.")
		end
		return
	end
	local hook = Phone.onOpen
	if hook then
		pcall(hook) -- (the other windows close; their onCloseWindows closes nothing open here yet)
	end
	local scale = fit()
	if not refs.body then
		buildBody()
	end
	refs.body.Size = UDim2.fromOffset(refs.fit.width, refs.fit.height)
	refs.scale.Scale = scale
	local body = refs.body
	body.AnchorPoint = Vector2.new(1, 1)
	local rest, hidden = restPosition()
	app = startApp or "home"
	if not isOpen then
		Net.get("PhoneHold"):FireServer(true) -- (5.0: everybody sees it in your hand while you are on foot: server/KitWear.luau)
	end
	isOpen = true
	renderApp()
	refreshBadges()
	local reduced = refs.motion.reducedMotion()
	if not body.Visible or reduced then
		body.Position = if reduced then rest else hidden
	end
	body.Visible = true
	TweenService:Create(body, SLIDE, { Position = rest }):Play()
	if refs.buttonLine then
		refs.buttonLine.BackgroundTransparency = 0
	end
	placeButton()
	if app == "home" then
		Ui.gamepadFocus(refs.firstTile)
	end
	startTicker()
end

function Phone.toggle()
	if isOpen then
		Phone.close()
	else
		Phone.open()
	end
end

-- ── The PHONE action (lower right) ─────────────────────────────────────────

local function buildButton(made: ScreenGui)
	local touch = Ui.touchLayout()
	local action = Ui.make("TextButton", {
		Name = "PhoneButton",
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -16, 1, -220),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		Visible = false,
	}, made)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, action)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 2) }, action)
	Ui.make("UISizeConstraint", { MinSize = Vector2.new(44, 44) }, action)
	refs.buttonScale = Ui.make("UIScale", {}, action)
	-- The little phone: a rounded outline with its screen and a home bar.
	local glyph = Ui.make("Frame", { Size = UDim2.fromOffset(13, 22), BackgroundColor3 = K.charcoal, BackgroundTransparency = 0.3, BorderSizePixel = 0, LayoutOrder = 1 }, action)
	Ui.corner(glyph, 3)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.text, Thickness = 1.5 }, glyph)
	Ui.make("Frame", { Size = UDim2.new(1, -6, 0, 1), Position = UDim2.new(0, 3, 1, -4), BackgroundColor3 = K.text, BorderSizePixel = 0 }, glyph)
	local label = P.text(action, if touch then "PHONE" else "PHONE  [Q]", UDim2.fromOffset(0, 44), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = K.secondary,
		LayoutOrder = 2,
	})
	local line = Ui.make("Frame", { Name = "Underline", Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 0.5, 11), BackgroundColor3 = K.red, BackgroundTransparency = 1, BorderSizePixel = 0 }, label)
	refs.buttonLine = line
	P.hover(action, line, label)
	refs.buttonDot = P.dot(glyph, { Position = UDim2.new(1, 3, 0, 1) })
	action.Activated:Connect(function()
		click()
		Phone.toggle()
	end)
	refs.button = action
end

-- Puts the PHONE action just over the weapon line (the HUD's right column), at its scale; left of the column when that
-- would run into the MENU row (a touch screen with the column over the buttons). Twice a second while it shows.
placeButton = function()
	local action = refs.button
	local made = gui
	if not action or not made then
		return
	end
	local shown = hasPhone() and hudOn() and not isOpen -- (the open phone covers its place)
	if action.Visible ~= shown then
		action.Visible = shown
	end
	if not shown then
		return
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	local right = hud and hud:FindFirstChild("RightStack")
	local weapon = right and right:FindFirstChild("WeaponBar")
	if not (right and weapon and right:IsA("GuiObject") and weapon:IsA("GuiObject")) then
		return
	end
	local layoutScale = right:FindFirstChild("LayoutScale")
	local s = if layoutScale and layoutScale:IsA("UIScale") then layoutScale.Scale else 1
	if Ui.touchLayout() then
		s = math.max(s, 0.8)
	end
	if math.abs(refs.buttonScale.Scale - s) > 0.001 then
		refs.buttonScale.Scale = s
	end
	local origin = made.AbsolutePosition
	local columnRight = right.AbsolutePosition.X + right.AbsoluteSize.X - origin.X
	local top = weapon.AbsolutePosition.Y - origin.Y
	local x, y = columnRight, top - 4
	-- Clear of the MENU row (upper right) or the screen's top: then left of the column, level with the weapon line.
	local row = hud and hud:FindFirstChild("HudButtons")
	local rowBottom = if row and row:IsA("GuiObject") then row.AbsolutePosition.Y + row.AbsoluteSize.Y - origin.Y else 0
	if y - 44 * s < rowBottom + 8 then
		x = right.AbsolutePosition.X - origin.X - 8
		y = top + weapon.AbsoluteSize.Y
	end
	local position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
	if action.Position ~= position then
		action.Position = position
	end
end

-- ── The NEW PHONE moment ───────────────────────────────────────────────────

local function phoneMoment()
	if momentShown then
		return
	end
	momentShown = true
	seed()
	addMessage("Marge", "That's my old phone. It's yours now: ORDERS shows your run, BOARD the work, CAREER your road, SHOP what to save up for. Don't lose it.", "marge", true)
	local notify = Phone.notify
	if notify then
		notify(if Ui.touchLayout() then "📱 NEW PHONE · Marge gave you her old phone · tap PHONE" else "📱 NEW PHONE · Marge gave you her old phone · Q opens it")
	end
	-- It pops up once, when nothing covers the middle any more (her dialog, a result) and the state says it is yours.
	task.spawn(function()
		local waited = 0
		while waited < 60 do
			local blocked = Phone.blocked
			if hasPhone() and hudOn() and not (blocked and blocked()) then
				break
			end
			waited += task.wait(0.25)
		end
		if not hasPhone() or isOpen then
			return
		end
		Phone.open()
		local ribbon = refs.ribbon
		if ribbon then
			ribbon.Visible = true
			task.delay(4, function()
				if ribbon.Parent then
					ribbon.Visible = false
				end
			end)
		end
	end)
end

-- ── Updates ────────────────────────────────────────────────────────────────

function Phone.setState(newState: any)
	if type(newState) ~= "table" then
		return
	end
	state = newState
	-- 5.5: what you earned since you joined (BANK): every rise of your money.
	local cash = tonumber(state.money)
	if cash then
		local seen = refs.cashSeen
		if seen and cash > seen then
			refs.earned = (refs.earned or 0) + (cash - seen)
		end
		refs.cashSeen = cash
	end
	local now = state.phone == true
	if phoneBefore == false and now then
		phoneMoment() -- (the tutorial's message may not come: the state turning says it too)
	end
	phoneBefore = now
	if now then
		seed()
	end
	placeButton()
	refreshBadges()
	if isOpen then
		if app == "home" then
			fillHome()
		elseif app == "shop" or app == "career" or app == "bank" or app == "garage" then
			renderApp()
		end
	end
end

-- A level-up while you play: Marge's tips for it and the career's note go to MESSAGES.
local function onXp()
	if not seeded then
		return
	end
	local level = myLevel()
	local before = shownLevel or level
	shownLevel = level
	for n = before + 1, level do
		local summary = Career.summary(Career.unlocksAt(n), 3, if state and type(state.cars) == "table" then state.cars else nil)
		addMessage("Career", `Level {n} · {Levels.rank(n)}.{if summary ~= "" then ` Unlocked: {summary}.` else ""}`, "level", true)
		for _, tip in margeTips(n) do
			addMessage("Marge", tip, "marge", true)
		end
	end
	if isOpen and app == "home" then
		fillHome()
	end
end

-- New offers on the board (Net "Offers"): pushed by the server when the board refreshes. While the board is closed
-- the dispatcher texts you about them.
local function onOffers(list: any, refreshAt: any, info: any)
	if type(list) ~= "table" then
		return
	end
	local isNew = type(refreshAt) == "number" and refreshAt ~= lastRefreshAt
	lastRefreshAt = if type(refreshAt) == "number" then refreshAt else lastRefreshAt
	-- 5.5: the phone's own BOARD keeps the last board (and draws it again while it shows).
	refs.offers = list
	refs.offersInfo = info
	local inPhone = isOpen and app == "board"
	if inPhone then
		renderApp()
	end
	local dispatch = Phone.boardOpen
	local function boardOpen(): boolean
		return inPhone or (dispatch ~= nil and dispatch())
	end
	if not isNew or boardOpen() or not hasPhone() or job then
		if boardOpen() then
			boardNew = 0
			refreshBadges()
		end
		return
	end
	local open, walks, best = 0, 0, 0
	for _, offer in list do
		if type(offer) == "table" and offer.locked ~= true and offer.tooBig ~= true then
			open += 1
			if offer.mode == "foot" then
				walks += 1
			end
			best = math.max(best, tonumber(offer.pay) or 0)
		end
	end
	if open == 0 then
		return
	end
	boardNew = open
	-- (one dispatcher's note at a time: a newer board replaces the last one)
	for index = #messages, 1, -1 do
		if messages[index].kind == "board" then
			table.remove(messages, index)
		end
	end
	addMessage("Dispatch", `{open} new {if open == 1 then "run" else "runs"} on the board{if walks > 0 then ` · {walks} on foot` else ""}. Best pay {Ui.money(best)}. Open the BOARD app or press J.`, "board", true)
end

function Phone.start()
	local made = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryPhone",
		ResetOnSpawn = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, -- like the HUD: the same coordinates as its right column
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 2,
	}, player:WaitForChild("PlayerGui"))
	gui = made
	-- 5.5: what client/PhoneApps.luau's apps may know and do.
	refs.host = {
		job = function(): any
			return job
		end,
		state = function(): any
			return state
		end,
		board = function(): ({ any }?, any, number?)
			return refs.offers, refs.offersInfo, lastRefreshAt
		end,
		go = function(id: string)
			setApp(id)
		end,
		close = function()
			Phone.close()
		end,
		redraw = function()
			if isOpen then
				renderApp()
			end
		end,
		notify = function(message: string)
			local tell = Phone.notify
			if tell then
				tell(message)
			end
		end,
		fullBoard = function()
			local cb = Phone.onBoard
			if cb then
				cb() -- (the board's onOpen closes the phone)
			end
		end,
		transport = transportText,
	}
	buildButton(made)
	buildBody()
	refs.body.Visible = false
	Net.get("Job").OnClientEvent:Connect(function(payload)
		job = if type(payload) == "table" then payload else nil
		refreshBadges()
		if isOpen and app == "orders" then
			renderApp()
		end
	end)
	Net.get("Offers").OnClientEvent:Connect(onOffers)
	-- 5.0: the tutorial's "phone" (server/Tutorial.luau: Marge gives it). Only the name is shared; it may not come.
	Net.get("Tutorial").OnClientEvent:Connect(function(phase, data)
		if phase == "phone" then
			phoneMoment()
		elseif phase == "message" and type(data) == "table" and type(data.text) == "string" then
			-- 5.0: a text from the server (Marge about Earl's van, server/VanQuest.luau); `gps`: a landmark to route to.
			addMessage(if type(data.from) == "string" then data.from else "Marge", data.text, "marge", true)
			local gps = data.gps
			if type(gps) == "table" and type(gps.id) == "string" then
				gpsTo(gps.id)
			end
		end
	end)
	player:GetAttributeChangedSignal("Xp"):Connect(onXp)
	player:GetAttributeChangedSignal("PackCount"):Connect(function()
		if isOpen and app == "orders" then
			renderApp() -- 5.0: the backpack line
		end
	end)
	-- 6.0.1: the popup's ✕ and backdrop return to the phone's home.
	refs.popup.onClose = function()
		if isOpen then
			setApp("home")
		else
			refs.popup.hide()
		end
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if UserInputService:GetFocusedTextBox() then
			return
		end
		-- 6.0.1: ESC and the gamepad's B close an open app, then the phone (also when Roblox took the key).
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			Phone.back()
			return
		end
		if processed then
			return
		end
		if (input.KeyCode == KEY or input.KeyCode == PAD_KEY) and hudOn() and hasPhone() then
			if Phone.appOpen() then
				Phone.back() -- (6.0.1: Q closes the app first)
			else
				Phone.toggle()
			end
		end
	end)
	GuiService.MenuOpened:Connect(function()
		if Phone.appOpen() then
			refs.menuAt = os.clock()
			setApp("home") -- (the Roblox menu: the app closes, like a window; the phone stays)
		end
	end)
	-- The screen turned or resized: a phone that is open is fitted again (6.0.1: upright, and its app's popup).
	local camera = workspace.CurrentCamera
	if camera then
		local resized = 0
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			resized += 1
			local mine = resized
			task.delay(0.3, function()
				if mine ~= resized or not isOpen then
					return
				end
				local scale = fit()
				refs.body.Size = UDim2.fromOffset(refs.fit.width, refs.fit.height)
				refs.scale.Scale = scale
				refs.body.Position = (restPosition())
				if refs.popup.refit() and app ~= "home" then
					renderApp() -- (the popup's two columns came or went)
				end
			end)
		end)
	end
	task.spawn(function()
		while true do
			placeButton()
			if isOpen and not hudOn() then
				Phone.close()
			end
			task.wait(0.3)
		end
	end)
end

return Phone
