--!strict
-- Drives the player: plot, buying (into the UI inventory), dragging soldiers between the
-- inventory, the 3D merge board and the squad, upgrades, the wave system and the battle.
-- The server validates everything; the client only asks.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Grid = require(Shared.Grid)
local Units = require(Shared.Config.Units)
local Levels = require(Shared.Config.Levels)
local Waves = require(Shared.Config.Waves)
local Difficulties = require(Shared.Config.Difficulties)
local Enemies = require(Shared.Config.Enemies)
local Spells = require(Shared.Config.Spells)
local Achievements = require(Shared.Config.Achievements)
local Maps = require(Shared.Config.Maps)
local Net = require(Shared.Net)
local Balance = require(Shared.Config.Balance)

local BattleService = require(script.Parent.BattleService)
local PlayerData = require(script.Parent.PlayerData)
local Plots = require(script.Parent.Plots)

local GameService = {}

local rng = Random.new()

local plots: { [Player]: Plots.Plot } = {}
local usedIndexes: { [number]: boolean } = {}

-- Defined further down (onSpawn needs it as a fallback timer).
local collectPending: (player: Player) -> () = function() end

-- The game owner, everyone listed in Balance.AdminUserIds and every player in Studio are admins
-- (they get the RESET / + PROGRESS buttons).
local adminCache: { [Player]: boolean } = {}
local function isAdmin(player: Player): boolean
	local cached = adminCache[player]
	if cached ~= nil then
		return cached
	end
	local admin = RunService:IsStudio() or table.find(Balance.AdminUserIds, player.UserId) ~= nil
	if not admin then
		if game.CreatorType == Enum.CreatorType.User then
			admin = player.UserId == game.CreatorId
		elseif game.CreatorType == Enum.CreatorType.Group then
			local ok, rank = pcall(function()
				return player:GetRankInGroup(game.CreatorId)
			end)
			admin = ok and rank >= 255
		end
	end
	adminCache[player] = admin
	return admin
end

