--!strict
-- 8.3 SANDBOX, the first-time hints (shared/SandboxHints.luau): when each matters (the first piece ever in the book,
-- a task done, FILL BEST worth it), the queue (once each, one at a time Gap s apart, Delay s after, never while the
-- screen is covered, a hint no longer true left out) and the words on each device. In the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local SandboxHints = require("./SandboxHints")

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

-- ── The words ───────────────────────────────────────────────────────────────
check("book, a computer: \"📖 New in your book! Press C (📖) to see it\"", SandboxHints.text("book", "keys") == "📖 New in your book! Press C (📖) to see it", SandboxHints.text("book", "keys"))
check("… a gamepad: the D-pad", SandboxHints.text("book", "pad") == "📖 New in your book! Press D-pad → (📖) to see it", SandboxHints.text("book", "pad"))
check("… a phone: the chip", SandboxHints.text("book", "touch") == "📖 New in your book! Tap 📖 BOOK to see it", SandboxHints.text("book", "touch"))
check("tasks: \"📋 Claim your reward in TASKS\" (its key on a computer)", SandboxHints.text("tasks", "touch") == "📋 Claim your reward in TASKS" and SandboxHints.text("tasks", "keys") == "📋 Claim your reward in TASKS (J)"
	and SandboxHints.text("tasks", "pad") == "📋 Claim your reward in TASKS (D-pad ↓)")
check("fill: \"⭐ FILL BEST puts your best pieces on show\" and where", string.find(SandboxHints.text("fill", "touch"), "⭐ FILL BEST puts your best pieces on show", 1, true) == 1
	and SandboxHints.text("fill", "keys") == "⭐ FILL BEST puts your best pieces on show: open 📦 STOCK (B)" and SandboxHints.text("fill", "pad") == "⭐ FILL BEST puts your best pieces on show: open 📦 STOCK (D-pad ←)"
	and SandboxHints.text("fill", "touch") == "⭐ FILL BEST puts your best pieces on show: open 📦 STOCK", SandboxHints.text("fill", "keys"))
for _, id in SandboxHints.Ids do
	for _, device in { "keys", "pad", "touch" } do
		local words = SandboxHints.text(id, device)
		check(`{id} on {device}: short enough for a toast (≤ 70 characters), no "(E)"-style key on a phone`, utf8.len(words) ~= nil and (utf8.len(words) :: number) <= 70
			and (device ~= "touch" or string.find(words, "%(%u%)") == nil), words)
	end
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
