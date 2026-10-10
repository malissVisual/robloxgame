--!strict
-- 5.5: the courier phone's bigger apps and the HUD MENU's actions in the phone (client/Phone.luau draws ORDERS,
-- CAREER, SHOP, MESSAGES, BANK and SETTINGS itself). Drawn with the phone's own approved kit (`look`, OrdersUi.Kit:
-- square charcoal cards, thin rules, red main actions; design/phone-ui/) through a `Host` (what the phone knows and
-- does). 6.0.1: every app draws in the phone's centred popup (client/PhonePopup.luau); `wide` (a popup with room for
-- two columns) splits the board's cards in two:
--   BOARD    the job board in the phone: the offers the phone keeps from the
--            Offers remote under ON FOOT / BIKE / one section per danger level (★ … ★★★★, the server's tierName), two
--            columns of cards (the cargo → the customer and its pay, big; the pickup → the address, the distance, the
--            time); ACCEPT and + ADD fire AcceptJob with the offer's index like the Dispatch board
--            (client/DispatchUi.luau); a locked offer says why (its level, licence, slots or vehicle). The board's
--            footNote (the shops near you are shut) heads ON FOOT. FULL BOARD opens the Dispatch board. No offers
--            yet, or old ones: it asks for the board (RequestOffers, at most every 3 s).
--            6.12.8 (the owner: "I don't need to see this window. I want a list where I have the jobs and how much I
--            earn, and add even all of them"): JOBS always opens it, during a run too. On top, while you have orders
--            on the go, YOUR RUN (every open order in one line: what, from → to, its pay and its clock; the run's
--            pay; the next stop; DETAILS opens ORDERS), then NEXT UP (the queued jobs in order: what, where, pay, ✕
--            to drop one; the next one says why it waits: shared/JobQueue.luau, the JobQueue remote). Every row has
--            Review: NEXT UP's PAUSE / RESUME (it pauses itself after a failed delivery, a lost order, a mission)
--            and CLEAR ALL; the next one says "Starts in a few seconds" while its idle start waits. Every row has
--            one add button during a run: + ADD (it joins the run now: AcceptJob) or + QUEUE (the run is full or it
--            can't stack: JobQueue "queue"); ADD ALL · $total over the rows adds every job it can (JobQueue
--            "addAll": into the run up to its room and max, the rest into the queue).
--            6.12.11: every row's card opens with its business's picture (client/JobThumbUi.luau, shared/JobThumbs.luau:
--            Codex's pictures, cropped to about 2.4 : 1, the name on a dark label), a slim banner (the cargo emoji and
--            the name) while it is not uploaded; NEXT UP's rows a small square of it once uploaded.
--            6.14: a GOLDEN ORDER or a REGULAR'S ORDER heads the list in a section of its own, its card in gold (or a
--            cool silver) with its perks and its countdown (client/SpecialOrderUi.luau); NEXT UP says when a queued one
--            runs out. Every card names your tier with its business (client/RegularsApp.luau badge: "🥈 SILVER REGULAR
--            +10%", "🤝 3/5 TO BRONZE").
--            6.15: while a live event pays (rush hour, the Blood Moon) its strip heads the jobs ("🕑 RUSH HOUR · ×1.5
--            pay · 3:12", its clock ticking: shared/LiveEvents.luau, SpecialOrderUi.countdown).
--            6.17 (the owner: "when I open JOBS I want to leave, it doesn't make me want to click a job"; redesign B):
--            the list is client/JobsView.luau's: the top bar's chips (YOUR RUN, NEXT UP: the cards above as its
--            sub-views; rush hour), the HERO card (the best job right now: shared/JobPick.luau) and compact rows (the
--            picture, the danger, the business, the distance and time, the pay, "+"). The card above is a job's
--            details (a tap on a row or the hero's ⓘ); every action keeps its path (act: AcceptJob, JobQueue).
--   BAG      your bag (client/BagUi.luau's render) in the phone.
--   GARAGE   BRING MY CAR (SpawnCar: the MENU's old CAR), 🚲 MY BIKE / 🚐 CALL CAR (the Equip remote) and ⛽ TOW while
--            your own car's tank is empty (the Fuel remote). Home's courier card keeps its quick switch too. 5.6: the
--            line "ZDC RIDE · nearest dock N studs" (shared/RentalDocks.luau) with 📍 GPS (MapView.setWaypoint).
--   KEYS     the settings' list of every key.
-- 6.5, the phone's six home tiles (client/Phone.luau):
--   BAG & ITEMS  the I window's tabs in the phone: 🛍 BAG (during a run: BagUi.render), ITEMS (your consumables, how
--            many, their key in the bottom bar and USE: the same path as the bar, Hotbar.onUse) and BAGS (BagUi.bags:
--            the bags you own, USE). PhoneApps.bagTab keeps the tab (nil: BAG during a run, else ITEMS).
--   SHOPS    SHOP's list of the shops (Map.Shops) and what each sells; a tap sets the GPS there (host.gps), puts the
--            phone away and says "GPS set: <shop>". Buying stays at the counters (Map.ShopRadius).
-- 6.18 wave 2 (the UI kit, design/ui-kit/README.md: "I need it unified so the phone looks like that"): BAG & ITEMS is
-- client/BagUi.luau's (the bag as the hero, the items' counts big, USE); SHOP (PhoneApps.shop, out of client/Phone.luau)
-- is SAVE UP (the savings goal as the hero, a row a thing to buy with its price big, 📍 its counter) and SHOPS (the list
-- above as the kit's rows); GARAGE the vehicle you have out as the hero (BRING MY CAR) and a row for MY BIKE, CALL CAR,
-- TOW and ZDC RIDE (PhoneApps.rideItem). client/ShopView.luau draws them.
-- Presentation only: the server decides every job, every vehicle and the money.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy) -- 6.7: the car-only items
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local RentalDocks = require(Shared.RentalDocks)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local BagUi = require(script.Parent.BagUi)
local OrdersUi = require(script.Parent.OrdersUi)
local MapView = require(script.Parent.MapView)
local JobQueue = require(Shared.JobQueue) -- 6.12.8: YOUR RUN, NEXT UP's words
local JobThumbUi = require(script.Parent.JobThumbUi) -- 6.12.11: the job pictures
local SpecialOrderUi = require(script.Parent.SpecialOrderUi) -- 6.14: the golden and the regulars' orders
local RegularsApp = require(script.Parent.RegularsApp) -- 6.14: your tier with a job's business
local JobsView = require(script.Parent.JobsView) -- 6.17: the JOBS app at a glance (hero + rows)
local CardKit = require(script.Parent.CardKit) -- 6.18 wave 2: SHOP, BAG & ITEMS, GARAGE in the UI kit's look
local ShopView = require(script.Parent.ShopView)
local Icons = require(Shared.Icons)
local Transport = require(Shared.Transport)

local K = Theme.Contract
local PhoneApps = {}

-- What the phone knows and does, for the apps here (Phone.start sets it up).
export type Host = {
	job: () -> any,
	state: () -> any,
	-- the last offers the server sent (nil before any), their info (footNote ...), when the next ones come
	board: () -> ({ any }?, any, number?),
	queue: () -> any, -- 6.12.8: the NEXT UP queue the server sent ({ list, max }), nil before any
	go: (id: string) -> (),
	close: () -> (),
	redraw: () -> (),
	notify: (text: string) -> (),
	fullBoard: () -> (),
	transport: () -> string,
	gps: (shopId: string) -> (), -- 6.5: the GPS to one of Map.Shops
	bar: () -> (any, number), -- 6.17: the popup header's strip and its width (PhonePopup.bar), nil while closed
	room: () -> number, -- 6.17: what shows of the popup's body without scrolling (PhonePopup.room)
}

local player = Players.LocalPlayer

-- 6.5: BAG & ITEMS' open tab ("bag", "items", "bags"); nil picks BAG during a run, else ITEMS. Phone sets it.
PhoneApps.bagTab = nil :: string?

-- Two columns in a list (a wide popup), each a vertical list of its own; else both are the list itself.
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
	return "FULL BOARD" -- (6.17: J opens JOBS now; the old Dispatch board, its REROLL and car card, stays here)
end

-- ── BOARD ──────────────────────────────────────────────────────────────────

local askedAt = 0

local function ask()
	local now = os.clock()
	if askedAt > 0 and now - askedAt < 3 then
		return
	end
	askedAt = now
	Net.get("RequestOffers"):FireServer()
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

-- 6.17: a job's one action (the old card's button, the JOBS app's hero button and its rows' "+"): locked, why; off
-- duty ACCEPT (AcceptJob, then ORDERS); on a run + ADD (AcceptJob: it joins the run), + QUEUE (JobQueue "queue": it
-- waits in NEXT UP) or why neither. A job taken or queued leaves the phone's board until the board comes back.
local function act(offer: any, host: Host)
	local label, why = lockOf(offer)
	local onDuty = type(host.job()) == "table"
	local waits = onDuty and offer.queue == true -- (6.12.8: a job waiting for your car or bike may still queue)
	local function unlist()
		local list = host.board()
		local spot = if list then table.find(list, offer) else nil
		if list and spot then
			table.remove(list, spot)
		end
	end
	if label and not waits then
		host.notify(why or "Not this one yet.")
	elseif not onDuty or offer.addOrder == true then
		Net.get("AcceptJob"):FireServer(offer.index)
		unlist()
		if onDuty then
			host.redraw()
		else
			host.go("orders")
		end
	elseif waits then
		Net.get("JobQueue"):FireServer("queue", offer.index)
		unlist()
		host.redraw()
	else
		host.notify(if type(offer.queueText) == "string" then offer.queueText elseif type(offer.orderText) == "string" then offer.orderText else "Finish your current delivery first.")
	end
end

-- One offer as a card: the cargo → the customer and the pay (6.12.8: big, the first thing you read), the pickup → the
-- address, chips (how it travels or its stars, the distance, the time, its trade-off), the one action: off duty
-- ACCEPT; on a run + ADD (it joins the run), + QUEUE (it waits in NEXT UP) or why neither. 6.17: the JOBS app's
-- details of a job (client/JobsView.luau).
local function offerCard(parent: Instance, offer: any, order: number, look: OrdersUi.Kit, host: Host)
	local label = lockOf(offer)
	local job = host.job()
	local onDuty = type(job) == "table"
	local waits = onDuty and offer.queue == true -- (6.12.8: a job waiting for your car or bike may still queue)
	local open = label == nil or waits
	local b = look.block(parent, order, open)
	SpecialOrderUi.decorate(b.Parent, b, offer) -- 6.14: a golden or a regular's order: its colours, perks, countdown
	-- 6.12.11: the business's picture across the top (its name on it), or while not uploaded a slim banner.
	JobThumbUi.strip(b, offer, 0)
	local title = if type(offer.jobType) == "table" then `{offer.jobType.name}: {offer.cargo}` else `{offer.cargo or "Cargo"} → {offer.customer or "a customer"}`
	local payText = Ui.money(tonumber(offer.pay) or 0)
	local payW = look.width(payText, 18, Theme.HeadingFont)
	local head = Ui.make("Frame", { Name = "TitleRow", Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
	look.text(head, payText, UDim2.new(0, payW, 1, 0), {
		Name = "Pay",
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 18,
		TextColor3 = if open then K.text else K.secondary,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	look.text(head, string.upper(title), UDim2.new(1, -(payW + 8), 1, 0), {
		Font = Theme.HeadingFont,
		TextColor3 = if open then K.text else K.secondary,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
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
	local badge, tint = RegularsApp.badge(offer) -- 6.14: your tier with its business
	if badge then
		look.chip(chips, badge, tint)
	end
	local night = tonumber(offer.nightPay)
	if night and night > 1 then
		look.chip(chips, string.format("Night ×%.1f", night))
	end
	local button, kind = "ACCEPT", "main"
	if label and not waits then
		button, kind = label, "off"
	elseif onDuty and offer.addOrder == true then
		button = "+ ADD"
	elseif waits then
		button = "+ QUEUE"
	elseif onDuty then
		button = if type(offer.queueButton) == "string" then offer.queueButton elseif type(offer.orderButton) == "string" then offer.orderButton else "FINISH YOUR RUN"
		kind = "off"
	end
	look.button(b, button, kind, 4, function()
		act(offer, host)
	end)
end

-- 6.12.8, YOUR RUN: the open orders of your run, one line each (what, from → to · its pay and its clock, ticked by
-- OrdersUi.tick), the run's pay, the next stop, DETAILS (the ORDERS app). Returns the last layout order used.
function PhoneApps.runCard(list: Instance, look: OrdersUi.Kit, host: Host, order: number): number
	local job = host.job()
	if type(job) ~= "table" then
		return order
	end
	local lines, total, nextStop = JobQueue.runLines(job)
	local b = look.block(list, order + 1, true)
	b.Parent.Name = "YourRun"
	local head = Ui.make("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = 1 }, b)
	local count = #lines
	local cap = look.caps(head, `Your run · {count} {if count == 1 then "order" else "orders"} · {Ui.money(total)}`, 0, K.red)
	cap.Size = UDim2.new(1, -96, 1, 0)
	cap.TextSize = 11
	look.pill(head, "Details", function()
		host.go("orders")
	end)
	for index, line in lines do
		local route = if line.route ~= "" then ` · {line.route}` else ""
		local prefix = `{Ui.money(line.pay)} · `
		local _, left, right = look.row2(b, `{line.icon}  {line.title}{route}`, `{prefix}00:00`, 1 + index, true)
		left.Name = "RunLine"
		left.TextSize = 13
		left.Font = if line.focused then Theme.HeadingFont else Theme.Font
		right.TextSize = 13
		if line.endsAt then
			OrdersUi.track(right, line.endsAt, prefix)
		else
			right.Text = Ui.money(line.pay)
		end
	end
	if nextStop then
		look.meta(b, `Next stop: {nextStop}`, 2 + count, K.text).Name = "NextStop"
	end
	return order + 1
end

-- 6.12.8, NEXT UP: the queued jobs in order (what, from → to, pay, ✕ drops one); the next one says why it waits.
-- Returns the last layout order used.
function PhoneApps.nextUp(list: Instance, look: OrdersUi.Kit, host: Host, order: number): number
	local queue = host.queue()
	local entries = if type(queue) == "table" and type(queue.list) == "table" then queue.list else {}
	if #entries == 0 then
		return order
	end
	local max = tonumber(queue.max) or JobQueue.max()
	local paused = queue.paused == true
	look.section(list, `Next up · {#entries} / {max}`, order + 1)
	local b = look.block(list, order + 2, paused)
	b.Parent.Name = "NextUp"
	-- review: PAUSED (after a failed delivery, a lost order, a mission: RESUME) or PAUSE, and CLEAR ALL.
	local controls = Ui.make("Frame", { Name = "Controls", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 0 }, b)
	local status = look.caps(controls, if paused then JobQueue.pausedLine(queue.pausedWhy) else "▶ They start on their own", 0, if paused then K.red else K.secondary)
	status.Name = "QueueState"
	status.Size = UDim2.new(1, -190, 1, 0)
	status.TextSize = 11
	status.TextWrapped = true
	local clear = look.pill(controls, "Clear all", function()
		Net.get("JobQueue"):FireServer("clear")
	end)
	clear.Name = "ClearAll"
	local toggle = look.pill(controls, if paused then "Resume" else "Pause", function()
		Net.get("JobQueue"):FireServer(if paused then "resume" else "pause")
	end, paused)
	toggle.Name = if paused then "Resume" else "Pause"
	toggle.Position = UDim2.new(1, -(look.width("CLEAR ALL", 11, Theme.HeadingFont) + 28), 0.5, 0)
	for index, entry in entries do
		if type(entry) ~= "table" then
			continue
		end
		local row = Ui.make("Frame", { Name = "NextRow", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = index }, b)
		Ui.list(row, true, 2)
		local line = Ui.make("Frame", { Name = "Line", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 1 }, row)
		local payText = Ui.money(tonumber(entry.pay) or 0)
		local payW = look.width(payText, 15, Theme.HeadingFont)
		-- 6.12.11: a small square of the business's picture on the left (once uploaded; else the row as before).
		local inset = if JobThumbUi.square(line, entry, 36) then 44 else 0
		look.text(line, `{index}  {JobQueue.icon(entry.mode, entry.stars)}  {entry.title or entry.cargo or "Job"}`, UDim2.new(1, -(payW + 64 + inset), 0, 18), {
			Position = UDim2.fromOffset(inset, 0),
			Font = Theme.HeadingFont,
			TextSize = 13,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		look.text(line, JobQueue.route(entry.from, entry.to), UDim2.new(1, -(payW + 64 + inset), 0, 16), {
			Position = UDim2.fromOffset(inset, 19),
			TextSize = 12,
			TextColor3 = K.secondary,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		look.text(line, payText, UDim2.new(0, payW, 1, 0), {
			Position = UDim2.new(1, -52, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			Font = Theme.HeadingFont,
			TextSize = 15,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local id = tonumber(entry.id)
		local drop = look.pill(line, "✕", function()
			Net.get("JobQueue"):FireServer("drop", id)
		end)
		drop.Name = "Drop"
		if entry.starting == true and not paused then
			look.meta(row, "▶ Starts in a few seconds · PAUSE to wait", 2, K.text).Name = "Starting"
		elseif type(entry.why) == "string" and entry.why ~= "" then
			look.meta(row, `⏸ Waits: {entry.why}`, 2, K.red).Name = "Why"
		end
		-- 6.14: a golden or a regular's order runs out in NEXT UP as on the board
		local special = if type(entry.specialOrder) == "table" then entry.specialOrder else nil
		if special then
			local runs = look.meta(row, "", 3, SpecialOrderUi.colorOf(special))
			runs.Name = "RunsOut"
			SpecialOrderUi.countdown(runs, special.expiresAt, `{if special.kind == "golden" then "★ GOLDEN ORDER" else "★ REGULAR'S ORDER"} · leaves NEXT UP in `)
		end
	end
	return order + 2
end

-- 6.17: JOBS opens on its list (Phone: a tap on JOBS, Phone.open("board")).
function PhoneApps.boardHome()
	JobsView.home()
end

-- The JOBS app: 6.17's hero card and compact rows (client/JobsView.luau), the old card as a job's details, YOUR RUN and
-- NEXT UP behind the top bar's chips. No offers yet, or old ones: it asks for the board.
function PhoneApps.board(list: Instance, look: OrdersUi.Kit, host: Host, wide: boolean?)
	local offers, _, refreshAt = host.board()
	if offers == nil or (refreshAt ~= nil and workspace:GetServerTimeNow() >= refreshAt) then
		ask()
	end
	JobsView.draw(list, look, host, wide == true, {
		card = function(parent: Instance, offer: any, order: number)
			offerCard(parent, offer, order, look, host)
		end,
		run = function(into: Instance, order: number): number
			return PhoneApps.runCard(into, look, host, order)
		end,
		nextUp = function(into: Instance, order: number): number
			return PhoneApps.nextUp(into, look, host, order)
		end,
		act = function(offer: any)
			act(offer, host)
		end,
		why = lockOf,
	}, fullBoardLabel())
end

-- ── BAG ────────────────────────────────────────────────────────────────────

-- 6.5: BAG & ITEMS, the I window's tabs (🛍 BAG during a run, ITEMS, BAGS). 6.18 wave 2: client/BagUi.luau draws them
-- in the UI kit's look (the bag as the hero, a row an item with its count big and a round USE), the tabs as chips in
-- the popup's header strip when they fit.
local BAG_TABS: { { string } } = { { "bag", "🛍 BAG" }, { "items", "ITEMS" }, { "bags", "BAGS" } }

function PhoneApps.bag(list: Instance, look: OrdersUi.Kit, host: Host, wide: boolean?)
	local job = host.job()
	local running = type(job) == "table"
	local tab = PhoneApps.bagTab or (if running then "bag" else "items")
	if tab == "bag" and not running then
		tab = "items" -- (the run ended)
	end
	local tabs: { { string } } = {}
	for _, entry in BAG_TABS do
		if entry[1] ~= "bag" or running then
			table.insert(tabs, entry)
		end
	end
	local Hotbar = require(script.Parent.Hotbar)
	BagUi.draw(list, {
		tab = tab,
		tabs = tabs,
		pick = function(id: string)
			PhoneApps.bagTab = id
			host.redraw()
		end,
		state = host.state(),
		job = job,
		side = wide == true,
		room = host.room(),
		bar = host.bar,
		redraw = host.redraw,
		toast = host.notify,
		use = function(id: string)
			local use = Hotbar.onUse
			if use then
				use(id) -- (the HUD's own useItem, the UseItem remote with your aim)
			else
				Net.get("UseItem"):FireServer(id)
			end
		end,
		slotOf = Hotbar.slotOf,
		keys = not Ui.touchLayout(),
	}, 1)
end

-- ── 6.5: SHOP's list of the shops ─────────────────────────────────────────

-- The shops (Map.Shops ids) in the order a new courier needs them, with what they sell. 6.6: ZDC Bags first (the
-- depot's bag kiosk, by the spawn); Last Stop Supplies keeps the vests and the items. 6.7: what each really sells
-- (Lead & Co. the gun upgrades and the bat too; Wrench Garage the stages, the car upgrades, gear and paint). 6.12.2:
-- the bags and Last Stop Supplies are the two counters of the gear stall by the spawn; no running shoes any more.
-- 6.12.7: one shop for the cars and the bikes, Dead End Motors (its CARS and BIKES counters), where Spoke & Chain's row
-- was (the bikes come before the first car). 6.12.14: Lead & Co. sells at its shooting range out of the safe zone (the
-- GPS to the range shop's counter, Map.Shops.guns).
local SHOPS: { { id: string, icon: string, sells: string } } = {
	{ id = "bags", icon = "🛍️", sells = "Bags (sprint with your deliveries)" },
	{ id = "supplies", icon = "🛒", sells = "Items and vests, next to the bags" }, -- (6.12.2: the gear stall, no shoes)
	{ id = "guns", icon = "🔫", sells = "Range · guns, gun upgrades, a baseball bat" }, -- (6.12.14: the range)
	{ id = "dealer", icon = "🚗", sells = "Cars, vans, trucks · bikes, the E-Scooter, bike gear" },
	{ id = "mechanic", icon = "🔧", sells = "Stages, car upgrades, gear, paint, car guns, repairs" },
}

-- Draws the list at `order` in the SHOP app: a row a shop (6.18 wave 2: the kit's compact row: its icon, name, what it
-- sells, a round "📍"); a tap sets the GPS to it, puts the phone away and says so.
function PhoneApps.shops(list: Instance, look: OrdersUi.Kit, host: Host, order: number)
	local holder = Ui.make("Frame", { Name = "Shops", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, list)
	Ui.list(holder, true, Config.UiKit.Gap)
	CardKit.sectionHeader(holder, { text = "THE SHOPS · TAP ONE FOR THE GPS", order = 0 })
	for index, entry in SHOPS do
		local shop = Map.Shops[entry.id]
		if not shop then
			continue
		end
		local function go()
			host.gps(entry.id)
			host.close()
			host.notify(`GPS set: {shop.name}`)
		end
		CardKit.row(holder, {
			name = `Shop_{entry.id}`,
			order = index,
			accent = K.line,
			picture = { emoji = entry.icon },
			thumb = Config.UiKit.Icon,
			title = shop.name,
			facts = entry.sells,
			action = "📍",
			silent = true,
			onOpen = function()
				CardKit.click()
				go()
			end,
		})
	end
end

-- The SHOP app (6.18 wave 2, the UI kit; client/Phone.luau opens it): two tabs as chips, SAVE UP (what to save up for:
-- the savings goal, 6.14's Readiness goal, or the best thing you can buy, as the HERO with your money's bar toward its
-- price; then a row each: the personal gear still to buy, the next bikes and vehicles, the PRICE big, green when you
-- can buy it; 📍 sets the GPS to its counter, buying stays at the counters) and SHOPS (the list above).
PhoneApps.shopTab = "save"

function PhoneApps.shop(list: Instance, look: OrdersUi.Kit, host: Host, wide: boolean?, goal: string?)
	local state = host.state()
	local money = if type(state) == "table" then tonumber(state.money) or 0 else 0
	local xp = tonumber(player:GetAttribute("Xp"))
	if xp == nil and type(state) == "table" and type(state.xp) == "number" then
		xp = state.xp
	end
	local level = Levels.levelFor(xp or 0)
	local tabs = { tabs = { { "save", "SAVE UP" }, { "shops", "SHOPS" } }, selected = PhoneApps.shopTab, onPick = function(id: string)
		PhoneApps.shopTab = id
		host.redraw()
	end }
	if PhoneApps.shopTab == "shops" then
		local strip = Ui.make("Frame", { Name = "ShopTabs", Size = UDim2.new(1, 0, 0, Config.UiKit.Chip + 4), BackgroundTransparency = 1, LayoutOrder = 0 }, list)
		CardKit.tabs(strip, tabs)
		PhoneApps.shops(list, look, host, 1)
		return
	end
	local items: { ShopView.Item } = {}
	local function add(id: string, name: string, picture: CardKit.Picture, where: string, shopId: string, price: number, lvl: number, label: string?)
		local locked = level < lvl
		table.insert(items, {
			id = id,
			name = name,
			picture = picture,
			fact = `{where}{if locked then ` · 🔒 LV {lvl}` else ""}`,
			price = price,
			valueColor = if locked or money < price then CardKit.Color.dim else nil, -- (locked: dim, its 📍 still works)
			forSale = true,
			act = { text = "📍 SET GPS", short = "📍", on = true, kind = if money >= price and not locked then "good" else "primary", run = function()
				host.gps(shopId)
				local shop = Map.Shops[shopId]
				host.notify(`GPS: {if shop then shop.name elseif shopId == "earl" then Config.VanQuest.Place else label or name}`)
			end },
			lines = { `{name}: {Ui.money(price)} · level {lvl}.`, `Sold at {where}. Buying happens at the counter: 📍 sets the GPS there.` },
		})
	end
	-- The personal gear still worth buying (Config.Kit), the cheapest first: 6.6: the bags (ZDC Bags), then the rest of
	-- the kit (Last Stop Supplies); 6.7: each piece at its own shop (the Baseball Bat at Lead & Co.'s range).
	local owned = if type(state) == "table" and type(state.kit) == "table" then state.kit else {}
	for _, shopId in { "bags", "supplies", "guns" } do
		local wanted: { Config.KitDef } = {}
		for _, def in Config.Kit do
			if not owned[def.id] and Transport.kitShop(def) == shopId then
				table.insert(wanted, def)
			end
		end
		table.sort(wanted, function(a: Config.KitDef, b: Config.KitDef): boolean
			return a.price < b.price
		end)
		local shop = Map.Shops[shopId]
		for _, def in wanted do
			add(def.id, def.name, { icon = Icons.kit(def.id), emoji = def.icon }, if shop then shop.name else shopId, shopId, def.price, def.level)
		end
	end
	-- 5.1: the next two bikes you do not own (6.12.7: Dead End Motors' BIKES counter, Map.Shops.bikes), then the next two
	-- vehicles (5.0: the Old Van from Earl, Marge's quest; the others from Dead End Motors).
	local cars = if type(state) == "table" and type(state.cars) == "table" then state.cars else {}
	local bikes, rides = 0, 0
	for _, def in Config.Cars do
		if def.bike and not cars[def.id] and bikes < 2 then
			bikes += 1
			add(def.id, def.name, ShopView.vehicle(def), `{Config.BikeShop.Shop}, {Config.BikeShop.Counter}`, "bikes", def.price, def.level or 1, "Dead End Motors · Bikes")
		end
	end
	local list2: { Config.CarDef } = {}
	for _, def in Config.Cars do
		if not def.company and not def.bike then
			table.insert(list2, def)
		end
	end
	table.sort(list2, function(a: Config.CarDef, b: Config.CarDef): boolean
		if (a.level or 1) ~= (b.level or 1) then
			return (a.level or 1) < (b.level or 1)
		end
		return a.price < b.price
	end)
	for _, def in list2 do
		if cars[def.id] or rides >= 2 then
			continue
		end
		rides += 1
		if def.id == Config.VanQuest.Car then
			local quest = type(state) == "table" and state.vanQuest == "open"
			add(def.id, def.name, ShopView.vehicle(def), if quest then `{Config.VanQuest.Seller}, far out west` else "Marge's quest", "earl", def.price, def.level or 1)
		else
			add(def.id, def.name, ShopView.vehicle(def), "Dead End Motors", "dealer", def.price, def.level or 1)
		end
	end
	local chips: { CardKit.Chip } = {
		{ name = "CashChip", text = Ui.money(money), ink = CardKit.Color.money, face = CardKit.Color.goodFace, static = true },
		{ name = "LevelChip", text = `LV {level}`, static = true },
	}
	ShopView.draw(list, {
		key = "phone:shop",
		items = items,
		money = money,
		goal = goal,
		side = wide == true,
		room = host.room(),
		order = 0,
		tabs = tabs,
		chips = chips,
		bar = host.bar,
		section = "SAVE UP FOR",
		empty = "You have it all. The counters still sell items, upgrades and looks.",
		foot = "Buying happens at the counters: 📍 sets the GPS.",
		redraw = host.redraw,
		toast = host.notify,
	})
end

-- ── GARAGE ─────────────────────────────────────────────────────────────────

-- Your own car's fuel share (its Tank / Fuel attributes, server/Fuel.luau), nil without one out.
local function fuelShare(): number?
	local cars = workspace:FindFirstChild("Cars")
	for _, car in if cars then cars:GetChildren() else {} do
		if car:GetAttribute("OwnerId") == player.UserId then
			local tank, fuel = car:GetAttribute("Tank"), car:GetAttribute("Fuel")
			if type(tank) == "number" and tank > 0 and type(fuel) == "number" then
				return math.clamp(fuel / tank, 0, 1)
			end
		end
	end
	return nil
end

-- 6.18 wave 2, GARAGE in the UI kit's look: the vehicle you have out as the HERO (its picture, its name, its cargo
-- slots big, its condition and fuel as facts, BRING MY CAR: SpawnCar), then a row each: 🚲 MY BIKE (RIDE: the Equip
-- remote's "ride"), 🚐 CALL CAR (CALL: "drive"), ⛽ TOW while your own car's tank is empty (the Fuel remote), and ZDC
-- RIDE (5.6: the nearest rental dock, shared/RentalDocks.luau; 📍 its GPS, MapView.setWaypoint).
function PhoneApps.garage(list: Instance, look: OrdersUi.Kit, host: Host, wide: boolean?)
	local state = host.state()
	local owned = if type(state) == "table" and type(state.cars) == "table" then state.cars else {}
	local hasBike, hasCar = false, false
	local bikeDef: Config.CarDef?, carDef: Config.CarDef? = nil, nil
	for _, def in Config.Cars do
		if owned[def.id] and not def.company then
			hasBike = hasBike or def.bike == true
			hasCar = hasCar or not def.bike
			if def.bike and not bikeDef then
				bikeDef = def
			elseif not def.bike and not carDef then
				carDef = def
			end
		end
	end
	local outId = if type(state) == "table" and type(state.car) == "string" then state.car else nil
	local out = if outId then Economy.findCar(outId) else nil
	if out and out.bike then
		bikeDef = out
	elseif out then
		carDef = out
	end
	local lastCar = if type(state) == "table" and type(state.lastCar) == "string" then Economy.findCar(state.lastCar) else nil
	if lastCar and not lastCar.bike then
		carDef = lastCar
	end
	local items: { ShopView.Item } = {}
	-- the hero: what you have out
	local heroFacts: { string } = {}
	local health = if out and type(state.carHealth) == "table" and type(state.carHealth[out.id]) == "number" then state.carHealth[out.id] else nil
	if health then
		table.insert(heroFacts, `🔧 {math.floor(health * 100 + 0.5)}%`)
	end
	local fuel = if out and not out.bike then fuelShare() else nil
	if fuel then
		table.insert(heroFacts, `⛽ {math.floor(fuel * 100 + 0.5)}%`)
	end
	local levels = if out then Economy.carLevels(state.carUpgrades, out.id) else nil
	table.insert(items, {
		id = "out",
		name = if out then out.name else "On foot",
		picture = ShopView.vehicle(out),
		fact = if #heroFacts > 0 then table.concat(heroFacts, " · ") else host.transport(),
		value = if out and levels then `📦 {Economy.capacity(out.id, levels)}` else nil,
		current = true,
		-- (6.18 review: a job's company vehicle comes too without a car of your own: SpawnCar brings it)
		act = if hasCar or type(host.job()) == "table" then { text = if hasCar then "BRING MY CAR" else "BRING THE VEHICLE", on = true, run = function()
			Net.get("SpawnCar"):FireServer()
			host.close()
		end, name = "BringCar" } else { text = if hasBike then "NO CAR YET" else "NO VEHICLE YET", on = false, why = "No vehicle of your own yet: the SHOP app says what comes next." },
		lines = { host.transport(), if hasCar then "BRING MY CAR sets your car (or a job's company vehicle) down next to you." elseif hasBike then "Your bike is yours; the first car comes later (the SHOP app says when)." else "No vehicle of your own yet: the SHOP app says what comes next." },
	})
	if hasBike and bikeDef then
		table.insert(items, {
			id = "bike",
			name = "🚲 MY BIKE",
			picture = ShopView.vehicle(bikeDef),
			fact = `{string.upper(bikeDef.name)} · NO GARAGE, AT ONCE`,
			owned = true,
			act = { text = "🚲 MY BIKE", short = "RIDE", on = true, kind = "good", run = function()
				Net.get("Equip"):FireServer("ride")
				host.close()
			end },
			actionName = "Ride",
		})
		if hasCar and carDef then
			table.insert(items, {
				id = "car",
				name = "🚐 CALL CAR",
				picture = ShopView.vehicle(carDef),
				fact = `{string.upper(carDef.name)} · A CHAUFFEUR BRINGS IT`,
				owned = true,
				act = { text = "🚐 CALL CAR", short = "CALL", on = true, kind = "good", run = function()
					Net.get("Equip"):FireServer("drive")
					host.close()
				end },
				actionName = "Call",
			})
		end
	end
	if PhoneApps.towDue() then
		table.insert(items, {
			id = "tow",
			name = "⛽ Out of fuel",
			picture = { emoji = "⛽" },
			fact = "TOW TO THE NEAREST PUMP",
			price = Config.Fuel.TowPrice,
			accent = K.red,
			act = { text = `⛽ TOW  {Ui.money(Config.Fuel.TowPrice)}`, short = "TOW", on = true, run = function()
				Net.get("Fuel"):FireServer("tow")
				host.close()
			end },
			actionName = "Tow",
			lines = { "Your car's tank is empty. The tow takes it to the nearest pump with a little fuel in it." },
		})
	end
	table.insert(items, PhoneApps.rideItem(host))
	ShopView.draw(list, {
		key = "phone:garage",
		items = items,
		money = if type(state) == "table" then tonumber(state.money) or 0 else 0,
		side = wide == true,
		room = host.room(),
		order = 1,
		redraw = host.redraw,
		toast = host.notify,
	})
end

-- 5.6, ZDC RIDE: the nearest rental dock (straight, from where you stand) and the GPS to it, as GARAGE's row; its
-- details say what to do (you have one out: the player attribute Rental).
function PhoneApps.rideItem(host: Host): ShopView.Item
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local here = if root and root:IsA("BasePart") then root.Position else nil
	local dock, far = nil, 0
	if here then
		dock, far = RentalDocks.nearest(here.X, here.Z)
	end
	local found = dock
	return {
		id = "ride",
		name = "🛴 ZDC RIDE",
		picture = { emoji = "🛴" },
		fact = if found then `ZDC RIDE · nearest dock {math.floor(far)} studs` else "ZDC RIDE · free e-scooters",
		owned = true,
		accent = K.warn,
		act = if found then { text = "📍 GPS", short = "📍", on = true, run = function()
			MapView.setWaypoint(Vector3.new(found.x, Map.RoadTop, found.z))
			pcall(function()
				MapView.onWaypoint({ id = "zdcride", name = `ZDC RIDE · {found.name}`, icon = "🛴", x = found.x, z = found.z, kind = "shop", description = "" })
			end)
			host.notify(`GPS: ZDC RIDE · {found.name}`)
		end } else nil,
		actionName = "Gps",
		lines = { if player:GetAttribute("Rental") ~= nil then "Your rental: leave it anywhere, or Return it at any dock." else "Free e-scooters at docks across Downtown and the Suburbs: hold Rent." },
	}
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
	{ "R", "Style: looks from Dot, Gus, Kip" }, -- 6.12: the clerks' second prompt (server/ShopClerks.luau)
	{ "F", "Fire" },
	{ "1 / 2 / 3", "Hold: fists, bag, gun" },
	{ "B", "Holster, draw" },
	{ "V", "Punch (the bat once bought), strike" },
	{ "Y", "Take a road offer" },
	{ "X", "Throw (at a door)" },
	{ "4 – 8", "Items" },
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
