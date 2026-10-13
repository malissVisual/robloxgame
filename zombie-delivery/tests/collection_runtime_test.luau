-- 8.0 SANDBOX, the collection on the server: the real server/Collection.luau and server/PlayerData.luau
-- (CollectionServer.luau, PlayerDataServer.luau through tests/run_tests.py) on tests/runtime/CollectionRuntime.luau's
-- players, DataStore, clock and Net. Joining (an old save gets the empty collection, the state goes out, the listeners
-- hear), add (uids, the entry's shape, mended input, refusals: garbage, no save, the stock full with one notice), the
-- state pushed once a frame, the analytics, display / undisplay (one piece a stand, the stand's range, only your own
-- pieces, moving one), the income over 60 s and 10 minutes paid in whole dollars every 10 s and exact to the cent
-- (a piece put up between two payouts, manual payouts at odd times), sell (the price, its reason, the sold message,
-- one on show, scrap), the remote (every kind, garbage, the rate limit, the client never names a price), openPicker,
-- Config.Warehouse's stands, leaving (the income counted is paid), the save round trip (the flag, rejoining twice
-- gives the same, the uids go on) and the migration (an old save twice, a new player, a garbled save cleaned).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local E = require("./CollectionRuntime")
local Config = require("./Config")
local Rules = require("./CollectionRules")
local PlayerData = require("./PlayerDataServer")
local Collection = require("./CollectionServer")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
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
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end

-- What the hooks saw: every money change (PlayerData.onMoney), every analytics event, every listener call.
type Money = { player: any, delta: number, reason: string?, sku: string? }
local money: { Money } = {}
PlayerData.onMoney = function(player: Player, delta: number, reason: string?, sku: string?)
	table.insert(money, { player = player, delta = delta, reason = reason, sku = sku })
end
local events: { { player: any, name: string, value: any, a: any } } = {}
PlayerData.analytics.event = function(player: any, name: any, value: any, a: any)
	table.insert(events, { player = player, name = name, value = value, a = a })
end
local heard: { any } = {}
Collection.onChanged(function(player: Player)
	table.insert(heard, player)
end)

local function paid(player: any, reason: string): (number, number)
	local sum, n = 0, 0
	for _, m in money do
		if m.player == player and m.reason == reason then
			sum += m.delta
			n += 1
		end
	end
	return sum, n
end
local function count(list: { any }, value: any, from: number?): number
	local n = 0
	for index = (from or 0) + 1, #list do
		if list[index] == value then
			n += 1
		end
	end
	return n
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
local function eventsNamed(name: string, from: number?): { any }
	local out = {}
	for index = (from or 0) + 1, #events do
		if events[index].name == name then
			table.insert(out, events[index])
		end
	end
	return out
end
local function stockOf(player: any): { [string]: any }
	local out = {}
	for _, entry in Collection.stock(player) do
		out[entry.uid] = entry
	end
	return out
end

-- A 7.x save (every flag of its day, no collection): an old courier.
local function oldSave(cash: number): any
	return {
		money = cash, xp = 0, deliveries = 3, tutorial = true, phone = true, starterKit = true, vestKit = true,
		noPacks = true, noJacket = true, noShoes = true, perGameBags = true, vanOnly = true, carStages = true,
		vanStages = true, xpCurve = Config.Levels.Curve, cars = { [Config.CompanyVan.Car] = true }, car = Config.CompanyVan.Car,
	}
end

PlayerData.start()
Collection.start()
local T = Config.Collection.Tick

