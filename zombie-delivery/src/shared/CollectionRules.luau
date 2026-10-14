--!strict
-- 8.0 SANDBOX, the collection's rules (design/sandbox/KONTRAKT.md "Collection"; the numbers are Config.Collection's).
-- Pure (no Roblox at its top level; tests/collection_test.luau). server/Collection.luau keeps the pieces and pays with
-- these; a client may use them to show a piece's rarity, its $ a minute and its price (the "Collection" remote's state
-- carries them too).
--
-- A piece (Entry) is one thing a move brought home: its furniture id (shared/FurnitureLooks.luau Items, the moves'
-- catalogue: its `value`), its colours (variant), its condition (0 … 1), its name, the display stand it stands on (nil:
-- in the stock) and when it came home (os.time).
--
--   CollectionRules.defOf(item)          the piece's furniture def (FurnitureLooks.Items) or nil (an id that left the
--                                        catalogue: worth $0)
--   CollectionRules.valueOf(entry)       its def's value ($), 0 without one
--   CollectionRules.rarityOf(def)        the tier's id: the def's own `rarity` when it is a tier (the collectibles), else
--                                        the rarest tier whose `min` its value reaches; tier(id) the tier (Config's),
--                                        tierOf(entry) the piece's
--   CollectionRules.broken(entry)        its condition is at or under BrokenAt
--   CollectionRules.income(entry, boost?)   $ a minute while it is on show: value × its tier's income × condition (0
--                                        broken) × boost (8.1: the owner's Showroom lights, CollectionRules.boost; 1
--                                        without one)
--   CollectionRules.sell(entry)          $ it sells for (a whole number): value × its tier's sell × condition, at least
--                                        $1; broken: scrap (value × Scrap, at least $1)
--   CollectionRules.view(entry, boost?)  a copy with rarity, value, income (× boost), price and broken for the client
--   CollectionRules.totals(entries, boost?)   { count, shown, value, income (the pieces on show, × boost), sell (all) }
--   CollectionRules.standsFor(profile)   the display stands a player has: the warehouse's start (Config.Warehouse.Stands,
--                                        else Config's Collection.Stands) + 8.1's More stands (profile.sandboxUpgrades,
--                                        shared/UpgradeRules.luau), never past Config.Warehouse.MaxStands; 8.3: their
--                                        warehouse level's (UpgradeRules.totalStands: 2 in a Garage … 32)
--   CollectionRules.boost(profile)       8.1: the income's × from the player's Showroom lights (1 without any)
--   The save (profile.collection = { entries = { Entry }, nextUid = n }):
--   CollectionRules.empty()              a new player's
--   CollectionRules.clean(raw)           a saved one checked, never trusted: entries with a uid (unique), a short item
--                                        id, variant, condition, name, a stand (a whole number, one piece a stand) and
--                                        got; MaxStock at most; nextUid past every uid's number
--   CollectionRules.fromSave(saved)      the migration (server/PlayerData.luau applySaved): only a real save (money in
--                                        it) written with the flag (SaveFlag) has a collection; an older one, a new
--                                        player or a lock-only record start with the empty one
--   CollectionRules.fitStands(collection, stands)   pieces on a stand past `stands` back to the stock (how many)
--   CollectionRules.uid(userId, n)       a piece's uid: "<userId>-<n>" (unique among every player's)

local Config = require(script.Parent.Config)
local FurnitureLooks = require(script.Parent.FurnitureLooks)
local UpgradeRules = require(script.Parent.UpgradeRules) -- 8.1: the stands and the lights a player bought

local CollectionRules = {}

export type Entry = {
	uid: string,
	item: string, -- Config.Furniture / FurnitureLooks id
	variant: number,
	condition: number, -- 0..1
	name: string,
	stand: number?, -- on show on this display stand of your warehouse (nil: in the stock)
	got: number, -- os.time() it came home
}
export type Saved = { entries: { Entry }, nextUid: number }
export type View = {
	uid: string,
	item: string,
	variant: number,
	condition: number,
	name: string,
	stand: number?,
	got: number,
	rarity: string,
	value: number,
	income: number, -- $ a minute on show (rounded to cents)
	price: number, -- $ it sells for now
	broken: boolean,
}
export type Totals = { count: number, shown: number, value: number, income: number, sell: number }

-- The flag a save carries once it holds a collection (server/PlayerData.luau writes it with every save).
CollectionRules.SaveFlag = "collectionKept"

local EPS = 1e-6
local MAX_ID = 40 -- an item id or a uid longer than this is no piece of ours
local MAX_NAME = 60
local MAX_VARIANT = 99
local MAX_STAND = 500 -- a stand index in a save past any warehouse (fitStands checks the real count)

