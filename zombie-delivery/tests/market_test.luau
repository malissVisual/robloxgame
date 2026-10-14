-- 8.3 SANDBOX, the market (shared/Market.luau, Config.Market): the pool (the sandbox house's kinds read from the
-- catalogue: no farm pieces, none too cheap, a new piece joins by itself), the day's picks (the same every time, three hot
-- with one collectible, one cold piece of furniture, all different, every kind hot some day of a year, no two days alike
-- in a row), the factors, the demand (−5 % a piece, floored at −40 %, a step back every Recover s, a new day afresh, the
-- pressure capped), a bulk sale priced one piece after the other, the save (clean never trusts, fromSave only with the
-- flag, twice the same), the remote's view checked, the words ("Today's market: …", the tags, "Market: Vintage Radio −10%
-- (you sold 2 today)"), and the rules that use it: CollectionRules' income, sell and view, StockPlan.price.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local FurnitureLooks = require("./FurnitureLooks")

-- a collectible the catalogue gains after this version (a new piece): the market must pick it up by itself
local NEW = "test_relic"
do
	local def: any = table.clone(FurnitureLooks.Items.gold_record)
	def.id, def.name, def.value, def.rarity = NEW, "Test Relic", 2222, "rare"
	FurnitureLooks.Items[NEW] = def
	table.insert(FurnitureLooks.Order, NEW)
end

local Market = require("./Market")
local Rules = require("./CollectionRules")
local StockPlan = require("./StockPlan")

local M = Config.Market
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

-- ── The numbers ─────────────────────────────────────────────────────────────
check("Config.Market: hot sells and earns more, cold sells for less, one collectible among the hot", M.HotSell > 1 and M.HotIncome > 1 and M.ColdSell < 1 and M.ColdSell > 0
	and M.Hot == 3 and M.HotCollectibles == 1 and M.Cold == 1)
check("… the demand: −5 % a piece, at most −40 %, a step back every 20 min; the flag", M.Drop == 0.05 and M.MaxDrop == 0.4 and M.Recover == 1200 and Market.Flag == "marketKept")

-- ── Time ────────────────────────────────────────────────────────────────────
local T = 1760000000
local DAY = Market.dayOf(T)
check("dayOf: the UTC day (1970-01-01 is day 0)", Market.dayOf(0) == 0 and Market.dayOf(86399) == 0 and Market.dayOf(86400) == 1 and DAY == 20370)
check("left: s to the day's end, never under 0", Market.left(DAY, DAY * 86400) == 86400 and Market.left(DAY, (DAY + 1) * 86400 - 5) == 5 and Market.left(DAY, (DAY + 2) * 86400) == 0)

-- ── The pool ────────────────────────────────────────────────────────────────
local plain, gems = Market.pool()
local farm: { [string]: boolean } = {}
for _, id in FurnitureLooks.FarmPieces do
	farm[id] = true
end
local okPool, why = #plain > 10 and #gems > 5, nil
local lastAt = 0
for _, id in plain do
	local def: any = FurnitureLooks.Items[id]
	local at = table.find(FurnitureLooks.Order, id) or 0
	if farm[id] or not def or def.rarity ~= nil or def.value < M.MinValue or at <= lastAt then
		okPool, why = false, id
	end
	lastAt = at
end
for _, id in gems do
	local def: any = FurnitureLooks.Items[id]
	if farm[id] or not def or type(def.rarity) ~= "string" then
		okPool, why = false, id
	end
end
check("pool: the house's furniture (no farm piece, none under MinValue, catalogue order) and its collectibles", okPool, why)
check("… the sofa, the piano and the wardrobe in it; the potted plant (too cheap) and the hay wagon (Walt's farm) not", table.find(plain, "sofa") ~= nil and table.find(plain, "piano") ~= nil
	and table.find(plain, "wardrobe") ~= nil and table.find(plain, "plant") == nil and table.find(plain, "hay_wagon") == nil and table.find(plain, "anvil") == nil)
local allGems = true
for _, id in FurnitureLooks.Collectibles do
	allGems = allGems and table.find(gems, id) ~= nil
