-- 10.x the map: the big map (client/SandboxMapUi.luau) and a run's minimap (client/SandboxMiniMap.luau), run for real
-- with client/SandboxMapData.luau and client/SandboxMapDraw.luau on sandbox_mock.luau's recorder beside the real
-- client/SandboxHud.luau (the money block), client/SandboxTasksUi.luau (the TASKS chip) and client/RunUi.luau (a run; 10.4
-- client/PlayUi.luau's lobby bar), Hud's groups where client/Hud.luau puts them, on phones held sideways (844 × 390 and 667 × 375: under
-- Roblox's top bar, the touch layout), a computer (1280 × 800) and a big screen (1920 × 1080). The world: the players
-- (you, Ann), 10.4 the lobby's PLAY circle with server/Parties.luau's attribute (the open lobbies, the runs now), the
-- warehouses' levels, a run's interior with its
-- MapPlan (plans.luau: the real HouseLayout's farmstead, server/HouseInterior.luau's code), its loot (the LootPiece tag),
-- Danny, zombies near and far, the truck, the danger tags; the walls a stand-in ray (a piece in another room is hidden).
--   * the 🗺 MAP chip beside the TASKS chip (in its ScreenGui), as tall, on the screen, clear of the money block, the
--     chips, the touch controls and the lobby bar, a finger's size on a phone, M on a computer's key, the gamepad's L2;
--     it opens and closes the map;
--   * M opens it (a window: its onOpen ran), M again, B, the ✕, the shade, SandboxMapUi.close() (ESC) close it; L2 with
--     a gamepad on foot opens it, not while carrying or in a seat;
--   * the lobby: on the screen, its map and its side column (10.4: the PLAY row; OPEN LOBBIES, a row a lobby: its host
--     and house over its difficulty, n/4, FRIENDS ONLY, FULL, STARTING; 10.6 the QUICK ROUND row under PLAY: its next
--     place, its difficulty, the countdown, how many are queued; IN A RUN, a row a run: its house over its
--     difficulty and party; a finger's size on a phone), the plaza, the hedge, the plots (yours YOUR WAREHOUSE in gold,
--     its UPGRADES desk), PAINT, TOP MOVERS, DISPATCH, the PLAY circle (▶ PLAY over its line, its ring amber while a
--     lobby counts down), Ann's dot and name, you a ▲ turned your way; every label in the map, none on another, its
--     words fitting, 11 px at least; a click on the circle (the map's, the PLAY row or a lobby's row) has the guide show
--     the way to it (SandboxGuide.goTo) and closes the map;
--   * a run: the farmstead's floor plan (its rooms, walls, doorways, fixtures, windows, the FRONT DOOR at the bottom
--     and the BACK DOOR), the yard's strip with the truck under it, you, Ann, Danny, the zombie near (not the far one),
--     the loot under fog (seen in your room within 40 studs, never through a wall, kept once seen, gone once in the
--     truck; an Epic's pulse while loose, none in hands), the danger markers (🔒 🔑 🔥 💰 🆘), the side column's clock,
--     truck, fill and the dangers; drawn once (the same canvas after many looks, its markers pooled);
--   * the minimap in a run: in its corner (a phone's top right, a computer's bottom right), square, clear of the touch
--     controls, the chips, the move's panel and Danny's line, the 📋 button's first place, you in its middle, the loot
--     dots, its caption fitting; hidden in the lobby, under a window, during a grip check, with the HUD hidden; a tap
--     opens the big map; no warnings.
-- `luau sandboxmap.luau -a dump` prints the preview's scenes as JSON instead (sandboxmap_preview.py).
local M = require("./sandbox_mock")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local Rules = require("./SandboxMapRules")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local TopBlocks = require("./TopBlocks")
local TasksRules = require("./SandboxTasks")
local Plans = require("./plans")
local PartyRules = require("./PartyRules")

local dump = select(1, ...) == "dump"
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
		if node.Visible == false or (node.ClassName == "ScreenGui" and node.Enabled == false) then
			return false
		end
		node = node.Parent
	end
	return true
end
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		if not object.TextWrapped and not (object.TextTruncate and object.TextTruncate.Name == "AtEnd") and (object.Rotation or 0) == 0 then
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
local function smallTexts(root, least)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		if (object.TextSize or 14) * M.scaleOf(object) < least - 0.01 then
			table.insert(bad, `{object.Name} "{object.Text}" {object.TextSize}`)
		end
	end
	return bad
end
local function smallButtons(root)
	local small = {}
	for _, object in all(root, function(o)
		return o.ClassName == "TextButton" and shown(o) and o.Name ~= "MapShade" and o.Name ~= "MiniMap"
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end
-- the dark pills of words in a canvas (the map's own: not the people's names or the danger marks that move over it):
-- none on another
local function pillsOverlap(root)
	local pills = all(root, function(o)
		return o.ClassName == "TextLabel" and shown(o) and ((o.BackgroundTransparency or 1) < 1 or o.Name == "PlayLine") and o.Text ~= ""
			and o.Name ~= "PersonName" and o.Name ~= "Danger"
	end)
	for i = 1, #pills do
		for j = i + 1, #pills do
			local a, b = box(pills[i]), box(pills[j])
			if overlap(a, b) then
				return `{pills[i].Name} "{pills[i].Text}" on {pills[j].Name} "{pills[j].Text}"`
			end
		end
	end
	return nil
end
local function sameColor(a, b)
	return a and b and math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
end
local function rgb(c)
	return M.Color3.fromRGB(c[1], c[2], c[3])
end

-- ── The stand-ins ────────────────────────────────────────────────────────────
local V3 = M.Vector3.new
local baseIsA = M.methods.IsA
M.methods.IsA = function(self, class)
	if class == "BasePart" and (self.ClassName == "Part" or self.ClassName == "BasePart") then
		return true
	end
	return baseIsA(self, class)
end
M.methods.GetPivot = function(self)
	return { Position = if self.PrimaryPart then self.PrimaryPart.Position else V3(0, 0, 0) }
end
local addedSignals, removedSignals = {}, {}
M.services.CollectionService.GetInstanceAddedSignal = function(_, tag)
	addedSignals[tag] = addedSignals[tag] or M.signal()
	return addedSignals[tag]
end
M.services.CollectionService.GetInstanceRemovedSignal = function(_, tag)
	removedSignals[tag] = removedSignals[tag] or M.signal()
	return removedSignals[tag]
end
local function tag(instance, name)
	M.tagged[name] = M.tagged[name] or {}
	table.insert(M.tagged[name], instance)
	local s = addedSignals[name]
	if s then
		s:Fire(instance)
	end
end
local function untag(instance, name)
	local list = M.tagged[name] or {}
	local at = table.find(list, instance)
	if at then
		table.remove(list, at)
	end
	local s = removedSignals[name]
	if s then
		s:Fire(instance)
	end
end
-- the walls: a ray from your eyes to a piece is stopped when the piece is in another room than you (M.walls)
M.rays = 0
M.workspace.Raycast = function(_, from, direction)
	M.rays += 1
	local to = from + direction
	local blocked = M.walls and M.walls(from, to)
	return if blocked then { Instance = M.make("Part", { Name = "Wall" }) } else nil
end

-- the players
local players = { M.player }
M.services.Players.GetPlayers = function()
	return players
end
local function body(player, at, look)
	local character = player.Character or M.make("Model", { Name = player.Name })
	player.Character = character
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		root = M.make("BasePart", { Name = "HumanoidRootPart" }, character)
	end
	root.Position = at
	root.CFrame = { Position = at, LookVector = look or V3(0, 0, -1) }
	return root
end
M.root.Parent = nil
M.player.Character = nil
local me = body(M.player, V3(1800, 3, 10), V3(0, 0, 1))
M.player:SetAttribute("Plot", 2)
local ann = M.make("Player", { Name = "Ann", DisplayName = "Ann", UserId = 22 })
body(ann, V3(1700, 3, 40), V3(1, 0, 0))
ann:SetAttribute("Plot", 1)
table.insert(players, ann)

-- the world's folders
local world = M.make("Folder", { Name = "Sandbox" }, M.workspace)
local lobby = M.make("Model", { Name = "Lobby" }, world)
local playModel = M.make("Model", { Name = "PlayCircle" }, lobby) -- (10.4: server/LobbyWorld.luau's, its attribute server/Parties.luau's)
local halls = M.make("Folder", { Name = "Warehouses" }, M.workspace)
for id, level in { 3, 4, 2, 5 } do
	halls:SetAttribute(`Level{id}`, level)
end
local moves = M.make("Folder", { Name = "Moves" }, M.workspace)
local npcs = M.make("Folder", { Name = "Npcs" }, M.workspace)
local zombies = M.make("Folder", { Name = "Zombies" }, M.workspace)
local cars = M.make("Folder", { Name = "Cars" }, M.workspace)
for _, folder in { moves, npcs, zombies, cars } do
	folder.ChildAdded, folder.ChildRemoved = M.signal(), M.signal()
end

-- ── The HUD's chips, Hud's groups, the screens ─────────────────────────────
local groups = {}
for _, name in { "LeftStack", "HudButtons" } do
	groups[name] = M.make("Frame", { Name = name, BackgroundTransparency = 1 }, M.hudGui)
end
local function place(object, b)
	object.Position = M.UDim2.fromOffset(b.x0, b.y0)
	object.Size = M.UDim2.fromOffset(b.x1 - b.x0, b.y1 - b.y0)
end
-- the move's panel and Danny's line (client/MovingHud.luau, client/MoveHelperHud.luau: top blocks) while in a run
local topGui = M.make("ScreenGui", { Name = "MovingHud" }, M.gui)
local panelFrame = M.make("Frame", { Name = "MovePanel", Visible = false }, topGui)
local stripFrame = M.make("Frame", { Name = "MoveHelper", Visible = false }, topGui)
TopBlocks.set("MovePanel", panelFrame)
TopBlocks.set("MoveHelper", stripFrame)
local camera = M.workspace.CurrentCamera
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	local S = M.MUi.scaleFor(M.Vector2.new(w, h))
	if touch then
		place(groups.LeftStack, M.leftColumn)
		groups.HudButtons.Visible = false
	else
		place(groups.LeftStack, { x0 = 16, y0 = h - 16 - 30 * S, x1 = 16 + 200 * S, y1 = h - 16 })
		place(groups.HudButtons, { x0 = w - 16 - MoveLayout.PLAYER_LIST_W - 260 * S, y0 = 0, x1 = w, y1 = 4 + 90 * S })
		groups.HudButtons.Visible = true
	end
	local panel = MoveLayout.panel(w, S)
	place(panelFrame, panel)
	place(stripFrame, MoveLayout.strip(panel, S, 44))
	camera.ViewportSize = M.Vector2.new(w, h + 36)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	M.flush()
end

screen(true, 844, 354)
local SandboxHud = require("./SandboxHud")
local SandboxTasksUi = require("./SandboxTasksUi")
SandboxHud.start()
SandboxHud.setState({ money = 12480 })
M.flush()
SandboxTasksUi.start()
local NOW = 20372 * 86400 + 18 * 3600
local tasksView = TasksRules.view(TasksRules.fresh(42, NOW), NOW) :: any
tasksView.kind = "state"
M.remotes.SandboxTasks.OnClientEvent:Fire(tasksView)
M.flush()
local RunUi = require("./RunUi")
RunUi.start()
local SandboxMapUi = require("./SandboxMapUi")
local SandboxMiniMap = require("./SandboxMiniMap")
local Data = require("./SandboxMapData")
local Draw = require("./SandboxMapDraw")

-- Off: nothing
Config.Sandbox.On = false
SandboxMapUi.start()
SandboxMiniMap.start()
check("Config.Sandbox.On false: neither the map nor the minimap start (no chip, no gui)", SandboxMapUi.parts().chip == nil and SandboxMiniMap.frame() == nil)
Config.Sandbox.On = true
SandboxMapUi.start()
SandboxMiniMap.start()
SandboxMiniMap.covered = SandboxMapUi.isOpen -- (Main's: CameraRig.windowOpen, the big map one of its windows)
M.flush()
local opened = 0
SandboxMapUi.onOpen = function()
	opened += 1
end
local toasts = #M.toasts
local function key(code, gamepad)
	M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode[code], UserInputType = if gamepad then M.Enum.UserInputType.Gamepad1 else M.Enum.UserInputType.Keyboard }, false)
	M.flush()
end
local function look()
	SandboxMapUi.step()
	SandboxMiniMap.step()
	M.flush()
end

-- What the chip and the minimap keep clear of: the touch controls, Hud's groups, the chips.
local function chipBlocks()
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
		list["the key hints"] = box(groups.HudButtons)
	end
	list["the money block"] = box(SandboxHud.block())
	list["the TASKS chip"] = box(named(M.gui:FindFirstChild("SandboxTasksChip"), "TasksChip"))
	return list
end

-- ── The preview's scenes (sandboxmap_preview.py) ───────────────────────────
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
	out.rot = p.Rotation
	if p.Text and p.Text ~= "" then
		out.text, out.ts = p.Text, p.TextSize
		out.tc, out.tt = color(p.TextColor3), p.TextTransparency
		out.xa = if p.TextXAlignment then p.TextXAlignment.Name else nil
		out.font = if p.Font then p.Font.Name else nil
		out.wrap = p.TextWrapped == true
		out.trunc = p.TextTruncate ~= nil and p.TextTruncate.Name == "AtEnd"
		if p.TextStrokeTransparency ~= nil and p.TextStrokeTransparency < 1 then
			out.stroke, out.tst = color(p.TextStrokeColor3), p.TextStrokeTransparency
		end
	end
	if p.ClassName == "UICorner" then
		out.radius = { p.CornerRadius.Scale, p.CornerRadius.Offset }
	elseif p.ClassName == "UIStroke" then
		out.color, out.thick, out.tr = color(p.Color), p.Thickness, p.Transparency
	elseif p.ClassName == "UIScale" then
		out.scale = p.Scale
	elseif p.ClassName == "ScreenGui" then
		out.display = p.DisplayOrder or 0
		out.enabled = p.Enabled ~= false
	end
	local kids = {}
	for _, kid in n:GetChildren() do
		table.insert(kids, node(kid))
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
	local tree = node(M.gui)
	local overlay = {}
	if M.touch then
		local S2 = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		local cluster = TouchLayout.cluster(M.width, M.height, S2)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = tree })
