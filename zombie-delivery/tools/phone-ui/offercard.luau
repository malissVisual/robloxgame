-- 8.3 the showroom's visitors: a visitor's offer card (client/OfferCard.luau), run for real on sandbox_mock.luau's
-- recorder with client/TopBlocks.luau, beside the real client/SandboxHud.luau (the money block) and
-- client/SandboxTasksUi.luau (the TASKS chip), a stand-in move's panel (a top block where MoveLayout.panel puts it) and
-- Hud's groups where client/Hud.luau puts them, on a phone held sideways (844 × 390: 844 × 354 under Roblox's top bar,
-- the touch layout), a computer (1280 × 800) and a big screen (1920 × 1080): nothing when Config.Sandbox.On is false;
-- the "Visitors" remote's offer opens it ("🤝 OFFER", "The collector offers", "$340", "for your Gramophone", "Market price
-- $260 · +31%", "⏳ 30 s", a 🔥 for a hot kind); on the screen, clear of the HUD's chips and groups, the move's panel,
-- the touch buttons, the thumbstick and the jump button; ACCEPT and DECLINE a finger's size on a phone, their words
-- fitting; ACCEPT sends { kind = "accept", id } once (a second tap nothing) and closes it, DECLINE { kind = "decline", id };
-- 8.3 review: the first-time hints (client/SandboxHintsUi.luau) and the guide's soft steps wait while it is open;
-- the gamepad: the selection on DECLINE, kept inside the card, B declines; closing it (ESC) is a DECLINE; 8.3 review:
-- another window opening only hides it (OfferCard.hide: nothing sent, the offer waits, the card back once nothing
-- covers the screen; its clock and the server's closed message still end it hidden); covered by another window it
-- waits and opens when that one closes; the clock counts down and runs out (the card goes, nothing sent); the server's
-- closed message closes it; junk ignored; 8.3 review: smaller phones (667 × 375, 740 × 360, 780 × 360: the card smaller,
-- its buttons still a finger's size, clear of the chips and the touch controls); a resize while open; no warnings.
-- `luau offercard.luau -a dump` prints the preview's scenes as JSON instead (offercard_preview.py).
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
-- Does a one-line text fit its label (after the scales above it)? Every line of the card must, uncut.
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		if not object.TextWrapped then
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
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end

-- ── The stand-ins the card needs on top of sandbox_mock's ──────────────────
UIS.LastInputTypeChanged = UIS.LastInputTypeChanged or M.signal()
-- the move's panel (client/MovingHud.luau's, a top block: a move may run while you are at your warehouse) where
-- MoveLayout.panel puts it, and Hud's groups where client/Hud.luau puts them (dannycard.luau's boxes)
local TopBlocks = require("./TopBlocks")
local movingGui = M.make("ScreenGui", { Name = "MovingHud", DisplayOrder = 6 }, M.gui)
local panel = M.make("Frame", { Name = "MovePanel", BackgroundColor3 = M.MTheme.Contract.charcoal, BackgroundTransparency = 0.12 }, movingGui)
M.make("UICorner", { CornerRadius = M.UDim.new(0, 8) }, panel)
M.make("TextLabel", { Name = "Title", Text = "THE OLD FARMSTEAD · 14:52", TextSize = 14, Font = M.Enum.Font.GothamBold, TextColor3 = M.MTheme.Contract.text,
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
local moveOn = false
local function screen(touch, w, h, move)
	M.touch, M.width, M.height = touch, w, h
	moveOn = move == true
	M.placeHud()
	local S = M.MUi.scaleFor(M.Vector2.new(w, h))
	panel.Size = M.UDim2.fromOffset(MoveLayout.PANEL_W, MoveLayout.PANEL_H)
	panel:FindFirstChild("Scale").Scale = S
	local p = MoveLayout.panel(w, S)
	panel.Position = M.UDim2.fromOffset(p.x0, p.y0)
	panel.Visible = moveOn
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
	TopBlocks.set("MovePanel", if moveOn then panel else nil)
	M.flush()
end

-- ── The preview's scenes (offercard_preview.py) ─────────────────────────────
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
-- A scene: Hud's column as client/Hud.luau lays it out (the money's spacer, the chip's).
local function scene(name)
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
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
local OfferCard = require("./OfferCard")
local remote = M.Net.get("Visitors")
screen(true, 844, 354)
Config.Sandbox.On = false
OfferCard.start()
local OFFER = { kind = "offer", id = "o1", name = "Gramophone", item = "gramophone", price = 340, base = 260, who = "Collector", seconds = 30, rarity = "rare" }
remote.OnClientEvent:Fire(OFFER)
check("Config.Sandbox.On false: OfferCard.start() does nothing (no card on an offer)", not OfferCard.isOpen() and M.gui:FindFirstChild("OfferCard") == nil)
Config.Sandbox.On = true

-- ── On: the HUD's chips ─────────────────────────────────────────────────────
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
OfferCard.start()
local covered = false
OfferCard.covered = function()
	return covered
end
local opened = 0
OfferCard.onOpen = function()
	opened += 1
end

-- What the card keeps clear of: the touch controls, Hud's groups, the chips, the move's panel.
local function blocks()
	local list = {}
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		for index, b in TouchLayout.buttons(cluster) do
			list[`a touch button {index}`] = b
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
	if moveOn then
		list["the move's panel"] = box(panel)
	end
	return list
end
local function cardChecks(label)
	local card = OfferCard.card()
	local c = box(card)
	check(`{label}: the card open, on the screen`, OfferCard.isOpen() and card.Visible and inside(c), show(c))
	for name, other in blocks() do
		check(`{label}: … clear of {name}`, not overlap(c, other), `{show(c)} on {show(other)}`)
	end
	check(`{label}: … its words fit`, #badTexts(card) == 0, badTexts(card)[1])
	if M.touch then
		check(`{label}: … ACCEPT and DECLINE a finger's size`, #smallButtons(card) == 0, smallButtons(card)[1])
	end
	check(`{label}: … DECLINE left of ACCEPT, one row`, box(named(card, "Decline")).x1 < box(named(card, "Accept")).x0 and math.abs(box(named(card, "Decline")).y0 - box(named(card, "Accept")).y0) < 0.5)
end
local function offer(id, extra)
	local message = table.clone(OFFER)
	message.id = id
	for k, v in extra or {} do
		message[k] = v
	end
	remote.OnClientEvent:Fire(message)
	M.flush()
end

-- ── The phone ───────────────────────────────────────────────────────────────
offer("o1")
local card = OfferCard.card()
check("an offer: the card opens (\"OfferCard\", over the HUD), its onOpen runs (the other windows close)", OfferCard.isOpen() and card ~= nil and card.Visible and opened == 1
	and M.gui:FindFirstChild("OfferCard") ~= nil and M.gui:FindFirstChild("OfferCard").DisplayOrder > M.gui:FindFirstChild("SandboxHud").DisplayOrder)
check("… \"🤝 OFFER\", \"The collector offers\", \"$340\", \"for your Gramophone\", \"Market price $260 · +31%\", \"⏳ 30 s\"",
	named(card, "Title").Text == "🤝 OFFER" and named(card, "Who").Text == "The collector offers" and named(card, "Price").Text == "$340"
	and named(card, "Item").Text == "for your Gramophone" and named(card, "Market").Text == "Market price $260 · +31%" and named(card, "Time").Text == "⏳ 30 s",
	named(card, "Market").Text)
check("… DECLINE and ✓ ACCEPT", named(card, "Decline").Text == "DECLINE" and named(card, "Accept").Text == "✓ ACCEPT")
-- 8.3 review: the first-time hints (client/SandboxHintsUi.luau, started by the real SandboxHud) and through them the
-- guide's soft steps (client/SandboxGuide.luau asks isCovered and window) wait while the card is open
local HintsUi = require("./SandboxHintsUi")
check("8.3 review: the card open covers the screen for the first-time hints and the guide's soft steps (SandboxHintsUi: isCovered, window \"OfferCard\")",
	HintsUi.isCovered() and HintsUi.window() == "OfferCard", HintsUi.window())
cardChecks("844 x 390")
scene("offer-phone")
-- the clock
M.now += 10
M.resume()
check("the clock: \"⏳ 20 s\" ten seconds on, the bar two thirds", named(card, "Time").Text == "⏳ 20 s" and math.abs(named(card, "Left").Size.X.Scale - 2 / 3) < 0.01,
	named(card, "Time").Text)
-- ACCEPT
local before = #sentOn("Visitors")
press(named(card, "Accept"))
press(named(card, "Accept"))
local sent = sentOn("Visitors")
check("ACCEPT: { kind = \"accept\", id } once (the second tap nothing), only the id (the server has the price), the card closes", #sent == before + 1 and sent[#sent][1].kind == "accept"
	and sent[#sent][1].id == "o1" and sent[#sent][1].price == nil and not OfferCard.isOpen() and not card.Visible)
check("… the hints no longer held back by it", HintsUi.window() == nil and not HintsUi.isCovered(), HintsUi.window())
-- DECLINE
offer("o2")
press(named(card, "Decline"))
sent = sentOn("Visitors")
check("DECLINE: { kind = \"decline\", id }, the card closes", sent[#sent][1].kind == "decline" and sent[#sent][1].id == "o2" and not OfferCard.isOpen())
-- a hot kind
offer("o3", { market = "hot", name = "Jukebox", price = 1250, base = 980 })
check("a hot kind: \"🔥 Market price $980 · +28%\"", named(card, "Market").Text == "🔥 Market price $980 · +28%" and named(card, "Price").Text == "$1,250", named(card, "Market").Text)
cardChecks("844 x 390, a hot jukebox")
scene("offer-phone-hot")
-- the gamepad
OfferCard.close()
sent = sentOn("Visitors")
check("closing it (ESC, the Roblox menu: client/Main.client.luau while Hud.escaping) is a DECLINE", sent[#sent][1].kind == "decline" and sent[#sent][1].id == "o3" and not OfferCard.isOpen())
offer("o4")
check("the gamepad: the selection on DECLINE (an A by habit never sells), kept inside the card", M.focus == named(card, "Decline") and card.SelectionGroup == true
	and card.SelectionBehaviorUp.Name == "Stop" and card.SelectionBehaviorDown.Name == "Stop" and card.SelectionBehaviorLeft.Name == "Stop" and card.SelectionBehaviorRight.Name == "Stop")
key("ButtonB")
sent = sentOn("Visitors")
check("… B declines", sent[#sent][1].kind == "decline" and sent[#sent][1].id == "o4" and not OfferCard.isOpen() and M.focus == nil)
-- the server's closed message
offer("o5")
remote.OnClientEvent:Fire({ kind = "closed", id = "o9", how = "gone" })
check("the server closes another offer: this one stays", OfferCard.isOpen())
before = #sentOn("Visitors")
remote.OnClientEvent:Fire({ kind = "closed", id = "o5", how = "gone" })
check("the server closes it (the piece gone, the visitor left): the card goes, nothing sent", not OfferCard.isOpen() and #sentOn("Visitors") == before and OfferCard.pending() == nil)
-- the clock runs out
offer("o6")
M.now += 31
M.resume()
check("its clock runs out: the card goes, nothing sent", not OfferCard.isOpen() and #sentOn("Visitors") == before and OfferCard.pending() == nil)
-- covered by another window: it waits
covered = true
local opens = opened
offer("o7")
check("another window open: the card waits (not shown, the offer pending)", not OfferCard.isOpen() and OfferCard.pending() ~= nil and opened == opens)
OfferCard.close()
check("… ESC then closes the other window only (the waiting offer is not declined)", #sentOn("Visitors") == before and OfferCard.pending() ~= nil)
M.now += 5
covered = false
M.resume()
check("… that window closed: the card opens with the time left (\"⏳ 25 s\")", OfferCard.isOpen() and named(card, "Time").Text == "⏳ 25 s" and opened == opens + 1, named(card, "Time").Text)
OfferCard.close()
-- 8.3 review: another window opening over it (STOCK, the BOOK to compare prices: Main's Hud.onCloseWindows, no escape)
-- only hides it
before = #sentOn("Visitors")
offer("o11")
covered = true
OfferCard.hide()
check("8.3 review: another window opening (OfferCard.hide) only hides it: nothing sent, the offer still waiting", not OfferCard.isOpen() and not card.Visible
	and #sentOn("Visitors") == before and OfferCard.pending() ~= nil and OfferCard.pending().id == "o11")
M.now += 4
M.resume()
check("… hidden while that window is open, its clock running", not OfferCard.isOpen() and OfferCard.pending() ~= nil)
covered = false
M.resume()
check("… that window closed: the same offer again, with the time left (\"⏳ 26 s\")", OfferCard.isOpen() and named(card, "Time").Text == "⏳ 26 s"
	and #sentOn("Visitors") == before and M.focus == named(card, "Decline"), named(card, "Time").Text)
press(named(card, "Accept"))
sent = sentOn("Visitors")
check("… and ACCEPT still answers it", #sent == before + 1 and sent[#sent][1].kind == "accept" and sent[#sent][1].id == "o11")
offer("o12")
covered = true
OfferCard.hide()
M.now += 31
M.resume()
check("… hidden, its clock runs out: gone, nothing sent, not shown again", not OfferCard.isOpen() and OfferCard.pending() == nil and #sentOn("Visitors") == before + 1)
covered = false
M.resume()
check("… (nothing comes back once the screen is free)", not OfferCard.isOpen())
offer("o13")
covered = true
OfferCard.hide()
remote.OnClientEvent:Fire({ kind = "closed", id = "o13", how = "expired" })
covered = false
M.resume()
check("… hidden, the server's timeout (closed, expired): gone, nothing sent, never shown again", not OfferCard.isOpen() and OfferCard.pending() == nil
	and #sentOn("Visitors") == before + 1)
OfferCard.hide()
check("… hide with nothing open: nothing", not OfferCard.isOpen() and #sentOn("Visitors") == before + 1)
-- junk
for _, junk in { "offer", { kind = "offer" }, { kind = "offer", id = 5, name = "X", item = "x", price = 5, base = 4, who = "W", seconds = 30 }, { kind = "offer", id = "j", name = "X", item = "x", price = -5, base = 4, who = "W", seconds = 30 } } do
	remote.OnClientEvent:Fire(junk)
end
M.flush()
check("junk on the remote: no card", not OfferCard.isOpen() and OfferCard.pending() == nil)

-- a move running while at the warehouse (its panel at the top)
screen(true, 844, 354, true)
offer("o8")
cardChecks("844 x 390, a move's panel at the top")
check("844 x 390: the card at its full touch size (scale 1: nothing to shrink for)", OfferCard.card():FindFirstChild("Scale").Scale == 1)
OfferCard.close()

-- 8.3 review: smaller phones (667 × 375: 667 × 339 under Roblox's top bar, where the card lay on the 📋 TASKS chip;
-- 740 × 360, 780 × 360): it shrinks until a place is clear, its buttons still a finger's size
for _, size in { { 667, 339 }, { 740, 324 }, { 780, 324 } } do
	for _, move in { false, true } do
		screen(true, size[1], size[2], move)
		offer(`s{size[1]}{if move then "m" else ""}`)
		local label = `{size[1]} x {size[2] + 36}{if move then ", a move's panel at the top" else ""}`
		cardChecks(label)
		local scale = OfferCard.card():FindFirstChild("Scale").Scale
		check(`{label}: … smaller than its full touch size only as needed (scale {string.format("%.2f", scale)}), its buttons Ui.MinTouch tall`, scale <= 1 and scale >= 0.55
			and box(named(OfferCard.card(), "Decline")).y1 - box(named(OfferCard.card(), "Decline")).y0 >= 44 - 0.01)
		if size[1] == 667 and not move then
			check(`{label}: … smaller there (the room under the TASKS chip)`, scale < 1, scale)
			scene("offer-phone-small")
		end
		OfferCard.close()
	end
end
screen(true, 844, 354, false)

-- ── A computer (1280 × 800) and a big screen (1920 × 1080) ─────────────────
for _, size in { { 1280, 764, "computer" }, { 1920, 1044, "big" } } do
	screen(false, size[1], size[2])
	local label = `{size[1]} x {size[2] + 36}`
	offer(`c{size[1]}`)
	cardChecks(label)
	scene(`offer-{size[3]}`)
	OfferCard.close()
end

-- ── A resize while it is open ───────────────────────────────────────────────
offer("o9")
screen(true, 844, 354)
cardChecks("a resize to a phone while open: placed again for it")
OfferCard.close()

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
	print("ALL OFFER CARD CHECKS PASSED")
end
