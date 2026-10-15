-- 7.0 review: the move's screen on a phone held sideways (844 × 390: 844 × 354 under Roblox's top bar), run for real on
-- tools/phone-ui/missions_mock.luau's recorder: client/MovingHud.luau (the panel, the list), client/MoveHelperHud.luau
-- (Danny's strip), client/QuickChat.luau (the 💬 button, the ring, the lines coming in), client/MoveLobbyUi.luau (the
-- planning), with client/MoveLayout.luau, client/TopBlocks.luau and client/TouchLayout.luau. The recorder has no layout
-- engine: this file lays out what the modules made (their Position, Size, AnchorPoint and UIScale, from the ScreenGui
-- down: no list layouts) to measure where each piece really sits, then asserts that none of them lies on the touch
-- buttons, the thumbstick's corner or the jump button, nor on each other; the ring's lines a finger's size; the list a
-- sheet over the whole height with GIVE UP in what scrolls (asked twice); the list drawn again only when what it shows
-- changed, its countdown ticking in place; the 💬 button hidden under a card, the list and the planning; the ring shut
-- while T is held stays shut; the key O (not Tab) and a taken key left alone; ESC; the GPS cleared only when it is still
-- the move's; the late grace's countdown; the panel following a resize; a computer's list under the player list.
-- The city's move screen (Config.Sandbox.On false: its GPS); 8.0.1: in the sandbox the move sets no GPS at all.
-- 8.8 no roles (the sandbox; the city's roles above): no role on the panel, the list starts with THE VAN (CALL VAN TO
-- DOOR for anybody, greyed once called; a stray role in a state shows nothing), the planning is the crew without PICK
-- YOUR ROLE: no role's word or icon anywhere in it.
local M = require("./missions_mock")

