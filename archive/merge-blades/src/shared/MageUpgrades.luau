--!strict
-- The Mage's UPGRADES: three tracks bought with coins in a mage's card (click a mage), each up to
-- Balance.MageUpgradeMax levels. They belong to the account and apply to EVERY mage in a battle (the mages are
-- interchangeable: merging keeps nothing per soldier). Numbers in Config/Balance.luau (MageUpgrades*).
--   power      +5 % damage per level
--   vitality   +5 % HP per level
--   swiftness  +3 % attack speed per level (the basic attack's cooldown shrinks)

local Balance = require(script.Parent.Config.Balance)

local MageUpgrades = {}

export type Levels = { [string]: number }
export type Multipliers = { hp: number, damage: number, cooldown: number }

-- Coins for the next level of a track that is at `level` now (nil when it is at the maximum).
function MageUpgrades.cost(level: number): number?
	if level >= Balance.MageUpgradeMax then
		return nil
	end
	return math.floor(Balance.MageUpgradeBaseCost * Balance.MageUpgradeGrowth ^ level + 0.5)
end

function MageUpgrades.level(levels: Levels?, id: string): number
	local level = if levels then levels[id] else nil
	return if type(level) == "number" then level else 0
end

-- The bonus of a track at `level`, as a fraction (0.25 = +25 %).
function MageUpgrades.bonus(id: string, level: number): number
	local def = Balance.MageUpgrades[id]
	return if def then def.step * level else 0
end

-- What a battle multiplies a mage's stats with.
function MageUpgrades.multipliers(levels: Levels?): Multipliers
	local speed = 1 + MageUpgrades.bonus("swiftness", MageUpgrades.level(levels, "swiftness"))
	return {
		hp = 1 + MageUpgrades.bonus("vitality", MageUpgrades.level(levels, "vitality")),
		damage = 1 + MageUpgrades.bonus("power", MageUpgrades.level(levels, "power")),
		cooldown = 1 / speed,
	}
end

-- "+15% damage" for the card.
function MageUpgrades.text(id: string, level: number): string
	local def = Balance.MageUpgrades[id]
	return if def then string.format(def.text, math.floor(MageUpgrades.bonus(id, level) * 100 + 0.5)) else ""
end

return MageUpgrades
