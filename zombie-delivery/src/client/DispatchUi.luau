--!strict
-- The Dispatch board (3.6, Postage & Trouble, design/ui-concept/ previews dispatch.png / hover-ticket.png): the job
-- board as a lavender window of die-cut delivery tickets. J, the JOBS menu entry, the depot counter and the result
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
--   * A ticket per offer: a numbered icon spine, the danger label ("RISKY · ★★") with the twists as chips (the
--     modifier, SPECIAL, RUSH CLOCK for a timed job, BANDITS when the cargo is wanted), the title (the special job's
--     name, else the cargo and the customer), the route (the first stop → the last address, its district), the stops,
--     the distance, the cargo slots and the time, the pieces and how they move (and a company vehicle), the
--     modifier's and the special job's descriptions; the payout stub (the pay, NIGHT ×n while night pay is up) with
--     ACCEPT JOB →. Hover lifts the ticket (Ui.tactile).
--   * Locked tickets are hatched and say why and what to do: above your driver level ("🔒 LEVEL 4", the level and
--     rank needed), or more pieces than your car holds ("📦 NEEDS 6 SLOTS", what your car holds and
--     Economy.roomAdvice: the next stage at Wrench Garage, or a bigger car from your garage). Their button toasts
--     the same reason, like the old board did.
--   * On a delivery the board shows that job and GIVE UP THIS DELIVERY (CancelJob) instead of offers.
--   * Footer: an ESC chip, "Close window", and "OLD VAN · 2 CARGO SLOTS · Road Rat / level 4".
-- The window (Ui.window) is built on first open (lazy) in a ScreenGui of its own, scaled like every window
-- (Ui.screenScale) and sized to the screen. ESC (and the gamepad's B, and opening the Roblox menu) close it; while it is open the mouse is
-- free (Main: CameraRig.mouseNeeded checks DispatchUi.isOpen()).

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

local P = Theme.Postage
local DispatchUi = {}

-- Set by Main: opening this window closes the others.
DispatchUi.onOpen = nil :: (() -> ())?

local player = Players.LocalPlayer

-- Sizes at scale 1 (the 1150 × 680 reference; Ui.screenScale scales the whole window).
local MAX_W, MAX_H, MIN_W, MIN_H = 1000, 600, 640, 380
local SIDEBAR = 220
local SPINE, STUB, GAP = 70, 160, 14
local MONO = Theme.MonoFont

-- Surfaces mixed from the Postage tokens (no new raw colours): the sidebar, the filters, the hatching, the lips.
local SIDE = P.lavender:Lerp(P.lavenderDeep, 0.75)
local FILTER_IDLE = P.lavender:Lerp(P.lavenderDeep, 0.35)
local FILTER_HOVER = P.lavender:Lerp(P.ticket, 0.35)
local HATCH_BASE = P.lavender:Lerp(P.ticket, 0.3)
local HATCH_LINE = P.lavender:Lerp(P.ticket, 0.8)
local NOTE = P.lavenderDeep:Lerp(P.paper, 0.45)
local ROSE = P.danger:Lerp(P.paper, 0.78)
local SEPARATOR = `<font color="#{P.line:ToHex()}">  |  </font>`

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
}

local FILTERS = {
	{ id = "all", name = "All jobs" },
	{ id = "delivery", name = "Deliveries" },
	{ id = "special", name = "Special jobs" },
}

local gui: ScreenGui? = nil
local refs: { [string]: any } = {}
local filterButtons: { [string]: any } = {}
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
local ticking = false -- 3.7: the countdown's loop runs (while the board is open)

local function getOffersRemote(): RemoteEvent
	if not offersRemote then
		offersRemote = Net.get("RequestOffers")
	end
	return offersRemote :: RemoteEvent
end

-- ── Small pieces ───────────────────────────────────────────────────────────

-- A label in ink (Ui.label with the Postage defaults).
local function text(parent: Instance, value: string, size: UDim2, props: { [string]: any }?): any
	local label = Ui.label(parent, value, size, { TextColor3 = P.ink, Font = Theme.Font, TextSize = 14 })
	if props then
		for key, v in props do
			label[key] = v
		end
	end
	return label
