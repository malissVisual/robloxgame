--!strict
-- Difficulty of the enemy waves. You choose it in the battle panel (the FIGHT button).

export type Def = {
	label: string,
	enemyPower: number, -- multiplies enemy HP and damage
	rewardMultiplier: number, -- multiplies the coins paid per enemy kill
	xpMultiplier: number, -- multiplies the XP of kills and of a won wave
	extraDrops: number, -- how many drops a won wave gives on top of the normal one
	luckyDropChance: number, -- chance of a lucky drop (unlocking a class) after a won wave
}

local Difficulties = {}

Difficulties.Order = { "Easy", "Normal", "Hard", "Nightmare" }
Difficulties.Default = "Normal"

Difficulties.Defs = {
	Easy = { label = "Easy", enemyPower = 0.7, rewardMultiplier = 0.7, xpMultiplier = 0.7, extraDrops = 0, luckyDropChance = 0.25 },
	Normal = { label = "Normal", enemyPower = 1, rewardMultiplier = 1, xpMultiplier = 1, extraDrops = 0, luckyDropChance = 0.35 },
	Hard = { label = "Hard", enemyPower = 1.6, rewardMultiplier = 1.6, xpMultiplier = 1.5, extraDrops = 0, luckyDropChance = 0.5 },
	-- The hardest: much stronger enemies, but the best rewards: an extra drop, a lot more coins and XP.
	Nightmare = { label = "Nightmare", enemyPower = 2.4, rewardMultiplier = 2.6, xpMultiplier = 2.5, extraDrops = 1, luckyDropChance = 0.6 },
} :: { [string]: Def }

return Difficulties
