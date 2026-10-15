-- 8.5 Danny's clipboard, ORDERS MODE (client/DannyOrders.luau; the owner: "I'll hold a paper in my hand, like a notepad
-- … a kind of ordering mode and I click on what he should carry"), run for real on sandbox_mock.luau's recorder with
-- client/MoveHelperCard.luau, client/MoveHelperHud.luau and client/TopBlocks.luau (dannycardenv.py's folder), beside the
-- real client/SandboxHud.luau (the money block) and client/SandboxTasksUi.luau (the TASKS chip), a stand-in move's panel
-- and Hud's groups where client/Hud.luau puts them, on phones held sideways (844 × 390, 667 × 375: the touch layout), a
-- computer (1280 × 800) and a big screen (1920 × 1080):
--   * the line at the bottom ("📋 Pick what Danny carries: E or click · Q put away", a gamepad's R1 and B, a phone's "tap 📋 to put away")
--     only while the clipboard is out (the server's ClipboardHeld) and Danny hired; on a touch screen the 📋 button
--     (ORDERS, orange while it is out) while he is hired and your hands are free; both on the screen, clear of the HUD's
--     chips, the touch controls (the buttons, the thumbstick's corner, the jump button), the move's panel, Danny's
--     status line, Hud's groups and each other; their words fit; the button a finger's size;
--   * asking: Q (not while typing), the gamepad's R1 out and B away (R1 left to "Give to Danny" while it is out, B to
--     a window that is open), the 📋 button, Danny's status line's 📋 ORDERS; never while he is not hired;
--   * stepping aside: his card open (a window), a grip check: the line and the button hidden; your hands full: no button;
--   * the piece pointed at (the mouse, a gamepad's nearest, a phone's tap a moment): outlined green to give, orange on
--     his list (its number), red with the reason (too far, in the van, his list full), nothing for another move's;
--     nothing once it is put away; 8.6 Danny himself orange, "📋 Orders for Danny", his click his orders menu;
--   * 9.0 E gives a piece: with the clipboard out the pieces' own Pick up hidden on this screen (their reach; Enabled,
--     the server's, untouched; nothing sent), a "Give to Danny" prompt of the client's in its place (E, the piece's
--     name and reach), "Take back" on his list, E sending the click's request each time, the click still working; none
--     when he can't take it (his list full, in the van) or it is far; parked under a window and with a gamepad (its R1
--     prompt instead); a phone's to tap; a door's prompt and another player's move's pieces untouched; everything back
--     at its reach when it is put away, on a new body and at the move's end; no warnings.
local M = require("./sandbox_mock")
local Config = require("./Config")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local TasksRules = require("./SandboxTasks")

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
local function sentOn(remote)
	local list = {}
	for _, entry in M.sent do
		if entry.name == remote then
			table.insert(list, entry.args)
		end
	end
	return list
end
local UIS = M.services.UserInputService
local function key(code, processed)
	UIS.InputBegan:Fire({ KeyCode = M.Enum.KeyCode[code], UserInputType = M.Enum.UserInputType.Keyboard, Position = M.Vector3.new(0, 0, 0) }, processed == true)
end
local box, overlap = M.box, TouchLayout.overlap
local function show(b)
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end
local function shown(object)
	local node = object
	while node do
		if node.Visible == false or node.Enabled == false then
			return false
		end
		node = node.Parent
	end
	return true
end
local function attribute(name, value)
	M.player:SetAttribute(name, value)
	M.player:GetAttributeChangedSignal(name):Fire()
end
-- Does a one-line text fit its label (after the scales above it)?
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		local b = box(object)
		local need = M.textWidth(object.Text, (object.TextSize or 14) * M.scaleOf(object), object.Font)
		if need > b.x1 - b.x0 + 0.5 then
			table.insert(bad, `{object.Name} "{object.Text}" {math.floor(need)} > {math.floor(b.x1 - b.x0)}`)
		end
	end
	return bad
end

-- ── The stand-ins (dannycard.luau's) ────────────────────────────────────────
UIS.TouchTapInWorld = M.signal()
UIS.LastInputTypeChanged = M.signal()
UIS.MouseBehavior = M.Enum.MouseBehavior.Default
UIS.GetMouseLocation = function()
	return M.Vector2.new(400, 236)
end
local make = M.make
M.make = function(class, props, parent)
	local made = make(class, props, parent)
	if class == "ProximityPrompt" then
		made.Triggered = M.signal()
	end
	return made
end
local vmeta = getmetatable(M.Vector3.new(0, 0, 0))
local vindex = vmeta.__index
vmeta.__add = function(a, b)
	return M.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
vmeta.__mul = function(a, k)
	return M.Vector3.new(a.X * k, a.Y * k, a.Z * k)
end
vmeta.__index = function(a, name)
	if name == "Unit" then
		local m = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
		return M.Vector3.new(a.X / m, a.Y / m, a.Z / m)
	elseif name == "Dot" then
		return function(self, b)
			return self.X * b.X + self.Y * b.Y + self.Z * b.Z
		end
	end
	return vindex(a, name)
end
M.methods.IsDescendantOf = function(self, ancestor)
	local node = self.Parent
	while node do
		if node == ancestor then
			return true
		end
		node = node.Parent
	end
	return false
end
M.methods.FindFirstAncestorOfClass = function(self, class)
	local node = self.Parent
	while node do
		if node.ClassName == class then
			return node
		end
		node = node.Parent
	end
	return nil
end
M.RaycastParams = { new = function()
	return {}
end }
local rayHit = nil
M.workspace.Raycast = function()
	return rayHit
end
local tagged = {}
M.services.CollectionService = { GetTagged = function(_, tag)
	return tagged[tag] or {}
end }
local gamepad = false
M.MUi.gamepadActive = function()
	return gamepad
end
M.MUi.gamepadRelease = function(container)
	local selected = M.focus
	if selected and container and selected:IsDescendantOf(container) then
		M.focus = nil
	end
end
local DANNY_ID = -2000000001
local npcs = M.make("Folder", { Name = "Npcs" }, M.workspace)
local body = M.make("Model", { Name = "Danny" }, npcs)
body:SetAttribute("MoveHelper", DANNY_ID)
local dannyRoot = M.make("BasePart", { Name = "HumanoidRootPart", Position = M.Vector3.new(8, 3, -6) }, body)
body.PrimaryPart = dannyRoot
M.player:SetAttribute("MoveWith", 14)
local function piece(name, spot, owner, at)
	local model = M.make("Model", { Name = name }, M.workspace)
	model:SetAttribute("MoveSpot", spot)
	local root = M.make("BasePart", { Name = "Root", Position = at }, model)
	model.PrimaryPart = root
	local own = M.make("ProximityPrompt", { Name = "Pick", ActionText = "Pick up", ObjectText = name, MaxActivationDistance = Config.Moving.Reach.Item }, root)
	own:SetAttribute("MoveOwner", owner)
	tagged.MovePrompt = tagged.MovePrompt or {}
	table.insert(tagged.MovePrompt, own)
	return model, root, own
end
local lamp, lampRoot, lampPick = piece("Lamp", 1, 14, M.Vector3.new(4, 1, 2))
local _, strangerRoot = piece("Vase", 1, 99, M.Vector3.new(-4, 1, 2))
local grip = require("./CarryGripUi")
local TopBlocks = require("./TopBlocks")
local movingGui = M.make("ScreenGui", { Name = "MovingHud", DisplayOrder = 6 }, M.gui)
local panel = M.make("Frame", { Name = "MovePanel", BackgroundColor3 = M.MTheme.Contract.charcoal, BackgroundTransparency = 0.12 }, movingGui)
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
camera.ScreenPointToRay = function()
	return { Origin = M.Vector3.new(0, 20, 30), Direction = M.Vector3.new(0, -0.5, -1) }
end
camera.ViewportPointToRay = camera.ScreenPointToRay
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
	M.resume() -- (DannyOrders' look: placed for the new screen)
end
local function clipboard(out) -- (the server's answer: your character's ClipboardHeld)
	M.player.Character:SetAttribute("ClipboardHeld", if out then true else nil)
	M.resume()
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
local MoveHelperHud = require("./MoveHelperHud")
local MoveHelperCard = require("./MoveHelperCard")
local DannyOrders = require("./DannyOrders")
Config.Sandbox.On = false
DannyOrders.start()
check("Config.Sandbox.On false: DannyOrders.start() does nothing (no line, no button)", M.gui:FindFirstChild("DannyOrders") == nil and DannyOrders.hint() == nil)
Config.Sandbox.On = true

-- ── On: the HUD's chips, Danny hired ────────────────────────────────────────
screen(true, 844, 354)
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
MoveHelperHud.start()
MoveHelperCard.start()
DannyOrders.start()
attribute("MoveHelperId", DANNY_ID)
attribute("MoveHelperDoing", "Waiting by the van for hire")
attribute("MoveHelperPrice", 170)
attribute("MoveHelper", "offer")
M.flush()
M.resume()
local hint, button = DannyOrders.hint(), DannyOrders.button()
local strip = MoveHelperHud.strip()
check("(the HUD's chips there; Danny for hire: his status line)", SandboxHud.block() ~= nil and chip ~= nil and chip.Visible and strip ~= nil and strip.Visible)
check("for hire: no line, no 📋 button (nothing to give orders to)", hint ~= nil and button ~= nil and not shown(hint) and not shown(button))
local before = #sentOn("Clipboard")
key("Q")
check("… Q asks nothing", #sentOn("Clipboard") == before)
attribute("MoveHelperPrice", nil)
attribute("MoveHelperQueue", 2)
attribute("MoveHelperDoing", "Carrying the Lamp to the van")
attribute("MoveHelper", "hired")
M.flush()
M.resume()
check("hired, a phone: the 📋 button (ORDERS, charcoal), no line yet (the clipboard away)", shown(button) and not shown(hint) and named(button, "Word").Text == "ORDERS"
	and button.BackgroundColor3.R < 0.5)

-- ── Where they go: clear of everything ──────────────────────────────────────
-- the HUD's chips, the touch controls, the move's panel, Danny's status line, Hud's groups
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
		list["the key hints (9.0: no MOUSE [ALT])"] = box(groups.HudButtons)
	end
	list["the money block"] = box(SandboxHud.block())
	list["the TASKS chip"] = box(chip)
	list["the move's panel"] = box(panel)
	if shown(strip) then
		list["Danny's status line"] = box(strip)
	end
	return list
end
local function clearOfAll(b)
	for name, other in blocks() do
		if overlap(b, other) then
			return false, `on {name} {show(other)}`
		end
	end
	return true, nil
end
local WORDS = {
	keys = "📋 Pick what Danny carries: E or click · Q put away", -- (9.0: E by a piece too)
	pad = "📋 Pick what Danny carries: R1 by it · B put away",
	touch = "📋 Tap what Danny carries · tap 📋 to put away",
}
local function layoutChecks(label)
	local h, s = box(hint), box(strip)
	check(`{label}: the line shown, on the screen, at the bottom`, shown(hint) and MoveLayout.inside(h, M.width, M.height) and h.y0 > M.height * 0.6, show(h))
	local clear, why = clearOfAll(h)
	check(`{label}: … clear of the HUD's chips, {if M.touch then "the touch controls, " else "Hud's groups, "}the move's panel and Danny's status line`, clear, why)
	check(`{label}: … under Danny's status line, never on it`, h.y0 >= s.y1 and not overlap(h, s), `{show(h)} / {show(s)}`)
	check(`{label}: … its words fit`, #badTexts(hint) == 0, badTexts(hint)[1])
	local device = if gamepad then "pad" elseif M.touch then "touch" else "keys"
	check(`{label}: … the device's words: "{WORDS[device]}"`, named(hint, "Words").Text == WORDS[device], named(hint, "Words").Text)
	if M.touch and not gamepad then
		local b = box(button)
		check(`{label}: the 📋 button on the screen, a finger's size (44 px at least each way)`, shown(button) and MoveLayout.inside(b, M.width, M.height)
			and b.x1 - b.x0 >= 44 - 0.01 and b.y1 - b.y0 >= 44 - 0.01, show(b))
		local clearB, whyB = clearOfAll(b)
		check(`{label}: … clear of the HUD's chips, the touch controls, the move's panel and Danny's status line`, clearB, whyB)
		check(`{label}: … and of the line`, not overlap(b, h), `{show(b)} / {show(h)}`)
		check(`{label}: … its words fit (📋, ORDERS)`, #badTexts(button) == 0, badTexts(button)[1])
		check(`{label}: … orange while the clipboard is out`, button.BackgroundColor3.R > 0.9)
	else
		check(`{label}: no 📋 button on a computer (Q) or with a gamepad (R1 / B)`, not shown(button))
	end
end

for _, size in { { true, 844, 354, "844 x 390" }, { true, 667, 339, "667 x 375" }, { false, 1280, 764, "1280 x 800" }, { false, 1920, 1044, "1920 x 1080" } } do
	screen(size[1], size[2], size[3])
	clipboard(false)
	check(`{size[4]}: the clipboard away: no line`, not shown(hint))
	clipboard(true)
	layoutChecks(`{size[4]}, orders mode`)
	gamepad = true
	UIS.LastInputTypeChanged:Fire()
	M.resume()
	check(`{size[4]}: with a gamepad: "{WORDS.pad}", no 📋 button`, named(hint, "Words").Text == WORDS.pad and not shown(button), named(hint, "Words").Text)
	layoutChecks(`{size[4]}, orders mode, a gamepad`)
	gamepad = false
	UIS.LastInputTypeChanged:Fire()
	M.resume()
	-- a resize keeps them clear
end
screen(true, 844, 354)
layoutChecks("844 x 390 again (a resize back)")

-- ── Asking: Q, R1 / B, the 📋 button, the status line's 📋 ORDERS ──────────
clipboard(false)
before = #sentOn("Clipboard")
key("Q")
local sent = sentOn("Clipboard")
check("Q, the clipboard away: asks for it (true)", #sent == before + 1 and sent[#sent][1] == true)
key("Q", true)
check("… not a Q the game took (typing in a box)", #sentOn("Clipboard") == before + 1)
clipboard(true)
key("Q")
sent = sentOn("Clipboard")
check("Q, the clipboard out: puts it away (false)", #sent == before + 2 and sent[#sent][1] == false)
gamepad = true
UIS.LastInputTypeChanged:Fire()
key("ButtonR1")
check("a gamepad, the clipboard out: R1 asks nothing (it is \"Give to Danny\"'s by a piece now)", #sentOn("Clipboard") == before + 2)
key("ButtonB")
sent = sentOn("Clipboard")
check("… B puts it away (false)", #sent == before + 3 and sent[#sent][1] == false)
MoveHelperCard.open({ x = 300, y = 170 })
key("ButtonB")
check("… B with his card open: the card's (it closes), the clipboard stays", #sentOn("Clipboard") == before + 3 and not MoveHelperCard.isOpen())
clipboard(false)
key("ButtonR1")
sent = sentOn("Clipboard")
check("… the clipboard away: R1 takes it out (true)", #sent == before + 4 and sent[#sent][1] == true)
key("ButtonB")
check("… and B then asks nothing (B is its other work's: the clipboard is away)", #sentOn("Clipboard") == before + 4)
gamepad = false
UIS.LastInputTypeChanged:Fire()
button.Activated:Fire()
sent = sentOn("Clipboard")
check("the 📋 button (a phone): takes it out (true)", #sent == before + 5 and sent[#sent][1] == true)
clipboard(true)
button.Activated:Fire()
sent = sentOn("Clipboard")
check("… and puts it away (false)", #sent == before + 6 and sent[#sent][1] == false)
named(strip, "Action").Activated:Fire()
sent = sentOn("Clipboard")
check("Danny's status line's 📋 PUT AWAY (out): false", #sent == before + 7 and sent[#sent][1] == false)

-- ── Stepping aside ──────────────────────────────────────────────────────────
clipboard(true)
MoveHelperCard.open({ x = 300, y = 170 })
M.resume()
check("his card open (a window): the line and the 📋 button step aside", not shown(hint) and not shown(button))
MoveHelperCard.close()
M.resume()
check("… shut: back", shown(hint) and shown(button))
DannyOrders.covered = function()
	return true
end
M.resume()
check("another window open (Main's covered: the camera's windowOpen): hidden too", not shown(hint) and not shown(button))
DannyOrders.covered = nil
grip.open = true
M.resume()
check("a grip check showing: hidden", not shown(hint) and not shown(button))
grip.open = false
clipboard(false)
M.player.Character:SetAttribute("Carrying", "crate")
M.resume()
check("your hands full (the clipboard away): no 📋 button (it can't come out: the server says so too)", not shown(button))
M.player.Character:SetAttribute("Carrying", nil)
M.resume()
check("… hands free: the 📋 button again", shown(button))

-- ── The piece pointed at ────────────────────────────────────────────────────
local mark = M.workspace:FindFirstChild("DannyOrders"):FindFirstChild("Pointed")
local function lit()
	local piece, words = DannyOrders.lit()
	return piece, words
end
screen(false, 1280, 764)
clipboard(true)
rayHit = { Instance = lampRoot, Position = lampRoot.Position }
M.resume()
local p, w = lit()
check("a computer, the mouse on the Lamp: outlined green, \"✔ Give to Danny\"", p == lamp and w == "✔ Give to Danny" and mark.Enabled and mark.Adornee == lamp
	and mark.OutlineColor.G > 0.8 and mark.OutlineColor.R < 0.5, w)
lamp:SetAttribute("DannyQueue", 2)
M.resume()
p, w = lit()
check("… on his list (#2): orange, \"↩ #2 on his list · take back\"", w == "↩ #2 on his list · take back" and mark.OutlineColor.R > 0.9 and mark.OutlineColor.B < 0.3, w)
lamp:SetAttribute("DannyQueue", nil)
attribute("MoveHelperQueue", Config.MoveHelper.Queue)
M.resume()
p, w = lit()
check(`… his list full: red, "✖ His list is full ({Config.MoveHelper.Queue}/{Config.MoveHelper.Queue})"`, w == `✖ His list is full ({Config.MoveHelper.Queue}/{Config.MoveHelper.Queue})`
	and mark.OutlineColor.R > 0.8 and mark.OutlineColor.G < 0.4, w)
attribute("MoveHelperQueue", 2)
lampRoot.Position = M.Vector3.new(Config.MoveHelper.ClickReach + 40, 1, 0)
M.resume()
p, w = lit()
check("… too far: red, \"✖ Too far: get closer\"", w == "✖ Too far: get closer", w)
lampRoot.Position = M.Vector3.new(4, 1, 2)
lampPick.Enabled = false
local van = M.make("Model", { Name = "Van" }, M.workspace)
local vanBody = M.make("BasePart", { Name = "Body" }, van)
local weld = M.make("WeldConstraint", { Part0 = vanBody, Part1 = lampRoot }, lampRoot)
M.resume()
p, w = lit()
check("… welded in the van (its prompt off): red, \"✖ In the van already\"", w == "✖ In the van already", w)
weld.Parent = nil
lampPick.Enabled = true
rayHit = { Instance = strangerRoot, Position = strangerRoot.Position }
M.resume()
p, w = lit()
check("another move's piece: nothing outlined", p == nil and not mark.Enabled)
rayHit = { Instance = dannyRoot, Position = dannyRoot.Position }
M.resume()
p, w = lit()
check("8.6 the mouse on Danny himself: outlined orange, \"📋 Orders for Danny\" (a click there opens his orders menu)", p == body and w == "📋 Orders for Danny"
	and mark.Enabled and mark.Adornee == body and mark.OutlineColor.R > 0.9 and mark.OutlineColor.B < 0.3, w)
local orderFrom = #sentOn("Moving")
UIS.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.Unknown, UserInputType = M.Enum.UserInputType.MouseButton1, Position = M.Vector3.new(400, 236, 0) }, false)
M.resume()
check("8.6 …its click: his orders menu (the card's short form), nothing given; the line steps aside for it", MoveHelperCard.isMenu() and #sentOn("Moving") == orderFrom
	and not shown(hint))
MoveHelperCard.close()
M.resume()
rayHit = { Instance = lampRoot, Position = lampRoot.Position }
M.resume()
clipboard(false)
p, w = lit()
check("the clipboard put away: nothing outlined (no orders mode)", p == nil and not mark.Enabled)
-- a phone: the tapped piece a moment
screen(true, 844, 354)
clipboard(true)
UIS.TouchTapInWorld:Fire(M.Vector2.new(400, 200), false)
M.resume()
p, w = lit()
check("a phone: a tap on the Lamp sends it and outlines it a moment", p == lamp and w == "✔ Give to Danny" and sentOn("Moving")[#sentOn("Moving")][3] == lamp, w)
M.now += Config.MoveHelper.Clipboard.Flash + 0.1
M.resume()
p, w = lit()
check("… Clipboard.Flash s later: gone", p == nil and not mark.Enabled)
-- a gamepad: the nearest piece (R1's)
gamepad = true
UIS.LastInputTypeChanged:Fire()
M.resume()
M.resume()
p, w = lit()
check("a gamepad: the piece \"Give to Danny\" is on (R1's: the nearest) outlined", p == lamp and w == "✔ Give to Danny" and MoveHelperCard.giveTarget() == lamp, w)
gamepad = false
UIS.LastInputTypeChanged:Fire()
clipboard(false)

-- ── 9.0 E gives a piece: its own prompts hidden, "Give to Danny" in their place ──
-- (the owner: "When I hold the clipboard (Q), the E shouldn't show 'pick up'; E should mark the piece for Danny")
screen(false, 1280, 764)
rayHit = nil
local REACH = Config.Moving.Reach.Item
local door = M.make("BasePart", { Name = "FrontDoor", Position = M.Vector3.new(2, 1, 6) }, M.workspace)
local enter = M.make("ProximityPrompt", { Name = "Enter", ActionText = "Enter house", ObjectText = "Linden House", MaxActivationDistance = 10 }, door)
enter:SetAttribute("MoveOwner", 14)
table.insert(tagged.MovePrompt, enter)
local strangerPick = strangerRoot:FindFirstChildOfClass("ProximityPrompt")
local function give()
	return lampRoot:FindFirstChild("DannyGive")
end
local function hiddenNow() -- (how many of the pieces' own prompts this client hides now)
	local _, muted = DannyOrders.prompts()
	local n = 0
	for _ in muted do
		n += 1
	end
	return n
end
M.resume()
check("9.0 the clipboard away: the pieces' own prompts as the server made them, no \"Give to Danny\" of ours", lampPick.MaxActivationDistance == REACH and give() == nil)
local sentBefore = #M.sent
clipboard(true)
local g = give()
check("9.0 the clipboard out (a computer): the Lamp's own Pick up hidden on this screen (its reach 0; Enabled, the server's, untouched)",
	lampPick.MaxActivationDistance == 0 and lampPick.Enabled == true and hiddenNow() == 1)
check("… a \"Give to Danny\" prompt of this client's in its place: E, the piece's name, the piece's own reach, no hold", g ~= nil and g.Enabled
	and g.ActionText == "Give to Danny" and g.ObjectText == "Lamp" and g.KeyboardKeyCode == M.Enum.KeyCode.E and g.MaxActivationDistance == REACH and g.HoldDuration == 0)
check("… the door's Enter house keeps its E (no piece's: doors, the van), another player's move's piece its Pick up, none of ours there",
	enter.MaxActivationDistance == 10 and strangerPick.MaxActivationDistance == REACH and strangerRoot:FindFirstChild("DannyGive") == nil)
check("… only on this screen: nothing asked of the server for it (another player's prompts are theirs)", #M.sent == sentBefore)
local fromMoving = #sentOn("Moving")
g.Triggered:Fire(M.player)
local moving = sentOn("Moving")
check("E (its Triggered): the click's request, the Lamp onto his list (\"helper\", \"assign\", the Lamp)", #moving == fromMoving + 1 and moving[#moving][1] == "helper"
	and moving[#moving][2] == "assign" and moving[#moving][3] == lamp)
lamp:SetAttribute("DannyQueue", 3) -- (the server's answer: #3 on his list)
M.resume()
check("… on his list: the same prompt says \"Take back\"", give() == g and g.Enabled and g.ActionText == "Take back", g.ActionText)
g.Triggered:Fire(M.player)
moving = sentOn("Moving")
check("… E again: the same request (the server takes it back)", #moving == fromMoving + 2 and moving[#moving][2] == "assign" and moving[#moving][3] == lamp)
lamp:SetAttribute("DannyQueue", nil)
M.resume()
check("… off his list: \"Give to Danny\" again", give() == g and g.ActionText == "Give to Danny")
rayHit = { Instance = lampRoot, Position = lampRoot.Position }
UIS.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.Unknown, UserInputType = M.Enum.UserInputType.MouseButton1, Position = M.Vector3.new(400, 236, 0) }, false)
moving = sentOn("Moving")
check("a click on the Lamp still gives it too", #moving == fromMoving + 3 and moving[#moving][3] == lamp)
rayHit = nil
attribute("MoveHelperQueue", Config.MoveHelper.Queue)
M.resume()
check("his list full: no prompt on the Lamp (red in the outline: nothing to press), its Pick up still hidden", give() == nil and lampPick.MaxActivationDistance == 0)
attribute("MoveHelperQueue", 2)
lampPick.Enabled = false
local inVan = M.make("WeldConstraint", { Part0 = vanBody, Part1 = lampRoot }, lampRoot)
M.resume()
check("in the van (its prompt off, welded to the van): no prompt (the van's Load keeps E)", give() == nil and lampPick.MaxActivationDistance == 0)
inVan.Parent = nil
lampPick.Enabled = true
lampRoot.Position = M.Vector3.new(Config.MoveHelper.Clipboard.PromptNear + 6, 1, 0)
M.resume()
check(`farther than Clipboard.PromptNear ({Config.MoveHelper.Clipboard.PromptNear} studs): none`, give() == nil)
lampRoot.Position = M.Vector3.new(4, 1, 2)
M.resume()
check("… near again: back, the same prompt (made once, moved round)", give() == g and #(DannyOrders.prompts()) == 1)
DannyOrders.covered = function()
	return true
end
M.resume()
check("a window covering the screen: ours parked (its E the window's), the Pick up still hidden", give() == nil and lampPick.MaxActivationDistance == 0)
DannyOrders.covered = nil
M.resume()
check("… shut: back", give() == g and g.Enabled)
gamepad = true
UIS.LastInputTypeChanged:Fire()
M.resume()
M.resume()
local padGive = lampRoot:FindFirstChild("GiveToDanny")
check("a gamepad: ours parked, MoveHelperCard's R1 \"Give to Danny\" on the nearest piece (one prompt, not two)", give() == nil and padGive ~= nil and padGive.Enabled
	and lampPick.MaxActivationDistance == 0)
gamepad = false
UIS.LastInputTypeChanged:Fire()
M.resume()
screen(true, 844, 354)
check("a phone: the prompt there to tap", give() == g and g.Enabled)
screen(false, 1280, 764)
clipboard(false)
check("the clipboard put away: the Lamp's own Pick up back at its reach exactly, ours parked", lampPick.MaxActivationDistance == REACH and give() == nil
	and hiddenNow() == 0)
clipboard(true)
check("(out again: hidden)", lampPick.MaxActivationDistance == 0 and give() == g)
local body1 = M.player.Character
local body2 = M.make("Model")
M.make("BasePart", { Name = "HumanoidRootPart", Position = M.Vector3.new(0, 0, 0) }, body2)
M.player.Character = body2
M.resume()
check("a new body (a respawn: no clipboard on it): given back, ours parked", lampPick.MaxActivationDistance == REACH and give() == nil)
M.player.Character = body1
body1:SetAttribute("ClipboardHeld", nil)
M.resume()
clipboard(true)
check("(out again: hidden)", lampPick.MaxActivationDistance == 0 and give() == g)
lamp:Destroy() -- (the move's end: the server takes its pieces away, ours on the Lamp with them, and the clipboard)
clipboard(false)
check("the move's end (the pieces gone, ours with them): nothing left hidden, no prompt kept", hiddenNow() == 0 and #(DannyOrders.prompts()) == 0
	and enter.MaxActivationDistance == 10)

check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL DANNY ORDERS CHECKS PASSED")