-- ── The stand-ins (on top of the MISSIONS window's) ─────────────────────────
-- Vector2 with its maths (the modules subtract the guis' AbsolutePosition)
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
v2.__mul = function(a, b)
	if type(a) == "number" then
		a, b = b, a
	end
	return if type(b) == "number" then M.Vector2.new(a.X * b, a.Y * b) else M.Vector2.new(a.X * b.X, a.Y * b.Y)
end
v2.__div = function(a, b)
	return if type(b) == "number" then M.Vector2.new(a.X / b, a.Y / b) else M.Vector2.new(a.X / b.X, a.Y / b.Y)
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
M.services.UserInputService.GetMouseLocation = function()
	return M.Vector2.new(M.width / 2, M.height / 2)
end
M.services.GuiService.GetGuiInset = function()
	return M.Vector2.new(0, 0)
end
M.services.Players.GetPlayers = function()
	return { M.player }
end
M.services.Players.GetPlayerByUserId = function(_, id)
	return if id == M.player.UserId then M.player else nil
end
M.scale = 1
M.MUi.closeButton = M.Ui.closeButton
M.MUi.screenScale = function()
	return M.scale
end
M.MUi.touchLayout = function()
	return M.touch
end
M.MUi.gamepadActive = function()
	return M.gamepad == true -- (8.3 keys: a gamepad used last)
end
M.MUi.MinTouch = 44
M.MTheme.PanelTransparency = 0.12
M.MTheme.WindowTransparency = 0.02
M.keys = {}
M.MKeys = {
	open = function(id, advance, options)
		M.keys[id] = { advance = advance, options = options }
	end,
	close = function(id)
		M.keys[id] = nil
	end,
	isOpen = function(id)
		return M.keys[id] ~= nil
	end,
	hint = function()
		return "SPACE"
	end,
}
M.MFade = { out = function() end, into = function() end, arrival = function() return nil end } -- (8.3: a trip's arrival)
M.MapView.waypointAt = function()
	return M.waypoint
end
M.MapView.onWaypoint = function() end
local camera = M.workspace.CurrentCamera

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
Config.Sandbox.On = false -- (the city's move screen; 8.0.1: the sandbox's GPS, none, after the city's GPS checks)
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local MovingHud = require("./MovingHud")
local MoveHelperHud = require("./MoveHelperHud")
local QuickChat = require("./QuickChat")
local MoveLobbyUi = require("./MoveLobbyUi")
local MoveStoryUi = require("./MoveStoryUi")
QuickChat.covered = function() -- (as client/Main.client.luau sets it)
	return MovingHud.isOpen() or MoveLobbyUi.isOpen() or MoveStoryUi.isOpen()
end

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
local function press(object)
	object.Activated:Fire()
end
local function attribute(key, value)
	M.player:SetAttribute(key, value)
	M.player:GetAttributeChangedSignal(key):Fire()
end
local function overlap(a, b)
	return TouchLayout.overlap(a, b)
end
local function inside(b)
	return MoveLayout.inside(b, M.width, M.height)
end

-- a phone sideways
M.touch, M.width, M.height = true, 844, 354
M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)
local cluster = TouchLayout.cluster(M.width, M.height, M.scale)
local touchBlocks = TouchLayout.buttons(cluster)
table.insert(touchBlocks, cluster.thumb)
table.insert(touchBlocks, cluster.jump)
local function clearOfTouch(b)
	for _, t in touchBlocks do
		if overlap(b, t) then
			return false
		end
	end
	return true
end

MovingHud.start()
MoveHelperHud.start()
QuickChat.start()
MoveLobbyUi.start()

local moving = M.remotes.Moving or M.Net.get("Moving")
local lobbyRemote = M.remotes.MoveLobby or M.Net.get("MoveLobby")
local function view(extra)
	local v = {
		id = 1, contract = "marge", name = "Marge's House", icon = "🏠", client = "Marge", owner = "Courier", mine = true,
		endsAt = M.now + 600, hordeAt = M.now + 420, seconds = Config.Moving.Time, horde = false,
		items = {
			{ spot = 1, name = "Grandfather Clock", icon = "🕰️", star = true, class = "both", weight = 6, fragile = true, value = 400, room = "hall", state = "home", condition = 1, broken = false, mine = false },
			{ spot = 2, name = "Lamp", icon = "💡", star = false, class = "hand", weight = 1, fragile = true, value = 40, room = "living", state = "truck", condition = 0.9, broken = false, mine = false },
		},
		counts = { total = 2, out = 1, stars = 1, starsOut = 0, broken = 0, carried = 0, home = 1 }, fill = 0.2,
		truck = true, backOpen = false, house = { x = 263, z = 839 }, door = { x = 263, z = 857 }, dropOff = { x = 178, z = -98 }, inside = false,
		team = { role = "driver", called = false, barricades = 0, free = { "carrier", "guard" }, switchAt = 0 },
	}
	for key, value in extra or {} do
		v[key] = value
	end
	return v
end

-- ── The panel and Danny's strip ─────────────────────────────────────────────
moving.OnClientEvent:Fire("state", view())
local panel = named(M.gui, "MovePanel")
local panelBox = box(panel)
check("the panel shows at the top in the middle, on the screen", panel.Visible and inside(panelBox) and math.abs((panelBox.x0 + panelBox.x1) / 2 - M.width / 2) < 1, show(panelBox))
check("… clear of the touch buttons, the thumbstick and the jump", clearOfTouch(panelBox))
check("… the GPS on the house", M.waypoint ~= nil and M.waypoint.X == 263)
attribute("MoveHelper", "hired") -- (8.3: Danny hired)
local strip = MoveHelperHud.strip()
local stripBox = box(strip)
check("Danny's strip right under the panel's real foot (its role line not covered)", strip.Visible and stripBox.y0 >= panelBox.y1 and stripBox.y0 - panelBox.y1 < 12 and not overlap(stripBox, panelBox),
	`{show(panelBox)} / {show(stripBox)}`)
check("… on the screen, clear of the touch buttons, a finger's button (8.3: its one button)", inside(stripBox) and clearOfTouch(stripBox) and named(strip, "Action").Size.Y.Offset * M.scale >= 44 - 0.01)

-- ── The quick chat ──────────────────────────────────────────────────────────
attribute("MoveWith", 14)
local button = named(M.gui, "QuickChatButton")
local buttonBox = box(button)
check("the 💬 button shows on a move, a finger's size", button.Visible and buttonBox.x1 - buttonBox.x0 >= 44 and buttonBox.y1 - buttonBox.y0 >= 44, show(buttonBox))
check("… on the screen, clear of the panel, the strip and the touch buttons", inside(buttonBox) and not overlap(buttonBox, panelBox) and not overlap(buttonBox, stripBox) and clearOfTouch(buttonBox),
	show(buttonBox))
lobbyRemote.OnClientEvent:Fire("chat", { index = 3, name = "Ann", from = 99 })
local feed = named(M.gui, "Feed")
local feedBox = box(feed)
check("a line coming in: under the panel and the strip (the lower of the two)", feedBox.y0 >= stripBox.y1 and not overlap(feedBox, stripBox) and not overlap(feedBox, panelBox), show(feedBox))
check("… clear of the touch buttons", clearOfTouch({ x0 = feedBox.x0, y0 = feedBox.y0, x1 = feedBox.x1, y1 = feedBox.y0 + 3 * 30 * M.scale }))
press(button)
local ring = named(M.gui, "Ring")
local middle = named(ring, "Middle")
check("the 💬 button opens the ring", QuickChat.isOpen() and ring.Visible)
local pills = all(middle, function(object)
	return string.sub(object.Name, 1, 4) == "Line"
end)
local fingers, onScreen, apart = true, true, true
for i, pill in pills do
	local b = box(pill)
	fingers = fingers and b.y1 - b.y0 >= 44 - 0.01
	onScreen = onScreen and inside(b)
	for j = i + 1, #pills do
		apart = apart and not overlap(b, box(pills[j]))
	end
end
check("the ring's six lines a finger's height (44 px or more)", #pills == 6 and fingers, box(pills[1]).y1 - box(pills[1]).y0)
check("… all on the screen, never on each other", onScreen and apart)
QuickChat.close(false)
check("ESC's close shuts it", not QuickChat.isOpen() and not ring.Visible)
-- held T: the ring opens after the hold; shut while T is still held, it stays shut
local input = M.services.UserInputService
input.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.T }, false)
local t0 = os.clock()
while os.clock() - t0 < Config.MoveRoles.Chat.Hold + 0.02 do
end
M.services.RunService.Heartbeat:Fire()
check("held T opens the ring", QuickChat.isOpen())
QuickChat.close(false)
local t1 = os.clock()
while os.clock() - t1 < Config.MoveRoles.Chat.Hold + 0.02 do
end
M.services.RunService.Heartbeat:Fire()
check("shut while T is still held: it stays shut", not QuickChat.isOpen())
input.InputEnded:Fire({ KeyCode = M.Enum.KeyCode.T })

-- ── The list: a sheet over the whole height ─────────────────────────────────
press(panel)
local shade = named(M.gui, "MoveListShade")
local sheet = named(M.gui, "MoveList")
local sheetBox = box(sheet)
check("a tap on the panel: the list as a sheet over the whole height (it covers the touch buttons: a modal)", shade ~= nil and MovingHud.isOpen()
	and sheetBox.y0 <= 8.5 and sheetBox.y1 >= M.height - 8.5 and inside(sheetBox), show(sheetBox))
check("… readable (the planning's size at least) and never wider than the screen", uiScale(sheet) >= 0.75 - 0.001 and sheetBox.x1 - sheetBox.x0 <= M.width - 32 + 0.01, uiScale(sheet))
local rows = named(sheet, "Rows")
local giveUp = named(rows, "GiveUp")
check("… GIVE UP at the end of what scrolls, a finger's height", giveUp ~= nil and named(rows, "Footer").Size.Y.Offset * uiScale(sheet) >= 44 - 0.01)
M.resume()
check("the 💬 button hides under the list", not button.Visible)
local before = #sentOn("Moving")
press(giveUp)
check("GIVE UP once: it asks (nothing sent)", #sentOn("Moving") == before and giveUp.Text == "TAP AGAIN TO GIVE UP")
press(giveUp)
local sent = sentOn("Moving")
check("… twice: the move is given up", #sent == before + 1 and sent[#sent][1] == "giveup")
-- no rebuild for an unchanged list; its countdown ticks in place
moving.OnClientEvent:Fire("state", view({ team = { role = "driver", called = false, barricades = 0, free = { "carrier" }, switchAt = M.now + 30 } }))
sheet = named(M.gui, "MoveList")
local waitLabel = named(sheet, "SwitchWait")
check("the role's switch counted down: SWITCH ROLE IN 30 S", waitLabel ~= nil and waitLabel.Text == "SWITCH ROLE IN 30 S")
moving.OnClientEvent:Fire("state", view({ team = { role = "driver", called = false, barricades = 0, free = { "carrier" }, switchAt = M.now + 30 } }))
check("the same state again: the list is not drawn again (a tap is never lost)", named(M.gui, "MoveList") == sheet)
M.now += 5
M.resume()
check("… a second later its countdown ticks in place", named(M.gui, "MoveList") == sheet and waitLabel.Text == "SWITCH ROLE IN 25 S", waitLabel.Text)
local changed = view({ team = { role = "driver", called = false, barricades = 0, free = { "carrier" }, switchAt = M.now + 25 } })
changed.items[1].state = "carried"
changed.items[1].by = "Ann"
moving.OnClientEvent:Fire("state", changed)
check("a thing changed hands: the list is drawn again", named(M.gui, "MoveList") ~= sheet)
MovingHud.closeAll()
check("ESC (MovingHud.closeAll) shuts the list", not MovingHud.isOpen() and named(M.gui, "MoveList") == nil)
M.resume()
check("the 💬 button back", button.Visible)

-- ── The planning ────────────────────────────────────────────────────────────
lobbyRemote.OnClientEvent:Fire("lobby", {
	card = { id = "marge", name = "Marge's House", icon = "🏠", client = "Marge", address = "155 Willow Ln", estimate = 9000, stars = { "a", "b", "c" }, items = 20, time = 720, hordeAt = 180 },
	members = { { name = "Courier", role = "driver", owner = true, you = true, ready = true } },
	maxCrew = 4, mine = true, role = "driver", canLaunch = true, waiting = 0, doubles = false,
})
M.resume()
local lobby = named(M.gui, "MoveLobby")
local lobbyCard = named(lobby, "Card")
local lobbyBox = box(lobbyCard)
check("the planning opens: the 💬 button hides under it (its title is not covered)", MoveLobbyUi.isOpen() and not button.Visible)
check("… its card on the screen", inside(lobbyBox), show(lobbyBox))
local launch = named(lobbyCard, "Launch")
check("… its LAUNCH a finger's height", launch ~= nil and launch.Size.Y.Offset * uiScale(lobbyCard) >= 44)
MoveLobbyUi.minimize()
M.resume()
local pill = named(M.gui, "PlanningPill")
check("folded: its pill at the top, the 💬 button back and clear of it", pill.Visible and button.Visible and not overlap(box(button), box(pill)) and clearOfTouch(box(button)))
lobbyRemote.OnClientEvent:Fire("lobby", nil)

-- ── Late: reach the Wall ────────────────────────────────────────────────────
moving.OnClientEvent:Fire("state", view({ endsAt = M.now - 10, hordeAt = M.now - 190, horde = true, graceEndsAt = M.now + 90 }))
local next = named(panel, "TextLabel") -- (the panel's labels: find the one that says what to do)
local said = all(panel, function(object)
	return type(object.Text) == "string" and string.find(object.Text, "REACH THE WALL", 1, true) ~= nil
end)
check("after 0:00: TIME'S UP · REACH THE WALL with its countdown", #said == 1 and string.find(said[1].Text, "01:30", 1, true) ~= nil, said[1] and said[1].Text)
local _ = next

-- ── The GPS: cleared only when it is still the move's ───────────────────────
check("late: the GPS on the Wall", M.waypoint ~= nil and M.waypoint.X == 178)
M.MapView.setWaypoint(M.Vector3.new(5, 0, 5)) -- (the player sets their own)
moving.OnClientEvent:Fire("state", nil)
check("the move's end leaves the player's own waypoint", M.waypoint ~= nil and M.waypoint.X == 5)
moving.OnClientEvent:Fire("state", view())
check("a new move: its GPS", M.waypoint.X == 263)
moving.OnClientEvent:Fire("state", nil)
check("its end clears it (still the move's)", M.waypoint == nil)
-- 8.0.1: in the sandbox (Config.Sandbox.On) the move sets no GPS: client/SandboxGuide.luau's chevron and path point at
-- the same spot (one arrow, not two: no waypoint, so no GPS ring, beacon, label or "GPS: …" toasts in client/Hud.luau)
do
	Config.Sandbox.On = true
	local onWaypoint, told = M.MapView.onWaypoint, 0
	M.MapView.onWaypoint = function()
		told += 1
	end
	moving.OnClientEvent:Fire("state", view({ drop = "your warehouse", dropOff = { x = -195, z = -122 }, horde = true }))
	check("8.0.1: the sandbox: no GPS from the move with a load (no waypoint to your warehouse, no GPS toast)", M.waypoint == nil and told == 0)
	moving.OnClientEvent:Fire("state", view({ drop = "your warehouse", dropOff = { x = -195, z = -122 }, counts = { total = 2, out = 0, stars = 1, starsOut = 0, broken = 0, carried = 0, home = 2 } }))
	check("…nor to the house", M.waypoint == nil and told == 0)
	-- the end (server/Moving.luau's SB.result): what came home, never the Wall, pay or XP
	moving.OnClientEvent:Fire("result", { name = "The Old Farmstead", icon = "🏡", how = "done", howText = "Finished: what came home is in your warehouse",
		delivered = 3, left = 3, broken = 0, total = 6, starsOut = 1, starsTotal = 2, stars = 4, pay = 0, money = 0, xp = 0, base = 0, starBonus = 0,
		timeBonus = 0, fine = 0, crew = 1, trips = 2, home = { pieces = 3, value = 640 } })
	local resultCard = named(M.gui, "MoveResult")
	local words = {}
	for _, object in all(resultCard, function(o)
		return type(o.Text) == "string"
	end) do
		table.insert(words, object.Text)
	end
	local said = table.concat(words, " | ")
	check("8.0.1: the sandbox's result card: what came home, no Wall, no pay, no XP, no share", resultCard ~= nil and string.find(said, "3 PIECES CAME HOME", 1, true) ~= nil
		and string.find(said, "Wall", 1, true) == nil and string.find(said, "XP", 1, true) == nil and string.find(string.upper(said), "SHARE", 1, true) == nil
		and string.find(string.lower(said), "%f[%a]pa[iy][ds]?%f[%A]") == nil, said)
	MovingHud.closeAll()
	moving.OnClientEvent:Fire("state", nil)
	M.MapView.onWaypoint = onWaypoint
	Config.Sandbox.On = false
	moving.OnClientEvent:Fire("state", view())
	check("…the city's GPS as before (the house)", M.waypoint ~= nil and M.waypoint.X == 263)
	moving.OnClientEvent:Fire("state", nil)
end

-- ── 7.x van moves: the trip line, FINISH (the owner's, asked twice) ──────────
local tripView = view({ trips = 1, counts = { total = 2, out = 0, stars = 1, starsOut = 0, broken = 0, carried = 0, home = 1, delivered = 1, starsDelivered = 0, lost = 0 } })
moving.OnClientEvent:Fire("state", tripView)
local finishButton = named(panel, "Finish")
local finishBox = box(finishButton)
local panelNow = box(panel)
check("7.x van moves: the panel's line says TRIP 2 · delivered 1/2", #all(panel, function(o)
	return type(o.Text) == "string" and string.find(o.Text, "TRIP 2 · delivered 1/2", 1, true) ~= nil
end) > 0)
check("…the owner's FINISH on the panel once something reached the Wall: inside it, clear of the touch buttons", finishButton.Visible
	and finishBox.x0 >= panelNow.x0 - 0.5 and finishBox.x1 <= panelNow.x1 + 0.5 and finishBox.y0 >= panelNow.y0 - 0.5 and finishBox.y1 <= panelNow.y1 + 0.5
	and clearOfTouch(finishBox), show(finishBox))
local finishSends = #sentOn("Moving")
press(finishButton)
check("…a first tap asks (TAP TO FINISH), nothing sent", finishButton.Text == "TAP TO FINISH" and #sentOn("Moving") == finishSends, finishButton.Text)
press(finishButton)
local finishSent = sentOn("Moving")
check("…a second tap finishes (Moving: finish)", #finishSent == finishSends + 1 and finishSent[#finishSent][1] == "finish")
moving.OnClientEvent:Fire("state", view({ mine = false, trips = 1, counts = tripView.counts }))
check("…not for the crew", not named(panel, "Finish").Visible)
moving.OnClientEvent:Fire("state", view())
check("…nor before the first delivery", not named(panel, "Finish").Visible)
moving.OnClientEvent:Fire("state", nil)

-- ── A resize, a computer ────────────────────────────────────────────────────
moving.OnClientEvent:Fire("state", view())
M.touch, M.width, M.height = false, 1280, 684
M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)
camera:GetPropertyChangedSignal("ViewportSize"):Fire()
check("the panel follows the screen's size", math.abs(uiScale(panel) - M.scale) < 0.001, uiScale(panel))
input.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.Tab }, false)
check("Tab is Roblox's player list: no list", not MovingHud.isOpen())
input.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.O }, true)
check("O taken by something else (gameProcessed): left alone", not MovingHud.isOpen())
input.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.O }, false)
local list = named(M.gui, "MoveList")
local listBox = box(list)
local players = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y0 = 0, x1 = M.width, y1 = math.min(M.height * 0.45, 52 + 40) }
check("O: a computer's list at the right, under the panel and Roblox's player list", MovingHud.isOpen() and named(M.gui, "MoveListShade") == nil and listBox.y0 >= box(panel).y1
	and listBox.y0 >= players.y1 and math.abs(listBox.x1 - (M.width - 16)) < 1 and inside(listBox), show(listBox))
input.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.O }, false)
check("O again shuts it", not MovingHud.isOpen())

