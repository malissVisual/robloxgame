-- 8.1 grip: the carry's timing check on a phone held sideways (844 × 390: 844 × 354 under Roblox's top bar), two more
-- touch screens and a computer, run for real on tools/phone-ui/missions_mock.luau's recorder (the folder:
-- tools/phone-ui/carrygripenv.py): client/CarryGripUi.luau (with client/MoveLayout.luau, client/TopBlocks.luau,
-- client/TouchLayout.luau and shared/CarryGrip.luau) beside the move's own pieces (client/MovingHud.luau's panel,
-- client/MoveHelperHud.luau's strip, client/QuickChat.luau's 💬 button), the sandbox's guide line (a stand-in in
-- TopBlocks, under them) and the HUD's groups where client/Hud.luau puts them (the actions' row, FIRE, the right
-- column, the bottom bar, the contextual action: TouchLayout's own boxes). Like movehud.luau it lays out what the
-- modules made (Position, Size, AnchorPoint, UIScale) and asserts: the widget and the round GRIP button (80 px and more)
-- on the screen, clear of the touch buttons, the thumbstick's corner, the jump button, the move's panel and strip, the
-- guide line, the 💬 button, the HUD's groups and each other; nothing shows without a check; the server's ("grip",
-- "open") shows one (GET A GRIP! / WOBBLE! / WOBBLE! MISS = DROP, the piece, the zone where the check has it, the needle
-- sweeping); one press (the GRIP button, a tap on the widget, the left mouse button, F; not a click the GUI took) sends
-- ("grip", id, "ok" | "miss", its time) once, the needle stops; no press: ("grip", id, "miss") at the window's end; the
-- outcomes (BALANCED!, SLIPPED BACK! with furniture_putdown, STAGGER! with grip_warning, DROPPED! with the real
-- client/MoveSounds.luau's grip_slip and no heavy_drop for the drop's damage), a miss shakes it and the camera; it goes
-- Ui.Linger s after; a "close" takes it off; a door's fade hides it (no press then); an older check's outcome is
-- ignored; the first Ui.Tutorial checks say "… when the needle is in the green"; no warnings.
-- 8.3 keys (shared/SandboxPad.luau, client/PadGlyph.luau): the press in the words of the device used now: a phone's
-- "Tap GRIP", a computer's "Press LMB / F", a gamepad's "Press R2" with R2's glyph at the top right (only while the
-- check waits; none when the platform gives no picture), a phone with a gamepad used last the gamepad's; SLIPPED BACK!'s
-- "try again" (a phone: the prompt is tapped), "(E)", "(X)"; a gamepad picked up or put down mid-check: the words and
-- the glyph follow at once.
-- CarryGripUi's and MoveSounds' os.clock is this check's M.clock (mock.os): a frame moves it on by its dt.
-- `luau carrygrip.luau -a dump` prints the preview's scenes instead (tools/phone-ui/carrygrip_preview.py).
local dump = select(1, ...) == "dump"
local M = require("./missions_mock")
M.clock = 500
M.os = setmetatable({ clock = function()
	return M.clock
end }, { __index = os })

-- ── The stand-ins (as movehud.luau's) ───────────────────────────────────────
local v2 = {}
v2.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y)
	end
	return nil
end
v2.__add = function(a, b)
	return M.Vector2.new(a.X + b.X, a.Y + b.Y)
end
v2.__sub = function(a, b)
	return M.Vector2.new(a.X - b.X, a.Y - b.Y)
end
M.Vector2.new = function(x, y)
	return setmetatable({ X = x or 0, Y = y or 0, kind = "Vector2" }, v2)
end
M.Vector2.zero = M.Vector2.new(0, 0)
local function signal()
	return M.signal()
end
M.services.CollectionService = {
	GetTagged = function()
		return {}
	end,
	GetInstanceAddedSignal = function()
		return signal()
	end,
	GetInstanceRemovedSignal = function()
		return signal()
	end,
	HasTag = function()
		return false
	end,
}
M.services.ProximityPromptService = { PromptShown = signal() }
M.services.UserInputService.InputEnded = signal()
M.services.UserInputService.WindowFocusReleased = signal()
M.services.UserInputService.GetMouseLocation = function()
	return M.Vector2.new(M.width / 2, M.height / 2)
end
M.services.RunService.RenderStepped = signal()
M.services.GuiService.GetGuiInset = function()
	return M.Vector2.new(0, 0)
end
M.services.GuiService.ReducedMotionEnabled = false
M.services.Players.GetPlayers = function()
	return { M.player }
end
M.services.Players.GetPlayerByUserId = function(_, id)
	return if id == M.player.UserId then M.player else nil
