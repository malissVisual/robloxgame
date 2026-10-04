--!strict
-- The admin tools for testing (Config.Admin): unlock everything, money, any car or gun, teleport to any landmark,
-- start any job, finish the current stop, god mode, spawn enemies, a bandit car, clear the enemies, the driver level,
-- time of day (day / night), heal, the real estate (give, take, set the home, teleport), the company's safe and the
-- missions (start any, all at 3 stars, reset). Admins (a Studio Play test, the owner of a user-owned place,
-- Config.Admin.UserIds) get the player attribute "Admin" (the client shows the panel, client/AdminPanel.luau); every
-- command is checked here again.
--
-- Commands over the "Admin" remote (name, arg):
--   unlockAll                 every car (company ones too), every gun (earned ones too), every paint, 10 of each
--                             item, every employer's progress at the top (their rewards count as earned), every
--                             property (the biggest mansion as the home if you have none) and the top driver level
--   maxUpgrades               every upgrade track at its last level
--   money      amount         + money
--   setLevel   level          the driver level (1 … Config.Levels.MaxLevel): XP = exactly what that level needs
--   car        car id         that car, now, next to you
--   weapon     weapon id      give it and put it in your hand
--   teleport   landmark id    you (and your car if you drive it) to a Map.Landmarks place
--   job        job type id    any Config.JobTypes id or "ordinary1" … "ordinary4" (Jobs.adminStart)
--   finishStop                the current stop is done (Jobs.adminFinishStop)
--   god        boolean?       toggle (or set) invulnerable: you and your car
--   spawn      kind | { kind, count }   enemies (Config.Zombies) near you; bandits, gunners and soldiers go after
--                             you for ADMIN_HUNT s even without a job (Zombies.hunts)
--   banditCar                 a bandit pickup chasing you (even without a job, BanditCars.wanted)
--   clear                     kill / remove the enemies around you and the ones after you
--   time       hour           the clock (DayNight.setClock: the night comes with it)
--   heal                      you and your car full
--   giveEstate id | "all"     a property (Config.Estate) for free, or every one (a first home becomes your home)
--   clearEstate               every property taken away (and the home: the depot), to try buying again
--   setHome    id | "depot"   the home you spawn at (an owned mansion / villa / house)
--   estateTeleport id         you to the property (its spawn spot inside, or the road at its plot)
--   businessCash amount?      your company's safe (Config.Business): + amount, or filled up to SafeCap
--   missionStart id           any mission (shared/Missions.luau) now, locks ignored (a running job is cancelled; a
--                             NIGHT ONLY mission turns the clock to night)
--   missionsAll               every mission at 3 stars, every campaign rewarded (no money; 3.1: its exclusive gun or
--                             paint and title); unlockAll does it too
--   missionsReset             the mission progress and the campaign rewards cleared
--   challengesAll             3.1: every challenge done (its money and title), every campaign's reward and the last
--                             one (Dead End) (server/Challenges.luau)
--   secretsAll                every lost package found (no money each) and their reward (Phantom)
--   challengesReset           the challenges' stats, secrets, places, titles and rewards cleared, the exclusive guns
--                             and paints taken back; the challenges the profile still reaches (kills, level,
--                             missions ...) stay done without money (the campaigns stay done: their rewards come back
--                             on the next join)
--   title      name           that title given and shown over your head ("none": no title shown); a reward's title
--                             comes without its reward

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local MissionData = require(Shared.Missions)

local Server = script.Parent
local World = require(Server.World)
local PlayerData = require(Server.PlayerData)
local Vehicles = require(Server.Vehicles)
local Zombies = require(Server.Zombies)
local BanditCars = require(Server.BanditCars)
local Jobs = require(Server.Jobs)
local DayNight = require(Server.DayNight)
local Estate = require(Server.Estate)
local Missions = require(Server.Missions)
local Challenges = require(Server.Challenges)

local Admin = {}

local notice = Net.get("Notice")
local rng = Random.new()

