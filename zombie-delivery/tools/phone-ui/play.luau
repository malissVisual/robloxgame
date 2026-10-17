-- 10.4 the PLAY panel and the lobby bar (client/PlayUi.luau, started by client/RunUi.luau), run for real on
-- sandbox_mock.luau's recorder beside the real client/SandboxHud.luau (the money block) and client/SandboxTasksUi.luau
-- (the TASKS chip), Hud's groups where client/Hud.luau puts them, on phones held sideways (844 × 390 and 667 × 375: under
-- Roblox's top bar, the touch layout), a computer (1280 × 800) and a big screen (1920 × 1080):
--   * nothing when Config.Sandbox.On is false; the Party remote's "state" asked once at the start;
--   * OPEN LOBBIES (you step into the circle: the server's view, circle true): the panel whole on the screen, ＋ CREATE
--     A LOBBY, how it works, the lobbies you may join (their pictures, host, house, difficulty, n/4, friends only): JOIN
--     sends { kind = "join", id } once, a full or starting one is not pressable; its words fit; on a phone every button a
--     finger's size;
--   * CREATE A LOBBY: the six houses (each its picture, name, line, state: one in a run, one another lobby holds: not
--     pressable), the difficulties (a locked one: nothing sent, how to open it said), PUBLIC / FRIENDS ONLY, CREATE
--     LOBBY sends { kind = "create", house, difficulty, friends }; ‹ BACK;
--   * YOUR LOBBY, the host's: the house, the players (👑, READY), KICK on the others ({ kind = "kick", id }), READY,
--     START ({ kind = "start" }), the difficulty ({ kind = "difficulty", id }), CHANGE HOUSE (the houses again: a pick
--     sends { kind = "house", id }), LEAVE LOBBY; counting down: STARTING IN …, CANCEL, no picks;
--   * a member's: READY ({ kind = "ready", on }), no START, no KICK, who picks;
--   * away from the circle (circle false) in a lobby: the lobby bar (on the screen, clear of the HUD's chips and groups
--     and the touch controls, its words fitting, OPEN a finger's size): OPEN brings the panel back, ✕ shuts it again;
--     RunUi.isOpen() while the panel is open, RunUi.close() (ESC) shuts it, RunUi.lobby() the lobby; the empty view:
--     nothing; stepping in again opens it after a ✕; a resize scales it; junk ignored; no warnings.
-- `luau play.luau -a dump` prints the preview's scenes as JSON instead (play_preview.py).
local M = require("./sandbox_mock")
local Config = require("./Config")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local TasksRules = require("./SandboxTasks")

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
local function sentOn(remote)
	local list = {}
	for _, entry in M.sent do
		if entry.name == remote then
			table.insert(list, entry.args)
		end
	end
	return list
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
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		if not object.TextWrapped and not (object.TextTruncate and object.TextTruncate.Name == "AtEnd") then
			local b = box(object)
			local room = b.x1 - b.x0
			local need = M.textWidth(object.Text, (object.TextSize or 14) * M.scaleOf(object), object.Font)
			if need > room + 0.5 then
				table.insert(bad, `{object.Name} "{object.Text}" {math.floor(need)} > {math.floor(room)}`)
			end
		elseif object.TextWrapped then
			-- wrapped words: their lines (word by word, as Roblox wraps them) fit in the label's height
			local b = box(object)
			local size = (object.TextSize or 14) * M.scaleOf(object)
			local lines = 0
			for _, paragraph in string.split(object.Text, "\n") do
				lines += 1
				local width = 0
				for _, word in string.split(paragraph, " ") do
					local w = M.textWidth(if width > 0 then " " .. word else word, size, object.Font)
					if width > 0 and width + w > b.x1 - b.x0 + 0.5 then
						lines += 1
						width = M.textWidth(word, size, object.Font)
					else
						width += w
					end
				end
			end
			if lines * size * 1.1 > b.y1 - b.y0 + 0.5 then
				table.insert(bad, `{object.Name} "{object.Text}" {lines} lines in {math.floor(b.y1 - b.y0)} px`)
			end
		end
	end
	return bad
end
local function smallButtons(root)
	local small = {}
	for _, object in all(root, function(o)
		return o.ClassName == "TextButton" and shown(o)
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end
-- every button inside the panel's box (none sticks out of it)
local function outside(root)
	local r = box(root)
	for _, object in all(root, function(o)
		return (o.ClassName == "TextButton" or o.ClassName == "Frame") and shown(o) and o ~= root and o.Parent ~= nil and o.Parent.ClassName ~= "ScrollingFrame"
	end) do
		local b = box(object)
		if b.x0 < r.x0 - 0.5 or b.y0 < r.y0 - 0.5 or b.x1 > r.x1 + 0.5 or b.y1 > r.y1 + 0.5 then
			return `{object.Name} {show(b)} out of {show(r)}`
		end
	end
	return nil
end

-- ── The preview's scenes (play_preview.py) ──────────────────────────────────
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
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
		table.insert(overlay, { kind = "pill", box = cluster.sprint, label = "SPRINT" })
	else
		table.insert(overlay, { kind = "minimap", box = { x0 = 16, y0 = M.height - 16 - 30 * S, x1 = 16 + 200 * S, y1 = M.height - 16 } })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── The stand-ins: Hud's groups ────────────────────────────────────────────
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
	M.flush()
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
local RunUi = require("./RunUi")
local PlayUi = require("./PlayUi")
local party = M.Net.get("Party")
screen(true, 844, 354)
Config.Sandbox.On = false
RunUi.start()
check("Config.Sandbox.On false: RunUi.start() starts no PLAY panel (nothing asked)", #sentOn("Party") == 0)
Config.Sandbox.On = true

-- ── On: the HUD's chips ─────────────────────────────────────────────────────
local SandboxHud = require("./SandboxHud")
local SandboxTasksUi = require("./SandboxTasksUi")
SandboxHud.start()
SandboxHud.setState({ money = 12480 })
M.flush()
SandboxTasksUi.start()
local NOW = 20372 * 86400 + 18 * 3600
local tasks = TasksRules.view(TasksRules.fresh(42, NOW), NOW) :: any
tasks.kind = "state"
M.remotes.SandboxTasks.OnClientEvent:Fire(tasks)
M.flush()
local chip = named(M.gui:FindFirstChild("SandboxTasksChip"), "TasksChip")
check("(the HUD's chips there: the money block, the TASKS chip)", SandboxHud.block() ~= nil and chip ~= nil and chip.Visible)
RunUi.start()
check("RunUi.start(): the Party remote's \"state\" asked once (client/PlayUi.luau)", #sentOn("Party") == 1 and sentOn("Party")[1][1].kind == "state")

-- What the bar keeps clear of: the touch controls, Hud's groups, the chips.
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
		list["the key hints"] = box(groups.HudButtons)
	end
	list["the money block"] = box(SandboxHud.block())
	list["the TASKS chip"] = box(chip)
	return list
end

-- ── The server's views ─────────────────────────────────────────────────────
local OPEN = { "easy", "normal", "hard" }
local function houses(mine)
	local list = {}
	for _, h in { { "sandbox_house", "The Old Farmstead" }, { "pond_cabin", "The Pond Cabin" }, { "lone_house", "The Lone House" }, { "forest_lodge", "The Forest Lodge" },
		{ "old_mill", "The Old Mill" }, { "orchard_cottage", "The Orchard Cottage" } } do
		local state, by = "free", nil
		if h[1] == "sandbox_house" then
			state, by = "run", "Cid"
		elseif h[1] == "pond_cabin" then
			state, by = "lobby", "Bob"
		elseif h[1] == "lone_house" and mine then
			state, by = "lobby", "Ann"
		end
		table.insert(list, { id = h[1], name = h[2], state = state, by = by, mine = mine and h[1] == "lone_house" })
	end
	return list
end
local LOBBIES = {
	{ id = 7, host = 22, hostName = "Bob", house = "pond_cabin", name = "The Pond Cabin", difficulty = "hard", n = 2, max = 4, friends = false, state = "open", mine = false },
	{ id = 8, host = 44, hostName = "Dee", house = "old_mill", name = "The Old Mill", difficulty = "nightmare", n = 4, max = 4, friends = true, state = "full", mine = false },
	{ id = 9, host = 55, hostName = "Evangelina Longname", house = "forest_lodge", name = "The Forest Lodge", difficulty = "easy", n = 3, max = 4, friends = false, state = "starting", mine = false },
}
local HOME = { kind = "play", circle = true, me = 14, open = OPEN, houses = houses(false), lobbies = LOBBIES }
local function lobbyView(mine, counting)
	local view = table.clone(HOME)
	view.houses = houses(true)
	view.lobby = { id = 10, host = if mine then 14 else 22, hostName = if mine then "Ann" else "Bob", mine = mine, house = "lone_house", name = "The Lone House", difficulty = "normal",
		friends = true, max = 4, endsAt = if counting then M.now + 4.2 else nil, ready = 2, open = OPEN, canStart = mine and not counting, why = nil,
		members = { { id = if mine then 14 else 22, name = if mine then "Ann" else "Bob", ready = true, host = true }, { id = if mine then 22 else 14, name = if mine then "Bob" else "Ann", ready = not mine, host = false },
			{ id = 33, name = "Cidonia Vandersteenhoven", ready = true, host = false }, { id = 55, name = "Eve", ready = false, host = false } } }
	if not mine then
		view.lobby.ready = 3
	end
	return view
end
local HOST, MEMBER, COUNTING = lobbyView(true, false), lobbyView(false, false), lobbyView(true, true)
local AWAY = table.clone(MEMBER)
AWAY.circle = false

local function gui()
	return M.gui:FindFirstChild("PlayUi")
end
local function panel()
	return gui() and gui():FindFirstChild("PlayPanel")
end
local function bar()
	return gui() and gui():FindFirstChild("PlayBar")
end
local function fire(view)
	party.OnClientEvent:Fire(view)
	M.flush()
end
local function press(object)
	object.Activated:Fire()
	M.flush()
end
local function last()
	local list = sentOn("Party")
	return list[#list] and list[#list][1]
end
local function panelChecks(label)
	local p = panel()
	check(`{label}: the panel there, whole on the screen`, p ~= nil and inside(box(p)) and PlayUi.isOpen() and RunUi.isOpen(), p and show(box(p)))
	check(`{label}: … its words fit`, #badTexts(p) == 0, badTexts(p)[1])
	check(`{label}: … nothing sticks out of it`, outside(p) == nil, outside(p))
	if M.touch then
		check(`{label}: … every button a finger's size`, #smallButtons(p) == 0, smallButtons(p)[1])
	end
	return p
end

local SIZES = { { true, 844, 354, "a phone (844 × 390)", "844x390" }, { true, 667, 339, "a small phone (667 × 375)", "667x375" },
	{ false, 1280, 764, "a computer (1280 × 800)", "1280x800" }, { false, 1920, 1044, "a big screen (1920 × 1080)", "1920x1080" } }
for _, s in SIZES do
	screen(s[1], s[2], s[3])
	local label, tag = s[4], s[5]
	fire({ kind = "play" })
	check(`{label}: the empty view: nothing`, panel() == nil and bar() == nil and RunUi.lobby() == nil and not PlayUi.isOpen())
	-- OPEN LOBBIES
	fire(HOME)
	local p = panelChecks(`{label}, OPEN LOBBIES`)
	check(`{label}: … ＋ CREATE A LOBBY, how it works, three lobbies to join (pictures, hosts, houses, difficulties, n/4)`, named(p, "Create") ~= nil and named(p, "How") ~= nil
		and named(p, "Lobby_7") ~= nil and named(p, "Lobby_9") ~= nil and named(named(p, "Lobby_7"), "Picture") ~= nil
		and string.find(named(named(p, "Lobby_7"), "Info").Text, "HARD · 2/4", 1, true) ~= nil and string.find(named(named(p, "Lobby_8"), "Info").Text, "👥", 1, true) == 1
		and named(named(p, "Lobby_8"), "Join").Text == "FULL" and named(named(p, "Lobby_9"), "Join").Text == "STARTING" and PlayUi.screen() == "home")
	local before = #sentOn("Party")
	press(named(named(p, "Lobby_8"), "Join"))
	check(`{label}: … FULL is not pressable (nothing sent)`, #sentOn("Party") == before)
	press(named(named(p, "Lobby_7"), "Join"))
	check(`{label}: … JOIN: {"{"} kind = "join", id = 7 {"}"} once`, #sentOn("Party") == before + 1 and last().kind == "join" and last().id == 7)
	scene(`play-home-{tag}`)
	-- CREATE A LOBBY
	press(named(p, "Create"))
	p = panelChecks(`{label}, CREATE A LOBBY`)
	local cards = 0
	for _, h in HOME.houses do
		cards += if named(p, `House_{h.id}`) and named(named(p, `House_{h.id}`), "Picture") then 1 else 0
	end
	check(`{label}: … six house cards (each its picture), the farmstead IN A RUN, the cabin TAKEN; ‹ BACK; CREATE waits for a house`, cards == 6 and PlayUi.screen() == "create"
		and string.find(named(named(p, "House_sandbox_house"), "State").Text, "IN A RUN", 1, true) == 1
		and string.find(named(named(p, "House_pond_cabin"), "State").Text, "TAKEN", 1, true) == 1 and named(p, "Back") ~= nil and named(p, "Make").Text == "PICK A HOUSE FIRST")
	before = #sentOn("Party")
	press(named(p, "House_sandbox_house"))
	press(named(panel(), "Make"))
	check(`{label}: … a house in a run is not pressable, CREATE neither yet (nothing sent)`, #sentOn("Party") == before and named(panel(), "Make").Text == "PICK A HOUSE FIRST")
	press(named(panel(), "House_lone_house"))
	named(panel(), "Difficulty_insane").Activated:Fire() -- (not flushed yet: the mock runs task.delay's at once, the note's 3 s too)
	check(`{label}: … The Lone House picked (outlined); Insane (locked): nothing sent, how to open it said`, #sentOn("Party") == before and named(panel(), "Note") ~= nil
		and string.find(named(panel(), "Note").Text, "HARD", 1, true) ~= nil and named(panel(), "Make").Text == "CREATE LOBBY",
		`{#sentOn("Party") - before} sent; {if named(panel(), "Note") then named(panel(), "Note").Text else "no note"}; {named(panel(), "Make").Text}`)
	press(named(panel(), "Difficulty_hard"))
	press(named(panel(), "Friends"))
	check(`{label}: … Hard and FRIENDS ONLY picked`, named(panel(), "Friends").Text == "👥 FRIENDS ONLY" and #sentOn("Party") == before)
	p = panelChecks(`{label}, CREATE A LOBBY (picked)`)
	scene(`play-create-{tag}`)
	press(named(p, "Make"))
	check(`{label}: … CREATE LOBBY: {"{"} kind = "create", house = "lone_house", difficulty = "hard", friends = true {"}"}`, #sentOn("Party") == before + 1 and last().kind == "create"
		and last().house == "lone_house" and last().difficulty == "hard" and last().friends == true)
	-- YOUR LOBBY (the host)
	fire(HOST)
	p = panelChecks(`{label}, YOUR LOBBY (the host's)`)
	check(`{label}: … the house, the four players (👑 Ann, READY or not), KICK on the other three, READY ✓, START, CHANGE HOUSE, LEAVE LOBBY`, PlayUi.screen() == "lobby"
		and named(p, "House").Text == "THE LONE HOUSE" and named(p, "Member4") ~= nil and string.find(named(named(p, "Member1"), "Name").Text, "👑 Ann", 1, true) == 1
		and named(named(p, "Member1"), "Kick") == nil and named(named(p, "Member2"), "Kick") ~= nil and named(named(p, "Member2"), "Status").Text == "NOT READY"
		and named(p, "Ready").Text == "✓ READY" and named(p, "Start") ~= nil and named(p, "ChangeHouse") ~= nil and named(p, "Leave") ~= nil and RunUi.lobby() ~= nil
		and RunUi.lobby().mine == true)
	scene(`play-lobby-host-{tag}`)
	before = #sentOn("Party")
	press(named(named(p, "Member2"), "Kick"))
	local kicked = last()
	press(named(panel(), "Start"))
	local started = last()
	press(named(panel(), "Difficulty_easy"))
	local picked = last()
	press(named(panel(), "Ready"))
	local unready = last()
	check(`{label}: … KICK (Bob), START, Easy, READY off: each its request`, #sentOn("Party") == before + 4 and kicked.kind == "kick" and kicked.id == 22 and started.kind == "start"
		and picked.kind == "difficulty" and picked.id == "easy" and unready.kind == "ready" and unready.on == false,
		`{#sentOn("Party") - before} sent: {kicked and kicked.kind}, {started and started.kind}, {picked and picked.kind}, {unready and unready.kind} {unready and tostring(unready.on)}`)
	press(named(panel(), "ChangeHouse"))
	p = panelChecks(`{label}, CHANGE HOUSE`)
	check(`{label}: … the houses again (its own pressable, the farmstead not)`, PlayUi.screen() == "house" and named(p, "House_lone_house") ~= nil and named(p, "Back") ~= nil)
	press(named(p, "House_orchard_cottage"))
	check(`{label}: … a pick: {"{"} kind = "house", id = "orchard_cottage" {"}"}, back to the lobby`, last().kind == "house" and last().id == "orchard_cottage" and PlayUi.screen() == "lobby")
	press(named(panel(), "Leave"))
	check(`{label}: … LEAVE LOBBY: {"{"} kind = "leave" {"}"}`, last().kind == "leave")
	-- counting down
	fire(COUNTING)
	p = panelChecks(`{label}, STARTING`)
	before = #sentOn("Party")
	press(named(p, "Difficulty_hard"))
	check(`{label}: … STARTING IN 5, CANCEL in START's place, the difficulty not pressable`, string.find(named(p, "Line").Text, "STARTING IN 5", 1, true) == 1
		and named(p, "Cancel") ~= nil and named(p, "Start") == nil and #sentOn("Party") == before, named(p, "Line").Text)
	press(named(p, "Cancel"))
	check(`{label}: … CANCEL: {"{"} kind = "cancel" {"}"}`, last().kind == "cancel")
	-- a member's
	fire(MEMBER)
	p = panelChecks(`{label}, A MEMBER'S LOBBY`)
	check(`{label}: … BOB'S LOBBY: READY, no START, no KICK, who picks`, string.find(named(p, "Subtitle").Text, "BOB'S LOBBY", 1, true) == 1 and named(p, "Start") == nil
		and named(p, "Kick") == nil and named(p, "Ready").Text == "✓ READY" and string.find(named(p, "HostDoes").Text, "Bob picks", 1, true) == 1)
	scene(`play-lobby-member-{tag}`)
	press(named(p, "Ready"))
	check(`{label}: … READY off: {"{"} kind = "ready", on = false {"}"}`, last().kind == "ready" and last().on == false)
	-- away: the bar
	fire(AWAY)
	local b = bar()
	check(`{label}: away from the circle: the panel shut, the lobby bar there, on the screen`, panel() == nil and b ~= nil and inside(box(b)) and not RunUi.isOpen(), b and show(box(b)))
	for name, other in blocks() do
		check(`{label}: … the bar clear of {name}`, not overlap(box(b), other), `{show(box(b))} on {show(other)}`)
	end
	check(`{label}: … its words fit; its line (2/4 … waiting for the host)`, #badTexts(b) == 0 and string.find(named(b, "House").Text, "THE LONE HOUSE · NORMAL", 1, true) == 1
		and string.find(named(b, "Line").Text, "WAITING FOR BOB", 1, true) ~= nil, badTexts(b)[1] or named(b, "Line").Text)
	if M.touch then
		check(`{label}: … OPEN a finger's size`, #smallButtons(b) == 0, smallButtons(b)[1])
	end
	scene(`play-bar-{tag}`)
	local opened = 0
	RunUi.onOpen = function()
		opened += 1
	end
	press(named(b, "Open"))
	check(`{label}: … OPEN: the panel again (the lobby's), its onOpen ran (the other windows close)`, panel() ~= nil and bar() == nil and PlayUi.isOpen() and opened == 1)
	press(named(panel(), "Close"))
	check(`{label}: … ✕: shut, the bar back`, panel() == nil and bar() ~= nil)
	press(named(bar(), "Open"))
	RunUi.close()
	check(`{label}: … RunUi.close() (ESC) shuts it too`, panel() == nil and bar() ~= nil and not RunUi.isOpen())
	fire(MEMBER)
	check(`{label}: … stepping into the circle again opens it after a ✕`, panel() ~= nil)
	RunUi.onOpen = nil
end

-- a resize while it is up: its scale follows (a big screen: 1; a phone: the touch scale, the panel whole)
screen(true, 844, 354)
fire(HOME)
local small = panel():FindFirstChild("Scale").Scale
screen(false, 1920, 1044)
check("a resize: the panel's scale follows the screen (a phone: 0.8 or so; a big screen: 1)", small >= Config.Runs.Panel.TouchScale - 0.01 and small < 1
	and panel():FindFirstChild("Scale").Scale == 1, small)
party.OnClientEvent:Fire({ kind = "nonsense" })
party.OnClientEvent:Fire(5)
M.flush()
check("junk on the remote: ignored", panel() ~= nil)
fire({ kind = "play" })
check("the empty view at last: nothing", panel() == nil and bar() == nil)
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
	print("ALL PLAY UI CHECKS PASSED")
end
