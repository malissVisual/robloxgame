--!strict
-- 5.0: the courier's phone. Marge gives it in the tutorial (profile.phone, the state's `phone`; the Tutorial remote's
-- "phone" message is the moment she does): from then on a PHONE action sits at the lower right, just over the weapon
-- line (client/Hud.luau's right column; on a touch screen left of that column when the MENU row is in the way), and
-- the O key opens it (Tab is Roblox's player list: this HUD keeps that list on screen and lays out around it, so Tab
-- would hide it with every press). A gamepad: the D-pad's down.
--
-- The phone slides up at the lower right (in the middle of a short touch screen, turned sideways: a phone held
-- upright would not be readable there): a rounded charcoal body with its side keys, the screen with a status bar (the
-- game's time from Lighting.ClockTime, server/DayNight.luau; the signal, the battery) and the home screen: the big
-- clock and the shift (day / night pay), your courier ID (rank, level, the XP line, cash, on foot or your vehicle), the
-- newest message, and six apps in the contract look (design/ui-contract/: charcoal tiles, fine lines, white caps, small
-- red badges):
--   ORDERS    your active job: the contract, where to, the stop and its step, the clock, the pay and the pieces
--             delivered; OPEN BOARD and SHOW ON MAP. Without one: OPEN BOARD. 5.3: 🎒 BAG opens your bag (the I
--             window's BAG tab, client/BagUi.luau).
--   BOARD     the Dispatch board (client/DispatchUi.luau, Phone.onBoard). Its badge counts the new runs the server
--             pushed while the board was closed.
--   CAREER    the career app: rank, level, XP, the next goal in work ("about 8 on-foot runs", client/CareerUi.luau),
--             what it opens, the next levels of the road (shared/Career.luau), and FULL CAREER (C, Phone.onCareer).
--   SHOP      what to buy next with your money and level: the personal gear at Last Stop Supplies (Config.Kit,
--             client/KitShop.luau), 5.1: the bikes at Spoke & Chain (SET GPS), the Old Van from Earl at Earl's Used Wheels (Marge's
--             quest at level 4, Config.VanQuest; SET GPS to Earl, Map.VanSeller), the next vehicles at Dead End
--             Motors; each with what is missing ($ to go, the level), SET GPS to the shop (MapView.setWaypoint).
--   MAP       the big map (MapView.toggle).
--   MESSAGES  Marge's tips for your level (the backpack, the bike shop, the Old Van, the car tiers: all from Config),
--             the dispatcher's new runs, your level-ups, and the texts the server sends (the Tutorial remote's
--             "message": Marge about Earl's van, server/VanQuest.luau; with `gps` it sets the GPS there). New ones put
--             a red dot on the PHONE action.
-- 5.1: the courier ID has the quick switch when you own a bike: 🚲 MY BIKE (the "Equip" remote's "ride": your bike
-- comes at once) and, with a car of your own too, 🚐 CALL CAR ("drive": back to your car, the chauffeur brings it).
-- 5.4: with your own car's tank empty (its Tank / Fuel attributes, server/Fuel.luau) the courier ID shows ⛽ TOW $150
-- (Config.Fuel.TowPrice; the "Fuel" remote's "tow": the server checks the tank and the money again and the tow brings the
-- car to the nearest gas station's pump with a little fuel in it).
-- The MENU and every key stay as they were (J, C, M ...); the phone is one more way in. Opening it closes the other
-- windows (Phone.onOpen, Main: Hud.closeWindows); ESC, O, the PHONE action or the home bar (on the home screen)
-- close it. While it is open the mouse is free (Main: CameraRig.mouseNeeded asks Phone.isOpen).
-- The NEW PHONE moment: on the Tutorial remote's "phone" (or the state's phone turning true while you play): a toast,
-- Marge's first message, and the phone pops up once, after her dialog is closed (Phone.blocked, set by Main).
-- Presentation only: the server decides everything (the remotes it opens are the ones the other windows use).

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
local Icons = require(Shared.Icons)
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
Phone.onBoard = nil :: (() -> ())? -- the BOARD app: DispatchUi.open
Phone.onCareer = nil :: (() -> ())? -- FULL CAREER: CareerUi.open
Phone.boardOpen = nil :: (() -> boolean)? -- is the Dispatch board open (DispatchUi.isOpen): no "new runs" then
Phone.blocked = nil :: (() -> boolean)? -- the NEW PHONE pop-up waits while this says so (Marge's dialog, a result)
Phone.notify = nil :: ((string) -> ())? -- a toast (Hud.toast)

local player = Players.LocalPlayer
local KEY = Enum.KeyCode.O
local PAD_KEY = Enum.KeyCode.DPadDown
local PORTRAIT = Vector2.new(300, 580) -- the body at scale 1, held upright
local LANDSCAPE = Vector2.new(600, 300) -- turned sideways (a short touch screen)
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
type AppDef = { id: string, name: string, glyph: string }

local APPS: { AppDef } = {
	{ id = "orders", name = "Orders", glyph = "📦" },
	{ id = "board", name = "Board", glyph = "📋" },
	{ id = "career", name = "Career", glyph = "🎖" },
	{ id = "shop", name = "Shop", glyph = "🛒" },
	{ id = "map", name = "Map", glyph = "🗺️" },
	{ id = "messages", name = "Messages", glyph = "💬" },
}

local state: any = nil
local job: any = nil
local gui: ScreenGui? = nil
local refs: { [string]: any } = {} -- the instances (one table: few locals)
local tiles: { [string]: any } = {} -- the app tiles' badges by app id
local isOpen = false
local app = "home"
local landscape: boolean? = nil -- the body's shape as built (nil: not built yet)
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
	return `🚶 ON FOOT · {KitShop.roomText(kit())}`
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

-- A block of the app's list: a slim charcoal row that grows with its children (a vertical list inside).
local function block(parent: Instance, order: number, selected: boolean?): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = if selected then K.raised else K.row,
		BorderSizePixel = 0,
		LayoutOrder = order,
	}, parent)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = if selected then 0.5 else 0.8 }, frame)
	if selected then
		Ui.make("Frame", { Name = "Selected", Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = K.red, BorderSizePixel = 0, ZIndex = 2 }, frame)
	end
	Ui.list(frame, true, 4)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 10) }, frame)
	return frame
