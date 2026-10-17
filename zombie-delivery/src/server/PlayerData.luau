--!strict
-- The player's progress (10.5: only the sandbox is the game), loaded from and saved to the sandbox's DataStore
-- (Config.Sandbox.Store, ZombieDelivery_v2_Sandbox; the key Player_<UserId> and the 10.1 slots' own keys, the lock).
-- In Studio without API access it simply runs without saving.
--
-- The profile: the money; the van (cars / car: Config.Sandbox.Van, SandboxBoot's ownVan keeps it the save's one car)
-- and what server/Vehicles.luau builds it with (carUpgrades, carHealth, carGear, carPaint, carGuns: as the save has
-- them); the XP (the level and the rank, shared/Levels.luau; a kill's XP) and the level rewards given (levelRewards:
-- Config.Levels Rewards' money, each level once; shared/Career.luau); rewards (short keys an older server keeps:
-- "book:<id>", "mv:<n>", "paint:<id>", "warehouse:<k>", the one-car flag, the chapters done of old); the counters
-- (deliveries, kills, earned) and every sandbox field, each read only from a real save written with its flag:
--   8.0 the collection (collection: the pieces the runs brought home, shared/CollectionRules.luau; server/Collection
--       .luau keeps it; collectionKept); 8.2 the collection book (collectionBook: { [item]: { n, best } },
--       collectionBookPaid: { [milestone id]: true }; shared/CollectionBookRules.luau; collectionBookKept: an older real
--       save fills the book from its stock); 8.1 the upgrades bought at the UPGRADES desk (sandboxUpgrades: { [id]:
--       level }, shared/UpgradeRules.luau; sandboxUpgradesKept; 8.3 the warehouse's level one of them, every save
--       written with warehouseLevelKept: a real save without it gets warehouse = 3, UpgradeRules.fromSave); 8.2 the
--       onboarding funnel's steps (sandboxOnboarding, AnalyticsPlan.SandboxSteps' bits; sandboxOnboardingKept: an older
--       real save is past every step); 8.2 the daily tasks (sandboxTasks, shared/SandboxTasks.luau; sandboxTasksKept);
--       8.3 the moves finished (sandboxMoves, the badges; sandboxMovesKept, or its "mv:<n>" key); 8.3 the market's
--       demand (market, shared/Market.luau; marketKept); 8.3 the van's paint (vanPaint, shared/VanPaintRules.luau;
--       vanPaintKept, or its "paint:" keys); 8.4 the house the next run's card has (sandboxHouseSeed, a whole number
--       1 … Config.Moving.Sandbox.Seeds; sandboxHouseSeedKept) and 8.9 which house (sandboxHouse, a SandboxMap.Houses id;
--       sandboxHouseKept; a real save from before with a seed: the farmstead's); 9.7 the runs' difficulties open
--       (runUnlocked, shared/RunRules.luau; runUnlockedKept); 10.1 the helpers' crew (crew, shared/CrewRules.luau;
--       crewKept).
-- 10.1, the save slots (Config.SaveSlots, shared/SaveSlotRules.luau): a player has Count saves, each its own game. With
-- PlayerData.chooseSlot set (server/SaveSlots.luau) a join's load waits for the start screen's pick: the slot (its key:
-- slot 1 the save of before, "Player_<id>"), a fresh game in it (START OVER, NEW GAME: the stored save is not read, a
-- new one is written at once) and the courier made for it (profile.character: shared/CharacterLooks.luau's look and its
-- name, read from a real save only); unset (the tests): slot 1 at once. Every save also writes the time played
-- (playTime, s: this session's added at each save) and when (savedAt, os.time) for the start screen's cards.
-- 10.5, the save stays the sandbox's as it was: the same store, keys, slots and lock; every sandbox field and its flag;
-- the city's boolean flags still written (xpCurve, carStages, vanStages, vestKit, starterKit, noPacks, noJacket,
-- noShoes, perGameBags, vanOnly: an older server reading a save of this one never pays a refund or gives a kit twice).
-- The city's fields a loaded save has (its guns, kit, tutorial, phone, wardrobe, skills, tasks, story …) are no field of
-- this version any more: as every key it does not know, they are written back as they were (SaveGuard, below).
-- 6.13, analytics (server/Analytics.luau): every money change tells its reason (addMoney / spend's `reason` and `sku`,
-- the level rewards) to PlayerData.onMoney; the game's other analytics calls go through PlayerData.track (the hooks
-- Analytics.start puts in PlayerData.analytics: without them nothing happens, so the game never depends on
-- server/Analytics.luau loading).
-- 8.3 SAVES (Config.Saving, shared/SaveGuard.luau): a save is written (UpdateAsync) only while the stored save is still
-- this server's session's (its lock: the JobId, the session and the save's number: never over another server's save
-- or over a newer snapshot), checked on its way (SaveGuard.clean: one bad value never costs the whole save; a bad money
-- keeps the stored one), with the top-level keys of the loaded save this version does not know put back (a newer
-- server's fields, and 10.5 the city's, survive a round trip through this one), and tried again after a backoff. When:
-- the autosave (every AutosaveSeconds; a player written a moment ago waits for the next round, and so does every save
-- that can wait while the request budget is under Reserve), a save soon after a purchase (PlayerData.spend), a book
-- milestone or pieces brought home (PlayerData.saveSoon: one for a burst), the leave save and the shutdown's (all at
-- once, waited for). A load that fails, or a save that cannot be read without an error, never gets a fresh profile that
-- would be saved over the real one: a live player is kicked. A rejoin to this server waits for its own leave save of
-- that player.
-- The player list (leaderstats) shows Level, Money and Deliveries; the player attributes Xp, Level and Rank carry the
-- level to every client.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Levels = require(Shared.Levels)
local Career = require(Shared.Career) -- 4.6: the level rewards
local AnalyticsPlan = require(Shared.AnalyticsPlan) -- 8.2: the onboarding funnel's steps in the save
local CollectionRules = require(Shared.CollectionRules) -- 8.0: the collection (profile.collection, server/Collection.luau)
local CharacterLooks = require(Shared.CharacterLooks) -- 10.1: the courier made for a slot
local SaveSlotRules = require(Shared.SaveSlotRules) -- 10.1: the slots' keys
local CollectionBookRules = require(Shared.CollectionBookRules) -- 8.2: the collection book (profile.collectionBook)
local UpgradeRules = require(Shared.UpgradeRules) -- 8.1: the sandbox's upgrades (profile.sandboxUpgrades, server/Upgrades.luau)
local SandboxTaskRules = require(Shared.SandboxTasks) -- 8.2: the sandbox's daily tasks (profile.sandboxTasks)
local Market = require(Shared.Market) -- 8.3: the market's demand (profile.market, server/Collection.luau)
local VanPaintRules = require(Shared.VanPaintRules) -- 8.3: the van's paint (profile.vanPaint, server/VanPaint.luau)
local SaveGuard = require(Shared.SaveGuard) -- 8.3 saves: what a save writes, checked; the unknown keys kept