end
M.player.CharacterAdded = signal()
M.scale = 1
M.MUi.closeButton = M.Ui.closeButton
M.MUi.screenScale = function()
	return M.scale
end
M.MUi.screenSize = function()
	return M.Vector2.new(M.width, M.height)
end
M.MUi.touchLayout = function()
	return M.touch
end
M.gamepad = false
M.MUi.gamepadActive = function()
	return M.gamepad
end
-- 8.3 keys: the last input's type changing (client/PadGlyph.luau watch), the platform's picture of a button
-- (M.padImages false: none)
M.services.UserInputService.LastInputTypeChanged = M.signal()
M.padImages = true
M.services.UserInputService.GetImageForKeyCode = function(_, key)
	return if M.padImages and key then "rbxasset://textures/ui/Controls/" .. key.Name .. ".png" else ""
end
local function useGamepad(on)
	M.gamepad = on
	M.services.UserInputService.LastInputTypeChanged:Fire(if on then M.Enum.UserInputType.Gamepad1 else M.Enum.UserInputType.Keyboard)
end
M.MUi.MinTouch = 44
M.MTheme.PanelTransparency = 0.12
M.MTheme.WindowTransparency = 0.02
M.MKeys = { open = function() end, close = function() end, isOpen = function()
	return false
end, hint = function()
	return "SPACE"
end }
M.MFade = { out = function() end, into = function() end }
M.MapView.waypointAt = function()
	return M.waypoint
end
M.MapView.onWaypoint = function() end
M.played = {}
M.Sounds.play = function(name)
	table.insert(M.played, name)
end
M.shakes = {}
M.MCamera = { shake = function(amount)
	table.insert(M.shakes, amount)
end }
local camera = M.workspace.CurrentCamera
local function played(name)
	local count = 0
	for _, n in M.played do
		count += if n == name then 1 else 0
	end
	return count
end

-- ── A layout: where a recorded piece sits (px from the screen's top left) ──
local function uiScale(object)
	for _, child in object:GetChildren() do
		if child.ClassName == "UIScale" then
			return child.Scale or 1
		end
	end
	return 1
end
local function layout(object)
	local class = object.ClassName
	if class == "ScreenGui" or class == "PlayerGui" or object.Parent == nil then
		return 0, 0, M.width, M.height, 1
	end
	local px, py, pw, ph, inherited = layout(object.Parent)
	local own = uiScale(object)
	local size = object.Size or M.UDim2.new()
	local w = (pw * size.X.Scale + size.X.Offset * inherited) * own
	local h = (ph * size.Y.Scale + size.Y.Offset * inherited) * own
	local position = object.Position or M.UDim2.new()
	local anchor = object.AnchorPoint or M.Vector2.new(0, 0)
	local x = px + pw * position.X.Scale + position.X.Offset * inherited - anchor.X * w
	local y = py + ph * position.Y.Scale + position.Y.Offset * inherited - anchor.Y * h
	return x, y, w, h, inherited * own
end
local meta = getmetatable(M.make("Frame"))
local baseIndex = meta.__index
meta.__index = function(self, key)
	if key == "AbsolutePosition" or key == "AbsoluteSize" then
		local x, y, w, h = layout(self)
		return if key == "AbsolutePosition" then M.Vector2.new(x, y) else M.Vector2.new(w, h)
	end
	return baseIndex(self, key)
end
local function box(object)
	local x, y, w, h = layout(object)
	return { x0 = x, y0 = y, x1 = x + w, y1 = y + h }
end
local function show(b)
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end

local Config = require("./Config")
local CarryGrip = require("./CarryGrip")
local Inventory = require("./Inventory")
local Holding = require("./Holding")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local TopBlocks = require("./TopBlocks")
local MovingHud = require("./MovingHud")
local MoveHelperHud = require("./MoveHelperHud")
local QuickChat = require("./QuickChat")
local CarryGripUi = require("./CarryGripUi")
local MoveSounds = require("./MoveSounds")
local G = Config.CarryGrip

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
local function answers()
	local list = {}
	for _, args in sentOn("Moving") do
		if args[1] == "grip" then
			table.insert(list, args)
		end
	end
	return list
end
local function setAttr(object, key, value)
	object:SetAttribute(key, value)
	object:GetAttributeChangedSignal(key):Fire()
end
local function overlap(a, b)
	return TouchLayout.overlap(a, b)
end
local function inside(b)
	return MoveLayout.inside(b, M.width, M.height)
end
local function frames(count, dt)
	for _ = 1, count or 1 do
		M.clock += dt or 1 / 60
		M.services.RunService.RenderStepped:Fire(dt or 1 / 60)
	end
end
-- 7.1: the move's sounds as client/MoveSounds.luau asks client/Sounds.luau to play them (its api, recorded)
M.cues = {}
local function cues(name)
	local count = 0
	for _, cue in M.cues do
		if cue == name then
			count += 1
		end
	end
	return count
end

-- ── The preview's scenes (carrygrip_preview.py) ─────────────────────────────
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
local function scene(name)
	if not dump then
		return
	end
	local overlay = {}
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, M.scale)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
		table.insert(overlay, { kind = "pill", box = cluster.sprint, label = "SPRINT" })
		table.insert(overlay, { kind = "pill", box = cluster.act, label = "PUT DOWN" })
	else
		table.insert(overlay, { kind = "text", box = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W - 150, y0 = 4, x1 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y1 = 30 }, label = "MOUSE [ALT]" })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── A phone sideways, with the HUD's groups where client/Hud.luau puts them ──