end

-- A thin bar in a list (share 0 … 1).
local function bar(parent: Instance, share: number, color: Color3, order: number)
	local holder = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	local back, fill = P.bar(holder, UDim2.new(1, 0, 0, 3), color)
	back.Position = UDim2.fromOffset(0, 2)
	fill.Size = UDim2.fromScale(math.clamp(share, 0, 1), 1)
end

-- A window action inside the phone (P.button), full width.
local function button(parent: Instance, label: string, kind: P.ButtonKind, order: number, onClick: () -> ()): any
	local made = P.button(parent, label, UDim2.new(1, 0, 0, 44), kind, onClick)
	made.LayoutOrder = order
	made.TextSize = 13
	return made
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

local function ordersApp(list: Instance)
	if not job then
		local b = block(list, 1)
		caps(b, "No active order", 1, K.red)
		text(b, "Nothing in your hands right now. The board has work: on foot from level 1, quick light runs near you.", UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextColor3 = K.secondary, TextSize = 13 })
		button(list, "OPEN BOARD", "main", 2, function()
			local cb = Phone.onBoard
			if cb then
				cb()
			end
		end)
		return
	end
	local b = block(list, 1, true)
	local head = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 16), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
	P.marker(head, 7, { Position = UDim2.fromOffset(0, 4) })
	P.caps(head, `{if type(job.orders) == "table" and #job.orders > 1 then `Now · order {job.focus or "?"}` else "Active order"}{if job.mission then " · mission" else ""}`, UDim2.new(1, -14, 1, 0), { Position = UDim2.fromOffset(14, 0), TextStrokeTransparency = 1 })
	text(b, `{job.cargo or "Cargo"} → {job.customer or "the customer"}`, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Font = Theme.HeadingFont, TextSize = 17 })
	text(b, `{job.address or "?"}{if job.district then `, {job.district}` else ""}`, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, TextColor3 = K.secondary, TextSize = 13 })
	P.rule(b, UDim2.new(1, 0, 0, 1), { LayoutOrder = 4 })
	local stops = tonumber(job.stopCount) or 1
	local stop = tonumber(job.stopIndex) or 1
	caps(b, `Stop {stop} / {stops} · {if job.stage == "pickup" then "pick up" else "deliver"}`, 5)
	if type(job.step) == "string" and job.step ~= "" then
		text(b, job.step, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 6, TextSize = 14 })
	end
	-- The clock (ticked by the open loop) and the pay.
	local line = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = 7 }, b)
	refs.timer = text(line, "", UDim2.new(0.5, 0, 1, 0), { Font = Theme.HeadingFont, TextSize = 22, TextWrapped = false })
	text(line, Ui.money(tonumber(job.pay) or 0), UDim2.new(0.5, 0, 1, 0), { Position = UDim2.fromScale(0.5, 0), Font = Theme.HeadingFont, TextSize = 22, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right })
	local labels = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, LayoutOrder = 8 }, b)
	P.caps(labels, "Time left", UDim2.fromScale(0.5, 1), { TextStrokeTransparency = 1, TextSize = 11 })
	P.caps(labels, "Pay on delivery", UDim2.fromScale(0.5, 1), { Position = UDim2.fromScale(0.5, 0), TextStrokeTransparency = 1, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right })
	local total = tonumber(job.total) or 0
	if total > 0 then
		local done = tonumber(job.deliveredTotal) or 0
		caps(b, `{done} / {total} {if total == 1 then (job.piece or "piece") else (job.pieces or "pieces")} delivered{if (tonumber(job.lost) or 0) > 0 then ` · {job.lost} lost` else ""}`, 9)
		bar(b, done / total, K.text, 10)
	end
	-- 5.0, on foot: what rides in your backpack (the payload's pack / packRoom; the PackCount attribute is live).
	local packRoom = tonumber(job.packRoom) or tonumber(player:GetAttribute("PackRoom")) or 0
	if (job.mode == "foot" or job.mode == "bike") and packRoom > 0 then
		local packed = tonumber(player:GetAttribute("PackCount")) or tonumber(job.pack) or 0
		caps(b, `{if job.mode == "bike" then "🚲 On the bike" else "🎒 Backpack"} {packed} / {packRoom}`, 11, if packed >= packRoom then K.red else K.secondary)
	end
	local condition = tonumber(job.condition)
	if condition and condition < 0.999 then
		caps(b, `Cargo condition {math.floor(condition * 100 + 0.5)}%`, 12, if condition < 0.5 then K.red else K.secondary)
	end
	if type(job.ruleLine) == "string" and job.ruleLine ~= "" then
		text(b, job.ruleLine, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 13, TextColor3 = K.secondary, TextSize = 13 })
	end
	-- 5.2: every order of the run (its stops, clock, pay, PIN), then the actions.
	OrdersUi.render(list, job, { block = block, caps = caps, text = text, button = button }, 2)
	-- 5.3: the bag (client/BagUi.luau: every piece you carry and where; the I window's BAG tab).
	local bag = require(script.Parent.BagUi)
	button(list, `🎒 BAG{if bag.line(job) then ` · {string.sub(bag.line(job) or "", 6)}` else " · empty"}`, "quiet", 89, function()
		Phone.close()
		bag.open()
	end)
	local stack = job.stack
	button(list, "SHOW ON MAP", "quiet", 90, function()
		Phone.close()
		if not MapView.isOpen() then
			MapView.toggle()
		end
	end)
	button(list, if type(stack) == "table" and stack.can == true then "OPEN BOARD · + ADD ORDER" else "OPEN BOARD", "quiet", 91, function()
		local cb = Phone.onBoard
		if cb then
			cb()
		end
	end)
end

local function careerApp(list: Instance)
	local xp = myXp()
	local level = myLevel()
	local road = Career.road()
	local b = block(list, 1, true)
	caps(b, "Dead End Dispatch · your career", 1)
	text(b, string.upper(Levels.rank(level)), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Font = Theme.DisplayFont, TextSize = 22 })
	caps(b, `Level {level} of {Config.Levels.MaxLevel} · {string.sub(Career.money(xp), 2)} XP`, 3, K.text)
	bar(b, Levels.progress(xp), K.text, 4)
	local nextStep = road[level + 1]
	if nextStep then
		local left = math.max(0, nextStep.xp - xp)
		local g = block(list, 2)
		caps(g, `Next goal · level {nextStep.level}{if nextStep.newRank then ` · {nextStep.rank}` else ""}`, 1, K.red)
		text(g, `{string.sub(Career.money(left), 2)} XP to go: about {CareerUi.toGo(left, level)}.`, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextSize = 14 })
		local opens: { string } = {}
		for _, unlock in nextStep.unlocks do
			if unlock.kind ~= "stage" or (state and type(state.cars) == "table" and state.cars[unlock.car or ""]) then
				table.insert(opens, CareerUi.unlockText(unlock))
			end
		end
		if #opens > 0 then
			text(g, table.concat(opens, "\n", 1, math.min(#opens, 5)), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, TextColor3 = K.secondary, TextSize = 13 })
		end
		local parts = Career.rewardParts(nextStep.reward)
		if #parts > 0 then
			text(g, `Reward: {table.concat(parts, " · ")}`, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 4, TextColor3 = K.good, TextSize = 13 })
		end
	end
	-- The next few levels of the road.
	local r = block(list, 3)
	caps(r, "The road ahead", 1)
	local shown = 0
	for n = level + 2, Config.Levels.MaxLevel do
		local step = road[n]
		if not step or shown >= 3 then
			break
		end
		shown += 1
		local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 + shown }, r)
		local stone = Ui.label(row, tostring(n), UDim2.fromOffset(24, 24), { BackgroundColor3 = K.charcoal, BackgroundTransparency = 0, Font = Theme.HeadingFont, TextSize = 12, TextColor3 = K.secondary, TextXAlignment = Enum.TextXAlignment.Center })
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.5 }, stone)
		local summary = Career.summary(step.unlocks, 3, if state and type(state.cars) == "table" then state.cars else {})
		text(row, if summary ~= "" then summary else "better pay and harder roads", UDim2.new(1, -34, 0, 0), { Position = UDim2.fromOffset(34, 3), AutomaticSize = Enum.AutomaticSize.Y, TextColor3 = K.secondary, TextSize = 13 })
	end
	if shown == 0 then
		text(r, "The top of the road is close.", UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextColor3 = K.secondary, TextSize = 13 })
	end
	button(list, if Ui.touchLayout() then "FULL CAREER" else "FULL CAREER  [C]", "main", 4, function()
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
	local head = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
	text(head, `{icon}  {name}`, UDim2.new(1, -96, 1, 0), { Font = Theme.HeadingFont, TextSize = 15, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	local status: string, color: Color3
	if soon then
		status, color = soon, K.secondary
	elseif myLevel() < level then
		status, color = `🔒 LEVEL {level}`, K.warn
	elseif mine >= price then
		status, color = "✓ AFFORD IT", K.good
	else
		status, color = `{Ui.money(price - mine)} TO GO`, K.secondary
	end
	text(head, status, UDim2.new(0, 96, 1, 0), { Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = 11, TextColor3 = color, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right })
	caps(b, if price > 0 then `{where} · {Ui.money(price)} · level {level}` else `{where} · level {level}`, 2)
	if not soon then
		bar(b, if price > 0 then mine / price else 1, if mine >= price and myLevel() >= level then K.good else K.text, 3)
	end
end

-- A shop's header in the SHOP app with SET GPS.
local function shopHeader(parent: Instance, order: number, shopId: string, title: string)
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = order }, parent)
	P.caps(row, title, UDim2.new(1, -100, 1, 0), { TextStrokeTransparency = 1, TextColor3 = K.text })
	local gps = P.button(row, "SET GPS", UDim2.fromOffset(92, 32), "quiet", function()
		gpsTo(shopId)
		local notify = Phone.notify
		local shop = Map.Shops[shopId]
		if notify then
			notify(`GPS: {if shop then shop.name elseif shopId == "earl" then Config.VanQuest.Place else title}`)
		end
	end)
	gps.TextSize = 11
	gps.AnchorPoint = Vector2.new(1, 0.5)
	gps.Position = UDim2.new(1, 0, 0.5, 0)
end

local function shopApp(list: Instance)
	local level = myLevel()
	local top = block(list, 1)
	caps(top, "What's next", 1, K.red)
	text(top, `{Ui.money(money())} in your pocket · level {level}. Personal gear is yours for good; a vehicle opens the car jobs.`, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextColor3 = K.secondary, TextSize = 13 })
	local order = 1
	-- The personal gear still worth buying (Config.Kit), the cheapest first.
	local owned = kit()
	local room = Transport.handsRoom(owned)
	local wanted: { Config.KitDef } = {}
	for _, def in Config.Kit do
		local outgrown = def.room ~= nil and def.speed == nil and def.warm == nil and def.room <= room
		if not owned[def.id] and not outgrown then
			table.insert(wanted, def)
		end
	end
	table.sort(wanted, function(a: Config.KitDef, b: Config.KitDef): boolean
		return a.price < b.price
	end)
	if #wanted > 0 then
		order += 1
		shopHeader(list, order, "supplies", "Last Stop Supplies · kit")
		for _, def in wanted do
			order += 1
			goal(list, order, def.icon, def.name, "Last Stop Supplies", def.price, def.level)
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
			shopHeader(list, order, "bikes", "Spoke & Chain · bikes")
			order += 1
		end
		goal(list, order, if def.stand then "🛴" else "🚲", def.name, `Spoke & Chain, {Config.BikeShop.Street}`, def.price, def.level or 1)
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
			shopHeader(list, order, "earl", `{Config.VanQuest.Place} · {def.name}`)
			order += 1
			goal(list, order, "🚐", def.name, if quest then `{Config.VanQuest.Seller}, far out west` else "Marge's quest", def.price, def.level or 1)
			continue
		end
		if not dealerShown then
			dealerShown = true
			shopHeader(list, order, "dealer", "Dead End Motors · vehicles")
			order += 1
		end
		goal(list, order, "🚐", def.name, "Dead End Motors", def.price, def.level or 1)
	end
