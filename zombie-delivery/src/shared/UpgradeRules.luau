--!strict
-- 8.1 SANDBOX, the upgrades' rules (Config.SandboxUpgrades): what each level costs and gives, the save's levels checked
-- and migrated, and the window's cards. Pure (no Roblox at its top level; tests/upgrades_test.luau): the server
-- (server/Upgrades.luau) decides every purchase with it, shared/CollectionRules.luau reads the stands and the lights
-- from it, shared/MoveHelperBrain.luau Danny's walk, client/UpgradeUi.luau draws its cards.
--
-- The levels (profile.sandboxUpgrades) are { [id]: level }: a known id, a whole level 1 … its max (0 is not kept).
--   UpgradeRules.Order                  the ids in the window's order (Config.SandboxUpgrades.Order)
--   UpgradeRules.def(id)                its Config entry (nil: no such upgrade; any type)
--   UpgradeRules.level(levels, id)      its level in these levels: 0 … its max (0 for junk)
--   UpgradeRules.price(id, level)       what the level after `level` costs (nil: at the top, or no such upgrade)
--   UpgradeRules.warehouseLevel(levels) 8.3: the warehouse's level (1 … 5: the ZDC Warehouse upgrade's level + 1,
--                                       Config.Warehouse.Levels; design/warehouse-levels/KONTRAKT.md)
--   UpgradeRules.totalStands(levels)    8.3: the display stands the player has: their level's big stands + the More
--                                       stands' small ones (from Config.Warehouse.MoreFrom on)
--   UpgradeRules.locked(levels, id)     8.3: why it can't be bought now (More stands below MoreFrom: "Needs the Big
--                                       Warehouse"), nil: it can
--   UpgradeRules.extraStands(levels)    the display stands More stands adds (2 a level; 8.3: counted from MoreFrom on)
--   UpgradeRules.mostStands()           the stands More stands adds at its top
--   UpgradeRules.incomeBoost(levels)    the stands' income × this (Showroom lights: 1.1 a level, compounding)
--   UpgradeRules.vanSpeed(levels)       the van's top speed × this (Van engine: + 5 % a level)
--   UpgradeRules.dannySpeed(level)      Danny's walk × this for a training level (any type: junk is 0)
--   UpgradeRules.effect(id, level, levels?)   what that level gives, in words ("Workshop · 4 stands", "14 display
--                                       stands" (with levels' warehouse), "Income ×1.21", "Top speed +10%", "Walks 20%
--                                       faster"; level 0: the start)
--   UpgradeRules.rows(levels, money)    the window's cards ({ Row }, in Order): the level, its top, now and next in
--                                       words, the next price, whether the money buys it (and if not, how much is
--                                       missing); 8.3: locked (its reason; can is false then)
--   UpgradeRules.money(n)               "$1,234"
--   The save:
--   UpgradeRules.empty()                a new player's (none bought)
--   UpgradeRules.full()                 every upgrade at its top (the admin's MAX UPGRADES)
--   UpgradeRules.clean(raw)             saved levels checked, never trusted: known ids, whole levels 1 … max
--   UpgradeRules.fromSave(saved)        the migration (server/PlayerData.luau applySaved): only a real save (money in
--                                       it) written with the flag (Config.SandboxUpgrades.Flag) has upgrades; an
--                                       older one, a new player or a lock-only record start with none. 8.3: a real
--                                       save without WarehouseFlag (from before 8.3) had today's warehouse: level 4
--   UpgradeRules.Flag                   that flag
--   UpgradeRules.WarehouseFlag          8.3: the warehouse level's (Config.SandboxUpgrades.WarehouseFlag)
--   UpgradeRules.WarehouseAttribute     8.3: the player attribute with their warehouse level (server/Upgrades.luau)

local Config = require(script.Parent.Config)

local UpgradeRules = {}

export type Levels = { [string]: number }
export type Row = {
	id: string,
	name: string,
	icon: string,
	level: number,
	max: number,
	now: string, -- what the level you have gives
	next: string?, -- what the next level gives (nil: at the top)
	price: number?, -- the next level's price (nil: at the top)
	can: boolean, -- the money buys the next level (and it is not locked)
	short: number, -- the money missing for it (0: none)
	locked: string?, -- 8.3: why it can't be bought now (nil: it can)
}

local function tune(): any
	return Config.SandboxUpgrades
end

UpgradeRules.Order = tune().Order :: { string }
UpgradeRules.Flag = tune().Flag :: string
UpgradeRules.WarehouseFlag = (tune().WarehouseFlag or "warehouseLevelKept") :: string
UpgradeRules.WarehouseAttribute = (tune().WarehouseAttribute or "WarehouseLevel") :: string

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function UpgradeRules.def(id: any): Config.SandboxUpgradeDef?
	if type(id) ~= "string" or #id > 32 then
		return nil
	end
	return tune().List[id]
end

local function clamp(def: Config.SandboxUpgradeDef, level: any): number
	if not finite(level) then
		return 0
	end
	return math.clamp(math.floor(level), 0, def.max)
end

function UpgradeRules.level(levels: any, id: string): number
	local def = UpgradeRules.def(id)
	if not def or type(levels) ~= "table" then
		return 0
	end
	return clamp(def, levels[id])
end

function UpgradeRules.price(id: string, level: number): number?
	local def = UpgradeRules.def(id)
	if not def then
		return nil
	end
	local now = clamp(def, level)
	if now >= def.max then
		return nil
	end
	return def.prices[now + 1]
end

-- ── The effects ────────────────────────────────────────────────────────────

local function step(id: string): number
	local def = UpgradeRules.def(id)
	return if def then def.step else 0
end

-- 8.3: the warehouse's levels (Config.Warehouse.Levels) and the first with the small stands (MoreFrom).
local function warehouseDefs(): { Config.WarehouseLevelDef }
	local warehouse = (Config :: any).Warehouse
	local list = if type(warehouse) == "table" then warehouse.Levels else nil
	return if type(list) == "table" then list else {}
end

local function moreFrom(): number
	local warehouse = (Config :: any).Warehouse
	local from = if type(warehouse) == "table" then warehouse.MoreFrom else nil
	return if finite(from) then math.floor(from) else 1
end

function UpgradeRules.warehouseLevel(levels: any): number
	local most = math.max(1, #warehouseDefs())
	return math.clamp(1 + UpgradeRules.level(levels, "warehouse"), 1, most)
end

-- The display stands a warehouse level has of its own (its big ones; nil level or none listed: the start's,
-- Config.Warehouse.Stands, else Config.Collection.Stands).
local baseStands: (level: number?) -> number

function UpgradeRules.extraStands(levels: any): number
	if UpgradeRules.warehouseLevel(levels) < moreFrom() then
		return 0
	end
	return math.floor(UpgradeRules.level(levels, "stands") * step("stands"))
end

function UpgradeRules.totalStands(levels: any): number
	return baseStands(UpgradeRules.warehouseLevel(levels)) + UpgradeRules.extraStands(levels)
end

function UpgradeRules.locked(levels: any, id: string): string?
	if id == "stands" then
		local from = moreFrom()
		if UpgradeRules.warehouseLevel(levels) < from then
			local def = warehouseDefs()[from]
			return `Needs the {if def then def.name else `level {from} warehouse`}`
		end
	end
	return nil
end

function UpgradeRules.mostStands(): number
	local def = UpgradeRules.def("stands")
	return if def then math.floor(def.max * def.step) else 0
end

function UpgradeRules.incomeBoost(levels: any): number
	return (1 + step("lights")) ^ UpgradeRules.level(levels, "lights")
end

function UpgradeRules.vanSpeed(levels: any): number
	return 1 + step("engine") * UpgradeRules.level(levels, "engine")
end

function UpgradeRules.dannySpeed(level: any): number
	local def = UpgradeRules.def("danny")
	if not def then
		return 1
	end
	return 1 + def.step * clamp(def, level)
end

baseStands = function(level: number?): number
	local def = if level then warehouseDefs()[level] else nil
	if def and finite(def.stands) and def.stands >= 1 then
		return math.floor(def.stands)
	end
	local warehouse = (Config :: any).Warehouse
	local stands = if type(warehouse) == "table" then warehouse.Stands else nil
	if not finite(stands) or stands < 1 then
		stands = Config.Collection.Stands
	end
	return math.floor(stands)
end

-- "$1,234" (whole dollars; the window's prices and the server's refusals).
function UpgradeRules.money(n: any): string
	local amount = if finite(n) then math.max(0, math.floor(n + 0.5)) else 0
	local out = string.reverse((string.gsub(string.reverse(string.format("%d", amount)), "(%d%d%d)", "%1,")))
	if string.sub(out, 1, 1) == "," then
		out = string.sub(out, 2)
	end
	return "$" .. out
end

local function percent(share: number): string
	return `{math.floor(share * 100 + 0.5)}%`
end

function UpgradeRules.effect(id: string, level: number, levels: any?): string
	local def = UpgradeRules.def(id)
	if not def then
		return ""
	end
	local at = clamp(def, level)
	if id == "warehouse" then
		local n = math.clamp(1 + at, 1, math.max(1, #warehouseDefs()))
		local building = warehouseDefs()[n]
		local stands = baseStands(n)
		return `{if building then building.name else `Level {n}`} · {stands} {if stands == 1 then "stand" else "stands"}`
	elseif id == "stands" then
		-- (the More stands' small stands on the warehouse's own: the levels' warehouse; none given, the start's)
		local warehouse = if type(levels) == "table" then UpgradeRules.warehouseLevel(levels) else nil
		local base = baseStands(warehouse)
		if warehouse and warehouse < moreFrom() then
			return `{base} display stands`
		end
		return `{base + math.floor(at * def.step)} display stands`
	elseif id == "lights" then
		return if at == 0 then "Income ×1.00" else string.format("Income ×%.2f", (1 + def.step) ^ at)
	elseif id == "engine" then
		return if at == 0 then "Stock engine" else `Top speed +{percent(def.step * at)}`
	elseif id == "danny" then
		return if at == 0 then "Danny's own pace" else `Danny walks {percent(def.step * at)} faster`
	end
	return `Level {at}`
end

function UpgradeRules.rows(levels: any, money: number?): { Row }
	local cash = if finite(money) then money :: number else 0
	local list: { Row } = {}
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		if def then
			local level = UpgradeRules.level(levels, id)
			local price = UpgradeRules.price(id, level)
			local locked = if price then UpgradeRules.locked(levels, id) else nil
			table.insert(list, {
				id = id,
				name = def.name,
				icon = def.icon,
				level = level,
				max = def.max,
				now = UpgradeRules.effect(id, level, levels),
				next = if price then UpgradeRules.effect(id, level + 1, levels) else nil,
				price = price,
				can = price ~= nil and locked == nil and cash >= price,
				short = if price and cash < price then math.ceil(price - cash) else 0,
				locked = locked,
			})
		end
	end
	return list
end

-- ── The save ───────────────────────────────────────────────────────────────

function UpgradeRules.empty(): Levels
	return {}
end

function UpgradeRules.full(): Levels
	local out: Levels = {}
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		if def then
			out[id] = def.max
		end
	end
	return out
end

-- Saved levels, checked: only known ids with a whole level 1 … max (a fraction rounds down, more than max is max; 0,
-- a negative, NaN, a string or an unknown id is dropped). Never an error.
function UpgradeRules.clean(raw: any): Levels
	local out: Levels = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		if def then
			local level = clamp(def, raw[id])
			if level > 0 then
				out[id] = level
			end
		end
	end
	return out
end

-- The migration: a real save (money in it) written with the flag keeps its levels (cleaned); every other one (from
-- before 8.1, a new player's nil, a lock-only record) starts with none. 8.3: a real save written without the warehouse
-- level's flag (from before 8.3) had today's warehouse: its warehouse is level 4 (the upgrade's level 3), whatever else
-- it kept; one written with it keeps its own (none saved: the Garage). Running it again on what it gave gives the same.
function UpgradeRules.fromSave(saved: any): Levels
	if type(saved) ~= "table" or saved.money == nil then
		return UpgradeRules.empty()
	end
	local out = if saved[UpgradeRules.Flag] == true then UpgradeRules.clean(saved.sandboxUpgrades) else UpgradeRules.empty()
	if saved[UpgradeRules.WarehouseFlag] ~= true then
		local def = UpgradeRules.def("warehouse")
		if def then
			out.warehouse = math.max(out.warehouse or 0, math.min(3, def.max))
		end
	end
	return out
end

return UpgradeRules
