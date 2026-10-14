--!strict
-- 8.3 SANDBOX, the warehouse's levels (the owner: "the warehouse can be upgraded from level 1 to level 5, and with each
-- upgrade it is bigger: more room for stands and other things"). The rules on Config.WarehouseLevels: a level checked,
-- its stands, its words, its UPGRADES card and the migration of a save from before the levels. Pure (no Roblox at its
-- top level; tests/warehouselevels_test.luau): shared/UpgradeRules.luau sells the levels (the "warehouse" card),
-- shared/CollectionRules.luau counts the stands with them, shared/WarehouseLayout.luau lays each one out,
-- server/Warehouse.luau builds the owner's, client/UpgradeUi.luau shows the card and the toast.
--
--   WarehouseLevels.Count            how many levels (5)
--   WarehouseLevels.Start            a new player's level (and a free plot's): Config.WarehouseLevels.Start
--   WarehouseLevels.Flag             the save's mark (a real save without it is migrated once: migrate)
--   WarehouseLevels.clamp(n)         a level 1 … Count (a fraction down; junk: Start)
--   WarehouseLevels.def(n)           its Config entry (clamped)
--   WarehouseLevels.stands(n)        its display stands
--   WarehouseLevels.price(n)         $ to grow into it (the start's 0)
--   WarehouseLevels.title(n)         "Level 2 · Workshop"
--   WarehouseLevels.summary(n, sized?)   "Level 2 · Workshop · 4 stands" (sized: "Level 3 · Warehouse · 58×42 · 8 stands")
--   WarehouseLevels.grew(n)          the purchase's toast: "🏗 Your warehouse grew: Workshop (4 stands)"
--   WarehouseLevels.forStands(count) the least level with at least `count` stands (the top when none has so many)
--   WarehouseLevels.card()           the UPGRADES card's def (shared/UpgradeRules.luau's "warehouse": its name, icon,
--                                    top level, prices[n] buys level n, start)
--   WarehouseLevels.migrate(saved)   the level a real save from before the levels starts at (nil: not one: a new player,
--                                    a lock-only record, junk, or a save written with Flag): the least level with every
--                                    stand it had (Old.Stands + Old.Step × its More stands, read only with the upgrades'
--                                    flag) and every piece it has on show (its collection, read only with the
--                                    collection's flag), never under Old.Least

local Config = require(script.Parent.Config)

local WarehouseLevels = {}

local L = Config.WarehouseLevels
local LIST = L.List

WarehouseLevels.Count = #LIST
WarehouseLevels.Start = math.clamp(math.floor(L.Start), 1, #LIST)
WarehouseLevels.Flag = L.Flag

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function WarehouseLevels.clamp(n: any): number
	if not finite(n) then
		return WarehouseLevels.Start
	end
	return math.clamp(math.floor(n), 1, #LIST)
end

function WarehouseLevels.def(n: any): Config.WarehouseLevelDef
	return LIST[WarehouseLevels.clamp(n)]
end

function WarehouseLevels.stands(n: any): number
	return WarehouseLevels.def(n).stands
end

function WarehouseLevels.price(n: any): number
	return WarehouseLevels.def(n).price
end

function WarehouseLevels.title(n: any): string
	return `Level {WarehouseLevels.clamp(n)} · {WarehouseLevels.def(n).name}`
end

function WarehouseLevels.summary(n: any, sized: boolean?): string
	local def = WarehouseLevels.def(n)
	local size = if sized then ` · {def.size[1]}×{def.size[3]}` else ""
	return `{WarehouseLevels.title(n)}{size} · {def.stands} stands`
end

function WarehouseLevels.grew(n: any): string
	local def = WarehouseLevels.def(n)
	return `🏗 Your warehouse grew: {def.name} ({def.stands} stands)`
end

function WarehouseLevels.forStands(count: any): number
	local want = if finite(count) then count else 0
	for n, def in LIST do
		if def.stands >= want then
			return n
		end
	end
	return #LIST
end

-- The UPGRADES card (UpgradeRules.def("warehouse")): made once.
local card: Config.SandboxUpgradeDef? = nil
function WarehouseLevels.card(): Config.SandboxUpgradeDef
	local made = card
	if made then
		return made
	end
	local prices: { number } = {}
	for n, def in LIST do
		prices[n] = def.price
	end
	local fresh: Config.SandboxUpgradeDef = { name = "Warehouse", icon = L.Icon, max = #LIST, step = 0, prices = prices, start = WarehouseLevels.Start }
	card = fresh
	return fresh
end

-- 8.3 review: the level an older server could not drop. 8.2 keeps every short key of `rewards` but neither
-- sandboxUpgrades.warehouse nor the flag, so the save also carries "wh:<level>" there (PlayerData.save). nil: none.
WarehouseLevels.RewardKey = "wh:"
function WarehouseLevels.carried(saved: any): number?
	local rewards = if type(saved) == "table" then saved.rewards else nil
	if type(rewards) ~= "table" then
		return nil
	end
	local best: number? = nil
	for key, on in rewards do
		if on == true and type(key) == "string" and string.sub(key, 1, #WarehouseLevels.RewardKey) == WarehouseLevels.RewardKey then
			local n = tonumber(string.sub(key, #WarehouseLevels.RewardKey + 1))
			if n and n == math.floor(n) and n >= 1 and n <= #LIST then
				best = math.max(best or 0, n)
			end
		end
	end
	return best
end

-- 8.3 review: what an older (8.2) server shows of this level: its More stands count (12 + 2 a level), so a visit there
-- neither hides stands nor sends pieces back to the stock. Levels 1 - 4: 0; level 5: 4.
function WarehouseLevels.oldStands(level: number): number
	local old = L.Old
	return math.clamp(math.floor((WarehouseLevels.stands(level) - old.Stands) / old.Step), 0, old.Bought)
end

function WarehouseLevels.migrate(saved: any): number?
	if type(saved) ~= "table" or saved.money == nil or saved[L.Flag] == true then
		return nil
	end
	local kept = WarehouseLevels.carried(saved)
	if kept then
		return kept -- (8.3 review: a save that went through an older server: its level from `rewards`, not migrated again)
	end
	local old = L.Old
	local bought = 0
	local upgrades = saved.sandboxUpgrades
	if saved[Config.SandboxUpgrades.Flag] == true and type(upgrades) == "table" and finite(upgrades.stands) then
		bought = math.clamp(math.floor(upgrades.stands), 0, old.Bought)
	end
	local most = old.Stands + old.Step * old.Bought -- (no stand of an older warehouse past this)
	local need = old.Stands + old.Step * bought
	local collection = saved.collection
	local entries = if saved.collectionKept == true and type(collection) == "table" then collection.entries else nil
	if type(entries) == "table" then
		for _, entry in entries do
			local stand = if type(entry) == "table" then entry.stand else nil
			if finite(stand) and stand >= 1 and stand <= most then
				need = math.max(need, math.floor(stand))
			end
		end
	end
	return math.max(math.clamp(old.Least, 1, #LIST), WarehouseLevels.forStands(need))
end

return WarehouseLevels
