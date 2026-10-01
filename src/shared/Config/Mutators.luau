--!strict
-- Wave TWISTS: every wave from the 3rd gets one (later two) modifiers picked DETERMINISTICALLY from its number, so a
-- replayed wave is the same fight, the arena preview and the fight agree (both read Waves.get → applyComposition),
-- and no two waves in a row feel alike. A twist is announced by the WaveIntro banner (label + one line of advice),
-- shown as a chip during the fight and, where it changes the enemy list, visible in the preview before FIGHT.
--
--   Mutators.forWave(wave, map)      → { Def }   the wave's twists (memoized; seeded by the wave number)
--   Mutators.coinBonus(list)         → number    extra coins fraction of these twists (capped by Balance.MutatorCoinsCap)
--   Mutators.applyComposition(...)   rewrites the wave's enemy list for the composition twists (Waves.get calls it)
--
-- Selection: slots(wave) = 0 for waves 1-2 and the map's last wave, 1 for waves 3-40, 2 on every 3rd wave of 41-70,
-- 2 for 71-99; a boss wave has 1 twist from wave 25 (only twists with bossOk), none before. Candidates must be
-- unlocked (minWave), not used in the previous 2 waves, keep the threat sum ≤ MaxStackThreat, have a different tag
-- from the first pick and no mutual exclusion; the pick is weighted by `weight`.
--
-- The runtime (server/Services/WaveMutators.luau) reads every number from `Mutators.Defs.<id>` — a tuning pass touches
-- only this file. This module requires only Balance (the test runner replaces everything above the module table).

local Balance = require(script.Parent.Balance)

local Mutators = {}

local C = Color3.fromRGB

export type Def = {
	id: string,
	label: string, -- the banner title (uppercase, short)
	subtitle: string, -- one line of advice shown under the title
	color: Color3,
	tag: string, -- "formation" | "aura" | "field" | "composition" | "event": a double wave mixes two tags
	minWave: number,
	weight: number, -- relative chance when it is a candidate
	threat: number, -- how much harder it makes the wave (two twists together stay ≤ Schedule.MaxStackThreat)
	bossOk: boolean, -- may appear on a boss wave
	excludes: { string }, -- never together with these ids
	coinBonus: number, -- extra coins for the wave (fraction)
	changesList: boolean?, -- rewrites the enemy list (kept on an elite wave so the preview and the fight agree)
	[string]: any, -- the twist's own numbers (see each Def)
}

-- When twists appear and how they stack.
Mutators.Schedule = {
	FirstWave = 3, -- no twist on waves 1-2 (learn the basics first)
	BossFrom = 25, -- boss waves carry a twist from this wave on
	DoubleFrom = 41, -- from here every DoubleEvery-th wave has two twists ...
	DoubleEvery = 3,
	AlwaysDoubleFrom = 71, -- ... and from here every wave has two
	MaxStackThreat = 2.1, -- the threat sum of a wave's twists
	NoRepeatWindow = 2, -- a twist is not reused within this many previous waves
}

-- The pool, in a fixed order (the selection iterates it; the order matters for determinism only).
Mutators.Order = {
	"swift", "shielded", "bigBoys", "swarm", "frenzy", "champion", "treasure", "poison", "regen", "totems",
	"pincer", "ambush", "volatile", "enrage", "storm",
}

