--!strict
-- The player's progress: money, the cars and guns they own, the equipped ones, the car guns on their roofs, the upgrade
-- levels (3.3: the car tracks per car in carUpgrades, the gun tracks for all guns in upgrades; 3.5: a car's stage is
-- carUpgrades[carId].stage), the damage of every car (3.4, carHealth: a parked car keeps it until a repair shop fixes
-- it), the driver XP (the level and the rank come from it, shared/Levels.luau), the real estate (Config.Estate: the
-- properties, the home you spawn at; server/Estate.luau), the delivery company (Config.Business: couriers, upgrades,
-- the safe; server/Business.luau) and lifetime stats. 4.6: the gear of every car (carGear: Config.Gear bought for a
-- car, "owned" or "installed" in its gear slots) and the career rewards already given (levelRewards: Config.Levels
-- Rewards, each level once; shared/Career.luau). 4.7: the streak of good jobs (streak) and the licences for the
-- dangerous tiers (licences held, licenceJobs counted toward them; shared/JobRules.luau). 5.0, "From the bottom" (a
-- new DataStore, Config.DataStoreName): a new player starts on foot with no vehicle (car = nil, cars = {}), the
-- personal gear bought at Last Stop Supplies (kit: Config.Kit ids, shared/Transport.luau) and the phone Marge gives
-- in the tutorial (phone). 5.1: bikes are Config.Cars entries in cars (bike = true); the equipped `car` may be one,
-- `bike` is your bike of choice and `lastCar` the car the phone's CALL CAR brings back (server/Shops.luau). 5.4: the
-- fuel in every car you own (carFuel, litres; server/Fuel.luau keeps it, a car without an entry is full).
-- Loaded from and saved to a DataStore. In Studio without API access it simply runs without saving.
-- The player list (leaderstats) shows Level, Money and Deliveries; the player attributes Xp, Level and Rank carry the
-- driver level to every client (the HUD's XP bar, the level-up flash, the locks in the shops).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Missions = require(Shared.Missions)
local Challenges = require(Shared.Challenges)
local Career = require(Shared.Career)
local JobRules = require(Shared.JobRules)

export type Profile = {
	money: number,
	cars: { [string]: boolean },
	car: string?, -- 5.0: the equipped car; nil = no vehicle yet (on foot). 5.1: or a bike (what CAR / MY BIKE brings)
	bike: string?, -- 5.1: your bike of choice (an owned Config.Cars bike; Spoke & Chain's EQUIP, the phone's MY BIKE)
	lastCar: string?, -- 5.1: the car you drove before you got on your bike (the phone's CALL CAR brings it back)
	weapons: { [string]: boolean },
	weapon: string?, -- the gun in your hand; 6.0: nil = none yet (a new courier has fists only, Config.Arms)
	upgrades: { [string]: number }, -- the gun tracks (Config.Upgrades without car): for all your guns
	carUpgrades: { [string]: { [string]: number } }, -- 3.3: car id → the car tracks' levels of that car (Config.Upgrades car); 3.5: + stage
	carHealth: { [string]: number }, -- 3.4: car id → its share of health (0 … 1) while parked; no entry = as new
	carFuel: { [string]: number }, -- 5.4: car id → litres in its tank (Config.Fuel); no entry = full (a new car)
	carGear: { [string]: { [string]: string } }, -- 4.6: car id → gear id → "owned" | "installed" (Config.Gear)
	items: { [string]: number }, -- consumables (Config.Items): how many
	paints: { [string]: boolean }, -- bought paint jobs
	carPaint: { [string]: string }, -- car id → paint id
	carGuns: { [string]: string }, -- car id → the car gun on its roof (Config.CarGuns); no entry = none
	rep: { [string]: number }, -- jobs done for each employer (Config.Employers)
	xp: number, -- driver XP (Config.Levels); older saves have none: 0
	levelRewards: { [string]: boolean }, -- 4.6: the levels (as strings, "2" … "15") whose Config.Levels.Rewards was given
	streak: number, -- 4.7: good jobs (rated ★★ or better) in a row; a ★ job or a failed one ends it (JobRules)
	licences: { [string]: boolean }, -- 4.7: the tiers ("3", "4") whose licence is held (Config.Jobs.Licences)
	licenceJobs: { [string]: number }, -- 4.7: tier → good jobs counted toward its licence (JobRules.countJob)
	properties: { [string]: boolean }, -- owned real estate (Config.Estate ids)
	home: string?, -- the home you spawn at (an owned mansion / villa / house), nil = the depot
	business: { couriers: number, upgrades: { [string]: number }, safe: number, lastTick: number }, -- your company (Config.Business); lastTick = os.time() of the last payout
	missions: { [string]: number }, -- the best rating (1 – 3 stars) of every mission done (shared/Missions.luau ids)
	campaigns: { [string]: boolean }, -- campaigns whose reward was paid (6.8: every mission of the chapter done)
	-- 3.1, the challenges (shared/Challenges.luau), secrets (Map.Secrets) and rewards (Config.Rewards):
	stats: { [string]: number }, -- counters the challenges read (Challenges.Counters: headshots, distance, …)
	visited: { [string]: boolean }, -- places (Map.Places ids) you have been to
	secrets: { [string]: boolean }, -- secret packages found (Map.Secrets ids)
	challenges: { [string]: boolean }, -- challenges done (their reward paid)
	titles: { [string]: boolean }, -- titles earned
	rewards: { [string]: boolean }, -- Config.Rewards given (a campaign id, "secrets", "challenges"): each once
	title: string?, -- the title shown over your head and on the leaderboard (an earned one)
	tutorial: boolean, -- 3.7: the first-day tutorial is done (or skipped); older saves with a delivery count as done
	explored: string, -- 3.7: the map cells uncovered (shared/Explore.luau encodes them)
	kit: { [string]: boolean }, -- 5.0: personal gear owned (Config.Kit ids: backpacks, shoes, a jacket), yours for good
	-- 6.4: the bag you chose to hold (a Config.Kit bag you own: USE in the KIT tab or the I window's BAGS); nil = the
	-- best one owned (shared/Transport.luau activeBag decides, a choice no longer owned falls back to it too)
	activeBag: string?,
	phone: boolean, -- 5.0: Marge gave you the phone (the tutorial; client/Phone.luau)
	vanQuest: string?, -- 5.0: Earl's van (Config.VanQuest, server/VanQuest.luau): nil, "open" (Marge told you) or "done"
	deliveries: number,
	kills: number,
	earned: number,
}

local PlayerData = {}

local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {}
local changed = Instance.new("BindableEvent")

-- Fires (player) whenever money or the inventory changed, so the state is sent to the client.
PlayerData.Changed = changed.Event

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local function newProfile(): Profile
	return {
		money = Config.StartMoney,
		cars = {}, -- 5.0: you start on foot (the Old Van is bought at level 4)
		car = nil,
		bike = nil, -- 5.1
		lastCar = nil, -- 5.1
		weapons = { [Config.Arms.Starter] = true }, -- 6.0.2: the start: the phone (Marge), a pistol and the plastic bag
		weapon = Config.Arms.Starter,
		upgrades = {},
		carUpgrades = {},
		carHealth = {},
		carFuel = {}, -- 5.4: every car comes full
		carGear = {},
		items = { medkit = 1 }, -- 5.0: no repair kit (no car)
		paints = { factory = true },
		carPaint = {},
		carGuns = {}, -- every car starts without a gun
		rep = {},
		xp = 0,
		levelRewards = {},
		streak = 0,
		licences = {},
		licenceJobs = {},
		properties = {},
		home = nil,
		business = { couriers = 0, upgrades = {}, safe = 0, lastTick = 0 },
		missions = {},
		campaigns = {},
		stats = {},
		visited = {},
		secrets = {},
		challenges = {},
		titles = {},
		rewards = {},
		title = nil,
		tutorial = false,
		explored = "",
		kit = { bag = true }, -- 6.0.2: the plastic bag from the start (the vest is bought)
		activeBag = nil, -- 6.4: the best bag owned
		phone = false,
		vanQuest = nil,
		deliveries = 0,
		kills = 0,
		earned = 0,
	}
end

local function number(value: any, default: number, high: number): number
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.clamp(math.floor(value), 0, high)
end

-- ── Real estate and the company (2.6) ───────────────────────────────────────

local HOME_KINDS = { mansion = true, villa = true, house = true }

local function findEstate(id: string): Config.EstateDef?
	for _, def in Config.Estate.Properties do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- The most couriers any office allows (a saved count above it is cut down).
local function maxCouriers(): number
	local most = 0
	for _, def in Config.Estate.Properties do
		most = math.max(most, def.couriers or 0)
	end
	return most
end

-- The properties (only Config.Estate ids), the home (an owned mansion / villa / house) and the company (couriers,
-- upgrade levels, the safe, the last payout's time; all clamped). Saves from before 2.6 keep newProfile's defaults.
local function applyEstate(profile: Profile, saved: { [any]: any })
	if type(saved.properties) == "table" then
		for id, owned in saved.properties do
			if owned == true and type(id) == "string" and findEstate(id) then
				profile.properties[id] = true
			end
		end
	end
	local home = saved.home
	if type(home) == "string" and profile.properties[home] then
		local def = findEstate(home)
		if def and HOME_KINDS[def.kind] then
			profile.home = home
		end
	end
	local business = saved.business
	if type(business) == "table" then
		local company = profile.business
		company.couriers = number(business.couriers, 0, maxCouriers())
		if type(business.upgrades) == "table" then
			for _, def in Config.Business.Upgrades do
				local level = number(business.upgrades[def.id], 0, def.maxLevel)
				if level > 0 then
					company.upgrades[def.id] = level
				end
			end
		end
		company.safe = number(business.safe, 0, Config.Business.SafeCap)
		-- A time in the future (a clock that was wrong) would pay nothing for hours: it becomes now.
		company.lastTick = number(business.lastTick, 0, os.time())
	end
end

-- The missions' best ratings (only shared/Missions.luau ids, 1 – 3 stars) and the campaigns already rewarded.
-- Saves from before 3.0 have none. 6.8, the chapters: the mission ids did not change, so a save's ratings keep their
-- meaning (a rating >= 1 = done: no first-time reward again, the replay's small pay); the ids of the missions no
-- chapter tells any more (Missions.isRetired) stay in the save untouched (nothing counts them), so nothing is lost.
local function applyMissions(profile: Profile, saved: { [any]: any })
	if type(saved.missions) == "table" then
		for id, stars in saved.missions do
			if type(id) == "string" and (Missions.find(id) or Missions.isRetired(id)) and type(stars) == "number" and stars >= 1 then
				profile.missions[id] = math.clamp(math.floor(stars), 1, 3)
			end
		end
	end
	if type(saved.campaigns) == "table" then
		for id, done in saved.campaigns do
			if type(id) == "string" and done == true and Missions.findCampaign(id) then
				profile.campaigns[id] = true
			end
		end
	end
end

-- The challenges' counters (only Challenges.Counters, whole numbers ≥ 0), the places visited, the secrets found, the
-- challenges done, the titles earned, the rewards given and the title shown. Saves from before 3.1 have none. Ids are
-- only kept when they are short strings (the lists they come from are checked by server/Challenges.luau).
local function applyChallenges(profile: Profile, saved: { [any]: any })
	if type(saved.stats) == "table" then
		for _, name in Challenges.Counters do
			local value = saved.stats[name]
			if type(value) == "number" and value == value and value > 0 then
				profile.stats[name] = math.floor(math.min(value, 1e12))
			end
		end
	end
	for _, key in { "visited", "secrets", "challenges", "titles", "rewards" } do
		local list = saved[key]
		if type(list) == "table" then
			local into = (profile :: any)[key] :: { [string]: boolean }
			for id, on in list do
				if on == true and type(id) == "string" and #id <= 40 then
					into[id] = true
				end
			end
		end
	end
	if type(saved.title) == "string" and profile.titles[saved.title] then
		profile.title = saved.title
	end
end

-- 4.6, the gear of every car you own (Config.Gear, only what fits it: Economy.gearFits), never more installed than
-- the car's gear slots at its stage (the extra ones stay "owned"). A save from before 4.6 (no carGear) gets its Hand
-- Trolley upgrades (carUpgrades[carId].trolley, 4.0 – 4.5) installed as gear, once (Economy.migrateGear).
-- (After the cars and their stages are read.)
local function applyGear(profile: Profile, saved: { [any]: any })
	local list: any = saved.carGear
	if type(list) ~= "table" then
		list = Economy.migrateGear(saved.carUpgrades, profile.cars)
	end
	for carId, gear in list do
		if type(carId) ~= "string" or not profile.cars[carId] or type(gear) ~= "table" then
			continue
		end
		local slots = Economy.gearSlots(carId, Economy.stageOf(carId, Economy.carLevels(profile.carUpgrades, carId)))
		local into: { [string]: string } = {}
		local used = 0
		for _, def in Config.Gear do
			local value = gear[def.id]
			if (value == "owned" or value == "installed") and Economy.gearFits(carId, def.id) then
				if value == "installed" and used < slots then
					used += 1
					into[def.id] = "installed"
				else
					into[def.id] = "owned"
				end
			end
		end
		if next(into) ~= nil then
			profile.carGear[carId] = into
		end
	end
end

-- 4.6, the career rewards given (the levels 2 … MaxLevel as strings). A save from before 4.6 (no levelRewards) has had
-- the levels it reached: they count as given (Career.reached), nothing is paid back. (After the XP is read.)
local function applyLevelRewards(profile: Profile, saved: { [any]: any })
	local list = saved.levelRewards
	if type(list) ~= "table" then
		profile.levelRewards = Career.reached(Levels.levelFor(profile.xp))
		return
	end
	for key, given in list do
		local level = tonumber(key)
		if given == true and level and level == math.floor(level) and level >= 2 and level <= Config.Levels.MaxLevel then
			profile.levelRewards[tostring(level)] = true
		end
	end
end

-- 4.7, the streak and the licences (after the XP and the deliveries are read). A save from before 4.7 (no licences)
-- keeps the tiers its level opens if it has delivered (JobRules.grandfather); its counters start at 0.
local function applyLicences(profile: Profile, saved: { [any]: any })
	profile.streak = number(saved.streak, 0, 10000)
	local held = saved.licences
	if type(held) ~= "table" then
		profile.licences = JobRules.grandfather(Levels.levelFor(profile.xp), profile.deliveries)
	else
		for _, def in Config.Jobs.Licences do
			if held[tostring(def.tier)] == true then
				profile.licences[tostring(def.tier)] = true
			end
		end
	end
	local counts = saved.licenceJobs
	if type(counts) == "table" then
		for _, def in Config.Jobs.Licences do
			local count = number(counts[tostring(def.tier)], 0, def.jobs)
			if count > 0 then
				profile.licenceJobs[tostring(def.tier)] = count
			end
		end
	end
end

-- Saved data is checked, never trusted.
local function applySaved(profile: Profile, saved: any)
	if type(saved) ~= "table" then
		return
	end
	profile.money = number(saved.money, profile.money, 2 ^ 50)
	profile.deliveries = number(saved.deliveries, 0, 2 ^ 50)
	profile.kills = number(saved.kills, 0, 2 ^ 50)
	profile.earned = number(saved.earned, 0, 2 ^ 50)
	profile.xp = number(saved.xp, 0, 2 ^ 50) -- older saves have no xp: 0 (level 1)
	profile.tutorial = saved.tutorial == true or profile.deliveries > 0 -- 3.7: a player who delivered before needs no tutorial
	profile.explored = if type(saved.explored) == "string" and #saved.explored <= 65536 then saved.explored else ""
	profile.phone = saved.phone == true -- 5.0
	profile.vanQuest = if saved.vanQuest == "open" or saved.vanQuest == "done" then saved.vanQuest else nil -- 5.0
	if type(saved.kit) == "table" then
		for _, def in Config.Kit do
			if saved.kit[def.id] == true then
				profile.kit[def.id] = true
			end
		end
	end
	-- 6.0.1: the red courier vest became bought kit (Config.Courier.VestKit, the Courier Vest). A save from before
	-- (no vestKit flag) wore it on the body, so it is given once and the look does not change; every save is written
	-- with the flag from now on, and a brand-new profile (no save to apply) starts without the vest.
	-- 6.0.2: the start kit (a pistol and the plastic bag) given once to a save from before it
	if saved.starterKit ~= true and saved.money ~= nil then
		profile.weapons[Config.Arms.Starter] = true
		if profile.weapon == nil then
			profile.weapon = Config.Arms.Starter
		end
		profile.kit.bag = true
	end
	if saved.vestKit ~= true and saved.money ~= nil then -- (a real old save: not a lock-only record of a new player)
		profile.kit[Config.Courier.VestKit] = true
	end
	-- 6.4: the bag chosen: kept only while it is a bag you own (else nil: the best one)
	local chosen = if type(saved.activeBag) == "string" then saved.activeBag else nil
	for _, def in Config.Kit do
		if chosen ~= nil and def.id == chosen and def.extra ~= nil and profile.kit[def.id] == true then
			profile.activeBag = def.id
		end
	end
	if saved.xpCurve ~= Config.Levels.Curve then
		profile.xp = Levels.fromLegacy(profile.xp) -- 3.2: a 3.1 save, the old XP curve: it keeps its level
	end
	if type(saved.cars) == "table" then
		for id, owned in saved.cars do
			if owned == true and type(id) == "string" and Economy.findCar(id) then
				profile.cars[id] = true
			end
		end
	end
	if type(saved.weapons) == "table" then
		for id, owned in saved.weapons do
			if owned == true and type(id) == "string" and Economy.findWeapon(id) then
				profile.weapons[id] = true
			end
		end
	end
	-- 3.3: the gun tracks stay for all your guns; the car tracks are per car (carUpgrades: only cars you own that can
	-- take them, only car tracks, clamped). An older save's global car-track levels go to every car it owns, once
	-- (they are not saved in upgrades again).
	if type(saved.carUpgrades) == "table" then
		for carId, levels in saved.carUpgrades do
			if type(carId) == "string" and type(levels) == "table" and profile.cars[carId] and Economy.canUpgrade(carId) then
				-- 4.0.1: Quick Hands (the loading track, $400 · $800 · $1,600) is gone with the holds: its price back, once
				-- (it is not saved again).
				local quick = number(levels.loading, 0, 3)
				if quick > 0 then
					profile.money += 400 * (2 ^ quick - 1)
				end
				local into: { [string]: number } = {}
				for _, def in Config.Upgrades do
					local level = if def.car then number(levels[def.id], 0, def.maxLevel) else 0
					if level > 0 then
						into[def.id] = level
					end
				end
				-- 3.5: the car's stage (a 3.4 save's cars get theirs below).
				local stage = number(levels.stage, 0, Economy.maxStage(carId))
				if stage > 0 then
					into.stage = stage
				end
				if next(into) ~= nil then
					profile.carUpgrades[carId] = into
				end
			end
		end
	end
	if type(saved.upgrades) == "table" then
		for _, def in Config.Upgrades do
			profile.upgrades[def.id] = number(saved.upgrades[def.id], 0, def.maxLevel)
		end
		Economy.migrateCarUpgrades(profile.upgrades, profile.cars, profile.carUpgrades)
	end
	-- 4.0: the Old Van got two more stages (Rusty, Patched, Work, Long Cargo): a 3.5 – 3.10 save (carStages, no
	-- vanStages) keeps the room it had: its old Work Van (stage 1, 3 slots) is the Work Van (2) now, its old Cargo Van
	-- (2, 4 slots) the Long Cargo Van (3); Economy.migrateStage40, once. (A 3.4 save gets its stage below, on the new ones.)
	if saved.carStages == true and saved.vanStages ~= true then
		for carId, levels in profile.carUpgrades do
			local stage = levels.stage
			if stage and stage > 0 then
				levels.stage = Economy.migrateStage40(carId, stage)
			end
		end
	end
	-- 3.5: a save from before the stages (no carStages) keeps the room of every car it owns: each becomes the stage that
	-- holds at least the slots it had in 3.4 (Economy.legacyStage: its capacity then plus its Cargo Rack, levels.rack,
	-- gone), once: the rack is not saved again.
	if saved.carStages ~= true then
		local old = if type(saved.carUpgrades) == "table" then saved.carUpgrades else {}
		for carId in profile.cars do
			if Economy.canUpgrade(carId) then
				local levels = old[carId]
				local stage = Economy.legacyStage(carId, if type(levels) == "table" then number(levels.rack, 0, 3) else 0)
				if stage > 0 then
					local into: { [string]: number } = profile.carUpgrades[carId] or {}
					into.stage = math.max(into.stage or 0, stage)
					profile.carUpgrades[carId] = into
				end
			end
		end
	end
	-- 3.4: the damage of every car (a share of its health, for cars you own).
	if type(saved.carHealth) == "table" then
		for carId, share in saved.carHealth do
			if type(carId) == "string" and profile.cars[carId] and type(share) == "number" and share == share then
				profile.carHealth[carId] = math.clamp(share, 0, 1)
			end
		end
	end
	-- 5.4: the fuel in every car you own (litres, within its tank).
	if type(saved.carFuel) == "table" then
		for carId, litres in saved.carFuel do
			local def = if type(carId) == "string" and profile.cars[carId] then Economy.findCar(carId) else nil
			if def and def.tank and type(litres) == "number" and litres == litres then
				profile.carFuel[carId] = math.clamp(litres, 0, def.tank)
			end
		end
	end
	if type(saved.items) == "table" then
		for _, def in Config.Items do
			profile.items[def.id] = number(saved.items[def.id], 0, def.max)
		end
	end
	if type(saved.paints) == "table" then
		for id, owned in saved.paints do
			if owned == true and type(id) == "string" and Economy.findPaint(id) then
				profile.paints[id] = true
			end
		end
	end
	if type(saved.carPaint) == "table" then
		for carId, paintId in saved.carPaint do
			if type(carId) == "string" and type(paintId) == "string" and Economy.findCar(carId) and profile.paints[paintId] then
				profile.carPaint[carId] = paintId
			end
		end
	end
	-- Older saves have none: { } (no car gun anywhere).
	if type(saved.carGuns) == "table" then
		for carId, gunId in saved.carGuns do
			if type(carId) == "string" and type(gunId) == "string" and profile.cars[carId] and Economy.canMount(carId) and Economy.findCarGun(gunId) then
				profile.carGuns[carId] = gunId
			end
		end
	end
	if type(saved.rep) == "table" then
		for _, employer in Config.Employers do
			profile.rep[employer.id] = number(saved.rep[employer.id], 0, 100000)
		end
	end
	applyGear(profile, saved)
	applyLevelRewards(profile, saved)
	applyLicences(profile, saved) -- 4.7
	applyEstate(profile, saved)
	applyMissions(profile, saved)
	applyChallenges(profile, saved)
	if type(saved.car) == "string" and profile.cars[saved.car] then
		profile.car = saved.car
	end
	-- 5.1: your bike of choice and the car CALL CAR brings back (only ones you own, of the right kind).
	local function kind(id: any, bike: boolean): string?
		local def = if type(id) == "string" and profile.cars[id] then Economy.findCar(id) else nil
		return if def and (def.bike == true) == bike and not def.company then def.id else nil
	end
	profile.bike = kind(saved.bike, true)
	profile.lastCar = kind(saved.lastCar, false)
	if type(saved.weapon) == "string" and profile.weapons[saved.weapon] then
		profile.weapon = saved.weapon
	else
		profile.weapon = Economy.firstWeapon(profile.weapons) -- 6.0: a gun you own, else none
	end
end

local function key(player: Player): string
	return "Player_" .. player.UserId
end

-- 4.2: is the save held by another live server (a lock it refreshed lately)?
local function lockedElsewhere(old: any): boolean
	if type(old) ~= "table" or type(old.lock) ~= "table" then
		return false
	end
	local lock = old.lock
	return lock.job ~= game.JobId and type(lock.at) == "number" and os.time() - lock.at < Config.SaveLockStale
end

-- Reads the save and locks it to this server in one UpdateAsync. "locked" = another server still holds it (its
-- leave save is on the way); force takes it over all the same. Returns success, the save, locked.
local function readAndLock(dataStore: DataStore, player: Player, force: boolean): (boolean, any, boolean)
	local saved: any, locked = nil, false
	local success, err = pcall(function()
		dataStore:UpdateAsync(key(player), function(old: any): any
			saved, locked = old, false
			if not force and lockedElsewhere(old) then
				locked = true
				return nil -- leave it as it is
			end
			local data: { [any]: any } = if type(old) == "table" then table.clone(old) else {}
			data.lock = { job = game.JobId, at = os.time() }
			return data
		end)
	end)
	if not success then
		warn(`[PlayerData] load failed: {err}`)
	end
	return success, saved, locked
end

function PlayerData.load(player: Player)
	local profile = newProfile()
	local ok = true
	local dataStore = store
	if dataStore then
		local saved: any = nil
		ok = false
		local failures, waited = 0, 0
		while player.Parent do
			local success, result, locked = readAndLock(dataStore, player, waited >= Config.SaveLockWait)
			if success and not locked then
				saved = result
				ok = true
				break
			elseif success then
				task.wait(2) -- the last server is still writing its leave save
				waited += 2
			else
				failures += 1
				if failures >= 3 or RunService:IsStudio() then
					break -- (Studio without API access: play without saving, right away)
				end
				task.wait(failures)
			end
		end
		applySaved(profile, saved)
		if not ok and player.Parent and not RunService:IsStudio() then
			-- Never let a live player play on a profile that cannot be saved: they would lose all of it.
			player:Kick("Your save could not be loaded right now (Roblox data service). Please rejoin in a moment.")
			return
		end
	end
	if not player.Parent then
		return -- left while loading: nothing to keep (and no lock to release: the next join takes it after the wait)
	end
	-- Never overwrite a save we could not read.
	canSave[player] = ok and dataStore ~= nil
	if RunService:IsStudio() and not canSave[player] then
		profile.money = Config.StudioStartMoney
	end
	if player.Parent then
		profiles[player] = profile
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		-- The first stat is the one the player list sorts by: the best couriers on top.
		local level = Instance.new("IntValue")
		level.Name = "Level"
		level.Value = Levels.levelFor(profile.xp)
		level.Parent = stats
		local money = Instance.new("IntValue")
		money.Name = "Money"
		money.Value = profile.money
		money.Parent = stats
		local deliveries = Instance.new("IntValue")
		deliveries.Name = "Deliveries"
		deliveries.Value = profile.deliveries
		deliveries.Parent = stats
		stats.Parent = player
		changed:Fire(player)
	end
end

-- The player list shows the level, money and deliveries; the attributes carry the XP to the client.
local function updateLeaderstats(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	local levelNow = Levels.levelFor(profile.xp)
	if player:GetAttribute("Xp") ~= profile.xp then
		player:SetAttribute("Xp", profile.xp)
	end
	if player:GetAttribute("Level") ~= levelNow then
		player:SetAttribute("Level", levelNow)
		player:SetAttribute("Rank", Levels.rank(levelNow))
	end
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		return
	end
	local level = stats:FindFirstChild("Level") :: IntValue?
	local money = stats:FindFirstChild("Money") :: IntValue?
	local deliveries = stats:FindFirstChild("Deliveries") :: IntValue?
	if level then
		level.Value = levelNow
	end
	if money then
		money.Value = math.min(profile.money, 2 ^ 31 - 1)
	end
	if deliveries then
		deliveries.Value = profile.deliveries
	end
end
changed.Event:Connect(updateLeaderstats)

local saving = 0 -- saves in flight (BindToClose waits for them)
local finished: { [Player]: boolean } = {} -- the final save (leave or shutdown) has started: no more saves

-- final = the player leaves (or the server closes): the lock is released and a failed write is tried again.
function PlayerData.save(player: Player, final: boolean?)
	local profile = profiles[player]
	local dataStore = store
	if not profile or not dataStore or not canSave[player] or finished[player] then
		return
	end
	if final then
		finished[player] = true
	end
	local data = {
		money = profile.money,
		cars = profile.cars,
		car = profile.car,
		bike = profile.bike, -- 5.1
		lastCar = profile.lastCar, -- 5.1
		weapons = profile.weapons,
		weapon = profile.weapon,
		upgrades = profile.upgrades,
		carUpgrades = profile.carUpgrades,
		carHealth = profile.carHealth,
		carFuel = profile.carFuel, -- 5.4
		carGear = profile.carGear, -- 4.6
		items = profile.items,
		paints = profile.paints,
		carPaint = profile.carPaint,
		carGuns = profile.carGuns,
		rep = profile.rep,
		xp = profile.xp,
		levelRewards = profile.levelRewards, -- 4.6
		streak = profile.streak, -- 4.7
		licences = profile.licences, -- 4.7
		licenceJobs = profile.licenceJobs, -- 4.7
		xpCurve = Config.Levels.Curve, -- 3.2: the XP curve the xp is on (applySaved converts older saves once)
		carStages = true, -- 3.5: the cars' room is their stages (applySaved moves a 3.4 save's cars once)
		vanStages = true, -- 4.0: the Old Van's four stages (applySaved moves a 3.5 – 3.10 save's van stage once)
		vestKit = true, -- 6.0.1: the courier vest is bought kit (applySaved gives it once to an older save)
		starterKit = true, -- 6.0.2: the pistol and the bag of the start (applySaved gives them once to an older save)
		properties = profile.properties,
		home = profile.home,
		business = profile.business,
		missions = profile.missions,
		campaigns = profile.campaigns,
		stats = profile.stats,
		visited = profile.visited,
		secrets = profile.secrets,
		challenges = profile.challenges,
		titles = profile.titles,
		rewards = profile.rewards,
		title = profile.title,
		tutorial = profile.tutorial,
		explored = profile.explored,
		kit = profile.kit, -- 5.0
		activeBag = profile.activeBag, -- 6.4
		phone = profile.phone, -- 5.0
		vanQuest = profile.vanQuest, -- 5.0
		deliveries = profile.deliveries,
		kills = profile.kills,
		earned = profile.earned,
		lock = if final then nil else { job = game.JobId, at = os.time() }, -- 4.2: this server plays it (nil = free)
	}
	saving += 1
	for attempt = 1, if final then 4 else 1 do
		local taken = false
		local success, err = pcall(function()
			dataStore:UpdateAsync(key(player), function(old: any): any
				taken = false
				-- 5.7: a regular autosave still in flight when the leave save started (or after a RESET MY SAVE swapped
				-- the profile) writes nothing: it would put this server's lock back on a save that was just released
				-- (the next server would wait for it), or write the old profile over the new one.
				if not final and (finished[player] or profiles[player] ~= profile) then
					return nil
				end
				if type(old) == "table" and type(old.lock) == "table" and old.lock.job ~= game.JobId then
					taken = true -- another server took the save over (we were stale): never overwrite its newer data
					return nil
				end
				return data
			end)
		end)
		if success and taken then
			warn(`[PlayerData] {player.Name}'s save is held by another server; this server stops saving it`)
			canSave[player] = false
			break
		elseif success then
			break
		end
		warn(`[PlayerData] save failed ({attempt}): {err}`)
		if final and attempt < 4 then
			task.wait(attempt)
		end
	end
	saving -= 1
end

-- 4.0.5, the admin's RESET MY SAVE: the profile starts over as a new player's (the tutorial, the fog, $ and all) and is
-- saved so at once; the caller then kicks the player, so every module builds them again from the fresh save.
function PlayerData.resetSave(player: Player)
	if not profiles[player] then
		return
	end
	local fresh = newProfile()
	if RunService:IsStudio() and not canSave[player] then
		fresh.money = Config.StudioStartMoney
	end
	profiles[player] = fresh
	PlayerData.save(player)
end

function PlayerData.release(player: Player)
	-- 5.7: the leave save runs after every other PlayerRemoving handler (Business pays the last accrual, Jobs ends a
	-- job, Fuel and Vehicles store the tank and the damage): a deferred thread starts once they all had their turn.
	task.defer(function()
		PlayerData.save(player, true)
		profiles[player] = nil
		canSave[player] = nil
		finished[player] = nil -- (with the profile gone, a late autosave's transform still writes nothing)
	end)
end

-- 3.7: was this player's save read (so their profile is really theirs)? False while a DataStore failure plays them
-- on a fresh, unsaved profile (and in Studio without API access).
function PlayerData.loaded(player: Player): boolean
	return canSave[player] == true
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

-- A real, finite number: NaN or ±inf from a remote would poison the money and the items for good.
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function PlayerData.addMoney(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or not finite(amount) or amount <= 0 then
		return
	end
	profile.money += math.floor(amount)
	profile.earned += math.floor(amount)
	changed:Fire(player)
end

-- Takes the money if there is enough; true when paid.
function PlayerData.spend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or not finite(amount) or amount < 0 or profile.money < amount then
		return false
	end
	profile.money -= amount
	changed:Fire(player)
	return true
end

-- Adds (or with a negative amount takes) consumables; false when there is not enough or no room.
function PlayerData.addItem(player: Player, id: string, amount: number): boolean
	local profile = profiles[player]
	local def = Economy.findItem(id)
	if not profile or not def or not finite(amount) then
		return false
	end
	local count = (profile.items[id] or 0) + math.floor(amount)
	if count < 0 or count > def.max then
		return false
	end
	profile.items[id] = count
	changed:Fire(player)
	return true
end

-- Gives a gun (an employer's reward, the admin tools); true when it is new. equip = put it in the hand too.
function PlayerData.giveWeapon(player: Player, id: string, equip: boolean?): boolean
	local profile = profiles[player]
	if not profile or not Economy.findWeapon(id) then
		return false
	end
	local new = not profile.weapons[id]
	profile.weapons[id] = true
	if equip or profile.weapon == nil then -- (6.0: your first gun goes in your hand)
		profile.weapon = id
	end
	changed:Fire(player)
	return new
end

-- Gives a car (an employer's reward, the admin tools); true when it is new.
function PlayerData.giveCar(player: Player, id: string): boolean
	local profile = profiles[player]
	if not profile or not Economy.findCar(id) then
		return false
	end
	local def = Economy.findCar(id)
	local new = not profile.cars[id]
	profile.cars[id] = true
	if profile.car == nil and def and not def.company then
		profile.car = id -- 5.0: the first car of your own you get is the one you drive (not an employer's vehicle)
	end
	if def and def.bike and profile.bike == nil then
		profile.bike = id -- 5.1: your first bike is your bike of choice
	end
	if id == Config.VanQuest.Car then
		profile.vanQuest = "done" -- 5.0: Earl's van (bought from him, or given)
	end
	changed:Fire(player)
	return new
end

-- 5.0: gives a piece of personal gear (Config.Kit: bought at Last Stop Supplies, the admin tools); true when it is new.
function PlayerData.giveKit(player: Player, id: string): boolean
	local profile = profiles[player]
	local known = false
	for _, def in Config.Kit do
		if def.id == id then
			known = true
		end
	end
	if not profile or not known or profile.kit[id] then
		return false
	end
	profile.kit[id] = true
	changed:Fire(player)
	return true
end

-- ── Driver levels (Config.Levels, shared/Levels.luau) ─────────────────────

-- 4.6, the career: every level reached whose reward (Config.Levels.Rewards) was not given yet gives it now, once
-- (profile.levelRewards): money (counted as earned), items (up to their max), a career paint, a title (shown at once
-- when none is). The client's level-up card (client/CareerUi.luau) shows the same reward from Config.
local function giveLevelRewards(profile: Profile)
	for _, level in Career.pending(Levels.levelFor(profile.xp), profile.levelRewards) do
		profile.levelRewards[tostring(level)] = true
		local reward = Career.reward(level)
		if not reward then
			continue
		end
		local money = reward.money
		if money and money > 0 then
			profile.money += math.floor(money)
			profile.earned += math.floor(money)
		end
		if reward.items then
			for _, def in Config.Items do
				local count = reward.items[def.id]
				if count and count > 0 then
					profile.items[def.id] = math.min(def.max, (profile.items[def.id] or 0) + math.floor(count))
				end
			end
		end
		local kitCash = Career.grantKit(reward, profile.kit) -- 5.7: a backpack, the shoes (owned: their price)
		profile.money += kitCash
		profile.earned += kitCash
		local paint = reward.paint
		if paint and Economy.findPaint(paint) then
			profile.paints[paint] = true
		end
		local title = reward.title
		if title then
			profile.titles[title] = true
			if profile.title == nil then
				profile.title = title
			end
		end
	end
end

-- Adds XP; returns the new level and whether it went up.
function PlayerData.addXp(player: Player, amount: number): (number, boolean)
	local profile = profiles[player]
	if not profile then
		return 1, false
	end
	local before = Levels.levelFor(profile.xp)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return before, false
	end
	profile.xp = math.min(profile.xp + math.floor(amount + 0.5), 2 ^ 50)
	local after = Levels.levelFor(profile.xp)
	giveLevelRewards(profile) -- 4.6
	changed:Fire(player)
	return after, after > before
end

-- The player's driver level (1 when not loaded).
function PlayerData.level(player: Player): number
	local profile = profiles[player]
	return if profile then Levels.levelFor(profile.xp) else 1
end

-- The player's XP (0 when not loaded).
function PlayerData.xp(player: Player): number
	local profile = profiles[player]
	return if profile then profile.xp else 0
end

-- Sets the driver level (the admin tools): the XP becomes exactly what that level needs. Returns the level.
function PlayerData.setLevel(player: Player, level: number): number
	local profile = profiles[player]
	if not profile then
		return 1
	end
	local target = math.clamp(math.floor(level), 1, Config.Levels.MaxLevel)
	profile.xp = Levels.xpFor(target)
	giveLevelRewards(profile) -- 4.6: the levels it reached, once
	changed:Fire(player)
	return target
end

function PlayerData.notify(player: Player)
	changed:Fire(player)
end

function PlayerData.start()
	Players.PlayerAdded:Connect(function(player)
		PlayerData.load(player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerData.load, player)
	end
	Players.PlayerRemoving:Connect(PlayerData.release)
	game:BindToClose(function()
		for player in profiles do
			task.spawn(PlayerData.save, player, true)
		end
		-- Wait for every save in flight (the leave saves too), not a fixed time: up to 25 s of the 30 Roblox gives.
		local deadline = os.clock() + 25
		task.wait()
		while saving > 0 and os.clock() < deadline do
			task.wait(0.25)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			for player in profiles do
				task.spawn(PlayerData.save, player)
			end
		end
	end)
end

return PlayerData