local function tune()
	return Config.Collection
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- ── A piece's worth ────────────────────────────────────────────────────────

function CollectionRules.defOf(item: string): FurnitureLooks.ItemDef?
	return FurnitureLooks.Items[item]
end

function CollectionRules.valueOf(entry: { item: string }): number
	local def = CollectionRules.defOf(entry.item)
	return if def and finite(def.value) then math.max(0, def.value) else 0
end

function CollectionRules.tier(id: string): Config.CollectionTier
	return tune().Tiers[id] or tune().Tiers[tune().Order[1]]
end

-- The def's own rarity (a tier's id: the collectibles set it), else by its value: the rarest tier it reaches.
function CollectionRules.rarityOf(def: { value: number }?): string
	local tiers, order = tune().Tiers, tune().Order
	if not def then
		return order[1]
	end
	local own = (def :: any).rarity
	if type(own) == "string" and tiers[own] then
		return own
	end
	local value = if finite(def.value) then def.value else 0
	local best = order[1]
	for _, id in order do
		if value >= tiers[id].min then
			best = id
		end
	end
	return best
end

function CollectionRules.tierOf(entry: { item: string }): Config.CollectionTier
	return CollectionRules.tier(CollectionRules.rarityOf(CollectionRules.defOf(entry.item)))
end

local function condition(entry: { condition: number }): number
	return if finite(entry.condition) then math.clamp(entry.condition, 0, 1) else 0
end

function CollectionRules.broken(entry: { condition: number }): boolean
	return condition(entry) <= tune().BrokenAt + EPS
end

-- A boost as given (8.1: CollectionRules.boost's), 1 for none or junk.
local function boostOf(boost: number?): number
	return if finite(boost) and (boost :: number) > 0 then boost :: number else 1
end

-- $ a minute while it stands on show (0 when broken), × the owner's boost (8.1: the Showroom lights).
function CollectionRules.income(entry: { item: string, condition: number }, boost: number?): number
	if CollectionRules.broken(entry) then
		return 0
	end
	return CollectionRules.valueOf(entry) * CollectionRules.tierOf(entry).income * condition(entry) * boostOf(boost)
end

-- $ it sells for (a whole number, at least 1): its tier's share of its worth, scrap when broken.
function CollectionRules.sell(entry: { item: string, condition: number }): number
	local value = CollectionRules.valueOf(entry)
	local price = if CollectionRules.broken(entry)
		then value * tune().Scrap
		else value * CollectionRules.tierOf(entry).sell * condition(entry)
	return math.max(1, math.floor(price + 0.5))
end

-- A copy of the piece with what the client shows: its rarity, value, $ a minute on show (to the cent, × the boost),
-- price, broken.
function CollectionRules.view(entry: Entry, boost: number?): View
	return {
		uid = entry.uid,
		item = entry.item,
		variant = entry.variant,
		condition = entry.condition,
		name = entry.name,
		stand = entry.stand,
		got = entry.got,
		rarity = CollectionRules.rarityOf(CollectionRules.defOf(entry.item)),
		value = CollectionRules.valueOf(entry),
		income = math.floor(CollectionRules.income(entry, boost) * 100 + 0.5) / 100,
		price = CollectionRules.sell(entry),
		broken = CollectionRules.broken(entry),
	}
end

-- The pieces' count, how many stand on show, their value, the income of the ones on show (× the boost) and the price of
-- them all.
function CollectionRules.totals(entries: { Entry }, boost: number?): Totals
	local out: Totals = { count = 0, shown = 0, value = 0, income = 0, sell = 0 }
	for _, entry in entries do
		out.count += 1
		out.value += CollectionRules.valueOf(entry)
		out.sell += CollectionRules.sell(entry)
		if entry.stand ~= nil then
			out.shown += 1
			out.income += CollectionRules.income(entry, boost)
		end
	end
	return out
end

-- The upgrades' levels in a profile (profile.sandboxUpgrades), nil without any.
local function levelsOf(profile: any?): any
	return if type(profile) == "table" then profile.sandboxUpgrades else nil
end

-- The display stands a player has: the warehouse's start (Config.Warehouse.Stands), else Config.Collection.Stands;
-- 8.1: + the More stands bought (profile.sandboxUpgrades), never past the hall's Config.Warehouse.MaxStands (a start
-- over it stays as it is). 8.3: their warehouse level's big stands (Config.Warehouse.Levels: a new player's Garage 2 …
-- the Logistics Center 24) + the More stands' small ones from Config.Warehouse.MoreFrom on (UpgradeRules.totalStands);
-- without the levels in Config, as before.
function CollectionRules.standsFor(profile: any?): number
	local warehouse = (Config :: any).Warehouse
	if type(warehouse) == "table" and type(warehouse.Levels) == "table" and #warehouse.Levels > 0 then
		return UpgradeRules.totalStands(levelsOf(profile))
	end
	local stands = if type(warehouse) == "table" then warehouse.Stands else nil
	if not finite(stands) or stands < 1 then
		stands = tune().Stands
	end
	local base = math.floor(stands)
	local extra = UpgradeRules.extraStands(levelsOf(profile))
	if extra <= 0 then
		return base
	end
	local most = if type(warehouse) == "table" and finite(warehouse.MaxStands) then math.floor(warehouse.MaxStands) else base + UpgradeRules.mostStands()
	return math.min(base + extra, math.max(base, most))
