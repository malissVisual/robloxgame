--!strict
-- The admin panel (P or the small ADMIN button top right; only for players with the "Admin" attribute, see
-- server/Admin.luau, which checks every command again). One window with sections on the left: unlock, driver level &
-- money, cars, guns, teleport (every Map.Landmarks place), jobs (every special job and the ordinary tiers), enemies,
-- world (time of day: day and night, server/DayNight.luau) and player (god mode, heal, finish the stop). The answers
-- come back as toasts (the Notice remote), and in the window's title bar while it is open (the toasts are behind it).
-- While it is open the mouse is free (Main: CameraRig.mouseNeeded checks AdminPanel.isOpen()).

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
local Ui = require(script.Parent.Ui)

local C = Ui.Colors
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
	Ui.label(content, text, UDim2.new(1, -10, 0, 26), { LayoutOrder = nextOrder(), TextSize = 19, Font = Enum.Font.GothamBlack, TextColor3 = C.yellow })
	if hint then
		Ui.label(content, hint, UDim2.new(1, -10, 0, 0), {
			LayoutOrder = nextOrder(),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextSize = 14,
			Font = Enum.Font.GothamMedium,
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
	{ "world", "World" },
	{ "player", "Player" },
}

local render: () -> ()

local function renderUnlock()
	heading("Unlock", `Every car (the company ones too), every gun (the earned ones too), every paint, 10 of each item, every employer's jobs counted as done and driver level {Config.Levels.MaxLevel}. Car guns: Cars tab.`)
	local row = grid(200)
	action(row, "UNLOCK EVERYTHING", C.yellow, function()
		send("unlockAll")
	end).TextColor3 = Color3.new(0, 0, 0)
	action(row, "MAX UPGRADES", C.blue, function()
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
		local button = action(levels, `LV {n}`, if on then C.yellow else C.blue, function()
			send("setLevel", n)
		end)
		button.TextColor3 = if on then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
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
		local button = action(cells, def.name, if def.company then C.yellow else C.blue, function()
			send("car", def.id)
		end)
		if def.company then
			button.TextColor3 = Color3.new(0, 0, 0)
		end
	end
	heading("Car gun on your car", "The gun on the roof of the car you drive (van, pickup, muscle, monster, armored). Without one you shoot out of the window: pistol, revolver or SMG only.")
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
		local button = action(cells, def.name, if def.earned then C.yellow else C.blue, function()
			send("weapon", def.id)
		end)
		if def.earned then
			button.TextColor3 = Color3.new(0, 0, 0)
		end
	end
end

local KIND_COLORS: { [string]: Color3 } = {
	shop = C.blue,
	employer = Color3.fromRGB(200, 150, 30),
	place = Color3.fromRGB(150, 90, 200),
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
		end).TextColor3 = Color3.new(0, 0, 0)
	end
	heading("Ordinary deliveries", "A job-board delivery of that danger level, from here.")
	local ordinary = grid(150)
	local colors = { C.green, C.yellow, C.red, Color3.fromRGB(200, 80, 255) }
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
		local button = action(counts, `×{n}`, if on then C.yellow else C.grey, function()
			spawnCount = n
			render()
		end)
		button.TextColor3 = if on then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
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
		action(cells, def.name, if def.ranged then Color3.fromRGB(170, 70, 50) else Color3.fromRGB(90, 130, 70), function()
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
		action(cells, entry.label, if dark then Color3.fromRGB(60, 60, 110) elseif hour >= 7 and hour <= 17 then C.blue else Color3.fromRGB(150, 100, 70), function()
			send("time", hour)
		end)
	end
end

local function renderPlayer()
	local on = player:GetAttribute("God") == true
	heading("God mode", "You and your car take no damage (a car in the water is put back on the road).")
	local row = grid(200)
	local button = action(row, if on then "GOD MODE: ON" else "GOD MODE: OFF", if on then C.yellow else C.grey, function()
		send("god", not on)
	end)
	button.TextColor3 = if on then Color3.new(0, 0, 0) else Color3.new(1, 1, 1)
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
	world = renderWorld,
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
		button.BackgroundColor3 = if selected then C.yellow else C.panelLight
		button.TextColor3 = if selected then Color3.new(0, 0, 0) else C.text
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

	window = Ui.panel(gui, UDim2.fromOffset(760, 520), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	window.Visible = false
	window.BackgroundTransparency = 0.05
	scale = Ui.make("UIScale", {}, window)
	Ui.stroke(window, C.red, 2)
	Ui.label(window, "ADMIN", UDim2.new(0, 200, 0, 44), { Position = UDim2.fromOffset(18, 6), TextSize = 26, Font = Enum.Font.GothamBlack, TextColor3 = C.red })
	Ui.label(window, "testing tools · P", UDim2.new(1, -300, 0, 44), { Position = UDim2.fromOffset(130, 8), TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = C.dim })
	status = Ui.label(window, "", UDim2.new(1, -360, 0, 20), {
		Position = UDim2.fromOffset(300, 20),
		TextSize = 14,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.yellow,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local close = Ui.button(window, "X", UDim2.fromOffset(40, 40), C.red, function()
		setOpen(false)
	end)
	close.Position = UDim2.new(1, -50, 0, 8)

	local tabs = Ui.make("Frame", {
		Size = UDim2.new(0, 160, 1, -68),
		Position = UDim2.fromOffset(14, 56),
		BackgroundTransparency = 1,
	}, window)
	Ui.list(tabs, true, 6)
	for index, entry in SECTIONS do
		local id = entry[1]
		local button = Ui.button(tabs, entry[2], UDim2.new(1, 0, 0, 46), C.panelLight, function()
			section = id
			render()
		end)
		button.TextSize = 16
		button.LayoutOrder = index
		tabButtons[id] = button
	end

	content = Ui.make("ScrollingFrame", {
		Size = UDim2.new(1, -200, 1, -68),
		Position = UDim2.fromOffset(188, 56),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
	}, window)
	Ui.list(content, true, 8)

	-- The small button top right (under Roblox's own buttons).
	openButton = Ui.button(gui, "ADMIN", UDim2.fromOffset(90, 32), C.red, function()
		setOpen(not window.Visible)
	end)
	openButton.AnchorPoint = Vector2.new(1, 0)
	openButton.Position = UDim2.new(1, -16, 0, 56)
	openButton.TextSize = 15
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
