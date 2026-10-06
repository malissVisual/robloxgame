--!strict
-- The office computer: your delivery company (server/Business.luau, Config.Business). Opens when you use the
-- computer in an office you own (the server sends the state with open = true through the `Business` remote).
--
--   * Three cards on top: the COMPANY SAFE (counting up live between the server's payouts, COLLECT), the EARNINGS
--     (per minute online, the upgrades' multiplier, the share while you are away) and the COURIERS (seats, HIRE,
--     FIRE with a second click to confirm).
--   * ON THE ROAD: every courier with a lively status line, typed out like a dispatch terminal ("Courier Ana —
--     delivering medicine boxes to 14 Oak Ave"), a phase tag and a progress bar: drive to a business from the job
--     board (Config.Jobs.Businesses), load, deliver to a real address (Map.addresses), hand over, paid. Now and then
--     trouble on the road (fewer with armed escorts), faster with better vans and dispatch software. Couriers the
--     office has no desk for wait. All of it is for show: the money is computed on the server.
--   * UPGRADES: the Config.Business.Upgrades tracks with their levels and the next price.
--   * DISPATCH RADIO: the last few things the couriers reported.
--   * The welcome-back card after a join ("While you were away your company made $x") with GPS TO OFFICE.
-- Every button only asks the server (hire / fire / upgrade / collect); the server checks everything. The window
-- closes when you walk away from the computer, when another window opens or when the interface goes off.
-- While it is open the mouse is free (Main: CameraRig.mouseNeeded checks BusinessUi.isOpen()).
-- 3.8 (the contract UI, design/ui-contract/): the charcoal window (Ui.window), flat cards and rows, the dispatch radio
-- a dark slip, the welcome-back card a charcoal card with a thin money-green rule.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Icons = require(Shared.Icons)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Client = script.Parent
local Ui = require(Client.Ui)
local Theme = require(Client.Theme)
local Hud = require(Client.Hud)
local MapView = require(Client.MapView)
local Leaderboard = require(Client.Leaderboard)
local CrewPanel = require(Client.CrewPanel)
local EstateUi = require(Client.EstateUi)
local DialogKeys = require(Client.DialogKeys)

local C = Ui.Colors
local P = Theme.Postage
local B = Config.Business
local BusinessUi = {}

local player = Players.LocalPlayer

local WIDTH, HEIGHT = 800, 640
local CONTENT_H = HEIGHT - Ui.WindowHeader - Ui.WindowFooter -- the content area under the window's header
local STEP = 0.05 -- seconds between two animation steps while the window is open
local TYPE_SPEED = 90 -- characters per second of the status lines
local WALK_AWAY = 30 -- studs from where the window opened: it closes
local WELCOME_SECONDS = 16

local COURIER_NAMES = {
	"Ana", "Marek", "Bea", "Tomas", "Lucy", "Rex", "Ivana", "Dusty", "Kofi", "Mila", "Hank", "Zoe", "Pavel", "Rosa",
	"Jin", "Olga", "Bruno", "Nina", "Vic", "Eva", "Sam", "Petra", "Duke", "Lena", "Otto", "Mae", "Igor", "Tess",
	"Radek", "June", "Max", "Kat",
}
local VANS = { "Rusty Van", "Box Van", "Cargo Van", "Turbo Van", "Armored Van", "Golden Van" }
local ROADS = {
	"Rust Bridge", "Old Bridge", "the North Highway", "the West Highway", "the Ranch Road", "Riding School Lane",
	"6th Ave", "the harbor road", "the Mount Rot tunnel",
}
local TROUBLE = {
	"stuck behind a zombie horde on %s",
	"changing a flat tyre on %s",
	"outrunning a bandit pickup on %s",
	"hiding from a zombie wave near %s",
	"pushing a wreck off %s",
}
local ESCORT_TROUBLE = {
	"the escort is shooting off a bandit roadblock on %s",
	"the escort cleared a zombie pack off %s",
}
local BREAKS = { "coffee break at the depot", "refuelling at the Gas Station", "washing zombie goo off the van", "fixing a mirror at Wrench Garage" }
local CARGO_EMOJI: { [string]: string } = {
	crate = "📦", ammo = "🧨", sack = "🛍️", barrel = "🛢️", icebox = "🧊", furniture = "🛋️", soup = "🍲",
}

type Phase = { tag: string, color: Color3, text: string, seconds: number, radio: string? }
type Courier = {
	name: string,
	phases: { Phase },
	index: number,
	started: number,
	ends: number,
	shown: number, -- graphemes typed out of the status line so far
	look: string?, -- the cargo look / kind of the job (the row's icon)
	kind: string?,
	row: any?,
}

local state: any = nil
local receivedAt = 0
local money = 0
local gui: any = nil
local window: any = nil
local chrome: any = nil
local scale: any = nil
local welcomeCard: any = nil
local welcomeScale: any = nil
local refs: { [string]: any } = {}
local couriers: { Courier } = {}
local radio: { string } = {}
local upgradeRows: { [string]: { level: any, pips: { any }, button: any } } = {}
local openedAt: Vector3? = nil
local running = 0 -- bumps on every open / close: the old animation loop stops
local fireArmedUntil = 0
local pendingWelcome: any = nil
local remote: RemoteEvent? = nil

local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.get("Business")
	end
	return remote :: RemoteEvent
end

local function ask(action: string, arg: any?)
	getRemote():FireServer(action, arg)
end

-- Is the game's interface on (after PLAY on the start screen)?
local function hudGui(): ScreenGui?
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	return if hud and hud:IsA("ScreenGui") then hud else nil
end

local function hudOn(): boolean
	local hud = hudGui()
	return hud == nil or hud.Enabled
end

local function rootPosition(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local hours, minutes = seconds // 3600, (seconds % 3600) // 60
	if hours > 0 then
		return if minutes > 0 then `{hours} h {minutes} min` else `{hours} h`
	end
	return if minutes > 0 then `{minutes} min` else `{seconds} s`
end

local function upgradeLevel(id: string): number
	local levels = state and state.upgrades
	return if type(levels) == "table" then tonumber(levels[id]) or 0 else 0
end

local function upgradeCost(def: { baseCost: number, costGrowth: number }, level: number): number
	return math.floor(def.baseCost * def.costGrowth ^ level + 0.5) -- the same formula as server/Business.luau
end

-- The safe right now: the server's number plus what the couriers made since (capped), for the live counter.
local function liveSafe(): number
	if not state then
		return 0
	end
	local cap = tonumber(state.safeCap) or B.SafeCap
	local safe = tonumber(state.safe) or 0
	local perMinute = tonumber(state.perMinute) or 0
	return math.min(cap, safe + perMinute * (os.clock() - receivedAt) / 60)
end

local function paintButton(button: any, text: string, color: Color3, enabled: boolean)
	local fill = if enabled then color else C.grey
	button.Text = text
	button.BackgroundColor3 = fill
	button.TextColor3 = if enabled then Theme.textOn(fill) else C.dim
	button.AutoButtonColor = false
end

-- ── The couriers' little lives (for show) ──────────────────────────────────

local rng = Random.new()

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function addressName(): string
	local list = Map.addresses()
	for _ = 1, 6 do
		local address = list[rng:NextInteger(1, #list)]
		if not address.poi then
			return address.name
		end
	end
	return list[rng:NextInteger(1, #list)].name
end

local function radioLine(text: string)
	table.insert(radio, 1, text)
	while #radio > 3 do
		table.remove(radio)
	end
	local lines = refs.radio
	if lines then
		for i, label in lines do
			label.Text = radio[i] or ""
			label.TextTransparency = (i - 1) * 0.3
		end
	end
end

-- A fresh run for one courier: to the business, load, deliver (maybe trouble on the way), hand over, paid.
local function plan(courier: Courier): { Phase }
	local vans, dispatch, security = upgradeLevel("vans"), upgradeLevel("dispatch"), upgradeLevel("security")
	local fast = 1 / (1 + vans * 0.15)
	local smart = 1 / (1 + dispatch * 0.1)
	local businesses = Config.Jobs.Businesses
	local business = businesses[rng:NextInteger(1, #businesses)]
	local count = rng:NextInteger(business.pieces[1], math.max(business.pieces[1], business.pieces[2]))
	local what = if count == 1 then `1 {business.piece}` else `{count} {business.plural}`
	local address = addressName()
	local receiver = pick(business.receivers)
	courier.look = business.look
	courier.kind = business.kind
	local phases: { Phase } = {}
	if rng:NextNumber() < 0.12 then
		table.insert(phases, { tag = "BREAK", color = C.grey, text = pick(BREAKS), seconds = rng:NextNumber(3, 5) })
	end
	table.insert(phases, { tag = "DRIVING", color = C.blue, text = `heading to the {business.place}`, seconds = rng:NextNumber(5, 9) * fast * smart })
	table.insert(phases, { tag = "LOADING", color = C.yellow, text = `loading {what} at the {business.place}`, seconds = rng:NextNumber(3, 5) * smart })
	local deliver = rng:NextNumber(8, 13) * fast
	local trouble = rng:NextNumber() < 0.24 * (1 - security * 0.15)
	local cargo = string.lower(business.cargo)
	if trouble then
		table.insert(phases, { tag = "ON THE ROAD", color = C.blue, text = `delivering {cargo} to {address}`, seconds = deliver * 0.45 })
		local road = pick(ROADS)
		local line = if security > 0 then pick(ESCORT_TROUBLE) else pick(TROUBLE)
		local text = string.format(line, road)
		table.insert(phases, { tag = "TROUBLE", color = C.red, text = text, seconds = rng:NextNumber(3, 5), radio = `{courier.name}: {text}!` })
		table.insert(phases, { tag = "ON THE ROAD", color = C.blue, text = `back on the road to {address}`, seconds = deliver * 0.55 })
	else
		table.insert(phases, { tag = "ON THE ROAD", color = C.blue, text = `delivering {cargo} to {address}`, seconds = deliver })
	end
	table.insert(phases, { tag = "DROP", color = C.green, text = `handing {what} to {receiver.name}`, seconds = rng:NextNumber(2, 3) * smart })
	-- The pay shown for the run: what the courier earns per minute over the run's time (the real money is the server's).
	local total = 0
	for _, phase in phases do
		total += phase.seconds
	end
	local perCourier = B.CourierPerMinute * (tonumber(state and state.multiplier) or 1)
	local pay = math.max(1, math.floor(perCourier * (total + 2.5) / 60 + 0.5))
	table.insert(phases, {
		tag = `+{Ui.money(pay)}`,
		color = C.money,
		text = `delivered {what} to {address} · back to the office`,
		seconds = 2.5,
		radio = `{courier.name}: {what} delivered to {address} · +{Ui.money(pay)}`,
	})
	return phases
end

-- ── Building ───────────────────────────────────────────────────────────────

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local size = Ui.screenSize() -- (under the top bar: the ScreenGui does not ignore the inset)
	if scale then
		scale.Scale = math.clamp(math.min((size.X - 16) / WIDTH, (size.Y - 16) / HEIGHT), 0.35, 1.1)
	end
	if welcomeScale then
		welcomeScale.Scale = math.clamp(math.min((size.X - 16) / 480, size.Y / 680), 0.5, 1.1)
	end
end

local function card(parent: any, x: number, width: number, title: string): any
	local frame = Ui.make("Frame", {
		Size = UDim2.fromOffset(width, 136),
		Position = UDim2.fromOffset(x, 0),
		BackgroundColor3 = P.ticket,
		BorderSizePixel = 0,
	}, parent)
	Ui.corner(frame)
	Ui.stroke(frame, P.line, 1).Transparency = 0
	Ui.caps(frame, title, UDim2.new(1, -24, 0, 16), { Position = UDim2.fromOffset(12, 8) })
	return frame
end

local function sectionTitle(parent: any, text: string, position: UDim2, width: UDim): any
	return Ui.caps(parent, text, UDim2.new(width.Scale, width.Offset, 0, 18), {
		Position = position,
		TextSize = 13,
		TextColor3 = C.text,
	})
end

local onCollect, onHire, onFire -- set below (the buttons need them)

local function build()
	if gui then
		return
	end
	gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryBusiness",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 3,
		IgnoreGuiInset = false,
	}, player:WaitForChild("PlayerGui"))

	-- ── The window ──
	local content
	window, content, chrome = Ui.window(gui, "Your company", "", "🏢", UDim2.fromOffset(WIDTH, HEIGHT))
	window.Visible = false
	chrome.onClose = function()
		BusinessUi.close()
	end
	chrome.context.Text = "Office computer · walk away to close"
	scale = Ui.make("UIScale", {}, window)
	refs.title = chrome.title
	refs.subtitle = chrome.subtitle

	-- ── The three cards ──
	local cards = Ui.make("Frame", { Size = UDim2.new(1, -36, 0, 136), Position = UDim2.fromOffset(18, 12), BackgroundTransparency = 1 }, content)
	local cardWidth = math.floor((WIDTH - 36 - 2 * 10) / 3)

	local safeCard = card(cards, 0, cardWidth, "COMPANY SAFE")
	refs.safe = Ui.label(safeCard, "$0", UDim2.new(1, -24, 0, 32), {
		Position = UDim2.fromOffset(12, 24),
		TextSize = 28,
		Font = Theme.MonoFont,
		TextColor3 = C.money,
		TextScaled = true,
	})
	local safeBack, safeFill = Ui.bar(safeCard, UDim2.new(1, -24, 0, 6), C.money)
	safeBack.Position = UDim2.fromOffset(12, 60)
	refs.safeFill = safeFill
	refs.safeInfo = Ui.label(safeCard, "", UDim2.new(1, -24, 0, 16), { Position = UDim2.fromOffset(12, 70), TextSize = 12, Font = Theme.Font, TextColor3 = C.dim })
	refs.collect = Ui.button(safeCard, "COLLECT", UDim2.new(1, -24, 0, 34), C.green, function()
		onCollect()
	end)
	refs.collect.Position = UDim2.fromOffset(12, 92)

	local earnCard = card(cards, cardWidth + 10, cardWidth, "EARNINGS")
	refs.rate = Ui.label(earnCard, "+$0 / min", UDim2.new(1, -24, 0, 32), {
		Position = UDim2.fromOffset(12, 24),
		TextSize = 26,
		Font = Theme.MonoFont,
		TextColor3 = C.text,
		TextScaled = true,
	})
	refs.multiplier = Ui.label(earnCard, "", UDim2.new(1, -24, 0, 16), { Position = UDim2.fromOffset(12, 60), TextSize = 13, TextColor3 = P.violet })
	refs.earnInfo = Ui.label(earnCard, "", UDim2.new(1, -24, 0, 50), {
		Position = UDim2.fromOffset(12, 80),
		TextSize = 12,
		Font = Theme.Font,
		TextColor3 = C.dim,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local crewCard = card(cards, 2 * (cardWidth + 10), cardWidth, "COURIERS")
	refs.count = Ui.label(crewCard, "0 / 0", UDim2.new(0, 110, 0, 32), {
		Position = UDim2.fromOffset(12, 24),
		TextSize = 28,
		Font = Theme.MonoFont,
	})
	refs.seats = Ui.make("Frame", { Size = UDim2.new(1, -24, 0, 12), Position = UDim2.fromOffset(12, 62), BackgroundTransparency = 1 }, crewCard)
	Ui.list(refs.seats, false, 3)
	refs.crewInfo = Ui.label(crewCard, "", UDim2.new(1, -24, 0, 14), { Position = UDim2.fromOffset(12, 76), TextSize = 12, Font = Theme.Font, TextColor3 = C.dim })
	refs.hire = Ui.button(crewCard, "HIRE", UDim2.new(1, -94, 0, 34), C.yellow, function()
		onHire()
	end)
	refs.hire.Position = UDim2.fromOffset(12, 92)
	refs.hire.TextSize = 15
	refs.fire = Ui.button(crewCard, "FIRE", UDim2.fromOffset(64, 34), C.red, function()
		onFire()
	end)
	refs.fire.Position = UDim2.new(1, -76, 0, 92)
	refs.fire.TextSize = 15

	-- ── On the road (left) and upgrades (right) ──
	local listTop = 160
	local radioHeight = 76
	local listHeight = CONTENT_H - (listTop + 22) - radioHeight - 22
	local leftWidth = math.floor((WIDTH - 36) * 0.58)
	sectionTitle(content, "ON THE ROAD", UDim2.fromOffset(20, listTop), UDim.new(0, leftWidth))
	refs.roadNote = Ui.label(content, "", UDim2.fromOffset(leftWidth - 120, 18), {
		Position = UDim2.fromOffset(18 + 120, listTop),
		TextSize = 12,
		Font = Theme.Font,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	refs.road = Ui.make("ScrollingFrame", {
		Size = UDim2.fromOffset(leftWidth, listHeight),
		Position = UDim2.fromOffset(18, listTop + 22),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = P.ink2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, content)
	Ui.list(refs.road, true, 6)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 1), PaddingLeft = UDim.new(0, 1), PaddingRight = UDim.new(0, 8) }, refs.road)

	local rightX = 18 + leftWidth + 12
	local rightWidth = WIDTH - 18 - rightX
	sectionTitle(content, "UPGRADES", UDim2.fromOffset(rightX + 2, listTop), UDim.new(0, rightWidth))
	local upgrades = Ui.make("ScrollingFrame", {
		Size = UDim2.fromOffset(rightWidth, listHeight),
		Position = UDim2.fromOffset(rightX, listTop + 22),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = P.ink2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, content)
	Ui.list(upgrades, true, 6)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 1), PaddingLeft = UDim.new(0, 1), PaddingRight = UDim.new(0, 6) }, upgrades)
	for order, def in B.Upgrades do
		local row = Ui.make("Frame", { Size = UDim2.new(1, -2, 0, 84), BackgroundColor3 = P.ticket, BorderSizePixel = 0, LayoutOrder = order }, upgrades)
		Ui.corner(row)
		Ui.stroke(row, P.line, 1).Transparency = 0
		Ui.label(row, def.name, UDim2.new(1, -20, 0, 20), { Position = UDim2.fromOffset(10, 6), TextSize = 16, Font = Theme.DisplayFont, TextWrapped = false })
		local level = Ui.label(row, "", UDim2.fromOffset(70, 20), {
			Position = UDim2.new(1, -80, 0, 6),
			TextSize = 13,
			Font = Theme.MonoFont,
			TextColor3 = P.violet,
			TextXAlignment = Enum.TextXAlignment.Right,
		})
		Ui.label(row, def.description, UDim2.new(1, -20, 0, 16), { Position = UDim2.fromOffset(10, 27), TextSize = 12, Font = Theme.Font, TextColor3 = C.dim, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false })
		local pipBox = Ui.make("Frame", { Size = UDim2.fromOffset(110, 10), Position = UDim2.fromOffset(10, 60), BackgroundTransparency = 1 }, row)
		Ui.list(pipBox, false, 4)
		local pips = {}
		for i = 1, def.maxLevel do
			local pip = Ui.make("Frame", { Size = UDim2.fromOffset(16, 10), BackgroundColor3 = P.track, BorderSizePixel = 0, LayoutOrder = i }, pipBox)
			Ui.corner(pip)
			table.insert(pips, pip)
		end
		local id = def.id
		local button = Ui.button(row, "UPGRADE", UDim2.fromOffset(136, 30), C.yellow, function()
			ask("upgrade", id)
		end)
		button.Position = UDim2.new(1, -146, 0, 48)
		button.TextSize = 13
		upgradeRows[def.id] = { level = level, pips = pips, button = button }
	end

	-- ── Dispatch radio ── (a paper slip, typed)
	local radioBox = Ui.make("Frame", {
		Size = UDim2.new(1, -36, 0, radioHeight),
		Position = UDim2.new(0, 18, 1, -(radioHeight + 12)),
		BackgroundColor3 = P.paper,
		BorderSizePixel = 0,
	}, content)
	Ui.corner(radioBox)
	Ui.stroke(radioBox, P.line, 1).Transparency = 0
	Ui.caps(radioBox, "📻 Dispatch radio", UDim2.fromOffset(200, 16), { Position = UDim2.fromOffset(10, 5), TextColor3 = C.green })
	refs.radio = {}
	for i = 1, 3 do
		local line = Ui.label(radioBox, "", UDim2.new(1, -20, 0, 16), {
			Position = UDim2.fromOffset(10, 6 + i * 17),
			TextSize = 13,
			Font = Theme.MonoFont,
			TextColor3 = C.text,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		table.insert(refs.radio, line)
	end

	-- ── The welcome-back card ── (a charcoal card with a thin money-green rule)
	welcomeCard = Ui.panel(gui, UDim2.fromOffset(460, 168), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	welcomeCard.Visible = false
	welcomeCard.BackgroundTransparency = 0
	welcomeScale = Ui.make("UIScale", {}, welcomeCard)
	Ui.stroke(welcomeCard, P.line, 1)
	Ui.edge(welcomeCard, C.money, 0)
	Ui.caps(welcomeCard, "Welcome back, boss", UDim2.new(1, -24, 0, 16), { Position = UDim2.fromOffset(16, 12), TextSize = 13, TextColor3 = C.green })
	refs.welcomeText = Ui.label(welcomeCard, "", UDim2.new(1, -32, 0, 54), {
		Position = UDim2.fromOffset(16, 30),
		TextSize = 20,
		Font = Enum.Font.GothamBold,
		RichText = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	refs.welcomeInfo = Ui.label(welcomeCard, "", UDim2.new(1, -32, 0, 30), {
		Position = UDim2.fromOffset(16, 86),
		TextSize = 13,
		Font = Theme.Font,
		TextColor3 = C.dim,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	refs.welcomeGps = Ui.button(welcomeCard, "📍 GPS TO OFFICE", UDim2.fromOffset(200, 34), C.blue, function()
		BusinessUi.gpsToOffice()
		welcomeCard.Visible = false
	end)
	refs.welcomeGps.Position = UDim2.new(0, 16, 1, -46)
	refs.welcomeGps.TextSize = 15
	local ok = Ui.ghostButton(welcomeCard, "OK", UDim2.fromOffset(90, 34), nil, function()
		welcomeCard.Visible = false
	end)
	ok.Position = UDim2.new(1, -106, 1, -46)
	-- 4.4.1: Space (Enter, the gamepad's A) closes the card like OK while it shows; the key's hint left of OK.
	Ui.label(welcomeCard, DialogKeys.hint(), UDim2.fromOffset(50, 34), {
		Position = UDim2.new(1, -160, 1, -46),
		Font = Theme.MonoFont,
		TextSize = 11,
		TextColor3 = C.dim,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	DialogKeys.watch("welcomeBack", welcomeCard, function()
		welcomeCard.Visible = false
	end)

	updateScale()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
end

-- ── The courier rows ───────────────────────────────────────────────────────

local function setIcon(courier: Courier)
	local row = courier.row
	if not row then
		return
	end
	Ui.clear(row.iconBox)
	local name = Icons.cargo(courier.look) or Icons.cargo(courier.kind)
	Ui.icon(row.iconBox, name, CARGO_EMOJI[courier.kind or ""] or "📦", UDim2.fromScale(1, 1), {
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ImageColor3 = C.text,
	})
end

-- Shows the courier's current phase: the tag, the typed-out line, the progress bar running over the phase.
local function showPhase(courier: Courier, now: number, elapsed: number?)
	local phase = courier.phases[courier.index]
	courier.started = now - (elapsed or 0)
	courier.ends = courier.started + phase.seconds
	courier.shown = if elapsed then 10000 else 0
	local row = courier.row
	if not row then
		return
	end
	row.status.Text = phase.text
	row.status.MaxVisibleGraphemes = if elapsed then -1 else 0
	row.tag.Text = phase.tag
	row.tag.BackgroundColor3 = phase.color
	row.tag.TextColor3 = Theme.textOn(phase.color)
	row.fill.BackgroundColor3 = phase.color
	local share = math.clamp((now - courier.started) / phase.seconds, 0, 1)
	row.fill.Size = UDim2.fromScale(share, 1)
	if row.tween then
		row.tween:Cancel()
		row.tween = nil
	end
	if phase.seconds > 3600 then
		return -- waiting, not going anywhere
	end
	local tween = TweenService:Create(row.fill, TweenInfo.new(math.max(0.05, courier.ends - now), Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
	row.tween = tween
	tween:Play()
end

local function startRun(courier: Courier, now: number, midway: boolean)
	courier.phases = plan(courier)
	courier.index = 1
	setIcon(courier)
	if midway then
		-- Opening the window: everybody is somewhere in their run already.
		courier.index = rng:NextInteger(1, #courier.phases)
		showPhase(courier, now, rng:NextNumber(0, courier.phases[courier.index].seconds * 0.8))
	else
		showPhase(courier, now, nil)
	end
end

local function courierName(index: number): string
	-- Every company has its own crew (the same names every time), shuffled by the owner's user id.
	local names = table.clone(COURIER_NAMES)
	local shuffle = Random.new(tonumber(state and state.userId) or player.UserId)
	for i = #names, 2, -1 do
		local j = shuffle:NextInteger(1, i)
		names[i], names[j] = names[j], names[i]
	end
	return names[(index - 1) % #names + 1]
end

local function rebuildRows()
	local road = refs.road
	if not road or not state then
		return
	end
	Ui.clear(road)
	couriers = {}
	local hired = math.max(0, math.floor(tonumber(state.couriers) or 0))
	local working = math.max(0, math.floor(tonumber(state.working) or 0))
	local van = VANS[math.clamp(upgradeLevel("vans") + 1, 1, #VANS)]
	refs.roadNote.Text = if hired > 0 then `{van}s · {working} working` else ""
	if hired == 0 then
		Ui.label(road, `No couriers yet. HIRE one for {Ui.money(B.CourierCost)}: each makes {Ui.money(B.CourierPerMinute)} a minute while you play, and {math.floor(B.OfflineShare * 100)}% of that while you are away (up to {B.OfflineHours} h).`, UDim2.new(1, -4, 0, 70), {
			TextSize = 14,
			Font = Theme.Font,
			TextColor3 = C.dim,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		return
	end
	local now = os.clock()
	for i = 1, hired do
		local frame = Ui.make("Frame", { Size = UDim2.new(1, -2, 0, 60), BackgroundColor3 = P.ticket, BorderSizePixel = 0, LayoutOrder = i }, road)
		Ui.corner(frame)
		Ui.stroke(frame, P.line, 1).Transparency = 0
		local iconBox = Ui.make("Frame", { Size = UDim2.fromOffset(34, 34), Position = UDim2.fromOffset(10, 10), BackgroundTransparency = 1 }, frame)
		local name = courierName(i)
		Ui.label(frame, `Courier {name}`, UDim2.new(1, -170, 0, 20), {
			Position = UDim2.fromOffset(54, 6),
			TextSize = 15,
			Font = Theme.DisplayFont,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local status = Ui.label(frame, "", UDim2.new(1, -66, 0, 18), {
			Position = UDim2.fromOffset(54, 28),
			TextSize = 13,
			Font = Theme.Font,
			TextColor3 = C.dim,
			TextWrapped = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local tagBox = Ui.make("Frame", { Size = UDim2.fromOffset(110, 20), Position = UDim2.new(1, -118, 0, 6), BackgroundTransparency = 1 }, frame)
		Ui.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right }, tagBox)
		local tag = Ui.chip(tagBox, "", C.blue)
		tag.TextSize = 12
		local back, fill = Ui.bar(frame, UDim2.new(1, -66, 0, 4), C.blue)
		back.Position = UDim2.fromOffset(54, 49)
		local courier: Courier = { name = name, phases = {}, index = 1, started = now, ends = now, shown = 0, look = nil, kind = nil, row = nil }
		courier.row = { frame = frame, iconBox = iconBox, status = status, tag = tag, fill = fill, tween = nil }
		table.insert(couriers, courier)
		if i <= working then
			startRun(courier, now, true)
		else
			-- No desk for this one (a smaller office): waiting.
			courier.phases = { { tag = "NO DESK", color = C.grey, text = `waiting for a desk: this office seats {state.seats}`, seconds = 1e9 } }
			courier.kind = "crate"
			setIcon(courier)
			showPhase(courier, now, 0)
			frame.BackgroundTransparency = 0.4
		end
	end
end

-- ── Rendering ──────────────────────────────────────────────────────────────

local rowsKey = "" -- what the rows were built for (rebuilt when the couriers change)

local function render()
	if not window or not state then
		return
	end
	local hasOffice = state.office ~= nil
	refs.title.Text = tostring(state.company or "Your company")
	refs.subtitle.Text = if hasOffice
		then `{state.officeName} · office computer{if state.atOffice then "" else " · walk up to the computer to manage"}`
		else "You have no office. Buy one in a tower to run your company."
	local perMinute = tonumber(state.perMinute) or 0
	local multiplier = tonumber(state.multiplier) or 1
	local seats = tonumber(state.seats) or 0
	local hired = tonumber(state.couriers) or 0
	local working = tonumber(state.working) or 0
	local at = state.atOffice == true

	-- Earnings.
	refs.rate.Text = `+{Ui.money(perMinute)} / min`
	refs.rate.TextColor3 = if perMinute > 0 then C.money else C.dim
	refs.multiplier.Text = `× {string.format("%.2f", multiplier)} from upgrades`
	refs.earnInfo.Text = `{Ui.money(B.CourierPerMinute * multiplier)} per courier a minute.\nAway: +{Ui.money(perMinute * B.OfflineShare)}/min for up to {B.OfflineHours} h.`

	-- Couriers.
	refs.count.Text = `{hired} / {seats}`
	refs.count.TextColor3 = if hired > seats then C.red else C.text
	Ui.clear(refs.seats)
	for i = 1, math.max(seats, hired) do
		local seat = Ui.make("Frame", {
			Size = UDim2.fromOffset(if math.max(seats, hired) > 8 then 10 else 16, 10),
			BackgroundColor3 = if i <= working then P.violet elseif i <= hired then C.red else P.track,
			BorderSizePixel = 0,
			LayoutOrder = i,
		}, refs.seats)
		Ui.corner(seat)
	end
	refs.crewInfo.Text = if hired > seats then `{hired - seats} without a desk: they do not earn` elseif hired >= seats and seats > 0 then "Every desk is taken" else `Hiring costs {Ui.money(B.CourierCost)}`
	local canHire = at and hasOffice and hired < seats
	paintButton(refs.hire, if hasOffice and hired >= seats then "OFFICE FULL" else `HIRE {Ui.money(B.CourierCost)}`, C.yellow, canHire and money >= B.CourierCost)
	paintButton(refs.fire, if os.clock() < fireArmedUntil then "SURE?" else "FIRE", C.red, at and hired > 0)

	-- Upgrades.
	for _, def in B.Upgrades do
		local row = upgradeRows[def.id]
		if row then
			local level = upgradeLevel(def.id)
			row.level.Text = `LV {level}/{def.maxLevel}`
			for i, pip in row.pips do
				pip.BackgroundColor3 = if i <= level then P.violet else P.track
			end
			if level >= def.maxLevel then
				paintButton(row.button, "MAX", C.green, false)
			else
				local cost = upgradeCost(def, level)
				paintButton(row.button, `UPGRADE {Ui.money(cost)}`, C.yellow, at and hasOffice and money >= cost)
			end
		end
	end

	-- The courier rows: rebuilt only when the crew or the vans changed.
	local key = `{hired}/{working}/{seats}/{upgradeLevel("vans")}`
	if key ~= rowsKey then
		rowsKey = key
		rebuildRows()
	end
end

-- The parts that move every step: the safe's counter and the courier lines.
local function step()
	if not state then
		return
	end
	local cap = tonumber(state.safeCap) or B.SafeCap
	local safe = liveSafe()
	local perMinute = tonumber(state.perMinute) or 0
	refs.safe.Text = Ui.money(safe)
	refs.safeFill.Size = UDim2.fromScale(math.clamp(safe / cap, 0, 1), 1)
	refs.safeFill.BackgroundColor3 = if safe >= cap then C.red else C.money
	if safe >= cap then
		refs.safeInfo.Text = "FULL: collect it, the couriers keep nothing extra"
		refs.safeInfo.TextColor3 = C.red
	elseif perMinute > 0 then
		refs.safeInfo.Text = `of {Ui.money(cap)} · full in {duration((cap - safe) / perMinute * 60)}`
		refs.safeInfo.TextColor3 = C.dim
	else
		refs.safeInfo.Text = `of {Ui.money(cap)} · hire couriers to fill it`
		refs.safeInfo.TextColor3 = C.dim
	end
	paintButton(refs.collect, if safe >= 1 then `COLLECT {Ui.money(safe)}` else "COLLECT", C.green, state.atOffice == true and safe >= 1)
	if fireArmedUntil > 0 and os.clock() >= fireArmedUntil then
		fireArmedUntil = 0
		paintButton(refs.fire, "FIRE", C.red, state.atOffice == true and (tonumber(state.couriers) or 0) > 0)
	end

	local now = os.clock()
	for _, courier in couriers do
		local row = courier.row
		if row and courier.shown < 10000 then
			local phase = courier.phases[courier.index]
			courier.shown = math.floor((now - courier.started) * TYPE_SPEED)
			if courier.shown >= (utf8.len(phase.text) or #phase.text) then
				courier.shown = 10000
				row.status.MaxVisibleGraphemes = -1
			else
				row.status.MaxVisibleGraphemes = courier.shown
			end
		end
		if now >= courier.ends and #courier.phases > 0 then
			local finished = courier.phases[courier.index]
			if finished.radio then
				radioLine(finished.radio)
			end
			if courier.index >= #courier.phases then
				startRun(courier, now, false)
			else
				courier.index += 1
				local next = courier.phases[courier.index]
				if next.radio and next.tag == "TROUBLE" then
					radioLine(next.radio)
					next.radio = nil
				end
				showPhase(courier, now, nil)
			end
		end
	end
end

-- ── Buttons ────────────────────────────────────────────────────────────────

onCollect = function()
	if state and state.atOffice and liveSafe() >= 1 then
		ask("collect")
	end
end

onHire = function()
	if not state or not state.atOffice then
		return
	end
	if money < B.CourierCost then
		Hud.toast(`Hiring a courier costs {Ui.money(B.CourierCost)}.`)
		return
	end
	ask("hire")
end

onFire = function()
	if not state or not state.atOffice or (tonumber(state.couriers) or 0) < 1 then
		return
	end
	if os.clock() < fireArmedUntil then
		fireArmedUntil = 0
		ask("fire")
	else
		fireArmedUntil = os.clock() + 3
		paintButton(refs.fire, "SURE?", C.red, true)
	end
end

-- ── Open / close ───────────────────────────────────────────────────────────

local function otherWindowOpen(): boolean
	local ok, open = pcall(function()
		return Hud.anyWindowOpen() or Leaderboard.isOpen() or CrewPanel.isOpen() or EstateUi.isOpen()
	end)
	return ok and open == true
end

function BusinessUi.isOpen(): boolean
	return window ~= nil and window.Visible == true
end

function BusinessUi.close()
	running += 1
	if window and window.Visible then
		window.Visible = false
		ask("close")
	end
	for _, courier in couriers do
		local row = courier.row
		if row and row.tween then
			row.tween:Cancel()
		end
	end
end

-- Opens the window (the server said so: the office computer was used).
function BusinessUi.open()
	build()
	if not hudOn() or not state then
		return
	end
	pcall(Hud.closeWindows)
	-- A window that cannot be closed from here (another module's) stays; one opened later closes this one.
	local othersBefore = otherWindowOpen()
	window.Visible = true
	openedAt = rootPosition()
	rowsKey = "" -- every courier gets a fresh, already running job
	if #radio == 0 then
		radioLine(`Dispatch: {tonumber(state.working) or 0} courier(s) on the road. Stay safe out there.`)
	end
	render()
	step()
	running += 1
	local mine = running
	task.spawn(function()
		while running == mine and window.Visible do
			task.wait(STEP)
			if running ~= mine then
				break
			end
			-- Walked away from the computer, another window, or the interface went off: close.
			local here = rootPosition()
			local away = here and openedAt and Vector3.new(here.X - openedAt.X, 0, here.Z - openedAt.Z).Magnitude > WALK_AWAY
			local others = otherWindowOpen()
			if away or not hudOn() or (others and not othersBefore) then
				BusinessUi.close()
				break
			end
			othersBefore = othersBefore and others
			step()
		end
	end)
end

-- Sets the GPS to the company's office (the welcome card).
function BusinessUi.gpsToOffice()
	local position: Vector3? = state and typeof(state.officePos) == "Vector3" and state.officePos or nil
	if not position then
		Hud.toast("Your office is in one of the towers: open the ESTATE list for the GPS.")
		return
	end
	local name = tostring(state.officeName or "Your office")
	MapView.setWaypoint(position)
	-- The HUD's guide (the circle, the beam, the waypoint) and "You are at ..." work from a landmark.
	pcall(MapView.onWaypoint, {
		id = tostring(state.office or "office"),
		name = name,
		icon = "🏢",
		x = position.X,
		z = position.Z,
		kind = "place",
		description = "Your company's office.",
	} :: any)
end

-- ── Welcome back ───────────────────────────────────────────────────────────

local welcomeToken = 0

local function showWelcome(info: any)
	build()
	if not hudOn() then
		pendingWelcome = info
		return
	end
	pendingWelcome = nil
	local amount = tonumber(info.amount) or 0
	if amount <= 0 then
		return
	end
	local seconds = tonumber(info.seconds) or 0
	local full = state and (tonumber(state.safe) or 0) >= (tonumber(state.safeCap) or B.SafeCap)
	refs.welcomeText.Text = `While you were away your company made <font color="#{C.money:ToHex()}">{Ui.money(amount)}</font>`
	refs.welcomeInfo.Text = `{duration(seconds)} away · it is in the safe at {tostring(state and state.officeName or "your office")}.{if full then " The safe is full!" else ""}`
	refs.welcomeGps.Visible = state ~= nil and typeof(state.officePos) == "Vector3"
	welcomeCard.Visible = true
	welcomeCard.Position = UDim2.new(0.5, 0, 0.5, -8)
	TweenService:Create(welcomeCard, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	welcomeToken += 1
	local mine = welcomeToken
	task.delay(WELCOME_SECONDS, function()
		if welcomeToken == mine and welcomeCard then
			welcomeCard.Visible = false
		end
	end)
end

-- ── The server's messages ──────────────────────────────────────────────────

local function onState(data: any)
	if type(data) ~= "table" then
		return
	end
	state = data
	receivedAt = os.clock()
	if type(data.money) == "number" then
		money = data.money
	end
	if data.open == true then
		BusinessUi.open()
	elseif BusinessUi.isOpen() then
		render()
		step()
	end
	if type(data.welcome) == "table" then
		showWelcome(data.welcome)
	end
end

function BusinessUi.start()
	build()
	getRemote().OnClientEvent:Connect(onState)
	-- Your money (for which buttons you can afford) comes with the usual state too.
	Net.get("State").OnClientEvent:Connect(function(data: any)
		if type(data) == "table" and type(data.money) == "number" then
			money = data.money
			if BusinessUi.isOpen() then
				render()
			end
		end
	end)
	-- The interface on and off (the start screen): close the window, show a waiting welcome after PLAY.
	task.spawn(function()
		local playerGui = player:WaitForChild("PlayerGui")
		local hud = playerGui:WaitForChild("ZombieDeliveryHud", 30)
		if hud and hud:IsA("ScreenGui") then
			hud:GetPropertyChangedSignal("Enabled"):Connect(function()
				if not hud.Enabled then
					BusinessUi.close()
					if welcomeCard then
						welcomeCard.Visible = false
					end
				elseif pendingWelcome then
					task.delay(1.5, function()
						if pendingWelcome then
							showWelcome(pendingWelcome)
						end
					end)
				end
			end)
		end
	end)
	-- Ready: the server sends the state (and the welcome-back, if the couriers made something while you were away).
	ask("sync")
end

return BusinessUi
