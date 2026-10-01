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

local Balance = require(script.Parent.Balance)
local Maps = require(script.Parent.Maps)

export type Enemy = { kind: string, tier: number } -- tier = enemy level

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
	return enemies
end

-- Coins for killing one enemy of the given level in the given wave (times the kind's coin multiplier).
function Waves.killReward(wave: number, enemyLevel: number): number
	local base = Balance.KillCoinBase + Balance.KillCoinPerWave * wave
	return math.max(1, math.floor(base * (1 + Balance.KillCoinPerLevel * (enemyLevel - 1))))
end

return Waves
