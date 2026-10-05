--!strict
-- Numbers of the enemy brains (server/Services/EnemyBrain.luau): one small brain per goblin, with a personality
-- per archetype. Every area attack is telegraphed on the floor for at least 0.6 s; every voluntary move is short,
-- committed and followed by standing (no pacing).
--
--   GRUNT   pack hunter: WAR CRY (speed for the pack), FLANK (wraps around the target), GANG UP (+damage per grunt nearby)
--   ARCHER  cowardly skirmisher: shoots the soldier with the lowest HP, SCURRIES away from melee once per 6 s, FOCUS FIRE
--   BRUTE   charger / the wall: telegraphed CHARGE down an orange lane, GUARD (taunt) near its casters, ENRAGE under 30 %
--   SHAMAN  support caster that stays behind: MEND / FRENZY / HEX with an interruptible wind-up
--   BOSSES  SLAM (Brute), VOLLEY (Archer), HEAL (Shaman), SUMMON + RALLY HORN + DESPERATE CALL (Chief); PHASE 2 at 50 %
-- All times are battle seconds (the battle speed stretches them). The boss cadences and radii come from Balance
-- (Balance.BossSlamEvery …) so they stay tuned in one place.

local Balance = require(script.Parent.Balance)

local EnemyAI = {
	Decide = 0.25, -- seconds between two decisions of a brain (movement runs every tick)
	AbilityGrace = 2.0, -- no special ability in the first seconds of a fight

	Grunt = {
		CrySight = 18, -- a soldier this close starts the WAR CRY
		CryTime = 0.6, -- the grunt stands and roars this long
		CryHaste = 1.2, -- speed and attack rate of the pack ...
		CryBuffTime = 3, -- ... for this long
		CryRadius = 10, -- grunts this close to the crier are hasted
		CryCooldown = 12, -- per grunt
		PackGap = 8, -- seconds between two war cries of the whole wave
		FlankOffset = 3, -- every second grunt aims this far beside a shared target
		GangPer = 0.1, -- +damage per other living grunt within GangRadius ...
		GangMax = 0.3, -- ... up to this
		GangRadius = 6,
		GangFromWave = 3, -- GANG UP starts on this wave (the first waves stay gentle) and after AbilityGrace
	},

	Archer = {
		Retarget = 2.5, -- seconds a target is kept before the lowest-HP soldier is chosen again
		ScurryAt = 8, -- a melee soldier this close → SCURRY
		ScurryDistance = 8, -- studs straight away ...
		ScurryTime = 0.9, -- ... over this long
		ScurryCooldown = 6, -- HARD LIMIT: one scurry per archer per this many seconds (a cornered archer dies)
		FocusEvery = 7, -- FOCUS FIRE: all archers shoot the same soldier every N seconds ...
		FocusFirst = 4, -- ... first at this time
		FocusTime = 3, -- ... and keep it this long
		FocusTelegraph = 0.3, -- red beams this long before the volley lands together
		FocusMinArchers = 2,
	},

	Brute = {
		ChargeMin = 7, -- CHARGE when the target is between ChargeMin and ChargeRange studs away
		ChargeRange = 14, -- (also the longest lane)
		FirstCharge = 2.5, -- the first charge is possible this many seconds into the fight
		Cooldown = 7, -- per brute
		WindUp = 0.8, -- the orange lane shows this long before the brute runs
		Speed = 40, -- studs per second along the lane (× slowFactor while slowed: the Mage's trip)
		Width = 4, -- lane width
		LaneStep = 4, -- a data hazard circle every N studs of the lane
		HitRadius = 3, -- soldiers this close to the stop point are hit
		Damage = 1.6, -- × the brute's damage
		Knockback = 3, -- studs the hit soldiers are pushed
		Stun = 0.4, -- seconds the hit soldiers cannot act
		Dizzy = 0.8, -- a charge that hit nobody: the brute stands stunned this long (a spinning star)
		CancelDrift = 1, -- pushed this far off the locked lane (the Mage's repel, a pull) → the charge is cancelled, no snap back
		CancelLate = 0.25, -- stunned past the wind-up's end by this much (the lane's hazards are gone) → cancelled
		EnrageAt = 0.3, -- under this HP fraction, once: faster for the rest of the fight
		EnrageHaste = 1.25,
		GuardRadius = 6, -- an allied Archer / Shaman this close → the brute is the wall ...
		GuardTaunt = 8, -- ... melee soldiers within this many studs attack it first
		PlayerDamage = 20, -- HP a player standing in the lane's end circle loses
	},

	Shaman = {
		Hold = 18, -- advances only while the nearest soldier is farther than this (and NEVER retreats)
		LateAdvanceAt = 40, -- after this battle time the hold shrinks to LateHold (a lone shaman cannot run the clock)
		LateHold = 10,
		CastEvery = 6,
		FirstCast = 2,
		WindUp = 0.6, -- interruptible
		Mend = 0.15, -- MEND heals this fraction of the ally's max HP ...
		MendBelow = 0.6, -- ... when an ally is under this fraction ...
		MendRange = 20, -- ... within this range
		Frenzy = { Damage = 0.35, Haste = 1.15, Time = 4, Range = 14 }, -- a Grunt / Brute that is fighting
		Hex = { Factor = 0.7, Time = 3, Range = 20 }, -- the soldier with the highest damage deals less
		InterruptFraction = 0.15, -- a hit of this fraction of max HP during the wind-up cancels the cast
		FizzleCooldown = 3, -- the next cast comes this soon after a fizzle
	},

	Boss = {
		FirstAbilityAt = 4, -- the first special of a boss
		-- From Balance: the cadence (× the brain's cooldownFactor), the slam's radius / damage / stun, the volley's
		-- damage, the heal's fraction, the Chief's summon threshold and count.
		SlamEvery = Balance.BossSlamEvery,
		SlamRadius = Balance.BossSlamRadius,
		SlamDamage = Balance.BossSlamDamage,
		SlamStun = Balance.BossSlamStun,
		VolleyEvery = Balance.BossVolleyEvery,
		VolleyDamage = Balance.BossVolleyDamage,
		HealEvery = Balance.BossHealEvery,
		HealFraction = Balance.BossHealFraction,
		SummonAt = Balance.BossSummonAt,
		SummonCount = Balance.BossSummonCount,
		SlamWindUp = 0.9, -- Brute boss: orange circle (Balance.BossSlamRadius) this long before the slam
		SlamPlayerDamage = 25, -- HP a player standing inside loses
		SlamDrift = 2, -- the boss pushed this far off its telegraph during the wind-up → the slam is cancelled
		VolleyWindUp = 0.7, -- Archer boss: red beams this long before the arrows
		HealWindUp = 0.6, -- Shaman boss: green ring this long before the heal
		HealRadius = 12, -- ... and only the enemies inside that ring are healed (the telegraph shows the area)
		HealInterruptFactor = 0.5, -- a counter-spell during the wind-up halves the heal
		SummonWarn = 0.8, -- Chief: purple circles this long before the summoned mobs appear
		RallyEvery = 10, -- Chief: RALLY HORN cadence ...
		RallyWindUp = 0.5,
		RallyRadius = 16,
		RallyBonus = 0.25, -- ... +damage and haste (1 + RallyBonus) for the enemies inside ...
		RallyTime = 4,
		DesperateAt = 0.25, -- Chief: under this HP fraction it calls DesperateCount more mobs (once)
		DesperateCount = 2,
		EnrageAt = 0.5, -- PHASE 2 (every boss, once): a roar, faster abilities, a bit bigger
		RoarTime = 0.8,
		EnrageCooldownFactor = 0.75,
		EnrageScale = 1.05,
		GuardStay = 8, -- bodyguards stay this close to their boss ...
		GuardBreak = 12, -- ... until a soldier is this close (or the boss is under half HP)
	},

	Colors = {
		warning = Color3.fromRGB(255, 70, 50),
		charge = Color3.fromRGB(255, 140, 40),
		mend = Color3.fromRGB(120, 255, 140),
		frenzy = Color3.fromRGB(255, 120, 60),
		hex = Color3.fromRGB(190, 110, 255),
		cry = Color3.fromRGB(255, 220, 60),
		rally = Color3.fromRGB(255, 200, 90),
		summon = Color3.fromRGB(200, 90, 255),
		dizzy = Color3.new(1, 1, 1),
		enrage = Color3.fromRGB(255, 60, 50),
		fizzle = Color3.fromRGB(160, 160, 170),
	},
}

return EnemyAI
