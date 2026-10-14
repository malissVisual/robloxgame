--!strict
-- 8.3 SANDBOX, the HUD's chips on every device (shared/SandboxPad.luau): the D-pad map (← the STOCK list, → the book,
-- ↓ the TASKS panel; ↑ left to Roblox's emote wheel; none of the sandbox's other buttons), each chip's way on a computer
-- (its key), with a gamepad (the D-pad) and on a touch screen (the chip itself), and a server's notice in this device's
-- words (a key in brackets gone on a phone and a gamepad; a chip's name with its key or D-pad where none is given). In
-- the standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]
-- 8.3 keys: the sandbox's actions (SandboxPad.Actions: the gamepad's map, the D-pad left to the chips) and how each is
-- shown on every device (keyFor, pads, button, keyWord, withKey, howTo, say), and the UPGRADES desk's monitor without
-- a key (shared/WarehouseLayout.luau).

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
-- put-down prompt (B), the prompts (X; the stands' SELL: Y; the move's unload: Y), Danny's "Talk to Danny" (L1,
-- client/MoveHelperCard.luau), the grip (R2), the sprint (L3), the camera (the right stick), Roblox's emote wheel (the
-- D-pad's ↑). (tests/run_tests.py checks the modules the sandbox starts read no D-pad button.)
local TAKEN = { "ButtonA", "ButtonB", "ButtonX", "ButtonY", "ButtonL1", "ButtonR2", "ButtonL3", "Thumbstick1", "Thumbstick2", "DPadUp", "ButtonSelect", "ButtonStart" }
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