end

-- A click that plays the interface's click (Ui.onClick, client/Sounds.luau) first.
local function onPress(button: any, fn: () -> ())
	button.Activated:Connect(function()
		local click = Ui.onClick
		if click then
			click()
		end
		fn()
	end)
end

-- A small chip that grows with its text (the twists on a ticket).
local function chip(parent: Instance, value: string, face: Color3, order: number): any
	local label = text(parent, value, UDim2.fromOffset(0, 20), {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0,
		BackgroundColor3 = face,
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextWrapped = false,
		LayoutOrder = order,
	})
	Ui.corner(label, 4)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, label)
	return label
end

-- A pastel action with a lip under it (the concept's ACCEPT JOB): hover raises it 3 px, press sinks it (Ui.tactile).
-- `face` nil: the disabled (locked) look, flat, no lip.
local function lipButton(parent: Instance, label: string, size: UDim2, position: UDim2, face: Color3?, fn: () -> ()): any
	if face then
		local lip = Ui.make("Frame", {
			Size = size,
			Position = position + UDim2.fromOffset(0, 4),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = P.sageLip,
			BorderSizePixel = 0,
		}, parent)
		Ui.corner(lip, 6)
	end
	local button = Ui.make("TextButton", {
		Size = size,
		Position = position,
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = face or P.lavenderDeep,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = label,
		TextColor3 = if face then P.ink else P.ink2,
		Font = Theme.HeadingFont,
		TextSize = 14,
		TextWrapped = true,
	}, parent)
	Ui.corner(button, 6)
	onPress(button, fn)
	if face then
		Ui.tactile(button, 3, 1.02)
	end
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

local function carLevels(id: string): any
	return Economy.carLevels(if state then state.carUpgrades else nil, id)
end

-- Your car's name at its stage ("Work Van"), its cargo slots and its condition (0 … 1: the live car's health while
-- it is out, else the parked share the state keeps).
local function myCar(): (string, number, number)
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

local function setFilterLook(id: string, hover: boolean)
	local entry = filterButtons[id]
	if not entry then
		return
	end
	local active = filter == id
	local face = if active then P.ticket elseif hover then FILTER_HOVER else FILTER_IDLE
	entry.button.BackgroundColor3 = face
	entry.tip.BackgroundColor3 = face
	entry.name.TextColor3 = if active then P.ink else P.ink2
	entry.name.Font = if active then Theme.HeadingFont else Theme.Font
	TweenService:Create(entry.name, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
		Position = UDim2.fromOffset(if hover then 18 else 12, 0),
	}):Play()
end

local renderList: () -> () = function() end