-- ── 8.3 keys: the panel's words for the device used now (the sandbox) ───────
local function panelSays(pattern)
	for _, label in all(panel, function(o)
		return o.ClassName == "TextLabel"
	end) do
		if string.find(label.Text, pattern) then
			return label.Text
		end
	end
	return nil
end
local carrying = { total = 2, out = 1, stars = 1, starsOut = 0, broken = 0, carried = 1, home = 0 }
local wasSandbox = Config.Sandbox.On
Config.Sandbox.On = true
moving.OnClientEvent:Fire("state", view({ inside = true, counts = { total = 2, out = 1, stars = 1, starsOut = 0, broken = 0, carried = 0, home = 1 } }))
check("8.3 keys, a computer: \"Pick up the things (E) · ★ first\", \"LIST [O]\"", panelSays("^Pick up") == "Pick up the things (E) · ★ first"
	and panelSays("LIST") == "LIST [O]", `{panelSays("^Pick up")} / {panelSays("LIST")}`)
M.gamepad = true
moving.OnClientEvent:Fire("state", view({ inside = true, counts = { total = 2, out = 1, stars = 1, starsOut = 0, broken = 0, carried = 0, home = 1 } }))
check("… a gamepad: \"Pick up the things (X) · ★ first\", no list hint (no button opens it)", panelSays("^Pick up") == "Pick up the things (X) · ★ first" and panelSays("LIST") == nil,
	`{panelSays("^Pick up")} / {panelSays("LIST")}`)