end

-- ── The lobby: the open lobbies and the runs now (the PLAY circle's attribute), the chip ──
M.now = 1000
playModel:SetAttribute(Config.Runs.Party.Attribute, PartyRules.encode({
	{ host = "Ann", house = "old_mill", difficulty = "normal", n = 3, max = 4, friends = false, state = "starting" },
	{ host = "Bob", house = "pond_cabin", difficulty = "hard", n = 2, max = 4, friends = true, state = "open" },
	{ host = "Evangelina Longname", house = "orchard_cottage", difficulty = "nightmare", n = 4, max = 4, friends = false, state = "full" },
	{ host = "Cid", house = "sandbox_house", difficulty = "hard", n = 2, max = 4, friends = false, state = "run", who = "Cid, Dee" },
}))
-- 10.6 both in PLAY: the quick round's attributes on the circle (server/Runs.luau's): its next place, the countdown, 3 queued
for key, value in { RoundPhase = "wait", RoundHouse = "lone_house", RoundDifficulty = "insane", RoundEndsAt = M.now + 42, RoundQueued = 3, RoundMovers = 0 } do
	playModel:SetAttribute(key, value)
end

local SCREENS = { { true, 844, 354, "a phone (844 × 390)", "844x390" }, { true, 667, 339, "a small phone (667 × 375)", "667x375" },
	{ false, 1280, 764, "a computer (1280 × 800)", "1280x800" }, { false, 1920, 1044, "a big screen (1920 × 1080)", "1920x1080" } }