local function buildFilters(side: any)
	for order, def in FILTERS do
		local button = Ui.make("TextButton", {
			Size = UDim2.new(1, -16, 0, 44),
			Position = UDim2.fromOffset(0, 40 + (order - 1) * 52),
			BackgroundColor3 = FILTER_IDLE,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
		}, side)
		-- the arrow tip on its right (the concept's clipped tab)
		local tip = Ui.make("Frame", {
			Size = UDim2.fromOffset(31, 31),
			Position = UDim2.fromScale(1, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			BackgroundColor3 = FILTER_IDLE,
			BorderSizePixel = 0,
			ZIndex = 0, -- under the tab's name and count
		}, button)
		local name = text(button, def.name, UDim2.new(1, -40, 1, 0), {
			Position = UDim2.fromOffset(12, 0),
			TextSize = 15,
			TextColor3 = P.ink2,
			TextWrapped = false,
		})
		local count = text(button, "", UDim2.new(0, 30, 1, 0), {
			Position = UDim2.new(1, -2, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			Font = Theme.HeadingFont,
			TextSize = 14,
			TextColor3 = P.ink2,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 2,
		})
		filterButtons[def.id] = { button = button, tip = tip, name = name, count = count }
		local id = def.id
		button.MouseEnter:Connect(function()
			setFilterLook(id, true)
		end)
		button.MouseLeave:Connect(function()
			setFilterLook(id, false)
		end)
		button.SelectionGained:Connect(function()
			setFilterLook(id, true)
		end)
		button.SelectionLost:Connect(function()
			setFilterLook(id, false)
		end)
		onPress(button, function()
			filter = id
			for _, other in FILTERS do
				setFilterLook(other.id, other.id == id)
			end
			renderList()
		end)
	end
end

-- The car card under the filters.
local function buildCarCard(side: any)
	local card = Ui.make("Frame", {
		Size = UDim2.new(1, -16, 0, 166),
		Position = UDim2.fromOffset(0, 40 + #FILTERS * 52 + 12),
		BackgroundColor3 = P.lavender,
		BorderSizePixel = 0,
	}, side)
	Ui.corner(card, 12)
	refs.carCard = card
	Ui.make("UIStroke", { Color = P.line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	Ui.icon(card, "map_dealer", "🚐", UDim2.fromOffset(30, 26), {
		Position = UDim2.fromOffset(14, 12),
		ImageColor3 = P.ink2,
		TextScaled = true,
	})
	refs.carName = text(card, "", UDim2.new(1, -28, 0, 22), {
		Position = UDim2.fromOffset(14, 42),
		Font = Theme.HeadingFont,
		TextSize = 17,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.carStats = text(card, "", UDim2.new(1, -28, 0, 18), { Position = UDim2.fromOffset(14, 66), TextColor3 = P.ink2, TextWrapped = false })
	refs.carHealth = text(card, "", UDim2.new(1, -28, 0, 18), { Position = UDim2.fromOffset(14, 86), TextColor3 = P.ink2, TextWrapped = false })
	refs.carNote = text(card, "Your vehicle sets your job capacity.", UDim2.new(1, -28, 0, 52), {
		Position = UDim2.fromOffset(14, 108),
		TextColor3 = P.ink2,
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
		BackgroundColor3 = P.veil,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Active = true,
	}, made)
	-- The window (Ui.window): the header with the badge, the title and the subtitle, the round ✕, the footer with ESC
	-- (ESC, the gamepad's B and the Roblox menu close it) and the car and the driver on the right.
	local window, content, chrome = Ui.window(made, "Dispatch board", "Choose your next run. Make every trip count.", "📋", UDim2.fromOffset(MAX_W, MAX_H))
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
		BorderSizePixel = 0,
	}, content)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 18), PaddingTop = UDim.new(0, 18) }, side)
	text(side, "AVAILABLE RUNS", UDim2.new(1, -16, 0, 16), {
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = P.ink2,
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
	refs.caption = text(main, "", UDim2.new(0.4, 0, 0, 30), { Position = UDim2.fromOffset(24, 12), TextColor3 = P.ink2, TextWrapped = false })
	refs.capacity = text(main, "", UDim2.new(0.6, -200, 0, 30), {
		Position = UDim2.new(1, -176, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Font = Theme.HeadingFont,
		TextSize = 12,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	-- 3.7: no refresh button: a quiet countdown to the next offers (tickCountdown).
	refs.countdown = text(main, "", UDim2.fromOffset(150, 30), {
		Position = UDim2.new(1, -24, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		Font = MONO,
		TextSize = 12,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
	})
	local list = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -50),
		Position = UDim2.fromOffset(24, 50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = P.ink2,
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
	refs.carStats.Text = `📦 {slots} cargo {if slots == 1 then "slot" else "slots"}`
	refs.carHealth.Text = `🔧 {percent}% condition`
	refs.carHealth.TextColor3 = if condition < 0.35 then P.danger else P.ink2
	refs.carNote.Text = if condition < 0.5 then "Your vehicle sets your job capacity. A repair bay fixes it." else "Your vehicle sets your job capacity."
	refs.capacity.Text = `YOUR CAPACITY · {slots} {if slots == 1 then "SLOT" else "SLOTS"}`
	local level = myLevel()
	refs.context.Text = `{string.upper(name)} · {slots} CARGO {if slots == 1 then "SLOT" else "SLOTS"}  ·  {Levels.rank(level)} / level {level}`
	local list: { any } = if job or offers == nil then {} else offers
	local special = 0
	for _, offer in list do
		if isSpecial(offer) then
			special += 1
		end
	end
	local counts = { all = #list, delivery = #list - special, special = special }
	for id, entry in filterButtons do
		entry.count.Text = if offers or job then tostring(counts[id] or 0) else "–"
		setFilterLook(id, false)
	end
	refs.countdown.Visible = job == nil and offers ~= nil
end

-- ── The tickets ────────────────────────────────────────────────────────────

-- A one-line message in the list (waiting, nothing on the board).
local function message(value: string)
	Ui.clear(refs.list)
	text(refs.list, value, UDim2.new(1, 0, 0, 60), {
		TextColor3 = P.ink2,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
end

-- Diagonal hatching over a locked ticket (thin rotated stripes, clipped to it).
local function hatch(card: any, w: number, h: number)
	card.BackgroundColor3 = HATCH_BASE
	local area = Ui.make("Frame", {
		Name = "Hatch",
		Size = UDim2.new(1, -4, 1, -4),
		Position = UDim2.fromOffset(2, 2),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		ZIndex = 0, -- under the ticket's text and perforations
	}, card)
	local length = h * 1.45 + 6
	for x = -h, w, 12 do
		Ui.make("Frame", {
			Size = UDim2.fromOffset(3, length),
			Position = UDim2.new(0, x + h / 2, 0.5, 0),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45,
			BackgroundColor3 = HATCH_LINE,
			BorderSizePixel = 0,
		}, area)
	end
end

-- The ticket's die-cut notches take the list's lavender (the contract's Ui.ticket paints them ink), and two more
-- half-round cut-outs sit in the middle of its left and right edges.
local function notches(card: any)
	for _, child in card:GetChildren() do
		if child:IsA("Frame") and child.Size == UDim2.fromOffset(12, 12) then
			child.BackgroundColor3 = P.lavender
			child.ZIndex = 3
		end
	end
	for _, x in { 0, 1 } do
		local cut = Ui.make("Frame", {
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.fromScale(x, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = P.lavender,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, card)
		Ui.corner(cut, 9)
	end
end

-- The spine: the cargo's icon (tilted) and the ticket's number.
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
	local emoji = if offer.timed then "⚡" else (KINDS[kind] or KINDS.crate).icon
	Ui.icon(card, art, emoji, UDim2.fromOffset(32, 32), {
		Position = UDim2.new(0, SPINE / 2, 0.5, -10),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = -4,
		ImageColor3 = P.ink2,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
	text(card, string.format("%02d", number), UDim2.fromOffset(SPINE, 16), {
		Position = UDim2.new(0, 0, 0.5, 14),
		Font = MONO,
		TextSize = 13,
		TextColor3 = P.ink2,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 2,
	})
	Ui.dashes(card, true, 14, P.line, UDim2.new(0, 1, 1, -16), UDim2.new(0, SPINE, 0, 8))
end

-- The danger label and the twists, in a row at the top of the ticket body (clipped to it: on a narrow board the
-- last chips are cut off rather than run over the perforation into the payout stub).
local function dangerRow(body: any, offer: any)
	local row = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 14), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2 }, body)
	Ui.make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)
	local stars = tonumber(offer.stars) or 1
	text(row, `{string.upper(tostring(offer.tierName or "Job"))} · {string.rep("★", stars)}`, UDim2.fromOffset(0, 20), {
		AutomaticSize = Enum.AutomaticSize.X,
		Font = MONO,
		TextSize = 13,
		TextColor3 = if stars >= 3 then P.danger else P.ink2,
		TextWrapped = false,
		LayoutOrder = 1,
	})
	if offer.modifier then
		chip(row, `⚠ {offer.modifier.name}`, ROSE, 2)
	end
	if isSpecial(offer) then
		chip(row, "SPECIAL", P.lavenderDeep, 3)
	end
	if offer.timed then
		chip(row, "⏱ RUSH CLOCK", P.lavenderDeep, 4)
	end
	local boost = tonumber(offer.banditBoost)
	if boost and boost > 1 then
		chip(row, "🎯 BANDITS WANT IT", ROSE, 5)
	end
end

-- The lines of the body under the title; returns where the next thing goes.
local function details(body: any, offer: any, w: number): number
	local y = 66
	text(body, `{offer.first or "Pick up"}  →  {offer.address or "?"}, {offer.district or ""}`, UDim2.new(1, 0, 0, 18), {
		Position = UDim2.fromOffset(0, y),
		TextColor3 = P.ink2,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
	})
	y += 20
	local slots = tonumber(offer.slots) or 0
	local stops = tonumber(offer.stops) or 1
	local parts: { string } = {}
	if stops > 1 then
		table.insert(parts, `{stops} stops`)
	end
	table.insert(parts, `{tonumber(offer.distance) or 0} m`)
	table.insert(parts, if slots > 0 then `📦 {slots} cargo {if slots == 1 then "slot" else "slots"}` else "no cargo slots")
	table.insert(parts, `⏱ {Ui.clock(tonumber(offer.time) or 0)}{if offer.timed then " fixed" else ""}`)
	text(body, table.concat(parts, SEPARATOR), UDim2.new(1, 0, 0, 18), {
		Position = UDim2.fromOffset(0, y),
		TextColor3 = P.ink2,
		RichText = true,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
	})
	y += 20
	-- The cargo: how many pieces, how they move, and a company vehicle the job lends.
	local count = tonumber(offer.pieces)
	if (count and count > 0) or offer.vehicle then
		local kind = KINDS[offer.itemKind or "crate"] or { icon = "📦", one = tostring(offer.itemKind), many = `{offer.itemKind}s` }
		local words: { string } = {}
		if count and count > 0 then
			local name = if count == 1 then (offer.piece or kind.one) else (offer.piecesName or kind.many)
			local how = HANDLING[offer.handling or ""]
			table.insert(words, `{kind.icon} {count} {name}` .. (if how then ` · {how}` else ""))
		end
		if offer.vehicle then
			table.insert(words, `🚚 company vehicle: {offer.vehicle}`)
		end
		text(body, table.concat(words, SEPARATOR), UDim2.new(1, 0, 0, 18), {
			Position = UDim2.fromOffset(0, y),
			RichText = true,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 2,
		})
		y += 20
	end
	if offer.modifier and offer.modifier.description then
		local line = `⚠ {offer.modifier.name}: {offer.modifier.description}`
		local h = textHeight(line, 14, Theme.Font, w)
		text(body, line, UDim2.new(1, 0, 0, h), { Position = UDim2.fromOffset(0, y), TextColor3 = P.danger, ZIndex = 2 })
		y += h + 2
	end
	if offer.jobType and offer.jobType.description then
		local h = textHeight(offer.jobType.description, 14, Theme.Font, w)
		text(body, offer.jobType.description, UDim2.new(1, 0, 0, h), { Position = UDim2.fromOffset(0, y), TextColor3 = P.ink2, ZIndex = 2 })
		y += h + 2
	end
	return y
end

-- The remedy under a locked ticket's details (a soft box across the body); returns where the next thing goes and the box.
local function remedy(body: any, value: string, y: number, w: number): (number, any)
	local h = textHeight(value, 14, Theme.Font, w - 24) + 16
	local box = text(body, value, UDim2.new(1, 0, 0, h), {
		Position = UDim2.fromOffset(0, y + 6),
		BackgroundTransparency = 0,
		BackgroundColor3 = NOTE,
		TextColor3 = P.ink,
		ZIndex = 2,
	})
	Ui.corner(box, 4)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, box)
	return y + 6 + h, box
end

-- The payout stub: the pay, night pay, and the action (ACCEPT JOB →, or the lock's reason). A locked button flashes
-- the ticket's remedy note (`note`): the HUD's toasts sit under this board's ScreenGui and its veil.
local function payStub(stub: any, offer: any, lockLevel: number?, why: string?, note: any?)
	local function flash()
		if note then
			note.BackgroundColor3 = ROSE
			TweenService:Create(note, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { BackgroundColor3 = NOTE }):Play()
		end
	end
	local touch = Ui.touchLayout()
	text(stub, Ui.money(tonumber(offer.pay) or 0), UDim2.new(1, -16, 0, 32), {
		Position = UDim2.new(0.5, 0, 0.5, -48),
		AnchorPoint = Vector2.new(0.5, 0),
		Font = Theme.DisplayFont,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		ZIndex = 2,
	})
	local nightRate = tonumber(offer.nightPay)
	if nightRate and nightRate > 1 then
		-- It is night: finished now, the job pays this many times more (Config.DayNight.NightPay).
		text(stub, string.format("🌙 NIGHT ×%.1f", nightRate), UDim2.new(1, -16, 0, 16), {
			Position = UDim2.new(0.5, 0, 0.5, -16),
			AnchorPoint = Vector2.new(0.5, 0),
			Font = Theme.HeadingFont,
			TextSize = 12,
			TextColor3 = P.ink2,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 2,
		})
	end
	local size = UDim2.new(1, -28, 0, if touch then 48 else 42)
	local at = UDim2.new(0.5, 0, 0.5, 4)
	if lockLevel then
		lipButton(stub, `🔒 LEVEL {lockLevel}`, size, at, nil, function()
			flash()
			local what = if offer.jobType then `The {offer.jobType.name}` else `{offer.tierName} jobs`
			Hud.toast(`{what} need{if offer.jobType then "s" else ""} driver level {lockLevel} ({Levels.rank(lockLevel)}). Deliveries give XP.`)
		end)
	elseif why then
		lipButton(stub, `📦 NEEDS {offer.slots} SLOTS`, size, at, nil, function()
			flash()
			Hud.toast(why)
		end)
	else
		lipButton(stub, "ACCEPT JOB  →", size, at, P.sage, function()
			Net.get("AcceptJob"):FireServer(offer.index)
			-- It leaves the board on the server once started: not shown again before the board comes back.
			local list = offers
			local spot = if list then table.find(list, offer) else nil
			if list and spot then
				table.remove(list, spot)
			end
			DispatchUi.close()
		end)
	end
end

-- The list's width at scale 1 (the window minus the sidebar, the margins and the scroll bar).
local function listWidth(): number
	return width - SIDEBAR - 24 - 20 - 6
end

local function offerTicket(offer: any, number: number)
	local w = listWidth()
	local bodyW = w - SPINE - STUB - 30
	-- Above your driver level: offered, but locked (the server refuses it too). Else too many pieces for the car.
	local lockLevel = if offer.locked == true then (tonumber(offer.level) or myLevel() + 1) else nil
	local why = if lockLevel == nil and offer.tooBig == true then roomRemedy(offer) else nil
	local note = if lockLevel then `Unlocks at LEVEL {lockLevel} ({Levels.rank(lockLevel)}). Deliveries give XP.` else why
	-- The slot in the list gets its height once the body is built (the ticket fills it).
	local slot = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 128), BackgroundTransparency = 1, LayoutOrder = number }, refs.list)
	local card: any, body: any, stub: any = Ui.ticket(slot, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), nil, STUB, 0)
	local holder = card.Parent
	card.BackgroundColor3 = P.ticket
	body.ZIndex = 2
	stub.ZIndex = 2
	notches(card)
	spine(card, offer, number)
	local column = Ui.make("Frame", {
		Size = UDim2.new(1, -(SPINE + 30), 1, 0),
		Position = UDim2.fromOffset(SPINE + 14, 0),
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, body)
	dangerRow(column, offer)
	local title = if offer.jobType then `{offer.jobType.name}: {offer.cargo}` else `{offer.cargo} for {offer.customer}`
	text(column, title, UDim2.new(1, 0, 0, 28), {
		Position = UDim2.fromOffset(0, 36),
		Font = Theme.DisplayFont,
		TextSize = 21,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
	})
	local after = details(column, offer, bodyW)
	local noteBox: any = nil
	if note then
		after, noteBox = remedy(column, note, after, bodyW)
	end
	local h = math.max(128, after + 16)
	slot.Size = UDim2.new(1, 0, 0, h)
	if note then
		hatch(card, w, h)
	end
	payStub(stub, offer, lockLevel, why, noteBox)
	Ui.tactile(holder, 5, 1)
end

-- On a delivery: that job, and giving it up.
local function jobTicket()
	Ui.clear(refs.list)
	local slot = Ui.make("Frame", { Size = UDim2.new(1, 0, 0, 132), BackgroundTransparency = 1 }, refs.list)
	local card, body, stub = Ui.ticket(slot, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), nil, STUB + 60, 0)
	card.BackgroundColor3 = P.paper
	notches(card)
	Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 24), PaddingTop = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, body)
	text(body, "ON A DELIVERY", UDim2.new(1, 0, 0, 18), { Font = MONO, TextSize = 13, TextColor3 = P.ink2 })
	text(body, `{job.cargo or "Cargo"} → {job.customer or "the customer"}`, UDim2.new(1, 0, 0, 30), {
		Position = UDim2.fromOffset(0, 22),
		Font = Theme.DisplayFont,
		TextSize = 21,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	text(body, `You are delivering {job.cargo or "cargo"} to {job.customer or "a customer"}. Finish it first, or give it up.`, UDim2.new(1, 0, 0, 40), {
		Position = UDim2.fromOffset(0, 56),
		TextColor3 = P.ink2,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	local give = lipButton(stub, "GIVE UP THIS DELIVERY", UDim2.new(1, -28, 0, 48), UDim2.new(0.5, 0, 0.5, -24), ROSE, function()
		Net.get("CancelJob"):FireServer()
		DispatchUi.close()
	end)
	give.TextColor3 = P.ink
end

renderList = function()
	if not gui then
		return
	end
	refreshChrome()
	if job then
		refs.caption.Text = "You are on a delivery"
		jobTicket()
		return
	end
	local list = offers
	if list == nil then
		refs.caption.Text = "Calling the dispatcher..."
		message("Calling the dispatcher...")
		return
	end
	local visible = shown(list)
	refs.caption.Text = `{#visible} {if #visible == 1 then "job" else "jobs"} on the board`
	Ui.clear(refs.list)
	if #visible == 0 then
		message(if #list == 0 then "No jobs on the board right now. New ones come soon." else "Nothing of this kind on the board right now.")
		return
	end
	for number, offer in visible do
		local ok, err = pcall(offerTicket, offer, number)
		if not ok then
			warn(`[DispatchUi] a ticket failed: {err}`)
		end
	end
	refs.list.CanvasPosition = Vector2.zero
end

-- ── Public ─────────────────────────────────────────────────────────────────

function DispatchUi.isOpen(): boolean
	return open
end

function DispatchUi.close()
	open = false
	if gui then
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
	local at = refreshAt
	if job or not at then
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
		while open do
			tickCountdown()
			task.wait(0.5)
		end
		ticking = false
	end)
end

-- Ask the dispatcher for the board (3.7: the current offers; the server makes new ones only when they expired). The
-- offers already here stay on show until the answer, unless their time is up ("Calling the dispatcher...").
function DispatchUi.request()
	if job then
		return
	end
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
	if job then
		renderList()
	else
		DispatchUi.request()
	end
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
-- come (server time; nil from an older server: no countdown). Kept while you are on a delivery, shown after it.
function DispatchUi.setOffers(list: { any }, nextAt: number?)
	if type(list) ~= "table" then
		return
	end
	askedAt = 0
	offers = list
	refreshAt = if type(nextAt) == "number" then nextAt else nil
	if open and not job then
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
	Net.get("Job").OnClientEvent:Connect(function(payload)
		local had = job ~= nil
		job = payload
		if open then
			if had and job == nil then
				DispatchUi.request()
			else
				renderList()
			end
		end
	end)
end

return DispatchUi
