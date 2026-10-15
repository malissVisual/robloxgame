-- 8.8 SANDBOX, the auction's rules (shared/AuctionRules.luau, Config.Auction; design/auction/PLAN.md): off by default;
-- the round's schedule (the same on every server) and its 3 – 5 minutes; a lot's price (its worth, the steps, the
-- opening), its clock and the anti-snipe extension; the bids (the next step only, never your own piece, never while you
-- lead, never more than your money); the NPC collectors (seeded, each stops at its max, the keenest at least the
-- opening: every lot sells, never under its worth; rarer and hot pieces dearer); who wins and what the seller gets and
-- pays (the fee, a player who can't pay, the house's lots), the money's reasons in AnalyticsPlan; who may consign what;
-- the Grand Auction's hooks; the client's view checked and its words; and the point of it all: a piece sells there for
-- many times what the game pays. Run with tests/run_tests.py.
local Config = require("./Config")
local Rules = require("./AuctionRules")
local CollectionRules = require("./CollectionRules")
local AnalyticsPlan = require("./AnalyticsPlan")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local A = Config.Auction

local function entry(uid: string, item: string, condition: number): CollectionRules.Entry
	return { uid = uid, item = item, variant = 1, condition = condition, name = (CollectionRules.defOf(item) :: any).name, got = 0 }
end

