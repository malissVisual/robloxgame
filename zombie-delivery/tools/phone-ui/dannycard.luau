-- 8.3 Danny for hire: his card (client/MoveHelperCard.luau: HIRE · $170 while he is for hire, CLEAR QUEUE once hired)
-- and his status line (client/MoveHelperHud.luau's strip once the card is there: "🧑‍🔧 DANNY · FOR HIRE" over the
-- price and HIRE $170; "🧑‍🔧 DANNY · 2 pieces to carry" over what he does and LIST; "⏳ WAITING FOR DANNY…" and STOP
-- while you wait for him), run for real on sandbox_mock.luau's recorder with client/TopBlocks.luau, beside the real
-- client/SandboxHud.luau (the money block) and client/SandboxTasksUi.luau (the TASKS chip), a stand-in move's panel (a
-- top block where MoveLayout.panel puts it) and Hud's groups where client/Hud.luau puts them, on a phone held sideways
-- (844 × 390: 844 × 354 under Roblox's top bar, the touch layout), a computer (1280 × 800) and a big screen
-- (1920 × 1080): nothing when Config.Sandbox.On is false; the status line under the panel, its words fitting, its button
-- a finger's size on a phone; HIRE on it opens the card (never a purchase at one tap); the card beside Danny's head on
-- the screen (right of it, else left of it: never on it), on the screen, clear of the HUD's chips, the move's panel and
-- status line, the touch buttons, the thumbstick and the jump button; for hire: "Hire Danny for this move · $170" and
-- HIRE · $170, its tap sending the Moving remote's ("helper", "hire") once and closing it; hired: his list in words, how
-- to give him pieces (a click, a tap, R1), CLEAR QUEUE (("helper", "clear")); its button a finger's size on a phone, its
-- words fitting; ✕, the gamepad's B, a tap beside it, closing it as ESC does, walking away from him and Danny gone close
-- it, a tap on it does not; a click (a tap) on him opens it; a click (a tap) on a piece of your move while he is hired
-- sends ("helper", "assign", its model), never while he is for hire, for another move's piece, with your hands full or
-- while a grip check shows; a gamepad: "Hire Danny" / "Talk to Danny" on him (L1), "Give to Danny" / "Take back from
-- Danny" on the nearest piece (R1); the wait: the line orange, STOP and G send ("helper", "stop"); a resize while open;
-- no warnings. 8.3 review: a tap beside the card fires Roblox's TouchTapInWorld too (tap()): it only closes the card
-- (no piece given, not open again); the gamepad's selection on ✕ once he is hired, kept inside the card, let go as it
-- closes when it drifted onto a chip or sits on nothing shown (another window's kept); opened from afar (LIST, a click
-- from ClickReach) it stays, closing CardSlack studs farther on; the line's words on every device ("tap STOP", "X:
-- stop", "G: stop"; "Carries what you tap / give him / click"); smaller phones (667 × 375, 740 × 360, 780 × 360): the
-- card beside his head, smaller, clear of the chips and the touch controls for his head anywhere over the middle.
-- 8.5 Danny's clipboard, orders mode (client/DannyOrders.luau started beside the card, as the game does): hired, the
-- line's button is 📋 ORDERS (his card a tap on the line), its words "Take out your clipboard (📋 / Q / R1) to give him
-- pieces"; his card's row 📋 CLIPBOARD beside CLEAR QUEUE (the Clipboard remote, the card closes), its words the
-- clipboard's; a click, a tap or R1 on a piece gives it to him only with the clipboard out (the server's ClipboardHeld
-- on your character): without it nothing, with it a click on Danny opens no card. (tools/phone-ui/dannyorders.luau:
-- the mode's line at the bottom and its touch 📋 button.)
-- `luau dannycard.luau -a dump` prints the preview's scenes as JSON instead (dannycard_preview.py).
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
	if processed ~= true then
		UIS.TouchTapInWorld:Fire(M.Vector2.new(x, y), false) -- (8.3 review: Roblox's for the same tap, as the finger lifts)
	end
end
local function click(x, y, processed)
	UIS.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.Unknown, UserInputType = M.Enum.UserInputType.MouseButton1, Position = M.Vector3.new(x, y, 0) }, processed == true)
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
-- title, the card's line or a button never.
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
-- A wrapped text's lines fit its label's height (its words broken at spaces, the mock's widths).
local function wrapFits(object)
	local b = box(object)
	local size = (object.TextSize or 14) * M.scaleOf(object)
	local lines, line = 1, ""
	for word in string.gmatch(object.Text, "%S+") do
		local try = if line == "" then word else line .. " " .. word
		if M.textWidth(try, size, object.Font) > b.x1 - b.x0 + 0.5 then
			lines += 1
			line = word
		else
			line = try
		end
	end
	return lines * size * 1.15 <= b.y1 - b.y0 + 0.5, `{lines} lines of {size} in {b.y1 - b.y0}`
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
UIS.GetMouseLocation = function() -- (8.5: client/DannyOrders.luau points where the mouse is)
	return M.Vector2.new(400, 236)
end
local make = M.make -- (a ProximityPrompt's Triggered: the gamepad's prompts)
M.make = function(class, props, parent)
	local made = make(class, props, parent)
	if class == "ProximityPrompt" then
		made.Triggered = M.signal()
	end
	return made
end
-- (the vector maths a ray needs, Instance.new's prompts, the world's ray, the camera's rays, the tags)
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
M.RaycastParams = { new = function()
	return {}
end }
local rayHit = nil -- what the next ray hits: { Instance, Position }
M.workspace.Raycast = function()
	return rayHit
end
local tagged = {} -- tag → its instances
M.services.CollectionService = { GetTagged = function(_, tag)
	return tagged[tag] or {}
end }
local gamepad = false
M.MUi.gamepadActive = function()
	return gamepad
end
-- (8.3 review: the gamepad's selection let go only inside the container given, as client/Ui.luau's gamepadRelease)
M.MUi.gamepadRelease = function(container)
	local selected = M.focus
	if selected and container and selected:IsDescendantOf(container) then
		M.focus = nil
	end
end
-- Danny's body in workspace.Npcs (his MoveHelper id, his root), your character's (sandbox_mock's: at 0, 0, 0)
local DANNY_ID = -2000000001
local npcs = M.make("Folder", { Name = "Npcs" }, M.workspace)
local body = M.make("Model", { Name = "Danny" }, npcs)
body:SetAttribute("MoveHelper", DANNY_ID)
local dannyRoot = M.make("BasePart", { Name = "HumanoidRootPart", Position = M.Vector3.new(8, 3, -6) }, body) -- (the recorder's IsA: its own class)
body.PrimaryPart = dannyRoot
-- a piece of your move (the attribute MoveSpot, its own Lift prompt tagged MovePrompt with the move's owner: you), one
-- of another move's
M.player:SetAttribute("MoveWith", 14)
local function piece(name, spot, owner, at)
	local model = M.make("Model", { Name = name }, M.workspace)
	model:SetAttribute("MoveSpot", spot)
	local root = M.make("BasePart", { Name = "Root", Position = at }, model)
	model.PrimaryPart = root
	local own = M.make("ProximityPrompt", { Name = "Pick", ActionText = "Pick up", ObjectText = name }, root)
	own:SetAttribute("MoveOwner", owner)
	tagged.MovePrompt = tagged.MovePrompt or {}
	table.insert(tagged.MovePrompt, own)
	return model, root
end
local lamp, lampRoot = piece("Lamp", 1, 14, M.Vector3.new(4, 1, 2))
local stranger, strangerRoot = piece("Vase", 1, 99, M.Vector3.new(-4, 1, 2))
local grip = require("./CarryGripUi")
-- the move's panel (client/MovingHud.luau's, a top block) where MoveLayout.panel puts it, and Hud's groups where
-- client/Hud.luau puts them (sandboxtasks.luau's boxes): a touch screen's left column (the cash, the minimap, the
-- health), a computer's health row at the bottom left and MOUSE [ALT] / the key hints at the top right
local TopBlocks = require("./TopBlocks")
local movingGui = M.make("ScreenGui", { Name = "MovingHud", DisplayOrder = 6 }, M.gui)
local panel = M.make("Frame", { Name = "MovePanel", BackgroundColor3 = M.MTheme.Contract.charcoal, BackgroundTransparency = 0.12 }, movingGui)
M.make("UICorner", { CornerRadius = M.UDim.new(0, 8) }, panel)
M.make("TextLabel", { Name = "Title", Text = "THE OLD CHALET · 14:52", TextSize = 14, Font = M.Enum.Font.GothamBold, TextColor3 = M.MTheme.Contract.text,
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
		out.ya = if p.TextYAlignment then p.TextYAlignment.Name else nil
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
attribute("MoveHelper", "offer")
check("Config.Sandbox.On false: MoveHelperCard.start() does nothing (no card, no prompt on him)", not MoveHelperCard.isOpen() and M.gui:FindFirstChild("MoveHelperCard") == nil
	and dannyRoot:FindFirstChild("TalkToDanny") == nil)
attribute("MoveHelper", nil)
Config.Sandbox.On = true

-- ── On: the HUD's chips, the status line for hire ──────────────────────────
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
local DannyOrders = require("./DannyOrders") -- 8.5: Danny's clipboard (the game starts it after the card)
DannyOrders.start()
local function clipboard(out) -- (the server's answer: your character's ClipboardHeld)
	M.player.Character:SetAttribute("ClipboardHeld", if out then true else nil)
end
attribute("MoveHelperId", DANNY_ID)
attribute("MoveHelperDoing", "Waiting by the van for hire")
attribute("MoveHelperPrice", 170)
attribute("MoveHelper", "offer")
M.flush()
local strip = MoveHelperHud.strip()
check("Danny for hire on your move: his status line (the strip), HIRE $170, orange", strip ~= nil and strip.Visible and named(strip, "Action").Visible
	and named(strip, "Action").Text == "HIRE $170" and named(strip, "Action").BackgroundColor3.R > 0.9)
check("… \"🧑‍🔧 DANNY · FOR HIRE\" over how a piece goes to him (8.5: the clipboard, a touch screen's 📋; the price HIRE's)", named(strip, "Title").Text == "🧑‍🔧 DANNY · FOR HIRE"
	and named(strip, "Doing").Text == "Take out your clipboard (📋) to give him pieces", named(strip, "Doing").Text)
local talk = dannyRoot:FindFirstChild("TalkToDanny")
check("the gamepad's prompt on his root: \"Hire Danny\" (ButtonL1), off without a gamepad", talk ~= nil and talk.ActionText == "Hire Danny"
	and talk.GamepadKeyCode == M.Enum.KeyCode.ButtonL1 and talk.Enabled == false)

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
	if withStrip and shown(strip) then -- (8.4: hidden while his card stands in for it on a small phone)
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
local function stripChecks(label, middle)
	local s = box(strip)
	local p = box(panel)
	check(`{label}: the status line right under the move's panel, on the screen`, s.y0 >= p.y1 - 0.5 and s.y0 - p.y1 < 12 and inside(s), `{show(p)} / {show(s)}`)
	local clear, why = clearOfAll(s, false)
	check(`{label}: … clear of the touch controls, Hud's groups and the chips`, clear, why)
	if middle then
		check(`{label}: … 8.4: in the middle under the panel as before (nothing in its way)`, math.abs((s.x0 + s.x1) / 2 - M.width / 2) < 1
			and math.abs(s.x0 - p.x0) < 1 and math.abs(s.x1 - p.x1) < 1, `{show(p)} / {show(s)}`)
	end
	check(`{label}: … its words fit (what he does may be cut with "…")`, #badTexts(strip) == 0, badTexts(strip)[1])
	if M.touch then
		check(`{label}: … its button a finger's size`, #smallButtons(strip) == 0, smallButtons(strip)[1])
	end
end
local function cardChecks(label, head, hired)
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
	local main = named(card, "Main")
	local clip = named(card, "Clip")
	if hired then
		check(`{label}: … hired: his list in words, how to give him pieces (8.5: the clipboard), CLEAR QUEUE`, named(card, "Line").Text == "2 pieces to carry"
			and string.find(named(card, "Hint").Text, "give it to him", 1, true) ~= nil and string.find(named(card, "Hint").Text, "📋 Clipboard out", 1, true) == 1
			and main.Text == "CLEAR QUEUE", named(card, "Hint").Text)
		local cb, mb = box(clip), box(main)
		check(`{label}: … 8.5 📋 CLIPBOARD (orange) left of CLEAR QUEUE, side by side in the card, never on each other`, shown(clip) and clip.Text == "📋 CLIPBOARD"
			and clip.BackgroundColor3.R > 0.9 and not overlap(cb, mb) and cb.x1 <= mb.x0 and math.abs(cb.y0 - mb.y0) < 0.5 and cb.x0 >= c.x0 and mb.x1 <= c.x1,
			`{show(cb)} / {show(mb)}`)
	else
		check(`{label}: … for hire: "Hire Danny for this move · $170", HIRE · $170 (orange), no clipboard yet`, named(card, "Line").Text == "Hire Danny for this move · $170"
			and main.Text == "HIRE · $170" and main.BackgroundColor3.R > 0.9 and not shown(clip), main.Text)
	end
	check(`{label}: … its words fit`, #badTexts(card) == 0, badTexts(card)[1])
	local fits, lines = wrapFits(named(card, "Hint"))
	check(`{label}: … its hint fits its lines`, fits, lines)
	if M.touch then
		check(`{label}: … every button a finger's size (its button, ✕)`, #smallButtons(card) == 0, smallButtons(card)[1])
	end
	if hired then
		check(`{label}: … the gamepad's selection on ✕ (8.3 review: an A by habit never clears his list), kept inside the card`, M.focus == named(card, "Close")
			and card.SelectionGroup == true and card.SelectionBehaviorUp.Name == "Stop" and card.SelectionBehaviorDown.Name == "Stop"
			and card.SelectionBehaviorLeft.Name == "Stop" and card.SelectionBehaviorRight.Name == "Stop")
	else
		check(`{label}: … the gamepad's selection on its button (HIRE), kept inside the card`, M.focus == main and card.SelectionGroup == true)
	end
end

-- ── The phone: for hire ─────────────────────────────────────────────────────
stripChecks("844 x 390, for hire", true)
scene("danny-status-hire-phone", nil)
local before = #sentOn("Moving")
press(named(strip, "Action"))
M.flush()
check("HIRE $170 on the line opens his card (\"MoveHelperCard\", over the HUD), nothing bought at one tap", MoveHelperCard.isOpen() and M.gui:FindFirstChild("MoveHelperCard") ~= nil
	and M.gui:FindFirstChild("MoveHelperCard").DisplayOrder > M.gui:FindFirstChild("MoveHelperHud").DisplayOrder and #sentOn("Moving") == before)
check("… \"🧑‍🔧 DANNY\" and his status (for hire, the price)", named(MoveHelperCard.card(), "Title").Text == "🧑‍🔧 DANNY"
	and named(MoveHelperCard.card(), "Doing").Text == "For hire · $170 this move")
cardChecks("844 x 390, for hire (his head off the screen)", nil, false)
check("8.4: … his status line stays with the card open (nothing in its way at 844 px: in the middle as before)", shown(strip))
MoveHelperCard.close()
local heads = { { x = 422, y = 170 }, { x = 760, y = 120 }, { x = 200, y = 120 }, { x = 560, y = 250 } }
for index, head in heads do
	MoveHelperCard.open(head)
	M.flush()
	cardChecks(`844 x 390, for hire, a tap on him at {head.x},{head.y}`, head, false)
	if index == 1 then
		scene("danny-card-hire-phone", head)
	end
	MoveHelperCard.close()
end
MoveHelperCard.open(heads[1])
before = #sentOn("Moving")
press(named(MoveHelperCard.card(), "Main"))
press(named(MoveHelperCard.card(), "Main"))
local sent = sentOn("Moving")
check("HIRE · $170: the Moving remote's (\"helper\", \"hire\") once (the card closes at the first tap; the server checks the money)", #sent == before + 1
	and sent[#sent][1] == "helper" and sent[#sent][2] == "hire" and not MoveHelperCard.isOpen())
-- a tap on a piece while he is for hire: nothing (his list is for a hired Danny)
rayHit = { Instance = lampRoot, Position = lampRoot.Position }
before = #sentOn("Moving")
UIS.TouchTapInWorld:Fire(M.Vector2.new(400, 200), false)
check("for hire: a tap on a piece of your move sends nothing", #sentOn("Moving") == before and not MoveHelperCard.isOpen())

-- ── The phone: hired ────────────────────────────────────────────────────────
attribute("MoveHelperPrice", nil)
attribute("MoveHelperQueue", 2)
attribute("MoveHelperDoing", "Carrying the Lamp to the van")
attribute("MoveHelper", "hired")
M.flush()
check("the server's answer (MoveHelper = hired): \"🧑‍🔧 DANNY · 2 pieces to carry\" over what he does, 8.5 📋 ORDERS (not lit)", named(strip, "Title").Text == "🧑‍🔧 DANNY · 2 pieces to carry"
	and named(strip, "Doing").Text == "Carrying the Lamp to the van" and named(strip, "Action").Text == "📋 ORDERS" and named(strip, "Action").BackgroundColor3.R < 0.5,
	named(strip, "Action").Text)
check("… the gamepad's prompt on him: \"Talk to Danny\"", talk.ActionText == "Talk to Danny")
stripChecks("844 x 390, hired", true)
scene("danny-status-hired-phone", nil)
before = #sentOn("Clipboard")
press(named(strip, "Action"))
sent = sentOn("Clipboard")
check("8.5 📋 ORDERS asks for the clipboard (the Clipboard remote's true; the server decides), no card", #sent == before + 1 and sent[#sent][1] == true and not MoveHelperCard.isOpen())
clipboard(true)
M.resume()
check("… the clipboard out (ClipboardHeld): 📋 PUT AWAY, orange", named(strip, "Action").Text == "📋 PUT AWAY" and named(strip, "Action").BackgroundColor3.R > 0.9,
	named(strip, "Action").Text)
stripChecks("844 x 390, the clipboard out", true)
press(named(strip, "Action"))
sent = sentOn("Clipboard")
check("… 📋 PUT AWAY asks to put it away (false)", #sent == before + 2 and sent[#sent][1] == false)
clipboard(false)
M.resume()
check("… away: 📋 ORDERS again", named(strip, "Action").Text == "📋 ORDERS")
attribute("MoveHelperQueue", 0)
check("8.5 his list empty, the clipboard away: the line says how (\"Take out your clipboard (📋) to give him pieces\")",
	named(strip, "Doing").Text == "Take out your clipboard (📋) to give him pieces" and named(strip, "Title").Text == "🧑‍🔧 DANNY · Nothing to carry", named(strip, "Doing").Text)
attribute("MoveHelperQueue", 2)
press(named(strip, "StatusTap"))
M.flush()
check("a tap on the line opens his card (LIST's): his status (2 pieces to carry · what he does)", MoveHelperCard.isOpen()
	and named(MoveHelperCard.card(), "Doing").Text == "2 pieces to carry · Carrying the Lamp to the van")
check("… a touch screen's words: \"📋 Clipboard out: tap a piece to give it to him, again to take it back.\"", named(MoveHelperCard.card(), "Hint").Text
	== "📋 Clipboard out: tap a piece to give it to him, again to take it back.", named(MoveHelperCard.card(), "Hint").Text)
MoveHelperCard.close()
for index, head in heads do
	MoveHelperCard.open(head)
	M.flush()
	cardChecks(`844 x 390, hired, a tap on him at {head.x},{head.y}`, head, true)
	if index == 1 then
		scene("danny-card-hired-phone", head)
	end
	MoveHelperCard.close()
end
MoveHelperCard.open(heads[1])
before = #sentOn("Moving")
press(named(MoveHelperCard.card(), "Main"))
sent = sentOn("Moving")
check("CLEAR QUEUE: (\"helper\", \"clear\") once, the card closes", #sent == before + 1 and sent[#sent][2] == "clear" and not MoveHelperCard.isOpen())
MoveHelperCard.open(heads[1])
before = #sentOn("Clipboard")
press(named(MoveHelperCard.card(), "Clip"))
press(named(MoveHelperCard.card(), "Clip"))
sent = sentOn("Clipboard")
check("8.5 📋 CLIPBOARD on his card: the Clipboard remote's true once (the card closes at the first tap)", #sent == before + 1 and sent[#sent][1] == true and not MoveHelperCard.isOpen())
clipboard(true)
MoveHelperCard.open(heads[1])
check("… the clipboard out: his card's button says 📋 PUT AWAY, its words fit", named(MoveHelperCard.card(), "Clip").Text == "📋 PUT AWAY"
	and #badTexts(MoveHelperCard.card()) == 0, named(MoveHelperCard.card(), "Clip").Text)
press(named(MoveHelperCard.card(), "Clip"))
sent = sentOn("Clipboard")
check("… and puts it away (false)", #sent == before + 2 and sent[#sent][1] == false and not MoveHelperCard.isOpen())
clipboard(false)
-- closing
MoveHelperCard.open(heads[1])
press(named(MoveHelperCard.card(), "Close"))
check("✕ closes it", not MoveHelperCard.isOpen() and not MoveHelperCard.card().Visible)
MoveHelperCard.open(heads[1])
key("ButtonB")
check("the gamepad's B closes it", not MoveHelperCard.isOpen())
MoveHelperCard.open(heads[1])
local c = box(MoveHelperCard.card())
tap((c.x0 + c.x1) / 2, (c.y0 + c.y1) / 2, true)
check("a tap on it (the game's: its buttons) keeps it open", MoveHelperCard.isOpen())
-- 8.3 review: the tap beside it ends in Roblox's TouchTapInWorld as the finger lifts (tap() fires both), on a piece of
-- your move or on him: it only closes the card
before = #sentOn("Moving")
rayHit = { Instance = lampRoot, Position = lampRoot.Position }
tap(math.max(4, c.x0 - 30), math.min(M.height - 4, c.y1 + 20), false)
check("a tap beside it closes it (8.3 review: its TouchTapInWorld on a piece of your move gives him nothing)", not MoveHelperCard.isOpen()
	and #sentOn("Moving") == before, #sentOn("Moving") - before)
MoveHelperCard.open(heads[1])
rayHit = { Instance = dannyRoot, Position = dannyRoot.Position }
tap(math.max(4, c.x0 - 30), math.min(M.height - 4, c.y1 + 20), false)
check("… a tap beside it on Danny himself closes it (not open again at once)", not MoveHelperCard.isOpen() and #sentOn("Moving") == before)
M.now += 1 -- (the swallowed moment over: a tap in the world is one again)
rayHit = nil
MoveHelperCard.open(heads[1])
MoveHelperCard.close() -- (ESC: client/Main.client.luau's Hud.onCloseWindows closes every window)
check("ESC (the windows' close) closes it", not MoveHelperCard.isOpen())
-- 8.3 review: the gamepad's selection as it closes: let go when it drifted onto a HUD chip or sits on nothing shown,
-- kept when another window (opening over it) has it
MoveHelperCard.open(heads[1])
M.focus = chip
MoveHelperCard.close()
check("8.3 review: a selection drifted onto the TASKS chip is let go as the card closes (the chips' D-pad needs none)", M.focus == nil)
local hiddenFrame = M.make("Frame", { Name = "Gone", Visible = false }, M.make("ScreenGui", { Name = "SomethingShut" }, M.gui))
local gone = M.make("TextButton", { Name = "GoneButton" }, hiddenFrame)
MoveHelperCard.open(heads[1])
M.focus = gone
MoveHelperCard.close()
check("… one on something hidden too", M.focus == nil)
local other = M.make("TextButton", { Name = "OtherWindowButton" }, M.make("Frame", { Name = "OtherWindow" }, M.make("ScreenGui", { Name = "OtherWindowGui" }, M.gui)))
MoveHelperCard.open(heads[1])
M.focus = other
MoveHelperCard.close()
check("… one in another window (it opened over the card) stays that window's", M.focus == other)
M.focus = nil
MoveHelperCard.open(heads[1])
dannyRoot.Position = M.Vector3.new(Config.MoveHelper.CardReach + 20, 3, 0)
M.resume()
check("walking away from him (CardReach studs) closes it", not MoveHelperCard.isOpen())
dannyRoot.Position = M.Vector3.new(8, 3, -6)
MoveHelperCard.open(heads[1])
attribute("MoveHelper", nil)
check("Danny gone (off your move): it closes, the line goes", not MoveHelperCard.isOpen() and not strip.Visible)
attribute("MoveHelper", "hired")
-- 8.3 review: opened from afar (the status line's LIST opens it from anywhere; a click reaches ClickReach studs) it
-- stays open; it closes once you are CardSlack studs farther from him than you were as it opened
local far = Config.MoveHelper.ClickReach + 30
dannyRoot.Position = M.Vector3.new(far, 3, 0)
press(named(strip, "StatusTap")) -- (8.5: the line's tap is LIST's, its button 📋 ORDERS)
M.resume()
M.resume()
check(`8.3 review: a tap on the line with Danny {far} studs off opens his card and it stays (never a flash and gone)`, MoveHelperCard.isOpen())
dannyRoot.Position = M.Vector3.new(far + Config.MoveHelper.CardSlack - 5, 3, 0)
M.resume()
check("… a few steps farther from him: still open", MoveHelperCard.isOpen())
dannyRoot.Position = M.Vector3.new(far + Config.MoveHelper.CardSlack + 5, 3, 0)
M.resume()
check("… CardSlack studs farther than as it opened: it closes", not MoveHelperCard.isOpen())
dannyRoot.Position = M.Vector3.new(Config.MoveHelper.ClickReach - 5, 3, 0)
rayHit = { Instance = dannyRoot, Position = dannyRoot.Position }
click(400, 200, false)
M.resume()
M.resume()
check("… a click on him from near ClickReach studs: his card opens and stays (CardReach at least ClickReach)", MoveHelperCard.isOpen()
	and Config.MoveHelper.CardReach >= Config.MoveHelper.ClickReach)
MoveHelperCard.close()
rayHit = nil
dannyRoot.Position = M.Vector3.new(8, 3, -6)

-- ── Clicks and taps in the world ────────────────────────────────────────────
-- 8.5 orders mode: without the clipboard out a click or a tap on a piece is nothing to him (no stray orders)
before = #sentOn("Moving")
rayHit = { Instance = lampRoot, Position = lampRoot.Position }
UIS.TouchTapInWorld:Fire(M.Vector2.new(400, 200), false)
click(400, 200, false)
check("8.5 hired, the clipboard away: a tap or a click on a piece of your move sends nothing (no stray orders), no card", #sentOn("Moving") == before
	and not MoveHelperCard.isOpen())
clipboard(true)
UIS.TouchTapInWorld:Fire(M.Vector2.new(400, 200), false)
sent = sentOn("Moving")
check("8.5 the clipboard out: a tap on a piece of your move sends (\"helper\", \"assign\", its model)", #sent == before + 1 and sent[#sent][1] == "helper"
	and sent[#sent][2] == "assign" and sent[#sent][3] == lamp and not MoveHelperCard.isOpen())
check("… the tapped piece is the one client/DannyOrders.luau outlines a moment", MoveHelperCard.tapped() == lamp)
click(400, 200, false)
sent = sentOn("Moving")
check("… a click (a computer) too", #sent == before + 2 and sent[#sent][3] == lamp)
click(400, 200, true)
check("… not a click the game took (a button)", #sentOn("Moving") == before + 2)
rayHit = { Instance = strangerRoot, Position = strangerRoot.Position }
click(400, 200, false)
check("… another move's piece: nothing", #sentOn("Moving") == before + 2 and stranger ~= nil)
rayHit = { Instance = lampRoot, Position = lampRoot.Position }
grip.open = true
click(400, 200, false)
check("… while a grip check shows (its press is the click): nothing", #sentOn("Moving") == before + 2)
grip.open = false
M.player.Character:SetAttribute("Carrying", "crate")
click(400, 200, false)
check("… your hands full: nothing", #sentOn("Moving") == before + 2)
M.player.Character:SetAttribute("Carrying", nil)
attribute("MoveHelperCall", "Sofa")
click(400, 200, false)
check("… while you wait for him: nothing", #sentOn("Moving") == before + 2)
attribute("MoveHelperCall", nil)
rayHit = { Instance = dannyRoot, Position = dannyRoot.Position }
click(400, 200, false)
check("8.5 the clipboard out: a click on him opens no card (orders only: nothing else fires), sends nothing", not MoveHelperCard.isOpen() and #sentOn("Moving") == before + 2)
clipboard(false)
click(400, 200, false)
check("the clipboard away: a click on him opens his card (sends nothing)", MoveHelperCard.isOpen() and #sentOn("Moving") == before + 2)
MoveHelperCard.close()
rayHit = nil

-- ── A gamepad: "Give to Danny" on the nearest piece ─────────────────────────
gamepad = true
UIS.LastInputTypeChanged:Fire()
local give = lampRoot:FindFirstChild("GiveToDanny")
check("8.5 a gamepad, the clipboard away: no \"Give to Danny\" (R1 takes the clipboard out instead), \"Talk to Danny\" on him on", (give == nil or not give.Enabled) and talk.Enabled)
clipboard(true)
M.resume()
give = lampRoot:FindFirstChild("GiveToDanny")
check("a gamepad, 8.5 the clipboard out: \"Give to Danny\" on the nearest piece of your move (R1, its name), \"Talk to Danny\" on him on", give ~= nil and give.Enabled
	and give.ActionText == "Give to Danny" and give.ObjectText == "Lamp" and give.GamepadKeyCode == M.Enum.KeyCode.ButtonR1 and talk.Enabled
	and strangerRoot:FindFirstChild("GiveToDanny") == nil and MoveHelperCard.giveTarget() == lamp)
before = #sentOn("Moving")
give.Triggered:Fire()
sent = sentOn("Moving")
check("… R1: (\"helper\", \"assign\", the piece)", #sent == before + 1 and sent[#sent][2] == "assign" and sent[#sent][3] == lamp)
lamp:SetAttribute("DannyQueue", 1)
M.resume()
check("… a piece of his list: \"Take back from Danny\"", give.ActionText == "Take back from Danny")
attribute("MoveHelper", "offer")
M.resume()
check("… for hire: no \"Give to Danny\"; \"Hire Danny\" on him", not give.Enabled and talk.ActionText == "Hire Danny")
attribute("MoveHelper", "hired")
lamp:SetAttribute("DannyQueue", nil)
M.resume()
check("… hired again: on again (the clipboard still out)", give.Enabled)
clipboard(false)
M.resume()
check("8.5 … the clipboard put away: off (no stray order from R1)", not give.Enabled)
before = #sentOn("Moving")
give.Triggered:Fire()
check("… its R1 then (a press already on its way): nothing sent", #sentOn("Moving") == before)
gamepad = false
UIS.LastInputTypeChanged:Fire()
check("… no gamepad: off", not give.Enabled and not talk.Enabled)

-- ── The wait: you called him to a two-person piece ──────────────────────────
attribute("MoveHelperCall", "Sofa")
attribute("MoveHelperDoing", "Coming to lift the Sofa with you")
M.flush()
check("8.3 you wait for him: the line orange, \"⏳ WAITING FOR DANNY…\", STOP (8.3 review: a touch screen's words, \"tap STOP\")", strip.BackgroundColor3.R > 0.9
	and named(strip, "Title").Text == "⏳ WAITING FOR DANNY…" and named(strip, "Doing").Text == "Stay at your end of the Sofa · tap STOP" and named(strip, "Action").Text == "STOP",
	named(strip, "Doing").Text)
stripChecks("844 x 390, waiting", true)
scene("danny-waiting-phone", nil)
attribute("MoveHelperReady", true)
check("… he is at its other end (MoveHelperReady: your lift check open): \"💪 ON THREE… LIFT!\", STOP still", named(strip, "Title").Text == "💪 ON THREE… LIFT!"
	and named(strip, "Doing").Text == "Danny is at the other end of the Sofa · tap STOP" and named(strip, "Action").Text == "STOP", named(strip, "Doing").Text)
stripChecks("844 x 390, ready", true)
-- 8.3 review: the words of the device used now, again when it changes (a gamepad picked up, the keys)
gamepad = true
UIS.LastInputTypeChanged:Fire()
check("8.3 review: a gamepad: he is there, the line says where he is (no key: the lift's own check is up)", named(strip, "Doing").Text == "Danny is at the other end of the Sofa",
	named(strip, "Doing").Text)
attribute("MoveHelperReady", nil)
check("… while he comes: the piece's \"Stop waiting\" prompt's button (X: stop)", named(strip, "Doing").Text == "Stay at your end of the Sofa · X: stop", named(strip, "Doing").Text)
gamepad = false
M.touch = false
UIS.LastInputTypeChanged:Fire()
check("… a computer: G: stop", named(strip, "Doing").Text == "Stay at your end of the Sofa · G: stop", named(strip, "Doing").Text)
M.touch = true
UIS.LastInputTypeChanged:Fire()
check("… the screen touched again: tap STOP", named(strip, "Doing").Text == "Stay at your end of the Sofa · tap STOP", named(strip, "Doing").Text)
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
check("the wait over: 📋 ORDERS again (8.5), the line charcoal", named(strip, "Action").Text == "📋 ORDERS" and strip.BackgroundColor3.R < 0.2)

-- ── 8.3 review: smaller phones (667 × 375, 740 × 360, 780 × 360) ───────────
-- The card shrinks until a place beside him is clear (its button and ✕ still a finger's size) and never reaches over
-- the touch controls at the right; Danny's head about the screen's middle (where the review saw the card over DRAW at
-- 740 and 780). Every head spot over the middle: a clear card, never on him (at 667 a few leave no room within 120 px
-- of him: the clear place nearest him then).
for _, size in { { 667, 339, "667" }, { 740, 324, "740" }, { 780, 324, "780" } } do
	screen(true, size[1], size[2])
	local label = `{size[1]} x {size[2] + 36}`
	for _, hired in { false, true } do
		attribute("MoveHelperPrice", if hired then nil else 170)
		attribute("MoveHelper", if hired then "hired" else "offer")
		local state = if hired then "hired" else "for hire"
		-- 8.4: Danny's status line itself (it lay on the TASKS chip and the money block at 667 × 375)
		M.flush()
		stripChecks(`{label}, {state}`)
		local sb, p = box(strip), box(panel)
		check(`{label}, {state}: … 8.4 off the 📋 TASKS chip and the money block, shifted right just past them (still under the panel)`,
			not overlap(sb, box(chip)) and not overlap(sb, box(SandboxHud.block())) and sb.x0 > p.x0 and sb.x0 < p.x1 and sb.x1 <= M.width - 8 + 0.5,
			`{show(sb)} / {show(box(chip))} / {show(box(SandboxHud.block()))}`)
		if hired then
			scene(`danny-status-hired-{size[3]}`, nil)
		end
		MoveHelperCard.open({ x = math.floor(size[1] * 0.5), y = math.floor(size[2] * 0.6) })
		M.flush()
		check(`{label}, {state}: … 8.4 his card open: the line, moved off the middle, gives it its room (hidden, no top block)`, not shown(strip)
			and not overlap(box(MoveHelperCard.card()), box(chip)))
		MoveHelperCard.close()
		M.flush()
		check(`{label}, {state}: … the card shut: the line back where it was`, shown(strip) and show(box(strip)) == show(sb))
		local spots, bad = 0, nil
		for fx = 0.2, 0.86, 0.05 do
			for fy = 0.2, 0.86, 0.05 do
				local head = { x = math.floor(size[1] * fx), y = math.floor(size[2] * fy) }
				MoveHelperCard.open(head)
				M.flush()
				local b = box(MoveHelperCard.card())
				local clear, why = clearOfAll(b, true)
				local onHim = head.x > b.x0 and head.x < b.x1 and head.y > b.y0 and head.y < b.y1
				spots += 1
				if not bad and (not clear or onHim or not inside(b) or #smallButtons(MoveHelperCard.card()) > 0) then
					bad = `{head.x},{head.y}: {show(b)} {why or (if onHim then "on him" else "off the screen or a button too small")}`
				end
				MoveHelperCard.close()
			end
		end
		check(`{label}, {state}: Danny's head at {spots} spots over the screen's middle: the card clear of the touch controls, Hud's groups, the chips, the move's panel and Danny's status line, on the screen, never on him, its buttons a finger's size`,
			bad == nil, bad)
		for index, at in { { 0.5, 0.5 }, { 0.4, 0.6 }, { 0.55, 0.45 }, { 0.35, 0.4 }, { 0.65, 0.55 }, { 0.5, 0.3 } } do
			local head = { x = math.floor(size[1] * at[1]), y = math.floor(size[2] * at[2]) }
			MoveHelperCard.open(head)
			M.flush()
			cardChecks(`{label}, {state}, a tap on him at {head.x},{head.y}`, head, hired)
			if index == 1 and hired then
				scene(`danny-card-hired-{size[3]}`, head)
			end
			MoveHelperCard.close()
		end
		MoveHelperCard.open(nil)
		M.flush()
		cardChecks(`{label}, {state} (his head off the screen)`, nil, hired)
		MoveHelperCard.close()
	end
end

-- ── A computer (1280 × 800) and a big screen (1920 × 1080) ─────────────────
for _, size in { { 1280, 764, "computer" }, { 1920, 1044, "big" } } do
	screen(false, size[1], size[2])
	local label = `{size[1]} x {size[2] + 36}`
	for _, hired in { false, true } do
		attribute("MoveHelperPrice", if hired then nil else 170)
		attribute("MoveHelper", if hired then "hired" else "offer")
		local state = if hired then "hired" else "for hire"
		stripChecks(`{label}, {state}`, true)
		if not hired then
			check(`{label}: a computer's words on the line (8.5): "Take out your clipboard (Q) to give him pieces"`, named(strip, "Doing").Text == "Take out your clipboard (Q) to give him pieces", named(strip, "Doing").Text)
			gamepad = true
			UIS.LastInputTypeChanged:Fire()
			check(`{label}: … a gamepad's: "(R1)"`, named(strip, "Doing").Text == "Take out your clipboard (R1) to give him pieces", named(strip, "Doing").Text)
			gamepad = false
			UIS.LastInputTypeChanged:Fire()
		end
		for index, head in { { x = size[1] * 0.5, y = size[2] * 0.42 }, { x = size[1] * 0.85, y = size[2] * 0.5 }, { x = size[1] * 0.3, y = size[2] * 0.12 } } do
			MoveHelperCard.open(head)
			M.flush()
			cardChecks(`{label}, {state}, a click on him at {math.floor(head.x)},{math.floor(head.y)}`, head, hired)
			if index == 1 then
				scene(`danny-card-{if hired then "hired" else "hire"}-{size[3]}`, head)
			end
			MoveHelperCard.close()
		end
	end
	MoveHelperCard.open({ x = size[1] * 0.5, y = size[2] * 0.42 })
	check(`{label}: a computer's words (8.5): "📋 Clipboard out (Q): click a piece to give it to him …"`, string.find(named(MoveHelperCard.card(), "Hint").Text,
		"📋 Clipboard out (Q): click a piece to give it to him", 1, true) == 1, named(MoveHelperCard.card(), "Hint").Text)
	MoveHelperCard.close()
end

-- ── A resize while it is open ───────────────────────────────────────────────
MoveHelperCard.open({ x = 640, y = 320 })
screen(true, 844, 354)
cardChecks("a resize to a phone while open: placed again for it", nil, true)
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