export type Profile = {
	money: number,
	cars: { [string]: boolean }, -- the van (Config.Sandbox.Van: SandboxBoot's ownVan keeps it the one car)
	car: string?, -- the van it is
	carUpgrades: { [string]: { [string]: number } }, -- 3.3: car id → its tracks' levels (+ 3.5 stage): server/Vehicles.luau
	carHealth: { [string]: number }, -- 3.4: car id → its share of health (0 … 1) while parked; no entry = as new
	carGear: { [string]: { [string]: string } }, -- 4.6: car id → gear id → "owned" | "installed" (Config.Gear)
	carPaint: { [string]: string }, -- car id → paint id (Config.Paints)
	carGuns: { [string]: string }, -- car id → the gun on its roof (Config.CarGuns); no entry = none
	xp: number, -- the XP (Config.Levels: the level and the rank)
	levelRewards: { [string]: boolean }, -- 4.6: the levels (as strings, "2" … ) whose Config.Levels.Rewards was given
	rewards: { [string]: boolean }, -- short keys an older server keeps ("book:<id>", "mv:<n>", "paint:<id>", "warehouse:<k>" …)
	-- 8.2 SANDBOX: the onboarding funnel's steps reached (a bit a step of AnalyticsPlan.SandboxSteps): read only from a
	-- real save written with its flag (AnalyticsPlan.sandboxFrom); an older real save is past every step
	sandboxOnboarding: number,
	-- 8.0 SANDBOX: the pieces the runs brought home (shared/CollectionRules.luau; server/Collection.luau keeps it): read
	-- only from a real save written with its flag (CollectionRules.fromSave); an older one starts with the empty one
	collection: CollectionRules.Saved,
	-- 8.2 SANDBOX: the collection book (shared/CollectionBookRules.luau; server/CollectionBook.luau keeps it): every piece
	-- ever brought home ({ n, best }) and the milestones paid; read only from a real save written with its flag
	-- (CollectionBookRules.fromSave); an older real save's is its stock's
	collectionBook: CollectionBookRules.Book,
	collectionBookPaid: CollectionBookRules.Paid,
	-- 8.1 SANDBOX: the upgrades bought ({ [id]: level }, shared/UpgradeRules.luau; server/Upgrades.luau): read only from a
	-- real save written with its flag (UpgradeRules.fromSave); an older one has none
	sandboxUpgrades: UpgradeRules.Levels,
	-- 8.2 SANDBOX: the daily tasks (shared/SandboxTasks.luau: the day's picks and progress, the week's): read only from a
	-- real save written with its flag (SandboxTasks.fromSave); nil until server/SandboxTasks.luau starts them
	sandboxTasks: SandboxTaskRules.Saved?,
	-- 8.3 SANDBOX: the moves finished, done or late with pieces home (server/SandboxBadges.luau: the badges): read only
	-- from a real save written with its flag (SandboxBadgeRules.movesFromSave); an older one starts at 0
	sandboxMoves: number,
	-- 8.3 SANDBOX: the market's demand (shared/Market.luau: the kinds sold today, what each weighs on its price): read only
	-- from a real save written with its flag (Market.fromSave); an older one starts with the empty one
	market: Market.Saved,
	-- 8.3 SANDBOX: the van's paint (shared/VanPaintRules.luau: the paints and liveries bought, the ones worn): read only
	-- from a real save written with its flag (VanPaintRules.fromSave); an older one starts with the empty one
	vanPaint: VanPaintRules.Saved,
	-- 8.4 SANDBOX: the seed of the house the next run's card has (server/Moving.luau sets and drops it with SB.seeds):
	-- read only from a real save written with its flag (sandboxHouseSeedKept), a whole number 1 …
	-- Config.Moving.Sandbox.Seeds; nil: none yet (the next card rolls one)
	sandboxHouseSeed: number?,
	-- 8.9: the house of that card (a SandboxMap.Houses id; the seed nil: the house emptied last), read only from a
	-- real save written with its flag (sandboxHouseKept); an older real save with a seed: the farmstead's; nil: none yet
	sandboxHouse: string?,
	-- 10.1: the courier made for this slot (a look and its name, shared/CharacterLooks.luau), read from a real save only;
	-- nil: the player's own Roblox avatar
	character: CharacterLooks.Look?,
	playTime: number, -- 10.1: s played in this slot (the start screen's card)
	-- 9.7 RUNS: how many of the runs' difficulties are open (shared/RunRules.luau: Config.Runs.Open at first, one more
	-- for a run finished at the hardest open one): read only from a real save written with its flag (runUnlockedKept)
	runUnlocked: number,
	-- 10.1 the helpers' crew (shared/CrewRules.luau; server/HelperCrew.luau keeps it): who you have (Danny always), your
	-- pick for runs, who is in hospital until when (os.time()): read only from a real save written with its flag
	-- (Config.Crew.Flag); anything else, an older save too, starts with Danny alone
	crew: any,
	deliveries: number,
	kills: number,
	earned: number,
}

local PlayerData = {}

local profiles: { [Player]: Profile } = {}
local canSave: { [Player]: boolean } = {}
-- 8.3 saves: each player's session here (the lock's `session`), the top-level keys of their loaded save this version
-- does not know (written back with every save) and that copy's size, their last write (os.clock), their saves'
-- number (the lock's `seq`), a save asked for soon; the leave saves running (by UserId: a rejoin waits for them); every
-- top-level key this version writes (PlayerData.start builds it: SaveGuard.probe) and what a save writes (build,
-- defined at PlayerData.save).
local sessions: { [Player]: string } = {}
local extras: { [Player]: { data: { [string]: any }, bytes: number } } = {}
local wrote: { [Player]: number } = {}
local serial: { [Player]: number } = {}
local soon: { [Player]: boolean } = {}
local leaving: { [number]: number } = {}
-- 10.1: the slot each player plays (no entry: slot 1) and when their time played was last added (os.clock)
local slots: { [Player]: { slot: number, ticked: number? } } = {}
local known: { [string]: boolean }? = nil
local build: (profile: Profile, lock: any) -> { [string]: any }
local changed = Instance.new("BindableEvent")

-- Fires (player) whenever money or the inventory changed, so the state is sent to the client.
PlayerData.Changed = changed.Event

-- 6.13, set by server/Analytics.luau: money moved (delta > 0 came in, < 0 went out) for a reason
-- (shared/AnalyticsPlan.luau Sources / Sinks; nil: "Other") and the item's id. In a pcall: it never stops a payment.
PlayerData.onMoney = nil :: ((player: Player, delta: number, reason: string?, sku: string?) -> ())?

local function tellMoney(player: Player, delta: number, reason: string?, sku: string?)
	local hook = PlayerData.onMoney
	if hook and delta ~= 0 then
		pcall(hook, player, delta, reason, sku)
	end
end

-- 6.13, filled by server/Analytics.luau's start: its hooks by name (onPlay, step, died, event, money). The game calls them only through PlayerData.track, never by requiring
-- Analytics: a hook that is missing (Analytics did not load or start) does nothing, one that errors is caught.
PlayerData.analytics = {} :: { [string]: (...any) -> () }

function PlayerData.track(name: string, ...: any)
	local hook = PlayerData.analytics[name]
	if hook then
		pcall(hook, ...)
	end
end

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Config.Sandbox.Store) -- (8.0: the sandbox's own saves; the city's never touched)
end)

