-- 8.2 SANDBOX, the warehouse's quality of life: shared/StockPlan.luau (pure), the rules behind the STOCK list's bulk
-- buttons and the window's orders. The order of the best earners (every tie broken, junk numbers safe), the free stands,
-- ⭐ FILL BEST (the best earners only, nothing on show moved, broken and $0 pieces left, what fits a small stand with
-- the real WarehouseLayout.fits and FurnitureLooks sizes, the small stands for the small pieces so the big ones still
-- go up, idempotent, a fits that errors), 💰 SELL…'s filters (common, broken, duplicates: the best of each item kept,
-- also when it is on show; nothing on show sold; a filter that isn't one), the total, the window's sorts and toggle,
-- the search.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local StockPlan = require("./StockPlan")
local WarehouseLayout = require("./WarehouseLayout")
local FurnitureLooks = require("./FurnitureLooks")
local Config = require("./Config")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function piece(uid: string, item: string, rarity: string, income: number, price: number, extra: { [string]: any }?): StockPlan.Piece
	local p: any = { uid = uid, item = item, rarity = rarity, income = income, price = price, condition = 1, got = 100, broken = false }
	for k, v in extra or {} do
		p[k] = v
	end
	return p
end
local function uids(list: { any }): string
	local out = {}
	for _, p in list do
		table.insert(out, tostring(p.uid))
	end
	return table.concat(out, ",")
end
local function placed(plan: { StockPlan.Placement }): string
	local out = {}
	for _, p in plan do
		table.insert(out, `{p.uid}@{p.stand}`)
	end
	return table.concat(out, ",")
end

-- the real stands: 1 … 12 the big grid, 13 … 20 the upgrades' small ones
local function fits(stand: number, item: string): boolean
	local def = FurnitureLooks.Items[item]
	return def == nil or WarehouseLayout.fits(stand, def.size)
end
check("the real sizes: a double bed fits big stand 1, not small stand 13; a radio fits both", fits(1, "bed") and not fits(13, "bed") and fits(13, "radio") and fits(1, "radio"))

