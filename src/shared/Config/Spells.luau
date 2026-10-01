--!strict
-- The player's spells. You carry TWO of them into a battle (one on Q, one on E, chosen in the SPELLS tab of
-- the left panel) and cast them yourself. You start with Meteor and Heal; every other spell is found only by
-- grinding: after a won wave of `dropWave` or higher there is a chance that the spell drops (and stays yours).
--
--   aimed    the spell hits an area: it aims itself (auto aim), or with the mouse while SHIFT is held
--   global   the spell hits every enemy and needs no aim
--
-- Numbers that are fractions ("damage", "heal") are parts of the target's max HP; the bosses take only
-- Balance.SpellBossFactor of a damage spell. All timers are in seconds.

export type Def = {
	label: string,
	hint: string, -- a short line for the button
	description: string, -- for the SPELLS tab
	color: Color3,
	cooldown: number,
	aimed: boolean,
	dropWave: number?, -- from this wave on the spell can drop (nil = you own it from the start)
	radius: number?,
	damage: number?, -- fraction of max HP of every enemy hit
	heal: number?, -- fraction of max HP healed
	slow: number?, -- enemies act at this speed (0.5 = half) ...
	slowTime: number?, -- ... for this long
	shieldTime: number?, -- allies take much less damage for this long ...
	reduction: number?, -- ... this much less (0.85 = 85% less)
	strikes: number?, -- number of meteors
}

local Spells = {}

-- The spells in the order the SPELLS tab lists them.
Spells.Order = { "meteor", "heal", "smite", "frost", "shield", "armageddon" }

-- What you carry at the start (and after a reset).
Spells.Start = { q = "meteor", e = "heal" }

Spells.Defs = {
	meteor = {
		label = "Meteor",
		hint = "12% damage · area",
		description = "A fireball hits the enemies around the target.",
		color = Color3.fromRGB(255, 140, 70),
		cooldown = 7,
		aimed = true,
		radius = 9,
		damage = 0.12,
	},
	heal = {
		label = "Heal",
		hint = "+35% HP · area",
		description = "Heals your soldiers around the target.",
		color = Color3.fromRGB(110, 230, 140),
		cooldown = 18,
		aimed = true,
		radius = 10,
		heal = 0.35,
	},
	smite = {
		label = "Smite",
		hint = "20% damage · all",
		description = "Lightning strikes every enemy.",
		color = Color3.fromRGB(150, 200, 255),
		cooldown = 30,
		aimed = false,
		dropWave = 25,
		damage = 0.20,
	},
	frost = {
		label = "Frost Nova",
		hint = "6% damage · slows",
		description = "Ice around the target: damage, and the enemies there act at half speed for 4 s.",
		color = Color3.fromRGB(150, 215, 255),
		cooldown = 14,
		aimed = true,
		dropWave = 50,
		radius = 10,
		damage = 0.06,
		slow = 0.5,
		slowTime = 4,
	},
	shield = {
		label = "Divine Shield",
		hint = "-85% damage taken",
		description = "Your soldiers around the target take 85% less damage for 4 s.",
		color = Color3.fromRGB(255, 215, 110),
		cooldown = 24,
		aimed = true,
		dropWave = 75,
		radius = 10,
		shieldTime = 4,
		reduction = 0.85,
	},
	armageddon = {
		label = "Armageddon",
		hint = "6 meteors · all",
		description = "Six meteors rain on random enemies, one after another.",
		color = Color3.fromRGB(255, 90, 60),
		cooldown = 45,
		aimed = false,
		dropWave = 100,
		radius = 7,
		damage = 0.10,
		strikes = 6,
	},
} :: { [string]: Def }

function Spells.isValid(id: any): boolean
	return type(id) == "string" and Spells.Defs[id] ~= nil
end

return Spells
