--!strict
-- Zombie Delivery (Deliveros): the client. The start screen first; PLAY starts the interface. 10.5 (the owner: "only
-- the sandbox is the game now"): the lobby, the runs, your warehouse; the old city game is gone (in git's history up
-- to 10.4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)
local Config = require(Shared.Config)

local Client = script.Parent

-- Every part starts on its own: one that fails (see the Output) does not take the others down.
local function safely(name: string, start: () -> ())
	local ok, err = pcall(function()
		start()
	end)
	if not ok then
		warn(`[Client] {name} failed to start: {err}`)
	end
end

-- 8.0 SANDBOX: one house to empty, your walk-in Sprinter van, your ZDC warehouse where the pieces go on show. Started:
--   walking, the camera and the body   Drive, CameraRig, ArmPose, Stamina, CarBoarding, GaitPose, BodyLife, Unstuck,
--                                      CurbRide
--   the cars                           CarVisuals, CarSway, TyreFx, CrashFx
--   the sounds, the admin              Sounds; AdminPanel, AdminFly, PerfOverlay (the panel's performance overlay)
--   the move's horde                   ZombieAnimator, ZombieLife, ZombieFx, EnemyOutline
--   the moves                          MovingHud (its story cards and the door's fade: MoveStoryUi, Fade, no start of
--                                      their own), MoveHelperHud, DannyBubble (8.6: what Danny does, over his head),
--                                      MoveLobbyUi, QuickChat, CarryGripUi, and CrewPanel (the planning's + INVITE: a
--                                      move's crew is server/Crew.luau's)
--   the HUD                            Hud (the city's parts hidden: client/Hud.luau ── Sandbox ──) and KeyHints (the
--                                      move's keys and the car's only)
--   the sandbox's own                  SandboxHud (the money, the income, the stock), WarehouseUi (the stands' picker),
--                                      SandboxGuide, 8.1's UpgradeUi (the UPGRADES desk's window), 8.2's
--                                      CollectionBookUi (the collection book), SandboxTasksUi (the TASKS chip and
--                                      panel), 8.3's MoveHelperCard (Danny's command card: a window too), 8.5's
--                                      DannyOrders (Danny's clipboard, orders mode: no window), OfferCard (a showroom
--                                      visitor's offer: a window too; 8.7: a player's offer too), VanPaintUi (the PAINT
--                                      shop's window), 8.7's TradeUi (trading between players: the offer composer,
--                                      the FOR SALE price picker, the buy question; a window too, the STOCK list's 🏷
--                                      opens its picker and closing that goes back to the list) and 8.8's AuctionUi (the
--                                      Auction House's window: it starts nothing while Config.Auction.On is false),
--                                      8.9's VillageTraffic (the D5's cars, this screen's only), 9.1's DrivePedals (GAS
--                                      and BRAKE while you drive: a touch screen's driving buttons, a computer's feet),
--                                      9.x's LootOutline and LootStars (the loot's coloured outlines, its stars and
--                                      its toasts; the stars step aside under a window), 10.x's SandboxMapUi (the big
--                                      map, M: a window too, its 🗺 MAP chip), SandboxMiniMap (a run's corner map: it
--                                      steps aside under a window), 10.1's CrewUi (the CREW window: a window too; the
--                                      ring over a helper down in a run) and 10.4's RideUi (the van's ride to a run's
--                                      house and back, over the jump's fade: no window):
--                                      each started only when it is there; 8.7's TradePrompts (the trade prompts on
--                                      your own stands hidden, a big sale's chat line) next to CargoPrompts
-- 8.5.1: Studio kept old scripts after a sync? This side's stamp (client/BuildStamp.luau) against the shared Config's
-- version and the server's stamp (workspace "ServerBuild"); different: a warning, and in Studio a red banner that says
-- what to delete before syncing again.
task.defer(function()
	local ok, err = pcall(function(): boolean
		local stamp = Client:FindFirstChild("BuildStamp")
		if not stamp then
			return false
		end
		local loaded, built = pcall(require, stamp :: ModuleScript)
		if not loaded or type(built) ~= "string" then
			return false
		end
		local server = workspace:GetAttribute("ServerBuild")
		local waited = 0
		while server == nil and waited < 15 do
			task.wait(0.5)
			waited += 0.5
			server = workspace:GetAttribute("ServerBuild")
		end
		local parts = {}
		if built ~= Config.Version then
			table.insert(parts, `ReplicatedStorage.Shared (Config) is {Config.Version}`)
		end
		if type(server) == "string" and server ~= built then
			table.insert(parts, `the server's scripts are {server}`)
		end
		if #parts == 0 then
			return false
		end
		local text = `STUDIO HAS A MIX OF OLD AND NEW SCRIPTS: the client's are {built}, {table.concat(parts, ", ")}. Fix: Stop, Rojo Disconnect, delete ReplicatedStorage > Shared, ServerScriptService > Server and StarterPlayer > StarterPlayerScripts > Client, then Rojo Connect and Play.`
		warn(`[Client] {text}`)
		if not game:GetService("RunService"):IsStudio() then
			return false
		end
		local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui", 10)
		if not playerGui then
			return false
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "StaleScripts"
		gui.DisplayOrder = 100
		gui.ResetOnSpawn = false
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 0, 8)
		label.Size = UDim2.new(0.9, 0, 0, 96)
		label.BackgroundColor3 = Color3.fromRGB(150, 20, 20)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextWrapped = true
		label.Text = text
		label.Parent = gui
		gui.Parent = playerGui
		return true
	end)
	if not ok then
		warn(`[Client] the version check failed: {err}`)
	end
