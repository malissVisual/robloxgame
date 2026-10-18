-- 8.3 SANDBOX: every device's way to the HUD's chips, the gamepad in the sandbox's windows and the first-time hints
-- (client/PadGlyph.luau, shared/SandboxPad.luau, client/SandboxHintsUi.luau, shared/SandboxHints.luau with the real
-- client/SandboxHud.luau, client/WarehouseUi.luau, client/CollectionBookUi.luau, client/SandboxTasksUi.luau and
-- client/UpgradeUi.luau), run for real on sandbox_mock.luau's recorder on a computer (1280 × 800) and a phone held
-- sideways (844 × 390):
--   * the chips' key outlines: B, C, J on a computer; with a gamepad the D-pad's glyph (the platform's picture, or an
--     arrow when it gives none), drawn again when the device changes; nothing on a touch screen;
--   * the D-pad: ← the STOCK list, → the book, ↓ the TASKS panel (again: closed); nothing while a window has the
--     gamepad's selection (the D-pad moves it), a GUI took the press, on the start screen, or on ↑ (Roblox's emote wheel);
--   * every window with a gamepad: its selection on its main action, kept inside it (a selection group that stops at its
--     edges), kept on the same button when a new state draws it again, every card of the book selectable (the grid
--     scrolls to it), a maxed upgrade selectable, a warehouse question's selection back on what asked it, B closing;
--   * a server's notice in this device's words (a key in brackets gone on a phone and a gamepad, a chip's key added),
--     the task done's toast;
--   * the first-time hints: the first piece ever in the book, a task done with its reward waiting, FILL BEST worth it;
--     once each, one at a time, never while a grip check, the move's cards, a window or the start screen covers the
--     screen, a hint no longer true left out, one the player found alone (the book opened) not needed, their words for
--     the device; no warnings.
local M = require("./sandbox_mock")
local Config = require("./Config")
local Rules = require("./SandboxTasks")
local SandboxHints = require("./SandboxHints")
local UpgradeRules = require("./UpgradeRules")

local function check(name, condition, detail)
	if not condition then
		error(`FAIL {name}{if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""}`)
	end
	print("ok    " .. name)
end
local function all(root, predicate)
	local out = {}
	local function visit(object)
		if predicate(object) then
			table.insert(out, object)
		end
		for _, child in object:GetChildren() do
			visit(child)
		end
	end
	visit(root)
	return out
end
local function named(root, name)
	return all(root, function(object)
		return object.Name == name
	end)[1]
end
local function press(object)
	object.Activated:Fire()
end
local function key(code, processed)
	M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode[code] }, processed == true)
end
local function stopsAtEdges(frame)
	return frame ~= nil and frame.SelectionGroup == true and frame.SelectionBehaviorUp.Name == "Stop" and frame.SelectionBehaviorDown.Name == "Stop"
		and frame.SelectionBehaviorLeft.Name == "Stop" and frame.SelectionBehaviorRight.Name == "Stop"
end
local function inside(object, root)
	return object ~= nil and root ~= nil and object:IsDescendantOf(root)
end

local camera = M.workspace.CurrentCamera
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	camera.ViewportSize = M.Vector2.new(w, h + 36)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	M.flush()
end
local function gamepad(on)
	M.gamepad = on
	M.inputChanged()
	M.flush()
end

-- ── The states the servers send ─────────────────────────────────────────────
local NOW = 20372 * 86400 + 18 * 3600
local function tasksView(daily)
	local saved = Rules.fresh(42, NOW)
	saved.daily = {}
	for _, spec in daily do
		table.insert(saved.daily, { id = spec[1], target = spec[2], progress = spec[3] or 0, claimed = spec[4] == true })
	end
	saved.weekly = { id = "w_income", target = 4500, progress = 100, claimed = false }
	local view = Rules.view(saved, NOW) :: any
	view.kind = "state"
	return view
