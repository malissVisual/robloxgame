--!strict
-- The admin panel (P or the small ADMIN button top right; only for players with the "Admin" attribute, see
-- server/Admin.luau, which checks every command again). One window with sections on the left: unlock, driver level &
-- money, cars, guns, teleport (every Map.Landmarks place), jobs (every special job and the ordinary tiers), enemies,
-- estate & company (give / take properties, the home, teleport to a property, the company's safe), world (time of
-- day: day and night, server/DayNight.luau), missions (start any of the 100, all at 3 stars, reset; shared/Missions.luau),
-- challenges (3.1: all done, every lost package found, start over, any title; server/Challenges.luau) and player (god mode, heal, finish the stop). The answers
-- come back as toasts (the Notice remote), and in the window's title bar while it is open (the toasts are behind it).
-- While it is open the mouse is free (Main: CameraRig.mouseNeeded checks AdminPanel.isOpen()).
-- 3.6 (Postage & Trouble): the lavender window (Ui.window) with the sections as a sidebar of tabs; the answers show in
-- its footer.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local MissionData = require(Shared.Missions)
local ChallengeData = require(Shared.Challenges)
local Ui = require(script.Parent.Ui)
local Theme = require(script.Parent.Theme)

local C = Ui.Colors
local P = Theme.Postage
local AdminPanel = {}

local player = Players.LocalPlayer
local remote: RemoteEvent? = nil

local gui: any = nil
local window: any = nil
local content: any = nil
local openButton: any = nil
local status: any = nil -- the last answer (Notice), shown in the title bar: the toasts are behind the window
local scale: any = nil
local tabButtons: { [string]: any } = {}
local section = "unlock"
local spawnCount = 1
local missionProgress: { [string]: number } = {} -- your best ratings (the Missions remote's "state"), for the colours
-- 3.1: your challenges' state (the Challenges remote's "state", asked when the Challenges tab opens).
local challengeState: { done: number, secrets: number, secretsTotal: number, visited: number, placesTotal: number, title: string?, titles: { [string]: boolean } } =
	{ done = 0, secrets = 0, secretsTotal = 0, visited = 0, placesTotal = 0, title = nil, titles = {} }

-- In a Studio Play test everybody is an admin (Config.Admin.InStudio): the panel opens even before the server's
-- "Admin" attribute arrives. The server checks every command again anyway.
local function isAdmin(): boolean
	return player:GetAttribute("Admin") == true or (Config.Admin.InStudio and RunService:IsStudio())
end

local function send(name: string, arg: any?)
	if not remote then
		remote = Net.get("Admin")
	end
	if remote then
		remote:FireServer(name, arg)
	end
end

-- ── Building blocks ────────────────────────────────────────────────────────

local order = 0
local function nextOrder(): number
	order += 1
	return order
end

local function heading(text: string, hint: string?)
	Ui.label(content, text, UDim2.new(1, -10, 0, 26), { LayoutOrder = nextOrder(), TextSize = 18, Font = Theme.DisplayFont, TextColor3 = C.text })
	if hint then
		Ui.label(content, hint, UDim2.new(1, -10, 0, 0), {
			LayoutOrder = nextOrder(),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 14,
			Font = Theme.Font,
			TextColor3 = C.dim,
		})
	end
end

