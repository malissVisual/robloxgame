-- 8.2 SANDBOX, the collection book's rules (shared/CollectionBookRules.luau, Config.CollectionBook): the book's pieces
-- (the catalogue without Walt's farm pieces: the ordinary furniture, then the 24 collectibles; exactly what the sandbox
-- house can hold), record (a discovery, the count, the best condition, nothing for a piece not in the book), the
-- counts, the milestones (their order and rewards, progress, reached, due: each once, a legendary, every collectible,
-- all the furniture), the admin's fill, the view for the remote (what a remote and a DataStore keep), and the save:
-- clean (garbage never trusted), cleanPaid, backfill from a stock, fromSave (the migration: only a real save; with the
-- flag its own, an older one its stock's with nothing paid, a new player's empty; running it twice gives the same).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local CollectionRules = require("./CollectionRules")
local Rules = require("./CollectionBookRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end
-- What a DataStore (or a remote) keeps: string keys or a plain list, numbers that are finite, no functions.
local function storable(value: any): boolean
	local kind = type(value)
	if kind == "number" then
		return value == value and value > -math.huge and value < math.huge
	elseif kind == "string" or kind == "boolean" then
		return true
	elseif kind ~= "table" then
		return false
	end
	local count, strings = 0, 0
	for key, item in value do
		count += 1
		if type(key) == "string" then
			strings += 1
		end
		if not storable(item) then
			return false
		end
	end
	return strings == count or (strings == 0 and #value == count)
end

-- ── The book's pieces ──────────────────────────────────────────────────────
local farm: { [string]: boolean } = {}
for _, id in FurnitureLooks.FarmPieces do
	farm[id] = true
end
local expected = #FurnitureLooks.Order - #FurnitureLooks.FarmPieces
check(`the book: the catalogue without the farm's {#FurnitureLooks.FarmPieces} pieces ({expected})`, #Rules.Pieces == expected and expected == 68, #Rules.Pieces) -- (8.3: 56 + 12 collectibles)
check("… the 24 collectibles (FurnitureLooks.Collectibles, in their order)", #Rules.Collectibles == 24 and same(Rules.Collectibles, FurnitureLooks.Collectibles))
check("… and 44 pieces of furniture (no rarity of their own)", #Rules.Furniture == 44 and #Rules.Furniture + #Rules.Collectibles == #Rules.Pieces)
local inOrder, noFarm, unique = true, true, true
local seen: { [string]: boolean } = {}
for index, id in Rules.Pieces do
	if index <= #Rules.Furniture then
		inOrder = inOrder and Rules.Furniture[index] == id and FurnitureLooks.Items[id].rarity == nil
	else
		inOrder = inOrder and Rules.Collectibles[index - #Rules.Furniture] == id and FurnitureLooks.Items[id].rarity ~= nil
	end
	noFarm = noFarm and not farm[id]
	unique = unique and not seen[id]
	seen[id] = true
	inOrder = inOrder and Rules.number(id) == index and Rules.inBook(id)
end
check("… the furniture first, then the collectibles, each numbered (#1 …) and in the book once", inOrder and unique)
check("… no farm piece (the hay wagon, Thunder's saddle …)", noFarm and not Rules.inBook("hay_wagon") and not Rules.inBook("thunders_saddle"))
check("inBook / isCollectible / number: anything else is not in the book", not Rules.inBook("nope") and not Rules.inBook(nil) and not Rules.inBook(5) and not Rules.inBook({})
	and Rules.isCollectible("jukebox") and not Rules.isCollectible("sofa") and not Rules.isCollectible(nil) and Rules.number("nope") == nil and Rules.number(3) == nil)
-- what the sandbox house holds: its recipes and its collectibles, every seed's spots
local inRecipes: { [string]: boolean } = {}
for _, entries in HouseLayout.Recipes do
	for _, entry in entries do
		inRecipes[entry.item] = true
	end
end
for _, entry in HouseLayout.Collectibles do
	inRecipes[entry.item] = true
end
local missing, extra = {}, {}
for _, id in Rules.Pieces do
	if not inRecipes[id] then
		table.insert(missing, id)
	end
end
for id in inRecipes do
	if not Rules.inBook(id) then
		table.insert(extra, id)
	end
end
check("the book is exactly what the sandbox house can hold (its recipes and its collectibles)", #missing == 0 and #extra == 0, table.concat(missing, ",") .. " / " .. table.concat(extra, ","))
local spotsIn = true
for seed = 1, 12 do
	for _, spot in HouseLayout.plan(seed, "house").spots do
		if not Rules.inBook(spot.item) then
			spotsIn = false
		end
	end
end
check("… every piece of 12 houses' plans is in the book", spotsIn)
check("rarityOf / valueOf: CollectionRules' (a collectible's own, else by value)", Rules.rarityOf("knight_armour") == "legendary" and Rules.rarityOf("piano") == CollectionRules.rarityOf(FurnitureLooks.Items.piano)
	and Rules.valueOf("oil_painting") == 6000 and Rules.valueOf("sofa") == 350)

-- ── record and counts ──────────────────────────────────────────────────────
local book = Rules.empty()
check("record: the first sofa is new", Rules.record(book, "sofa", 0.6) == true and same(book.sofa, { n = 1, best = 0.6 }))
check("… a second one is not; n 2, the better condition kept", Rules.record(book, "sofa", 0.9) == false and same(book.sofa, { n = 2, best = 0.9 }))
check("… a worse one: n 3, best stays 0.9", Rules.record(book, "sofa", 0.2) == false and same(book.sofa, { n = 3, best = 0.9 }))
check("… a condition out of range or garbage: 0 … 1", Rules.record(book, "tv", 7) and book.tv.best == 1 and Rules.record(book, "piano", 0 / 0) and book.piano.best == 0 and Rules.record(book, "radio", "x") and book.radio.best == 0)
check("… a piece not in the book (a farm piece, junk): nothing", Rules.record(book, "hay_wagon", 1) == false and Rules.record(book, "nope", 1) == false and Rules.record(book, nil, 1) == false and book.hay_wagon == nil and book.nope == nil)
local counts = Rules.counts(book)
check("counts: 4 found of 68 (4 furniture of 44, 0 collectibles of 24, no legendary)", counts.found == 4 and counts.total == 68 and counts.furniture == 4 and counts.furnitureTotal == 44 and counts.collectibles == 0 and counts.collectiblesTotal == 24 and counts.legendary == 0)
Rules.record(book, "oil_painting", 0.8)
counts = Rules.counts(book)
check("… a legendary collectible counts as a collectible and a legendary", counts.found == 5 and counts.collectibles == 1 and counts.legendary == 1)
local big = Rules.empty()
big.box = { n = Config.CollectionBook.MaxCount, best = 1 }
Rules.record(big, "box", 1)
check("n stops at MaxCount", big.box.n == Config.CollectionBook.MaxCount)

-- ── Milestones ─────────────────────────────────────────────────────────────
local M = Rules.Milestones
local ids = {}
for _, milestone in M do
	table.insert(ids, milestone.id)
end
check("the milestones in order: found 10, found 20, all the furniture, every collectible, a legendary", table.concat(ids, ",") == "found10,found20,furniture,collectibles24,legendary", table.concat(ids, ","))
check("… their names as the owner asked", M[1].name == "Found 10 pieces" and M[2].name == "Found 20 pieces" and M[4].name == "Found every collectible" and M[5].name == "A legendary!")
local small = true
for _, milestone in M do
	small = small and milestone.reward >= 100 and milestone.reward <= 5000 and milestone.reward == math.floor(milestone.reward)
end
check("… small whole-dollar rewards ($100 – 5,000), the rarer goals dearer", small and M[1].reward < M[2].reward and M[2].reward < M[3].reward and M[3].reward < M[4].reward)
check("milestone(id): the milestone, nil for anything else", Rules.milestone("found10") == M[1] and Rules.milestone("nope") == nil and Rules.milestone(nil) == nil and Rules.milestone(5) == nil)
local fresh = Rules.empty()
local have, need = Rules.progress(fresh, M[1])
check("progress: an empty book is 0 / 10, nothing reached, nothing due", have == 0 and need == 10 and not Rules.reached(fresh, M[1]) and #Rules.due(fresh, {}) == 0)
for index = 1, 9 do
	Rules.record(fresh, Rules.Furniture[index], 1)
end
check("9 found: found 10 not reached (9 / 10)", not Rules.reached(fresh, M[1]) and select(1, Rules.progress(fresh, M[1])) == 9)
Rules.record(fresh, Rules.Furniture[10], 1)
local due = Rules.due(fresh, {})
check("10 found: found 10 reached and due (only it)", Rules.reached(fresh, M[1]) and #due == 1 and due[1].id == "found10")
check("… paid: due no more", #Rules.due(fresh, { found10 = true }) == 0)
Rules.record(fresh, "jukebox", 1) -- (an epic)
for index = 11, 19 do
	Rules.record(fresh, Rules.Furniture[index], 1)
end
due = Rules.due(fresh, { found10 = true })
check("20 found (a collectible among them): found 20 due", #due == 1 and due[1].id == "found20")
Rules.record(fresh, "knight_armour", 0.4)
due = Rules.due(fresh, { found10 = true, found20 = true })
check("a legendary: \"A legendary!\" due", #due == 1 and due[1].id == "legendary")
check("progress never over need (21 / 20)", select(1, Rules.progress(fresh, M[2])) == 20)
for _, id in Rules.Furniture do
	Rules.record(fresh, id, 1)
end
due = Rules.due(fresh, { found10 = true, found20 = true, legendary = true })
check("every piece of furniture: \"All the furniture\" due (not the collectibles: 2 of 24)", #due == 1 and due[1].id == "furniture" and select(1, Rules.progress(fresh, M[4])) == 2)
for _, id in Rules.Collectibles do
	Rules.record(fresh, id, 1)
end
due = Rules.due(fresh, { found10 = true, found20 = true, legendary = true, furniture = true })
check("every collectible: \"Found every collectible\" due", #due == 1 and due[1].id == "collectibles24")
-- 8.4 review: 8.2's "collectibles" ($2,500 for its 12) is retired: the 24-piece one has its own id
check("… its own id (collectibles24); 8.2's \"collectibles\" retired in its favour (no milestone of the book)", Config.CollectionBook.Retired.collectibles == "collectibles24"
	and Rules.Retired.collectibles == "collectibles24" and Rules.milestone("collectibles") == nil and Rules.milestone("collectibles24") == M[4])
check("… paid by an older server (\"collectibles\"): the 24 still due here (its $5,000 pays)", #Rules.due(fresh, { found10 = true, found20 = true, legendary = true, furniture = true, collectibles = true }) == 1)
local paidNow: { [string]: boolean } = {}
Rules.pay(paidNow, "collectibles24")
check("pay: the 24 marks the retired one paid too (an older server never pays its 12 again); another milestone only itself", same(paidNow, { collectibles24 = true, collectibles = true }))
local paidOne: { [string]: boolean } = {}
Rules.pay(paidOne, "found10")
check("… found10: only itself", same(paidOne, { found10 = true }))
local everything = Rules.due(fresh, {})
check("a full book unpaid: all five due, in order", #everything == 5 and everything[1].id == "found10" and everything[5].id == "legendary")
local weird = { id = "odd", name = "Odd", kind = "dance", reward = 5 }
check("a milestone of a kind it does not know is never reached", not Rules.reached(fresh, weird :: any))

-- ── fill (the admin's FILL BOOK) ────────────────────────────────────────────
local part = Rules.empty()
Rules.record(part, "sofa", 0.3)
Rules.record(part, "sofa", 0.3)
local added = Rules.fill(part)
check("fill: every piece not found yet once (67 added, in order), the found ones kept", #added == 67 and added[1] == Rules.Pieces[2] and same(part.sofa, { n = 2, best = 0.3 }) and Rules.counts(part).found == 68 and same(part.jukebox, { n = 1, best = 1 }))
check("… a full book: fill adds nothing", #Rules.fill(part) == 0)

-- ── view, paidList ─────────────────────────────────────────────────────────
local raw = Rules.empty()
Rules.record(raw, "sofa", 0.33333333)
Rules.record(raw, "jukebox", 1)
local view = Rules.view(raw)
check("view: a copy, best to the thousandth", view.sofa ~= raw.sofa and same(view, { sofa = { n = 1, best = 0.333 }, jukebox = { n = 1, best = 1 } }))
view.sofa.n = 99
check("… changing it changes nothing in the book", raw.sofa.n == 1)
check("… what a remote and a DataStore keep", storable(Rules.view(fresh)) and storable(Rules.view(Rules.empty())))
check("paidList: the paid milestones' ids in order", same(Rules.paidList({ legendary = true, found10 = true, junk = true }), { "found10", "legendary" }) and #Rules.paidList({}) == 0)
check("… a retired one is not in it (the book never shows it)", same(Rules.paidList({ collectibles = true, collectibles24 = true }), { "collectibles24" }))

-- ── The save ───────────────────────────────────────────────────────────────
check("empty: a new book", same(Rules.empty(), {}))
local cleaned = Rules.clean({
	sofa = { n = 3, best = 0.8 },
	tv = { n = 2.7, best = 4 },
	piano = { best = 0.5 }, -- (no n: found once)
	radio = { n = 0, best = 1 }, -- (never found)
	bed = { n = -4 },
	fridge = { n = 0 / 0, best = 0 / 0 },
	jukebox = { n = 1e12, best = -1 },
	hay_wagon = { n = 1, best = 1 }, -- (not in the book)
	nope = { n = 1, best = 1 },
	[5] = { n = 1, best = 1 },
	mirror = "found",
})
check("clean: only the book's pieces, n whole (none: 1; under 1 or NaN: not found), at most MaxCount, best 0 … 1", same(cleaned, {
	sofa = { n = 3, best = 0.8 },
	tv = { n = 2, best = 1 },
	piano = { n = 1, best = 0.5 },
	jukebox = { n = Config.CollectionBook.MaxCount, best = 0 },
}), cleaned)
check("… garbage: empty", same(Rules.clean(nil), {}) and same(Rules.clean("x"), {}) and same(Rules.clean(5), {}))
check("cleanPaid: the known ids marked true (a list of ids too), nothing else", same(Rules.cleanPaid({ found10 = true, legendary = "yes", nope = true }), { found10 = true })
	and same(Rules.cleanPaid({ "found20", "nope" }), { found20 = true }) and same(Rules.cleanPaid(nil), {}))
check("cleanPaid: a retired id an older server paid is kept (never dropped: it never pays there again)", same(Rules.cleanPaid({ collectibles = true, nope = true }), { collectibles = true })
	and same(Rules.cleanPaid({ "collectibles" }), { collectibles = true }) and same(Rules.cleanPaid({ collectibles = "yes" }), {}))
local stock = {
	{ uid = "1-1", item = "sofa", condition = 0.5 },
	{ uid = "1-2", item = "sofa", condition = 0.9 },
	{ uid = "1-3", item = "jukebox", condition = 0.7 },
	{ uid = "1-4", item = "hay_wagon", condition = 1 }, -- (a farm piece from an admin's FILL STOCK)
	"junk",
	{ item = 5 },
}
local filled = Rules.backfill(stock)
check("backfill: each piece of the book in the stock counted, its best condition", same(filled, { sofa = { n = 2, best = 0.9 }, jukebox = { n = 1, best = 0.7 } }))
check("… garbage: empty", same(Rules.backfill(nil), {}) and same(Rules.backfill("x"), {}))

-- fromSave
local collection = CollectionRules.clean({ entries = stock, nextUid = 9 })
local oldSave = { money = 500, collectionKept = true, collection = { entries = stock, nextUid = 9 } }
local b1, p1 = Rules.fromSave(oldSave, collection)
check("fromSave: an older real save (no book flag): the book of its stock, nothing paid", same(b1, { sofa = { n = 2, best = 0.9 }, jukebox = { n = 1, best = 0.7 } }) and same(p1, {}))
local b0, p0 = Rules.fromSave(nil, collection)
check("… a new player (no save): empty", same(b0, {}) and same(p0, {}))
local bl, pl = Rules.fromSave({ lock = { job = "x" } }, collection)
check("… a lock-only record (no money): empty, even with a stock passed", same(bl, {}) and same(pl, {}))
local written = { money = 500, [Rules.Flag] = true, collectionBook = Rules.view(b1), collectionBookPaid = { found10 = true } }
local b2, p2 = Rules.fromSave(written, collection)
check("… saved with the flag: its own book and paid milestones", same(b2, b1) and same(p2, { found10 = true }))
local b3, p3 = Rules.fromSave({ money = 500, [Rules.Flag] = true, collectionBook = b2, collectionBookPaid = p2 }, CollectionRules.empty())
check("… running it again on what it gave: the same (the stock is not read again)", same(b3, b2) and same(p3, p2))
local b4 = Rules.fromSave({ money = 500, [Rules.Flag] = true }, collection)
check("… flagged but no book in it: the stock's pieces still found (8.3 review: a piece in the stock is always found)", same(b4, b1))
local b5, p5 = Rules.fromSave({ money = 0, [Rules.Flag] = true, collectionBook = { sofa = { n = "x" }, tv = { n = 2, best = 0.5 } }, collectionBookPaid = "all" }, collection)
check("… a garbled book in the save: cleaned, the stock's pieces found again", same(b5, { tv = { n = 2, best = 0.5 }, sofa = { n = 2, best = 0.9 }, jukebox = { n = 1, best = 0.7 } }) and same(p5, {}))
check("the flag is Config's", Rules.Flag == Config.CollectionBook.Flag and Rules.Flag == "collectionBookKept")

-- ── Config ─────────────────────────────────────────────────────────────────
local W = Config.CollectionBook.Window
check("Config.CollectionBook: the key C, the window's numbers, the 3D pictures capped", Config.CollectionBook.Key == "C" and W.Width > 0 and W.Height > 0 and W.Side > 0 and W.Tile > 0
	and Config.CollectionBook.MaxViews >= 1 and Config.CollectionBook.MaxViews <= 24 and Config.CollectionBook.MaxModels >= Config.CollectionBook.MaxViews)
check("the remote's rate limit (a few a second)", (Config.Robust.Limits :: any).CollectionBook ~= nil and (Config.Robust.Limits :: any).CollectionBook >= 1 and (Config.Robust.Limits :: any).CollectionBook <= 10)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