end

local function messagesApp(list: Instance)
	if #messages == 0 then
		text(list, "No messages yet.", UDim2.new(1, 0, 0, 40), { TextColor3 = K.secondary, TextXAlignment = Enum.TextXAlignment.Center })
		return
	end
	local order = 0
	for index = #messages, 1, -1 do
		local message = messages[index]
		order += 1
		local b = block(list, order, message.unread)
		local head = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
		local avatar = Ui.label(head, string.upper(string.sub(message.from, 1, 1)), UDim2.fromOffset(22, 22), {
			BackgroundColor3 = if message.kind == "marge" then K.red elseif message.kind == "level" then K.text else K.charcoal,
			BackgroundTransparency = 0,
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = if message.kind == "level" then K.charcoal else K.text,
			TextXAlignment = Enum.TextXAlignment.Center,
		})
		Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.5 }, avatar)
		P.caps(head, message.from, UDim2.new(1, -80, 1, 0), { Position = UDim2.fromOffset(30, 0), TextStrokeTransparency = 1, TextColor3 = K.text })
		P.caps(head, message.time, UDim2.fromOffset(50, 22), { Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Right, TextSize = 11 })
		text(b, message.text, UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextSize = 13, TextColor3 = if message.unread then K.text else K.secondary })
	end
	-- Read now (the dots go; the rows keep their red rule until the app is drawn again).
	for _, message in messages do
		message.unread = false
	end
	refreshBadges()
