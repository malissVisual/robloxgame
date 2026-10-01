--!strict
-- Enemy waves: bigger, but made by a few simple rules. A map has a number of waves split into
-- PHASES of Balance.PhaseLength (5) waves. Each phase brings a new mob and ends with its own boss, so
-- the game changes every 5 waves (see `phases` in Config/Maps.luau; the Training Camp has 20 = 100 waves).
--
--   count  = Balance.EnemyBase + 2 + (phase - 1) // 3 + (the wave's place in its phase - 1), at most
--            Balance.EnemyMax (12): a phase starts with a few enemies and gets bigger wave by wave, and
--            later phases start bigger
--   level  = the phase number (phase 1 → enemy level 1, phase 2 → level 2, …); Balance.EnemyLevelScale
--   kinds  = the phase's `kinds` in order, repeated (a kind listed twice appears twice as often)
--   boss   = every Balance.PhaseLength-th wave the last enemy is the phase's boss
--   twists = the wave's TWISTS (Config/Mutators.luau, seeded by the wave number) may rewrite the list: SWARM (more,
--            weaker), BIG BOYS (fewer, a level higher), CHAMPION (one entry flagged), TREASURE GOBLIN / WAR TOTEMS
--            (extra entries). The preview and the fight both read this list, so they always agree.
--   formation = Waves.formation(wave, twists): the layout the enemies stand in (Config/Formations.luau)

local Balance = require(script.Parent.Balance)
local Maps = require(script.Parent.Maps)
local Enemies = require(script.Parent.Enemies)
local Mutators = require(script.Parent.Mutators)

export type Enemy = {
	kind: string,
	tier: number, -- enemy level
	champion: boolean?, -- the wave's CHAMPION (twist): much stronger, the Mage prefers it
	role: string?, -- "treasure" | "totem" for the twist extras (the formation places them apart)
}

local Waves = {}

-- The phase a wave belongs to: (its number, its definition).
function Waves.phase(wave: number, map: Maps.Def): (number, Maps.Phase)
	local index = math.min((wave - 1) // Balance.PhaseLength + 1, #map.phases)
	return index, map.phases[index]
end

function Waves.get(wave: number, map: Maps.Def): { Enemy }
	local phaseIndex, phase = Waves.phase(wave, map)
	local inPhase = (wave - 1) % Balance.PhaseLength + 1 -- 1 … 5 inside the phase
	local count = math.min(Balance.EnemyBase + 2 + (phaseIndex - 1) // 3 + (inPhase - 1), Balance.EnemyMax)
	local level = phaseIndex

	local enemies: { Enemy } = {}
	for i = 1, count do
		table.insert(enemies, { kind = phase.kinds[(i - 1) % #phase.kinds + 1], tier = level })
	end
	if wave % Balance.PhaseLength == 0 then
		enemies[count] = { kind = phase.boss, tier = level } -- the last wave of a phase has its boss
	end
	return Mutators.applyComposition(enemies, Mutators.forWave(wave, map), wave, function(kind)
		local def = Enemies.Kinds[kind]
		return if def then def.archetype else nil
	end)
end

-- The layout the wave stands in (Config/Formations.luau): a boss wave holds court, a swarm scatters, the pincer
-- twist takes the flanks, otherwise the place in the phase decides (line, wedge, shieldwall, wedge, boss).
function Waves.formation(wave: number, twists: { Mutators.Def }): string
	if wave % Balance.PhaseLength == 0 then
		return "bossCourt"
	end
	if Mutators.has(twists, "swarm") then
		return "scatter"
	end
	local pincer = Mutators.has(twists, "pincer")
	if pincer then
		return pincer.Formation
	end
	local inPhase = (wave - 1) % Balance.PhaseLength + 1
	return ({ "line", "wedge", "shieldwall", "wedge" })[inPhase] or "line"
end

-- Coins for killing one enemy of the given level in the given wave (times the kind's coin multiplier).
function Waves.killReward(wave: number, enemyLevel: number): number
	local base = Balance.KillCoinBase + Balance.KillCoinPerWave * wave
	return math.max(1, math.floor(base * (1 + Balance.KillCoinPerLevel * (enemyLevel - 1))))
end

return Waves