local hud = named(M.gui, "ZombieDeliveryHud")
local HUD_NAMES = { "HudButtons", "Fire", "RightStack", "BottomBar", "Hint", "LeftStack" }
local guideGui = M.make("ScreenGui", { Name = "SandboxGuide", DisplayOrder = 2 }, M.gui)
local guide = M.make("TextLabel", { Name = "GuideLine", Text = "Carry the Old TV to your van", TextSize = 15, TextColor3 = M.MTheme.Contract.text, BackgroundColor3 = M.MTheme.Contract.charcoal, BackgroundTransparency = 0.25 }, guideGui)
-- The HUD's groups on a screen of M.width × M.height at M.scale (the old ones go): (the touch cluster, the touch
-- buttons with the thumbstick's corner and the jump button, the groups' boxes, their names); the guide line under the
-- move's top blocks
local function layoutHud()
	for _, name in HUD_NAMES do
		local old = named(hud, name)
		if old then
			old:Destroy()
		end
	end
	local W, H, scale = M.width, M.height, M.scale
	local c = TouchLayout.cluster(W, H, scale)
	local blocks = table.clone(TouchLayout.buttons(c))
	table.insert(blocks, c.thumb)
	table.insert(blocks, c.jump)
	local names, boxes = {}, {}
	local function hudGroup(name, b, label)
		M.make("TextLabel", { Name = name, Text = label or "", TextSize = 11, TextColor3 = M.MTheme.Contract.secondary, BackgroundColor3 = M.MTheme.Contract.charcoal,
			BackgroundTransparency = 0.55, Position = M.UDim2.fromOffset(b.x0, b.y0), Size = M.UDim2.fromOffset(b.x1 - b.x0, b.y1 - b.y0) }, hud)
		table.insert(names, name)
		table.insert(boxes, b)
	end
	local barW, barH = Inventory.size(#Holding.Order + 2, true)
	local barScale = math.max(scale, Inventory.minScale(M.touch))
	if M.touch then
		-- (client/Hud.luau's touch layout: the actions' row 170 × 44 at 0.8 top right, FIRE (hidden in the sandbox,
		-- kept here: the harder case), the right column 300 × 130, the bottom bar, the contextual action over it)
		local rowW, rowH = 170 * 0.8, 44 * 0.8
		hudGroup("HudButtons", TouchLayout.box(W - 16 - rowW, 16, W - 16, 16 + rowH), "≡ ⚙")
		hudGroup("Fire", c.fire, "FIRE")
		local column, _, bar = TouchLayout.dock(c, W, H, 300 * scale, 130 * scale, 16 + rowH, W - 16 - rowW, barW * barScale, barH * barScale)
		hudGroup("RightStack", column, "")
		hudGroup("BottomBar", bar, "▣ ▣ ▣")
		local buttons = table.clone(TouchLayout.buttons(c))
		table.insert(buttons, column)
		local hintX, hintBottom, hintW = TouchLayout.hint(c, buttons, W, H, scale, bar.y0)
		hudGroup("Hint", TouchLayout.box(hintX - hintW / 2, hintBottom - 96 * scale, hintX + hintW / 2, hintBottom), "")
		hudGroup("LeftStack", TouchLayout.box(16, 16, 16 + 200 * scale, 16 + 90 * scale), "$1,240 · +$3/min")
	else
		-- (a computer: the money top left, the bottom bar in the middle at the bottom, the key hints top right)
		local w, h = barW * barScale, barH * barScale
		hudGroup("BottomBar", TouchLayout.box(W / 2 - w / 2, H - 16 - h, W / 2 + w / 2, H - 16), "▣ ▣ ▣")
		hudGroup("LeftStack", TouchLayout.box(16, 16, 16 + 200 * scale, 16 + 90 * scale), "$1,240 · +$3/min")
		hudGroup("RightStack", TouchLayout.box(W - 16 - 300 * scale, 56, W - 16, 56 + 130 * scale), "[E] Use [G] Put down [LMB/F] Grip")
	end
	-- the sandbox's guide line under the move's panel and Danny's strip (TopBlocks: the widget keeps clear of it)
	TopBlocks.set("SandboxGuide", nil)
	local under = TopBlocks.bottom() or 8
	local gw = math.min(W - 32, 560 * scale)
	guide.Position = M.UDim2.fromOffset(W / 2 - gw / 2, under + 6)
	guide.Size = M.UDim2.fromOffset(gw, 34 * math.max(scale, 0.8))
	TopBlocks.set("SandboxGuide", guide)
	return c, blocks, boxes, names
end
M.touch, M.width, M.height = true, 844, 354
M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)

