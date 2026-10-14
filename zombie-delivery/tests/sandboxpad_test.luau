--!strict
-- 8.3 SANDBOX, the HUD's chips on every device (shared/SandboxPad.luau): the D-pad map (← the STOCK list, → the book,
-- ↓ the TASKS panel; ↑ left to Roblox's emote wheel; none of the sandbox's other buttons), each chip's way on a computer
-- (its key), with a gamepad (the D-pad) and on a touch screen (the chip itself), and a server's notice in this device's
-- words (a key in brackets gone on a phone and a gamepad; a chip's name with its key or D-pad where none is given). In
-- the standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
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

-- ── The map ─────────────────────────────────────────────────────────────────
check("the chips in the HUD's order: stock, book, tasks", table.concat(SandboxPad.Ids, ",") == "stock,book,tasks")
local stock, book, tasks = SandboxPad.chip("stock"), SandboxPad.chip("book"), SandboxPad.chip("tasks")
check("their keys: B, C, J (the configs')", stock ~= nil and book ~= nil and tasks ~= nil and stock.key == Config.SandboxHud.StockKey and book.key == Config.CollectionBook.Key
	and tasks.key == Config.SandboxTasks.Key and stock.key == "B" and book.key == "C" and tasks.key == "J")
check("their gamepad buttons: the D-pad's ←, →, ↓", stock ~= nil and book ~= nil and tasks ~= nil and stock.pad == "DPadLeft" and book.pad == "DPadRight" and tasks.pad == "DPadDown")
check("… each its own (no two chips on one button)", stock ~= nil and book ~= nil and tasks ~= nil and stock.pad ~= book.pad and book.pad ~= tasks.pad and stock.pad ~= tasks.pad)
-- The sandbox's gamepad buttons taken elsewhere (none of them is the D-pad): jump (A), every window's close and the
-- put-down prompt (B), the prompts (X; the stands' SELL: Y; the move's unload: Y), the grip (R2), the sprint (L3), the
-- camera (the right stick), Roblox's emote wheel (the D-pad's ↑).
local TAKEN = { "ButtonA", "ButtonB", "ButtonX", "ButtonY", "ButtonR2", "ButtonL3", "Thumbstick1", "Thumbstick2", "DPadUp", "ButtonSelect", "ButtonStart" }
local clash = {}
for _, id in SandboxPad.Ids do
	local chip = SandboxPad.chip(id)
	if chip and table.find(TAKEN, chip.pad) then
		table.insert(clash, `{id} {chip.pad}`)
	end