end

-- ── Building ───────────────────────────────────────────────────────────────

local function setApp(id: string)
	app = id
	renderApp()
end

local function launch(id: string)
	click()
	if id == "board" then
		boardNew = 0
		refreshBadges()
		local cb = Phone.onBoard
		if cb then
			cb() -- (the board's onOpen closes the phone)
		end
	elseif id == "map" then
		Phone.close()
		if not MapView.isOpen() then
			MapView.toggle()
		end
	else
		setApp(id)
	end
end

-- An app tile: a raised charcoal square with the glyph, its name under it, a red badge.
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
	Ui.corner(face, 14)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.6 }, face)
	-- (the app's icon, art/icons/app_*, once uploaded: shared/Icons.luau; the emoji until then)
	Ui.icon(face, Icons.app(def.id), def.glyph, UDim2.fromOffset(34, 34), {
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Font,
		ImageColor3 = K.text,
	})
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
	Ui.corner(badge, 9)
	tiles[def.id] = badge
	cell.Activated:Connect(function()
		launch(def.id)
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

-- The home screen's widgets: the clock and the shift, your courier ID, the newest message.
local function homeWidgets(parent: Instance)
	refs.bigClock = text(parent, clockText(), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Font = Theme.DisplayFont, TextSize = if landscape then 36 else 46, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
	refs.shift = P.caps(parent, shiftText(), UDim2.new(1, 0, 0, 14), { LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 1, TextSize = 11 })
	-- The courier ID.
	local card = block(parent, 3, true)
	local head = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, LayoutOrder = 1 }, card)
	P.marker(head, 6, { Position = UDim2.fromOffset(0, 4) })
	P.caps(head, "Courier · Dead End Dispatch", UDim2.new(1, -12, 1, 0), { Position = UDim2.fromOffset(12, 0), TextStrokeTransparency = 1, TextSize = 10 })
	local nameRow = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 2 }, card)
	text(nameRow, player.DisplayName, UDim2.new(1, -84, 1, 0), { Font = Theme.HeadingFont, TextSize = 16, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	refs.idMoney = text(nameRow, "", UDim2.fromOffset(84, 22), { Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = 15, TextColor3 = K.good, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right })
	refs.idRank = caps(card, "", 3, K.text)
	local holder = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, LayoutOrder = 4 }, card)
	local back, fill = P.bar(holder, UDim2.new(1, 0, 0, 3), K.text)
	back.Position = UDim2.fromOffset(0, 2)
	refs.idXp = fill
	refs.idTransport = caps(card, "", 5)
	-- 5.1: the quick switch (fillHome shows it when you own a bike): MY BIKE, and CALL CAR with a car of your own too.
	local switch = Ui.make("Frame", { Name = "Switch", Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 6, Visible = false }, card)
	Ui.list(switch, false, 6)
	local function switchButton(label: string, order: number, how: string): any
		local made = P.button(switch, label, UDim2.new(0.5, -3, 1, 0), "quiet", function()
			Net.get("Equip"):FireServer(how)
			Phone.close()
		end)
		made.LayoutOrder = order
		made.TextSize = 12
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
		LayoutOrder = 4,
		Visible = false,
	}, parent)
	Ui.corner(note, 10)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = K.line, Thickness = 1, Transparency = 0.7 }, note)
	Ui.list(note, true, 2)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 7), PaddingBottom = UDim.new(0, 8) }, note)
	refs.noteFrom = caps(note, "", 1, K.text)
	refs.noteText = text(note, "", UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextSize = 12, TextColor3 = K.secondary, TextTruncate = Enum.TextTruncate.AtEnd })
	Ui.make("UISizeConstraint", { MaxSize = Vector2.new(math.huge, 64) }, refs.noteText)
	refs.note = note
	note.Activated:Connect(function()
		click()
		setApp("messages")
	end)
