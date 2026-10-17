-- 8.7 SANDBOX, trading between players: the rules (shared/PlayerTradeRules.luau, Config.PlayerTrade) and what the save
-- keeps (shared/CollectionRules.luau's `sale`). Checked: the numbers (1 × … 10 ×, an 8 % fee, the presets within them);
-- a piece's value (its price to the game without the market: the same every day); the price bounds; clamp and check
-- (whole dollars within the bounds, junk refused); the fee and what the seller keeps (rounded to the dollar, fee + net
-- = the price); the −/+ step (the roundest 1, 2, 5 × 10ⁿ under 10 % of the price, never under the value's) and nudge
-- (clamped, back the way it went); the presets (1×, 1.5×, 2×, 3×, clamped, their labels); the words (the seller's
-- toast, the deal's toasts, a big sale's line, the card's lines for a player's offer); the client's reading of the
-- server's messages; the save: a sign kept only on a piece on show, junk dropped, an older save without it, a level
-- down's fitStands takes it off with the piece, the client's View carries it; selling to a player beats the game.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local CollectionRules = require("./CollectionRules")
local Market = require("./Market")
local Visitors = require("./Visitors")
local Rules = require("./PlayerTradeRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.PlayerTrade

-- ── The numbers ────────────────────────────────────────────────────────────
do
	local ascending = true
	for index, times in T.Presets do
		ascending = ascending and times >= T.MinTimes and times <= T.MaxTimes and (index == 1 or times > T.Presets[index - 1])
	end
	check("Config.PlayerTrade: on, 1 × … 10 × the value, an 8 % fee, 45 s to answer, a few offers a seller",
		T.On == true and T.MinTimes == 1 and T.MaxTimes == 10 and T.Fee == 0.08 and T.Expire == 45 and T.PerSeller >= 1 and T.PerSeller <= 5)
	check("… the presets 1×, 1.5×, 2×, 3×, rising, within the bounds", #T.Presets == 4 and T.Presets[1] == 1 and T.Presets[2] == 1.5 and ascending)
	check("… the rate limits in Config.Robust.Limits (the remote; a new offer every 5 s at most)", Config.Robust.Limits.PlayerTrade >= 1
		and Config.Robust.Limits.TradeOffer > 0 and 1 / Config.Robust.Limits.TradeOffer >= 3)
	check("… a big sale's line from $2,500; the prompts' tag and attribute", T.BigSale == 2500 and type(T.PromptTag) == "string" and type(T.SellerAttribute) == "string"
		and T.PromptTag ~= Config.Cargo.PromptTag)
end

-- ── A piece's value ────────────────────────────────────────────────────────
do
	local gramophone = { item = "gramophone", condition = 0.9 }
	local value = Rules.value(gramophone)
	check("value: the game's price without the market (CollectionRules.sell: its condition in it)", value == CollectionRules.sell(gramophone) and value >= 1, value)
	local market = Market.view(nil, Market.dayOf(1760000000), 1760000000)
	check("… the same whatever the market says (a sign's price stays allowed)", Rules.value(gramophone) == value and CollectionRules.sell(gramophone, market) ~= nil)
	check("… a better condition is worth more, a broken piece its scrap", Rules.value({ item = "gramophone", condition = 1 }) > Rules.value({ item = "gramophone", condition = 0.5 })
		and Rules.value({ item = "gramophone", condition = 0 }) == CollectionRules.sell({ item = "gramophone", condition = 0 }))
end

-- ── Bounds, clamp, check ───────────────────────────────────────────────────
do
	local least, most = Rules.bounds(800)
	check("bounds: $800 → $800 … $8,000", least == 800 and most == 8000, `{least} {most}`)
	local l1, m1 = Rules.bounds(1)
	local l0, m0 = Rules.bounds(0)
	local ln, mn = Rules.bounds(0 / 0)
	check("… $1 → $1 … $10; nothing or NaN as $1", l1 == 1 and m1 == 10 and l0 == 1 and m0 == 10 and ln == 1 and mn == 10)
	check("clamp: under → the least, over → the most, a fraction rounded, junk → the least",
		Rules.clamp(10, 800) == 800 and Rules.clamp(99999, 800) == 8000 and Rules.clamp(1234.6, 800) == 1235 and Rules.clamp(0 / 0, 800) == 800
		and Rules.clamp(nil, 800) == 800 and Rules.clamp("900", 800) == 800)
	local ok = Rules.check(1200, 800)
	local low, lowWhy = Rules.check(799, 800)
	local high, highWhy = Rules.check(8001, 800)
	local frac, fracWhy = Rules.check(900.5, 800)
	local junk = Rules.check("900", 800)
	local nan = Rules.check(0 / 0, 800)
	check("check: a whole price within the bounds", ok and Rules.check(800, 800) and Rules.check(8000, 800))
	check("… under or over: refused, the words name the bounds", not low and not high and lowWhy == "Price it between $800 and $8,000." and highWhy == lowWhy, lowWhy)
	check("… a fraction, a string, NaN: no price", not frac and fracWhy == "That's no price." and not junk and not nan)
end

-- ── The fee ────────────────────────────────────────────────────────────────
do
	check("fee: 8 % rounded to the dollar ($1,200 → $96, $13 → $1, $5 → $0)", Rules.fee(1200) == 96 and Rules.fee(13) == 1 and Rules.fee(5) == 0
		and Rules.fee(1250) == 100 and Rules.fee(19) == 2)
	check("net: the seller keeps the rest ($1,200 → $1,104)", Rules.net(1200) == 1104)
	local sums = true
	for price = 1, 3000, 7 do
		sums = sums and Rules.fee(price) + Rules.net(price) == price and Rules.fee(price) >= 0 and Rules.fee(price) <= price
	end
	check("… fee + net = the price for every price; never negative", sums)
	check("… junk: no fee", Rules.fee(0) == 0 and Rules.fee(-5) == 0 and Rules.fee(0 / 0) == 0 and Rules.net(0 / 0) == 0)
end

-- ── The step, nudge, the presets ───────────────────────────────────────────
do
	check("step: the roundest 1, 2, 5 × 10ⁿ under 10 % ($800 → $50, $1,000 → $100, $150 → $10, $25 → $2, $12 → $1)",
		Rules.step(800) == 50 and Rules.step(1000) == 100 and Rules.step(150) == 10 and Rules.step(25) == 2 and Rules.step(12) == 1 and Rules.step(0) == 1, Rules.step(800))
	check("nudge: + a step, − back; never out of the bounds", Rules.nudge(800, 800, 1) == 850 and Rules.nudge(850, 800, -1) == 800
		and Rules.nudge(800, 800, -1) == 800 and Rules.nudge(8000, 800, 1) == 8000 and Rules.nudge(7990, 800, 1) == 8000)
	local back = true
	for _, value in { 1, 3, 12, 37, 144, 800, 1400 } do
		local least, most = Rules.bounds(value)
		local price = least
		for _ = 1, 40 do
			local up = Rules.nudge(price, value, 1)
			-- (a step that hits the most is cut there: back down from it goes a whole step)
			back = back and up >= price and up <= most and (up == price or up == most or Rules.nudge(up, value, -1) == price)
			price = up
		end
	end
	check("… up and down again lands where it was, all the way up (any value)", back)
	local taps, price = 0, Rules.presets(800)[4].price
	while price < 8000 and taps < 100 do
		price = Rules.nudge(price, 800, 1)
		taps += 1
	end
	check("… from the 3× preset to 10 × in a couple of dozen taps at most", price == 8000 and taps <= 24, taps)
	local presets = Rules.presets(800)
	check("presets: 1×, 1.5×, 2×, 3× of $800 → $800, $1,200, $1,600, $2,400", #presets == 4 and presets[1].label == "1×" and presets[2].label == "1.5×"
		and presets[3].label == "2×" and presets[4].label == "3×" and presets[1].price == 800 and presets[2].price == 1200 and presets[3].price == 1600
		and presets[4].price == 2400)
	local tiny = Rules.presets(1)
	check("… clamped and whole for a $1 piece", tiny[1].price == 1 and tiny[2].price == 2 and tiny[4].price == 3)
	check("times: ×1.5, ×2, ×10", Rules.times(1200, 800) == "×1.5" and Rules.times(1600, 800) == "×2" and Rules.times(8000, 800) == "×10" and Rules.times(5, 0) == "×1")
end

-- ── The words ──────────────────────────────────────────────────────────────
do
	check("the seller's toast: \"🧑 Ann offers $1,200 for your Gramophone (worth $800)\"", Rules.offerToast("Ann", 1200, "Gramophone", 800) == "🧑 Ann offers $1,200 for your Gramophone (worth $800)")
	check("the deal's toasts: sold (the fee in it), bought", Rules.soldToast("Gramophone", "Ann", 1200, 96) == "🤝 Sold Gramophone to Ann for $1,200 (fee $96)"
		and Rules.boughtToast("Gramophone", "Bob", 1200) == "📦 Bought Gramophone from Bob for $1,200")
	check("a big sale: from BigSale on, its chat line", Rules.isBig(2500) and not Rules.isBig(2499) and Rules.news("Bob", "Ann", "Gold Record", 4000) == "🤝 Bob sold the Gold Record to Ann for $4,000!")
	local offer = Visitors.readOffer({ kind = "offer", id = "t1", name = "Gramophone", item = "gramophone", price = 1200, base = 800, who = "Ann", seconds = 45, rarity = "rare", player = true })
	local lines = if offer then Visitors.cardLines(offer) else nil
	check("the offer card reads a player's offer (player kept) and words it: \"🧑 Ann offers\", \"Worth $800 · +50%\"", offer ~= nil and offer.player == true and lines ~= nil
		and lines.who == "🧑 Ann offers" and lines.price == "$1,200" and lines.item == "for your Gramophone" and lines.market == "Worth $800 · +50%", lines and lines.market)
	local npc = Visitors.readOffer({ kind = "offer", id = "o1", name = "Gramophone", item = "gramophone", price = 340, base = 260, who = "Collector", seconds = 30, player = "yes" })
	check("… a visitor's stays a visitor's (player only for true)", npc ~= nil and npc.player == nil and Visitors.cardLines(npc :: any).who == "The collector offers")
end

-- ── The client's reading of the server's messages ─────────────────────────
do
	local raw = { kind = "compose", seller = 22, sellerName = "Bob", uid = "22-5", stand = 3, name = "Gramophone", item = "gramophone", rarity = "rare",
		condition = 0.9, value = 800, income = 6.4, isNew = true, sale = 2000, money = 3400 }
	local piece = Rules.readPiece(raw)
	check("readPiece: the composer's piece, its bounds worked out from its value", piece ~= nil and piece.kind == "compose" and piece.least == 800 and piece.most == 8000
		and piece.isNew and piece.sale == 2000 and piece.money == 3400 and piece.stand == 3 and piece.seller == 22)
	local confirm = table.clone(raw)
	confirm.kind = "confirm"
	check("… a buy question needs its price", Rules.readPiece(confirm) == nil)
	confirm.price = 2000
	check("… with it: read", (Rules.readPiece(confirm) :: any).price == 2000)
	local bad = 0
	for _, change in { { "kind", "steal" }, { "uid", 5 }, { "value", 0 }, { "value", 0 / 0 }, { "stand", 0 }, { "seller", "x" }, { "name", string.rep("x", 99) } } do
		local copy = table.clone(raw)
		copy[change[1]] = change[2]
		if Rules.readPiece(copy) ~= nil then
			bad += 1
		end
	end
	check("… junk: nil (a strange kind, uid, value, stand, seller, a long name)", bad == 0 and Rules.readPiece(nil) == nil and Rules.readPiece("compose") == nil, bad)
	local odd = table.clone(raw)
	odd.condition, odd.income, odd.rarity, odd.isNew, odd.sale, odd.money = 7, -3, 42, "yes", -1, 0 / 0
	local read = Rules.readPiece(odd)
	check("… odd fields mended (condition 0 … 1, no income under 0, common, not new, no sale, no money)", read ~= nil and read.condition == 1 and read.income == 0
		and read.rarity == "common" and read.isNew == false and read.sale == nil and read.money == nil)
end

-- ── The save: the FOR SALE sign (10.4: a sign is the showroom's: its stands past Config.Showroom.Base) ─
do
	local S = Config.Showroom.Base
	local saved = CollectionRules.clean({ entries = {
		{ uid = "1-1", item = "gramophone", variant = 1, condition = 0.9, name = "Gramophone", stand = S + 1, got = 1, sale = 1200 },
		{ uid = "1-2", item = "sofa", variant = 1, condition = 1, name = "Sofa", got = 2, sale = 500 }, -- (in the stock: no sign)
		{ uid = "1-3", item = "radio", variant = 1, condition = 1, name = "Radio", stand = S + 2, got = 3, sale = 0 / 0 },
		{ uid = "1-4", item = "radio", variant = 1, condition = 1, name = "Radio", stand = S + 3, got = 4, sale = 12.5 },
		{ uid = "1-5", item = "radio", variant = 1, condition = 1, name = "Radio", stand = S + 4, got = 5, sale = "900" },
		{ uid = "1-6", item = "radio", variant = 1, condition = 1, name = "Radio", stand = S + 5, got = 6, sale = 2 ^ 41 },
		{ uid = "1-7", item = "radio", variant = 1, condition = 1, name = "Radio", stand = S + 6, got = 7, sale = -5 },
		{ uid = "1-8", item = "radio", variant = 1, condition = 1, name = "Radio", stand = S + 7, got = 8 }, -- (8.6's: none)
	}, nextUid = 9 })
	local e = saved.entries
	check("clean: a sign on a piece on show kept, a whole number of dollars", e[1].sale == 1200)
	check("… none on a piece in the stock; NaN, a fraction, a string, too big, negative: none", e[2].sale == nil and e[3].sale == nil and e[4].sale == nil
		and e[5].sale == nil and e[6].sale == nil and e[7].sale == nil)
	check("… an older save's piece (no field): simply not for sale", e[8].sale == nil and e[8].stand == S + 7)
	local again = CollectionRules.clean(saved)
	check("… clean again: the same", again.entries[1].sale == 1200 and #again.entries == #saved.entries)
	check("fromSave: a real save's signs come back; an older one's collection has none to lose", CollectionRules.fromSave({ money = 10, collectionKept = true, showroomKept = true, collection = saved }).entries[1].sale == 1200
		and #CollectionRules.fromSave({ money = 10, collection = saved }).entries == 0)
	check("saleOf: the save's own check", CollectionRules.saleOf(5) == 5 and CollectionRules.saleOf(0) == nil and CollectionRules.saleOf(1.5) == nil and CollectionRules.saleOf(nil) == nil)
	check("view: the client's View carries the sign", CollectionRules.view(e[1]).sale == 1200 and CollectionRules.view(e[2]).sale == nil)
	local moved = CollectionRules.fitStands(saved, 0, nil, 1)
	check("fitStands (a level down): the pieces that leave their stands lose their signs; the one that stays keeps it", moved >= 1 and e[1].sale == 1200 and e[1].stand == S + 1
		and saved.entries[8].sale == nil and saved.entries[8].stand == nil)
	local sold = { stand = S + 1, sale = 1200, item = "gramophone", condition = 1 }
	CollectionRules.fitStands({ entries = { sold :: any }, nextUid = 2 }, 0)
	check("… and its sign goes with it to the stock", sold.stand == nil and sold.sale == nil)
	check("10.4: a sign on a hall stand is none (clean), and a save from before the showroom (no showroomKept) keeps none", CollectionRules.clean({ entries = { { uid = "1-1", item = "radio", condition = 1, stand = 1, sale = 900 } } }).entries[1].sale == nil
		and CollectionRules.fromSave({ money = 10, collectionKept = true, collection = { entries = { { uid = "1-1", item = "radio", condition = 1, stand = S + 1, sale = 900 } } } }).entries[1].sale == nil)
end

-- ── Selling to a player makes sense ────────────────────────────────────────
do
	local value = Rules.value({ item = "gramophone", condition = 1 })
	local twice = Rules.presets(value)[3].price
	check("at 2 × the value the seller keeps 1.8 × what the game pays (the fee taken)", Rules.net(twice) >= 1.8 * value - 1, `{Rules.net(twice)} {value}`)
	check("… at 1 × a loss (a sign at the game's price is pointless)", Rules.net(Rules.bounds(value)) < value or value < 13)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