-- ── 8.3 keys: the sandbox's actions on every device ─────────────────────────
local A = SandboxPad.Actions
-- The gamepad's map (the owner's): X the prompts and out of a seat, Y held for Sell and the van's Take out, R2 the grip,
-- B Put down and closing (held: the guide), L1 Danny's alone, R2 / L2 and the left stick Roblox's driving.
check("the prompts on X (Use, out of a seat), the grip on R2", A.use.pad[1] == "ButtonX" and A.getout.pad[1] == "ButtonX" and A.grip.pad[1] == "ButtonR2" and #A.grip.pad == 1)
check("Y held for Sell and the van's Take out (server/Warehouse.luau's F, server/Moving.luau's Z)", A.sell.pad[1] == "ButtonY" and A.takeout.pad[1] == "ButtonY"
	and A.sell.hold == true and A.takeout.hold == true and A.sell.key == "F" and A.takeout.key == "Z")
check("B for Put down and closing; the guide's hold on B as on G", A.putdown.pad[1] == "ButtonB" and A.close.pad[1] == "ButtonB" and A.guide.pad[1] == "ButtonB"
	and A.guide.key == "G" and A.putdown.key == "G" and A.guide.hold == true)
check("L1 is Danny's alone (\"Talk to Danny\", client/MoveHelperCard.luau)", (function()
	for id, action in A do
		if table.find(action.pad, "ButtonL1") and id ~= "danny" then
			return false
		end
	end
	return A.danny.pad[1] == "ButtonL1"
end)())
check("8.3 R1 is Danny's too: \"Give to Danny\" at a piece (client/MoveHelperCard.luau), nothing else on it", (function()
	for id, action in A do
		if table.find(action.pad, "ButtonR1") and id ~= "dannygive" then
			return false
		end
	end
	return A.dannygive.pad[1] == "ButtonR1" and #A.dannygive.pad == 1
end)())
check("driving: R2 on, L2 back, the left stick steers", table.concat(A.drive.pad, ",") == "ButtonR2,ButtonL2" and A.steer.pad[1] == "Thumbstick1")
check("no button for the horn, the list or the chat", #A.horn.pad == 0 and #A.list.pad == 0 and #A.chat.pad == 0)
local onPad, clashes = {}, {}
for id, action in A do
	for _, pad in action.pad do
		if string.sub(pad, 1, 4) == "DPad" or SandboxPad.chipOf(pad) ~= nil then
			table.insert(clashes, `{id} {pad}`) -- (the D-pad is the chips')
		end
		onPad[pad] = true
	end
end
check("no action on the D-pad (the chips' ← → ↓, Roblox's ↑)", #clashes == 0, table.concat(clashes, ", "))
check("… nor on A (jump), L3 (sprint) or the right stick (the camera)", not onPad.ButtonA and not onPad.ButtonL3 and not onPad.Thumbstick2)
check("the keyboard's keys as the key hints show them", A.use.key == "E" and A.grip.key == "LMB / F" and A.drive.key == "W/S" and A.steer.key == "A/D" and A.horn.key == "H"
	and A.list.key == "O" and A.chat.key == "T")

check("keyFor: the key on a computer, the buttons' names with a gamepad, nothing on a phone",
	SandboxPad.keyFor("use", "keys") == "E" and SandboxPad.keyFor("use", "pad") == "ButtonX" and SandboxPad.keyFor("use", "touch") == nil)
check("… two buttons: \"ButtonR2/ButtonL2\"; none: nil; an unknown action: nil", SandboxPad.keyFor("drive", "pad") == "ButtonR2/ButtonL2" and SandboxPad.keyFor("horn", "pad") == nil
	and SandboxPad.keyFor("horn", "keys") == "H" and SandboxPad.keyFor("nope", "keys") == nil)
check("pads: the buttons (empty for none or an unknown action)", SandboxPad.pads("grip")[1] == "ButtonR2" and #SandboxPad.pads("list") == 0 and #SandboxPad.pads("nope") == 0)
check("a button's word: X, B, Y, R2, L2, L1, the left stick, the D-pad's arrows", SandboxPad.button("ButtonX") == "X" and SandboxPad.button("ButtonB") == "B" and SandboxPad.button("ButtonY") == "Y"
	and SandboxPad.button("ButtonR2") == "R2" and SandboxPad.button("ButtonL2") == "L2" and SandboxPad.button("ButtonL1") == "L1" and SandboxPad.button("Thumbstick1") == "left stick"
	and SandboxPad.button("DPadLeft") == "D-pad ←" and SandboxPad.button("Odd") == "Odd")
check("keyWord: \"E\", \"X\", \"R2/L2\", \"left stick\"; nil on a phone or with no button",
	SandboxPad.keyWord("use", "keys") == "E" and SandboxPad.keyWord("use", "pad") == "X" and SandboxPad.keyWord("drive", "pad") == "R2/L2"
	and SandboxPad.keyWord("steer", "pad") == "left stick" and SandboxPad.keyWord("use", "touch") == nil and SandboxPad.keyWord("list", "pad") == nil)
check("withKey: \"try again (E)\", \"try again (X)\", \"try again\" (a phone taps the prompt)", SandboxPad.withKey("try again", "use", "keys") == "try again (E)"
	and SandboxPad.withKey("try again", "use", "pad") == "try again (X)" and SandboxPad.withKey("try again", "use", "touch") == "try again")
check("… a key no gamepad button does: no bracket with a gamepad", SandboxPad.withKey("LIST", "list", "pad") == "LIST" and SandboxPad.withKey("LIST", "list", "keys") == "LIST (O)")
check("howTo the grip: \"Press LMB / F\", \"Press R2\", \"Tap GRIP\"", SandboxPad.howTo("grip", "keys") == "Press LMB / F" and SandboxPad.howTo("grip", "pad") == "Press R2"
	and SandboxPad.howTo("grip", "touch") == "Tap GRIP")
check("howTo the guide: \"Hold G\", \"Hold B\", \"Tap 💡\"", SandboxPad.howTo("guide", "keys") == "Hold G" and SandboxPad.howTo("guide", "pad") == "Hold B" and SandboxPad.howTo("guide", "touch") == "Tap 💡")
check("… a prompt on a phone: no way to name (the prompt itself is tapped); no button: nil", SandboxPad.howTo("use", "touch") == nil and SandboxPad.howTo("horn", "pad") == nil
	and SandboxPad.howTo("nope", "keys") == nil)
local back = "Load it into the van: walk in or E at the back"
check("say: a prompt's E standing alone in a computer's words stays", SandboxPad.say(back, "use", "keys") == back)
check("… a gamepad's X: \"walk in or X at the back\"", SandboxPad.say(back, "use", "pad") == "Load it into the van: walk in or X at the back", SandboxPad.say(back, "use", "pad"))
check("… a phone's tap: \"walk in or tap at the back\" (as shared/SandboxSteps.luau's)", SandboxPad.say(back, "use", "touch") == "Load it into the van: walk in or tap at the back"
	and SandboxPad.say(back, "use", "touch") == require("./SandboxSteps").text({ id = "load", hint = back, nav = false, info = false }, true))
check("… \"(E to pick up)\" → \"(X to pick up)\", a word's E left alone (\"Everything\", \"FREE\")",
	SandboxPad.say("Carry it out (E to pick up)", "use", "pad") == "Carry it out (X to pick up)" and SandboxPad.say("Everything is FREE", "use", "pad") == "Everything is FREE")
check("… \"hold G\" → \"hold B\" with a gamepad", SandboxPad.say("Guide off · hold G to bring it back", "guide", "pad") == "Guide off · hold B to bring it back")

-- 8.3 keys: the warehouse's 3D signs name no keyboard key (a phone and a gamepad read them too)
local WarehouseLayout = require("./WarehouseLayout")
local keyed = {}
for _, line in WarehouseLayout.terminalLines() do
	if string.find(line.text, "%[%u%]") or string.find(line.text, "%(%u%)") then
		table.insert(keyed, line.text)
	end
end
check("the UPGRADES desk's monitor names no key (\"[E] OPEN\" went)", #keyed == 0 and #WarehouseLayout.terminalLines() == 3, table.concat(keyed, ", "))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(failures .. " CHECK(S) FAILED")
end
