--!strict
-- 8.0 SANDBOX: the server's boot in the owner's small test world (Config.Sandbox.On; design/sandbox/KONTRAKT.md), in
-- place of the city's: server/Main.server.luau calls SandboxBoot.start and stops there. Nothing of the city is built
-- or started: no World build, no Alps, no MapStyle, no jobs, job queue, special orders, live events, shops, clerks,
-- bandit cars, animals, traffic, buses, rentals, zip lines, estate, business, missions, challenges, tasks, shift,
-- garages, repair bays, exploring, tutorial, Earl's van, fuel, buddies, loot crates, day and night (the map sets a
-- fixed pleasant day), and no weapons (no Gun, Items, Hand or CloseCombat: every body is holstered). Those modules
-- are still required by the ones that run (Vehicles, Moving, Admin): a module whose start() is not called builds and
-- runs nothing.
--
-- What starts, in this order:
--   * the folders the game puts things in (Cars, Zombies, Effects: World's build made them) and the map
--     (server/SandboxWorld.luau: the ground, the roads, the house's outside, the scenery, the lighting);
--   * PlayerData (its own saves, Config.Sandbox.Store), Analytics, Vehicles, CarRighting, Zombies (Zombies.ambient
--     off: no camps, no roamers round the players; only what a move spawns), Npcs (Danny, the greeters), Admin, Crew
--     (the moves' lobby, the crew panel), Transport, KitWear, Horn;
--   * the plots (server/SandboxPlots.luau), FurnitureMesh (the Blender furniture, before any piece is shown), the
--     collection (Collection: its payout loop) and 8.2's collection book (CollectionBook: its remote, its hook on
--     Collection.add), the warehouses (Warehouse), 8.1's upgrades (Upgrades: its remote, the vans' engines), the
--     Sprinter's model (SprinterMesh) and last
--     Moving (it wraps the hooks set here: Vehicles.callCar …).
--   The modules written alongside this one (SandboxWorld.build, Collection.start, Warehouse.start, SprinterMesh.start)
--   run only when they are in the place (a FindFirstChild guard); every service through `safely` (one that fails only
--   warns).
--
-- The player:
--   * every spawn stands you at your plot's `spawn` (SandboxPlots.of, SandboxMap.cframe; streamed in first), holstered
--     (the character's Holstered: no aim arm); without a plot (the server full) on Depot Row in front of plot 1; on a
--     move by the move's van, else outside the house (server/Moving.luau respawnAt);
--   * PLAY (the Play remote) parks your van at your plot's vanSpot, you not in it: Config.Sandbox.Van, the ZDC Van
--     while that one is not in Config.Cars. It is your only vehicle (profile.car; no bike, no dealer). Marge's first
--     day is off (no Tutorial: the van never waits for it). A respawn leaves the van where it is (a new one only when
--     it is gone, and never on a move: there the move's CAR brings it back);
--   * CAR (the SpawnCar remote → Vehicles.callCar) parks your van at the sandbox's spot nearest you: your vanSpot, or
--     the house's curb (SandboxMap.House.curb) when you are nearer the house. No chauffeur (server/CarCall.luau drives
--     the city's roads, which are not here) and no repair bay: every van parked here comes repaired. A forced spawn
--     (an admin's: Vehicles.homeGarage) and Vehicles.placeNear (you in the driver's seat) park it the same way;
--   * RequestState sends the State (Main's queueState).
--
--   SandboxBoot.start(queueState)   boots the sandbox; queueState: Main's (the State to a player's client)
--   SandboxBoot.vanId()             the van's Config.Cars id
--   SandboxBoot.spawnSpot(player)   where the player stands at every spawn (SandboxMap.Spot)
--   SandboxBoot.vanSpot(player)     where PLAY parks their van (SandboxMap.Spot)
--   SandboxBoot.parkVan(player, spot, seat, carId?)   the van parked there, repaired (PLAY, CAR, a move's START): err, car

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Net = require(Shared.Net)
local SandboxMap = require(Shared.SandboxMap)

local Server = script.Parent
local PlayerData = require(Server.PlayerData)
local Vehicles = require(Server.Vehicles)
local Zombies = require(Server.Zombies)
local SandboxPlots = require(Server.SandboxPlots)

local SandboxBoot = {}

local PLOT_WAIT = 3 -- seconds a new body waits for its player's plot (SandboxPlots claims it when they join)
local SAVE_WAIT = 15 -- seconds PLAY waits for the save to load

local notice = Net.get("Notice")
local playing: { [Player]: boolean } = {} -- PLAY pressed (the van is theirs to keep)

-- ── The spots ──────────────────────────────────────────────────────────────

function SandboxBoot.vanId(): string
	local id = Config.Sandbox.Van
	return if Economy.isPlayerCar(id) then id else Config.CompanyVan.Car
end

-- Without a plot (more players than plots): on Depot Row in front of plot 1, looking at it, the van on the road
-- beside you (nose east).
local function fallback(): (SandboxMap.Spot, SandboxMap.Spot)
	local plot = SandboxMap.Plots[1]
	for _, road in SandboxMap.Roads do
		if road.name == "Depot Row" then
			local x = plot.spawn.x
			local stand = { x = x, y = plot.spawn.y, z = road.z1 - 4, yaw = 0 }
			local van = { x = x + 20, y = SandboxMap.RoadTop, z = (road.z0 + road.z1) / 2, yaw = 270 }
			return stand, van
		end
	end
	return plot.spawn, plot.vanSpot
end

function SandboxBoot.spawnSpot(player: Player): SandboxMap.Spot
	local plot = SandboxPlots.of(player)
	if plot then
		return plot.spawn
	end
	return (fallback())
end

function SandboxBoot.vanSpot(player: Player): SandboxMap.Spot
	local plot = SandboxPlots.of(player)
	if plot then
		return plot.vanSpot
	end
	local _, van = fallback()
	return van
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Where the player's vanSpot is, for the notices.
local function homeWords(player: Player): string
	return if SandboxPlots.of(player) then "at your warehouse" else "on Depot Row"
end

-- The sandbox's parking spot nearest the player: their vanSpot, or the house's curb when they are nearer the house.
-- Also what the notice says about it.
local function parkingNear(player: Player): (SandboxMap.Spot, string)
	local home = SandboxBoot.vanSpot(player)
	local curb = SandboxMap.House.curb
	local root = rootOf(player)
	if root then
		local at = root.Position
		if (at.X - curb.x) ^ 2 + (at.Z - curb.z) ^ 2 < (at.X - home.x) ^ 2 + (at.Z - home.z) ^ 2 then
			return curb, `at {SandboxMap.House.name}`
		end
	end
	return home, homeWords(player)
end

-- A spot's CFrame for Vehicles.placeAt, which stands a long van out of a garage's door by Vehicles.driveOut along its
-- look: taken back here, so the van's middle is the spot itself.
local function parkAt(player: Player, spot: SandboxMap.Spot): CFrame
	local out = Vehicles.driveOut(player, nil)
	return SandboxMap.cframe(spot) * CFrame.new(0, 0, out)
end

-- ── The van ────────────────────────────────────────────────────────────────

-- The van is the player's one vehicle: profile.car, the only car in the sandbox save (no bike).
local function ownVan(player: Player, profile: PlayerData.Profile): string
	local id = SandboxBoot.vanId()
	local changed = profile.car ~= id or profile.bike ~= nil or profile.lastCar ~= nil or profile.cars[id] ~= true
	for other in profile.cars do
		if other ~= id then
			profile.cars[other] = nil
			changed = true
		end
	end
	profile.cars[id] = true
	profile.car, profile.bike, profile.lastCar = id, nil, nil
	if changed then
		PlayerData.notify(player)
	end
	return id
end

local function nameOf(car: Vehicles.Car): string
	local def = Economy.findCar(car.id)
	return if def then def.name else "van"
end

-- Parks the player's van (or carId's car) at `spot` (the old one goes: Vehicles.placeAt), repaired: the sandbox has
-- no repair bay. Returns an error text and the car (nil with no error: server/Moving.luau's wrap refused and said why).
-- (server/Moving.luau's START brings the van this way too, when none is out: its hook Moving.parkVan.)
function SandboxBoot.parkVan(player: Player, spot: SandboxMap.Spot, seat: boolean, carId: string?): (string?, Vehicles.Car?)
	local profile = PlayerData.get(player)
	if not profile then
		return "Still loading...", nil
	end
	if carId == nil then
		ownVan(player, profile)
	end
	local car = Vehicles.placeAt(player, carId, parkAt(player, spot), seat)
	if car and carId == nil then
		Vehicles.repair(car, 1)
	end
	return nil, car
end

-- PLAY (and a respawn with no van): the van at the player's vanSpot, they not in it. Waits for the save.
local function vanAtHome(player: Player)
	local waited = 0
	while player.Parent and not PlayerData.get(player) and waited < SAVE_WAIT do
		waited += task.wait(0.5)
	end
	if not player.Parent or not playing[player] then
		return
	end
	local err, car = SandboxBoot.parkVan(player, SandboxBoot.vanSpot(player), false)
	if err then
		notice:FireClient(player, err)
	elseif car then
		notice:FireClient(player, `Your {nameOf(car)} is parked {homeWords(player)}.`)
	end
end

-- CAR (Vehicles.callCar: server/Moving.luau wraps it, a move's van stays out): the van at the spot nearest you.
local function callVan(player: Player, _carId: string?): string?
	local busy = Vehicles.cooldown(player)
	if busy then
		return busy
	end
	local spot, where = parkingNear(player)
	local err, car = SandboxBoot.parkVan(player, spot, false)
	if car then
		notice:FireClient(player, `Your {nameOf(car)} is parked {where}.`)
	end
	return err
end

-- On a move (its owner or its crew)? Then a respawn brings no van: the move decides (its CAR, after VanAgain).
local function onMove(player: Player): boolean
	return require(Server.Moving).busy(player) ~= nil
end

-- The hooks the city's services set (server/CarCall.luau, Main), the sandbox's way. Before Moving.start: it wraps them.
local function vehicleHooks()
	Vehicles.callCar = callVan
	-- a forced spawn (an admin's car, Vehicles.spawn(player, true)): parked at the spot nearest you
	Vehicles.homeGarage = function(player: Player): CFrame?
		return parkAt(player, (parkingNear(player)))
	end
	-- the city's "next to you on the nearest road" (a move's LAUNCH without a van out): the spot nearest you, seated
	Vehicles.placeNear = function(player: Player, carId: string?): string?
		local err, car = SandboxBoot.parkVan(player, (parkingNear(player)), true, carId)
		return err or (if car then nil else "Your van could not come: try again.")
	end
	Vehicles.onWrecked = function(player: Player, car: Vehicles.Car, reason: string)
		Zombies.releaseCar(car)
		notice:FireClient(player, `{reason} Press CAR: it comes back repaired.`)
	end
end

-- ── The players ────────────────────────────────────────────────────────────

-- A new body stands at the player's plot's spawn (the plot is claimed as they join: a moment's wait for it); on a move
-- where server/Moving.luau's respawnAt says (by the move's van, else outside the house: never stranded at home).
local function standAtHome(player: Player, character: Model)
	character:SetAttribute("Holstered", true) -- (no weapons here: holding a mouse button never raises the aim arm)
	local waited = 0
	while player.Parent and not SandboxPlots.of(player) and waited < PLOT_WAIT do
		waited += task.wait(0.25)
	end
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root or player.Character ~= character then
		return
	end
	local frame = require(Server.Moving).respawnAt(player) or SandboxMap.cframe(SandboxBoot.spawnSpot(player))
	pcall(function()
		player:RequestStreamAroundAsync(frame.Position, 5)
	end)
	if player.Character == character and character.Parent then
		character:PivotTo(frame)
	end
end

local function onPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.Died:Connect(function()
				PlayerData.track("died", player, onMove(player)) -- 6.13: DeathOnJob (here: on a move)
			end)
		end
		standAtHome(player, character)
		-- the van stays where it is; only a van that is gone (wrecked) comes back, at home
		if playing[player] then
			task.wait(1)
			if player.Character == character and not Vehicles.get(player) and not onMove(player) then
				vanAtHome(player)
			end
		end
	end)
	if player.Character then
		task.spawn(standAtHome, player, player.Character)
	end
end

local function remotes(queueState: (Player) -> ())
	-- PLAY on the start screen: the van at your warehouse (the city's: the car call, the trip home, the car, Marge)
	Net.get("Play").OnServerEvent:Connect(function(player: Player)
		if playing[player] then
			return
		end
		playing[player] = true
		PlayerData.track("onPlay", player) -- 6.13: the onboarding funnel's PressedPlay
		local ok, err = pcall(function()
			vanAtHome(player)
		end)
		if not ok then
			warn(`[Sandbox] PLAY for {player.Name}: the van failed: {err}`)
			if player.Parent then
				playing[player] = nil -- (a PLAY sent again tries again)
			end
		end
	end)
	Net.get("SpawnCar").OnServerEvent:Connect(function(player: Player)
		local call = Vehicles.callCar
		local err = if call then call(player, nil) else callVan(player, nil)
		if err then
			notice:FireClient(player, err)
		end
	end)
	local asked: { [Player]: number } = {}
	Net.get("RequestState").OnServerEvent:Connect(function(player: Player)
		if os.clock() - (asked[player] or -1) < 0.5 then
			return -- (a client asks once on start; a flood would send the whole profile each time)
		end
		asked[player] = os.clock()
		queueState(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		playing[player] = nil
		asked[player] = nil
		Zombies.clearOwner(player)
	end)
end

-- ── Booting ────────────────────────────────────────────────────────────────

-- Every service starts on its own: one that fails (see the Output) does not take the others down.
local function safely(name: string, start: () -> ())
	local ok, err = pcall(function()
		start()
	end)
	if not ok then
		warn(`[Sandbox] {name} failed to start: {err}`)
	end
end

-- A sandbox module written alongside this one (design/sandbox/KONTRAKT.md): its `method` run (start, the map's build)
-- when it is in the place.
local function optional(name: string, method: string)
	local module = Server:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		warn(`[Sandbox] {name} is not in this build: skipped`)
		return
	end
	safely(name, function()
		local api = require(module :: ModuleScript) :: any
		api[method]()
	end)
end

-- The map first (World's build did the same): the place's own baseplate and spawn would lie in its ground.
local function world()
	for _, name in { "Cars", "Zombies", "Effects" } do
		if not workspace:FindFirstChild(name) then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = workspace
		end
	end
	if Server:FindFirstChild("SandboxWorld") then
		for _, child in workspace:GetChildren() do
			if child.Name == "Baseplate" or child:IsA("SpawnLocation") then
				child:Destroy()
			end
		end
	end
	optional("SandboxWorld", "build")
end

local function services()
	safely("PlayerData", PlayerData.start)
	-- 6.13: Roblox's analytics (its hooks first: before any pay; a module that fails to load only means none)
	safely("Analytics", function()
		require(Server.Analytics).start()
	end)
	optional("SandboxAnalytics", "start") -- 8.2: the sandbox's funnel steps and events (listeners only; after Analytics' hooks)
	safely("Vehicles", Vehicles.start)
	safely("CarRighting", function()
		require(Server.CarRighting).start()
	end)
	Zombies.ambient = false -- no camps, no roamers round the players: only what a move spawns
	safely("Zombies", Zombies.start)
	safely("Npcs", function()
		require(Server.Npcs).start()
	end)
	safely("Admin", function()
		require(Server.Admin).start()
	end)
	safely("Crew", function()
		require(Server.Crew).start()
	end)
	safely("Transport", function()
		require(Server.Transport).start()
	end)
	safely("KitWear", function()
		require(Server.KitWear).start()
	end)
	safely("Horn", function()
		require(Server.Horn).start()
	end)
end

-- The sandbox's own pieces (after PlayerData: the collection reads the saves), then the moves (last: Moving wraps the
-- hooks set before it).
local function sandbox()
	safely("SandboxPlots", SandboxPlots.start)
	-- the owner's Blender furniture, before the warehouses show any piece (and before the moves' houses)
	safely("FurnitureMesh", function()
		require(Server.FurnitureMesh).start()
	end)
	optional("Collection", "start")
	optional("CollectionBook", "start") -- 8.2: the collection book (after the collection: its hook on Collection.add)
	optional("Warehouse", "start")
	optional("Upgrades", "start") -- 8.1: the UPGRADES desk's shop (after the collection and the warehouses)
	optional("SprinterMesh", "start") -- (before any van: PLAY parks one)
	vehicleHooks()
	safely("Moving", function()
		local Moving = require(Server.Moving)
		Moving.parkVan = SandboxBoot.parkVan -- (a move's START brings the van this way too: repaired)
		Moving.start()
	end)
end

function SandboxBoot.start(queueState: (Player) -> ())
	world()
	PlayerData.Changed:Connect(queueState) -- (before PlayerData starts: the first load's State goes out)
	services()
	sandbox()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	remotes(queueState)
	print(`[Server] Zombie Delivery {Config.Version} SANDBOX is running`)
end

return SandboxBoot
