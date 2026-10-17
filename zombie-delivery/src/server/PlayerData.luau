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
-- fuel in every car you own (carFuel, litres; server/Fuel.luau keeps it, a car without an entry is full). 6.6: the
-- backpacks are gone (Config.RetiredKit): a save from before (no noPacks flag) gets their price back once
-- (shared/Transport.luau packRefund; profile.packRefund, never saved, tells server/Tutorial.luau to say so). 6.7: the
-- Thermal Jacket the same way (the noJacket flag, profile.jacketRefund; 6.12.2: the Running Shoes, noShoes and
-- profile.shoeRefund). 6.12: the daily and weekly tasks (tasks:
-- shared/Tasks.luau's save, kept by server/Tasks.luau; read only from a real save). 6.12: the wardrobe of cosmetics
-- (style: the items owned and the one worn in each slot, Config.Cosmetics; shared/Style.luau cleans it,
-- server/StyleWear.luau changes it): a save from before 6.12 has none and gets the empty one; real saves only.
-- 6.13, analytics (server/Analytics.luau): the onboarding funnel's steps reached (onboarding, a bit a step,
-- shared/AnalyticsPlan.luau): a new courier starts at 0, a real save from before 6.13 counts as past every step (it
-- is no new courier; a step is marked only once Roblox took it); every money change tells its reason (addMoney /
-- spend's `reason` and `sku`, the level rewards, the retired kit's refunds) to PlayerData.onMoney; and the game's
-- other analytics calls go through PlayerData.track (the hooks Analytics.start puts in PlayerData.analytics: without
-- them nothing happens, so the game never depends on server/Analytics.luau loading). 6.14: the regulars (regulars: the
-- deliveries for each business, shared/Regulars.luau; server/Regulars.luau counts them): a new field, checked on load
-- (Regulars.clean), an empty table in a save from before (no migration). 6.20: the skills (skills: skill id → rank,
-- Config.Skills; shared/Skills.luau, server/Skills.luau): only the ranks bought are kept, the points come from the
-- level (an old save has its level's points to spend at once); checked on load (Skills.clean: a save over its level's
-- points gets every point back), an empty table in a save from before (no migration). The player attribute Skills
-- carries them to the client (Skills.encode).
-- 6.23, bags for each game (Config.BagShop): the bags bought this game are profile.bags, a per-game table that is never
-- saved (leaving loses them, a death keeps them), and the bag in use (profile.activeBag) is no longer saved either. A
-- game starts with no bag, except the free one while the tutorial is ahead (Transport.startBags: a brand-new courier's
-- first game). The saved kit holds no bag any more: a real save from before (no perGameBags flag) is paid back once for
-- the bags it owned (Transport.bagRefund, at the price they were sold at; profile.bagRefund, never saved, tells
-- server/Tutorial.luau to say so; the money's reason "BagRefund"). PlayerData.giveKit puts a bag into profile.bags.
-- 7.0, the moves' story (shared/MoveStory.luau): the story cards seen (story: MoveStory.SeenKeys, "intro" = Marge's
-- moving intro at the first contracts board), read only from a real save (an older one has none: the empty table, so
-- everybody sees the intro once); PlayerData.markStory sets one (client/MoveStoryUi.luau asks through server/
-- Tutorial.luau) and the player attribute MoveStory carries them to the client (MoveStory.encodeSeen).
-- 7.x, one car (Config.CompanyVan): every courier owns the ZDC Van (a new profile, and every save on load: cars and
-- car hold only Config.Cars ids, the ZDC Van and the bikes; a car that is gone falls back to the van). A real save from
-- before (no vanOnly flag) is paid back once for the cars it owned (Economy.carRefund: their price and the stages it
-- bought, as sold; profile.carRefund, never saved, tells server/Tutorial.luau to say so; the money's reason
-- "CarRefund") and the van takes over their best car tracks, gear, paint and roof gun (Economy.vanCarry). Earl's
-- quest (vanQuest) is no longer read or saved. 7.2 review: the refund also pays what the van could not take over
-- (VanCarry.lost) and the bonus of every employer whose vehicle the save had earned (Economy.employerBonus), never the
-- ZDC Van itself; the flag is written into `rewards` too (an older server drops unknown fields but keeps that table's
-- short keys: Economy.vanMigrated reads either), and so are the chapters done (its story keeps only "intro").
-- 8.0 SANDBOX: the collection (collection: the pieces the moves brought home, shared/CollectionRules.luau; kept by
-- server/Collection.luau), read only from a real save written with its flag (collectionKept); older saves: empty.
-- 8.2 SANDBOX: the collection book (collectionBook: { [item]: { n, best } } the pieces ever brought home,
-- collectionBookPaid: { [milestone id]: true } its milestones paid; shared/CollectionBookRules.luau, kept by
-- server/CollectionBook.luau), read only from a real save written with its flag (collectionBookKept); an older real save
-- fills the book from its stock (its milestones pay on joining); a new player: empty.
-- 8.1 SANDBOX: the upgrades bought at the warehouse's UPGRADES desk (sandboxUpgrades: { [id]: level },
-- shared/UpgradeRules.luau; server/Upgrades.luau sells them), read only from a real save written with its flag
-- (sandboxUpgradesKept); older saves: none. (profile.upgrades stays the city's gun tracks.)
-- 8.3 SANDBOX (design/warehouse-levels/KONTRAKT.md): the warehouse's level is one of them (sandboxUpgrades.warehouse,
-- upgrade level k = warehouse level k + 1). Every save is written with the flag warehouseLevelKept
-- (Config.SandboxUpgrades.WarehouseFlag); a real save without it (from before 8.3: its owner has the warehouse every
-- plot had, level 4) gets warehouse = 3 on top of what it had, a new player none (the garage, level 1):
-- UpgradeRules.fromSave.
-- 8.2 SANDBOX, analytics: the sandbox's own onboarding funnel's steps reached (sandboxOnboarding, a bit a step of
-- shared/AnalyticsPlan.luau's SandboxSteps; server/Analytics.luau marks them on a sandbox server), read only from a real
-- save written with its flag (sandboxOnboardingKept: AnalyticsPlan.sandboxFrom); an older real save is past every step.
-- 8.2 SANDBOX: the daily tasks (sandboxTasks: shared/SandboxTasks.luau's save, kept by server/SandboxTasks.luau), read
-- only from a real save written with their flag (sandboxTasksKept); older saves: none (the server starts them fresh).
-- 8.3 SANDBOX: the moves finished (sandboxMoves: server/SandboxBadges.luau counts them for the badges, shared/
-- SandboxBadgeRules.luau), read only from a real save written with its flag (sandboxMovesKept); older saves: 0. (8.4
-- review: and in `rewards` as "mv:<n>", up to the badges' count: a save an 8.2 server wrote again gets it back from there.)
-- 8.3 SANDBOX: the market's demand (market: shared/Market.luau's save, what each kind sold today weighs on its price;
-- kept by server/Collection.luau), read only from a real save written with its flag (marketKept); older saves: none.
-- 8.3 SANDBOX: the van's paint (vanPaint: { owned, worn }, shared/VanPaintRules.luau; the PAINT shop, server/VanPaint.luau),
-- read only from a real save written with its flag (vanPaintKept); older saves: nothing bought, the factory's look. (8.4
-- review: and in `rewards` as "paint:<id>" / "paintOn:<id>": a save an 8.2 server wrote again gets it back from there; the
-- market's demand is not kept so: it is lost there, a day's worth at most.)
-- 8.4 SANDBOX: the house the moving card shows (sandboxHouseSeed: its seed, server/Moving.luau's SB.seeds, kept until a
-- trip brings something home), read only from a real save written with its flag (sandboxHouseSeedKept) and only a
-- whole number 1 … Config.Moving.Sandbox.Seeds; else none (the next card rolls one). Leaving and joining another server
-- shows the same house (no reroll by server hopping). Not mirrored into `rewards` (an 8.2 server drops it: a new house).
-- 8.9: which house it is (sandboxHouse: a shared/SandboxMap.luau Houses id, server/Moving.luau's SB.houses; with no
-- seed, the house emptied last: the next card takes the one after it), read only from a real save written with its flag
-- (sandboxHouseKept) and only an id SandboxMap knows (9.4: a village house's id of 8.9's map is none now: its card takes
-- the next free place from the farmstead on, its seed kept); a real save from before it with a house's seed has the
-- farmstead's (sandbox_house: the one house there was); else none.
-- 10.1, the save slots (Config.SaveSlots, shared/SaveSlotRules.luau): a player has Count saves, each its own game. With
-- PlayerData.chooseSlot set (server/SaveSlots.luau, on the sandbox) a join's load waits for the start screen's pick: the
-- slot (its key: slot 1 the save of before, "Player_<id>"), a fresh game in it (START OVER, NEW GAME: the stored save is
-- not read, a new one is written at once) and the courier made for it (profile.character: shared/CharacterLooks.luau's
-- look and its name, read from a real save only); unset (the city, the tests of before): slot 1 at once, as before.
-- Every save also writes the time played (playTime, s: this session's added at each save) and when (savedAt, os.time)
-- for the start screen's cards.
-- Loaded from and saved to a DataStore. In Studio without API access it simply runs without saving.
-- 8.3 SAVES (Config.Saving, shared/SaveGuard.luau): a save is written (UpdateAsync) only while the stored save is still
-- this server's session's (its lock: the JobId, the session and the save's number: never over another server's save
-- or over a newer snapshot), checked on its way (SaveGuard.clean: one bad value never costs the whole save; a bad money
-- keeps the stored one), with the top-level keys of the loaded save this version does not know put back (a newer
-- server's fields survive a round trip through this one), and tried again after a backoff. When: the autosave (every
-- AutosaveSeconds; a player written a moment ago waits for the next round, and so does every save that can wait while
-- the request budget is under Reserve), a save soon after a purchase (PlayerData.spend), a book milestone or pieces
-- brought home (PlayerData.saveSoon: one for a burst), the leave save and the shutdown's (all at once, waited for). A
-- load that fails, or a save that cannot be read without an error, never gets a fresh profile that would be saved over
-- the real one: a live player is kicked. A rejoin to this server waits for its own leave save of that player.
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
local TaskData = require(Shared.Tasks) -- 6.12: the daily and weekly tasks (profile.tasks)
local Style = require(Shared.Style) -- 6.12: the cosmetics' wardrobe
local AnalyticsPlan = require(Shared.AnalyticsPlan) -- 6.13: the onboarding funnel's steps in the save
local SkillRules = require(Shared.Skills) -- 6.20: the skills' ranks (profile.skills)
local MoveStory = require(Shared.MoveStory) -- 7.0: the moves' story cards seen (profile.story)
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
	cars: { [string]: boolean },
	car: string?, -- 5.0: the equipped car; nil = no vehicle yet (on foot). 5.1: or a bike (what CAR / MY BIKE brings)
	bike: string?, -- 5.1: your bike of choice (an owned Config.Cars bike; the BIKES counter's EQUIP, the phone's MY BIKE)
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
	kit: { [string]: boolean }, -- 5.0: personal gear owned (Config.Kit ids: vests, the bat), yours for good (6.23: no bags)
	-- 6.23: the bags bought this game (Config.Kit bag ids): per game, NEVER saved (Transport.startBags at the start)
	bags: { [string]: boolean },
	-- 6.4: the bag you chose to hold (a Config.Kit bag you have: USE in the KIT tab or the I window's BAGS); nil = the
	-- best one (shared/Transport.luau activeBag decides, a choice no longer had falls back to it too). 6.23: per game,
	-- never saved
	activeBag: string?,
	bagRefund: number?, -- 6.23: the money this load paid back for the bags owned for good before (never saved)
	bagHinted: boolean?, -- 6.23: the "no bag this game" hint was given this game (server/Cargo.luau; never saved)
	packRefund: number?, -- 6.6: the money this load paid back for retired backpacks (Marge says so once; never saved)
	jacketRefund: number?, -- 6.7: … and for the retired Thermal Jacket (the same way)
	shoeRefund: number?, -- 6.12.2: … and for the retired Running Shoes (the same way)
	style: Style.Wardrobe, -- 6.12: the cosmetics owned (id → true) and worn (slot → id); server/StyleWear.luau
	phone: boolean, -- 5.0: Marge gave you the phone (the tutorial; client/Phone.luau)
	carRefund: number?, -- 7.x: what this load paid back for the cars that are gone (0: only free ones went; never saved)
	-- 6.12: the daily and weekly tasks (shared/Tasks.luau: the day, the level, the picks' ids, progress, claims; the
	-- week the same). nil until server/Tasks.luau starts them (a new courier, a save from before 6.12)
	tasks: TaskData.Saved?,
	-- 6.13: the onboarding funnel's steps reached (a bit a step, shared/AnalyticsPlan.luau; server/Analytics.luau)
	onboarding: number,
	-- 8.2 SANDBOX: the sandbox's onboarding funnel's steps reached (a bit a step of AnalyticsPlan.SandboxSteps): read only
	-- from a real save written with its flag (AnalyticsPlan.sandboxFrom); an older real save is past every step
	sandboxOnboarding: number,
	-- 6.14: the regulars: deliveries for each business (shared/Regulars.luau ids, the job pictures'; server/Regulars.luau
	-- counts them); a save from before 6.14 has none (the empty table, no migration)
	regulars: { [string]: number },
	-- 6.20: the skills bought (Config.Skills ids → rank); the points are the level's (shared/Skills.luau points)
	skills: { [string]: number },
	-- 7.0: the moves' story cards seen (shared/MoveStory.luau SeenKeys: "intro"); none before 7.0 (the empty table)
	story: { [string]: boolean },
	-- 8.0 SANDBOX: the pieces the moves brought home (shared/CollectionRules.luau; server/Collection.luau keeps it): read
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
	-- 8.4 SANDBOX: the seed of the house the moving card shows (server/Moving.luau sets and drops it with SB.seeds): read
	-- only from a real save written with its flag (sandboxHouseSeedKept), a whole number 1 … Config.Moving.Sandbox.Seeds;
	-- nil: none yet (the next card rolls one)
	sandboxHouseSeed: number?,
	-- 8.9: the house of that card (a SandboxMap.Houses id; the seed nil: the house emptied last), read only from a
	-- real save written with its flag (sandboxHouseKept); an older real save with a seed: the farmstead's; nil: none yet
	sandboxHouse: string?,
	-- 10.1: the courier made for this slot (a look and its name, shared/CharacterLooks.luau), read from a real save only;
	-- nil: the player's own Roblox avatar, as before 10.1
	character: CharacterLooks.Look?,
	playTime: number, -- 10.1: s played in this slot (the start screen's card)
	-- 9.7 RUNS: how many of the runs' difficulties are open (shared/RunRules.luau: Config.Runs.Open at first, one more
	-- for a run finished at the hardest open one): read only from a real save written with its flag (runUnlockedKept)
	runUnlocked: number,
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

-- 6.13, filled by server/Analytics.luau's start: its hooks by name (order, stopDone, jobFailed, missionStarted,
-- missionDone, onPlay, step, died, event, money). The game calls them only through PlayerData.track, never by requiring
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
	-- 8.0 SANDBOX: its own saves (Config.Sandbox.Store); the city's are never touched there
	store = DataStoreService:GetDataStore(if Config.Sandbox.On then Config.Sandbox.Store else Config.DataStoreName)
end)

local function newProfile(): Profile
	return {
		money = if Config.Sandbox.On then Config.Sandbox.StartMoney else Config.StartMoney, -- (8.0: the sandbox's own)
		cars = { [Config.CompanyVan.Car] = true }, -- 7.x: every courier's ZDC Van (5.0 – 6.x: on foot, Earl's van at level 4)
		car = Config.CompanyVan.Car,
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
		kit = {}, -- 5.0 (6.23: no bag in it: the bags are bought for each game)
		bags = require(Shared.Transport).startBags(false), -- 6.23: the tutorial's free bag (a new courier's first game)
		activeBag = nil, -- 6.4: the best bag owned
		bagRefund = nil, -- 6.23
		bagHinted = nil, -- 6.23
		packRefund = nil, -- 6.6
		jacketRefund = nil, -- 6.7
		shoeRefund = nil, -- 6.12.2
		style = Style.empty(), -- 6.12: no cosmetics yet
		phone = false,
		carRefund = nil, -- 7.x
		tasks = nil, -- 6.12: server/Tasks.luau starts them (it knows the UserId and the level)
		onboarding = 0, -- 6.13: a new courier, no step yet
		sandboxOnboarding = 0, -- 8.2: no step of the sandbox's funnel yet
		regulars = {}, -- 6.14: no business knows you yet
		skills = {}, -- 6.20: no skill yet (the points come with the levels)
		story = {}, -- 7.0: no story card seen yet
		collection = CollectionRules.empty(), -- 8.0: nothing brought home yet
		collectionBook = CollectionBookRules.empty(), -- 8.2: nothing found yet
		collectionBookPaid = {}, -- 8.2: no milestone paid yet
		sandboxUpgrades = UpgradeRules.empty(), -- 8.1: no upgrade bought yet
		sandboxTasks = nil, -- 8.2: server/SandboxTasks.luau starts them (it knows the UserId and the day)
		sandboxMoves = 0, -- 8.3: no move finished yet (the badges)
		market = Market.empty(), -- 8.3: nothing sold yet
		vanPaint = VanPaintRules.empty(), -- 8.3: nothing bought, the factory's look
		sandboxHouseSeed = nil, -- 8.4: no house rolled yet
		sandboxHouse = nil, -- none of the six yet
		character = nil, -- 10.1: the player's own avatar until a courier is made
		playTime = 0, -- 10.1
		runUnlocked = Config.Runs.Open, -- 9.7: Easy and Normal
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

-- 7.x, one car: the ZDC Van takes over the best of a save's old cars, once (Economy.vanCarry): every car track at
-- the highest level, their gear (installed while the van has a free gear slot, else owned), the paint (one the save
-- owns) and the roof gun of the car it drove. (After the cars, their levels, gear, paints and guns are read.)
local function takeOver(profile: Profile, carry: Economy.VanCarry)
	local van = Config.CompanyVan.Car
	local levels = profile.carUpgrades[van] or {}
	for id, level in carry.levels do
		levels[id] = math.max(levels[id] or 0, level)
	end
	if next(levels) ~= nil then
		profile.carUpgrades[van] = levels
	end
	local gear: { [string]: string } = profile.carGear[van] or {}
	local slots = Economy.gearSlots(van, Economy.stageOf(van, levels))
	local used = 0
	for _, value in gear do
		if value == "installed" then
			used += 1
		end
	end
	for _, def in Config.Gear do
		local value = carry.gear[def.id]
		if value and gear[def.id] ~= "installed" then
			if value == "installed" and used < slots then
				gear[def.id] = "installed"
				used += 1
			else
				gear[def.id] = "owned"
			end
		end
	end
	if next(gear) ~= nil then
		profile.carGear[van] = gear
	end
	local paint = carry.paint
	if paint and profile.paints[paint] then
		profile.carPaint[van] = paint
	end
	local gun = carry.gun
	if gun and Economy.canMount(van) then
		profile.carGuns[van] = gun
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
	-- 6.6: the backpacks are gone (Config.RetiredKit): a real save from before (no noPacks flag; not a lock-only record
	-- of a new player) gets their price back, once (the kit below no longer knows them, so they are dropped). 6.7: the
	-- Thermal Jacket too, by its own noJacket flag (a 6.6 save has noPacks already): Transport.retiredRefunds, by flag;
	-- Marge says so (profile.packRefund / jacketRefund, never saved).
	local refunds = require(Shared.Transport).retiredRefunds(saved)
	for _, refund in refunds do
		profile.money = math.min(profile.money + refund, 2 ^ 50)
	end
	profile.packRefund = refunds.noPacks
	profile.jacketRefund = refunds.noJacket
	profile.shoeRefund = refunds.noShoes -- 6.12.2: the Running Shoes (their noShoes flag)
	-- 6.23: the bags are bought for each game: a real save from before (no perGameBags flag) gets the price of the
	-- bags it owned for good back, once (Transport.bagRefund); no bag is read into the kit (they are not kept)
	local bagRefund = require(Shared.Transport).bagRefund(saved)
	if bagRefund > 0 then
		profile.money = math.min(profile.money + bagRefund, 2 ^ 50)
		profile.bagRefund = bagRefund
	end
	if type(saved.kit) == "table" then
		for _, def in Config.Kit do
			if saved.kit[def.id] == true and def.extra == nil then
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
		-- (6.23: no plastic bag any more: the bags are bought for each game)
	end
	if saved.vestKit ~= true and saved.money ~= nil then -- (a real old save: not a lock-only record of a new player)
		profile.kit[Config.Courier.VestKit] = true
	end
	-- 6.12: the daily and weekly tasks, checked (TaskData.clean), only from a real save (not a lock-only record of a
	-- new player); a save from before 6.12 has none: server/Tasks.luau starts them fresh.
	if saved.money ~= nil then
		profile.tasks = TaskData.clean(saved.tasks)
		-- 6.12: the cosmetics' wardrobe too (a save from before 6.12 has none: the empty one; a saved one is cleaned:
		-- known items, each worn one owned and in its own slot, shared/Style.luau).
		profile.style = Style.sanitize(saved.style)
	end
	-- 6.13: the onboarding funnel's steps (only a real save has them; one from before 6.13 is past every step).
	profile.onboarding = AnalyticsPlan.onboardingFrom(saved)
	-- 8.2: the sandbox's funnel's steps, only from a real save written with their flag (sandboxOnboardingKept); a real
	-- save from before 8.2 is past every step (a player who knows the sandbox), a new one at none
	profile.sandboxOnboarding = AnalyticsPlan.sandboxFrom(saved)
	-- 6.14: the regulars, checked (known businesses, whole counts up to Config.Regulars.Cap); none before 6.14: empty.
	profile.regulars = require(Shared.Regulars).clean(saved.regulars)
	-- 7.0: the moves' story cards seen, checked (known keys only), only from a real save (not a lock-only record of a
	-- new player); a save from before 7.0 has none: the empty table (Marge's moving intro shows once for it too).
	if saved.money ~= nil then
		profile.story = MoveStory.cleanSeen(saved.story, saved.rewards) -- (7.2 review: + the chapters done kept in rewards)
	end
	-- 8.0: the collection, checked, only from a real save written with its flag (collectionKept); a save from before
	-- 8.0 (or a lock-only record of a new player) starts with the empty one (CollectionRules.fromSave)
	profile.collection = CollectionRules.fromSave(saved)
	-- 8.2: the collection book, checked, only from a real save: written with its flag (collectionBookKept) its own; an
	-- older real save the book of its stock (just read above), no milestone paid yet (CollectionBookRules.fromSave)
	profile.collectionBook, profile.collectionBookPaid = CollectionBookRules.fromSave(saved, profile.collection)
	-- (8.2 review: the milestones paid are also short keys of `rewards`, "book:<id>", which an older server keeps: a save
	-- that went through one never pays them again)
	local carried: { string } = {}
	if type(saved.rewards) == "table" then -- (the save's own: profile.rewards is read later, applyChallenges)
		for key, on in saved.rewards do
			if on == true and type(key) == "string" and string.sub(key, 1, 5) == "book:" then
				table.insert(carried, string.sub(key, 6))
			end
		end
	end
	for id in CollectionBookRules.cleanPaid(carried) do
		profile.collectionBookPaid[id] = true
	end
	-- 8.1: the sandbox's upgrades, checked, only from a real save written with their flag (sandboxUpgradesKept); a save
	-- from before 8.1 (or a lock-only record) has none (UpgradeRules.fromSave). 8.3, the migration (the same call): a
	-- real save (money in it) without warehouseLevelKept, from before 8.3, gets the warehouse at level 4 (warehouse = 3,
	-- the building it had) on top of those; a save with the flag keeps its own level; a new player (no save) or a
	-- lock-only record none: the garage, level 1
	profile.sandboxUpgrades = UpgradeRules.fromSave(saved)
	-- 8.2: the sandbox's daily tasks, checked, only from a real save written with their flag (sandboxTasksKept); a save
	-- from before 8.2 (or a lock-only record) has none: server/SandboxTasks.luau starts them fresh
	profile.sandboxTasks = SandboxTaskRules.fromSave(saved)
	-- 8.3: the moves finished (the badges), only from a real save written with their flag (sandboxMovesKept); else 0 (8.4
	-- review: a real save without it, from the "mv:" key of its own `rewards`: an 8.2 server dropped the field)
	profile.sandboxMoves = require(Shared.SandboxBadgeRules).movesFromSave(saved)
	-- 8.3: the market's demand, checked, only from a real save written with its flag (marketKept); a save from before 8.3
	-- (or a lock-only record) starts with the empty one (Market.fromSave)
	profile.market = Market.fromSave(saved)
	-- 8.3: the van's paint, checked, only from a real save written with its flag (vanPaintKept); a save from before 8.3
	-- (or a lock-only record) starts with the empty one (VanPaintRules.fromSave; 8.4 review: a real save without the flag,
	-- from the "paint:" keys of its own `rewards`: an 8.2 server dropped the field)
	profile.vanPaint = VanPaintRules.fromSave(saved)
	-- 8.4: the house the moving card shows, only from a real save written with its flag (sandboxHouseSeedKept), and only
	-- a whole number in the seeds' range (Config.Moving.Sandbox.Seeds: Moving rolls 1 … that); else none
	local seed = saved.sandboxHouseSeed
	profile.sandboxHouseSeed = if saved.money ~= nil and saved.sandboxHouseSeedKept == true and type(seed) == "number" and seed == math.floor(seed)
		and seed >= 1 and seed <= Config.Moving.Sandbox.Seeds then seed else nil
	-- 8.9: which house, only from a real save written with its flag (sandboxHouseKept) and only an id SandboxMap
	-- knows (9.4: an id of the village's houses, gone with the countryside, is none: the next card takes the next free
	-- place from the farmstead on); a real save from before it with a seed: the farmstead's (its seed rolled for it)
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
	-- 9.7 RUNS: the difficulties open, only from a real save written with its flag (runUnlockedKept: Config.Runs.Flag);
	-- a save from before 9.7 (or a lock-only record) starts with Easy and Normal (RunRules.fromSave)
	profile.runUnlocked = require(Shared.RunRules).fromSave(saved)
	-- (6.4: the bag chosen was read here; 6.23: it is per game, never saved: a game starts with the best bag you have)
	if saved.xpCurve ~= Config.Levels.Curve then
		profile.xp = Levels.fromLegacy(profile.xp) -- 3.2: a 3.1 save, the old XP curve: it keeps its level
	end
	-- 7.x, one car: only the vehicles a player may have (Economy.isPlayerCar: the ZDC Van, the bikes); a real save from
	-- before (no vanOnly flag) is paid back once for the other cars it owned (Economy.carRefund) and its van takes over
	-- their best (Economy.vanCarry, below once the cars' tables are read). 7.2 review: + what the van could not take
	-- over (VanCarry.lost: track levels, roof guns, gear, as sold) and the bonus of every employer whose vehicle it had
	-- earned (Economy.employerBonus); a save put right already counts by its flag or the same mark in its rewards
	-- (Economy.vanMigrated: an older server drops the flag)
	local carry = Economy.vanCarry(saved)
	local carRefund = Economy.carRefund(saved) + (if carry then carry.lost else 0) + Economy.employerBonus(saved)
	if carRefund > 0 then
		profile.money = math.min(profile.money + carRefund, 2 ^ 50)
	end
	if carRefund > 0 or (carry and carry.retired > 0) then
		profile.carRefund = carRefund
	end
	if type(saved.cars) == "table" then
		for id, owned in saved.cars do
			if owned == true and type(id) == "string" and Economy.isPlayerCar(id) then
				profile.cars[id] = true
			end
		end
	end
	profile.cars[Config.CompanyVan.Car] = true
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
			if type(carId) == "string" and type(paintId) == "string" and profile.cars[carId] and profile.paints[paintId] then
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
	if carry then
		takeOver(profile, carry) -- 7.x
	end
	applyLevelRewards(profile, saved)
	applyLicences(profile, saved) -- 4.7
	profile.skills = SkillRules.clean(saved.skills, Levels.levelFor(profile.xp)) -- 6.20 (none saved: an empty table)
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
		profile.bags = require(Shared.Transport).startBags(profile.tutorial) -- 6.23: the free bag only with the tutorial ahead
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
		profile.money = if Config.Sandbox.On then Config.Sandbox.StartMoney else Config.StudioStartMoney
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
		-- 6.13: the retired kit's money back (applySaved), for the economy's numbers
		tellMoney(player, (profile.packRefund or 0) + (profile.jacketRefund or 0) + (profile.shoeRefund or 0), "Refund", "RetiredKit")
		tellMoney(player, profile.bagRefund or 0, "BagRefund", "Bags") -- 6.23: the bags owned for good, paid back
		tellMoney(player, profile.carRefund or 0, "CarRefund", "Cars") -- 7.x: the cars that are gone, paid back
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
	-- 6.20: the skills' ranks for the client (client/Stamina.luau, CameraRig, Shooting, Hotbar, the SKILLS tab)
	local skills = SkillRules.encode(profile.skills)
	if player:GetAttribute("Skills") ~= skills then
		player:SetAttribute("Skills", skills)
	end
	-- 7.0: the moves' story cards seen, for client/MoveStoryUi.luau ("" = none yet)
	local story = MoveStory.encodeSeen(profile.story)
	if player:GetAttribute("MoveStory") ~= story then
		player:SetAttribute("MoveStory", story)
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
		noPacks = true, -- 6.6: the backpacks are gone (applySaved pays an older save's back once)
		noJacket = true, -- 6.7: the Thermal Jacket is gone (applySaved pays it back once)
		noShoes = true, -- 6.12.2: the Running Shoes are gone (applySaved pays them back once)
		perGameBags = true, -- 6.23: the bags are bought for each game (applySaved pays an older save's bags back once)
		vanOnly = true, -- 7.x: Config.CompanyVan.Flag: one car (applySaved pays an older save's other cars back once)
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
		kit = profile.kit, -- 5.0 (6.23: no bag: profile.bags and profile.activeBag are per game, never saved)
		style = profile.style, -- 6.12: the cosmetics owned and worn
		phone = profile.phone, -- 5.0
		tasks = profile.tasks, -- 6.12
		onboarding = profile.onboarding, -- 6.13
		sandboxOnboarding = profile.sandboxOnboarding, -- 8.2
		sandboxOnboardingKept = true, -- 8.2: AnalyticsPlan.SandboxFlag (applySaved reads the steps only with it)
		regulars = profile.regulars, -- 6.14
		skills = profile.skills, -- 6.20
		story = profile.story, -- 7.0
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
	-- the one-car flag goes there too (Economy.vanMigrated: never paid back twice) and so do the chapters done (its
	-- story keeps only "intro"; MoveStory.cleanSeen reads them back)
	profile.rewards[Config.CompanyVan.Flag] = true
	-- (8.4 review: the van's paint and the moves finished too, "paint:" / "paintOn:" and one "mv:<n>" key, the stale ones
	-- cleared: an 8.2 server drops vanPaint and sandboxMoves with their flags; their fromSave reads these back)
	VanPaintRules.mirror(profile.rewards, profile.vanPaint)
	require(Shared.SandboxBadgeRules).mirror(profile.rewards, profile.sandboxMoves)
	for id in profile.collectionBookPaid do
		profile.rewards["book:" .. id] = true -- (8.2 review: the book's milestones paid, as the chapters done below)
	end
	for key in profile.story do
		if string.sub(key, 1, 5) == "done:" then
			profile.rewards[key] = true
		end
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

-- 4.0.5, the admin's RESET MY SAVE: the profile starts over as a new player's (the tutorial, the fog, $ and all) and is
-- saved so at once; the caller then kicks the player, so every module builds them again from the fresh save.
function PlayerData.resetSave(player: Player)
	if not profiles[player] then
		return
	end
	local fresh = newProfile()
	if RunService:IsStudio() and not canSave[player] then
		fresh.money = if Config.Sandbox.On then Config.Sandbox.StartMoney else Config.StudioStartMoney
	end
	fresh.character = profiles[player].character -- (10.1: the slot's courier stays)
	profiles[player] = fresh
	extras[player] = nil -- (8.3: a fresh start keeps no newer server's keys either)
	PlayerData.save(player)
end

function PlayerData.release(player: Player)
	-- 5.7: the leave save runs after every other PlayerRemoving handler (Business pays the last accrual, Jobs ends a
	-- job, Fuel and Vehicles store the tank and the damage): a deferred thread starts once they all had their turn.
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

-- 7.0: a story card seen (shared/MoveStory.luau SeenKeys: "intro"), kept in the save; the attribute MoveStory follows
-- (Changed). True when it was new; an unknown key or a profile not loaded yet changes nothing.
function PlayerData.markStory(player: Player, key: any): boolean
	local profile = profiles[player]
	if not profile or not MoveStory.isSeenKey(key) or profile.story[key] == true then
		return false
	end
	profile.story[key] = true
	changed:Fire(player)
	return true
end

-- A real, finite number: NaN or ±inf from a remote would poison the money and the items for good.
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

-- Gives a vehicle (the admin tools); true when it is new. 7.x: only one a player may have (Economy.isPlayerCar: the ZDC
-- Van, a bike); the employers give no car any more.
function PlayerData.giveCar(player: Player, id: string): boolean
	local profile = profiles[player]
	if not profile or not Economy.isPlayerCar(id) then
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
	changed:Fire(player)
	return new
end

-- 5.0: gives a piece of personal gear (Config.Kit: bought at Last Stop Supplies or ZDC Bags, the admin tools); true when it is new.
-- 6.23: a bag goes into profile.bags (this game only, never saved), the rest into the kit (yours for good).
function PlayerData.giveKit(player: Player, id: string): boolean
	local profile = profiles[player]
	local found: Config.KitDef? = nil
	for _, def in Config.Kit do
		if def.id == id then
			found = def
		end
	end
	if not profile or not found then
		return false
	end
	local into = PlayerData.kitTable(profile, found)
	if into[id] then
		return false
	end
	into[id] = true
	changed:Fire(player)
	return true
end

-- 6.23: the table a piece of kit is had in: a bag in profile.bags (this game), the rest in profile.kit (for good).
function PlayerData.kitTable(profile: Profile, def: Config.KitDef?): { [string]: boolean }
	return if def and def.extra ~= nil then profile.bags else profile.kit
end

-- 6.23: the kit as it is this game (profile.kit's pieces + the bags bought this game): what the client's state carries
-- and every reader that needs both (the room on foot, the outfit).
function PlayerData.kitNow(profile: Profile): { [string]: boolean }
	return require(Shared.Transport).withBags(profile.kit, profile.bags)
end

-- ── Driver levels (Config.Levels, shared/Levels.luau) ─────────────────────

-- 4.6, the career: every level reached whose reward (Config.Levels.Rewards) was not given yet gives it now, once
-- (profile.levelRewards): money (counted as earned), items (up to their max), a career paint, a title (shown at once
-- when none is). The client's level-up card (client/CareerUi.luau) shows the same reward from Config. 6.13: returns
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
		if reward.items then
			for _, def in Config.Items do
				local count = reward.items[def.id]
				if count and count > 0 then
					profile.items[def.id] = math.min(def.max, (profile.items[def.id] or 0) + math.floor(count))
				end
			end
		end
		-- 5.7: the shoes, 6.6: the tote (owned: their price); 6.23: a bag for this game (profile.bags)
		local kitCash = Career.grantKit(reward, PlayerData.kitTable(profile, Career.kitOf(reward)))
		profile.money += kitCash
		profile.earned += kitCash
		cash += kitCash
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
	profile.skills = SkillRules.clean(profile.skills, target) -- 6.20: a lower level than the points spent: all back
	local cash = giveLevelRewards(profile) -- 4.6: the levels it reached, once
	changed:Fire(player)
	tellMoney(player, cash, "Admin") -- 6.13: the admin's doing, not earned in play
	return target
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