moving.OnClientEvent:Fire("state", view({ counts = carrying }))
check("… \"Open the van's back (X), then Load\"", panelSays("^Open") == "Open the van's back (X), then Load", panelSays("^Open"))
M.gamepad = false
M.touch = true
moving.OnClientEvent:Fire("state", view({ counts = carrying, backOpen = true }))
check("… a phone: \"Load it at the van's back\" (the prompt is tapped), \"TAP: LIST\"", panelSays("^Load") == "Load it at the van's back" and panelSays("LIST") == "TAP: LIST",
	`{panelSays("^Load")} / {panelSays("LIST")}`)
M.touch = false
moving.OnClientEvent:Fire("state", view({ counts = carrying, backOpen = true }))
check("… a computer again: \"Load it at the van's back (E)\", \"LIST [O]\"", panelSays("^Load") == "Load it at the van's back (E)" and panelSays("LIST") == "LIST [O]",
	`{panelSays("^Load")} / {panelSays("LIST")}`)
moving.OnClientEvent:Fire("state", nil)
Config.Sandbox.On = false
M.touch, M.gamepad = true, true
moving.OnClientEvent:Fire("state", view({ counts = carrying, backOpen = true }))
check("… the city's words as before (a phone with a gamepad: still \"(E)\")", panelSays("^Load") == "Load it at the van's back (E)", panelSays("^Load"))
moving.OnClientEvent:Fire("state", nil)
M.touch, M.gamepad = false, false
Config.Sandbox.On = wasSandbox