MovingHud.start()
MoveHelperHud.start()
QuickChat.start()
CarryGripUi.start()
MoveSounds.start({
	play = function(name)
		table.insert(M.cues, name)
	end,
	make = function()
		return nil
	end,
	on = function()
		return true
	end,
})

local moving = M.remotes.Moving or M.Net.get("Moving")
-- The move's state (a new table each time: the sounds compare it with the last), the TV (spot 2) as given.
local function moveState(tvState, tvCondition)
	return {
		id = 1, contract = "marge", name = "Marge's House", icon = "🏠", client = "Marge", owner = "Courier", mine = true,
		endsAt = M.now + 600, hordeAt = M.now + 420, seconds = Config.Moving.Time, horde = false,
		items = {
			{ spot = 2, name = "Old TV", icon = "📺", star = false, class = "both", weight = 4, fragile = true, value = 300, room = "living", state = tvState, condition = tvCondition, broken = false, mine = true, by = "Courier" },
			{ spot = 7, name = "Sofa", icon = "🛋️", star = false, class = "pair", weight = 8, fragile = false, value = 350, room = "living", state = "home", condition = 1, broken = false, mine = false },
		},
		counts = { total = 2, out = 0, stars = 0, starsOut = 0, broken = 0, carried = if tvState == "carried" then 1 else 0, home = 1 }, fill = 0,
		truck = true, backOpen = false, house = { x = 263, z = 839 }, door = { x = 263, z = 857 }, dropOff = { x = 178, z = -98 }, inside = true,
		team = { role = "driver", called = false, barricades = 0, free = {}, switchAt = 0 },
	}