local function newProfile(): Profile
	return {
		money = Config.Sandbox.StartMoney,
		cars = { [Config.CompanyVan.Car] = true },
		car = Config.CompanyVan.Car,
		carUpgrades = {},
		carHealth = {},
		carGear = {},
		carPaint = {},
		carGuns = {},
		xp = 0,
		levelRewards = {},
		rewards = {},
		sandboxOnboarding = 0, -- 8.2: no step of the funnel yet
		collection = CollectionRules.empty(), -- 8.0: nothing brought home yet
		collectionBook = CollectionBookRules.empty(), -- 8.2: nothing found yet
		collectionBookPaid = {}, -- 8.2: no milestone paid yet
		sandboxUpgrades = UpgradeRules.empty(), -- 8.1: no upgrade bought yet
		sandboxTasks = nil, -- 8.2: server/SandboxTasks.luau starts them (it knows the UserId and the day)
		sandboxMoves = 0, -- 8.3: no move finished yet (the badges)
		market = Market.empty(), -- 8.3: nothing sold yet
		vanPaint = VanPaintRules.empty(), -- 8.3: nothing bought, the factory's look
		sandboxHouseSeed = nil, -- 8.4: no house rolled yet
		sandboxHouse = nil, -- none of the houses yet
		character = nil, -- 10.1: the player's own avatar until a courier is made
		playTime = 0, -- 10.1
		runUnlocked = Config.Runs.Open, -- 9.7: Easy and Normal
		crew = require(Shared.CrewRules).empty(), -- 10.1: Danny, free, picked
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

-- The rewards' short keys (`true` ones, short strings: "book:<id>", "mv:<n>", "paint:<id>", "warehouse:<k>" and the city's
-- of old, kept as they were).
local function applyRewards(profile: Profile, saved: { [any]: any })
	local list = saved.rewards
	if type(list) == "table" then
		for id, on in list do
			if on == true and type(id) == "string" and #id <= 40 then
				profile.rewards[id] = true
			end
		end
	end
end

-- 4.6, the gear of every car you own (Config.Gear, only what fits it: Economy.gearFits), never more installed than
-- the car's gear slots at its stage (the extra ones stay "owned"). (After the cars and their stages are read.)
local function applyGear(profile: Profile, saved: { [any]: any })
	local list: any = saved.carGear
	if type(list) ~= "table" then
		return
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