end

-- Fills the home widgets with the state right now.
local function fillHome()
	if not refs.bigClock then
		return
	end
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
	refs.note.Visible = newest ~= nil and not landscape -- (sideways there is no room for it)
	if newest then
		refs.noteFrom.Text = `💬 {string.upper(newest.from)} · {newest.time}`
		refs.noteText.Text = newest.text
	end
end

-- The phone: its body, the screen, the status bar, the home screen and the app screen. Built again when it turns.
local function buildBody(sideways: boolean)
	local made = gui :: ScreenGui
	if refs.body then
		refs.body:Destroy()
	end
	table.clear(tiles)
	refs.bigClock = nil
	landscape = sideways
	local size = if sideways then LANDSCAPE else PORTRAIT
	local body = Ui.make("Frame", {
		Name = "Phone",
		Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = BODY,
		BorderSizePixel = 0,
		Visible = false,
		Active = true, -- (clicks on the phone do not reach the world)
	}, made)
	refs.body = body
	Ui.corner(body, 34)
	Ui.make("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = BODY_EDGE, Thickness = 1.5 }, body)
	Ui.make("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 192, 196)) }, body)
	refs.scale = Ui.make("UIScale", {}, body)
	-- The side keys (power on the right, the volume on the left; on their long edges when sideways).
	local keyColor = BODY_EDGE
	if sideways then
		Ui.make("Frame", { Size = UDim2.fromOffset(46, 3), Position = UDim2.new(0, 70, 0, -3), BackgroundColor3 = keyColor, BorderSizePixel = 0 }, body)
		Ui.make("Frame", { Size = UDim2.fromOffset(60, 3), Position = UDim2.new(1, -150, 1, 0), BackgroundColor3 = keyColor, BorderSizePixel = 0 }, body)
	else
		Ui.make("Frame", { Size = UDim2.fromOffset(3, 60), Position = UDim2.new(1, 0, 0, 120), BackgroundColor3 = keyColor, BorderSizePixel = 0 }, body)
		Ui.make("Frame", { Size = UDim2.fromOffset(3, 36), Position = UDim2.new(0, -3, 0, 100), BackgroundColor3 = keyColor, BorderSizePixel = 0 }, body)
		Ui.make("Frame", { Size = UDim2.fromOffset(3, 36), Position = UDim2.new(0, -3, 0, 144), BackgroundColor3 = keyColor, BorderSizePixel = 0 }, body)
	end
	local screen = Ui.make("Frame", {
		Name = "Screen",
		Size = UDim2.new(1, -BEZEL * 2, 1, -BEZEL * 2),
		Position = UDim2.fromOffset(BEZEL, BEZEL),
		BackgroundColor3 = SCREEN,
		BorderSizePixel = 0,
	}, body)
	Ui.corner(screen, 26)
	-- A faint sheen at the top of the screen (glass, not a glow).
	local sheen = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 160), BackgroundColor3 = K.text, BackgroundTransparency = 0, BorderSizePixel = 0 }, screen)
	Ui.corner(sheen, 26)
	Ui.make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.95), NumberSequenceKeypoint.new(1, 1) }) }, sheen)
	local STATUS_H = if sideways then 24 else 30
	statusBar(screen, STATUS_H)
	-- The NEW PHONE ribbon (the moment Marge gives it).
	refs.ribbon = P.tag(screen, "New phone", K.red)
	refs.ribbon.AnchorPoint = Vector2.new(0.5, 0)
	refs.ribbon.Position = UDim2.new(0.5, 0, 0, STATUS_H + 2)
	refs.ribbon.ZIndex = 6
	refs.ribbon.Visible = false
	-- The home bar at the bottom: home from an app; on the home screen it puts the phone away.
	local homeBar = Ui.make("TextButton", {
		Name = "HomeBar",
		Size = UDim2.new(0, 140, 0, 22),
		Position = UDim2.new(0.5, 0, 1, -2),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
	}, screen)
	local pill = Ui.make("Frame", { Size = UDim2.fromOffset(104, 4), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = K.text, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 5 }, homeBar)
	Ui.corner(pill, 2)
	homeBar.MouseEnter:Connect(function()
		pill.BackgroundTransparency = 0
	end)
	homeBar.MouseLeave:Connect(function()
		pill.BackgroundTransparency = 0.25
	end)
	homeBar.Activated:Connect(function()
		click()
		if app == "home" then
			Phone.close()
		else
			setApp("home")
		end
	end)
	refs.homeBar = homeBar
	local BOTTOM = 26
	-- The home screen.
	local home = Ui.make("Frame", { Name = "Home", Size = UDim2.new(1, -24, 1, -(STATUS_H + BOTTOM)), Position = UDim2.fromOffset(12, STATUS_H), BackgroundTransparency = 1 }, screen)
	refs.home = home
	local widgets = Ui.make("Frame", {
		Name = "Widgets",
		Size = if sideways then UDim2.new(0.44, 0, 1, 0) else UDim2.new(1, 0, 0, 0),
		AutomaticSize = if sideways then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, home)
	Ui.list(widgets, true, 8)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, if sideways then 4 else 14) }, widgets)
	homeWidgets(widgets)
	local grid = Ui.make("Frame", {
		Name = "Apps",
		Size = if sideways then UDim2.new(0.56, -8, 1, -18) else UDim2.new(1, 0, 0, 190),
		Position = if sideways then UDim2.new(0.44, 8, 0, 0) else UDim2.new(0, 0, 1, -20),
		AnchorPoint = if sideways then Vector2.zero else Vector2.new(0, 1),
		BackgroundTransparency = 1,
	}, home)
	-- How to put it away, under the apps (the home bar below does it on the home screen).
	P.caps(home, if Ui.touchLayout() then "Tap the bar below to put it away" else "O · ESC · the bar below put it away", UDim2.new(if sideways then 0.56 else 1, if sideways then -8 else 0, 0, 14), {
		Position = UDim2.new(if sideways then 0.44 else 0, if sideways then 8 else 0, 1, -2),
		AnchorPoint = Vector2.new(0, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 1,
		TextSize = 10,
		TextColor3 = K.line,
	})
	Ui.make("UIGridLayout", {
		CellSize = UDim2.fromOffset(80, 88),
		CellPadding = UDim2.fromOffset(if sideways then 6 else 4, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, grid)
	for order, def in APPS do
		local cell = tile(grid, def, order)
		if order == 1 then
			refs.firstTile = cell
		end
	end
	-- The app screen: a header (back, the app's name) and its scrolling list.
	local appFrame = Ui.make("Frame", { Name = "App", Size = UDim2.new(1, 0, 1, -(STATUS_H + BOTTOM)), Position = UDim2.fromOffset(0, STATUS_H), BackgroundTransparency = 1, Visible = false }, screen)
	refs.app = appFrame
	local header = Ui.make("Frame", { Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1 }, appFrame)
	local back = P.action(header, "‹  HOME", { Size = UDim2.fromOffset(0, 44), TextSize = 12 }, function()
		setApp("home")
	end)
	refs.back = back
	refs.appTitle = P.text(header, "", UDim2.new(1, -90, 1, 0), { Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Font = Theme.HeadingFont, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Right, TextStrokeTransparency = 1 })
	P.rule(appFrame, UDim2.new(1, -20, 0, 1), { Position = UDim2.fromOffset(10, 44) })
	local list = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -16, 1, -50),
		Position = UDim2.fromOffset(10, 50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = K.line,
		ScrollBarImageTransparency = 0.3,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, appFrame)
	Ui.list(list, true, 8)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 6) }, list)
	refs.list = list