end
local TASKS = tasksView({ { "home", 12, 12 }, { "trips", 3, 1 }, { "sell", 250, 120 } })
local function piece(uid, item, stand, income)
	return { uid = uid, item = item, variant = 1, condition = 0.9, name = item, got = 1, stand = stand, rarity = "common", income = income or 1.5, price = 60, broken = false }
end
local STOCK = {
	piece("a1", "grandfather_clock"), piece("a2", "sofa"), piece("a3", "piano"), piece("a4", "armchair", 1),
	piece("a5", "floor_lamp"), piece("a6", "bookshelf"),
}
local function stockState(stock, stands)
	return { kind = "state", stock = stock, income = 1.5, stands = stands or 1 } -- (one stand, taken: no FILL BEST hint until the hints' part)
end
local BOOK = {}
for index, item in require("./CollectionBookRules").Pieces do
	if index <= 30 then
		BOOK[item] = { n = 1, best = 0.8 }
	end
end

-- ── Start: a computer ───────────────────────────────────────────────────────
local SandboxHud = require("./SandboxHud")
local Book = require("./CollectionBookUi")
local Tasks = require("./SandboxTasksUi")
local WarehouseUi = require("./WarehouseUi")
local UpgradeUi = require("./UpgradeUi")
local Hints = require("./SandboxHintsUi")
screen(false, 1280, 764)
SandboxHud.start()
Book.start()
Tasks.start()
UpgradeUi.start()
SandboxHud.setState({ money = 5000 })
M.flush()
local collection, bookRemote, tasksRemote, upgrades = M.remotes.Collection, M.remotes.CollectionBook, M.remotes.SandboxTasks, M.remotes.Upgrades
check("the remotes the windows and the hints listen to", collection ~= nil and bookRemote ~= nil and tasksRemote ~= nil and upgrades ~= nil)
check("SandboxHud started the first-time hints, their toasts are its toasts", Hints.notify == SandboxHud.toast)
collection.OnClientEvent:Fire(stockState(STOCK))
bookRemote.OnClientEvent:Fire({ kind = "state", book = BOOK, paid = {}, new = {} })
tasksRemote.OnClientEvent:Fire(TASKS)
M.flush()
local block = SandboxHud.block()
local stockChip, bookChip = named(block, "StockChip"), named(block, "BookChip")
local tasksChip = named(M.gui:FindFirstChild("SandboxTasksChip"), "TasksChip")
local function keysOf()
	return named(stockChip, "Key"), named(bookChip, "Key"), named(tasksChip, "Key")
end
local stockKey, bookKey, tasksKey = keysOf()
check("a computer: the chips' keys B, C, J (no gamepad glyph)", stockKey.Visible and stockKey.Text == "B" and bookKey.Visible and bookKey.Text == "C" and tasksKey.Visible and tasksKey.Text == "J"
	and stockKey:FindFirstChild("Pad") == nil and tasksKey:FindFirstChild("Pad") == nil)
local widthKeys = stockChip.Size.X.Offset

-- ── A gamepad: the glyphs ───────────────────────────────────────────────────
gamepad(true)
local function glyph(label, pad)
	local image = label:FindFirstChild("Pad")
	return label.Visible and label.Text == "" and image ~= nil and image.ClassName == "ImageLabel" and image.Visible and image.Image == `rbxasset://textures/ui/Controls/{pad}.png`
end
check("a gamepad picked up: the chips show the D-pad's glyphs (←, →, ↓: the platform's pictures)", glyph(stockKey, "DPadLeft") and glyph(bookKey, "DPadRight") and glyph(tasksKey, "DPadDown"))
check("… in the key's outline: the chip as wide as with its key", stockChip.Size.X.Offset == widthKeys)
M.padImages = false
SandboxHud.setState({ money = 5001 })
tasksRemote.OnClientEvent:Fire(TASKS)
M.flush()
check("… no picture for them on this platform: the arrows in the outline", stockKey.Text == "←" and bookKey.Text == "→" and tasksKey.Text == "↓" and not stockKey:FindFirstChild("Pad").Visible)
M.padImages = true
SandboxHud.setState({ money = 5002 })
tasksRemote.OnClientEvent:Fire(TASKS)
M.flush()
check("… the pictures again", glyph(stockKey, "DPadLeft") and glyph(tasksKey, "DPadDown"))

-- ── The D-pad's routes ──────────────────────────────────────────────────────
M.focus = nil
key("DPadLeft")
local whGui = M.gui:FindFirstChild("WarehouseUi") or all(M.gui, function(o) return o.Name == "WarehouseShade" end)[1].Parent
local picker = named(whGui, "Picker")
check("D-pad ←: the STOCK list", WarehouseUi.showing() == "stock" and picker ~= nil)
check("… the gamepad's selection on its first tile's button", M.focus ~= nil and inside(M.focus, picker) and string.sub(M.focus.Parent.Name, 1, 5) == "Tile_", M.focus and M.focus.Name)
check("… kept inside the window (a selection group stopping at its edges)", stopsAtEdges(picker))
key("DPadRight")
check("… the D-pad then moves the selection: the book does not open over it", WarehouseUi.showing() == "stock" and not Book.isOpen())
-- a question: its selection, B back to what asked it
local tile3 = named(named(picker, "Grid"), "Tile_a3")
local sell3 = named(tile3, "Sell")
M.focus = sell3
press(sell3)
local question = named(picker, "Confirm")
check("SELL asks: the selection on the question's SELL, kept inside the question", question ~= nil and M.focus == named(question, "ConfirmSell") and stopsAtEdges(named(question, "ConfirmBox")))
key("ButtonB")
check("… B closes the question (the window stays), the selection back on the tile's SELL", named(picker, "Confirm") == nil and WarehouseUi.isOpen() and M.focus == sell3)
local more = table.clone(STOCK)
table.insert(more, piece("a7", "tv"))
collection.OnClientEvent:Fire(stockState(more))
M.flush()
picker = named(whGui, "Picker")
check("a new state draws it again: the selection stays on the same tile's SELL", M.focus ~= nil and M.focus ~= sell3 and M.focus.Name == "Sell" and M.focus.Parent.Name == "Tile_a3" and inside(M.focus, picker),
	M.focus and `{M.focus.Parent.Name}.{M.focus.Name}`)
M.focus = named(picker, "FillBest")
collection.OnClientEvent:Fire(stockState(STOCK))
M.flush()
picker = named(whGui, "Picker")
check("… the header's button too (⭐ FILL BEST)", M.focus ~= nil and M.focus.Name == "FillBest" and inside(M.focus, picker))
key("ButtonB")
check("B closes the STOCK list, the selection let go", not WarehouseUi.isOpen() and M.focus == nil)

key("DPadRight")
local bookGui = M.gui:FindFirstChild("CollectionBookUi")
local bookFrame = bookGui and named(bookGui, "Book")
check("D-pad →: the book, the selection on its lit tab", Book.isOpen() and bookFrame ~= nil and M.focus == named(bookFrame, "Tab_all"))
check("… kept inside the book", stopsAtEdges(bookFrame))
local cards = all(named(bookFrame, "Grid"), function(o) return string.sub(o.Name, 1, 5) == "Card_" end)
local selectable = #cards > 0
for _, card in cards do
	selectable = selectable and card.Selectable == true
end
check(`… every card selectable ({#cards}: the D-pad walks the grid, the grid scrolls to it)`, selectable and #cards == #require("./CollectionBookRules").Pieces)
local deep = cards[#cards]
M.focus = deep
local moreBook = table.clone(BOOK)
moreBook.jukebox = { n = 1, best = 0.9 }
bookRemote.OnClientEvent:Fire({ kind = "state", book = moreBook, paid = {}, new = { "jukebox" } })
M.flush()
bookFrame = named(bookGui, "Book")
check("a new piece draws it again: the selection stays on the same card", M.focus ~= nil and M.focus ~= deep and M.focus.Name == deep.Name and inside(M.focus, bookFrame), M.focus and M.focus.Name)
key("DPadRight")
check("… the D-pad moves its selection (the book stays open)", Book.isOpen())
key("ButtonB")
check("B closes the book", not Book.isOpen() and M.focus == nil)

key("DPadDown")
local tasksGui = M.gui:FindFirstChild("SandboxTasksUi")
local panel = tasksGui and named(tasksGui, "Tasks")
check("D-pad ↓: the TASKS panel, the selection on the first CLAIM", Tasks.isOpen() and panel ~= nil and M.focus == named(named(panel, "Task_1"), "Claim"))
check("… kept inside the panel", stopsAtEdges(panel))
M.focus = named(panel, "Close")
tasksRemote.OnClientEvent:Fire(tasksView({ { "home", 12, 12 }, { "trips", 3, 2 }, { "sell", 250, 120 } }))
M.flush()
panel = named(tasksGui, "Tasks")
check("a new state draws it again: the selection stays on ✕", M.focus ~= nil and M.focus.Name == "Close" and inside(M.focus, panel))
M.focus = named(named(panel, "Task_1"), "Claim")
tasksRemote.OnClientEvent:Fire(tasksView({ { "home", 12, 12 }, { "trips", 3, 3 }, { "sell", 250, 120 } }))
M.flush()
panel = named(tasksGui, "Tasks")
check("… on the same row's CLAIM", M.focus ~= nil and M.focus.Name == "Claim" and M.focus.Parent.Name == "Task_1" and inside(M.focus, panel))
key("ButtonB")
check("B closes the panel", not Tasks.isOpen() and M.focus == nil)
key("DPadDown")
key("DPadDown")
check("… (D-pad ↓ with the selection in it: the panel stays; B closes it)", Tasks.isOpen())
key("ButtonB")
M.focus = nil
key("DPadDown", true)
check("a press a GUI took (gameProcessed): nothing", not Tasks.isOpen())
key("DPadUp")
check("D-pad ↑: nothing of ours (Roblox's emote wheel)", not Tasks.isOpen() and not Book.isOpen() and not WarehouseUi.isOpen())
M.hudGui.Enabled = false
M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
SandboxHud.gui():GetPropertyChangedSignal("Enabled"):Fire()
key("DPadLeft")
key("DPadRight")
key("DPadDown")
check("the start screen (the HUD hidden): the D-pad opens nothing", not WarehouseUi.isOpen() and not Book.isOpen() and not Tasks.isOpen())
M.hudGui.Enabled = true
M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
SandboxHud.gui():GetPropertyChangedSignal("Enabled"):Fire()

-- the UPGRADES desk's window
upgrades.OnClientEvent:Fire({ kind = "state", levels = UpgradeRules.full(), money = 54000 })
upgrades.OnClientEvent:Fire({ kind = "open" })
local upGui = all(M.gui, function(o) return o.Name == "UpgradeShade" end)[1]
local upFrame = upGui and named(upGui, "Upgrades")
-- (10.4, the tree: every node and tier a button the selection reaches, the canvas scrolls to it; the details' MAX)
local nodes = all(upFrame, function(o) return string.match(o.Name, "^Node_") ~= nil or string.match(o.Name, "^Tier_%d$") ~= nil end)
local reachable = #nodes > 0 and named(upFrame, "Max") ~= nil and named(upFrame, "Max").Selectable == true
for _, made in nodes do
	reachable = reachable and made.ClassName == "TextButton" and made.Selectable ~= false
end
check("the UPGRADES window: kept inside it, every node of the tree selectable (its canvas scrolls to it), the trunk's top tier selected (every node bought)",
	stopsAtEdges(upFrame) and reachable and M.focus == named(upFrame, "Tier_5"), M.focus and M.focus.Name)
key("ButtonB")
check("… B closes it", not UpgradeUi.isOpen())

-- ── A server's notice in this device's words ────────────────────────────────
local function lastToast()
	return M.toasts[#M.toasts]
end
SandboxHud.notice("🌅 New daily tasks: open 📋 TASKS.")
check("a gamepad: \"open 📋 TASKS (D-pad ↓).\"", lastToast() == "🌅 New daily tasks: open 📋 TASKS (D-pad ↓).", lastToast())
SandboxHud.notice("Your hands are full: put down what you carry first (G).")
check("… a key in brackets goes", lastToast() == "Your hands are full: put down what you carry first.", lastToast())
tasksRemote.OnClientEvent:Fire({ kind = "done", title = "Bring 12 pieces home", money = 270 })
check("… a task done: \"claim $270 in TASKS (D-pad ↓)\"", lastToast() == "✅ Task done: Bring 12 pieces home · claim $270 in TASKS (D-pad ↓)", lastToast())
gamepad(false)
check("the keys again: the chips' letters back", stockKey.Text == "B" and not stockKey:FindFirstChild("Pad").Visible and tasksKey.Text == "J")
SandboxHud.notice("🌅 New daily tasks: open 📋 TASKS.")
check("a computer: \"open 📋 TASKS (J).\"", lastToast() == "🌅 New daily tasks: open 📋 TASKS (J).", lastToast())
SandboxHud.notice("Your hands are full: put down what you carry first (G).")
check("… the key stays", lastToast() == "Your hands are full: put down what you carry first (G).")
SandboxHud.notice(nil)
SandboxHud.notice(5)
check("… junk: no toast", lastToast() == "Your hands are full: put down what you carry first (G).")
screen(true, 844, 354)
SandboxHud.setState({ money = 5003 })
tasksRemote.OnClientEvent:Fire(TASKS)
M.flush()
check("a phone: no key on the chips", not stockKey.Visible and not bookKey.Visible and not tasksKey.Visible)
SandboxHud.notice("🌅 New daily tasks: open 📋 TASKS.")
check("… the notice as it is (the chip is tapped)", lastToast() == "🌅 New daily tasks: open 📋 TASKS.")
SandboxHud.notice("Your hands are full. Put it down (G), then open the side door (E).")
check("… keys in brackets gone", lastToast() == "Your hands are full. Put it down, then open the side door.", lastToast())
tasksRemote.OnClientEvent:Fire({ kind = "done", title = "Bring 12 pieces home", money = 270 })
check("… a task done: \"claim $270 in TASKS\"", lastToast() == "✅ Task done: Bring 12 pieces home · claim $270 in TASKS", lastToast())

-- ── The first-time hints ────────────────────────────────────────────────────
-- (the hints' clock is the recorder's M.now; a step is M.resume(): the loop's look)
screen(false, 1280, 764)
gamepad(true)
local queue = Hints.queue()
local H = Config.SandboxHud.Hints
local function after(seconds)
	M.now += seconds
	M.resume()
	M.flush()
end
-- the tasks hint was offered by the "done"s above: their state says no reward waits any more → left out, not seen
tasksRemote.OnClientEvent:Fire(tasksView({ { "home", 12, 12, true }, { "trips", 3, 1 }, { "sell", 250, 120 } }))
local toastsAt = #M.toasts
after(H.Delay + 1)
check("a task done whose reward was claimed before its hint's turn: no hint, not seen", #M.toasts == toastsAt and not SandboxHints.seen(queue, "tasks") and not SandboxHints.waiting(queue, "tasks"))
check("a book that had pieces: no book hint (a save's book)", not SandboxHints.waiting(queue, "book") and not SandboxHints.seen(queue, "book"))
-- the first piece ever, the book opened alone before the hint's turn: no hint needed
bookRemote.OnClientEvent:Fire({ kind = "state", book = {}, paid = {}, new = {} })
bookRemote.OnClientEvent:Fire({ kind = "state", book = { sofa = { n = 1, best = 0.7 } }, paid = {}, new = { "sofa" } })
check("the first piece ever in the book: its hint waits", SandboxHints.waiting(queue, "book"))
local toastsBook = #M.toasts
after(H.Delay / 3)
check(`… not before Delay ({H.Delay} s)`, #M.toasts == toastsBook)
key("DPadRight")
after(H.Every)
key("ButtonB")
after(H.Gap + H.Delay)
check("… the book opened (D-pad →) before its turn: no hint (found alone), seen for good", #M.toasts == toastsBook and SandboxHints.seen(queue, "book") and not SandboxHints.waiting(queue, "book"))
bookRemote.OnClientEvent:Fire({ kind = "state", book = {}, paid = {}, new = {} })
bookRemote.OnClientEvent:Fire({ kind = "state", book = { chair = { n = 1, best = 0.7 } }, paid = {}, new = { "chair" } })
check("… (the book emptied by the admin and a piece again: no second hint)", not SandboxHints.waiting(queue, "book"))
-- a task done with its reward waiting: what covers the screen
M.focus = nil
tasksRemote.OnClientEvent:Fire({ kind = "done", title = "Bring 3 truckloads home", money = 380 })
tasksRemote.OnClientEvent:Fire(tasksView({ { "home", 12, 12, true }, { "trips", 3, 3 }, { "sell", 250, 120 } }))
check("a task done, its reward waiting: its hint waits", SandboxHints.waiting(queue, "tasks"))
local toastsTasks = #M.toasts
M.gripActive = true
after(H.Delay + 1)
check("… not during a grip check", #M.toasts == toastsTasks and SandboxHints.waiting(queue, "tasks"))
M.gripActive = false
M.moveCard = true
after(1)
check("… nor while the move's result card shows", #M.toasts == toastsTasks)
M.moveCard = false
UpgradeUi.open()
after(1)
check("… nor while a window is open (the UPGRADES desk's)", #M.toasts == toastsTasks and SandboxHints.waiting(queue, "tasks"))
UpgradeUi.close()
M.hudGui.Enabled = false
M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
after(1)
check("… nor on the start screen (the HUD hidden)", #M.toasts == toastsTasks)
M.hudGui.Enabled = true
M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
after(H.Every)
check("… then: \"📋 Claim your reward in TASKS (D-pad ↓)\" (a gamepad)", #M.toasts == toastsTasks + 1 and lastToast() == "📋 Claim your reward in TASKS (D-pad ↓)", lastToast())
check("… seen: never again", SandboxHints.seen(queue, "tasks") and not SandboxHints.waiting(queue, "tasks"))
-- FILL BEST worth it: one at a time, a Gap after the task's
gamepad(false)
local three = {}
for i = 1, 3 do
	table.insert(three, piece(`f{i}`, "chair"))
end
collection.OnClientEvent:Fire(stockState(three, 6))
local seven = table.clone(three)
for i = 4, 7 do
	table.insert(seven, piece(`f{i}`, "chair"))
end
collection.OnClientEvent:Fire(stockState(seven, 6))
check("pieces came home, FILL BEST worth it: its hint waits", SandboxHints.waiting(queue, "fill"))
local toastsFill = #M.toasts
after(H.Delay + 0.5)
check(`… one at a time: not within Gap ({H.Gap} s) of the task's`, #M.toasts == toastsFill)
after(H.Gap)
check("… then: \"⭐ FILL BEST puts your best pieces on show: open 📦 STOCK (B)\" (a computer)", #M.toasts == toastsFill + 1
	and lastToast() == "⭐ FILL BEST puts your best pieces on show: open 📦 STOCK (B)", lastToast())
after(10 * H.Gap)
check("… then nothing more (each once)", #M.toasts == toastsFill + 1 and #queue.waiting == 0)
tasksRemote.OnClientEvent:Fire({ kind = "done", title = "Sell pieces worth $250", money = 200 })
collection.OnClientEvent:Fire(stockState(three, 6))
collection.OnClientEvent:Fire(stockState(seven, 6))
check("… a later task done, more pieces home: no hint again", #queue.waiting == 0)

check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL SANDBOX PAD CHECKS PASSED")