end
check("… every collectible, and a new piece in the catalogue joins by itself (Test Relic)", allGems and table.find(gems, NEW) ~= nil, #gems)
local copy = Market.pool()
table.insert(copy, "junk")
check("… a copy: changing it changes nothing", table.find((Market.pool()), "junk") == nil)

-- ── The day's picks ─────────────────────────────────────────────────────────
local picks = Market.pick(DAY)
local again = Market.pick(DAY)
check("pick: the same day, the same picks (twice, and as a fresh table compares)", same(picks, again) and same(Market.today(DAY).hot, picks.hot))
check("… three hot, one cold", #picks.hot == 3 and #picks.cold == 1, `{#picks.hot} hot, {#picks.cold} cold`)
local function counts(p: Market.Picks): (number, number, boolean)
	local g, f = 0, 0
	local seen: { [string]: boolean } = {}
	local distinct = true
	for _, id in p.hot do
		if table.find(gems, id) then
			g += 1
		elseif table.find(plain, id) then
			f += 1
		end
		distinct = distinct and not seen[id]
		seen[id] = true
	end
	for _, id in p.cold do
		distinct = distinct and not seen[id] and table.find(plain, id) ~= nil
		seen[id] = true
	end
	return g, f, distinct
end
local hotSeen: { [string]: number } = {}
local coldSeen: { [string]: number } = {}
local shapeOk, shapeWhy = true, nil
local repeats = 0
local previous: Market.Picks? = nil
for day = DAY, DAY + 364 do
	local p = Market.pick(day)
	local g, f, distinct = counts(p)
	if g ~= 1 or f ~= 2 or not distinct or #p.cold ~= 1 then
		shapeOk, shapeWhy = false, `day {day}: {table.concat(p.hot, ",")} / {table.concat(p.cold, ",")}`
	end
	for i = 2, #p.hot do
		if (table.find(FurnitureLooks.Order, p.hot[i - 1]) or 0) > (table.find(FurnitureLooks.Order, p.hot[i]) or 0) then
			shapeOk, shapeWhy = false, `day {day} not in catalogue order`
		end
	end
	for _, id in p.hot do
		hotSeen[id] = (hotSeen[id] or 0) + 1
	end
	coldSeen[p.cold[1]] = (coldSeen[p.cold[1]] or 0) + 1
	if previous and same(previous.hot, p.hot) then
		repeats += 1
	end
	previous = p
end
check("a year of days: each with one hot collectible, two hot pieces of furniture and a cold one, all different, in catalogue order", shapeOk, shapeWhy)
local everyHot, missing = true, nil
for _, id in plain do
	if not hotSeen[id] or not coldSeen[id] then
		everyHot, missing = false, id
	end
end
for _, id in gems do
	if not hotSeen[id] then
		everyHot, missing = false, id
	end
end
check("… every kind of the pool hot some day (every piece of furniture cold some day too), Test Relic included", everyHot, missing)
check("… never the same hot kinds two days in a row", repeats == 0, repeats)
local spread = 0
for _, n in hotSeen do
	spread = math.max(spread, n)
end
check("… spread out: no kind hot on more than a fifth of the days", spread <= 73, spread)

-- ── The factors ─────────────────────────────────────────────────────────────
local today = Market.today(DAY, T)
local hot, cold = today.hot[1], today.cold[1]
local plainKind: string = "sofa"
for _, id in plain do
	if Market.tag(today, id) == nil then
		plainKind = id
		break
	end
end
check("today: the day's picks, no demand, the time left", today.day == DAY and same(today.hot, picks.hot) and next(today.demand) == nil and today.left == Market.left(DAY, T))
check("tag: hot, cold, nil (and nil without a market)", Market.tag(today, hot) == "hot" and Market.tag(today, cold) == "cold" and Market.tag(today, plainKind) == nil and Market.tag(nil, hot) == nil)
check("sellFactor: × HotSell, × ColdSell, × 1", Market.sellFactor(today, hot) == M.HotSell and Market.sellFactor(today, cold) == M.ColdSell and Market.sellFactor(today, plainKind) == 1 and Market.sellFactor(nil, hot) == 1)
check("incomeFactor: × HotIncome for a hot kind only", Market.incomeFactor(today, hot) == M.HotIncome and Market.incomeFactor(today, cold) == 1 and Market.incomeFactor(nil, hot) == 1)
check("demandFactor: 1, 0.95 a piece … floored at 0.6", Market.demandFactor(0) == 1 and math.abs(Market.demandFactor(1) - 0.95) < 1e-9 and math.abs(Market.demandFactor(2) - 0.9) < 1e-9
	and math.abs(Market.demandFactor(8) - 0.6) < 1e-9 and math.abs(Market.demandFactor(30) - 0.6) < 1e-9 and Market.demandFactor(-3) == 1 and Market.demandFactor(0 / 0) == 1)
check("price: no market, the base (rounded, at least $1)", Market.price(100, nil, hot) == 100 and Market.price(0.2, nil, hot) == 1 and Market.price(0 / 0, nil, hot) == 1)
check(`… hot × {M.HotSell}, cold × {M.ColdSell}, plain × 1`, Market.price(100, today, hot) == math.floor(100 * M.HotSell + 0.5) and Market.price(100, today, cold) == math.floor(100 * M.ColdSell + 0.5)
	and Market.price(100, today, plainKind) == 100)
check("8.3 economy: hot sells × 1.4 and earns × 1.2 on show (was 1.6 and 1.25)", M.HotSell == 1.4 and M.HotIncome == 1.2 and Market.price(100, today, hot) == 140)
check("… a cheap scrap piece still $1 at least", Market.price(1, today, cold) == 1)

-- ── The demand ──────────────────────────────────────────────────────────────
local saved = Market.empty()
check("empty: day 0, no kinds", saved.day == 0 and next(saved.kinds) == nil)
Market.note(saved, "vintage_radio", DAY, T)
Market.note(saved, "vintage_radio", DAY, T + 60)
local view = Market.view(saved, DAY, T + 60)
local radio = view.demand.vintage_radio
check("note: two radios sold → the pressure 2, sold 2, a step back in Recover s (from the first sale)", radio ~= nil and radio.n == 2 and radio.sold == 2 and radio.back == M.Recover - 60, radio and `{radio.n} {radio.sold} {radio.back}`)
check("… the price 10 % down (× 0.9) and the tag's words", Market.pressure(view, "vintage_radio") == 2 and Market.price(1000, view, "vintage_radio") == math.floor(1000 * Market.sellFactor(view, "vintage_radio") * 0.9 + 0.5)
	and Market.percent(view, "vintage_radio") == 10)
check("… the demand line: \"Market: Vintage Radio −10% (you sold 2 today)\"", Market.demandLine(view, "vintage_radio") == "Market: Vintage Radio −10% (you sold 2 today)", Market.demandLine(view, "vintage_radio"))
check("… a kind not sold: no line, 0 %", Market.demandLine(view, "sofa") == nil and Market.percent(view, "sofa") == 0 and Market.demandLine(nil, "sofa") == nil)
check("nextChange: the first step back in Recover s", Market.nextChange(saved, DAY, T + 60) == M.Recover - 60 and Market.nextChange(nil, DAY, T) == nil and Market.nextChange(saved, DAY + 1, T) == nil)
view = Market.view(saved, DAY, T + M.Recover)
check("Recover s on: one step back (the pressure 1, still sold 2 today)", view.demand.vintage_radio.n == 1 and view.demand.vintage_radio.sold == 2 and view.demand.vintage_radio.back == M.Recover)
view = Market.view(saved, DAY, T + 2 * M.Recover + 5)
check("two steps on: the price whole again (sold 2 still told)", view.demand.vintage_radio.n == 0 and view.demand.vintage_radio.sold == 2 and Market.percent(view, "vintage_radio") == 0 and Market.nextChange(saved, DAY, T + 2 * M.Recover + 5) == nil)
Market.note(saved, "vintage_radio", DAY, T + M.Recover + 30)
view = Market.view(saved, DAY, T + M.Recover + 30)
check("a sale after one step back: 1 + 1, its next step on the old count (no step lost)", view.demand.vintage_radio.n == 2 and view.demand.vintage_radio.sold == 3 and view.demand.vintage_radio.back == M.Recover - 30, `{view.demand.vintage_radio.n} {view.demand.vintage_radio.back}`)
Market.note(saved, "sofa", DAY, T, 30)
view = Market.view(saved, DAY, T)
check("thirty sofas at once: the pressure stops at MaxDrop / Drop (8: −40 %), sold 30", view.demand.sofa.n == 8 and view.demand.sofa.sold == 30 and Market.percent(view, "sofa") == 40)
view = Market.view(saved, DAY, T + 8 * M.Recover)
check("… whole again eight steps later (not thirty)", view.demand.sofa.n == 0)
check("a view of another day: no demand (the save's day is over)", next(Market.view(saved, DAY + 1, (DAY + 1) * 86400 + 10).demand) == nil)
Market.note(saved, "piano", DAY + 1, (DAY + 1) * 86400 + 10)
check("a sale on a new day: yesterday forgotten, today's demand alone", saved.day == DAY + 1 and saved.kinds.vintage_radio == nil and saved.kinds.sofa == nil and saved.kinds.piano.n == 1)
Market.note(saved, "piano", DAY + 1, (DAY + 1) * 86400 + 10, 0)
Market.note(saved, string.rep("x", 60), DAY + 1, (DAY + 1) * 86400 + 10)
check("note: nothing for 0 pieces or a junk id", saved.kinds.piano.sold == 1 and saved.kinds[string.rep("x", 60)] == nil)

-- ── A bulk sale ─────────────────────────────────────────────────────────────
local fresh = Market.today(DAY, T)
local total, prices = Market.batch({ { item = plainKind, base = 100 }, { item = plainKind, base = 100 }, { item = plainKind, base = 100 }, { item = hot, base = 50 }, { item = hot, base = 50 } }, fresh)
local hot1, hot2 = math.floor(50 * M.HotSell + 0.5), math.floor(50 * (M.HotSell * 0.95) + 0.5) -- (Market.price: the base × its factors)
check(`batch: one after the other, each next piece of a kind 5 % lower (100, 95, 90; hot {hot1}, {hot2})`, total == 100 + 95 + 90 + hot1 + hot2 and same(prices, { 100, 95, 90, hot1, hot2 }), table.concat(prices, ","))
local withDemand = Market.view(nil, DAY, T)
withDemand.demand[plainKind] = { n = 7, sold = 7, back = 60 }
total, prices = Market.batch({ { item = plainKind, base = 100 }, { item = plainKind, base = 100 }, { item = plainKind, price = 100 } }, withDemand)
check("… on top of the demand already there, never under −40 % (65, 60, 60); a piece without base: its price", same(prices, { 65, 60, 60 }) and total == 185, table.concat(prices, ","))
check("… no market: the bases summed", (Market.batch({ { item = hot, base = 10 }, { item = hot, base = 10 } }, nil)) == 20)

-- ── The save ────────────────────────────────────────────────────────────────
local good = { day = DAY, kinds = { sofa = { n = 2, at = T, sold = 3 } } }
check("clean: junk is the empty one", same(Market.clean(nil), Market.empty()) and same(Market.clean("x"), Market.empty()) and same(Market.clean({ day = "x", kinds = 5 }), Market.empty()))
local raw = { day = DAY + 0.5, kinds = {
	sofa = { n = 2.7, at = T, sold = 3 },
	nonsense = { n = 1, at = T, sold = 1 },
	piano = { n = 99, at = 0 / 0, sold = -4 },
	tv = "x",
	[5] = { n = 1, at = T, sold = 1 },
	radio = { n = 0, at = T, sold = 0 },
} }
local cleaned = Market.clean(raw)
check("… a whole day; known kinds only; n whole and capped (8), at finite, sold whole ≥ 0; a kind with nothing dropped", cleaned.day == DAY and cleaned.kinds.sofa.n == 2 and cleaned.kinds.sofa.sold == 3
	and cleaned.kinds.nonsense == nil and cleaned.kinds.piano.n == 8 and cleaned.kinds.piano.at == 0 and cleaned.kinds.piano.sold == 0 and cleaned.kinds.tv == nil and cleaned.kinds[5 :: any] == nil and cleaned.kinds.radio == nil)
check("fromSave: a new player, a lock-only record, an old save, a stray market without the flag: empty", same(Market.fromSave(nil), Market.empty()) and same(Market.fromSave({ lock = {}, marketKept = true, market = good }), Market.empty())
	and same(Market.fromSave({ money = 5 }), Market.empty()) and same(Market.fromSave({ money = 5, market = good }), Market.empty()))
check("… a save with the flag: its market (cleaned); twice the same", same(Market.fromSave({ money = 5, marketKept = true, market = good }), good)
	and same(Market.fromSave({ money = 5, marketKept = true, market = Market.fromSave({ money = 5, marketKept = true, market = raw }) }), cleaned))

-- ── The remote's view ───────────────────────────────────────────────────────
local sent = Market.view(good :: any, DAY, T + 10)
check("readView: a server's view back as it was", same(Market.readView(sent), sent))
check("… junk: nil (no table, no day, a hot list that is no list, too long, an id too long)", Market.readView(nil) == nil and Market.readView({ day = DAY }) == nil
	and Market.readView({ day = DAY, left = 5, hot = { a = "sofa" }, cold = {} }) == nil and Market.readView({ day = DAY, left = 5, hot = { "a", "b", "c", "d", "e", "f", "g", "h", "i" }, cold = {} }) == nil
	and Market.readView({ day = DAY, left = 5, hot = { string.rep("x", 50) }, cold = {} }) == nil)
local odd = Market.readView({ day = DAY, left = -5, hot = { "sofa" }, cold = {}, demand = { sofa = { n = 99, sold = "x", back = -1 }, [3] = { n = 1 } } })
check("… its numbers mended (left ≥ 0, n capped, sold a number, back ≥ 0), junk demand left out", odd ~= nil and odd.left == 0 and odd.demand.sofa.n == 8 and odd.demand.sofa.sold == 0 and odd.demand.sofa.back == 0 and odd.demand[3 :: any] == nil)

-- ── The words ───────────────────────────────────────────────────────────────
check("factor: ×1.6, ×1.25, ×0.7, ×2", Market.factor(1.6) == "×1.6" and Market.factor(1.25) == "×1.25" and Market.factor(0.7) == "×0.7" and Market.factor(2) == "×2")
check("wait: 5 h, 40 min, 1 min (never 0)", Market.wait(5 * 3600 + 100) == "5 h" and Market.wait(2400) == "40 min" and Market.wait(10) == "1 min" and Market.wait(-4) == "1 min")
check("money: $1,234", Market.money(1234) == "$1,234" and Market.money(5) == "$5" and Market.money(1234567) == "$1,234,567")
local shown: Market.View = { day = DAY, hot = { "record_player", "old_globe", "jukebox" }, cold = { "wardrobe" }, left = 5 * 3600 + 30, demand = {} }
check("line: \"Today's market: 🔥 Old Record Player, Old Globe, Jukebox · ❄ Wardrobe · new in 5 h\"", Market.line(shown) == "Today's market: 🔥 Old Record Player, Old Globe, Jukebox · ❄ Wardrobe · new in 5 h", Market.line(shown))
check("… the time left given: new in 40 min", Market.line(shown, 2400) == "Today's market: 🔥 Old Record Player, Old Globe, Jukebox · ❄ Wardrobe · new in 40 min")
check("badge: \"🔥 HOT ×1.4\", \"❄ COLD\", nil", Market.badge(shown, "jukebox") == `🔥 HOT {Market.factor(M.HotSell)}` and Market.badge(shown, "jukebox") == "🔥 HOT ×1.4"
	and Market.badge(shown, "wardrobe") == "❄ COLD" and Market.badge(shown, "sofa") == nil and Market.badge(nil, "jukebox") == nil)
check("hotToast: \"🔥 Hot today: … (sell ×1.4, on show ×1.2)\"", Market.hotToast(shown) == "🔥 Hot today: Old Record Player, Old Globe, Jukebox (sell ×1.4, on show ×1.2)", Market.hotToast(shown))
check("nameOf: the catalogue's name, else the id", Market.nameOf("vintage_radio") == "Vintage Radio" and Market.nameOf("nope") == "nope")

-- ── The rules that use it ───────────────────────────────────────────────────
local piece: Rules.Entry = { uid = "1-1", item = shown.hot[3], variant = 1, condition = 0.9, name = "Jukebox", got = 0 }
local plainIncome = Rules.income(piece, 1.1)
check("CollectionRules.income: a hot kind × HotIncome (× the lights too); no market as before", math.abs(Rules.income(piece, 1.1, shown) - plainIncome * M.HotIncome) < 1e-9 and Rules.income(piece, 1.1, nil) == plainIncome)
local base = Rules.sell(piece)
check("CollectionRules.sell: with the market Market.price on its price", Rules.sell(piece, shown) == Market.price(base, shown, piece.item) and Rules.sell(piece, shown) == math.floor(base * M.HotSell + 0.5))
local v = Rules.view(piece, 1, shown)
check("CollectionRules.view: price the market's, base without it, the tag, income × HotIncome", v.price == Rules.sell(piece, shown) and v.base == base and v.market == "hot"
	and math.abs(v.income - math.floor(Rules.income(piece, 1, shown) * 100 + 0.5) / 100) < 1e-9)
local v0 = Rules.view(piece)
check("… without a market: price = base, no tag", v0.price == base and v0.base == base and v0.market == nil)
local wardrobe: Rules.Entry = { uid = "1-2", item = "wardrobe", variant = 1, condition = 1, name = "Wardrobe", got = 0, stand = 1 }
local totals = Rules.totals({ piece, wardrobe }, 1, shown)
check("CollectionRules.totals: the market's prices and incomes", totals.sell == Rules.sell(piece, shown) + Rules.sell(wardrobe, shown) and math.abs(totals.income - Rules.income(wardrobe, 1, shown)) < 1e-9
	and Rules.sell(wardrobe, shown) < Rules.sell(wardrobe))
local radios: { StockPlan.Piece } = {}
for i = 1, 4 do
	table.insert(radios, { uid = `1-{i}`, item = "radio", rarity = "common", income = 1, price = 9, base = 9 })
end
local demandView: Market.View = { day = DAY, hot = {}, cold = {}, left = 100, demand = {} }
check("StockPlan.price: without a market the prices summed; with it one after the other (9, 9, 8, 8)", StockPlan.price(radios) == 36 and StockPlan.price(radios, demandView) == 9 + 9 + 8 + 8, StockPlan.price(radios, demandView))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