end
check("no chip on a button the sandbox already uses (the D-pad's ↑ stays Roblox's emote wheel)", #clash == 0, table.concat(clash, ", "))
check("the button → its chip", SandboxPad.chipOf("DPadLeft") == "stock" and SandboxPad.chipOf("DPadRight") == "book" and SandboxPad.chipOf("DPadDown") == "tasks")
check("… nothing on the D-pad's ↑ or another button", SandboxPad.chipOf("DPadUp") == nil and SandboxPad.chipOf("ButtonX") == nil and SandboxPad.chipOf("") == nil)
check("an unknown chip: none", SandboxPad.chip("nope") == nil)

-- ── The device ──────────────────────────────────────────────────────────────
check("a keyboard: keys", SandboxPad.device(false, false) == "keys")
check("a touch screen: touch", SandboxPad.device(true, false) == "touch")
check("a gamepad used last: pad (on a computer and on a touch screen)", SandboxPad.device(false, true) == "pad" and SandboxPad.device(true, true) == "pad")

-- ── The words ───────────────────────────────────────────────────────────────
check("the D-pad's words and arrows", SandboxPad.padWord("DPadLeft") == "D-pad ←" and SandboxPad.padWord("DPadRight") == "D-pad →" and SandboxPad.padWord("DPadDown") == "D-pad ↓"
	and SandboxPad.arrow("DPadLeft") == "←" and SandboxPad.arrow("DPadDown") == "↓")
check("… another button's name as it is", SandboxPad.padWord("ButtonY") == "ButtonY" and SandboxPad.arrow("ButtonY") == "ButtonY")
check("what opens a chip: its key, the D-pad, nothing on a touch screen", SandboxPad.keyOf("tasks", "keys") == "J" and SandboxPad.keyOf("tasks", "pad") == "D-pad ↓" and SandboxPad.keyOf("tasks", "touch") == nil)
check("named: \"TASKS (J)\", \"TASKS (D-pad ↓)\", \"TASKS\"", SandboxPad.named("tasks", "keys") == "TASKS (J)" and SandboxPad.named("tasks", "pad") == "TASKS (D-pad ↓)" and SandboxPad.named("tasks", "touch") == "TASKS")
check("… with its icon: \"📖 BOOK (C)\", \"📦 STOCK\"", SandboxPad.named("book", "keys", true) == "📖 BOOK (C)" and SandboxPad.named("stock", "touch", true) == "📦 STOCK")
check("how: \"Press C\", \"Press D-pad →\", \"Tap 📖 BOOK\"", SandboxPad.how("book", "keys") == "Press C" and SandboxPad.how("book", "pad") == "Press D-pad →" and SandboxPad.how("book", "touch") == "Tap 📖 BOOK", SandboxPad.how("book", "touch"))

-- ── A server's notice in this device's words ────────────────────────────────
local daily = "🌅 New daily tasks: open 📋 TASKS."
check("the new dailies on a computer: the key added", SandboxPad.notice(daily, "keys") == "🌅 New daily tasks: open 📋 TASKS (J).", SandboxPad.notice(daily, "keys"))
check("… with a gamepad: the D-pad", SandboxPad.notice(daily, "pad") == "🌅 New daily tasks: open 📋 TASKS (D-pad ↓).", SandboxPad.notice(daily, "pad"))
check("… on a phone: no key (the chip is tapped)", SandboxPad.notice(daily, "touch") == daily)
local hands = "Your hands are full: put down what you carry first (G)."
check("a key in brackets stays on a computer", SandboxPad.notice(hands, "keys") == hands)
check("… goes on a phone", SandboxPad.notice(hands, "touch") == "Your hands are full: put down what you carry first.", SandboxPad.notice(hands, "touch"))
check("… and with a gamepad (the prompts show their button)", SandboxPad.notice(hands, "pad") == "Your hands are full: put down what you carry first.")
local both = "Your hands are full. Put it down (G), then open the side door (E)."
check("two keys: both go on a phone", SandboxPad.notice(both, "touch") == "Your hands are full. Put it down, then open the side door.", SandboxPad.notice(both, "touch"))
check("a bracket of words stays everywhere (\"(E at the back)\")", SandboxPad.notice("Load them first (E at the back).", "touch") == "Load them first (E at the back).")
check("a chip's name with its key already: not twice", SandboxPad.notice("open 📋 TASKS (J)", "keys") == "open 📋 TASKS (J)")
check("… with a gamepad: the key's letter goes, the D-pad comes", SandboxPad.notice("open 📋 TASKS (J)", "pad") == "open 📋 TASKS (D-pad ↓)", SandboxPad.notice("open 📋 TASKS (J)", "pad"))
check("every chip's name, each time it is named", SandboxPad.notice("📖 BOOK and 📦 STOCK, 📖 BOOK", "keys") == "📖 BOOK (C) and 📦 STOCK (B), 📖 BOOK (C)", SandboxPad.notice("📖 BOOK and 📦 STOCK, 📖 BOOK", "keys"))
check("words without a key or a chip: as they are", SandboxPad.notice("Sold Grandpa's Clock · +$420", "pad") == "Sold Grandpa's Clock · +$420" and SandboxPad.notice("", "touch") == "")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