Mutators.Defs = {
	swift = {
		id = "swift", label = "SWIFT FEET", subtitle = "they move 30% faster", color = C(235, 240, 255), tag = "aura",
		minWave = 3, weight = 1.0, threat = 0.5, bossOk = true, excludes = {}, coinBonus = 0.05,
		Haste = 1.3, -- attack rate and movement (the Brute's charge keeps its own speed constant)
	},
	shielded = {
		id = "shielded", label = "WARDED", subtitle = "first hits are wasted — AoE pops bubbles", color = C(90, 220, 255), tag = "aura",
		minWave = 4, weight = 0.8, threat = 0.6, bossOk = true, excludes = {}, coinBonus = 0.10,
		Fraction = 0.15, -- shieldHp = this × maxHp ...
		LateFraction = 0.2, -- ... from LateWave on
		LateWave = 60,
		TintTime = 2, -- the cyan bubble tint at the start (seconds)
	},
	bigBoys = {
		id = "bigBoys", label = "BIG BOYS", subtitle = "fewer but stronger", color = C(255, 170, 90), tag = "composition",
		minWave = 5, weight = 0.9, threat = 0.7, bossOk = false, excludes = { "swarm" }, coinBonus = 0.10, changesList = true,
		Fewer = 2, -- this many enemies less ...
		MinCount = 3, -- ... but at least this many
		TierBonus = 1, -- every enemy one level higher
	},
	swarm = {
		id = "swarm", label = "SWARM", subtitle = "many weak goblins — splash wins", color = C(170, 255, 120), tag = "composition",
		minWave = 6, weight = 1.0, threat = 0.8, bossOk = false, excludes = { "ambush", "champion", "totems", "bigBoys" }, coinBonus = 0, changesList = true,
		Factor = 1.6, -- count × this, at most Balance.HordeMax
		Hp = 0.55, -- each enemy's HP ×
		Damage = 0.7, -- each enemy's damage ×
		Coins = 0.6, -- each enemy's coins × (bonusCoins = Coins − 1)
		Archetypes = { Grunt = true, Archer = true }, -- only these kinds of the phase (fallback: the phase's kinds)
	},
	frenzy = {
		id = "frenzy", label = "FRENZY", subtitle = "fast and fragile", color = C(255, 80, 70), tag = "aura",
		minWave = 8, weight = 0.9, threat = 1.0, bossOk = true, excludes = { "enrage", "champion" }, coinBonus = 0.15,
		Haste = 1.35,
		BossHaste = 1.2,
		Hp = 0.8,
		PulseFrom = 0.85, -- the red Highlight pulses between these fill transparencies
		PulseTo = 0.7,
		PulseTime = 0.5,
	},
	champion = {
		id = "champion", label = "CHAMPION", subtitle = "one big goblin — focus it", color = C(255, 190, 60), tag = "composition",
		minWave = 9, weight = 1.5, threat = 1.2, bossOk = false, excludes = { "swarm", "frenzy", "ambush" }, coinBonus = 0, changesList = true,
		Hp = 3,
		Damage = 1.5,
		Size = 1.3, -- model scale (pcall ScaleTo) and lift ×
		Armor = 0.15,
		Coins = 4, -- coins × (bonusCoins = Coins − 1)
		CooldownFactor = 0.5, -- its specials twice as often (ai.cooldownFactor)
		BarEvery = 0.15, -- the BossHp bar "CHAMPION · <name>" refresh (seconds)
	},
	treasure = {
		id = "treasure", label = "TREASURE GOBLIN", subtitle = "catch him before he escapes", color = C(255, 215, 80), tag = "event",
		minWave = 7, weight = 0.8, threat = 0.2, bossOk = false, excludes = { "ambush", "enrage" }, coinBonus = 0, changesList = true,
		Kind = "Treasure", -- Enemies.Kinds entry appended to the wave
		EscapeAt = 20, -- battle seconds until it teleports away (no coins, no kill)
	},
	poison = {
		id = "poison", label = "TOXIC GROUND", subtitle = "green puddles hurt everyone", color = C(120, 255, 90), tag = "field",
		minWave = 10, weight = 1.0, threat = 0.7, bossOk = true, excludes = {}, coinBonus = 0.10,
		Count = 4, -- puddles ...
		LateCount = 5, -- ... from LateWave on
		LateWave = 50,
		Radius = 6,
		Dps = 0.03, -- × maxHp per second to every fighter inside (both sides)
		Slow = 0.7, -- slowFactor while inside
		PlayerDps = 3, -- HP per second to a player standing inside
		BandX = 24, -- puddle centers: x within center ± BandX ...
		BandZMin = -6, -- ... z within center + [BandZMin, BandZMax] (the middle band, between the two sides)
		BandZMax = 10,
		MinGap = 11, -- between two puddles
		SpotGap = 8, -- from every start spot of a fighter
		PulseFrom = 0.45, -- the cylinders pulse between these transparencies
		PulseTo = 0.65,
		BubbleEvery = 0.5, -- a rising bubble per puddle (seconds)
		PayEvery = 1, -- the damage of a fighter inside is paid (one hit, one green number) once per this many seconds
		HazardTime = Balance.BattleTimeLimit + 10, -- the data hazards (what the Mage avoids) stand for the whole battle
	},
	regen = {
		id = "regen", label = "BLOOD MOON", subtitle = "finish what you start", color = C(255, 60, 90), tag = "aura",
		minWave = 12, weight = 0.9, threat = 0.9, bossOk = true, excludes = { "totems" }, coinBonus = 0.15,
		Rate = 0.025, -- × maxHp per second ...
		Delay = 2, -- ... after this many seconds without being hit
		MoteEvery = 1, -- green motes per regenerating enemy (seconds)
		MotesPerTick = 6, -- at most this many enemies spark in one tick
		MoonSize = 10,
		MoonHeight = 40, -- studs above the far end of the arena
	},
	totems = {
		id = "totems", label = "WAR TOTEMS", subtitle = "kill the totems first", color = C(110, 230, 120), tag = "field",
		minWave = 13, weight = 0.9, threat = 0.9, bossOk = false, excludes = { "regen", "swarm" }, coinBonus = 0.10, changesList = true,
		Kind = "Totem", -- Enemies.Kinds entry appended to the wave
		Count = 2, -- totems ...
		LateCount = 3, -- ... from LateWave on
		LateWave = 60,
		Radius = 12, -- heals enemies within this many studs ...
		Rate = 0.03, -- ... × maxHp per second (paid once a second)
		PulseEvery = 1, -- the green ring from every living totem (seconds)
	},
	pincer = {
		id = "pincer", label = "PINCER", subtitle = "they come from the sides — guard your archers", color = C(255, 140, 200), tag = "formation",
		minWave = 14, weight = 1.0, threat = 0.7, bossOk = false, excludes = {}, coinBonus = 0.10,
		Formation = "pincer", -- Formations.luau layout
	},
	ambush = {
		id = "ambush", label = "AMBUSH", subtitle = "reinforcements arrive mid-fight", color = C(255, 90, 60), tag = "event",
		minWave = 15, weight = 1.0, threat = 1.0, bossOk = false, excludes = { "swarm", "champion", "treasure" }, coinBonus = 0.10,
		At = 12, -- battle seconds, or ...
		HalfDead = 0.5, -- ... when this part of the wave is dead (whichever first)
		Warning = 1.5, -- seconds of red circles before they appear
		Radius = 4,
		SideX = 30, -- the two arrival points: x center ± SideX, z center + SideZ
		SideZ = -10,
		Count = { 2, 3, 4 }, -- reinforcements by wave band (CountWaves)
		CountWaves = { 30, 70 }, -- < 30 → 2, 30-69 → 3, ≥ 70 → 4
	},
	volatile = {
		id = "volatile", label = "VOLATILE", subtitle = "they explode — kill them apart or all at once", color = C(255, 150, 40), tag = "aura",
		minWave = 16, weight = 0.9, threat = 0.9, bossOk = true, excludes = {}, coinBonus = 0.10,
		Delay = 0.4, -- seconds between the death and the blast (orange glow, swelling ball)
		Radius = 5,
		SquadMult = 1.2, -- soldiers inside take this × the dead one's damage
		EnemyFraction = 0.3, -- other enemies inside lose this part of their max HP (chains)
		PlayerDamage = 15, -- HP for a player inside
	},
	enrage = {
		id = "enrage", label = "ENRAGE TIMER", subtitle = "win fast", color = C(255, 70, 70), tag = "event",
		minWave = 18, weight = 0.9, threat = 1.0, bossOk = true, excludes = { "frenzy", "treasure" }, coinBonus = 0.20,
		Time = 35, -- seconds on the bar ...
		LateTime = 30, -- ... from LateWave on
		LateWave = 70,
		WarnAt = 10, -- the bar turns red and a notice shows with this many seconds left
		Damage = 0.6, -- every enemy's damage × (1 + this) at 0
		Haste = 1.3,
		BarEvery = 0.25, -- the BossHp bar refresh (seconds)
	},
	storm = {
		id = "storm", label = "THUNDERSTORM", subtitle = "step out of the glowing circles", color = C(160, 200, 255), tag = "field",
		minWave = 20, weight = 0.9, threat = 1.0, bossOk = true, excludes = {}, coinBonus = 0.15,
		Every = 4, -- a strike every N seconds ...
		LateEvery = 3, -- ... from LateWave on
		LateWave = 60,
		FirstAt = 3,
		EnemyBias = 0.65, -- chance the strike aims at a random enemy (else a random soldier)
		Radius = 5,
		Warning = 1.2, -- seconds of the locked circle before the bolt
		Damage = 0.10, -- × maxHp to everyone inside (both sides) ...
		BossDamage = 0.05, -- ... bosses this much
		PlayerDamage = 10,
		CloudHeight = 35,
		CloudSize = 30,
		CloudTransparency = 0.4,
	},
} :: { [string]: Def }

-- How many twists a wave gets (see the header).
function Mutators.slots(wave: number, map: { waves: number, [string]: any }): number
	local S = Mutators.Schedule
	if wave < S.FirstWave or wave >= map.waves then
		return 0
	end
	if wave % Balance.PhaseLength == 0 then
		return if wave >= S.BossFrom then 1 else 0
	end
	if wave < S.DoubleFrom then
		return 1
	end
	if wave < S.AlwaysDoubleFrom then
		return if wave % S.DoubleEvery == 0 then 2 else 1
	end
	return 2
end

local function excludes(def: Def, id: string): boolean
	for _, other in def.excludes do
		if other == id then
			return true
		end
	end
	return false
end

local function compatible(def: Def, picked: { Def }): boolean
	for _, other in picked do
		if other.id == def.id or other.tag == def.tag or excludes(def, other.id) or excludes(other, def.id) then
			return false
		end
	end
	return true
end

-- The twists of one wave given the picks of the previous NoRepeatWindow waves.
local function compute(wave: number, map: { waves: number, [string]: any }, previous: { { Def } }): { Def }
	local S = Mutators.Schedule
	local slots = Mutators.slots(wave, map)
	if slots == 0 then
		return {}
	end
	local rng = Random.new(wave * 7919 + 17)
	local bossWave = wave % Balance.PhaseLength == 0
	local recent: { [string]: boolean } = {}
	for _, list in previous do
		for _, def in list do
			recent[def.id] = true
		end
	end
	local picked: { Def } = {}
	local threat = 0
	for _ = 1, slots do
		local candidates: { Def } = {}
		local total = 0
		for _, id in Mutators.Order do
			local def = Mutators.Defs[id]
			if def.minWave <= wave and (not bossWave or def.bossOk) and not recent[id] and threat + def.threat <= S.MaxStackThreat + 1e-9 and compatible(def, picked) then
				table.insert(candidates, def)
				total += def.weight
			end
		end
		if #candidates == 0 then
			break
		end
		local roll = rng:NextNumber() * total
		local chosen = candidates[#candidates]
		for _, def in candidates do
			roll -= def.weight
			if roll <= 0 then
				chosen = def
				break
			end
		end
		table.insert(picked, chosen)
		threat += chosen.threat
	end
	return picked
end

-- Memoized per map: the picks depend on the previous waves' picks, so they are built from the first wave up.
local cache: { [any]: { [number]: { Def } } } = setmetatable({}, { __mode = "k" }) :: any

function Mutators.forWave(wave: number, map: { waves: number, [string]: any }): { Def }
	local perMap = cache[map]
	if not perMap then
		perMap = {}
		cache[map] = perMap
	end
	local known = perMap[wave]
	if known then
		return known
	end
	local S = Mutators.Schedule
	for w = 1, wave do
		if not perMap[w] then
			local previous: { { Def } } = {}
			for back = 1, S.NoRepeatWindow do
				local earlier = perMap[w - back]
				if earlier then
					table.insert(previous, earlier)
				end
			end
			perMap[w] = compute(w, map, previous)
		end
	end
	return perMap[wave]
end

-- The extra coins fraction of a wave's twists together (capped).
function Mutators.coinBonus(list: { Def }): number
	local sum = 0
	for _, def in list do
		sum += def.coinBonus
	end
	return math.min(Balance.MutatorCoinsCap, sum)
end

function Mutators.has(list: { Def }, id: string): Def?
	for _, def in list do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- Rewrites a wave's enemy list (the entries are { kind, tier, champion?, role? }) for the twists that change WHO
-- comes: SWARM (more, weaker kinds of the phase), BIG BOYS (fewer, a level higher), CHAMPION (the first Brute, else
-- the first entry, is flagged), TREASURE GOBLIN and WAR TOTEMS (extra entries). `archetypeOf(kind)` tells a kind's
-- archetype (Enemies.Kinds); without it every kind counts for the swarm and the champion is the first entry.
-- Called by Waves.get, so the preview, the banner and the fight read the same list.
function Mutators.applyComposition(enemies: { any }, twists: { Def }, wave: number, archetypeOf: ((kind: string) -> string?)?): { any }
	if #enemies == 0 then
		return enemies
	end
	local tier = enemies[1].tier
	local swarm = Mutators.has(twists, "swarm")
	if swarm then
		local kinds: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, e in enemies do
			local archetype = if archetypeOf then archetypeOf(e.kind) else nil
			if not seen[e.kind] and (archetype == nil or swarm.Archetypes[archetype]) then
				seen[e.kind] = true
				table.insert(kinds, e.kind)
			end
		end
		if #kinds == 0 then
			for _, e in enemies do
				if not seen[e.kind] then
					seen[e.kind] = true
					table.insert(kinds, e.kind)
				end
			end
		end
		local count = math.min(Balance.HordeMax, math.floor(#enemies * swarm.Factor + 0.5))
		table.clear(enemies)
		for i = 1, count do
			table.insert(enemies, { kind = kinds[(i - 1) % #kinds + 1], tier = tier })
		end
	end
	local bigBoys = Mutators.has(twists, "bigBoys")
	if bigBoys then
		for _ = 1, bigBoys.Fewer do
			if #enemies > bigBoys.MinCount then
				table.remove(enemies)
			end
		end
		for _, e in enemies do
			e.tier += bigBoys.TierBonus
		end
	end
	local champion = Mutators.has(twists, "champion")
	if champion then
		local index = 1
		if archetypeOf then
			for i, e in enemies do
				if archetypeOf(e.kind) == "Brute" then
					index = i
					break
				end
			end
		end
		enemies[index].champion = true
	end
	local treasure = Mutators.has(twists, "treasure")
	if treasure then
		table.insert(enemies, { kind = treasure.Kind, tier = tier, role = "treasure" })
	end
	local totems = Mutators.has(twists, "totems")
	if totems then
		local count = if wave >= totems.LateWave then totems.LateCount else totems.Count
		for _ = 1, count do
			table.insert(enemies, { kind = totems.Kind, tier = tier, role = "totem" })
		end
	end
	return enemies
end

return Mutators