-- A block of equal buttons that wraps.
local function grid(cellWidth: number): any
	local frame = Ui.make("Frame", {
		Size = UDim2.new(1, -10, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
	}, content)
	Ui.make("UIGridLayout", {
		CellSize = UDim2.fromOffset(cellWidth, 40),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, frame)
	return frame
end

local function action(parent: any, text: string, color: Color3, onClick: () -> ()): any
	local button = Ui.button(parent, text, UDim2.fromOffset(150, 40), color, onClick)
	button.TextSize = 15
	button.TextWrapped = true
	button.LayoutOrder = nextOrder()
	return button
end

-- ── Sections ───────────────────────────────────────────────────────────────

local SECTIONS = {
	{ "unlock", "Unlock, level, $" },
	{ "cars", "Cars" },
	{ "guns", "Guns" },
	{ "teleport", "Teleport" },
	{ "jobs", "Jobs" },
	{ "enemies", "Enemies" },
	{ "estate", "Estate, company" },
	{ "world", "World" },
	{ "missions", "Missions" },
	{ "challenges", "Challenges, secrets" },
	{ "player", "Player" },
}

local render: () -> ()

local function renderUnlock()
	heading("Unlock", `Every car (the company ones too), every gun (the earned ones too), every paint, 10 of each item, every employer's jobs counted as done, every owned car's upgrades and stages maxed and driver level {Config.Levels.MaxLevel}. Car guns: Cars tab.`)
	local row = grid(200)
	action(row, "UNLOCK EVERYTHING", C.yellow, function()
		send("unlockAll")
	end)
	action(row, "MAX UPGRADES + STAGES", C.blue, function()
		send("maxUpgrades")
	end)
	local level = tonumber(player:GetAttribute("Level")) or 1
	heading(`Driver level: {level} · {Levels.rank(level)}`, "Sets the XP to exactly what the level needs. The levels unlock the danger levels on the job board, special jobs, cars, guns and car guns.")
	local levels = grid(80)
	local picks: { number } = {}
	for _, n in { 1, 2, 3, 4, 5, 6, 8, 10, 12 } do
		if n < Config.Levels.MaxLevel then
			table.insert(picks, n)
		end
	end
	table.insert(picks, Config.Levels.MaxLevel)
	for _, n in picks do
		local on = n == level
		action(levels, `LV {n}`, if on then C.yellow else C.blue, function()
			send("setLevel", n)
		end)
	end
	local steps = grid(150)
	action(steps, "LEVEL -1", C.grey, function()
		send("setLevel", math.max(1, level - 1))
	end)
	action(steps, "LEVEL +1", C.green, function()
		send("setLevel", math.min(Config.Levels.MaxLevel, level + 1))
	end)
	heading("Money")
	local amounts = grid(150)
	for _, amount in { 1_000, 10_000, 100_000, 1_000_000 } do
		action(amounts, "+" .. Ui.money(amount), C.green, function()
			send("money", amount)
		end)
	end
end

local function renderCars()
	heading("Spawn a car", "It comes right now on the road next to you (yellow = an employer's company vehicle).")
	local cells = grid(150)
	for _, def in Config.Cars do
		action(cells, def.name, if def.company then C.yellow else C.blue, function()
			send("car", def.id)
		end)
	end
	heading("Car gun on your car", "The gun on the roof of the car you drive (every dealer car, the monster truck, the armored truck). Without one you shoot out of the window: pistol, revolver or SMG only.")
	local gunCells = grid(150)
	action(gunCells, "No car gun", C.red, function()
		send("carGun", "none")
	end)
	for _, def in Config.CarGuns do
		action(gunCells, def.name, C.blue, function()
			send("carGun", def.id)
		end)
	end
end

local function renderGuns()
	heading("Give a gun", "You get it and it goes straight into your hand (yellow = earned from an employer).")
	local cells = grid(150)
	for _, def in Config.Weapons do
		action(cells, def.name, if def.earned then C.yellow else C.blue, function()
			send("weapon", def.id)
		end)
	end
end

local KIND_COLORS: { [string]: Color3 } = {
	shop = C.blue,
	employer = P.gold,
	place = P.violet,
}

local function renderTeleport()
	heading("Teleport", "To the road at the place. If you are driving, your car comes along.")
	local cells = grid(232)
	for _, landmark in Map.Landmarks do
		local button = action(cells, `{landmark.icon} {landmark.name}`, KIND_COLORS[landmark.kind] or C.grey, function()
			send("teleport", landmark.id)
		end)
		button.TextXAlignment = Enum.TextXAlignment.Left
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6) }, button)
	end
end

local function renderJobs()
	heading("Special jobs", "Starts it now with its vehicle (a running job is cancelled).")
	local special = grid(150)
	for _, def in Config.JobTypes do
		action(special, def.name, C.yellow, function()
			send("job", def.id)
		end)
	end
	heading("Ordinary deliveries", "A job-board delivery of that danger level, from here.")
	local ordinary = grid(150)
	local colors = { C.green, C.yellow, C.red, P.violet }
	for index, tier in Config.Jobs.Tiers do
		action(ordinary, `{string.rep("★", tier.stars)} {tier.name}`, colors[index] or C.grey, function()
			send("job", `ordinary{index}`)
		end)
	end
	heading("Testing")
	local testing = grid(200)
	action(testing, "FINISH THIS STOP", C.green, function()
		send("finishStop")
	end)
end

