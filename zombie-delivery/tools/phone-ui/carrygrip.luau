-- 7.0 grip: the carry's grip bar on a phone held sideways (844 × 390: 844 × 354 under Roblox's top bar) and on a
-- computer, run for real on tools/phone-ui/missions_mock.luau's recorder: client/CarryGripUi.luau (with
-- client/MoveLayout.luau, client/TopBlocks.luau, client/TouchLayout.luau and shared/CarryGrip.luau) beside the move's
-- own pieces (client/MovingHud.luau's panel, client/MoveHelperHud.luau's strip, client/QuickChat.luau's 💬 button) and
-- the HUD's groups where client/Hud.luau puts them on that phone (the actions' row, FIRE, the right column, the bottom
-- bar, the contextual action: TouchLayout's own boxes). Like movehud.luau it lays out what the modules made (Position,
-- Size, AnchorPoint, UIScale) and asserts: the bar and the round HOLD button (72 px and more) on the screen, clear of the
-- touch buttons, the thumbstick's corner, the jump button, the move's panel and strip, the 💬 button, the HUD's groups
-- and each other; the bar shows with the character's CarryGrip and MoveCarry and goes with them; HOLD raises the grip
-- box, letting go drops it; the load is the thing's icon; the report about once a second; SLIPPING! before the slip,
-- the "slip" sent once; the tutorial's tip; a door's fade pauses it; a computer has no HOLD button and the left mouse
-- button or F holds; no warnings.
local M = require("./missions_mock")

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
M.MUi.touchLayout = function()
	return M.touch
end
M.gamepad = false
M.MUi.gamepadActive = function()
	return M.gamepad
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
M.playedAt = {} -- (grip_tick: the frame it played on)
M.frame = 0
M.Sounds.play = function(name, volume)
	table.insert(M.played, name)
	if name == "grip_tick" then
		table.insert(M.playedAt, M.frame)
		M.tickVolume = volume
	end
end
local camera = M.workspace.CurrentCamera

-- the body: a humanoid (its health, the way it walks, the floor) and the root's speed
local character = M.player.Character
local humanoid = M.make("Humanoid", { Name = "Humanoid", Health = 100, MoveDirection = M.Vector3.new(0, 0, 0), FloorMaterial = M.Enum.Material.Plastic }, character)
M.root.AssemblyLinearVelocity = M.Vector3.new(0, 0, 0)
local function walk(speed)
	M.root.AssemblyLinearVelocity = M.Vector3.new(0, 0, -speed)
	humanoid.MoveDirection = if speed > 0 then M.Vector3.new(0, 0, -1) else M.Vector3.new(0, 0, 0)
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
local function shown(object)
	local node = object
	while node and node.ClassName ~= "PlayerGui" do
		if node.Visible == false then
			return false
		end
		node = node.Parent
	end
	return true
end

local Config = require("./Config")
local Inventory = require("./Inventory")
local Holding = require("./Holding")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local MovingHud = require("./MovingHud")
local MoveHelperHud = require("./MoveHelperHud")
local QuickChat = require("./QuickChat")
local CarryGripUi = require("./CarryGripUi")

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
	for _ = 1, count do
		M.frame += 1
		M.services.RunService.RenderStepped:Fire(dt or 1 / 60)
	end
end

-- ── A phone sideways, with the HUD's groups where client/Hud.luau puts them ──
M.touch, M.width, M.height = true, 844, 354
M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)
local S = M.scale
local cluster = TouchLayout.cluster(M.width, M.height, S)
local touchBlocks = TouchLayout.buttons(cluster)
table.insert(touchBlocks, cluster.thumb)
table.insert(touchBlocks, cluster.jump)
local hud = named(M.gui, "ZombieDeliveryHud")
local hudNames = {}
local function hudGroup(name, b)
	M.make("Frame", { Name = name, Position = M.UDim2.fromOffset(b.x0, b.y0), Size = M.UDim2.fromOffset(b.x1 - b.x0, b.y1 - b.y0) }, hud)
	table.insert(hudNames, name)
	return b
