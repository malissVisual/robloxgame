--!strict
-- Squad synergies: bonuses for the composition of the battle squad. Used by the server (battle) and
-- by the client (the line in the battle panel).
--   Frontline (Knight, Tank, Berserker, Soldier): 2 of them +10% HP for everybody, 3 or more +20%.
--   Ranged (Archer, Hunter, Mage): 2 of them +10% damage for everybody, 3 or more +20%.
--   Mixed: 4 or more different classes: +10% HP and damage.
-- The numbers are in Balance.luau.

local Balance = require(script.Parent.Config.Balance)
local Grid = require(script.Parent.Grid)

local Synergy = {}

Synergy.Roles = {
	Knight = "Frontline",
	Tank = "Frontline",
	Berserker = "Frontline",
	Soldier = "Frontline",
	Archer = "Ranged",
	Hunter = "Ranged",
	Mage = "Ranged",
} :: { [string]: string }

export type Result = {
	hp: number, -- multiplier of every soldier's HP
	damage: number, -- multiplier of every soldier's damage
	lines: { string }, -- what is active, for the UI
}

local function tierBonus(count: number): number
	if count >= Balance.SynergyHigh.count then
		return Balance.SynergyHigh.bonus
	elseif count >= Balance.SynergyLow.count then
		return Balance.SynergyLow.bonus
	end
	return 0
end

function Synergy.compute(squad: Grid.Cells): Result
	local roles: { [string]: number } = {}
	local classes: { [string]: boolean } = {}
	local distinct = 0
	for i = 1, #squad do
		local unit = squad[i]
		if unit then
			local role = Synergy.Roles[unit.class]
			if role then
				roles[role] = (roles[role] or 0) + 1
			end
			if not classes[unit.class] then
				classes[unit.class] = true
				distinct += 1
			end
		end
	end

	local result: Result = { hp = 1, damage = 1, lines = {} }
	local frontline = tierBonus(roles.Frontline or 0)
	if frontline > 0 then
		result.hp += frontline
		table.insert(result.lines, string.format("Frontline x%d: +%d%% HP", roles.Frontline, math.floor(frontline * 100 + 0.5)))
	end
	local ranged = tierBonus(roles.Ranged or 0)
	if ranged > 0 then
		result.damage += ranged
		table.insert(result.lines, string.format("Ranged x%d: +%d%% damage", roles.Ranged, math.floor(ranged * 100 + 0.5)))
	end
	if distinct >= Balance.SynergyMixedClasses then
		result.hp += Balance.SynergyMixedBonus
		result.damage += Balance.SynergyMixedBonus
		table.insert(result.lines, string.format("%d classes: +%d%% HP and damage", distinct, math.floor(Balance.SynergyMixedBonus * 100 + 0.5)))
	end
	return result
end

return Synergy