end)

local Hud = require(Client.Hud)
local Menu = require(Client.Menu)
local Drive = require(Client.Drive)
local CameraRig = require(Client.CameraRig)
local AdminPanel = require(Client.AdminPanel)
local Sounds = require(Client.Sounds)
local MovingHud = require(Client.MovingHud)
local QuickChat = require(Client.QuickChat)
local KeyHints = require(Client.KeyHints)
local PerfOverlay = require(Client.PerfOverlay)
-- The sandbox's own modules (other workers write them at the same time): only when they are there, and one that
-- fails to load is skipped with a warning.
local own: { { name: string, module: any } } = {}
for _, name in { "SandboxHud", "WarehouseUi", "SandboxGuide", "UpgradeUi", "CollectionBookUi", "SandboxTasksUi", "MoveHelperCard", "DannyOrders", "OfferCard", "VanPaintUi", "TradeUi", "AuctionUi", "VillageTraffic", "DrivePedals", "RunUi", "LootOutline", "LootStars", "RunDangerUi", "SandboxMapUi", "SandboxMiniMap", "CrewUi", "RideUi" } do -- (10.4: the ride to a run's house and back, RideUi; 8.1: the UPGRADES desk's window; 8.2: the collection book, the TASKS panel; 8.3: Danny's command card, a visitor's offer, the PAINT shop; 8.5: Danny's clipboard, orders mode; 8.7: trading between players; 8.8: the Auction House's window, only while Config.Auction.On; 8.9: the D5's cars, Jinočany; 9.1: the drive pedals; 9.x loot: the outlines, the stars and the toasts; 10.x the map: the big map (M) and a run's minimap, after the TASKS chip its 🗺 MAP chip stands beside)
	local found = Client:FindFirstChild(name)
	if found and found:IsA("ModuleScript") then
		local ok, module = pcall(function(): any
			return require(found) :: any
		end)
		if ok and type(module) == "table" then
			table.insert(own, { name = name, module = module })
		else
			warn(`[Client] {name} did not load: {module}`)
		end
	end
end
local function ownModule(name: string): any
	for _, entry in own do
		if entry.name == name then
			return entry.module
		end
	end
	return nil