local function renderEnemies()
	heading("How many", nil)
	local counts = grid(80)
	for _, n in { 1, 3, 5, 10 } do
		local on = spawnCount == n
		action(counts, `×{n}`, if on then C.yellow else C.grey, function()
			spawnCount = n
			render()
		end)
	end
	heading("Spawn near you", "On the roads 30-70 studs away (they burn in the safe zone).")
	local kinds = {}
	for kind in Config.Zombies do
		table.insert(kinds, kind)
	end
	table.sort(kinds, function(a, b)
		return Config.Zombies[a].health < Config.Zombies[b].health
	end)
	local cells = grid(150)
	for _, kind in kinds do
		local def = Config.Zombies[kind]
		action(cells, def.name, if def.ranged then C.red else C.green, function()
			send("spawn", { kind = kind, count = spawnCount })
		end)
	end
	heading("Bandit cars and cleaning up")
	local other = grid(200)
	action(other, "BANDIT CAR", C.red, function()
		send("banditCar")
	end)
	action(other, "CLEAR ENEMIES", C.grey, function()
		send("clear")
	end)
end

-- The real estate (Config.Estate) and the company's safe (Config.Business). The player attributes Estates
-- ("id,id,…") and Home (server/Estate.luau) mark what you own: yellow = your home, green = owned.
local ESTATE_KINDS = { mansion = "🏰", villa = "🏡", house = "🏠", garage = "🅿️", office = "🏢" }

local function renderEstate()
	local owned: { [string]: boolean } = {}
	local list = player:GetAttribute("Estates")
	if type(list) == "string" then
		for id in string.gmatch(list, "[^,]+") do
			owned[id] = true
		end
	end
	local home = player:GetAttribute("Home")
	local slots = tonumber(player:GetAttribute("CarSlots")) or Config.Estate.BaseCarSlots
	heading("Real estate", `Homes, garages and offices for free (green = yours, yellow = your home). Car slots now: {slots}. Players open the list with H or the ESTATE button.`)
	local all = grid(200)
	action(all, "GIVE EVERY PROPERTY", C.yellow, function()
		send("giveEstate", "all")
	end)
	action(all, "TAKE THEM ALL AWAY", C.red, function()
		send("clearEstate")
	end)
	action(all, "SPAWN AT THE DEPOT", C.grey, function()
		send("setHome", "depot")
	end)
	heading("Give a property", "Click: it is yours (no money). A first home becomes your home.")
	local cells = grid(232)
	for _, def in Config.Estate.Properties do
		local mine = owned[def.id] == true
		local color = if home == def.id then C.yellow elseif mine then C.green else C.blue
		local button = action(cells, `{ESTATE_KINDS[def.kind] or "🏠"} {def.name}`, color, function()
			send("giveEstate", def.id)
		end)
		button.TextXAlignment = Enum.TextXAlignment.Left
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6) }, button)
	end
	heading("Set the home", "You spawn there after every death (and after PLAY). It is given first if you do not own it.")
	local homes = grid(232)
	for _, def in Config.Estate.Properties do
		if def.kind == "mansion" or def.kind == "villa" or def.kind == "house" then
			local on = home == def.id
			action(homes, `{if on then "★ " else ""}{def.name}`, if on then C.yellow else C.panelLight, function()
				send("setHome", def.id)
			end)
		end
	end
	heading("Teleport to a property", "Inside at its door (homes, offices), else the road at its plot.")
	local places = grid(232)
	for _, def in Config.Estate.Properties do
		local button = action(places, `{ESTATE_KINDS[def.kind] or "🏠"} {def.name}`, P.violet, function()
			send("estateTeleport", def.id)
		end)
		button.TextXAlignment = Enum.TextXAlignment.Left
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6) }, button)
	end
	heading("Company safe", `Your company's earnings wait in the safe (up to {Ui.money(Config.Business.SafeCap)}) until you COLLECT them at the office computer.`)
	local safe = grid(200)
	action(safe, "FILL THE SAFE", C.green, function()
		send("businessCash")
	end)
	action(safe, "+" .. Ui.money(50_000), C.green, function()
		send("businessCash", 50_000)
	end)
	action(safe, "EMPTY THE SAFE", C.grey, function()
		send("businessCash", -Config.Business.SafeCap)
	end)
end