end

-- 8.1: the stands' income × this for the player (their Showroom lights: shared/UpgradeRules.luau incomeBoost).
function CollectionRules.boost(profile: any?): number
	return UpgradeRules.incomeBoost(levelsOf(profile))
end

-- ── The save ───────────────────────────────────────────────────────────────

function CollectionRules.uid(userId: number, n: number): string
	return `{userId}-{n}`
end

-- The number at a uid's end (its place in the order they came home), 0 without one.
local function uidNumber(uid: string): number
	return tonumber(string.match(uid, "(%d+)$")) or 0
end

function CollectionRules.empty(): Saved
	return { entries = {}, nextUid = 1 }
end

local function shortString(value: any, most: number): boolean
	return type(value) == "string" and #value >= 1 and #value <= most
end

-- A saved collection, checked: never trusted, never an error. A piece without a uid or an item is dropped (a second
-- piece with a uid seen already too); the rest is mended (variant 1 … 99, condition 0 … 1, a name, got ≥ 0); a second
-- piece on one stand goes back to the stock; MaxStock pieces at most (the first ones); nextUid past every uid.
function CollectionRules.clean(raw: any): Saved
	local out = CollectionRules.empty()
	if type(raw) ~= "table" then
		return out
	end
	local list = raw.entries
	local seen: { [string]: boolean } = {}
	local stands: { [number]: boolean } = {}
	local top = 0
	if type(list) == "table" then
		for _, e in list do
			if #out.entries >= tune().MaxStock then
				break
			end
			if type(e) ~= "table" or not shortString(e.uid, MAX_ID) or seen[e.uid] or not shortString(e.item, MAX_ID) then
				continue
			end
			local def = CollectionRules.defOf(e.item)
			local variant = if finite(e.variant) then math.clamp(math.floor(e.variant), 1, MAX_VARIANT) else 1
			local stand: number? = nil
			if finite(e.stand) and e.stand == math.floor(e.stand) and e.stand >= 1 and e.stand <= MAX_STAND and not stands[e.stand] then
				stand = e.stand
				stands[e.stand] = true
			end
			local name = if shortString(e.name, MAX_NAME) then e.name elseif def then def.name else e.item
			seen[e.uid] = true
			top = math.max(top, uidNumber(e.uid))
			table.insert(out.entries, {
				uid = e.uid,
				item = e.item,
				variant = variant,
				condition = if finite(e.condition) then math.clamp(e.condition, 0, 1) else 0,
				name = name,
				stand = stand,
				got = if finite(e.got) then math.clamp(math.floor(e.got), 0, 2 ^ 40) else 0,
			})
		end
	end
	local nextUid = if finite(raw.nextUid) then math.floor(raw.nextUid) else 1
	out.nextUid = math.clamp(math.max(nextUid, top + 1), 1, 2 ^ 40)
	return out
end

-- The migration (server/PlayerData.luau applySaved): a real save (money in it) written with SaveFlag keeps its
-- collection (cleaned); every other one (from before 8.0, a new player's nil, a lock-only record) starts empty.
-- Running it again on what it gave (saved again) gives the same.
function CollectionRules.fromSave(saved: any): Saved
	if type(saved) ~= "table" or saved.money == nil or saved[CollectionRules.SaveFlag] ~= true then
		return CollectionRules.empty()
	end
	return CollectionRules.clean(saved.collection)
end

-- Pieces on a stand the warehouse does not have (past `stands`) back to the stock; returns how many.
function CollectionRules.fitStands(collection: Saved, stands: number): number
	local moved = 0
	for _, entry in collection.entries do
		local stand = entry.stand
		if stand ~= nil and (stand < 1 or stand > stands) then
			entry.stand = nil
			moved += 1
		end
	end
	return moved
end

return CollectionRules
