--!strict
-- 5.5: the courier phone's bigger apps and the HUD MENU's actions in the phone (client/Phone.luau draws ORDERS,
-- CAREER, SHOP, MESSAGES, BANK and SETTINGS itself). Drawn with the phone's own approved kit (`look`, OrdersUi.Kit:
-- square charcoal cards, thin rules, red main actions; design/phone-ui/) through a `Host` (what the phone knows and
-- does):
--   BOARD    the job board in the phone (the phone turns sideways for it): the offers the phone keeps from the
--            Offers remote under ON FOOT / BIKE / one section per danger level (★ … ★★★★, the server's tierName), two
--            columns of cards (the cargo → the customer, the pickup → the address, the distance, the time, the pay);
--            ACCEPT and + ADD ORDER fire AcceptJob with the offer's index like the Dispatch board
--            (client/DispatchUi.luau); a locked offer says why (its level, licence, slots or vehicle). The board's
--            footNote (the shops near you are shut) heads ON FOOT. FULL BOARD opens the Dispatch board. No offers
--            yet, or old ones: it asks for the board (RequestOffers, at most every 3 s).
--   BAG      your bag (client/BagUi.luau's render) in the phone (sideways).
--   GARAGE   BRING MY CAR (SpawnCar: the MENU's old CAR), 🚲 MY BIKE / 🚐 CALL CAR (the Equip remote) and ⛽ TOW while
--            your own car's tank is empty (the Fuel remote). Home's courier card keeps its quick switch too. 5.6: the
--            line "ZDC RIDE · nearest dock N studs" (shared/RentalDocks.luau) with 📍 GPS (MapView.setWaypoint).
--   KEYS     the settings' list of every key.
-- Presentation only: the server decides every job, every vehicle and the money.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local RentalDocks = require(Shared.RentalDocks)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local BagUi = require(script.Parent.BagUi)
local OrdersUi = require(script.Parent.OrdersUi)
local MapView = require(script.Parent.MapView)

local K = Theme.Contract
local PhoneApps = {}

-- What the phone knows and does, for the apps here (Phone.start sets it up).
export type Host = {
	job: () -> any,
	state: () -> any,
	-- the last offers the server sent (nil before any), their info (footNote ...), when the next ones come
	board: () -> ({ any }?, any, number?),
	sideways: () -> boolean,
	go: (id: string) -> (),
	close: () -> (),
	redraw: () -> (),
	notify: (text: string) -> (),
	fullBoard: () -> (),
	transport: () -> string,
}

local player = Players.LocalPlayer

-- Two columns in a list (sideways), each a vertical list of its own; upright both are the list itself.
function PhoneApps.columns(list: Instance, order: number, two: boolean): (Instance, Instance)
	if not two then
		return list, list
	end
	local row = Ui.make("Frame", { Name = "Columns", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, list)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, row)
	local function column(index: number): Instance
		local made = Ui.make("Frame", {
			Name = if index == 1 then "Left" else "Right",
			Size = UDim2.new(0.5, -4, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, row)
		Ui.list(made, true, 8)
		return made
	end
	return column(1), column(2)
end

-- 5.4: your own car's tank is empty (its Tank / Fuel attributes, server/Fuel.luau): TOW is offered.
function PhoneApps.towDue(): boolean
	local cars = workspace:FindFirstChild("Cars")
	for _, car in if cars then cars:GetChildren() else {} do
		if car:GetAttribute("OwnerId") == player.UserId then
			local tank, fuel = car:GetAttribute("Tank"), car:GetAttribute("Fuel")
			return type(tank) == "number" and tank > 0 and type(fuel) == "number" and fuel <= 1e-3
		end
	end
	return false
end

local function fullBoardLabel(): string
	return if Ui.touchLayout() then "FULL BOARD" else "FULL BOARD  [J]"
end

-- ── BOARD ──────────────────────────────────────────────────────────────────

local askedAt = 0

type Tier = { stars: number, name: string, list: { any } }

local function ask()
	local now = os.clock()
	if askedAt > 0 and now - askedAt < 3 then
		return
	end
	askedAt = now
	Net.get("RequestOffers"):FireServer()
end

-- 5.2: a run that takes more orders (+ ADD ORDER).
local function stacking(job: any): boolean
	return type(job) == "table" and type(job.stack) == "table" and job.stack.can == true
end

-- A locked offer's button and why (nil, nil: it is open). The server refuses a locked one anyway.
local function lockOf(offer: any): (string?, string?)
	local licence = if offer.locked == true and offer.lockReason == "licence" and type(offer.licence) == "table" then offer.licence else nil
	if offer.locked == true and not licence then
		local level = tonumber(offer.level) or 1
		return `🔒 LEVEL {level}`, `This run unlocks at level {level} ({Levels.rank(level)}). Deliveries give XP.`
	elseif licence then
		local have, need = tonumber(licence.have) or 0, tonumber(licence.need) or 0
		return `🪪 LICENCE {have} / {need}`, `{licence.stars or "These"} jobs need their licence: {need} jobs rated ★★ or better at {licence.atStars or "this level"} or harder ({have} / {need} done).`
	elseif offer.tooBig == true then
		local label = if type(offer.lockButton) == "string" then offer.lockButton else `📦 NEEDS {offer.slots or "?"} SLOTS`
		local why = if type(offer.lockText) == "string" then offer.lockText else `This run needs {offer.slots or "?"} cargo slots; your {offer.carName or "vehicle"} holds {offer.capacity or 0}.`
		return label, why
	end
	return nil, nil
end

-- One offer as a card: the cargo → the customer and the pay, the pickup → the address, chips (how it travels or its
-- stars, the distance, the time, its trade-off), the action.
local function offerCard(parent: Instance, offer: any, order: number, look: OrdersUi.Kit, host: Host)
	local label, why = lockOf(offer)
	local job = host.job()
	local b = look.block(parent, order, label == nil)
	local title = if type(offer.jobType) == "table" then `{offer.jobType.name}: {offer.cargo}` else `{offer.cargo or "Cargo"} → {offer.customer or "a customer"}`
	local _, left, right = look.row2(b, string.upper(title), Ui.money(tonumber(offer.pay) or 0), 1, true)
	left.Font = Theme.HeadingFont
	left.TextColor3 = if label then K.secondary else K.text
	right.TextColor3 = if label then K.secondary else K.text
	look.meta(b, `{offer.first or "Pick up"} → {offer.address or "?"}{if type(offer.district) == "string" and offer.district ~= "" then `, {offer.district}` else ""}`, 2)
	local chips = look.chipRow(b, 3)
	look.chip(chips, if offer.mode == "foot" then "🚶 On foot" elseif offer.mode == "bike" then "🚲 Bike" else string.rep("★", math.max(1, tonumber(offer.stars) or 1)))
	look.chip(chips, `{tonumber(offer.distance) or 0} studs`)
	look.chip(chips, `⏱ {Ui.clock(tonumber(offer.time) or 0)}`, if offer.timed then K.red else nil)
	if type(offer.roleName) == "string" then
		look.chip(chips, `{offer.roleIcon or ""} {offer.roleName}`, if offer.role == "risky" then K.red else nil)
	end
	if type(offer.jobType) == "table" then
		look.chip(chips, "Special", K.warn)
	end
	local night = tonumber(offer.nightPay)
	if night and night > 1 then
		look.chip(chips, string.format("Night ×%.1f", night))
	end
	local function take()
		Net.get("AcceptJob"):FireServer(offer.index)
		-- It leaves the board on the server once taken: not shown again before the board comes back.
		local list = host.board()
		local spot = if list then table.find(list, offer) else nil
		if list and spot then
			table.remove(list, spot)
		end
		if stacking(job) then
			host.redraw()
		else
			host.go("orders")
		end
	end
	if label then
		look.button(b, label, "off", 4, function()
			host.notify(why or "Not this one yet.")
		end)
	elseif stacking(job) then
		if offer.addOrder == true then
			look.button(b, "+ ADD ORDER", "main", 4, take)
		else
			look.button(b, if type(offer.orderButton) == "string" then offer.orderButton else "FINISH YOUR RUN", "off", 4, function()
				host.notify(if type(offer.orderText) == "string" then offer.orderText else "Finish your current delivery first.")
			end)
		end
	else
		look.button(b, "ACCEPT", "main", 4, take)
	end
end

function PhoneApps.board(list: Instance, look: OrdersUi.Kit, host: Host)
	local job = host.job()
	if job and not stacking(job) then
		look.emptyState(list, "📦", "You are on a delivery", "Finish it, or give it up in ORDERS, and the board is yours again.", 1)
		look.button(list, "OPEN ORDERS", "main", 2, function()
			host.go("orders")
		end)
		look.button(list, fullBoardLabel(), "quiet", 3, host.fullBoard)
		return
	end
	local offers, info, refreshAt = host.board()
	if offers == nil or (refreshAt ~= nil and workspace:GetServerTimeNow() >= refreshAt) then
		ask()
	end
	if offers == nil then
		look.emptyState(list, "📋", "Calling the dispatcher...", "The board comes in a moment.", 1)
		look.button(list, fullBoardLabel(), "quiet", 2, host.fullBoard)
		return
	end
	local walks: { any } = {}
	local rides: { any } = {}
	local tiers: { Tier } = {}
	local byStars: { [number]: Tier } = {}
	for _, offer in offers do
		if type(offer) ~= "table" then
			continue
		end
		if offer.mode == "foot" then
			table.insert(walks, offer)
		elseif offer.mode == "bike" then
			table.insert(rides, offer)
		else
			local stars = tonumber(offer.stars) or 1
			local known = byStars[stars]
			local group = known or { stars = stars, name = tostring(offer.tierName or "Jobs"), list = {} }
			if known == nil then
				byStars[stars] = group
				table.insert(tiers, group)
			end
			table.insert(group.list, offer)
		end
	end
	local count = #walks + #rides
	for _, entry in tiers do
		count += #entry.list
	end
	local fresh = if refreshAt then math.max(0, refreshAt - workspace:GetServerTimeNow()) else nil
	look.section(list, `{count} {if count == 1 then "job" else "jobs"} on the board{if fresh then ` · new ones in {Ui.clock(fresh)}` else ""}`, 1)
	local order = 1
	local footNote = if type(info) == "table" and type(info.footNote) == "string" then info.footNote else nil
	local two = host.sideways()
	local function group(title: string, items: { any }, note: string?)
		order += 1
		look.section(list, title, order)
		if note then
			order += 1
			look.meta(list, note, order, if #items == 0 then K.red else K.secondary)
		end
		order += 1
		local left, right = PhoneApps.columns(list, order, two)
		for index, offer in items do
			order += 1
			local column = if index % 2 == 1 then left else right
			local ok, err = pcall(function()
				offerCard(column, offer, order, look, host)
			end)
			if not ok then
				warn(`[PhoneApps] a board card failed: {err}`)
			end
		end
	end
	if #walks > 0 or footNote then
		group(`On foot · {#walks}`, walks, footNote)
	end
	if #rides > 0 then
		group(`Bike · {#rides}`, rides)
	end
	for _, entry in tiers do
		group(`{string.rep("★", math.max(1, entry.stars))} {entry.name} · {#entry.list}`, entry.list)
	end
	if count == 0 and not footNote then
		order += 1
		look.emptyState(list, "📋", "No jobs right now", "New ones come soon.", order)
	end
	look.button(list, fullBoardLabel(), "quiet", order + 1, host.fullBoard)
end

-- ── BAG ────────────────────────────────────────────────────────────────────

function PhoneApps.bag(list: Instance, look: OrdersUi.Kit, host: Host)
	local n = BagUi.render(list, host.job(), 1)
	look.meta(list, `Pieces ride where they fit: your hands, the backpack, the bike's rack, the car.{if Ui.touchLayout() then "" else " The I key opens the bag too."}`, n + 1)
end

-- ── GARAGE ─────────────────────────────────────────────────────────────────

function PhoneApps.garage(list: Instance, look: OrdersUi.Kit, host: Host)
	local state = host.state()
	local owned = if type(state) == "table" and type(state.cars) == "table" then state.cars else {}
	local hasBike, hasCar = false, false
	for _, def in Config.Cars do
		if owned[def.id] and not def.company then
			hasBike = hasBike or def.bike == true
			hasCar = hasCar or not def.bike
		end
	end
	local now = look.block(list, 1, true)
	look.caps(now, "Now", 1, K.secondary)
	look.text(now, host.transport(), UDim2.new(1, 0, 0, 0), { AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Font = Theme.HeadingFont, TextSize = 15 })
	look.meta(now, if hasCar then "BRING MY CAR sets your car (or a job's company vehicle) down next to you."
		elseif hasBike then "Your bike is yours; the first car comes later (the SHOP app says when)."
		else "No vehicle of your own yet: the SHOP app says what comes next.", 3)
	look.button(list, "BRING MY CAR", if hasCar then "main" else "quiet", 2, function()
		Net.get("SpawnCar"):FireServer()
		host.close()
	end)
	local order = 2
	if hasBike then
		order += 1
		look.button(list, "🚲 MY BIKE", "quiet", order, function()
			Net.get("Equip"):FireServer("ride")
			host.close()
		end)
		if hasCar then
			order += 1
			look.button(list, "🚐 CALL CAR", "quiet", order, function()
				Net.get("Equip"):FireServer("drive")
				host.close()
			end)
		end
	end
	order = PhoneApps.rideLine(list, look, host, order + 1)
	if PhoneApps.towDue() then
		order += 1
		look.section(list, "Out of fuel", order)
		order += 1
		look.meta(list, "Your car's tank is empty. The tow takes it to the nearest pump with a little fuel in it.", order)
		order += 1
		look.button(list, `⛽ TOW  {Ui.money(Config.Fuel.TowPrice)}`, "main", order, function()
			Net.get("Fuel"):FireServer("tow")
			host.close()
		end)
	end
end

-- 5.6, ZDC RIDE: the nearest rental dock (straight, from where you stand) and the GPS to it; under it what to do
-- (you have one out: the player attribute Rental). Returns the last order used.
function PhoneApps.rideLine(list: Instance, look: OrdersUi.Kit, host: Host, order: number): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local here = if root and root:IsA("BasePart") then root.Position else nil
	local dock, far = nil, 0
	if here then
		dock, far = RentalDocks.nearest(here.X, here.Z)
	end
	local card = look.block(list, order)
	local head = Ui.make("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, card)
	local title = if dock then `🛴 ZDC RIDE · nearest dock {math.floor(far)} studs` else "🛴 ZDC RIDE · free e-scooters"
	look.text(head, title, UDim2.new(1, if dock then -96 else 0, 1, 0), { Font = Theme.HeadingFont, TextSize = 14, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	if dock then
		local found = dock
		look.pill(head, "📍 GPS", function()
			MapView.setWaypoint(Vector3.new(found.x, Map.RoadTop, found.z))
			pcall(function()
				MapView.onWaypoint({ id = "zdcride", name = `ZDC RIDE · {found.name}`, icon = "🛴", x = found.x, z = found.z, kind = "shop", description = "" })
			end)
			host.notify(`GPS: ZDC RIDE · {found.name}`)
		end)
	end
	look.meta(card, if player:GetAttribute("Rental") ~= nil then "Your rental: leave it anywhere, or Return it at any dock."
		else "Free e-scooters at docks across Downtown and the Suburbs: hold Rent.", 2)
	return order
end

-- ── SETTINGS: the keys ─────────────────────────────────────────────────────

local KEYS: { { string } } = {
	{ "Q", "Phone" },
	{ "J", "Job board" },
	{ "U", "Missions" },
	{ "C", "Career" },
	{ "I", "Bag" },
	{ "M", "Map" },
	{ "K", "Crew" },
	{ "L", "Top couriers" },
	{ "H", "Real estate" },
	{ "N", "Sound" },
	{ "T", "Weapon wheel" },
	{ "E", "Doors, get in and out" },
	{ "G", "Put down, let go" },
	{ "F", "Fire" },
	{ "B", "Holster, draw" },
	{ "V", "Punch, strike" },
	{ "Y", "Take a road offer" },
	{ "1 – 6", "Items" },
	{ "Shift", "Sprint" },
	{ "ESC", "Close a window" },
}

-- Every key in one card (`order` in the list), and the version under it.
function PhoneApps.keys(list: Instance, look: OrdersUi.Kit, order: number)
	look.section(list, "Keys", order)
	local keys = look.block(list, order + 1)
	if Ui.touchLayout() then
		look.meta(keys, "On a touch screen the buttons on the screen do these; with a keyboard:", 0)
	end
	for index, entry in KEYS do
		local _, _, right = look.row2(keys, entry[2], entry[1], index, true)
		right.TextColor3 = K.text
	end
	look.meta(list, `ZDC courier terminal · Zombie Delivery {Config.Version}`, order + 2)
end

return PhoneApps
