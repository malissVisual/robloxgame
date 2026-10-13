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
-- 7.1 review: the slipped bar stays (DROPPED!) till the server drops it, "slip" asked again a second later; dropped and
-- the same piece picked up again inside DROPPED!'s moment: a new bar, no second "slip" (the old bar's would hurt it
-- twice); the real client/MoveSounds.luau: grip_slip at the slip and no heavy_drop for the slip's damage in the state
-- that follows (one thud), a jolt otherwise thuds; the bar and HOLD clear of everything on three touch screens (a phone
-- sideways 844 × 390, a small one 740 × 360, a 1024 × 768 tablet; each under Roblox's top bar). CarryGripUi's and
-- MoveSounds' os.clock is this check's M.clock (check.py gives them mock.os): a frame moves it on by its dt, a wait is
-- M.clock += s, so the bar's seed and every timing are the same each run.
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
local MoveSounds = require("./MoveSounds")

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
		M.clock += dt or 1 / 60
		M.services.RunService.RenderStepped:Fire(dt or 1 / 60)
	end
end
local function slipsSent()
	local count = 0
	for _, args in sentOn("Moving") do
		if args[1] == "slip" then
			count += 1
		end
	end
	return count
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

-- ── A phone sideways, with the HUD's groups where client/Hud.luau puts them ──
local hud = named(M.gui, "ZombieDeliveryHud")
local HUD_NAMES = { "HudButtons", "Fire", "RightStack", "BottomBar", "Hint" }
-- The HUD's groups on a touch screen of M.width × M.height at M.scale (the old ones go): (the touch cluster, the touch
-- buttons with the thumbstick's corner and the jump button, the groups' boxes, their names)
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
	local function hudGroup(name, b)
		M.make("Frame", { Name = name, Position = M.UDim2.fromOffset(b.x0, b.y0), Size = M.UDim2.fromOffset(b.x1 - b.x0, b.y1 - b.y0) }, hud)
		table.insert(names, name)
		table.insert(boxes, b)
	end
	-- (client/Hud.luau's touch layout: the actions' row 170 × 44 at 0.8 top right, FIRE, the right column 300 × 130,
	-- the bottom bar (client/Hotbar.luau: the hands and two slots), the contextual action over it)
	local rowW, rowH = 170 * 0.8, 44 * 0.8
	hudGroup("HudButtons", TouchLayout.box(W - 16 - rowW, 16, W - 16, 16 + rowH))
	hudGroup("Fire", c.fire)
	local barW, barH = Inventory.size(#Holding.Order + 2, true)
	local barScale = math.max(scale, Inventory.minScale(true))
	local column, _, bar = TouchLayout.dock(c, W, H, 300 * scale, 130 * scale, 16 + rowH, W - 16 - rowW, barW * barScale, barH * barScale)
	hudGroup("RightStack", column)
	hudGroup("BottomBar", bar)
	local buttons = table.clone(TouchLayout.buttons(c))
	table.insert(buttons, column)
	local hintX, hintBottom, hintW = TouchLayout.hint(c, buttons, W, H, scale, bar.y0)
	hudGroup("Hint", TouchLayout.box(hintX - hintW / 2, hintBottom - 96 * scale, hintX + hintW / 2, hintBottom))
	return c, blocks, boxes, names
end
M.touch, M.width, M.height = true, 844, 354
M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)
local cluster, touchBlocks, hudBoxes, hudNames = layoutHud()

