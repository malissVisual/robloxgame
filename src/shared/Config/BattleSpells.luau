--!strict
-- THE FIGHT'S EXTRA ACTION (server/Services/BattleSpells.luau runs it):
--   REINFORCEMENTS  part of the wave arrives a few seconds into the fight (red circles, then they flash in), so a
--                   fight has a second beat instead of one clash
--   METEOR          YOUR spell: the round button at the bottom of the screen during a fight (or F). It falls on the
--                   biggest group of enemies; its damage grows with your squad (a part of the six mages' attack)
--   SIGNATURES      every element wizard (Fire, Ice, Storm, Nature, Shadow, Arcane: Config/Wizards.luau `evolution`)
--                   casts its own big spell every few seconds, with its name over its head
-- Damage numbers are multiples of the caster's attack damage (the mage's, or for the meteor the squad's sum).

local C = Color3.fromRGB

export type Signature = {
	label: string, -- shown over the mage as it casts
	color: Color3,
	color2: Color3,
	damage: number, -- × the mage's attack (per hit / per target)
	radius: number?, -- area spells
	hits: number?, -- Storm / Arcane: strikes, Shadow: targets
	burn: { dps: number, time: number }?, -- Fire: fraction of max HP per second
	freeze: number?, -- Ice: seconds frozen (bosses a third)
	root: { factor: number, time: number }?, -- Nature: slow of the enemies in the area
	heal: number?, -- Nature: fraction of max HP for every ally in HealRadius
	execute: number?, -- Shadow: a non-boss target under this fraction of HP after the hit dies
}

local BattleSpells = {
	Reinforcements = {
		MinWave = 2, -- not on wave 1 and never on a boss wave (the boss is the event)
		SkipTwists = { "ambush", "swarm" }, -- those waves have their own extra enemies
		At = 6, -- battle seconds, or ...
		HalfDead = 0.4, -- ... when this part of the starting wave is dead (whichever first)
		Fraction = 0.35, -- this part of the starting wave comes again (rounded) ...
		Min = 1, -- ... at least
		Max = 4, -- ... at most
		Warning = 1.5, -- seconds of red circles before they flash in
		Radius = 4,
		Points = { Vector3.new(-22, 0, 38), Vector3.new(22, 0, 38), Vector3.new(0, 0, 46) }, -- from the arena center (+z = the enemies' side)
		Color = C(255, 90, 60),
	},

	Meteor = {
		Key = Enum.KeyCode.F,
		Cooldown = 15, -- battle seconds
		FirstDelay = 3, -- ready this long after the fight starts
		Damage = 1.2, -- × the sum of the living mages' attack, to every enemy inside
		BossDamage = 0.6, -- a boss takes this part of it
		Radius = 9,
		Fall = 0.7, -- seconds from the warning to the impact
		Stun = 0.5,
		Color = C(255, 120, 40),
		Color2 = C(255, 220, 140),
	},

	-- Signature spells: the first one this long after the fight starts (+ a little random), then every Cooldown
	-- (from CooldownLow at level 1 to CooldownTop at level 16), only with an enemy within the mage's range + Reach.
	SignatureFirst = 3,
	SignatureCooldownLow = 12,
	SignatureCooldownTop = 8,
	SignatureReach = 6,
	HealRadius = 30,

	Signatures = {
		Fire = { label = "INFERNO", color = C(255, 110, 40), color2 = C(255, 210, 120), damage = 1.2, radius = 7, burn = { dps = 0.03, time = 3 } },
		Ice = { label = "FROST NOVA", color = C(110, 210, 255), color2 = C(230, 248, 255), damage = 0.8, radius = 7, freeze = 1.6 },
		Storm = { label = "THUNDERSTORM", color = C(255, 225, 77), color2 = C(200, 210, 255), damage = 0.7, hits = 4, radius = 3 },
		Nature = { label = "WILD GROVE", color = C(110, 220, 110), color2 = C(210, 255, 170), damage = 0.6, radius = 7, root = { factor = 0.25, time = 2.5 }, heal = 0.12 },
		Shadow = { label = "SHADOW CLAW", color = C(150, 90, 255), color2 = C(215, 185, 255), damage = 1.0, hits = 3, execute = 0.15 },
		Arcane = { label = "ARCANE BARRAGE", color = C(255, 120, 225), color2 = C(255, 215, 245), damage = 0.4, hits = 6 },
	} :: { [string]: Signature },
}

-- The cooldown of a level's signature spell.
function BattleSpells.signatureCooldown(level: number): number
	local f = math.clamp((level - 1) / 15, 0, 1)
	return BattleSpells.SignatureCooldownLow + (BattleSpells.SignatureCooldownTop - BattleSpells.SignatureCooldownLow) * f
end

return BattleSpells
