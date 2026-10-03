--!strict
-- THE FIGHT'S EXTRA ACTION (server/Services/BattleSpells.luau runs it, the client draws the buttons and the feel):
--   PLAYER SPELLS   YOUR four spells, the round buttons at the bottom of the screen during a fight (keys 1-4, F =
--                   meteor): press, then click where it should land (press again = it aims itself). Their damage
--                   grows with your squad ("power" = the sum of the living mages' attack)
--   REINFORCEMENTS  part of the wave arrives a few seconds into the fight
--   SIGNATURES      every element wizard (Fire, Ice, Storm, Nature, Shadow, Arcane) casts its own big spell
--   AFFIXES         some enemies come with a trait you can see over their heads (shielded, explosive, swift,
--                   splitter, giant) and pay more coins
--   FEEL            critical hits, the kill COMBO (more coins), camera shakes, the boss's slow-motion death
--   BOSS CHEST      a won boss wave pays a chest: coins and extra wizards (GameService)

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

export type PlayerSpell = {
	id: string,
	label: string,
	key: Enum.KeyCode,
	alt: Enum.KeyCode?,
	aim: boolean, -- false: it needs no target (heal)
	cooldown: number, -- battle seconds
	first: number, -- ready this long after the fight starts
	radius: number, -- the aiming ring (and the area)
	color: Color3,
	color2: Color3,
	damage: number?, -- × power
	bossDamage: number?, -- a boss takes this part of it
	stun: number?,
	fall: number?, -- meteor: seconds from the cast to the impact
	freeze: number?, -- frost: seconds frozen ...
	bossFreeze: number?, -- ... a boss
	jumps: number?, -- lightning: extra enemies the bolt jumps to ...
	jumpRadius: number?, -- ... within this many studs of the last one
	heal: number?, -- heal: fraction of every mage's max HP
	shield: number?, -- heal: damage reduction ...
	shieldTime: number?, -- ... for this long
	shake: number, -- the camera shake at the impact (0 = none)
}

export type Affix = {
	id: string,
	label: string,
	color: Color3,
	minWave: number,
	shield: number?, -- shielded: a bubble of this part of max HP
	haste: number?, -- swift
	delay: number?, -- explosive: seconds between the death and the blast ...
	radius: number?, -- ... its radius ...
	damage: number?, -- ... × its attack to every mage inside (giant: × its attack)
	parts: number?, -- splitter: copies at death ...
	hp: number?, -- ... with this part of its max HP (giant: × max HP)
	scale: number?, -- giant: model size
}

local BattleSpells = {
	PlayerSpells = {
		meteor = {
			id = "meteor", label = "METEOR", key = Enum.KeyCode.One, alt = Enum.KeyCode.F, aim = true,
			cooldown = 15, first = 3, radius = 9, damage = 1.0, bossDamage = 0.6, stun = 0.5, fall = 0.7, shake = 0.9,
			color = C(255, 120, 40), color2 = C(255, 220, 140),
		},
		frost = {
			id = "frost", label = "BLIZZARD", key = Enum.KeyCode.Two, aim = true,
			cooldown = 20, first = 5, radius = 10, damage = 0.3, bossDamage = 1, freeze = 2.5, bossFreeze = 0.8, shake = 0.35,
			color = C(110, 210, 255), color2 = C(235, 250, 255),
		},
		lightning = {
			id = "lightning", label = "LIGHTNING", key = Enum.KeyCode.Three, aim = true,
			cooldown = 10, first = 2, radius = 6, damage = 0.4, bossDamage = 0.7, stun = 0.3, jumps = 4, jumpRadius = 14, shake = 0.4,
			color = C(255, 230, 90), color2 = C(210, 220, 255),
		},
		heal = {
			id = "heal", label = "HEAL", key = Enum.KeyCode.Four, aim = false,
			cooldown = 25, first = 8, radius = 0, heal = 0.35, shield = 0.4, shieldTime = 3, shake = 0,
			color = C(110, 235, 140), color2 = C(220, 255, 225),
		},
	} :: { [string]: PlayerSpell },
	PlayerSpellOrder = { "meteor", "frost", "lightning", "heal" },
	AimSlack = 8, -- an aimed point this far outside the arena's circle still counts (farther: the spell aims itself)

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

	-- ENEMY AFFIXES: from FromWave on, every starting enemy (not a boss, not a twist extra) has Chance (+ ChancePerWave
	-- per wave, at most ChanceMax) to get one affix (one whose minWave is reached); it shows over its head and its
	-- kill pays Coins more.
	Affixes = {
		FromWave = 4,
		Chance = 0.15,
		ChancePerWave = 0.01,
		ChanceMax = 0.4,
		Coins = 0.5,
		Order = { "shielded", "swift", "explosive", "splitter", "giant" },
		Defs = {
			shielded = { id = "shielded", label = "SHIELDED", color = C(120, 230, 255), minWave = 4, shield = 0.6 },
			swift = { id = "swift", label = "SWIFT", color = C(240, 245, 255), minWave = 4, haste = 1.6 },
			explosive = { id = "explosive", label = "EXPLOSIVE", color = C(255, 140, 40), minWave = 6, delay = 0.8, radius = 6, damage = 2 },
			splitter = { id = "splitter", label = "SPLITTER", color = C(150, 255, 120), minWave = 8, parts = 2, hp = 0.35 },
			giant = { id = "giant", label = "GIANT", color = C(255, 90, 90), minWave = 10, hp = 2.5, damage = 1.3, scale = 1.35 },
		} :: { [string]: Affix },
	},

	-- FEEL
	Crit = { Chance = 0.12, Mult = 2, Color = C(255, 215, 70) }, -- a mage's hit (its basic attack or a spell)
	Combo = { Window = 1.6, CoinStep = 0.1, CoinMax = 1.0, Show = 2 }, -- kills within Window seconds chain; kill n of a combo pays CoinStep × (n - 1) more coins (at most CoinMax); the counter shows from Show
	BossSlowmo = { Speed = 0.25, Time = 1.3 }, -- a boss's death: the fight runs at Speed for Time real seconds
	BossShake = 1.4,
	ExplosionShake = 0.5,

	-- BOSS CHEST (GameService): a won boss wave pays Drops extra wizards (the first EpicDrops of them Epic or better)
	-- and CoinKills × the coins of one kill of that wave.
	BossChest = { Drops = 2, EpicDrops = 1, CoinKills = 12 },
}

-- The cooldown of a level's signature spell.
function BattleSpells.signatureCooldown(level: number): number
	local f = math.clamp((level - 1) / 15, 0, 1)
	return BattleSpells.SignatureCooldownLow + (BattleSpells.SignatureCooldownTop - BattleSpells.SignatureCooldownLow) * f
end

-- The chance of an enemy of `wave` to have an affix (0 before FromWave).
function BattleSpells.affixChance(wave: number): number
	local A = BattleSpells.Affixes
	if wave < A.FromWave then
		return 0
	end
	return math.min(A.ChanceMax, A.Chance + A.ChancePerWave * (wave - A.FromWave))
end

return BattleSpells