local function renderWorld()
	local night = Config.DayNight
	heading("Time of day", string.format("The clock runs (a day is %d min). Night from %02d:%02d to %02d:%02d: dark, more zombies, bigger waves, better pay, the lamps and headlights on.", math.floor(night.DayLength / 60), math.floor(night.NightFrom), math.floor(night.NightFrom % 1 * 60), math.floor(night.NightTo), math.floor(night.NightTo % 1 * 60)))
	local cells = grid(150)
	local times: { { hour: number, label: string } } = {
		{ hour = 0, label = "00:00 Midnight" },
		{ hour = 5.5, label = "05:30 Dawn" },
		{ hour = 9, label = "09:00 Morning" },
		{ hour = 12, label = "12:00 Noon" },
		{ hour = 15, label = "15:00 Afternoon" },
		{ hour = 17.75, label = "17:45 Dusk" },
		{ hour = 20, label = "20:00 Evening" },
		{ hour = 22, label = "22:00 Night" },
	}
	for _, entry in times do
		local hour = entry.hour
		local dark = hour >= night.NightFrom or hour < night.NightTo
		action(cells, entry.label, if dark then P.violet elseif hour >= 7 and hour <= 17 then C.blue else P.bronze, function()
			send("time", hour)
		end)
	end
end

-- The missions (shared/Missions.luau): start any one now (locks ignored), every one at 3 stars, or start over.
-- Done ones show their best rating (green), 👥 = co-op, then the twist icons.
local function renderMissions()
	local got, most = MissionData.stars(missionProgress, nil)
	heading(`Missions · {got} / {most} ★`, "Players open the MISSIONS window with U. Here: everything done at 3 stars (no money; UNLOCK EVERYTHING does it too), or the progress cleared to play the campaigns again.")
	local row = grid(200)
	action(row, "ALL MISSIONS 3 ★", C.yellow, function()
		send("missionsAll")
	end)
	action(row, "RESET MISSIONS", C.red, function()
		send("missionsReset")
	end)
	for _, campaign in MissionData.Campaigns do
		local done = MissionData.done(missionProgress, campaign.id)
		local rgb = campaign.color
		local color = Color3.fromRGB(rgb[1] or 200, rgb[2] or 200, rgb[3] or 200)
		heading(`{campaign.icon} {campaign.name} · LV {campaign.level} · {done}/10`, `{campaign.client}. Click a mission: it starts now (a running job is cancelled; NIGHT ONLY turns the clock to night).`)
		local cells = grid(232)
		for _, def in MissionData.ofCampaign(campaign.id) do
			local best = missionProgress[def.id] or 0
			local twists = ""
			local twistList: { string } = def.twists or {}
			for _, twist in twistList do
				local info = Config.Missions.Twists[twist]
				twists ..= if info then info.icon else ""
			end
			local mark = if best > 0 then " " .. string.rep("★", best) else ""
			local button = action(cells, `{def.number}. {def.name}{if def.coop then " 👥" else ""} {twists}{mark}`, if best > 0 then C.green else C.panelLight, function()
				send("missionStart", def.id)
			end)
			button.TextXAlignment = Enum.TextXAlignment.Left
			-- The campaign's colour on the button's own border (one UIStroke per button).
			local border = button:FindFirstChildOfClass("UIStroke")
			if border then
				border.Color = color
				border.Thickness = 1.5
			end
			Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6) }, button)
		end
	end
end

-- 3.1, the challenges (shared/Challenges.luau): all done, every secret package found, start over, any title.
local function renderChallenges()
	local state = challengeState
	heading(
		`Challenges · {state.done} / {#ChallengeData.List} · secrets {state.secrets} / {state.secretsTotal} · places {state.visited} / {state.placesTotal}`,
		"Players see them in the MISSIONS window (U): CHALLENGES, SECRETS, REWARDS. ALL CHALLENGES gives every challenge's money and title, every campaign's reward and Dead End. RESET takes the exclusive guns and paints back too."
	)
	local row = grid(200)
	action(row, "ALL CHALLENGES", C.yellow, function()
		send("challengesAll")
	end)
	action(row, "ALL SECRETS FOUND", C.blue, function()
		send("secretsAll")
	end)
	action(row, "RESET CHALLENGES", C.red, function()
		send("challengesReset")
	end)
	heading(`Title: {state.title or "none"}`, "Given and shown over your head and on the leaderboard (TOP).")
	local titles = grid(232)
	action(titles, "NO TITLE", if state.title == nil then C.yellow else C.grey, function()
		send("title", "none")
	end)
	for _, title in ChallengeData.allTitles() do
		local on = state.title == title
		action(titles, title, if on then C.yellow elseif state.titles[title] then C.green else C.panelLight, function()
			send("title", title)
		end)
	end
