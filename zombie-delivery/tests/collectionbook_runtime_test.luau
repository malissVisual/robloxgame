-- 8.2 SANDBOX, the collection book on the server: the real server/CollectionBook.luau with the real
-- server/Collection.luau and server/PlayerData.luau (CollectionBookServer.luau, CollectionServer.luau,
-- PlayerDataServer.luau through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's players, DataStore, clock
-- and Net. Joining (an older save's book filled from its stock and its milestones paid once, with their messages after
-- the state; a new player's empty book), Collection.add → a discovery → one state push a frame with the new pieces (a
-- second one only counts, a van's load is one push), the milestones paid once each (found 10, found 20, a legendary;
-- the money's reason BookMilestone), what is not written (a farm piece, a refused add, a piece sold stays in the book),
-- the remote (the state on request, garbage, the rate limit, a client never fills its book), the save round trip (the
-- flag, rejoining gives the same book and pays nothing again) and the admin's FILL BOOK / CLEAR BOOK.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
local Rules = require("./CollectionBookRules")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")
local Book = require("./CollectionBookServer")

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
local function kinds(messages: { any }, kind: string): { any }
	local out = {}
	for _, m in messages do
		if type(m) == "table" and m.kind == kind then
			table.insert(out, m)
		end
	end
	return out
end

-- Every money change (PlayerData.onMoney).
type Money = { player: any, delta: number, reason: string?, sku: string? }
local money: { Money } = {}
PlayerData.onMoney = function(player: Player, delta: number, reason: string?, sku: string?)
	table.insert(money, { player = player, delta = delta, reason = reason, sku = sku })
end
PlayerData.analytics.event = function() end
local function paid(player: any, sku: string?): (number, number)
	local sum, n = 0, 0
	for _, m in money do
		if m.player == player and m.reason == "BookMilestone" and (sku == nil or m.sku == sku) then
			sum += m.delta
			n += 1
		end
	end
	return sum, n
end
local REWARD: { [string]: number } = {}
for _, milestone in Rules.Milestones do
	REWARD[milestone.id] = milestone.reward
end

-- A 8.1 save: money, a collection with its flag, no book yet.
local function oldSave(cash: number, items: { string }): any
	local entries = {}
	for index, item in items do
		table.insert(entries, { uid = `x-{index}`, item = item, variant = 1, condition = 0.5 + index / 100, name = item, got = 1 })
	end
	return {
		money = cash, xp = 0, deliveries = 3, tutorial = true, phone = true, starterKit = true, vestKit = true,
		noPacks = true, noJacket = true, noShoes = true, perGameBags = true, vanOnly = true, carStages = true,
		vanStages = true, xpCurve = Config.Levels.Curve, cars = { [Config.CompanyVan.Car] = true }, car = Config.CompanyVan.Car,
		collectionKept = true, collection = { entries = entries, nextUid = #entries + 1 },
	}
end

PlayerData.start()
Collection.start()
Book.start()

-- ── Joining: an older save's book from its stock ────────────────────────────
local OLD = { "sofa", "armchair", "tv", "coffee_table", "floor_lamp", "bookshelf", "painting", "plant", "piano", "sofa", "oil_painting", "jukebox" }
E.saves.Player_101 = oldSave(1000, OLD)
local mark = #E.sent
local A = E.join(101, "Ann")
local book = Book.book(A)
check("an older save: the book filled from its stock (11 pieces, the two sofas counted, their best)", book ~= nil and Rules.counts(book :: any).found == 11 and book.sofa.n == 2 and book.sofa.best == 0.6 and book.jukebox.n == 1, book and Rules.counts(book :: any).found)
local got = E.received(A, "CollectionBook", mark)
local states = kinds(got, "state")
check("… the state on joining (the book, nothing new)", #states == 1 and Rules.counts(states[1].book).found == 11 and #states[1].new == 0 and #states[1].paid == 0)
local milestones = kinds(got, "milestone")
check("… then its milestones paid at once: found 10 and A legendary! (their messages after the state)", #milestones == 2 and milestones[1].id == "found10" and milestones[2].id == "legendary"
	and milestones[1].money == REWARD.found10 and milestones[2].name == "A legendary!" and got[1].kind == "state")
check("… the money: $250 + $750 as BookMilestone (each its id)", paid(A) == REWARD.found10 + REWARD.legendary and select(2, paid(A, "found10")) == 1 and select(2, paid(A, "legendary")) == 1 and (PlayerData.get(A) :: any).money == 1000 + REWARD.found10 + REWARD.legendary)
check("… marked paid", same(Book.paid(A), { "found10", "legendary" }))
E.flush()
check("… nothing more on the next frame", #kinds(E.received(A, "CollectionBook", mark), "milestone") == 2)

-- ── A new player ───────────────────────────────────────────────────────────
mark = #E.sent
local B = E.join(202, "Ben")
local bStates = kinds(E.received(B, "CollectionBook", mark), "state")
check("a new player: an empty book, its state on joining, no milestone", same(Book.book(B), {}) and #bStates == 1 and next(bStates[1].book) == nil and #kinds(E.received(B, "CollectionBook", mark), "milestone") == 0)

-- ── add → a discovery → the push ───────────────────────────────────────────
mark = #E.sent
Collection.add(B, { item = "sofa", condition = 0.7 })
check("Collection.add: the book has it at once (a discovery)", same(Book.book(B), { sofa = { n = 1, best = 0.7 } }))
check("… the push waits for the frame's end", #E.received(B, "CollectionBook", mark) == 0)
E.flush()
bStates = kinds(E.received(B, "CollectionBook", mark), "state")
check("… then one state with it as new", #bStates == 1 and same(bStates[1].new, { "sofa" }) and same(bStates[1].book, { sofa = { n = 1, best = 0.7 } }))
check("… what a remote carries", (pcall(E.stored, bStates[1], "state")))
mark = #E.sent
Collection.add(B, { item = "sofa", condition = 0.95 })
Collection.add(B, { item = "sofa", condition = 0.2 })
E.flush()
bStates = kinds(E.received(B, "CollectionBook", mark), "state")
check("two more sofas: one state, nothing new, n 3, the best 0.95", #bStates == 1 and #bStates[1].new == 0 and same(bStates[1].book.sofa, { n = 3, best = 0.95 }))
check("CollectionBook.record: a second one is not new", Book.record(B, "sofa", 1) == false and Book.record(B, "nope", 1) == false)
E.flush()
-- a van's load: 9 new pieces in one frame (the 10th piece: found 10)
local LOAD = { "tv", "piano", "bed", "fridge", "wardrobe", "toolbox", "bicycle", "dresser", "mirror" }
mark = #E.sent
for _, item in LOAD do
	Collection.add(B, { item = item, condition = 0.8 })
end
Collection.add(B, { item = "tv", condition = 0.9 })
E.flush()
got = E.received(B, "CollectionBook", mark)
bStates = kinds(got, "state")
check("a van's load (10 pieces, 9 new): one state, its new pieces in the order they came", #bStates == 1 and same(bStates[1].new, LOAD) and Rules.counts(bStates[1].book).found == 10)
milestones = kinds(got, "milestone")
check("… found 10: paid once, its message after the state", #milestones == 1 and milestones[1].id == "found10" and milestones[1].name == "Found 10 pieces" and milestones[1].money == REWARD.found10 and got[1].kind == "state")
check("… $250 as BookMilestone (found10)", paid(B) == REWARD.found10 and select(2, paid(B, "found10")) == 1)
mark = #E.sent
for _, item in { "nightstand", "plant", "guitar", "desk", "toy_box", "kids_bed", "rocking_horse", "radio", "microwave" } do
	Collection.add(B, { item = item, condition = 0.6 })
end
E.flush()
check("19 found: no new milestone", #kinds(E.received(B, "CollectionBook", mark), "milestone") == 0 and paid(B) == REWARD.found10)
Collection.add(B, { item = "stag_head", condition = 0.6 })
Collection.add(B, { item = "accordion", condition = 0.6 })
E.flush()
check("20 found: found 20 paid once ($500)", select(2, paid(B, "found20")) == 1 and paid(B) == REWARD.found10 + REWARD.found20)
for _ = 1, 3 do
	Collection.add(B, { item = "box", condition = 1 })
	E.flush()
end
check("… more pieces: nothing paid again", paid(B) == REWARD.found10 + REWARD.found20 and select(2, paid(B, "found10")) == 1)

-- what is not written
local before = Book.book(B)
mark = #E.sent
Collection.add(B, { item = "hay_wagon", condition = 1 }) -- (a farm piece: an admin's FILL STOCK may bring one)
E.flush()
check("a piece not in the book (a farm piece): the book unchanged, no push", same(Book.book(B), before) and #E.received(B, "CollectionBook", mark) == 0)
local cap = Config.Collection.MaxStock
Config.Collection.MaxStock = #Collection.stock(B)
local refused = Collection.add(B, { item = "jukebox", condition = 1 })
Config.Collection.MaxStock = cap
E.flush()
check("a refused add (the stock full): not in the book", refused == nil and Book.book(B).jukebox == nil)
local sofaUid = Collection.stock(B)[1].uid
local sofas = Book.book(B).sofa.n
check("a piece sold: it stays in the book (as it was)", Collection.sell(B, sofaUid) ~= nil and Book.book(B).sofa ~= nil and Book.book(B).sofa.n == sofas)
local stranger = E.player(303) -- here, but their save never loaded
check("a player not loaded: nothing recorded, the admin waits", Book.record(stranger, "sofa", 1) == false and Book.book(stranger) == nil and Book.admin(stranger, "fill") == "Still loading..." and #Book.paid(stranger) == 0)

-- ── The remote ─────────────────────────────────────────────────────────────
E.advance(2)
mark = #E.sent
E.fire(B, "CollectionBook", { kind = "state" })
local asked = kinds(E.received(B, "CollectionBook", mark), "state")
check("state on request: sent at once (nothing new in it)", #asked == 1 and #asked[1].new == 0 and same(asked[1].book, Book.book(B)) and same(asked[1].paid, { "found10", "found20" }))
local bookBefore, moneyBefore = Book.book(B), (PlayerData.get(B) :: any).money
mark = #E.sent
for _, message in { nil, "x", 5, true, {}, { kind = 7 }, { kind = "fill" }, { kind = "milestone", id = "collectibles" }, { kind = "record", item = "jukebox" }, { kind = "state", book = { jukebox = { n = 1, best = 1 } } } } do
	E.advance(1)
	E.fire(B, "CollectionBook", message)
end
check("garbage on the remote: no error, the book and the money unchanged (a client never fills its book)", same(Book.book(B), bookBefore) and (PlayerData.get(B) :: any).money == moneyBefore and #kinds(E.received(B, "CollectionBook", mark), "milestone") == 0)
check("… only the state asked for answered (once)", #kinds(E.received(B, "CollectionBook", mark), "state") == 1)
E.advance(2)
mark = #E.sent
for _ = 1, 20 do
	E.fire(B, "CollectionBook", { kind = "state" })
end
local limit = Config.Robust.Limits.CollectionBook
check(`the rate limit: {limit} of 20 at once answered`, #kinds(E.received(B, "CollectionBook", mark), "state") == limit, #kinds(E.received(B, "CollectionBook", mark), "state"))

-- ── The save ───────────────────────────────────────────────────────────────
local kept = Book.book(B)
PlayerData.save(B)
local saved = E.saves.Player_202
check("the save: the book (as the view), its paid milestones and the flag", saved.collectionBookKept == true and same(saved.collectionBook, kept) and same(saved.collectionBookPaid, { found10 = true, found20 = true }))
local paidBefore = paid(B)
E.leave(B)
mark = #E.sent
local B2 = E.join(202, "Ben")
check("rejoining: the same book, the same paid milestones", same(Book.book(B2), kept) and same(Book.paid(B2), { "found10", "found20" }))
check("… nothing paid again", paid(B2) == 0 and #kinds(E.received(B2, "CollectionBook", mark), "milestone") == 0 and paidBefore == REWARD.found10 + REWARD.found20)
E.leave(A)
local A2 = E.join(101, "Ann")
check("the older save rejoining: its book from the save now (not filled again), nothing paid again", Rules.counts(Book.book(A2) :: any).found == 11 and same(Book.paid(A2), { "found10", "legendary" }) and paid(A2) == 0)
local bookA2 = Book.book(A2)
E.leave(A2)
local A3 = E.join(101, "Ann")
check("… and again (running twice): the same", bookA2 ~= nil and same(Book.book(A3), bookA2) and Rules.counts(Book.book(A3) :: any).found == 11 and paid(A3) == 0)

-- ── The admin's FILL BOOK / CLEAR BOOK ─────────────────────────────────────
mark = #E.sent
local said = Book.admin(B2, "fill")
E.flush()
got = E.received(B2, "CollectionBook", mark)
local filled = kinds(got, "state")
check("FILL BOOK: every piece found (its answer says so)", Rules.counts(Book.book(B2) :: any).found == #Rules.Pieces and string.find(said, "full", 1, true) ~= nil, said)
check("… one state, the pieces it added as new", #filled == 1 and #filled[1].new == #Rules.Pieces - Rules.counts(kept :: any).found)
local ids = {}
for _, m in kinds(got, "milestone") do
	table.insert(ids, m.id)
end
check("… the milestones it reached pay (all the furniture, every collectible, a legendary)", table.concat(ids, ",") == "furniture,collectibles,legendary" and select(2, paid(B2, "collectibles")) == 1, table.concat(ids, ","))
mark = #E.sent
said = Book.admin(B2, "clear")
E.flush()
local cleared = kinds(E.received(B2, "CollectionBook", mark), "state")
check("CLEAR BOOK: the book and its milestones empty, the state says so", same(Book.book(B2), {}) and #Book.paid(B2) == 0 and #cleared == 1 and next(cleared[1].book) == nil and #cleared[1].paid == 0 and string.find(said, "empty", 1, true) ~= nil)
check("… an unknown admin command changes nothing", string.find(Book.admin(B2, "explode"), "no book command", 1, true) ~= nil and same(Book.book(B2), {}))
Collection.add(B2, { item = "jukebox", condition = 0.5 })
E.flush()
check("… the next piece is a discovery again", same(Book.book(B2), { jukebox = { n = 1, best = 0.5 } }))

check("no warnings (no failed save)", #E.warnings == 0, E.warnings[1])

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