-- ── The numbers ────────────────────────────────────────────────────────────
do
	check("off by default: nothing of the auction shows until the server's step lands", A.On == false)
	local nominal = A.MaxLots * A.LotSeconds + (A.MaxLots - 1) * A.Gap
	check(`a full round lasts 3 – 5 minutes ({nominal} s as planned, {Rules.span()} s with every lot extended to the most)`, nominal >= 180 and Rules.span() <= 300 and Rules.span() == A.MaxLots * (A.LotSeconds + A.Snipe.Most) + (A.MaxLots - 1) * A.Gap)
	check("about every half an hour, the round, its results and the closing fit in the gap", A.Every == 1800 and Rules.span() + A.Results + A.Close < A.Every)
	check("one lot a player on a full server", A.MaxLots == Config.Sandbox.MaxPlayers)
	check("a lot ~45 s; a bid in its last seconds extends it a few seconds", A.LotSeconds >= 30 and A.LotSeconds <= 60 and A.Snipe.Window >= 5 and A.Snipe.Window <= 12 and A.Snipe.Most >= A.Snipe.Window)
	local tiersOk = true
	for _, id in A.Rarities do
		tiersOk = tiersOk and Config.Collection.Tiers[id] ~= nil and Config.Collection.Tiers[id].rank >= 3
	end
	check("rare, epic and legendary may be consigned (Config.Collection's tiers, rare and up)", tiersOk and table.concat(A.Rarities, ",") == "rare,epic,legendary")
	local ascending = true
	for i = 2, #A.Steps do
		ascending = ascending and A.Steps[i][1] > A.Steps[i - 1][1] and A.Steps[i][2] >= A.Steps[i - 1][2]
	end
	check("the bid steps grow with the price", ascending and A.Steps[1][1] == 0)
	check("the fee: 8 % (the trades' once Config.PlayerTrade has one)", A.Fee == 0.08 and Rules.feeRate() == (if (Config :: any).PlayerTrade and (Config :: any).PlayerTrade.Fee then (Config :: any).PlayerTrade.Fee else 0.08))
	local C = A.Collectors
	local seen: { [string]: boolean } = {}
	local unique = true
	for _, name in C.Names do
		unique = unique and not seen[name]
		seen[name] = true
	end
	check("the collectors: 3 a lot from more distinct names, their dice in order, the rarer the keener", C.Count == 3 and #C.Names > C.Count and unique and C.Spread[1] < C.Spread[2] and C.Delay[1] < C.Delay[2]
		and C.Rarity.rare < C.Rarity.epic and C.Rarity.epic < C.Rarity.legendary and C.Hot > 1 and C.Cold < 1)
	check("the reserve: never under the piece's worth", A.Reserve >= 1)
	check("the Grand Auction: hooks only, off", A.Grand.On == false and #A.Grand.Items == 0 and A.Grand.Reserve >= 1)
end

-- ── The round's schedule ────────────────────────────────────────────────────
do
	local round = 1000000
	local start = Rules.startOf(round)
	check("rounds start every Every s from Offset (00:00 UTC)", start == A.Offset + round * A.Every and Rules.roundOf(start) == round and Rules.roundOf(start - 1) == round - 1 and Rules.roundOf(start + A.Every - 1) == round)
	local live = Rules.phase(start + 10)
	check("just after a start: live (that round), until its lots end", live.name == "live" and live.round == round and live.startsAt == start and live.endsAt == start + Rules.span() and live.left == Rules.span() - 10)
	local results = Rules.phase(start + Rules.span() + 5)
	check("then its results for Results s", results.name == "results" and results.round == round and results.endsAt == start + Rules.span() + A.Results)
	local consign = Rules.phase(start + Rules.span() + A.Results + 1)
	check("then consignments for the next round, until Close s before it", consign.name == "consign" and consign.round == round + 1 and consign.startsAt == start + A.Every and consign.endsAt == start + A.Every - A.Close)
	local closing = Rules.phase(start + A.Every - 5)
	check("the last Close s: closing", closing.name == "closing" and closing.round == round + 1 and closing.left == 5)
	local early = Rules.phase(start + 100, start + 90)
	check("the server's real end (its lots done early): results from then", early.name == "results" and early.endsAt == start + 90 + A.Results)
	local none = Rules.phase(start + 1, start)
	check("a round without lots (ended at its start): straight back to consigning", none.name == "consign" and none.round == round + 1)
	local silly = Rules.phase(start + 10, start + 99999)
	check("an end past the round's longest is not believed", silly.name == "live" and silly.endsAt == start + Rules.span())
end

-- ── A lot's price ───────────────────────────────────────────────────────────
do
	local knight = entry("1-1", "knight_armour", 0.9)
	check("a piece's worth: its value × its condition (Knight's Armour $5,500 at 90 %: $4,950)", Rules.worthOf(knight) == 4950)
	check("the steps by the price's band", Rules.step(0) == 25 and Rules.step(499) == 25 and Rules.step(500) == 50 and Rules.step(1500) == 100 and Rules.step(2500) == 200 and Rules.step(6000) == 250 and Rules.step(12000) == 500 and Rules.step(40000) == 1000)
	check("an amount up to a whole step", Rules.roundUp(4950) == 5000 and Rules.roundUp(1610) == 1700 and Rules.roundUp(1600) == 1600 and Rules.roundUp(3) == 25 and Rules.roundUp(0) == 25)
	local okAll = true
	for worth = 1, 30000, 37 do
		local opening = Rules.opening(worth)
		okAll = okAll and opening >= Rules.reserve(worth) and Rules.reserve(worth) >= worth and opening % Rules.step(Rules.reserve(worth)) == 0
			and opening - Rules.reserve(worth) < Rules.step(Rules.reserve(worth))
	end
	check("a lot opens at its worth or a little over (a whole step), never under", okAll)
	local view = { day = 0, hot = { "knight_armour" }, cold = {}, left = 0, demand = {} }
	local lot = Rules.lotOf(knight, 14, "Ann", view :: any, 77)
	check("a player's piece as a lot: its seller, rarity, worth, opening, the day's market and its $/min (no boost)", lot.seller == 14 and lot.sellerName == "Ann" and lot.uid == "1-1" and lot.rarity == "legendary"
		and lot.worth == 4950 and lot.opening == 5000 and lot.market == "hot" and math.abs(lot.income - CollectionRules.income(knight, 1, view :: any)) < 0.01 and not lot.opened and #lot.bids == 0)
	local vase = Rules.lotOf(entry("2-1", "antique_vase", 1), 15, "Ben", nil, 78)
	local record = Rules.lotOf(entry("3-1", "gold_record", 1), 16, "Cy", nil, 79)
	local record2 = Rules.lotOf(entry("3-2", "gold_record", 1), 17, "Di", nil, 80)
	local ordered = Rules.order({ lot, record, vase, record2 })
	check("the round's order: the cheapest first, the best last; a tie keeps who came first; ids 1 … n", ordered[1] == record and ordered[2] == record2 and ordered[3] == vase and ordered[4] == lot
		and ordered[1].id == 1 and ordered[4].id == 4)
	local house = Rules.houseLot("oil_painting", 1, 9)
	check("a house lot (the Grand Auction's): no seller, opening at Grand.Reserve × its worth", house.seller == nil and house.sellerName == "The house" and house.opening >= 6000 * A.Grand.Reserve and house.rarity == "legendary")
	check("seeds: whole, ≥ 1, apart for other rounds, places and pieces", Rules.seedOf(5, 1, "a") >= 1 and Rules.seedOf(5, 1, "a") ~= Rules.seedOf(6, 1, "a") and Rules.seedOf(5, 1, "a") ~= Rules.seedOf(5, 2, "a")
		and Rules.seedOf(5, 1, "a") ~= Rules.seedOf(5, 1, "b") and Rules.seedOf(5, 1, "a") == Rules.seedOf(5, 1, "a"))
end

-- ── A lot's clock and its bids ──────────────────────────────────────────────
local function freshLot(item: string, seller: number?, seed: number?): Rules.Lot
	local lot = Rules.lotOf(entry("9-" .. item, item, 1), seller, "Seller", nil, seed or 4242)
	return lot
end
do
	local lot = freshLot("antique_vase", 14)
	check("not open yet: no time left, no bids", not Rules.isOpen(lot, 100) and Rules.left(lot, 100) == 0)
	Rules.open(lot, 100)
	check("open: LotSeconds on its clock, its latest Snipe.Most s past", lot.opensAt == 100 and lot.endsAt == 100 + A.LotSeconds and lot.latest == lot.endsAt + A.Snipe.Most and Rules.isOpen(lot, 100) and Rules.left(lot, 110) == A.LotSeconds - 10)
	check("no extension for a bid with time left", not Rules.extend(lot, 110) and lot.endsAt == 100 + A.LotSeconds)
	local late = lot.endsAt - 3
	check("a bid 3 s before the end: the clock back to Window s", Rules.extend(lot, late) and lot.endsAt == late + A.Snipe.Window)
	local guard = 0
	while Rules.extend(lot, lot.endsAt - 1) and guard < 100 do
		guard += 1
	end
	check("…but never past its latest (a sniping war ends)", lot.endsAt == lot.latest and guard < 100, lot.endsAt)
	check("closed at its end", not Rules.isOpen(lot, lot.endsAt) and Rules.left(lot, lot.endsAt + 5) == 0)
end
do
	local lot = freshLot("antique_vase", 14)
	local ok, why = Rules.canBid(lot, 20, lot.opening, 1e6, 100)
	check("no bid before the lot is up", not ok and why == "This lot isn't up yet.")
	Rules.open(lot, 100)
	check("the first bid is the opening price", Rules.nextBid(lot) == lot.opening and lot.opening == 3000)
	ok, why = Rules.canBid(lot, 14, lot.opening, 1e6, 101)
	check("never on your own piece", not ok and why == "You can't bid on your own piece.")
	ok, why = Rules.canBid(lot, 20, lot.opening + 200, 1e6, 101)
	check("only the next step (a stale or a bigger amount: refused, the next bid said)", not ok and why == "Someone bid first: the next bid is $3,000.", why)
	ok, why = Rules.canBid(lot, 20, lot.opening, 2900, 101)
	check("never more than your money (how much is missing)", not ok and why == "You need $100 more.", why)
	ok = Rules.canBid(lot, 20, lot.opening, 3000, 101)
	check("the next step with the money: a bid", ok)
	Rules.place(lot, { by = 20, name = "Zed", npc = false, amount = 3000, at = 101 })
	check("placed: the price, the leader, the next step ($3,000 + $200)", lot.price == 3000 and (Rules.leader(lot) :: any).by == 20 and Rules.nextBid(lot) == 3200)
	ok, why = Rules.canBid(lot, 20, 3200, 1e6, 102)
	check("never while you lead", not ok and why == "You're the top bidder already.")
	ok, why = Rules.canBid(lot, 21, 3200, 1e6, lot.endsAt)
	check("never after the hammer", not ok and why == "Too late: the hammer has fallen on this lot.")
end

-- ── The collectors ──────────────────────────────────────────────────────────
do
	local lot = freshLot("knight_armour", 14, 99)
	local a, b = Rules.collectors(lot), Rules.collectors(lot)
	local same, names, distinct = #a == A.Collectors.Count, {}, true
	for i, c in a do
		same = same and c.name == b[i].name and c.max == b[i].max and c.index == i
		distinct = distinct and not names[c.name] and table.find(A.Collectors.Names, c.name) ~= nil
		names[c.name] = true
	end
	check("seeded: the same lot, the same collectors and maxes; their names distinct, from Config", same and distinct)
	local top = 0
	for _, c in a do
		top = math.max(top, c.max)
	end
	check("the keenest goes at least to the opening price", top >= lot.opening)
	local other = Rules.collectors(freshLot("knight_armour", 14, 100))
	local differs = false
	for i, c in other do
		differs = differs or c.max ~= a[i].max
	end
	check("another seed, other maxes", differs)
	check("nothing before the lot opens", Rules.npcNext(lot, a) == nil)
	Rules.open(lot, 1000)
	local nb = Rules.npcNext(lot, a) :: Rules.NpcBid
	check("the first collector's bid: the opening price, within Delay s", nb ~= nil and nb.amount == lot.opening and nb.at >= 1000 + A.Collectors.Delay[1] and nb.at <= 1000 + A.Collectors.Delay[2] + 1e-9)
	Rules.place(lot, { by = Rules.npcKey(nb.index), name = nb.name, npc = true, amount = nb.amount, at = nb.at })
	local again = Rules.npcNext(lot, a)
	check("a collector never outbids itself", again == nil or again.index ~= nb.index)
	-- push the price past every max: no collector goes on
	lot.price = top
	table.insert(lot.bids, { by = 99, name = "Rich", npc = false, amount = top, at = 1001 })
	check("none goes past its max", Rules.npcNext(lot, a) == nil)
	local tight = freshLot("antique_vase", 14, 5)
	Rules.open(tight, 0)
	local cs = Rules.collectors(tight)
	Rules.place(tight, { by = 77, name = "P", npc = false, amount = tight.opening, at = tight.endsAt - 0.5 })
	local nx = Rules.npcNext(tight, cs)
	check("an answer to a last-second bid comes at once (the extension gives it room)", nx == nil or (nx.at >= tight.endsAt - A.Snipe.Window - 1e-9 and nx.at < tight.endsAt))
end

-- ── A lot played to its end ────────────────────────────────────────────────
local function played(item: string, seed: number, market: string?, players: { Rules.Player }?): (Rules.Lot, { Rules.Collector })
	local lot = Rules.lotOf(entry("8-" .. seed, item, 1), 14, "Seller", if market then { day = 0, hot = if market == "hot" then { item } else {}, cold = if market == "cold" then { item } else {}, left = 0, demand = {} } :: any else nil, seed)
	Rules.open(lot, 0)
	local collectors = Rules.collectors(lot)
	return Rules.play(lot, collectors, players), collectors
end
do
	local lot, collectors = played("knight_armour", 1234, nil)
	local again = played("knight_armour", 1234, nil)
	local same = #lot.bids == #again.bids and lot.price == again.price and lot.endsAt == again.endsAt
	check("deterministic: the same lot plays the same", same and #lot.bids > 0)
	local overMax, order = false, true
	for i, bid in lot.bids do
		local index = tonumber(string.match(tostring(bid.by), "^npc:(%d+)$"))
		local c = if index then collectors[index] else nil
		overMax = overMax or c == nil or bid.amount > c.max
		order = order and (i == 1 or (bid.amount > lot.bids[i - 1].amount and bid.at >= lot.bids[i - 1].at and bid.by ~= lot.bids[i - 1].by))
	end
	check("the collectors alone: each bid a step up, in time, never two in a row by one, never over the bidder's max", not overMax and order)
	check("…and the lot ends by its latest, at or over its opening", lot.endsAt <= lot.latest and lot.price >= lot.opening)
	-- many lots: every one sells at or over its worth; how far over (the design's numbers)
	local function median(list: { number }): number
		table.sort(list)
		return list[math.floor(#list / 2) + 1]
	end
	local ratios: { [string]: { number } } = { rare = {}, epic = {}, legendary = {} }
	local floorOk, endsOk = true, true
	for seed = 1, 400 do
		for item, rarity in { gold_record = "rare", antique_vase = "epic", oil_painting = "legendary" } do
			local l = played(item, seed * 7 + #item, nil)
			local result = Rules.settle(l, Rules.collectors(l))
			floorOk = floorOk and result.price >= l.opening and l.opening >= l.worth
			endsOk = endsOk and l.endsAt <= l.latest
			table.insert(ratios[rarity], result.price / l.worth)
		end
	end
	local mr, me, ml = median(ratios.rare), median(ratios.epic), median(ratios.legendary)
	check(`1,200 lots: every one sells at or over its worth, within its latest`, floorOk and endsOk)
	check(`the collectors pay 5 – 35 % over the worth, the rarer the keener (medians ×{string.format("%.2f", mr)} rare, ×{string.format("%.2f", me)} epic, ×{string.format("%.2f", ml)} legendary)`,
		mr >= 1.0 and ml <= 1.35 and mr < ml and me < ml)
	local hot, cold = {}, {}
	for seed = 1, 200 do
		table.insert(hot, Rules.settle(played("jukebox", seed, "hot"), {}).price)
		table.insert(cold, Rules.settle(played("jukebox", seed, "cold"), {}).price)
	end
	check("a hot piece fetches more than a cold one (the day's market)", median(hot) > median(cold))
	-- a player
	local keen = played("antique_vase", 55, nil, { { by = 20, name = "Zed", max = 100000, delay = 2 } })
	local won = Rules.settle(keen, {})
	check("a player who goes higher than every collector wins, paying a step over the last", won.buyer == 20 and won.winner == "Zed" and not won.npc and won.price <= 100000)
	local shy = played("antique_vase", 55, nil, { { by = 20, name = "Zed", max = 3000, delay = 2 } })
	check("a player whose max is under the keenest collector's loses", Rules.settle(shy, {}).buyer == nil)
	-- a sniper: bids late, the clock goes back
	local snipe = Rules.lotOf(entry("7-1", "jukebox", 1), 14, "S", nil, 31)
	Rules.open(snipe, 0)
	local cs = { { index = 1, name = "Lady Fairbanks", max = 3400 } }
	Rules.play(snipe, cs)
	local before = snipe.endsAt
	Rules.place(snipe, { by = 21, name = "Late", npc = false, amount = Rules.nextBid(snipe), at = before - 1 })
	check("anti-snipe: a bid in the last second puts the clock back Window s", snipe.endsAt == before - 1 + A.Snipe.Window)
end

-- ── The settlement ──────────────────────────────────────────────────────────
do
	local lot = freshLot("antique_vase", 14, 300)
	Rules.open(lot, 0)
	local cs = Rules.collectors(lot)
	local noBids = Rules.settle(lot, cs)
	check("no bid at all: the keenest collector buys it at the opening price", noBids.npc and noBids.price == lot.opening and noBids.buyer == nil and noBids.seller == 14)
	check("the fee: 8 % of the price, rounded; the seller's net the rest", noBids.fee == math.floor(lot.opening * 0.08 + 0.5) and noBids.net == noBids.price - noBids.fee)
	Rules.place(lot, { by = "npc:1", name = cs[1].name, npc = true, amount = 3000, at = 1 })
	Rules.place(lot, { by = 20, name = "Zed", npc = false, amount = 3200, at = 2 })
	Rules.place(lot, { by = 21, name = "Yan", npc = false, amount = 3400, at = 3 })
	local paid = Rules.settle(lot, cs, function(userId: number, amount: number): boolean
		return userId == 20 and amount <= 5000
	end)
	check("the top bidder can't pay (spent it, left): the next bid down that can buys it at its own price", paid.buyer == 20 and paid.price == 3200 and paid.winner == "Zed")
	local nobody = Rules.settle(lot, cs, function(): boolean
		return false
	end)
	check("…no player can: the collector's bid under them", nobody.npc and nobody.price == 3000 and nobody.buyer == nil)
	local pays = Rules.payments(paid)
	local sum = 0
	for _, p in pays do
		if p.userId == 14 then
			sum += p.delta
		end
	end
	check("the payments: the seller +price (AuctionSale) and −fee (AuctionFee), the buyer −price (AuctionBuy)", #pays == 3 and pays[1].reason == "AuctionSale" and pays[1].delta == 3200 and pays[2].reason == "AuctionFee"
		and pays[2].delta == -paid.fee and pays[3].userId == 20 and pays[3].reason == "AuctionBuy" and pays[3].delta == -3200 and sum == paid.net)
	local npcPays = Rules.payments(noBids)
	check("a collector buys: only the seller is paid", #npcPays == 2 and npcPays[1].userId == 14 and npcPays[2].reason == "AuctionFee")
	local house = Rules.houseLot("oil_painting", 1, 10)
	Rules.open(house, 0)
	local hr = Rules.settle(house, Rules.collectors(house))
	check("a house lot: no fee, no seller paid", hr.house and hr.fee == 0 and hr.net == 0 and hr.seller == nil and #Rules.payments(hr) == 0)
	local sale, fee, buy = AnalyticsPlan.money("AuctionSale", 100), AnalyticsPlan.money("AuctionFee", -8), AnalyticsPlan.money("AuctionBuy", -100)
	check("the money's reasons in AnalyticsPlan: AuctionSale a source (Sale), AuctionFee and AuctionBuy sinks", sale.reason == "AuctionSale" and sale.flow == "Source" and sale.kind == "Sale"
		and fee.reason == "AuctionFee" and fee.flow == "Sink" and buy.reason == "AuctionBuy" and buy.flow == "Sink" and buy.kind == "Shop")
	local saved = (Config :: any).PlayerTrade
	;(Config :: any).PlayerTrade = { Fee = 0.1 }
	local shared = Rules.feeRate() == 0.1 and Rules.fee(1000) == 100
	;(Config :: any).PlayerTrade = { Fee = 2 }
	local junk = Rules.feeRate() == A.Fee
	;(Config :: any).PlayerTrade = saved
	check("one fee with the trades: Config.PlayerTrade.Fee once it exists (junk ignored)", shared and junk)
end

-- ── Who may consign what ────────────────────────────────────────────────────
do
	local function can(item: string, condition: number): (boolean, string?)
		return Rules.consignable(entry("5-" .. item, item, condition))
	end
	local ok, why = can("sofa", 1)
	check("a common piece: no", not ok and why == "Only rare, epic or legendary pieces go to auction.", why)
	check("an uncommon one: no", not (can("old_globe", 1)))
	check("rare (a collectible, the piano), epic, legendary: yes", (can("gold_record", 1)) and (can("piano", 1)) and (can("jukebox", 1)) and (can("trex_skull", 0.5)))
	ok, why = can("trex_skull", Config.Collection.BrokenAt)
	check("a broken one: no", not ok and why == "A broken piece can't go to auction.")
	ok, why = Rules.consignable({ item = "nothing_here", condition = 1 })
	check("a piece that left the catalogue: no", not ok and why == "This piece can't go to auction.")
	local piece = entry("14-3", "jukebox", 1)
	ok, why = Rules.canConsign({}, 14, piece, "consign")
	check("in the consignment window: yes", ok and why == nil)
	for phaseName, words in { live = "The auction is on: consign for the next round.", closing = "Consignments are closed: the auction starts in a moment.", results = "The round's results are up: consignments open in a moment." } do
		ok, why = Rules.canConsign({}, 14, piece, phaseName)
		check(`{phaseName}: no ("{words}")`, not ok and why == words, why)
	end
	local mine = Rules.lotOf(entry("14-1", "gold_record", 1), 14, "Ann", nil, 1)
	ok, why = Rules.canConsign({ mine }, 14, piece, "consign")
	check("one piece a round a player", not ok and why == "One piece a round: your Gold Record is in already.", why)
	local full = {}
	for i = 1, A.MaxLots do
		table.insert(full, Rules.lotOf(entry(`{i}-1`, "gold_record", 1), 100 + i, "P", nil, i))
	end
	ok, why = Rules.canConsign(full, 14, piece, "consign")
	check("a full round: try the next one", not ok and why == "This round is full: try the next one.")
end

-- ── The Grand Auction's hooks ───────────────────────────────────────────────
do
	check("off: no Grand Auction", Rules.grandAt(1000) == nil and not Rules.isGrand(19 * 3600))
	A.Grand.On = true
	local at = Rules.grandAt(86400 * 3 + 10)
	local next = Rules.grandAt(86400 * 3 + 20 * 3600)
	check("on: daily at Hour UTC (today's, else tomorrow's)", at == 86400 * 3 + A.Grand.Hour * 3600 and next == 86400 * 4 + A.Grand.Hour * 3600 and Rules.isGrand(at :: number) and not Rules.isGrand(Rules.startOf(1)))
	A.Grand.On = false
end

-- ── The client's view and its words ─────────────────────────────────────────
do
	local lot = freshLot("knight_armour", 14, 12)
	Rules.open(lot, 500)
	Rules.place(lot, { by = 20, name = "Zed", npc = false, amount = lot.opening, at = 501 })
	local mineView = Rules.lotView(lot, 14, true)
	local theirs = Rules.lotView(lot, 20, false)
	check("a lot's view: price, next bid, step, leader, yours / leading / new for your book", mineView.mine and not mineView.leaderMe and mineView.fresh and theirs.leaderMe and not theirs.mine
		and theirs.price == lot.opening and theirs.next == lot.opening + Rules.step(lot.opening) and theirs.step == Rules.step(lot.opening) and theirs.leader == "Zed" and theirs.endsAt == lot.endsAt)
	local raw = {
		phase = "live", round = 7, startsAt = 1000, endsAt = 1200, index = 2, count = 4, grand = false,
		lot = theirs,
		upcoming = { { item = "jukebox", name = "Jukebox", rarity = "epic" }, { item = 5 } },
		mine = { uid = "20-4", item = "gold_record", name = "Gold Record", rarity = "rare", opening = 1600 },
		results = { { item = "gramophone", name = "Gramophone", rarity = "rare", price = 1800, winner = "Lady Fairbanks", npc = true }, "junk" },
	}
	local view = Rules.readView(raw) :: Rules.View
	check("the remote's view read back (junk dropped)", view ~= nil and view.phase == "live" and view.lot ~= nil and (view.lot :: any).leaderMe and #view.upcoming == 1 and view.mine ~= nil
		and #view.results == 1 and view.results[1].winner == "Lady Fairbanks" and view.index == 2 and view.count == 4)
	check("anything else: nil", Rules.readView(nil) == nil and Rules.readView({ phase = "party", startsAt = 1, endsAt = 2 }) == nil and Rules.readView({ phase = "live" }) == nil)
	local consign = Rules.readView({ phase = "consign", startsAt = 1000, endsAt = 980, lot = theirs }) :: Rules.View
	check("a lot only while live", consign ~= nil and consign.lot == nil and consign.index == 0)
	local many = { phase = "results", startsAt = 1, endsAt = 2, results = {} }
	for i = 1, 40 do
		table.insert(many.results, { item = "jukebox", price = i })
	end
	check("lists capped", #(Rules.readView(many) :: Rules.View).results == 12)
	-- the words
	check("the clock", Rules.clock(45) == "0:45" and Rules.clock(754) == "12:34" and Rules.clock(3723) == "1:02:03" and Rules.clock(-5) == "0:00" and Rules.clock(0.2) == "0:01")
	check("money, rarity, condition", Rules.money(12345) == "$12,345" and Rules.rarityName("legendary") == "Legendary" and Rules.percent(0.924) == "92%" and Rules.rarityWords() == "rare, epic or legendary")
	check("the fresh line", Rules.Fresh == "📖 New for your book!")
	local now = 1000
	check("the phase line: consigning", Rules.phaseLine({ phase = "consign", round = 1, startsAt = 1754, endsAt = 1734, index = 0, count = 0, upcoming = {}, results = {}, grand = false }, now)
		== "Next auction in 12:34 · consign a rare, epic or legendary piece")
	check("…live", Rules.phaseLine(view, now) == "LIVE · lot 2 of 4")
	check("…without the server (the schedule alone)", string.find(Rules.phaseLine(nil, Rules.startOf(3) + Rules.span() + A.Results + 10), "^Next auction in ") ~= nil)
	local fresh = Rules.lotView(freshLot("jukebox", 14, 3), 20, false)
	check("the leader line", Rules.leaderLine(fresh) == "No bids yet · opens at $3,400" and Rules.leaderLine(theirs) == "Leading: you" and Rules.leaderLine(mineView) == "Leading: Zed")
	local t1, k1 = Rules.bidButton(fresh, 99999, fresh.endsAt - 10)
	local during = 510 -- (the lot opened at 500)
	local t2, k2 = Rules.bidButton(mineView, 99999, during)
	local t3, k3 = Rules.bidButton(theirs, 99999, during)
	local other = Rules.lotView(lot, 33, false)
	local t4, k4 = Rules.bidButton(other, 99999, during)
	local t5, k5, why5 = Rules.bidButton(other, 100, during)
	local t6 = Rules.bidButton(other, 99999, other.endsAt)
	check("the BID button: the opening, + the step, your piece, you lead, NEED, SOLD", t1 == "BID · $3,400" and k1 == "good" and t2 == "YOUR PIECE" and k2 == "shut" and t3 == "YOU LEAD" and k3 == "shut"
		and t4 == `BID +$250 · {Rules.money(other.next)}` and k4 == "good" and t5 == `NEED {Rules.money(other.next - 100)}` and k5 == "shut" and why5 ~= nil and t6 == "SOLD", t4)
	check("a result's line", Rules.resultLine({ item = "x", name = "X", rarity = "rare", price = 3450, winner = "Lady Fairbanks", npc = true, sold = false, won = false, fee = 0, net = 0 }) == "Sold to Lady Fairbanks for $3,450"
		and Rules.resultLine({ item = "x", name = "X", rarity = "rare", price = 3450, winner = "You", npc = false, sold = false, won = true, fee = 0, net = 0 }) == "You bought it for $3,450"
		and Rules.resultLine({ item = "x", name = "X", rarity = "rare", price = 3450, winner = "Zed", npc = false, sold = true, won = false, fee = 276, net = 3174 }) == "Sold to Zed for $3,450 · you got $3,174")
end

-- ── The point: selling makes sense ──────────────────────────────────────────
do
	local worst, minutes, bad = math.huge, math.huge, nil
	for _, item in { "gold_record", "ship_bottle", "jewellery_box", "piano", "antique_vase", "jukebox", "alphorn", "oil_painting", "trex_skull", "ski_trophy" } do
		for _, condition in { 1, 0.8, 0.5 } do
			local e = entry("6-" .. item, item, condition)
			local game = CollectionRules.sell(e)
			local floor = Rules.opening(Rules.worthOf(e))
			local net = floor - Rules.fee(floor)
			local ratio = net / game
			if ratio < worst then
				worst, bad = ratio, `{item} at {condition}`
			end
			minutes = math.min(minutes, floor / CollectionRules.income(e))
		end
	end
	check(`at the auction's floor (no player bids, the fee paid) a piece nets 4 × what the game pays or more (worst ×{string.format("%.1f", worst)}: {bad})`, worst >= 4, worst)
	check(`…and at least 45 minutes of its own income on show ({math.floor(minutes)} at the least)`, minutes >= 45, minutes)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