end

-- ── Showing ────────────────────────────────────────────────────────────────

local APP_TITLES: { [string]: string } = { orders = "ORDERS", career = "CAREER", shop = "SHOP", messages = "MESSAGES" }

renderApp = function()
	if not refs.body then
		return
	end
	refs.timer = nil
	OrdersUi.clear()
	local home = app == "home"
	refs.home.Visible = home
	refs.app.Visible = not home
	if home then
		fillHome()
		return
	end
	refs.appTitle.Text = APP_TITLES[app] or string.upper(app)
	Ui.clear(refs.list)
	refs.list.CanvasPosition = Vector2.zero
	local ok, err = pcall(function()
		if app == "orders" then
			ordersApp(refs.list)
		elseif app == "career" then
			careerApp(refs.list)
		elseif app == "shop" then
			shopApp(refs.list)
		elseif app == "messages" then
			messagesApp(refs.list)
		end
	end)
	if not ok then
		warn(`[Phone] the {app} app failed: {err}`)
	end
	Ui.gamepadFocus(refs.back)
end

-- Can anything in the SHOP app be bought right now (your level, your money)?
local function affordable(): boolean
	local owned = kit()
	local room = Transport.handsRoom(owned)
	local level = myLevel()
	for _, def in Config.Kit do
		local outgrown = def.room ~= nil and def.speed == nil and def.warm == nil and def.room <= room
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

