--!strict
-- The Mage's merge-level TREE: what every merge level (1 … 16) adds. Odd levels from 3 add an ATTACK (a spell of
-- Config/MageSpells.luau, its minLevel matches this table), even levels add a PASSIVE (applied in BattleService
-- and MageBrain). Everything stacks: a level 16 mage has every attack and every passive. The card of a mage lists
-- what it has and what the next level brings. All numbers of the passives live in `Passives` below.

local MageTree = {}

export type Entry = { level: number, kind: string, id: string, label: string, text: string } -- kind "attack" | "passive"

MageTree.Levels = {
	{ level = 1, kind = "attack", id = "fireStone", label = "Fire Stone", text = "the basic bolt" },
	{ level = 2, kind = "passive", id = "smolder", label = "Smolder", text = "every hit sets the target on fire: 2% max HP/s for 3 s" },
	{ level = 3, kind = "attack", id = "sparkSwarm", label = "Spark Swarm", text = "the first strong attack: an area burst into a group" },
	{ level = 4, kind = "passive", id = "focus", label = "Focus", text = "every 4th hit deals double damage" },
	{ level = 5, kind = "attack", id = "arcanePush", label = "Arcane Push", text = "melee that gets close is knocked back and stunned" },
	{ level = 6, kind = "passive", id = "healAura", label = "Healing Aura", text = "allies within 12 studs heal 1% HP every second" },
	{ level = 7, kind = "attack", id = "sunRay", label = "Sun Ray", text = "a new basic bolt that pierces into a second enemy" },
	{ level = 8, kind = "passive", id = "bloodMana", label = "Blood Mana", text = "a kill gives 25 mana and shortens every cooldown by 1 s" },
	{ level = 9, kind = "attack", id = "sandstorm", label = "Sandstorm", text = "area damage that slows" },
	{ level = 10, kind = "passive", id = "mirror", label = "Mirror", text = "20% chance to reflect a ranged hit back at the shooter" },
	{ level = 11, kind = "attack", id = "chainLightning", label = "Chain Lightning", text = "jumps over 3 enemies; the basic bolt becomes the Magic Missile" },
	{ level = 12, kind = "passive", id = "emergencyBarrier", label = "Emergency Barrier", text = "under 50% HP a barrier takes half the damage for 3 s (once per battle)" },
	{ level = 13, kind = "attack", id = "electricArc", label = "Electric Arc", text = "a chain over 4 enemies" },
	{ level = 14, kind = "passive", id = "overload", label = "Overload", text = "after 5 hits in a row the next bolt explodes into an area" },
	{ level = 15, kind = "attack", id = "steamBlast", label = "Steam Blast + Shockwave", text = "a strong area blast and a knockback around the mage" },
	{ level = 16, kind = "passive", id = "archmage", label = "Archmage", text = "-25% cooldowns and +20% damage (Ascended: doubled)" },
} :: { Entry }

-- The numbers of the passives (BattleService applies most of them, MageBrain Blood Mana and the Archmage's cooldowns).
MageTree.Passives = {
	smolder = { Dps = 0.02, Time = 3 }, -- × max HP per second, seconds
	focus = { Every = 4, Mult = 2 },
	healAura = { Radius = 12, Rate = 0.01 }, -- × max HP per second
	bloodMana = { Mana = 25, Cooldown = 1 },
	mirror = { Chance = 0.2, MinRange = 10 }, -- the attacker's range counts as "ranged" from here
	emergencyBarrier = { Below = 0.5, Reduction = 0.5, Time = 3 },
	overload = { Hits = 5, Radius = 6, Fraction = 1.0 }, -- the explosion deals this × the bolt's damage to everybody around the target
	archmage = { Cooldown = 0.25, Damage = 0.2 },
}

MageTree.MaxLevel = #MageTree.Levels

-- The passive `id` is unlocked at `level`.
function MageTree.has(level: number, id: string): boolean
	for _, entry in MageTree.Levels do
		if entry.id == id then
			return entry.level <= level
		end
	end
	return false
end

-- Everything a mage of `level` has, in level order.
function MageTree.unlocked(level: number): { Entry }
	local out: { Entry } = {}
	for _, entry in MageTree.Levels do
		if entry.level <= level then
			table.insert(out, entry)
		end
	end
	return out
end

-- What the next level brings (nil at the top).
function MageTree.nextEntry(level: number): Entry?
	for _, entry in MageTree.Levels do
		if entry.level > level then
			return entry
		end
	end
	return nil
end

return MageTree
