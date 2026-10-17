-- 10.1 the helpers' crew: the CREW window and the down ring (client/CrewUi.luau), run for real on sandbox_mock.luau's
-- recorder with the real shared/CrewRules.luau rows (crewenv.py builds the folder), on phones held sideways (844 × 390
-- and 667 × 375: under Roblox's top bar, the touch layout), a computer (1280 × 800) and a big screen (1920 × 1080):
--   * the Crew remote's "state" asked once at the start;
--   * the window ({ kind = "open" }): whole on the screen, its words fitting (what a helper does in two lines at most),
--     on a phone its buttons a finger's size; a row a kind in Config.Crew.Order: the pick ✓ PICKED, a ready one PICK
--     ({ kind = "pick", id } once for a double tap), one in hospital its time left counting down in place and DISCHARGE
--     $X (its price following the minutes left; without the money grey: a tap only says what it costs; with it
--     { kind = "discharge", id }), one not yours locked ("🔒 Rescue him in a run", nothing to press);
--   * who comes into your runs under the title (your pick in hospital: who comes instead; all in hospital: nobody);
--     a countdown run out asks the state once; ✕, ESC, the Roblox menu and a tap beside it close it; a resize scales it;
--   * the down ring over a helper down in a run (tagged CrewDown, his CrewDownUntil): its seconds left, its dots going
--     out (the last third red), "REVIVE <NAME>" fitting, seen through walls within Config.Crew.Ring.Range; gone once he
--     is up or out, made again when he is down again; the loop's look every Ring.Every s; junk ignored; no warnings.
-- `luau crew.luau -a dump` prints the preview's scenes as JSON instead (crew_preview.py).
local M = require("./sandbox_mock")
local Config = require("./Config")
local CrewRules = require("./CrewRules")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")

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
			table.insert(list, entry.args[1])
		end
	end
	return list
end
local box = M.box
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
-- Does every one-line text fit its label (after the scales above it)? One cut at its end on purpose is let be.
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		if not object.TextWrapped and not (object.TextTruncate and object.TextTruncate.Name == "AtEnd") then
			local b = box(object)
			local need = M.textWidth(object.Text, (object.TextSize or 14) * M.scaleOf(object), object.Font)
			if need > b.x1 - b.x0 + 0.5 then
				table.insert(bad, `{object.Name} "{object.Text}" {math.floor(need)} > {math.floor(b.x1 - b.x0)}`)
			end
		end
	end
	return bad
end
local function smallButtons(root)
	local small = {}
	for _, object in all(root, function(o)
		return o.ClassName == "TextButton" and shown(o) and o.Name ~= "CrewShade"
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end
local function click(button)
	button.Activated:Fire()
	M.flush()
end

-- ── The preview's scenes (crew_preview.py) ──────────────────────────────────
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
-- A scene: the touch controls under the window; `ring` (a BillboardGui) drawn over a helper lying at `at` (px).
local function scene(name, ring, at)
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
	local tree = node(M.gui)
	if ring then
		local w, h = ring.Size.X.Offset, ring.Size.Y.Offset
		table.insert(overlay, { kind = "piece", box = { x0 = at.X - 70, y0 = at.Y + h + 6, x1 = at.X + 70, y1 = at.Y + h + 40 }, label = "lying down", color = { 229, 83, 75 } })
		table.insert(tree.kids, { c = "ScreenGui", n = "RingOver", display = 1, enabled = true,
			kids = { { c = "Frame", n = "Billboard", pos = { 0, at.X - w / 2, 0, at.Y }, size = { 0, w, 0, h }, bgT = 1, kids = node(ring).kids } } })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = tree })
end