-- ── Joining ────────────────────────────────────────────────────────────────
E.saves.Player_101 = oldSave(5000)
local mark = #E.sent
local A = E.join(101, "Ann")
local profileA = PlayerData.get(A) :: any
check("an old save (no collection) loads: its money kept, the empty collection", profileA ~= nil and profileA.money == 5000 and same(profileA.collection, Rules.empty()), profileA and profileA.money)
local states = kinds(E.received(A, "Collection", mark), "state")
check("joining: the state goes out (no stock, $0 a minute, 12 stands)", #states == 1 and #states[1].stock == 0 and states[1].income == 0 and states[1].stands == 12)
check("joining: the listeners hear of it", count(heard, A) == 1)
local B = E.join(202, "Ben") -- a new player: no save at all
check("a new player: the empty collection", same((PlayerData.get(B) :: any).collection, Rules.empty()))

-- ── add ────────────────────────────────────────────────────────────────────
mark = #E.sent
local heardAt, eventsAt = #heard, #events
local u1 = Collection.add(A, { item = "piano", condition = 1, variant = 2 })
local u2 = Collection.add(A, { item = "sofa", condition = 0.9 })
local u3 = Collection.add(A, { item = "dining_chair", condition = 1, name = "Grandma's Chair" })
local u4 = Collection.add(A, { item = "tv", condition = 0.1 })
local u5 = Collection.add(A, { item = "grandfather_clock", condition = 0.95 })
check("uids: <UserId>-1 … -5", u1 == "101-1" and u2 == "101-2" and u3 == "101-3" and u4 == "101-4" and u5 == "101-5", `{u1} {u5}`)
local s = stockOf(A)
local piano = s["101-1"]
check("the entry's shape: uid, item, variant, condition, name, no stand, got (os.time)", piano and piano.item == "piano" and piano.variant == 2 and piano.condition == 1 and piano.name == "Upright Piano" and piano.stand == nil and piano.got == E.os.time())
check("a name given is kept, a variant missing is 1", s["101-3"].name == "Grandma's Chair" and s["101-2"].variant == 1)
check("the listeners hear every add at once", count(heard, A, heardAt) == 5)
check("the state waits for the frame's end", #E.received(A, "Collection", mark) == 0)
E.flush()
states = kinds(E.received(A, "Collection", mark), "state")
local five = states[1]
check("… then goes out once for the five pieces", #states == 1 and #five.stock == 5, #states)
local view = five and five.stock[1]
check("the stock's views: the entry + rarity, value, income, price, broken", view and view.uid == "101-1" and view.rarity == "epic" and view.value == 1200 and view.income == 31.2 and view.price == Rules.sell(piano) and view.broken == false)
check("the broken TV's view", five and five.stock[4].broken == true and five.stock[4].income == 0 and five.stock[4].price == 9)
check("the state is what a remote can carry", (pcall(E.stored, five, "state")))
local added = eventsNamed("CollectionAdded", eventsAt)
check("analytics: one CollectionAdded for the frame (5 pieces, the rarest epic)", #added == 1 and added[1].value == 5 and added[1].a == "epic", #added)

heardAt = #heard
local stranger = E.player(303) -- here, but their save never loaded
local refusals = {
	{ Collection.add(A, nil :: any) },
	{ Collection.add(A, "piano" :: any) },
	{ Collection.add(A, { item = "nope", condition = 1 }) },
	{ Collection.add(A, { item = 5 } :: any) },
	{ Collection.add(stranger, { item = "sofa", condition = 1 }) },
}
local allRefused = true
for _, r in refusals do
	if r[1] ~= nil or type(r[2]) ~= "string" then
		allRefused = false
	end
end
check("refused with a why: no table, an unknown item, no item, no save loaded", allRefused)
check("… nothing added, nobody told", #Collection.stock(A) == 5 and count(heard, A, heardAt) == 0 and #Collection.stock(stranger) == 0)
local b1 = Collection.add(B, { item = "sofa" } :: any)
local b2 = Collection.add(B, { item = "sofa", condition = 0 / 0, variant = 3.9, name = string.rep("x", 80) })
local b3 = Collection.add(B, { item = "sofa", condition = 7 })
local sb = stockOf(B)
check("mended input: no condition 1, NaN 0, over 1 → 1, a variant whole, a long name the def's", sb[b1 :: string].condition == 1 and sb[b2 :: string].condition == 0 and sb[b3 :: string].condition == 1 and sb[b2 :: string].variant == 3 and sb[b2 :: string].name == "Sofa")
check("B's uids are B's", b1 == "202-1" and b3 == "202-3")
local copy = Collection.stock(A)
copy[1].stand = 7
copy[1].condition = 0
check("stock gives copies", Collection.stock(A)[1].stand == nil and Collection.stock(A)[1].condition == 1)

-- ── display / undisplay ───────────────────────────────────────────────────
heardAt, eventsAt = #heard, #events
local ok, why = Collection.display(A, u1 :: string, 1)
check("display: the piano on stand 1", ok and why == nil and stockOf(A)["101-1"].stand == 1)
check("… the listeners hear, CollectionDisplayed (its $ a minute, epic)", count(heard, A, heardAt) == 1 and #eventsNamed("CollectionDisplayed", eventsAt) == 1 and eventsNamed("CollectionDisplayed", eventsAt)[1].value == 31 and eventsNamed("CollectionDisplayed", eventsAt)[1].a == "epic")
ok, why = Collection.display(A, u2 :: string, 1)
check("a stand holds one piece (refused, why)", ok == false and type(why) == "string" and stockOf(A)["101-2"].stand == nil, why)
local badStand = true
for _, stand in { 0, 13, 1.5, -1, "2", nil, 0 / 0, math.huge, {} } do
	local yes = Collection.display(A, u2 :: string, stand :: any)
	if yes then
		badStand = false
	end
end
check("a bad stand (0, 13 of 12, 1.5, -1, a string, nil, NaN, inf, a table): refused", badStand and stockOf(A)["101-2"].stand == nil)
ok, why = Collection.display(A, b1 :: string, 2)
check("another player's piece: refused (not in your stock); theirs untouched", ok == false and why ~= nil and stockOf(B)["202-1"].stand == nil, why)
local badUid = true
for _, uid in { nil, 5, {}, "", string.rep("1", 100), "101-99" } do
	if Collection.display(A, uid :: any, 2) then
		badUid = false
	end
end
check("garbage uids: refused", badUid)
check("refusals change nothing (no listener)", count(heard, A, heardAt) == 1)
check("the clock on stand 2, then moved to 3", Collection.display(A, u5 :: string, 2) and Collection.display(A, u5 :: string, 3) and stockOf(A)["101-5"].stand == 3)
check("… stand 2 free again (the chair goes there, comes down)", Collection.display(A, u3 :: string, 2) and Collection.undisplay(A, u3 :: string) and stockOf(A)["101-3"].stand == nil)
check("displaying it where it is: fine, no change", Collection.display(A, u5 :: string, 3) == true)
ok, why = Collection.undisplay(A, u2 :: string)
check("undisplay a piece not on show: refused", ok == false and why ~= nil)
check("undisplay garbage / another's: refused", not Collection.undisplay(A, "nope") and not Collection.undisplay(A, b1 :: string) and not Collection.undisplay(A, nil :: any))
check("B shows its sofa on its own stand 1", Collection.display(B, b1 :: string, 1))
check("incomePerMinute: the pieces on show (piano $31.20 + clock $22.23)", near(Collection.incomePerMinute(A), 53.43) and near(Collection.incomePerMinute(B), 7.7), Collection.incomePerMinute(A))
check("… nobody else's (a player not loaded: 0)", Collection.incomePerMinute(stranger) == 0)
E.flush()

-- ── The income ─────────────────────────────────────────────────────────────
-- (everything above happened at one moment: the payouts come every T s from it)
local startA, startB = (PlayerData.get(A) :: any).money, (PlayerData.get(B) :: any).money
E.advance(60)
local a60, aTicks = paid(A, "CollectionIncome")
local b60 = paid(B, "CollectionIncome")
check(`60 s: A paid $53 of $53.43 in {60 / T} payouts (the cents wait)`, a60 == 53 and aTicks == 60 / T, `{a60} in {aTicks}`)
check("60 s: B paid $7 of $7.70", b60 == 7, b60)
local whole = true
for _, m in money do
	if m.reason == "CollectionIncome" and (m.delta ~= math.floor(m.delta) or m.delta < 1) then
		whole = false
	end
end
check("every payout whole dollars, its reason CollectionIncome", whole)
check("the money is in the profile", (PlayerData.get(A) :: any).money == startA + 53 and (PlayerData.get(B) :: any).money == startB + 7)
E.advance(540)
check("10 minutes: exact, no drift (A $534 of $534.30, B $77)", paid(A, "CollectionIncome") == 534 and paid(B, "CollectionIncome") == 77, `{paid(A, "CollectionIncome")} {paid(B, "CollectionIncome")}`)
E.advance(T / 2)
check("a piece put up between two payouts", Collection.display(A, u3 :: string, 4)) -- (+ $0.60 a minute from now)
E.advance(T / 2)
check("… counts from that moment ($534.30 + 53.43 × 5/60 + 54.03 × 5/60 = $543.26)", paid(A, "CollectionIncome") == 543, paid(A, "CollectionIncome"))

-- ── sell ───────────────────────────────────────────────────────────────────
mark, heardAt, eventsAt = #E.sent, #heard, #events
local price, whySold = Collection.sell(A, u5 :: string) -- the clock, on show (epic, 0.95)
check("sell a piece on show: the clock for $205", price == 205 and whySold == nil, price)
check("… paid as CollectionSale (its item)", money[#money].reason == "CollectionSale" and money[#money].delta == 205 and money[#money].sku == "grandfather_clock")
check("… its stand free, out of the stock, the income down to $31.80", stockOf(A)["101-5"] == nil and near(Collection.incomePerMinute(A), 31.8))
local sold = kinds(E.received(A, "Collection", mark), "sold")
check("… the sold message (name, money)", #sold == 1 and sold[1].name == "Grandfather Clock" and sold[1].money == 205)
check("… CollectionSold, the listeners", #eventsNamed("CollectionSold", eventsAt) == 1 and eventsNamed("CollectionSold", eventsAt)[1].value == 205 and count(heard, A, heardAt) == 1)
E.advance(3.3)
Collection.tick()
E.advance(1.2)
Collection.tick()
check("payouts at odd times stay exact ($543.26 + 31.80 × 4.5/60 = $545.64)", paid(A, "CollectionIncome") == 545, paid(A, "CollectionIncome"))
E.advance(5.5)
E.advance(60)
check("… and the loop's after them ($545.64 + 31.80 × 65.5/60 = $580.36)", paid(A, "CollectionIncome") == 580, paid(A, "CollectionIncome"))
check("sell from the stock: the sofa (rare, 0.9) for $63", Collection.sell(A, u2 :: string) == 63)
check("sell the broken TV: scrap, $9", Collection.sell(A, u4 :: string) == 9)
local sales = paid(A, "CollectionSale")
local bad1 = Collection.sell(A, u2 :: string)
local bad2 = Collection.sell(A, b1 :: string)
local bad3 = Collection.sell(A, nil :: any)
local bad4 = Collection.sell(stranger, "303-1")
check("sell refused: sold already, another's, garbage, not loaded; no money", bad1 == nil and bad2 == nil and bad3 == nil and bad4 == nil and paid(A, "CollectionSale") == sales and stockOf(B)["202-1"] ~= nil)
check("A keeps the piano (stand 1) and the chair (stand 4)", #Collection.stock(A) == 2 and stockOf(A)["101-1"].stand == 1 and stockOf(A)["101-3"].stand == 4)

-- ── The remote ─────────────────────────────────────────────────────────────
local function ask(player: any, message: any)
	E.advance(1) -- (a second apart: under the rate limit)
	E.fire(player, "Collection", message)
end
local u6 = Collection.add(A, { item = "fridge", condition = 0.8 }) :: string
E.flush()
mark = #E.sent
ask(A, { kind = "state" })
check("state: sent at once", #kinds(E.received(A, "Collection", mark), "state") == 1)
ask(A, { kind = "display", uid = u6, stand = 5 })
check("display through the remote", stockOf(A)[u6].stand == 5)
ask(A, { kind = "undisplay", uid = u6 })
check("undisplay through the remote", stockOf(A)[u6].stand == nil)
mark = #E.sent
local before = (PlayerData.get(A) :: any).money
ask(A, { kind = "sell", uid = u6, money = 1e9, price = 1e9 })
local soldNow = kinds(E.received(A, "Collection", mark), "sold")
check("sell through the remote: the server's price ($80), never the client's", #soldNow == 1 and soldNow[1].money == 80 and (PlayerData.get(A) :: any).money == before + 80, soldNow[1] and soldNow[1].money)
check("… and the state after it", #kinds(E.received(A, "Collection", mark), "state") == 1)
mark = #E.sent
local stockBefore = deepCopy(Collection.stock(A))
local moneyBefore = (PlayerData.get(A) :: any).money - paid(A, "CollectionIncome")
for _, message in { nil, "x", 5, true, {}, { kind = 7 }, { kind = "display" }, { kind = "display", uid = u1 }, { kind = "display", uid = u3, stand = "3" }, { kind = "display", uid = b1, stand = 6 }, { kind = "undisplay", uid = {} }, { kind = "sell" }, { kind = "sell", uid = b1 }, { kind = "explode", uid = u1 } } do
	ask(A, message)
end
local notices = E.received(A, "Notice", mark)
check("garbage on the remote: no error, the stock and the money unchanged", same(Collection.stock(A), stockBefore) and (PlayerData.get(A) :: any).money - paid(A, "CollectionIncome") == moneyBefore and stockOf(B)["202-1"] ~= nil)
check("… each refusal a Notice with its why (7 of them)", #notices == 7 and type(notices[1]) == "string", #notices)
mark = #E.sent
E.advance(1)
for _ = 1, 20 do
	E.fire(A, "Collection", { kind = "state" })
end
local limit = Config.Robust.Limits.Collection
check(`the rate limit: {limit} of 20 at once answered`, #kinds(E.received(A, "Collection", mark), "state") == limit, #kinds(E.received(A, "Collection", mark), "state"))
E.advance(1)
mark = #E.sent
E.fire(A, "Collection", { kind = "state" })
check("… a second later again", #kinds(E.received(A, "Collection", mark), "state") == 1)

-- ── openPicker ─────────────────────────────────────────────────────────────
mark = #E.sent
Collection.openPicker(A, 5)
local got = E.received(A, "Collection", mark)
check("openPicker: the state, then { kind = pick, stand }", #got == 2 and got[1].kind == "state" and got[2].kind == "pick" and got[2].stand == 5)
mark = #E.sent
Collection.openPicker(A, 13)
Collection.openPicker(A, "x" :: any)
Collection.openPicker(A, 0)
Collection.openPicker(stranger, 1)
check("… not for a stand there isn't, nor a player not loaded", #E.received(A, "Collection", mark) == 0 and #E.received(stranger, "Collection", mark) == 0)

-- ── The stock's cap and the warehouse's stands ─────────────────────────────
local cap = Config.Collection.MaxStock
Config.Collection.MaxStock = #Collection.stock(A) + 2
mark = #E.sent
local f1 = Collection.add(A, { item = "box", condition = 1 })
local f2 = Collection.add(A, { item = "box", condition = 1 })
local f3, whyFull = Collection.add(A, { item = "box", condition = 1 })
local f4 = Collection.add(A, { item = "box", condition = 1 })
E.flush()
local full = E.received(A, "Notice", mark)
check("the stock full: add refuses and says why", f1 ~= nil and f2 ~= nil and f3 == nil and f4 == nil and type(whyFull) == "string" and string.find(whyFull :: string, "full") ~= nil, whyFull)
check("… one notice for the frame (2 pieces didn't fit)", #full == 1 and string.find(full[1], "2 pieces") ~= nil, full[1])
Config.Collection.MaxStock = cap
local C2: any = Config
local warehouse = C2.Warehouse
C2.Warehouse = { Stands = 4 }
check("Config.Warehouse.Stands (4): stand 5 refused, the state says 4", not Collection.display(A, f1 :: string, 5) and Collection.display(A, f1 :: string, 2) and (function()
	E.fire(A, "Collection", { kind = "state" })
	local last = kinds(E.received(A, "Collection"), "state")
	return last[#last].stands == 4
end)())
C2.Warehouse = warehouse
Collection.undisplay(A, f1 :: string)

-- ── Leaving pays what was counted ──────────────────────────────────────────
local function nextPayout()
	local at = math.huge
	for _, entry in E.sleeping do
		at = math.min(at, entry.wake)
	end
	E.advance(at - E.clock)
end
nextPayout() -- (a payout just ran: everybody's cents under $1)
local C = E.join(404, "Cid")
local c1 = Collection.add(C, { item = "piano", condition = 1 }) :: string
Collection.display(C, c1, 1)
E.advance(T - 1) -- $31.20 × 9/60 = $4.68 counted, not paid yet
check("before leaving: nothing paid yet", paid(C, "CollectionIncome") == 0)
E.leave(C)
check("leaving pays the whole dollars counted ($4)", paid(C, "CollectionIncome") == 4, paid(C, "CollectionIncome"))
check("… before the leave save (it holds the money)", E.saves.Player_404.money == Config.StartMoney + 4, E.saves.Player_404.money)

-- ── The save ───────────────────────────────────────────────────────────────
local saved = E.saves.Player_404
check("the leave save: the collection and its flag", saved.collectionKept == true and #saved.collection.entries == 1 and saved.collection.entries[1].uid == "404-1" and saved.collection.entries[1].stand == 1 and saved.collection.nextUid == 2)
local C2nd = E.join(404, "Cid")
check("rejoining: the same collection", same((PlayerData.get(C2nd) :: any).collection, saved.collection))
check("… its uids go on (404-2)", Collection.add(C2nd, { item = "sofa", condition = 1 }) == "404-2")
check("… the piano still earns ($31.20)", near(Collection.incomePerMinute(C2nd), 31.2))

local kept = deepCopy((PlayerData.get(A) :: any).collection)
PlayerData.save(A)
check("A's save: written with the flag, the collection as it is", E.saves.Player_101.collectionKept == true and same(E.saves.Player_101.collection, kept))
E.leave(A)
local A2 = E.join(101, "Ann")
check("A rejoins: the same collection (pieces, stands, conditions, nextUid)", same((PlayerData.get(A2) :: any).collection, kept))
local stateA2 = kinds(E.received(A2, "Collection"), "state")
check("… the state on joining shows it", #stateA2 == 1 and #stateA2[1].stock == #kept.entries and near(stateA2[1].income, Collection.incomePerMinute(A2), 0.01))
E.leave(A2)
local A3 = E.join(101, "Ann")
check("… and again (running twice): the same", same((PlayerData.get(A3) :: any).collection, kept))
check("… a new piece gets the next uid", Collection.add(A3, { item = "box", condition = 1 }) == `101-{kept.nextUid}`)

-- the migration: an old save twice, a new player, a garbled save
E.saves.Player_505 = oldSave(777)
local D = E.join(505, "Dot")
check("an old save: empty, its money kept", same((PlayerData.get(D) :: any).collection, Rules.empty()) and (PlayerData.get(D) :: any).money == 777)
E.leave(D)
check("… saved with the flag and the empty collection", E.saves.Player_505.collectionKept == true and same(E.saves.Player_505.collection, Rules.empty()) and E.saves.Player_505.money == 777)
local D2 = E.join(505, "Dot")
check("… loaded again: still empty", same((PlayerData.get(D2) :: any).collection, Rules.empty()))
local fresh = E.join(606, "Eve")
check("a brand-new player: empty", same((PlayerData.get(fresh) :: any).collection, Rules.empty()))
E.leave(fresh)
check("… saved with the flag", E.saves.Player_606.collectionKept == true and #E.saves.Player_606.collection.entries == 0)
local garbled = oldSave(10)
garbled.collectionKept = true
garbled.collection = {
	entries = {
		{ uid = "707-1", item = "sofa", condition = 2, stand = 1 },
		{ uid = "707-1", item = "tv", condition = 1 },
		{ uid = "707-2", item = "tv", condition = 1, stand = 1 },
		{ uid = "707-9", item = "piano", condition = 1, stand = 40 },
		{ item = "sofa" },
	},
	nextUid = -5,
}
E.saves.Player_707 = garbled
local G = E.join(707, "Gus")
local g = (PlayerData.get(G) :: any).collection
check("a garbled save: cleaned (bad and doubled pieces out, one piece a stand, stands past the warehouse's to the stock)", #g.entries == 3 and g.entries[1].condition == 1 and g.entries[1].stand == 1 and g.entries[2].stand == nil and g.entries[3].stand == nil and g.nextUid == 10)
check("… it earns only what stands on its stands (the sofa, $7.70)", near(Collection.incomePerMinute(G), 7.7))

check("no warnings (no failed save, no failed payout)", #E.warnings == 0, E.warnings[1])

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