local function chipChecks(label)
	SandboxMapUi.arrange()
	local chip = SandboxMapUi.parts().chip
	local tasks = named(M.gui:FindFirstChild("SandboxTasksChip"), "TasksChip")
	check(`{label}: the 🗺 MAP chip in the TASKS chip's ScreenGui (what keeps clear of the chips keeps clear of it)`, chip ~= nil and chip.Parent == M.gui:FindFirstChild("SandboxTasksChip"))
	local c, t = box(chip), box(tasks)
	check(`{label}: … beside the TASKS chip, as tall, on the screen`, inside(c) and math.abs(c.y0 - t.y0) < 1 and math.abs((c.y1 - c.y0) - (t.y1 - t.y0)) < 1 and c.x0 >= t.x1, `{show(c)} by {show(t)}`)
	for name, other in chipBlocks() do
		check(`{label}: … clear of {name}`, not overlap(c, other), `{show(c)} on {show(other)}`)
	end
	check(`{label}: … its words fit`, #badTexts(chip) == 0, badTexts(chip)[1])
	local keyLabel = named(chip, "Key")
	if M.touch then
		check(`{label}: … a finger's size, no key shown`, #smallButtons(chip.Parent) == 0 and keyLabel.Visible == false, smallButtons(chip.Parent)[1])
	else
		check(`{label}: … its key M`, keyLabel.Visible and keyLabel.Text == "M")
	end
end

local function lobbyChecks(label)
	local parts = SandboxMapUi.parts()
	local window, map, side, canvas = parts.window, parts.map, parts.side, parts.canvas
	check(`{label}: the map open (a window: its onOpen ran), its gui on`, SandboxMapUi.isOpen() and parts.gui.Enabled and window ~= nil and opened > 0)
	local w = box(window)
	check(`{label}: … on the screen`, inside(w), show(w))
	check(`{label}: … its map and its side column in it`, within(box(map), w) and side ~= nil and within(box(side), w) and not overlap(box(map), box(side)))
	check(`{label}: … the lobby drawn: the hedge, the meadow, the plaza, the fountain, 4 plots and warehouses with their desks, PAINT, TOP MOVERS, DISPATCH, the PLAY circle`,
		named(map, "Hedge") and named(map, "Meadow") and named(map, "Plaza") and named(map, "Fountain") and named(map, "Plot4") and named(map, "Warehouse4") and named(map, "Desk4")
			and named(map, "Paint") and named(map, "Leaders") and named(map, "Dispatch") and named(map, "PlayCircle") and named(map, "Portal_orchard_cottage") == nil and true)
	check(`{label}: … your plot named in gold (YOUR WAREHOUSE) with its UPGRADES desk, Ann's by her name`, named(map, "PlotName2").Text == "YOUR" and named(map, "PlotName2b").Text == "WAREHOUSE"
		and sameColor(named(map, "PlotName2").TextColor3, rgb(Config.SandboxMapUi.Colors.Yours)) and named(map, "Upgrades") ~= nil and named(map, "PlotName1").Text == "ANN"
		and named(map, "PlotName3").Text == "FREE")
	local W = Config.Runs.Play
	local circle, playName, playLine = named(map, "PlayCircle"), named(map, "PlayName"), named(map, "PlayLine")
	local cb = box(circle)
	check(`{label}: … the PLAY circle round (as wide as tall), its ring amber (Ann's lobby counts down)`, math.abs((cb.x1 - cb.x0) - (cb.y1 - cb.y0)) < 1.01 and cb.x1 - cb.x0 >= 8
		and sameColor(named(circle, "Ring").Color, rgb(W.Waiting)), show(cb))
	check(`{label}: … ▶ PLAY over its line STARTING beside it, both shown, clear of the circle`, shown(playName) and shown(playLine) and playName.Text == "▶ PLAY" and playLine.Text == "STARTING"
		and box(playLine).y0 >= box(playName).y1 - 0.01 and not overlap(box(playName), cb) and not overlap(box(playLine), cb), `{playLine.Text} {show(box(playName))} {show(box(playLine))} by {show(cb)}`)
	local rows, play = parts.rows, parts.play
	check(`{label}: … the side column: the PLAY row (▶ THE PLAY CIRCLE), OPEN LOBBIES (Ann's STARTING, Bob's FRIENDS ONLY, the full one), IN A RUN (the farmstead, its party)`,
		play ~= nil and play.top.Text == "▶ THE PLAY CIRCLE" and rows ~= nil and rows[1].row.Visible and rows[1].top.Text == "ANN · THE OLD MILL" and rows[1].bottom.Text == "STARTING · NORMAL · 3/4"
			and rows[2].top.Text == "BOB · THE POND CABIN" and rows[2].bottom.Text == "HARD · 2/4 · FRIENDS ONLY" and rows[3].bottom.Text == "NIGHTMARE · 4/4 · FULL"
			and rows[4].top.Text == "THE OLD FARMSTEAD" and rows[4].bottom.Text == "IN A RUN · HARD · Cid, Dee" and not rows[5].row.Visible
			and shown(named(side, "OpenTitle")) and shown(named(side, "RunsTitle")) and not shown(named(side, "None")),
		rows and `{rows[1].top.Text} / {rows[1].bottom.Text} / {rows[2].bottom.Text} / {rows[3].bottom.Text} / {rows[4].top.Text} / {rows[4].bottom.Text}`)
	local quick = parts.quick
	check(`{label}: … 10.6 the QUICK ROUND row under PLAY: its next place, the countdown, 3 queued`, quick ~= nil and quick.row.Visible
		and quick.top.Text == "⚡ THE LONE HOUSE" and quick.bottom.Text == "NEXT · INSANE · 0:42 · 3 QUEUED" and shown(named(side, "QuickTitle")),
		quick and `{quick.top.Text} / {quick.bottom.Text}`)
	local order = { play.row, named(side, "QuickTitle"), quick.row, named(side, "OpenTitle"), rows[1].row, rows[2].row, rows[3].row, named(side, "RunsTitle"), rows[4].row, named(side, "LegendTitle") }
	local stacked = nil
	for n = 2, #order do
		if box(order[n]).y0 < box(order[n - 1]).y1 - 0.01 then
			stacked = `{order[n].Name} {show(box(order[n]))} on {order[n - 1].Name} {show(box(order[n - 1]))}`
		end
	end
	check(`{label}: … its rows down the column in that order, none on another, the legend under them`, stacked == nil, stacked)
	local mapBox = box(map)
	local outside = nil
	for _, o in all(map, function(o)
		return o.ClassName == "TextLabel" and shown(o) and o.Text ~= ""
	end) do
		if not within(box(o), mapBox) then
			outside = `{o.Name} "{o.Text}" {show(box(o))}`
		end
	end
	check(`{label}: … every label in the map`, outside == nil, outside)
	check(`{label}: … no label on another`, pillsOverlap(map) == nil, pillsOverlap(map))
	check(`{label}: … the words fit`, #badTexts(window) == 0, badTexts(window)[1])
	check(`{label}: … readable: 11 px and more`, #smallTexts(window, 11) == 0, smallTexts(window, 11)[1])
	if M.touch then
		check(`{label}: … a finger's size (the ✕, the rows, the PLAY circle)`, #smallButtons(window) == 0, smallButtons(window)[1])
	end
	-- the people: Ann's dot and name, you a ▲ turned your way (south: 180°)
	local you = named(map, "You")
	local f = canvas.frame
	local x, y = Rules.toMap(f, 1800, 10)
	check(`{label}: … you a ▲ where you stand, turned your way (south)`, you ~= nil and you.Visible and math.abs(math.abs(you.Rotation) - 180) < 0.6
		and math.abs(you.Position.X.Offset - x) < 1 and math.abs(you.Position.Y.Offset - y) < 1)
	local annName = all(map, function(o)
		return o.Name == "PersonName" and o.Text == "Ann" and shown(o)
	end)[1]
	check(`{label}: … Ann a dot with her name`, annName ~= nil and named(map, "Person").Visible)
end

for _, s in SCREENS do
	screen(s[1], s[2], s[3])
	local label = s[4]
	chipChecks(label)
	opened = 0
	key("M")
	lobbyChecks(label)
	scene(`map-lobby-{s[5]}`)
	key("M")
	check(`{label}: M again closes it`, not SandboxMapUi.isOpen() and not SandboxMapUi.parts().gui.Enabled)
end

-- the chip opens and closes it; B, the ✕, the shade and ESC (Main's close) close it
screen(false, 1280, 764)
local chip = SandboxMapUi.parts().chip
chip.Activated:Fire()
M.flush()
check("the 🗺 MAP chip opens the map", SandboxMapUi.isOpen())
chip.Activated:Fire()
M.flush()
check("… and closes it", not SandboxMapUi.isOpen())
SandboxMapUi.open()
key("ButtonB", true)
check("the gamepad's B closes it", not SandboxMapUi.isOpen())
SandboxMapUi.open()
named(SandboxMapUi.parts().window, "Close").Activated:Fire()
M.flush()
check("the ✕ closes it", not SandboxMapUi.isOpen())
SandboxMapUi.open()
SandboxMapUi.parts().gui:FindFirstChild("MapShade").Activated:Fire()
M.flush()
check("a click beside the window closes it", not SandboxMapUi.isOpen())
SandboxMapUi.open()
SandboxMapUi.close()
check("SandboxMapUi.close() (ESC: Main's Hud.onCloseWindows) closes it", not SandboxMapUi.isOpen())
-- the gamepad's L2: on foot opens it; carrying or in a seat not
M.gamepad = true
M.inputChanged()
key("ButtonL2", true)
check("a gamepad's L2 on foot opens it, B closes it", SandboxMapUi.isOpen())
key("ButtonB", true)
M.player.Character:SetAttribute("Carrying", "box")
key("ButtonL2", true)
check("… not while carrying (B would put the piece down)", not SandboxMapUi.isOpen())
M.player.Character:SetAttribute("Carrying", nil)
local humanoid = M.make("Humanoid", { Name = "Humanoid", SeatPart = M.make("Part", { Name = "Seat" }) }, M.player.Character)
key("ButtonL2", true)
check("… not in a seat (L2 is the brake there)", not SandboxMapUi.isOpen())
humanoid.Parent = nil
SandboxMapUi.arrange()
local padKey = named(SandboxMapUi.parts().chip, "Key")
check("… the chip's key with a gamepad: the platform's L2 glyph", padKey.Visible and padKey.Text == "" and named(padKey, "Pad") ~= nil and string.find(named(padKey, "Pad").Image, "ButtonL2", 1, true) ~= nil)
M.gamepad = false
M.inputChanged()
SandboxMapUi.arrange()

-- 10.4 the PLAY circle picked: the guide shows the way to it; the map closes
SandboxMapUi.open()
SandboxMapUi.parts().play.row.Activated:Fire()
M.flush()
local P = SandboxMap.Lobby.play
local guided = M.guided[#M.guided]
check("a click on the PLAY row: the guide shows the way to the PLAY circle (SandboxGuide.goTo), the map closes, a toast says so", guided ~= nil and guided.label == "PLAY"
	and math.abs(guided.at.X - P.x) < 0.01 and math.abs(guided.at.Z - P.z) < 0.01 and not SandboxMapUi.isOpen()
	and #M.toasts > toasts and string.find(M.toasts[#M.toasts], "PLAY", 1, true) ~= nil)
SandboxMapUi.open()
local guides = #M.guided
SandboxMapUi.parts().rows[2].row.Activated:Fire()
M.flush()
check("… a click on an open lobby's row too (it is joined in the circle)", #M.guided == guides + 1 and M.guided[#M.guided].label == "PLAY" and not SandboxMapUi.isOpen())
SandboxMapUi.open()
local onMap = all(SandboxMapUi.parts().map, function(o)
	return o.Name == "PlayButton"
end)[1]
onMap.Activated:Fire()
M.flush()
check("… a click on the circle on the map too", #M.guided == guides + 2 and M.guided[#M.guided].label == "PLAY" and not SandboxMapUi.isOpen())

-- 10.4 the lobby bar (client/PlayUi.luau) of a small phone may stand where the chip would be: the chip waits
screen(true, 667, 339)
tasksView = TasksRules.view(TasksRules.fresh(42, NOW), NOW) :: any
tasksView.kind = "state"
tasksView.ready = 1
M.remotes.SandboxTasks.OnClientEvent:Fire(tasksView)
M.flush()
local me14 = M.player.UserId
M.remotes.Party.OnClientEvent:Fire({ kind = "play", circle = false, me = me14, open = { "easy", "normal" }, houses = {}, lobbies = {},
	lobby = { id = 3, host = me14, hostName = "Courier", mine = true, house = "sandbox_house", name = "The Old Farmstead", difficulty = "normal", friends = false, max = 4,
		ready = 0, open = { "easy", "normal" }, canStart = false, members = { { id = me14, name = "Courier", ready = false, host = true } } } })
M.flush()
SandboxMapUi.arrange()
local lobbyBar = named(M.gui:FindFirstChild("PlayUi"), "PlayBar")
local chipNow = SandboxMapUi.parts().chip
check("a small phone with the lobby bar up: the chip never on it (it waits when it would be)", lobbyBar ~= nil and shown(lobbyBar)
	and (not chipNow.Visible or not overlap(box(chipNow), box(lobbyBar))))
M.remotes.Party.OnClientEvent:Fire({ kind = "play" })
tasksView.ready = 0
M.remotes.SandboxTasks.OnClientEvent:Fire(tasksView)
M.flush()
SandboxMapUi.arrange()
check("… out of the lobby: it is back", SandboxMapUi.parts().chip.Visible)

-- ── A run: the farmstead ─────────────────────────────────────────────────────
local farm = Plans.big
local O = farm.origin
local interior = M.make("Model", { Name = "HouseInterior" }, moves)
interior:SetAttribute("MapPlan", farm.code)
interior:SetAttribute("Kind", "big")
interior:SetAttribute("Seed", farm.seed)
interior:SetAttribute("RunDifficulty", "hard")
local shell = M.make("Folder", { Name = "Shell" }, interior)
local items = M.make("Folder", { Name = "Items" }, interior)
moves.ChildAdded:Fire(interior)
local plan = Rules.decode(farm.code)
local function world(lx, lz, y)
	return V3(O.x + lx, O.y + (y or 3), O.z + lz)
end
local function roomAt(lx, lz)
	for _, r in plan.rooms do
		if lx >= r.x0 - 0.6 and lx <= r.x1 + 0.6 and lz >= r.z0 - 0.6 and lz <= r.z1 + 0.6 then
			return r.id
		end
	end
	return nil
end
M.walls = function(from, to)
	return roomAt(from.X - O.x, from.Z - O.z) ~= roomAt(to.X - O.x, to.Z - O.z)
end
-- the pieces (their rarities: the first ones rare, a legendary and an epic in the living room)
local RARITY = { "common", "uncommon", "rare", "common", "epic", "common", "legendary", "uncommon" }
local pieces = {}
local living = {}
for n, s in farm.spots do
	local model = M.make("Model", { Name = s.item }, items)
	local root = M.make("Part", { Name = "Root", Position = world(s.x, s.z, s.y + 1) }, model)
	model.PrimaryPart = root
	model:SetAttribute("MoveSpot", s.id)
	model:SetAttribute("Rarity", RARITY[(n - 1) % #RARITY + 1])
	tag(model, Config.Loot.Tag)
	pieces[s.id] = { model = model, spot = s }
	if s.room == "living" then
		table.insert(living, s)
	end
end
-- Danny, a zombie near and one far, the truck at the curb, the dangers
local house = SandboxMap.house("sandbox_house")
local danny = M.make("Model", { Name = "Danny" }, npcs)
danny.PrimaryPart = M.make("Part", { Name = "HumanoidRootPart", Position = world(20, 20) }, danny)
danny:SetAttribute("MoveHelper", 1)
local nearZombie = M.make("Model", { Name = "Zombie" }, zombies)
nearZombie.PrimaryPart = M.make("Part", { Name = "Root", Position = world(-20, 14) }, nearZombie)
local farZombie = M.make("Model", { Name = "Zombie" }, zombies)
farZombie.PrimaryPart = M.make("Part", { Name = "Root", Position = world(60, 70) }, farZombie)
local truck = M.make("Model", { Name = "Sprinter" }, cars)
truck.PrimaryPart = M.make("Part", { Name = "Chassis", Position = V3(house.curb.x, 1, house.curb.z) }, truck)
truck:SetAttribute(Config.Runs.Truck.Attribute, true)
local lock = M.make("Part", { Name = "Lock", Position = world(-16.5, 38, 4) }, interior)
lock:SetAttribute("Open", false)
tag(lock, "RunLock")
local keyPart = M.make("Part", { Name = "Key", Position = world(30, 60, 2) }, interior)
tag(keyPart, "RunKey")
local fire = M.make("Part", { Name = "Fire", Position = world(-40, 20, 1) }, interior)
fire:SetAttribute("Kind", "fire")
tag(fire, "RunHazard")
local vault = M.make("Part", { Name = "Vault", Position = world(60, 70, 2) }, interior)
vault:SetAttribute("Open", true)
tag(vault, "RunVault")
local rescue = M.make("Part", { Name = "Rescue", Position = world(-45, 70, 2) }, interior)
tag(rescue, "RunRescue")

-- the run: RunUi's view and the Moving state (its contract the house, its clock, the truck's load, the items' states)
local function movingState(states)
	local list = {}
	for id, p in pieces do
		table.insert(list, { spot = id, name = p.spot.item, state = states[id] or "home" })
	end
	M.remotes.Moving.OnClientEvent:Fire("state", { contract = "sandbox_house", name = "The Old Farmstead", endsAt = M.now + 463, counts = { out = 6, total = #farm.spots, stars = 2 },
		fill = 0.45, items = list, run = { difficulty = "hard", name = "Hard", host = "Courier", mine = true } })
	M.flush()
end
M.remotes.Runs.OnClientEvent:Fire({ kind = "run", house = "sandbox_house", name = "The Old Farmstead", difficulty = "hard", host = 14, hostName = "Courier", mine = true, members = 2, votes = 0, voted = false })
movingState({})
-- you in the hall looking into the house, Ann in the living room
local hall = plan.rooms[1]
local hx, hz = (hall.x0 + hall.x1) / 2, hall.z0 + 6
body(M.player, world(hx, hz), V3(0, 0, 1))
local livingRoom
for _, r in plan.rooms do
	if r.id == "living" then
		livingRoom = r
	end
end
body(ann, world((livingRoom.x0 + livingRoom.x1) / 2, (livingRoom.z0 + livingRoom.z1) / 2), V3(-1, 0, 0))

local place = Data.place()
check("a run: SandboxMapData's place is the farmstead with its interior's plan (MapPlan) and its yard", place.kind == "run" and place.house == "sandbox_house" and place.plan ~= nil
	and place.interior == interior and place.yard ~= nil and place.difficulty == "Hard")

-- the fog: what you see from the hall
local function seenNow()
	local count = 0
	for _, p in pieces do
		if Data.seen(p.model) then
			count += 1
		end
	end
	return count
end
check("the fog: nothing seen before a look", seenNow() == 0)
M.rays = 0
Data.look()
local bad = nil
for _, p in pieces do
	local d = (p.model.PrimaryPart.Position - (M.player.Character:FindFirstChild("HumanoidRootPart").Position + V3(0, Config.SandboxMapUi.Fog.Eye, 0))).Magnitude
	local same = roomAt(p.spot.x, p.spot.z) == "hall"
	if Data.seen(p.model) and not (same and d <= Config.SandboxMapUi.Fog.See) then
		bad = `{p.spot.item} in {p.spot.room} seen ({d})`
	end
end
check("… a look: the pieces in your room within 40 studs seen, none through a wall, none farther", bad == nil and M.rays <= Config.SandboxMapUi.Fog.Most, bad)
local before = seenNow()
-- you walk into the living room: its pieces seen too, the hall's stay seen
body(M.player, world((livingRoom.x0 + livingRoom.x1) / 2, (livingRoom.z0 + livingRoom.z1) / 2), V3(1, 0, 0))
for _ = 1, 4 do
	Data.look()
end
local livingSeen = 0
for _, s in living do
	if Data.seen(pieces[s.id].model) then
		livingSeen += 1
	end
end
check("… walking into the living room: its pieces seen (the nearest Fog.Most a look), the hall's kept", livingSeen > 0 and seenNow() >= before + livingSeen, `{livingSeen} of {#living}`)
body(M.player, world(hx, hz), V3(0, 0, 1))

local function runChecks(label)
	local parts = SandboxMapUi.parts()
	local window, map, side, canvas = parts.window, parts.map, parts.side, parts.canvas
	check(`{label}: the run's map open, on the screen`, SandboxMapUi.isOpen() and inside(box(window)), show(box(window)))
	check(`{label}: … the farmstead's floor plan: its walls, its rooms, its doorways, its windows, its fixtures, the yard and its asphalt`, named(map, "Walls") and named(map, "Room_kitchen")
		and named(map, "Room_garage") and named(map, "Door1") and named(map, "Window1") and named(map, "Fixture1") and named(map, "Yard") and named(map, "Road") and true)
	local front = all(map, function(o)
		return o.ClassName == "TextLabel" and o.Text == "FRONT DOOR"
	end)[1]
	local back = all(map, function(o)
		return o.ClassName == "TextLabel" and o.Text == "BACK DOOR"
	end)[1]
	check(`{label}: … the FRONT DOOR at the bottom (under the rooms), the BACK DOOR named`, front ~= nil and back ~= nil and box(front).y0 > box(named(map, "Room_kitchen")).y1 - 1)
	local truckBox = box(named(map, "Truck"))
	check(`{label}: … the truck in the yard's strip under the house`, within(truckBox, box(named(map, "Yard"))) and truckBox.y0 > box(named(map, "Walls")).y1 - 1, show(truckBox))
	-- the people
	local f = canvas.frame
	local you = named(map, "You")
	local lx, lz = hx, hz
	local x, y = Rules.toMap(f, lx, lz)
	check(`{label}: … you a ▲ in the hall pointing up (into the house)`, you.Visible and math.abs(you.Rotation or 0) < 0.6 and math.abs(you.Position.X.Offset - x) < 1 and math.abs(you.Position.Y.Offset - y) < 1)
	local names = {}
	for _, o in all(map, function(o)
		return o.Name == "PersonName" and shown(o)
	end) do
		names[o.Text] = o
	end
	check(`{label}: … Ann (your party, gold) and Danny (orange) with their names`, names.Ann ~= nil and names.Danny ~= nil and sameColor(names.Ann.TextColor3, rgb(Config.SandboxMapUi.Colors.Party))
		and sameColor(names.Danny.TextColor3, rgb(Config.SandboxMapUi.Colors.Helper)))
	local reds = 0
	for _, o in all(map, function(o)
		return o.Name == "Person" and shown(o) and sameColor(o.BackgroundColor3, rgb(Config.SandboxMapUi.Colors.Zombie))
	end) do
		reds += 1
	end
	check(`{label}: … the zombie near you a red dot, not the far one`, reds == 1)
	-- the loot
	local dots = all(map, function(o)
		return o.Name == "Loot" and shown(o)
	end)
	check(`{label}: … the loot you saw (and only that) in its tiers' colours`, #dots == seenNow() and #dots > 0, `{#dots} dots, {seenNow()} seen`)
	-- the dangers
	local icons = {}
	for _, o in all(map, function(o)
		return o.Name == "Danger" and shown(o)
	end) do
		icons[o.Text] = true
	end
	check(`{label}: … the dangers' markers: 🔒 (locked), 🔑, 🔥 (a hazard's kind), 💰 (an open vault), 🆘`, icons["🔒"] and icons["🔑"] and icons["🔥"] and icons["💰"] and icons["🆘"] and true)
	-- the side column
	local lines = parts.lines
	check(`{label}: … the side column: the clock, the truck's load, the van's fill, the dangers`, lines.clock.Text == "⏱ 7:43" and lines.truck.Text == `🚚 IN THE TRUCK 6 / {#farm.spots}`
		and lines.fill.Text == "VAN 45 % FULL" and string.find(lines.danger.Text, "🔒", 1, true) ~= nil, lines.clock.Text)
	local mapBox = box(map)
	local outside = nil
	for _, o in all(map, function(o)
		return o.ClassName == "TextLabel" and shown(o) and o.Text ~= "" and o.Name ~= "TruckName" and o.Name ~= "PersonName" and o.Name ~= "Danger"
	end) do
		if not within(box(o), mapBox) then
			outside = `{o.Name} "{o.Text}" {show(box(o))}`
		end
	end
	check(`{label}: … every label in the map`, outside == nil, outside)
	check(`{label}: … the words fit`, #badTexts(window) == 0, badTexts(window)[1])
	check(`{label}: … readable: 11 px and more`, #smallTexts(window, 11) == 0, smallTexts(window, 11)[1])
	if M.touch then
		check(`{label}: … a finger's size`, #smallButtons(window) == 0, smallButtons(window)[1])
	end
end

for _, s in SCREENS do
	screen(s[1], s[2], s[3])
	panelFrame.Visible, stripFrame.Visible = true, true
	SandboxMapUi.open()
	runChecks(s[4])
	scene(`map-run-{s[5]}`)
	-- drawn once: the same canvas after more looks, its markers pooled
	local canvas = SandboxMapUi.parts().canvas
	local count = #canvas.root:GetChildren()
	for _ = 1, 5 do
		look()
	end
	check(`{s[4]}: … drawn once (the same canvas after five looks, no more pieces in it)`, SandboxMapUi.parts().canvas == canvas and #canvas.root:GetChildren() == count)
	SandboxMapUi.close()
end

-- the loot carried out: gone; an Epic's pulse while it is loose, none in hands
screen(false, 1280, 764)
local epic = nil
for _, p in pieces do
	if Data.seen(p.model) and (p.model:GetAttribute("Rarity") == "epic" or p.model:GetAttribute("Rarity") == "legendary") then
		epic = p
	end
end
check("(an Epic or a Legendary seen)", epic ~= nil)
SandboxMapUi.open()
local function ringOf(model)
	local canvas = SandboxMapUi.parts().canvas
	local f = canvas.frame
	local x, z = model.PrimaryPart.Position.X - O.x, model.PrimaryPart.Position.Z - O.z
	local px, py = Rules.toMap(f, x, z)
	for _, entry in canvas.pool.loot do
		if entry.dot.Visible and math.abs(entry.dot.Position.X.Offset - px) < 1 and math.abs(entry.dot.Position.Y.Offset - py) < 1 then
			return entry
		end
	end
	return nil
end
local entry = ringOf(epic.model)
check("an uncarried Epic or Legendary pulses (a looping ring)", entry ~= nil and entry.ring.Visible and entry.tweens ~= nil)
movingState({ [epic.spot.id] = "carried" })
look()
entry = ringOf(epic.model)
check("… in somebody's hands: shown, no pulse", entry ~= nil and not entry.ring.Visible and entry.tweens == nil)
local dotsBefore = #all(SandboxMapUi.parts().map, function(o)
	return o.Name == "Loot" and shown(o)
end)
movingState({ [epic.spot.id] = "truck" })
look()
local dotsAfter = #all(SandboxMapUi.parts().map, function(o)
	return o.Name == "Loot" and shown(o)
end)
check("… loaded in the truck: off the map (carried out)", dotsAfter == dotsBefore - 1 and ringOf(epic.model) == nil)
movingState({})
SandboxMapUi.close()

-- ── The minimap ──────────────────────────────────────────────────────────────
local function miniBlocks()
	local list = chipBlocks()
	list["the 🗺 MAP chip"] = box(SandboxMapUi.parts().chip)
	list["the move's panel"] = box(panelFrame)
	list["Danny's line"] = box(stripFrame)
	if M.touch then
		local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		local clip = Config.MoveHelper.Clipboard
		list["the 📋 button's place"] = MoveLayout.tapSpots(M.width, M.height, S, math.max(clip.ButtonMin, 44, clip.Button * S))[1]
	end
	return list
end
for _, s in SCREENS do
	screen(s[1], s[2], s[3])
	panelFrame.Visible, stripFrame.Visible = true, true
	SandboxMiniMap.step()
	SandboxMiniMap.step()
	local mini = SandboxMiniMap.frame()
	local label = s[4]
	local b = box(mini)
	local C = Config.SandboxMapUi.Mini
	check(`{label}: the minimap in a run, square, on the screen`, mini.Visible and inside(b) and math.abs((b.x1 - b.x0) - (b.y1 - b.y0)) < 1 and b.x1 - b.x0 >= C.Least - 0.5, show(b))
	if M.touch then
		check(`{label}: … at the top right`, math.abs(b.x1 - (M.width - C.Margin)) < 1 and math.abs(b.y0 - C.Top) < 1, show(b))
	else
		check(`{label}: … at the bottom right`, math.abs(b.x1 - (M.width - C.Margin)) < 1 and math.abs(b.y1 - (M.height - C.Margin)) < 1, show(b))
	end
	for name, other in miniBlocks() do
		check(`{label}: … clear of {name}`, not overlap(b, other), `{show(b)} on {show(other)}`)
	end
	local canvas = SandboxMiniMap.canvas()
	local you = named(canvas.root, "You")
	local yb = box(you)
	check(`{label}: … you in its middle`, math.abs((yb.x0 + yb.x1) / 2 - (b.x0 + b.x1) / 2) < 1.5 and math.abs((yb.y0 + yb.y1) / 2 - (b.y0 + b.y1) / 2) < 1.5, `{show(yb)} in {show(b)}`)
	check(`{label}: … the loot you saw (dots), no names, its caption fitting`, #all(canvas.root, function(o)
		return o.Name == "Loot" and shown(o)
	end) > 0 and #all(canvas.root, function(o)
		return o.Name == "PersonName"
	end) == 0 and #badTexts(mini) == 0, badTexts(mini)[1])
	check(`{label}: … its caption: {if M.touch then "TAP: MAP" else "MAP · M"}`, named(mini, "Caption").Text == (if M.touch then "TAP: MAP" else "MAP · M"))
	scene(`minimap-run-{s[5]}`)
end
local mini = SandboxMiniMap.frame()
SandboxMiniMap.covered = function()
	return true
end
SandboxMiniMap.step()
check("the minimap steps aside under a window", not mini.Visible)
SandboxMiniMap.covered = SandboxMapUi.isOpen
M.gripActive = true
SandboxMiniMap.step()
check("… during a grip check", not mini.Visible)
M.gripActive = false
SandboxMiniMap.step()
check("… back after it", mini.Visible)
mini.Activated:Fire()
M.flush()
check("a tap on the minimap opens the big map", SandboxMapUi.isOpen())
SandboxMapUi.close()
local hudGui = M.gui:FindFirstChild("SandboxHud")
hudGui.Enabled = false
SandboxMiniMap.step()
check("the minimap hidden with the HUD", not mini.Visible or not M.gui:FindFirstChild("SandboxMiniMap").Enabled)
hudGui.Enabled = true
-- the run over: the lobby, no minimap
M.remotes.Runs.OnClientEvent:Fire({ kind = "run" })
M.remotes.Moving.OnClientEvent:Fire("state", nil)
body(M.player, V3(1800, 3, 10), V3(0, 0, -1))
M.flush()
SandboxMiniMap.step()
check("back in the lobby: no minimap, the map is the lobby's", not mini.Visible and Data.place().kind == "lobby")
untag(fire, "RunHazard")
check("a danger's tag gone: off the list", #Data.dangers(Data.place()) == 0)

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
	print("ALL MAP CHECKS PASSED")
end
