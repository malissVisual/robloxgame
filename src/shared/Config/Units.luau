--!strict
-- Soldier classes and their growth by level (tier).
-- Merging two of the same (class + level) creates level + 1 (see Levels.luau).
--
-- Everyone starts with two classes (Knight and Archer). The others are locked: clearing the
-- wave in `unlock.wave` in Arena 1 (Training Camp) unlocks the class and drops one of them.

export type Stats = {
	hp: number,
	damage: number,
	range: number,
	cooldown: number,
	speed: number,
	splash: boolean,
}

export type Unlock = {
	wave: number, -- the first wave whose lucky drop can unlock the class
	weight: number?, -- relative chance inside the lucky drop (default 1; small = rare)
	legendary: boolean?, -- shown as LEGENDARY
}

export type ClassDef = Stats & {
	label: string,
	color: Color3,
	unlock: Unlock?, -- nil = unlocked from the start
	passive: string, -- the class's own trick in the battle (see Units.Passives)
	maxTier: number?, -- the class's own highest merge level (default Units.MaxTier); Knight, Archer and Mage have 30 looks
}

-- Every class has a PASSIVE (BattleService applies it). `value` is its strength; an ASCENDED soldier
-- (two level 9 merged) has it doubled.
--   block    a hit is negated with this chance
--   volley   every 3rd shot deals this many times the damage
--   crit     a hit deals double damage with this chance
--   splash   hits splash to the enemies around the target (the fraction of the damage)
--   taunt    enemies within `value` studs attack this soldier first
--   rage     up to +value damage as its HP drops (full bonus at 0 HP)
--   inspire  your soldiers within 10 studs deal +value damage
export type Passive = { label: string, text: string, value: number }
local Units = {}

Units.MaxTier = 9
Units.AscendedBonus = 0.5 -- an Ascended soldier (two level 9 merged) has +50% HP and damage and a doubled passive
Units.TierScale = 1.8 -- how many times stronger level + 1 is than level

Units.ClassList = { "Knight", "Archer", "Hunter", "Mage", "Tank", "Berserker", "Soldier" }

Units.Classes = {
	Soldier = {
		label = "Soldier",
		color = Color3.fromRGB(90, 140, 220),
		hp = 100,
		damage = 10,
		range = 4,
		cooldown = 1.0,
		speed = 12,
		splash = false,
		-- LEGENDARY: the 9-stage designed soldier is a rare lucky drop (it is only a fraction of the draw).
		unlock = { wave = 15, weight = 0.25, legendary = true },
		passive = "inspire",
	},
	Archer = {
		label = "Archer",
		color = Color3.fromRGB(90, 190, 110),
		hp = 60,
		damage = 14,
		range = 30,
		cooldown = 1.1,
		speed = 10,
		splash = false,
		passive = "volley",
		-- 30 merge levels: the R15 evolution of the archer woman, prehistory to the year 3000 (design/ArcherEvolution,
		-- built from StageModels/ArcherEvolution by SoldierRig).
		maxTier = 30,
	},
	-- The three new classes of Arena 1 (Training Camp):
	Hunter = {
		label = "Hunter",
		color = Color3.fromRGB(70, 200, 200),
		hp = 40,
		damage = 34,
		range = 45,
		cooldown = 2.2,
		speed = 8,
		splash = false,
		unlock = { wave = 3 },
		passive = "crit",
	},
	Mage = {
		label = "Mage",
		color = Color3.fromRGB(180, 100, 210),
		hp = 50,
		damage = 20,
		range = 22,
		cooldown = 1.6,
		speed = 9,
		splash = true,
		unlock = { wave = 6 },
		passive = "splash",
		-- 30 merge levels: the R15 evolution of the mage, a shaman's apprentice to the Apex mage of the year 3000
		-- (design/MageEvolution, built from StageModels/MageEvolution by SoldierRig).
		maxTier = 30,
	},
	Tank = {
		label = "Tank",
		color = Color3.fromRGB(200, 165, 70),
		hp = 220,
		damage = 7,
		range = 4,
		cooldown = 1.0,
		speed = 9,
		splash = false,
		unlock = { wave = 10 },
		passive = "taunt",
	},
	-- Reserved for the wave system (later waves):
	Berserker = {
		label = "Berserker",
		color = Color3.fromRGB(235, 130, 50),
		hp = 90,
		damage = 24,
		range = 4,
		cooldown = 0.8,
		speed = 15,
		splash = false,
		unlock = { wave = 15 },
		passive = "rage",
	},
	Knight = {
		label = "Knight",
		color = Color3.fromRGB(150, 160, 190),
		hp = 170,
		damage = 15,
		range = 4,
		cooldown = 1.1,
		speed = 10,
		splash = false,
		passive = "block",
		-- 30 merge levels: the R15 evolution from the first human to the year 3000 (design/KnightEvolution,
		-- built from StageModels/KnightEvolution by SoldierRig).
		maxTier = 30,
	},
} :: { [string]: ClassDef }

-- The highest merge level of a class (Units.MaxTier unless the class says otherwise).
function Units.maxTier(class: string?): number
	local def = if class then Units.Classes[class] else nil
	return if def and def.maxTier then def.maxTier else Units.MaxTier
end

Units.Passives = {
	block = { label = "Shield Wall", text = "%d%% chance to block a hit", value = 0.2 },
	volley = { label = "Power Shot", text = "every 3rd shot deals x%d damage", value = 2 },
	crit = { label = "Deadeye", text = "%d%% chance of a double-damage hit", value = 0.25 },
	splash = { label = "Arcane Burst", text = "hits splash %d%% to nearby enemies", value = 0.5 },
	taunt = { label = "Bulwark", text = "enemies within %d studs attack it first", value = 14 },
	rage = { label = "Bloodlust", text = "up to +%d%% damage as HP drops", value = 0.8 },
	inspire = { label = "Banner", text = "your characters nearby deal +%d%% damage", value = 0.1 },
} :: { [string]: Passive }

-- The text of a class's passive, with its number filled in (doubled for an Ascended soldier).
function Units.passiveText(class: string, ascended: boolean?): string
	local passive = Units.Passives[Units.Classes[class].passive]
	local value = passive.value * (if ascended then 2 else 1)
	local shown = if value < 1 then value * 100 else value
	return string.format("%s: " .. passive.text, passive.label, math.floor(shown + 0.5))
end

function Units.isValidClass(class: any): boolean
	return type(class) == "string" and Units.Classes[class] ~= nil
end

-- Classes that need to be unlocked (in ClassList order).
function Units.lockedClasses(): { string }
	local out = {}
	for _, class in Units.ClassList do
		if Units.Classes[class].unlock then
			table.insert(out, class)
		end
	end
	return out
end

-- `ascended` = two level 9 soldiers merged into one: Units.AscendedBonus more HP and damage.
function Units.stats(class: string, tier: number, ascended: boolean?): Stats
	local base = Units.Classes[class]
	local scale = Units.TierScale ^ (tier - 1) * (if ascended then 1 + Units.AscendedBonus else 1)
	return {
		hp = base.hp * scale,
		damage = base.damage * scale,
		range = base.range,
		cooldown = base.cooldown,
		speed = base.speed,
		splash = base.splash,
	}
end

return Units