end
local WarehouseUi = ownModule("WarehouseUi")
local UpgradeUi = ownModule("UpgradeUi")
local BookUi = ownModule("CollectionBookUi") -- (8.2: the collection book and the TASKS panel, windows like the others)
local TasksUi = ownModule("SandboxTasksUi")
local DannyCard = ownModule("MoveHelperCard") -- (8.3: Danny's command card, a window like the others)
local OfferCard = ownModule("OfferCard") -- (8.3: a showroom visitor's offer, a window like the others)
local PaintUi = ownModule("VanPaintUi") -- (8.3: the PAINT shop's window)
local TradeUi = ownModule("TradeUi") -- (8.7: trading between players: the composer, the price picker, the buy question)
local AuctionUi = ownModule("AuctionUi") -- (8.8: the Auction House's window: the live lot, the consign picker, the results)
local MapUi = ownModule("SandboxMapUi") -- (10.x the big map: a window like the others)
local windows = { WarehouseUi, UpgradeUi, BookUi, TasksUi, DannyCard, OfferCard, PaintUi, TradeUi, AuctionUi, ownModule("RunUi"), MapUi, ownModule("CrewUi") } -- (9.7: a run's results card; 10.x: the map; 10.1: the CREW window)

safely("Drive", Drive.start)
safely("ZombieAnimator", require(Client.ZombieAnimator).start)
safely("CarVisuals", require(Client.CarVisuals).start)
safely("Hud", Hud.start)
safely("CameraRig", CameraRig.start)
safely("ArmPose", require(Client.ArmPose).start)
safely("AdminPanel", AdminPanel.start)
safely("AdminFly", require(Client.AdminFly).start)
safely("Sounds", Sounds.start)
safely("Stamina", require(Client.Stamina).start)
safely("CarBoarding", require(Client.CarBoarding).start)
safely("GaitPose", require(Client.GaitPose).start)
safely("BodyLife", require(Client.BodyLife).start)
safely("KeyHints", function()
	task.spawn(KeyHints.start)
end)
safely("Unstuck", require(Client.Unstuck).start)
safely("CurbRide", require(Client.CurbRide).start)
safely("PerfOverlay", PerfOverlay.start)
safely("EnemyOutline", require(Client.EnemyOutline).start)
safely("ZombieLife", require(Client.ZombieLife).start)
safely("ZombieFx", require(Client.ZombieFx).start)
safely("CarSway", require(Client.CarSway).start)
safely("TyreFx", require(Client.TyreFx).start)
safely("CrashFx", require(Client.CrashFx).start)
safely("MovingHud", MovingHud.start)
safely("MoveHelperHud", require(Client.MoveHelperHud).start)
safely("DannyBubble", require(Client.DannyBubble).start) -- 8.6: what Danny does, over his head (his move's crew only)
safely("QuickChat", QuickChat.start)
safely("CarryGripUi", require(Client.CarryGripUi).start)
safely("WalkDoors", require(Client.WalkDoors).start) -- 8.3: the doors' leaves swing, the trip's camera behind you
-- (8.0 merge: the moves' and the warehouse stands' prompts are their owner's: the others' hidden, as in the city)
safely("CargoPrompts", require(Client.CargoPrompts).start)
safely("TradePrompts", require(Client.TradePrompts).start) -- 8.7: the trade prompts on your own stands hidden; a big sale's chat line
for _, entry in own do
	local start = entry.module.start
	if type(start) == "function" then
		safely(entry.name, start)
	end
end
safely("SandboxSounds", function() require(Client.SandboxSounds).start() end) -- 8.1: the stands, the till, the van's doors
safely("SandboxLight", function() require(Client.SandboxLight).start() end) -- 8.3: the eyes adapt to the house, the hall, the van

-- The hooks (the city's, less what the sandbox does not run).
Drive.notify = Hud.toast
Sounds.notify = Hud.toast
AdminPanel.onPerformance = PerfOverlay.toggle
AdminPanel.performanceOn = PerfOverlay.isOn
QuickChat.covered = MovingHud.isOpen
-- Is a sandbox window open (the warehouse's picker, 8.1's UPGRADES desk: module.isOpen, when it has one)?
local function ownOpen(module: any): boolean
	local isOpen = module and module.isOpen
	if type(isOpen) ~= "function" then
		return false
	end
	local ok, open = pcall(isOpen)
	return ok and open == true
end
local function ownClose(module: any)
	local close = module and module.close
	if type(close) == "function" then
		pcall(close)
	end
end
-- One window at a time; ESC closes them all (the crew panel, the move's cards and list, the quick chat's ring, the
-- planning folds to its pill, the warehouse's picker, the UPGRADES window, the collection book, the TASKS panel,
-- 8.3: Danny's command card). `keep`: the sandbox window opening now
-- (its onOpen runs once it counts as open, so it must not close itself).
-- 8.3 review: a visitor's offer is declined only by ESC (the Roblox menu: Hud.escaping); another window opening (STOCK,
-- the BOOK to compare prices …) only hides it (OfferCard.hide): it waits and comes back once nothing covers the screen.
local keep: any = nil
Hud.onCloseWindows = function()
	MovingHud.closeAll()
	QuickChat.close(false)
	for _, module in windows do
		if module == keep then
			continue
		end
		local hide = if module == OfferCard and not Hud.escaping then module.hide else nil
		if type(hide) == "function" then
			pcall(hide)
		else
			ownClose(module)
		end
	end
end
for _, module in windows do -- (8.1 review: opening one closes the others)
	if type(module) == "table" then
		module.onOpen = function()
			keep = module
			pcall(Hud.closeWindows)
			keep = nil
		end
	end
end
CameraRig.windowOpen = function(): boolean
	return AdminPanel.isOpen() or MovingHud.isOpen()
		or QuickChat.isOpen() or ownOpen(WarehouseUi) or ownOpen(UpgradeUi) or ownOpen(BookUi) or ownOpen(TasksUi) or ownOpen(DannyCard) or ownOpen(PaintUi)
		or ownOpen(OfferCard) or ownOpen(TradeUi) or ownOpen(AuctionUi) or ownOpen(windows[10]) or ownOpen(MapUi) or ownOpen(windows[12])
end
CameraRig.mouseNeeded = CameraRig.windowOpen
-- 9.0 (the owner: "aiming with the crosshair only when I want to shoot or have pistols; the mouse normally free, so
-- no Alt"): the cursor is free (the right mouse held turns the camera) unless a weapon is in the hands, a Tool
-- equipped (no guns here yet: CameraRig's toolEquipped); Alt does nothing, no MOUSE [ALT] (Hud's view.sandbox)
CameraRig.aimOnly = true
CameraRig.armed = CameraRig.toolEquipped
if type(OfferCard) == "table" then
	OfferCard.covered = CameraRig.windowOpen -- (8.3: a visitor's offer waits while another window is open)
end
if type(TradeUi) == "table" and type(WarehouseUi) == "table" then -- 8.7: the STOCK list's 🏷 opens the price picker; closing it goes back
	WarehouseUi.onPrice = TradeUi.openPrice
	TradeUi.onBack = WarehouseUi.openStock
end
-- 8.5 Danny's clipboard (orders mode: no window, nothing closes for it; 9.0: the cursor points, free): its line, its
-- outline and its 📋 button step aside while a window covers the screen
local Orders = ownModule("DannyOrders")
if type(Orders) == "table" then
	Orders.covered = CameraRig.windowOpen
end
-- 9.x loot: the pieces' stars step aside while a window covers the game (their outlines stay: they are the world's)
local Stars = ownModule("LootStars")
if type(Stars) == "table" then
	Stars.covered = CameraRig.windowOpen
end
-- 10.x the map: a run's minimap steps aside while a window (the big map too) covers the game
local Mini = ownModule("SandboxMiniMap")
if type(Mini) == "table" then
	Mini.covered = CameraRig.windowOpen
end
if type(ownModule("RunDangerUi")) == "table" then -- 10.x danger: the run's danger strip steps aside under a window too
	ownModule("RunDangerUi").covered = CameraRig.windowOpen
end
KeyHints.covered = function(): boolean
	return CameraRig.mouseNeeded()
end
-- 9.1 the drive pedals step aside while a window, a menu or the result card covers the game; a visitor's offer card
-- is no reason (they keep clear of each other: client/OfferCard.luau, client/DrivePedals.luau)
local Pedals = ownModule("DrivePedals")
if type(Pedals) == "table" then
	Pedals.covered = function(): boolean
		for _, module in windows do
			if module ~= OfferCard and ownOpen(module) then
				return true
			end
		end
		return AdminPanel.isOpen() or MovingHud.isOpen() or QuickChat.isOpen()
	end
end

-- The State: the HUD (its old money line is hidden: SandboxHud shows the money), the start screen, the key hints and
-- SandboxHud.setState when it has one.
local SandboxHud = ownModule("SandboxHud")
Net.get("State").OnClientEvent:Connect(function(state)
	Menu.setState(state)
	local setState = SandboxHud and SandboxHud.setState
	if type(setState) == "function" then
		pcall(setState, state)
	end
end)
Net.get("Notice").OnClientEvent:Connect(if SandboxHud and type(SandboxHud.notice) == "function" then SandboxHud.notice else Hud.toast) -- (8.3: in this device's words)

local function play()
	pcall(function()
		Hud.setVisible(true)
		CameraRig.setEnabled(true)
		Sounds.setInGame(true)
	end)
	Net.get("Play"):FireServer()
end
local ok, err = pcall(function()
	Menu.show(play)
end)
if not ok then
	-- No start screen: straight into the game (10.1: the loading screen goes, the server picks the slot played last).
	warn(`[Client] the start screen failed: {err}`)
	game:GetService("Players").LocalPlayer:SetAttribute("StartScreen", true)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	play()
end
Net.get("RequestState"):FireServer()
