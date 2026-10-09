--!strict
-- The admin tools for testing (Config.Admin): unlock everything, money, any car or gun, teleport to any landmark,
-- start any job, finish the current stop, god mode, spawn enemies, a bandit car, clear the enemies, the driver level,
-- time of day (day / night), heal, the real estate (give, take, set the home, teleport), the company's safe and the
-- missions (start any, all at 3 stars, reset). Admins (a Studio Play test, the owner of a user-owned place,
-- Config.Admin.UserIds) get the player attribute "Admin" (the client shows the panel, client/AdminPanel.luau); every
-- command is checked here again.
-- 4.5, the OP admin: any player in the server as the TARGET (marked [T] below), more give commands, the OP toggles
-- (fly, noclip, speed, super jump, car boost, hidden, one-hit kills), bring / goto, the whole map's enemies killed or
-- frozen, traffic and hordes, the whole job finished, and NPC buddies (server/Buddy.luau).
--
-- 6.13: every admin's player attribute AdminAnalytics carries the analytics line (server/Analytics.luau summary: on or
-- off, what this server logged), refreshed every second; the panel's WORLD tab shows it.
--
-- Commands over the "Admin" remote (name, arg, target?): target = the UserId of a player in this server (nil: you).
-- Only [T] commands take it; the others always act on / near you. Every notice goes to the target, and a copy to you.
-- Every argument is checked here (types, NaN, ranges, ids that exist); a bad one does nothing but say so.
--   unlockAll [T]             every car (company ones too), every gun (earned ones too), every paint, 10 of each
--                             item, every employer's progress at the top (their rewards count as earned), every
--                             property (the biggest mansion as the home if you have none), the top driver level
--                             and (4.7) every licence (Config.Jobs.Licences); 5.0: every piece of kit (Config.Kit),
--                             the phone, and the Old Van as the car you drive when you had none
--   maxUpgrades [T]           every upgrade track at its last level (3.3: the car tracks of every car you own; 3.5:
--                             and every such car at its last stage)
--   money [T]  amount         + money (1 … 10 000 000)
--   xp [T]     amount         + driver XP (1 … 10 000 000)
--   setLevel [T] level        the driver level (1 … Config.Levels.MaxLevel): XP = exactly what that level needs
--   item [T]   { id, count }  a consumable (Config.Items): + count (-1000 … 1000), kept within 0 … its max
--   car [T]    car id         that car, now, next to you
--   carGun [T] id | "none"    the gun on the roof of your equipped car (Config.CarGuns)
--   carStage [T] { car, stage }   a car's stage (0 … Economy.maxStage), the car given first if you lack it; the live
--                             car is rebuilt (not during a job: then it shows from the next car call)
--   upgrade [T] { id, level } one upgrade track (Config.Upgrades) at that level (0 … maxLevel); a car track goes on
--                             your equipped car (rebuilt like carStage)
--   paint [T]  paint id       that paint (Config.Paints) given and put on your equipped car
--   weapon [T] weapon id      give it and put it in your hand
--   giveAll [T]               unlockAll (its upgrades and stages maxed) + $1 000 000
--   teleport [T] landmark id  you (and your car if you drive it) to a Map.Landmarks place
--   bring [T]                 the target to you;  goto [T]: you to the target
--   job [T]    job type id    any Config.JobTypes id, "ordinary1" … "ordinary4" or (5.0) "foot" (Jobs.adminStart)
--   finishStop [T]            the current stop is done (Jobs.adminFinishStop)
--   finishJob [T]             the whole current job done and paid (Jobs.adminComplete)
--   streak [T] n              6.14: the streak of good jobs (profile.streak, 0 … 50): the HUD's ON A ROLL chip pops
--                             (or, at 0, cracks)
--   shift [T]  n              6.14: this session's shift at n deliveries (0 … Config.Jobs.Shift.Jobs − 1; the next
--                             one paid finishes it at Jobs − 1) (server/Shift.luau)
--   roadEvent [T] kind        4.8: "survivor" | "addon" | "roadblock" on the current job as you drive on (Jobs.adminRoadEvent)
--   god [T]    boolean?       toggle (or set) invulnerable: you and your car
--   fly [T] / noclip [T] / jump [T] / carBoost [T] / hidden [T] / oneHit [T]   boolean?: toggle (or set) the player
--                             attributes AdminFly, AdminNoclip (client/AdminFly.luau), AdminJump (super jump, there
--                             too), AdminCarBoost (twice the car's top speed, client/Drive.luau), AdminHidden (no
--                             zombie or bandit goes after you: Zombies / BanditCars), AdminOneHit (every round kills:
--                             server/Gun.luau). (The guns have no ammo or reload: nothing to make infinite.)
--   speed [T]  1 | 2 | 4      the walk × that (the attribute AdminSpeed, client/CameraRig.luau)
--   clearWanted [T]           the enemies and bandit cars after the target gone (Zombies.clearOwner, BanditCars.clearFor)
--   spawn      kind | { kind, count }   enemies (Config.Zombies) near you; bandits, gunners and soldiers go after
--                             you for ADMIN_HUNT s even without a job (Zombies.hunts)
--   horde      count          a zombie wave (Config.Horde.Roam kinds, 1 … MAX_HORDE) on the roads around you
--   banditCar                 a bandit pickup chasing you (even without a job, BanditCars.wanted)
--   traffic    count          1 … 5 traffic cars on the lanes near you (Traffic.adminSpawn)
--   clear                     kill / remove the enemies around you and the ones after you
--   killAll                   every enemy and bandit car on the whole map killed
--   freeze     boolean?       toggle (or set) FREEZE: every enemy and bandit car stands still (Zombies.frozen,
--                             BanditCars.frozen; the workspace attribute AdminFrozen; off when its admin leaves)
--   time       hour           the clock (DayNight.setClock: the night comes with it)
--   heal [T]                  you and your car full
--   refuel [T] share?         5.4: the car's tank full (share 1, the default) or empty (0: try the crawl and the TOW)
--                             (server/Fuel.luau adminFill)
--   buddy [T]  count          1 … 3 NPC buddies (Buddy.spawn); buddyDismiss [T]: all gone; buddyMode [T] "follow" |
--                             "stay" | "guard". The player attributes AdminBuddies (how many) and AdminBuddyMode show it
--   giveEstate [T] id | "all" a property (Config.Estate) for free, or every one (a first home becomes your home)
--   clearEstate [T]           every property taken away (and the home: the depot), to try buying again
--   setHome [T] id | "depot"  the home you spawn at (an owned mansion / villa / house)
--   estateTeleport [T] id     you to the property (its spawn spot inside, or the road at its plot)
--   businessCash [T] amount?  your company's safe (Config.Business): + amount, or filled up to SafeCap
--   missionStart [T] id       any mission (shared/Missions.luau) now, locks ignored (a running job is cancelled; a
--                             NIGHT ONLY mission turns the clock to night)
--   missionsAll [T]           every mission at 3 stars, every campaign rewarded (no money; 3.1: its exclusive gun or
--                             paint and title); unlockAll does it too
--   missionsReset [T]         the mission progress and the campaign rewards cleared
--   challengesAll [T]         3.1: every challenge done (its money and title), every campaign's reward and the last
--                             one (Dead End) (server/Challenges.luau)
--   secretsAll [T]            every lost package found (no money each) and their reward (Phantom)
--   challengesReset [T]       the challenges' stats, secrets, places, titles and rewards cleared, the exclusive guns
--                             and paints taken back; the challenges the profile still reaches (kills, level,
--                             missions ...) stay done without money (the campaigns stay done: their rewards come back
--                             on the next join)
--   resetSave                 4.0.5: YOUR save (never another player's) starts over as a new player's (PlayerData.resetSave), then you are
--                             kicked: join again (in Studio: Play again) to start fresh, the tutorial included
--   title [T]  name           that title given and shown over your head ("none": no title shown); a reward's title
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
local Traffic = require(Server.Traffic)
local Buddy = require(Server.Buddy)

local Admin = {}

local notice = Net.get("Notice")
local rng = Random.new()

local CLEAR_RADIUS = 350 -- "clear" kills every enemy this close
local MAX_SPAWN = 10 -- enemies per "spawn"
local ADMIN_HUNT = 300 -- seconds the people an admin called (bandits, gunners, soldiers) go after them without a job
local GOD_FIELD = "AdminGod" -- the invisible ForceField of god mode (Humanoid:TakeDamage does nothing through it)
local MAX_HORDE = 30 -- zombies per "horde"
local MAX_BUDDIES = 3 -- buddies per "buddy"
local GIVE_ALL_MONEY = 1_000_000

local god: { [Player]: boolean } = {}
local lastCommand: { [Player]: number } = {}
-- Bandit cars and bandits an admin called stay after them even without a job (BanditCars.wanted, Zombies.hunts),
-- until this time.
local chaseUntil: { [Player]: number } = {}
-- 4.5: who runs the command on this target right now (another admin): the notices go to both.
local acting: { [Player]: Player } = {}
local frozenBy: Player? = nil -- the admin who turned FREEZE on

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

-- A notice to the player; when another admin runs the command on them (4.5), they see who did it and the admin gets a
-- copy with the target's name.
local function say(player: Player, text: string)
	local admin = acting[player]
	if admin and admin ~= player then
		local body = (string.gsub(text, "^ADMIN: ", ""))
		notice:FireClient(player, `ADMIN {admin.DisplayName}: {body}`)
		if admin.Parent then
			notice:FireClient(admin, `ADMIN → {player.DisplayName}: {body}`)
		end
		return
	end
	notice:FireClient(player, text)
end

-- A real, finite number from the remote (nil for anything else: NaN, ±inf, a string).
local function finite(value: any): number?
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else nil
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

-- Every upgrade track at its last level: the gun tracks, and (3.3) the car tracks of every car you own that takes them;
-- 3.5: every such car at its last stage too.
local function maxAllUpgrades(profile: PlayerData.Profile)
	for carId, owned in profile.cars do
		if owned and Economy.canUpgrade(carId) and Economy.maxStage(carId) > 0 then
			local levels: { [string]: number } = profile.carUpgrades[carId] or {}
			levels.stage = Economy.maxStage(carId)
			profile.carUpgrades[carId] = levels
		end
	end
	for _, upgrade in Config.Upgrades do
		if upgrade.car then
			for carId, owned in profile.cars do
				if owned and Economy.canUpgrade(carId) then
					local levels = profile.carUpgrades[carId] or {}
					levels[upgrade.id] = upgrade.maxLevel
					profile.carUpgrades[carId] = levels
				end
			end
		else
			profile.upgrades[upgrade.id] = upgrade.maxLevel
		end
	end
	-- 4.6: every piece of gear that fits each car, installed while it has a free gear slot (at its stage), else owned.
	for carId, owned in profile.cars do
		if owned and Economy.canUpgrade(carId) then
			local slots = Economy.gearSlots(carId, Economy.stageOf(carId, Economy.carLevels(profile.carUpgrades, carId)))
			local gear: { [string]: string } = profile.carGear[carId] or {}
			local used = Economy.gearUsed(profile.carGear, carId)
			for _, def in Config.Gear do
				if Economy.gearFits(carId, def.id) and gear[def.id] == nil then
					gear[def.id] = if used < slots then "installed" else "owned"
					used += if gear[def.id] == "installed" then 1 else 0
				end
			end
			profile.carGear[carId] = gear
		end
	end
end

local function unlockAll(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	for _, car in Config.Cars do
		profile.cars[car.id] = true
	end
	profile.vanQuest = "done" -- 5.0: Earl's van is yours already
	-- 5.0: a player still on foot drives the Old Van from now on; every piece of personal gear, and the phone.
	if profile.car == nil then
		profile.car = Config.Cars[1].id
		task.defer(function()
			if player.Parent and not Vehicles.get(player) and not Jobs.active(player) then
				Vehicles.spawn(player, true) -- it comes out to you now
			end
		end)
	end
	for _, def in Config.Kit do
		profile.kit[def.id] = true
	end
	profile.phone = true
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
	-- 4.7: every licence (the ★★★ and ★★★★ board jobs; setLevel alone does not give them).
	for _, licence in Config.Jobs.Licences do
		profile.licences[tostring(licence.tier)] = true
	end
	-- 3.3: every owned car's upgrades (and the gun tracks) at the top.
	maxAllUpgrades(profile)
	Vehicles.refreshStats(player)
	-- Every property (homes, garages, offices); the biggest home becomes the home if there is none.
	Estate.give(player, "all")
	-- The top driver level: nothing is locked any more (PlayerData.setLevel fires Changed).
	local level = PlayerData.setLevel(player, Config.Levels.MaxLevel)
	-- Every mission done at 3 stars (no money), and (3.1) every campaign's exclusive reward and title.
	Missions.adminAll(player)
	for _, campaign in MissionData.Campaigns do
		Challenges.campaignDone(player, campaign.id)
	end
	say(player, `ADMIN: every car (its upgrades and stages maxed), gun, paint, property, mission and employer reward unlocked, 10 of each item, level {level}. Car guns: Cars tab.`)
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
	if not carId then
		say(player, "ADMIN: you have no vehicle yet (unlockAll gives the Old Van).")
		return
	end
	if not Economy.canMount(carId) then
		say(player, "ADMIN: this vehicle can't carry a gun (the dealer's cars, the monster truck and the armored truck can).")
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
	maxAllUpgrades(profile)
	PlayerData.notify(player)
	Vehicles.refreshStats(player)
	say(player, "ADMIN: every upgrade and the last stage of every car you own (and the gun upgrades) at its last level.")
end

local function money(player: Player, arg: any)
	local amount = if type(arg) == "number" and arg == arg then math.clamp(math.floor(arg), 1, 10_000_000) else 10_000
	PlayerData.addMoney(player, amount, "Admin")
	say(player, `ADMIN: you got {moneyText(amount)}.`)
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

-- 4.8: a road event on the current job now (Jobs.adminRoadEvent).
local function roadEvent(player: Player, arg: any)
	say(player, if Jobs.adminRoadEvent(player, arg) then `ADMIN: road event "{arg}" comes as you drive on.` else "ADMIN: no job running (or an unknown event).")
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

-- ── 4.5: more to give ──────────────────────────────────────────────────────
-- (in a table, not more top-level locals: the 200-register limit)

local Give = {}

-- The live car takes a new stage or car track now (a rebuild); during a job it waits for the next car call. A text
-- to add to the notice ("" when it shows now, or the car is not the equipped one).
local function refreshCar(player: Player, carId: string): string
	local profile = PlayerData.get(player)
	if not profile or profile.car ~= carId then
		return ""
	end
	if Jobs.active(player) then
		return " It shows on the car after this job."
	end
	Vehicles.refreshStats(player)
	return ""
end

-- A consumable: { id, count } (count -1000 … 1000, default 1), kept within 0 … its max.
function Give.item(player: Player, arg: any)
	local id = if type(arg) == "table" then arg.id else arg
	local def = if type(id) == "string" then Economy.findItem(id) else nil
	if not def then
		say(player, "ADMIN: unknown item.")
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	local count = math.clamp(math.floor(finite(if type(arg) == "table" then arg.count else nil) or 1), -1000, 1000)
	local now = math.clamp((profile.items[def.id] or 0) + count, 0, def.max)
	profile.items[def.id] = now
	PlayerData.notify(player)
	say(player, `ADMIN: {def.name}: you have {now} (at most {def.max}).`)
end

function Give.xp(player: Player, arg: any)
	local amount = finite(arg)
	if not amount or amount < 1 then
		say(player, "ADMIN: how much XP?")
		return
	end
	if not PlayerData.get(player) then
		say(player, "Still loading...")
		return
	end
	local given = math.clamp(math.floor(amount), 1, 10_000_000)
	local level, up = PlayerData.addXp(player, given)
	say(player, `ADMIN: +{given} XP: driver level {level} ({Levels.rank(level)}){if up then ", a level up" else ""}.`)
end

-- { car, stage }: that car at that stage (given first if the player lacks it).
function Give.carStage(player: Player, arg: any)
	local carId = if type(arg) == "table" then arg.car else nil
	local def = if type(carId) == "string" then Economy.findCar(carId) else nil
	if not def then
		say(player, "ADMIN: unknown car.")
		return
	end
	local top = Economy.maxStage(def.id)
	if top <= 0 then
		say(player, `ADMIN: the {def.name} has no stages.`)
		return
	end
	local wanted = finite(arg.stage)
	if not wanted then
		say(player, "ADMIN: which stage?")
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	local stage = math.clamp(math.floor(wanted), 0, top)
	if not profile.cars[def.id] then
		PlayerData.giveCar(player, def.id)
	end
	local levels: { [string]: number } = profile.carUpgrades[def.id] or {}
	levels.stage = stage
	profile.carUpgrades[def.id] = levels
	PlayerData.notify(player)
	local stageDef = Economy.stageDef(def.id, stage)
	say(player, `ADMIN: the {def.name} at stage {stage}{if stageDef then " (" .. stageDef.name .. ")" else ""}.{refreshCar(player, def.id)}`)
end

-- { id, level }: one upgrade track at that level; a car track on the equipped car.
function Give.upgrade(player: Player, arg: any)
	local id = if type(arg) == "table" then arg.id else nil
	local def = if type(id) == "string" then Economy.findUpgrade(id) else nil
	if not def then
		say(player, "ADMIN: unknown upgrade.")
		return
	end
	local wanted = finite(arg.level)
	if not wanted then
		say(player, "ADMIN: which level?")
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	local level = math.clamp(math.floor(wanted), 0, def.maxLevel)
	if def.car then
		local carId = profile.car
		if not carId then
			say(player, "ADMIN: you have no vehicle yet (unlockAll gives the Old Van).")
			return
		end
		if not Economy.upgradeFits(carId, def.id) then
			say(player, `ADMIN: the {carName(carId)} can't take {def.name}.`)
			return
		end
		local levels: { [string]: number } = profile.carUpgrades[carId] or {}
		levels[def.id] = level
		profile.carUpgrades[carId] = levels
		PlayerData.notify(player)
		say(player, `ADMIN: {def.name} {level}/{def.maxLevel} on your {carName(carId)}.{refreshCar(player, carId)}`)
	else
		profile.upgrades[def.id] = level
		PlayerData.notify(player)
		say(player, `ADMIN: {def.name} {level}/{def.maxLevel} (all your guns).`)
	end
end

-- A paint job: yours, and on your equipped car (a company vehicle keeps its colours).
function Give.paint(player: Player, arg: any)
	local def = if type(arg) == "string" then Economy.findPaint(arg) else nil
	if not def then
		say(player, "ADMIN: unknown paint.")
		return
	end
	local profile = PlayerData.get(player)
	if not profile then
		say(player, "Still loading...")
		return
	end
	profile.paints[def.id] = true
	local carDef = if profile.car then Economy.findCar(profile.car) else nil
	if carDef and not carDef.company then
		profile.carPaint[carDef.id] = def.id
		PlayerData.notify(player)
		Vehicles.repaint(player)
		say(player, `ADMIN: {def.name} on your {carDef.name}.`)
	else
		PlayerData.notify(player)
		say(player, `ADMIN: {def.name} is yours (a company vehicle keeps its colours).`)
	end
end

function Give.giveAll(player: Player)
	if not PlayerData.get(player) then
		say(player, "Still loading...")
		return
	end
	unlockAll(player)
	PlayerData.addMoney(player, GIVE_ALL_MONEY, "Admin")
	say(player, `ADMIN: GIVE ALL: everything unlocked and maxed, and {moneyText(GIVE_ALL_MONEY)}.`)
end

-- ── 4.5: the OP toggles ────────────────────────────────────────────────────
-- Player attributes (nil = off): the clients (client/AdminFly.luau, CameraRig, Drive) and the server's modules (Gun,
-- Zombies, BanditCars) read them. They stay through a respawn and go with the player.

local FLAGS: { [string]: { attribute: string, name: string } } = {
	fly = { attribute = "AdminFly", name = "FLY (WASD where you look, Space up, Ctrl down, Shift faster)" },
	noclip = { attribute = "AdminNoclip", name = "NOCLIP (through walls)" },
	jump = { attribute = "AdminJump", name = "SUPER JUMP" },
	carBoost = { attribute = "AdminCarBoost", name = "CAR BOOST (twice the top speed)" },
	hidden = { attribute = "AdminHidden", name = "HIDDEN (zombies and bandits ignore you)" },
	oneHit = { attribute = "AdminOneHit", name = "ONE-HIT KILLS" },
}

local function setFlag(player: Player, command: string, arg: any)
	local flag = FLAGS[command]
	local on = if type(arg) == "boolean" then arg else player:GetAttribute(flag.attribute) ~= true
	player:SetAttribute(flag.attribute, if on then true else nil)
	say(player, `ADMIN: {flag.name} {if on then "ON" else "OFF"}.`)
end

function Give.speed(player: Player, arg: any)
	local value = finite(arg)
	if value ~= 1 and value ~= 2 and value ~= 4 then
		say(player, "ADMIN: the walking speed is 1×, 2× or 4×.")
		return
	end
	player:SetAttribute("AdminSpeed", if value == 1 then nil else value)
	say(player, `ADMIN: walking speed {value}×.`)
end

-- A character (out of its seat first) to a spot; true when it went.
local function moveCharacter(player: Player, at: CFrame): boolean
	local character = player.Character
	local humanoid = humanoidOf(player)
	if not character or not humanoid then
		return false
	end
	local seat = humanoid.SeatPart
	if seat then
		humanoid.Sit = false
		local seatWeld = seat:FindFirstChild("SeatWeld")
		if seatWeld then
			seatWeld:Destroy()
		end
		task.wait()
	end
	pcall(function()
		player:RequestStreamAroundAsync(at.Position, 5)
	end)
	if player.Character ~= character or not character.Parent then
		return false
	end
	character:PivotTo(at)
	local root = rootOf(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
	return true
end

-- A spot next to a player (a few studs to their right, facing the way they face).
local function besideOf(player: Player): CFrame?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local flatLook = flat(root.CFrame.LookVector)
	local look = if flatLook.Magnitude > 0.01 then flatLook.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local at = root.Position + right * 6 + Vector3.new(0, 1, 0)
	return CFrame.lookAt(at, at + look)
end

-- The target to you.
function Give.bring(player: Player, _arg: any, admin: Player)
	if player == admin then
		say(admin, "ADMIN: pick another player as the TARGET first.")
		return
	end
	local at = besideOf(admin)
	if not at then
		say(admin, "ADMIN: you have no body right now.")
		return
	end
	say(player, if moveCharacter(player, at) then `ADMIN: you were brought to {admin.DisplayName}.` else "ADMIN: no body to bring right now.")
end

-- You to the target.
Give["goto"] = function(player: Player, _arg: any, admin: Player)
	if player == admin then
		say(admin, "ADMIN: pick another player as the TARGET first.")
		return
	end
	local at = besideOf(player)
	if not at then
		say(admin, `ADMIN: {player.DisplayName} has no body right now.`)
		return
	end
	notice:FireClient(admin, if moveCharacter(admin, at) then `ADMIN: you are with {player.DisplayName}.` else "ADMIN: you have no body right now.")
end

-- The enemies and bandit cars after the target gone (and the ones an admin called).
function Give.clearWanted(player: Player)
	Zombies.clearOwner(player)
	BanditCars.clearFor(player)
	chaseUntil[player] = nil
	say(player, "ADMIN: nobody is after you any more (your enemies and bandit cars are gone).")
end

-- ── 4.5: the world ─────────────────────────────────────────────────────────

-- Every enemy and bandit car on the whole map.
function Give.killAll(player: Player)
	local killed = 0
	for _, z in table.clone(Zombies.all()) do
		if not z.dead and Zombies.damage(z, math.huge, nil) then
			killed += 1
		end
	end
	killed += BanditCars.damageArea(Vector3.zero, 1e7, 1e9, nil)
	say(player, `ADMIN: {killed} enemies killed on the whole map.`)
end

function Give.freeze(player: Player, arg: any)
	local on = if type(arg) == "boolean" then arg else not Zombies.frozen
	Zombies.frozen = on
	BanditCars.frozen = on
	frozenBy = if on then player else nil
	workspace:SetAttribute("AdminFrozen", if on then true else nil)
	say(player, if on then "ADMIN: FREEZE ON: every enemy and bandit car stands still." else "ADMIN: FREEZE OFF: the enemies move again.")
end

function Give.horde(player: Player, arg: any)
	local count = math.clamp(math.floor(finite(arg) or 10), 1, MAX_HORDE)
	local root = rootOf(player)
	if not root then
		return
	end
	if World.isSafe(root.Position) then
		say(player, "ADMIN: enemies burn in the safe zone. Leave it first.")
		return
	end
	local made = Zombies.spawnAround(player, root.Position, nil, count, Config.Horde.Roam.kinds)
	say(player, if made > 0 then `ADMIN: a horde of {made} on the roads around you.` else "ADMIN: no room for more enemies here.")
end

function Give.traffic(player: Player, arg: any)
	local count = math.clamp(math.floor(finite(arg) or 1), 1, 5)
	local root = rootOf(player)
	if not root then
		return
	end
	local made = 0
	for _ = 1, count do
		if Traffic.adminSpawn(root.Position) then
			made += 1
		end
	end
	say(player, if made > 0 then `ADMIN: {made} traffic car{if made > 1 then "s" else ""} on the lanes near you.` else "ADMIN: no traffic lane near you.")
end

-- ── 4.5: the jobs ──────────────────────────────────────────────────────────

function Give.finishJob(player: Player)
	if not Jobs.active(player) then
		say(player, "ADMIN: no job of your own running (a crew member's job is finished by its leader).")
		return
	end
	say(player, if Jobs.adminComplete(player) then "ADMIN: the whole job is done and paid." else "ADMIN: the job could not be finished.")
end

-- 6.14: the streak of good jobs and the shift, to try the HUD's chips and SHIFT DONE.
function Give.streak(player: Player, arg: any)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.streak = math.clamp(math.floor(finite(arg) or 0), 0, 50)
	PlayerData.notify(player)
	say(player, `ADMIN: your streak of good jobs is {profile.streak}.`)
end

function Give.shift(player: Player, arg: any)
	local count = require(Server.Shift).set(player, finite(arg) or 0)
	say(player, `ADMIN: your shift is at {count} / {Config.Jobs.Shift.Jobs} (the next delivery paid counts on).`)
end

-- ── 4.5: the buddies (server/Buddy.luau) ───────────────────────────────────

local BUDDY_MODES: { [string]: boolean } = { follow = true, stay = true, guard = true }

local function showBuddies(player: Player)
	if player.Parent then
		player:SetAttribute("AdminBuddies", Buddy.count(player))
	end
end

function Give.buddy(player: Player, arg: any)
	local count = math.clamp(math.floor(finite(arg) or 1), 1, MAX_BUDDIES)
	local before = Buddy.count(player)
	local now = Buddy.spawn(player, count)
	showBuddies(player)
	if player:GetAttribute("AdminBuddyMode") == nil then
		player:SetAttribute("AdminBuddyMode", "follow")
	end
	say(player, if now > before then `ADMIN: {now - before} {if now - before == 1 then "buddy" else "buddies"} with you ({now} in all).` else `ADMIN: no more buddies ({now} is the most).`)
end

function Give.buddyDismiss(player: Player)
	Buddy.dismiss(player)
	showBuddies(player)
	say(player, "ADMIN: your buddies are gone.")
end

function Give.buddyMode(player: Player, arg: any)
	if type(arg) ~= "string" or not BUDDY_MODES[arg] then
		say(player, "ADMIN: the buddies follow, stay or guard.")
		return
	end
	Buddy.setMode(player, arg :: Buddy.Mode)
	player:SetAttribute("AdminBuddyMode", arg)
	say(player, `ADMIN: your buddies {if arg == "follow" then "follow you" elseif arg == "stay" then "stay where they are" else "guard this spot"}.`)
end

-- ── The remote ─────────────────────────────────────────────────────────────

local COMMANDS: { [string]: (Player, any, Player) -> () } = {
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
	roadEvent = roadEvent, -- 4.8
	god = setGod,
	spawn = spawnEnemies,
	banditCar = banditCar,
	clear = clear,
	time = setTime,
	heal = function(player: Player)
		heal(player, false)
	end,
	refuel = function(player: Player, arg: any) -- 5.4
		say(player, require(Server.Fuel).adminFill(player, if type(arg) == "number" then arg else nil))
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
	resetSave = function(player: Player)
		PlayerData.resetSave(player)
		player:Kick("ADMIN: your save was reset. Join again to start as a new player.")
	end,
	-- 4.5
	item = Give.item,
	xp = Give.xp,
	carStage = Give.carStage,
	upgrade = Give.upgrade,
	paint = Give.paint,
	giveAll = Give.giveAll,
	speed = Give.speed,
	bring = Give.bring,
	["goto"] = Give["goto"],
	clearWanted = Give.clearWanted,
	killAll = Give.killAll,
	freeze = Give.freeze,
	horde = Give.horde,
	traffic = Give.traffic,
	finishJob = Give.finishJob,
	streak = Give.streak, -- 6.14
	shift = Give.shift, -- 6.14
	buddy = Give.buddy,
	buddyDismiss = Give.buddyDismiss,
	buddyMode = Give.buddyMode,
}
for command in FLAGS do
	COMMANDS[command] = function(player: Player, arg: any)
		setFlag(player, command, arg)
	end
end

-- 4.5: the commands that take a target (another player in the server); the others always act on / near the admin.
local TARGETED: { [string]: boolean } = {}
for _, name in {
	"unlockAll", "maxUpgrades", "money", "xp", "setLevel", "item", "car", "carGun", "carStage", "upgrade", "paint",
	"weapon", "giveAll", "teleport", "bring", "goto", "job", "finishStop", "finishJob", "roadEvent", "god", "heal", "refuel", "speed",
	"clearWanted", "buddy", "buddyDismiss", "buddyMode", "giveEstate", "clearEstate", "setHome", "estateTeleport",
	"businessCash", "missionStart", "missionsAll", "missionsReset", "challengesAll", "secretsAll", "challengesReset",
	"title", "streak", "shift",
} do
	TARGETED[name] = true
end
for command in FLAGS do
	TARGETED[command] = true
end

local function onCommand(player: Player, name: any, arg: any, targetId: any)
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
	-- 4.5: the target (a player in this server), else you.
	local target = player
	local id = finite(targetId)
	if targetId ~= nil and TARGETED[name] and id ~= player.UserId then
		local found = if id and id >= 1 and id <= 2 ^ 53 then Players:GetPlayerByUserId(math.floor(id)) else nil
		if not found or found.Parent ~= Players then
			say(player, "ADMIN: that player is not in this server any more.")
			return
		end
		target = found
	end
	if target ~= player then
		acting[target] = player
	end
	local ok, err = pcall(function()
		command(target, arg, player)
	end)
	if acting[target] == player then
		acting[target] = nil
	end
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
		-- God mode survives a respawn (and so do the OP toggles: they are player attributes).
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
		acting[player] = nil
		for target, admin in acting do
			if admin == player then
				acting[target] = nil
			end
		end
		-- FREEZE goes with the admin who turned it on.
		if frozenBy == player then
			frozenBy = nil
			Zombies.frozen = false
			BanditCars.frozen = false
			workspace:SetAttribute("AdminFrozen", nil)
		end
	end)
	Net.get("Admin").OnServerEvent:Connect(onCommand)
	RunService.Heartbeat:Connect(keepGods)
	-- 4.5: the buddies' count (the panel shows it) for the players who have had buddies; a buddy may fall meanwhile.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				if player:GetAttribute("AdminBuddies") ~= nil then
					pcall(showBuddies, player)
				end
				-- 6.13: the panel's Analytics line (WORLD): on or off and this server's counts (server/Analytics.luau)
				if player:GetAttribute("Admin") == true then
					pcall(function()
						player:SetAttribute("AdminAnalytics", require(Server.Analytics).summary())
					end)
				end
			end
		end
	end)

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
