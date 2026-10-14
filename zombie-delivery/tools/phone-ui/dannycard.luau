-- 8.3 Danny's orders: his command card (client/MoveHelperCard.luau) and his status line (client/MoveHelperHud.luau's
-- strip once the card is there: "🧑‍🔧 DANNY · AUTO", what he does, ORDERS; "⏳ WAITING FOR DANNY…" and STOP while you wait
-- for him), run for real on sandbox_mock.luau's recorder with client/TopBlocks.luau, beside the real
-- client/SandboxHud.luau (the money block) and client/SandboxTasksUi.luau (the TASKS chip), a stand-in move's panel (a
-- top block where MoveLayout.panel puts it) and Hud's groups where client/Hud.luau puts them, on a phone held sideways
-- (844 × 390: 844 × 354 under Roblox's top bar, the touch layout), a computer (1280 × 800) and a big screen
-- (1920 × 1080): nothing when Config.Sandbox.On is false; the status line under the panel, its words fitting, ORDERS a
-- finger's size on a phone; ORDERS opens the card; the card beside Danny's head on the screen (right of it, else left
-- of it: never on it), on the screen, clear of the HUD's chips, the move's panel and status line, the touch buttons,
-- the thumbstick and the jump button; its four orders (AUTO, HELP ME, WAIT HERE, WAIT AT VAN) with the one in force lit,
-- each a finger's size on a phone, their words fitting; a tap sends the Moving remote's ("helper", order) once and
-- closes it; 1-4 on a computer; ✕, the gamepad's B, a tap beside it, closing it as ESC does, walking away from him and
-- Danny gone close it, a tap on it does not; the order's change lit; the wait: the line orange, STOP and G send
-- ("helper", "stop"), ORDERS back after it; a resize while open; the gamepad's prompt on him off without a gamepad; no
-- warnings. `luau dannycard.luau -a dump` prints the preview's scenes as JSON instead (dannycard_preview.py).
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local TasksRules = require("./SandboxTasks")

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
local UIS = M.services.UserInputService
local function key(code, processed)
	UIS.InputBegan:Fire({ KeyCode = M.Enum.KeyCode[code], UserInputType = M.Enum.UserInputType.Keyboard, Position = M.Vector3.new(0, 0, 0) }, processed == true)
end
local function tap(x, y, processed)
	UIS.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.Unknown, UserInputType = M.Enum.UserInputType.Touch, Position = M.Vector3.new(x, y, 0) }, processed == true)