-- ── better ──────────────────────────────────────────────────────────────────
local a = piece("1-1", "sofa", "rare", 7.7, 63)
local b = piece("1-2", "sofa", "rare", 7.7, 63)
check("better: the higher $ a minute first", StockPlan.better(piece("1-9", "x", "common", 2, 1), piece("1-1", "y", "legendary", 1, 900)))
check("… then the rarer", StockPlan.better(piece("1-9", "x", "epic", 2, 1), piece("1-1", "y", "rare", 2, 900)))
check("… then the dearer", StockPlan.better(piece("1-9", "x", "rare", 2, 50), piece("1-1", "y", "rare", 2, 40)))
check("… then the better condition", StockPlan.better(piece("1-9", "x", "rare", 2, 40, { condition = 0.9 }), piece("1-1", "y", "rare", 2, 40, { condition = 0.8 })))
check("… then the older (the lower uid number: 1-2 before 1-10)", StockPlan.better(b, piece("1-10", "sofa", "rare", 7.7, 63)) and StockPlan.better(a, b) and not StockPlan.better(b, a))
check("… a strict order (never a before itself)", not StockPlan.better(a, a))
local junk = piece("1-3", "sofa", "rare", 0 / 0, math.huge, { condition = "x" })
local sortedJunk = { junk, a, b, piece("1-4", "tv", "common", 1, 5) }
local okSort = pcall(table.sort, sortedJunk, StockPlan.better)
check("junk numbers (NaN, inf, a string) count as 0: a sort doesn't break", okSort and sortedJunk[#sortedJunk] == junk, uids(sortedJunk))

-- ── free and FILL BEST ──────────────────────────────────────────────────────
local stock = {
	piece("a-1", "piano", "epic", 31.2, 288, { stand = 2 }),
	piece("a-2", "sofa", "rare", 7.7, 63),
	piece("a-3", "grandfather_clock", "epic", 22.2, 205),
	piece("a-4", "tv", "rare", 0, 9, { broken = true, condition = 0.1 }),
	piece("a-5", "dining_chair", "common", 0.6, 6),
	piece("a-6", "radio", "uncommon", 1.5, 14),
	piece("a-7", "box", "common", 0, 1),
}
check("free: the stands no piece holds (stand 2 holds the piano)", table.concat(StockPlan.free(stock, 4), ",") == "1,3,4")
check("… a stand count that is no number: none", #StockPlan.free(stock, 0 / 0) == 0 and #StockPlan.free(stock, -3) == 0)
local plan = StockPlan.fill(stock, 4, fits)
check("fill: the best earners of the stock onto the free stands (clock, sofa, radio on 1, 3, 4)", placed(plan) == "a-3@1,a-2@3,a-6@4", placed(plan))
plan = StockPlan.fill(stock, 12, fits)
check("… more free stands than pieces: every earning piece, never the broken TV nor the $0 box, the piano not moved", placed(plan) == "a-3@1,a-2@3,a-6@4,a-5@5", placed(plan))
check("… nothing free: nothing", #StockPlan.fill({ piece("b-1", "sofa", "rare", 7.7, 63, { stand = 1 }), piece("b-2", "tv", "rare", 3, 90, { stand = 2 }), piece("b-3", "piano", "epic", 31.2, 288) }, 2, fits) == 0)
check("… an empty stock: nothing", #StockPlan.fill({}, 20, fits) == 0)
-- idempotent: the plan applied, a second fill changes nothing
local applied = table.clone(stock)
for index, p in applied do
	applied[index] = table.clone(p)
end
for _, place in StockPlan.fill(applied, 6, fits) do
	for _, p in applied do
		if p.uid == place.uid then
			p.stand = place.stand
		end
	end
end
check("… applied, a second fill does nothing (idempotent)", #StockPlan.fill(applied, 6, fits) == 0)

-- the upgrades' small stands: 12 big ones full, 13 and 14 free
local hall = {}
for i = 1, 12 do
	table.insert(hall, piece(`h-{i}`, "sofa", "rare", 7.7, 63, { stand = i }))
end
local only = table.clone(hall)
table.insert(only, piece("h-20", "bed", "rare", 12, 90))
table.insert(only, piece("h-21", "hay_wagon", "epic", 15, 160))
check("small stands: the bed and the hay wagon don't fit 13 / 14: nothing to do", #StockPlan.fill(only, 14, fits) == 0)
table.insert(only, piece("h-22", "radio", "uncommon", 1.5, 14))
check("… a radio does: it goes on 13 (the beds stay in the stock)", placed(StockPlan.fill(only, 14, fits)) == "h-22@13", placed(StockPlan.fill(only, 14, fits)))
-- stands 1 (big) and 13 (small) free; the best piece is small, the next a bed: best-first onto stand 1 would leave the
-- bed in the stock, so the small stand takes the small piece and both go up
local mixed = {
	piece("m-1", "radio", "uncommon", 20, 14),
	piece("m-2", "bed", "rare", 12, 90),
}
local twoFree = table.clone(mixed)
for i = 2, 12 do
	table.insert(twoFree, piece(`t-{i}`, "dining_chair", "common", 0.5, 1, { stand = i }))
end
check("the small stand takes the small piece, the big one the bed: the radio on 13, the bed on 1 (both up)", placed(StockPlan.fill(twoFree, 13, fits)) == "m-1@13,m-2@1", placed(StockPlan.fill(twoFree, 13, fits)))
local cranky = StockPlan.fill(mixed, 2, function(stand)
	if stand == 1 then
		error("no")
	end
	return true
end)
check("a fits that errors counts as no", placed(cranky) == "m-1@2", placed(cranky))

-- ── 💰 SELL… ────────────────────────────────────────────────────────────────
check("the filters, in the menu's order", table.concat(StockPlan.Filters, ",") == "common,broken,duplicates")
check("isFilter: only them", StockPlan.isFilter("common") and StockPlan.isFilter("broken") and StockPlan.isFilter("duplicates") and not StockPlan.isFilter("all") and not StockPlan.isFilter(nil) and not StockPlan.isFilter(5) and not StockPlan.isFilter({}))
check("their words", StockPlan.filterName("common") == "ALL COMMON" and StockPlan.filterName("broken") == "ALL BROKEN" and StockPlan.filterName("duplicates") == "DUPLICATES")
local shelf = {
	piece("s-1", "dining_chair", "common", 0.6, 6, { stand = 1 }),
	piece("s-2", "dining_chair", "common", 0.5, 5),
	piece("s-3", "dining_chair", "common", 0.6, 6, { condition = 0.9 }),
	piece("s-4", "box", "common", 0, 1),
	piece("s-5", "tv", "rare", 0, 9, { broken = true }),
	piece("s-6", "tv", "rare", 3, 90),
	piece("s-7", "sofa", "rare", 7.7, 63),
	piece("s-8", "sofa", "rare", 0, 2, { broken = true, stand = 3 }),
	piece("s-9", "piano", "epic", 31.2, 288),
}
check("common: every Common piece in the stock (not the chair on show), best first", uids(StockPlan.toSell(shelf, "common")) == "s-3,s-2,s-4", uids(StockPlan.toSell(shelf, "common")))
check("broken: every broken piece in the stock (not the sofa on show)", uids(StockPlan.toSell(shelf, "broken")) == "s-5", uids(StockPlan.toSell(shelf, "broken")))
check("duplicates: all but the best of each item (the chair on show is the best chair; the good TV and the sofa kept; never a piece on show)", uids(StockPlan.toSell(shelf, "duplicates")) == "s-3,s-2,s-5", uids(StockPlan.toSell(shelf, "duplicates")))
check("… the best in the stock is kept when it beats the one on show", uids(StockPlan.toSell({ piece("d-1", "sofa", "rare", 7.7, 63), piece("d-2", "sofa", "rare", 3, 30, { stand = 1 }), piece("d-3", "sofa", "rare", 2, 20) }, "duplicates")) == "d-3")
check("… one of each: nothing", #StockPlan.toSell({ piece("d-1", "sofa", "rare", 7.7, 63), piece("d-4", "tv", "rare", 3, 30) }, "duplicates") == 0)
check("a filter that isn't one sells nothing", #StockPlan.toSell(shelf, "all") == 0 and #StockPlan.toSell(shelf, nil) == 0 and #StockPlan.toSell(shelf, { "common" }) == 0)
check("price: the total ($6 + $5 + $1)", StockPlan.price(StockPlan.toSell(shelf, "common")) == 12 and StockPlan.price({}) == 0 and StockPlan.price({ piece("p", "x", "common", 0, 0 / 0) }) == 0)

-- ── The window's orders and its search ─────────────────────────────────────
check("the sorts, in the toggle's order, with their words", table.concat(StockPlan.Sorts, ",") == "income,value,newest,rarity" and StockPlan.sortLabel("income") == "$/MIN" and StockPlan.sortLabel("value") == "VALUE" and StockPlan.sortLabel("newest") == "NEWEST" and StockPlan.sortLabel("rarity") == "RARITY" and StockPlan.sortLabel("nope") == "$/MIN")
check("the toggle goes round", StockPlan.nextSort("income") == "value" and StockPlan.nextSort("value") == "newest" and StockPlan.nextSort("newest") == "rarity" and StockPlan.nextSort("rarity") == "income" and StockPlan.nextSort(nil) == "value" and StockPlan.nextSort("junk") == "income")
local list = {
	piece("o-1", "piano", "epic", 31.2, 288, { got = 50 }),
	piece("o-2", "gold_record", "legendary", 20, 600, { got = 70 }),
	piece("o-3", "sofa", "rare", 7.7, 900, { got = 70 }),
	piece("o-4", "box", "common", 0.1, 1, { got = 90 }),
}
local function sortedBy(by: string?): string
	local copy = table.clone(list)
	table.sort(copy, StockPlan.order(by))
	return uids(copy)
end
check("$/MIN: the best earners first", sortedBy("income") == "o-1,o-2,o-3,o-4", sortedBy("income"))
check("VALUE: the dearest first", sortedBy("value") == "o-3,o-2,o-1,o-4", sortedBy("value"))
check("NEWEST: came home last first (one trip: the later uid first)", sortedBy("newest") == "o-4,o-3,o-2,o-1", sortedBy("newest"))
check("RARITY: the rarest first", sortedBy("rarity") == "o-2,o-1,o-3,o-4", sortedBy("rarity"))
check("an unknown order: $/MIN's", sortedBy("junk") == sortedBy("income") and sortedBy(nil) == sortedBy("income"))
check("search: every word, any case, anywhere in the name", StockPlan.matches("Grandpa's Clock", "clock") and StockPlan.matches("Grandpa's Clock", "GRAND clo") and not StockPlan.matches("Grandpa's Clock", "clock sofa"))
check("… an empty query (or none) matches everything; a pattern is plain text", StockPlan.matches("Sofa", "") and StockPlan.matches("Sofa", "   ") and StockPlan.matches("Sofa", nil) and not StockPlan.matches("Sofa", "s.f") and StockPlan.matches("50% off", "50%"))
check("Config: a tier for every rarity the filters read", Config.Collection.Tiers.common ~= nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
