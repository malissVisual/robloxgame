--!strict
-- Enemy kinds. Enemies are NOT the player's soldier classes: every map has its own enemy folk (a ROSTER).
-- A roster has 20 phases (100 waves): every phase brings ONE NEW MOB and its own BOSS, so the wave changes
-- every 5 waves. A roster is generated from four archetypes and five families, so a new map's enemies
-- are a small table and not new models.
--
--   <prefix>Mob1 … Mob20    the mob that is new in phase N
--   <prefix>Boss1 … Boss20  the boss of phase N (the last wave of the phase)
--   Training Camp: prefix "" (Mob1 = Goblin … Mob20 = Demon Shaman).
--
-- An enemy has a kind and a level (1 …): the level (= the phase number) scales its stats
-- (see Balance.EnemyLevelScale and Waves.luau for how waves are made).

local Units = require(script.Parent.Units)
local Balance = require(script.Parent.Balance)

export type Kind = {
	label: string,
	look: string, -- which model of Enemy.luau it uses: Goblin, GoblinArcher, GoblinBrute, GoblinShaman, GoblinChief
	color: Color3, -- skin / main color
	hp: number,
	damage: number,
	range: number,
	cooldown: number,
	speed: number,
	splash: boolean,
	size: number, -- model size multiplier (a brute is bigger than a goblin)
	coins: number, -- multiplier of the coins it drops
	boss: boolean?, -- a boss (percent-damage spells hurt it less, and it has an ability: see BattleService)
}

type Family = { name: string, color: Color3, power: number, size: number }

local Enemies = {}

Enemies.Kinds = {} :: { [string]: Kind }
Enemies.PhaseCount = 20

local C = Color3.fromRGB

-- The four archetypes of normal mobs (the base of every family).
local ARCHETYPES = {
	Grunt = { look = "Goblin", hp = 35, damage = 5, range = 4, cooldown = 1.0, speed = 12, splash = false, size = 1, coins = 1, suffix = "" },
	Archer = { look = "GoblinArcher", hp = 25, damage = 6, range = 26, cooldown = 1.3, speed = 10, splash = false, size = 0.95, coins = 1.2, suffix = " Archer" },
	Brute = { look = "GoblinBrute", hp = 130, damage = 9, range = 4, cooldown = 1.4, speed = 8, splash = false, size = 1.35, coins = 2, suffix = " Brute" },
	Shaman = { look = "GoblinShaman", hp = 30, damage = 10, range = 20, cooldown = 2.0, speed = 9, splash = true, size = 1, coins = 2, suffix = " Shaman" },
}
-- The order the four archetypes of a family appear in (one per phase).
local ORDER = { "Grunt", "Archer", "Brute", "Shaman" }

-- The bosses: an archetype each. The boss's `look` decides its ability in the battle:
-- Brute = slam, Chief = summons, Archer = volley, Shaman = heals its wave.
local BOSS_ARCHETYPES = {
	Brute = { look = "GoblinBrute", hp = 300, damage = 12, range = 4, cooldown = 1.4, speed = 8, splash = false, size = 1.9, coins = 5 },
	Chief = { look = "GoblinChief", hp = 380, damage = 16, range = 5, cooldown = 1.2, speed = 9, splash = false, size = 1.7, coins = 6 },
	Archer = { look = "GoblinArcher", hp = 220, damage = 15, range = 32, cooldown = 1.1, speed = 9, splash = false, size = 1.6, coins = 5 },
	Shaman = { look = "GoblinShaman", hp = 240, damage = 14, range = 22, cooldown = 1.8, speed = 9, splash = true, size = 1.7, coins = 5 },
}

-- Builds the 20 mobs and 20 bosses of a roster. `families` rule 4 phases each (a bit stronger and bigger
-- than the previous one), `bosses` = { { name, archetype }, … } (20 entries). `power` scales the roster.
local function buildRoster(prefix: string, families: { Family }, bosses: { { string } }, power: number)
	for n = 1, Enemies.PhaseCount do
		local family = families[(n - 1) // 4 + 1]

		local archetype = ARCHETYPES[ORDER[(n - 1) % 4 + 1]]
		Enemies.Kinds[prefix .. "Mob" .. n] = {
			label = family.name .. archetype.suffix,
			look = archetype.look,
			color = family.color,
			hp = archetype.hp * family.power * power,
			damage = archetype.damage * family.power * power,
			range = archetype.range,
			cooldown = archetype.cooldown,
			speed = archetype.speed,
			splash = archetype.splash,
			size = archetype.size * family.size,
			coins = archetype.coins,
		}

		local name, bossType = bosses[n][1], bosses[n][2]
		local boss = BOSS_ARCHETYPES[bossType]
		Enemies.Kinds[prefix .. "Boss" .. n] = {
			label = name,
			look = boss.look,
			color = family.color:Lerp(Color3.new(0, 0, 0), 0.15),
			hp = boss.hp * family.power * power,
			damage = boss.damage * family.power * power,
			range = boss.range,
			cooldown = boss.cooldown,
			speed = boss.speed,
			splash = boss.splash,
			size = boss.size * family.size * (if n == Enemies.PhaseCount then 1.15 else 1),
			coins = boss.coins,
			boss = true,
		}
	end
end

-- ── Training Camp: goblins and their bigger cousins ──
buildRoster("", {
	{ name = "Goblin", color = C(110, 165, 70), power = 1.0, size = 1.0 },
	{ name = "Hobgoblin", color = C(165, 120, 65), power = 1.15, size = 1.1 },
	{ name = "Orc", color = C(95, 115, 90), power = 1.3, size = 1.2 },
	{ name = "Troll", color = C(120, 140, 165), power = 1.45, size = 1.3 },
	{ name = "Demon", color = C(190, 60, 60), power = 1.6, size = 1.4 },
}, {
	{ "Grubnak the Bully", "Brute" }, { "Goblin Chief", "Chief" }, { "Goblin King", "Chief" }, { "Shaman Elder", "Shaman" },
	{ "Hobgoblin Warlord", "Chief" }, { "Deadeye Hob", "Archer" }, { "Bonecrusher", "Brute" }, { "Hexmaster", "Shaman" },
	{ "Orc Chieftain", "Chief" }, { "Orc Sniper Lord", "Archer" }, { "Mountain Breaker", "Brute" }, { "Orc Warlock", "Shaman" },
	{ "Troll King", "Chief" }, { "Troll Stalker", "Archer" }, { "Colossus", "Brute" }, { "Troll Witch Doctor", "Shaman" },
	{ "Demon Lord", "Chief" }, { "Hellbow", "Archer" }, { "Infernal Titan", "Brute" }, { "The Demon Emperor", "Chief" },
}, 1)

-- Stats of a kind at an enemy level (each level makes it Balance.EnemyLevelScale times stronger).
function Enemies.stats(kind: string, level: number): Units.Stats
	local def = Enemies.Kinds[kind]
	local scale = Balance.EnemyLevelScale ^ (level - 1)
	return {
		hp = def.hp * scale * Balance.EnemyHpBoost,
		damage = def.damage * scale * Balance.EnemyDamageBoost,
		range = def.range,
		cooldown = def.cooldown,
		speed = def.speed,
		splash = def.splash,
	}
end

return Enemies
