-- 8.2 SANDBOX: the daily tasks' TASKS chip and panel (client/SandboxTasksUi.luau, with client/CardKit.luau, the real
-- client/SandboxHud.luau beside it and the real shared data: shared/SandboxTasks.luau makes the server's view) run for
-- real on sandbox_mock.luau's recorder, on a phone held sideways (844 × 390: 844 × 354 under Roblox's top bar, the
-- touch layout), a computer (1280 × 800, the chat shut and open) and a big screen (1920 × 1080): the state
-- asked at the start; THE CHIP in its own ScreenGui ("SandboxTasksChip"), just
-- under SandboxHud's money block at its scale (read from the ScreenGui "SandboxHud", following it when it grows),
-- "📋 TASKS 1/3", the key J on a computer, a badge and the green look with a reward waiting, a spacer of its size second
-- in Hud's column (the toasts under it), clear of the touch buttons, the thumbstick, the left column and the move's
-- panel, a finger's size on a phone; THE PANEL on J, on the chip (a key the game took does nothing), the three dailies,
-- the bonus and the weekly with their progress ("3 / 10", "$120 / $250"), bars, rewards and CLAIM on a done one only;
-- CLAIM's request ({ kind = "claim", slot }) once for a double tap; "done" and "claimed" toasts (8.3: their sounds are
-- client/SandboxSounds.luau's, the panel plays none); no redraw
-- for the same state; the countdown; ✕, J, ESC, the gamepad's B, the menu and a tap beside it close it; on each screen
-- the panel on the screen, every row shown whole inside it, the texts fitting, a phone's buttons a finger's size (44
-- px), a computer's panel under the chip, a phone's beside (two columns); a resize while open; garbage states.
-- `luau sandboxtasks.luau -a dump` prints the preview's scenes as JSON instead (sandbox_preview.py --scenes
-- sandboxtasks.luau).
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
local Rules = require("./SandboxTasks")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local CardKit = require("./CardKit")

local function check(name, condition, detail)
	if not condition then
		error(`FAIL {name}{if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""}`)
	end
	if not dump then
		print("ok    " .. name)
	end
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
local function sentOn(remote)
	local list = {}
	for _, entry in M.sent do
		if entry.name == remote then
			table.insert(list, entry.args)
		end
	end
	return list
end
local function press(object)
	object.Activated:Fire()
end
local function key(code, processed)
	M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode[code] }, processed == true)
end
local box, overlap = M.box, TouchLayout.overlap
local function show(b)
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end
local function inside(b)
	return MoveLayout.inside(b, M.width, M.height)
end
local function within(b, outer)
	return b.x0 >= outer.x0 - 0.5 and b.y0 >= outer.y0 - 0.5 and b.x1 <= outer.x1 + 0.5 and b.y1 <= outer.y1 + 0.5
end
local function shown(object)
	local node = object
	while node do
		if node.Visible == false then
			return false
		end
		node = node.Parent
	end
	return true
end
-- Does a one-line text fit its label (after the scales above it)? A title may run long and is cut with "…"; a
-- reward, a count or a button never. The chip's words leave room for its key and badge.
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		local truncated = object.TextTruncate and object.TextTruncate.Name == "AtEnd" and object.Name ~= "Reward" and object.Name ~= "Claim" and object.Name ~= "Progress"
		if not object.TextWrapped and not truncated then
			local b = box(object)
			local room = b.x1 - b.x0
			local need = M.textWidth(object.Text, (object.TextSize or 14) * M.scaleOf(object), object.Font)
			if need > room + 0.5 then
				table.insert(bad, `{object.Name} "{object.Text}" {math.floor(need)} > {math.floor(room)}`)
			end
		end
	end
	return bad