end

local function renderPlayer()
	local on = player:GetAttribute("God") == true
	heading("God mode", "You and your car take no damage (a car in the water is put back on the road).")
	local row = grid(200)
	action(row, if on then "GOD MODE: ON" else "GOD MODE: OFF", if on then C.yellow else C.grey, function()
		send("god", not on)
	end)
	heading("Quick")
	local quick = grid(200)
	action(quick, "HEAL ME AND MY CAR", C.green, function()
		send("heal")
	end)
	action(quick, "FINISH THIS STOP", C.blue, function()
		send("finishStop")
	end)
end

local RENDERERS: { [string]: () -> () } = {
	unlock = renderUnlock,
	cars = renderCars,
	guns = renderGuns,
	teleport = renderTeleport,
	jobs = renderJobs,
	enemies = renderEnemies,
	estate = renderEstate,
	world = renderWorld,
	missions = renderMissions,
	challenges = renderChallenges,
	player = renderPlayer,
}

render = function()
	if not content then
		return
	end
	Ui.clear(content)
	order = 0
	for id, button in tabButtons do
		local selected = id == section
		-- The concept's filter tabs: the selected one cream paper, the others lavender.
		button.BackgroundColor3 = if selected then P.ticket else P.lavenderDeep
		button.TextColor3 = if selected then C.text else C.dim
	end
	local renderer = RENDERERS[section]
	if renderer then
		renderer()
	end
end

-- ── The window ─────────────────────────────────────────────────────────────

local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera or not scale then
		return
	end
	local size = camera.ViewportSize
	scale.Scale = math.clamp(math.min(size.X / 1150, size.Y / 680), 0.55, 1.1)
end

local function setOpen(open: boolean)
	if not window then
		return
	end
	window.Visible = open and isAdmin()
	if window.Visible then
		render()
	end
end

