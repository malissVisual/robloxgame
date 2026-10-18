--!strict
-- 8.3 SANDBOX, the first-time hints (shared/SandboxHints.luau): when each matters (the first piece ever in the book,
-- a task done, FILL BEST worth it), the queue (once each, one at a time Gap s apart, Delay s after, never while the
-- screen is covered, a hint no longer true left out) and the words on each device. 8.9: the 8.5 – 8.7 features' hints
-- (the clipboard out, another player's warehouse with pieces on show, pieces enough on show for a FOR SALE sign, a
-- player's offer): when each matters, once each, their words on each device. In the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local SandboxHints = require("./SandboxHints")
local SandboxPad = require("./SandboxPad")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local H = Config.SandboxHud.Hints
check("Config.SandboxHud.Hints: a delay, a gap longer than a toast, a look's period, the stock for FILL BEST", H.Delay >= 0 and H.Gap > Config.SandboxHud.Toast and H.Every > 0 and H.Every <= 1 and H.FillStock >= 2)

-- ── When each matters ───────────────────────────────────────────────────────
check("the first piece ever: the book had none, now one, new in this state", SandboxHints.firstPiece(0, 1, 1) and SandboxHints.firstPiece(0, 4, 4))
check("… not the book's first state (a save's book, whatever it holds)", not SandboxHints.firstPiece(nil, 5, 0) and not SandboxHints.firstPiece(nil, 0, 0))
check("… not a book that had pieces", not SandboxHints.firstPiece(3, 4, 1))
check("… not a state with nothing new", not SandboxHints.firstPiece(0, 0, 0))
local function piece(uid: number, stand: number?, income: number, broken: boolean?): any
	return { uid = tostring(uid), item = "chair", stand = stand, rarity = "common", income = income, price = 10, broken = broken }
end
local function stockOf(n: number, onShow: number, income: number?): { any }
	local list = {}
	for i = 1, n do
		table.insert(list, piece(i, if i <= onShow then i else nil, income or 1.5))
	end
	return list
end
local F = H.FillStock
check(`FILL BEST worth saying: {F} pieces waiting, a free stand`, SandboxHints.fillWorth(stockOf(F, 0), 4))
check(`… not with {F - 1}`, not SandboxHints.fillWorth(stockOf(F - 1, 0), 4))
check("… not with every stand taken", not SandboxHints.fillWorth(stockOf(F + 3, 3), 3))
check("… the pieces on show do not count as waiting", not SandboxHints.fillWorth(stockOf(F + 1, 2), 12))
check("… nor pieces that earn nothing (broken)", not SandboxHints.fillWorth(stockOf(F, 0, 0), 12))
local broken = stockOf(F, 0)
broken[1].broken = true
check("… nor a broken one", not SandboxHints.fillWorth(broken, 12))
check("junk: no", not SandboxHints.fillWorth("x", 4) and not SandboxHints.fillWorth({ 1, "a", { uid = {} } }, 4) and not SandboxHints.fillWorth(stockOf(F, 0), "x"))

-- ── The queue ───────────────────────────────────────────────────────────────
local q = SandboxHints.new()
check("offered: it waits", SandboxHints.offer(q, "book", 100) and SandboxHints.waiting(q, "book") and not SandboxHints.seen(q, "book"))
check("… once (offered again: no)", not SandboxHints.offer(q, "book", 100.5))
check("… an unknown hint: no", not SandboxHints.offer(q, "nope", 100))
check(`… not before Delay ({H.Delay} s)`, SandboxHints.take(q, 100 + H.Delay / 2, false) == nil)
check("… not while the screen is covered (a grip check, the result card, a window)", SandboxHints.take(q, 100 + H.Delay + 5, true) == nil and SandboxHints.waiting(q, "book"))
check("… then: shown and seen", SandboxHints.take(q, 100 + H.Delay + 6, false) == "book" and SandboxHints.seen(q, "book") and not SandboxHints.waiting(q, "book"))
check("… seen: never offered again", not SandboxHints.offer(q, "book", 300))
local t = 100 + H.Delay + 6
SandboxHints.offer(q, "tasks", t)
SandboxHints.offer(q, "fill", t)
check(`one at a time: the next not within Gap ({H.Gap} s) of the last`, SandboxHints.take(q, t + H.Delay, false) == nil)
check("… then the first offered", SandboxHints.take(q, t + H.Gap, false) == "tasks")
check("… and the other a Gap later", SandboxHints.take(q, t + H.Gap + 1, false) == nil and SandboxHints.take(q, t + 2 * H.Gap, false) == "fill")
check("… then nothing", SandboxHints.take(q, t + 10 * H.Gap, false) == nil)
local q2 = SandboxHints.new()
SandboxHints.offer(q2, "tasks", 0)
SandboxHints.offer(q2, "fill", 0)
local function onlyFill(id: string): boolean
	return id == "fill"
end
check("a hint no longer true (the reward claimed) is left out, the next one shows", SandboxHints.take(q2, 50, false, onlyFill) == "fill" and not SandboxHints.waiting(q2, "tasks"))
check("… and not marked seen (a later time may say it)", not SandboxHints.seen(q2, "tasks") and SandboxHints.offer(q2, "tasks", 60))
SandboxHints.found(q2, "tasks")
check("the player found it alone while it waited (opened TASKS): not shown, seen", not SandboxHints.waiting(q2, "tasks") and SandboxHints.seen(q2, "tasks") and SandboxHints.take(q2, 500, false) == nil)
SandboxHints.found(q2, "book")
check("… found with no hint waiting: nothing marked", not SandboxHints.seen(q2, "book"))
-- 8.3: busy (the guide's soft steps keep quiet meanwhile)
local q3 = SandboxHints.new()
check("8.3 busy: a new queue is quiet", not SandboxHints.busy(q3, 0) and not SandboxHints.busy(q3, 1e6))
SandboxHints.offer(q3, "tasks", 10)
check("… a hint waiting (its Delay too): busy", SandboxHints.busy(q3, 10) and SandboxHints.busy(q3, 10 + H.Delay / 2))
check("… shown: busy for Gap s after", SandboxHints.take(q3, 10 + H.Delay, false) == "tasks" and SandboxHints.busy(q3, 10 + H.Delay + H.Gap / 2))
check("… then quiet again", not SandboxHints.busy(q3, 10 + H.Delay + H.Gap + 0.01))

-- ── The words ───────────────────────────────────────────────────────────────
check("book, a computer: \"📖 New in your book! Press C (📖) to see it\"", SandboxHints.text("book", "keys") == "📖 New in your book! Press C (📖) to see it", SandboxHints.text("book", "keys"))
check("… a gamepad: the D-pad", SandboxHints.text("book", "pad") == "📖 New in your book! Press D-pad → (📖) to see it", SandboxHints.text("book", "pad"))
check("… a phone: the chip", SandboxHints.text("book", "touch") == "📖 New in your book! Tap 📖 BOOK to see it", SandboxHints.text("book", "touch"))
check("tasks: \"📋 Claim your reward in TASKS\" (its key on a computer)", SandboxHints.text("tasks", "touch") == "📋 Claim your reward in TASKS" and SandboxHints.text("tasks", "keys") == "📋 Claim your reward in TASKS (J)"
	and SandboxHints.text("tasks", "pad") == "📋 Claim your reward in TASKS (D-pad ↓)")
check("fill: \"⭐ FILL BEST puts your best pieces on show\" and where", string.find(SandboxHints.text("fill", "touch"), "⭐ FILL BEST puts your best pieces on show", 1, true) == 1
	and SandboxHints.text("fill", "keys") == "⭐ FILL BEST puts your best pieces on show: open 📦 STOCK (B)" and SandboxHints.text("fill", "pad") == "⭐ FILL BEST puts your best pieces on show: open 📦 STOCK (D-pad ←)"
	and SandboxHints.text("fill", "touch") == "⭐ FILL BEST puts your best pieces on show: open 📦 STOCK", SandboxHints.text("fill", "keys"))
-- (8.9: the 8.5 – 8.7 hints say a little more: a toast wraps them in two or three lines, tools/phone-ui/sandboxhints.luau)
local LONGER = { orders = true, visit = true, price = true, deal = true }
for _, id in SandboxHints.Ids do
	local most = if LONGER[id] then 100 else 70
	for _, device in { "keys", "pad", "touch" } do
		local words = SandboxHints.text(id, device)
		check(`{id} on {device}: short enough for a toast (≤ {most} characters), no "(E)"-style key on a phone`, utf8.len(words) ~= nil and (utf8.len(words) :: number) <= most
			and (device ~= "touch" or string.find(words, "%(%u%)") == nil), words)
	end
end

-- ── 8.9: the 8.5 – 8.7 features ─────────────────────────────────────────────
check("8.9: the new hints are ours (orders, visit, price, deal), after the 8.3 ones; 10.4 the lobby's last", table.concat(SandboxHints.Ids, ",") == "book,tasks,fill,orders,visit,price,deal,lobby")
check("10.4 lobby: \"👥 In a lobby you can walk anywhere: only LEAVE takes you out.\" on every device", SandboxHints.text("lobby", "keys") == "👥 In a lobby you can walk anywhere: only LEAVE takes you out."
	and SandboxHints.text("lobby", "pad") == SandboxHints.text("lobby", "keys") and SandboxHints.text("lobby", "touch") == SandboxHints.text("lobby", "keys"))
do
	local q = SandboxHints.new()
	check("10.4 lobby: offered once, shown after Delay, never again", SandboxHints.offer(q, "lobby", 0) and SandboxHints.take(q, H.Delay, false) == "lobby"
		and not SandboxHints.offer(q, "lobby", 100))
	local q2 = SandboxHints.new()
	SandboxHints.offer(q2, "lobby", 0)
	check("…back in the circle (or out of the lobby) before its turn: dropped, not seen", SandboxHints.take(q2, H.Delay, false, function(id: string): boolean
		return id ~= "lobby"
	end) == nil and not SandboxHints.seen(q2, "lobby"))
end
check("8.9 Config: a look at your clipboard and where you stand at most every few seconds; the sign's hint from 3 pieces on show", H.Look > 0 and H.Look <= 3
	and H.PriceShown == 3)
check("8.9: trading between players is on (Config.PlayerTrade.On): the trade's hints may come", SandboxHints.tradeOn() == (Config.PlayerTrade.On == true) and SandboxHints.tradeOn())

-- the words on every device (the clipboard's: SandboxPad's keys for "dannygive", "danny", "stow")
local ORDERS = {
	keys = "📋 Orders mode: E or click a piece to give it to Danny. Click Danny for his orders. (Q) puts it away.", -- (9.0: E too)
	pad = "📋 Orders mode: R1 by a piece gives it to Danny. L1 at Danny for his orders. (B) puts it away.",
	touch = "📋 Orders mode: tap a piece to give it to Danny. Tap Danny for his orders. Tap 📋 to put it away.",
}
for device, want in ORDERS do
	check(`orders on {device}: "{want}"`, SandboxHints.text("orders", device) == want, SandboxHints.text("orders", device))
end
check("… no click on a phone or with a gamepad, no tap on a computer", string.find(string.lower(ORDERS.touch), "click", 1, true) == nil
	and string.find(string.lower(ORDERS.pad), "click", 1, true) == nil and string.find(string.lower(ORDERS.keys), "tap", 1, true) == nil)
check("… the keys Config's and SandboxPad's (Q, R1, L1, B)", Config.MoveHelper.Clipboard.Key == "Q" and SandboxPad.keyWord("dannygive", "pad") == "R1"
	and SandboxPad.keyWord("danny", "pad") == "L1" and SandboxPad.keyWord("stow", "pad") == "B" and SandboxPad.howTo("stow", "touch") == "Tap 📋")
local SAME = {
	visit = "🤝 Like a piece here? Make the owner an offer.",
	price = "🏷 Put a price on a piece and other players can buy it, even while you're away.",
	deal = "Players pay more than the game: a piece they lack is worth more to them.",
}
for id, want in SAME do
	check(`{id}: "{want}" on every device (no key: the prompts show their own)`, SandboxHints.text(id, "keys") == want and SandboxHints.text(id, "pad") == want
		and SandboxHints.text(id, "touch") == want, SandboxHints.text(id, "pad"))
end

-- price: PriceShown pieces on show, none with a sign
local function shownOf(n: number, extra: number?, sale: number?): { any }
	local list = {}
	for i = 1, n do
		table.insert(list, { uid = `s{i}`, item = "chair", stand = i, sale = if i == 1 then sale else nil })
	end
	for i = 1, extra or 0 do
		table.insert(list, { uid = `x{i}`, item = "chair" })
	end
	return list
end
local P = H.PriceShown
check(`price: {P} pieces on show, no sign: worth saying`, SandboxHints.priceWorth(shownOf(P)) and SandboxHints.priceWorth(shownOf(P + 4)))
check(`… not with {P - 1} on show (the stock's pieces do not count)`, not SandboxHints.priceWorth(shownOf(P - 1, 10)))
check("… not with a sign on one already (the player knows it)", not SandboxHints.priceWorth(shownOf(P + 2, 0, 1500)))
check("… a sign of 0 or junk is no sign", SandboxHints.priceWorth(shownOf(P, 0, 0)) and SandboxHints.priceWorth(shownOf(P, 0, 0 / 0)))
check("… junk: no", not SandboxHints.priceWorth(nil) and not SandboxHints.priceWorth("x") and not SandboxHints.priceWorth({ 1, "a", { stand = "2" } }))

-- visit: where you stand (the warehouse of a plot at its level) and the trade prompts on there
local SandboxMap = require("./SandboxMap")
local WarehouseLayout = require("./WarehouseLayout")
local plot2 = SandboxMap.Plots[2]
local hall4 = WarehouseLayout.inside(WarehouseLayout.site(plot2, 4) :: any)
local mid = { x = (hall4.x0 + hall4.x1) / 2, z = (hall4.z0 + hall4.z1) / 2 }
local id, floor = SandboxHints.hallAt(mid.x, mid.z)
check("hallAt: the middle of plot 2's warehouse (level 4 without levelOf): plot 2, its floor", id == 2 and floor ~= nil and floor.x0 == hall4.x0 and floor.z1 == hall4.z1, id)
local backZ = hall4.z0 + 2 -- (at the back wall of the Big Warehouse: a Garage ends long before)
local function garage(plotId: number): number?
	return if plotId == 2 then 1 else nil
end
check("… the level's own building (levelOf: a Garage on plot 2): its back is outside it", SandboxHints.hallAt(mid.x, backZ) == 2 and SandboxHints.hallAt(mid.x, backZ, garage) == nil)
check("… the plot's yard (its van's spot, its board), a road, the house: none", SandboxHints.hallAt(plot2.vanSpot.x, plot2.vanSpot.z) == nil
	and SandboxHints.hallAt(plot2.board.x, plot2.board.z) == nil and SandboxHints.hallAt(0, -60) == nil and SandboxHints.hallAt(SandboxMap.House.door.x, SandboxMap.House.door.z) == nil)
local ME, ANN = 14, 22
local annsPiece = { x = mid.x + 6, z = mid.z, seller = ANN }
local myPiece = { x = mid.x - 6, z = mid.z, seller = ME }
local hall1 = WarehouseLayout.inside(WarehouseLayout.site(SandboxMap.Plots[1], 4) :: any)
local elsewhere = { x = (hall1.x0 + hall1.x1) / 2, z = (hall1.z0 + hall1.z1) / 2, seller = ANN }
check("visiting: in Ann's warehouse with her piece on show (its trade prompt on)", SandboxHints.visiting(mid.x, mid.z, ME, { myPiece, annsPiece }))
check("… not in your own (only your pieces there)", not SandboxHints.visiting(mid.x, mid.z, ME, { myPiece }))
check("… not in a warehouse with nothing on show", not SandboxHints.visiting(mid.x, mid.z, ME, {}))
check("… not for a piece of hers in another warehouse", not SandboxHints.visiting(mid.x, mid.z, ME, { elsewhere }))
check("… not outside, in front of her door", not SandboxHints.visiting(plot2.vanSpot.x, plot2.vanSpot.z, ME, { annsPiece }))
local hallG = WarehouseLayout.inside(WarehouseLayout.site(plot2, 1) :: any)
local inG = { x = (hallG.x0 + hallG.x1) / 2, z = (hallG.z0 + hallG.z1) / 2 }
check("… her Garage (levelOf): in it with her piece there; not for a spot past its back wall (where the Big Warehouse's was)",
	SandboxHints.visiting(inG.x, inG.z, ME, { { x = inG.x + 3, z = inG.z, seller = ANN } }, garage)
	and not SandboxHints.visiting(inG.x, inG.z, ME, { { x = mid.x, z = backZ, seller = ANN } }, garage))

-- deal: a player's offer on the PlayerTrade remote (a visitor's comes on the Visitors remote)
check("deal: a player's offer ({ kind = \"offer\", id, player = true })", SandboxHints.playerOffer({ kind = "offer", id = "t1", name = "Gramophone", price = 1200, player = true }))
check("… not a visitor's (no player), the server's other messages or junk", not SandboxHints.playerOffer({ kind = "offer", id = "o1", price = 340 })
	and not SandboxHints.playerOffer({ kind = "closed", id = "t1", player = true }) and not SandboxHints.playerOffer({ kind = "offer", id = 5, player = true })
	and not SandboxHints.playerOffer("offer") and not SandboxHints.playerOffer(nil))

-- the queue: once each, the clipboard's dropped when put away before its turn (said the next time it comes out)
local q4 = SandboxHints.new()
check("orders: offered (the clipboard out), waits Delay", SandboxHints.offer(q4, "orders", 0) and SandboxHints.take(q4, H.Delay / 2, false) == nil)
local function away(hint: string): boolean
	return hint ~= "orders"
end
check("… put away before its turn: dropped, not seen", SandboxHints.take(q4, H.Delay + 0.1, false, away) == nil and not SandboxHints.seen(q4, "orders")
	and not SandboxHints.waiting(q4, "orders"))
check("… out again: offered again, and said", SandboxHints.offer(q4, "orders", 10) and SandboxHints.take(q4, 10 + H.Delay, false) == "orders" and SandboxHints.seen(q4, "orders"))
check("… then never again (once a session)", not SandboxHints.offer(q4, "orders", 100))
for _, hint in { "visit", "price", "deal" } do
	local q5 = SandboxHints.new()
	check(`{hint}: offered, held back while a window covers the screen (its offer card), said once`, SandboxHints.offer(q5, hint, 0)
		and SandboxHints.take(q5, H.Delay + 1, true) == nil and SandboxHints.waiting(q5, hint) and SandboxHints.take(q5, H.Delay + 2, false) == hint
		and not SandboxHints.offer(q5, hint, 50))
end
local q6 = SandboxHints.new()
SandboxHints.offer(q6, "visit", 0)
SandboxHints.offer(q6, "price", 0)
SandboxHints.offer(q6, "deal", 0)
check("… three at once: one at a time, Gap apart, in their order", SandboxHints.take(q6, H.Delay, false) == "visit" and SandboxHints.take(q6, H.Delay + 1, false) == nil
	and SandboxHints.take(q6, H.Delay + H.Gap, false) == "price" and SandboxHints.take(q6, H.Delay + 2 * H.Gap, false) == "deal")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
