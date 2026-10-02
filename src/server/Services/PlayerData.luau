--!strict
-- Player state — the single source of truth. It is loaded from and saved to a DataStore (progress only).
-- Coins and wave are shown on the leaderboard (leaderstats), no custom GUI.

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balance = require(Shared.Config.Balance)
local Units = require(Shared.Config.Units)
local Maps = require(Shared.Config.Maps)
local Difficulties = require(Shared.Config.Difficulties)
local Achievements = require(Shared.Config.Achievements)
local Grid = require(Shared.Grid)
local Levels = require(Shared.Config.Levels)

export type Profile = {
	coins: number,
	xp: number, -- account experience (the account level is calculated from it)
	streak: number, -- waves won in a row (this session only)
	autoFight: boolean, -- start the next wave by itself after a win (this session only)
	quests: { day: string, progress: { [string]: number }, done: { [string]: boolean } }, -- today's daily quests
	board: Grid.Cells, -- the INVENTORY = the 6x6 merge board (only the first `boardSlots` pads are usable)
	boardSlots: number, -- unlocked merge slots, bought with upgrades
	squad: Grid.Cells, -- the squad that fights (one row of six)
	purchases: number,
	startLevel: number, -- merge level a bought soldier starts at (upgraded at the lobby station)
	tierUnlocked: { [string]: number }, -- per class: the highest merge level bought for it (coins + cleared waves)
	mageUpgrades: { [string]: number }, -- the Mage's upgrade tracks (shared/MageUpgrades.luau): level per track
	wave: number, -- the highest wave you can fight (progress)
	selectedWave: number, -- the wave you will fight next (1 … wave), set in the Waves tab
	difficulty: string, -- key of Config/Difficulties, set in the Waves tab
	battling: boolean,
	mapCleared: boolean, -- the map's last wave was cleared once
	nextWaveAt: number, -- os.clock() time before which the next wave cannot start (result screen / defeat)
	luckyMisses: number, -- clears in a row without a lucky drop (pity counter)
	pendingUnits: { Grid.Unit }, -- drops waiting for the result screen to finish (then they enter the inventory)
	pendingUnlock: string?, -- class unlocked by the lucky drop, applied together with pendingUnits
	coinDrops: { [number]: { value: number } }, -- coins lying on the ground (client shows them, pays on pickup)
	nextCoinId: number,
	unlocked: { [string]: boolean }, -- unlocked classes
	rolling: boolean, -- roll animation running (actions are locked)
	map: string, -- current map (Config/Maps)
	bestWave: number, -- the highest wave ever reached (offline income)
	stats: { [string]: number }, -- lifetime counters for achievements (Config/Achievements.luau)
	achievements: { [string]: boolean }, -- done achievements
	title: string?, -- the title shown over your head (the latest achievement)
	lastSeen: number, -- os.time() of the last save (offline income)
	settings: { [string]: any }, -- volume, numbers, arrows (arena holograms), music
	battleSpeed: number, -- 1 or 2 (this session only)
}

local PlayerData = {}

local profiles: { [Player]: Profile } = {}

function PlayerData.spawnCost(profile: Profile): number
	return 0 -- soldiers are free: coins are for upgrades and for unlocking merge levels
end

-- Account level from total experience: (level, experience into this level, experience this level needs).
function PlayerData.levelInfo(xp: number): (number, number, number)
	local level = 1
	local needed = math.floor(Balance.XpLevelBase * level ^ Balance.XpLevelPower)
	while xp >= needed do
		xp -= needed
		level += 1
		needed = math.floor(Balance.XpLevelBase * level ^ Balance.XpLevelPower)
	end
	return level, xp, needed
end

-- The daily quests: a new day (UTC) starts them over.
function PlayerData.questDay(profile: Profile)
	local day = os.date("!%Y%m%d") :: string
	if profile.quests.day ~= day then
		profile.quests = { day = day, progress = {}, done = {} }
	end
end

-- The quests as the client shows them: { id, label, progress, target, done }.
function PlayerData.questsView(profile: Profile): { { [string]: any } }
	PlayerData.questDay(profile)
	local view = {}
	for _, quest in Balance.Quests do
		table.insert(view, {
			id = quest.id,
			label = string.format(quest.text, quest.target),
			progress = profile.quests.progress[quest.id] or 0,
			target = quest.target,
			done = profile.quests.done[quest.id] == true,
		})
	end
	return view
end

-- Waves cleared so far.
function PlayerData.clearedWaves(profile: Profile): number
	if profile.mapCleared then
		return Maps.Defs[profile.map].waves
	end
	return profile.wave - 1
end

