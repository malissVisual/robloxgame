--!strict
-- Merge levels (1 … 9). A soldier's level (its tier) grows by one whenever two identical soldiers
-- (same class and level) are merged, up to Units.MaxTier. A level changes the soldier's power
-- (Units.TierScale ^ (level - 1)) and its look (see Soldier.luau).

local Levels = {}

-- One color per level (1 … 9): used for the level label, the pad under the soldier, effects and
-- cards. They follow the rarity colors of the Soldier design: two Common, two Uncommon, two Rare,
-- then Epic, Legendary and Mythic.
Levels.Colors = {
	Color3.fromRGB(156, 163, 175), -- 1 Common
	Color3.fromRGB(156, 163, 175), -- 2 Common
	Color3.fromRGB(74, 222, 128), -- 3 Uncommon
	Color3.fromRGB(74, 222, 128), -- 4 Uncommon
	Color3.fromRGB(96, 165, 250), -- 5 Rare
	Color3.fromRGB(96, 165, 250), -- 6 Rare
	Color3.fromRGB(192, 132, 252), -- 7 Epic
	Color3.fromRGB(251, 146, 60), -- 8 Legendary
	Color3.fromRGB(248, 113, 113), -- 9 Mythic
}

function Levels.color(level: number): Color3
	return Levels.Colors[math.clamp(level, 1, #Levels.Colors)]
end

function Levels.label(level: number): string
	return "Lv " .. level
end

-- Coins a soldier is sold for (the SELL button of a card, or automatically when the inventory is
-- full): it doubles with every level and stays below what a summoned level 1 soldier costs.
function Levels.sellValue(level: number, ascended: boolean?): number
	return math.floor(2 * 2 ^ (level - 1)) * (if ascended then 3 else 1)
end

return Levels