local function build()
	gui = Ui.make("ScreenGui", {
		Name = "ZombieDeliveryAdmin",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	}, player:WaitForChild("PlayerGui"))

	local inner, chrome
	window, inner, chrome = Ui.window(gui, "Admin", "Testing tools · only admins see this · P", "🛠", UDim2.fromOffset(780, 580))
	window.Visible = false
	chrome.onClose = function()
		setOpen(false)
	end
	-- The admin's badge is rose: these buttons change the game.
	local badge = chrome.icon.Parent
	if badge and badge:IsA("Frame") then
		badge.BackgroundColor3 = P.rose
	end
	scale = Ui.make("UIScale", {}, window)
	-- The server's last answer, in the footer (the toasts are behind the window).
	status = chrome.context
	status.TextColor3 = C.text

	-- The sections: a lavender sidebar of tabs (the Dispatch board's filters).
	local sidebar = Ui.make("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 190, 1, 0),
		BackgroundColor3 = P.lavenderDeep,
		BorderSizePixel = 0,
	}, inner)
	local tabs = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, -20),
		Position = UDim2.fromOffset(14, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, sidebar)
	Ui.list(tabs, true, 6)
	for index, entry in SECTIONS do
		local id = entry[1]
		local button = Ui.button(tabs, entry[2], UDim2.new(1, -4, 0, 34), P.lavenderDeep, function()
			section = id
			render()
			if id == "missions" then
				Net.get("Missions"):FireServer("open")
			elseif id == "challenges" then
				Net.get("Challenges"):FireServer("open")
			end
		end)
		button.TextSize = 15
		button.TextXAlignment = Enum.TextXAlignment.Left
		Ui.make("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 8) }, button)
		button.LayoutOrder = index
		tabButtons[id] = button
	end

	content = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -220, 1, -24),
		Position = UDim2.fromOffset(208, 12),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = P.ink2,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, inner)
	Ui.list(content, true, 8)
	Ui.make("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10), PaddingRight = UDim.new(0, 8) }, content)

	-- The small button top right (under Roblox's own buttons).
	-- A quiet rose pill (only admins see it), the red is just its edge and text.
	openButton = Ui.button(gui, "🛠  ADMIN", UDim2.fromOffset(96, 32), C.red, function()
		setOpen(not window.Visible)
	end)
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -16, 0, 56)
	openButton.TextSize = 13
	openButton.TextColor3 = C.red
	openButton.Visible = false
	Ui.make("UIScale", {}, openButton)
end

-- The ADMIN button shows for admins once the game's interface is on (after PLAY on the start screen).
local function refreshButton()
	if not openButton then
		return
	end
	local playerGui = player:FindFirstChild("PlayerGui")
	local hud = playerGui and playerGui:FindFirstChild("ZombieDeliveryHud")
	local hudOn = not (hud and hud:IsA("ScreenGui")) or hud.Enabled
	openButton.Visible = isAdmin() and hudOn
	if not isAdmin() and window and window.Visible then
		window.Visible = false
	end
end

function AdminPanel.start()
	build()
	updateScale()
	local stamp = 0
	Net.get("Notice").OnClientEvent:Connect(function(text: any)
		if not status then
			return
		end
		stamp += 1
		local mine = stamp
		status.Text = tostring(text)
		task.delay(4, function()
			if stamp == mine then
				status.Text = ""
			end
		end)
	end)
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	player:GetAttributeChangedSignal("Admin"):Connect(refreshButton)
	player:GetAttributeChangedSignal("God"):Connect(function()
		if window.Visible and section == "player" then
			render()
		end
	end)
	-- Your mission ratings (the same "state" the MISSIONS window gets), asked when the Missions tab opens.
	Net.get("Missions").OnClientEvent:Connect(function(kind: any, state: any)
		if kind ~= "state" or type(state) ~= "table" or type(state.progress) ~= "table" then
			return
		end
		missionProgress = {}
		for id, stars in state.progress do
			if type(id) == "string" and type(stars) == "number" then
				missionProgress[id] = stars
			end
		end
		if window.Visible and section == "missions" then
			render()
		end
	end)
	-- 3.1: your challenges' state (the same "state" the MISSIONS window's tabs get).
	Net.get("Challenges").OnClientEvent:Connect(function(kind: any, state: any)
		if kind ~= "state" or type(state) ~= "table" then
			return
		end
		local function size(set: any): number
			local n = 0
			if type(set) == "table" then
				for _ in set do
					n += 1
				end
			end
			return n
		end
		local titles: { [string]: boolean } = {}
		if type(state.titles) == "table" then
			for title, on in state.titles do
				if type(title) == "string" and on then
					titles[title] = true
				end
			end
		end
		challengeState = {
			done = size(state.done),
			secrets = size(state.secrets),
			secretsTotal = tonumber(state.secretsTotal) or 0,
			visited = size(state.visited),
			placesTotal = tonumber(state.placesTotal) or 0,
			title = if type(state.title) == "string" then state.title else nil,
			titles = titles,
		}
		if window.Visible and section == "challenges" then
			render()
		end
	end)
	for _, name in { "Estates", "Home", "CarSlots" } do
		player:GetAttributeChangedSignal(name):Connect(function()
			if window.Visible and section == "estate" then
				render()
			end
		end)
	end
	player:GetAttributeChangedSignal("Level"):Connect(function()
		if window.Visible and section == "unlock" then
			render()
		end
	end)
	local playerGui = player:WaitForChild("PlayerGui")
	local hud = playerGui:FindFirstChild("ZombieDeliveryHud")
	if hud and hud:IsA("ScreenGui") then
		hud:GetPropertyChangedSignal("Enabled"):Connect(refreshButton)
	end
	refreshButton()

	-- P opens and closes the panel (not while typing in a text box, e.g. the chat). Bound at a high priority, so no
	-- other binding of the game or of Roblox can swallow it.
	ContextActionService:BindActionAtPriority("ZombieDeliveryAdmin", function(_name, state, _input)
		if state ~= Enum.UserInputState.Begin or UserInputService:GetFocusedTextBox() then
			return Enum.ContextActionResult.Pass
		end
		if isAdmin() then
			setOpen(not window.Visible)
			print(`[AdminPanel] P: the panel is {if window.Visible then "open" else "closed"}`)
			return Enum.ContextActionResult.Sink
		end
		warn("[AdminPanel] P pressed, but you are not an admin (Config.Admin)")
		return Enum.ContextActionResult.Pass
	end, false, Enum.ContextActionPriority.High.Value + 100, Enum.KeyCode.P)
	print(`[AdminPanel] ready: press P (admin: {isAdmin()})`)
end

function AdminPanel.isOpen(): boolean
	return window ~= nil and window.Visible == true
end

return AdminPanel