end
local box, overlap = M.box, TouchLayout.overlap
local function show(b)
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end
local function inside(b)
	return MoveLayout.inside(b, M.width, M.height)
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
-- Does a one-line text fit its label (after the scales above it)? What he does may run long and is cut with "…"; a
-- title, an order's name or a button never.
local CUT_OK = { Doing = true }
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		local truncated = object.TextTruncate and object.TextTruncate.Name == "AtEnd" and CUT_OK[object.Name]
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
-- The buttons a finger taps on a phone: each at least 44 × 44 screen px (the line's invisible tap area aside).
local function smallButtons(root)
	local small = {}
	for _, object in all(root, function(o)
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end
local function attribute(name, value)
	M.player:SetAttribute(name, value)
	M.player:GetAttributeChangedSignal(name):Fire()
end

-- ── The stand-ins the card needs on top of sandbox_mock's ──────────────────
UIS.TouchTapInWorld = M.signal()
UIS.LastInputTypeChanged = M.signal()
UIS.MouseBehavior = M.Enum.MouseBehavior.Default
local make = M.make -- (a ProximityPrompt's Triggered: the gamepad's "Talk to Danny")
M.make = function(class, props, parent)
	local made = make(class, props, parent)
	if class == "ProximityPrompt" then
		made.Triggered = M.signal()
	end
	return made
end
-- Danny's body in workspace.Npcs (his MoveHelper id, his root), your character's (sandbox_mock's: at 0, 0, 0)
local DANNY_ID = -2000000001
local npcs = M.make("Folder", { Name = "Npcs" }, M.workspace)
local body = M.make("Model", { Name = "Danny" }, npcs)
body:SetAttribute("MoveHelper", DANNY_ID)
local dannyRoot = M.make("BasePart", { Name = "HumanoidRootPart", Position = M.Vector3.new(8, 3, -6) }, body) -- (the recorder's IsA: its own class)
body.PrimaryPart = dannyRoot
-- the move's panel (client/MovingHud.luau's, a top block) where MoveLayout.panel puts it, and Hud's groups where
-- client/Hud.luau puts them (sandboxtasks.luau's boxes): a touch screen's left column (the cash, the minimap, the
-- health), a computer's health row at the bottom left and MOUSE [ALT] / the key hints at the top right
local TopBlocks = require("./TopBlocks")
local movingGui = M.make("ScreenGui", { Name = "MovingHud", DisplayOrder = 6 }, M.gui)
local panel = M.make("Frame", { Name = "MovePanel", BackgroundColor3 = M.MTheme.Contract.charcoal, BackgroundTransparency = 0.12 }, movingGui)
M.make("UICorner", { CornerRadius = M.UDim.new(0, 8) }, panel)
local panelTitle = M.make("TextLabel", { Name = "Title", Text = "THE ALPINE LODGE · 24:52", TextSize = 14, Font = M.Enum.Font.GothamBold, TextColor3 = M.MTheme.Contract.text,
	BackgroundTransparency = 1, Position = M.UDim2.fromOffset(12, 8), Size = M.UDim2.new(1, -24, 0, 20), TextXAlignment = M.Enum.TextXAlignment.Left }, panel)
M.make("TextLabel", { Name = "Count", Text = "📦 2 / 6 out · van 18%", TextSize = 12, Font = M.Enum.Font.GothamMedium, TextColor3 = M.MTheme.Contract.secondary,
	BackgroundTransparency = 1, Position = M.UDim2.fromOffset(12, 32), Size = M.UDim2.new(1, -24, 0, 18), TextXAlignment = M.Enum.TextXAlignment.Left }, panel)
M.make("UIScale", { Name = "Scale", Scale = 1 }, panel)
local groups = {}
for _, name in { "LeftStack", "HudButtons" } do
	groups[name] = M.make("Frame", { Name = name, BackgroundTransparency = 1 }, M.hudGui)
end
local function place(object, b)
	object.Position = M.UDim2.fromOffset(b.x0, b.y0)
	object.Size = M.UDim2.fromOffset(b.x1 - b.x0, b.y1 - b.y0)
end
local camera = M.workspace.CurrentCamera
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	local S = M.MUi.scaleFor(M.Vector2.new(w, h))
	panel.Size = M.UDim2.fromOffset(MoveLayout.PANEL_W, MoveLayout.PANEL_H)
	panel:FindFirstChild("Scale").Scale = S
	local p = MoveLayout.panel(w, S)
	panel.Position = M.UDim2.fromOffset(p.x0, p.y0)
	if touch then
		place(groups.LeftStack, M.leftColumn)
		groups.HudButtons.Visible = false
	else
		place(groups.LeftStack, { x0 = 16, y0 = h - 16 - 30 * S, x1 = 16 + 200 * S, y1 = h - 16 })
		place(groups.HudButtons, { x0 = w - 16 - MoveLayout.PLAYER_LIST_W - 260 * S, y0 = 0, x1 = w, y1 = 4 + 90 * S })
		groups.HudButtons.Visible = true
	end
	camera.ViewportSize = M.Vector2.new(w, h + 36)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	TopBlocks.set("MovePanel", panel)
	M.flush()
end

-- ── The preview's scenes (dannycard_preview.py) ─────────────────────────────
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
-- A scene: Hud's column as client/Hud.luau lays it out (the money's spacer, the chip's), Danny's head where it was.
local function scene(name, head)
	if not dump then
		return
	end
	local slot = M.topStack:FindFirstChild("Slot_sandbox")
	local money = slot and slot:FindFirstChild("SandboxSpace")
	local tasks = slot and slot:FindFirstChild("TasksSpace")
	if money and tasks then
		tasks.Position = M.UDim2.fromOffset(0, money.Size.Y.Offset + 8)
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
		table.insert(overlay, { kind = "text", box = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W - 150, y0 = 4, x1 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y1 = 30 }, label = "MOUSE [ALT]" })
	end
	if head then
		local r = math.max(18, 26 * S)
		table.insert(overlay, { kind = "round", box = { x0 = head.x - r, y0 = head.y - r, x1 = head.x + r, y1 = head.y + r }, label = "DANNY" })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
local MoveHelperHud = require("./MoveHelperHud")
local MoveHelperCard = require("./MoveHelperCard")
screen(true, 844, 354)
Config.Sandbox.On = false
MoveHelperCard.start()
attribute("MoveHelper", "auto")
check("Config.Sandbox.On false: MoveHelperCard.start() does nothing (no card, no prompt on him)", not MoveHelperCard.isOpen() and M.gui:FindFirstChild("MoveHelperCard") == nil
	and dannyRoot:FindFirstChild("TalkToDanny") == nil)
attribute("MoveHelper", nil)
Config.Sandbox.On = true

-- ── On: the HUD's chips, the status line ────────────────────────────────────
local SandboxHud = require("./SandboxHud")
local SandboxTasksUi = require("./SandboxTasksUi")
SandboxHud.start()
SandboxHud.setState({ money = 12480 })
M.flush()
SandboxTasksUi.start()
local NOW = 20372 * 86400 + 18 * 3600
local view = TasksRules.view(TasksRules.fresh(42, NOW), NOW) :: any
view.kind = "state"
M.remotes.SandboxTasks.OnClientEvent:Fire(view)
M.flush()
local chip = named(M.gui:FindFirstChild("SandboxTasksChip"), "TasksChip")
check("(the HUD's chips there: the money block, the TASKS chip)", SandboxHud.block() ~= nil and chip ~= nil and chip.Visible)
MoveHelperHud.start()
MoveHelperCard.start()
attribute("MoveHelperId", DANNY_ID)
attribute("MoveHelperDoing", "Carrying the Lamp to the van")
attribute("MoveHelper", "auto")
M.flush()
local strip = MoveHelperHud.strip()
check("Danny on your move: his status line (the strip) with the card: no order buttons, ORDERS", strip ~= nil and strip.Visible and named(strip, "Action").Visible
	and named(strip, "Action").Text == "ORDERS" and not named(strip, "auto").Visible and not named(strip, "help").Visible)
check("… \"🧑‍🔧 DANNY · AUTO\" over what he does", named(strip, "Title").Text == "🧑‍🔧 DANNY · AUTO" and named(strip, "Doing").Text == "Carrying the Lamp to the van")
check("the gamepad's \"Talk to Danny\" on his root (ButtonL1), off without a gamepad", dannyRoot:FindFirstChild("TalkToDanny") ~= nil
	and dannyRoot:FindFirstChild("TalkToDanny").ActionText == "Talk to Danny" and dannyRoot:FindFirstChild("TalkToDanny").GamepadKeyCode == M.Enum.KeyCode.ButtonL1
	and dannyRoot:FindFirstChild("TalkToDanny").Enabled == false)

-- What the card (and the status line) keeps clear of: the touch controls, Hud's groups, the chips, the move's panel.
local function blocks(withStrip)
	local list = {}
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		for _, b in TouchLayout.buttons(cluster) do
			list["a touch button"] = b
		end
		list["the thumbstick"] = cluster.thumb
		list["the jump button"] = cluster.jump
		list["the left column"] = M.leftColumn
	else
		list["the health row"] = box(groups.LeftStack)
		list["MOUSE [ALT], the key hints"] = box(groups.HudButtons)
	end
	list["the money block"] = box(SandboxHud.block())
	list["the TASKS chip"] = box(chip)
	list["the move's panel"] = box(panel)
	if withStrip then
		list["Danny's status line"] = box(strip)
	end
	return list
end
local function buttonsAll(fn)
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, M.MUi.scaleFor(M.Vector2.new(M.width, M.height)))
		for index, b in TouchLayout.buttons(cluster) do
			fn(`a touch button {index}`, b)
		end
	end
end
local function clearOfAll(b, withStrip)
	for name, other in blocks(withStrip) do
		if overlap(b, other) then
			return false, `on {name} {show(other)}`
		end
	end
	local hit = nil
	buttonsAll(function(name, other)
		if not hit and overlap(b, other) then
			hit = `on {name} {show(other)}`
		end
	end)
	return hit == nil, hit
end
local function stripChecks(label)
	local s = box(strip)
	local p = box(panel)
	check(`{label}: the status line right under the move's panel, on the screen`, s.y0 >= p.y1 - 0.5 and s.y0 - p.y1 < 12 and inside(s), `{show(p)} / {show(s)}`)
	local clear, why = clearOfAll(s, false)
	check(`{label}: … clear of the touch controls, Hud's groups and the chips`, clear, why)
	check(`{label}: … its words fit (what he does may be cut with "…")`, #badTexts(strip) == 0, badTexts(strip)[1])
	if M.touch then
		check(`{label}: … ORDERS a finger's size`, #smallButtons(strip) == 0, smallButtons(strip)[1])
	end
end
local function cardChecks(label, head)
	local card = MoveHelperCard.card()
	local c = box(card)
	check(`{label}: the card open, on the screen`, MoveHelperCard.isOpen() and card.Visible and inside(c), show(c))
	local clear, why = clearOfAll(c, true)
	check(`{label}: … clear of the touch controls, Hud's groups, the chips, the move's panel and Danny's status line`, clear, why)
	if head then
		local onHim = head.x > c.x0 and head.x < c.x1 and head.y > c.y0 and head.y < c.y1
		local gap = math.max(c.x0 - head.x, head.x - c.x1, c.y0 - head.y, head.y - c.y1, 0)
		check(`{label}: … beside Danny's head (never on it, a short way off)`, not onHim and gap <= 120, `{show(c)} by {head.x},{head.y}`)
	end
	local names = {}
	for _, id in { "auto", "help", "stay", "van" } do
		local button = named(card, id)
		table.insert(names, if button then named(button, "Label").Text else "-")
	end
	check(`{label}: … its four orders in order: 🤖 AUTO, 🙋 HELP ME, ⏸ WAIT HERE, 🚐 WAIT AT VAN`, table.concat(names, "|") == "🤖 AUTO|🙋 HELP ME|⏸ WAIT HERE|🚐 WAIT AT VAN",
		table.concat(names, "|"))
	check(`{label}: … its words fit`, #badTexts(card) == 0, badTexts(card)[1])
	if M.touch then
		check(`{label}: … every button a finger's size (the orders, ✕)`, #smallButtons(card) == 0, smallButtons(card)[1])
		check(`{label}: … no key hints on a touch screen`, not named(named(card, "auto"), "Key").Visible)
	else
		check(`{label}: … the keys 1-4 on its orders`, named(named(card, "auto"), "Key").Visible and named(named(card, "van"), "Key").Text == "4")
	end
end
local function lit(id)
	local card = MoveHelperCard.card()
	local count = 0
	for _, other in { "auto", "help", "stay", "van" } do
		if named(card, other).BackgroundColor3.R > 0.9 then
			count += 1
		end
	end
	return count == 1 and named(card, id).BackgroundColor3.R > 0.9
end

-- ── The phone ───────────────────────────────────────────────────────────────
stripChecks("844 x 390")
scene("danny-status-phone", nil)
press(named(strip, "Action"))
M.flush()
check("ORDERS opens his card (\"MoveHelperCard\", over the HUD)", MoveHelperCard.isOpen() and M.gui:FindFirstChild("MoveHelperCard") ~= nil
	and M.gui:FindFirstChild("MoveHelperCard").DisplayOrder > M.gui:FindFirstChild("MoveHelperHud").DisplayOrder)
check("… \"🧑‍🔧 DANNY\" and what he does (the order · his doing)", named(MoveHelperCard.card(), "Title").Text == "🧑‍🔧 DANNY"
	and named(MoveHelperCard.card(), "Doing").Text == "AUTO · Carrying the Lamp to the van")
check("… AUTO lit (the order in force)", lit("auto"))
cardChecks("844 x 390 (ORDERS: his head off the screen)", nil)
MoveHelperCard.close()
local heads = { { x = 422, y = 170 }, { x = 760, y = 120 }, { x = 200, y = 120 }, { x = 560, y = 250 } }
for index, head in heads do
	MoveHelperCard.open(head)
	M.flush()
	cardChecks(`844 x 390, a tap on him at {head.x},{head.y}`, head)
	if index == 1 then
		scene("danny-card-phone", head)
	end
	MoveHelperCard.close()
end
-- an order
MoveHelperCard.open(heads[1])
local before = #sentOn("Moving")
press(named(MoveHelperCard.card(), "help"))
press(named(MoveHelperCard.card(), "help"))
local sent = sentOn("Moving")
check("HELP ME: the Moving remote's (\"helper\", \"help\") once (the card closes at the first tap)", #sent == before + 1 and sent[#sent][1] == "helper" and sent[#sent][2] == "help"
	and not MoveHelperCard.isOpen())
attribute("MoveHelper", "help")
attribute("MoveHelperDoing", "Right behind you")
MoveHelperCard.open(heads[1])
check("the server's answer (MoveHelper = help): HELP ME lit, the line too", lit("help") and named(strip, "Title").Text == "🧑‍🔧 DANNY · HELP ME"
	and named(MoveHelperCard.card(), "Doing").Text == "HELP ME · Right behind you")
-- closing
press(named(MoveHelperCard.card(), "Close"))
check("✕ closes it", not MoveHelperCard.isOpen() and not MoveHelperCard.card().Visible)
MoveHelperCard.open(heads[1])
key("ButtonB")
check("the gamepad's B closes it", not MoveHelperCard.isOpen())
MoveHelperCard.open(heads[1])
local c = box(MoveHelperCard.card())
tap((c.x0 + c.x1) / 2, (c.y0 + c.y1) / 2, true)
check("a tap on it (the game's: its buttons) keeps it open", MoveHelperCard.isOpen())
tap(math.max(4, c.x0 - 30), math.min(M.height - 4, c.y1 + 20), false)
check("a tap beside it closes it", not MoveHelperCard.isOpen())
MoveHelperCard.open(heads[1])
MoveHelperCard.close() -- (ESC: client/Main.client.luau's Hud.onCloseWindows closes every window)
check("ESC (the windows' close) closes it", not MoveHelperCard.isOpen())
MoveHelperCard.open(heads[1])
dannyRoot.Position = M.Vector3.new(Config.MoveHelper.CardReach + 20, 3, 0)
M.resume()
check("walking away from him (CardReach studs) closes it", not MoveHelperCard.isOpen())
dannyRoot.Position = M.Vector3.new(8, 3, -6)
MoveHelperCard.open(heads[1])
attribute("MoveHelper", nil)
check("Danny gone (off your move): it closes, the line goes", not MoveHelperCard.isOpen() and not strip.Visible)
attribute("MoveHelper", "auto")
attribute("MoveHelperDoing", "Carrying the Lamp to the van")

-- the wait: you called him to a two-person piece
attribute("MoveHelperCall", "Sofa")
attribute("MoveHelperDoing", "Coming to lift the Sofa with you")
M.flush()
check("8.3 you wait for him: the line orange, \"⏳ WAITING FOR DANNY…\", STOP", strip.BackgroundColor3.R > 0.9 and named(strip, "Title").Text == "⏳ WAITING FOR DANNY…"
	and named(strip, "Doing").Text == "Stay at your end of the Sofa · G: stop" and named(strip, "Action").Text == "STOP")
stripChecks("844 x 390, waiting")
scene("danny-waiting-phone", nil)
attribute("MoveHelperReady", true)
check("… he is at its other end (MoveHelperReady: your lift check open): \"💪 ON THREE… LIFT!\", STOP still", named(strip, "Title").Text == "💪 ON THREE… LIFT!"
	and named(strip, "Doing").Text == "Danny is at the other end of the Sofa · G: stop" and named(strip, "Action").Text == "STOP")
stripChecks("844 x 390, ready")
attribute("MoveHelperReady", nil)
before = #sentOn("Moving")
press(named(strip, "Action"))
sent = sentOn("Moving")
check("… STOP sends (\"helper\", \"stop\") (the server ends the call), the card stays shut", #sent == before + 1 and sent[#sent][1] == "helper" and sent[#sent][2] == "stop"
	and not MoveHelperCard.isOpen())
key("G")
sent = sentOn("Moving")
check("… G too", #sent == before + 2 and sent[#sent][2] == "stop")
key("G", true)
check("… not a G the game took (typing)", #sentOn("Moving") == before + 2)
attribute("MoveHelperCall", nil)
attribute("MoveHelperDoing", "Carrying the Lamp to the van")
key("G")
check("… no wait: G sends nothing", #sentOn("Moving") == before + 2)
check("the wait over: ORDERS again, the line charcoal", named(strip, "Action").Text == "ORDERS" and strip.BackgroundColor3.R < 0.2)

-- ── A computer (1280 × 800) and a big screen (1920 × 1080) ─────────────────
for _, size in { { 1280, 764, "computer" }, { 1920, 1044, "big" } } do
	screen(false, size[1], size[2])
	local label = `{size[1]} x {size[2] + 36}`
	stripChecks(label)
	for index, head in { { x = size[1] * 0.5, y = size[2] * 0.42 }, { x = size[1] * 0.85, y = size[2] * 0.5 }, { x = size[1] * 0.3, y = size[2] * 0.12 } } do
		MoveHelperCard.open(head)
		M.flush()
		cardChecks(`{label}, a click on him at {math.floor(head.x)},{math.floor(head.y)}`, head)
		if index == 1 then
			scene(`danny-card-{size[3]}`, head)
		end
		MoveHelperCard.close()
	end
	MoveHelperCard.open({ x = size[1] * 0.5, y = size[2] * 0.42 })
	before = #sentOn("Moving")
	key("Three")
	sent = sentOn("Moving")
	check(`{label}: the key 3: WAIT HERE (\"helper\", \"stay\"), the card closes`, #sent == before + 1 and sent[#sent][2] == "stay" and not MoveHelperCard.isOpen())
	MoveHelperCard.open({ x = size[1] * 0.5, y = size[2] * 0.42 })
	key("One", true)
	check(`{label}: … not a key the game took`, #sentOn("Moving") == before + 1 and MoveHelperCard.isOpen())
	MoveHelperCard.close()
end

-- ── A resize while it is open ───────────────────────────────────────────────
MoveHelperCard.open({ x = 640, y = 320 })
screen(true, 844, 354)
cardChecks("a resize to a phone while open: placed again for it", nil)
MoveHelperCard.close()

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
			table.insert(out, '"' .. string.gsub(value, '[%c"\\]', function(ch)
				return string.format("\\u%04x", string.byte(ch))
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
	print("ALL DANNY CARD CHECKS PASSED")
end