local CLEAR_RADIUS = 350 -- "clear" kills every enemy this close
local MAX_SPAWN = 10 -- enemies per "spawn"
local ADMIN_HUNT = 300 -- seconds the people an admin called (bandits, gunners, soldiers) go after them without a job
local GOD_FIELD = "AdminGod" -- the invisible ForceField of god mode (Humanoid:TakeDamage does nothing through it)

local god: { [Player]: boolean } = {}
local lastCommand: { [Player]: number } = {}
-- Bandit cars and bandits an admin called stay after them even without a job (BanditCars.wanted, Zombies.hunts),
-- until this time.
local chaseUntil: { [Player]: number } = {}

function Admin.isAdmin(player: Player): boolean
	if Config.Admin.InStudio and RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 and player.UserId == game.CreatorId then
		return true
	end
	return table.find(Config.Admin.UserIds, player.UserId) ~= nil
end

-- ── Helpers ────────────────────────────────────────────────────────────────

local function say(player: Player, text: string)
	notice:FireClient(player, text)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

-- $1,234,567
local function moneyText(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return "$" .. formatted
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function carName(id: string): string
	local def = Economy.findCar(id)
	return if def then def.name else id
end

-- ── Unlocks and money ──────────────────────────────────────────────────────

local function unlockAll(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	for _, car in Config.Cars do
		profile.cars[car.id] = true
	end
	for _, weapon in Config.Weapons do
		profile.weapons[weapon.id] = true
	end
	for _, paint in Config.Paints do
		profile.paints[paint.id] = true
	end
	for _, item in Config.Items do
		profile.items[item.id] = math.max(profile.items[item.id] or 0, math.min(10, item.max))
	end
	-- Every employer's jobs counted as done: their car and gun are "earned" in the windows too.
	for _, employer in Config.Employers do
		profile.rep[employer.id] = math.max(profile.rep[employer.id] or 0, employer.needed, employer.weaponAt or 0)
	end
	-- Every property (homes, garages, offices); the biggest home becomes the home if there is none.
	Estate.give(player, "all")
	-- The top driver level: nothing is locked any more (PlayerData.setLevel fires Changed).
	local level = PlayerData.setLevel(player, Config.Levels.MaxLevel)
	-- Every mission done at 3 stars (no money), and (3.1) every campaign's exclusive reward and title.
	Missions.adminAll(player)
	for _, campaign in MissionData.Campaigns do
		Challenges.campaignDone(player, campaign.id)
	end
	say(player, `ADMIN: every car, gun, paint, property, mission and employer reward unlocked, 10 of each item, level {level}. Car guns: Cars tab.`)
end

-- The driver level: the XP becomes exactly what that level needs.
local function setLevel(player: Player, arg: any)
	if type(arg) ~= "number" or arg ~= arg then
		say(player, "ADMIN: which level?")
		return
	end
	if not PlayerData.get(player) then
		say(player, "Still loading...")
		return
	end
	local level = PlayerData.setLevel(player, arg)
	say(player, `ADMIN: driver level {level} ({Levels.rank(level)}).`)
end

-- The gun on the roof of your equipped car (a Config.CarGuns id, or "none" to take it off).
local function carGun(player: Player, arg: any)
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	local carId = profile.car
	if not Economy.canMount(carId) then
		say(player, "ADMIN: this vehicle can't carry a gun (van, pickup, muscle car, monster truck, armored truck can).")
		return
	end
	if arg == "none" then
		profile.carGuns[carId] = nil
		say(player, "ADMIN: the car gun is off. Now you shoot out of the window (pistol, revolver, SMG only).")
	elseif type(arg) == "string" and Economy.findCarGun(arg) then
		profile.carGuns[carId] = arg
		local def = Economy.findCarGun(arg)
		say(player, `ADMIN: {if def then def.name else arg} on the roof.`)
	else
		say(player, "ADMIN: unknown car gun.")
		return
	end
	PlayerData.notify(player)
	Vehicles.refreshGun(player)
end

local function maxUpgrades(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	for _, upgrade in Config.Upgrades do
		profile.upgrades[upgrade.id] = upgrade.maxLevel
	end
	PlayerData.notify(player)
	Vehicles.refreshStats(player)
	say(player, "ADMIN: every upgrade at its last level.")
end

local function money(player: Player, arg: any)
	local amount = if type(arg) == "number" and arg == arg then math.clamp(math.floor(arg), 1, 10_000_000) else 10_000
	PlayerData.addMoney(player, amount)
	say(player, `ADMIN: +{amount} money.`)
end

local function car(player: Player, arg: any)
	local def = if type(arg) == "string" then Economy.findCar(arg) else nil
	if not def then
		say(player, "ADMIN: unknown car.")
		return
	end
	local err = Vehicles.spawn(player, true, def.id)
	say(player, err or `ADMIN: here is the {def.name}.`)
end

local function weapon(player: Player, arg: any)
	local def = if type(arg) == "string" then Economy.findWeapon(arg) else nil
	if not def then
		say(player, "ADMIN: unknown gun.")
		return
	end
	PlayerData.giveWeapon(player, def.id, true)
	say(player, `ADMIN: {def.name} in your hand.`)
end

-- ── Teleport ───────────────────────────────────────────────────────────────

local function findLandmark(id: string): Map.Landmark?
	for _, landmark in Map.Landmarks do
		if landmark.id == id then
			return landmark
		end
	end
	return nil
end

-- How high the chassis rides above the ground under it (kept when the car is moved).
local function rideHeight(vehicle: Vehicles.Car): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { vehicle.model }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local origin = vehicle.chassis.Position
	local hit = workspace:Raycast(origin, Vector3.new(0, -30, 0), params)
	return if hit then math.clamp(origin.Y - hit.Position.Y, 1, 8) else 3
end

local function teleport(player: Player, arg: any)
	local landmark = if type(arg) == "string" then findLandmark(arg) else nil
	if not landmark then
		say(player, "ADMIN: unknown place.")
		return
	end
	local root = rootOf(player)
	local humanoid = humanoidOf(player)
	if not root or not humanoid then
		say(player, "ADMIN: you have no body right now.")
		return
	end
	-- A road next to the place (the shops' points are inside their buildings), facing along the road.
	local rx, rz, dx, dz = Map.nearestRoad(landmark.x, landmark.z)
	local along = Vector3.new(dx, 0, dz)
	if along:Dot(Vector3.new(landmark.x - rx, 0, landmark.z - rz)) < 0 then
		along = -along
	end

	local vehicle, driving = Vehicles.seatedIn(player)
	if vehicle and driving and vehicle.owner == player then
		local ground = Vector3.new(rx, World.RoadTop, rz)
		local height = rideHeight(vehicle)
		-- The client drives the car: it must have the ground there before the car arrives (StreamingEnabled).
		pcall(function()
			player:RequestStreamAroundAsync(ground, 5)
		end)
		if not vehicle.model.Parent or vehicle.owner ~= player then
			return
		end
		vehicle.model:PivotTo(CFrame.lookAt(ground + Vector3.new(0, height + 0.5, 0), ground + Vector3.new(0, height + 0.5, 0) + along))
		vehicle.chassis.AssemblyLinearVelocity = Vector3.zero
		vehicle.chassis.AssemblyAngularVelocity = Vector3.zero
		say(player, `ADMIN: {landmark.name} (with your {carName(vehicle.id)}).`)
		return
	end
	-- On foot (or riding along: get up first). A yard or a road at the place itself, else the road next to it.
	local x, z = rx, rz
	if landmark.kind == "employer" then
		-- The point is the WORK HERE board itself: stand a few studs off it, toward the road.
		local d = Vector3.new(rx - landmark.x, 0, rz - landmark.z)
		if d.Magnitude > 1 then
			local p = Vector3.new(landmark.x, 0, landmark.z) + d.Unit * math.min(8, d.Magnitude)
			x, z = p.X, p.Z
		end
	elseif Map.onRoad(landmark.x, landmark.z) then
		x, z = landmark.x, landmark.z
	end
	if humanoid.SeatPart then
		humanoid.Sit = false
		local seatWeld = humanoid.SeatPart:FindFirstChild("SeatWeld")
		if seatWeld then
			seatWeld:Destroy()
		end
		task.wait()
	end
	local character = player.Character
	if not character then
		return
	end
	local at = Vector3.new(x, World.RoadTop + 3.5, z)
	pcall(function()
		player:RequestStreamAroundAsync(at, 5)
	end)
	if player.Character ~= character or not character.Parent then
		return
	end
	character:PivotTo(CFrame.lookAt(at, at + along))
	root.AssemblyLinearVelocity = Vector3.zero
	say(player, `ADMIN: {landmark.name}.`)
end

-- ── Real estate and the company ────────────────────────────────────────────

local function giveEstate(player: Player, arg: any)
	if not PlayerData.get(player) then
		say(player, "Still loading...")
		return
	end
	if arg == "all" then
		local given = Estate.give(player, "all")
		local home = Estate.homeOf(player)
		local def = if home then Estate.find(home) else nil
		say(player, `ADMIN: every property is yours ({given} new). Home: {if def then def.name else "the depot"}.`)
		return
	end
	local def = Estate.find(arg)
	if not def then
		say(player, "ADMIN: unknown property.")
		return
	end
	local given = Estate.give(player, def.id)
	say(player, if given > 0 then `ADMIN: {def.name} is yours.` else `ADMIN: you already own {def.name}.`)
end

local function clearEstate(player: Player)
	local count = Estate.clear(player)
	say(player, `ADMIN: {count} properties taken away. You spawn at the depot.`)
end

local function setHome(player: Player, arg: any)
	if arg == nil or arg == "depot" then
		local err = Estate.setHome(player, nil)
		if err then
			say(player, `ADMIN: {err}`)
		end
		return
	end
	local def = Estate.find(arg)
	if not def or not Estate.isHome(def.id) then
		say(player, "ADMIN: that is not a home (mansion, villa or house).")
		return
	end
	if not Estate.owns(player, def.id) then
		Estate.give(player, def.id) -- the admin way: own it first
	end
	local err = Estate.setHome(player, def.id)
	if err then
		say(player, `ADMIN: {err}`)
	end
end

-- To the property: inside at its spawn spot (homes, offices), else the road next to its plot.
local function estateTeleport(player: Player, arg: any)
	local def = Estate.find(arg)
	if not def then
		say(player, "ADMIN: unknown property.")
		return
	end
	local spawns = (World :: any).EstateSpawns
	local spot = if type(spawns) == "table" then spawns[def.id] else nil
	local at: CFrame? = nil
	if typeof(spot) == "CFrame" then
		at = spot + Vector3.new(0, 3.5, 0)
	else
		local plots = (Map :: any).EstatePlots
		local plot = if type(plots) == "table" then plots[def.id] else nil
		if type(plot) == "table" and type(plot.x) == "number" and type(plot.z) == "number" then
			local rx, rz, dx, dz = Map.nearestRoad(plot.x, plot.z)
			local ground = Vector3.new(rx, World.RoadTop + 3.5, rz)
			at = CFrame.lookAt(ground, ground + Vector3.new(dx, 0, dz))
		end
	end
	local character = player.Character
	local humanoid = humanoidOf(player)
	if not at then
		say(player, `ADMIN: {def.name} has no place on the map yet.`)
		return
	end
	if not character or not humanoid then
		say(player, "ADMIN: you have no body right now.")
		return
	end
	if humanoid.SeatPart then
		humanoid.Sit = false
		local seatWeld = humanoid.SeatPart:FindFirstChild("SeatWeld")
		if seatWeld then
			seatWeld:Destroy()
		end
		task.wait()
	end
	local target: CFrame = at
	pcall(function()
		player:RequestStreamAroundAsync(target.Position, 5)
	end)
	if player.Character ~= character or not character.Parent then
		return
	end
	character:PivotTo(target)
	local root = rootOf(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	say(player, `ADMIN: {def.name}.`)
end

-- The company's safe (server/Business.luau pays the couriers into it; COLLECT at the office takes it out).
local function businessCash(player: Player, arg: any)
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	local cap = Config.Business.SafeCap
	local company = profile.business
	if type(arg) == "number" and arg == arg then
		company.safe = math.clamp(company.safe + math.floor(arg), 0, cap)
	else
		company.safe = cap
	end
	PlayerData.notify(player)
	local office = Estate.officeOf(player)
	say(player, `ADMIN: the company safe holds {moneyText(company.safe)}.{if office then "" else " Buy an office (or giveEstate) to collect it."}`)
end

-- ── Jobs ───────────────────────────────────────────────────────────────────

local function job(player: Player, arg: any)
	if type(arg) ~= "string" then
		return
	end
	-- Jobs.adminStart tells the player itself when it cannot.
	if Jobs.adminStart(player, arg) then
		local def = Economy.findJobType(arg)
		say(player, `ADMIN: job started: {if def then def.name else arg}.`)
	end
end

local function finishStop(player: Player)
	if not Jobs.active(player) then
		say(player, "ADMIN: no job running.")
		return
	end
	say(player, if Jobs.adminFinishStop(player) then "ADMIN: stop finished." else "ADMIN: nothing to finish at this stop.")
end

-- ── Missions (server/Missions.luau) ────────────────────────────────────────

local function missionStart(player: Player, arg: any)
	local def = if type(arg) == "string" then MissionData.find(arg) else nil
	if not def then
		say(player, "ADMIN: unknown mission.")
		return
	end
	if Jobs.active(player) then
		Jobs.fail(player, "Cancelled for an admin mission.")
	end
	-- A NIGHT ONLY mission: make it night first.
	if def.twists and table.find(def.twists, "night") and not DayNight.isNight() then
		DayNight.setClock(22)
	end
	local ok, why = Missions.adminStart(player, def.id)
	say(player, if ok then `ADMIN: mission started: {def.name}.` else `ADMIN: {why or "the mission could not start"}`)
end

local function missionsAll(player: Player)
	local count = Missions.adminAll(player)
	-- 3.1: every campaign's exclusive reward too (a gun or a paint and a title).
	for _, campaign in MissionData.Campaigns do
		Challenges.campaignDone(player, campaign.id)
	end
	say(player, `ADMIN: {count} missions at 3 stars, every campaign done with its reward (no money paid).`)
end

local function missionsReset(player: Player)
	Missions.adminReset(player)
	say(player, "ADMIN: mission progress cleared. Every campaign starts at mission 1 again.")
end

-- ── Challenges, secrets, titles (3.1, server/Challenges.luau) ─────────────

local function challengesAll(player: Player)
	local count = Challenges.adminAll(player)
	say(player, `ADMIN: {count} challenges done, every campaign reward and Dead End given.`)
end

local function secretsAll(player: Player)
	local count = Challenges.adminSecrets(player)
	say(player, if count > 0 then `ADMIN: all {count} lost packages found.` else "ADMIN: there are no lost packages on the map yet.")
end

local function challengesReset(player: Player)
	local kept = Challenges.adminReset(player)
	say(player, `ADMIN: challenges, stats, secrets, places, titles and rewards cleared, exclusive guns and paints taken back. {kept} challenges your progress still reaches stay done (no money).`)
end

local function setTitle(player: Player, arg: any)
	if type(arg) ~= "string" or #arg > 40 then
		say(player, "ADMIN: which title?")
		return
	end
	local title = Challenges.adminTitle(player, arg)
	say(player, if title then `ADMIN: your title: {title}.` else "ADMIN: no title shown.")
end

-- ── God mode and healing ───────────────────────────────────────────────────

local function shield(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local field = character:FindFirstChild(GOD_FIELD)
	if god[player] and not field then
		local new = Instance.new("ForceField")
		new.Name = GOD_FIELD
		new.Visible = false
		new.Parent = character
	elseif not god[player] and field then
		field:Destroy()
	end
end

local function heal(player: Player, quiet: boolean?)
	local humanoid = humanoidOf(player)
	if humanoid and humanoid.Health < humanoid.MaxHealth then
		humanoid.Health = humanoid.MaxHealth
	end
	local vehicle = Vehicles.get(player)
	if vehicle and vehicle.health < vehicle.stats.health then
		Vehicles.repair(vehicle, 1)
	end
	if not quiet then
		say(player, "ADMIN: you and your car are as good as new.")
	end
end

local function setGod(player: Player, arg: any)
	local on = if type(arg) == "boolean" then arg else not god[player]
	if on then
		god[player] = true
	else
		god[player] = nil
	end
	player:SetAttribute("God", on)
	shield(player)
	if on then
		heal(player, true)
	end
	say(player, if on then "ADMIN: god mode ON (you and your car)." else "ADMIN: god mode OFF.")
end

-- Every frame: god-mode players and their cars stay full (a car falling into the water is put back on a road).
local function keepGods()
	for player in god do
		if not player.Parent then
			god[player] = nil
			continue
		end
		heal(player, true)
		local vehicle = Vehicles.get(player)
		if vehicle and vehicle.chassis.Position.Y < -3 then
			local position = vehicle.chassis.Position
			local x, z, dx, dz = Map.nearestRoad(position.X, position.Z)
			local at = Vector3.new(x, World.RoadTop + 4, z)
			vehicle.model:PivotTo(CFrame.lookAt(at, at + Vector3.new(dx, 0, dz)))
			vehicle.chassis.AssemblyLinearVelocity = Vector3.zero
			vehicle.chassis.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

-- ── Enemies ────────────────────────────────────────────────────────────────

local function spawnEnemies(player: Player, arg: any)
	local kind: any, count: any = arg, 1
	if type(arg) == "table" then
		kind, count = arg.kind, arg.count
	end
	if type(kind) ~= "string" or not Config.Zombies[kind] then
		say(player, "ADMIN: unknown enemy.")
		return
	end
	count = if type(count) == "number" and count == count then math.clamp(math.floor(count), 1, MAX_SPAWN) else 1
	local root = rootOf(player)
	if not root then
		return
	end
	if World.isSafe(root.Position) then
		say(player, "ADMIN: enemies burn in the safe zone. Leave it first.")
		return
	end
	if Config.Zombies[kind].jobOnly then
		chaseUntil[player] = math.max(chaseUntil[player] or 0, os.clock() + ADMIN_HUNT)
	end
	local made = 0
	for _ = 1, count do
		local spot = Zombies.findSpot(root.Position, nil, 30, 70)
		if not spot then
			-- No road around: a point on the nearest road a little away.
			local angle = rng:NextNumber(0, math.pi * 2)
			local x, z = Map.nearestRoad(root.Position.X + math.cos(angle) * 35, root.Position.Z + math.sin(angle) * 35)
			local guess = Vector3.new(x, World.RoadTop, z)
			if not World.isSafe(guess) and not Map.inWater(x, z) then
				spot = guess
			end
		end
		if spot and Zombies.spawn(kind, spot, player, false) then
			made += 1
		end
	end
	local name = Config.Zombies[kind].name
	say(player, if made > 0 then `ADMIN: {made} × {name} near you.` else "ADMIN: no room for more enemies here.")
end

local function banditCar(player: Player)
	local root = rootOf(player)
	if not root then
		return
	end
	local vehicle = Vehicles.seatedIn(player)
	local velocity = if vehicle then vehicle.chassis.AssemblyLinearVelocity else Vector3.zero
	local heading = if flat(velocity).Magnitude > 5 then velocity else root.CFrame.LookVector * 10
	chaseUntil[player] = os.clock() + Config.BanditCar.Lifetime
	if BanditCars.chase(player, root.Position, heading) then
		say(player, "ADMIN: a bandit pickup is coming after you.")
	else
		say(player, "ADMIN: no road for a bandit car here (not in the safe zone, not on the ice).")
	end
end

local function clear(player: Player)
	local root = rootOf(player)
	local killed = 0
	if root then
		for _, z in table.clone(Zombies.all()) do
			if not z.dead and (z.root.Position - root.Position).Magnitude <= CLEAR_RADIUS then
				if Zombies.damage(z, math.huge, nil) then
					killed += 1
				end
			end
		end
		killed += BanditCars.damageArea(root.Position, CLEAR_RADIUS, 1e9, nil)
	end
	-- The ones on their way to you, wherever they are.
	Zombies.clearOwner(player)
	BanditCars.clearFor(player)
	chaseUntil[player] = nil
	say(player, `ADMIN: enemies cleared ({killed} killed nearby).`)
end

-- ── World ──────────────────────────────────────────────────────────────────

local function setTime(player: Player, arg: any)
	if type(arg) ~= "number" or arg ~= arg then
		return
	end
	local hour = math.clamp(arg, 0, 24) % 24
	DayNight.setClock(hour)
	say(player, string.format("ADMIN: the time is %02d:%02d (%s).", math.floor(hour), math.floor(hour % 1 * 60), if DayNight.isNight() then "night" else "day"))
end

-- ── The remote ─────────────────────────────────────────────────────────────

local COMMANDS: { [string]: (Player, any) -> () } = {
	unlockAll = unlockAll,
	maxUpgrades = maxUpgrades,
	money = money,
	setLevel = setLevel,
	car = car,
	carGun = carGun,
	weapon = weapon,
	teleport = teleport,
	job = job,
	finishStop = finishStop,
	god = setGod,
	spawn = spawnEnemies,
	banditCar = banditCar,
	clear = clear,
	time = setTime,
	heal = function(player: Player)
		heal(player, false)
	end,
	giveEstate = giveEstate,
	clearEstate = clearEstate,
	setHome = setHome,
	estateTeleport = estateTeleport,
	businessCash = businessCash,
	missionStart = missionStart,
	missionsAll = missionsAll,
	missionsReset = missionsReset,
	challengesAll = challengesAll,
	secretsAll = secretsAll,
	challengesReset = challengesReset,
	title = setTitle,
}

local function onCommand(player: Player, name: any, arg: any)
	if not Admin.isAdmin(player) then
		return
	end
	local command = if type(name) == "string" then COMMANDS[name] else nil
	if not command then
		say(player, "ADMIN: unknown command.")
		return
	end
	-- A double click does not run it twice.
	local now = os.clock()
	if lastCommand[player] and now - lastCommand[player] < 0.15 then
		return
	end
	lastCommand[player] = now
	local ok, err = pcall(function()
		command(player, arg)
	end)
	if not ok then
		warn(`[Admin] {name} failed: {err}`)
		say(player, `ADMIN: {name} failed (see the server Output).`)
	end
end

local function onPlayer(player: Player)
	if Admin.isAdmin(player) then
		player:SetAttribute("Admin", true)
		print(`[Admin] {player.Name} is an admin: press P for the admin panel`)
	end
	player.CharacterAdded:Connect(function()
		-- God mode survives a respawn.
		task.defer(shield, player)
	end)
end

function Admin.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		god[player] = nil
		lastCommand[player] = nil
		chaseUntil[player] = nil
	end)
	Net.get("Admin").OnServerEvent:Connect(onCommand)
	RunService.Heartbeat:Connect(keepGods)

	-- Bandit cars and bandits an admin called keep after them without a job (Main set BanditCars.wanted = Jobs.active
	-- and Zombies.hunts = Jobs.involved before this).
	local function called(player: Player): boolean
		local untilTime = chaseUntil[player]
		return untilTime ~= nil and os.clock() < untilTime
	end
	local wanted = BanditCars.wanted
	BanditCars.wanted = function(player: Player): boolean
		return wanted(player) or called(player)
	end
	local hunts = Zombies.hunts
	Zombies.hunts = function(player: Player): boolean
		return hunts(player) or called(player)
	end
end

return Admin
