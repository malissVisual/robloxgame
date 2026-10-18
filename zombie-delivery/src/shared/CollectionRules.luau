--!strict
-- 8.0 SANDBOX, the collection's rules (design/sandbox/KONTRAKT.md "Collection"; the numbers are Config.Collection's).
-- Pure (no Roblox at its top level; tests/collection_test.luau). server/Collection.luau keeps the pieces and pays with
-- these; a client may use them to show a piece's rarity, its $ a minute and its price (the "Collection" remote's state
-- carries them too).
--
-- A piece (Entry) is one thing a move brought home: its furniture id (shared/FurnitureLooks.luau Items, the moves'
-- catalogue: its `value`), its colours (variant), its condition (0 … 1), its name, the display stand it stands on (nil:
-- in the stock) and when it came home (os.time). 8.7: a piece on show may carry a FOR SALE sign: its price (`sale`, a
-- whole number of dollars; server/PlayerTrade.luau sets it, shared/PlayerTradeRules.luau has its bounds), the price any
-- other player may buy it for while it stands there; it goes when the piece leaves its stand.
--
--   CollectionRules.defOf(item)          the piece's furniture def (FurnitureLooks.Items) or nil (an id that left the
--                                        catalogue: worth $0)
--   CollectionRules.valueOf(entry)       its def's value ($), 0 without one; 9.x loot: × lift for its rarity (a whole
--                                        number of $; its item's own rarity: the def's value as before)
--   CollectionRules.rarityOf(def)        the tier's id: the def's own `rarity` when it is a tier (the collectibles), else
--                                        the rarest tier whose `min` its value reaches; tier(id) the tier (Config's),
--                                        tierOf(entry) the piece's (9.x loot: its own rarity, pieceRarity)
--   9.x loot (Config.Loot, shared/LootRules.luau, server/Loot.luau): a piece's rarity is the server's roll when its house
--   was made, kept with the piece (Entry.rarity); a piece without one (every piece before 9.x) is its item's own:
--   CollectionRules.pieceRarity(entry)   the piece's rarity: its `rarity` when that is a tier, else its item's own
--   CollectionRules.lift(own, rarity)    × the catalogue value of a piece of rarity `rarity` whose item's own is `own`:
--                                        Config.Loot.Lift a tier over, Drop a tier under (1: the same)
--   CollectionRules.keepRarity(item, r)  what the save keeps of a rarity: a tier's id other than the item's own, else nil
--                                        (the item's own needs nothing kept: it reads so without one)
--   CollectionRules.broken(entry)        its condition is at or under BrokenAt
--   CollectionRules.income(entry, boost?, market?)   $ a minute while it is on show: value × its tier's income ×
--                                        condition (0 broken) × boost (8.1: the owner's Showroom lights,
--                                        CollectionRules.boost; 1 without one) × the market's (8.3: shared/Market.luau's
--                                        View: a hot kind × Config.Market.HotIncome; none: 1)
--   CollectionRules.sell(entry, market?) $ it sells for (a whole number): value × its tier's sell × condition, at least
--                                        $1; broken: scrap (value × Scrap, at least $1); 8.3: with the market's View that
--                                        price through Market.price (hot × HotSell, cold × ColdSell, × the player's demand)
--   CollectionRules.view(entry, boost?, market?)   a copy with rarity, value, income (× boost, × the market's), price (the
--                                        market's), broken for the client; 8.3: base (the price without the market) and
--                                        market ("hot", "cold" or nil)
--   CollectionRules.totals(entries, boost?, market?)   { count, shown, value, income (the pieces on show, × boost, × the
--                                        market's), sell (all, each at the market's price alone) }
--   CollectionRules.standsFor(profile)   the display stands a player has: the warehouse's start (Config.Warehouse.Stands,
--                                        else Config's Collection.Stands) + 8.1's More stands (profile.sandboxUpgrades,
--                                        shared/UpgradeRules.luau), never past Config.Warehouse.MaxStands; 8.3: their
--                                        warehouse level's (UpgradeRules.totalStands: 2 in a Garage … 32)
--   CollectionRules.boost(profile)       8.1: the income's × from the player's Showroom lights (1 without any)
--   The save (profile.collection = { entries = { Entry }, nextUid = n }):
--   CollectionRules.empty()              a new player's
--   CollectionRules.clean(raw)           a saved one checked, never trusted: entries with a uid (unique), a short item
--                                        id, variant, condition, name, a stand (a whole number, one piece a stand) and
--                                        got; MaxStock at most; nextUid past every uid's number; 8.7: a sale (a whole
--                                        number 1 … 2^40, only on a piece on a stand: else none); 9.x loot: its rarity
--                                        (keepRarity: a tier's id other than its item's own, else none)
--   CollectionRules.fromSave(saved)      the migration (server/PlayerData.luau applySaved): only a real save (money in
--                                        it) written with the flag (SaveFlag) has a collection; an older one, a new
--                                        player or a lock-only record start with the empty one. 8.7: a piece's `sale` needs
--                                        no migration of its own: a piece without one is simply not for sale (a save from
--                                        before 8.7, or written again by an 8.2 – 8.6 server, whose clean drops the field it
--                                        does not know: the sign is lost there, nothing breaks). 9.x loot: a piece's
--                                        `rarity` the same way: none is its item's own (a save from before 9.x, or
--                                        written again by an older server: the piece reads as its own rarity there)
--   CollectionRules.fitStands(collection, stands, fits?)   pieces on a stand past `stands` back to the stock (how
--                                        many); 8.3: with fits(stand, item), a piece that no longer fits its stand too
--                                        (a warehouse level down: a small stand where a big one stood); 8.7: their FOR
--                                        SALE signs go with them
--   CollectionRules.saleOf(value)        8.7: a sign's price as the save keeps it: a whole number 1 … 2^40, else nil
--   CollectionRules.uid(userId, n)       a piece's uid: "<userId>-<n>" (unique among every player's)
-- 10.4 THE WAREHOUSE IN TWO (Config.Showroom): a stand is the collection HALL's (1 … standsFor: its pieces earn every
-- minute) or the SHOWROOM's (Config.Showroom.Base + 1 …: its pieces are on sale, they earn nothing a minute and sell
-- for more). A piece's `stand` is saved as before; which area it is in is its number's:
--   CollectionRules.ShowBase             Config.Showroom.Base (a showroom stand's number is past it); ShowFlag its flag
--   CollectionRules.area(stand)          "hall", "show" or nil (no stand); isShow(stand) a showroom stand's number?
--   CollectionRules.showStandsFor(profile)  the showroom stands a player has (shared/UpgradeRules.luau showStands: their
--                                        level's own and the tree's Showroom stands)
--   CollectionRules.open(profile, stand) does the player have that stand (a hall one 1 … standsFor, a showroom one
--                                        Base + 1 … Base + showStandsFor)?
--   CollectionRules.bonus(profile, entries?)  the hall's income multipliers: { all (Hall spotlights × the room sets'
--                                        bonus: setBonus × the sets of `entries` in the hall), rare (Collector's corner:
--                                        × an Epic or Legendary piece's), sets (how many) }; a Bonus goes wherever a
--                                        boost (a number) went: income, view, totals
--   CollectionRules.sets(entries, open?) the room sets in the hall: rooms (FurnitureLooks' room) with
--                                        Config.Collection.SetSize different items on hall stands (open(stand): the
--                                        stands the player has; nil: any), MaxSets at most
--   CollectionRules.showFactor(profile)  × a showroom piece's price: Config.Showroom.SellBonus × the tree's Sales pitch
--   sell / view / totals take that factor (`show`) too: a showroom piece's price is × it (its income is what it would
--                                        earn in the hall: the picker's $/min); totals' income counts the hall only
--   fitStands(collection, stands, fits?, show?)   + the showroom's: a piece on a showroom stand past Base + show goes
--                                        back to the stock (its sign with it)
--   fromSave(saved)                      + the showroom's migration: a real save written without Config.Showroom.Flag
--                                        (8.0 – 10.3) keeps every piece on its stand: the hall's, earning as before; its
--                                        FOR SALE sign comes down (a sign is the showroom's: clean keeps one only there)
-- 10.4 THE WAREHOUSE IN TWO (Config.Showroom): a stand is the collection HALL's (1 … standsFor: its pieces earn every
-- minute) or the SHOWROOM's (Config.Showroom.Base + 1 …: its pieces are on sale, they earn nothing a minute and sell
-- for more). A piece's `stand` is saved as before; which area it is in is its number's:
--   CollectionRules.ShowBase             Config.Showroom.Base (a showroom stand's number is past it)
--   CollectionRules.area(stand)          "hall", "show" or nil (no stand)
--   CollectionRules.isShow(stand)        a showroom stand's number?
--   CollectionRules.showStandsFor(profile)  the showroom stands a player has (shared/UpgradeRules.luau showStands: their
--                                        level's own and the tree's Showroom stands)
--   CollectionRules.open(profile, stand) does the player have that stand (a hall one 1 … standsFor, a showroom one
--                                        Base + 1 … Base + showStandsFor)?
--   CollectionRules.bonus(profile, entries?)  the hall's income multipliers: { all (Hall spotlights × the room sets'
--                                        bonus: setBonus × the sets of `entries` in the hall), rare (Collector's corner:
--                                        × an Epic or Legendary piece's), sets (how many) }; a Bonus goes wherever a
--                                        boost (a number) went: income, view, totals
--   CollectionRules.sets(entries, open?) the room sets in the hall: rooms (FurnitureLooks' room) with SetSize different
--                                        items on hall stands (open(stand): the stands the player has; nil: any)
--   CollectionRules.showFactor(profile)  × a showroom piece's price: Config.Showroom.SellBonus × the tree's Sales pitch
--   CollectionRules.income / sell / view / totals take that factor (`show`) too: a showroom piece's price is × it
--                                        (its income is what it would earn in the hall: the picker's $/min), totals'
--                                        income counts the hall's pieces only
--   CollectionRules.fitStands(collection, stands, fits?, show?)   + the showroom's: a piece on a showroom stand past
--                                        Base + show goes back to the stock (its sign with it)
--   CollectionRules.fromSave(saved)      + the showroom's migration: a real save written without Config.Showroom.Flag
--                                        (8.0 – 10.3) keeps every piece on its stand: the hall's, earning as before, and
--                                        its FOR SALE sign comes down (a sign is the showroom's); a showroom number in
--                                        it (none can be) back to the stock

local Config = require(script.Parent.Config)
local FurnitureLooks = require(script.Parent.FurnitureLooks)
local UpgradeRules = require(script.Parent.UpgradeRules) -- 8.1: the stands and the lights a player bought
local Market = require(script.Parent.Market) -- 8.3: the market (hot and cold kinds, the player's demand)

local CollectionRules = {}

export type Entry = {
	uid: string,
	item: string, -- Config.Furniture / FurnitureLooks id
	variant: number,
	condition: number, -- 0..1
	name: string,
	stand: number?, -- on show on this display stand of your warehouse (nil: in the stock)
	got: number, -- os.time() it came home
	sale: number?, -- 8.7: its FOR SALE sign's price ($; only while it is on show: server/PlayerTrade.luau)
	rarity: string?, -- 9.x loot: the server's roll when its house was made, when not its item's own (nil: its own)
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
	base: number, -- 8.3: $ it sells for without the market (Market.batch prices a bulk sale from it)
	market: string?, -- 8.3: "hot", "cold" or nil (Market.tag)
	sale: number?, -- 8.7: its FOR SALE sign's price (nil: none)
	area: string?, -- 10.4: "hall" or "show" (its stand's area; nil: in the stock)
}
export type Totals = { count: number, shown: number, value: number, income: number, sell: number }
-- 10.4: the hall's income multipliers (CollectionRules.bonus): all its pieces' (Hall spotlights, the room sets), an Epic
-- or Legendary piece's on top (Collector's corner), and how many room sets the hall holds
export type Bonus = { all: number, rare: number, sets: number }
export type Boost = number | Bonus

-- The flag a save carries once it holds a collection (server/PlayerData.luau writes it with every save).
CollectionRules.SaveFlag = "collectionKept"
-- 10.4: the showroom's (Config.Showroom): its stand numbers' base and the save's mark of the split.
CollectionRules.ShowBase = Config.Showroom.Base :: number
CollectionRules.ShowFlag = Config.Showroom.Flag :: string
-- 10.4: the showroom's (Config.Showroom): its stand numbers' base and the save's mark of the split.
CollectionRules.ShowBase = Config.Showroom.Base :: number
CollectionRules.ShowFlag = Config.Showroom.Flag :: string

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

-- ── 9.x loot: a piece's own rarity ─────────────────────────────────────────

local function isTier(id: any): boolean
	return type(id) == "string" and tune().Tiers[id] ~= nil
end

-- The piece's rarity: the server's roll kept with it (Entry.rarity) when it is a tier, else its item's own.
function CollectionRules.pieceRarity(entry: { item: string }): string
	local own = (entry :: any).rarity
	if isTier(own) then
		return own
	end
	return CollectionRules.rarityOf(CollectionRules.defOf(entry.item))
end

-- × the catalogue value of a piece of rarity `rarity` whose item's own rarity is `own`: Lift for every tier over it,
-- Drop for every tier under it (1: the same tier, or one that is no tier).
function CollectionRules.lift(own: string, rarity: string): number
	if not isTier(own) or not isTier(rarity) then
		return 1
	end
	local steps = CollectionRules.tier(rarity).rank - CollectionRules.tier(own).rank
	local loot = (Config :: any).Loot
	if steps == 0 or type(loot) ~= "table" then
		return 1
	end
	local per = if steps > 0 then loot.Lift else loot.Drop
	return if finite(per) and per > 0 then per ^ math.abs(steps) else 1
end

-- What a save keeps of a piece's rarity: a tier's id that is not its item's own (nil: it reads as its own).
function CollectionRules.keepRarity(item: string, rarity: any): string?
	if not isTier(rarity) or rarity == CollectionRules.rarityOf(CollectionRules.defOf(item)) then
		return nil
	end
	return rarity
end

-- Its def's value ($), 0 without one; 9.x loot: × lift for the piece's rarity (a whole number of $; its item's own
-- rarity: the def's value as before).
function CollectionRules.valueOf(entry: { item: string }): number
	local def = CollectionRules.defOf(entry.item)
	local value = if def and finite(def.value) then math.max(0, def.value) else 0
	local own = (entry :: any).rarity
	if not def or not isTier(own) then
		return value
	end
	local lift = CollectionRules.lift(CollectionRules.rarityOf(def), own)
	return if lift == 1 then value else math.floor(value * lift + 0.5)
end

function CollectionRules.tierOf(entry: { item: string }): Config.CollectionTier
	return CollectionRules.tier(CollectionRules.pieceRarity(entry))
end

local function condition(entry: { condition: number }): number
	return if finite(entry.condition) then math.clamp(entry.condition, 0, 1) else 0
end

function CollectionRules.broken(entry: { condition: number }): boolean
	return condition(entry) <= tune().BrokenAt + EPS
end

-- A boost as given (8.1: CollectionRules.boost's), 1 for none or junk; 10.4: a Bonus (CollectionRules.bonus): all its
-- pieces' ×, an Epic or Legendary piece's rare × on top.
local function factorOf(entry: { item: string }, boost: Boost?): number
	if type(boost) == "table" then
		local all = if finite(boost.all) and boost.all > 0 then boost.all else 1
		local rare = if finite(boost.rare) and boost.rare > 0 then boost.rare else 1
		return if CollectionRules.tierOf(entry).rank >= 4 then all * rare else all
	end
	return if finite(boost) and (boost :: number) > 0 then boost :: number else 1
end

-- 10.4: a showroom factor as given (CollectionRules.showFactor's), 1 for none or junk.
local function showOf(show: number?): number
	return if finite(show) and (show :: number) > 0 then show :: number else 1
end

-- $ a minute while it stands on show (0 when broken), × the owner's boost (8.1: the Showroom lights; 10.4 the hall's
-- Bonus), × the market's (8.3: a hot kind's). (10.4: only the hall's pieces are paid it: server/Collection.luau.)
function CollectionRules.income(entry: { item: string, condition: number }, boost: Boost?, market: Market.View?): number
	if CollectionRules.broken(entry) then
		return 0
	end
	return CollectionRules.valueOf(entry) * CollectionRules.tierOf(entry).income * condition(entry) * factorOf(entry, boost) * Market.incomeFactor(market, entry.item)
end

-- $ it sells for (a whole number, at least 1): its tier's share of its worth, scrap when broken; 8.3: with the
-- market's View, the market's price for it now (Market.price). 10.4: a piece on a showroom stand × `show`
-- (CollectionRules.showFactor; never a broken one's scrap).
function CollectionRules.sell(entry: { item: string, condition: number }, market: Market.View?, show: number?): number
	local value = CollectionRules.valueOf(entry)
	local broken = CollectionRules.broken(entry)
	local price = if broken
		then value * tune().Scrap
		else value * CollectionRules.tierOf(entry).sell * condition(entry)
	local base = math.max(1, math.floor(price + 0.5))
	local out = if market then Market.price(base, market, entry.item) else base
	local factor = showOf(show)
	if factor ~= 1 and not broken and CollectionRules.isShow((entry :: any).stand) then
		out = math.max(1, math.floor(out * factor + 0.5))
	end
	return out
end

-- A copy of the piece with what the client shows: its rarity, value, $ a minute on show (to the cent, × the boost and
-- the market's), price (the market's), broken; 8.3: its price without the market and its market tag. 10.4: its area,
-- its price × `show` in the showroom.
function CollectionRules.view(entry: Entry, boost: Boost?, market: Market.View?, show: number?): View
	local base = CollectionRules.sell(entry)
	return {
		uid = entry.uid,
		item = entry.item,
		variant = entry.variant,
		condition = entry.condition,
		name = entry.name,
		stand = entry.stand,
		got = entry.got,
		rarity = CollectionRules.pieceRarity(entry), -- (9.x loot: its own roll)
		value = CollectionRules.valueOf(entry),
		income = math.floor(CollectionRules.income(entry, boost, market) * 100 + 0.5) / 100,
		price = CollectionRules.sell(entry, market, show),
		broken = CollectionRules.broken(entry),
		base = base,
		market = Market.tag(market, entry.item),
		sale = entry.sale,
		area = CollectionRules.area(entry.stand),
	}
end

-- The pieces' count, how many stand on show, their value, the income of the ones on show (× the boost, the market's)
-- and the price of them all (each at the market's price alone).
function CollectionRules.totals(entries: { Entry }, boost: Boost?, market: Market.View?, show: number?): Totals
	local out: Totals = { count = 0, shown = 0, value = 0, income = 0, sell = 0 }
	for _, entry in entries do
		out.count += 1
		out.value += CollectionRules.valueOf(entry)
		out.sell += CollectionRules.sell(entry, market, show)
		if entry.stand ~= nil then
			out.shown += 1
			if not CollectionRules.isShow(entry.stand) then -- (10.4: the hall's pieces earn, the showroom's are on sale)
				out.income += CollectionRules.income(entry, boost, market)
			end
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

-- 8.1: the stands' income × this for the player (their Showroom lights: shared/UpgradeRules.luau incomeBoost; 10.4
-- the Hall spotlights).
function CollectionRules.boost(profile: any?): number
	return UpgradeRules.incomeBoost(levelsOf(profile))
end

-- ── 10.4: the hall and the showroom ────────────────────────────────────────

function CollectionRules.isShow(stand: any): boolean
	return finite(stand) and stand > CollectionRules.ShowBase
end

function CollectionRules.area(stand: any): string?
	if not finite(stand) then
		return nil
	end
	return if stand > CollectionRules.ShowBase then "show" else "hall"
end

function CollectionRules.showStandsFor(profile: any?): number
	return UpgradeRules.showStands(levelsOf(profile))
end

function CollectionRules.open(profile: any?, stand: any): boolean
	if not finite(stand) or stand ~= math.floor(stand) or stand < 1 then
		return false
	end
	if stand > CollectionRules.ShowBase then
		return stand <= CollectionRules.ShowBase + CollectionRules.showStandsFor(profile)
	end
	return stand <= CollectionRules.standsFor(profile)
end

function CollectionRules.showFactor(profile: any?): number
	local bonus = Config.Showroom.SellBonus
	return (if finite(bonus) and bonus > 0 then bonus else 1) * UpgradeRules.effect(levelsOf(profile), "showPrice")
end

function CollectionRules.sets(entries: { Entry }, open: ((number) -> boolean)?): number
	local need = math.max(1, math.floor(tune().SetSize or 3))
	local seen: { [string]: { [string]: boolean } } = {}
	local count: { [string]: number } = {}
	for _, entry in entries do
		local stand = entry.stand
		if stand ~= nil and not CollectionRules.isShow(stand) and (open == nil or open(stand)) then
			local def = CollectionRules.defOf(entry.item)
			local room = if def then def.room else nil
			if type(room) == "string" then
				local items = seen[room] or {}
				seen[room] = items
				if not items[entry.item] then
					items[entry.item] = true
					count[room] = (count[room] or 0) + 1
				end
			end
		end
	end
	local sets = 0
	for _, n in count do
		if n >= need then
			sets += 1
		end
	end
	return math.min(sets, math.max(0, math.floor(tune().MaxSets or sets)))
end

function CollectionRules.bonus(profile: any?, entries: { Entry }?): Bonus
	local levels = levelsOf(profile)
	local sets = 0
	if entries then
		sets = CollectionRules.sets(entries, function(stand: number): boolean
			return CollectionRules.open(profile, stand)
		end)
	end
	return {
		all = UpgradeRules.effect(levels, "hallIncome") * (1 + UpgradeRules.effect(levels, "setBonus") * sets),
		rare = UpgradeRules.effect(levels, "rareIncome"),
		sets = sets,
	}
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

function CollectionRules.saleOf(value: any): number?
	return if finite(value) and value == math.floor(value) and value >= 1 and value < 2 ^ 40 then value else nil
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
				sale = if stand ~= nil and CollectionRules.isShow(stand) then CollectionRules.saleOf(e.sale) else nil, -- (8.7: a sign only on a stand; 10.4 a showroom's)
				rarity = CollectionRules.keepRarity(e.item, e.rarity), -- (9.x loot: none reads as its item's own)
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
	local out = CollectionRules.clean(saved.collection)
	if saved[CollectionRules.ShowFlag] ~= true then
		-- 10.4: a save from before the showroom: every piece on a stand stays there, in the hall (its stand is the
		-- hall's, its income as before); a showroom number (none can be there) back to the stock, and no sign stays
		-- (clean keeps a sign only in the showroom)
		for _, entry in out.entries do
			if CollectionRules.isShow(entry.stand) then
				entry.stand = nil
			end
			entry.sale = nil
		end
	end
	return out
end

-- Pieces on a stand the warehouse does not have (past `stands`) back to the stock; returns how many. 8.3: with `fits`
-- (whether a piece of that item stands on that stand: WarehouseLayout.fits at the owner's level), a piece too big for
-- its stand now goes back too (a level down made it a small stand).
function CollectionRules.fitStands(collection: Saved, stands: number, fits: ((number, string) -> boolean)?, show: number?): number
	local moved = 0
	local shows = if finite(show) then math.max(0, math.floor(show :: number)) else 0
	for _, entry in collection.entries do
		local stand = entry.stand
		local had = if stand == nil then true
			elseif stand > CollectionRules.ShowBase then stand <= CollectionRules.ShowBase + shows
			else stand >= 1 and stand <= stands
		if stand ~= nil and (not had or (fits ~= nil and not fits(stand, entry.item))) then
			entry.stand = nil
			entry.sale = nil -- (8.7: its FOR SALE sign goes with it)
			moved += 1
		end
	end
	return moved
end

return CollectionRules