-- ── The screens ─────────────────────────────────────────────────────────────
local camera = M.workspace.CurrentCamera
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	camera.ViewportSize = M.Vector2.new(w, h + 36)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	M.flush()
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
local CrewUi = require("./CrewUi")
local remote = M.Net.get("Crew")
screen(true, 844, 354)
CrewUi.start()
check("CrewUi.start(): the Crew remote's \"state\" asked once", #sentOn("Crew") == 1 and sentOn("Crew")[1].kind == "state")

-- The server's state (server/HelperCrew.luau sendState) for a crew: the real CrewRules rows.
local T = 1800000000 -- (the server's os.time(): the rows' seconds left are what it sends)
local function stateFor(crew, money)
	local comes, instead = CrewRules.comes(crew, T)
	return { kind = "state", rows = CrewRules.view(crew, T), pick = crew.pick, comes = comes, instead = instead, money = money }
end
local CREW = { have = { "danny", "bruno", "gus" }, pick = "danny", hospital = { bruno = T + 190 } }
local function frameOf()
	local shade = M.gui:FindFirstChild("CrewUi") and M.gui:FindFirstChild("CrewUi"):FindFirstChild("CrewShade")
	return shade and shade:FindFirstChild("Crew")
end
local function rowOf(id)
	local frame = frameOf()
	return frame and named(frame, `Crew_{id}`)
end

local SCREENS = { { true, 844, 354, "a phone (844 × 390)", "phone" }, { true, 667, 339, "a small phone (667 × 375)", nil },
	{ false, 1280, 764, "a computer (1280 × 800)", "computer" }, { false, 1920, 1044, "a big screen (1920 × 1080)", nil } }
for _, s in SCREENS do
	screen(s[1], s[2], s[3])
	local label = s[4]
	local start = M.now
	remote.OnClientEvent:Fire(stateFor(CREW, 120))
	remote.OnClientEvent:Fire({ kind = "open" })
	M.flush()
	local frame = frameOf()
	check(`{label}: {"{"} kind = "open" {"}"} opens the window, whole on the screen`, frame ~= nil and CrewUi.isOpen() and inside(box(frame)), frame and show(box(frame)))
	check(`{label}: … its words fit`, #badTexts(frame) == 0, badTexts(frame)[1])
	if s[1] then
		check(`{label}: … a finger's size for every button (PICK, DISCHARGE, ✕)`, #smallButtons(frame) == 0, smallButtons(frame)[1])
	end
	local list = named(frame, "List")
	local listBox = box(list)
	local rowsShown = true
	for index, id in Config.Crew.Order do
		local row = rowOf(id)
		rowsShown = rowsShown and row ~= nil and row.Position.Y.Offset > (if index == 1 then -1 else rowOf(Config.Crew.Order[index - 1]).Position.Y.Offset)
	end
	check(`{label}: … a row a helper in Config.Crew.Order (5), each whole in the list (no scrolling)`, rowsShown and list.CanvasSize.Y.Offset <= (listBox.y1 - listBox.y0) / M.scaleOf(list) + 0.5,
		`{list.CanvasSize.Y.Offset} > {(listBox.y1 - listBox.y0) / M.scaleOf(list)}`)
	local twoLines = true
	for _, id in Config.Crew.Order do
		local ability = named(rowOf(id), "Ability")
		local b = box(ability)
		twoLines = twoLines and ability.TextWrapped and M.textWidth(ability.Text, ability.TextSize * M.scaleOf(ability), ability.Font) <= 2 * (b.x1 - b.x0) * 0.92
	end
	check(`{label}: … what each does in two lines at most`, twoLines)
	check(`{label}: … Danny (the pick) ✓ PICKED, Gus PICK, Bruno in hospital (🏥 3:10, DISCHARGE $250), Zip and Lucy locked (her words hers)`,
		named(rowOf("danny"), "Picked").Text == "✓ PICKED" and named(rowOf("gus"), "Pick").Text == "PICK"
		and named(rowOf("bruno"), "Left").Text == "🏥 3:10" and named(rowOf("bruno"), "Discharge").Text == "DISCHARGE $250"
		and named(rowOf("zip"), "Locked").Text == "🔒 Rescue him in a run" and named(rowOf("lucy"), "Locked").Text == "🔒 Rescue her in a run"
		and named(rowOf("zip"), "Pick") == nil, named(rowOf("bruno"), "Left").Text)
	check(`{label}: … who comes under the title`, named(frame, "Subtitle").Text == "🧑‍🔧 Danny comes into your runs · rescue trapped helpers in runs for more")
	if s[5] then
		scene(`crew-window-{s[5]}`)
	end
	-- DISCHARGE without the money: only says what it costs
	local before = #sentOn("Crew")
	local toasts = #M.toasts
	click(named(rowOf("bruno"), "Discharge"))
	check(`{label}: DISCHARGE without the money: nothing sent, what it costs said`, #sentOn("Crew") == before and #M.toasts == toasts + 1
		and M.toasts[#M.toasts] == "🏥 Discharging Bruno costs $250: you have $120.", M.toasts[#M.toasts])
	-- PICK: once for a double tap
	local pick = named(rowOf("gus"), "Pick")
	click(pick)
	click(pick)
	local sent = sentOn("Crew")
	check(`{label}: PICK (Gus): {"{"} kind = "pick", id = "gus" {"}"} once for a double tap`, #sent == before + 1 and sent[#sent].kind == "pick" and sent[#sent].id == "gus")
	-- the countdown in place, the price following the minutes left
	M.now += 10
	CrewUi.step()
	check(`{label}: 10 s later: 🏥 3:00 in place, DISCHARGE $200 (a minute less)`, named(rowOf("bruno"), "Left").Text == "🏥 3:00"
		and named(rowOf("bruno"), "Discharge").Text == "DISCHARGE $200", named(rowOf("bruno"), "Discharge").Text)
	-- the money from the State remote: DISCHARGE lights up and asks
	M.remotes.State = M.remotes.State or M.Net.get("State")
	M.Net.get("State").OnClientEvent:Fire({ money = 900 })
	M.flush()
	local out = named(rowOf("bruno"), "Discharge")
	check(`{label}: the money there ($900, the State remote): DISCHARGE green`, out ~= nil and out.BackgroundColor3 == M.MTheme.Contract.good)
	click(out)
	sent = sentOn("Crew")
	check(`{label}: … {"{"} kind = "discharge", id = "bruno" {"}"} sent`, sent[#sent].kind == "discharge" and sent[#sent].id == "bruno")
	click(named(frameOf(), "Close"))
	check(`{label}: ✕ closes it`, not CrewUi.isOpen() and frameOf() == nil)
	M.now = start + 1 -- (the next screen's requests a second on: none taken for a double tap)
	CrewUi.close()
end

-- ── Who comes ───────────────────────────────────────────────────────────────
screen(false, 1280, 764)
remote.OnClientEvent:Fire(stateFor({ have = { "danny", "bruno", "gus" }, pick = "bruno", hospital = { bruno = T + 50 } }, 900))
CrewUi.open()
M.flush()
check("your pick in hospital: who comes instead under the title (amber), PICKED by his role",
	named(frameOf(), "Subtitle").Text == "💪 Bruno is in hospital: 🧑‍🔧 Danny comes into your runs instead" and named(rowOf("bruno"), "Role").Text == "STRONG · PICKED"
	and named(rowOf("danny"), "Ready").Text == "Comes now", named(frameOf(), "Subtitle").Text)
scene("crew-window-hospital")
local asked = #sentOn("Crew")
M.now += 51
CrewUi.step()
CrewUi.step()
local sent = sentOn("Crew")
check("… his time run out: the state asked once (the server's word on it)", #sent == asked + 1 and sent[#sent].kind == "state")
M.now -= 51
remote.OnClientEvent:Fire(stateFor({ have = { "danny", "gus" }, pick = "danny", hospital = { danny = T + 200, gus = T + 30 } }, 900))
M.flush()
check("everybody in hospital: nobody comes, said", named(frameOf(), "Subtitle").Text == "Everybody is in hospital: nobody comes into your runs until one is out")
-- the ways it closes
M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode.Escape })
check("ESC closes it", not CrewUi.isOpen())
CrewUi.open()
M.services.GuiService.MenuOpened:Fire()
check("the Roblox menu closes it", not CrewUi.isOpen())
CrewUi.open()
click(M.gui:FindFirstChild("CrewUi"):FindFirstChild("CrewShade"))
check("a tap beside the card closes it", not CrewUi.isOpen())
local opened = 0
CrewUi.onOpen = function()
	opened += 1
end
CrewUi.open()
CrewUi.open()
check("its onOpen runs once as it opens (the other windows close: client/Main.client.luau)", opened == 1)
screen(true, 844, 354)
local small = frameOf():FindFirstChild("Scale").Scale
screen(false, 1920, 1044)
check("a resize: its scale follows the screen", frameOf():FindFirstChild("Scale").Scale ~= small and frameOf():FindFirstChild("Scale").Scale >= 1)
CrewUi.close()

-- ── The down ring ───────────────────────────────────────────────────────────
screen(false, 1280, 764)
local npcs = M.make("Folder", { Name = "Npcs" }, M.workspace)
local helper = M.make("Model", { Name = "Bruno" }, npcs)
local root = M.make("Part", { Name = "HumanoidRootPart", Position = M.Vector3.new(0, 1, -12) }, helper)
helper.PrimaryPart = root
helper:SetAttribute("CrewKind", "bruno")
M.tagged.CrewDown = {}
local function ringOf(model)
	return CrewUi.rings()[model]
end
CrewUi.step()
check("nobody down: no ring", next(CrewUi.rings()) == nil)
local SECONDS = Config.Crew.Down.Seconds
helper:SetAttribute("CrewDownUntil", M.now + SECONDS)
table.insert(M.tagged.CrewDown, helper)
CrewUi.step()
local ring = ringOf(helper)
local function lit(gui)
	local n = 0
	for _, dot in named(gui, "Ring"):GetChildren() do
		if string.sub(dot.Name, 1, 3) == "Dot" and dot.BackgroundTransparency == 0 then
			n += 1
		end
	end
	return n
end
check(`down (tagged CrewDown, CrewDownUntil): a ring over him (on his root, through walls, within {Config.Crew.Ring.Range} studs)`, ring ~= nil and ring.ClassName == "BillboardGui"
	and ring.Adornee == root and ring.AlwaysOnTop == true and ring.MaxDistance == Config.Crew.Ring.Range and ring.Size.Y.Offset > Config.Crew.Ring.Size)
check(`… {SECONDS} in its middle, every dot lit, "REVIVE BRUNO" under it, fitting`, named(ring, "Left").Text == tostring(SECONDS) and lit(ring) == 24
	and named(ring, "Revive").Text == "REVIVE BRUNO" and #badTexts(ring) == 0, badTexts(ring)[1])
M.now += 6
CrewUi.step()
check("6 s later: 9 left, the dots going out (15 of 24)", named(ring, "Left").Text == "9" and lit(ring) == 15, lit(ring))
scene("crew-down-ring", ring, M.Vector2.new(640, 250))
M.now += 5
CrewUi.step()
check("the last third: red (4 left)", named(ring, "Left").Text == "4" and named(ring, "Ring"):FindFirstChild("Dot1").BackgroundColor3.R > 0.85
	and named(ring, "Left").TextColor3.R > 0.85)
-- the loop: a look every Ring.Every s (RunService.Heartbeat)
M.now += 1
M.services.RunService.Heartbeat:Fire(0.016)
check("the loop looks every Ring.Every s (Heartbeat): 3 left", named(ring, "Left").Text == "3")
M.now += Config.Crew.Ring.Every / 2
helper:SetAttribute("CrewDownUntil", M.now + SECONDS)
M.services.RunService.Heartbeat:Fire(0.016)
check("… not sooner (a frame before it: nothing looked at, the ring as it was)", named(ring, "Left").Text == "3" and ringOf(helper) == ring)
helper:SetAttribute("CrewDownUntil", nil)
table.remove(M.tagged.CrewDown, 1)
CrewUi.step()
check("revived (the tag and the attribute gone): the ring gone", ringOf(helper) == nil and ring.Parent == nil)
helper:SetAttribute("CrewDownUntil", M.now + SECONDS)
table.insert(M.tagged.CrewDown, helper)
CrewUi.step()
local again = ringOf(helper)
check("down again: a new ring, its seconds full", again ~= nil and again ~= ring and named(again, "Left").Text == tostring(SECONDS))
helper.Parent = nil
CrewUi.step()
check("out (his body gone): the ring gone", ringOf(helper) == nil)

remote.OnClientEvent:Fire({ kind = "nonsense" })
remote.OnClientEvent:Fire(5)
remote.OnClientEvent:Fire({ kind = "state", rows = { { id = "nobody" }, 7 } })
M.flush()
check("junk on the remote: ignored (unknown rows dropped)", not CrewUi.isOpen() and #CrewUi.state().rows == 0)
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
	print("ALL CREW UI CHECKS PASSED")
end