end
-- (client/Hud.luau's touch layout: the actions' row 170 × 44 at 0.8 top right, FIRE, the right column 300 × 130,
-- the bottom bar (client/Hotbar.luau: the hands and two slots), the contextual action over it)
local rowW, rowH = 170 * 0.8, 44 * 0.8
local hudBoxes = {}
table.insert(hudBoxes, hudGroup("HudButtons", TouchLayout.box(M.width - 16 - rowW, 16, M.width - 16, 16 + rowH)))
table.insert(hudBoxes, hudGroup("Fire", cluster.fire))
local barW, barH = Inventory.size(#Holding.Order + 2, true)
local barScale = math.max(S, Inventory.minScale(true))
local column, _, bar = TouchLayout.dock(cluster, M.width, M.height, 300 * S, 130 * S, 16 + rowH, M.width - 16 - rowW, barW * barScale, barH * barScale)
table.insert(hudBoxes, hudGroup("RightStack", column))
table.insert(hudBoxes, hudGroup("BottomBar", bar))
local buttons = table.clone(TouchLayout.buttons(cluster))
table.insert(buttons, column)
local hintX, hintBottom, hintW = TouchLayout.hint(cluster, buttons, M.width, M.height, S, bar.y0)
table.insert(hudBoxes, hudGroup("Hint", TouchLayout.box(hintX - hintW / 2, hintBottom - 96 * S, hintX + hintW / 2, hintBottom)))

MovingHud.start()
MoveHelperHud.start()
QuickChat.start()
CarryGripUi.start()

local moving = M.remotes.Moving or M.Net.get("Moving")
moving.OnClientEvent:Fire("state", {
	id = 1, contract = "marge", name = "Marge's House", icon = "🏠", client = "Marge", owner = "Courier", mine = true,
	endsAt = M.now + 600, hordeAt = M.now + 420, seconds = Config.Moving.Time, horde = false,
	items = {
		{ spot = 2, name = "Old TV", icon = "📺", star = false, class = "both", weight = 4, fragile = true, value = 300, room = "living", state = "carried", condition = 1, broken = false, mine = true, by = "Courier" },
		{ spot = 7, name = "Sofa", icon = "🛋️", star = false, class = "pair", weight = 8, fragile = false, value = 350, room = "living", state = "home", condition = 1, broken = false, mine = false },
	},
	counts = { total = 2, out = 0, stars = 0, starsOut = 0, broken = 0, carried = 1, home = 1 }, fill = 0,
	truck = true, backOpen = false, house = { x = 263, z = 839 }, door = { x = 263, z = 857 }, dropOff = { x = 178, z = -98 }, inside = true,
	team = { role = "driver", called = false, barricades = 0, free = {}, switchAt = 0 },
})
setAttr(M.player, "MoveHelper", "carry") -- (Danny's strip)
setAttr(M.player, "MoveWith", 14) -- (the 💬 button)
local panel = named(M.gui, "MovePanel")
local strip = MoveHelperHud.strip()
local chatButton = named(M.gui, "QuickChatButton")
check("the move's pieces show: the panel, Danny's strip, the 💬 button", panel.Visible and strip.Visible and chatButton.Visible)

-- ── No bar without a carry that has one ─────────────────────────────────────
local grip = CarryGripUi.panel()
check("no carry: no bar", not CarryGripUi.active() and (grip == nil or not grip.Visible))
setAttr(character, "MoveCarry", 5)
check("a carry without CarryGrip (a plain one-hand thing): no bar", not CarryGripUi.active())

-- ── The TV: a bar ───────────────────────────────────────────────────────────
setAttr(character, "MoveCarry", 2)
setAttr(character, "CarryGrip", "both 4 fragile")
grip = CarryGripUi.panel()
local hold = CarryGripUi.holdButton()
check("carrying the TV (CarryGrip \"both 4 fragile\"): the bar and the HOLD button show", CarryGripUi.active() and grip.Visible and hold.Visible)
local gripBox, holdBox = box(grip), box(hold)
check("the HOLD button: round, 72 px and more, at the right over the touch buttons", holdBox.x1 - holdBox.x0 >= 72 and math.abs((holdBox.x1 - holdBox.x0) - (holdBox.y1 - holdBox.y0)) < 1
	and holdBox.x0 > M.width / 2 and holdBox.y1 <= cluster.top + 0.5, show(holdBox))
check("the bar right of the middle, on the screen", inside(gripBox) and (gripBox.x0 + gripBox.x1) / 2 > M.width / 2, show(gripBox))
local pieces = { ["the move's panel"] = box(panel), ["Danny's strip"] = box(strip), ["the 💬 button"] = box(chatButton) }
for index, b in hudBoxes do
	pieces[`the HUD's {hudNames[index]}`] = b
end
local touchNames = { "FIRE", "SPRINT", "PUT DOWN (the hand button)", "DRAW", "the thumbstick's corner", "the jump button" }
for index, b in touchBlocks do
	pieces[touchNames[index]] = b
end
for what, b in pieces do
	check(`the bar and HOLD clear of {what}`, not overlap(gripBox, b) and not overlap(holdBox, b), `{show(gripBox)} {show(holdBox)} / {show(b)}`)
end
check("…and of each other", not overlap(gripBox, holdBox) and inside(holdBox))
local marker = named(grip, "Marker")
check("the load is the thing's icon (📺, from the move's state)", named(marker, "Icon").Text == "📺")
local tip = named(grip, "Tip")
check("the first carry: the tip \"Hold to keep it steady!\" (on a phone the button says HOLD)", tip.Visible and tip.Text == "Hold to keep it steady!")
local tipBox = box(tip)
local tipClear = inside(tipBox) and not overlap(tipBox, holdBox)
for _, b in pieces do
	tipClear = tipClear and not overlap(tipBox, b)
end
check("…on the screen, clear of the move's pieces, the HUD's groups and the touch controls", tipClear, show(tipBox))
print(`      (844 × 354: the bar {show(gripBox)} at {uiScale(grip)}, HOLD {show(holdBox)}, the tip {show(tipBox)})`)

-- ── HOLD raises the grip box, letting go drops it ───────────────────────────
local zone = named(grip, "Zone")
local function zoneTop()
	return zone.Position.Y.Offset
end
frames(2)
local top0 = zoneTop()
local finger = { UserInputType = M.Enum.UserInputType.Touch } -- (one touch: the same InputObject begins and ends)
hold.InputBegan:Fire(finger)
frames(20)
local top1 = zoneTop()
check("HOLD pressed: the box rises (up the screen)", top1 < top0, `{top0} → {top1}`)
local lit = hold.BackgroundColor3
hold.InputEnded:Fire({ UserInputType = M.Enum.UserInputType.Touch })
frames(5)
check("another finger lifting: still held", zoneTop() < top1)
M.services.UserInputService.InputEnded:Fire(finger) -- (the finger slid off the button and lifted: it lets go too)
frames(60)
check("let go: it falls back", zoneTop() > top1, `{top1} → {zoneTop()}`)
check("…the button lit while held", lit ~= hold.BackgroundColor3)
local reports = sentOn("Moving")
local report = reports[#reports]
check("about once a second: (\"grip\", the spot, the share outside, steady)", report ~= nil and report[1] == "grip" and report[2] == 2 and type(report[3]) == "number"
	and report[3] >= 0 and report[3] <= 1 and type(report[4]) == "boolean")

-- ── A door's fade pauses it ─────────────────────────────────────────────────
moving.OnClientEvent:Fire("fade", "out", 0.35)
local before = #sentOn("Moving")
local zoneBefore = zoneTop()
frames(120)
check("in a door's fade: paused (no step, no report)", #sentOn("Moving") == before and zoneTop() == zoneBefore)
moving.OnClientEvent:Fire("fade", "in", 0.35)

-- ── Walking without holding: SLIPPING!, then the slip ───────────────────────
walk(10.5)
local title = named(grip, "Title")
local warned, slipAt = false, nil
for i = 1, 60 * 30 do
	frames(1)
	if title.Text == "SLIPPING!" then
		warned = true
	end
	local sent = sentOn("Moving")
	if sent[#sent][1] == "slip" then
		slipAt = i
		break
	end
end
check("walking, never holding: SLIPPING! first, then (\"slip\", the spot) is sent", warned and slipAt ~= nil and sentOn("Moving")[#sentOn("Moving")][2] == 2, slipAt)
local warnings = 0
for _, name in M.played do
	if name == "grip_warning" then
		warnings += 1
	end
end
check("…grip_warning on entering SLIPPING! (once), MoveSounds.slipped() at the slip (not grip_slip itself)", warnings == 1 and M.slipped == 1
	and table.find(M.played, "grip_slip") == nil, `{warnings} {M.slipped}`)
local closest = math.huge
for i = 2, #M.playedAt do
	closest = math.min(closest, M.playedAt[i] - M.playedAt[i - 1])
end
check("grip_tick as the meter moves, at volume 0.5, never closer than 0.08 s (5 frames at 60 fps)", #M.playedAt > 5 and M.tickVolume == 0.5 and closest >= 5, `{#M.playedAt} {closest}`)
local slips = 0
frames(30)
for _, args in sentOn("Moving") do
	if args[1] == "slip" then
		slips += 1
	end
end
check("…once (not every frame)", slips == 1 and title.Text == "DROPPED!" and M.slipped == 1)
-- the server drops it: the attributes go, the bar with them (after DROPPED! a moment)
setAttr(character, "MoveCarry", nil)
setAttr(character, "CarryGrip", nil)
M.now += 1
local t0 = os.clock()
while os.clock() - t0 < 0.85 do
end
M.resume()
check("the carry ends: the bar and the HOLD button go", not CarryGripUi.active() and not grip.Visible and not hold.Visible)

-- ── The second carry: the tip again; the third: none ────────────────────────
walk(0)
setAttr(character, "MoveCarry", 7)
setAttr(character, "CarryGrip", "pair 8")
check("the second carry (the sofa, by two): the tip again", CarryGripUi.active() and tip.Visible and named(marker, "Icon").Text == "🛋️")
setAttr(character, "MoveCarry", nil)
M.resume()
setAttr(character, "MoveCarry", 2)
setAttr(character, "CarryGrip", "both 4 fragile")
check("the third: no tip", CarryGripUi.active() and not tip.Visible)
setAttr(character, "MoveCarry", nil)
setAttr(character, "CarryGrip", nil)
M.resume()
check("gone again", not CarryGripUi.active() and not grip.Visible)

-- ── A computer: no HOLD button; the left mouse button or F holds ───────────
M.touch, M.width, M.height = false, 1280, 684
M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)
for _, name in { "HudButtons", "Fire", "RightStack", "BottomBar", "Hint" } do
	named(hud, name):Destroy()
end
camera:GetPropertyChangedSignal("ViewportSize"):Fire()
setAttr(character, "MoveCarry", 2)
setAttr(character, "CarryGrip", "both 4 fragile")
gripBox = box(grip)
check("a computer: the bar right of the middle, no HOLD button", grip.Visible and not hold.Visible and (gripBox.x0 + gripBox.x1) / 2 > M.width / 2 and inside(gripBox)
	and not overlap(gripBox, box(panel)), show(gripBox))
local input = M.services.UserInputService
frames(2)
top0 = zoneTop()
input.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1, KeyCode = M.Enum.KeyCode.Unknown }, false)
frames(20)
check("the left mouse button held: the box rises", zoneTop() < top0)
input.InputEnded:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1, KeyCode = M.Enum.KeyCode.Unknown })
frames(60)
top0 = zoneTop()
input.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.Keyboard, KeyCode = M.Enum.KeyCode.F }, false)
frames(20)
check("F held: the box rises", zoneTop() < top0)
input.InputEnded:Fire({ UserInputType = M.Enum.UserInputType.Keyboard, KeyCode = M.Enum.KeyCode.F })
frames(60)
top0 = zoneTop()
input.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1, KeyCode = M.Enum.KeyCode.Unknown }, true)
frames(20)
check("a click on a button (gameProcessed): not a hold", zoneTop() >= top0)
-- the list (O) open at the right: the bar keeps clear of it
input.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.O, UserInputType = M.Enum.UserInputType.Keyboard }, false)
M.resume()
M.resume()
M.resume()
M.resume()
local list = named(M.gui, "MoveList")
check("the list (O) open: the bar clear of it", list ~= nil and shown(list) and not overlap(box(grip), box(list)), `{show(box(grip))} / {show(box(list))}`)
check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL CARRYGRIP CHECKS PASSED")