MovingHud.start()
MoveHelperHud.start()
QuickChat.start()
CarryGripUi.start()
MoveSounds.start({
	play = function(name)
		table.insert(M.cues, name)
		if name == "grip_slip" then
			M.slipped = (M.slipped or 0) + 1
		end
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
setAttr(M.player, "MoveHelper", "carry") -- (Danny's strip)
setAttr(M.player, "MoveWith", 14) -- (the 💬 button)
local panel = named(M.gui, "MovePanel")
local strip = MoveHelperHud.strip()
local chatButton = named(M.gui, "QuickChatButton")
check("the move's pieces show: the panel, Danny's strip, the 💬 button", panel.Visible and strip.Visible and chatButton.Visible)

-- ── No bar without a carry that has one ─────────────────────────────────────
local grip = CarryGripUi.panel()
check("no carry: no bar", not CarryGripUi.active() and (grip == nil or not grip.Visible))
moving.OnClientEvent:Fire("state", moveState("carried", 0.8))
check("7.1: a jolt in your hands (its condition down 0.2, no slip): heavy_drop", cues("heavy_drop") == 1, cues("heavy_drop"))
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
frames(30)
check("…once (not every frame)", slipsSent() == 1 and title.Text == "DROPPED!" and M.slipped == 1)
-- 7.1 review: the slip's damage in the move's next state (fragile: 0.15, over the jolt's 0.12): one thud, grip_slip's
local drops = cues("heavy_drop")
moving.OnClientEvent:Fire("state", moveState("carried", 0.65))
check("7.1 review: the state with the slip's damage: no heavy_drop (grip_slip had its thud)", cues("heavy_drop") == drops and cues("grip_slip") == 1,
	`{cues("heavy_drop")} {cues("grip_slip")}`)
-- 7.1 review: the server has not dropped it yet (the carry's attributes still on): the same slipped bar
M.resume() -- (the bar's look at the attributes four times a second)
check("7.1 review: not dropped yet (the attributes still on): the same bar, DROPPED!, no new one", CarryGripUi.active() and title.Text == "DROPPED!" and slipsSent() == 1)
M.clock += 1.05
frames(2)
check("…still in your hands a second later: \"slip\" asked again, once", slipsSent() == 2 and title.Text == "DROPPED!", slipsSent())
-- the server drops it: the attributes go, the bar with them (DROPPED!'s moment, 0.8 s from the slip, is over by now;
-- a drop inside it: below)
setAttr(character, "MoveCarry", nil)
setAttr(character, "CarryGrip", nil)
M.now += 1
M.resume()
check("the carry ends: the bar and the HOLD button go", not CarryGripUi.active() and not grip.Visible and not hold.Visible)
M.clock += Config.Soundscape.Move.SlipQuiet
moving.OnClientEvent:Fire("state", moveState("ground", 0.5))
check("7.1 review: SlipQuiet s later a jolt thuds again", cues("heavy_drop") == drops + 1, cues("heavy_drop"))

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

-- ── 7.1 review: dropped and picked up again inside DROPPED!'s moment ────────
walk(10.5)
local sentBefore = slipsSent()
for _ = 1, 60 * 30 do
	frames(1)
	if slipsSent() > sentBefore then
		break
	end
end
check("the TV slips again (walking, never holding)", slipsSent() == sentBefore + 1 and title.Text == "DROPPED!", slipsSent())
setAttr(character, "MoveCarry", nil) -- (the server drops it …)
setAttr(character, "CarryGrip", nil)
frames(5)
check("…dropped at once: DROPPED! stays a moment", CarryGripUi.active() and grip.Visible and title.Text == "DROPPED!")
setAttr(character, "MoveCarry", 2) -- (… and the TV is picked up again a moment later, inside DROPPED!'s moment)
setAttr(character, "CarryGrip", "both 4 fragile")
check("7.1 review: the same piece picked up again inside DROPPED!'s moment: a new bar (GRIP, not DROPPED!)", CarryGripUi.active() and grip.Visible and title.Text == "GRIP",
	title.Text)
M.clock += 1.1
frames(3)
M.resume()
check("…and no \"slip\" asked again for the old bar (the server would hurt the new carry with it)", slipsSent() == sentBefore + 1 and title.Text ~= "DROPPED!",
	`{slipsSent()} {title.Text}`)
-- ── 7.1 review: STEADY +10% only when the server gives it ────────────────────
-- an attentive hold (HOLD while the load is over the box's middle, a quarter second ahead) fills the meter; the title
-- says STEADY +10% only after a report steady as the server takes it (at most Server.SteadyOutside of it outside)
walk(0)
local thumb = { UserInputType = M.Enum.UserInputType.Touch }
local pressed, lastZone = false, zoneTop()
local reportSteady, seen = false, #sentOn("Moving")
local shownSteady, shownWrong, steadyReports, badReports = 0, 0, 0, 0
for _ = 1, 60 * 20 do
	local top = zoneTop()
	local ahead = top + zone.Size.Y.Offset / 2 + (top - lastZone) * 15
	lastZone = top
	local want = marker.Position.Y.Offset < ahead
	if want ~= pressed then
		pressed = want
		if want then
			hold.InputBegan:Fire(thumb)
		else
			M.services.UserInputService.InputEnded:Fire(thumb)
		end
	end
	frames(1)
	local sent = sentOn("Moving")
	for index = seen + 1, #sent do
		local args = sent[index]
		if args[1] == "grip" then
			reportSteady = args[4] == true
			if reportSteady then
				steadyReports += 1
				badReports += if args[3] > Config.CarryGrip.Server.SteadyOutside then 1 else 0
			end
		end
	end
	seen = #sent
	if title.Text == "STEADY +10%" then
		shownSteady += 1
		shownWrong += if reportSteady then 0 else 1
	end
end
M.services.UserInputService.InputEnded:Fire(thumb)
check("7.1 review: held attentively, the bar gets steady: STEADY +10% (its reports steady as the server takes them)", shownSteady > 0 and steadyReports > 0 and badReports == 0,
	`{shownSteady} frames, {steadyReports} steady reports, {badReports} over SteadyOutside`)
check("…STEADY +10% never shown before a report the server takes as steady (no +10% then)", shownWrong == 0, shownWrong)
setAttr(character, "MoveCarry", nil)
setAttr(character, "CarryGrip", nil)
check("a bar that did not slip goes at once with the carry", not CarryGripUi.active() and not grip.Visible)

-- ── 7.1 review: three touch screens: the bar and HOLD clear of everything ─
-- (a small phone has no clear place for the bar at its smallest, Config.CarryGrip.Ui.Min: client/MoveLayout.luau grip
-- takes the one that covers the least, never a touch control, a sliver of the HUD's right column)
local function area(a, b)
	return math.max(0, math.min(a.x1, b.x1) - math.max(a.x0, b.x0)) * math.max(0, math.min(a.y1, b.y1) - math.max(a.y0, b.y0))
end
for _, screen in { { 844, 390, "a phone sideways", true }, { 740, 360, "a small phone sideways", false }, { 1024, 768, "a tablet", true } } do
	M.touch, M.width, M.height = true, screen[1], screen[2] - 36 -- (under Roblox's top bar)
	M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)
	local _, blocks, groups, names = layoutHud()
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	setAttr(character, "MoveCarry", 2)
	setAttr(character, "CarryGrip", "both 4 fragile")
	local g, h = box(grip), box(hold)
	local pieces = { ["the move's panel"] = box(panel), ["Danny's strip"] = box(strip), ["the 💬 button"] = box(chatButton) }
	for index, b in blocks do
		pieces[touchNames[index]] = b
	end
	local hit = {}
	for what, b in pieces do
		if overlap(g, b) or overlap(h, b) then
			table.insert(hit, what)
		end
	end
	local covered = 0 -- (the share of the bar on the HUD's groups)
	for index, b in groups do
		if overlap(h, b) then
			table.insert(hit, `the HUD's {names[index]}`)
		end
		covered += area(g, b) / ((g.x1 - g.x0) * (g.y1 - g.y0))
	end
	local label = `{screen[1]} × {screen[2]} ({screen[3]}): the bar and a HOLD of 72 px and more on the screen, clear of the touch controls, the move's pieces and each other; HOLD of the HUD's groups`
	check(label .. (if screen[4] then ", the bar too" else ", the bar at most a sliver of them (no place is clear: the one that covers the least)"),
		grip.Visible and hold.Visible and #hit == 0 and inside(g) and inside(h) and not overlap(g, h) and h.x1 - h.x0 >= 72
			and (if screen[4] then covered == 0 else covered < 0.12),
		`{show(g)} {show(h)} on {table.concat(hit, ", ")}, {math.floor(covered * 100 + 0.5)}% of the bar on the HUD's groups`)
	print(`      ({M.width} × {M.height}: the bar {show(g)} at {uiScale(grip)}, HOLD {show(h)}, {math.floor(covered * 100 + 0.5)}% of the bar on the HUD's groups)`)
	setAttr(character, "MoveCarry", nil)
	setAttr(character, "CarryGrip", nil)
end
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
