-- 8.0 SANDBOX, the guide (client/SandboxGuide.luau, its steps shared/SandboxSteps.luau) on a phone held sideways
-- (844 × 390: 844 × 354 under Roblox's top bar) and a computer, run for real on tools/phone-ui/missions_mock.luau's
-- recorder beside the real client/MovingHud.luau (the move's panel) and client/MoveHelperHud.luau (Danny's strip), with
-- client/TopBlocks.luau, client/MoveLayout.luau and client/TouchLayout.luau, and a stand-in for the sandbox HUD's money at
-- the top left (client/SandboxHud.luau's ScreenGui "SandboxHud"). Like movehud.luau this file lays out what the modules
-- made (Position, Size, AnchorPoint, UIScale) to measure where each piece sits, then checks: the hint line at the top in
-- the middle, on the screen, clear of the money, the move's panel, Danny's strip, Roblox's player list and the touch
-- buttons, readable on a phone, its ✕ a finger's size; every row of the owner's table with its words and its 3D target
-- (9.7: the nearest portal's pad, the run house's door, the truck's back, the nearest empty stand), a straight path;
-- a step done once goes quiet; the ✕ and a held G; the 💡 chip on a phone; nothing made loop after loop; no warnings. 8.0.1: one arrow: the move's HUD (client/MovingHud.luau) sets no GPS
-- in the sandbox (no waypoint, so none of client/Hud.luau's GPS ring, beacon, label or toasts) beside the guide's.
-- 8.3 keys (shared/SandboxPad.luau, client/PadGlyph.luau): the line's words for the device used now: a computer's
-- "E at the back", a phone's "tap at the back", a gamepad's "X at the back" (a phone's or a computer's, used last);
-- "Guide off · hold G / tap 💡 / hold B to bring it back"; a gamepad's B held as G (not while carrying, not while a
-- window holds the gamepad's selection), no 💡 chip while a gamepad is used.
-- 8.3, the soft steps (SandboxSteps.choose) at 844 × 390, 1280 × 800 and 1920 × 1080: the warehouse full and its next
-- level affordable (the chevron over the real UPGRADES desk at the warehouse's level, shared/WarehouseLayout.luau
-- terminal), the market's hot piece (a free stand, else an orange ring round the HUD's 📦 STOCK chip), another upgrade,
-- the PAINT shop (9.7: the lobby's booth); the line placed as above; nothing while the screen is covered, SoftGap after;
-- the ✕ on one dismisses it alone (the guide stays on); a window opened, a purchase or SoftSeconds on the screen: done;
-- a run wins; the ring makes nothing loop after loop.
-- 9.7 runs (no contract board, nobody drives): "Walk to a portal: step onto a house's glowing pad" (the chevron over
-- the nearest portal's pad, its house's name), quiet on a pad (client/RunUi.luau's panel says it: the host's "pick", the
-- others' "waitPad"), the run's front door, "Carry the loot out to the truck", "Load the truck", "Finish or beat the
-- clock" (the truck's back), the stock on show, "Walk into another house for more!" (the nearest portal).
-- 8.4, Danny's steps (SandboxSteps.danny) at the same three sizes (10.1: no "Hire Danny" step: he is free, with you
-- from the start; outside his list says nothing yet): 8.5 "Take out your clipboard (Q) and pick a
-- piece for Danny" in the house (10.1 the crew's helper's name: "… for Zip") ("(tap 📋)" on a phone, "(R1)" with a gamepad; with the clipboard out "Pick a piece to
-- give it to Danny") until a piece goes on his list; "Heavy piece: press Lift and wait for Danny" with a
-- two-person piece's Lift near (looked for at most once a second, no more once done) until your Lift calls him; the
-- line under the move's panel and Danny's strip, clear of the money, the touch buttons and the player list.
-- 8.9, trading between players' step at 844 × 390, 667 × 375, 1280 × 800 and 1920 × 1080: "🏷 Sell to players: set a
-- price on a piece on show" once another player is on the server (not alone) with four pieces of yours on show and no
-- FOR SALE sign, after the other soft steps; the chevron over your nearest piece on show (SET PRICE); the same words
-- with a gamepad; quiet while the screen is covered; a sign set: done, not again.
local M = require("./missions_mock")

-- ── The stand-ins (on top of the MISSIONS window's, as movehud.luau) ────────
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
local keysDown = {}
M.services.UserInputService.IsKeyDown = function(_, key)
	return keysDown[key] == true
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
M.playerList = true
M.services.StarterGui = {
	GetCoreGuiEnabled = function()
		return M.playerList
	end,
}
-- tweens: applied at once (mock.luau), with Pause for the chevron's bob
local tweens = M.services.TweenService
local create = tweens.Create
tweens.Create = function(self, target, info, props)
	local tween = create(self, target, info, props)
	function tween:Pause() end
	return tween
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
M.MKeys = { open = function() end, close = function() end, isOpen = function()
	return false
end, hint = function()
	return "SPACE"
end }
M.MFade = { out = function() end, into = function() end, arrival = function() return nil end } -- (8.3: a trip's arrival)
M.MapView.waypointAt = function()
	return M.waypoint
end
-- (8.0.1: every GPS the move would set, counted: none in the sandbox)
local gpsSets, gpsTold = 0, 0
M.MapView.onWaypoint = function()
	gpsTold += 1
end
local setWaypoint = M.MapView.setWaypoint
M.MapView.setWaypoint = function(at)
	if at ~= nil then
		gpsSets += 1
	end
	setWaypoint(at)
end
local camera = M.workspace.CurrentCamera

-- the world: the Terrain (the path's points live in it), the cars' folder, your character's humanoid
local terrain = M.make("Terrain", { Name = "Terrain" })
terrain.Parent = M.workspace
M.workspace.Terrain = terrain
local cars = M.make("Folder", { Name = "Cars" }, M.workspace)
local humanoid = M.make("Humanoid", { Name = "Humanoid" }, M.player.Character)
-- shared/WarehouseLayout.luau (written alongside): a stand-in with three stands on plot 2, in the world's coordinates.
-- 8.3: a Site (the plot at the level asked: WarehouseLayout.site), its spots (level 4's, the WarehouseLevel attribute
-- unset; level 5's further back in the hall), its capacity; each plot and level's spots asked for counted.
local SandboxMap = require("./SandboxMap")
local plot = SandboxMap.Plots[2]
local standsGiven = {
	{ x = plot.warehouse.x - 20, y = 0, z = plot.warehouse.z },
	{ x = plot.warehouse.x, y = 0, z = plot.warehouse.z },
	{ x = plot.warehouse.x + 20, y = 0, z = plot.warehouse.z },
}
local standsLevel5 = {
	{ x = plot.warehouse.x - 30, y = 0, z = plot.warehouse.z - 20 },
	{ x = plot.warehouse.x, y = 0, z = plot.warehouse.z - 20 },
	{ x = plot.warehouse.x + 30, y = 0, z = plot.warehouse.z - 20 },
}
local standsAsked = {} -- "<plot>@<level>" → how many times its spots were asked for
M.warehouseLayout = {
	site = function(id, level)
		local found = SandboxMap.Plots[id]
		if not found then
			return nil
		end
		local site = table.clone(found)
		site.level = if type(level) == "number" and level >= 1 and level <= 5 then level else 4
		return site
	end,
	capacity = function(level)
		return 3
	end,
	stands = function(site, count)
		local key = `{site.id}@{site.level}`
		standsAsked[key] = (standsAsked[key] or 0) + 1
		if site.id ~= 2 or count ~= 3 then
			return {}
		end
		return if site.level == 5 then standsLevel5 else standsGiven
	end,
}
M.warehouseLayout.terminal = function(site) -- 8.3: the UPGRADES desk, the real one's spot at the Site's level
	local real = require("./WarehouseLayout")
	return real.terminal(real.site(site.id, site.level) or site)
end
rawset(M.services.ReplicatedStorage.Shared, "FindFirstChild", function(_, name)
	if name == "WarehouseLayout" then
		return { fakeModule = M.warehouseLayout, IsA = function(_, class)
			return class == "ModuleScript"
		end }
	end
	return nil
end)
-- how many instances are made (a loop that makes none)
local made = 0
local make = M.make
M.make = function(...)
	made += 1
	return make(...)
end
M.MUi.make = M.make
M.Instance.new = function(class)
	return M.make(class)
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
local meta = getmetatable(make("Frame"))
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
local G = Config.SandboxGuide
G.HideHold, G.OffNote = 0.05, 0.05 -- (the waits short: the check's own clock is the real one)
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local SandboxSteps = require("./SandboxSteps")
local MovingHud = require("./MovingHud")
local MoveHelperHud = require("./MoveHelperHud")
local SandboxGuide = require("./SandboxGuide")

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
local function overlap(a, b)
	return TouchLayout.overlap(a, b)
end
local function inside(b)
	return MoveLayout.inside(b, M.width, M.height)
end
local function attribute(key, value)
	M.player:SetAttribute(key, value)
	M.player:GetAttributeChangedSignal(key):Fire()
end
local function wait(seconds)
	local t0 = os.clock()
	while os.clock() - t0 < seconds do
	end
end
local function stand(x, z)
	M.root.Position = M.Vector3.new(x, 3, z)
end

-- a phone sideways, the money at the top left (the sandbox HUD's)
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
local hudGui = make("ScreenGui", { Name = "SandboxHud" }, M.gui)
local money = make("Frame", { Name = "Money", Position = M.UDim2.fromOffset(8, 8), Size = M.UDim2.fromOffset(230, 60) }, hudGui)
local moneyScale = make("UIScale", { Scale = M.scale }, money)
make("Frame", { Name = "Toasts", Position = M.UDim2.new(0.5, -150, 1, -140), Size = M.UDim2.fromOffset(300, 100) }, hudGui) -- (low: no matter)

M.player:SetAttribute("Plot", 2)
stand(plot.spawn.x, plot.spawn.z)
MovingHud.start()
MoveHelperHud.start()
SandboxGuide.start()
local moving = M.remotes.Moving
local collection = M.remotes.Collection
local lobby = M.remotes.MoveLobby
check("it asks for the collection's state ({ kind = \"state\" }) and the move's", collection ~= nil and (function()
	for _, entry in M.sent do
		if entry.name == "Collection" and type(entry.args[1]) == "table" and entry.args[1].kind == "state" then
			return true
		end
	end
	return false
end)())
local hint = SandboxGuide.hint()
local words = named(hint, "Words")
local closeButton = named(hint, "Close")
local chip = named(M.gui, "GuideOn")
local marker = named(M.gui, "SandboxGuideMarker")
local targetPoint = named(terrain, "SandboxGuideTarget")
local tag = named(marker, "Distance")
local beams = all(M.workspace, function(o)
	return o.ClassName == "Beam"
end)
local function lit()
	local n = 0
	for _, beam in beams do
		if beam.Enabled then
			n += 1
		end
	end
	return n
end
local function at(x, z)
	local p = targetPoint.WorldPosition
	return p ~= nil and math.abs(p.X - x) < 0.01 and math.abs(p.Z - z) < 0.01
end
local function tick()
	M.resume()
end
local function view(extra)
	local v = {
		id = 1, contract = "sandbox_house", name = SandboxMap.House.name, icon = "🏠", client = "Ms Alder", owner = "Courier", mine = true,
		endsAt = M.now + 600, hordeAt = M.now + 420, seconds = 600, horde = false,
		items = {
			{ spot = 1, name = "Sofa", icon = "🛋️", star = true, class = "pair", state = "home", condition = 1, broken = false, mine = false },
			{ spot = 2, name = "Lamp", icon = "💡", star = false, class = "hand", state = "home", condition = 1, broken = false, mine = false },
		},
		counts = { total = 2, out = 0, stars = 1, starsOut = 0, broken = 0, carried = 0, home = 2, delivered = 0, starsDelivered = 0, lost = 0 },
		fill = 0, truck = true, backOpen = false, house = { x = SandboxMap.House.curb.x, z = SandboxMap.House.curb.z },
		door = { x = SandboxMap.House.door.x, z = SandboxMap.House.door.z }, dropOff = { x = plot.unload.x, z = plot.unload.z },
		inside = false, team = { called = false }, trips = 0, -- (8.8: no roles: the van's call only)
	}
	for key, value in extra or {} do
		v[key] = value
	end
	return v
end
local function hintBox()
	return box(hint)
end
-- the screen: a phone sideways (844 × 354 under the top bar) or a computer (1280 × 684); 8.3: or the size given
local function screen(touch, w, h)
	M.touch = touch
	M.width, M.height = w or (if touch then 844 else 1280), h or (if touch then 354 else 684)
	M.scale = math.clamp(math.min(M.width / 1150, M.height / 680), 0.55, 1.1)
	moneyScale.Scale = M.scale
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	M.resume()
end
local function closeBox()
	return box(closeButton)
end
local function shown()
	return hint.Visible and words.TextTransparency == 0
end

-- ── No run: walk to a portal (9.7: the lobby's) ─────────────────────────────
-- (the nearest portal's pad from where you stand, as the guide finds it)
local function nearestPad(x, z)
	local best, bestD = nil, math.huge
	for _, portal in SandboxMap.Lobby.portals do
		local mx, mz = (portal.pad.x0 + portal.pad.x1) / 2, (portal.pad.z0 + portal.pad.z1) / 2
		local d = (mx - x) ^ 2 + (mz - z) ^ 2
		if d < bestD then
			best, bestD = portal, d
		end
	end
	return best, (best.pad.x0 + best.pad.x1) / 2, (best.pad.z0 + best.pad.z1) / 2
end
tick()
local moneyBox = box(money)
local b = hintBox()
local PORTAL_WORDS = "Walk to a portal: step onto a house's glowing pad"
check("no run: \"Walk to a portal: step onto a house's glowing pad\" (9.7: no contract board)", SandboxGuide.step() == "portal" and words.Text == PORTAL_WORDS and shown(), words.Text)
check("… the hint line at the top in the middle, on the screen", inside(b) and math.abs((b.x0 + b.x1) / 2 - M.width / 2) < 1 and b.y0 < 30, show(b))
check("… clear of the money at the top left", not overlap(b, moneyBox), `{show(b)} / {show(moneyBox)}`)
check("… clear of the touch buttons", clearOfTouch(b))
check("… readable on a phone (its scale at least Config.SandboxGuide.TouchScale)", uiScale(hint) >= G.TouchScale - 0.001 and G.TextSize * uiScale(hint) >= 12, uiScale(hint))
local cb = closeBox()
check("… its ✕ a finger's size, on the screen, clear of the money", cb.x1 - cb.x0 >= 44 - 0.01 and cb.y1 - cb.y0 >= 44 - 0.01 and inside(cb) and not overlap(cb, moneyBox), show(cb))
check("a top block (\"SandboxGuide\"): the others keep clear of it", require("./TopBlocks").get("SandboxGuide") == hint)
local portal, px, pz = nearestPad(plot.spawn.x, plot.spawn.z)
check("the 3D guide: the chevron over the nearest portal's pad, its house's name and distance on it", marker.Enabled and at(px, pz)
	and string.find(tag.Text, "^" .. string.upper(portal.name) .. " · %d+ m$") ~= nil, tag.Text)
check("… a straight path in the lobby (one beam: no road to follow)", lit() == 1, lit())
screen(false)
moneyBox = box(money)
b = hintBox()
local players = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y0 = 0, x1 = M.width, y1 = math.min(M.height * 0.45, 52 + 40) }
check("a computer: the line at the screen's scale, in the middle at the top", math.abs(uiScale(hint) - M.scale) < 0.001
	and math.abs((b.x0 + b.x1) / 2 - M.width / 2) < 1 and b.y0 < 30 and inside(b), show(b))
check("… clear of the money and of Roblox's player list (top right)", not overlap(b, moneyBox) and not overlap(b, players) and not overlap(closeBox(), players),
	`{show(b)} / {show(moneyBox)} / {show(players)}`)
screen(true)
moneyBox = box(money)

-- ── The ✕, the 💡 chip ──────────────────────────────────────────────────────
closeButton.Activated:Fire()
tick()
check("the ✕ hides the guide: \"Guide off\" for a moment, no ✕ on it, no 3D guide", not SandboxGuide.enabled() and shown()
	and string.find(words.Text, "Guide off", 1, true) ~= nil and not closeButton.Visible and not marker.Enabled and lit() == 0, words.Text)
check("… a phone's words: \"Guide off · tap 💡 to bring it back\" (8.3 keys)", words.Text == "Guide off · tap 💡 to bring it back", words.Text)
wait(G.OffNote + 0.02)
tick()
local chipBox = box(chip)
check("… then the line fades; on a phone the 💡 chip a finger's size in its place, on the screen", not hint.Visible and chip.Visible
	and chipBox.x1 - chipBox.x0 >= 44 - 0.01 and chipBox.y1 - chipBox.y0 >= 44 - 0.01 and inside(chipBox) and not overlap(chipBox, moneyBox) and clearOfTouch(chipBox), show(chipBox))
chip.Activated:Fire()
tick()
check("… a tap on 💡 brings it back (the step not done: its words and target again)", SandboxGuide.enabled() and not chip.Visible and shown() and closeButton.Visible
	and words.Text == PORTAL_WORDS and marker.Enabled)

-- ── 9.7 on a portal's pad: its panel (client/RunUi.luau) says it, the line steps aside ──
local RunUi = require("./RunUi")
RunUi.start()
local runsRemote = M.remotes.Runs
runsRemote.OnClientEvent:Fire({ kind = "pad", house = portal.house, name = portal.name, left = 8, host = M.player.UserId, hostName = "Courier", party = { "Courier" },
	going = 1, max = 4, difficulty = "normal", open = { "easy", "normal" }, mine = true, place = 1 })
tick()
check("9.7 on a pad, its host: the step \"pick\" (the portal step done), no line: the pad panel says it", SandboxGuide.step() == "pick" and not hint.Visible and not marker.Enabled)
runsRemote.OnClientEvent:Fire({ kind = "pad", house = portal.house, name = portal.name, left = 6, host = 99, hostName = "Ann", party = { "Ann", "Courier" },
	going = 2, max = 4, difficulty = "normal", open = { "easy", "normal" }, mine = false, place = 2 })
tick()
check("… on another's pad: \"waitPad\", no line either", SandboxGuide.step() == "waitPad" and not hint.Visible)
runsRemote.OnClientEvent:Fire({ kind = "pad" })
tick()
check("… off the pad: the portal step done (quiet)", SandboxGuide.step() == "portal" and not hint.Visible and not marker.Enabled)

-- ── The planning: LAUNCH ────────────────────────────────────────────────────
lobby.OnClientEvent:Fire("lobby", { mine = true, members = {}, canLaunch = true })
tick()
check("the planning open: \"Press LAUNCH to start the move\" (no 3D target: the planning's card)", SandboxGuide.step() == "plan" and shown() and not marker.Enabled, words.Text)
lobby.OnClientEvent:Fire("lobby", { mine = false, members = {} })
tick()
check("… a crew's planning: the owner launches", SandboxGuide.step() == "planCrew" and shown(), words.Text)
lobby.OnClientEvent:Fire("lobby", nil)

-- ── A run: in the house's front yard, the door; the line under the move's panel ──
local zone = SandboxMap.zone(SandboxMap.House.id)
stand(zone.arrive.x, zone.arrive.z)
moving.OnClientEvent:Fire("state", view())
tick()
local panel = MovingHud.panel()
local panelBox = box(panel)
b = hintBox()
cb = closeBox()
check("9.7 a run started, the party in the front yard: \"Walk in through the front door\" (no drive)", SandboxGuide.step() == "door"
	and words.Text == "Walk in through the front door" and shown(), words.Text)
check("… under the move's panel, never on it (the ✕'s finger area neither)", b.y0 >= panelBox.y1 and cb.y0 >= panelBox.y1 - 0.01 and not overlap(b, panelBox) and not overlap(cb, panelBox),
	`{show(panelBox)} / {show(b)} / {show(cb)}`)
check("… on the screen, clear of the money and the touch buttons", inside(b) and inside(cb) and not overlap(b, moneyBox) and clearOfTouch(b) and clearOfTouch(cb), show(b))
check("… the chevron over the front door, a straight path to it", marker.Enabled and at(SandboxMap.House.door.x, SandboxMap.House.door.z)
	and string.find(tag.Text, "FRONT DOOR", 1, true) ~= nil and lit() == 1, tag.Text)
screen(false)
panelBox = box(panel)
b = hintBox()
cb = closeBox()
check("a computer: under the move's panel at the screen's scale, never on it, in the middle, clear of the money",
	math.abs(uiScale(hint) - M.scale) < 0.001 and b.y0 >= panelBox.y1 and not overlap(b, panelBox) and not overlap(cb, panelBox)
	and math.abs((b.x0 + b.x1) / 2 - M.width / 2) < 1 and inside(b) and not overlap(b, box(money)), `{show(panelBox)} / {show(b)}`)
screen(true)
panelBox = box(panel)
attribute("MoveHelper", "hired") -- (8.3: Danny on the move; 10.1 free; his list not known yet: no step of his)
tick()
local strip = MoveHelperHud.strip()
b = hintBox()
check("Danny's strip under the panel: the line under the strip", strip.Visible and b.y0 >= box(strip).y1 and not overlap(b, box(strip)), `{show(box(strip))} / {show(b)}`)
closeButton.Activated:Fire()
wait(G.OffNote + 0.02)
tick()
local chipUnder = box(chip)
check("… the guide off there: the 💡 chip under the strip too, on neither", chip.Visible and chipUnder.y0 >= box(strip).y1 and not overlap(chipUnder, panelBox)
	and not overlap(chipUnder, box(strip)) and inside(chipUnder) and clearOfTouch(chipUnder), show(chipUnder))
chip.Activated:Fire()
tick()
attribute("MoveHelper", nil)

-- ── In the house, out with a piece, into the truck ─────────────────────────
moving.OnClientEvent:Fire("state", view({ inside = true }))
tick()
check("in the house: \"Carry the loot out to the truck (tap to pick up)\"", SandboxGuide.step() == "inside" and words.Text == "Carry the loot out to the truck (tap to pick up)" and shown(), words.Text)
M.gamepad = true
tick()
check("… with a gamepad: \"(X to pick up)\" (8.3 keys)", words.Text == "Carry the loot out to the truck (X to pick up)", words.Text)
M.gamepad = false
tick()
check("… no 3D target inside: no chevron, no path", not marker.Enabled and lit() == 0)
local vanModel = make("Model", { Name = "Courier's Sprinter" }, cars)
vanModel:SetAttribute("OwnerId", M.player.UserId)
local chassis = make("Part", { Name = "Chassis" }, vanModel)
vanModel.PrimaryPart = chassis
local vanBack = SandboxMap.House.curb
make("Attachment", { Name = "CargoDoor", WorldPosition = M.Vector3.new(vanBack.x, 3, vanBack.z + 10) }, chassis)
local carried = view({ inside = false })
carried.items[1].state = "carried"
carried.items[1].mine = true
moving.OnClientEvent:Fire("state", carried)
stand(SandboxMap.House.door.x, SandboxMap.House.door.z - 4)
tick()
check("out with a piece: \"Load the truck: walk in or tap at its back\"", SandboxGuide.step() == "load" and words.Text == "Load the truck: walk in or tap at its back" and shown(), words.Text)
-- 8.3 keys: the same step's words on a phone with a gamepad used last, on a computer, a computer's gamepad
M.gamepad = true
tick()
check("… a phone with a gamepad used last: \"walk in or X at its back\" (8.3 keys: the prompts' X)", words.Text == "Load the truck: walk in or X at its back" and shown(), words.Text)
M.gamepad = false
screen(false)
tick()
check("… a computer: \"walk in or E at its back\"", words.Text == "Load the truck: walk in or E at its back" and shown(), words.Text)
M.gamepad = true
tick()
check("… a computer's gamepad: \"walk in or X at its back\"", words.Text == "Load the truck: walk in or X at its back" and shown(), words.Text)
M.gamepad = false
screen(true)
tick()
check("… the chevron over the truck's back (its CargoDoor)", at(vanBack.x, vanBack.z + 10) and string.find(tag.Text, "THE TRUCK", 1, true) ~= nil, tag.Text)
local held = 0
M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.G }, false)
wait(G.HideHold + 0.02)
tick()
check("G held while carrying puts the piece down (the server's prompt): the guide stays", SandboxGuide.enabled())
M.services.UserInputService.InputEnded:Fire({ KeyCode = M.Enum.KeyCode.G })
local _ = held
local loaded = view({ counts = { total = 2, out = 1, stars = 1, starsOut = 1, broken = 0, carried = 0, home = 1, delivered = 0, starsDelivered = 0, lost = 0 } })
loaded.items[1].state = "truck"
moving.OnClientEvent:Fire("state", loaded)
tick()
b = hintBox()
check("9.7 the truck has things: \"Finish or beat the clock: load more, or FINISH at the truck\"", SandboxGuide.step() == "finish"
	and words.Text == "Finish or beat the clock: load more, or FINISH at the truck" and shown(), words.Text)
check("… on the screen, still clear of the money and the touch buttons (its words may wrap on a phone)", not overlap(b, moneyBox) and inside(b) and clearOfTouch(b), show(b))
check("… the chevron over the truck's back (its FINISH there), a straight path", at(vanBack.x, vanBack.z + 10) and lit() == 1 and string.find(tag.Text, "THE TRUCK", 1, true) ~= nil,
	`{tag.Text} {lit()}`)

-- ── Nothing made loop after loop ────────────────────────────────────────────
local before = made
for i = 1, 20 do
	stand(SandboxMap.House.curb.x + G.Near + 10, SandboxMap.House.curb.z + i * 0.7) -- (walking to the truck: the distance changes)
	tick()
end
check("twenty looks at the truck (the chevron on its back, its metres changing) make no instance", marker.Enabled and lit() > 0 and made == before, made - before)

-- ── Done once: quiet ───────────────────────────────────────────────────────
moving.OnClientEvent:Fire("state", view({ inside = true, counts = loaded.counts }))
tick()
check("in the house again: the carrying out was done, quiet", SandboxGuide.step() == "inside" and not hint.Visible)
moving.OnClientEvent:Fire("state", loaded)
stand(SandboxMap.House.curb.x + 6, SandboxMap.House.curb.z)
tick()
check("… out again, the truck loaded: finish still said (not done before the run's end)", SandboxGuide.step() == "finish" and shown())

-- ── No run: the stock on show, the portals ─────────────────────────────────
moving.OnClientEvent:Fire("state", nil)
stand(plot.door.x, plot.door.z + 6)
collection.OnClientEvent:Fire({ kind = "state", stock = {
	{ uid = "a", item = "sofa", variant = 1, condition = 0.9, name = "Sofa", got = 1 },
	{ uid = "b", item = "lamp", variant = 1, condition = 1, name = "Lamp", got = 1 },
	{ uid = "c", item = "vase", variant = 1, condition = 1, name = "Vase", stand = 2, got = 1 },
}, income = 4, stands = 3 })
tick()
check("pieces in the stock: \"Put your pieces on show: tap at an empty stand\"", SandboxGuide.step() == "show" and words.Text == "Put your pieces on show: tap at an empty stand" and shown(), words.Text)
M.gamepad = true
tick()
check("… with a gamepad: \"X at an empty stand\" (8.3 keys)", words.Text == "Put your pieces on show: X at an empty stand", words.Text)
M.gamepad = false
tick()
local nearest = SandboxSteps.nearestFree(plot.door.x, plot.door.z + 6, standsGiven, { [2] = true })
check("… the chevron over the nearest empty stand (shared/WarehouseLayout.luau's; the taken one skipped)", nearest ~= nil and nearest ~= 2
	and at(standsGiven[nearest].x, standsGiven[nearest].z) and string.find(tag.Text, "EMPTY STAND", 1, true) ~= nil, tag.Text)
-- 8.3: a level up (the WarehouseLevel attribute): the new building's spots, each plot and level's asked for once
attribute("WarehouseLevel", 5)
tick()
local nearest5 = SandboxSteps.nearestFree(plot.door.x, plot.door.z + 6, standsLevel5, { [2] = true })
check("8.3: a level up (WarehouseLevel 5): the chevron over the nearest empty stand of level 5's building", nearest5 ~= nil and nearest5 ~= 2
	and at(standsLevel5[nearest5].x, standsLevel5[nearest5].z) and string.find(tag.Text, "EMPTY STAND", 1, true) ~= nil, tag.Text)
tick()
attribute("WarehouseLevel", 4)
tick()
check("… back at level 4: its stands again; each plot and level's spots asked for once (WarehouseLayout.site, capacity)", at(standsGiven[nearest].x, standsGiven[nearest].z)
	and standsAsked["2@4"] == 1 and standsAsked["2@5"] == 1, `{standsAsked["2@4"]} {standsAsked["2@5"]}`)
M.player:SetAttribute("WarehouseLevel", nil)
collection.OnClientEvent:Fire({ kind = "state", stock = {
	{ uid = "a", item = "sofa", stand = 1 }, { uid = "b", item = "lamp", stand = 3 }, { uid = "c", item = "vase", stand = 2 },
}, income = 9, stands = 3 })
tick()
check("pieces on show: \"Your pieces earn money while you play. Walk into another house for more!\"", SandboxGuide.step() == "earn" and shown()
	and words.Text == "Your pieces earn money while you play. Walk into another house for more!", words.Text)
local p2, qx, qz = nearestPad(plot.door.x, plot.door.z + 6)
check("… the chevron on the nearest portal's pad", at(qx, qz) and string.find(tag.Text, string.upper(p2.name), 1, true) ~= nil, tag.Text)
for _ = 1, math.ceil(G.InfoSeconds / G.Every) + 1 do
	tick()
end
check("… said for a while (Config.SandboxGuide.InfoSeconds): then quiet", SandboxGuide.step() == "earn" and not hint.Visible and not marker.Enabled)
-- ── The next run: every step done once ─────────────────────────────────────
moving.OnClientEvent:Fire("state", loaded)
stand(SandboxMap.House.curb.x + 6, SandboxMap.House.curb.z)
tick()
check("the next run, its truck loaded: every step said once already (the run ended with things in the truck: finish done), quiet",
	SandboxGuide.step() == "finish" and not hint.Visible and not marker.Enabled)

-- ── A computer: a held G ────────────────────────────────────────────────────
screen(false)
M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.G }, true)
wait(G.HideHold + 0.02)
tick()
check("G taken by something else (gameProcessed): left alone", SandboxGuide.enabled())
M.services.UserInputService.InputEnded:Fire({ KeyCode = M.Enum.KeyCode.G })
M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.G }, false)
tick()
check("a short G: nothing", SandboxGuide.enabled())
wait(G.HideHold + 0.02)
tick()
b = hintBox()
check("G held: the guide off (\"Guide off · hold G to bring it back\"), no chip on a computer", not SandboxGuide.enabled() and not marker.Enabled
	and string.find(words.Text, "hold G", 1, true) ~= nil and shown() and not chip.Visible, words.Text)
check("… that line under the move's panel too", b.y0 >= box(panel).y1 and not overlap(b, box(panel)), show(b))
tick()
wait(G.HideHold + 0.02)
tick()
check("… still held: once a hold", not SandboxGuide.enabled())
M.services.UserInputService.InputEnded:Fire({ KeyCode = M.Enum.KeyCode.G })
M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.G }, false)
wait(G.HideHold + 0.02)
tick()
check("held again: back on (every step of the run said: still quiet)", SandboxGuide.enabled() and not marker.Enabled and lit() == 0)
M.services.UserInputService.InputEnded:Fire({ KeyCode = M.Enum.KeyCode.G })

-- ── 8.3 keys: a gamepad: B held as G ────────────────────────────────────────
local input = M.services.UserInputService
local B = M.Enum.KeyCode.ButtonB
M.gamepad = true
input.InputBegan:Fire({ KeyCode = B }, false)
tick()
check("a gamepad: a short B: nothing", SandboxGuide.enabled())
wait(G.HideHold + 0.02)
tick()
check("… B held: the guide off, \"Guide off · hold B to bring it back\", no 💡 chip", not SandboxGuide.enabled() and not marker.Enabled
	and words.Text == "Guide off · hold B to bring it back" and shown() and not chip.Visible, words.Text)
input.InputEnded:Fire({ KeyCode = B })
M.services.GuiService.SelectedObject = make("TextButton", { Name = "AWindowsButton" })
input.InputBegan:Fire({ KeyCode = B }, false)
wait(G.HideHold + 0.02)
tick()
check("… B while a window holds the gamepad's selection (B closes it): left alone", not SandboxGuide.enabled())
input.InputEnded:Fire({ KeyCode = B })
M.services.GuiService.SelectedObject = nil
input.InputBegan:Fire({ KeyCode = B }, false)
wait(G.HideHold + 0.02)
tick()
check("… B held again: back on", SandboxGuide.enabled())
input.InputEnded:Fire({ KeyCode = B })
moving.OnClientEvent:Fire("state", carried)
tick()
input.InputBegan:Fire({ KeyCode = B }, false)
wait(G.HideHold + 0.02)
tick()
check("… B held while carrying puts the piece down (the server's prompt): the guide stays", SandboxGuide.enabled())
input.InputEnded:Fire({ KeyCode = B })
moving.OnClientEvent:Fire("state", nil)
screen(true)
input.InputBegan:Fire({ KeyCode = B }, false)
wait(G.HideHold + 0.02)
tick()
check("a phone with a gamepad used last: B held: \"hold B\", no 💡 chip", not SandboxGuide.enabled() and words.Text == "Guide off · hold B to bring it back" and not chip.Visible, words.Text)
input.InputEnded:Fire({ KeyCode = B })
wait(G.OffNote + 0.02)
tick()
check("… the note gone: still no 💡 chip while the gamepad is used", not hint.Visible and not chip.Visible)
M.gamepad = false
tick()
check("… the screen touched (no gamepad used last): the 💡 chip", chip.Visible)
chip.Activated:Fire()
tick()
check("… a tap on it: back on", SandboxGuide.enabled())
screen(false)

-- ── 8.3: the soft steps (the UPGRADES desk, the market, the PAINT shop) ─────
-- at 844 × 390 (844 × 354 under the top bar), 1280 × 800 (1280 × 764) and 1920 × 1080 (1920 × 1044)
local WarehouseLayout = require("./WarehouseLayout")
G.SoftGap = 0.05 -- (the waits short: the check's own clock is the real one)
local coveredNow, windowNow = false, nil
SandboxGuide.covered = function()
	return coveredNow
end
SandboxGuide.windowOpen = function()
	return windowNow
end
local SIZES = { { true, 844, 354, "844 x 390" }, { false, 1280, 764, "1280 x 800" }, { false, 1920, 1044, "1920 x 1080" } }
-- the HUD's 📦 STOCK chip under the money (client/SandboxHud.luau's "StockChip" in its block)
local stockChipUi = make("TextButton", { Name = "StockChip", Position = M.UDim2.fromOffset(0, 64), Size = M.UDim2.fromOffset(150, 32), Visible = true }, money)
local ring = named(M.gui, "StockRing")
local function onScreenClear(what)
	local hb, cb2 = hintBox(), closeBox()
	local ok = shown() and inside(hb) and inside(cb2) and math.abs((hb.x0 + hb.x1) / 2 - M.width / 2) < 1 and hb.y0 < 40
		and not overlap(hb, box(money)) and not overlap(cb2, box(money))
	if M.touch then
		ok = ok and clearOfTouch(hb) and clearOfTouch(cb2) and cb2.x1 - cb2.x0 >= 44 - 0.01 and cb2.y1 - cb2.y0 >= 44 - 0.01
	else
		local list = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y0 = 0, x1 = M.width, y1 = math.min(M.height * 0.45, 52 + 40) }
		ok = ok and not overlap(hb, list) and not overlap(cb2, list)
	end
	check(`… {what}: the line at the top in the middle, on the screen, clear of the money{if M.touch then ", the touch buttons (its ✕ a finger's size)" else " and the player list"}`, ok, show(hb))
end
moving.OnClientEvent:Fire("state", nil)
lobby.OnClientEvent:Fire("lobby", nil)
stand(plot.door.x, plot.door.z + 6)
attribute(Config.SandboxUpgrades.WarehouseAttribute, 2)
local growTo = Config.SandboxUpgrades.List.warehouse.prices[2] -- (the Storehouse's price, 8.3 economy: Config's; $200 more in hand)
M.remotes.Upgrades.OnClientEvent:Fire({ kind = "state", levels = { warehouse = 1 }, money = growTo + 200 }) -- (level 2: the Workshop)
M.remotes.State.OnClientEvent:Fire({ money = growTo + 200 })
local market = { day = 20375, hot = { "jukebox" }, cold = { "sofa" }, left = 4000, demand = {} }
local function hotState(free)
	return { kind = "state", stands = 3, market = market, income = 9, stock = {
		{ uid = "a", item = "sofa", name = "Sofa", stand = 1, market = "cold" },
		{ uid = "c", item = "vase", name = "Vase", stand = 3 },
		{ uid = "b", item = "lamp", name = "Lamp", stand = if free then nil else 2 },
		{ uid = "j", item = "jukebox", name = "Jukebox", market = "hot" },
		{ uid = "k", item = "clock", name = "Clock" },
	} }
end
collection.OnClientEvent:Fire(hotState(true))
check("8.3: the guide asks for the UPGRADES' and the PAINT shop's states too", (function()
	local asked = {}
	for _, entry in M.sent do
		if type(entry.args[1]) == "table" and entry.args[1].kind == "state" then
			asked[entry.name] = true
		end
	end
	return asked.Upgrades == true and asked.VanPaint == true
end)())
local desk2 = WarehouseLayout.terminal(WarehouseLayout.site(plot, 2))
local desk1 = WarehouseLayout.terminal(WarehouseLayout.site(plot, 1))
for _, size in SIZES do
	screen(size[1], size[2], size[3])
	tick()
	check(`{size[4]}: the warehouse full (3 waiting, 1 free stand), {WarehouseLayout.money(growTo + 200)} at level 2: "Your warehouse is full: grow it at the UPGRADES desk ({WarehouseLayout.money(growTo)})"`,
		SandboxGuide.step() == "grow" and words.Text == `Your warehouse is full: grow it at the UPGRADES desk ({WarehouseLayout.money(growTo)})` and shown() and closeButton.Visible, words.Text)
	onScreenClear(size[4])
end
check("… the chevron over the UPGRADES desk at the level-2 warehouse's back wall (shared/WarehouseLayout.luau terminal), its tag", marker.Enabled
	and at(desk2.x, desk2.z) and string.find(tag.Text, "^UPGRADES DESK · %d+ m$") ~= nil and (desk1.z ~= desk2.z), `{tag.Text} {desk1.z} {desk2.z}`)
check("10.3 … no path on the ground once something of yours is home (Config.SandboxGuide.Path \"new\"): the chevron alone", lit() == 0, lit())
SandboxGuide.goTo(M.Vector3.new(desk2.x, 0, desk2.z), "UPGRADES DESK", 60)
tick()
check("10.3 … a place picked on the big map shows its path all the same", lit() >= 1, lit())
SandboxGuide.goTo(nil)
tick()
coveredNow = true
tick()
check("never while something covers the screen (a grip check, the result card, a window): quiet", SandboxGuide.step() ~= "grow" and not hint.Visible and not marker.Enabled)
coveredNow = false
tick()
check("… the window shut: not at once (SoftGap)", SandboxGuide.step() ~= "grow" and not hint.Visible)
wait(G.SoftGap + 0.02)
tick()
check("… then back", SandboxGuide.step() == "grow" and shown())
closeButton.Activated:Fire()
tick()
check("its ✕: that step alone dismissed, the guide stays on (no \"Guide off\")", SandboxGuide.enabled() and SandboxGuide.step() ~= "grow"
	and string.find(words.Text, "Guide off", 1, true) == nil and not hint.Visible, words.Text)
wait(G.SoftGap + 0.02)
tick()
check("… the next soft step after SoftGap: \"🔥 Your Jukebox is hot today: sell it or show it\" (the computer's words)", SandboxGuide.step() == "hot"
	and words.Text == "🔥 Your Jukebox is hot today: sell it or show it" and shown(), words.Text)
local free = standsGiven[2]
check("… a stand free: the chevron over it (EMPTY STAND), no ring round the chip", at(free.x, free.z) and string.find(tag.Text, "EMPTY STAND", 1, true) ~= nil and not ring.Visible, tag.Text)
collection.OnClientEvent:Fire(hotState(false))
for _, size in SIZES do
	screen(size[1], size[2], size[3])
	tick()
	local rb, chipB = box(ring), box(stockChipUi)
	check(`{size[4]}: every stand taken: no chevron, an orange ring round the 📦 STOCK chip (on the screen, round it)`, SandboxGuide.step() == "hot" and shown()
		and not marker.Enabled and ring.Visible and rb.x0 <= chipB.x0 and rb.y0 <= chipB.y0 and rb.x1 >= chipB.x1 and rb.y1 >= chipB.y1 and inside(rb)
		and (not M.touch or clearOfTouch(rb)) and not overlap(rb, hintBox()), `{show(rb)} / {show(chipB)}`)
	onScreenClear(size[4])
end
local before = made
for _ = 1, 20 do
	tick()
end
check("… twenty looks with the ring make no instance", ring.Visible and made == before, made - before)
coveredNow, windowNow = true, "WarehouseUi"
tick()
check("the STOCK list opened (it shows the 🔥 tags): the market found, the ring gone", not ring.Visible and not hint.Visible)
coveredNow, windowNow = false, nil
wait(G.SoftGap + 0.02)
tick()
check("… then another upgrade in reach (8.3 economy: the first nodes $1,500, the tree's order first): \"💡 New upgrade in reach: Hall spotlights at the UPGRADES desk ($1,500)\" (the desk again)", SandboxGuide.step() == "upgrade"
	and words.Text == "💡 New upgrade in reach: Hall spotlights at the UPGRADES desk ($1,500)" and shown() and at(desk2.x, desk2.z), words.Text)
local soft = G.SoftSeconds
G.SoftSeconds = 1
for _ = 1, math.ceil(1 / G.Every) + 1 do
	tick()
end
check("… said for a while (Config.SandboxGuide.SoftSeconds): then done and quiet", SandboxGuide.step() ~= "upgrade" and not hint.Visible)
G.SoftSeconds = soft
-- the PAINT shop: 9.7 the lobby's booth (SandboxMap.Lobby.shops.paint: its counter), nothing bought there yet
local booth = SandboxMap.Lobby.shops.paint.stand
M.remotes.VanPaint.OnClientEvent:Fire({ kind = "state", owned = {}, worn = { paint = "cream", livery = "zdc" }, money = growTo + 200, paid = {} })
wait(G.SoftGap + 0.02)
for _, size in SIZES do
	screen(size[1], size[2], size[3])
	tick()
	local want = "🎨 Make your truck your own at the PAINT SHOP"
	check(`{size[4]}: in the lobby, a level bought: "{want}" (9.7: its booth there)`, SandboxGuide.step() == "paint" and words.Text == want and shown(), words.Text)
	onScreenClear(size[4])
end
M.gamepad = true
tick()
check("… with a gamepad the same words (the booth's prompt shows its own button)", words.Text == "🎨 Make your truck your own at the PAINT SHOP", words.Text)
M.gamepad = false
tick()
check("… the chevron over the PAINT shop's counter in the lobby (PAINT SHOP)", at(booth.x, booth.z) and string.find(tag.Text, "PAINT SHOP", 1, true) ~= nil, tag.Text)
moving.OnClientEvent:Fire("state", view())
tick()
check("a run wins over every soft step (the front door)", SandboxGuide.step() == "door")
moving.OnClientEvent:Fire("state", nil)
wait(G.SoftGap + 0.02)
tick()
check("… the move gone: the paint step again", SandboxGuide.step() == "paint" and shown())
M.remotes.VanPaint.OnClientEvent:Fire({ kind = "bought", id = "red" })
tick()
check("something bought at the PAINT shop: done, quiet", SandboxGuide.step() ~= "paint" and not hint.Visible)

-- ── 8.4: Danny's steps (give him a piece, a heavy piece; 10.1 no hire) ──────
-- a move from your plot, Danny with you by your van (10.1 free), his body in workspace.Npcs (its MoveHelper your
-- MoveHelperId), the move's pieces' own prompts tagged MovePrompt (a heavy one's Lift)
local DANNY_ID = -2000000001
local npcs = make("Folder", { Name = "Npcs" }, M.workspace)
local dannyModel = make("Model", { Name = "Danny" }, npcs)
dannyModel:SetAttribute("MoveHelper", DANNY_ID)
local dannyAt = M.Vector3.new(plot.vanSpot.x + 6, 3, plot.vanSpot.z)
dannyModel.PrimaryPart = make("BasePart", { Name = "HumanoidRootPart", Position = dannyAt }, dannyModel) -- (the recorder's IsA: its own class)
local tagged, tagLooks = {}, 0
M.services.CollectionService.GetTagged = function(_, name)
	tagLooks += 1
	return tagged[name] or {}
end
-- the line under the move's panel and Danny's strip, in the middle, on the screen, clear of the money, the touch buttons
-- (its ✕ a finger's size) or Roblox's player list
local function dannyClear(what)
	local hb, cb2 = hintBox(), closeBox()
	local strip2, panel2 = box(MoveHelperHud.strip()), box(MovingHud.panel())
	local ok = shown() and inside(hb) and inside(cb2) and math.abs((hb.x0 + hb.x1) / 2 - M.width / 2) < 1 and hb.y0 >= strip2.y1 and cb2.y0 >= strip2.y1 - 0.01
		and not overlap(hb, panel2) and not overlap(cb2, panel2) and not overlap(hb, box(money)) and not overlap(cb2, box(money))
	if M.touch then
		ok = ok and clearOfTouch(hb) and clearOfTouch(cb2) and cb2.x1 - cb2.x0 >= 44 - 0.01 and cb2.y1 - cb2.y0 >= 44 - 0.01
	else
		local list = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y0 = 0, x1 = M.width, y1 = math.min(M.height * 0.45, 52 + 40) }
		ok = ok and not overlap(hb, list) and not overlap(cb2, list)
	end
	check(`… {what}: the line under the move's panel and Danny's strip, in the middle, on the screen, clear of the money{if M.touch then ", the touch buttons (its ✕ a finger's size)" else " and the player list"}`,
		ok, `{show(hb)} under {show(strip2)}`)
end
stand(plot.vanSpot.x - 14, plot.vanSpot.z)
attribute("MoveHelperId", DANNY_ID)
attribute("MoveHelperDoing", "Waiting at the van")
attribute("MoveHelperQueue", 0)
attribute("MoveHelper", "hired") -- (10.1: free, with you from the start)
moving.OnClientEvent:Fire("state", view())
wait(G.SoftGap + 0.02)
for _, size in SIZES do
	screen(size[1], size[2], size[3])
	tick()
	check(`10.1 {size[4]}: a move, Danny with you (free): no "Hire Danny" step; outside his list says nothing yet (the move's step: quiet)`,
		SandboxGuide.step() ~= "hire" and SandboxGuide.step() ~= "give" and not hint.Visible, SandboxGuide.step())
end
check("… no chevron over Danny (nothing to do with him out here)", not (marker.Enabled and at(dannyAt.X, dannyAt.Z + 0)))
moving.OnClientEvent:Fire("state", view({ inside = true }))
wait(G.SoftGap + 0.02)
for _, size in SIZES do
	screen(size[1], size[2], size[3])
	tick()
	-- (8.5 orders mode: the clipboard's key in the device's way, Q on a computer, its 📋 button on a phone)
	local want = if size[1] then "Take out your clipboard (tap 📋) and pick a piece for Danny" else "Take out your clipboard (Q) and pick a piece for Danny"
	check(`{size[4]}: in the house, his list empty: "{want}" (8.5: orders mode, the device's key)`, SandboxGuide.step() == "give"
		and words.Text == want and shown(), words.Text)
	dannyClear(size[4])
end
check("… no 3D target in the house", not marker.Enabled and lit() == 0)
M.gamepad = true
tick()
check("… with a gamepad: \"(R1)\" (8.5: R1 takes the clipboard out)", words.Text == "Take out your clipboard (R1) and pick a piece for Danny", words.Text)
M.player.Character:SetAttribute("ClipboardHeld", true) -- (8.5: the server's, the clipboard out)
tick()
check("8.5 the clipboard out: \"Pick a piece to give it to Danny (R1)\" with a gamepad (R1 at a piece)", words.Text == "Pick a piece to give it to Danny (R1)", words.Text)
M.gamepad = false
tick()
check("… a computer: \"Pick a piece to give it to Danny\" (a click: no key)", words.Text == "Pick a piece to give it to Danny" and shown(), words.Text)
M.player.Character:SetAttribute("ClipboardHeld", nil)
tick()
check("… put away again: the clipboard's words again", words.Text == "Take out your clipboard (Q) and pick a piece for Danny", words.Text)
attribute("MoveHelperName", "Zip")
tick()
check("10.1 the crew's helper with you (MoveHelperName Zip): \"… pick a piece for Zip\"", words.Text == "Take out your clipboard (Q) and pick a piece for Zip", words.Text)
attribute("MoveHelperName", nil)
tick()
attribute("MoveHelperQueue", 1)
tick()
check("… a piece given him (his list went up): give done, quiet", SandboxGuide.step() ~= "give" and not hint.Visible)
-- a heavy piece: the Sofa (two people, still in the house) near you, its own Lift prompt
local sofaPart = make("BasePart", { Name = "Root", Position = M.root.Position + M.Vector3.new(4, 0, 3) }, make("Model", { Name = "Sofa" }, M.workspace))
local lift = make("ProximityPrompt", { Name = "Pick", ActionText = "Lift", ObjectText = "Sofa", Enabled = true }, sofaPart)
lift:SetAttribute("MoveOwner", M.player.UserId)
tagged.MovePrompt = { lift }
local looksBefore = tagLooks
for _ = 1, 4 do
	tick()
end
check("8.4 a heavy piece looked for at most once a second (a few looks: one scan at most)", tagLooks - looksBefore <= 1, tagLooks - looksBefore)
wait(1.05)
for _, size in SIZES do
	screen(size[1], size[2], size[3])
	tick()
	check(`{size[4]}: a two-person piece near (its Lift): "Heavy piece: press Lift and wait for Danny"`, SandboxGuide.step() == "lift"
		and words.Text == "Heavy piece: press Lift and wait for Danny" and shown(), words.Text)
	dannyClear(size[4])
end
M.gamepad = true
tick()
check("… with a gamepad the same (the prompt's Lift shows its own button)", words.Text == "Heavy piece: press Lift and wait for Danny", words.Text)
M.gamepad = false
attribute("MoveHelperCall", "Sofa")
tick()
check("… your Lift called him (MoveHelperCall: you wait for him): lift done, quiet", SandboxGuide.step() ~= "lift" and not hint.Visible)
attribute("MoveHelperCall", nil)
wait(1.05)
looksBefore = tagLooks
for _ = 1, 10 do
	tick()
end
check("… done: no more looks for heavy pieces", tagLooks == looksBefore and SandboxGuide.step() ~= "lift", tagLooks - looksBefore)
before = made
for _ = 1, 20 do
	tick()
end
check("… twenty looks on a move with Danny make no instance", made == before, made - before)
moving.OnClientEvent:Fire("state", nil)
for _, name in { "MoveHelper", "MoveHelperQueue", "MoveHelperDoing", "MoveHelperId" } do
	attribute(name, nil)
end
tagged.MovePrompt = nil
tick()

-- ── 8.9: trading between players' step (set a price on a piece on show) ─────
-- no move; four pieces of yours on show on plot 2, none with a FOR SALE sign; the soft steps before it said already
local playersHere = { M.player }
M.services.Players.GetPlayers = function()
	return playersHere
end
local function onShow(signed)
	return { kind = "state", stands = 4, income = 12, market = market, stock = {
		{ uid = "s1", item = "sofa", name = "Sofa", stand = 1 },
		{ uid = "s2", item = "lamp", name = "Lamp", stand = 2, sale = if signed then 1500 else nil },
		{ uid = "s3", item = "vase", name = "Vase", stand = 3 },
		{ uid = "s4", item = "clock", name = "Clock", stand = 4 },
	} }
end
local nearStand = standsGiven[3]
stand(nearStand.x + 2, nearStand.z + 8)
collection.OnClientEvent:Fire(onShow(false))
wait(G.SoftGap + 0.02)
for _ = 1, 3 do
	tick()
end
check("8.9: four pieces on show, no sign, alone on the server: no sell step (nobody there to buy)", SandboxGuide.step() ~= "sell")
table.insert(playersHere, { UserId = 22, Name = "Ann" })
wait(1.05) -- (the players counted at most once a second)
local sellWords = "🏷 Sell to players: set a price on a piece on show"
for _, size in { { true, 844, 354, "844 x 390" }, { true, 667, 339, "667 x 375" }, { false, 1280, 764, "1280 x 800" }, { false, 1920, 1044, "1920 x 1080" } } do
	screen(size[1], size[2], size[3])
	tick()
	check(`{size[4]}: Ann here too: "{sellWords}" (the last soft step)`, SandboxGuide.step() == "sell" and words.Text == sellWords and shown() and closeButton.Visible, words.Text)
	local hb, cb2 = hintBox(), closeBox()
	local ok = inside(hb) and inside(cb2) and math.abs((hb.x0 + hb.x1) / 2 - M.width / 2) < 1 and not overlap(hb, box(money)) and not overlap(cb2, box(money))
	if M.touch then
		local here = TouchLayout.cluster(M.width, M.height, M.scale)
		local controls = TouchLayout.buttons(here)
		table.insert(controls, here.thumb)
		table.insert(controls, here.jump)
		for _, t in controls do
			ok = ok and not overlap(hb, t) and not overlap(cb2, t)
		end
		ok = ok and cb2.x1 - cb2.x0 >= 44 - 0.01 and cb2.y1 - cb2.y0 >= 44 - 0.01
	else
		local list = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y0 = 0, x1 = M.width, y1 = math.min(M.height * 0.45, 52 + 40 * #playersHere) } -- (two rows now)
		ok = ok and not overlap(hb, list) and not overlap(cb2, list)
	end
	check(`… {size[4]}: the line at the top in the middle, on the screen, clear of the money{if M.touch then ", the touch controls (its ✕ a finger's size)" else " and the player list (two players)"}`, ok, show(hb))
end
check("… the chevron over your nearest piece on show (its Set price prompt: SET PRICE)", marker.Enabled and at(nearStand.x, nearStand.z)
	and string.find(tag.Text, "^SET PRICE · %d+ m$") ~= nil, tag.Text)
M.gamepad = true
tick()
check("… with a gamepad the same words (the prompt shows its own button)", words.Text == sellWords, words.Text)
M.gamepad = false
coveredNow = true
tick()
check("… never while something covers the screen", SandboxGuide.step() ~= "sell" and not hint.Visible)
coveredNow = false
wait(G.SoftGap + 0.02)
tick()
check("… uncovered: back after SoftGap", SandboxGuide.step() == "sell" and shown())
collection.OnClientEvent:Fire(onShow(true))
tick()
check("a FOR SALE sign set: done, quiet", SandboxGuide.step() ~= "sell" and not hint.Visible)
collection.OnClientEvent:Fire(onShow(false))
wait(G.SoftGap + 0.02)
tick()
check("… the sign taken off again: not again (once a session)", SandboxGuide.step() ~= "sell" and not hint.Visible)
M.services.Players.GetPlayers = function()
	return { M.player }
end
SandboxGuide.covered, SandboxGuide.windowOpen = nil, nil
screen(false)
check("8.0.1: one arrow: through the whole move the move's HUD set no GPS (no waypoint, no GPS toast), only the guide's chevron and path",
	Config.Sandbox.On == true and gpsSets == 0 and gpsTold == 0 and M.waypoint == nil, `{gpsSets} {gpsTold}`)
check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL SANDBOX GUIDE CHECKS PASSED")
