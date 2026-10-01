--!strict
-- Grubnak — The Rift King: the final boss of the Training Camp (wave 100). Every number of the fight is here:
-- health, damage, ranges, cooldowns and the warning (dodge) windows of its four attacks. The fight itself is
-- server/Services/RiftKing.luau, the model is in shared/Enemy.luau (look "RiftKing").
--
-- Damage to YOUR SOLDIERS is a multiple of the boss's attack damage (Enemies.stats, scaled by the wave);
-- damage to YOUR CHARACTER (you stand in the arena and dodge) is in plain health points (a player has 100).
-- Every attack goes: ground warning → dodge window → impact. The warnings never hurt; the impact hits exactly
-- the marked area once.

local RiftKing = {
	Name = "Grubnak — The Rift King",

	-- The boss as an enemy kind (Enemies.luau builds Boss20 from these; the wave scaling applies on top).
	Hp = 560,
	Damage = 18,
	Range = 8, -- its hammer reaches this far in a normal hit
	Cooldown = 1.6,
	Speed = 7,
	Size = 1.1, -- about twice a player's height after the wave scaling (x the Demon family, the last phase and the level)
	Coins = 12,

	-- Between two special attacks (battle seconds). The first one comes FirstAttackAfter seconds into the fight.
	AttackCooldown = 5.0,
	FirstAttackAfter = 2.5,
	-- Enraged below this fraction of health: cooldowns shrink by this factor and attacks come in combinations.
	EnrageAt = 0.3,
	EnrageCooldownFactor = 0.6,
	-- A single hit of at least this fraction of max health staggers the boss (a flash and a step back).
	StaggerFraction = 0.06,
	StaggerTime = 0.5,
	-- The boss health bar (client) is refreshed at most this often (seconds).
	HpBarInterval = 0.15,

	-- 1. CRYSTAL VOLLEY: three crystals fly along arcs onto locked spots marked with red circles.
	Volley = {
		Count = 3,
		Radius = 5, -- of every circle (studs)
		WarningTime = 1.3, -- the circles show this long before the crystals land (>= 1.2 asked)
		ArcHeight = 14, -- how high the crystals fly
		Damage = 1.4, -- x the boss's damage, to every soldier inside a circle
		PlayerDamage = 35, -- health points to a player inside a circle
		Busy = 1.6, -- the boss stands and casts this long
	},

	-- 2. HAMMER SLAM: an orange cone in front of the boss, locked when it appears; the hammer comes down after it.
	Slam = {
		Range = 16,
		HalfAngle = 35, -- degrees to each side of the locked direction
		WarningTime = 1.0,
		Damage = 2.2,
		PlayerDamage = 50,
		Stun = 0.8, -- soldiers hit cannot act this long
		Busy = 1.5,
	},

	-- 3. RIFT SHOCKWAVE: after the wind-up a purple ring runs outward; only the moving ring hurts, jump over it.
	Shockwave = {
		WindUp = 0.9,
		Speed = 14, -- studs per second
		MaxRadius = 24,
		Thickness = 2.4, -- the width of the ring on the floor (= the band that hurts)
		Damage = 1.2,
		PlayerDamage = 30,
		JumpHeight = 2.2, -- a player this high above the floor (or mid-jump) is over the ring
	},

	-- 4. METEOR RAIN: red circles mark where purple crystal meteors land; gaps stay between them.
	Meteors = {
		Count = 4,
		EnragedCount = 6,
		Radius = 4.5,
		Gap = 4, -- at least this much floor between two circles (a safe path)
		WarningTime = 1.5,
		FallTime = 0.5, -- the meteor is visible falling this long before the impact (inside the warning time)
		Damage = 1.6,
		PlayerDamage = 40,
		Busy = 2.0,
	},
}

return RiftKing
