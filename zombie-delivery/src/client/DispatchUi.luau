--!strict
-- The Dispatch board: the job board as a charcoal window of delivery briefings (3.8, the contract UI,
-- design/ui-contract/; it replaced 3.6's die-cut tickets). J, the JOBS menu entry, the depot counter and the result
-- window's NEXT JOB open it (Main sets Hud.onJobs = DispatchUi.open; another window opening closes it).
--
--   * Opening asks the server for the board (RequestOffers): it sends the current offers, sorted ★ → ★★★★, and when
--     the next ones come (Offers → DispatchUi.setOffers(list, refreshAt), wired in Main; "Calling the dispatcher..."
--     until the first ones). 3.7: no refresh button: the server makes new offers every Config.Jobs.RefreshSeconds and
--     pushes them; the caption row counts down to them quietly ("NEW JOBS IN 2:41"). ACCEPT JOB fires AcceptJob with
--     the offer's index (its id on the server's board) and closes; the server checks every offer again (a taken,
--     replaced or locked one is refused there with its own notice).
--   * Left column: AVAILABLE RUNS filters (All jobs / Deliveries / Special jobs, with counts) and a card for your
--     car (its name at its stage, cargo slots, condition): your vehicle sets your job capacity.
--   * A briefing row per offer: a numbered spine with the cargo's icon, the risk label ("RISKY · ★★") with the
--     twists as compact tags (the modifier, SPECIAL, RUSH CLOCK for a timed job, BANDITS when the cargo is wanted),
--     the title (the special job's name, else the cargo and the customer), then labelled lines: ROUTE (the first stop
--     → the last address, its district, the stops, the distance), CARGO (the pieces, how they move, the cargo slots,
--     a company vehicle), DEADLINE (the time, fixed on a rush clock), RISK (the modifier's description) and JOB (the
--     special job's); the payout column on the right (PAYOUT, the pay, NIGHT ×n while night pay is up) with
--     ACCEPT JOB →. Hover brightens the row (Ui.tactile).
--   * Locked rows say why and what to do under a red LOCKED label: above your driver level ("🔒 LEVEL 4", the level
--     and rank needed), or more pieces than your car holds ("📦 NEEDS 6 SLOTS", what your car holds and
--     Economy.roomAdvice: the next stage at Wrench Garage, or a bigger car from your garage). Their button flashes the
--     remedy and toasts the same reason, like the old board did.
--   * 4.7, a choice: the ordinary offers of a danger level come in a group under its header ("★★ RISKY · pick one"):
--     three rows, each with its trade-off as a tag (🛡 SHORT & SAFE, 🛣 LONG HAUL, ☠ RISKY, 📦 BULK ORDER) and a WHY
--     line, and REROLL $100 on the header (RerollTier: new offers of that tier, once until the board refreshes). A
--     tier without its licence (shared/JobRules.luau) shows one row locked "🪪 LICENCE 3 / 5" with what it needs; the
--     caption names your streak of good jobs.
--   * On a delivery the board shows that job and GIVE UP THIS DELIVERY (CancelJob) instead of offers.
--   * Footer: an ESC chip, "Close window", and "OLD VAN · 2 CARGO SLOTS · Road Rat / level 4".
--   * 5.0, the career starts on foot: the offers with mode = "foot" (a missing mode is "car") come first in an ON FOOT
--     section: a header with your room ("HANDS 2 / TOTE 5", client/KitShop.luau roomText from shared/Transport),
--     each row with a 🚶 ON FOOT chip in place of the danger level and "fits your hands (2 / 3)" on its CARGO line. With
--     no vehicle (state.car nil) the car card is an ON FOOT card (your room, your pace, when the first vehicle comes),
--     the car tiers' headers say "NEEDS A VEHICLE · Old Van at level 4" (no REROLL) and every job that needs your own
--     vehicle is locked "🚐 NEEDS A VEHICLE" with that remedy (a job that lends a company vehicle is not). The server
--     refuses them anyway.
--   * 5.1, the bikes: the offers with mode = "bike" come next in a BIKE section (from Config.Jobs.Bike.Level): a header
--     with your bike and what it holds (the Offers info's `bike`), each row with a 🚲 BIKE chip and "fits your bike
--     (3 / 4)" on its CARGO line; without a bike they are locked "🚲 NEEDS A BIKE" (the BIKES counter), while your car is
--     the one you drive "🚲 RIDE YOUR BIKE" (the server's lockText / lockButton). Riding your bike (state.car a bike)
--     the car card shows the bike, and the car jobs are locked "🚐 CALL YOUR CAR" (the phone's CALL CAR).
--   * 5.8, the courier phone's look (design/phone-ui/): the ZDC window header (Ui.window, the board glyph), the filters
--     as the phone's square tabs (Ui.tabs, a column: the open one raised with a red bar, its count on the right), the
--     offers as slim hairline cards like the phone's BOARD (the title in caps, the twists as the phone's chips, the
--     payout behind a thin divider) with ACCEPT JOB / + ADD ORDER as the red primary action, and the section headers
--     (ON FOOT, BIKE, the danger levels) led by the small red marker.
--   * 6.12.8 (the owner: "once I take a job I can't add more … a list where I have the jobs and how much I earn, and
--     add even all of them"): the board shows its offers during every run. On top YOUR RUN (the phone's summary,
--     shared/JobQueue.luau runLines: every open order in one line with its pay and clock, the run's pay, the next
--     stop; DETAILS opens the phone's ORDERS, GIVE UP), NEXT UP (the queued jobs: what, where, pay, why the next one
--     waits, ✕; review: PAUSE / RESUME, PAUSED after a failed delivery, CLEAR ALL) and ADD ALL · $total. A row's one action during a run: + ADD (AcceptJob: it joins the run) or + QUEUE
--     (the JobQueue remote: it waits in NEXT UP), else why neither; off duty ACCEPT JOB as before.
--   * 6.12.11, the job pictures (Codex's business pictures, shared/JobThumbs.luau, client/JobThumbUi.luau): a row's
--     briefing opens with its business's picture across the column (about 2.4 : 1, at most 150 px tall, cropped: the
--     sign stays; the business's name on a dark label), a slim banner (the cargo emoji and the name) while it is not
--     uploaded; NEXT UP's rows a small square of it once uploaded.
-- The window (Ui.window) is built on first open (lazy) in a ScreenGui of its own, scaled like every window
-- (Ui.screenScale) and sized to the screen. ESC (and the gamepad's B, and opening the Roblox menu) close it; while it is open the mouse is
-- free (Main: CameraRig.mouseNeeded checks DispatchUi.isOpen()). 4.2, a gamepad: the selection starts on the first
-- ACCEPT JOB you can take (Ui.gamepadFocus), A takes it, the stick moves to the others.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Icons = require(Shared.Icons)
local Levels = require(Shared.Levels)
local Net = require(Shared.Net)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)
local Drive = require(script.Parent.Drive)
local Hud = require(script.Parent.Hud)
local KitShop = require(script.Parent.KitShop) -- 5.0: the room on foot in words ("HANDS 2 / TOTE 5")
local BikeShop = require(script.Parent.BikeShop) -- 5.1: your bike and what it holds
local Transport = require(Shared.Transport)
local JobQueue = require(Shared.JobQueue) -- 6.12.8: YOUR RUN and NEXT UP, the same words as the phone's BOARD
local JobThumbUi = require(script.Parent.JobThumbUi) -- 6.12.11: the job pictures

local K = Theme.Contract
local C = Theme.Colors
local DispatchUi = {}

-- Set by Main: opening this window closes the others.
DispatchUi.onOpen = nil :: (() -> ())?
-- 6.12.8, set by Main: YOUR RUN's DETAILS (the phone's ORDERS app).
DispatchUi.onDetails = nil :: (() -> ())?

local player = Players.LocalPlayer

-- Sizes at scale 1 (the 1150 × 680 reference; Ui.screenScale scales the whole window).
local MAX_W, MAX_H, MIN_W, MIN_H = 1000, 600, 640, 380
local SIDEBAR = 220
local SPINE, STUB, GAP = 64, 160, 8
local LABEL_W = 78 -- the small caps label column of a briefing line (ROUTE, CARGO, DEADLINE ...)
local MONO = Theme.MonoFont

-- 3.8: the contract surfaces (Theme.Contract): the sidebar sunk, the rows a step above charcoal, a locked row a step
-- below, the remedy note with a red rule.
local SIDE = K.recessed
local ROW = K.row
local LOCKED_ROW = Theme.Postage.hatch
local NOTE = Theme.Postage.note
local FLASH = Theme.Postage.rose
local SEPARATOR = `<font color="#{K.line:ToHex()}">  /  </font>`

-- How one piece of each kind of cargo looks (the same names and emoji the old board used; Hud's ITEMS).
local KINDS: { [string]: { icon: string, one: string, many: string } } = {
	crate = { icon = "📦", one = "crate", many = "crates" },
	ammo = { icon = "🧰", one = "ammo box", many = "ammo boxes" },
	sack = { icon = "🌽", one = "sack", many = "sacks" },
	barrel = { icon = "🛢️", one = "barrel", many = "barrels" },
	icebox = { icon = "🍦", one = "ice box", many = "ice boxes" },
	furniture = { icon = "🛋️", one = "furniture", many = "pieces of furniture" },
	soup = { icon = "🍲", one = "soup pot", many = "soup pots" },
	horse = { icon = "🐴", one = "horse", many = "horses" },
	kid = { icon = "🧒", one = "kid", many = "kids" },
}

-- How the cargo of an offer moves, in two or three words (offer.handling: the first stop's mode).
local HANDLING: { [string]: string } = {
	carry = "carried by hand",
	lead = "led on a rope",
	board = "they get on",
	serve = "sold from the truck",
	pallet = "moved on a pallet jack", -- 4.0, the Freight Run
}

local FILTERS = {
	{ id = "all", name = "All jobs" },
	{ id = "delivery", name = "Deliveries" },
	{ id = "special", name = "Special jobs" },
}

local gui: ScreenGui? = nil
local refs: { [string]: any } = {}
local filterTabs: Ui.Tabs? = nil -- 5.8: the AVAILABLE RUNS filters (Ui.tabs)
local filterCounts: { [string]: any } = {} -- their counts, by filter id
local open = false
local offers: { any }? = nil -- nil: waiting for the dispatcher
local state: any = nil
local job: any = nil
local filter = "all"
local width, height = MAX_W, MAX_H
local resizeQueued = false
local offersRemote: RemoteEvent? = nil
local askedAt = 0 -- os.clock() of the RequestOffers still waiting for its answer (0: none)
local refreshAt: number? = nil -- 3.7: when the server makes the next offers (workspace:GetServerTimeNow())
local boardInfo: any = nil -- 4.7: { tiers = { { stars, name, fee, rerolled, open, level, licence? } }, streak } (Offers' third value)
local ticking = false -- 3.7: the countdown's loop runs (while the board is open)
local queueState: any = nil -- 6.12.8: the NEXT UP queue the server sent ({ list, max }; the JobQueue remote)

-- 5.2: is the board open on a run that takes more orders (the job payload's `stack`)? Then it shows the offers with
-- + ADD on the ones that fit (6.12.8: + QUEUE on the others when they may wait; every run shows the offers now).
local function stacking(): boolean
	return job ~= nil and type(job.stack) == "table" and job.stack.can == true
end

local function getOffersRemote(): RemoteEvent
	if not offersRemote then
		offersRemote = Net.get("RequestOffers")
	end
	return offersRemote :: RemoteEvent
end

-- ── Small pieces ───────────────────────────────────────────────────────────

-- A label in the contract text (Ui.label with the board's defaults).
local function text(parent: Instance, value: string, size: UDim2, props: { [string]: any }?): any
	local label = Ui.label(parent, value, size, { TextColor3 = K.text, Font = Theme.Font, TextSize = 14 })
	if props then
		for key, v in props do
			label[key] = v
		end
	end
	return label
end

-- A compact tag that grows with its text (the twists on a row), the phone's chip (5.8): a raised face, the text in
-- caps in its tint (red for a danger, white for `K.text`, else the secondary white) and a faint outline of that tint.
local function chip(parent: Instance, value: string, accent: Color3, order: number): any
	local tint = if accent == K.red then K.red elseif accent == K.text then K.text else K.secondary
	local label = text(parent, string.upper(value), UDim2.fromOffset(0, 20), {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = K.raised,
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = tint,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		LayoutOrder = order,
	})
	Ui.stroke(label, tint, 1).Transparency = if tint == K.red then 0.5 else 0.72
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }, label)
	return label
end

-- 5.8: the small red marker square that leads a section's title (the phone's "■ ACTIVE ORDER"), in a header row.
local function marker(row: Instance)
	Ui.make("Frame", {
		Name = "Marker",
		Size = UDim2.fromOffset(7, 7),
		Position = UDim2.fromOffset(4, 9),
		BackgroundColor3 = K.red,
		BorderSizePixel = 0,
	}, row)
end

-- The row's action (Ui.button: a flat rectangle, a fine line, hover brightens it and shows its underline, press dips
-- it). `color` nil: the locked look (disabled grey; it still answers with the reason). Placed by its top centre.
local function action(parent: Instance, label: string, size: UDim2, position: UDim2, color: Color3?, fn: () -> ()): any
	local button = Ui.button(parent, label, size, color or C.grey, fn)
	button.Position = position
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.TextSize = 13
	button.TextWrapped = true
	button.ZIndex = 2
	return button
end

-- How tall `value` wraps at `w` px.
local function textHeight(value: string, size: number, font: Enum.Font, w: number): number
	local ok, bounds = pcall(function()
		return TextService:GetTextSize(value, size, font, Vector2.new(math.max(40, w), 10000))
	end)
	return if ok then math.ceil(bounds.Y) else size * 3
end

-- ── What the footer and the car card say ───────────────────────────────────

local function myLevel(): number
	local xp = tonumber(player:GetAttribute("Xp"))
	if xp == nil and state and type(state.xp) == "number" then
		xp = state.xp
	end
	return Levels.levelFor(xp or 0)
end

local function carId(): string
	return if state and type(state.car) == "string" then state.car else Config.Cars[1].id
end

-- 5.0: no vehicle yet (the career starts on foot; state.car is nil). Before the first state: as before (a car).
local function onFoot(): boolean
	return state ~= nil and type(state.car) ~= "string"
end

-- 5.0: an on-foot run (offer.mode; an offer without one is a car job).
local function isFoot(offer: any): boolean
	return offer.mode == "foot"
end

-- 5.1: a bike run (the BIKE section), and riding your bike (state.car is a bike: the car jobs need your car).
local function isBike(offer: any): boolean
	return offer.mode == "bike"
end
local function riding(): boolean
	return state ~= nil and type(state.car) == "string" and Transport.isBike(state.car)
end

local function myKit(): Transport.Kit
	return KitShop.owned(state)
end

-- 6.4: the bag in use (the server's state.bag; its room alone counts, never every bag's)
local function myBag(): string?
	return if state and type(state.bag) == "string" then state.bag else nil
end

-- 5.0: the first vehicle you can own (the earliest dealer car: the Old Van), for "Old Van at level 4".
local function firstVehicle(): Config.CarDef?
	local best: Config.CarDef? = nil
	for _, def in Config.Cars do
		if def.company or def.bike then
			continue
		end
		local b = best
		if b == nil or (def.level or 1) < (b.level or 1) or ((def.level or 1) == (b.level or 1) and def.price < b.price) then
			best = def
		end
	end
	return best
end

-- "Old Van at level 4" (the headers, the car card) and the remedy of a job that needs a vehicle (the row's note).
local function vehicleShort(): string
	local van = firstVehicle()
	return if van then `{van.name} at level {van.level or 1}` else "a vehicle"
end
local function vehicleNote(): string
	local van = firstVehicle()
	if not van then
		return "Car jobs need a vehicle of your own. Until then the ON FOOT runs pay."
	end
	local level = van.level or 1
	local when = if myLevel() >= level then "now" else `from level {level}`
	local where = if van.id == Config.VanQuest.Car then `from {Config.VanQuest.Seller} at {Config.VanQuest.Place} (Marge's quest)` else "at Dead End Motors"
	return `No vehicle yet: this job needs one. The {van.name} is for sale {when} {where} ({Ui.money(van.price)}). Until then the ON FOOT runs pay.`
end

local function carLevels(id: string): any
	return Economy.carLevels(if state then state.carUpgrades else nil, id)
end

-- Your car's name at its stage ("Work Van"), its cargo slots and its condition (0 … 1: the live car's health while
-- it is out, else the parked share the state keeps).
local function myCar(): (string, number, number)
	if onFoot() then
		return "On foot", Transport.handsRoom(myKit(), myBag()), 1 -- 5.0: your hands and your bag (6.6)
	elseif riding() then
		local bike = Economy.findCar(carId())
		return if bike then bike.name else "Bike", BikeShop.room(state, carId()), 1 -- 5.1: what your bike holds
	end
	local id = carId()
	local levels = carLevels(id)
	local def = Economy.findCar(id)
	local stage = Economy.stageDef(id, Economy.stageOf(id, levels))
	local name = if stage then stage.name elseif def then def.name else id
	local condition = 1
	local health = state and type(state.carHealth) == "table" and state.carHealth[id]
	if type(health) == "number" then
		condition = health
	end
	local live = Drive.myCar()
	if live and live:GetAttribute("CarId") == id then
		local hp = tonumber(live:GetAttribute("Health"))
		local max = tonumber(live:GetAttribute("MaxHealth"))
		if hp and max and max > 0 then
			condition = hp / max
		end
	end
	return name, Economy.capacity(id, levels), math.clamp(condition, 0, 1)
end

-- What to do about a job with more pieces than the car holds: Economy.roomAdvice (the next stage at Wrench Garage,
-- else the dealer's bigger cars), and a bigger car of yours waiting in your garages.
local function roomRemedy(offer: any): string
	local need = tonumber(offer.slots) or 0
	if isFoot(offer) then
		-- 5.0: on foot the room is your hands and your bag (6.6).
		local room = Transport.handsRoom(myKit(), myBag())
		return `You carry {room} light {if room == 1 then "piece" else "pieces"} ({KitShop.roomText(myKit(), myBag())}); this run has {math.max(need, tonumber(offer.pieces) or 0)}. A bigger bag at {Config.BagShop.Name} (by the spawn) carries more.`
	elseif isBike(offer) then
		-- 5.1: your bike, its bike gear and your bag (6.6: the bike's own bag and yours).
		return `Your {offer.carName or "bike"}'s bag and yours hold {offer.capacity or 0}; this run has {math.max(need, tonumber(offer.pieces) or 0)}. Bike gear from the BIKES counter at Dead End Motors (a basket, panniers) holds more.`
	end
	local head = `Your {offer.carName or "car"} holds {offer.capacity or 0} {if offer.capacity == 1 then "slot" else "slots"}; this job needs {need}.`
	if offer.vehicle then
		return head -- a company vehicle the job lends: nothing of yours to change
	end
	local id = carId()
	local advice = Economy.roomAdvice(id, Economy.stageOf(id, carLevels(id)), need)
	local owned: string? = nil
	if state and type(state.cars) == "table" then
		for _, def in Config.Cars do
			if def.id ~= id and state.cars[def.id] and Economy.capacity(def.id, carLevels(def.id)) >= need then
				owned = def.name
				break
			end
		end
	end
	local stage = string.find(advice, "Wrench Garage", 1, true) ~= nil -- the next stage would hold it
	if owned then
		return if stage then `{head} {advice} Or take your {owned} out at your garage.` else `{head} Take your {owned} out at your garage.`
	elseif stage then
		return `{head} {advice} Or take a bigger car out at your garage.`
	end
	return `{head} {advice}`
end

local function isSpecial(offer: any): boolean
	return offer.special == true or offer.jobType ~= nil
end

local function shown(list: { any }): { any }
	local out = {}
	for _, offer in list do
		if filter == "all" or (filter == "special") == isSpecial(offer) then
			table.insert(out, offer)
		end
	end
	return out
end

-- ── The window ─────────────────────────────────────────────────────────────

local renderList: () -> () = function() end

-- 5.8: AVAILABLE RUNS as the phone's square tabs (Ui.tabs, a column: the open one raised with a red bar down its left
-- edge; hover / gamepad focus brightens the others), each with its count on the right; 44 px tall, 52 apart as before.
local function buildFilters(side: any)
	local items: { Ui.TabItem } = {}
	for _, def in FILTERS do
		table.insert(items, { id = def.id, text = def.name })
	end
	local tabs = Ui.tabs(side, items, function(id: string)
		filter = id
		renderList()
	end, { selected = filter, vertical = true, height = 44, gap = 8, textSize = 13 })
	tabs.frame.Size = UDim2.new(1, -16, 0, #FILTERS * 52)
	tabs.frame.Position = UDim2.fromOffset(0, 40)
	for id, button in tabs.buttons do
		filterCounts[id] = text(button, "", UDim2.new(0, 30, 1, 0), {
			Position = UDim2.new(1, 0, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			Font = MONO,
			TextSize = 13,
			TextColor3 = K.secondary,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextWrapped = false,
			ZIndex = button.ZIndex + 1,
		})
	end
	filterTabs = tabs
end

-- The car card under the filters.
local function buildCarCard(side: any)
	local card = Ui.make("Frame", {
		Size = UDim2.new(1, -16, 0, 166),
		Position = UDim2.fromOffset(0, 40 + #FILTERS * 52 + 12),
		BackgroundColor3 = ROW,
		BorderSizePixel = 0,
	}, side)
	refs.carCard = card
	Ui.stroke(card, K.line, 1).Transparency = Ui.HAIRLINE -- 5.8: the slim card's hairline
	refs.carIcon = Ui.icon(card, "map_dealer", "🚐", UDim2.fromOffset(22, 20), {
		Position = UDim2.fromOffset(14, 12),
		ImageColor3 = K.secondary,
		TextScaled = true,
	})
	-- 5.0: on foot (no vehicle yet) the card shows a walker instead
	refs.footIcon = text(card, "🚶", UDim2.fromOffset(22, 20), { Position = UDim2.fromOffset(14, 12), TextScaled = true, Visible = false })
	refs.carCaps = Ui.caps(card, "Your vehicle", UDim2.new(1, -54, 0, 20), { Position = UDim2.fromOffset(44, 12), TextSize = 11 })
	refs.carName = text(card, "", UDim2.new(1, -28, 0, 22), {
		Position = UDim2.fromOffset(14, 42),
		Font = Theme.HeadingFont,
		TextSize = 16,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.carStats = text(card, "", UDim2.new(1, -28, 0, 18), { Position = UDim2.fromOffset(14, 66), TextColor3 = K.secondary, TextWrapped = false })
	refs.carHealth = text(card, "", UDim2.new(1, -28, 0, 18), { Position = UDim2.fromOffset(14, 86), TextColor3 = K.secondary, TextWrapped = false })
	refs.carNote = text(card, "Your vehicle sets your job capacity.", UDim2.new(1, -28, 0, 52), {
		Position = UDim2.fromOffset(14, 108),
		TextColor3 = K.secondary,
		TextSize = 13,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
end

local function build()
	if gui then
		return
	end
	local made = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryDispatch",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
		IgnoreGuiInset = false,
		Enabled = false,
	}, player:WaitForChild("PlayerGui"))
	gui = made
	-- The world dims behind the window; clicks on it do not reach the game (no shots while choosing a job).
	refs.backdrop = Ui.make("Frame", {
		Size = UDim2.new(1, 0, 1, 80),
		Position = UDim2.fromOffset(0, -80),
		BackgroundColor3 = Theme.Postage.veil,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Active = true,
	}, made)
	-- The window (Ui.window): the ZDC header with the board glyph, the title and the subtitle, the square ✕, the footer
	-- (ESC, the gamepad's B and the Roblox menu close it) with the car and the driver on the right.
	local window, content, chrome = Ui.window(made, "Dispatch board", "Delivery contracts · choose your next run", "📋", UDim2.fromOffset(MAX_W, MAX_H))
	chrome.onClose = function()
		DispatchUi.close()
	end
	refs.window = window
	refs.scale = Ui.make("UIScale", {}, window)
	refs.context = chrome.context
	-- The sidebar: AVAILABLE RUNS and your car.
	local side = Ui.make("Frame", {
		Size = UDim2.new(0, SIDEBAR, 1, 0),
		BackgroundColor3 = SIDE,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, content)
	Ui.make("Frame", { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, side)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingTop = UDim.new(0, 18) }, side)
	text(side, "AVAILABLE RUNS", UDim2.new(1, -16, 0, 16), {
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.secondary,
		TextWrapped = false,
	})
	buildFilters(side)
	buildCarCard(side)
	-- The tickets: a caption row and the scrolling list.
	local main = Ui.make("Frame", {
		Size = UDim2.new(1, -SIDEBAR, 1, 0),
		Position = UDim2.fromOffset(SIDEBAR, 0),
		BackgroundTransparency = 1,
	}, content)
	refs.caption = text(main, "", UDim2.new(0.4, 0, 0, 30), { Position = UDim2.fromOffset(24, 12), TextColor3 = K.secondary, TextWrapped = false })
	refs.capacity = text(main, "", UDim2.new(0.6, -200, 0, 30), {
		Position = UDim2.new(1, -176, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	-- 3.7: no refresh button: a quiet countdown to the next offers (tickCountdown).
	refs.countdown = text(main, "", UDim2.fromOffset(150, 30), {
		Position = UDim2.new(1, -24, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Font = MONO,
		TextSize = 12,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	local list = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -50),
		Position = UDim2.fromOffset(24, 50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = K.line,
		ScrollBarImageTransparency = 0.4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, main)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 16), PaddingRight = UDim.new(0, 20) }, list)
	Ui.list(list, true, GAP)
	refs.list = list
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			if not open or resizeQueued then
				return
			end
			resizeQueued = true
			task.delay(0.2, function()
				resizeQueued = false
				if open then
					DispatchUi.refresh()
				end
			end)
		end)
	end
end

-- The window's size at scale 1: as big as the design, smaller when the screen is.
local function fit()
	local scale = Ui.screenScale()
	local screen = Ui.screenSize()
	if Ui.touchLayout() then
		-- A phone: the window fills the screen at the biggest scale its smallest size fits (bigger text and buttons
		-- than the shared phone scale would give; never above 1).
		scale = math.clamp(math.min(screen.X / (MIN_W + 48), screen.Y / (MIN_H + 36)), scale, math.max(scale, 1))
	end
	refs.scale.Scale = scale
	width = math.floor(math.clamp(screen.X / scale - 48, MIN_W, MAX_W))
	height = math.floor(math.clamp(screen.Y / scale - 36, MIN_H, MAX_H))
	refs.window.Size = UDim2.fromOffset(width, height)
	-- A short window (a phone) drops the car card: the capacity line and the footer still name the car.
	refs.carCard.Visible = height - Ui.WindowHeader - Ui.WindowFooter >= 18 + 40 + #FILTERS * 52 + 12 + 166
end

-- The car card, the capacity, the counts and the footer.
local function refreshChrome()
	local name, slots, condition = myCar()
	local percent = math.floor(condition * 100 + 0.5)
	refs.carName.Text = name
	local walking = onFoot()
	local onBike = riding() -- 5.1
	refs.carIcon.Visible = not walking and not onBike
	refs.footIcon.Visible = walking or onBike
	refs.footIcon.Text = if onBike then "🚲" else "🚶"
	refs.carCaps.Text = if walking or onBike then "YOUR TRANSPORT" else "YOUR VEHICLE"
	-- 4.6: a Roof Rack (gear) takes one more light piece on the roof.
	local mine = carId()
	local rack = Economy.installedGear(if state and type(state.carGear) == "table" then state.carGear else nil, mine).roofrack == true and Economy.gearFits(mine, "roofrack")
	local level = myLevel()
	if walking then
		-- 5.0: on foot: your room (hands and bag), your pace, when the first vehicle comes.
		local room = KitShop.roomText(myKit(), myBag())
		local speed = Transport.speedMult(myKit())
		refs.carStats.Text = `🛍 {room}`
		refs.carHealth.Text = if speed > 1.001 then `👟 pace ×{string.format("%.2g", speed)} · light cargo` else "Light cargo only"
		refs.carHealth.TextColor3 = K.secondary
		refs.carNote.Text = `No vehicle yet: the {vehicleShort()}. A bigger bag carries more ({Config.BagShop.Name}).`
		refs.capacity.Text = `YOUR ROOM · {room}`
		refs.context.Text = `ON FOOT · {room}  ·  {Levels.rank(level)} / level {level}`
	elseif onBike then
		-- 5.1: on your bike: what it holds (its room, its bike gear, your bag), light cargo; the car jobs need your car.
		refs.carStats.Text = `📦 {slots} light {if slots == 1 then "piece" else "pieces"} · bike's bag + gear + your bag`
		refs.carHealth.Text = "Light cargo only · BIKE runs"
		refs.carHealth.TextColor3 = K.secondary
		refs.carNote.Text = "Car jobs need your car: CALL CAR on your phone."
		refs.capacity.Text = `YOUR BIKE · {slots} LIGHT`
		refs.context.Text = `{string.upper(name)} · {slots} LIGHT  ·  {Levels.rank(level)} / level {level}`
	else
		refs.carStats.Text = `📦 {slots} cargo {if slots == 1 then "slot" else "slots"}{if rack then " + 1 on the roof (light)" else ""}`
		refs.carHealth.Text = `🔧 {percent}% condition`
		refs.carHealth.TextColor3 = if condition < 0.35 then K.red else K.secondary
		refs.carNote.Text = if condition < 0.5 then "Your vehicle sets your job capacity. A repair bay fixes it." else "Your vehicle sets your job capacity."
		refs.capacity.Text = `YOUR CAPACITY · {slots} {if slots == 1 then "SLOT" else "SLOTS"}`
		refs.context.Text = `{string.upper(name)} · {slots} CARGO {if slots == 1 then "SLOT" else "SLOTS"}  ·  {Levels.rank(level)} / level {level}`
	end
	local list: { any } = if offers == nil then {} else offers
	local special = 0
	for _, offer in list do
		if isSpecial(offer) then
			special += 1
		end
	end
	local counts = { all = #list, delivery = #list - special, special = special }
	local tabs = filterTabs
	if tabs and tabs.selected ~= filter then
		tabs.select(filter)
	end
	for id, count in filterCounts do
		count.Text = if offers or job then tostring(counts[id] or 0) else "–"
		count.TextColor3 = if filter == id then K.text else K.secondary
	end
	refs.countdown.Visible = offers ~= nil
end

-- ── The tickets ────────────────────────────────────────────────────────────

-- A one-line message in the list (waiting, nothing on the board). 6.12.8: under YOUR RUN and NEXT UP (no clear).
local function message(value: string)
	text(refs.list, value, UDim2.new(1, 0, 0, 60), {
		TextColor3 = K.secondary,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
	})
end

-- The spine: the row's number over the cargo's icon (white, upright), a fine line on its right.
local function spine(card: any, offer: any, number: number)
	local kind = if type(offer.itemKind) == "string" then offer.itemKind else "crate"
	local art = Icons.cargo(kind)
	if type(offer.piece) == "string" then
		for _, business in Config.Jobs.Businesses do
			if business.piece == offer.piece and business.kind == kind then
				art = Icons.cargo(business.look) or art
				break
			end
		end
	end
	text(card, string.format("%02d", number), UDim2.fromOffset(SPINE, 16), {
		Position = UDim2.fromOffset(0, 16),
		Font = MONO,
		TextSize = 13,
		TextColor3 = K.secondary,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
	local emoji = if offer.timed then "⚡" else (KINDS[kind] or KINDS.crate).icon
	Ui.icon(card, art, emoji, UDim2.fromOffset(28, 28), {
		Position = UDim2.fromOffset(SPINE / 2, 44),
		AnchorPoint = Vector2.new(0.5, 0),
		ImageColor3 = K.text,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
	Ui.make("Frame", { Size = UDim2.new(0, 1, 1, -24), Position = UDim2.fromOffset(SPINE, 12), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, card)
end

-- The risk label and the twists, in a row at the top of the row's body (clipped to it: on a narrow board the last
-- tags are cut off rather than run into the payout column).
local function dangerRow(body: any, offer: any)
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 14), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2 }, body)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local stars = tonumber(offer.stars) or 1
	if isFoot(offer) then
		-- 5.0: an on-foot run: no danger level, the walker's chip.
		chip(row, "🚶 ON FOOT", K.text, 1).TextColor3 = K.text
	elseif isBike(offer) then
		chip(row, "🚲 BIKE", K.text, 1).TextColor3 = K.text -- 5.1
	else
		text(row, `{string.upper(tostring(offer.tierName or "Job"))} · {string.rep("★", stars)}`, UDim2.fromOffset(0, 20), {
			AutomaticSize = Enum.AutomaticSize.X,
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = if stars >= 3 then K.red else K.secondary,
			TextWrapped = false,
			LayoutOrder = 1,
		})
	end
	-- 4.7: the trade-off of an ordinary offer (its role).
	if type(offer.roleName) == "string" then
		chip(row, `{offer.roleIcon or ""} {offer.roleName}`, if offer.role == "risky" then K.red else K.rule, 2)
	end
	if offer.modifier then
		chip(row, `⚠ {offer.modifier.name}`, K.red, 3)
	end
	if isSpecial(offer) then
		chip(row, "SPECIAL", K.rule, 4)
	end
	if offer.timed then
		chip(row, "⏱ RUSH CLOCK", K.rule, 5)
	end
	-- 5.3: the evening peak of the pizzas, burgers and noodles (Config.Jobs.Businesses peak), a newspaper round's doors.
	local peak = tonumber(offer.peak)
	if peak and peak > 1 then
		chip(row, `🌆 EVENING +{math.floor((peak - 1) * 100 + 0.5)}%`, K.rule, 5)
	end
	if offer.round == true then
		chip(row, `📰 {math.max(1, (tonumber(offer.stops) or 2) - 1)} DOORS`, K.rule, 2)
	end
	local boost = tonumber(offer.banditBoost)
	if boost and boost > 1 then
		chip(row, "🎯 BANDITS WANT IT", K.red, 6)
	end
	-- 4.8: a multi-drop delivery (its customers) and the cargo's rules (the RULES line says what they ask).
	local drops = tonumber(offer.drops)
	if drops and drops > 1 then
		chip(row, `📍 {drops} DROPS`, K.rule, 2)
	end
	if type(offer.rules) == "table" then
		local icons = { fragile = "🥚 FRAGILE", food = "🍕 FOOD", heavy = "🏋 HEAVY", cash = "💰 CASH", people = "👥 PASSENGERS" }
		for index, rule in offer.rules do
			local name = icons[rule]
			if name and rule ~= "cash" then -- (cash: BANDITS WANT IT says it)
				chip(row, name, if rule == "fragile" then K.red else K.rule, 6 + index)
			end
		end
	end
end

-- One briefing line: a small caps label (ROUTE, CARGO ...) and its value, wrapped to `w` (or one line cut short when
-- `wrap` is false). Returns its height.
local function brief(body: any, label: string, value: string, y: number, w: number, wrap: boolean, props: { [string]: any }?): number
	local h = if wrap then math.max(18, textHeight(value, 14, Theme.Font, w - LABEL_W)) else 18
	Ui.caps(body, label, UDim2.fromOffset(LABEL_W - 8, 18), {
		Position = UDim2.fromOffset(0, y),
		TextSize = 11,
		TextColor3 = if label == "Risk" then K.red else K.secondary,
		ZIndex = 2,
	})
	local line = text(body, value, UDim2.new(1, -LABEL_W, 0, h), {
		Position = UDim2.fromOffset(LABEL_W, y),
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = wrap,
		TextTruncate = if wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		RichText = true,
		ZIndex = 2,
	})
	if props then
		for key, v in props do
			line[key] = v
		end
	end
	return h + 4
end

-- The briefing under the title (route, cargo, deadline, risk, the special job); returns where the next thing goes.
local function details(body: any, offer: any, w: number): number
	local y = 70
	-- 4.7, WHY: the trade-off of this offer (the board's choice).
	if type(offer.roleWhy) == "string" then
		y += brief(body, "Why", offer.roleWhy, y, w, true, { TextColor3 = K.secondary })
	end
	-- ROUTE: the first stop → the last address, its district; the stops and the distance.
	local stops = tonumber(offer.stops) or 1
	local route = string.gsub(`{offer.first or "Pick up"}  →  {offer.address or "?"}, {offer.district or ""}`, "[&<>]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;" })
	local legs = `{if stops > 1 then `{stops} stops{SEPARATOR}` else ""}{tonumber(offer.distance) or 0} m`
	y += brief(body, "Route", `{route}{SEPARATOR}{legs}`, y, w, false)
	-- CARGO: the pieces and how they move, the cargo slots, a company vehicle the job lends.
	local slots = tonumber(offer.slots) or 0
	local count = tonumber(offer.pieces)
	local kind = KINDS[offer.itemKind or "crate"] or { icon = "📦", one = tostring(offer.itemKind), many = `{offer.itemKind}s` }
	local words: { string } = {}
	if count and count > 0 then
		local name = if count == 1 then (offer.piece or kind.one) else (offer.piecesName or kind.many)
		local how = HANDLING[offer.handling or ""]
		table.insert(words, `{kind.icon} {count} {name}` .. (if how then ` · {how}` else ""))
	end
	if isFoot(offer) then
		-- 5.0: on foot it is your hands and your bag, not cargo slots.
		local room = Transport.handsRoom(myKit(), myBag())
		local pieces = count or slots
		table.insert(words, if pieces <= room then `fits your hands ({pieces} / {room})` else `{pieces} pieces: you carry {room}`)
	elseif isBike(offer) then
		-- 5.1: your bike's room with its gear and your bag (the server's capacity).
		local room = tonumber(offer.capacity) or 0
		local pieces = count or slots
		table.insert(words, if offer.needsBike then "light pieces on a bike" elseif pieces <= room then `fits your bike ({pieces} / {room})` else `{pieces} pieces: your bike holds {room}`)
	else
		table.insert(words, if slots > 0 then `{slots} cargo {if slots == 1 then "slot" else "slots"}` else "no cargo slots")
	end
	if offer.vehicle then
		table.insert(words, `🚚 company vehicle: {offer.vehicle}`)
	end
	y += brief(body, "Cargo", table.concat(words, SEPARATOR), y, w, false)
	-- DEADLINE: the time for the run (fixed on a rush clock).
	local deadline = `⏱ {Ui.clock(tonumber(offer.time) or 0)}{if offer.timed then " · fixed, the rush clock does not wait" else ""}`
	y += brief(body, "Deadline", deadline, y, w, true, { Font = MONO })
	-- RISK: the modifier's description (red label; the words say what it is).
	if offer.modifier and offer.modifier.description then
		y += brief(body, "Risk", `{offer.modifier.name}: {offer.modifier.description}`, y, w, true, { TextColor3 = K.text })
	end
	if offer.jobType and offer.jobType.description then
		y += brief(body, "Job", offer.jobType.description, y, w, true, { TextColor3 = K.secondary })
	end
	-- 4.8: the cargo's rules (fragile, food, heavy, cash, passengers) and a multi-drop delivery's customers.
	if type(offer.rulesText) == "string" then
		y += brief(body, "Rules", offer.rulesText, y, w, true, { TextColor3 = K.text })
	end
	local drops = tonumber(offer.drops)
	if drops and drops > 1 then
		y += brief(body, "Drops", `{drops} customers, one after the other: every piece is labelled for its customer, the wrong one is refused.`, y, w, true, { TextColor3 = K.secondary })
	end
	-- 4.0: the server's tip (a hand trolley helps with 4+ pieces).
	if type(offer.tip) == "string" then
		y += brief(body, "Tip", offer.tip, y, w, true, { TextColor3 = K.secondary })
	end
	return y
end

-- The remedy under a locked row's briefing (a note with a red rule on its left); returns where the next thing goes
-- and the note.
local function remedy(body: any, value: string, y: number, w: number): (number, any)
	local h = textHeight(value, 14, Theme.Font, w - 28) + 16
	local box = text(body, value, UDim2.new(1, 0, 0, h), {
		Position = UDim2.fromOffset(0, y + 6),
		BackgroundTransparency = 0,
		BackgroundColor3 = NOTE,
		TextColor3 = K.text,
		ZIndex = 2,
	})
	Ui.make("Frame", { Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = K.red, BorderSizePixel = 0, ZIndex = 3 }, box)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 12) }, box)
	return y + 6 + h, box
end

-- The payout column: PAYOUT, the pay, night pay, and the action (ACCEPT JOB →, or the lock's reason). A locked button
-- flashes the row's remedy note (`note`): the HUD's toasts sit under this board's ScreenGui and its veil.
local function payStub(stub: any, offer: any, lockLevel: number?, why: string?, note: any?, lockLabel: string?)
	local function flash()
		if note then
			note.BackgroundColor3 = FLASH
			TweenService:Create(note, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { BackgroundColor3 = NOTE }):Play()
		end
	end
	local touch = Ui.touchLayout()
	-- 5.8: the payout behind a thin divider (the phone's "| $ 1 240").
	Ui.make("Frame", { Name = "Divider", Size = UDim2.new(0, 1, 1, -24), Position = UDim2.fromOffset(0, 12), BackgroundColor3 = K.rule, BorderSizePixel = 0, ZIndex = 2 }, stub)
	Ui.caps(stub, "Payout", UDim2.new(1, -28, 0, 14), {
		Position = UDim2.new(0.5, 0, 0.5, -66),
		AnchorPoint = Vector2.new(0.5, 0),
		TextSize = 11,
		ZIndex = 2,
	})
	text(stub, Ui.money(tonumber(offer.pay) or 0), UDim2.new(1, -28, 0, 30), {
		Position = UDim2.new(0.5, 0, 0.5, -50),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.HeadingFont,
		TextSize = 24,
		TextWrapped = false,
		ZIndex = 2,
	})
	local nightRate = tonumber(offer.nightPay)
	if nightRate and nightRate > 1 then
		-- It is night: finished now, the job pays this many times more (Config.DayNight.NightPay).
		text(stub, string.format("🌙 NIGHT ×%.1f", nightRate), UDim2.new(1, -28, 0, 16), {
			Position = UDim2.new(0.5, 0, 0.5, -18),
			AnchorPoint = Vector2.new(0.5, 0),
			Font = Theme.HeadingFont,
			TextSize = 11,
			TextColor3 = K.secondary,
			ZIndex = 2,
		})
	end
	local size = UDim2.new(1, -28, 0, if touch then 48 else 44)
	local at = UDim2.new(0.5, 0, 0.5, 4)
	if lockLevel then
		action(stub, `🔒 LEVEL {lockLevel}`, size, at, nil, function()
			flash()
			local what = if offer.jobType then `The {offer.jobType.name}` else `{offer.tierName} jobs`
			Hud.toast(`{what} need{if offer.jobType then "s" else ""} driver level {lockLevel} ({Levels.rank(lockLevel)}). Deliveries give XP.`)
		end)
	elseif job ~= nil and offer.addOrder == true then
		-- 5.2: on a run that takes more orders: + ADD where it fits (the board stays open for another).
		local add = action(stub, "+ ADD", size, at, K.red, function() -- 5.8: the red primary action
			Net.get("AcceptJob"):FireServer(offer.index)
			local list = offers
			local spot = if list then table.find(list, offer) else nil
			if list and spot then
				table.remove(list, spot)
			end
			renderList()
		end)
		refs.firstAccept = refs.firstAccept or add
	elseif job ~= nil and offer.queue == true then
		-- 6.12.8: it can't join the run now (full, another transport, a ★★★ car job, waiting for your car): NEXT UP.
		local queue = action(stub, "+ QUEUE", size, at, K.red, function()
			Net.get("JobQueue"):FireServer("queue", offer.index)
			local list = offers
			local spot = if list then table.find(list, offer) else nil
			if list and spot then
				table.remove(list, spot)
			end
			renderList()
		end)
		refs.firstAccept = refs.firstAccept or queue
	elseif why then
		-- 4.0: a Freight Run is locked by pallets (the server's lockButton: "NEEDS N PALLETS"). 4.7: a tier without its
		-- licence: "LICENCE 3 / 5".
		local licence = if offer.lockReason == "licence" and type(offer.licence) == "table" then offer.licence else nil
		local label = if lockLabel then lockLabel
			elseif licence then `🪪 LICENCE {licence.have or 0} / {licence.need or 0}`
			elseif type(offer.lockButton) == "string" then offer.lockButton
			else `📦 NEEDS {offer.slots} SLOTS`
		action(stub, label, size, at, nil, function()
			flash()
			Hud.toast(why)
		end)
	elseif job ~= nil then
		-- 5.2 / 6.12.8: on a run, neither + ADD nor + QUEUE: why (the queue is full, ORDERS FULL, a special …).
		local label = if type(offer.queueButton) == "string" then offer.queueButton elseif type(offer.orderButton) == "string" then offer.orderButton else "FINISH YOUR RUN"
		local words = if type(offer.queueText) == "string" then offer.queueText elseif type(offer.orderText) == "string" then offer.orderText else "Finish your current delivery first."
		action(stub, label, size, at, nil, function()
			flash()
			Hud.toast(words)
		end)
	else
		local accept = action(stub, "ACCEPT JOB", size, at, K.red, function() -- 5.8: the red primary action
			Net.get("AcceptJob"):FireServer(offer.index)
			-- It leaves the board on the server once started: not shown again before the board comes back.
			local list = offers
			local spot = if list then table.find(list, offer) else nil
			if list and spot then
				table.remove(list, spot)
			end
			DispatchUi.close()
		end)
		refs.firstAccept = refs.firstAccept or accept -- 4.2: the gamepad's selection starts on the first one
	end
end

-- The list's width at scale 1 (the window minus the sidebar, the margins and the scroll bar).
local function listWidth(): number
	return width - SIDEBAR - 24 - 20 - 4
end

-- 4.7: what a missing licence needs, in words (the server's licence info).
local function licenceNote(licence: any): string
	return `{licence.stars} jobs need the {licence.stars} LICENCE: {licence.need} jobs rated ★★ or better at {licence.atStars} or harder ({licence.have} / {licence.need} done). Drive them well: on time, the cargo whole, no wreck.`
end

local function offerTicket(offer: any, number: number, order: number?)
	local w = listWidth()
	local bodyW = w - SPINE - STUB - 30
	-- Above your driver level: offered, but locked (the server refuses it too). 4.7: or without the tier's licence.
	-- Else too many pieces for the car.
	local licence = if offer.locked == true and offer.lockReason == "licence" and type(offer.licence) == "table" then offer.licence else nil
	local lockLevel = if offer.locked == true and not licence then (tonumber(offer.level) or myLevel() + 1) else nil
	-- 5.0: a job that needs your own vehicle while you have none (a job that lends a company vehicle does not).
	local noVehicle = onFoot() and not isFoot(offer) and not isBike(offer) and offer.vehicle == nil -- (5.1: a bike run has its own lock)
	local why = if licence then licenceNote(licence)
		elseif lockLevel == nil and noVehicle then vehicleNote()
		elseif lockLevel == nil and offer.tooBig == true then (if type(offer.lockText) == "string" then offer.lockText else roomRemedy(offer))
		else nil
	local note = if lockLevel then `Unlocks at LEVEL {lockLevel} ({Levels.rank(lockLevel)}). Deliveries give XP.{if noVehicle then ` It needs a vehicle too: the {vehicleShort()}.` else ""}` else why
	-- The slot in the list gets its height once the body is built (the row fills it).
	local slot = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 140), BackgroundTransparency = 1, LayoutOrder = order or number }, refs.list)
	local card: any, body: any, stub: any = Ui.ticket(slot, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), nil, STUB)
	local holder = card.Parent
	local waits = job ~= nil and offer.queue == true and lockLevel == nil -- 6.12.8: + QUEUE: it waits for your car or bike
	card.BackgroundColor3 = if note and not waits then LOCKED_ROW else ROW
	body.ZIndex = 2
	stub.ZIndex = 2
	spine(card, offer, number)
	local column = Ui.make("Frame", {
		Size = UDim2.new(1, -(SPINE + 30), 1, 0),
		Position = UDim2.fromOffset(SPINE + 16, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, body)
	-- 6.12.11: the business's picture across the top of the column (about 2.4 : 1, at most 150 px tall), or while not
	-- uploaded a slim banner; the briefing goes under it (`inner`, the column below it).
	local thumb = JobThumbUi.strip(column, offer, 0, math.clamp(math.floor(bodyW / JobThumbUi.RATIO), 56, 150))
	local shift = 0
	if thumb then
		thumb.Position = UDim2.fromOffset(0, 12)
		shift = thumb.Size.Y.Offset + 6
	end
	local inner = if shift > 0
		then Ui.make("Frame", { Name = "Inner", Size = UDim2.new(1, 0, 1, -shift), Position = UDim2.fromOffset(0, shift), BackgroundTransparency = 1, ZIndex = 2 }, column)
		else column
	dangerRow(inner, offer)
	local title = if offer.jobType then `{offer.jobType.name}: {offer.cargo}` else `{offer.cargo} for {offer.customer}`
	text(inner, string.upper(title), UDim2.new(1, 0, 0, 26), { -- 5.8: in caps, like the phone's board cards
		Position = UDim2.fromOffset(0, 38),
		Font = Theme.HeadingFont,
		TextSize = 18,
		TextColor3 = if note and not waits then K.secondary else K.text,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
	})
	local after = details(inner, offer, bodyW)
	local noteBox: any = nil
	if note then
		Ui.caps(inner, if waits then "Waits in NEXT UP" else "Locked", UDim2.fromOffset(if waits then 140 else 80, 14), {
			Position = UDim2.new(1, 0, 0, 17),
			AnchorPoint = Vector2.new(1, 0),
			TextSize = 11,
			TextColor3 = K.red,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 2,
		})
		after, noteBox = remedy(inner, note, after, bodyW)
	end
	local h = math.max(140, after + 16 + shift)
	slot.Size = UDim2.new(1, 0, 0, h)
	payStub(stub, offer, lockLevel, why, noteBox, if lockLevel == nil and noVehicle and not licence then "🚐 NEEDS A VEHICLE" else nil)
	Ui.tactile(holder)
end

-- 4.7: the header of a danger level's group: its stars and name, what to do (pick one, or what it needs), and REROLL
-- (Net "RerollTier": new ordinary offers of that tier for its fee, once until the board refreshes).
local function tierHeader(index: number, info: any, order: number)
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = order }, refs.list)
	local stars = tonumber(info.stars) or index
	marker(row) -- 5.8
	text(row, `{string.rep("★", stars)}  {string.upper(tostring(info.name or ""))}`, UDim2.new(1, -194, 0, 18), {
		Position = UDim2.fromOffset(18, 4),
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextColor3 = if stars >= 3 then K.red else K.text,
		TextWrapped = false,
	})
	local licence = if type(info.licence) == "table" then info.licence else nil
	local level = tonumber(info.level) or 1
	local onBike = riding() and boardInfo ~= nil and boardInfo.ownsCar == true -- 5.1: on your bike, a car at home
	local walking = onFoot() or onBike -- 5.0: no vehicle yet: the car tiers need one
	local sub = if onBike then `NEEDS YOUR CAR · CALL CAR on your phone{if myLevel() < level then ` · LEVEL {level}` else ""}`
		elseif walking and myLevel() < level then `LOCKED · LEVEL {level} · needs a vehicle ({vehicleShort()})`
		elseif walking then `NEEDS A VEHICLE · {vehicleShort()}, {if firstVehicle() and (firstVehicle() :: Config.CarDef).id == Config.VanQuest.Car then Config.VanQuest.Place else "Dead End Motors"}`
		elseif info.open == true then "Pick one: each run has its own trade-off"
		elseif myLevel() < level then `LOCKED · LEVEL {level}{if licence then ` and the {licence.stars} licence` else ""}`
		elseif licence then `LOCKED · LICENCE {licence.have or 0} / {licence.need or 0} · jobs rated ★★+ at {licence.atStars}`
		else "LOCKED"
	text(row, sub, UDim2.new(1, -194, 0, 16), {
		Position = UDim2.fromOffset(18, 22),
		TextSize = 12,
		TextColor3 = if info.open == true and not walking then K.secondary else K.red,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, row)
	if info.open ~= true or walking then
		return
	end
	local fee = tonumber(info.fee) or 0
	local size, at = UDim2.fromOffset(160, 30), UDim2.new(1, -82, 0, 4)
	if info.rerolled == true then
		action(row, "REROLLED", size, at, nil, function()
			Hud.toast("Rerolled already: new jobs come with the next board.")
		end)
		return
	end
	local button: any
	button = action(row, `↻ REROLL {Ui.money(fee)}`, size, at, C.blue, function()
		local money = if state and type(state.money) == "number" then state.money else math.huge
		if money < fee then
			button.Text = "NOT ENOUGH MONEY"
			return
		end
		button.Text = "REROLLING..."
		Net.get("RerollTier"):FireServer(index)
	end)
end

-- 5.0: the header of the ON FOOT section: what these runs are, and your room on the right. 5.3 review: `note`, why
-- there is no run (the board's footNote: the shops near you are shut), in red when there is none.
local function footHeader(count: number, order: number, note: string?)
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = order }, refs.list)
	marker(row) -- 5.8
	text(row, "🚶  ON FOOT", UDim2.new(1, -234, 0, 18), {
		Position = UDim2.fromOffset(18, 4),
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextWrapped = false,
	})
	local none = count == 0 and note ~= nil
	text(row, if none and note then note else `{count} light {if count == 1 then "run" else "runs"} near you · no vehicle needed · quick money`, UDim2.new(1, -234, 0, 16), {
		Position = UDim2.fromOffset(18, 22),
		TextSize = 12,
		TextColor3 = if none then K.red else K.secondary,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local room = text(row, KitShop.roomText(myKit(), myBag()), UDim2.fromOffset(0, 22), {
		Position = UDim2.new(1, -4, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.text,
		TextWrapped = false,
	})
	Ui.stroke(room, K.rule, 1)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, room)
	Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, row)
end

-- 5.1: the header of the BIKE section: what these runs are, and your bike's room on the right (or what is missing).
local function bikeHeader(count: number, order: number)
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = order }, refs.list)
	marker(row) -- 5.8
	text(row, "🚲  BIKE", UDim2.new(1, -234, 0, 18), {
		Position = UDim2.fromOffset(18, 4),
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextWrapped = false,
	})
	local bike = if boardInfo and type(boardInfo.bike) == "table" then boardInfo.bike else nil
	local sub = if bike == nil then `NEEDS A BIKE · Dead End Motors' BIKES counter, level {Config.Jobs.Bike.Level}`
		elseif bike.riding ~= true then "Your car is out: MY BIKE on your phone gets you on the bike"
		else `{count} light {if count == 1 then "run" else "runs"} · longer, better paid · light cargo only`
	text(row, sub, UDim2.new(1, -234, 0, 16), {
		Position = UDim2.fromOffset(18, 22),
		TextSize = 12,
		TextColor3 = if bike and bike.riding == true then K.secondary else K.red,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local room = text(row, if bike then `{string.upper(tostring(bike.name))} · {tonumber(bike.room) or 0} LIGHT` else "NO BIKE", UDim2.fromOffset(0, 22), {
		Position = UDim2.new(1, -4, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Font = Theme.HeadingFont,
		TextSize = 11,
		TextColor3 = K.text,
		TextWrapped = false,
	})
	Ui.stroke(room, K.rule, 1)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, room)
	Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, row)
end

-- 6.12.8, YOUR RUN (any run: J's board shows the offers during every run now), the same summary as the phone's BOARD
-- (shared/JobQueue.luau runLines): every open order in one line (what, from → to, its pay and its clock, ticked by
-- tickCountdown), the run's pay, the next stop; DETAILS (the phone's ORDERS: DispatchUi.onDetails) and GIVE UP THIS
-- DELIVERY (CancelJob).
local function runTicket()
	local lines, total, nextStop = JobQueue.runLines(job)
	local count = #lines
	local slot = Ui.make("Frame", { Name = "YourRun", Size = UDim2.new(1, 0, 0, math.max(132, 64 + count * 24 + (if nextStop then 24 else 0))), BackgroundTransparency = 1, LayoutOrder = -30 }, refs.list)
	local card, body, stub = Ui.ticket(slot, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), nil, STUB + 60)
	Ui.selectRow(card, true) -- the run you are on: the selected look (the red rule)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingTop = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, body)
	Ui.caps(body, `Your run · {count} {if count == 1 then "order" else "orders"} · {Ui.money(total)}`, UDim2.new(1, 0, 0, 16), { TextSize = 11, TextColor3 = K.red })
	refs.runClocks = {}
	for index, line in lines do
		local y = 24 + (index - 1) * 24
		local route = if line.route ~= "" then ` · {line.route}` else ""
		text(body, `{line.icon}  {line.title}{route}`, UDim2.new(1, -150, 0, 22), {
			Position = UDim2.fromOffset(0, y),
			Font = if line.focused then Theme.HeadingFont else Theme.Font,
			TextSize = 14,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local prefix = `{Ui.money(line.pay)} · `
		local clock = text(body, Ui.money(line.pay), UDim2.fromOffset(144, 22), {
			Position = UDim2.new(1, 0, 0, y),
			AnchorPoint = Vector2.new(1, 0),
			Font = Theme.HeadingFont,
			TextSize = 14,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		if line.endsAt then
			table.insert(refs.runClocks, { label = clock, endsAt = line.endsAt, prefix = prefix })
		end
	end
	if nextStop then
		text(body, `Next stop: {nextStop}`, UDim2.new(1, 0, 0, 22), {
			Position = UDim2.fromOffset(0, 24 + count * 24),
			TextSize = 13,
			TextColor3 = K.secondary,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
	end
	action(stub, "DETAILS", UDim2.new(1, -28, 0, 40), UDim2.new(0.5, 0, 0.5, -46), K.red, function()
		local details = DispatchUi.onDetails
		if details then
			details()
		end
	end)
	action(stub, "GIVE UP THIS DELIVERY", UDim2.new(1, -28, 0, 40), UDim2.new(0.5, 0, 0.5, 4), C.red, function()
		Net.get("CancelJob"):FireServer()
		DispatchUi.close()
	end)
end

-- 6.12.8, NEXT UP (the JobQueue remote's state, server/JobQueue.luau): the queued jobs in order, each with what, from →
-- to, its pay and ✕ (JobQueue "drop"); the next one says why it waits.
local function nextUpRows()
	local entries = if type(queueState) == "table" and type(queueState.list) == "table" then queueState.list else {}
	if #entries == 0 then
		return
	end
	local paused = queueState.paused == true
	local head = Ui.make("Frame", { Name = "NextUpHeader", Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = -21 }, refs.list)
	marker(head)
	text(head, `▶  NEXT UP · {#entries} / {tonumber(queueState.max) or JobQueue.max()}`, UDim2.new(1, -324, 0, 18), {
		Position = UDim2.fromOffset(18, 4),
		Font = Theme.HeadingFont,
		TextSize = 13,
		TextWrapped = false,
	})
	text(head, if paused then JobQueue.pausedLine(queueState.pausedWhy) else "They start on their own: when you have no job, or they join your run when it has room.", UDim2.new(1, -324, 0, 16), {
		Position = UDim2.fromOffset(18, 22),
		Font = if paused then Theme.HeadingFont else Theme.Font,
		TextSize = 12,
		TextColor3 = if paused then K.red else K.secondary,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	-- review: PAUSE / RESUME and CLEAR ALL (the phone's NEXT UP has the same).
	local toggle = action(head, if paused then "▶ RESUME" else "⏸ PAUSE", UDim2.fromOffset(140, 32), UDim2.new(1, -230, 0, 4), if paused then K.red else nil, function()
		Net.get("JobQueue"):FireServer(if paused then "resume" else "pause")
	end)
	toggle.Name = if paused then "Resume" else "Pause"
	local clear = action(head, "CLEAR ALL", UDim2.fromOffset(140, 32), UDim2.new(1, -74, 0, 4), nil, function()
		Net.get("JobQueue"):FireServer("clear")
	end)
	clear.Name = "ClearAll"
	Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1), BackgroundColor3 = K.rule, BorderSizePixel = 0 }, head)
	for index, entry in entries do
		if type(entry) ~= "table" then
			continue
		end
		local starting = entry.starting == true and not paused
		local why = if starting then "starts in a few seconds (PAUSE to wait)" elseif type(entry.why) == "string" and entry.why ~= "" then entry.why else nil
		local row = Ui.make("Frame", { Name = "NextRow", Size = UDim2.new(1, 0, 0, if why then 66 else 48), BackgroundColor3 = ROW, BorderSizePixel = 0, LayoutOrder = -20 + index }, refs.list)
		Ui.stroke(row, K.rule, 1)
		-- 6.12.11: a small square of the business's picture on the left (once uploaded; else the row as before).
		local left = if JobThumbUi.square(row, entry, 38, { Position = UDim2.fromOffset(10, 5) }) then 58 else 14
		text(row, `{index}  {JobQueue.icon(entry.mode, entry.stars)}  {string.upper(tostring(entry.title or entry.cargo or "Job"))}`, UDim2.new(1, -(186 + left), 0, 20), {
			Position = UDim2.fromOffset(left, 5),
			Font = Theme.HeadingFont,
			TextSize = 14,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		text(row, JobQueue.route(entry.from, entry.to), UDim2.new(1, -(186 + left), 0, 18), {
			Position = UDim2.fromOffset(left, 25),
			TextSize = 12,
			TextColor3 = K.secondary,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		if why then
			text(row, if starting then `▶ {why}` else `⏸ Waits: {why}`, UDim2.new(1, -(186 + left), 0, 18), {
				Position = UDim2.fromOffset(left, 43),
				Font = Theme.HeadingFont,
				TextSize = 12,
				TextColor3 = if starting then K.text else K.red,
				TextWrapped = false,
				TextTruncate = Enum.TextTruncate.AtEnd,
			})
		end
		text(row, Ui.money(tonumber(entry.pay) or 0), UDim2.fromOffset(110, 24), {
			Position = UDim2.new(1, -70, 0, 6),
			AnchorPoint = Vector2.new(1, 0),
			Font = Theme.HeadingFont,
			TextSize = 18,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		local id = tonumber(entry.id)
		action(row, "✕", UDim2.fromOffset(44, 36), UDim2.new(1, -32, 0, 6), nil, function()
			Net.get("JobQueue"):FireServer("drop", id)
		end)
	end
end

-- 6.12.8, ADD ALL · $total (the server's plan in the board's info: into the run up to its room and max, the rest into
-- NEXT UP) and what it will do.
local function addAllRow()
	local plan = if boardInfo and type(boardInfo.addAll) == "table" then boardInfo.addAll else nil
	local count = if plan then tonumber(plan.count) or 0 else 0
	if not plan or count <= 0 then
		return
	end
	local row = Ui.make("Frame", { Name = "AddAllRow", Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, LayoutOrder = -5 }, refs.list)
	local parts: { string } = {}
	local started, added, queued = tonumber(plan.started) or 0, tonumber(plan.added) or 0, tonumber(plan.queued) or 0
	if started > 0 then
		table.insert(parts, "the first one starts")
	end
	if added > 0 then
		table.insert(parts, `{added} {if added == 1 then "joins" else "join"} your run`)
	end
	if queued > 0 then
		table.insert(parts, `{queued} wait in NEXT UP`)
	end
	text(row, `{count} {if count == 1 then "job" else "jobs"} on the board you can take: {table.concat(parts, ", ")}.`, UDim2.new(1, -250, 0, 40), {
		Position = UDim2.fromOffset(4, 4),
		TextSize = 13,
		TextColor3 = K.secondary,
		TextYAlignment = Enum.TextYAlignment.Center,
	})
	local all = action(row, `ADD ALL · {Ui.money(tonumber(plan.total) or 0)}`, UDim2.fromOffset(230, 40), UDim2.new(1, -117, 0, 4), K.red, function()
		Net.get("JobQueue"):FireServer("addAll")
	end)
	all.Name = "AddAll"
end

renderList = function()
	if not gui then
		return
	end
	refreshChrome()
	refs.firstAccept = nil
	Ui.clear(refs.list)
	local list = offers
	-- 6.12.8: YOUR RUN (any run), NEXT UP and ADD ALL on top of the offers.
	local draws: { () -> () } = { nextUpRows }
	if job then
		table.insert(draws, 1, runTicket)
	end
	if list then
		table.insert(draws, addAllRow)
	end
	for _, draw in draws do
		local ok, err = pcall(function()
			draw()
		end)
		if not ok then
			warn(`[DispatchUi] the run's summary failed: {err}`)
		end
	end
	if list == nil then
		refs.caption.Text = "Calling the dispatcher..."
		message("Calling the dispatcher...")
		return
	end
	local visible = shown(list)
	-- 4.7: your streak of good jobs (rated ★★ or better) in the caption.
	local streak = if boardInfo and type(boardInfo.streak) == "number" then boardInfo.streak else 0
	local bonus = math.floor(math.min(Config.Jobs.Rating.StreakMax, Config.Jobs.Rating.StreakStep * streak) * 100 + 0.5)
	refs.caption.Text = `{#visible} {if #visible == 1 then "job" else "jobs"} on the board{if streak > 0 then `  ·  STREAK {streak} (+{bonus}% pay)` else ""}`
	local footNote = if boardInfo and type(boardInfo.footNote) == "string" then boardInfo.footNote else nil -- 5.3 review
	if #visible == 0 then
		message(if footNote and filter == "all" then footNote elseif #list == 0 then "No jobs on the board right now. New ones come soon." else "Nothing of this kind on the board right now.")
		return
	end
	-- 5.0: the on-foot runs first, under their own header; 5.1: then the bike runs under theirs; then the car jobs.
	local walks: { any } = {}
	local rides: { any } = {}
	local rest: { any } = {}
	for _, offer in visible do
		table.insert(if isFoot(offer) then walks elseif isBike(offer) then rides else rest, offer)
	end
	local order = 0
	if #walks > 0 or (footNote ~= nil and filter == "all") then
		order += 1
		local ok, err = pcall(footHeader, #walks, order, footNote)
		if not ok then
			warn(`[DispatchUi] the on-foot header failed: {err}`)
		end
		for number, offer in walks do
			order += 1
			local ticketOk, ticketErr = pcall(offerTicket, offer, number, order)
			if not ticketOk then
				warn(`[DispatchUi] a ticket failed: {ticketErr}`)
			end
		end
	end
	if #rides > 0 then
		order += 1
		local ok, err = pcall(bikeHeader, #rides, order) -- 5.1
		if not ok then
			warn(`[DispatchUi] the bike header failed: {err}`)
		end
		for number, offer in rides do
			order += 1
			local ticketOk, ticketErr = pcall(offerTicket, offer, #walks + number, order)
			if not ticketOk then
				warn(`[DispatchUi] a ticket failed: {ticketErr}`)
			end
		end
	end
	-- 4.7: a header over every danger level's group (not on the Special jobs filter).
	local tiers = if boardInfo and type(boardInfo.tiers) == "table" and filter ~= "special" then boardInfo.tiers else nil
	local headed: { [number]: boolean } = {}
	for index, offer in rest do
		local stars = tonumber(offer.stars) or 0
		local info = if tiers then tiers[stars] else nil
		if info and not headed[stars] then
			headed[stars] = true
			order += 1
			local ok, err = pcall(tierHeader, stars, info, order)
			if not ok then
				warn(`[DispatchUi] a header failed: {err}`)
			end
		end
		order += 1
		local ok, err = pcall(offerTicket, offer, #walks + #rides + index, order)
		if not ok then
			warn(`[DispatchUi] a ticket failed: {err}`)
		end
	end
	refs.list.CanvasPosition = Vector2.zero
	-- 4.2, a gamepad: A takes the first job you can take (the stick moves to the others; B closes).
	if open then
		Ui.gamepadFocus(refs.firstAccept)
	end
end

-- ── Public ─────────────────────────────────────────────────────────────────

function DispatchUi.isOpen(): boolean
	return open
end

function DispatchUi.close()
	open = false
	if gui then
		Ui.gamepadRelease(gui)
		gui.Enabled = false
	end
end

-- 3.7: the countdown to the next offers (the caption row), twice a second while the board is open. Past the time the
-- server pushes the new board; if it has not come a few seconds later, the board asks for it.
local function tickCountdown()
	local label = refs.countdown
	if not label then
		return
	end
	-- 6.12.8: YOUR RUN's clocks.
	local now = workspace:GetServerTimeNow()
	for _, timer in (refs.runClocks or {}) :: { any } do
		local clock = timer.label
		if clock and clock.Parent then
			local left = timer.endsAt - now
			clock.Text = timer.prefix .. Ui.clock(math.max(0, left))
			clock.TextColor3 = if left < 30 then K.red else K.text
		end
	end
	local at = refreshAt
	if not at then
		label.Text = ""
		return
	end
	local left = at - workspace:GetServerTimeNow()
	label.Text = if left > 0 then `NEW JOBS IN {Ui.clock(math.ceil(left))}` else "NEW JOBS COMING..."
	if left < -3 then
		DispatchUi.request()
	end
end

local function startTicker()
	if ticking then
		return
	end
	ticking = true
	task.spawn(function()
		local lastErr: string? = nil
		while open do
			-- 5.7: an error in one tick is warned once and skipped, so `ticking` never sticks with no countdown.
			local ok, err = pcall(function()
				tickCountdown()
			end)
			if not ok and tostring(err) ~= lastErr then
				lastErr = tostring(err)
				warn(`[DispatchUi] ticker: {err}`)
			end
			task.wait(0.5)
		end
		ticking = false
	end)
end

-- Ask the dispatcher for the board (3.7: the current offers; the server makes new ones only when they expired). The
-- offers already here stay on show until the answer, unless their time is up ("Calling the dispatcher...").
function DispatchUi.request()
	local now = os.clock()
	if askedAt > 0 and now - askedAt < 3 then
		return
	end
	askedAt = now
	local at = refreshAt
	if offers and at and workspace:GetServerTimeNow() >= at then
		offers = nil
	end
	renderList()
	getOffersRemote():FireServer()
end

-- Re-fit the window to the screen and draw it again (a resize while open).
function DispatchUi.refresh()
	if not gui or not open then
		return
	end
	fit()
	renderList()
end

function DispatchUi.open()
	build()
	local hook = DispatchUi.onOpen
	if hook then
		pcall(hook)
	end
	open = true
	local made = gui :: ScreenGui
	made.Enabled = true
	fit()
	DispatchUi.request() -- (6.12.8: during a run too: its rows + ADD / + QUEUE)
	startTicker()
end

function DispatchUi.toggle()
	if open then
		DispatchUi.close()
	else
		DispatchUi.open()
	end
end

-- The offers the server sent (Main wires Net "Offers" here), already sorted ★ → ★★★★, and (3.7) when the next ones
-- come (server time; nil from an older server: no countdown), and (4.7) the board's tiers and your streak. Kept while you are on a delivery, shown after it.
function DispatchUi.setOffers(list: { any }, nextAt: number?, info: any?)
	if type(list) ~= "table" then
		return
	end
	askedAt = 0
	offers = list
	boardInfo = if type(info) == "table" then info else nil -- 4.7: the tiers' REROLL and licences, the streak
	refreshAt = if type(nextAt) == "number" then nextAt else nil
	if open then
		renderList()
		tickCountdown()
	end
end

-- The state (money, level, car) for the car card and the footer.
function DispatchUi.setState(newState: any)
	state = newState
	if open and gui then
		refreshChrome()
	end
end

function DispatchUi.start()
	-- The active job (the same "Job" remote Hud.setJob gets): on a delivery the board offers to give it up.
	-- 5.2: drawn again only when what it shows changes (a run's payload comes often: its orders, its room).
	local function runKey(): string
		if not job then
			return ""
		end
		local stack = if type(job.stack) == "table" then job.stack else {}
		local orders: { string } = {} -- 6.12.8: YOUR RUN's lines and its next stop
		for _, entry in (if type(job.orders) == "table" then job.orders else {}) :: { any } do
			if type(entry) == "table" and entry.state == "open" then
				table.insert(orders, `{entry.id}:{entry.pay}`)
			end
		end
		return `{job.cargo}|{job.customer}|{stacking()}|{stack.open}|{stack.free}|{stack.room}|{job.stopLabel}|{table.concat(orders, ",")}`
	end
	Net.get("Job").OnClientEvent:Connect(function(payload)
		local had = job ~= nil
		local before = runKey()
		job = payload
		if open then
			if had and job == nil then
				DispatchUi.request()
			elseif runKey() ~= before then
				renderList()
			end
		end
	end)
	-- 6.12.8: the NEXT UP queue (server/JobQueue.luau).
	Net.get("JobQueue").OnClientEvent:Connect(function(action, data)
		if action == "state" and type(data) == "table" then
			queueState = data
			if open then
				renderList()
			end
		end
	end)
end

return DispatchUi