-- The next merge level of a class and what it needs, or nil when the class is maxed.
function PlayerData.nextTierUnlock(profile: Profile, class: string): (number?, { wave: number, cost: number }?)
	local tier = (profile.tierUnlocked[class] or 1) + 1
	if tier > Units.maxTier(class) then
		return nil, nil
	end
	return tier, Balance.TierUnlocks[tier]
end

-- Cost of the next start-level upgrade (lobby station), or nil at the maximum.
function PlayerData.levelUpgradeCost(profile: Profile): number?
	if profile.startLevel >= Balance.StartLevelMax then
		return nil
	end
	return math.floor(Balance.StartLevelBaseCost * Balance.StartLevelGrowth ^ (profile.startLevel - 1))
end

-- Cost of the next merge-slot upgrade, or nil when every slot is unlocked.
function PlayerData.upgradeCost(profile: Profile): number?
	if profile.boardSlots >= Balance.BoardSize then
		return nil
	end
	local level = (profile.boardSlots - Balance.BoardStartSlots) // Balance.BoardUpgradeStep
	return math.floor(Balance.BoardUpgradeBaseCost * Balance.BoardUpgradeGrowth ^ level)
end

function PlayerData.get(player: Player): Profile?
	return profiles[player]
end

function PlayerData.isUnlocked(profile: Profile, class: string): boolean
	return profile.unlocked[class] == true
end

-- Unlocked classes in Units.ClassList order.
function PlayerData.unlockedClasses(profile: Profile): { string }
	local out = {}
	for _, class in Units.ClassList do
		if profile.unlocked[class] then
			table.insert(out, class)
		end
	end
	return out
end

-- A brand new profile (also what the admin reset goes back to).
local function fresh(): Profile
	local unlocked: { [string]: boolean } = {}
	local tierUnlocked: { [string]: number } = {}
	for _, class in Units.ClassList do
		tierUnlocked[class] = Units.maxTier(class) -- merging is never capped (the Upgrades tab is gone)
		if not Units.Classes[class].unlock then
			unlocked[class] = true
		end
	end
	return {
		coins = Balance.StartCoins,
		xp = 0,
		streak = 0,
		autoFight = false,
		quests = { day = "", progress = {}, done = {} },
		board = Grid.new(Balance.BoardSize),
		boardSlots = Balance.BoardStartSlots,
		-- There is no summoning: a new player starts with four level 1 Mages already in the squad (merge two for a
		-- level 2; more come as wave drops).
		squad = (function(): Grid.Cells
			local squad = Grid.new(Balance.SquadSize)
			for i = 1, 4 do
				squad[i] = { class = "Mage", tier = 1 }
			end
			return squad
		end)(),
		purchases = 0,
		startLevel = 1,
		tierUnlocked = tierUnlocked,
		mageUpgrades = {},
		wave = 1,
		selectedWave = 1,
		difficulty = Difficulties.Default,
		battling = false,
		mapCleared = false,
		nextWaveAt = 0,
		luckyMisses = 0,
		pendingUnits = {},
		pendingUnlock = nil,
		coinDrops = {},
		nextCoinId = 0,
		unlocked = unlocked,
		rolling = false,
		map = Maps.First,
		bestWave = 1,
		stats = {},
		achievements = {},
		title = nil,
		lastSeen = 0,
		settings = { volume = 1, numbers = true, arrows = true, music = true, layout = "" }, -- layout: where the player dragged the UI panels (JSON, client-owned)
		battleSpeed = 1,
	}
end

-- ── Saving ────────────────────────────────────────────────────────────────

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(Balance.DataStoreName)
end)
local canSave: { [Player]: boolean } = {} -- false when loading failed: never overwrite a save we could not read

local function saveKey(player: Player): string
	return "Player_" .. player.UserId
end

local function copyUnit(raw: any): Grid.Unit?
	if type(raw) == "table" and type(raw.class) == "string" and type(raw.tier) == "number" then
		-- A soldier of a removed class (Knight, Archer, …) in an old save becomes a Mage of the same level.
		local class = if Units.isValidClass(raw.class) then raw.class else Units.ClassList[1]
		return { class = class, tier = math.clamp(math.floor(raw.tier), 1, Units.maxTier(class)), ascended = if raw.ascended == true then true else nil }
	end
	return nil
end

local function cleanCells(raw: any, size: number): Grid.Cells
	local cells = Grid.new(size)
	if type(raw) == "table" then
		for i = 1, size do
			cells[i] = copyUnit(raw[i]) or false
		end
	end
	return cells
end

