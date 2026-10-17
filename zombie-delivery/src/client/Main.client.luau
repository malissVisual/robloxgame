--!strict
-- Zombie Delivery: the client. The start screen first; PLAY starts the interface and asks the server for the car.
-- 8.0 SANDBOX (Config.Sandbox.On, design/sandbox/KONTRAKT.md): the owner's small test world starts only its own
-- systems (the block right below) and never requires the city's; with On = false the city starts as before.

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
--                                      its toasts; the stars step aside under a window):
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

-- Never required here: the phone, the job board, MISSIONS, CAREER, the garage, the estate, the business, the maps and
-- their discovery, the tutorial, the buses, the rentals, the zip lines, the guns and the hands (Shooting, Holster, the
-- weapon wheel), the throw, the city's chips and banners, the leaderboard, the weather, the traffic and the animals.
if Config.Sandbox.On then
	local Hud = require(Client.Hud)
	local Menu = require(Client.Menu)
	local Drive = require(Client.Drive)
	local CameraRig = require(Client.CameraRig)
	local AdminPanel = require(Client.AdminPanel)
	local Sounds = require(Client.Sounds)
	local CrewPanel = require(Client.CrewPanel)
	local MovingHud = require(Client.MovingHud)
	local MoveLobbyUi = require(Client.MoveLobbyUi)
	local QuickChat = require(Client.QuickChat)
	local KeyHints = require(Client.KeyHints)
	local PerfOverlay = require(Client.PerfOverlay)
	-- The sandbox's own modules (other workers write them at the same time): only when they are there, and one that
	-- fails to load is skipped with a warning.
	local own: { { name: string, module: any } } = {}
	for _, name in { "SandboxHud", "WarehouseUi", "SandboxGuide", "UpgradeUi", "CollectionBookUi", "SandboxTasksUi", "MoveHelperCard", "DannyOrders", "OfferCard", "VanPaintUi", "TradeUi", "AuctionUi", "VillageTraffic", "DrivePedals", "RunUi", "LootOutline", "LootStars" } do -- (8.1: the UPGRADES desk's window; 8.2: the collection book, the TASKS panel; 8.3: Danny's command card, a visitor's offer, the PAINT shop; 8.5: Danny's clipboard, orders mode; 8.7: trading between players; 8.8: the Auction House's window, only while Config.Auction.On; 8.9: the D5's cars, Jinočany; 9.1: the drive pedals; 9.x loot: the outlines, the stars and the toasts)
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
	local windows = { WarehouseUi, UpgradeUi, BookUi, TasksUi, DannyCard, OfferCard, PaintUi, TradeUi, AuctionUi, ownModule("RunUi") } -- (9.7: a run's results card)

	safely("Drive", Drive.start)
	safely("ZombieAnimator", require(Client.ZombieAnimator).start)
	safely("CarVisuals", require(Client.CarVisuals).start)
	safely("Hud", Hud.start)
	safely("CameraRig", CameraRig.start)
	safely("ArmPose", require(Client.ArmPose).start)
	safely("AdminPanel", AdminPanel.start)
	safely("AdminFly", require(Client.AdminFly).start)
	safely("CrewPanel", CrewPanel.start)
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
	safely("MoveLobbyUi", MoveLobbyUi.start)
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
	MoveLobbyUi.onInvite = CrewPanel.open -- (the lobby's + INVITE; it comes back when the crew panel closes)
	MoveLobbyUi.crewOpen = CrewPanel.isOpen
	QuickChat.covered = function(): boolean
		return MovingHud.isOpen() or MoveLobbyUi.isOpen() or require(Client.MoveStoryUi).isOpen()
	end
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
		CrewPanel.close()
		MoveLobbyUi.minimize()
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
	CrewPanel.onOpen = Hud.closeWindows
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
		return Hud.anyWindowOpen() or AdminPanel.isOpen() or CrewPanel.isOpen() or MovingHud.isOpen() or MoveLobbyUi.isOpen()
			or QuickChat.isOpen() or ownOpen(WarehouseUi) or ownOpen(UpgradeUi) or ownOpen(BookUi) or ownOpen(TasksUi) or ownOpen(DannyCard) or ownOpen(PaintUi)
			or ownOpen(OfferCard) or ownOpen(TradeUi) or ownOpen(AuctionUi) or ownOpen(windows[10])
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
	KeyHints.covered = function(): boolean
		return CameraRig.mouseNeeded() or Hud.resultOpen()
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
			return Hud.anyWindowOpen() or AdminPanel.isOpen() or CrewPanel.isOpen() or MovingHud.isOpen() or MoveLobbyUi.isOpen()
				or QuickChat.isOpen() or Hud.resultOpen()
		end
	end

	-- The State: the HUD (its old money line is hidden: SandboxHud shows the money), the start screen, the key hints and
	-- SandboxHud.setState when it has one.
	local SandboxHud = ownModule("SandboxHud")
	Net.get("State").OnClientEvent:Connect(function(state)
		Hud.setState(state)
		Menu.setState(state)
		KeyHints.setState(state)
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
		-- No start screen: straight into the game.
		warn(`[Client] the start screen failed: {err}`)
		workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		play()
	end
	Net.get("RequestState"):FireServer()
	return
end

local Drive = require(Client.Drive)
local Shooting = require(Client.Shooting)
local ZombieAnimator = require(Client.ZombieAnimator)
local CarVisuals = require(Client.CarVisuals)
local Hud = require(Client.Hud)
local Menu = require(Client.Menu)
local Weather = require(Client.Weather)
local CameraRig = require(Client.CameraRig)
local ArmPose = require(Client.ArmPose)
local AdminPanel = require(Client.AdminPanel)
local AdminFly = require(Client.AdminFly)
local AnimalAnimator = require(Client.AnimalAnimator)
local Leaderboard = require(Client.Leaderboard)
local CrewPanel = require(Client.CrewPanel)
local EstateUi = require(Client.EstateUi)
local BusinessUi = require(Client.BusinessUi)
local TrafficAnimator = require(Client.TrafficAnimator)
local Sounds = require(Client.Sounds)
local MissionsUi = require(Client.MissionsUi)
local WeaponWheel = require(Client.WeaponWheel)
local DispatchUi = require(Client.DispatchUi)
local Secrets = require(Client.Secrets)
local GarageUi = require(Client.GarageUi)
local Stamina = require(Client.Stamina)
local Discovery = require(Client.Discovery)
local TutorialUi = require(Client.TutorialUi)
local Holster = require(Client.Holster)
local CarBoarding = require(Client.CarBoarding)
local LocationTag = require(Client.LocationTag)
local CareerUi = require(Client.CareerUi)
local RoadEventUi = require(Client.RoadEventUi)
local Phone = require(Client.Phone)
local CargoPrompts = require(Client.CargoPrompts)
local ReadyCheck = require(Client.ReadyCheck) -- 6.14: get ready for the mission (the phone's NEXT MISSION, the HUD's savings line)

safely("Drive", Drive.start)
safely("Shooting", Shooting.start)
safely("ZombieAnimator", ZombieAnimator.start)
safely("CarVisuals", CarVisuals.start)
safely("Weather", Weather.start)
safely("Hud", Hud.start)
safely("ReadyCheck", ReadyCheck.start) -- 6.14: the Missions and Tutorial states it reads, the HUD's savings line
safely("CameraRig", CameraRig.start)
safely("ArmPose", ArmPose.start)
safely("AdminPanel", AdminPanel.start)
safely("AdminFly", AdminFly.start) -- 4.5: the admin's fly, noclip and super jump (gated by player attributes)
safely("AnimalAnimator", AnimalAnimator.start)
safely("Leaderboard", Leaderboard.start)
safely("CrewPanel", CrewPanel.start)
safely("EstateUi", EstateUi.start)
safely("BusinessUi", BusinessUi.start)
safely("TrafficAnimator", TrafficAnimator.start)
safely("Sounds", Sounds.start)
safely("MissionsUi", MissionsUi.start)
safely("WeaponWheel", WeaponWheel.start)
safely("DispatchUi", DispatchUi.start)
safely("Secrets", Secrets.start)
safely("GarageUi", GarageUi.start) -- 3.4: the garage window, your garages' prompts, the repair timer
safely("Stamina", Stamina.start) -- 3.7: the sprint's breath
safely("Discovery", Discovery.start) -- 3.7: the map you discover
safely("TutorialUi", TutorialUi.start) -- 3.7: the first-day tutorial
safely("Holster", Holster.start) -- 3.9: B holsters / draws the gun, V punches or strikes
safely("CarBoarding", CarBoarding.start) -- 3.10: getting in and out of a car (E at a door, E or Space in a seat)
safely("LocationTag", LocationTag.start) -- 4.3: the quiet caption that names the building you come up to
safely("CareerUi", CareerUi.start) -- 4.6: the CAREER window (C) and the level-up card
safely("RoadEventUi", RoadEventUi.start) -- 4.8: a road event's side pick-up offer (Y takes it)
safely("Phone", Phone.start) -- 5.0: the courier's phone (O, the PHONE action), Marge gives it in the tutorial
safely("CargoPrompts", CargoPrompts.start) -- 5.3 review: only your own job's prompts (another courier's pile is hidden)
safely("BusRide", require(Client.BusRide).start) -- 5.5: the city buses glide, the stop card, the ride banner (E: STOP), the job's bus hint
safely("BusMapBoard", require(Client.BusMapBoard).start) -- 6.3: the bus map on the nearest stop's board, YOU ARE HERE
safely("RentalUi", require(Client.RentalUi).start) -- 5.6: ZDC RIDE's Rent / Return prompts, each player the one that fits
safely("ZipRide", require(Client.ZipRide).start) -- 5.6: riding the zip lines, the riders' pose and trolley; 6.10: a jump on a start platform grabs it
require(Client.ZipRide).notify = Hud.toast
safely("GaitPose", require(Client.GaitPose).start) -- 6.24: the gait (the walk, the run, the jump, the idle's life; 6.0's sprint)
safely("BodyLife", require(Client.BodyLife).start) -- 6.7: the breath, the weight shift, the head, blinks, the landing, the flinch, the walk
safely("BagSway", require(Client.BagSway).start) -- 6.1: the bag in the hand swings on a spring (its only writer)
safely("KeyHints", function() -- 6.1: the quiet key hints under the top buttons (F1 folds them)
	task.spawn(require(Client.KeyHints).start)
end)
safely("Throw", require(Client.Throw).start) -- 6.0: hold X at a home's door to throw the delivery (the dotted arc, TRICKSHOT)
safely("Unstuck", require(Client.Unstuck).start) -- 6.0.1: lifts your courier out of the ground if it ever sinks in (and says why)
safely("CurbRide", require(Client.CurbRide).start) -- 6.10: up the kerb's slope at speed without a hop off its top
safely("ShopPropMotion", require(Client.ShopPropMotion).start) -- 6.11: the bank's coin spins, Luigi's pizza slice bobs
safely("PerfOverlay", require(Client.PerfOverlay).start) -- 6.13.1: the admin's performance overlay (the P panel's WORLD tab)
safely("GrindChips", require(Client.GrindChips).start) -- 6.14: ON A ROLL and SHIFT 3/5 at the top, SHIFT DONE
safely("EnemyOutline", require(Client.EnemyOutline).start) -- 6.15: a subtle outline on the enemies (zombies red, bandits orange)
safely("JobThumbs", require(Client.JobThumbUi).preload) -- 6.16.1: the job and chapter pictures fetched ahead (JOBS shows them at once)
safely("ZombieLife", require(Client.ZombieLife).start) -- 6.16: the zombies' eyes glowing at night, their groans, screams, grunts
safely("ZombieFx", require(Client.ZombieFx).start) -- 6.24: the bloaters' glow, swell and hiss, the brutes' clink, the runners' shriek, a knock
safely("EventBanner", require(Client.EventBanner).start) -- 6.15: the live event's banner at the top, its stings
safely("CarSway", require(Client.CarSway).start) -- 6.16: the cars' bodies roll in a turn, dip on the brake, squat on the throttle
safely("TyreFx", require(Client.TyreFx).start) -- 6.16: dust, snow spray and tyre smoke from the wheels, skid marks (after CarSway)
safely("CrashFx", require(Client.CrashFx).start) -- 6.16: sparks and a kick on a hard hit, sparks scraping a wall
safely("SpeedLines", require(Client.SpeedLines).start) -- 6.16: streaks at the screen's edges near the top speed
safely("MovingHud", require(Client.MovingHud).start) -- 7.0: MOVES: the contract card, the move's panel and list (O), the fade, the result
safely("MoveHelperHud", require(Client.MoveHelperHud).start) -- 7.0: the depot's helper's orders under the move's panel (Danny)
safely("MoveLobbyUi", require(Client.MoveLobbyUi).start) -- 7.0 planning: the move's planning lobby (roles, READY, LAUNCH)
safely("QuickChat", require(Client.QuickChat).start) -- 7.0 planning: the crew's quick chat (hold T on a move or in its planning)
safely("CarryGripUi", require(Client.CarryGripUi).start) -- 8.1 grip: the timing checks as you lift and carry a heavy or fragile thing
require(Client.MoveLobbyUi).onInvite = CrewPanel.open -- (the lobby's + INVITE; it comes back when the crew panel closes)
require(Client.MoveLobbyUi).crewOpen = CrewPanel.isOpen
WeaponWheel.yields = require(Client.QuickChat).active -- (a held T is the quick chat on a move; a tap still takes the next gun)
-- 7.0 review: the quick chat's touch button hides while a card, the move's list or the planning covers the screen
require(Client.QuickChat).covered = function(): boolean
	return require(Client.MovingHud).isOpen() or require(Client.MoveLobbyUi).isOpen() or require(Client.MoveStoryUi).isOpen()
end
AdminPanel.onPerformance = require(Client.PerfOverlay).toggle
AdminPanel.performanceOn = require(Client.PerfOverlay).isOn
require(Client.Throw).notify = Hud.toast
Shooting.notify = Hud.toast
Holster.notify = Hud.toast -- 6.1: what you hold (keys 1 / 2 / 3)
Drive.notify = Hud.toast
Sounds.notify = Hud.toast
WeaponWheel.notify = Hud.toast
Hud.onWeaponWheel = WeaponWheel.openTouch -- 4.2, touch: a tap on the weapon line opens the wheel
Hud.onSound = Sounds.cycle
-- One window at a time: every HUD window, the leaderboard and the crew window close the others.
Hud.onCloseWindows = function()
	CrewPanel.close()
	EstateUi.close()
	BusinessUi.close()
	MissionsUi.close()
	GarageUi.close()
	DispatchUi.close()
	CareerUi.close()
	require(Client.MoveLobbyUi).minimize() -- 7.0 planning: the lobby folds away to its pill at the top
	require(Client.MovingHud).closeAll() -- 7.0 review: ESC closes the move's cards and its list …
	require(Client.QuickChat).close(false) -- … and the quick chat's ring
	if not (Hud.escaping and Phone.appOpen()) then
		Phone.close() -- (6.0.1 review: ESC with an app open goes back to the phone's home, the phone handles it)
	end
end
CrewPanel.onOpen = Hud.closeWindows
EstateUi.onOpen = Hud.closeWindows
MissionsUi.onOpen = Hud.closeWindows
DispatchUi.onOpen = Hud.closeWindows
-- 6.17: J, the depot counter and NEXT JOB open the phone's JOBS (client/JobsView.luau: the hero and the rows) once
-- Marge gave the phone; before it, the Dispatch board as before (it stays behind JOBS' FULL BOARD too).
local function openJobs()
	if Phone.has() then
		if Phone.showing() ~= "board" then
			Phone.open("board")
		end
	else
		DispatchUi.open()
	end
end
Hud.onJobs = openJobs -- (the depot counter and NEXT JOB must not close an open board; ✕ or J closes it)
Hud.onJobsKey = function() -- 4.0.2: J opens the board, J again closes it
	if DispatchUi.isOpen() then
		DispatchUi.close()
	elseif Phone.showing() == "board" then
		Phone.close()
	else
		openJobs()
	end
end
GarageUi.onOpen = Hud.closeWindows
CareerUi.onOpen = Hud.closeWindows
Hud.onCareer = CareerUi.toggle
-- 5.0: the phone is one more window (it closes the others); its apps open the board, the career, the map.
Phone.onOpen = Hud.closeWindows
Phone.onBoard = DispatchUi.open
DispatchUi.onDetails = function() -- 6.12.8: YOUR RUN's DETAILS on J's board: the phone's ORDERS, as before
	DispatchUi.close()
	Phone.open("orders")
end
Phone.onCareer = CareerUi.open
-- 5.5: the HUD MENU's actions are phone apps (their windows open; the phone closes first), and MENU opens the phone.
Phone.onMissions = function() -- 6.8: MORE → MISSIONS always opens it (on the chapter you are at)
	MissionsUi.open()
end
Phone.missionInfo = MissionsUi.summary -- 6.12.5: the MISSIONS tile on the phone's home
Phone.onCrew = CrewPanel.toggle
-- 6.14, get ready for the mission (client/ReadyCheck.luau): START opens the MISSIONS window on that mission and presses
-- its own START (the server checks it all, as always); MISSIONS opens the chapter; INVITE falls back to CREW (the crew
-- board for that mission); the HUD's savings line opens the phone's READY CHECK; the level-up card's buttons.
ReadyCheck.notify = Hud.toast
ReadyCheck.toGo = CareerUi.toGo
ReadyCheck.onStart = function(missionId: string)
	local def = require(Shared.Missions).find(missionId)
	MissionsUi.open(if def then def.campaign else nil)
	MissionsUi.startMission(missionId)
end
ReadyCheck.onMissions = function(campaignId: string?)
	MissionsUi.open(campaignId)
end
-- 6.19: a shop's "🔒 Finish Mail Call" (MISSIONS ›) opens MISSIONS on that mission.
require(Client.ShopWindow).onMission = MissionsUi.openMission
ReadyCheck.onCrew = function(missionId: string?)
	if missionId then
		MissionsUi.findCrew(missionId)
	else
		CrewPanel.open()
	end
end
require(Client.SavingsLine).onOpen = function()
	Phone.open("ready")
end
CareerUi.notify = Hud.toast
CareerUi.openWindow = function(window: string, id: string?)
	if window == "missions" then
		MissionsUi.open(id)
	elseif window == "estate" then
		EstateUi.openList()
	end
end
Phone.onTop = Leaderboard.toggle
Phone.onEstate = EstateUi.toggleList
Phone.onSound = Sounds.cycle
Phone.onOutline = require(Client.EnemyOutline).toggle -- 6.15: SETTINGS' ENEMY OUTLINES (this session)
Phone.outlineOn = require(Client.EnemyOutline).isOn
Hud.onMenu = function(): boolean
	if not Phone.has() then
		return false -- (before Marge: the old list)
	end
	Phone.toggle()
	return true
end
Phone.boardOpen = DispatchUi.isOpen
Phone.notify = Hud.toast
Hud.onCrewBadge = Phone.setCrewInvites -- 6.5 review: crew invitations on the phone's MORE tile
Phone.onUnread = Hud.setPhoneUnread -- 6.5: the unread dot on PHONE [Q] top right (the phone's own action: touch only)
Phone.blocked = function(): boolean -- (the NEW PHONE pop-up waits for Marge's dialog and a result or card)
	return TutorialUi.isOpen() or Hud.resultOpen() or MissionsUi.isOpen() or CareerUi.cardOpen()
end
-- 4.6: the level-up card waits for the DELIVERY result and a mission's cleared card (MissionsUi.isOpen counts it).
CareerUi.blocked = function(): boolean
	return Hud.resultOpen() or MissionsUi.isOpen()
end
Hud.onEstate = EstateUi.toggleList
Hud.onMissions = MissionsUi.toggle
MissionsUi.onFindCrew = CrewPanel.open
MissionsUi.onGetReady = function() -- 6.18: the chapter hero's GET READY: the phone's READY CHECK (what is missing)
	MissionsUi.close()
	Phone.open("ready")
end
CameraRig.mouseNeeded = function(): boolean
	return CameraRig.windowOpen() or Phone.isOpen()
end
-- Every window but the phone (5.4.1: with only the phone open, the right mouse still turns the camera).
CameraRig.windowOpen = function(): boolean
	return Hud.anyWindowOpen() or AdminPanel.isOpen() or Leaderboard.isOpen() or CrewPanel.isOpen() or EstateUi.isOpen() or BusinessUi.isOpen() or MissionsUi.isOpen() or WeaponWheel.isOpen() or DispatchUi.isOpen() or GarageUi.isOpen()
		or CareerUi.isOpen() or CareerUi.cardOpen() or require(Client.MovingHud).isOpen() -- (7.0: the move's card, its list)
		or require(Client.MoveLobbyUi).isOpen() or require(Client.QuickChat).isOpen() -- (7.0 planning: the lobby, the quick chat's ring)
end
-- 6.0.1: not while an app is open in the phone's popup (the mouse is needed there).
CameraRig.freeLook = function(): boolean
	return Phone.isOpen() and not Phone.appOpen() and not CameraRig.windowOpen()
end
LocationTag.windowOpen = CameraRig.mouseNeeded -- 4.3: no location caption while a window is open
-- 6.0.1: the bottom bar (client/Hotbar.luau: the items 1-5 and what you carry) hides while a window, the phone or a
-- dialog (Marge's, the delivery result) covers the game.
require(Client.Hotbar).covered = function(): boolean
	return CameraRig.mouseNeeded() or TutorialUi.isOpen() or Hud.resultOpen()
end
require(Client.KeyHints).covered = require(Client.Hotbar).covered -- 6.1: the key hints hide the same way

Net.get("State").OnClientEvent:Connect(function(state)
	Shooting.setState(state)
	require(Client.KeyHints).setState(state) -- 6.1
	-- 6.1 (6.4: any bag, the server's state.bag; one that stays is slung on the back, never set down)
	local bagDef = if type(state) == "table" and type(state.bag) == "string" then require(Shared.Transport).findKit(state.bag) else nil
	Holster.setBag(bagDef ~= nil, bagDef ~= nil and bagDef.stays == true)
	Holster.setBat(type(state) == "table" and require(Shared.Melee).hasBat(state.kit)) -- 6.7: V swings the bat
	Hud.setState(state)
	DispatchUi.setState(state)
	Menu.setState(state)
	CareerUi.setState(state)
	ReadyCheck.setState(state) -- 6.14 (before the phone: its NEXT MISSION tile reads it)
	Phone.setState(state)
end)
Net.get("Job").OnClientEvent:Connect(Hud.setJob)
Net.get("Job").OnClientEvent:Connect(require(Client.JobStartCard).onJob) -- 6.19.1: JOB STARTED (no ORDERS popping up)
Net.get("Offers").OnClientEvent:Connect(DispatchUi.setOffers)
Net.get("DeliveryResult").OnClientEvent:Connect(Hud.showResult)
require(Client.RegularsApp).start(Hud.toast) -- 6.14: a regulars' tier reached (the State): a toast and a sting
require(Client.SpecialOrderUi).start(Hud.toast) -- 6.14: a golden or a regular's order on the board: a toast and a sting
Net.get("Notice").OnClientEvent:Connect(Hud.toast)
Net.get("OpenShop").OnClientEvent:Connect(Hud.openShop)
Net.get("Boost").OnClientEvent:Connect(Drive.boost)

local function play()
	pcall(function()
		Hud.setVisible(true)
		CameraRig.setEnabled(true)
		Holster.setEnabled(true)
		Sounds.setInGame(true)
	end)
	Net.get("Play"):FireServer()
end
local ok, err = pcall(function()
	Menu.show(play)
end)
if not ok then
	-- No start screen: straight into the game.
	warn(`[Client] the start screen failed: {err}`)
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
	play()
end

Net.get("RequestState"):FireServer()
