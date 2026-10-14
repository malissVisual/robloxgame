--!strict
-- 8.2 SANDBOX, the warehouse's quality of life: the rules behind the STOCK list's bulk buttons and the window's orders
-- (client/WarehouseUi.luau shows them; server/Collection.luau decides with the same rules, so what the window offers
-- before it asks is what the server does). Pure (no Roblox at its top level; tests/stockplan_test.luau).
-- It works on pieces as the collection's views carry them (shared/CollectionRules.luau view: uid, item, stand, got,
-- rarity, income, price, broken, condition): the server builds them from its own entries, the client has them in the
-- "Collection" remote's state. A number that is no number counts as 0; a uid may be a string or a number.
--
--   StockPlan.better(a, b)               does piece a earn more on show than b: its $ a minute, then its rarity, its
--                                        price, its condition, then the older piece (its uid's number) first; every tie
--                                        broken (a total order: table.sort's)
--   StockPlan.free(pieces, stands)       the display stands 1 … stands that hold no piece, in order
--   StockPlan.fill(pieces, stands, fits) ⭐ FILL BEST: { { uid, stand } } the best earners in the stock (not on show,
--                                        earning: not broken, over $0 a minute) onto the free stands, each on one it
--                                        fits (fits(stand, item) → boolean: an upgrade's small stand holds no bed) and of
--                                        those the one the fewest of the candidates fit (the small stands take the small
--                                        pieces, the big ones stay for the big): the most a minute those stands can earn.
--                                        Nothing free or nothing that fits: {} (so a second FILL BEST changes nothing)
--   StockPlan.Filters                    💰 SELL…'s filters, in the menu's order: "common" (every Common piece), "broken"
--                                        (every broken piece: scrap), "duplicates" (every piece but the best of each item)
--   StockPlan.isFilter(filter)           one of them (anything else: false)
--   StockPlan.filterName(filter)         the menu's words for it: "ALL COMMON", "ALL BROKEN", "DUPLICATES"
--   StockPlan.toSell(pieces, filter)     the pieces that filter sells, best first: only pieces in the stock (a piece on
--                                        show is never sold in bulk; it still counts as the best of its item); {} for a
--                                        filter that isn't one
--   StockPlan.price(pieces)              what they sell for together (their prices summed)
--   StockPlan.Sorts                      the window's orders, in the toggle's order: "income" ($/MIN, the best earners
--                                        first), "value" (the price), "newest" (came home last), "rarity" (the rarest);
--   StockPlan.order(by)                  its comparator (an unknown order: income's); StockPlan.sortLabel(by) its words;
--                                        StockPlan.nextSort(by) the toggle's next one
--   StockPlan.matches(name, query)       the search box: every word of the query (any case) is in the name; an empty
--                                        query matches everything

local Config = require(script.Parent.Config)

local StockPlan = {}

export type Piece = {
	uid: any,
	item: string,
	stand: number?,
	got: number?,
	rarity: string,
	income: number, -- $ a minute on show
	price: number, -- $ it sells for
	broken: boolean?,
	condition: number?,
}
export type Placement = { uid: any, stand: number }

StockPlan.Filters = { "common", "broken", "duplicates" }
local FILTER_NAMES: { [string]: string } = { common = "ALL COMMON", broken = "ALL BROKEN", duplicates = "DUPLICATES" }

StockPlan.Sorts = { "income", "value", "newest", "rarity" }
local SORT_LABELS: { [string]: string } = { income = "$/MIN", value = "VALUE", newest = "NEWEST", rarity = "RARITY" }

local function number(value: any): number
	return if type(value) == "number" and value == value and value > -math.huge and value < math.huge then value else 0
end

local function rank(rarity: any): number
	local tier = if type(rarity) == "string" then Config.Collection.Tiers[rarity] else nil
	return if tier then tier.rank else 0
end

-- The number at a uid's end (its place in the order the pieces came home), 0 without one.
local function uidNumber(uid: any): number
	if type(uid) == "number" then
		return number(uid)
	end
	return if type(uid) == "string" then tonumber(string.match(uid, "(%d+)$")) or 0 else 0
end

local function older(a: Piece, b: Piece): boolean
	local na, nb = uidNumber(a.uid), uidNumber(b.uid)
	if na ~= nb then
		return na < nb
	end
	return tostring(a.uid) < tostring(b.uid)
end

function StockPlan.better(a: Piece, b: Piece): boolean
	local ia, ib = number(a.income), number(b.income)
	if ia ~= ib then
		return ia > ib
	end
	local ra, rb = rank(a.rarity), rank(b.rarity)
	if ra ~= rb then
		return ra > rb
	end
	local pa, pb = number(a.price), number(b.price)
	if pa ~= pb then
		return pa > pb
	end
	local ca, cb = number(a.condition), number(b.condition)
	if ca ~= cb then
		return ca > cb
	end
	return older(a, b)
end

local function onStand(piece: Piece): number?
	local stand = piece.stand
	return if type(stand) == "number" and stand == stand then stand else nil
end

-- ── ⭐ FILL BEST ───────────────────────────────────────────────────────────

function StockPlan.free(pieces: { Piece }, stands: number): { number }
	local taken: { [number]: boolean } = {}
	for _, piece in pieces do
		local stand = onStand(piece)
		if stand then
			taken[stand] = true
		end
	end
	local out: { number } = {}
	for stand = 1, math.floor(number(stands)) do
		if not taken[stand] then
			table.insert(out, stand)
		end
	end
	return out
end

function StockPlan.fill(pieces: { Piece }, stands: number, fits: (stand: number, item: string) -> boolean): { Placement }
	local plan: { Placement } = {}
	local free = StockPlan.free(pieces, stands)
	if #free == 0 then
		return plan
	end
	local candidates: { Piece } = {}
	for _, piece in pieces do
		if onStand(piece) == nil and piece.broken ~= true and number(piece.income) > 0 then
			table.insert(candidates, piece)
		end
	end
	table.sort(candidates, StockPlan.better)
	-- (each stand and item asked once; a stand's room: how many of the candidates fit it)
	local known: { [string]: boolean } = {}
	local function ask(stand: number, item: string): boolean
		local key = `{stand}|{item}`
		local answer = known[key]
		if answer == nil then
			local ok, yes = pcall(fits, stand, item)
			answer = ok and yes == true
			known[key] = answer
		end
		return answer :: boolean
	end
	local room: { [number]: number } = {}
	for _, stand in free do
		local n = 0
		for _, piece in candidates do
			if ask(stand, piece.item) then
				n += 1
			end
		end
		room[stand] = n
	end
	for _, piece in candidates do
		if #free == 0 then
			break
		end
		local pick, least = nil, math.huge
		for index, stand in free do
			if room[stand] < least and ask(stand, piece.item) then
				pick, least = index, room[stand] -- (ties: the lower stand, free is in order)
			end
		end
		if pick then
			table.insert(plan, { uid = piece.uid, stand = table.remove(free, pick) :: number })
		end
	end
	return plan
end

-- ── 💰 SELL… ────────────────────────────────────────────────────────────────

function StockPlan.isFilter(filter: any): boolean
	return type(filter) == "string" and FILTER_NAMES[filter] ~= nil
end

function StockPlan.filterName(filter: string): string
	return FILTER_NAMES[filter] or string.upper(tostring(filter))
end

function StockPlan.toSell(pieces: { Piece }, filter: any): { Piece }
	local out: { Piece } = {}
	if filter == "common" then
		for _, piece in pieces do
			if onStand(piece) == nil and piece.rarity == "common" then
				table.insert(out, piece)
			end
		end
	elseif filter == "broken" then
		for _, piece in pieces do
			if onStand(piece) == nil and piece.broken == true then
				table.insert(out, piece)
			end
		end
	elseif filter == "duplicates" then
		local best: { [string]: Piece } = {}
		for _, piece in pieces do
			local top = best[piece.item]
			if not top or StockPlan.better(piece, top) then
				best[piece.item] = piece
			end
		end
		for _, piece in pieces do
			if onStand(piece) == nil and best[piece.item] ~= piece then
				table.insert(out, piece)
			end
		end
	end
	table.sort(out, StockPlan.better)
	return out
end

function StockPlan.price(pieces: { Piece }): number
	local total = 0
	for _, piece in pieces do
		total += math.max(0, number(piece.price))
	end
	return total
end

-- ── The window's orders and its search ─────────────────────────────────────

local function byValue(a: Piece, b: Piece): boolean
	local pa, pb = number(a.price), number(b.price)
	if pa ~= pb then
		return pa > pb
	end
	return StockPlan.better(a, b)
end

local function byNewest(a: Piece, b: Piece): boolean
	local ga, gb = number(a.got), number(b.got)
	if ga ~= gb then
		return ga > gb
	end
	local na, nb = uidNumber(a.uid), uidNumber(b.uid)
	if na ~= nb then
		return na > nb
	end
	return StockPlan.better(a, b)
end

local function byRarity(a: Piece, b: Piece): boolean
	local ra, rb = rank(a.rarity), rank(b.rarity)
	if ra ~= rb then
		return ra > rb
	end
	return StockPlan.better(a, b)
end

local ORDERS: { [string]: (Piece, Piece) -> boolean } = { income = StockPlan.better, value = byValue, newest = byNewest, rarity = byRarity }

function StockPlan.order(by: string?): (Piece, Piece) -> boolean
	return ORDERS[by or "income"] or StockPlan.better
end

function StockPlan.sortLabel(by: string?): string
	return SORT_LABELS[by or "income"] or SORT_LABELS.income
end

function StockPlan.nextSort(by: string?): string
	local at = table.find(StockPlan.Sorts, by or "income") or 0
	return StockPlan.Sorts[at % #StockPlan.Sorts + 1]
end

function StockPlan.matches(name: string, query: string?): boolean
	if type(query) ~= "string" then
		return true
	end
	local haystack = string.lower(if type(name) == "string" then name else "")
	for word in string.gmatch(string.lower(query), "%S+") do
		if not string.find(haystack, word, 1, true) then
			return false
		end
	end
	return true
end

return StockPlan
