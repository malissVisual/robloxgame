--!strict
-- 8.2 SANDBOX, the collection book's rules (Config.CollectionBook). Pure (no Roblox at its top level;
-- tests/collectionbook_test.luau). server/CollectionBook.luau keeps a player's book and pays its milestones with these;
-- client/CollectionBookUi.luau draws the book with them (the "CollectionBook" remote's state carries the book itself).
--
-- The book lists every piece the sandbox house can hold: shared/FurnitureLooks.luau's catalogue (Order) without Walt's
-- farm pieces (FurnitureLooks.FarmPieces: the sandbox's chalet never holds them), i.e. the ordinary furniture (the
-- house's and the alpine pieces) and the collectibles (a def with a `rarity` of its own). A piece is unknown until a
-- move brings one home (Collection.add), then found: how many came home (n) and the best condition (best, 0 … 1).
-- 8.7 review: a piece only ever BOUGHT from another player (server/PlayerTrade.luau's deal) is in the book with the mark
-- `bought` (its page: { n, best, bought = true }; n and best the copies bought): the book shows it, tagged, but it is
-- not found: counts (and so the milestones, progress, due, the badges' found / legendary and the house's legendary
-- pick) skip it. The first one a move brings home makes it found for real (the page starts again: n 1, that piece's
-- condition; a discovery); one bought after that changes nothing. Otherwise one set of pieces passed between accounts
-- would pay every account the book's milestones.
--
--   CollectionBookRules.Pieces              the book's pieces, in catalogue order (the furniture, then the collectibles)
--   CollectionBookRules.Furniture           the ordinary ones, in that order
--   CollectionBookRules.Collectibles        the collectibles, in that order
--   CollectionBookRules.inBook(item)        one of Pieces (any type: false for anything else)
--   CollectionBookRules.isCollectible(item) one of Collectibles
--   CollectionBookRules.number(item)        its place in the book (1 … #Pieces), nil for anything else
--   CollectionBookRules.rarityOf(item)      shared/CollectionRules.luau's: a collectible's own, else by its value
--   CollectionBookRules.valueOf(item)       its catalogue value ($)
--   CollectionBookRules.record(book, item, condition, bought?)   one more of `item` came home: n + 1 (MaxCount at
--                                           most), best the better condition → true when it is new in the book (a piece
--                                           not in the book: nothing, false). 8.7 review: `bought` (a deal between
--                                           players): a page marked bought (n + 1 on one already bought), never a
--                                           discovery (false), nothing on a page found for real; a piece brought home
--                                           onto a bought page: found for real now (n 1, its condition; true)
--   CollectionBookRules.isFound(book, item) 8.7 review: its page is there and not only bought
--   CollectionBookRules.counts(book)        { found, total, furniture, furnitureTotal, collectibles, collectiblesTotal,
--                                           legendary } (found: pieces of the book in it, the bought-only ones not;
--                                           legendary: legendary ones)
--   CollectionBookRules.Milestones          Config.CollectionBook.Milestones
--   CollectionBookRules.Retired             8.4 review: Config.CollectionBook.Retired (a retired milestone's id → the one
--                                           that took its place): kept as paid, never due, never in paidList
--   CollectionBookRules.milestone(id)       the milestone with that id, nil for anything else (a retired id too)
--   CollectionBookRules.pay(paid, id)       8.4 review: a milestone paid, and every retired one it took the place of
--   CollectionBookRules.progress(book, milestone)   have, need (have never over need)
--   CollectionBookRules.reached(book, milestone)
--   CollectionBookRules.due(book, paid)     the milestones reached and not paid yet, in order (what the server pays)
--   CollectionBookRules.fill(book)          the admin's FILL BOOK: every piece not found yet found once (best 1; 8.7
--                                           review: a bought-only one too) → the pieces it added, in order
--   CollectionBookRules.view(book)          a copy for the remote ({ [item] = { n, best, bought? } }, best to the
--                                           thousandth)
--   CollectionBookRules.paidList(paid)      the paid milestones' ids, in order (for the remote)
--   The save (profile.collectionBook = { [item] = { n, best, bought? } }, profile.collectionBookPaid =
--   { [milestone id] = true }):
--   CollectionBookRules.empty()             a new player's book
--   CollectionBookRules.clean(raw)          a saved book checked, never trusted: only the book's pieces, n a whole
--                                           number 1 … MaxCount (none: 1; under 1: not found), best 0 … 1; 8.7 review:
--                                           bought kept only as true (an older server's clean drops it: the page reads
--                                           as found there, as it did before 8.7; a rollout's few minutes at most)
--   CollectionBookRules.cleanPaid(raw)      the known milestones' ids marked true, nothing else (a list of ids too); 8.4
--                                           review: a retired one too (an older server paid it: never paid there again)
--   CollectionBookRules.backfill(entries)   a book from a collection's pieces (shared/CollectionRules.luau Entry: item,
--                                           condition): each piece of the book in it counted, its best condition
--   CollectionBookRules.fromSave(saved, collection)   the migration (server/PlayerData.luau applySaved) → book, paid:
--                                           only a real save (money in it) has a book; written with the flag (Flag) its
--                                           own, cleaned (the stock's pieces where it has no page: a bought page
--                                           stays bought); an older real save the book of its stock (`collection`, its
--                                           cleaned collection) and no milestone paid yet (they pay on joining); a new
--                                           player or a lock-only record: empty. Running it again on what it gave (saved
--                                           with the flag) gives the same.

local Config = require(script.Parent.Config)
local FurnitureLooks = require(script.Parent.FurnitureLooks)
local CollectionRules = require(script.Parent.CollectionRules)

local CollectionBookRules = {}

export type Found = { n: number, best: number, bought: boolean? } -- (8.7 review: bought, only ever bought from a player)
export type Book = { [string]: Found }
export type Paid = { [string]: boolean }
export type Counts = {
	found: number,
	total: number,
	furniture: number,
	furnitureTotal: number,
	collectibles: number,
	collectiblesTotal: number,
	legendary: number,
}
export type Milestone = Config.BookMilestone

local function tune()
	return Config.CollectionBook
end

-- The save's mark (server/PlayerData.luau writes it with every save).
CollectionBookRules.Flag = tune().Flag
CollectionBookRules.Milestones = tune().Milestones
CollectionBookRules.Retired = ((tune() :: any).Retired or {}) :: { [string]: string } -- 8.4 review

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- ── The book's pieces ──────────────────────────────────────────────────────

local farm: { [string]: boolean } = {}
for _, id in (FurnitureLooks :: any).FarmPieces or {} do
	farm[id] = true
end
local pieces: { string } = {}
local furniture: { string } = {}
local collectibles: { string } = {}
local place: { [string]: number } = {}
local collectible: { [string]: boolean } = {}
for _, id in FurnitureLooks.Order do
	local def = FurnitureLooks.Items[id]
	if def and not farm[id] and not place[id] then
		if type((def :: any).rarity) == "string" then
			table.insert(collectibles, id)
			collectible[id] = true
		else
			table.insert(furniture, id)
		end
	end
end
for _, list in { furniture, collectibles } do
	for _, id in list do
		table.insert(pieces, id)
		place[id] = #pieces
	end
end
CollectionBookRules.Pieces = pieces
CollectionBookRules.Furniture = furniture
CollectionBookRules.Collectibles = collectibles

function CollectionBookRules.inBook(item: any): boolean
	return type(item) == "string" and place[item] ~= nil
end

function CollectionBookRules.isCollectible(item: any): boolean
	return type(item) == "string" and collectible[item] == true
end

function CollectionBookRules.number(item: any): number?
	return if type(item) == "string" then place[item] else nil
end

function CollectionBookRules.rarityOf(item: string): string
	return CollectionRules.rarityOf(CollectionRules.defOf(item))
end

function CollectionBookRules.valueOf(item: string): number
	return CollectionRules.valueOf({ item = item })
end

-- ── Found ──────────────────────────────────────────────────────────────────

local function unit(condition: any): number
	return if finite(condition) then math.clamp(condition, 0, 1) else 0
end

function CollectionBookRules.record(book: Book, item: any, condition: any, bought: boolean?): boolean
	if not CollectionBookRules.inBook(item) then
		return false
	end
	local best = unit(condition)
	local found = book[item]
	if bought == true then -- (8.7 review: a deal between players: shown, never found)
		if not found then
			book[item] = { n = 1, best = best, bought = true }
		elseif found.bought == true then
			found.n = math.min(found.n + 1, tune().MaxCount)
			found.best = math.max(found.best, best)
		end
		return false
	end
	if found and found.bought ~= true then
		found.n = math.min(found.n + 1, tune().MaxCount)
		found.best = math.max(found.best, best)
		return false
	end
	book[item] = { n = 1, best = best } -- (new, or 8.7 review: found for real on a bought page)
	return true
end

function CollectionBookRules.isFound(book: Book, item: any): boolean
	local found = if type(item) == "string" then book[item] else nil
	return found ~= nil and found.bought ~= true
end

function CollectionBookRules.counts(book: Book): Counts
	local out: Counts = {
		found = 0,
		total = #pieces,
		furniture = 0,
		furnitureTotal = #furniture,
		collectibles = 0,
		collectiblesTotal = #collectibles,
		legendary = 0,
	}
	for _, id in pieces do
		if CollectionBookRules.isFound(book, id) then -- (8.7 review: a bought-only page is no find)
			out.found += 1
			if collectible[id] then
				out.collectibles += 1
			else
				out.furniture += 1
			end
			if CollectionBookRules.rarityOf(id) == "legendary" then
				out.legendary += 1
			end
		end
	end
	return out
end

-- ── Milestones ─────────────────────────────────────────────────────────────

function CollectionBookRules.milestone(id: any): Milestone?
	if type(id) ~= "string" then
		return nil
	end
	for _, milestone in CollectionBookRules.Milestones do
		if milestone.id == id then
			return milestone
		end
	end
	return nil
end

local function measure(counts: Counts, milestone: Milestone): (number, number)
	local kind = milestone.kind
	if kind == "found" then
		return counts.found, math.max(1, math.floor(milestone.need or counts.total))
	elseif kind == "furniture" then
		return counts.furniture, math.max(1, counts.furnitureTotal)
	elseif kind == "collectibles" then
		return counts.collectibles, math.max(1, counts.collectiblesTotal)
	elseif kind == "legendary" then
		return counts.legendary, math.max(1, math.floor(milestone.need or 1))
	end
	return 0, 1 -- (a kind it does not know is never reached)
end

function CollectionBookRules.progress(book: Book, milestone: Milestone): (number, number)
	local have, need = measure(CollectionBookRules.counts(book), milestone)
	return math.min(have, need), need
end

function CollectionBookRules.reached(book: Book, milestone: Milestone): boolean
	local have, need = measure(CollectionBookRules.counts(book), milestone)
	return have >= need
end

function CollectionBookRules.due(book: Book, paid: Paid): { Milestone }
	local counts = CollectionBookRules.counts(book)
	local list: { Milestone } = {}
	for _, milestone in CollectionBookRules.Milestones do
		local have, need = measure(counts, milestone)
		if have >= need and paid[milestone.id] ~= true then
			table.insert(list, milestone)
		end
	end
	return list
end

function CollectionBookRules.fill(book: Book): { string }
	local added: { string } = {}
	for _, id in pieces do
		if not CollectionBookRules.isFound(book, id) then
			book[id] = { n = 1, best = 1 }
			table.insert(added, id)
		end
	end
	return added
end

function CollectionBookRules.view(book: Book): Book
	local out: Book = {}
	for _, id in pieces do
		local found = book[id]
		if found then
			out[id] = { n = found.n, best = math.floor(found.best * 1000 + 0.5) / 1000, bought = if found.bought == true then true else nil }
		end
	end
	return out
end

function CollectionBookRules.paidList(paid: Paid): { string }
	local list: { string } = {}
	for _, milestone in CollectionBookRules.Milestones do
		if paid[milestone.id] == true then
			table.insert(list, milestone.id)
		end
	end
	return list
end

-- ── The save ───────────────────────────────────────────────────────────────

function CollectionBookRules.empty(): Book
	return {}
end

function CollectionBookRules.clean(raw: any): Book
	local out: Book = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, id in pieces do
		local found = raw[id]
		if type(found) == "table" then
			local n = if finite(found.n) then math.floor(found.n) elseif found.n == nil then 1 else 0
			if n >= 1 then
				out[id] = { n = math.min(n, tune().MaxCount), best = unit(found.best), bought = if found.bought == true then true else nil }
			end
		end
	end
	return out
end

function CollectionBookRules.cleanPaid(raw: any): Paid
	local out: Paid = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, milestone in CollectionBookRules.Milestones do
		if raw[milestone.id] == true or table.find(raw, milestone.id) ~= nil then
			out[milestone.id] = true
		end
	end
	for id in CollectionBookRules.Retired do -- (8.4 review: an older server's milestone, paid there: kept so)
		if raw[id] == true or table.find(raw, id) ~= nil then
			out[id] = true
		end
	end
	return out
end

-- 8.4 review: the retired milestones a milestone took the place of are paid with it (an older server never pays them).
function CollectionBookRules.pay(paid: Paid, id: string)
	paid[id] = true
	for old, by in CollectionBookRules.Retired do
		if by == id then
			paid[old] = true
		end
	end
end

function CollectionBookRules.backfill(entries: any): Book
	local out: Book = {}
	if type(entries) ~= "table" then
		return out
	end
	for _, entry in entries do
		if type(entry) == "table" then
			CollectionBookRules.record(out, entry.item, entry.condition)
		end
	end
	return out
end

function CollectionBookRules.fromSave(saved: any, collection: any): (Book, Paid)
	if type(saved) ~= "table" or saved.money == nil then
		return CollectionBookRules.empty(), {}
	end
	if saved[CollectionBookRules.Flag] == true then
		local book = CollectionBookRules.clean(saved.collectionBook)
		-- (8.3 review: a piece in the stock is always found: an older server's save may have dropped newer kinds from
		-- the book while the stock kept them. 8.7 review: only where the book has no page: a piece bought from a player
		-- keeps its bought page, so a rejoin never turns it into a find)
		for item, page in CollectionBookRules.backfill(if type(collection) == "table" then collection.entries else nil) do
			if book[item] == nil then
				book[item] = page
			end
		end
		return book, CollectionBookRules.cleanPaid(saved.collectionBookPaid)
	end
	return CollectionBookRules.backfill(if type(collection) == "table" then collection.entries else nil), {}
end

return CollectionBookRules