-- The phone's scale and shape for this screen: upright when it is readable so, else sideways (a short touch screen).
local function fit(): (boolean, number)
	local screen = Ui.screenSize()
	local cap = if Ui.touchLayout() then 1 else math.clamp(Ui.screenScale() * 0.88, 0.7, 1)
	local upright = math.min(cap, (screen.Y - 48) / PORTRAIT.Y, (screen.X - 32) / PORTRAIT.X)
	if upright >= 0.72 then
		return false, upright
	end
	local sideways = math.min(cap, (screen.Y - 20) / LANDSCAPE.Y, (screen.X - 24) / LANDSCAPE.X)
	if sideways > upright then
		return true, sideways
	end
	return false, upright
end

-- Where the phone rests (and where it slides from).
local function restPosition(): (UDim2, UDim2)
	if landscape then
		return UDim2.new(0.5, 0, 1, -8), UDim2.new(0.5, 0, 1, 40)
	end
	return UDim2.new(1, -24, 1, -16), UDim2.new(1, -24, 1, 40)
end

local function reducedMotion(): boolean
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

local function hudOn(): boolean
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	return hud ~= nil and hud:IsA("ScreenGui") and hud.Enabled
end

-- The clock, the timer and the shift while the phone is open (twice a second).
local ticking = false
local function startTicker()
	if ticking then
		return
	end
	ticking = true
	task.spawn(function()
		while isOpen do
			local now = clockText()
			if refs.statusTime then
				refs.statusTime.Text = now
			end
			if refs.bigClock then
				refs.bigClock.Text = now
				refs.shift.Text = shiftText()
			end
			local timer = refs.timer
			if timer and job and type(job.endsAt) == "number" then
				local left = job.endsAt - workspace:GetServerTimeNow()
				timer.Text = Ui.clock(math.max(0, left))
				timer.TextColor3 = if left < 30 then K.red else K.text
			end
			if app == "orders" then
				OrdersUi.tick() -- 5.2: every order's clock
			end
			if refs.tow and refs.bigClock then
				refs.tow.Visible = refs.towShown() -- 5.4: the tank ran dry (or the tow came)
			end
			task.wait(0.5)
		end
		ticking = false
	end)
