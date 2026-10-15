-- 8.7 SANDBOX, trading between players on the server: the real server/PlayerTrade.luau with the real
-- server/PlayerData.luau, server/Collection.luau (its new setSale and transfer), server/Upgrades.luau,
-- server/CollectionBook.luau, server/SandboxTasks.luau, server/VisitorOffers.luau and server/SandboxBadges.luau
-- (PlayerTradeServer.luau and the others through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's players,
-- DataStore, clock and Net; three and more players. Checked:
--   * the composer (Make an offer): its piece, value, bounds, the buyer's $ a minute, "new for your book"; the refusals
--     (your own piece, an empty stand, no warehouse, an offer of yours still open);
--   * an offer and ACCEPT: the card and the toast to the seller, "sent" to the buyer; the money (PlayerBuy, PlayerSale,
--     TradeFee: 8 % gone), the piece into the buyer's stock (a new uid of theirs, not on show, its look kept), the
--     seller's stand free and their income down, the buyer's book, the toasts, the closed and result messages, the
--     analytics, the badge, both saved soon;
--   * DECLINE; the clock run out; the buyer out of money at ACCEPT; the piece taken down, moved, sold meanwhile; the
--     buyer's stock full at ACCEPT; the seller leaving, the buyer leaving; the seller's warehouse a level down;
--   * a price out of the bounds refused; the rate limits (the remote's, one offer every 5 s); one open offer a buyer and
--     PerSeller a seller; a self-trade refused (PlayerTrade and Collection.transfer);
--   * the FOR SALE sign: Set price (the bounds, take off), in the state, Buy $X's question, BUY only at the price shown,
--     the sign gone with the piece taken down; a visitor's offer and other players' offers for the piece closed by the
--     sale ("gone"; the buyer's own quietly); a big sale's chat line for everybody;
--   * the save: the sign survives a rejoin; an 8.6 save (no field, the collection kept) and junk in it load as not for
--     sale; a save written again by an older server (the field dropped) too.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
local CollectionRules = require("./CollectionRules")
local Visitors = require("./Visitors")
local Market = require("./Market")
local Rules = require("./PlayerTradeRules")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Upgrades = require("./UpgradesServer")
local Book = require("./CollectionBookServer")
local Tasks = require("./SandboxTasksServer")
local Offers = require("./VisitorOffersServer")
local Badges = require("./SandboxBadgesServer")
local Trade = require("./PlayerTradeServer")

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

local T = Config.PlayerTrade
E.now = 20372 * 86400 + 12 * 3600

-- What the hooks saw: the money, the analytics' events.
local money: { { player: any, delta: number, reason: string?, sku: string? } } = {}
PlayerData.onMoney = function(player: Player, delta: number, reason: string?, sku: string?)
	table.insert(money, { player = player, delta = delta, reason = reason, sku = sku })
end
local function paid(player: any, reason: string, from: number?): (number, number, string?)
	local sum, count, sku = 0, 0, nil
	for index = (from or 0) + 1, #money do
		local m = money[index]
		if m.player == player and m.reason == reason then
			sum += m.delta
			count += 1
			sku = m.sku
		end
	end
	return sum, count, sku
end
local events: { { player: any, name: string, value: any, a: any, b: any } } = {}
PlayerData.analytics.event = function(player: any, name: any, value: any, a: any, b: any)
	table.insert(events, { player = player, name = name, value = value, a = a, b = b })
end
local function tradeEvents(how: string): { any }
	local out = {}
	for _, e in events do
		if e.name == "PlayerTrade" and e.a == how then
			table.insert(out, e)
		end
	end
	return out
end
-- the badges: a fake BadgeService; First Deal set up (its id) and awarded on this server
local awarded: { [number]: { number } } = {}
Badges.service = {
	UserHasBadgeAsync = function()
		return false
	end,
	AwardBadgeAsync = function(_self: any, userId: number, id: number)
		awarded[userId] = awarded[userId] or {}
		table.insert(awarded[userId], id)
		return true
	end,
}
Config.SandboxBadges.Badges.firstDeal.id = 8701

-- (the name the server says: the display name, the user name without one: the runtime's players have none)
local function nm(player: any): string
	return player.DisplayName or player.Name
end
local function profileOf(player: any): any
	return PlayerData.get(player) :: any
end
local function entryOf(player: any, uid: string): any
	for _, entry in Collection.stock(player) do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end
local function uidOf(player: any, item: string, nth: number?): string
	local seen = 0
	for _, entry in Collection.stock(player) do
		if entry.item == item then
			seen += 1
			if seen == (nth or 1) then
				return entry.uid
			end
		end
	end
	error(`no {item} of {player.Name}`)
end
local function said(player: any, from: number): { string }
	local out = {}
	for _, text in E.received(player, "Notice", from) do
		table.insert(out, tostring(text))
	end
	return out
end
local function heard(player: any, from: number, text: string): boolean
	return table.find(said(player, from), text) ~= nil
end
local function lastSaid(player: any, from: number): string
	local list = said(player, from)
	return list[#list] or ""
end
local function trade(player: any, from: number, kind: string): { any }
	return kinds(E.received(player, "PlayerTrade", from), kind)
end

PlayerData.start()
Collection.start()
Upgrades.start()
Book.start()
Tasks.start()
Offers.start()
Trade.start()
Trade.start() -- (twice: once)

local ann = E.join(301, "Ann") -- (a buyer)
local bob = E.join(302, "Bob") -- (the seller)
local cid = E.join(303, "Cid") -- (another buyer)
E.flush()
for _, p in { ann, bob, cid } do
	profileOf(p).money = 50000
end
Upgrades.admin(bob, "level5") -- (Bob's warehouse the Logistics Center: 24 stands)
for _, item in { "gramophone", "piano", "sofa", "armchair", "plant", "tv", "radio" } do
	Collection.add(bob, { item = item, condition = 0.9 })
end
E.flush()
local gramophone, piano, sofa, armchair = uidOf(bob, "gramophone"), uidOf(bob, "piano"), uidOf(bob, "sofa"), uidOf(bob, "armchair")
local plant, tv, radio = uidOf(bob, "plant"), uidOf(bob, "tv"), uidOf(bob, "radio")
for stand, uid in { gramophone, piano, sofa, armchair, plant, tv, radio } do
	Collection.display(bob, uid, stand)
end
E.flush()
check("(Bob's seven pieces on stands 1 – 7 of his 24)", Collection.stands(bob) == 24 and entryOf(bob, radio).stand == 7)

-- ── The composer ───────────────────────────────────────────────────────────
local gramEntry = entryOf(bob, gramophone)
local gramValue = Rules.value(gramEntry)
local least, most = Rules.bounds(gramValue)
local mark = #E.sent
local message, why = Trade.compose(ann, bob, 1)
E.flush()
local composed = trade(ann, mark, "compose")[1]
local piece = Rules.readPiece(composed)
check("Make an offer: the composer for Ann (the piece on stand 1, its value, the bounds, read on her client)", message ~= nil and why == nil and piece ~= nil
	and piece.uid == gramophone and piece.stand == 1 and piece.name == gramEntry.name and piece.value == gramValue and piece.least == least and piece.most == most
	and piece.seller == 302 and piece.sellerName == nm(bob), why)
check("… the $ a minute in HER warehouse (her boost, her market), new for her book, no sign, her money", piece ~= nil
	and math.abs(piece.income - CollectionRules.income(gramEntry, Collection.boost(ann), Collection.market(ann))) < 0.01 and piece.isNew == true and piece.sale == nil
	and piece.money == 50000)
check("… nothing to Bob", #trade(bob, mark, "compose") == 0)
local _, own = Trade.compose(bob, bob, 1)
local _, empty = Trade.compose(ann, bob, 20)
check("… refused: his own piece, an empty stand", own == "That's your own piece." and empty == "Nothing is on show on this stand.", `{own} | {empty}`)
Collection.hasWarehouse = function(player: Player): boolean
	return player ~= ann
end
local _, house = Trade.compose(ann, bob, 1)
check("… refused: no warehouse of her own (a full server's fifth player)", house == "You need a warehouse of your own to buy: wait for a free plot.", house)
Collection.hasWarehouse = nil

-- ── An offer, ACCEPT ───────────────────────────────────────────────────────
local price = Rules.clamp(gramValue * 2, gramValue)
local fee = Rules.fee(price)
mark = #E.sent
local offer, offerWhy = Trade.offer(ann, bob, gramophone, 1, price)
E.flush()
local card = trade(bob, mark, "offer")[1]
local read = Visitors.readOffer(card)
check("an offer: open, the price, the piece's value as its base", offer ~= nil and offerWhy == nil and offer.price == price and offer.value == gramValue and offer.stand == 1
	and #Trade.open(bob) == 1, offerWhy)
check("… Bob's card (a player's offer: read by client/OfferCard, \"🧑 Ann offers\") and his toast", read ~= nil and read.player == true and read.price == price
	and read.base == gramValue and read.who == nm(ann) and read.seconds == T.Expire and Visitors.cardLines(read :: any).who == `🧑 {nm(ann)} offers`
	and heard(bob, mark, Rules.offerToast(nm(ann), price, gramEntry.name, gramValue)))
check("… Ann: sent (its clock), a notice; analytics PlayerTrade made", #trade(ann, mark, "sent") == 1 and trade(ann, mark, "sent")[1].seconds == T.Expire
	and string.find(lastSaid(ann, mark), "Offer sent", 1, true) ~= nil and #tradeEvents("made") == 1 and tradeEvents("made")[1].value == price)
local again, againWhy = Trade.offer(ann, bob, piano, 2, Rules.bounds(Rules.value(entryOf(bob, piano))))
local _, composeWhy = Trade.compose(ann, bob, 2)
check("… one open offer a buyer: another refused (and the composer too)", again == nil and string.find(againWhy or "", "still open", 1, true) ~= nil and composeWhy == againWhy, againWhy)

local moneyAt = #money
local annMoney, bobMoney = profileOf(ann).money, profileOf(bob).money
local incomeBefore = Collection.incomePerMinute(bob)
local stockBefore = #Collection.stock(ann)
local savesBefore = E.writes
mark = #E.sent
E.fire(bob, "PlayerTrade", { kind = "answer", id = (offer :: any).id, accept = true })
E.flush()
local bought: any = nil
for _, entry in Collection.stock(ann) do
	if entry.item == "gramophone" then
		bought = entry
	end
end
check("ACCEPT: the money: Ann −price (PlayerBuy), Bob +price (PlayerSale) −8 % (TradeFee: gone)", paid(ann, "PlayerBuy", moneyAt) == -price and paid(bob, "PlayerSale", moneyAt) == price
	and paid(bob, "TradeFee", moneyAt) == -fee and fee == math.floor(price * 0.08 + 0.5) and profileOf(ann).money == annMoney - price and profileOf(bob).money == bobMoney + price - fee,
	`{paid(ann, "PlayerBuy", moneyAt)} {paid(bob, "PlayerSale", moneyAt)} {paid(bob, "TradeFee", moneyAt)}`)
local _, _, sku = paid(bob, "PlayerSale", moneyAt)
check("… its SKU the furniture id; no CollectionSale (a deal between players counts for no sell task)", sku == "gramophone" and select(2, paid(bob, "CollectionSale", moneyAt)) == 0)
check("… the piece: gone from Bob, in Ann's stock (not on show, a new uid of hers, its look and name kept, no sign)", entryOf(bob, gramophone) == nil and bought ~= nil
	and bought.stand == nil and string.sub(bought.uid, 1, 4) == "301-" and bought.variant == gramEntry.variant and bought.condition == gramEntry.condition and bought.name == gramEntry.name
	and bought.sale == nil and #Collection.stock(ann) == stockBefore + 1)
check("… Bob's stand 1 free, his income down by the piece's", Collection.incomePerMinute(bob) < incomeBefore
	and math.abs(incomeBefore - Collection.incomePerMinute(bob) - CollectionRules.income(gramEntry, Collection.boost(bob), Collection.market(bob))) < 1e-6)
check("… Ann's book: the gramophone found", ((Book.book(ann) :: any).gramophone or {}).n == 1)
check("… the toasts: \"🤝 Sold … (fee $X)\" to Bob, \"📦 Bought … from Bob\" to Ann", heard(bob, mark, Rules.soldToast(gramEntry.name, nm(ann), price, fee))
	and heard(ann, mark, Rules.boughtToast(gramEntry.name, nm(bob), price)))
check("… Bob's card closed (sold), Ann's result; no offer open; analytics sold", #trade(bob, mark, "closed") == 1 and trade(bob, mark, "closed")[1].how == "sold"
	and trade(ann, mark, "result")[1].how == "sold" and #Trade.open() == 0 and #tradeEvents("sold") == 1)
E.advance(1)
check("… First Deal for both (its id set up)", awarded[301] ~= nil and awarded[301][1] == 8701 and awarded[302] ~= nil and awarded[302][1] == 8701)
E.advance(Config.Saving.Gap + Config.Saving.Soon + 1)
local stored = E.saves.Player_301
local inSave = false
for _, entry in (stored and stored.collection and stored.collection.entries) or {} do
	inSave = inSave or entry.uid == bought.uid
end
check("… both saved soon (the piece in Ann's save)", E.writes > savesBefore and inSave)
mark = #E.sent
E.fire(bob, "PlayerTrade", { kind = "answer", id = (offer :: any).id, accept = true })
check("… a second ACCEPT: that offer isn't open any more", lastSaid(bob, mark) == "That offer isn't open any more.")

-- ── DECLINE, the clock ─────────────────────────────────────────────────────
local pianoValue = Rules.value(entryOf(bob, piano))
local cidOffer = Trade.offer(cid, bob, piano, 2, pianoValue)
mark = #E.sent
moneyAt = #money
E.fire(bob, "PlayerTrade", { kind = "answer", id = (cidOffer :: any).id, accept = false })
check("DECLINE: closed, Cid hears it in words, nothing moved", #Trade.open() == 0 and trade(bob, mark, "closed")[1].how == "declined"
	and heard(cid, mark, `{nm(bob)} declined your offer for the {entryOf(bob, piano).name}.`) and entryOf(bob, piano).stand == 2 and #money == moneyAt)
cidOffer = Trade.offer(cid, bob, piano, 2, pianoValue + 1)
mark = #E.sent
E.advance(T.Expire - 1)
check("… open until its clock runs out", #Trade.open() == 1)
E.advance(2)
check("the clock run out: expired (the card closed, Cid told)", #Trade.open() == 0 and trade(bob, mark, "closed")[1].how == "expired"
	and heard(cid, mark, `{nm(bob)} didn't answer: your offer for the {entryOf(bob, piano).name} ran out.`))

-- ── The buyer out of money at ACCEPT; the stock full ───────────────────────
cidOffer = Trade.offer(cid, bob, piano, 2, pianoValue * 3)
profileOf(cid).money = 10
mark = #E.sent
moneyAt = #money
local got, refused = Trade.answer(bob, (cidOffer :: any).id, true)
check("ACCEPT with Cid out of money: refused, nothing moved, both told, closed (failed)", got == nil and refused == `{nm(cid)} can't pay {Market.money(pianoValue * 3)} any more: the deal is off.`
	and entryOf(bob, piano).stand == 2 and #money == moneyAt and string.find(lastSaid(cid, mark), "couldn't pay", 1, true) ~= nil and #Trade.open() == 0
	and trade(bob, mark, "closed")[1].how == "failed", refused)
profileOf(cid).money = 50000
cidOffer = Trade.offer(cid, bob, piano, 2, pianoValue)
local maxStock = Config.Collection.MaxStock
Config.Collection.MaxStock = #Collection.stock(cid) -- (Cid's stock full meanwhile)
mark = #E.sent
got, refused = Trade.answer(bob, (cidOffer :: any).id, true)
check("ACCEPT with Cid's stock full: refused (his warehouse full), nothing moved", got == nil and refused == `{nm(cid)}'s warehouse is full: the deal is off.`
	and entryOf(bob, piano).stand == 2 and string.find(lastSaid(cid, mark), "warehouse is full", 1, true) ~= nil, refused)
local _, fullWhy = Trade.compose(cid, bob, 2)
check("… the composer refused too while it is full", string.find(fullWhy or "", "warehouse is full", 1, true) ~= nil, fullWhy)
Config.Collection.MaxStock = maxStock

-- ── The piece taken down, moved, sold meanwhile ────────────────────────────
cidOffer = Trade.offer(cid, bob, piano, 2, pianoValue)
mark = #E.sent
Collection.undisplay(bob, piano)
E.flush()
check("the piece taken down: the offer gone (Cid told)", #Trade.open() == 0 and trade(bob, mark, "closed")[1].how == "gone"
	and heard(cid, mark, `Your offer is off: the {entryOf(bob, piano).name} isn't on show at {nm(bob)}'s any more.`))
Collection.display(bob, piano, 2)
cidOffer = Trade.offer(cid, bob, piano, 2, pianoValue)
Collection.display(bob, piano, 9)
E.flush()
check("… moved to another stand: gone", #Trade.open() == 0)
Collection.display(bob, piano, 2)
local sofaValue = Rules.value(entryOf(bob, sofa))
cidOffer = Trade.offer(cid, bob, sofa, 3, sofaValue)
Collection.sell(bob, sofa)
E.flush()
check("… sold to the game: gone; an ACCEPT after it refused", #Trade.open() == 0 and (Trade.answer(bob, (cidOffer :: any).id, true)) == nil)

-- ── Bounds, limits, self ───────────────────────────────────────────────────
local pLeast, pMost = Rules.bounds(pianoValue)
local low, lowWhy = Trade.offer(cid, bob, piano, 2, pLeast - 1)
local high, highWhy = Trade.offer(cid, bob, piano, 2, pMost + 1)
local frac = Trade.offer(cid, bob, piano, 2, pLeast + 0.5)
local wrong = Trade.offer(cid, bob, piano, 5, pLeast)
check("a price out of the bounds refused (the words name them); a fraction; the wrong stand", low == nil and high == nil and frac == nil and wrong == nil
	and lowWhy == `Price it between {Market.money(pLeast)} and {Market.money(pMost)}.` and highWhy == lowWhy, lowWhy)
local selfOffer, selfWhy = Trade.offer(bob, bob, piano, 2, pLeast)
local selfDeal, selfRefusal = Collection.transfer(bob, bob, piano, 2, pLeast, 0)
check("a self-trade refused (PlayerTrade and Collection.transfer)", selfOffer == nil and selfWhy == "That's your own piece." and selfDeal == nil and selfRefusal ~= nil and selfRefusal.code == "self")
E.advance(6)
mark = #E.sent
E.fire(cid, "PlayerTrade", { kind = "offer", seller = 302, uid = piano, stand = 2, price = pLeast })
E.fire(cid, "PlayerTrade", { kind = "offer", seller = 302, uid = armchair, stand = 4, price = Rules.value(entryOf(bob, armchair)) })
check("the remote: an offer made; a second within 5 s: one offer every few seconds", #Trade.open(cid) == 1 and Trade.open(cid)[1].uid == piano
	and lastSaid(cid, mark) == "One offer every few seconds: try again in a moment.", lastSaid(cid, mark))
for _ = 1, 12 do
	E.fire(cid, "PlayerTrade", { kind = "answer", id = "nope", accept = true })
end
local answered = 0
for _, text in said(cid, mark) do
	answered += if text == "That offer isn't open any more." then 1 else 0
end
check("… the remote's limit: a burst of 12 answered PlayerTrade a second at most", answered >= 1 and answered <= Config.Robust.Limits.PlayerTrade, answered)
E.advance(1)
E.fire(cid, "PlayerTrade", "offer")
E.fire(cid, "PlayerTrade", { kind = "offer", seller = "302", uid = piano, stand = 2, price = pLeast })
E.fire(cid, "PlayerTrade", { kind = "buy", seller = 999, uid = piano, stand = 2, price = pLeast })
E.fire(cid, "PlayerTrade", { kind = "price", uid = { 1 }, price = "x" })
check("… junk ignored or refused in words (no error)", #Trade.open(cid) == 1)
-- PerSeller: Dee and Eve offer too, a fourth buyer is refused
local dee = E.join(304, "Dee")
local eve = E.join(305, "Eve")
local fay = E.join(306, "Fay")
E.flush()
for _, p in { dee, eve, fay } do
	profileOf(p).money = 50000
end
local armValue, plantValue = Rules.value(entryOf(bob, armchair)), Rules.value(entryOf(bob, plant))
Trade.offer(dee, bob, armchair, 4, armValue)
Trade.offer(eve, bob, plant, 5, plantValue)
local fourth, fourthWhy = Trade.offer(fay, bob, radio, 7, Rules.value(entryOf(bob, radio)))
check(`PerSeller: {T.PerSeller} offers open to Bob; a fourth refused`, #Trade.open(bob) == T.PerSeller and fourth == nil
	and fourthWhy == `{nm(bob)} has {T.PerSeller} offers open already: try again in a moment.`, fourthWhy)

-- ── Leaving ────────────────────────────────────────────────────────────────
mark = #E.sent
E.leave(eve)
check("the buyer leaves: her offer closed (left), Bob told", #Trade.open(bob) == 2 and heard(bob, mark, `{nm(eve)} left: their offer for your {entryOf(bob, plant).name} is off.`))
-- a seller who leaves: Fay sells to Dee… no: Dee's offer stays with Bob; Fay displays a piece, Cid's offer is elsewhere
Collection.add(fay, { item = "plant", condition = 1 })
E.flush()
local fayPlant = uidOf(fay, "plant")
Collection.display(fay, fayPlant, 1)
local fayOffer = Trade.offer(dee, fay, fayPlant, 1, Rules.value(entryOf(fay, fayPlant)))
check("(an offer from Dee to Fay refused: Dee's offer to Bob still open)", fayOffer == nil)
local gusLike = E.join(307, "Gus")
E.flush()
profileOf(gusLike).money = 50000
fayOffer = Trade.offer(gusLike, fay, fayPlant, 1, Rules.value(entryOf(fay, fayPlant)))
mark = #E.sent
E.leave(fay)
check("the seller leaves: the offer to her closed (left), Gus told", fayOffer ~= nil and #Trade.open(gusLike) == 0
	and heard(gusLike, mark, `{nm(fay)} left: your offer for the {(fayOffer :: any).name} is off.`) and trade(gusLike, mark, "result")[1].how == "left")
-- the seller's warehouse a level down: pieces past its stands go to the stock, their offers with them
mark = #E.sent
local deeOffer = Trade.open(dee)[1]
Upgrades.admin(bob, "level2") -- (a Workshop: 4 stands; the armchair on stand 4 stays, the radio on stand 7 goes)
E.flush()
local radioAfter = entryOf(bob, radio)
check("(a level down: the radio on stand 7 back to the stock)", radioAfter.stand == nil and entryOf(bob, armchair).stand == 4)
Collection.display(bob, radio, 3)
E.flush()
local radioOffer = Trade.offer(fay, bob, radio, 3, Rules.value(radioAfter))
check("(Fay gone: no offer from her)", radioOffer == nil)
Trade.offer(gusLike, bob, radio, 3, Rules.value(radioAfter))
Upgrades.admin(bob, "level1") -- (the Garage: 2 stands; the radio on 3 and the armchair on 4 go)
E.flush()
check("the seller's warehouse a level down: the offers for pieces that left their stands gone", #Trade.open(gusLike) == 0 and #Trade.open(dee) == 0 and deeOffer ~= nil)
Upgrades.admin(bob, "level5")
E.flush()
Collection.display(bob, armchair, 4)
Collection.display(bob, plant, 5)
Collection.display(bob, tv, 6)
Collection.display(bob, radio, 7)
E.flush()
for _, open in Trade.open(bob) do -- (Cid's offer for the piano: declined)
	Trade.answer(bob, open.id, false)
end

-- ── The FOR SALE sign ──────────────────────────────────────────────────────
E.advance(6)
local radioValue = Rules.value(entryOf(bob, radio))
local rLeast, rMost = Rules.bounds(radioValue)
mark = #E.sent
check("Set price: the picker for Bob (pricing: the piece on stand 7)", Trade.pricing(bob, 7) == nil and (Rules.readPiece(trade(bob, mark, "pricing")[1]) :: any).uid == radio)
check("… nothing for an empty stand", Trade.pricing(bob, 20) == "Nothing is on show on this stand.")
Trade.prompt(ann, bob, 7, "price")
check("… another player's Set price: whose warehouse it is", lastSaid(ann, mark) == `This is {nm(bob)}'s warehouse.`)
local okLow, lowPrice = Trade.setPrice(bob, radio, rLeast - 1)
local okHigh = Trade.setPrice(bob, radio, rMost + 1)
check("… a price out of the bounds refused", not okLow and not okHigh and string.find(lowPrice or "", "Price it between", 1, true) ~= nil and entryOf(bob, radio).sale == nil)
local signPrice = Rules.clamp(radioValue * 3, radioValue)
mark = #E.sent
E.fire(bob, "PlayerTrade", { kind = "price", uid = radio, price = signPrice })
E.flush()
local states = kinds(E.received(bob, "Collection", mark), "state")
local viewSale = nil
for _, v in (states[#states] or { stock = {} }).stock do
	if v.uid == radio then
		viewSale = v.sale
	end
end
check("… SET (the remote): the sign on the piece, in Bob's state, his notice", entryOf(bob, radio).sale == signPrice and viewSale == signPrice
	and string.find(lastSaid(bob, mark), "FOR SALE", 1, true) ~= nil)
local stockUid = Collection.add(bob, { item = "sofa", condition = 1 }) :: string
local stockOk, stockWhy = Trade.setPrice(bob, stockUid, Rules.value(entryOf(bob, stockUid)))
check("… a piece in the stock takes no sign", not stockOk and string.find(stockWhy or "", "on show first", 1, true) ~= nil and entryOf(bob, stockUid).sale == nil, stockWhy)
-- Buy $X: the question, then BUY only at its price
mark = #E.sent
Trade.prompt(ann, bob, 7, "buy")
local confirm = Rules.readPiece(trade(ann, mark, "confirm")[1])
check("Buy $X: Ann's question (the price, her money)", confirm ~= nil and confirm.price == signPrice and confirm.uid == radio and confirm.money == profileOf(ann).money)
local poorCid = profileOf(cid).money
profileOf(cid).money = 1
check("… refused before the question without the money", string.find(Trade.askBuy(cid, bob, 7) or "", "not enough", 1, true) ~= nil)
profileOf(cid).money = poorCid
local _, noSign = Trade.buy(ann, bob, piano, 2, signPrice)
local _, otherPrice = Trade.buy(ann, bob, radio, 7, signPrice - 1)
check("… BUY at another price refused (the price changed); a piece without a sign refused", string.find(otherPrice or "", "The price changed", 1, true) ~= nil
	and string.find(noSign or "", "off sale", 1, true) ~= nil and entryOf(bob, radio) ~= nil, otherPrice)
-- a visitor's offer and Cid's offer for the radio; Ann's own offer for it too
local visitor = Offers.make(bob, radio, "collector", 0.5)
Trade.offer(cid, bob, radio, 7, radioValue)
check("(a visitor's offer and Cid's open for the radio)", visitor ~= nil and Offers.current(bob) ~= nil and #Trade.open(cid) == 1)
mark = #E.sent
moneyAt = #money
local feeSign = Rules.fee(signPrice)
E.advance(0.5)
E.fire(ann, "PlayerTrade", { kind = "buy", seller = 302, uid = radio, stand = 7, price = signPrice })
E.flush()
check("BUY (the remote): the radio Ann's, the money moved (the fee gone), analytics sign", entryOf(bob, radio) == nil and paid(ann, "PlayerBuy", moneyAt) == -signPrice
	and paid(bob, "PlayerSale", moneyAt) == signPrice and paid(bob, "TradeFee", moneyAt) == -feeSign and #tradeEvents("sign") == 1)
check("… the visitor's offer closed (gone)", Offers.current(bob) == nil and kinds(E.received(bob, "Visitors", mark), "closed")[1].how == "gone")
check("… Cid's offer for it closed (gone), told it went to somebody else", #Trade.open(cid) == 0
	and heard(cid, mark, `{nm(bob)} sold the {radioAfter.name} to somebody else: your offer is off.`))
-- the sign goes when its piece is taken down
Trade.setPrice(bob, armchair, Rules.value(entryOf(bob, armchair)) * 2)
check("(the armchair on sale)", entryOf(bob, armchair).sale ~= nil)
Collection.undisplay(bob, armchair)
check("… taken down: no sign", entryOf(bob, armchair).sale == nil)
Collection.display(bob, armchair, 4)
Trade.setPrice(bob, armchair, Rules.value(entryOf(bob, armchair)) * 2)
local okOff = Trade.setPrice(bob, armchair, 0)
check("… TAKE OFF SALE (price 0): no sign", okOff and entryOf(bob, armchair).sale == nil)
-- the buyer's own open offer for a piece she buys by its sign: closed quietly
E.advance(6)
local tvValue = Rules.value(entryOf(bob, tv))
Trade.setPrice(bob, tv, tvValue * 2)
local annOffer = Trade.offer(ann, bob, tv, 6, tvValue)
mark = #E.sent
Trade.buy(ann, bob, tv, 6, tvValue * 2)
E.flush()
check("her own offer for what she bought: closed (bought), no words about it", annOffer ~= nil and #Trade.open(ann) == 0 and trade(ann, mark, "result")[1].how == "bought"
	and not heard(ann, mark, `{nm(bob)} sold the {(annOffer :: any).name} to somebody else: your offer is off.`))

-- ── A big sale: the chat line for everybody ────────────────────────────────
local plantNow = entryOf(bob, plant)
local big = math.max(T.BigSale, Rules.value(plantNow))
local saved = T.MaxTimes
T.MaxTimes = math.ceil(big / Rules.value(plantNow)) + 1
Trade.setPrice(bob, plant, big)
mark = #E.sent
Trade.buy(cid, bob, plant, 5, big)
local news = 0
for _, sent in E.sent do
	if sent.remote == "PlayerTrade" and type(sent.args[1]) == "table" and sent.args[1].kind == "news" then
		news += 1
	end
end
check("a big sale: its line to every player here", news >= 4 and entryOf(bob, plant) == nil, news)
T.MaxTimes = saved

-- ── The save ───────────────────────────────────────────────────────────────
local pianoSign = Rules.clamp(pianoValue * 1.5, pianoValue)
Trade.setPrice(bob, piano, pianoSign)
E.flush()
E.leave(bob)
local bobSave = E.saves.Player_302
local savedSign = nil
for _, entry in bobSave.collection.entries do
	if entry.uid == piano then
		savedSign = entry.sale
	end
end
check("the save: the sign in Bob's leave save", savedSign == pianoSign)
local bob2 = E.join(302, "Bob")
E.flush()
check("… back: the piano on its stand, its sign kept", entryOf(bob2, piano) ~= nil and entryOf(bob2, piano).stand == 2 and entryOf(bob2, piano).sale == pianoSign)
-- an older server writes it again: it drops the field (its clean knows none)
E.leave(bob2)
for _, entry in E.saves.Player_302.collection.entries do
	entry.sale = nil
end
local bob3 = E.join(302, "Bob")
E.flush()
check("… written again by an 8.6 server (the field dropped): back, simply not for sale", entryOf(bob3, piano) ~= nil and entryOf(bob3, piano).stand == 2 and entryOf(bob3, piano).sale == nil)
-- an 8.6 save: the collection kept with its flag, no sale anywhere; junk in one
E.saves.Player_308 = { money = 900, collectionKept = true, collection = { nextUid = 4, entries = {
	{ uid = "308-1", item = "sofa", variant = 1, condition = 1, name = "Sofa", stand = 1, got = 1 },
	{ uid = "308-2", item = "radio", variant = 1, condition = 1, name = "Radio", stand = 2, got = 2, sale = "lots" },
	{ uid = "308-3", item = "tv", variant = 1, condition = 1, name = "TV", got = 3, sale = 500 },
} } }
local hal = E.join(308, "Hal")
E.flush()
check("an 8.6 save (no sign) and junk in one: loaded, not for sale, the pieces on their stands", entryOf(hal, "308-1").stand == 1 and entryOf(hal, "308-1").sale == nil
	and entryOf(hal, "308-2").sale == nil and entryOf(hal, "308-3").sale == nil and #Collection.stock(hal) == 3)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
