--!strict
-- 8.1 SANDBOX, the upgrades' rules (Config.SandboxUpgrades): what each level costs and gives, the save's levels checked
-- and migrated, and the window's cards. Pure (no Roblox at its top level; tests/upgrades_test.luau): the server
-- (server/Upgrades.luau) decides every purchase with it, shared/CollectionRules.luau reads the stands and the lights
-- from it, shared/MoveHelperBrain.luau Danny's walk, client/UpgradeUi.luau draws its cards.
-- 8.3: the first card is the warehouse's level ("warehouse": shared/WarehouseLevels.luau, Config.WarehouseLevels): its
-- level is the warehouse level itself (Start … 5: a level of its own start, `start`, instead of 0); 8.1's More stands
-- (+2 small stands a level) is gone into it.
--
-- The levels (profile.sandboxUpgrades) are { [id]: level }: a known id, a whole level over its start … its max (the
-- start is not kept: 0, the warehouse's Start).
--   UpgradeRules.Order                  the ids in the window's order (Config.SandboxUpgrades.Order)
--   UpgradeRules.def(id)                its Config entry (nil: no such upgrade; any type; "warehouse":
--                                       WarehouseLevels.card())
--   UpgradeRules.level(levels, id)      its level in these levels: its start (0; the warehouse's Start) … its max (the
--                                       start for junk)
--   UpgradeRules.price(id, level)       what the level after `level` costs (nil: at the top, or no such upgrade)
--   UpgradeRules.warehouseLevel(levels) 8.3: the warehouse's level (1 … 5)
--   UpgradeRules.stands(levels)         8.3: the display stands that level has (2 … 20)
--   UpgradeRules.incomeBoost(levels)    the stands' income × this (Showroom lights: 1.1 a level, compounding)
--   UpgradeRules.vanSpeed(levels)       the van's top speed × this (Van engine: + 5 % a level)
--   UpgradeRules.dannySpeed(level)      Danny's walk × this for a training level (any type: junk is 0)
--   UpgradeRules.effect(id, level)      what that level gives, in words ("Level 2 · Workshop · 4 stands", "Income ×1.21",
--                                       "Top speed +10%", "Walks 20% faster"; level 0: the start)
--   UpgradeRules.rows(levels, money)    the window's cards ({ Row }, in Order): the level, its top, now and next in
--                                       words (the warehouse's next with its size: "Level 3 · Warehouse · 58×42 · 8
--                                       stands"), the next price, whether the money buys it (and if not, how much is
--                                       missing)
--   UpgradeRules.money(n)               "$1,234"
--   The save:
--   UpgradeRules.empty()                a new player's (none bought)
--   UpgradeRules.full()                 every upgrade at its top (the admin's MAX UPGRADES)
--   UpgradeRules.clean(raw)             saved levels checked, never trusted: known ids, whole levels over the start …
--                                       max
--   UpgradeRules.fromSave(saved)        the migration (server/PlayerData.luau applySaved): only a real save (money in
--                                       it) written with the flag (Config.SandboxUpgrades.Flag) has upgrades; an
--                                       older one, a new player or a lock-only record start with none. 8.3: a real
--                                       save without the warehouse's flag (WarehouseLevels.Flag, written with every
--                                       save from now on) is from before the levels: its warehouse starts at
--                                       WarehouseLevels.migrate's level (every stand it had, every piece on show; at
--                                       least level 4), once
--   UpgradeRules.Flag                   that flag; UpgradeRules.WarehouseFlag the warehouse's

local Config = require(script.Parent.Config)
local WarehouseLevels = require(script.Parent.WarehouseLevels) -- 8.3: the warehouse's levels (the "warehouse" card)

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
	can: boolean, -- the money buys the next level
	short: number, -- the money missing for it (0: none)
}

local function tune(): any
	return Config.SandboxUpgrades
end

UpgradeRules.Order = tune().Order :: { string }
UpgradeRules.Flag = tune().Flag :: string
UpgradeRules.WarehouseFlag = WarehouseLevels.Flag

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

function UpgradeRules.def(id: any): Config.SandboxUpgradeDef?
	if type(id) ~= "string" or #id > 32 then
		return nil
	end
	if id == "warehouse" then
		return WarehouseLevels.card()
	end
	return tune().List[id]
end

-- A level of this upgrade: its start (0; the warehouse's Start) … its max, junk its start.
local function clamp(def: Config.SandboxUpgradeDef, level: any): number
	local start = def.start or 0
	if not finite(level) then
		return start
	end
	return math.clamp(math.floor(level), start, def.max)
end

function UpgradeRules.level(levels: any, id: string): number
	local def = UpgradeRules.def(id)
	if not def then
		return 0
	end
	return clamp(def, if type(levels) == "table" then levels[id] else nil)
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

-- 8.3: the warehouse's level (Start … 5) and the display stands it has.
function UpgradeRules.warehouseLevel(levels: any): number
	return UpgradeRules.level(levels, "warehouse")
end

function UpgradeRules.stands(levels: any): number
	return WarehouseLevels.stands(UpgradeRules.warehouseLevel(levels))
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

function UpgradeRules.effect(id: string, level: number): string
	local def = UpgradeRules.def(id)
	if not def then
		return ""
	end
	local at = clamp(def, level)
	if id == "warehouse" then
		return WarehouseLevels.summary(at)
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
			table.insert(list, {
				id = id,
				name = def.name,
				icon = def.icon,
				level = level,
				max = def.max,
				now = UpgradeRules.effect(id, level),
				next = if not price then nil elseif id == "warehouse" then WarehouseLevels.summary(level + 1, true) else UpgradeRules.effect(id, level + 1),
				price = price,
				can = price ~= nil and cash >= price,
				short = if price and cash < price then math.ceil(price - cash) else 0,
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

-- Saved levels, checked: only known ids with a whole level over the start … max (a fraction rounds down, more than max
-- is max; the start, under it, NaN, a string or an unknown id is dropped). Never an error.
function UpgradeRules.clean(raw: any): Levels
	local out: Levels = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		if def then
			local level = clamp(def, raw[id])
			if level > (def.start or 0) then
				out[id] = level
			end
		end
	end
	return out
end

-- The migration: a real save (money in it) written with the flag keeps its levels (cleaned); every other one (from
-- before 8.1, a new player's nil, a lock-only record) starts with none. 8.3: a real save without the warehouse's flag
-- (from before the levels, whatever else it has) gets its warehouse's level once: WarehouseLevels.migrate (its More
-- stands are gone into it). Running it again on what it gave (saved again with both flags) gives the same.
function UpgradeRules.fromSave(saved: any): Levels
	if type(saved) ~= "table" or saved.money == nil then
		return UpgradeRules.empty()
	end
	local levels = if saved[UpgradeRules.Flag] == true then UpgradeRules.clean(saved.sandboxUpgrades) else UpgradeRules.empty()
	local migrated = WarehouseLevels.migrate(saved)
	if migrated and migrated > WarehouseLevels.Start then
		levels.warehouse = migrated
	elseif migrated then
		levels.warehouse = nil :: any -- (the start: not kept)
	end
	return levels
end

return UpgradeRules