end
moving.OnClientEvent:Fire("state", moveState("carried", 1))
setAttr(M.player, "MoveHelper", "hired") -- (Danny's strip: 8.3 hired)
setAttr(M.player, "MoveWith", 14) -- (the 💬 button)
local panel = named(M.gui, "MovePanel")
local strip = MoveHelperHud.strip()
local chatButton = named(M.gui, "QuickChatButton")
check("the move's pieces show: the panel, Danny's strip, the 💬 button", panel.Visible and strip.Visible and chatButton.Visible)
local cluster, touchBlocks, hudBoxes, hudNames = layoutHud()
local touchNames = { "FIRE", "SPRINT", "PUT DOWN (the hand button)", "DRAW", "the thumbstick's corner", "the jump button" }

-- The server's checks: a lift on the TV, a wobble (its miss drops it or not)
local nextId = 0
local function open(what, drop, roll, kind, weight, fragile)
	nextId += 1
	local check = CarryGrip.check(CarryGrip.profile(kind or "both", weight or 4, if fragile == nil then true else fragile, false), what, roll or 0.5)
	local wire = CarryGrip.wire(check, { id = nextId, spot = 2, name = "Old TV", icon = "📺", drop = drop == true, help = false })
	moving.OnClientEvent:Fire("grip", "open", wire)
	return wire, check
end
local function result(id, outcome, left)
	moving.OnClientEvent:Fire("grip", "result", { id = id, what = "lift", outcome = outcome, left = left or 96, name = "Old TV" })
end
-- Frames until the needle is in the zone's middle (± a frame), then nothing more
local function untilHit(check)
	local at = M.clock
	for _ = 1, 600 do
		local e = M.clock - at
		if CarryGrip.hits(check, e) and math.abs(CarryGrip.needle(check, e) - (check.zone0 + check.zone / 2)) < check.zone * 0.25 then
			return
		end
		frames(1)
	end
end

-- ── No check: nothing ───────────────────────────────────────────────────────
check("no check: no widget", not CarryGripUi.active() and not CarryGripUi.panel().Visible and not CarryGripUi.tapButton().Visible)
setAttr(M.player.Character, "MoveCarry", 2)
setAttr(M.player.Character, "CarryGrip", "both 4 fragile")
frames(30)
check("a carry with a grip: still nothing (no holding; walking is free)", not CarryGripUi.active() and not CarryGripUi.panel().Visible)

-- ── The lift check ──────────────────────────────────────────────────────────
local opensAt = M.clock
local wire, lift = open("lift")
local grip = CarryGripUi.panel()
local tap = CarryGripUi.tapButton()
frames(1)
check("the server's lift check: the widget and the GRIP button show", CarryGripUi.active() and grip.Visible and tap.Visible)
local title, piece, hint = named(grip, "Title"), named(grip, "Piece"), named(grip, "Hint")
check("…GET A GRIP!, the piece's icon (📺), the tutorial's hint (a phone: Tap GRIP in the green)", title.Text == "GET A GRIP!" and piece.Text == "📺"
	and hint.Text == "Tap GRIP in the green", `{title.Text} / {piece.Text} / {hint.Text}`)
local padKey = named(grip, "PadKey")
check("…no gamepad glyph on a phone (8.3 keys)", padKey ~= nil and not padKey.Visible)
check("…grip_tick as it opens", played("grip_tick") == 1)
local gripBox, tapBox = box(grip), box(tap)
check("the GRIP button: round, 80 px and more, at the right over the touch buttons", tapBox.x1 - tapBox.x0 >= 80 and math.abs((tapBox.x1 - tapBox.x0) - (tapBox.y1 - tapBox.y0)) < 1
	and tapBox.x0 > M.width / 2 and tapBox.y1 <= cluster.top + 0.5, show(tapBox))
check("the widget on the screen (a short phone: its middle under the character is the HUD's: beside it), readable (× 0.62 and more)",
	inside(gripBox) and uiScale(grip) >= G.Ui.Min - 1e-6, show(gripBox))
local pieces = { ["the move's panel"] = box(panel), ["Danny's strip"] = box(strip), ["the 💬 button"] = box(chatButton), ["the guide line"] = box(guide) }
for index, b in hudBoxes do
	pieces[`the HUD's {hudNames[index]}`] = b
end
for index, b in touchBlocks do
	pieces[touchNames[index]] = b
end
for what, b in pieces do
	check(`the widget and GRIP clear of {what}`, not overlap(gripBox, b) and not overlap(tapBox, b), `{show(gripBox)} {show(tapBox)} / {show(b)}`)
end
check("…and of each other", not overlap(gripBox, tapBox) and inside(tapBox))
print(`      (844 × 354: the widget {show(gripBox)} at {uiScale(grip)}, GRIP {show(tapBox)})`)
local zone, needle = named(grip, "Zone"), named(grip, "Needle")
local trackW = MoveLayout.CHECK_W - 24
check("the zone where the check has it", zone.Position.X.Offset == math.floor(lift.zone0 * trackW + 0.5) and zone.Size.X.Offset == math.floor(lift.zone * trackW + 0.5))
local x0 = needle.Position.X.Offset
frames(20)
check("the needle sweeps (from the left end, to the right)", needle.Position.X.Offset > x0 and x0 <= 2, `{x0} → {needle.Position.X.Offset}`)
scene("phone-lift")
untilHit(lift)
local elapsed = M.clock - opensAt
local sent = #answers()
tap.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Touch })
local a = answers()[#answers()]
check("GRIP in the zone: (\"grip\", id, \"ok\", its time) sent at once", #answers() == sent + 1 and a[2] == wire.id and a[3] == "ok" and math.abs(a[4] - elapsed) < 0.05
	and CarryGrip.hits(lift, a[4]), a[4])
frames(1)
check("…NICE!, ding, the GRIP button goes", title.Text == "NICE!" and played("ding") == 1 and not tap.Visible)
local stopped = needle.Position.X.Offset
frames(10)
check("…the needle stops where it was pressed", needle.Position.X.Offset == stopped)
tap.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Touch })
M.services.UserInputService.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1, KeyCode = M.Enum.KeyCode.Unknown }, false)
check("…a second press sends nothing more (one answer a check)", #answers() == sent + 1)
result(wire.id, "balanced", 100)
frames(1)
check("the server's BALANCED!: \"Balanced: +10% walk\"", title.Text == "BALANCED!" and hint.Text == "Balanced: +10% walk", title.Text)
scene("phone-balanced")
frames(math.ceil(G.Ui.Linger * 60) + 2)
check(`…gone {G.Ui.Linger} s later`, not CarryGripUi.active() and not grip.Visible)

-- ── A miss: SLIPPED BACK! ───────────────────────────────────────────────────
wire, lift = open("lift")
frames(2)
check("the second check: the tutorial's hint still", hint.Text == "Tap GRIP in the green")
named(grip, "Press").InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Touch })
a = answers()[#answers()]
check("a tap on the widget at once (the needle short of the zone): (\"grip\", id, \"miss\", its time)", a[2] == wire.id and a[3] == "miss" and type(a[4]) == "number" and a[4] < 0.1)
frames(1)
check("…MISSED!", title.Text == "MISSED!")
local shakes = #M.shakes
result(wire.id, "knock", 95)
local restX = math.floor(box(grip).x0 + 0.5)
local moved = false
for _ = 1, 12 do
	frames(1)
	moved = moved or math.floor(box(grip).x0 + 0.5) ~= restX
end
check("the server's knock: SLIPPED BACK!, \"95% left · try again\" (8.3 keys: a phone taps the prompt, no E), furniture_putdown, a shake (the widget and the camera)", title.Text == "SLIPPED BACK!"
	and hint.Text == "95% left · try again" and played("furniture_putdown") == 1 and moved and #M.shakes == shakes + 1, `{title.Text} / {hint.Text}`)
frames(math.ceil(G.Ui.Linger * 60) + 2)
check("…and it goes", not CarryGripUi.active())

-- ── No press: a miss at the window's end ────────────────────────────────────
wire, lift = open("lift")
frames(2)
sent = #answers()
frames(math.ceil(lift.window * 60) + 2)
a = answers()[#answers()]
check("no press: (\"grip\", id, \"miss\") at the window's end, once", #answers() == sent + 1 and a[2] == wire.id and a[3] == "miss" and title.Text == "MISSED!")
frames(60)
check("…once (not every frame)", #answers() == sent + 1)
frames(math.ceil(2.6 * 60))
check("…no outcome from the server (the move ended meanwhile): it goes anyway", not CarryGripUi.active())

-- ── A wobble: STAGGER!, then one whose miss drops it ────────────────────────
wire, lift = open("wobble", false)
frames(2)
check("a wobble: WOBBLE!, the short hint now (the 4th check)", title.Text == "WOBBLE!" and hint.Text == "Tap GRIP" and played("grip_warning") == 1, `{title.Text} / {hint.Text}`)
local wobbleZone = zone.Size.X.Offset
M.services.UserInputService.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Touch }, false)
check("…a touch elsewhere on the screen (the camera, the thumbstick): no press", #answers() == sent + 1)
tap.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Touch })
result(wire.id, "stagger", 92)
frames(1)
check("…missed: STAGGER!, \"92% left · don't miss again\", grip_warning", title.Text == "STAGGER!" and hint.Text == "92% left · don't miss again"
	and played("grip_warning") == 2)
scene("phone-stagger")
frames(math.ceil(G.Ui.Linger * 60) + 2)
wire, lift = open("wobble", true)
frames(30)
check("a shaky wobble: LAST CHANCE!, \"A miss drops it · Tap GRIP\" (its edge red)", title.Text == "LAST CHANCE!" and hint.Text == "A miss drops it · Tap GRIP" and named(grip, "Edge").Color == M.MTheme.Contract.red and zone.Size.X.Offset == wobbleZone)
scene("phone-wobble-drop")
tap.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Touch })
local drops, shakes2 = cues("heavy_drop"), #M.shakes
result(wire.id, "drop", 77)
moving.OnClientEvent:Fire("state", moveState("ground", 0.77))
frames(1)
check("…missed: DROPPED!, \"It fell · 77% left\", grip_slip (client/MoveSounds.luau), no heavy_drop for the drop's damage", title.Text == "DROPPED!"
	and hint.Text == "It fell · 77% left" and cues("grip_slip") == 1 and cues("heavy_drop") == drops and #M.shakes == shakes2 + 1 and M.shakes[#M.shakes] == G.Ui.CameraDrop)
frames(math.ceil(G.Ui.Linger * 60) + 2)

-- ── A close, a fade, a stale outcome ────────────────────────────────────────
wire, lift = open("wobble", false)
frames(2)
moving.OnClientEvent:Fire("grip", "close", wire.id)
frames(1)
check("(\"grip\", \"close\", id): gone at once, no outcome", not CarryGripUi.active() and not grip.Visible)
wire, lift = open("wobble", false)
frames(2)
sent = #answers()
moving.OnClientEvent:Fire("fade", "out", 0.35)
frames(2)
tap.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Touch })
check("a door's fade: hidden, a press does nothing", not grip.Visible and #answers() == sent)
moving.OnClientEvent:Fire("fade", "in", 0.35)
moving.OnClientEvent:Fire("grip", "close", wire.id)
local newer = open("lift")
frames(2)
result(newer.id - 1, "drop", 50)
frames(1)
check("an older check's outcome while a newer one is on: ignored", title.Text == "GET A GRIP!" and CarryGripUi.active())
moving.OnClientEvent:Fire("grip", "close", newer.id)
result(newer.id + 5, "knock", 90)
frames(1)
check("an outcome with no check on (the server's timeout): it shows anyway", title.Text == "SLIPPED BACK!" and grip.Visible)
moving.OnClientEvent:Fire("state", nil)
frames(1)
check("off the move: gone", not CarryGripUi.active() and not grip.Visible)
moving.OnClientEvent:Fire("state", moveState("carried", 0.77)) -- (back on it: the move's panel again)

-- ── Three touch screens: the widget and GRIP clear of everything ───────────
local function area(p, q)
	return math.max(0, math.min(p.x1, q.x1) - math.max(p.x0, q.x0)) * math.max(0, math.min(p.y1, q.y1) - math.max(p.y0, q.y0))
end
for _, screen in { { 844, 390, "a phone sideways" }, { 740, 360, "a small phone sideways" }, { 1024, 768, "a tablet" } } do
	M.touch, M.width, M.height = true, screen[1], screen[2] - 36 -- (under Roblox's top bar)
	M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	local _, blocks, groups, names = layoutHud()
	wire = open("wobble", false)
	frames(1)
	local g, t = box(grip), box(tap)
	local stuff = { ["the move's panel"] = box(panel), ["Danny's strip"] = box(strip), ["the 💬 button"] = box(chatButton), ["the guide line"] = box(guide) }
	for index, b in blocks do
		stuff[touchNames[index]] = b
	end
	for index, b in groups do
		stuff[`the HUD's {names[index]}`] = b
	end
	local hit = {}
	for what, b in stuff do
		if overlap(g, b) or overlap(t, b) then
			table.insert(hit, `{what} {math.floor(area(g, b) + area(t, b))} px²`)
		end
	end
	check(`{screen[1]} × {screen[2]} ({screen[3]}): the widget and a GRIP of 80 px and more on the screen, clear of the touch controls, the move's pieces, the guide line, the HUD's groups and each other`,
		grip.Visible and tap.Visible and #hit == 0 and inside(g) and inside(t) and not overlap(g, t) and t.x1 - t.x0 >= 80,
		`{show(g)} {show(t)} on {table.concat(hit, ", ")}`)
	print(`      ({M.width} × {M.height}: the widget {show(g)} at {uiScale(grip)}, GRIP {show(t)})`)
	if screen[1] == 844 then
		local check2 = CarryGrip.fromWire(wire) :: any
		untilHit(check2)
		scene("phone-wobble")
	end
	moving.OnClientEvent:Fire("grip", "close", wire.id)
	frames(1)
end
check("gone again", not CarryGripUi.active() and not grip.Visible)

-- ── A computer: no GRIP button; the left mouse button or F presses ─────────
M.touch, M.width, M.height = false, 1280, 764
M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)
camera:GetPropertyChangedSignal("ViewportSize"):Fire()
local _, _, pcBoxes, pcNames = layoutHud()
wire, lift = open("lift", false, 0.3, "pair", 8, false)
frames(1)
gripBox = box(grip)
check("a computer: the widget in the middle under the character, no GRIP button", grip.Visible and not tap.Visible and math.abs((gripBox.x0 + gripBox.x1) / 2 - M.width / 2) < 2
	and gripBox.y0 > M.height / 2 and inside(gripBox), show(gripBox))
check("…the hint: Press LMB / F", hint.Text == "Press LMB / F", hint.Text)
local pcPieces = { ["the move's panel"] = box(panel), ["Danny's strip"] = box(strip), ["the guide line"] = box(guide) }
for index, b in pcBoxes do
	pcPieces[`the HUD's {pcNames[index]}`] = b
end
for what, b in pcPieces do
	check(`…clear of {what}`, not overlap(gripBox, b), `{show(gripBox)} / {show(b)}`)
end
print(`      ({M.width} × {M.height}: the widget {show(gripBox)} at {uiScale(grip)})`)
local input = M.services.UserInputService
sent = #answers()
frames(10)
input.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1, KeyCode = M.Enum.KeyCode.Unknown }, true)
check("a click on a button (gameProcessed): not a press", #answers() == sent)
scene("pc-lift")
untilHit(lift)
input.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1, KeyCode = M.Enum.KeyCode.Unknown }, false)
a = answers()[#answers()]
check("the left mouse button in the zone: \"ok\"", #answers() == sent + 1 and a[3] == "ok")
moving.OnClientEvent:Fire("grip", "close", wire.id)
wire, lift = open("wobble", false)
frames(2)
untilHit(lift)
input.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Keyboard, KeyCode = M.Enum.KeyCode.F }, false)
a = answers()[#answers()]
check("F in the zone: \"ok\"", #answers() == sent + 2 and a[3] == "ok" and a[2] == wire.id)
result(wire.id, "steady", 100)
frames(1)
check("STEADY!: \"Steady again: +10% walk\"", title.Text == "STEADY!" and hint.Text == "Steady again: +10% walk")
scene("pc-steady")
frames(math.ceil(G.Ui.Linger * 60) + 2)
M.gamepad = true
wire = open("wobble", false)
frames(1)
check("a gamepad: \"Press R2\"", hint.Text == "Press R2")
-- 8.3 keys: R2's glyph at the top right, the title making room for it
check("…R2's glyph at the widget's top right (the platform's picture), the title narrower", padKey.Visible and string.find(padKey.Image, "ButtonR2", 1, true) ~= nil
	and box(padKey).x1 <= box(grip).x1 and box(padKey).y0 >= box(grip).y0 and box(title).x1 <= box(padKey).x0 + 1, `{padKey.Image} {show(box(padKey))} / {show(box(title))}`)
input.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Gamepad1, KeyCode = M.Enum.KeyCode.ButtonR2 }, false)
check("…R2 presses", answers()[#answers()][2] == wire.id)
frames(1)
check("…the glyph goes once pressed (nothing more to press)", not padKey.Visible)
result(wire.id, "knock", 90)
frames(1)
check("…SLIPPED BACK! with a gamepad: \"90% left · try again (X)\" (the prompts' X)", hint.Text == "90% left · try again (X)", hint.Text)
frames(math.ceil(G.Ui.Linger * 60) + 2)
-- 8.3 keys: no picture from the platform: the words alone
M.padImages = false
wire = open("wobble", false)
frames(1)
check("a gamepad without the platform's pictures: \"Press R2\", no glyph", hint.Text == "Press R2" and not padKey.Visible)
moving.OnClientEvent:Fire("grip", "close", wire.id)
M.padImages = true
-- 8.3 keys: the gamepad put down mid-check (the mouse used): the computer's words at the next frame, the glyph gone; picked up again
wire = open("wobble", false)
frames(1)
useGamepad(false)
frames(1) -- (the next frame draws it)
check("the gamepad put down mid-check: \"Press LMB / F\" at once, no glyph", hint.Text == "Press LMB / F" and not padKey.Visible, hint.Text)
useGamepad(true)
frames(1) -- (the next frame draws it)
check("…picked up again: \"Press R2\" and its glyph at once", hint.Text == "Press R2" and padKey.Visible, hint.Text)
moving.OnClientEvent:Fire("grip", "close", wire.id)
-- 8.3 keys: a computer's knock names the prompt's E
useGamepad(false)
wire = open("lift", false)
frames(1)
result(wire.id, "knock", 88)
frames(1)
check("a computer's knock: \"88% left · try again (E)\"", hint.Text == "88% left · try again (E)", hint.Text)
frames(math.ceil(G.Ui.Linger * 60) + 2)
-- 8.3 keys: a phone with a gamepad used last: the gamepad's words (the GRIP button still there to tap)
M.touch = true
useGamepad(true)
wire = open("wobble", false)
frames(1)
check("a phone with a gamepad used last: \"Press R2\" and its glyph", hint.Text == "Press R2" and padKey.Visible, hint.Text)
moving.OnClientEvent:Fire("grip", "close", wire.id)
-- 8.3 keys: the city's words as before (a touch screen first, its E; no glyph)
Config.Sandbox.On = false
wire = open("lift", false)
frames(1)
check("the city: a phone with a gamepad: \"Tap GRIP\" as before, no glyph", string.find(hint.Text, "Tap GRIP", 1, true) == 1 and not padKey.Visible, hint.Text)
result(wire.id, "knock", 87)
frames(1)
check("… its knock: \"87% left · try again (E)\" as before", hint.Text == "87% left · try again (E)", hint.Text)
frames(math.ceil(G.Ui.Linger * 60) + 2)
Config.Sandbox.On = true
M.touch = false
useGamepad(false)
frames(1)
-- the list (O) open at the right: the widget keeps clear of it
input.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.O, UserInputType = M.Enum.UserInputType.Keyboard }, false)
M.resume()
M.resume()
wire = open("wobble", false)
frames(1)
local list = named(M.gui, "MoveList")
check("the list (O) open: the widget clear of it", list ~= nil and not overlap(box(grip), box(list)), `{show(box(grip))} / {show(box(list))}`)
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
	print("ALL CARRYGRIP CHECKS PASSED")
end
