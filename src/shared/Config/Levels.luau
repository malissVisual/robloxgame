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
	-- 10 … 30 exist only for the Knight, the Archer and the Mage (their 30-level evolutions): the eras of the design.
	Color3.fromRGB(239, 68, 68), -- 10 Legionnaire (the last of antiquity)
	Color3.fromRGB(125, 211, 252), -- 11 Middle Ages
	Color3.fromRGB(125, 211, 252), -- 12
	Color3.fromRGB(56, 189, 248), -- 13
	Color3.fromRGB(56, 189, 248), -- 14
	Color3.fromRGB(14, 165, 233), -- 15
	Color3.fromRGB(217, 170, 90), -- 16 Industrial age (brass)
	Color3.fromRGB(217, 170, 90), -- 17
	Color3.fromRGB(234, 140, 60), -- 18
	Color3.fromRGB(234, 140, 60), -- 19
	Color3.fromRGB(249, 115, 22), -- 20
	Color3.fromRGB(134, 190, 110), -- 21 Modern (olive)
	Color3.fromRGB(134, 190, 110), -- 22
	Color3.fromRGB(74, 222, 128), -- 23
	Color3.fromRGB(74, 222, 128), -- 24
	Color3.fromRGB(34, 197, 94), -- 25
	Color3.fromRGB(103, 232, 249), -- 26 Future (cyan to gold)
	Color3.fromRGB(103, 232, 249), -- 27
	Color3.fromRGB(167, 139, 250), -- 28
	Color3.fromRGB(250, 204, 21), -- 29
	Color3.fromRGB(253, 224, 71), -- 30 Apex
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
