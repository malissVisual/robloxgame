-- 8.3 SANDBOX, the showroom visitors' offers on the server: the real server/VisitorOffers.luau with the real
-- server/PlayerData.luau, server/Collection.luau (its new sellAt), server/Upgrades.luau and server/SandboxTasks.luau
-- (VisitorOffersServer.luau and the others through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's players,
-- DataStore, clock and Net, the market the real shared/Market.luau. Checked: an offer made for a piece on show (its price
-- the market's price now × the offer's factor, more for a hot kind; the toast, the card's message, the analytics), one
-- at a time and Every s apart, the pieces nobody offers for (not on show, broken, not yours); ACCEPT through the remote
-- (sold at the server's price whatever the client sends; the money's reason VisitorOffer and its SKU; the piece gone;
-- the market's demand one more of its kind and the next offer's price under it; onPaid's sale: the sell task; the daily
-- task "offer" done; the closed message, the visitor's answer); the refusals: a forged or stale id, a number for an id,
-- garbage, another player's id, a second ACCEPT, the clock run out (at the tick and at a late ACCEPT), the piece taken
-- down, moved to another stand or sold before the answer; DECLINE; the rate limit; leaving; the offer task never picked
-- while Config.Visitors.On is false. 10.4 (the warehouse in two, Config.Showroom): the offers are the showroom's: Ann's
-- pieces on showroom stands (S(k)), the price the market's × the showroom's factor (Collection.showFactor), a piece in
-- the hall gets none and one moved there closes its offer (gone).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
local CollectionRules = require("./CollectionRules")
local Market = require("./Market")
local Visitors = require("./Visitors")
local TaskRules = require("./SandboxTasks")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Upgrades = require("./UpgradesServer")
local Tasks = require("./SandboxTasksServer")
local Offers = require("./VisitorOffersServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function kinds(messages: { any }, kind: string): { any }
	local out = {}
	for _, m in messages do
		if type(m) == "table" and m.kind == kind then
			table.insert(out, m)
		end
	end
	return out
end

local O = Config.Visitors.Offer
local DAY = 86400
E.now = 20372 * DAY + 12 * 3600 -- (a Saturday at noon UTC)

-- What the hooks saw: the money, the analytics' events, the visitors' answers (VisitorOffers.onClosed).
local money: { { player: any, delta: number, reason: string?, sku: string? } } = {}
PlayerData.onMoney = function(player: Player, delta: number, reason: string?, sku: string?)
	table.insert(money, { player = player, delta = delta, reason = reason, sku = sku })
end
local function paid(player: any, reason: string?, from: number?): (number, number, string?)
	local sum, count, sku = 0, 0, nil
	for index = (from or 0) + 1, #money do
		local m = money[index]
		if m.player == player and (reason == nil or m.reason == reason) then
			sum += m.delta
			count += 1
			sku = m.sku
		end
	end
	return sum, count, sku
end
-- what was paid for pieces (an offer or a sale; the stands' income goes on meanwhile)
local function sales(player: any, from: number?): number
	return (paid(player, "VisitorOffer", from)) + (paid(player, "CollectionSale", from))
end
local events: { { player: any, name: string, value: any, a: any, b: any } } = {}
PlayerData.analytics.event = function(player: any, name: any, value: any, a: any, b: any)
	table.insert(events, { player = player, name = name, value = value, a = a, b = b })
end
local function lastEvent(name: string): any
	for index = #events, 1, -1 do
		if events[index].name == name then
			return events[index]
		end
	end
	return nil
end
local answers: { { player: any, offer: any, how: string, money: number? } } = {}
Offers.onClosed(function(player: any, offer: any, how: string, cash: number?)
	table.insert(answers, { player = player, offer = offer, how = how, money = cash })
end)

local function profileOf(player: any): any
	return PlayerData.get(player) :: any
end
local function uidOf(player: any, item: string, nth: number?): string?
	local seen = 0
	for _, entry in Collection.stock(player) do
		if entry.item == item then
			seen += 1
			if seen == (nth or 1) then
				return entry.uid
			end
		end
	end
	return nil
end
local function entryOf(player: any, uid: string): any
	for _, entry in Collection.stock(player) do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end
local function lastNotice(player: any, from: number?): string
	local said = E.received(player, "Notice", from)
	return tostring(said[#said] or "")
end
local function setTasks(player: any, daily: { { any } })
	local saved = profileOf(player).sandboxTasks
	saved.daily = {}
	for _, pair in daily do
		table.insert(saved.daily, { id = pair[1], target = pair[2], progress = 0, claimed = false })
	end
end
-- the expected price of an offer for this piece now (the market's price × the factor at `roll`)
local function priceFor(player: any, uid: string, kind: string, roll: number): (number, number)
	local entry = entryOf(player, uid)
	local market = Collection.market(player)
	local base = CollectionRules.sell(entry, market, Collection.showFactor(player)) -- (10.4: the showroom's price)
	local rank = CollectionRules.tier(CollectionRules.rarityOf(CollectionRules.defOf(entry.item))).rank
	local pay = (Visitors.kind(kind) :: Visitors.Kind).pay
	return Visitors.offerPrice(base, rank, Market.tag(market, entry.item) == "hot", pay, roll), base
end

PlayerData.start()
Collection.start()
Upgrades.start()
Tasks.start()
Offers.start()
Offers.start() -- (twice: once)

local A = E.join(301, "Ann")
local B = E.join(302, "Bob")
E.flush()
check("(Ann and Bob in with their saves: the tasks loaded)", profileOf(A) ~= nil and profileOf(A).sandboxTasks ~= nil and Tasks.state(A) ~= nil)
Upgrades.admin(A, "level5") -- (8.3 levels: Ann's warehouse the Logistics Center, 24 stands; Bob's the Garage, 2)
profileOf(A).sandboxUpgrades.showstands = 3 -- (10.4: her showroom's six plinths)
E.flush()
local function S(k: number): number -- (10.4: showroom stand k)
	return Config.Showroom.Base + k
end
check("(10.4: Ann's showroom: 6 stands)", Collection.showStands(A) == 6, Collection.showStands(A))
check("(Ann at level 5: 24 stands; Bob at the start's: 2)", Collection.stands(A) == 24 and Collection.stands(B) == 2)
for _, item in { "piano", "sofa", "sofa", "plant", "armchair" } do
	Collection.add(A, { item = item, condition = 1 })
end
Collection.add(A, { item = "tv", condition = 0.02 }) -- (broken)
local hotKind = Market.pick(Market.dayOf(E.now)).hot[1]
Collection.add(A, { item = hotKind, condition = 1 })
Collection.add(B, { item = "sofa", condition = 1 })
E.flush()
local piano, sofa1, sofa2, plant, armchair = uidOf(A, "piano") :: string, uidOf(A, "sofa", 1) :: string, uidOf(A, "sofa", 2) :: string, uidOf(A, "plant") :: string, uidOf(A, "armchair") :: string
local broken, hot = uidOf(A, "tv") :: string, uidOf(A, hotKind) :: string
Collection.display(A, piano, S(1))
Collection.display(A, sofa1, S(2))
Collection.display(A, broken, S(3))
Collection.display(A, hot, S(4))
Collection.display(A, armchair, S(5))
Collection.display(B, uidOf(B, "sofa") :: string, 1)
E.flush()

-- ── An offer ───────────────────────────────────────────────────────────────
check("ready: a save, no offer open, none made yet", Offers.ready(A) and Offers.ready(B))
local mark = #E.sent
local want, base = priceFor(A, piano, "collector", 0.5)
local offer = Offers.make(A, piano, "collector", 0.5, "tok1")
E.flush()
check("an offer for the piano on show from the collector: the market's price × its factor (rare: 8.3 economy, the collector's pay)", offer ~= nil and offer.price == want
	and offer.base == base and offer.price > base and offer.who == "Collector" and offer.stand == S(1) and offer.rarity == "rare" and offer.token == "tok1", offer and offer.price)
check("… its price over the market price: × 1.1 – 1.5 and more (rarity, kind), Top at most", offer ~= nil and offer.price >= base * O.Min and offer.price <= base * O.Top + 10)
local cards = kinds(E.received(A, "Visitors", mark), "offer")
local card = cards[1]
check("the card's message: id, name, item, price, base, who, seconds, rarity (and nothing to Bob)", #cards == 1 and offer ~= nil and card.id == offer.id
	and card.name == "Upright Piano" and card.item == "piano" and card.price == offer.price and card.base == base and card.who == "Collector"
	and card.seconds == O.Expire and card.rarity == "rare" and #E.received(B, "Visitors", mark) == 0)
check("… the client reads it back (Visitors.readOffer)", Visitors.readOffer(card) ~= nil)
check("the toast: \"🤝 The collector offers $… for your Upright Piano\"", offer ~= nil and lastNotice(A, mark) == Visitors.toast("Collector", offer.price, "Upright Piano"), lastNotice(A, mark))
local made = lastEvent("VisitorOffer")
check("analytics: VisitorOffer made (its $, the rarity)", made ~= nil and made.player == A and offer ~= nil and made.value == offer.price and made.a == "made" and made.b == "rare")
check("VisitorOffers.current: a copy of the open offer", Offers.current(A) ~= nil and (Offers.current(A) :: any).id == (offer :: any).id and Offers.current(A) ~= Offers.current(A))
local again, why = Offers.make(A, sofa1, "tourist", 0.5)
check("one offer at a time: another refused, ready false", again == nil and why ~= nil and not Offers.ready(A) and Offers.ready(B))

-- ── The remote: forged ids, garbage, another player's ─────────────────────
local moneyAt = #money
mark = #E.sent
E.fire(A, "Visitors", { kind = "accept", id = "o999" })
check("ACCEPT with a forged id: refused (a notice), nothing paid, the offer still open", sales(A, moneyAt) == 0 and lastNotice(A, mark) == "That offer isn't open any more."
	and Offers.current(A) ~= nil and entryOf(A, piano) ~= nil)
E.advance(1)
E.fire(A, "Visitors", { kind = "accept", id = 1 })
E.fire(A, "Visitors", "accept")
E.advance(1)
E.fire(A, "Visitors", { kind = "sell", id = (offer :: any).id })
E.fire(A, "Visitors", { id = (offer :: any).id })
E.advance(1)
E.fire(B, "Visitors", { kind = "accept", id = (offer :: any).id })
check("a number for an id, a string, an unknown kind, no kind, Bob with Ann's id: nothing paid, the offer still Ann's", sales(A, moneyAt) == 0 and sales(B, moneyAt) == 0
	and Offers.current(A) ~= nil and entryOf(A, piano) ~= nil)

-- ── ACCEPT: sold at the server's price ─────────────────────────────────────
setTasks(A, { { "offer", 1 }, { "sell", 150 }, { "home", 8 } })
E.advance(1)
local demandBefore = (Collection.market(A) :: any).demand.piano
mark = #E.sent
moneyAt = #money
local closedAt = #answers
E.fire(A, "Visitors", { kind = "accept", id = (offer :: any).id, price = 999999 })
E.flush()
local sum, count, sku = paid(A, "VisitorOffer", moneyAt)
check("ACCEPT (with a forged price of $999,999): sold at the offer's own price, as VisitorOffer, its SKU the piano", offer ~= nil and sum == offer.price and count == 1 and sku == "piano"
	and sales(A, moneyAt) == offer.price, sum)
check("… the piano out of the stock and off its stand", entryOf(A, piano) == nil and Offers.current(A) == nil)
local after = (Collection.market(A) :: any).demand.piano
check("… the market's demand: one more piano sold today (as a sale)", demandBefore == nil and after ~= nil and after.n == 1 and after.sold == 1)
local closed = kinds(E.received(A, "Visitors", mark), "closed")
local sold = kinds(E.received(A, "Collection", mark), "sold")
check("… the card's closed message (sold, the money), the collection's sold toast", #closed == 1 and closed[1].how == "sold" and offer ~= nil and closed[1].money == offer.price
	and #sold == 1 and sold[1].name == "Upright Piano" and sold[1].money == offer.price)
check("… the visitor hears: sold, the money, its token", #answers == closedAt + 1 and answers[#answers].how == "sold" and answers[#answers].offer.token == "tok1"
	and offer ~= nil and answers[#answers].money == offer.price)
local slots = profileOf(A).sandboxTasks.daily
local dones = kinds(E.received(A, "SandboxTasks", mark), "done")
local offerDone = false
for _, done in dones do
	offerDone = offerDone or done.title == "Accept an offer from a visitor"
end
check("… the daily task \"Accept an offer from a visitor\" done (and the sale counts for the sell task too)", slots[1].progress == 1 and offerDone
	and offer ~= nil and slots[2].progress == math.min(150, offer.price), `{slots[1].progress} {slots[2].progress}`)
local soldEvent = lastEvent("VisitorOffer")
check("… analytics: VisitorOffer sold; CollectionSold with its price", soldEvent ~= nil and soldEvent.a == "sold" and lastEvent("CollectionSold") ~= nil
	and offer ~= nil and lastEvent("CollectionSold").value == offer.price)
mark = #E.sent
moneyAt = #money
E.advance(1)
E.fire(A, "Visitors", { kind = "accept", id = (offer :: any).id })
check("a second ACCEPT of it: refused, nothing more paid", sales(A, moneyAt) == 0 and lastNotice(A, mark) == "That offer isn't open any more.")

-- ── Every s apart; the pieces nobody offers for ────────────────────────────
check("the next offer to Ann waits Every s", not Offers.ready(A) and Offers.make(A, sofa1, "tourist", 0.5) == nil)
E.advance(O.Every)
check("… then ready again", Offers.ready(A))
check("no offer for a piece not on show, a broken one, one not hers, junk", Offers.make(A, plant, "tourist", 0.5) == nil and Offers.make(A, broken, "tourist", 0.5) == nil
	and Offers.make(A, uidOf(B, "sofa") :: string, "tourist", 0.5) == nil and Offers.make(A, string.rep("9", 99), "tourist", 0.5) == nil
	and Offers.make(A, (nil :: any), "tourist", 0.5) == nil and Offers.current(A) == nil)

-- ── DECLINE ────────────────────────────────────────────────────────────────
mark = #E.sent
moneyAt = #money
local tourist = Offers.make(A, sofa1, "tourist", 0, "tok2")
check("a tourist's offer for the sofa: × Min (rare, an ordinary kind)", tourist ~= nil and tourist.price == (priceFor(A, sofa1, "tourist", 0)))
E.fire(A, "Visitors", { kind = "decline", id = (tourist :: any).id })
E.flush()
closed = kinds(E.received(A, "Visitors", mark), "closed")
check("DECLINE: closed (declined), nothing paid, the sofa still on its stand, no notice", #closed == 1 and closed[1].how == "declined" and sales(A, moneyAt) == 0
	and entryOf(A, sofa1).stand == S(2) and #E.received(A, "Notice", mark) == 1 and answers[#answers].how == "declined" and answers[#answers].offer.token == "tok2")

-- ── The clock runs out ────────────────────────────────────────────────────
E.advance(O.Every)
mark = #E.sent
local late = Offers.make(A, sofa1, "hiker", 0.5, "tok3")
E.advance(O.Expire - 1)
Offers.tick()
check("the clock: still open a second before it runs out", late ~= nil and Offers.current(A) ~= nil)
E.advance(1.5)
Offers.tick()
closed = kinds(E.received(A, "Visitors", mark), "closed")
check("… run out: closed (expired) at the tick, the visitor hears", Offers.current(A) == nil and #closed == 1 and closed[1].how == "expired" and answers[#answers].how == "expired")
E.advance(O.Every)
mark = #E.sent
moneyAt = #money
local tooLate = Offers.make(A, sofa1, "hiker", 0.5, "tok4")
E.advance(O.Expire + 1)
E.fire(A, "Visitors", { kind = "accept", id = (tooLate :: any).id })
check("an ACCEPT after the clock ran out (before any tick): refused, closed expired, nothing paid", sales(A, moneyAt) == 0 and Offers.current(A) == nil
	and lastNotice(A, mark) == "Too late: that offer has run out." and entryOf(A, sofa1) ~= nil and answers[#answers].how == "expired")

-- ── The piece taken down, moved, sold before the answer ───────────────────
local function gone(label: string, change: () -> ())
	E.advance(O.Every)
	mark = #E.sent
	moneyAt = #money
	local open = Offers.make(A, sofa1, "dealer", 0.5, label)
	change()
	E.flush()
	local closedNow = kinds(E.received(A, "Visitors", mark), "closed")
	check(`{label}: the offer closes (gone), the visitor hears`, open ~= nil and Offers.current(A) == nil and #closedNow == 1 and closedNow[1].how == "gone"
		and answers[#answers].how == "gone" and answers[#answers].offer.token == label)
	local before = paid(A, "VisitorOffer", moneyAt)
	E.advance(1)
	E.fire(A, "Visitors", { kind = "accept", id = (open :: any).id })
	check(`{label}: … an ACCEPT then sells nothing`, paid(A, "VisitorOffer", moneyAt) == before)
end
gone("taken down", function()
	Collection.undisplay(A, sofa1)
end)
Collection.display(A, sofa1, S(2))
E.flush()
gone("moved to another stand", function()
	Collection.display(A, sofa1, S(6))
end)
gone("10.4: put in the hall", function()
	Collection.place(A, sofa1, "hall")
end)
check("10.4: no offer for a piece in the hall (it earns there)", entryOf(A, sofa1).stand ~= nil and not CollectionRules.isShow(entryOf(A, sofa1).stand)
	and (function()
		E.advance(O.Every)
		return Offers.make(A, sofa1, "tourist", 0.5) == nil
	end)())
Collection.place(A, sofa1, "show")
check("10.4: … shown for sale again (Collection.place): the showroom's first free stand (the piano's, sold)", entryOf(A, sofa1).stand == S(1), entryOf(A, sofa1).stand)
Collection.display(A, sofa2, S(6))
E.flush()
gone("sold at its stand", function()
	Collection.sell(A, sofa1)
end)
check("… sold once only (CollectionSale)", entryOf(A, sofa1) == nil and paid(A, "VisitorOffer", moneyAt) == 0)

-- ── The market: the demand and a hot kind ─────────────────────────────────
E.advance(O.Every)
local sofaDemand = (Collection.market(A) :: any).demand.sofa
local wantSofa, baseSofa = priceFor(A, sofa2, "tourist", 0.5)
local plainSofa = CollectionRules.sell(entryOf(A, sofa2), nil, Collection.showFactor(A))
local afterSale = Offers.make(A, sofa2, "tourist", 0.5)
check("the next sofa's offer: its market price under the demand (one sofa sold today: 5 % less)", sofaDemand ~= nil and sofaDemand.n == 1 and afterSale ~= nil
	and afterSale.base == baseSofa and afterSale.price == wantSofa and baseSofa < plainSofa, `{baseSofa} vs {plainSofa}`)
Offers.close(A, "left")
check("VisitorOffers.close: the server's own close (the visitor went: left)", Offers.current(A) == nil and answers[#answers].how == "left")
E.advance(O.Every)
local wantHot, baseHot = priceFor(A, hot, "tourist", 0.5)
local hotOffer = Offers.make(A, hot, "tourist", 0.5)
check(`a hot kind ({hotKind}): its market price × HotSell, the offer's factor + Hot`, hotOffer ~= nil and hotOffer.market == "hot" and hotOffer.base == baseHot
	and hotOffer.price == wantHot and baseHot >= CollectionRules.sell(entryOf(A, hot)) * Config.Market.HotSell - 1
	and wantHot >= baseHot * (O.Min + (O.Max - O.Min) * 0.5 + O.Hot) - 1e-6, `{baseHot} {wantHot}`)
moneyAt = #money
E.advance(1)
E.fire(A, "Visitors", { kind = "accept", id = (hotOffer :: any).id })
E.flush()
check("… accepted: paid its price, the stands' hot share (onPaid's hot = 1: hotsell)", paid(A, "VisitorOffer", moneyAt) == wantHot)

-- ── The rate limit ─────────────────────────────────────────────────────────
E.advance(O.Every)
local limited = Offers.make(A, armchair, "tourist", 0.5)
mark = #E.sent
for _ = 1, Config.Robust.Limits.Visitors + 2 do
	E.fire(A, "Visitors", { kind = "accept", id = "o0" })
end
check(`the remote: {Config.Robust.Limits.Visitors} requests a second (the rest dropped unanswered)`, #E.received(A, "Notice", mark) == Config.Robust.Limits.Visitors)
E.advance(1)
E.fire(A, "Visitors", { kind = "decline", id = (limited :: any).id })
check("… a second later it answers again (DECLINE)", Offers.current(A) == nil and answers[#answers].how == "declined")

-- ── Leaving ────────────────────────────────────────────────────────────────
E.advance(O.Every)
local leaving = Offers.make(A, armchair, "tourist", 0.5, "tok-leave")
E.leave(A)
check("Ann leaves with an offer open: closed (left), the visitor hears", leaving ~= nil and Offers.current(A) == nil and answers[#answers].how == "left"
	and answers[#answers].offer.token == "tok-leave")
check("a player whose save is not there: no offer", Offers.make(A, armchair, "tourist", 0.5) == nil and not Offers.ready(A))

-- ── The offer task never picked while the visitors are off ────────────────
do
	local user: number? = nil
	for id = 400, 4000 do
		local picks = TaskRules.fresh(id, E.now, nil).daily
		for _, pick in picks do
			if pick.id == "offer" then
				user = id
			end
		end
		if user then
			break
		end
	end
	check("(a player whose picks today hold the offer task)", user ~= nil)
	Config.Visitors.On = false
	local C = E.join(user :: number, "Cleo")
	E.flush()
	local has = false
	for _, pick in profileOf(C).sandboxTasks.daily do
		has = has or pick.id == "offer"
	end
	check("Config.Visitors.On false: her picks skip it (no visitors, no offers)", not has and #profileOf(C).sandboxTasks.daily == Config.SandboxTasks.Daily)
	Config.Visitors.On = true
end

check("no warnings", #E.warnings == 0, E.warnings[1])
if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