-- ── 8.8 no roles (the sandbox): the panel, the list, the planning ─────────────
do
	local was = Config.Sandbox.On
	Config.Sandbox.On = true
	local function texts(root)
		local words = {}
		for _, object in all(root, function(o)
			return type(o.Text) == "string" and o.Text ~= ""
		end) do
			table.insert(words, object.Text)
		end
		return table.concat(words, " | ")
	end
	local function roleFree(said)
		local upper = string.upper(said)
		return string.find(upper, "ROLE", 1, true) == nil and string.find(upper, "DRIVER", 1, true) == nil and string.find(upper, "MOVER", 1, true) == nil
			and string.find(upper, "GUARD", 1, true) == nil and string.find(said, "💪", 1, true) == nil and string.find(said, "🛡", 1, true) == nil
	end
	moving.OnClientEvent:Fire("state", view({ team = { called = false } }))
	check("8.8 the sandbox: no role on the panel (no role line, no role's word or icon)", panel.Visible and roleFree(texts(panel)), texts(panel))
	press(panel)
	local sheet = named(M.gui, "MoveList")
	local van = sheet and named(sheet, "Van")
	local buttons = if van then all(van, function(o)
		return o.Name == "Ability" and o.ClassName == "TextButton"
	end) else {}
	check("…the list starts with THE VAN: CALL VAN TO DOOR, no YOUR ROLE, no SWITCH, no barricade", van ~= nil and named(sheet, "Role") == nil and named(sheet, "Switch") == nil
		and named(sheet, "SwitchWait") == nil and #buttons == 1 and buttons[1].Text == "📍 CALL VAN TO DOOR" and roleFree(texts(sheet)), sheet and texts(sheet))
	local before = #sentOn("Moving")
	press(buttons[1])
	local sent = sentOn("Moving")
	check("…its button calls the van, whoever you are (the remote's \"call\")", #sent == before + 1 and sent[#sent][1] == "call")
	moving.OnClientEvent:Fire("state", view({ team = { called = true } }))
	sheet = named(M.gui, "MoveList")
	van = sheet and named(sheet, "Van")
	buttons = if van then all(van, function(o)
		return o.Name == "Ability" and o.ClassName == "TextButton"
	end) else {}
	before = #sentOn("Moving")
	if buttons[1] then
		press(buttons[1])
	end
	check("…once called: VAN CALLED (ONCE A MOVE), a tap sends nothing", #buttons == 1 and buttons[1].Text == "🚐 VAN CALLED (ONCE A MOVE)" and #sentOn("Moving") == before,
		buttons[1] and buttons[1].Text)
	moving.OnClientEvent:Fire("state", view({ team = { role = "guard", called = false, barricades = 2, free = { "driver" }, switchAt = 0 } }))
	sheet = named(M.gui, "MoveList")
	check("…a stray role in a state shows nothing of it (no Guard, no barricade, no switch)", sheet ~= nil and named(sheet, "Van") ~= nil and named(sheet, "Role") == nil
		and named(sheet, "Switch") == nil and roleFree(texts(sheet)) and roleFree(texts(panel)), sheet and texts(sheet))
	MovingHud.closeAll()
	moving.OnClientEvent:Fire("state", nil)
	lobbyRemote.OnClientEvent:Fire("lobby", {
		card = { id = "sandbox_house", name = "The Old Farmstead", icon = "🏡", client = "The Nováks", address = "the end of Pražská", estimate = 9000, stars = { "a" }, items = 20, time = 1500, hordeAt = 0 },
		members = { { name = "Courier", owner = true, you = true, ready = true }, { name = "Ann", ready = false } },
		maxCrew = 4, mine = true, canLaunch = false, waiting = 1, ready = false,
	})
	M.resume()
	local lobby = named(M.gui, "MoveLobby")
	local card = lobby and named(lobby, "Card")
	check("…the planning: the crew (LEADER, NOT READY), LAUNCH waits; no PICK YOUR ROLE, no role cards, no role's word or icon", card ~= nil and named(card, "Member21") ~= nil
		and named(card, "Member22") ~= nil and named(card, "Roles") == nil and named(card, "Role_driver") == nil and named(card, "Launch") ~= nil
		and string.find(named(card, "Launch").Text, "WAITING FOR 1", 1, true) ~= nil and roleFree(texts(card)), card and texts(card))
	lobbyRemote.OnClientEvent:Fire("lobby", nil)
	Config.Sandbox.On = was
end
check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL MOVEHUD CHECKS PASSED")