-- Saved data is checked, never trusted. (10.5: the city's fields and migrations went; what a save has of them is
-- written back as it was: an unknown key.)
local function applySaved(profile: Profile, saved: any)
	if type(saved) ~= "table" then
		return
	end
	profile.money = number(saved.money, profile.money, 2 ^ 50)
	profile.deliveries = number(saved.deliveries, 0, 2 ^ 50)
	profile.kills = number(saved.kills, 0, 2 ^ 50)
	profile.earned = number(saved.earned, 0, 2 ^ 50)
	profile.xp = number(saved.xp, 0, 2 ^ 50)
	-- 8.2: the funnel's steps, only from a real save written with their flag (sandboxOnboardingKept); a real save from
	-- before 8.2 is past every step (a player who knows the sandbox), a new one at none
	profile.sandboxOnboarding = AnalyticsPlan.sandboxFrom(saved)
	-- 8.0: the collection, checked, only from a real save written with its flag (collectionKept); else the empty one
	profile.collection = CollectionRules.fromSave(saved)
	-- 8.2: the collection book, checked, only from a real save: written with its flag (collectionBookKept) its own; an
	-- older real save the book of its stock (just read above), no milestone paid yet (CollectionBookRules.fromSave)
	profile.collectionBook, profile.collectionBookPaid = CollectionBookRules.fromSave(saved, profile.collection)
	-- (8.2 review: the milestones paid are also short keys of `rewards`, "book:<id>", which an older server keeps: a save
	-- that went through one never pays them again)
	local carried: { string } = {}
	if type(saved.rewards) == "table" then
		for k, on in saved.rewards do
			if on == true and type(k) == "string" and string.sub(k, 1, 5) == "book:" then
				table.insert(carried, string.sub(k, 6))
			end
		end
	end
	for id in CollectionBookRules.cleanPaid(carried) do
		profile.collectionBookPaid[id] = true
	end
	-- 8.1: the upgrades, checked, only from a real save written with their flag (sandboxUpgradesKept); 8.3, the
	-- migration (the same call): a real save (money in it) without warehouseLevelKept gets the warehouse at level 4
	-- (warehouse = 3) on top of those; a new player (no save) or a lock-only record none: the garage, level 1
	profile.sandboxUpgrades = UpgradeRules.fromSave(saved)
	-- 8.2: the daily tasks, checked, only from a real save written with their flag (sandboxTasksKept); else none:
	-- server/SandboxTasks.luau starts them fresh
	profile.sandboxTasks = SandboxTaskRules.fromSave(saved)
	-- 8.3: the moves finished (the badges), only from a real save written with their flag (sandboxMovesKept); else 0 (8.4
	-- review: a real save without it, from the "mv:" key of its own `rewards`: an 8.2 server dropped the field)
	profile.sandboxMoves = require(Shared.SandboxBadgeRules).movesFromSave(saved)
	-- 8.3: the market's demand, checked, only from a real save written with its flag (marketKept); else the empty one
	profile.market = Market.fromSave(saved)
	-- 8.3: the van's paint, checked, only from a real save written with its flag (vanPaintKept); else the empty one (8.4
	-- review: a real save without the flag, from the "paint:" keys of its own `rewards`)
	profile.vanPaint = VanPaintRules.fromSave(saved)
	-- 8.4: the house the next card has, only from a real save written with its flag (sandboxHouseSeedKept), and only a
	-- whole number in the seeds' range (Config.Moving.Sandbox.Seeds: Moving rolls 1 … that); else none
	local seed = saved.sandboxHouseSeed
	profile.sandboxHouseSeed = if saved.money ~= nil and saved.sandboxHouseSeedKept == true and type(seed) == "number" and seed == math.floor(seed)
		and seed >= 1 and seed <= Config.Moving.Sandbox.Seeds then seed else nil
	-- 8.9: which house, only from a real save written with its flag (sandboxHouseKept) and only an id SandboxMap
	-- knows; a real save from before it with a seed: the farmstead's (its seed rolled for it)
	local house = saved.sandboxHouse
	if saved.money == nil then
		profile.sandboxHouse = nil
	elseif saved.sandboxHouseKept == true then
		profile.sandboxHouse = if require(Shared.SandboxMap).house(house) then house else nil
	else
		profile.sandboxHouse = if profile.sandboxHouseSeed ~= nil then require(Shared.SandboxMap).House.id else nil
	end
	-- 10.1: the slot's courier and its time played, from a real save only
	profile.character = if saved.money ~= nil and type(saved.character) == "table" then CharacterLooks.clean(saved.character) else nil
	local played = saved.playTime
	profile.playTime = if saved.money ~= nil and type(played) == "number" and played == played and played >= 0 and played < math.huge then math.floor(played) else 0
	-- 9.7 RUNS: the difficulties open, only from a real save written with its flag (runUnlockedKept); else Easy and
	-- Normal (RunRules.fromSave)
	profile.runUnlocked = require(Shared.RunRules).fromSave(saved)
	-- 10.1 the helpers' crew, only from a real save written with its flag (crewKept); else Danny alone, free
	profile.crew = require(Shared.CrewRules).fromSave(saved)
	-- the van and what it is built with: only the vehicles a player may have (Economy.isPlayerCar), the van always
	if type(saved.cars) == "table" then
		for id, owned in saved.cars do
			if owned == true and type(id) == "string" and Economy.isPlayerCar(id) then
				profile.cars[id] = true
			end
		end
	end
	profile.cars[Config.CompanyVan.Car] = true
	-- 3.3: a car's tracks (only cars you own that can take them, only car tracks, clamped) and 3.5 its stage
	if type(saved.carUpgrades) == "table" then
		for carId, levels in saved.carUpgrades do
			if type(carId) == "string" and type(levels) == "table" and profile.cars[carId] and Economy.canUpgrade(carId) then
				local into: { [string]: number } = {}
				for _, def in Config.Upgrades do
					local level = if def.car then number(levels[def.id], 0, def.maxLevel) else 0
					if level > 0 then
						into[def.id] = level
					end
				end
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
	-- 3.4: the damage of every car (a share of its health, for cars you own)
	if type(saved.carHealth) == "table" then
		for carId, share in saved.carHealth do
			if type(carId) == "string" and profile.cars[carId] and type(share) == "number" and share == share then
				profile.carHealth[carId] = math.clamp(share, 0, 1)
			end
		end
	end
	if type(saved.carPaint) == "table" then
		for carId, paintId in saved.carPaint do
			if type(carId) == "string" and type(paintId) == "string" and profile.cars[carId] and Economy.findPaint(paintId) then
				profile.carPaint[carId] = paintId
			end
		end
	end
	if type(saved.carGuns) == "table" then
		for carId, gunId in saved.carGuns do
			if type(carId) == "string" and type(gunId) == "string" and profile.cars[carId] and Economy.canMount(carId) and Economy.findCarGun(gunId) then
				profile.carGuns[carId] = gunId
			end
		end
	end
	applyGear(profile, saved)
	applyLevelRewards(profile, saved)
	applyRewards(profile, saved)
	if type(saved.car) == "string" and profile.cars[saved.car] then
		profile.car = saved.car
	end