-- Puts saved data (checked, never trusted) into a fresh profile.
local function applySaved(profile: Profile, saved: any)
	if type(saved) ~= "table" then
		return
	end
	local function number(value: any, default: number, low: number, high: number): number
		if type(value) ~= "number" or value ~= value then
			return default
		end
		return math.clamp(math.floor(value), low, high)
	end
	profile.coins = number(saved.coins, profile.coins, 0, 2 ^ 50)
	profile.xp = number(saved.xp, 0, 0, 2 ^ 50)
	if type(saved.quests) == "table" and type(saved.quests.day) == "string" then
		local quests = { day = saved.quests.day, progress = {}, done = {} }
		for _, quest in Balance.Quests do
			quests.progress[quest.id] = number(if type(saved.quests.progress) == "table" then saved.quests.progress[quest.id] else 0, 0, 0, quest.target)
			quests.done[quest.id] = type(saved.quests.done) == "table" and saved.quests.done[quest.id] == true
		end
		profile.quests = quests
	end
	profile.boardSlots = number(saved.boardSlots, profile.boardSlots, Balance.BoardStartSlots, Balance.BoardSize)
	profile.board = cleanCells(saved.board, Balance.BoardSize)
	profile.squad = cleanCells(saved.squad, Balance.SquadSize)
	-- A squad saved when it had more places than today (it was 3 x 3 = 9): the soldiers beyond the last place
	-- go to free pads of the merge board (unlocked pads first), and when there is no room they are sold.
	if type(saved.squad) == "table" then
		for i = Balance.SquadSize + 1, 30 do
			local unit = copyUnit(saved.squad[i])
			if unit then
				local placed = false
				for pass = 1, 2 do
					for id = 1, Balance.BoardSize do
						if not profile.board[id] and (pass == 2 or Grid.isBoardUnlocked(id, profile.boardSlots)) then
							profile.board[id] = unit
							placed = true
							break
						end
					end
					if placed then
						break
					end
				end
				if not placed then
					profile.coins += Levels.sellValue(unit.tier, unit.ascended)
				end
			end
		end
	end
	profile.purchases = number(saved.purchases, 0, 0, 2 ^ 40)
	for _, class in Units.ClassList do
		local raw = if type(saved.tierUnlocked) == "table" then saved.tierUnlocked[class] elseif type(saved.tierUnlocked) == "number" then saved.tierUnlocked else nil
		local _ = raw -- an old save's bought cap is ignored: merging is never capped any more
		profile.tierUnlocked[class] = Units.maxTier(class)
	end
	profile.startLevel = number(saved.startLevel, 1, 1, Balance.StartLevelMax)
	if type(saved.map) == "string" and Maps.Defs[saved.map] then
		profile.map = saved.map
	end
	profile.wave = number(saved.wave, 1, 1, Maps.Defs[profile.map].waves)
	profile.selectedWave = number(saved.selectedWave, profile.wave, 1, profile.wave)
	if type(saved.difficulty) == "string" and Difficulties.Defs[saved.difficulty] then
		profile.difficulty = saved.difficulty
	end
	profile.mapCleared = saved.mapCleared == true
	profile.bestWave = number(saved.bestWave, profile.wave, 1, 100000)
	if type(saved.stats) == "table" then
		for _, key in Achievements.StatKeys do
			profile.stats[key] = number(saved.stats[key], 0, 0, 2 ^ 40)
		end
	end
	if type(saved.achievements) == "table" then
		for id in Achievements.ById do
			if saved.achievements[id] == true then
				profile.achievements[id] = true
			end
		end
	end
	if type(saved.title) == "string" and #saved.title <= 32 then
		profile.title = saved.title
	end
	profile.lastSeen = number(saved.lastSeen, 0, 0, 2 ^ 40)
	if type(saved.settings) == "table" then
		for key, default in profile.settings do
			local value = saved.settings[key]
			if type(value) == type(default) then
				profile.settings[key] = if type(value) == "number" then math.clamp(value, 0, 1) else value
			end
		end
	end
	profile.luckyMisses = number(saved.luckyMisses, 0, 0, 1000)
	if type(saved.mageUpgrades) == "table" then
		for _, id in Balance.MageUpgradeOrder do
			profile.mageUpgrades[id] = number(saved.mageUpgrades[id], 0, 0, Balance.MageUpgradeMax)
		end
	end
	if type(saved.unlocked) == "table" then
		for _, class in Units.ClassList do
			if saved.unlocked[class] == true then
				profile.unlocked[class] = true
			end
		end
	end
	-- Drops that were still waiting for the result screen when the player left.
	if type(saved.pending) == "table" then
		for _, raw in saved.pending do
			local unit = copyUnit(raw)
			if unit then
				table.insert(profile.pendingUnits, unit)
			end
		end
	end
	if type(saved.pendingUnlock) == "string" and Units.isValidClass(saved.pendingUnlock) then
		profile.pendingUnlock = saved.pendingUnlock
	end