-- State for the client UI: bottom bar, inventory, merge slots, soldiers index and waves.
local function pushState(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local upgradeCost = PlayerData.upgradeCost(profile)
	local accountLevel, xpInto, xpNeeded = PlayerData.levelInfo(profile.xp)
	local boardFree, squadFree = 0, 0
	for id = 1, Balance.BoardSize do
		if not profile.board[id] and Grid.isBoardUnlocked(id, profile.boardSlots) then
			boardFree += 1
		end
	end
	for i = 1, Balance.SquadSize do
		if not profile.squad[i] then
			squadFree += 1
		end
	end
	Net.get("State"):FireClient(player, {
		coins = profile.coins,
		cost = PlayerData.spawnCost(profile),
		wave = profile.wave,
		selectedWave = profile.selectedWave,
		map = profile.map,
		mapWaves = Maps.Defs[profile.map].waves,
		difficulty = profile.difficulty,
		unlocked = profile.unlocked,
		rolling = profile.rolling,
		battling = profile.battling,
		nextWaveIn = math.max(0, profile.nextWaveAt - os.clock()), -- seconds until the next wave can start
		rollTime = Balance.RollTime + Balance.RollReveal + 0.6, -- the roll popup plus the card's flight
		battleLimit = Balance.BattleTimeLimit,
		board = profile.board, -- the inventory (= merge board), by slot id
		squad = profile.squad, -- the equipped soldiers
		boardSlots = profile.boardSlots,
		boardFree = boardFree,
		squadFree = squadFree,
		boardMax = Balance.BoardSize,
		upgradeCost = upgradeCost or 0, -- 0 = everything is already unlocked
		upgradeMaxed = upgradeCost == nil,
		startLevel = profile.startLevel,
		startLevelMax = Balance.StartLevelMax,
		levelCost = PlayerData.levelUpgradeCost(profile) or 0, -- 0 = at the maximum
		tierUnlocked = profile.tierUnlocked,
		level = accountLevel,
		autoFight = profile.autoFight,
		spells = profile.spells,
		saving = PlayerData.savingOn(player),
		quests = PlayerData.questsView(profile),
		mapCleared = profile.mapCleared,
		streak = profile.streak,
		xpInto = xpInto,
		xpNeeded = xpNeeded,
		cleared = PlayerData.clearedWaves(profile),
		isAdmin = isAdmin(player),
		stats = profile.stats,
		achievements = profile.achievements,
		title = profile.title,
		settings = profile.settings,
		battleSpeed = profile.battleSpeed,
		bestWave = profile.bestWave,
	})
end

-- Short on-screen message for the player (shown as a toast by the client).
local function notify(player: Player, text: string)
	Net.get("Notice"):FireClient(player, text)
end

local function refresh(player: Player)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot then
		return
	end
	PlayerData.updateStats(player)
	if not profile.battling then
		Plots.showEnemies(plot, profile.selectedWave, profile.difficulty)
	end
	Plots.render(plot, profile.board, profile.squad, profile.boardSlots)
	pushState(player)
end

-- Plays a sound on the client (Config/Sounds.luau).
local function sfx(player: Player, name: string)
	Net.get("Sfx"):FireClient(player, name)
end

-- The title over the player's head (the latest achievement).
local function showTitle(player: Player, profile: PlayerData.Profile)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not profile.title then
		return
	end
	local gui = head:FindFirstChild("TitleTag") :: BillboardGui?
	if not gui then
		gui = Instance.new("BillboardGui")
		local made = gui :: BillboardGui
		made.Name = "TitleTag"
		made.Size = UDim2.fromOffset(200, 24)
		made.StudsOffset = Vector3.new(0, 2.6, 0)
		made.AlwaysOnTop = true
		made.MaxDistance = 80
		made.Parent = head
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBold
		text.TextSize = 14
		text.TextColor3 = Color3.fromRGB(255, 205, 90)
		text.TextStrokeTransparency = 0.4
		text.Parent = made
	end
	local text = (gui :: BillboardGui):FindFirstChild("Text") :: TextLabel
	text.Text = "★ " .. profile.title
end

local addXp: (Player, PlayerData.Profile, number) -> () = function() end -- defined below

-- Checks every achievement against the profile's counters; a finished one pays and becomes your title.
local function checkAchievements(player: Player, profile: PlayerData.Profile)
	for _, def in Achievements.List do
		if not profile.achievements[def.id] and PlayerData.statValue(profile, def.stat) >= def.target then
			profile.achievements[def.id] = true
			profile.coins += def.coins
			profile.title = def.label
			notify(player, string.format("ACHIEVEMENT: %s (%s) · +%d coins%s", def.label, def.text, def.coins, if def.xp > 0 then string.format(" · +%d XP", def.xp) else ""))
			sfx(player, "achievement")
			showTitle(player, profile)
			if def.xp > 0 then
				addXp(player, profile, def.xp)
			end
		end
	end
end

-- A lifetime counter goes up and the achievements are checked.
local function addStat(player: Player, profile: PlayerData.Profile, key: string, amount: number)
	PlayerData.addStat(profile, key, amount)
	checkAchievements(player, profile)
end

-- Gives account experience. Every account level gives coins, and every 5th one also merge slots;
-- the level up is announced (the top-left HUD shows the new state with the next refresh).
addXp = function(player: Player, profile: PlayerData.Profile, amount: number)
	local before = PlayerData.levelInfo(profile.xp)
	profile.xp += math.max(0, math.floor(amount))
	local after = PlayerData.levelInfo(profile.xp)
	local slotsChanged = false
	for level = before + 1, after do
		local coins = Balance.LevelRewardCoins * level
		profile.coins += coins
		local text = string.format("LEVEL UP! Level %d · +%d coins", level, coins)
		if level % Balance.LevelRewardSlotsEvery == 0 and profile.boardSlots < Balance.BoardSize then
			profile.boardSlots = math.min(Balance.BoardSize, profile.boardSlots + Balance.LevelRewardSlots)
			slotsChanged = true
			text ..= string.format(" · +%d merge slots", Balance.LevelRewardSlots)
		end
		notify(player, text)
		sfx(player, "levelUp")
	end
	if slotsChanged then
		refresh(player)
	end
	if after > before then
		checkAchievements(player, profile)
	end
end

-- Daily quest progress (kills, won waves, merges): when one is complete it pays coins and XP.
local function questProgress(player: Player, profile: PlayerData.Profile, id: string, amount: number)
	PlayerData.questDay(profile)
	local quests = profile.quests
	if quests.done[id] then
		return
	end
	for _, quest in Balance.Quests do
		if quest.id == id then
			local progress = math.min(quest.target, (quests.progress[id] or 0) + amount)
			quests.progress[id] = progress
			if progress >= quest.target then
				quests.done[id] = true
				profile.coins += quest.coins
				notify(player, string.format("QUEST DONE: %s · +%d coins", string.format(quest.text, quest.target), quest.coins))
				addXp(player, profile, quest.xp)
			end
			return
		end
	end
end

-- The inventory IS the merge board: the first `boardSlots` pads (front row first) hold your
-- soldiers, so whatever is in the inventory is automatically visible on the 3D merge board.

-- The first free usable pad of the inventory / merge board (front row first), or nil when full.
local function firstFreeBoardSlot(profile: PlayerData.Profile): number?
	local best: number?, bestRank = nil, math.huge
	for id = 1, Balance.BoardSize do
		if not profile.board[id] then
			local rank = Grid.boardRank(id)
			if rank <= profile.boardSlots and rank < bestRank then
				best, bestRank = id, rank
			end
		end
	end
	return best
end

local function countFreeBoard(profile: PlayerData.Profile): number
	local free = 0
	for id = 1, Balance.BoardSize do
		if not profile.board[id] and Grid.isBoardUnlocked(id, profile.boardSlots) then
			free += 1
		end
	end
	return free
end

-- Puts a soldier into the inventory (the first free pad). When the inventory is full the soldier
-- is sold instead. Returns true if it was stored.
local function addToInventory(profile: PlayerData.Profile, unit: Grid.Unit): boolean
	local id = firstFreeBoardSlot(profile)
	if not id then
		profile.coins += Levels.sellValue(unit.tier, unit.ascended)
		return false
	end
	profile.board[id] = unit
	return true
end

-- The client drags a soldier from one pad onto another (`from`, `to`).
-- Move / merge / swap is decided by Grid.interact.
local function onInteract(player: Player, from: any, to: any)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or profile.battling or profile.rolling then
		return
	end
	local fromCells, fromIndex = Grid.resolve(profile.board, profile.squad, from, profile.boardSlots)
	local toCells, toIndex = Grid.resolve(profile.board, profile.squad, to, profile.boardSlots)
	if not fromCells or not fromIndex or not toCells or not toIndex then
		return
	end
	local a, b = fromCells[fromIndex], toCells[toIndex]
	if a and b and a.class == b.class and a.tier == b.tier and not Grid.canMerge(a, b, profile.tierUnlocked) and not (a.ascended or b.ascended) then
		notify(player, if a.tier >= Units.MaxTier then string.format("Two level 9 %ss become an ASCENDED one once level 9 of the class is bought (UPGRADES tab)", Units.Classes[a.class].label) else string.format("%s level %d is locked — buy it in the UPGRADES tab (coins + cleared waves)", Units.Classes[a.class].label, a.tier + 1))
		sfx(player, "error")
	end
	local result = Grid.interact(fromCells, fromIndex, toCells, toIndex, profile.tierUnlocked)
	if not result then
		return
	end
	if result == "merge" then
		questProgress(player, profile, "merges", 1)
		local made = toCells[toIndex]
		if made then
			PlayerData.addStat(profile, "merges", 1)
			profile.stats.maxTier = math.max(profile.stats.maxTier or 0, made.tier)
			if made.ascended then
				PlayerData.addStat(profile, "ascended", 1)
			end
			checkAchievements(player, profile)
			sfx(player, if made.tier >= 5 then "mergeBig" else "merge")
		end
	end
	refresh(player)
	if result == "merge" then
		local cell = toCells[toIndex]
		if cell then
			Plots.mergeEffect(plot, Plots.slotGround(plot, from), to, cell.tier)
		end
	end
end

-- Auto merge: merges every possible pair of the inventory (merge board) AND the battle squad (same
-- class and level), over and over, until nothing can be merged any more. When a pair has a soldier
-- in the squad, the merged soldier stays in the squad (on the first squad pad of the pair).
local function onAutoMerge(player: Player)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or profile.battling or profile.rolling then
		return
	end
	-- Slot ids in the order they are checked: the squad first, then the usable board pads.
	local order: { number } = {}
	for i = 1, Balance.SquadSize do
		table.insert(order, Balance.SquadOffset + i)
	end
	for id = 1, Balance.BoardSize do
		if Grid.isBoardUnlocked(id, profile.boardSlots) then
			table.insert(order, id)
		end
	end
	local function cell(id: number): Grid.Cell
		local cells, index = Grid.resolve(profile.board, profile.squad, id, profile.boardSlots)
		return if cells and index then cells[index] else false
	end
	local function set(id: number, value: Grid.Cell)
		local cells, index = Grid.resolve(profile.board, profile.squad, id, profile.boardSlots)
		if cells and index then
			cells[index] = value
		end
	end

	local merges = 0
	local lastFrom: { [number]: number } = {} -- target pad -> a pad that was merged into it
	local changed = true
	while changed do
		changed = false
		local waiting: { [string]: number } = {} -- "class|level" -> first pad holding one
		for _, id in order do
			local unit = cell(id)
			if unit and Grid.canMerge(unit, unit, profile.tierUnlocked) then
				local key = unit.class .. "|" .. unit.tier
				local other = waiting[key]
				if other then
					local made = Grid.mergeResult(unit)
					profile.stats.maxTier = math.max(profile.stats.maxTier or 0, made.tier)
					if made.ascended then
						PlayerData.addStat(profile, "ascended", 1)
					end
					set(other, made)
					set(id, false)
					lastFrom[other] = id
					waiting[key] = nil
					merges += 1
					changed = true
				else
					waiting[key] = id
				end
			end
		end
	end
	if merges == 0 then
		notify(player, "Nothing to merge — you need two identical characters and the level bought in the UPGRADES tab")
		return
	end
	questProgress(player, profile, "merges", merges)
	addStat(player, profile, "merges", merges)
	sfx(player, "mergeBig")
	refresh(player)
	-- A burst on every pad that ended up with a merged soldier (a few at a time so it stays readable).
	local shown = 0
	for target, source in lastFrom do
		local result = cell(target)
		if result and shown < 8 then
			shown += 1
			task.delay(shown * 0.12, function()
				if plots[player] == plot and cell(target) == result then
					Plots.mergeEffect(plot, Plots.slotGround(plot, source), target, result.tier)
				end
			end)
		end
	end
	notify(player, string.format("Auto merged %d times", merges))
end

-- Equip best: the strongest soldiers (all of the squad and the inventory) go into the battle squad;
-- the others wait in the inventory.
local function onEquipBest(player: Player)
	local profile = PlayerData.get(player)
	if not profile or profile.battling or profile.rolling then
		return
	end
	local entries: { { unit: Grid.Unit, score: number } } = {}
	local function add(unit: Grid.Cell)
		if unit then
			local stats = Units.stats(unit.class, unit.tier, unit.ascended)
			table.insert(entries, { unit = unit, score = stats.hp * stats.damage / stats.cooldown })
		end
	end
	for i = 1, Balance.SquadSize do
		add(profile.squad[i])
	end
	for id = 1, Balance.BoardSize do
		if Grid.isBoardUnlocked(id, profile.boardSlots) and profile.board[id] then
			add(profile.board[id])
		end
	end
	table.sort(entries, function(a, b)
		return a.score > b.score
	end)

	-- Rebuild: the best go to the squad, the rest to the first free inventory pads.
	local newSquad = Grid.new(Balance.SquadSize)
	local rest: { Grid.Unit } = {}
	for i, entry in entries do
		if i <= Balance.SquadSize then
			newSquad[i] = entry.unit
		else
			table.insert(rest, entry.unit)
		end
	end
	local changedSquad = false
	for i = 1, Balance.SquadSize do
		if newSquad[i] ~= profile.squad[i] then
			changedSquad = true
		end
	end
	if not changedSquad then
		notify(player, "Your squad is already the best")
		return
	end
	local newBoard = Grid.new(Balance.BoardSize)
	local nextRest = 1
	for id = 1, Balance.BoardSize do
		if Grid.isBoardUnlocked(id, profile.boardSlots) and rest[nextRest] then
			newBoard[id] = rest[nextRest]
			nextRest += 1
		end
	end
	profile.squad = newSquad
	profile.board = newBoard
	refresh(player)
	notify(player, "Equipped your best characters")
end

-- Equip: a soldier from the inventory goes into the first free slot of the battle squad.
local function onEquip(player: Player, id: any)
	local profile = PlayerData.get(player)
	if not profile or profile.battling or profile.rolling then
		return
	end
	local cells, index = Grid.resolve(profile.board, profile.squad, id, profile.boardSlots)
	if cells ~= profile.board or not index then
		return
	end
	local unit = profile.board[index]
	if not unit then
		return
	end
	local free = Grid.firstEmpty(profile.squad)
	if not free then
		notify(player, "Your battle squad is full — unequip a character first")
		return
	end
	profile.squad[free] = unit
	profile.board[index] = false
	refresh(player)
end

-- Unequip: a squad soldier goes back to the inventory (the first free pad). Also used when a squad
-- soldier is dropped onto the inventory panel.
local function onUnequip(player: Player, id: any)
	local profile = PlayerData.get(player)
	if not profile or profile.battling or profile.rolling then
		return
	end
	local cells, index = Grid.resolve(profile.board, profile.squad, id, profile.boardSlots)
	if cells ~= profile.squad or not index then
		return
	end
	local unit = profile.squad[index]
	if not unit then
		return
	end
	local free = firstFreeBoardSlot(profile)
	if not free then
		notify(player, "Your inventory is full — merge characters or buy more merge slots")
		return
	end
	profile.board[free] = unit
	profile.squad[index] = false
	refresh(player)
end

-- The level a soldier of the BETTER summoner gets: at least Balance.BetterSummonMinLevel (or your start
-- level), plus 0 - 3 bonus levels; it may be above the merge limit of its class.
local function rollBetterTier(profile: PlayerData.Profile): number
	local roll = rng:NextNumber()
	local bonus = 0
	local threshold = 0
	for _, entry in Balance.BetterSummonBonus do
		threshold += entry.chance
		if roll < threshold then
			bonus = entry.levels
			break
		end
	end
	return math.min(math.max(profile.startLevel, Balance.BetterSummonMinLevel) + bonus, Units.MaxTier)
end

-- Summoning: an altar gives Balance.SummonCount soldiers for Balance.SummonCost coins (the better summoner,
-- amount = "better", needs cleared waves, costs more and gives better levels). Each altar has a cooldown.
local summonReadyAt: { [Player]: { [string]: number } } = {}
local function onSpawn(player: Player, amount: any)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or profile.battling or profile.rolling then
		return
	end
	local better = amount == "better"
	local kind = if better then "better" else "basic"
	local now = os.clock()
	local cooldowns = summonReadyAt[player]
	if not cooldowns then
		cooldowns = {}
		summonReadyAt[player] = cooldowns
	end
	if (cooldowns[kind] or 0) > now then
		notify(player, string.format("Summoning again in %ds", math.ceil((cooldowns[kind] or 0) - now)))
		return
	end
	local free = countFreeBoard(profile)
	if free <= 0 then
		notify(player, "Your inventory is full — sell or merge characters, or buy more merge slots")
		return
	end
	local count = math.min(Balance.SummonCount, free)
	if better then
		local cleared = PlayerData.clearedWaves(profile)
		if cleared < Balance.BetterSummonWave then
			notify(player, string.format("The better summoner needs %d cleared waves in Arena 1 (you have %d)", Balance.BetterSummonWave, cleared))
			return
		end
	end
	-- The price is for a full summon; with fewer free places you get fewer soldiers and pay only for those.
	local fullCost = if better then Balance.BetterSummonCost else Balance.SummonCost
	local cost = math.ceil(fullCost * count / Balance.SummonCount)
	if profile.coins < cost then
		notify(player, string.format("%s costs %d coins (%d characters)", if better then "The better summoner" else "Summoning", cost, count))
		return
	end
	profile.coins -= cost
	cooldowns[kind] = now + Balance.SummonCooldown
	profile.purchases += count
	addStat(player, profile, "summons", count)

	-- No roll to wait for: the soldiers land on the first free pads right away (a light beam on each), and the
	-- client shows a short message with what came out.
	local pool = PlayerData.unlockedClasses(profile)
	local classes: { string } = {}
	local tiers: { number } = {}
	local landed: { number } = {}
	for _ = 1, count do
		local class = pool[rng:NextInteger(1, #pool)]
		local tier = if better then rollBetterTier(profile) else math.min(profile.startLevel, profile.tierUnlocked[class] or 1)
		local id = firstFreeBoardSlot(profile)
		if id then
			profile.board[id] = { class = class, tier = tier }
			table.insert(landed, id)
		else
			profile.coins += Levels.sellValue(tier)
		end
		table.insert(classes, class)
		table.insert(tiers, tier)
	end
	refresh(player)
	for _, id in landed do
		local unit = profile.board[id]
		if unit then
			Plots.dropEffect(plot, id, unit.tier)
		end
	end
	Net.get("RollResult"):FireClient(player, pool, classes, tiers)
end

-- Selling: a soldier of the inventory or the squad goes for coins (Levels.sellValue).
local function onSell(player: Player, id: any)
	local profile = PlayerData.get(player)
	if not profile or profile.battling or profile.rolling then
		return
	end
	local cells, index = Grid.resolve(profile.board, profile.squad, id, profile.boardSlots)
	if not cells or not index then
		return
	end
	local unit = cells[index]
	if not unit then
		return
	end
	local price = Levels.sellValue(unit.tier, unit.ascended)
	cells[index] = false
	profile.coins += price
	refresh(player)
	notify(player, string.format("Sold %s %s for %d coins", Units.Classes[unit.class].label, Levels.label(unit.tier), price))
	sfx(player, "coins")
end

-- Level upgrade (lobby station): bought soldiers start at a higher merge level.
local function onUpgradeLevel(player: Player)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or profile.battling or profile.rolling then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not Plots.isInUpgradeZone(plot, root.Position) then
		notify(player, "Go to the level upgrade station in the lobby")
		return
	end
	local cost = PlayerData.levelUpgradeCost(profile)
	if not cost then
		notify(player, "Characters already start at the highest level")
		return
	end

	if profile.coins < cost then
		notify(player, string.format("Not enough coins (the next level costs %d)", cost))
		return
	end
	profile.coins -= cost
	profile.startLevel += 1
	refresh(player)
	notify(player, string.format("New characters now start at level %d!", profile.startLevel))
end

-- Buys the next merge level of one soldier class: needs enough cleared waves and coins. Without it
-- two soldiers of that class cannot be merged past the level bought so far.
local function onUnlockTier(player: Player, class: any)
	local profile = PlayerData.get(player)
	if not profile or profile.battling or profile.rolling then
		return
	end
	if not Units.isValidClass(class) or not profile.unlocked[class] then
		return
	end
	local label = Units.Classes[class].label
	local tier, def = PlayerData.nextTierUnlock(profile, class)
	if not tier or not def then
		notify(player, string.format("%s is already at the highest level", label))
		return
	end
	local cleared = PlayerData.clearedWaves(profile)
	if cleared < def.wave then
		notify(player, string.format("%s level %d needs %d cleared waves (you have %d)", label, tier, def.wave, cleared))
		return
	end
	if profile.coins < def.cost then
		notify(player, string.format("%s level %d costs %d coins", label, tier, def.cost))
		return
	end
	profile.coins -= def.cost
	profile.tierUnlocked[class] = tier
	refresh(player)
	PlayerData.save(player)
	notify(player, string.format("%s: you can now merge up to level %d", label, tier))
end

-- Admin: +1 wave of progress and some coins.
local function onAdminProgress(player: Player)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or not isAdmin(player) or profile.battling or profile.rolling then
		return
	end
	if profile.wave < plot.map.waves then
		profile.wave += 1
		profile.selectedWave = profile.wave
	else
		profile.mapCleared = true
	end
	profile.coins += Balance.AdminProgressCoins
	addXp(player, profile, Balance.XpPerWave + 5 * profile.wave)
	refresh(player)
	notify(player, string.format("Admin: wave %d reached, +%d coins", profile.wave, Balance.AdminProgressCoins))
end

-- Admin: everything unlocked at once: every class and all its merge levels, every spell, all merge slots,
-- the best start level, every wave of the map (so any wave can be picked) and a pile of coins.
local function onAdminUnlock(player: Player)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or not isAdmin(player) or profile.battling or profile.rolling then
		return
	end
	for _, class in Units.ClassList do
		profile.unlocked[class] = true
		profile.tierUnlocked[class] = Units.MaxTier
	end
	for _, id in Spells.Order do
		profile.spells.owned[id] = true
	end
	profile.boardSlots = Balance.BoardSize
	profile.startLevel = Balance.StartLevelMax
	profile.wave = plot.map.waves
	profile.mapCleared = true
	profile.bestWave = math.max(profile.bestWave, plot.map.waves)
	profile.coins += Balance.AdminUnlockCoins
	refresh(player)
	notify(player, "Admin: everything unlocked")
end

-- Admin: wipes the whole progress (and the saved data) and starts over.
local function onAdminReset(player: Player)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or not isAdmin(player) or profile.battling or profile.rolling then
		return
	end
	table.clear(profile.coinDrops)
	Net.get("CoinsClear"):FireClient(player)
	PlayerData.reset(profile)
	refresh(player)
	PlayerData.save(player)
	notify(player, "Admin: progress reset")
end

local function onUpgrade(player: Player)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or profile.battling or profile.rolling then
		return
	end
	local cost = PlayerData.upgradeCost(profile)
	if not cost then
		notify(player, "All merge slots are already unlocked")
		return
	end
	if profile.coins < cost then
		notify(player, string.format("Not enough coins (the next upgrade costs %d)", cost))
		return
	end
	local old = profile.boardSlots
	profile.coins -= cost
	profile.boardSlots = math.min(Balance.BoardSize, old + Balance.BoardUpgradeStep)
	refresh(player)
	-- A light beam on every newly unlocked pad.
	for id = 1, Balance.BoardSize do
		local rank = Grid.boardRank(id)
		if rank > old and rank <= profile.boardSlots then
			Plots.dropEffect(plot, id, 3)
		end
	end
	notify(player, string.format("Merge slots: %d / %d", profile.boardSlots, Balance.BoardSize))
end

-- Wave system: choose which wave to fight (any wave you have reached, so you can repeat old ones).
local function onSetWave(player: Player, wave: any)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or profile.battling or profile.rolling then
		return
	end
	if type(wave) ~= "number" or wave % 1 ~= 0 or wave < 1 or wave > profile.wave then
		return
	end
	profile.selectedWave = wave
	refresh(player)
end

-- Wave system: choose the difficulty (enemy power and coin rewards).
local function onSetDifficulty(player: Player, difficulty: any)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or profile.battling or profile.rolling then
		return
	end
	if type(difficulty) ~= "string" or not Difficulties.Defs[difficulty] then
		return
	end
	profile.difficulty = difficulty
	refresh(player)
end

type Drop = { class: string, tier: number, stored: boolean, bonus: boolean }

-- Drop for a won wave: a random unlocked class; the higher the wave, the higher its level.
-- It is only queued here; it enters the inventory after the result screen (collectPending).
local function battleDrop(profile: PlayerData.Profile, wave: number, guaranteedBonus: boolean): Drop
	local pool = PlayerData.unlockedClasses(profile)
	local class = pool[rng:NextInteger(1, #pool)]
	local tier = math.min(1 + wave // 7, 5, profile.tierUnlocked[class] or 1)
	-- A bonus drop is one level higher (always on a boss wave, otherwise a small chance).
	local bonus = guaranteedBonus or rng:NextNumber() < Balance.BonusDropChance
	if bonus then
		tier = math.min(tier + 1, Units.MaxTier)
	end
	local stored = countFreeBoard(profile) > #profile.pendingUnits
	table.insert(profile.pendingUnits, { class = class, tier = tier })
	return { class = class, tier = tier, stored = stored, bonus = bonus }
end

-- Lucky drop: a chance to unlock one of the locked classes that can drop from this wave on
-- (`Units.Classes[...].unlock.wave`). The unlocked class also arrives as a Lv 1 soldier in the
-- inventory. After Balance.LuckyDropPity clears in a row without luck, the next one is guaranteed.
-- Returns the classes that were in the draw and the class that was unlocked (or nil).
local function luckyDrop(profile: PlayerData.Profile, wave: number, chance: number): ({ string }, string?)
	local eligible: { string } = {}
	for _, class in Units.lockedClasses() do
		local unlock = Units.Classes[class].unlock :: Units.Unlock
		if unlock.wave <= wave and not PlayerData.isUnlocked(profile, class) then
			table.insert(eligible, class)
		end
	end
	if #eligible == 0 then
		return eligible, nil
	end

	profile.luckyMisses += 1
	if profile.luckyMisses >= Balance.LuckyDropPity or rng:NextNumber() < chance then
		-- A weighted pick: a class with a small `weight` (the legendary Soldier) is rarer.
		local totalWeight = 0
		for _, candidate in eligible do
			totalWeight += (Units.Classes[candidate].unlock :: Units.Unlock).weight or 1
		end
		local pick = rng:NextNumber() * totalWeight
		local class = eligible[#eligible]
		for _, candidate in eligible do
			pick -= (Units.Classes[candidate].unlock :: Units.Unlock).weight or 1
			if pick < 0 then
				class = candidate
				break
			end
		end
		profile.pendingUnlock = class -- applied together with the drop (collectPending)
		table.insert(profile.pendingUnits, { class = class, tier = 1 })
		profile.luckyMisses = 0
		return eligible, class
	end
	return eligible, nil
end

-- ── XP on the ground ──
-- Coins of a kill go straight to your balance. The XP of a kill is split into a few orbs: the client
-- shows them lying on the ground and reports each pickup (CollectCoin, the name is historic);
-- nothing is given before that. Leftovers are given by a timer and when the next battle starts, so
-- no XP is ever lost.

local function payXp(player: Player, id: any): boolean
	local profile = PlayerData.get(player)
	if not profile or type(id) ~= "number" then
		return false
	end
	local drop = profile.coinDrops[id]
	if not drop then
		return false -- unknown or already paid
	end
	profile.coinDrops[id] = nil
	addXp(player, profile, drop.value)
	pushState(player)
	return true
end

-- Rolls the bonus multiplier of a kill (1 = no bonus): it multiplies the coins AND the XP of the kill.
-- See Balance.CoinBonus.
local function rollCoinBonus(): number
	local roll = rng:NextNumber()
	local threshold = 0
	for _, bonus in Balance.CoinBonus do
		threshold += bonus.chance
		if roll < threshold then
			return bonus.multiplier
		end
	end
	return 1
end

local function dropXp(player: Player, profile: PlayerData.Profile, value: number, position: Vector3, multiplier: number)
	-- A bonus drops more pickups too, so it is easy to see.
	local count = math.clamp(math.ceil(value / 8), 1, Balance.CoinsPerKillMax + (multiplier - 1) * 2)
	local list: { { id: number, value: number } } = {}
	local remaining = value
	for i = 1, count do
		local part = if i == count then remaining else math.floor(value / count)
		remaining -= part
		profile.nextCoinId += 1
		local id = profile.nextCoinId
		profile.coinDrops[id] = { value = part }
		table.insert(list, { id = id, value = part })
		-- Fallback: pay it even if the client never picks it up.
		task.delay(Balance.CoinLifetime + 8, function()
			payXp(player, id)
		end)
	end
	Net.get("CoinDrop"):FireClient(player, list, position, multiplier)
end

-- Gives every XP orb still lying on the ground (a new battle starts) and tells the client to make
-- them fly away.
local function payAllXp(player: Player)
	local profile = PlayerData.get(player)
	if not profile or next(profile.coinDrops) == nil then
		return
	end
	local ids = {}
	for id in profile.coinDrops do
		table.insert(ids, id)
	end
	for _, id in ids do
		payXp(player, id)
	end
	Net.get("CoinsClear"):FireClient(player)
end

-- Moves the queued drop (and the lucky-drop soldier + unlock) into the inventory. The client
-- calls it (CollectDrops) when the cards have flown into the inventory panel; a timer calls it as
-- a fallback. Safe to call twice.
collectPending = function(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	-- The drops have landed (or the result screen was skipped): the next wave may start soon.
	if not profile.battling and profile.nextWaveAt > os.clock() + 0.4 then
		profile.nextWaveAt = os.clock() + 0.4
	end
	local wasRolling = profile.rolling
	profile.rolling = false -- a UI roll is over once its soldier has been delivered
	if #profile.pendingUnits == 0 and not profile.pendingUnlock then
		if wasRolling then
			refresh(player)
		end
		return
	end
	if profile.pendingUnlock then
		profile.unlocked[profile.pendingUnlock] = true
		profile.pendingUnlock = nil
	end
	local units = table.clone(profile.pendingUnits)
	table.clear(profile.pendingUnits)
	for _, unit in units do
		addToInventory(profile, unit) -- sold if the inventory is full
	end
	refresh(player)
end

-- Auto fight on / off (the client button in the battle panel).
local function onAutoFight(player: Player, value: any)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	profile.autoFight = value == true
	pushState(player)
end

-- Spells (Config/Spells.luau): you carry two, one on Q and one on E; each slot has its own cooldown. The
-- client sends the slot (and, when the player holds SHIFT, the point he aims at on the arena floor); without
-- a point the spell aims itself (auto aim).
local abilityReadyAt: { [Player]: { [string]: number } } = {}
local function onAbility(player: Player, slot: any, position: any)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or not profile.battling then
		return
	end
	if slot ~= "q" and slot ~= "e" then
		return
	end
	local id = (profile.spells.slots :: { [string]: string })[slot]
	local def = Spells.Defs[id]
	if not def then
		return
	end
	local cooldowns = abilityReadyAt[player]
	if not cooldowns then
		cooldowns = {}
		abilityReadyAt[player] = cooldowns
	end
	local now = os.clock()
	if (cooldowns[slot] or 0) > now then
		return
	end

	-- With a point (the player aims with the mouse) it must be a real position inside the arena's range.
	local target: Vector3? = nil
	if def.aimed and position ~= nil then
		if typeof(position) ~= "Vector3" or position.X ~= position.X or position.Z ~= position.Z then
			return
		end
		local center = plot.arena.center
		if (Vector3.new(position.X, 0, position.Z) - Vector3.new(center.X, 0, center.Z)).Magnitude > Balance.SpellRange then
			return
		end
		target = Vector3.new(position.X, center.Y, position.Z)
	end
	local ok, reason = BattleService.spell(player, id, target)
	if not ok and reason then
		notify(player, reason)
	end
	if ok then
		cooldowns[slot] = now + def.cooldown
		Net.get("Ability"):FireClient(player, slot, def.cooldown) -- the client shows the cooldown
		addStat(player, profile, "spellsCast", 1)
		sfx(player, "spell")
	end
end

-- Puts an owned spell into the Q or the E slot (if it is in the other slot, the two swap).
local function onEquipSpell(player: Player, id: any, slot: any)
	local profile = PlayerData.get(player)
	if not profile or profile.battling or profile.rolling then
		return
	end
	if not Spells.isValid(id) or (slot ~= "q" and slot ~= "e") or not profile.spells.owned[id] then
		return
	end
	local slots = profile.spells.slots :: { [string]: string }
	local other = if slot == "q" then "e" else "q"
	if slots[other] == id then
		slots[other] = slots[slot]
	end
	slots[slot] = id
	pushState(player)
end

-- After a won wave a spell can drop (and stays yours): only spells whose dropWave has been reached and that
-- you do not own yet. The chance is the difficulty's lucky-drop chance x Balance.SpellDropFactor (doubled
-- on a boss wave). Returns the id of the new spell.
local function rollSpellDrop(player: Player, profile: PlayerData.Profile, wave: number, luckyChance: number, isBoss: boolean): string?
	local eligible: { string } = {}
	for _, id in Spells.Order do
		local def = Spells.Defs[id]
		if def.dropWave and wave >= def.dropWave and not profile.spells.owned[id] then
			table.insert(eligible, id)
		end
	end
	if #eligible == 0 then
		return nil
	end
	local chance = luckyChance * Balance.SpellDropFactor * (if isBoss then 2 else 1)
	if rng:NextNumber() >= chance then
		return nil
	end
	local id = eligible[rng:NextInteger(1, #eligible)]
	profile.spells.owned[id] = true
	notify(player, string.format("NEW SPELL: %s! Equip it in the SPELLS tab (you carry two).", Spells.Defs[id].label))
	return id
end

-- The SPEED button: cycles the battle speed (Balance.BattleSpeeds), also during a battle.
local function onBattleSpeed(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local speeds = Balance.BattleSpeeds
	local index = table.find(speeds, profile.battleSpeed) or 1
	profile.battleSpeed = speeds[index % #speeds + 1]
	pushState(player)
end

-- Settings: volume (0 - 1), and on / off for damage numbers, arena holograms, music.
local function onSetSetting(player: Player, key: any, value: any)
	local profile = PlayerData.get(player)
	if not profile or type(key) ~= "string" then
		return
	end
	local current = profile.settings[key]
	if current == nil or type(value) ~= type(current) then
		return
	end
	if type(value) == "string" and #value > 1000 then
		return -- the UI layout is a short JSON; anything longer is not ours
	end
	profile.settings[key] = if type(value) == "number" then math.clamp(value, 0, 1) else value
	pushState(player)
end

-- ── Offline income (on join) ──
-- While you were away you earned coins per hour for every wave of your best wave (up to OfflineMaxHours).
local function welcome(player: Player, profile: PlayerData.Profile)
	if profile.lastSeen <= 0 then
		return
	end
	local hours = math.min(Balance.OfflineMaxHours, (os.time() - profile.lastSeen) / 3600)
	if hours < 0.05 then
		return
	end
	local coins = math.floor(Balance.OfflineCoinsPerWaveHour * profile.bestWave * hours)
	if coins <= 0 then
		return
	end
	profile.coins += coins
	Net.get("WelcomeBack"):FireClient(player, { coins = coins, hours = hours })
	sfx(player, "coins")
end

local function onBattle(player: Player)
	local profile, plot = PlayerData.get(player), plots[player]
	if not profile or not plot or profile.battling or profile.rolling then
		return
	end
	-- The FIGHT button starts the selected wave from anywhere (the wave and difficulty are chosen
	-- up on the fight arena).
	local wait = profile.nextWaveAt - os.clock()
	if wait > 0 then
		notify(player, string.format("Next wave starts in %ds", math.ceil(wait)))
		return
	end
	if Grid.count(profile.squad) == 0 then
		if Grid.count(profile.board) == 0 then
			notify(player, "You have no characters — summon some at the altar")
		else
			notify(player, "Your squad is empty — click a character in the inventory and equip it")
		end
		return
	end

	local wave = profile.selectedWave
	local difficulty = Difficulties.Defs[profile.difficulty]
	payAllXp(player) -- XP left over from the last wave is given, then a fresh battle starts
	profile.battling = true
	refresh(player)

	-- You fight too (Q / E spells): START WAVE puts you into the arena, on its near edge behind your squad,
	-- looking at the enemies.
	local character = player.Character
	if character then
		local spot = plot.arena.center + Vector3.new(0, 3, -27)
		character:PivotTo(CFrame.lookAt(spot, spot + Vector3.new(0, 0, 1)))
	end

	-- Coins come only from kills and go straight to your balance (so progress is kept even when the
	-- wave is lost); the XP of a kill drops on the ground as orbs.
	local kills = 0
	local earnedCoins = 0 -- shown (small) on the result screen
	local isBoss = wave % Balance.PhaseLength == 0
	-- An ELITE wave (never a boss wave): stronger, golden enemies and doubled rewards.
	local isElite = not isBoss and wave >= Balance.EliteMinWave and rng:NextNumber() < Balance.EliteChance
	local streakMult = 1 + Balance.StreakBonus * math.min(profile.streak, Balance.StreakMax) -- waves won in a row
	local eliteMult = if isElite then Balance.EliteCoins else 1
	local function onKill(level: number, position: Vector3, coinMult: number)
		local base = math.floor(Waves.killReward(wave, level) * difficulty.rewardMultiplier * coinMult * streakMult * eliteMult)
		local multiplier = rollCoinBonus() -- a lucky kill drops x2, x3 or x5 the coins
		kills += 1
		questProgress(player, profile, "kills", 1)
		PlayerData.addStat(profile, "kills", 1)
		-- The coins go straight to your balance; the XP drops on the ground as orbs to pick up.
		profile.coins += base * multiplier
		earnedCoins += base * multiplier
		pushState(player)
		dropXp(player, profile, math.floor((Balance.XpPerKill * level + wave) * multiplier * difficulty.xpMultiplier), position, multiplier)
	end

	-- A boss wave is announced with a banner; SMITE is ready again for every wave.
	abilityReadyAt[player] = nil
	local _, phase = Waves.phase(wave, plot.map)
	if isBoss then
		Net.get("BossIntro"):FireClient(player, Enemies.Kinds[phase.boss].label)
		sfx(player, "boss")
	elseif isElite then
		Net.get("BossIntro"):FireClient(player, "ELITE WAVE")
		sfx(player, "elite")
	else
		sfx(player, "fight")
	end

	task.spawn(function()
		-- Get ready: 3, 2, 1, FIGHT!
		for i = Balance.BattleCountdown, 1, -1 do
			if plots[player] ~= plot then
				return
			end
			Net.get("Countdown"):FireClient(player, i)
			task.wait(1)
		end
		if plots[player] ~= plot then
			return
		end
		Net.get("Countdown"):FireClient(player, 0)

		BattleService.start(player, profile, plot, {
			enemyPower = difficulty.enemyPower * (if isElite then Balance.ElitePower else 1),
			elite = isElite,
			summonKind = phase.kinds[1],
			summonTier = (Waves.phase(wave, plot.map)),
		}, onKill, function(won)
			checkAchievements(player, profile)
			-- Back to the spawn once the fight is over.
			task.delay(1.2, function()
				local character = player.Character
				local home = plots[player]
				if character and home then
					character:PivotTo(home.respawn.CFrame + Vector3.new(0, 4, 0))
				end
			end)
			if not won then
				profile.streak = 0
				if profile.autoFight then
					profile.autoFight = false -- a defeat stops auto fight: merge / equip better first
					notify(player, "Auto fight stopped after a defeat")
				end
				profile.nextWaveAt = os.clock() + Balance.DefeatCooldown
				refresh(player)
				sfx(player, "lost")
				Net.get("WaveResult"):FireClient(player, {
					won = false,
					wave = wave,
					difficulty = difficulty.label,
					kills = kills,
					coins = earnedCoins,
					duration = Balance.DefeatCooldown,
				})
				return
			end

			-- The client plays the result screen (spinning coins, the drop, the lucky drop) over
			-- Balance.RewardTime seconds, during which the next wave cannot be started.
			-- The map's last wave does not open a new wave: it completes the map.
			local mapWaves = plot.map.waves
			local firstClear = wave == profile.wave and not (wave >= mapWaves and profile.mapCleared)
			local mapJustCleared = false
			if firstClear then
				if wave < mapWaves then
					profile.wave += 1
					profile.selectedWave = profile.wave
				else
					profile.mapCleared = true
					mapJustCleared = true
				end
			end
			profile.bestWave = math.max(profile.bestWave, wave)
			profile.streak += 1
			questProgress(player, profile, "waves", 1)
			PlayerData.addStat(profile, "wavesWon", 1)
			if isBoss then
				PlayerData.addStat(profile, "bossKills", 1)
			end
			if profile.difficulty == "Nightmare" then
				PlayerData.addStat(profile, "nightmareWaves", 1)
			end
			sfx(player, "won")
			addXp(player, profile, (Balance.XpPerWave + 5 * wave) * (if isBoss then 2 else 1) * difficulty.xpMultiplier)
			local drop = battleDrop(profile, wave, isBoss)
			local extraDrops: { Drop } = {} -- Nightmare (and an elite wave) gives an extra drop
			for _ = 1, difficulty.extraDrops + (if isElite then 1 else 0) do
				table.insert(extraDrops, battleDrop(profile, wave, false))
			end
			local candidates, lucky = luckyDrop(profile, wave, difficulty.luckyDropChance)
			local spellDrop = rollSpellDrop(player, profile, wave, difficulty.luckyDropChance, isBoss or isElite)
			checkAchievements(player, profile)
			profile.nextWaveAt = os.clock() + Balance.RewardTime
			refresh(player)

			task.spawn(PlayerData.save, player) -- progress is saved after every won wave

			-- Auto fight: the next wave starts by itself once the result screen is over.
			if profile.autoFight then
				task.delay(Balance.RewardTime + 0.6, function()
					if plots[player] == plot and profile.autoFight and not profile.battling and not profile.rolling then
						onBattle(player)
					end
				end)
			end

			task.delay(Balance.DropCollectTime, function()
				if plots[player] == plot then
					collectPending(player)
				end
			end)
			Net.get("WaveResult"):FireClient(player, {
				won = true,
				wave = wave,
				replay = not firstClear,
				mapCleared = mapJustCleared,
				mapLabel = plot.map.label,
				difficulty = difficulty.label,
				kills = kills,
				coins = earnedCoins,
				streak = profile.streak,
				boss = isBoss,
				elite = isElite,
				drop = drop,
				extraDrops = extraDrops,
				spellDrop = spellDrop,
				luckyCandidates = candidates,
				luckyResult = lucky,
				luckyChance = difficulty.luckyDropChance,
				duration = Balance.RewardTime,
			})
		end)
	end)
end

local function join(player: Player)
	local index = 1
	while usedIndexes[index] do
		index += 1
	end
	usedIndexes[index] = true

	local saved, loadedOk = PlayerData.load(player)
	if not player.Parent then
		usedIndexes[index] = nil
		return -- left while loading
	end
	local profile = PlayerData.create(player, saved, loadedOk)
	if not loadedOk then
		task.delay(4, function()
			notify(player, "Saving is OFF: enable Studio access to API services (Game Settings > Security) and publish the place")
		end)
	end
	local plot = Plots.create(index, player, profile.map)
	plots[player] = plot
	player.RespawnLocation = plot.respawn
	player.CameraMaxZoomDistance = 300 -- allow zooming out to see the whole battlefield

	-- Every player spawns on their own plot, even if the character loaded before
	-- RespawnLocation was set (or another plot's spawn was picked).
	-- The player runs 1.25x faster than the default 16 studs/s (Roblox's default walk speed).
	local WALK_SPEED = 16 * 1.25

	local function toOwnSpawn(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
		if humanoid then
			humanoid.WalkSpeed = WALK_SPEED
		end
		local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
		local home = plots[player]
		if root and home and (root.Position - home.respawn.Position).Magnitude > 40 then
			character:PivotTo(home.respawn.CFrame + Vector3.new(0, 4, 0))
		end
		showTitle(player, profile)
	end
	player.CharacterAdded:Connect(toOwnSpawn)
	if player.Character then
		task.spawn(toOwnSpawn, player.Character)
	end
	refresh(player)
	if #profile.pendingUnits > 0 or profile.pendingUnlock then
		collectPending(player) -- drops that were waiting when the player left last time
	end
	task.delay(2, function()
		if plots[player] then
			welcome(player, profile)
			checkAchievements(player, profile)
			refresh(player)
		end
	end)
end

local function leave(player: Player)
	local plot = plots[player]
	if plot then
		usedIndexes[plot.index] = nil
		Plots.destroy(plot)
	end
	plots[player] = nil
	adminCache[player] = nil
	abilityReadyAt[player] = nil
	summonReadyAt[player] = nil
	PlayerData.save(player)
	PlayerData.remove(player)
end

function GameService.init()
	-- E = buy, Q = battle, R = upgrade (the client sends key presses and drags).
	Net.get("Buy").OnServerEvent:Connect(onSpawn)
	Net.get("Battle").OnServerEvent:Connect(onBattle)
	Net.get("Upgrade").OnServerEvent:Connect(onUpgrade)
	Net.get("UnlockTier").OnServerEvent:Connect(onUnlockTier)
	Net.get("Ability").OnServerEvent:Connect(onAbility)
	Net.get("Sell").OnServerEvent:Connect(onSell)
	Net.get("EquipSpell").OnServerEvent:Connect(onEquipSpell)
	Net.get("AutoFight").OnServerEvent:Connect(onAutoFight)
	Net.get("AdminProgress").OnServerEvent:Connect(onAdminProgress)
	Net.get("AdminUnlock").OnServerEvent:Connect(onAdminUnlock)
	Net.get("AdminReset").OnServerEvent:Connect(onAdminReset)
	Net.get("UpgradeLevel").OnServerEvent:Connect(onUpgradeLevel)
	Net.get("BattleSpeed").OnServerEvent:Connect(onBattleSpeed)
	Net.get("SetSetting").OnServerEvent:Connect(onSetSetting)
	Net.get("AutoMerge").OnServerEvent:Connect(onAutoMerge)
	Net.get("EquipBest").OnServerEvent:Connect(onEquipBest)
	Net.get("SetWave").OnServerEvent:Connect(onSetWave)
	Net.get("SetDifficulty").OnServerEvent:Connect(onSetDifficulty)
	Net.get("CollectDrops").OnServerEvent:Connect(collectPending)
	Net.get("CollectCoin").OnServerEvent:Connect(payXp)
	Net.get("Interact").OnServerEvent:Connect(onInteract)
	Net.get("Equip").OnServerEvent:Connect(onEquip)
	Net.get("Unequip").OnServerEvent:Connect(onUnequip)
	Net.get("RequestState").OnServerEvent:Connect(pushState)
	Players.PlayerAdded:Connect(join)
	Players.PlayerRemoving:Connect(leave)
	for _, player in Players:GetPlayers() do
		task.spawn(join, player)
	end

	-- Autosave, and a last save when the server shuts down.
	task.spawn(function()
		while true do
			task.wait(Balance.SaveInterval)
			for _, player in Players:GetPlayers() do
				task.spawn(PlayerData.save, player)
			end
		end
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			task.spawn(PlayerData.save, player)
		end
		task.wait(3)
	end)
end

return GameService
