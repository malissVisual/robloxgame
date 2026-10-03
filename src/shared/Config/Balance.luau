--!strict
-- All tuning numbers in one place.

local Balance = {
	-- Inventory = merge board (6 × 6 pads in the lobby next to your spawn): every soldier you own that
	-- is not equipped stands on a pad, and the same soldiers are the cards of the UI inventory.
	-- You start with only a few usable slots (= the inventory size) and buy more with upgrades.
	BoardColumns = 6,
	BoardSize = 36,
	BoardStartSlots = 6,
	BoardUpgradeStep = 3, -- slots gained per upgrade
	BoardUpgradeBaseCost = 40, -- cost of the first upgrade
	BoardUpgradeGrowth = 1.6, -- every upgrade costs 60% more
	-- The Mage's upgrades (shared/MageUpgrades.luau): bought in a mage's card, they apply to every mage. Three
	-- tracks, each up to MageUpgradeMax levels; level n costs MageUpgradeBaseCost x MageUpgradeGrowth ^ (n - 1).
	MageUpgrades = {
		power = { label = "POWER", text = "+%d%% damage", step = 0.05 },
		vitality = { label = "VITALITY", text = "+%d%% HP", step = 0.05 },
		swiftness = { label = "SWIFTNESS", text = "+%d%% attack speed", step = 0.03 },
	},
	MageUpgradeOrder = { "power", "vitality", "swiftness" },
	-- THE WIZARDS (Config/Wizards.luau): the summon portal in the lobby, the income, the luck of the drops.
	WizardSummonCost = 200, -- coins for one summon …
	WizardSummonTenCost = 1800, -- … and for ten at once (a 10% discount)
	SummonPity = 40, -- summons without an Epic or better → the next one is Epic or better
	SummonLevel = 1, -- the level of a summoned wizard
	IncomeTick = 5, -- seconds between two payouts of the wizards' income (coins per minute, Wizards.income)
	CodexCompleteBonus = 0.25, -- every type found: +25% income
	DropLuckPerWave = 0.012, -- a wave drop's luck = 1 + wave × this (bosses ×1.6, Nightmare ×1.3)
	MageUpgradeMax = 20,
	MageUpgradeBaseCost = 60,
	MageUpgradeGrowth = 1.3,
	-- Squad: the soldiers that actually fight: exactly six, in ONE row side by side (left to right), in the
	-- arena. The squad has no upgrades and the pads give no bonuses: the six just stand there, well apart.
	SquadColumns = 6,
	SquadSize = 6,
	SquadSpacing = 12, -- between the squad pads (the merge board uses the tighter SlotSpacing)
	-- Slot ids: the board is 1 … BoardSize, the squad is SquadOffset + 1 … SquadOffset + SquadSize.
	SquadOffset = 100,

	StartCoins = 30,
	-- Summoning at the altars in the lobby: one summon gives SummonCount soldiers and costs SummonCost coins
	-- (the better summoner: BetterSummonCost); every altar has a cooldown between two summons. With fewer
	-- free places in the inventory you get fewer soldiers and pay only for those.
	SummonCost = 15,
	SummonCount = 2,
	SummonCooldown = 0.8, -- seconds between two summons at an altar (only against spamming; there is no roll to wait for)

	-- Level upgrade (a station in the lobby): bought soldiers start at a higher merge level instead of 1.
	StartLevelMax = 5, -- the highest level a bought soldier can start at
	StartLevelBaseCost = 250, -- cost of the first upgrade (level 1 -> 2)
	StartLevelGrowth = 3, -- every further upgrade costs 3x more

	-- Soldiers cost coins at the altars (see SummonCost). Every soldier class has its OWN
	-- merge level limit: you start unable to merge a class at all (limit 1) and buy its next level with
	-- coins (and enough cleared waves). Without the upgrade two identical soldiers cannot be merged.
	StartUnlockedTier = 1,
	TierUnlocks = { -- the price of merge level N (for one class): cleared waves needed + coins
		[2] = { wave = 0, cost = 50 },
		[3] = { wave = 1, cost = 150 },
		[4] = { wave = 3, cost = 400 },
		[5] = { wave = 8, cost = 1000 },
		[6] = { wave = 15, cost = 2500 },
		[7] = { wave = 25, cost = 6000 },
		[8] = { wave = 40, cost = 15000 },
		[9] = { wave = 60, cost = 40000 },
		-- levels 10 … 30 (the Mage goes this far) are filled in below
	},

	-- Account level (shown top left): experience from kills and won waves. Going from level L to L + 1
	-- takes floor(XpLevelBase * L ^ XpLevelPower) experience.
	XpLevelBase = 60,
	XpLevelPower = 1.5,
	XpPerKill = 4, -- per enemy level (a level-2 enemy gives 8) plus the wave number
	XpPerWave = 25, -- for a won wave, plus 5 per wave number

	-- Saving (DataStore) and admin tools.
	DataStoreName = "MergeBladesV1",
	SaveInterval = 60, -- seconds between autosaves
	AdminUserIds = {} :: { number }, -- extra admins (the game owner and everyone in Studio are always admins)
	AdminUnlockCoins = 1000000, -- coins the admin "UNLOCK ALL" button gives
	AdminProgressCoins = 1000, -- coins the admin "+ PROGRESS" button gives

	-- (The pads of the squad give no bonuses: where a soldier stands only decides what it fights first.)
	-- Synergies of the squad (see Synergy.luau): two roles, Frontline and Ranged, and a mixed squad.
	SynergyLow = { count = 2, bonus = 0.10 }, -- 2 soldiers of a role
	SynergyHigh = { count = 3, bonus = 0.20 }, -- 3 or more soldiers of a role
	SynergyMixedClasses = 4, -- this many different classes in the squad ...
	SynergyMixedBonus = 0.10, -- ... give +10% HP and damage to everybody

	-- Daily quests (three per day, they reset at midnight UTC): progress counts while you play.
	Quests = {
		{ id = "kills", text = "Defeat %d enemies", target = 40, coins = 200, xp = 60 },
		{ id = "waves", text = "Win %d waves", target = 3, coins = 300, xp = 80 },
		{ id = "merges", text = "Merge %d times", target = 10, coins = 150, xp = 40 },
	},

	-- The better summoner (a second altar in the lobby, from wave 10 of Training Camp): it costs coins, but a
	-- soldier it summons starts at least at level BetterSummonMinLevel (or your start level, if higher)
	-- and can get up to 3 more levels, even above what you may merge (the merge limit of its class).
	BetterSummonWave = 10, -- cleared waves needed
	BetterSummonCost = 150, -- coins for one summon (SummonCount soldiers)
	BetterSummonMinLevel = 2,
	BetterSummonBonus = { -- extra levels on top: chance of each (the rest of the rolls give +0)
		{ levels = 3, chance = 0.05 },
		{ levels = 2, chance = 0.15 },
		{ levels = 1, chance = 0.35 },
	},

	-- Elite waves: a normal (not boss) wave has this chance to be ELITE: stronger, golden enemies, double
	-- coins, a guaranteed extra drop and a doubled spell-drop chance.
	EliteChance = 0.1,
	EliteMinWave = 3,
	ElitePower = 1.5,
	EliteCoins = 2,

	-- Boss abilities (BattleService): the boss's look decides which one it has.
	BossSlamEvery = 8, -- Brute: every N seconds hits your soldiers within BossSlamRadius for BossSlamDamage x its damage
	BossSlamRadius = 9,
	BossSlamDamage = 2,
	BossSlamStun = 1, -- seconds your hit soldiers cannot act
	BossSummonAt = 0.5, -- Chief: at this fraction of HP it summons BossSummonCount mobs of the phase (once)
	BossSummonCount = 2,
	BossVolleyEvery = 6, -- Archer: every N seconds every soldier of yours in range takes BossVolleyDamage x its damage
	BossVolleyDamage = 0.6,
	BossHealEvery = 7, -- Shaman: every N seconds heals every enemy for BossHealFraction of its max HP
	BossHealFraction = 0.08,

	-- Offline income: while you are away you earn coins per hour for every wave of your best wave, up to
	-- OfflineMaxHours hours.
	OfflineCoinsPerWaveHour = 6,
	OfflineMaxHours = 8,

	-- Rewards.
	LevelRewardCoins = 50, -- coins for reaching an account level (times the level)
	LevelRewardSlotsEvery = 5, -- every 5th account level also gives merge slots ...
	LevelRewardSlots = 3, -- ... this many
	BonusDropChance = 0.08, -- chance that a wave drop is one level higher (always on a boss wave)
	StreakBonus = 0.05, -- +5% coins per won wave in a row ...
	StreakMax = 5, -- ... up to 5 waves (+25%)

	-- Coins come ONLY from killing enemies (no bonus for clearing a wave). One kill pays
	-- floor((KillCoinBase + KillCoinPerWave * wave) * (1 + KillCoinPerLevel * (enemyLevel - 1)))
	-- times the difficulty's reward multiplier.
	KillCoinBase = 8,
	KillCoinPerWave = 2,
	KillCoinPerLevel = 0.2,
	-- The coins of a kill lie on the ground as a few pickups (not paid until you pick them up).
	CoinsPerKillMax = 6, -- a kill's coins are split into at most this many pickups (more for a bonus)
	-- Chance for a kill to drop MORE coins than usual: one roll per kill, the multipliers are checked
	-- in this order (so the total bonus chance is the sum: 1% + 4% + 15% = 20%).
	CoinBonus = {
		{ multiplier = 5, chance = 0.01 },
		{ multiplier = 3, chance = 0.04 },
		{ multiplier = 2, chance = 0.15 },
	},
	CoinMagnetRadius = 30, -- studs: coins this close fly to you smoothly (generous, so collecting is easy)
	CoinLifetime = 40, -- seconds on the ground before a coin flies to you on its own

	-- World (studs, z is the direction from the lobby to the enemies)
	SlotSpacing = 7, -- between pads (the characters are ~0.9-1.26 of an R15; 7 leaves air between them)
	-- Every player gets their own plot (own spawn, board, arena). Plots are laid out in a grid:
	PlotsPerRow = 4,
	PlotSpacingX = 190, -- between plots side by side (a plot is 160 wide)
	PlotSpacingZ = 330, -- between rows of plots (a plot is 296 long)
	BoardStart = -50, -- z of the board's back row (rows go up to z = -15), in the lobby
	SquadStart = 43, -- z of the squad's row (one row of six), inside the arena, just before the round fight arena's step (z 56)
	EnemyFront = 204, -- z of the enemies' row (one row, side by side; the round fight arena, z 56 … 196, is between the two rows)

	-- Enemy waves (see Config/Waves.luau): a map's waves come in phases of PhaseLength waves.
	PhaseLength = 5,
	EnemyBase = 2, -- enemies in a wave = EnemyBase + wave * EnemyPerWave, at most EnemyMax
	EnemyPerWave = 1,
	EnemyMax = 12,
	HordeMax = 18, -- the SWARM twist (Config/Mutators.luau) may raise a wave to this many enemies (the row holds 19 on the 160 wide plot)
	MutatorCoinsCap = 0.35, -- the coin bonus of a wave's twists together is at most +35 %
	EnemyHpBoost = 1.7, -- every enemy's HP and damage are multiplied by these (the wave difficulty in one place)
	EnemyDamageBoost = 1.4,
	EnemyLevelScale = 1.2, -- each enemy level (= phase number, every 5 waves) makes an enemy this much stronger
	-- THE WAVE CURVE: on top of all that, the enemies of wave W get WaveHp(W) times the HP and WaveDamage(W) times the
	-- damage (points in between are interpolated). Without it a squad killed every wave in 1-4 s (the mages merge
	-- 1.8x per level, the waves grew far slower), so nothing of the fight (spells, dodges, Fury, Overcharge, boss
	-- slams and volleys) ever happened. Tuned on a model of a player who wins every wave, summons with the coins
	-- and merges every pair: a fight takes about 14 s of shooting at wave 1, 20-25 s later, a boss wave a third
	-- longer (plus the walk in), and the squad loses about a third of its HP. An under-merged squad struggles and
	-- may lose (Balance.BattleTimeLimit); replaying low waves stays quick.
	-- BOSSES are long fights, not one-shots: a boss (every 5th wave and the Rift King) gets BossHp × the HP but only
	-- BossDamage × the damage, so the squad has to grind it down without dying in seconds. Damage that is a part of
	-- the target's max HP (burns: the Ember Mage, Smolder, Inferno) hurts a boss only BossPercentDamage as much, or
	-- a big HP pool would not matter. A boss wave may last BossBattleTimeLimit seconds.
	BossHp = 3.5,
	BossDamage = 0.6,
	BossPercentDamage = 0.3,
	BossBattleTimeLimit = 180,
	WaveHp = { { 1, 3.5 }, { 5, 4.8 }, { 10, 7.5 }, { 20, 13 }, { 30, 22 }, { 45, 27 }, { 60, 24 }, { 80, 17 }, { 100, 11 } },
	WaveDamage = { { 1, 0.7 }, { 5, 0.8 }, { 10, 1.3 }, { 20, 2 }, { 30, 2.7 }, { 45, 3 }, { 60, 2.5 }, { 80, 1.7 }, { 100, 1.1 } },

	-- Roll animation of a bought soldier (UI only): swirl, then reveal (seconds)
	RollTime = 1.1,
	RollReveal = 0.3,
	PlaceFlightTime = 0.55, -- a soldier flies from the inventory onto its pad this long (then it is placed)

	BattleTickRate = 1 / 20,
	BattleSpeeds = { 1, 2 }, -- the speeds the SPEED button cycles through
	BattleTimeLimit = 90, -- battle counts as a loss after this many seconds (the arena is big)
	BattleCountdown = 1.1, -- the black fade with FIGHT! before the fight starts (seconds); the end fades 1 s
	RewardTime = 4.5, -- seconds after a won wave before the next one may start (the result screen takes longer anyway)
	ResultHold = 1.4, -- seconds the camera stays on the battlefield after the fight (victory poses) before the fade and the result screen
	DropCollectTime = 180, -- fallback: the loot reaches the inventory after this long even if CLAIM LOOT is never clicked
	DefeatCooldown = 3, -- seconds before you can try again after a defeat
	LuckyDropPity = 4, -- clears in a row without a lucky drop before one is guaranteed
	SplashRadius = 6,
	SplashFraction = 0.5,
}

-- The wave curve's multipliers of enemy HP and damage at a wave (Balance.WaveHp / WaveDamage, interpolated between
-- the points on a log scale; before the first / after the last point the end values hold).
local function curve(points: { { number } }, wave: number): number
	if wave <= points[1][1] then
		return points[1][2]
	end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if wave <= b[1] then
			local f = (wave - a[1]) / (b[1] - a[1])
			return math.exp(math.log(a[2]) + (math.log(b[2]) - math.log(a[2])) * f)
		end
	end
	return points[#points][2]
end

function Balance.waveScale(wave: number?): (number, number)
	if type(wave) ~= "number" or wave < 1 then
		return 1, 1
	end
	return curve(Balance.WaveHp, wave), curve(Balance.WaveDamage, wave)
end

-- Merge levels 10 … 30 exist for the Mage (its 30-level evolution, maxTier in Units):
-- every further level needs two more cleared waves (up to 100) and costs 25 % more coins than the one before.
for tier = 10, 30 do
	Balance.TierUnlocks[tier] = { wave = math.min(100, 60 + 2 * (tier - 9)), cost = math.floor(40000 * 1.25 ^ (tier - 9)) }
end

return Balance
