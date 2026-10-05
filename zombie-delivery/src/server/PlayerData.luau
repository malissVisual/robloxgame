--!strict
-- The player's progress: money, the cars and guns they own, the equipped ones, the car guns on their roofs, the upgrade
-- levels (3.3: the car tracks per car in carUpgrades, the gun tracks for all guns in upgrades; 3.5: a car's stage is
-- carUpgrades[carId].stage), the damage of every car (3.4, carHealth: a parked car keeps it until a repair shop fixes
-- it), the driver XP (the level and the rank come from it, shared/Levels.luau), the real estate (Config.Estate: the
-- properties, the home you spawn at; server/Estate.luau), the delivery company (Config.Business: couriers, upgrades,
-- the safe; server/Business.luau) and lifetime stats.
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

export type Profile = {
	money: number,
	cars: { [string]: boolean },
	car: string,
	weapons: { [string]: boolean },
	weapon: string,
	upgrades: { [string]: number }, -- the gun tracks (Config.Upgrades without car): for all your guns
	carUpgrades: { [string]: { [string]: number } }, -- 3.3: car id → the car tracks' levels of that car (Config.Upgrades car); 3.5: + stage
	carHealth: { [string]: number }, -- 3.4: car id → its share of health (0 … 1) while parked; no entry = as new
	items: { [string]: number }, -- consumables (Config.Items): how many
	paints: { [string]: boolean }, -- bought paint jobs
	carPaint: { [string]: string }, -- car id → paint id
	carGuns: { [string]: string }, -- car id → the car gun on its roof (Config.CarGuns); no entry = none
	rep: { [string]: number }, -- jobs done for each employer (Config.Employers)
	xp: number, -- driver XP (Config.Levels); older saves have none: 0
	properties: { [string]: boolean }, -- owned real estate (Config.Estate ids)
	home: string?, -- the home you spawn at (an owned mansion / villa / house), nil = the depot
	business: { couriers: number, upgrades: { [string]: number }, safe: number, lastTick: number }, -- your company (Config.Business); lastTick = os.time() of the last payout
	missions: { [string]: number }, -- the best rating (1 – 3 stars) of every mission done (shared/Missions.luau ids)
	campaigns: { [string]: boolean }, -- campaigns whose reward was paid (all ten missions done)
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
		cars = { [Config.Cars[1].id] = true },
		car = Config.Cars[1].id,
		weapons = { [Config.Weapons[1].id] = true },
		weapon = Config.Weapons[1].id,
		upgrades = {},
		carUpgrades = {},
		carHealth = {},
		items = { repair = 1, molotov = 2 },
		paints = { factory = true },
		carPaint = {},
		carGuns = {}, -- every car starts without a gun
		rep = {},
		xp = 0,
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
-- Saves from before 3.0 have none.
local function applyMissions(profile: Profile, saved: { [any]: any })
	if type(saved.missions) == "table" then
		for id, stars in saved.missions do
			if type(id) == "string" and Missions.find(id) and type(stars) == "number" and stars >= 1 then
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
	applyEstate(profile, saved)
	applyMissions(profile, saved)
	applyChallenges(profile, saved)
	if type(saved.car) == "string" and profile.cars[saved.car] then
		profile.car = saved.car
	end
	if type(saved.weapon) == "string" and profile.weapons[saved.weapon] then
		profile.weapon = saved.weapon
	end
end

local function key(player: Player): string
	return "Player_" .. player.UserId
end

function PlayerData.load(player: Player)
	local profile = newProfile()
	local ok = true
	local dataStore = store
	if dataStore then
		local saved: any = nil
		ok = false
		for attempt = 1, 3 do
			local success, result = pcall(function()
				return dataStore:GetAsync(key(player))
			end)
			if success then
				saved = result
				ok = true
				break
			end
			warn(`[PlayerData] load failed ({attempt}/3): {result}`)
			if RunService:IsStudio() then
				break -- Studio without API access: play without saving, right away
			end
			task.wait(attempt)
		end
		applySaved(profile, saved)
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

function PlayerData.save(player: Player)
	local profile = profiles[player]
	local dataStore = store
	if not profile or not dataStore or not canSave[player] then
		return
	end
	local data = {
		money = profile.money,
		cars = profile.cars,
		car = profile.car,
		weapons = profile.weapons,
		weapon = profile.weapon,
		upgrades = profile.upgrades,
		carUpgrades = profile.carUpgrades,
		carHealth = profile.carHealth,
		items = profile.items,
		paints = profile.paints,
		carPaint = profile.carPaint,
		carGuns = profile.carGuns,
		rep = profile.rep,
		xp = profile.xp,
		xpCurve = Config.Levels.Curve, -- 3.2: the XP curve the xp is on (applySaved converts older saves once)
		carStages = true, -- 3.5: the cars' room is their stages (applySaved moves a 3.4 save's cars once)
		vanStages = true, -- 4.0: the Old Van's four stages (applySaved moves a 3.5 – 3.10 save's van stage once)
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
		deliveries = profile.deliveries,
		kills = profile.kills,
		earned = profile.earned,
	}
	local success, err = pcall(function()
		dataStore:SetAsync(key(player), data)
	end)
	if not success then
		warn(`[PlayerData] save failed: {err}`)
	end
end

function PlayerData.release(player: Player)
	PlayerData.save(player)
	profiles[player] = nil
	canSave[player] = nil
end

-- 3.7: was this player's save read (so their profile is really theirs)? False while a DataStore failure plays them
-- on a fresh, unsaved profile (and in Studio without API access).
function PlayerData.loaded(player: Player): boolean
	return canSave[player] == true
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.addMoney(player: Player, amount: number)
	local profile = profiles[player]
	if not profile or amount <= 0 then
		return
	end
	profile.money += math.floor(amount)
	profile.earned += math.floor(amount)
	changed:Fire(player)
end

-- Takes the money if there is enough; true when paid.
function PlayerData.spend(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or amount < 0 or profile.money < amount then
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
	if not profile or not def then
		return false
	end
	local count = (profile.items[id] or 0) + amount
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
	if equip then
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
	local new = not profile.cars[id]
	profile.cars[id] = true
	changed:Fire(player)
	return new
end

-- ── Driver levels (Config.Levels, shared/Levels.luau) ─────────────────────

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
		for _, player in Players:GetPlayers() do
			task.spawn(PlayerData.save, player)
		end
		task.wait(2)
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