end
-- The buttons a finger taps on a phone: each at least 44 × 44 screen px.
local function smallButtons(root)
	local small = {}
	for _, object in all(root, function(o)
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false and o.Name ~= "TasksShade"
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end

-- ── Screens ─────────────────────────────────────────────────────────────────
local camera = M.workspace.CurrentCamera
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	camera.ViewportSize = M.Vector2.new(w, h + 36)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	M.flush()
end
-- What the chip must keep clear of (tools/phone-ui/sandbox.luau's list): the touch buttons, the thumbstick, the jump,
-- the left column on a phone; the health row and the key hints on a computer; the move's panel.
local function blocks()
	local list = {}
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		for _, b in TouchLayout.buttons(cluster) do
			table.insert(list, b)
		end
		table.insert(list, cluster.thumb)
		table.insert(list, cluster.jump)
		table.insert(list, M.leftColumn)
	else
		table.insert(list, { x0 = 16, y0 = M.height - 16 - 258 * S, x1 = 16 + 200 * S, y1 = M.height - 16 })
		table.insert(list, { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W - 260 * S, y0 = 0, x1 = M.width, y1 = 4 + 90 * S })
	end
	table.insert(list, MoveLayout.panel(M.width, S))
	return list
end

-- ── The preview's scenes (sandbox_preview.py --scenes sandboxtasks.luau) ────
local scenes = {}
local function color(c)
	return if type(c) == "table" and c.R then { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) } else nil
end
local function udim2(u)
	return if type(u) == "table" and type(u.X) == "table" then { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset } else nil
end
local function node(n)
	local p = n._p
	local out = { c = p.ClassName, n = p.Name }
	if p.Visible == false then
		out.vis = false
	end
	out.pos, out.size = udim2(p.Position), udim2(p.Size)
	if p.AnchorPoint then
		out.anchor = { p.AnchorPoint.X, p.AnchorPoint.Y }
	end
	out.z, out.order = p.ZIndex, p.LayoutOrder
	out.bg, out.bgT = color(p.BackgroundColor3), p.BackgroundTransparency
	out.clip = p.ClipsDescendants
	if p.Text and p.Text ~= "" then
		out.text, out.ts = p.Text, p.TextSize
		out.tc, out.tt = color(p.TextColor3), p.TextTransparency
		out.xa = if p.TextXAlignment then p.TextXAlignment.Name else nil
		out.font = if p.Font then p.Font.Name else nil
		out.wrap = p.TextWrapped == true
		out.trunc = p.TextTruncate ~= nil and p.TextTruncate.Name == "AtEnd"
	end
	if p.ClassName == "UICorner" then
		out.radius = { p.CornerRadius.Scale, p.CornerRadius.Offset }
	elseif p.ClassName == "UIStroke" then
		out.color, out.thick, out.tr = color(p.Color), p.Thickness, p.Transparency
	elseif p.ClassName == "UIScale" then
		out.scale = p.Scale
	elseif p.ClassName == "UIPadding" then
		out.pad = { p.PaddingLeft and p.PaddingLeft.Offset or 0, p.PaddingRight and p.PaddingRight.Offset or 0 }
	elseif p.ClassName == "ScreenGui" then
		out.display = p.DisplayOrder or 0
		out.enabled = p.Enabled ~= false
	end
	local kids = {}
	for _, child in n:GetChildren() do
		table.insert(kids, node(child))
	end
	if #kids > 0 then
		out.kids = kids
	end
	return out
end
-- A scene: Hud's column as client/Hud.luau lays it out (the money's spacer, the chip's, the toasts under them).
local function scene(name, toasts)
	if not dump then
		return
	end
	local slot = M.topStack:FindFirstChild("Slot_sandbox")
	local toastSlot = M.topStack:FindFirstChild("Slot_toasts") or M.make("Frame", { Name = "Slot_toasts", Size = M.UDim2.fromOffset(380, 0), BackgroundTransparency = 1 }, M.topStack)
	for _, child in toastSlot:GetChildren() do
		child:Destroy()
	end
	local money = slot and slot:FindFirstChild("SandboxSpace")
	local tasks = slot and slot:FindFirstChild("TasksSpace")
	if money and tasks then
		tasks.Position = M.UDim2.fromOffset(0, money.Size.Y.Offset + 8)
		local y = money.Size.Y.Offset + 8 + tasks.Size.Y.Offset + 8
		slot.Size = M.UDim2.fromOffset(380, y - 8)
		for _, text in toasts or {} do
			local w = M.textWidth(text, 14, M.Enum.Font.GothamMedium) + 28
			local strip = M.make("Frame", { Name = "Toast", Size = M.UDim2.fromOffset(w, 30), Position = M.UDim2.fromOffset(0, y), BackgroundColor3 = M.MTheme.Contract.charcoal, BackgroundTransparency = 0.22 }, toastSlot)
			M.make("Frame", { Name = "Rule", Size = M.UDim2.fromOffset(2, 30), BackgroundColor3 = M.MTheme.Contract.text }, strip)
			M.make("TextLabel", { Name = "Text", Text = text, TextSize = 14, Font = M.Enum.Font.GothamMedium, TextColor3 = M.MTheme.Contract.text, TextXAlignment = M.Enum.TextXAlignment.Left, Size = M.UDim2.new(1, -14, 1, 0), Position = M.UDim2.fromOffset(14, 0), BackgroundTransparency = 1 }, strip)
			y += 38
		end
	end
	local overlay = {}
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
		table.insert(overlay, { kind = "pill", box = cluster.sprint, label = "SPRINT" })
		table.insert(overlay, { kind = "minimap", box = M.leftColumn })
	else
		table.insert(overlay, { kind = "minimap", box = { x0 = 16, y0 = M.height - 16 - 30 * S, x1 = 16 + 200 * S, y1 = M.height - 16 } })
		table.insert(overlay, { kind = "text", box = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W - 150, y0 = 4, x1 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y1 = 30 }, label = "? KEYS [F1]" }) -- (9.0: no MOUSE [ALT] in the sandbox)
		if M.chatOpen then
			table.insert(overlay, { kind = "chat", box = { x0 = 8, y0 = 0, x1 = 400, y1 = 200 }, label = "Roblox chat" })
		end
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── The server's states (shared/SandboxTasks.luau's view of a save) ────────
local NOW = 20372 * 86400 + 18 * 3600 + 47 * 60 + 30 -- (18:47:30 UTC: 5 h 12 min to the dailies' reset)
local function viewOf(daily, weekly, bonus)
	local saved = Rules.fresh(42, NOW)
	saved.daily = {}
	for _, spec in daily do
		table.insert(saved.daily, { id = spec[1], target = spec[2], progress = spec[3] or 0, claimed = spec[4] == true })
	end
	saved.weekly = if weekly then { id = weekly[1], target = weekly[2], progress = weekly[3] or 0, claimed = weekly[4] == true } else nil
	saved.bonus = bonus == true
	local view = Rules.view(saved, NOW) :: any
	view.kind = "state"
	return view
end
local FIRST = viewOf({ { "home", 12, 12 }, { "trips", 3, 1 }, { "sell", 250, 120 } }, { "w_income", 4500, 1830 })

-- ── Off: nothing ────────────────────────────────────────────────────────────
local SandboxHud = require("./SandboxHud")
local SandboxTasksUi = require("./SandboxTasksUi")
screen(true, 844, 354)

-- ── On: the chip under the money ────────────────────────────────────────────
SandboxHud.start()
SandboxHud.setState({ money = 12480 })
M.flush()
SandboxTasksUi.start()
M.flush()
local remote = M.remotes.SandboxTasks
check("on: the SandboxTasks remote asked for the state", remote ~= nil and #sentOn("SandboxTasks") == 1 and sentOn("SandboxTasks")[1][1].kind == "state")
local chipGui = M.gui:FindFirstChild("SandboxTasksChip")
local chip = chipGui and named(chipGui, "TasksChip")
local block = SandboxHud.block()
check("the chip in its own ScreenGui \"SandboxTasksChip\" (SandboxHud's untouched: no child of ours in it)", chip ~= nil and chipGui.ClassName == "ScreenGui"
	and named(SandboxHud.gui(), "TasksChip") == nil and #all(SandboxHud.gui(), function(o) return o.Name == "TasksSpace" end) == 0)
local slot = M.topStack:FindFirstChild("Slot_sandbox")
local spacer = slot and slot:FindFirstChild("TasksSpace")
check("… its spacer second in Hud's left column (after SandboxHud's: the toasts flow under the chip)", spacer ~= nil and spacer.LayoutOrder == 1 and slot:FindFirstChild("SandboxSpace") ~= nil
	and slot:FindFirstChild("SandboxSpace").LayoutOrder == 0)
remote.OnClientEvent:Fire(FIRST)
M.flush()
check("the state: \"📋 TASKS 1/3\" (the dailies done), a badge (1 to claim), green", named(chip, "Label").Text == "📋 TASKS 1/3" and named(chip, "Badge").Visible
	and named(chip, "Badge").Text == "1" and chip.BackgroundColor3 == CardKit.Color.goodFace, named(chip, "Label").Text)
check("… no key on a touch screen", not named(chip, "Key").Visible)

local function chipChecks(label)
	local c, b = box(chip), box(block)
	local blockScale = M.uiScale(block)
	check(`{label}: the chip just under the money block, at its left, at its scale`, math.abs(c.x0 - b.x0) < 1 and c.y0 >= b.y1 - 0.5 and c.y0 - b.y1 <= 12
		and math.abs(M.uiScale(chip) - math.max(blockScale, if M.touch then Config.SandboxHud.TouchScale else 0)) < 0.001, `{show(c)} under {show(b)}`)
	local clear, hit = true, nil
	for _, other in blocks() do
		if overlap(c, other) then
			clear, hit = false, show(other)
		end
	end
	check(`{label}: … on the screen, clear of the touch buttons, the thumbstick, the left column, the HUD's corners and the move's panel`, inside(c) and clear, `{show(c)} on {hit}`)
	check(`{label}: … its words fit`, #badTexts(chip) == 0, badTexts(chip)[1])
	if M.touch then
		check(`{label}: … a finger's size (44 px)`, c.x1 - c.x0 >= 44 - 0.01 and c.y1 - c.y0 >= 44 - 0.01, show(c))
	end
	local unit = M.scaleOf(spacer)
	check(`{label}: … its spacer as big as it is (in the column's px)`, math.abs(spacer.Size.Y.Offset * unit - (c.y1 - c.y0)) <= unit + 0.5
		and math.abs(spacer.Size.X.Offset * unit - (c.x1 - c.x0)) <= unit + 0.5, `{spacer.Size.X.Offset}x{spacer.Size.Y.Offset} @ {unit}`)
end
chipChecks("844 x 390")
SandboxHud.setState({ money = 1234567890 })
M.flush()
M.flush()
check("the money block grows: the chip follows (still under it, at its left)", box(chip).y0 >= box(block).y1 - 0.5 and math.abs(box(chip).x0 - box(block).x0) < 1)
scene("tasks-chip-phone", { "✅ Task done: Bring 12 pieces home · claim $270 in TASKS" })

-- ── The panel on a phone ────────────────────────────────────────────────────
press(chip)
M.flush()
local panelGui = M.gui:FindFirstChild("SandboxTasksUi")
local panel = panelGui and named(panelGui, "Tasks")
check("a tap on the chip: the panel in its ScreenGui \"SandboxTasksUi\" (over the HUD)", SandboxTasksUi.isOpen() and panel ~= nil and panelGui.DisplayOrder > chipGui.DisplayOrder)
check("… modal: its shade frees the mouse; the state asked again", named(panelGui, "TasksShade").Modal == true and sentOn("SandboxTasks")[#sentOn("SandboxTasks")][1].kind == "state")
local function panelChecks(label, columns)
	panel = named(panelGui, "Tasks")
	local p = box(panel)
	check(`{label}: the panel on the screen`, inside(p), show(p))
	local rows = 0
	for _, name in { "Task_1", "Task_2", "Task_3", "Bonus", "Task_weekly" } do
		local made = named(panel, name)
		if made and within(box(made), p) then
			rows += 1
		end
	end
	check(`{label}: … the three dailies, the bonus and the weekly shown whole inside it`, rows == 5, rows)
	check(`{label}: … its texts fit`, #badTexts(panel) == 0, badTexts(panel)[1])
	local plan = SandboxTasksUi.layout(M.width, M.height, M.touch)
	check(`{label}: … {columns} column{if columns == 1 then "" else "s"}`, plan.columns == columns, plan.columns)
	if M.touch then
		check(`{label}: … every button a finger's size (CLAIM, ✕)`, #smallButtons(panel) == 0, smallButtons(panel)[1])
	else
		local c = box(chip)
		check(`{label}: … under the chip, at its left`, p.y0 >= c.y1 and math.abs(p.x0 - c.x0) <= 1, `{show(p)} / {show(c)}`)
	end
end
panelChecks("844 x 390", 2)
local home, trips, sell = named(panel, "Task_1"), named(panel, "Task_2"), named(panel, "Task_3")
check("the dailies: their emoji, titles and progress (\"3 / 10\", money as $)", named(home, "Emoji").Text == "📦" and named(home, "Title").Text == "Bring 12 pieces home"
	and named(home, "Progress").Text == "12 / 12" and named(trips, "Progress").Text == "1 / 3" and named(sell, "Progress").Text == "$120 / $250", named(sell, "Progress").Text)
check("… the bars: full, a third, about half", named(named(home, "Bar"), "Fill").Size.X.Scale == 1 and math.abs(named(named(trips, "Bar"), "Fill").Size.X.Scale - 1 / 3) < 1e-6
	and math.abs(named(named(sell, "Bar"), "Fill").Size.X.Scale - 0.48) < 1e-6)
check("… CLAIM only on the done one (green, its reward); the others their reward in money green", named(home, "Claim") ~= nil and named(home, "Claim").Text == `CLAIM {M.MUi.money(FIRST.daily[1].money)}`
	and named(trips, "Claim") == nil and named(trips, "Reward").Text == M.MUi.money(FIRST.daily[2].money) and named(trips, "Reward").TextColor3 == CardKit.Color.money)
local bonus, weekly = named(panel, "Bonus"), named(panel, "Task_weekly")
check("the bonus: \"⭐ All three done: +$300\" (8.3 economy), \"1 / 3 done\"", named(bonus, "Words").Text == "⭐ All three done: +$300" and named(bonus, "Count").Text == "1 / 3 done")
check("the weekly: gold, its title, \"$1,830 / $4,500\", its reward", named(weekly, "Title").Text == "Earn $4,500 from your stands" and named(weekly, "Progress").Text == "$1,830 / $4,500"
	and named(weekly, "Reward").TextColor3 == CardKit.Color.gold and named(named(weekly, "Bar"), "Fill").BackgroundColor3 == CardKit.Color.gold)
check("the countdowns: \"New tasks in 5 h 12 min\", \"THIS WEEK · NEW IN 1 D 5 H\"", named(panel, "Subtitle").Text == "New tasks in 5 h 12 min" and named(panel, "WeekLabel").Text == "THIS WEEK · NEW IN 1 D 5 H", named(panel, "WeekLabel").Text)
check("the gamepad lands on the first CLAIM", M.focus == named(home, "Claim"))
scene("tasks-phone")

-- CLAIM
local before = #sentOn("SandboxTasks")
press(named(home, "Claim"))
press(named(home, "Claim"))
local sent = sentOn("SandboxTasks")
check("CLAIM sends { kind = \"claim\", slot = 1 } once for a double tap; the button waits (…)", #sent == before + 1 and sent[#sent][1].kind == "claim" and sent[#sent][1].slot == 1
	and named(home, "Claim").Text == "…")
local same = named(panelGui, "Tasks")
remote.OnClientEvent:Fire(FIRST)
M.flush()
check("the same state again: no redraw (a tap is never lost)", named(panelGui, "Tasks") == same)
local toastsAt = #M.toasts
local playedAt = #M.played
remote.OnClientEvent:Fire({ kind = "claimed", title = "Bring 12 pieces home", money = 270 })
check("\"claimed\": a toast (8.3: its sound is SandboxSounds', the panel plays none)", M.toasts[#M.toasts] == "💰 Bring 12 pieces home: +$270" and #M.played == playedAt and #M.toasts == toastsAt + 1, M.toasts[#M.toasts])
local CLAIMED = viewOf({ { "home", 12, 12, true }, { "trips", 3, 3 }, { "sell", 250, 250 } }, { "w_income", 4500, 4500 })
remote.OnClientEvent:Fire(CLAIMED)
M.flush()
panel = named(panelGui, "Tasks")
home, trips = named(panel, "Task_1"), named(panel, "Task_2")
check("the new state: drawn again (✓ CLAIMED, two CLAIMs, the bonus's CLAIM, the weekly's gold CLAIM)", named(home, "Claimed") ~= nil and named(home, "Claim") == nil
	and named(trips, "Claim") ~= nil and named(named(panel, "Bonus"), "Claim") ~= nil and named(named(panel, "Task_weekly"), "Claim").BackgroundColor3 == CardKit.Color.gold)
check("… the chip: 3/3, four to claim (two dailies, the bonus, the weekly)", named(chip, "Label").Text == "📋 TASKS 3/3" and named(chip, "Badge").Text == "4")
panelChecks("844 x 390, everything done", 2)
scene("tasks-phone-done")
before = #sentOn("SandboxTasks")
press(named(named(panel, "Bonus"), "Claim"))
sent = sentOn("SandboxTasks")
check("the bonus's CLAIM sends slot \"bonus\"", #sent == before + 1 and sent[#sent][1].slot == "bonus")
press(named(named(panel, "Task_weekly"), "Claim"))
sent = sentOn("SandboxTasks")
check("the weekly's CLAIM sends slot \"weekly\"", sent[#sent][1].slot == "weekly")
remote.OnClientEvent:Fire({ kind = "done", title = "Bring 3 truckloads home", money = 380, weekly = false })
check("\"done\": a toast (claim it in TASKS; 8.3: its sound is SandboxSounds')", M.toasts[#M.toasts] == "✅ Task done: Bring 3 truckloads home · claim $380 in TASKS" and #M.played == playedAt, M.toasts[#M.toasts])
remote.OnClientEvent:Fire({ kind = "done", title = "Earn $4,500 from your stands", money = 2630, weekly = true })
check("… a weekly one says so", string.find(M.toasts[#M.toasts], "Weekly task done", 1, true) ~= nil)

-- closing
press(named(named(panelGui, "Tasks"), "Close"))
check("✕ closes it", not SandboxTasksUi.isOpen() and named(panelGui, "Tasks") == nil)
press(chip)
press(named(panelGui, "TasksShade"))
check("a tap beside it closes it", not SandboxTasksUi.isOpen())
press(chip)
press(chip)
check("the chip again closes it", not SandboxTasksUi.isOpen())
SandboxTasksUi.open()
M.services.GuiService.MenuOpened:Fire()
check("the Roblox menu closes it", not SandboxTasksUi.isOpen())

-- ── A computer (1280 × 800: the chat shut, open) and a big screen ──────────
remote.OnClientEvent:Fire(FIRST)
for _, size in { { 1280, 764, "computer" }, { 1280, 764, "chat" }, { 1920, 1044, "big" } } do
	M.chatOpen = size[3] == "chat"
	screen(false, size[1], size[2])
	M.flush()
	local label = `{size[1]} x {size[2] + 36}{if M.chatOpen then " (the chat open)" else ""}`
	chipChecks(label)
	check(`{label}: the key J on the chip`, named(chip, "Key").Visible and named(chip, "Key").Text == "J")
	key("J", true)
	check(`{label}: J the game took (typing, another use) does nothing`, not SandboxTasksUi.isOpen())
	key("J")
	M.flush()
	check(`{label}: J opens the panel`, SandboxTasksUi.isOpen())
	panelChecks(label, 1)
	scene(`tasks-{size[3]}`)
	key("J")
	check(`{label}: J again closes it`, not SandboxTasksUi.isOpen())
end
M.chatOpen = false
-- the longest titles on a computer: whole beside their reward and beside CLAIM
remote.OnClientEvent:Fire(viewOf({ { "rare", 4, 2 }, { "clean", 1, 1 }, { "shown", 8, 8, true } }, { "w_clean", 4, 1 }))
screen(false, 1280, 764)
SandboxTasksUi.open()
M.flush()
panelChecks("1280 x 800, the longest titles", 1)
local whole, cut = true, nil
for _, name in { "Task_1", "Task_2", "Task_3", "Task_weekly" } do
	local title = named(named(named(panelGui, "Tasks"), name), "Title")
	local b = box(title)
	local need = M.textWidth(title.Text, title.TextSize * M.scaleOf(title), title.Font)
	if need > b.x1 - b.x0 + 0.5 then
		whole = false
		cut = `{title.Text}: {math.floor(need)} > {math.floor(b.x1 - b.x0)}`
	end
end
check("… \"Bring home 4 rare or better pieces\", \"Finish a move with nothing broken\" (CLAIM beside it), the weekly's: never cut", whole, cut)
scene("tasks-computer-long")
SandboxTasksUi.close()
remote.OnClientEvent:Fire(FIRST)
SandboxTasksUi.open()
key("Escape")
check("ESC closes it", not SandboxTasksUi.isOpen())
SandboxTasksUi.open()
key("ButtonB")
check("the gamepad's B closes it", not SandboxTasksUi.isOpen())

-- ── A resize while it is open ───────────────────────────────────────────────
SandboxTasksUi.open()
screen(true, 844, 354)
M.flush()
panel = named(panelGui, "Tasks")
check("a resize to a phone while open: drawn again for it (two columns, a finger's buttons)", math.abs(M.uiScale(panel) - SandboxTasksUi.layout(844, 354, true).scale) < 0.001
	and #smallButtons(panel) == 0 and inside(box(panel)))
SandboxTasksUi.close()

-- ── Garbage ─────────────────────────────────────────────────────────────────
local fine = pcall(function()
	for _, junk in { nil, 5, "state", {}, { kind = "state" }, { kind = "state", daily = "x", bonus = 4, weekly = { title = 3 } },
		{ kind = "state", daily = { { title = "x", id = "home", target = 0 / 0 }, { title = 5 }, "row" }, dayLeft = "soon", ready = -3 },
		{ kind = "done" }, { kind = "done", title = 7 }, { kind = "claimed", title = "x", money = "lots" } } do
		remote.OnClientEvent:Fire(junk)
	end
	SandboxTasksUi.open()
	M.flush()
end)
check("garbage states and messages: no error, the panel still opens (no rows from junk)", fine and SandboxTasksUi.isOpen() and named(named(panelGui, "Tasks"), "Task_1") == nil)
SandboxTasksUi.close()
remote.OnClientEvent:Fire(FIRST)
check("… a good state after them: the chip back to 1/3", named(chip, "Label").Text == "📋 TASKS 1/3")

-- ── Words ───────────────────────────────────────────────────────────────────
check("SandboxTasksUi.left: 5 h 12 min, 2 d 5 h, 12 min, 40 s", SandboxTasksUi.left(5 * 3600 + 12 * 60 + 30) == "5 h 12 min" and SandboxTasksUi.left(2 * 86400 + 5 * 3600 + 59) == "2 d 5 h"
	and SandboxTasksUi.left(12 * 60 + 5) == "12 min" and SandboxTasksUi.left(40) == "40 s" and SandboxTasksUi.left(-5) == "0 s")
check("SandboxTasksUi.amount: a count, money", SandboxTasksUi.amount(7, nil) == "7" and SandboxTasksUi.amount(1830, "$") == "$1,830")

check("no warnings", #M.warnings == 0, M.warnings[1])
if dump then
	local function encode(value, out)
		local t = type(value)
		if t == "number" then
			if value ~= value or value == math.huge or value == -math.huge then
				table.insert(out, "null")
			elseif value == math.floor(value) and math.abs(value) < 1e15 then
				table.insert(out, string.format("%d", value))
			else
				table.insert(out, string.format("%.3f", value))
			end
		elseif t == "string" then
			table.insert(out, '"' .. string.gsub(value, '[%c"\\]', function(c)
				return string.format("\\u%04x", string.byte(c))
			end) .. '"')
		elseif t == "boolean" then
			table.insert(out, tostring(value))
		elseif t == "table" then
			if #value > 0 or next(value) == nil then
				table.insert(out, "[")
				for k, v in value do
					if k > 1 then
						table.insert(out, ",")
					end
					encode(v, out)
				end
				table.insert(out, "]")
			else
				table.insert(out, "{")
				local first = true
				for k, v in value do
					if not first then
						table.insert(out, ",")
					end
					first = false
					encode(tostring(k), out)
					table.insert(out, ":")
					encode(v, out)
				end
				table.insert(out, "}")
			end
		else
			table.insert(out, "null")
		end
	end
	local out = {}
	encode(scenes, out)
	print(table.concat(out))
else
	print("ALL TASKS UI CHECKS PASSED")
end
