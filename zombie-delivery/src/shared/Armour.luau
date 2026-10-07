--!strict
-- 6.0: the vests in numbers (Config.Kit pieces with `armour`: the Kevlar Vest, the Heavy Armour). The best vest you own
-- counts (they never stack); its share comes off every bite and bullet (server/Armour.luau, the one place a player is
-- hurt). The HUD shows the share as a small shield with the percent (client/Hud.luau's health row), the KIT tab as the
-- piece's effect (client/KitShop.luau).
--
--   Armour.best(kit)           the owned Config.Kit piece with the most armour, or nil
--   Armour.share(kit)          that piece's share (0 – Config.Arms.MaxArmour; 0 without a vest)
--   Armour.percent(kit)        the share in whole percent (0 without a vest)
--   Armour.reduce(amount, kit) the damage left after the vest (never below 0)
--
-- Pure Luau (tests/armour_test.luau).

local Config = require(script.Parent.Config)

local Armour = {}

export type Kit = { [string]: boolean } -- Config.Kit ids owned (profile.kit)

function Armour.best(kit: Kit): Config.KitDef?
	local best: Config.KitDef? = nil
	for _, def in Config.Kit do
		local armour = def.armour
		if kit[def.id] == true and armour and armour > 0 then
			local b = best
			if b == nil or armour > (b.armour or 0) then
				best = def
			end
		end
	end
	return best
end

function Armour.share(kit: Kit): number
	local best = Armour.best(kit)
	if not best then
		return 0
	end
	return math.clamp(best.armour or 0, 0, Config.Arms.MaxArmour)
end

function Armour.percent(kit: Kit): number
	return math.floor(Armour.share(kit) * 100 + 0.5)
end

function Armour.reduce(amount: number, kit: Kit): number
	if amount ~= amount or amount <= 0 then
		return 0
	end
	return amount * (1 - Armour.share(kit))
end

return Armour
