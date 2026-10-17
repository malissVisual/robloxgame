-- 8.0 SANDBOX: the server's boot choice. The real server/Main.server.luau and server/SandboxBoot.luau run in the Luau
-- CLI (tests/run_tests.py builds MainServer.luau and SandboxBootServer.luau on tests/runtime/BootRuntime.luau's
-- recorders: every other module and Roblox object records what it is asked).
--   * Config.Sandbox.On: Main runs SandboxBoot and nothing of the city (no world build, no Alps, none of the city's
--     services, no hooks into them); the sandbox's services start in their order (the map first, Zombies without its
--     own zombies, Moving last after the van's hooks); the parallel modules only when they are in the place.
--   * The sandbox's player: every spawn at the plot's spawn and holstered, PLAY's van at the vanSpot (not seated,
--     repaired, the only vehicle, Marge's tutorial never asked), a second PLAY nothing, a respawn keeps the van (a gone
--     one comes back, not on a move), CAR at the house's curb or at home, a player without a plot on Depot Row,
--     RequestState through Main's queueState.
--   * Off: the city's boot as before (the Alps, World.build, World.buildLate deferred, every service in Main's order,
--     the hooks, its PLAY asking Marge's tutorial before the car).
--   * 8.0.1: Moving's hook parkVan is SandboxBoot.parkVan, set before Moving starts (a move's START parks the van the
--     sandbox's way: at the vanSpot, not seated, repaired); a respawn on a move stands where Moving.respawnAt says (by
--     the move's van, else outside the house), off a move at home.
local E = require("./BootRuntime")
local main = require("./MainServer")
local loadBoot = require("./SandboxBootServer")
local Economy = require("./Economy")
local Config = E.Config
local Map = E.SandboxMap

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- Main's order of the city's services (server/Main.server.luau's `safely` list).
local CITY = { "PlayerData", "Analytics", "Vehicles", "CarRighting", "Zombies", "Jobs", "JobQueue", "SpecialOrders", "LiveEvents", "Gun", "Items", "Shops", "ShopClerks", "BanditCars", "Npcs", "Animals", "Cargo", "Admin", "DayNight", "Traffic", "Crew", "Ranking", "Estate", "CarCall", "Business", "Missions", "Challenges", "Tasks", "Shift", "Garages", "Repair", "Explore", "Tutorial", "Hand", "CloseCombat", "Buddy", "Transport", "Skills", "VanQuest", "KitWear", "Fuel", "StyleWear", "Horn", "Buses", "Rental", "ZipLines", "FurnitureMesh", "FixtureMesh", "Moving" }
-- What the sandbox starts (SandboxWorld: its start or build) and what it never touches.
local SANDBOX = { "SandboxWorld", "PlayerData", "Analytics", "SandboxAnalytics", "Vehicles", "CarRighting", "Zombies", "Npcs", "Admin", "Crew", "Transport", "KitWear", "Horn", "Clipboard", "SandboxPlots", "Collection", "CollectionBook", "Warehouse", "Upgrades", "VanPaint", "SandboxTasks", "SandboxLeaders", "Visitors", "SandboxBadges", "PlayerTrade", "SprinterMesh", "FurnitureMesh", "FixtureMesh", "Moving" }
local PARALLEL = { "SandboxWorld", "Collection", "CollectionBook", "Warehouse", "Upgrades", "VanPaint", "SandboxTasks", "SandboxLeaders", "Visitors", "SprinterMesh", "SandboxAnalytics", "SandboxBadges", "PlayerTrade" }
local NEVER = { "World", "MapStyle", "Alpine", "Jobs", "JobQueue", "SpecialOrders", "LiveEvents", "Shops", "ShopClerks", "BanditCars", "Animals", "Traffic", "Buses", "Rental", "ZipLines", "Estate", "Business", "Missions", "Challenges", "Tasks", "Shift", "Garages", "Repair", "Explore", "Tutorial", "VanQuest", "Fuel", "Buddy", "DayNight", "Gun", "Items", "Cargo", "Ranking", "CarCall", "StyleWear", "Skills", "Hand", "CloseCombat" }

-- Was anything of module `name` called or set this run?
local function touched(name: string): string?
	for _, entry in E.log do
		if string.sub(entry, 1, #name + 1) == name .. "." or string.sub(entry, 1, #name + 5) == "set " .. name .. "." then
			return entry
		end
	end
	return nil
end

local function contains(list: { string }, text: string): boolean
	for _, line in list do
		if string.find(line, text, 1, true) then
			return true
		end
	end
	return false
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- ── The sandbox's world: the fakes a test reads back ────────────────────────
local profiles: { [any]: any } = {}
local cars: { [any]: any } = {}
local plotOf: { [any]: number } = {}
local moving: { [any]: string } = {}
local placed: { any } = {}
local repaired: { any } = {}
local respawn: { [any]: any } = {} -- 8.0.1: player → Moving.respawnAt's frame (on a move)

local function boot(absent: { string }?)
	Config.Sandbox.On = true
	E.reset()
	for _, name in absent or {} do
		E.absent[name] = true
	end
	profiles, cars, plotOf, moving, placed, repaired, respawn = {}, {}, {}, {}, {}, {}, {}
	E.override("PlayerData", {
		get = function(player: any): any
			return profiles[player]
		end,
	})
	E.override("Vehicles", {
		get = function(player: any): any
			return cars[player]
		end,
		driveOut = function(): (number, number)
			return 3, 20 -- (a long van: placeAt stands it 3 studs out along its look)
		end,
		cooldown = function(): string?
			return nil
		end,
		placeAt = function(player: any, carId: string?, frame: any, seat: boolean?): any
			local car = { id = carId or profiles[player].car, owner = player }
			table.insert(placed, { player = player, carId = carId, frame = frame, seat = seat })
			cars[player] = car
			return car
		end,
		repair = function(car: any, share: number)
			table.insert(repaired, { car = car, share = share })
		end,
	})
	E.override("SandboxPlots", {
		of = function(player: any): any
			local id = plotOf[player]
			return if id then Map.Plots[id] else nil
		end,
	})
	E.override("Moving", {
		busy = function(player: any): string?
			return moving[player]
		end,
		respawnAt = function(player: any): any
			return respawn[player]
		end,
	})
	E.fakes.SandboxBoot = loadBoot()
	main()
	return E.fakes.SandboxBoot
end

local serial = 0
local function newPlayer(name: string, plot: number?): any
	serial += 1
	local player = E.object(name, { Name = name, UserId = serial })
	E.override(player, { Character = E.Nil })
	plotOf[player] = plot
	profiles[player] = {
		money = Config.Sandbox.StartMoney,
		car = Config.CompanyVan.Car,
		cars = { [Config.CompanyVan.Car] = true, citybike = true },
		bike = "citybike",
		lastCar = nil,
		carHealth = {},
	}
	E.fire("Players.PlayerAdded", player)
	return player
end

-- A new body for the player at (x, z), spawned (CharacterAdded). Returns the body and its root.
local bodies = 0
local function spawnBody(player: any, x: number, z: number): (any, any)
	bodies += 1
	local root = E.object(`{player.Name}.Root{bodies}`, { Position = E.Vector3.new(x, 3, z) })
	local humanoid = E.object(`{player.Name}.Humanoid{bodies}`)
	local body = E.object(`{player.Name}.Body{bodies}`, { Parent = E.workspace })
	E.override(body, {
		FindFirstChild = function(_: any, name: string): any
			return if name == "HumanoidRootPart" then root else nil
		end,
		WaitForChild = function(_: any, name: string): any
			return if name == "HumanoidRootPart" then root elseif name == "Humanoid" then humanoid else nil
		end,
	})
	E.override(player, { Character = body })
	E.fire(`{player.Name}.CharacterAdded`, body)
	return body, root
end

local function pivotOf(body: any): any
	local calls = E.callsOf(E.pathOf(body) .. ".PivotTo")
	local last = calls[#calls]
	return if last then last[2] else nil
end

local function lastNotice(): string
	local calls = E.callsOf("Net.get(Notice).FireClient")
	local last = calls[#calls]
	return if last then tostring(last[3]) else ""
end

-- ── Sandbox: Main boots the sandbox only ────────────────────────────────────
local Boot = boot()
local started = E.started()
check("sandbox: the courier avatar first (both worlds)", started.CourierAvatar ~= nil and started.CourierAvatar < (started.SandboxWorld or math.huge))
local missing = {}
for _, name in SANDBOX do
	if started[name] == nil then
		table.insert(missing, name)
	end
end
check("sandbox: every sandbox service starts", #missing == 0, table.concat(missing, ", "))
local extra = {}
for name in started do
	if not table.find(SANDBOX, name) and name ~= "CourierAvatar" then
		table.insert(extra, name)
	end
end
check("sandbox: nothing else starts", #extra == 0, table.concat(extra, ", "))
local touchedCity = {}
for _, name in NEVER do
	local entry = touched(name)
	if entry then
		table.insert(touchedCity, entry)
	end
end
check("sandbox: nothing of the city is called or hooked (no world build, no Alps, no tutorial, no weapons …)", #touchedCity == 0, table.concat(touchedCity, ", "))
check("sandbox: no World.buildLate deferred", #E.deferred == 0, #E.deferred)
check("sandbox: the map before the services", started.SandboxWorld < started.PlayerData)
check("sandbox: the State hooked before PlayerData starts", (E.find("PlayerData.Changed.Connect") or math.huge) < started.PlayerData)
check("sandbox: Zombies without its own zombies (ambient off before it starts)", E.module("Zombies").ambient == false and (E.find("set Zombies.ambient") or math.huge) < started.Zombies)
check("sandbox: the map is SandboxWorld.build, the others' start()", E.called("SandboxWorld.build") and E.called("Collection.start") and E.called("Warehouse.start") and E.called("SprinterMesh.start"))
check("sandbox: the collection after PlayerData (it reads the saves)", started.PlayerData < started.Collection)
check("sandbox: the plots, the Blender furniture and the collection before the warehouses", started.SandboxPlots < started.Warehouse and started.FurnitureMesh < started.Warehouse and started.Collection < started.Warehouse)
check("8.1: the upgrades (Upgrades.start) after the collection and the warehouses", E.called("Upgrades.start") and started.Collection < started.Upgrades and started.Warehouse < started.Upgrades)
check("8.2: the collection book (CollectionBook.start) right after the collection (its hook on Collection.add)", E.called("CollectionBook.start") and started.Collection < started.CollectionBook and started.CollectionBook < started.Warehouse)
check("8.2: the sandbox's analytics (SandboxAnalytics.start) right after Analytics (its money hook), before the moves and the collection",
	E.called("SandboxAnalytics.start") and started.Analytics < started.SandboxAnalytics and started.SandboxAnalytics < started.Vehicles
	and started.SandboxAnalytics < started.Collection and started.SandboxAnalytics < started.Moving)
check("8.2: the daily tasks (SandboxTasks.start) after the collection and the upgrades, before Moving", E.called("SandboxTasks.start") and started.Collection < started.SandboxTasks
	and started.Upgrades < started.SandboxTasks and started.SandboxTasks < started.Moving)
check("8.2: the leaders (SandboxLeaders.start: the player list's columns, the TOP MOVERS board) after the collection, before the moves", E.called("SandboxLeaders.start") and started.Collection < started.SandboxLeaders and started.SandboxLeaders < started.Moving)
check("8.3: the showroom's visitors (Visitors.start) after the warehouses and the daily tasks, before the moves", E.called("Visitors.start") and started.Warehouse < started.Visitors
	and started.SandboxTasks < started.Visitors and started.Visitors < started.Moving)
check("8.3: the badges (SandboxBadges.start: listeners only) after what they listen to (the collection, the book, the upgrades, the PAINT shop, the leaders), before the moves",
	E.called("SandboxBadges.start") and started.Collection < started.SandboxBadges and started.CollectionBook < started.SandboxBadges
	and started.Upgrades < started.SandboxBadges and started.VanPaint < started.SandboxBadges and started.SandboxLeaders < started.SandboxBadges
	and started.SandboxBadges < started.Moving)
check("8.7: trading between players (PlayerTrade.start) after the collection, the book, the warehouses and the visitors' offers, before the moves; the stands' trade prompts go to it (Warehouse.onTrade)",
	E.called("PlayerTrade.start") and started.Collection < started.PlayerTrade and started.CollectionBook < started.PlayerTrade and started.Warehouse < started.PlayerTrade
	and started.Visitors < started.PlayerTrade and started.PlayerTrade < started.Moving and (E.find("set Warehouse.onTrade") or math.huge) < started.Moving)
local last = 0
for _, index in started do
	last = math.max(last, index)
end
check("sandbox: Moving last", started.Moving == last)
local hooksSet = true
for _, hook in { "callCar", "homeGarage", "placeNear", "onWrecked" } do
	local at = E.find("set Vehicles." .. hook)
	hooksSet = hooksSet and at ~= nil and at < started.Moving and type(E.module("Vehicles")[hook]) == "function"
end
check("sandbox: the van's hooks set before Moving wraps them (CAR, a forced spawn, placeNear, a wreck)", hooksSet)
local parkHook = E.find("set Moving.parkVan")
check("8.0.1: Moving's hook parkVan is SandboxBoot.parkVan, set before Moving starts (a move's START parks the van the sandbox's way)",
	parkHook ~= nil and parkHook < started.Moving and E.module("Moving").parkVan == Boot.parkVan and type(Boot.parkVan) == "function")
local folders = {}
for _, made in E.made do
	if made.ClassName == "Folder" then
		folders[made.Name] = true
	end
end
check("sandbox: the folders World's build made (Cars, Zombies, Effects)", folders.Cars and folders.Zombies and folders.Effects or false)
check("sandbox: the place's baseplate goes (the map has its own ground)", E.called("Baseplate.Destroy"))
for _, remote in { "Play", "SpawnCar", "RequestState" } do
	check(`sandbox: the {remote} remote answered`, E.handlers[`Net.get({remote}).OnServerEvent`] ~= nil and #E.handlers[`Net.get({remote}).OnServerEvent`] == 1)
end
check("sandbox: no Aiming listener (no weapons)", E.handlers["Net.get(Aiming).OnServerEvent"] == nil)
check("sandbox: it says it runs", contains(E.printed, "SANDBOX is running"))
check("sandbox: no warnings", #E.warnings == 0, table.concat(E.warnings, " | "))

-- ── Sandbox: the player ────────────────────────────────────────────────────
local vanId = if Economy.isPlayerCar(Config.Sandbox.Van) then Config.Sandbox.Van else Config.CompanyVan.Car
check("the van: Config.Sandbox.Van, else the ZDC Van while it is not in Config.Cars", Boot.vanId() == vanId, Boot.vanId())

local ann = newPlayer("Ann", 2)
local plot = Map.Plots[2]
local body = spawnBody(ann, 0, 0)
local at = pivotOf(body)
check("a spawn stands you at your plot's spawn", at ~= nil and near(at.Position.X, plot.spawn.x) and near(at.Position.Z, plot.spawn.z))
check("streamed in first", E.called("Ann.RequestStreamAroundAsync"))
local holstered = false
for _, args in E.callsOf(E.pathOf(body) .. ".SetAttribute") do
	holstered = holstered or (args[2] == "Holstered" and args[3] == true)
end
check("every spawn holstered (no aim arm)", holstered)
check("no van before PLAY", #placed == 0)

check("PLAY answered", E.fire("Net.get(Play).OnServerEvent", ann) == 1)
local van = placed[1]
check("PLAY: one van", #placed == 1, #placed)
check("PLAY: at your plot's vanSpot (placeAt's 3 studs out taken back)", van ~= nil and near(van.frame.Position.X, plot.vanSpot.x) and near(van.frame.Position.Z + 3, plot.vanSpot.z), van and `{van.frame.Position.X}, {van.frame.Position.Z}`)
check("PLAY: you are not seated in it", van ~= nil and van.seat == false)
check("PLAY: your own van (profile.car), repaired", van ~= nil and van.carId == nil and repaired[1] ~= nil and repaired[1].share == 1)
local profile = profiles[ann]
local owned = 0
for _ in profile.cars do
	owned += 1
end
check("the only vehicle: profile.car the van, no other car, no bike", profile.car == vanId and profile.cars[vanId] == true and owned == 1 and profile.bike == nil)
check("PLAY: the notice says where", string.find(lastNotice(), "at your warehouse", 1, true) ~= nil, lastNotice())
check("Marge's tutorial is never asked (Tutorial.ahead)", touched("Tutorial") == nil)
E.fire("Net.get(Play).OnServerEvent", ann)
check("a second PLAY changes nothing", #placed == 1)

body = spawnBody(ann, 0, 400)
at = pivotOf(body)
check("a respawn: at the plot's spawn again", at ~= nil and near(at.Position.X, plot.spawn.x) and near(at.Position.Z, plot.spawn.z))
check("a respawn: the van stays where it is", #placed == 1)
cars[ann] = nil
spawnBody(ann, 0, 400)
check("a respawn with the van gone (wrecked): it comes back at home", #placed == 2 and near(placed[2].frame.Position.Z + 3, plot.vanSpot.z))
cars[ann] = nil
moving[ann] = "You are on a move"
spawnBody(ann, 0, 400)
check("… but not on a move (the move's CAR brings it)", #placed == 2)
moving[ann] = nil

local curb = Map.House.curb
cars[ann] = placed[2]
-- 8.0.1: a death on a move: the new body where Moving.respawnAt says (by the move's van, else outside the house)
moving[ann] = "You are on a move"
respawn[ann] = E.CFrame.new(curb.x + 7, 3, curb.z + 10)
body = spawnBody(ann, 0, 0)
at = pivotOf(body)
check("8.0.1: a respawn on a move: where Moving.respawnAt says (by the move's van), not at the plot", at ~= nil and near(at.Position.X, curb.x + 7)
	and near(at.Position.Z, curb.z + 10) and #placed == 2, at and `{at.Position.X}, {at.Position.Z}`)
moving[ann], respawn[ann] = nil, nil
body = spawnBody(ann, 0, 0)
at = pivotOf(body)
check("…off a move again: at the plot's spawn", at ~= nil and near(at.Position.X, plot.spawn.x) and near(at.Position.Z, plot.spawn.z))
local _, root = spawnBody(ann, 0, 0)
root.Position = E.Vector3.new(curb.x + 6, 3, curb.z + 20)
check("CAR answered", E.fire("Net.get(SpawnCar).OnServerEvent", ann) == 1)
van = placed[#placed]
check("CAR near the house: the van at its curb (nose north, back to the door)", #placed == 3 and near(van.frame.Position.X, curb.x) and near(van.frame.Position.Z - 3, curb.z) and van.seat == false)
check("CAR: the notice names the house", string.find(lastNotice(), Map.House.name, 1, true) ~= nil, lastNotice())
root.Position = E.Vector3.new(plot.spawn.x, 3, plot.spawn.z)
E.fire("Net.get(SpawnCar).OnServerEvent", ann)
van = placed[#placed]
check("CAR at home: the van at the vanSpot", #placed == 4 and near(van.frame.Position.Z + 3, plot.vanSpot.z))

local deferred = #E.deferred
E.fire("Net.get(RequestState).OnServerEvent", ann)
check("RequestState: Main's queueState sends the State", #E.deferred == deferred + 1)

local bob = newPlayer("Bob", nil)
local bobBody = spawnBody(bob, 0, 0)
at = pivotOf(bobBody)
local row = Map.Roads[2]
check("no plot (the server full): on Depot Row in front of plot 1", at ~= nil and near(at.Position.X, Map.Plots[1].spawn.x) and at.Position.Z > row.z0 and at.Position.Z < row.z1)
E.fire("Net.get(Play).OnServerEvent", bob)
van = placed[#placed]
check("no plot: the van on Depot Row", van.player == bob and van.frame.Position.Z > row.z0 and van.frame.Position.Z < row.z1 and string.find(lastNotice(), "on Depot Row", 1, true) ~= nil)

-- 8.0.1: SandboxBoot.parkVan (Moving's hook: a move's START without a van out) parks it the sandbox's way
profiles[ann].carHealth = { [vanId] = 0.2 } -- (wrecked before: the save keeps the damage)
local repairsBefore = #repaired
local parkErr, parkedVan = Boot.parkVan(ann, plot.vanSpot, false)
van = placed[#placed]
check("8.0.1: SandboxBoot.parkVan: the player's own van at the spot (placeAt's 3 studs taken back), not seated", parkErr == nil and parkedVan ~= nil
	and van.player == ann and van.carId == nil and van.seat == false and near(van.frame.Position.X, plot.vanSpot.x) and near(van.frame.Position.Z + 3, plot.vanSpot.z))
check("…repaired whole (never the save's 0.2: a 144/720 hp Sprinter)", #repaired == repairsBefore + 1 and repaired[#repaired].car == parkedVan and repaired[#repaired].share == 1)

-- ── Sandbox: the modules written alongside are not in the place yet ─────────
boot(PARALLEL)
started = E.started()
local early = {}
for _, name in PARALLEL do
	if started[name] then
		table.insert(early, name)
	end
	check(`missing {name}: warned and skipped`, contains(E.warnings, `{name} is not in this build`))
end
check("missing modules: none of them run", #early == 0, table.concat(early, ", "))
check("missing modules: the rest still starts (Moving last)", started.PlayerData ~= nil and started.Zombies ~= nil and started.Moving ~= nil and started.SandboxPlots ~= nil)
check("missing map: the place's baseplate stays (something to stand on)", not E.called("Baseplate.Destroy"))

-- ── The city: unchanged ────────────────────────────────────────────────────
Config.Sandbox.On = false
E.reset()
E.override("Jobs", {
	vehicleFor = function(): string?
		return nil
	end,
})
E.override("Vehicles", {
	get = function(): any
		return nil
	end,
})
main()
started = E.started()
check("city: SandboxBoot never required", E.modules.SandboxBoot == nil)
local publish, build = E.find("MapStyle.publish"), E.find("World.build")
check("city: the Alps' summary, then the world, before every service", publish ~= nil and build ~= nil and publish < build and build < started.PlayerData)
check("city: World.buildLate deferred", E.deferred[1] == E.module("World").buildLate)
local order, previous, absentCity = true, 0, {}
for _, name in CITY do
	local index = started[name]
	if index == nil then
		table.insert(absentCity, name)
	elseif index < previous then
		order = false
	else
		previous = index
	end
end
check("city: every service starts", #absentCity == 0, table.concat(absentCity, ", "))
check("city: in Main's order", order)
check("city: the sandbox's own pieces do not start", started.SandboxPlots == nil and started.Warehouse == nil and started.Collection == nil and started.SandboxWorld == nil)
check("city: Zombies keeps its own zombies (ambient untouched)", E.find("set Zombies.ambient") == nil)
check("city: the hooks wired (Zombies.hunts = Jobs.involved, Crew.hasJob = Jobs.active)", E.module("Zombies").hunts == E.module("Jobs").involved and E.module("Crew").hasJob == E.module("Jobs").active)
for _, remote in { "Play", "SpawnCar", "RequestState", "Aiming" } do
	check(`city: the {remote} remote answered`, E.handlers[`Net.get({remote}).OnServerEvent`] ~= nil)
end
local carl = E.object("Carl", { Name = "Carl" })
E.fire("Net.get(Play).OnServerEvent", carl)
check("city PLAY: the call, the trip home, Marge's tutorial asked before the car", E.called("CarCall.onPlay") and E.called("Estate.onPlay") and E.called("Tutorial.ahead") and E.called("Tutorial.onPlay"))
check("city PLAY: her first day ahead keeps the van away", not E.called("Vehicles.spawn"))
E.override("Tutorial", {
	ahead = function(): boolean
		return false
	end,
})
local dora = E.object("Dora", { Name = "Dora" })
E.fire("Net.get(Play).OnServerEvent", dora)
local spawns = E.callsOf("Vehicles.spawn")
check("city PLAY: after her first day the van comes (Vehicles.spawn, force)", #spawns == 1 and spawns[1][1] == dora and spawns[1][2] == true)
check("city: it says it runs (not the sandbox)", contains(E.printed, "is running") and not contains(E.printed, "SANDBOX"))
Config.Sandbox.On = true

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