end

function Phone.isOpen(): boolean
	return isOpen
end

function Phone.close()
	if not isOpen then
		return
	end
	isOpen = false
	Net.get("PhoneHold"):FireServer(false) -- (5.0: the phone leaves your hand: server/KitWear.luau)
	local body = refs.body
	if body then
		Ui.gamepadRelease(body)
		if reducedMotion() then
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

function Phone.open(startApp: string?)
	if not gui or not hasPhone() then
		return
	end
	local hook = Phone.onOpen
	if hook then
		pcall(hook) -- (the other windows close; their onCloseWindows closes nothing open here yet)
	end
	local sideways, scale = fit()
	if landscape ~= sideways or not refs.body then
		buildBody(sideways)
	end
	refs.scale.Scale = scale
	local body = refs.body
	body.AnchorPoint = if landscape then Vector2.new(0.5, 1) else Vector2.new(1, 1)
	local rest, hidden = restPosition()
	app = startApp or "home"
	if not isOpen then
		Net.get("PhoneHold"):FireServer(true) -- (5.0: everybody sees it in your hand while you are on foot: server/KitWear.luau)
	end
	isOpen = true
	renderApp()
	refreshBadges()
	if not body.Visible or reducedMotion() then
		body.Position = if reducedMotion() then rest else hidden
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
	local label = P.text(action, if touch then "PHONE" else "PHONE  [O]", UDim2.fromOffset(0, 44), {
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
		notify(if Ui.touchLayout() then "📱 NEW PHONE · Marge gave you her old phone · tap PHONE" else "📱 NEW PHONE · Marge gave you her old phone · O opens it")
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
		elseif app == "shop" or app == "career" then
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
local function onOffers(list: any, refreshAt: any)
	if type(list) ~= "table" then
		return
	end
	local isNew = type(refreshAt) == "number" and refreshAt ~= lastRefreshAt
	lastRefreshAt = if type(refreshAt) == "number" then refreshAt else lastRefreshAt
	local boardOpen = Phone.boardOpen
	if not isNew or (boardOpen and boardOpen()) or not hasPhone() or job then
		if boardOpen and boardOpen() then
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
	buildButton(made)
	buildBody(false)
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
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() then
			return
		end
		if (input.KeyCode == KEY or input.KeyCode == PAD_KEY) and hudOn() and hasPhone() then
			Phone.toggle()
		end
	end)
	-- The screen turned or resized: a phone that is open is fitted again (upright or sideways).
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
				local sideways, scale = fit()
				if sideways ~= landscape then
					local current = app
					Phone.close()
					task.delay(0.2, function()
						Phone.open(current)
					end)
				elseif refs.scale then
					refs.scale.Scale = scale
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
