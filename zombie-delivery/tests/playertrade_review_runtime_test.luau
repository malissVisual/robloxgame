-- 8.7 review of trading between players (server/PlayerTrade.luau and the modules around it): the review's findings,
-- each closed, on the real modules as tests/playertrade_runtime_test.luau runs them (server/PlayerData.luau,
-- Collection.luau, Upgrades.luau, CollectionBook.luau, SandboxTasks.luau, VisitorOffers.luau, PlayerTrade.luau on
-- tests/runtime/CollectionRuntime.luau's players, DataStore, clock and Net). Each check here failed before the fix:
--   1. a bought piece fills no book: the book's whole set of 68 (broken, at 1×: the cheapest) sold to a fresh account
--      pays it no milestone, earns no book badge (shared/SandboxBadgeRules.luau: legendary, fullBook), finds nothing
--      and toasts no "new"; its pages are there, marked bought, in the save too, and stay so after a rejoin (the stock's
--      backfill makes no find of them); the first piece a move brings home is a find; the milestones paid go to the
--      save's `rewards` as "book:<id>" (an 8.2 server's copy), the ones not reached never;
--   2. a piece passed back and forth between two friends counts for neither one's "home" or "rare" tasks (a piece that
--      comes home still does);
--   3. a deal's two saves are written at once, the buyer's first: also with the request budget under
--      Config.Saving.Reserve and either side written a moment before (Config.Saving.Gap); a "crash" right after the
--      deal leaves no dupe and makes no money; the buyer's write failing once, the seller's waits for its retry;
--   5. who may send: an offer or a BUY through the remote alone (no prompt, a guessed uid) is refused; a prompt's ticket
--      is good only for its own piece and stand, for Config.PlayerTrade.Ticket s, with its buyer within Reach studs of
--      the stand (no character: not there), and is spent by its offer; after a DECLINE or an offer run out, no offer to
--      that seller for Cooldown s (after a deal: at once; a rejoin keeps it); accounts from afar can't hold a seller's
--      PerSeller slots.
-- (4, the offer card's double click: tools/phone-ui/trade.luau.)
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")

-- 10.4: trading is the SHOWROOM's (Config.Showroom): this test's stands are showroom stands (S(k) = its Base + k), its
-- showroom as big as its hall was (2, 4, 9, 9, 9 stands by level, every one a big stand's size: the test's own spots)
local SB = Config.Showroom.Base
local function S(k: number): number
	return SB + k
end
for showLevel, showCount in { 2, 4, 9, 9, 9 } do
	Config.Showroom.Levels[showLevel] = { Stands = showCount, Most = showCount }
	local spots = require("./WarehouseLayout").grid(showLevel).show
	table.clear(spots)
	for k = 1, showCount do
		spots[k] = { 0, 0, 10, 10, 180 }
	end
end
local CollectionRules = require("./CollectionRules")
local BookRules = require("./CollectionBookRules")
local BadgeRules = require("./SandboxBadgeRules")
local FurnitureLooks = require("./FurnitureLooks")
local Rules = require("./PlayerTradeRules")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Upgrades = require("./UpgradesServer")
local Book = require("./CollectionBookServer")
local Tasks = require("./SandboxTasksServer")
local Offers = require("./VisitorOffersServer")
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

local T = Config.PlayerTrade
local V3 = E.Mock.Vector3.new
E.now = 20372 * 86400 + 12 * 3600

local money: { { player: any, delta: number, reason: string? } } = {}
PlayerData.onMoney = function(player: Player, delta: number, reason: string?)
	table.insert(money, { player = player, delta = delta, reason = reason })
end
local function paid(player: any, reason: string, from: number): number
	local sum = 0
	for index = from + 1, #money do
		local m = money[index]
		if m.player == player and m.reason == reason then
			sum += m.delta
		end
	end
	return sum
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
local function uidOf(player: any, item: string): string?
	for _, entry in Collection.stock(player) do
		if entry.item == item then
			return entry.uid
		end
	end
	return nil
end
local function count(player: any, item: string): number
	local n = 0
	for _, entry in Collection.stock(player) do
		n += if entry.item == item then 1 else 0
	end
	return n
end
local function lastSaid(player: any, from: number): string
	local list = E.received(player, "Notice", from)
	return tostring(list[#list] or "")
end
-- The player's body: its root at (x, 3, z) (a new player has none: no character)
local function standAt(player: any, x: number, z: number)
	local body = player.Character
	if not body then
		body = E.Mock.Instance.new("Model")
		body.Name = player.Name
		local root = E.Mock.Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Parent = body
		player.Character = body
	end
	body:FindFirstChild("HumanoidRootPart").CFrame = E.Mock.CFrame.new(x, 3, z) -- (the recorder's part reads its Position there)
end
-- A buyer joins with money (a warehouse of their own: the runtime gives everybody one).
local function buyer(id: number, name: string, cash: number?): any
	local p = E.join(id, name)
	E.flush()
	profileOf(p).money = cash or 50000
	return p
end
-- A seller with these pieces on stands 1, 2, … (the Logistics Center: 24 stands) → the player, the uids in order.
local function seller(id: number, name: string, items: { string }, condition: number?): (any, { string })
	local p = buyer(id, name)
	Upgrades.admin(p, "level5")
	local uids = {}
	for index, item in items do
		local uid = Collection.add(p, { item = item, condition = condition or 1 }) :: string
		E.flush()
		Collection.display(p, uid, S(index))
		table.insert(uids, uid)
	end
	E.flush()
	return p, uids
end
-- A FOR SALE sign bought the way a player does: the sign, the buy question (its ticket), BUY.
local function signBuy(from: any, to: any, uid: string, stand: number): (number?, string?)
	local entry = entryOf(from, uid)
	local least = Rules.bounds(Rules.value(entry))
	Trade.setPrice(from, uid, least)
	local why = Trade.askBuy(to, from, stand)
	if why then
		return nil, why
	end
	return Trade.buy(to, from, uid, stand, least)
end

PlayerData.start()
Collection.start()
Upgrades.start()
Book.start()
Tasks.start()
Offers.start()
Trade.start()

-- ── 1. A bought piece fills no book ────────────────────────────────────────
do
	local main = buyer(501, "Main")
	Upgrades.admin(main, "level5")
	for _, item in BookRules.Pieces do
		Collection.add(main, { item = item, condition = 0 })
	end
	E.advance(2) -- (the main's own finds: its milestones paid now, before the count)
	local alt = buyer(510, "Alt", 20000)
	E.advance(1)
	local at, mark = #money, #E.sent
	local bought = 0
	for _, item in BookRules.Pieces do
		local uid = uidOf(main, item) :: string
		Collection.display(main, uid, S(1))
		bought += if signBuy(main, alt, uid, S(1)) then 1 else 0
		E.advance(0.2)
	end
	E.advance(2)
	local view = Book.book(alt) :: any
	local allMarked = true
	for _, item in BookRules.Pieces do
		allMarked = allMarked and view[item] ~= nil and view[item].bought == true
	end
	local counts = BookRules.counts(view)
	check(`1. the book's {#BookRules.Pieces} pieces sold to a fresh account at 1×, every one bought: no milestone paid for them (was $14,250 an account), none marked paid`,
		bought == #BookRules.Pieces and #Collection.stock(alt) == #BookRules.Pieces and paid(alt, "BookMilestone", at) == 0 and #Book.paid(alt) == 0, `{bought} bought, ${paid(alt, "BookMilestone", at)}`)
	check("… the book: every page there, marked bought; found 0 (no legendary)", allMarked and counts.found == 0 and counts.legendary == 0, counts.found)
	local badges = BadgeRules.fromState(BadgeRules.stateOf(profileOf(alt)))
	check("… no book badge (legendary, fullBook)", table.find(badges, "legendary") == nil and table.find(badges, "fullBook") == nil, table.concat(badges, ","))
	local toasted = 0
	for _, m in E.received(alt, "CollectionBook", mark) do
		if type(m) == "table" and (m.kind == "milestone" or (m.kind == "state" and #(m.new or {}) > 0)) then
			toasted += 1
		end
	end
	check("… no \"New in your book\" and no milestone toast for them", toasted == 0, toasted)
	-- the save and a rejoin (the stock's backfill on load)
	E.leave(alt)
	local stored = E.saves.Player_510
	local storedPage = stored and stored.collectionBook and stored.collectionBook[BookRules.Pieces[1]]
	check("… the save keeps the bought pages (bought = true)", storedPage ~= nil and storedPage.bought == true)
	at = #money
	local alt2 = E.join(510, "Alt")
	E.advance(2)
	local again = BookRules.counts(Book.book(alt2) :: any)
	check("… back after a rejoin: still bought, found 0, no milestone paid on joining", again.found == 0 and paid(alt2, "BookMilestone", at) == 0
		and #Collection.stock(alt2) == #BookRules.Pieces and ((Book.book(alt2) :: any)[BookRules.Pieces[1]] or {}).bought == true, again.found)
	-- a move brings pieces home: finds (the first a discovery), the milestone for 10 paid, mirrored for an 8.2 server
	mark = #E.sent
	Collection.add(alt2, { item = BookRules.Pieces[1], condition = 1 })
	E.advance(1)
	local news = {}
	for _, m in E.received(alt2, "CollectionBook", mark) do
		if type(m) == "table" and m.kind == "state" then
			for _, item in m.new or {} do
				table.insert(news, item)
			end
		end
	end
	local page = (Book.book(alt2) :: any)[BookRules.Pieces[1]]
	check("… a piece of it brought home: found now (a discovery, n 1, its condition)", BookRules.counts(Book.book(alt2) :: any).found == 1 and table.find(news, BookRules.Pieces[1]) ~= nil
		and page ~= nil and page.bought == nil and page.n == 1 and page.best == 1)
	for index = 2, 10 do
		Collection.add(alt2, { item = BookRules.Pieces[index], condition = 1 })
	end
	E.advance(2)
	check("… ten brought home: \"Found 10 pieces\" paid ($250), nothing else", paid(alt2, "BookMilestone", at) == 250 and #Book.paid(alt2) == 1 and Book.paid(alt2)[1] == "found10",
		paid(alt2, "BookMilestone", at))
	E.leave(alt2)
	local keys = {}
	for key in (E.saves.Player_510 or {}).rewards or {} do
		if string.sub(key, 1, 5) == "book:" then
			table.insert(keys, key)
		end
	end
	check("… its save's rewards: \"book:found10\" only (an 8.2 server's copy of the milestones paid)", #keys == 1 and keys[1] == "book:found10", table.concat(keys, ","))
	E.leave(main)
end

-- ── 2. A piece passed between friends finishes no task ─────────────────────
do
	local counted: { [any]: { [string]: number } } = {}
	local realNote = Tasks.note
	Tasks.note = function(player: any, event: string, amount: number, info: any)
		counted[player] = counted[player] or {}
		counted[player][event] = (counted[player][event] or 0) + amount
		return realNote(player, event, amount, info)
	end
	-- the cheapest rare piece of the book, broken (its value: its scrap)
	local rareItem: string? = nil
	for id, def in FurnitureLooks.Items do
		if BookRules.inBook(id) and CollectionRules.tier(CollectionRules.rarityOf(def)).rank >= Config.SandboxTasks.RareRank then
			if not rareItem or def.value < FurnitureLooks.Items[rareItem :: string].value then
				rareItem = id
			end
		end
	end
	local item = rareItem :: string
	local ann, uids = seller(902, "Ann", { item }, 0)
	local bob = buyer(901, "Bob")
	Upgrades.admin(bob, "level5")
	E.advance(5)
	counted = {}
	local holder, other, uid = ann, bob, uids[1]
	local passes = 0
	for _ = 1, 10 do
		Collection.display(holder, uid, S(1))
		passes += if signBuy(holder, other, uid, S(1)) then 1 else 0
		E.advance(0.5)
		uid = uidOf(other, item) :: string
		holder, other = other, holder
	end
	E.advance(2)
	local a, b = counted[ann] or {}, counted[bob] or {}
	check(`2. a broken rare {item} passed back and forth 10 times: "home" and "rare" counted for neither`, passes == 10 and (a.home or 0) == 0 and (a.rare or 0) == 0
		and (b.home or 0) == 0 and (b.rare or 0) == 0, `{passes} passes; Ann {a.home or 0}/{a.rare or 0}, Bob {b.home or 0}/{b.rare or 0}`)
	Collection.add(ann, { item = item, condition = 1 })
	E.advance(1)
	a = counted[ann] or {}
	check("… only a piece that comes home counts (home 1, rare 1 in all)", (a.home or 0) == 1 and (a.rare or 0) == 1, `{a.home} {a.rare}`)
	Tasks.note = realNote
	E.leave(ann)
	E.leave(bob)
end

-- ── 3. The deal's two saves: at once, the buyer's first ────────────────────
local function deepcopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local o = {}
	for k, x in v do
		o[k] = deepcopy(x)
	end
	return o
end
local function savedCount(userId: number, item: string): (number, number?)
	local s = E.saves["Player_" .. userId]
	local n = 0
	for _, e in (s and s.collection and s.collection.entries) or {} do
		n += if e.item == item then 1 else 0
	end
	return n, s and s.money
end
-- the calls written since `from`, in order: their keys
local function writes(from: number): { string }
	local out = {}
	for index = from + 1, #E.storeCalls do
		local call = E.storeCalls[index]
		if call.wrote then
			table.insert(out, call.key)
		end
	end
	return out
end
do
	local ids = 700
	local function deal(label: string, buyerSavedBefore: boolean, sellerSavedBefore: boolean, budget: number)
		ids += 10
		local bob, uids = seller(ids + 2, "Bob" .. ids, { "gramophone" })
		local ann = buyer(ids + 1, "Ann" .. ids)
		E.advance(30)
		local gram = uids[1]
		local price = Rules.clamp(Rules.value(entryOf(bob, gram)) * 2, Rules.value(entryOf(bob, gram)))
		Trade.setPrice(bob, gram, price)
		Trade.askBuy(ann, bob, S(1))
		E.advance(4)
		if buyerSavedBefore then
			PlayerData.save(ann)
		end
		if sellerSavedBefore then
			PlayerData.save(bob)
		end
		E.advance(1)
		E.budget = budget
		local from = #E.storeCalls
		local annMoney, bobMoney = profileOf(ann).money, profileOf(bob).money
		local got = Trade.buy(ann, bob, gram, S(1), price)
		local order = writes(from)
		local annKey, bobKey = `Player_{ann.UserId}`, `Player_{bob.UserId}`
		local annHas, annSaved = savedCount(ann.UserId, "gramophone")
		local bobHas, bobSaved = savedCount(bob.UserId, "gramophone")
		check(`3. {label}: both saves written with the deal (no wait), the buyer's first`, got ~= nil and order[1] == annKey and order[2] == bobKey
			and annHas == 1 and annSaved == annMoney - price and bobHas == 0 and bobSaved == bobMoney + price - Rules.fee(price), table.concat(order, " "))
		E.budget = 100
		return ann, bob, price, annMoney, bobMoney
	end
	deal("a sign bought 5 s after it was set", false, false, 100)
	deal("the buyer saved a second before", true, false, 100)
	deal("the seller saved a second before", false, true, 100)
	deal(`the request budget short (2 < Reserve {Config.Saving.Reserve})`, false, false, 2)
	-- a crash right after the deal: the stored saves as they are, the server gone, both back on a new one
	local ann, bob, price, annMoney, bobMoney = deal("then a crash", true, true, 100)
	local snapshot = deepcopy(E.saves)
	E.storeFault = function()
		return "server gone"
	end
	local annId, bobId = ann.UserId, bob.UserId
	E.leave(ann)
	E.leave(bob)
	E.advance(120)
	E.storeFault = nil
	E.saves = snapshot
	local ann2, bob2 = E.join(annId, "Ann"), E.join(bobId, "Bob")
	E.flush()
	check("… a crash right after it: the gramophone in the buyer's save only (no dupe), the money moved (none made)", count(ann2, "gramophone") == 1 and count(bob2, "gramophone") == 0
		and profileOf(ann2).money == annMoney - price and profileOf(bob2).money == bobMoney + price - Rules.fee(price))
	E.leave(ann2)
	E.leave(bob2)
	-- the buyer's write fails once: the seller's waits for the buyer's retry (never the seller's side alone)
	ids += 10
	local seller3, uids = seller(ids + 2, "Bob3", { "gramophone" })
	local buyer3 = buyer(ids + 1, "Ann3")
	E.advance(30)
	local price3 = Rules.value(entryOf(seller3, uids[1]))
	Trade.setPrice(seller3, uids[1], price3)
	Trade.askBuy(buyer3, seller3, S(1))
	local failed = false
	E.storeFault = function(key: string): string?
		if key == `Player_{buyer3.UserId}` and not failed then
			failed = true
			return "busy"
		end
		return nil
	end
	local from = #E.storeCalls
	Trade.buy(buyer3, seller3, uids[1], S(1), price3)
	local sellerLost = savedCount(seller3.UserId, "gramophone") == 0
	local buyerHas = savedCount(buyer3.UserId, "gramophone") == 1
	check("… the buyer's write failing: the seller's not written before it (the stored saves as before the deal)", failed and not sellerLost and not buyerHas, #writes(from))
	E.advance(Config.Saving.Backoff.First + 0.1)
	local order = writes(from)
	check("… its retry a moment later: the buyer's written, then the seller's", savedCount(buyer3.UserId, "gramophone") == 1 and savedCount(seller3.UserId, "gramophone") == 0
		and order[1] == `Player_{buyer3.UserId}` and order[2] == `Player_{seller3.UserId}`, table.concat(order, " "))
	E.storeFault = nil
	E.leave(buyer3)
	E.leave(seller3)
end

-- ── 5. Who may send: the prompt's ticket, being there, the cooldown ────────
do
	local bob, uids = seller(602, "Bob", { "gramophone", "tv", "piano", "sofa", "armchair", "plant" })
	local gram, tv, piano, sofa, armchair, plant = uids[1], uids[2], uids[3], uids[4], uids[5], uids[6]
	-- the stands' points (where Warehouse's prompts are); a buyer right in front of one, or far away
	local spots = {}
	for index = 1, 6 do
		spots[index] = V3(index * 10, 3, 0)
	end
	local mal = buyer(601, "Mallory")
	standAt(mal, 300, 300)
	E.advance(10)
	-- the remote alone: a guessed uid ("<UserId>-<n>"), no prompt ever used
	local mark = #E.sent
	E.fire(mal, "PlayerTrade", { kind = "offer", seller = 602, uid = "602-1", stand = S(1), price = Rules.value(entryOf(bob, gram)) })
	check("5. an offer through the remote alone (no Make an offer used, a guessed uid): refused, nothing to Bob", #Trade.open(mal) == 0
		and #E.received(bob, "PlayerTrade", mark) == 0 and lastSaid(mal, mark) == "Walk up to Bob's stand and use Make an offer there.", lastSaid(mal, mark))
	Trade.setPrice(bob, tv, Rules.value(entryOf(bob, tv)))
	E.advance(1)
	mark = #E.sent
	E.fire(mal, "PlayerTrade", { kind = "buy", seller = 602, uid = tv, stand = S(2), price = Rules.value(entryOf(bob, tv)) })
	check("… a FOR SALE sign bought through the remote alone (no Buy used): refused, nothing moved", count(mal, "tv") == 0 and entryOf(bob, tv) ~= nil
		and lastSaid(mal, mark) == "Walk up to Bob's stand and use Buy there.", lastSaid(mal, mark))
	-- the ticket: its own piece and stand only; the buyer there
	local ann = buyer(603, "Ann")
	standAt(ann, 11, 4) -- (in front of stand 1)
	Trade.prompt(ann, bob, S(1), "offer", spots[1])
	local gramValue = Rules.value(entryOf(bob, gram))
	local other, otherWhy = Trade.offer(ann, bob, piano, S(3), Rules.value(entryOf(bob, piano)))
	check("… Make an offer at stand 1: its window may offer for that piece only (the piano on stand 3 refused)", other == nil and otherWhy == "Walk up to Bob's stand and use Make an offer there.", otherWhy)
	standAt(ann, 11 + T.Reach + 5, 4)
	local far, farWhy = Trade.offer(ann, bob, gram, S(1), gramValue)
	check(`… sent from more than Reach ({T.Reach} studs) from the stand: refused`, far == nil and farWhy == "You walked away from Bob's warehouse: go back to send your offer.", farWhy)
	standAt(ann, 11 + T.Reach - 5, 4)
	local near = Trade.offer(ann, bob, gram, S(1), gramValue)
	check("… sent from within Reach: the offer made", near ~= nil and #Trade.open(ann) == 1)
	Trade.answer(bob, if near then near.id else "", true)
	local spent, spentWhy = Trade.offer(ann, bob, gram, S(1), gramValue)
	check("… the ticket spent by its offer (accepted: no cooldown; the same ticket again: refused)", count(ann, "gramophone") == 1 and spent == nil
		and spentWhy == "Walk up to Bob's stand and use Make an offer there.", spentWhy)
	local composed = Trade.compose(ann, bob, S(3), spots[3])
	check("… after a deal she may offer Bob again at once (a new prompt)", composed ~= nil)
	-- no character (dead, respawning): not there
	local cid = buyer(604, "Cid")
	Trade.prompt(cid, bob, S(3), "offer", spots[3])
	local _, bodyless = Trade.offer(cid, bob, piano, S(3), Rules.value(entryOf(bob, piano)))
	check("… a buyer with no character: not there", bodyless == "You walked away from Bob's warehouse: go back to send your offer.", bodyless)
	-- an old ticket
	standAt(cid, 31, 4)
	E.advance(T.Ticket + 1)
	local _, stale = Trade.offer(cid, bob, piano, S(3), Rules.value(entryOf(bob, piano)))
	check(`… a ticket older than Ticket ({T.Ticket} s): refused`, stale == "That was a while ago: use Make an offer at Bob's stand again.", stale)
	-- the cooldown: after a DECLINE, after one run out; none after a deal (above); a rejoin keeps it
	Trade.prompt(cid, bob, S(3), "offer", spots[3])
	local declined = Trade.offer(cid, bob, piano, S(3), Rules.value(entryOf(bob, piano)))
	Trade.answer(bob, if declined then declined.id else "", false)
	mark = #E.sent
	Trade.prompt(cid, bob, S(3), "offer", spots[3])
	local again = Trade.offer(cid, bob, piano, S(3), Rules.value(entryOf(bob, piano)))
	check(`… DECLINEd: no new offer to Bob for Cooldown ({T.Cooldown} s): the prompt says so, no composer`, declined ~= nil and again == nil
		and lastSaid(cid, mark) == `You can make Bob another offer in {T.Cooldown} s.` and #E.received(cid, "PlayerTrade", mark) == 0, lastSaid(cid, mark))
	local cidId = cid.UserId
	E.leave(cid)
	cid = buyer(cidId, "Cid")
	standAt(cid, 31, 4)
	E.advance(T.Cooldown / 2)
	local _, rejoined = Trade.compose(cid, bob, S(3), spots[3])
	E.advance(T.Cooldown / 2 + 1)
	Trade.prompt(cid, bob, S(3), "offer", spots[3])
	local later = Trade.offer(cid, bob, piano, S(3), Rules.value(entryOf(bob, piano)))
	check("… a rejoin keeps it; Cooldown s on, an offer again", rejoined ~= nil and string.find(rejoined, "another offer in", 1, true) ~= nil and later ~= nil, rejoined)
	E.advance(T.Expire + 1)
	local _, afterExpiry = Trade.compose(cid, bob, S(3), spots[3])
	check("… run out (Bob never answered): the cooldown again", #Trade.open(cid) == 0 and afterExpiry ~= nil and string.find(afterExpiry, "another offer in", 1, true) ~= nil, afterExpiry)
	-- accounts from afar can't keep Bob's PerSeller slots full
	local alts = { buyer(611, "A1"), buyer(612, "A2"), buyer(613, "A3") }
	local honest = { buyer(614, "H1"), buyer(615, "H2"), buyer(616, "H3") }
	local refused, held = 0, 0
	for round = 1, 3 do
		E.advance(6)
		for _, alt in alts do
			standAt(alt, 500, 500)
			Trade.prompt(alt, bob, S(4), "offer", spots[4]) -- (a prompt used once, then off home: no better)
			E.fire(alt, "PlayerTrade", { kind = "offer", seller = 602, uid = sofa, stand = S(4), price = Rules.value(entryOf(bob, sofa)) })
			held += #Trade.open(alt)
		end
		local h = honest[round]
		standAt(h, 41, 4)
		Trade.prompt(h, bob, S(4), "offer", spots[4])
		refused += if Trade.offer(h, bob, sofa, S(4), Rules.value(entryOf(bob, sofa)) * 5) == nil then 1 else 0
		E.advance(40) -- (Bob never answers: it runs out)
	end
	check(`… three accounts from afar hold none of Bob's {T.PerSeller} slots; an honest buyer at the stand is heard every round`, held == 0 and refused == 0, `{held} held, {refused} refused`)
	-- BUY: the question's ticket, the buyer there
	local armValue, plantValue = Rules.value(entryOf(bob, armchair)), Rules.value(entryOf(bob, plant))
	Trade.setPrice(bob, armchair, armValue)
	local eve = buyer(620, "Eve")
	standAt(eve, 51, 4)
	Trade.prompt(eve, bob, S(5), "buy", spots[5])
	standAt(eve, 51 + T.Reach + 5, 4)
	local _, farBuy = Trade.buy(eve, bob, armchair, S(5), armValue)
	standAt(eve, 51, 4)
	local boughtNear = Trade.buy(eve, bob, armchair, S(5), armValue)
	check("… BUY: refused from afar, bought from the stand", farBuy == "You walked away from Bob's warehouse: go back to buy it." and boughtNear ~= nil and count(eve, "armchair") == 1, farBuy)
	local _, wrongStand = Trade.buy(eve, bob, plant, S(6), plantValue)
	check("… the question's ticket spent, and good for its own piece only", wrongStand == "Walk up to Bob's stand and use Buy there.", wrongStand)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