end

-- What is written to the DataStore: only progress (no timers, no roll / battle state).
local function serialize(profile: Profile): { [string]: any }
	local function cells(source: Grid.Cells): { any }
		local out = {}
		for i = 1, #source do
			local unit = source[i]
			out[i] = if unit then { class = unit.class, tier = unit.tier, ascended = unit.ascended } else false
		end
		return out
	end
	local pending = {}
	for _, unit in profile.pendingUnits do
		table.insert(pending, { class = unit.class, tier = unit.tier, ascended = unit.ascended })
	end
	return {
		version = 1,
		coins = profile.coins,
		xp = profile.xp,
		quests = profile.quests,
		board = cells(profile.board),
		boardSlots = profile.boardSlots,
		squad = cells(profile.squad),
		purchases = profile.purchases,
		startLevel = profile.startLevel,
		tierUnlocked = profile.tierUnlocked,
		mageUpgrades = profile.mageUpgrades,
		wave = profile.wave,
		selectedWave = profile.selectedWave,
		difficulty = profile.difficulty,
		mapCleared = profile.mapCleared,
		luckyMisses = profile.luckyMisses,
		unlocked = profile.unlocked,
		map = profile.map,
		bestWave = profile.bestWave,
		stats = profile.stats,
		achievements = profile.achievements,
		title = profile.title,
		lastSeen = os.time(),
		settings = profile.settings,
		pending = pending,
		pendingUnlock = profile.pendingUnlock,
	}
end

-- Reads the saved data of a player. Returns (data or nil, ok): ok = false means the DataStore could not
-- be read (then nothing is saved for this player this session, so the old save is never overwritten).
function PlayerData.load(player: Player): (any, boolean)
	if not store then
		return nil, false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync(saveKey(player))
		end)
		if ok then
			return result, true
		end
		warn("[PlayerData] load failed:", result)
		-- Studio without API access / an unpublished place never works: do not wait for retries.
		local message = tostring(result)
		if string.find(message, "Studio access") or string.find(message, "publish") or string.find(message, "403") then
			return nil, false
		end
		task.wait(attempt)
	end
	return nil, false
end

-- Is saving on for this player? (false when the saved data could not be read: then nothing is written.)
function PlayerData.savingOn(player: Player): boolean
	return canSave[player] == true
end

function PlayerData.save(player: Player): boolean
	local profile = profiles[player]
	if not profile or not store or not canSave[player] then
		return false
	end
	local data = serialize(profile)
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			(store :: DataStore):SetAsync(saveKey(player), data)
		end)
		if ok then
			return true
		end
		warn("[PlayerData] save failed:", err)
		task.wait(attempt)
	end
	return false
end

-- Admin reset: the same profile table goes back to a brand new state (other code holds on to it).
function PlayerData.reset(profile: Profile)
	for key in profile :: any do
		(profile :: any)[key] = nil
	end
	for key, value in fresh() :: any do
		(profile :: any)[key] = value
	end
end

-- A lifetime counter (achievements) goes up.
function PlayerData.addStat(profile: Profile, key: string, amount: number)
	profile.stats[key] = (profile.stats[key] or 0) + amount
end

-- The value an achievement looks at.
function PlayerData.statValue(profile: Profile, key: string): number
	if key == "level" then
		return (PlayerData.levelInfo(profile.xp))
	end
	return profile.stats[key] or 0
end

function PlayerData.create(player: Player, saved: any?, loadedOk: boolean?): Profile
	local profile = fresh()
	applySaved(profile, saved)
	canSave[player] = loadedOk ~= false
	profiles[player] = profile

	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	for _, name in { "Coins", "Wave", "Level" } do
		local value = Instance.new("IntValue")
		value.Name = name
		value.Parent = stats
	end
	stats.Parent = player

	return profile
end

function PlayerData.remove(player: Player)
	profiles[player] = nil
	canSave[player] = nil
end

-- Rewrites leaderstats from the profile.
function PlayerData.updateStats(player: Player)
	local profile = profiles[player]
	local stats = player:FindFirstChild("leaderstats")
	if not profile or not stats then
		return
	end
	(stats:FindFirstChild("Coins") :: IntValue).Value = profile.coins;
	(stats:FindFirstChild("Wave") :: IntValue).Value = profile.wave;
	(stats:FindFirstChild("Level") :: IntValue).Value = (PlayerData.levelInfo(profile.xp))
end

return PlayerData
