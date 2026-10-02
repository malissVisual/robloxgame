--!strict
-- Soldier classes and their growth by level (tier).
-- Merging two of the same (class + level) creates level + 1 (see Levels.luau).
--
-- There is ONE class now: the Mage (30 merge levels, the R15 evolution). The other classes (Knight, Archer, Hunter,
-- Tank, Berserker, Soldier) were removed; a saved soldier of a removed class loads as a Mage of the same level
-- (PlayerData). The unlock machinery (`unlock`) stays for a future class.

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
	maxTier: number?, -- the class's own highest merge level (default Units.MaxTier); the Mage has 16 (of 30 looks)
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

Units.ClassList = { "Mage" }

Units.Classes = {
	Mage = {
		label = "Mage",
		color = Color3.fromRGB(180, 100, 210),
		hp = 50,
		damage = 20,
		range = 22,
		cooldown = 1.6,
		speed = 9,
		splash = true,
		passive = "splash",
		-- 16 merge levels (the top: two level 16 merged = ASCENDED). The looks are the first 16 of the mage's 30-level
		-- R15 evolution (design/MageEvolution, StageModels/MageEvolution, SoldierRig), prehistory to the industrial
		-- age; the data for 17 … 30 stays for later. The Mage casts all the spells of the game itself
		-- (Config/MageSpells.luau, MageBrain); you only walk around with your character.
		maxTier = 16,
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
