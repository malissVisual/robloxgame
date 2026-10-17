-- 9.7 runs: the pad panel and the run's results card (client/RunUi.luau), run for real on sandbox_mock.luau's recorder
-- beside the real client/SandboxHud.luau (the money block) and client/SandboxTasksUi.luau (the TASKS chip), Hud's groups
-- where client/Hud.luau puts them, on phones held sideways (844 × 390 and 667 × 375: under Roblox's top bar, the touch
-- layout), a computer (1280 × 800) and a big screen (1920 × 1080):
--   * the Runs remote's "state" asked once at the start;
--   * the pad panel (the host's): the house, the countdown and how many go, the line (the host first, the fifth
--     "waits"), five difficulty buttons (the locked ones 🔒); on the screen, clear of the HUD's chips and groups, the
--     touch buttons, the thumbstick and the jump button; its words fitting; on a phone its buttons a finger's size; a
--     locked one tapped: nothing sent, how to open it said; an open one: { kind = "difficulty", id } once; another
--     player's panel: no buttons, the difficulty and who picks it; off the pad ({ kind = "pad" }) or into the run
--     ({ kind = "run" }): gone;
--   * the results card: its head, the pieces (each its rarity's stripe and stars, its value, whose warehouse) in a list
--     that scrolls when they are many, the total, yours, a difficulty opened; on the screen whole (a phone too: the list
--     shorter), its words fitting, OK a finger's size, OK and RunUi.close() close it; a resize scales both; no warnings.
--     10.x danger: its line for the run's danger (the vault opened, the zombies stopped).
--   * 10.x danger, the run's danger strip (the real client/RunDangerUi.luau): under the move's panel (a stand-in in
--     client/TopBlocks.luau, as client/MovingHud.luau puts it), on the screen, clear of the HUD's chips and groups and
--     the touch controls; the difficulty, the keys found, the vault, the zombies; an event's line; the horde's banner on
--     the screen; away under a window (RunDangerUi.covered) and when the run ends ({ kind = "danger" }).
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
-- Does every one-line text fit its label (after the scales above it)? A label cut at its end on purpose (TextTruncate)
-- is let be.
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
local remote = M.Net.get("Runs")
screen(true, 844, 354)

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
RunUi.start()
local asked = sentOn("Runs")
check("RunUi.start(): the Runs remote's \"state\" asked once", #asked == 1 and asked[1][1].kind == "state")

-- What the panel and the card keep clear of: the touch controls, Hud's groups, the chips.
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

local HOST = { kind = "pad", house = "sandbox_house", name = "The Old Farmstead", endsAt = 110, left = 7, host = 14, hostName = "Ann",
	party = { "Ann", "Bob", "Cid", "Dee", "Eve" }, going = 4, max = 4, difficulty = "normal", open = { "easy", "normal" }, mine = true, place = 1 }
local GUEST = table.clone(HOST)
GUEST.mine, GUEST.place = false, 2
local PIECES = {}
local RARITY = { "legendary", "epic", "rare", "uncommon", "common" }
for n = 1, 12 do
	table.insert(PIECES, { item = "sofa", name = if n == 1 then "Grandfather Clock" else `Piece {n}`, icon = "📦", value = 900 - n * 50,
		rarity = RARITY[(n - 1) % #RARITY + 1], to = if n % 3 == 0 then 22 else 14, by = if n % 3 == 0 then "Bob" else "Ann" })
end
local RESULT = { kind = "result", house = "sandbox_house", name = "The Old Farmstead", difficulty = "normal", phase = "done",
	why = "Finished at the truck by Ann: what was in the truck went home", pieces = PIECES, count = #PIECES, value = 5700, mine = 8, mineValue = 3900,
	total = 40, me = 14, opened = "hard", openedName = "Hard", danger = { vault = true, stopped = 7, zombies = true } }

local function panelChecks(label, host)
	local panel = M.gui:FindFirstChild("RunUi") and M.gui:FindFirstChild("RunUi"):FindFirstChild("PadPanel")
	check(`{label}: the pad panel there, on the screen`, panel ~= nil and inside(box(panel)), panel and show(box(panel)))
	local p = box(panel)
	for name, other in blocks() do
		check(`{label}: … clear of {name}`, not overlap(p, other), `{show(p)} on {show(other)}`)
	end
	check(`{label}: … its words fit`, #badTexts(panel) == 0, badTexts(panel)[1])
	local row = panel:FindFirstChild("Difficulties")
	if host then
		check(`{label}: … the host's five difficulty buttons (Hard, Insane, Nightmare 🔒)`, row ~= nil and #row:GetChildren() >= 5
			and string.find(named(row, "Difficulty_hard").Text, "🔒", 1, true) ~= nil and string.find(named(row, "Difficulty_easy").Text, "🔒", 1, true) == nil)
		if M.touch then
			check(`{label}: … a finger's size each`, #smallButtons(panel) == 0, smallButtons(panel)[1])
		end
	else
		check(`{label}: … another player's: no buttons, the difficulty and who picks it`, row == nil and named(panel, "Difficulty") ~= nil
			and string.find(named(panel, "Difficulty").Text, "Ann picks", 1, true) ~= nil)
	end
	check(`{label}: … the line, the fifth waits`, string.find(named(panel, "Party").Text, "Ann (host)", 1, true) ~= nil and string.find(named(panel, "Party").Text, "Eve (waits)", 1, true) ~= nil)
	return panel
end

local function cardChecks(label)
	local card = M.gui:FindFirstChild("RunUi") and M.gui:FindFirstChild("RunUi"):FindFirstChild("RunResult")
	check(`{label}: the results card open, whole on the screen`, card ~= nil and RunUi.isOpen() and inside(box(card)), card and show(box(card)))
	check(`{label}: … its words fit`, #badTexts(card) == 0, badTexts(card)[1])
	local list = named(card, "Pieces")
	local listBox = box(list)
	check(`{label}: … the pieces in a list that scrolls (12 rows, fewer shown), each its rarity's stripe and stars`, list ~= nil and list.CanvasSize.Y.Offset == 12 * 30
		and (listBox.y1 - listBox.y0) / M.scaleOf(list) < 12 * 30 and named(named(list, "Piece1"), "Rarity") ~= nil and named(named(list, "Piece1"), "Stars").Text == "★★★★★"
		and named(named(list, "Piece5"), "Stars").Text == "★")
	check(`{label}: … the total, yours, Hard opened`, string.find(named(card, "Total").Text, "12 PIECES HOME", 1, true) ~= nil
		and string.find(named(card, "Yours").Text, "YOURS: 8", 1, true) ~= nil and string.find(named(card, "Unlocked").Text, "HARD", 1, true) ~= nil)
	check(`{label}: … 10.x the run's danger: the vault opened, the zombies stopped`, named(card, "Danger") ~= nil
		and string.find(named(card, "Danger").Text, "VAULT OPENED ✓", 1, true) ~= nil and string.find(named(card, "Danger").Text, "ZOMBIES STOPPED: 7", 1, true) ~= nil)
	if M.touch then
		check(`{label}: … OK a finger's size`, #smallButtons(card) == 0, smallButtons(card)[1])
	end
	return card
end

for _, s in { { true, 844, 354, "a phone (844 × 390)" }, { true, 667, 339, "a small phone (667 × 375)" }, { false, 1280, 764, "a computer (1280 × 800)" },
	{ false, 1920, 1044, "a big screen (1920 × 1080)" } } do
	screen(s[1], s[2], s[3])
	local label = s[4]
	remote.OnClientEvent:Fire(HOST)
	M.flush()
	local panel = panelChecks(`{label}, the host's`, true)
	local before = #sentOn("Runs")
	named(panel, "Difficulty_hard").Activated:Fire() -- (its words stay 3 s: no flush here, the recorder's delays run at a flush)
	check(`{label}: a locked one tapped: nothing sent, how to open it said`, #sentOn("Runs") == before and named(panel, "Locked") ~= nil
		and string.find(named(panel, "Locked").Text, "NORMAL", 1, true) ~= nil)
	named(panel, "Difficulty_easy").Activated:Fire()
	local sent = sentOn("Runs")
	check(`{label}: an open one: {"{"} kind = "difficulty", id = "easy" {"}"} once`, #sent == before + 1 and sent[#sent][1].kind == "difficulty" and sent[#sent][1].id == "easy")
	check(`{label}: RunUi.pad() the view (the guide's "pick" step)`, RunUi.pad() ~= nil and RunUi.pad().mine == true)
	remote.OnClientEvent:Fire(GUEST)
	M.flush()
	panelChecks(`{label}, another player's`, false)
	remote.OnClientEvent:Fire({ kind = "pad" })
	M.flush()
	check(`{label}: off the pad: the panel gone, RunUi.pad() nil`, M.gui:FindFirstChild("RunUi"):FindFirstChild("PadPanel") == nil and RunUi.pad() == nil)
	remote.OnClientEvent:Fire(HOST)
	remote.OnClientEvent:Fire({ kind = "run", house = "sandbox_house", name = "The Old Farmstead", difficulty = "normal", host = 14, hostName = "Ann", mine = true, members = 4, votes = 0, voted = false })
	M.flush()
	check(`{label}: the run starts: the panel gone, RunUi.run() the run`, M.gui:FindFirstChild("RunUi"):FindFirstChild("PadPanel") == nil and RunUi.run() ~= nil)
	local opened = 0
	RunUi.onOpen = function()
		opened += 1
	end
	remote.OnClientEvent:Fire(RESULT)
	M.flush()
	local card = cardChecks(label)
	check(`{label}: … its onOpen ran (the other windows close), the run over (RunUi.run() nil)`, opened == 1 and RunUi.run() == nil)
	named(card, "Ok").Activated:Fire()
	M.flush()
	check(`{label}: OK closes it`, not RunUi.isOpen() and M.gui:FindFirstChild("RunUi"):FindFirstChild("RunResult") == nil)
	remote.OnClientEvent:Fire(RESULT)
	M.flush()
	RunUi.close()
	check(`{label}: RunUi.close() (ESC) closes it too`, not RunUi.isOpen())
end

-- ── 10.x danger: the run's danger strip, the horde's banner ─────────────────
do
	local RunDangerUi = require("./RunDangerUi")
	local TopBlocks = require("./TopBlocks")
	RunDangerUi.start()
	local holder = M.make("ScreenGui", { Name = "MoveStandIn" }, M.gui)
	local panel = M.make("Frame", { Name = "MovePanel", Size = M.UDim2.fromOffset(MoveLayout.PANEL_W, MoveLayout.PANEL_H), Position = M.UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = M.Vector2.new(0.5, 0) }, holder)
	local scale = M.make("UIScale", { Name = "Scale", Scale = 1 }, panel)
	TopBlocks.set("MovePanel", panel)
	local VIEW = { kind = "danger", house = "lone_house", difficulty = "hard", name = "Hard", weapon = true, hazards = 5, zombies = 3, stopped = 2,
		keys = { { name = "Bedroom key", room = "Bedroom", found = true, by = "Ann", open = false }, { name = "Garage key", room = "Garage", found = false, open = false } },
		vault = { open = false, key = false, pieces = 1 } }
	for _, s in { { true, 844, 354, "a phone (844 × 390)" }, { true, 667, 339, "a small phone (667 × 375)" }, { false, 1280, 764, "a computer (1280 × 800)" },
		{ false, 1920, 1044, "a big screen (1920 × 1080)" } } do
		screen(s[1], s[2], s[3])
		local label = s[4]
		scale.Scale = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		remote.OnClientEvent:Fire(VIEW)
		M.flush()
		local strip = named(M.gui:FindFirstChild("RunDangerUi"), "DangerStrip")
		local b = box(strip)
		check(`{label}: the danger strip there, on the screen, under the move's panel`, strip ~= nil and strip.Visible and inside(b) and b.y0 >= box(panel).y1 - 0.5, strip and show(b))
		for name, other in blocks() do
			check(`{label}: … clear of {name}`, not overlap(b, other), `{show(b)} on {show(other)}`)
		end
		check(`{label}: … its words fit`, #badTexts(strip) == 0, badTexts(strip)[1])
		local top = named(strip, "Top").Text
		check(`{label}: … the difficulty, the keys found, the vault, the zombies, the bat`, string.find(top, "HARD", 1, true) ~= nil and string.find(top, "KEYS 1/2", 1, true) ~= nil
			and string.find(top, "VAULT LOCKED", 1, true) ~= nil and string.find(top, "🧟 3", 1, true) ~= nil and string.find(top, "🏏", 1, true) ~= nil)
		check(`{label}: … its line: the locked doors`, string.find(named(strip, "Line").Text, "🔑 Bedroom", 1, true) ~= nil and string.find(named(strip, "Line").Text, "🔒 Garage", 1, true) ~= nil)
		remote.OnClientEvent:Fire({ kind = "danger", event = "🔑 Garage key found by Bob", sound = "task_done" })
		M.flush()
		check(`{label}: … an event's line ("🔑 Garage key found by Bob")`, named(strip, "Line").Text == "🔑 Garage key found by Bob")
		remote.OnClientEvent:Fire({ kind = "danger", event = "🧟 A horde is coming! Get the loot into the truck and hold the door.", sound = "horde_siren", banner = true })
		M.flush()
		local banner = named(M.gui:FindFirstChild("RunDangerUi"), "HordeBanner")
		check(`{label}: … the horde's banner, on the screen`, banner ~= nil and banner.Visible and inside(box(banner)) and string.find(banner.Text, "horde", 1, true) ~= nil,
			banner and show(box(banner)))
		RunDangerUi.covered = function(): boolean
			return true
		end
		remote.OnClientEvent:Fire(VIEW)
		M.flush()
		check(`{label}: … away under a window (RunDangerUi.covered)`, not strip.Visible and not banner.Visible)
		RunDangerUi.covered = nil
		remote.OnClientEvent:Fire({ kind = "danger" })
		M.flush()
		check(`{label}: … gone when the run ends`, not strip.Visible and RunDangerUi.view() == nil)
	end
	TopBlocks.set("MovePanel", nil)
	holder:Destroy()
end

-- ── 10.5 rounds: the round's results card (its ranking), RoundUi's banner and table ────────────────────────────
do
	local ranking = {}
	local NAMES = { "Ann", "Bartholomew", "Cid", "Dee", "Eve", "Fay", "Gus", "Hal", "Ivy", "Jon", "Kim", "Lou", "Max", "Ned", "Oli", "Pam" }
	for n, name in NAMES do
		table.insert(ranking, { id = n, name = name, count = 17 - n, value = 9000 - n * 400, place = n })
	end
	local ROUND = table.clone(RESULT)
	ROUND.why, ROUND.opened, ROUND.openedName, ROUND.danger, ROUND.me = "Time's up: what you loaded is in your warehouse", nil, nil, nil, 3
	ROUND.round = { ranking = ranking, place = 3, players = #ranking }
	local RoundUi = require("./RoundUi")
	Config.Rounds.On = true
	RoundUi.start()
	local WAIT = { kind = "round", phase = "wait", endsAt = (M.now or 0) + 42, house = "orchard_cottage", name = "The Orchard Cottage", difficulty = "insane",
		inRound = false, players = 16, ready = true, top = {}, mine = nil }
	local top = {}
	for n = 1, Config.Rounds.Top do
		table.insert(top, { name = NAMES[n], count = 17 - n, value = 9000 - n * 400, place = n, me = false })
	end
	local PLAY = { kind = "round", phase = "play", endsAt = 300, house = "orchard_cottage", name = "The Orchard Cottage", difficulty = "insane", inRound = true,
		players = 16, ready = true, top = top, mine = { place = 9, count = 4, value = 1200 } }
	for _, s in { { true, 844, 354, "a phone (844 × 390)" }, { true, 667, 339, "a small phone (667 × 375)" }, { false, 1280, 764, "a computer (1280 × 800)" },
		{ false, 1920, 1044, "a big screen (1920 × 1080)" } } do
		screen(s[1], s[2], s[3])
		local label = s[4]
		remote.OnClientEvent:Fire(ROUND)
		M.flush()
		local card = M.gui:FindFirstChild("RunUi"):FindFirstChild("RunResult")
		check(`{label}: 10.5 the round's results card, whole on the screen, its words fit`, card ~= nil and inside(box(card)) and #badTexts(card) == 0,
			card and (badTexts(card)[1] or show(box(card))))
		local list = named(card, "Pieces")
		check(`{label}: … everybody's row (16) in a list that scrolls, the first three's medals, yours lit`, list ~= nil and list.CanvasSize.Y.Offset == 16 * 30
			and named(named(list, "Rank1"), "Place").Text == "🥇" and named(named(list, "Rank3"), "Name").Font == M.MTheme.HeadingFont and named(list, "Piece1") == nil)
		check(`{label}: … ROUND OVER, your place ("YOU: 3RD OF 16")`, string.find(named(card, "Head").Text, "ROUND OVER", 1, true) ~= nil
			and string.find(named(card, "Total").Text, "YOU: 3RD OF 16", 1, true) ~= nil and named(card, "Unlocked") == nil)
		if M.touch then
			check(`{label}: … OK a finger's size`, #smallButtons(card) == 0, smallButtons(card)[1])
		end
		RunUi.close()
		remote.OnClientEvent:Fire(WAIT)
		M.flush()
		local gui = M.gui:FindFirstChild("RoundUi")
		local banner = named(gui, "Banner")
		check(`{label}: the lobby's banner: on the screen, its words fit, the place, its difficulty and the countdown`, banner ~= nil and banner.Visible and inside(box(banner))
			and #badTexts(banner) == 0 and string.find(named(banner, "Title").Text, "THE ORCHARD COTTAGE · INSANE", 1, true) ~= nil, banner and (badTexts(banner)[1] or show(box(banner))))
		for name, other in blocks() do
			check(`{label}: … clear of {name}`, not overlap(box(banner), other), `{show(box(banner))} on {show(other)}`)
		end
		remote.OnClientEvent:Fire(PLAY)
		M.flush()
		local board = named(gui, "Board")
		check(`{label}: in the round: the banner gone, the table on the screen (its top {Config.Rounds.Top} and your row: 9th), its words fit`, not banner.Visible and board.Visible
			and inside(box(board)) and #badTexts(board) == 0 and #board:GetChildren() >= Config.Rounds.Top + 2, board and (badTexts(board)[1] or show(box(board))))
		for name, other in blocks() do
			check(`{label}: … clear of {name}`, not overlap(box(board), other), `{show(box(board))} on {show(other)}`)
		end
		remote.OnClientEvent:Fire({ kind = "claim", by = "Bartholomew", mine = false, name = "Grandfather Clock", icon = "🕰", rarity = "legendary", value = 2400 })
		remote.OnClientEvent:Fire({ kind = "claim", by = "Cid", mine = true, name = "Rocking Horse", icon = "🐴", rarity = "rare", value = 450 })
		M.flush()
		local feed = named(gui, "Feed")
		check(`{label}: … the feed under it: the latest first (yours), on the screen`, feed.Visible and inside(box(feed))
			and string.find(named(feed, "Line1").Text, "Rocking Horse is yours", 1, true) ~= nil and string.find(named(feed, "Line2").Text, "Bartholomew took", 1, true) ~= nil,
			feed and show(box(feed)))
		for name, other in blocks() do
			check(`{label}: … the feed clear of {name}`, not overlap(box(feed), other), `{show(box(feed))} on {show(other)}`)
		end
		remote.OnClientEvent:Fire(WAIT)
		M.flush()
	end
end

-- a resize while both are up: their scale follows
screen(true, 844, 354)
remote.OnClientEvent:Fire(HOST)
remote.OnClientEvent:Fire(RESULT)
M.flush()
screen(false, 1920, 1044)
local gui = M.gui:FindFirstChild("RunUi")
check("a resize: the card's scale follows the screen (a big screen: 1)", gui:FindFirstChild("RunResult"):FindFirstChild("Scale").Scale == 1)
RunUi.close()
remote.OnClientEvent:Fire({ kind = "nonsense" })
remote.OnClientEvent:Fire(5)
M.flush()
check("junk on the remote: ignored", not RunUi.isOpen())
check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL RUNS UI CHECKS PASSED")
