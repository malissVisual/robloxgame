--!strict
-- 8.1 SANDBOX, the upgrades' rules (Config.SandboxUpgrades): what each level costs and gives, the save's levels checked
-- and migrated, and the window's cards. Pure (no Roblox at its top level; tests/upgrades_test.luau): the server
-- (server/Upgrades.luau) decides every purchase with it, shared/CollectionRules.luau reads the stands and the lights
-- from it, shared/MoveHelperBrain.luau Danny's walk, client/UpgradeUi.luau draws its cards.
-- 10.4 THE UPGRADE TREE (Config.SandboxUpgrades' header): the upgrades are the nodes of one tree. The trunk is the
-- warehouse (its tiers 1 … 5), five branches grow from it (the collection hall, the showroom, runs, the crew, looks).
-- A node has ranks 1 … max; buying rank 1 needs its parents (`needs`: a parent at a rank) and every rank needs its
-- warehouse tier (`tiers`); a `soon` node is shown and never sold, the auction's while the Auction House is closed.
-- The effects every other system reads are UpgradeRules.effect(levels, key) (Config.SandboxUpgrades.Effects: the
-- hall's income, the showroom's stands and prices, the visitors, the run clock, the helpers …).
--
-- The levels (profile.sandboxUpgrades) are { [id]: rank }: a known node id, a whole rank 1 … its max (0 is not kept).
--   UpgradeRules.Order                  the node ids in the tree's order (Config.SandboxUpgrades.Order)
--   UpgradeRules.def(id)                its Config entry (nil: no such node; any type)
--   UpgradeRules.level(levels, id)      its rank in these levels: 0 … its max (0 for junk)
--   UpgradeRules.price(id, level)       what the rank after `level` costs (nil: at the top, or no such node)
--   UpgradeRules.warehouseLevel(levels) 8.3: the warehouse's level (1 … 5: the warehouse node's rank + 1,
--                                       Config.Warehouse.Levels; design/warehouse-levels/KONTRAKT.md): the tree's tier
--   UpgradeRules.totalStands(levels)    8.3: the collection hall's stands: their level's big stands + More hall stands'
--                                       small ones (from Config.Warehouse.MoreFrom on)
--   UpgradeRules.showStands(levels)     10.4: the showroom's stands: the level's own (Config.Showroom.Levels' Stands) +
--                                       the Showroom stands node's, never more than the level has room for (Most)
--   UpgradeRules.locked(levels, id)     why its next rank can't be bought now (nil: it can, with the money): "Comes
--                                       later" (soon), the Auction House closed, "Needs Hall spotlights 2" (a parent),
--                                       "Needs the Big Warehouse" (its tier)
--   UpgradeRules.needs(levels, id)      10.4: its requirements for the next rank as lines { text, ok } (the parents, the
--                                       tier): the details' checklist
--   UpgradeRules.status(levels, id, money?)  10.4: "max" (every rank), "buy" (the money buys the next), "short" (it
--                                       could be bought, the money is missing), "locked", "soon"
--   UpgradeRules.extraStands(levels)    the hall stands More hall stands adds (2 a rank; 8.3: counted from MoreFrom on)
--   UpgradeRules.mostStands()           the stands More hall stands adds at its top
--   UpgradeRules.incomeBoost(levels)    the hall's income × this (Hall spotlights: 1.1 a rank, compounding)
--   UpgradeRules.vanSpeed(levels)       the van's top speed × this (Van engine: + 5 % a rank)
--   UpgradeRules.dannySpeed(level)      Danny's walk × this for a training rank (any type: junk is 0)
--   UpgradeRules.effect(levels, key)    10.4: an effect's value for these levels (Config.SandboxUpgrades.Effects: its
--                                       base with no rank, every node feeding it added up by its mode, clamped):
--                                       "hallIncome", "rareIncome", "setBonus", "idleShare", "hallStands",
--                                       "showStands", "showPrice", "visitorRate", "vip", "auctionSpeed", "vanSpeed",
--                                       "runClock", "startKey", "truckSize", "lootLuck", "helperSlots", "dannySpeed",
--                                       "helperHealth", "helperSpeed", "reviveTime", "hospital", "wallPaint",
--                                       "signPaint", "tier"; an unknown key: 0
--   UpgradeRules.looks(levels)          10.4: the LOOKS owned { wall = RGB?, sign = RGB? } (the warehouse paints them)
--   UpgradeRules.words(id, level, levels?)   what that rank gives, in words ("Workshop · 4 stands", "14 hall stands"
--                                       (with levels' warehouse), "Income ×1.21", "Top speed +10%", "Walks 20%
--                                       faster", "Run clock +16%"; rank 0: the start)
--   UpgradeRules.rows(levels, money)    the tree's nodes as rows ({ Row }, in Order): the rank, its top, now and next in
--                                       words, the next price, whether the money buys it (and if not, how much is
--                                       missing), why it is locked, 10.4: its branch, place, status, blurb, checklist
--   UpgradeRules.branches()             10.4: Config's branches (the window's lanes and colours), branch(id) one
--   UpgradeRules.links()                10.4: the tree's lines { { from, to, rank, tier } }: from a parent node (rank:
--                                       the rank it needs) or, for a node with none, from the trunk's tier it needs
--                                       (from = "warehouse", tier its tier)
--   UpgradeRules.trunkAt(tier)          10.4: the trunk tile of a tier's place in the grid { column, row }
--   UpgradeRules.total(), cost(levels)  10.4: the whole tree's price (what can be bought); what these levels cost
--   UpgradeRules.money(n)               "$1,234"
--   The save:
--   UpgradeRules.empty()                a new player's (none bought)
--   UpgradeRules.full()                 every node at its top (the admin's MAX UPGRADES; never a soon one)
--   UpgradeRules.offered(id)            10.4: the tree sells it, now or once its needs are met (not a soon one, nor the
--                                       auction's while the Auction House is shut)
--   UpgradeRules.clean(raw)             saved levels checked, never trusted: known ids, whole ranks 1 … max
--   UpgradeRules.fromSave(saved)        the migration (server/PlayerData.luau applySaved): only a real save (money in
--                                       it) written with the flag (Config.SandboxUpgrades.Flag) has upgrades; an
--                                       older one, a new player or a lock-only record start with none. 8.3: a real
--                                       save without WarehouseFlag (from before 8.3) had today's warehouse: level 4.
--                                       10.4: a real save without TreeFlag (8.1 – 10.3: the five tracks) maps each
--                                       track onto its node (Migrate: its level the node's rank, nothing lost); the
--                                       tree's ranks kept in `rewards` ("up:<id>:<rank>", mirror) come back when the
--                                       save's own lost them (an older server wrote it again)
--   UpgradeRules.mirror(rewards, levels)  10.4: the tree's own nodes (not the five tracks an older server keeps) as
--                                       `rewards`' short keys "up:<id>:<rank>" (the stale ones cleared)
--   UpgradeRules.Flag, TreeFlag         the flags
--   UpgradeRules.WarehouseFlag          8.3: the warehouse level's (Config.SandboxUpgrades.WarehouseFlag)
--   UpgradeRules.warehouseKey(levels)   8.3: the short key of `rewards` keeping the level through an older server
--                                       ("warehouse:<k>"; server/PlayerData.luau writes it, fromSave reads it back
--                                       when the flag is gone: keptWarehouse(rewards))
--   UpgradeRules.WarehouseAttribute     8.3: the player attribute with their warehouse level (server/Upgrades.luau)

local Config = require(script.Parent.Config)

local UpgradeRules = {}

export type Levels = { [string]: number }
export type Need = { text: string, ok: boolean }
export type Row = {
	id: string,
	name: string,
	icon: string,
	level: number,
	max: number,
	now: string, -- what the rank you have gives
	next: string?, -- what the next rank gives (nil: at the top)
	price: number?, -- the next rank's price (nil: at the top)
	can: boolean, -- the money buys the next rank (and it is not locked)
	short: number, -- the money missing for it (0: none)
	locked: string?, -- 8.3: why it can't be bought now (nil: it can)
	-- 10.4 the tree
	branch: string,
	at: { number },
	status: string, -- "max" | "buy" | "short" | "locked" | "soon"
	blurb: string,
	needs: { Need }, -- the next rank's requirements (none at the top)
	tier: number, -- the warehouse tier the next rank needs (1 at the top)
	soon: boolean,
}
export type Link = { from: string, to: string, rank: number, tier: number }

local function tune(): any
	return Config.SandboxUpgrades
end

UpgradeRules.Order = tune().Order :: { string }
UpgradeRules.Flag = tune().Flag :: string
UpgradeRules.TreeFlag = (tune().TreeFlag or "upgradeTreeKept") :: string
UpgradeRules.WarehouseFlag = (tune().WarehouseFlag or "warehouseLevelKept") :: string
UpgradeRules.WarehouseAttribute = (tune().WarehouseAttribute or "WarehouseLevel") :: string

local MIRROR = "up:" -- 10.4: rewards' short keys of the tree's own nodes

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

-- ── The warehouse and its stands ───────────────────────────────────────────

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

function UpgradeRules.mostStands(): number
	local def = UpgradeRules.def("stands")
	return if def then math.floor(def.max * def.step) else 0
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

-- 10.4: a warehouse level's showroom (Config.Showroom.Levels: the stands it comes with, the most it holds).
local function showroomOf(level: number): (number, number)
	local show = (Config :: any).Showroom
	local list = if type(show) == "table" then show.Levels else nil
	local def = if type(list) == "table" then list[math.clamp(level, 1, math.max(1, #list))] else nil
	if type(def) ~= "table" then
		return 0, 0
	end
	local own = if finite(def.Stands) then math.max(0, math.floor(def.Stands)) else 0
	local most = if finite(def.Most) then math.max(own, math.floor(def.Most)) else own
	return own, most
end

-- ── The effects ────────────────────────────────────────────────────────────

-- every node feeding each effect key (built once)
local feeding: { [string]: { string } }? = nil
local function feeders(key: string): { string }
	local map = feeding
	if not map then
		local fresh: { [string]: { string } } = {}
		for _, id in UpgradeRules.Order do
			local def = UpgradeRules.def(id)
			local effect = if def then def.effect else nil
			if type(effect) == "string" then
				fresh[effect] = fresh[effect] or {}
				table.insert(fresh[effect], id)
			end
		end
		feeding = fresh
		map = fresh
	end
	return (map :: { [string]: { string } })[key] or {}
end

function UpgradeRules.effect(levels: any, key: any): number
	local spec = if type(key) == "string" then tune().Effects[key] else nil
	if type(spec) ~= "table" then
		return 0
	end
	local value = spec.base
	for _, id in feeders(key) do
		local def = UpgradeRules.def(id) :: Config.SandboxUpgradeDef
		local rank = UpgradeRules.level(levels, id)
		if rank > 0 then
			if spec.mode == "pow" then
				value *= (1 + def.step) ^ rank
			else
				value += def.step * rank
			end
		end
	end
	if key == "tier" then
		value = math.min(value, math.max(1, #warehouseDefs()))
	end
	if finite(spec.min) then
		value = math.max(value, spec.min)
	end
	if finite(spec.max) then
		value = math.min(value, spec.max)
	end
	return value
end

function UpgradeRules.incomeBoost(levels: any): number
	return UpgradeRules.effect(levels, "hallIncome")
end

function UpgradeRules.vanSpeed(levels: any): number
	return UpgradeRules.effect(levels, "vanSpeed")
end

function UpgradeRules.dannySpeed(level: any): number
	local def = UpgradeRules.def("danny")
	if not def then
		return 1
	end
	return 1 + def.step * clamp(def, level)
end

function UpgradeRules.showStands(levels: any): number
	local own, most = showroomOf(UpgradeRules.warehouseLevel(levels))
	return math.clamp(own + math.floor(UpgradeRules.effect(levels, "showStands")), 0, most)
end

function UpgradeRules.looks(levels: any): { wall: { number }?, sign: { number }? }
	local out: { wall: { number }?, sign: { number }? } = {}
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		local look = if def then def.look else nil
		if look and UpgradeRules.level(levels, id) >= 1 then
			if look.kind == "wall" then
				out.wall = look.color
			elseif look.kind == "sign" then
				out.sign = look.color
			end
		end
	end
	return out
end

-- ── The tree: requirements ─────────────────────────────────────────────────

-- The warehouse tier rank `rank` of a node needs (its `tiers`; none: 1).
local function tierFor(def: Config.SandboxUpgradeDef, rank: number): number
	local tiers = def.tiers
	local need = if tiers then tiers[math.clamp(rank, 1, math.max(1, #tiers))] else nil
	return if finite(need) then math.floor(need :: number) else 1
end

local function tierName(tier: number): string
	local def = warehouseDefs()[tier]
	return if def then `the {def.name}` else `warehouse tier {tier}`
end

local function auctionOpen(): boolean
	local auction = (Config :: any).Auction
	return type(auction) == "table" and auction.On == true
end

-- The parents in a stable order (Order's).
local function parentsOf(def: Config.SandboxUpgradeDef): { string }
	local out: { string } = {}
	local needs = def.needs
	if needs then
		for _, id in UpgradeRules.Order do
			if needs[id] ~= nil then
				table.insert(out, id)
			end
		end
	end
	return out
end

function UpgradeRules.needs(levels: any, id: string): { Need }
	local def = UpgradeRules.def(id)
	local out: { Need } = {}
	if not def then
		return out
	end
	local rank = UpgradeRules.level(levels, id)
	if rank >= def.max then
		return out
	end
	if rank == 0 then
		for _, parent in parentsOf(def) do
			local pdef = UpgradeRules.def(parent)
			local want = math.max(1, math.floor((def.needs :: any)[parent]))
			local have = UpgradeRules.level(levels, parent)
			local name = if pdef then pdef.name else parent
			table.insert(out, { text = if want > 1 then `{name} rank {want}` else name, ok = have >= want })
		end
	end
	local tier = tierFor(def, rank + 1)
	if tier > 1 and id ~= "warehouse" then
		local name = tierName(tier)
		table.insert(out, { text = (string.gsub(name, "^the ", "The ")), ok = UpgradeRules.warehouseLevel(levels) >= tier })
	end
	return out
end

function UpgradeRules.locked(levels: any, id: string): string?
	local def = UpgradeRules.def(id)
	if not def then
		return nil
	end
	if def.soon then
		return def.soon
	end
	if def.auction and not auctionOpen() then
		return "The Auction House opens later"
	end
	local rank = UpgradeRules.level(levels, id)
	if rank >= def.max then
		return nil
	end
	if rank == 0 then
		for _, parent in parentsOf(def) do
			local want = math.max(1, math.floor((def.needs :: any)[parent]))
			if UpgradeRules.level(levels, parent) < want then
				local pdef = UpgradeRules.def(parent)
				local name = if pdef then pdef.name else parent
				return if want > 1 then `Needs {name} rank {want}` else `Needs {name}`
			end
		end
	end
	local tier = tierFor(def, rank + 1)
	if id ~= "warehouse" and UpgradeRules.warehouseLevel(levels) < tier then
		return `Needs {tierName(tier)}`
	end
	return nil
end

function UpgradeRules.status(levels: any, id: string, money: number?): string
	local def = UpgradeRules.def(id)
	if not def then
		return "locked"
	end
	if def.soon then
		return "soon"
	end
	local rank = UpgradeRules.level(levels, id)
	if rank >= def.max then
		return "max"
	end
	if UpgradeRules.locked(levels, id) then
		return "locked"
	end
	local price = UpgradeRules.price(id, rank) or 0
	return if finite(money) and (money :: number) >= price then "buy" else "short"
end

-- ── Words ──────────────────────────────────────────────────────────────────

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

function UpgradeRules.words(id: string, level: number, levels: any?): string
	local def = UpgradeRules.def(id)
	if not def then
		return ""
	end
	local at = clamp(def, level)
	local amount = def.step * at
	local effect = def.effect
	if id == "warehouse" then
		local n = math.clamp(1 + at, 1, math.max(1, #warehouseDefs()))
		local building = warehouseDefs()[n]
		local stands = baseStands(n)
		return `{if building then building.name else `Level {n}`} · {stands} {if stands == 1 then "stand" else "stands"}`
	elseif id == "stands" then
		-- (the More hall stands' small stands on the warehouse's own: the levels' warehouse; none given, the start's)
		local warehouse = if type(levels) == "table" then UpgradeRules.warehouseLevel(levels) else nil
		local base = baseStands(warehouse)
		if warehouse and warehouse < moreFrom() then
			return `{base} hall stands`
		end
		return `{base + math.floor(amount)} hall stands`
	elseif effect == "hallIncome" then
		return if at == 0 then "Income ×1.00" else string.format("Income ×%.2f", (1 + def.step) ^ at)
	elseif effect == "vanSpeed" then
		return if at == 0 then "Stock engine" else `Top speed +{percent(amount)}`
	elseif effect == "dannySpeed" then
		return if at == 0 then "Danny's own pace" else `Danny walks {percent(amount)} faster`
	end
	if at == 0 then
		return "Not bought yet"
	end
	if effect == "idleShare" then
		local share = (Config.Collection :: any).IdleShare or 0
		return `Pays {percent(math.min(1, share + amount))} while idle`
	elseif effect == "rareIncome" then
		return `Epic & Legendary +{percent(amount)}`
	elseif effect == "setBonus" then
		return `+{percent(amount)} a room set`
	elseif effect == "showStands" then
		return `+{math.floor(amount)} showroom {if amount == 1 then "stand" else "stands"}`
	elseif effect == "visitorRate" then
		return `Visitors ×{string.format("%.1f", 1 + amount)}`
	elseif effect == "showPrice" then
		return `Showroom prices +{percent(amount)}`
	elseif effect == "vip" then
		return "VIP buyers visit"
	elseif effect == "auctionSpeed" then
		return "Your lots first"
	elseif effect == "runClock" then
		return `Run clock +{percent(amount)}`
	elseif effect == "startKey" then
		return "Start with a key"
	elseif effect == "truckSize" then
		return `Truck room +{percent(amount)}`
	elseif effect == "lootLuck" then
		return `Rarer loot +{percent(amount)}`
	elseif effect == "helperSlots" then
		return `{1 + math.floor(amount)} helpers a run`
	elseif effect == "helperHealth" then
		return `Helpers' health +{percent(amount)}`
	elseif effect == "reviveTime" then
		return `Revive {percent(-amount)} faster`
	elseif effect == "helperSpeed" then
		return `Helpers walk {percent(amount)} faster`
	elseif effect == "hospital" then
		return `Hospital {percent(-amount)} shorter`
	elseif effect == "wallPaint" or effect == "signPaint" then
		return "Owned · on your warehouse"
	end
	return `Rank {at}`
end

-- (8.1 – 10.3's name for it: the window's lines; 10.4 the words)
UpgradeRules.effectWords = UpgradeRules.words

-- ── The tree: rows, branches, lines ────────────────────────────────────────

function UpgradeRules.branches(): { Config.UpgradeBranch }
	return tune().Branches
end

function UpgradeRules.branch(id: string): Config.UpgradeBranch?
	for _, b in tune().Branches do
		if b.id == id then
			return b
		end
	end
	return nil
end

function UpgradeRules.trunkAt(tier: number): { number }
	local def = UpgradeRules.def("warehouse")
	local at = if def and def.at then def.at else { 1, tune().Grid.TrunkRow }
	return { at[1] + 2 * (math.max(1, math.floor(tier)) - 1), at[2] }
end

function UpgradeRules.links(): { Link }
	local out: { Link } = {}
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		if def and id ~= "warehouse" then
			local parents = parentsOf(def)
			for _, parent in parents do
				table.insert(out, { from = parent, to = id, rank = math.max(1, math.floor((def.needs :: any)[parent])), tier = 0 })
			end
			if #parents == 0 then
				table.insert(out, { from = "warehouse", to = id, rank = 0, tier = tierFor(def, 1) })
			end
		end
	end
	return out
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
				now = UpgradeRules.words(id, level, levels),
				next = if price then UpgradeRules.words(id, level + 1, levels) else nil,
				price = price,
				can = price ~= nil and locked == nil and cash >= price,
				short = if price and cash < price then math.ceil(price - cash) else 0,
				locked = locked,
				branch = def.branch or "warehouse",
				at = def.at or { 1, 1 },
				status = UpgradeRules.status(levels, id, cash),
				blurb = def.blurb or "",
				needs = UpgradeRules.needs(levels, id),
				tier = if price then tierFor(def, level + 1) else 1,
				soon = def.soon ~= nil,
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
		if def and not def.soon then
			out[id] = def.max
		end
	end
	return out
end

function UpgradeRules.offered(id: string): boolean
	local def = UpgradeRules.def(id)
	return def ~= nil and not def.soon and not (def.auction and not auctionOpen())
end

function UpgradeRules.total(): number
	local sum = 0
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		if def and not def.soon then
			for n = 1, def.max do
				sum += def.prices[n] or 0
			end
		end
	end
	return sum
end

function UpgradeRules.cost(levels: any): number
	local sum = 0
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		if def then
			for n = 1, UpgradeRules.level(levels, id) do
				sum += def.prices[n] or 0
			end
		end
	end
	return sum
end

-- Saved levels, checked: only known ids with a whole rank 1 … max (a fraction rounds down, more than max is max; 0,
-- a negative, NaN, a string or an unknown id is dropped; 10.4: a soon node is never owned). Never an error.
function UpgradeRules.clean(raw: any): Levels
	local out: Levels = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		if def and not def.soon then
			local level = clamp(def, raw[id])
			if level > 0 then
				out[id] = level
			end
		end
	end
	return out
end

-- 10.4: the five tracks of 8.1 – 10.3 onto the tree's nodes (Config.SandboxUpgrades.Migrate: a track's level is its
-- node's rank).
local function migrate(raw: any): Levels
	local out: Levels = {}
	if type(raw) ~= "table" then
		return out
	end
	for old, node in tune().Migrate :: { [string]: string } do
		local level = raw[old]
		if finite(level) and level >= 1 then
			out[node] = math.max(out[node] or 0, math.floor(level))
		end
	end
	return out
end

-- The nodes the five tracks are (an older server keeps those in sandboxUpgrades itself).
local function legacy(id: string): boolean
	for _, node in tune().Migrate :: { [string]: string } do
		if node == id then
			return true
		end
	end
	return false
end

-- 10.4: the tree's ranks kept in `rewards` ("up:<id>:<rank>"), nil for none.
local function mirrored(rewards: any): Levels
	local out: Levels = {}
	if type(rewards) ~= "table" then
		return out
	end
	for key, on in rewards do
		if on == true and type(key) == "string" and string.sub(key, 1, #MIRROR) == MIRROR then
			local id, rank = string.match(string.sub(key, #MIRROR + 1), "^(%w+):(%d+)$")
			local def = if id then UpgradeRules.def(id) else nil
			local n = tonumber(rank)
			if id and def and n and not legacy(id) then
				out[id] = math.max(out[id] or 0, clamp(def, n))
			end
		end
	end
	return out
end

-- The migration: a real save (money in it) written with the flag keeps its levels (cleaned); every other one (from
-- before 8.1, a new player's nil, a lock-only record) starts with none. 8.3: a real save written without the warehouse
-- level's flag (from before 8.3) had today's warehouse: its warehouse is level 4 (the upgrade's level 3), whatever else
-- it kept; one written with it keeps its own (none saved: the Garage). 10.4: one written without the tree's flag had
-- the five tracks: each is its node now (Migrate); the tree's own nodes an older server dropped come back from the
-- mirror in `rewards` (the higher rank of the two). Running it again on what it gave gives the same.
function UpgradeRules.fromSave(saved: any): Levels
	if type(saved) ~= "table" or saved.money == nil then
		return UpgradeRules.empty()
	end
	local out = UpgradeRules.empty()
	if saved[UpgradeRules.Flag] == true then
		out = if saved[UpgradeRules.TreeFlag] == true then UpgradeRules.clean(saved.sandboxUpgrades) else UpgradeRules.clean(migrate(saved.sandboxUpgrades))
	end
	for id, rank in mirrored(saved.rewards) do
		if rank > (out[id] or 0) then
			out[id] = rank
		end
	end
	if saved[UpgradeRules.WarehouseFlag] ~= true then
		local def = UpgradeRules.def("warehouse")
		if def then
			-- (a save an older server wrote again lost the level and its flag, but kept `rewards`' short keys: the level
			-- PlayerData writes there too, "warehouse:<k>", is its own; none: a save from before 8.3, level 4)
			local kept = UpgradeRules.keptWarehouse(saved.rewards)
			if kept and kept > 0 then
				out.warehouse = kept
			elseif kept then
				(out :: any).warehouse = nil -- (the Garage: none saved)
			else
				out.warehouse = math.max(out.warehouse or 0, math.min(3, def.max))
			end
		end
	end
	return UpgradeRules.clean(out)
end

function UpgradeRules.mirror(rewards: { [any]: any }, levels: any)
	local stale: { string } = {}
	for key in rewards do
		if type(key) == "string" and string.sub(key, 1, #MIRROR) == MIRROR then
			table.insert(stale, key)
		end
	end
	for _, key in stale do
		rewards[key] = nil
	end
	for _, id in UpgradeRules.Order do
		local rank = UpgradeRules.level(levels, id)
		if rank > 0 and not legacy(id) then
			rewards[`{MIRROR}{id}:{rank}`] = true
		end
	end
end

-- 8.3: the warehouse level an older server kept in a save's `rewards` ("warehouse:<k>", PlayerData's save: its upgrade
-- level k, 0 the Garage); nil: none there.
function UpgradeRules.keptWarehouse(rewards: any): number?
	if type(rewards) ~= "table" then
		return nil
	end
	local def = UpgradeRules.def("warehouse")
	local best: number? = nil
	for key, on in rewards do
		if on == true and type(key) == "string" and string.sub(key, 1, 10) == "warehouse:" then
			local k = tonumber(string.sub(key, 11))
			if k and k == math.floor(k) and k >= 0 and (def == nil or k <= def.max) then
				best = math.max(best or 0, k)
			end
		end
	end
	return best
end

-- 8.3: the `rewards` key that keeps a warehouse level through an older server ("warehouse:<k>", k its upgrade level).
function UpgradeRules.warehouseKey(levels: any): string
	return `warehouse:{UpgradeRules.level(levels, "warehouse")}`
end

return UpgradeRules