end

local function key(player: Player): string
	local playing = slots[player]
	return SaveSlotRules.key(player.UserId, if playing then playing.slot else 1) -- (10.1: slot 1 is the save of before)
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
			data.lock = { job = game.JobId, at = os.time(), session = sessions[player], seq = 0 } -- (8.3: + this session)
			return data
		end)
	end)
	if not success then
		warn(`[PlayerData] load failed: {err}`)
	end
	return success, saved, locked
end

-- 10.1: what the start screen picked (server/SaveSlots.luau): the slot, a fresh game in it, the courier made (nil: the
-- slot's own, or none).
export type Choice = { slot: number, fresh: boolean, character: CharacterLooks.Look? }

-- 10.1, set by server/SaveSlots.luau: waits for the player's pick on the start screen (nil: they left). Unset: slot 1.
PlayerData.chooseSlot = nil :: ((player: Player) -> Choice?)?

function PlayerData.load(player: Player)
	local profile = newProfile()
	local ok = true
	local dataStore = store
	local choice: Choice? = nil
	local choose = PlayerData.chooseSlot
	if choose then
		choice = choose(player)
		if not choice or not player.Parent then
			return -- (left on the start screen: nothing was read, nothing to keep)
		end
		slots[player] = { slot = choice.slot }
	end
	if dataStore then
		local saved: any = nil
		ok = false
		-- 8.3 saves: a rejoin to this server waits for its own leave save of this player (else it reads the one before).
		-- 8.4 review: as long as that save runs, at most its worst case (FinalTries tries, the backoffs between them, each
		-- UpdateAsync up to Call s) and LeaveWait s more: an outage's leave save outlasts a fixed wait
		local held, most = 0, Config.Saving.LeaveWait + Config.Saving.FinalTries * Config.Saving.Call
		for try = 1, Config.Saving.FinalTries - 1 do
			most += SaveGuard.backoff(try, Config.Saving.Backoff)
		end
		while leaving[player.UserId] and player.Parent and held < most do
			held += task.wait(0.25)
		end
		sessions[player] = `{player.UserId}-{os.time()}-{math.random(1, 2 ^ 30)}` -- 8.3: this session's (its lock)
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
				if failures >= Config.Saving.LoadTries or RunService:IsStudio() then
					break -- (Studio without API access: play without saving, right away)
				end
				task.wait(SaveGuard.backoff(failures, Config.Saving.Backoff)) -- (8.3: 1, 2, 4 s)
			end
		end
		-- 8.3 saves: a save that cannot be read without an error (a migration's bug on odd data) is never played on a
		-- fresh profile (nor saved over): as a failed load. The top-level keys it has that this version does not know
		-- are kept to be written back (known: PlayerData.start).
		if ok and choice and choice.fresh then
			saved = nil -- 10.1: a fresh game in this slot (START OVER, NEW GAME): what it held is written over
		end
		local applied, err = pcall(function()
			applySaved(profile, saved)
		end)
		if not applied then
			warn(`[PlayerData] {player.Name}'s save could not be read: {err}`)
			ok, profile = false, newProfile()
		elseif ok and known then
			local kept, _, bytes = SaveGuard.clean(SaveGuard.unknown(saved, known))
			if next(kept) ~= nil then
				extras[player] = { data = kept, bytes = bytes }
			end
		end
		if not ok and player.Parent and not RunService:IsStudio() then
			-- Never let a live player play on a profile that cannot be saved: they would lose all of it.
			sessions[player], extras[player] = nil, nil
			player:Kick("Your save could not be loaded right now (Roblox data service). Please rejoin in a moment.")
			return
		end
	end
	if not player.Parent then
		sessions[player], extras[player] = nil, nil -- (8.3: their leave's cleanup may have run already)
		return -- left while loading: nothing to keep (and no lock to release: the next join takes it after the wait)
	end
	-- Never overwrite a save we could not read.
	canSave[player] = ok and dataStore ~= nil
	if RunService:IsStudio() and not canSave[player] then
		profile.money = Config.Sandbox.StartMoney
	end
	if choice and choice.character then
		profile.character = CharacterLooks.clean(choice.character) -- 10.1: the courier made (or changed) for this slot
	end
	if player.Parent then
		profiles[player] = profile
		local playing: { slot: number, ticked: number? } = slots[player] or { slot = 1, ticked = nil }
		playing.ticked = os.clock() -- 10.1: the time played counts from here
		slots[player] = playing
		local stats = Instance.new("Folder")
		stats.Name = "leaderstats"
		-- The first stat is the one the player list sorts by: the best players on top.
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
		if choice and (choice.fresh or choice.character) and canSave[player] then
			task.spawn(PlayerData.save, player) -- 10.1: a fresh game (or a new look) is the slot's at once
		end
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

-- 8.3 saves: what a save writes, every field and flag of this version (lock: this server's, nil = released: the leave
-- save). PlayerData.start builds one from a stand-in with every field set (SaveGuard.probe) for the keys this version
-- knows, so a field added here is known by itself.
build = function(profile: Profile, lock: any): { [string]: any }
	return {
		money = profile.money,
		cars = profile.cars,
		car = profile.car,
		carUpgrades = profile.carUpgrades,
		carHealth = profile.carHealth,
		carGear = profile.carGear, -- 4.6
		carPaint = profile.carPaint,
		carGuns = profile.carGuns,
		xp = profile.xp,
		levelRewards = profile.levelRewards, -- 4.6
		-- 10.5: the city's flags, still written: an older server reading this save never runs their migration again
		xpCurve = Config.Levels.Curve, -- 3.2: the XP curve the xp is on
		carStages = true, -- 3.5: the cars' room is their stages
		vanStages = true, -- 4.0: the Old Van's four stages
		vestKit = true, -- 6.0.1: the courier vest is bought kit
		starterKit = true, -- 6.0.2: the pistol and the bag of the start
		noPacks = true, -- 6.6: the backpacks are gone
		noJacket = true, -- 6.7: the Thermal Jacket is gone
		noShoes = true, -- 6.12.2: the Running Shoes are gone
		perGameBags = true, -- 6.23: the bags are bought for each game
		vanOnly = true, -- 7.x: Config.CompanyVan.Flag: one car
		rewards = profile.rewards,
		sandboxOnboarding = profile.sandboxOnboarding, -- 8.2
		sandboxOnboardingKept = true, -- 8.2: AnalyticsPlan.SandboxFlag (applySaved reads the steps only with it)
		collection = profile.collection, -- 8.0
		collectionKept = true, -- 8.0: CollectionRules.SaveFlag (applySaved reads the collection only with it)
		collectionBook = profile.collectionBook, -- 8.2
		collectionBookPaid = profile.collectionBookPaid, -- 8.2
		collectionBookKept = true, -- 8.2: CollectionBookRules.Flag (applySaved reads the book only with it)
		sandboxUpgrades = profile.sandboxUpgrades, -- 8.1
		sandboxUpgradesKept = true, -- 8.1: UpgradeRules.Flag (applySaved reads the upgrades only with it)
		warehouseLevelKept = true, -- 8.3: Config.SandboxUpgrades.WarehouseFlag (the warehouse's level in them is the player's: no migration)
		sandboxTasks = profile.sandboxTasks, -- 8.2
		sandboxTasksKept = true, -- 8.2: Config.SandboxTasks.Flag (applySaved reads the tasks only with it)
		sandboxMoves = profile.sandboxMoves, -- 8.3
		sandboxMovesKept = true, -- 8.3: SandboxBadgeRules.Flag (applySaved reads the moves finished only with it)
		market = profile.market, -- 8.3
		marketKept = true, -- 8.3: Market.Flag (applySaved reads the market's demand only with it)
		vanPaint = profile.vanPaint, -- 8.3
		vanPaintKept = true, -- 8.3: VanPaintRules.Flag (applySaved reads the van's paint only with it)
		sandboxHouseSeed = profile.sandboxHouseSeed, -- 8.4 (nil: none)
		sandboxHouseSeedKept = true, -- 8.4 (applySaved reads the house's seed only with it)
		sandboxHouse = profile.sandboxHouse, -- 8.9 (nil: none)
		sandboxHouseKept = true, -- 8.9 (applySaved reads which house only with it)
		character = profile.character, -- 10.1 (nil: the player's own avatar)
		playTime = profile.playTime, -- 10.1
		savedAt = os.time(), -- 10.1 (the start screen's "saved 5 min ago")
		runUnlocked = profile.runUnlocked, -- 9.7
		runUnlockedKept = true, -- 9.7: Config.Runs.Flag (applySaved reads the difficulties open only with it)
		crew = require(Shared.CrewRules).toSave(profile.crew), -- 10.1
		crewKept = true, -- 10.1: Config.Crew.Flag (applySaved reads the crew only with it)
		deliveries = profile.deliveries,
		kills = profile.kills,
		earned = profile.earned,
		lock = lock, -- 4.2: this server plays it (nil = free); 8.3: { job, at, session, seq }
	}
end

-- 8.3 saves: is the stored save still this session's (its lock: this JobId and this session)? Only then is it written:
-- else another server took it over, or a later session of this player here (a rejoin), or it was released.
local function ours(old: any, session: string?): boolean
	local lock = if type(old) == "table" then old.lock else nil
	return type(lock) == "table" and lock.job == game.JobId and session ~= nil and lock.session == session
end

-- 8.3 saves: room in the server's UpdateAsync budget for a save that can wait (Config.Saving.Reserve stays for the
-- loads and the last saves)? Without a budget to read (Studio, the tests' runtimes): yes.
local function roomFor(): boolean
	local read, budget = pcall(function(): any
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return not read or type(budget) ~= "number" or budget >= Config.Saving.Reserve
end

-- final = the player leaves (or the server closes): the lock is released. 8.3 saves: true when it was written. The
-- data is a snapshot, checked (SaveGuard.clean; a bad money keeps the stored one), with the unknown keys of the loaded
-- save put back; written only while the save is this session's and never over a newer save of it (the lock's seq);
-- every failed write tried again after a backoff (Config.Saving: Tries, FinalTries).
function PlayerData.save(player: Player, final: boolean?): boolean
	local profile = profiles[player]
	local dataStore = store
	if not profile or not dataStore or not canSave[player] or finished[player] then
		return false
	end
	if final then
		finished[player] = true
	end
	-- 10.1: this session's time played since the last save
	local playing = slots[player]
	if playing and playing.ticked then
		local now = os.clock()
		profile.playTime = (profile.playTime or 0) + math.max(0, now - playing.ticked)
		playing.ticked = now
	end
	-- 7.2 review: an older server (main before 7.x) keeps the fields it knows only, but every short key of `rewards`:
	-- the one-car flag goes there too (Economy.vanMigrated: never paid back twice)
	profile.rewards[Config.CompanyVan.Flag] = true
	-- (8.4 review: the van's paint and the moves finished too, "paint:" / "paintOn:" and one "mv:<n>" key, the stale ones
	-- cleared: an 8.2 server drops vanPaint and sandboxMoves with their flags; their fromSave reads these back)
	VanPaintRules.mirror(profile.rewards, profile.vanPaint)
	require(Shared.SandboxBadgeRules).mirror(profile.rewards, profile.sandboxMoves)
	for id in profile.collectionBookPaid do
		profile.rewards["book:" .. id] = true -- (8.2 review: the book's milestones paid)
	end
	-- 8.3: the warehouse's level as a short key too ("warehouse:<k>", only the one it is now): a save an older server
	-- writes again loses sandboxUpgrades.warehouse and its flag, and UpgradeRules.fromSave reads the level back from it
	for key in profile.rewards do
		if type(key) == "string" and string.sub(key, 1, 10) == "warehouse:" then
			profile.rewards[key] = nil
		end
	end
	profile.rewards[UpgradeRules.warehouseKey(profile.sandboxUpgrades)] = true
	local seq = (serial[player] or 0) + 1
	serial[player] = seq
	local session = sessions[player] -- (kept here: the leave's cleanup may clear it while the shutdown's save still runs)
	local lock = if final then nil else { job = game.JobId, at = os.time(), session = session, seq = seq }
	local data, problems, bytes = SaveGuard.clean(build(profile, lock))
	local money = profile.money
	local badMoney = type(money) ~= "number" or money ~= money or money < 0 or money == math.huge
	if #problems > 0 or badMoney then
		warn(`[PlayerData] {player.Name}'s save mended: {table.concat(problems, "; ")}{if badMoney then ` (money {money}: the stored money kept)` else ""}`)
	end
	local more = extras[player]
	if more and bytes + more.bytes <= Config.Saving.MaxBytes then
		SaveGuard.merge(data, more.data)
		bytes += more.bytes
	elseif more then
		warn(`[PlayerData] {player.Name}'s save: the keys of a newer server left out ({more.bytes} bytes; too big)`)
	end
	if bytes >= Config.Saving.WarnBytes then
		warn(`[PlayerData] {player.Name}'s save is {math.floor(bytes / 1000)} kB (a DataStore key holds 4 MB)`)
	end
	saving += 1
	local tries = if final then Config.Saving.FinalTries else Config.Saving.Tries
	local written = false
	for attempt = 1, tries do
		local taken, put = false, false
		local success, err = pcall(function()
			dataStore:UpdateAsync(key(player), function(old: any): any
				taken, put = false, false
				-- 5.7: a regular autosave still in flight when the leave save started (or after a RESET MY SAVE swapped
				-- the profile) writes nothing: it would put this server's lock back on a save that was just released
				-- (the next server would wait for it), or write the old profile over the new one.
				if not final and (finished[player] or profiles[player] ~= profile) then
					return nil
				end
				if not ours(old, session) then
					taken = true -- another server took the save over (we were stale): never overwrite its newer data
					return nil
				end
				local newest = old.lock.seq
				if type(newest) == "number" and newest > seq then
					return nil -- (8.3: a newer save of this session is in already: never an older snapshot over it)
				end
				if badMoney then
					data.money = if type(old.money) == "number" and old.money >= 0 then old.money else 0
				end
				put = true
				return data
			end)
		end)
		if success and taken then
			warn(`[PlayerData] {player.Name}'s save is held by another server; this server stops saving it`)
			canSave[player] = false
			break
		elseif success then
			written = put
			break
		end
		warn(`[PlayerData] save failed ({attempt}/{tries}): {err}`)
		if attempt < tries then
			task.wait(SaveGuard.backoff(attempt, Config.Saving.Backoff))
			if not final and (finished[player] or profiles[player] ~= profile or serial[player] ~= seq) then
				break -- (a newer save, or the leave save, carries it now)
			end
		end
	end
	if written and profiles[player] == profile then
		wrote[player] = os.clock()
		if badMoney then
			profile.money = data.money -- (the live money mended too: never negative, never NaN)
		end
	end
	saving -= 1
	return written
end

-- 8.3 saves: a save a moment from now (Config.Saving.Soon s; one for a burst of calls). PlayerData.spend asks for it
-- after every purchase (the warehouse's level, the upgrades, the paint), server/CollectionBook.luau after a milestone,
-- server/Collection.luau when pieces come home (server/SandboxTasks.luau saves its claims its own way). Never sooner
-- than Gap s after this player's last write; while the request budget is under Reserve it is left to the autosave.
-- Nothing while the save is not loaded or the player is leaving (the leave save carries it).
function PlayerData.saveSoon(player: Player)
	if soon[player] or not canSave[player] or finished[player] or not profiles[player] then
		return
	end
	soon[player] = true
	local since = os.clock() - (wrote[player] or -math.huge)
	task.delay(math.max(Config.Saving.Soon, Config.Saving.Gap - since), function()
		soon[player] = nil
		if player.Parent and profiles[player] and roomFor() then
			PlayerData.save(player)
		end
	end)
end

-- 4.0.5, the admin's RESET MY SAVE: the profile starts over as a new player's ($ and all) and is saved so at once; the
-- caller then kicks the player, so every module builds them again from the fresh save.
function PlayerData.resetSave(player: Player)
	if not profiles[player] then
		return
	end
	local fresh = newProfile()
	if RunService:IsStudio() and not canSave[player] then
		fresh.money = Config.Sandbox.StartMoney
	end
	fresh.character = profiles[player].character -- (10.1: the slot's courier stays)
	profiles[player] = fresh
	extras[player] = nil -- (8.3: a fresh start keeps no newer server's keys either)
	PlayerData.save(player)
end

function PlayerData.release(player: Player)
	-- 5.7: the leave save runs after every other PlayerRemoving handler (Vehicles stores the van's damage, Moving ends a
	-- run, the collection pays its last minute): a deferred thread starts once they all had their turn.
	-- 8.3 saves: a rejoin to this server waits for it (leaving, by UserId); an error in it still cleans up.
	local userId = player.UserId
	leaving[userId] = (leaving[userId] or 0) + 1
	task.defer(function()
		local ok, err = pcall(PlayerData.save, player, true)
		if not ok then
			warn(`[PlayerData] {player.Name}'s leave save failed: {err}`)
		end
		profiles[player] = nil
		canSave[player] = nil
		finished[player] = nil -- (with the profile gone, a late autosave's transform still writes nothing)
		sessions[player], extras[player], wrote[player], serial[player], soon[player] = nil, nil, nil, nil, nil
		slots[player] = nil -- (10.1)
		local left = (leaving[userId] or 1) - 1
		if left > 0 then
			leaving[userId] = left
		else
			leaving[userId] = nil
		end
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

-- 10.1: the save slot this player plays (1 before a pick, and without slots)
function PlayerData.slot(player: Player): number
	local playing = slots[player]
	return if playing then playing.slot else 1
end

-- 10.1: reads one of this player's slots as it is stored, without taking it (the start screen's summaries,
-- server/SaveSlots.luau): ok (false: the DataStore failed or there is none: Studio without API access) and the save.
function PlayerData.peek(player: Player, slot: number): (boolean, any)
	local dataStore = store
	if not dataStore then
		return false, nil
	end
	local ok, saved = pcall(function(): any
		return dataStore:GetAsync(SaveSlotRules.key(player.UserId, slot))
	end)
	if not ok then
		warn(`[PlayerData] {player.Name}'s slot {slot} could not be read: {saved}`)
		return false, nil
	end
	return true, saved
end

-- A real, finite number: NaN or ±inf from a remote would poison the money for good.
local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- 6.13: `reason` and `sku` (the item's id) are for analytics (shared/AnalyticsPlan.luau Sources), nil: "Other".
function PlayerData.addMoney(player: Player, amount: number, reason: string?, sku: string?)
	local profile = profiles[player]
	if not profile or not finite(amount) or amount <= 0 then
		return
	end
	profile.money += math.floor(amount)
	profile.earned += math.floor(amount)
	changed:Fire(player)
	tellMoney(player, math.floor(amount), reason, sku)
end

-- Takes the money if there is enough; true when paid. 6.13: `reason` and `sku` as in addMoney (AnalyticsPlan Sinks).
function PlayerData.spend(player: Player, amount: number, reason: string?, sku: string?): boolean
	local profile = profiles[player]
	if not profile or not finite(amount) or amount < 0 or profile.money < amount then
		return false
	end
	profile.money -= amount
	changed:Fire(player)
	tellMoney(player, -amount, reason, sku)
	if amount > 0 then
		PlayerData.saveSoon(player) -- 8.3 saves: a purchase is saved a moment later (one save for a burst)
	end
	return true
end

-- ── Levels (Config.Levels, shared/Levels.luau) ────────────────────────────

-- 4.6, the career: every level reached whose reward (Config.Levels.Rewards) was not given yet gives its money now, once
-- (profile.levelRewards; counted as earned). 10.5: its items, kit, paint and title went with the city. 6.13: returns
-- the money it gave (for analytics).
local function giveLevelRewards(profile: Profile): number
	local cash = 0
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
			cash += math.floor(money)
		end
	end
	return cash
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
	local cash = giveLevelRewards(profile) -- 4.6
	changed:Fire(player)
	tellMoney(player, cash, "LevelReward") -- 6.13
	return after, after > before
end

-- The player's level (1 when not loaded).
function PlayerData.level(player: Player): number
	local profile = profiles[player]
	return if profile then Levels.levelFor(profile.xp) else 1
end

-- The player's XP (0 when not loaded).
function PlayerData.xp(player: Player): number
	local profile = profiles[player]
	return if profile then profile.xp else 0
end

function PlayerData.notify(player: Player)
	changed:Fire(player)
end

function PlayerData.start()
	-- 8.3 saves: every top-level key this version writes (a save built from a stand-in with every field set); a loaded
	-- save's other keys are a newer server's, kept and written back. Without the list (an error): none are kept.
	local built, probe = pcall(build, SaveGuard.probe(), {})
	if built and type(probe) == "table" then
		known = SaveGuard.keys(probe)
	else
		warn(`[PlayerData] the save's keys could not be listed ({probe}): a newer server's keys are not kept`)
	end
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
		local deadline = os.clock() + Config.Saving.CloseWait
		task.wait()
		while saving > 0 and os.clock() < deadline do
			task.wait(0.25)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveSeconds)
			-- 8.3 saves: a player written a moment ago (a purchase's save) waits for the next round, and so does every
			-- save while the request budget is under its reserve (the loads and the leave saves come first)
			local waiting = 0
			for player in profiles do
				if not canSave[player] or os.clock() - (wrote[player] or -math.huge) < Config.Saving.Gap then
					continue -- (a save not loaded, Studio without API access: nothing to write)
				elseif not roomFor() then
					waiting += 1
					continue
				end
				task.spawn(PlayerData.save, player)
			end
			if waiting > 0 then
				warn(`[PlayerData] the DataStore's request budget is low: {waiting} autosave(s) wait for the next round`)
			end
		end
	end)
end

return PlayerData
