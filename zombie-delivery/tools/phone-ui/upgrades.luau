-- 8.1 SANDBOX: the UPGRADES desk's window (client/UpgradeUi.luau, with client/CardKit.luau and the real shared data:
-- shared/UpgradeRules.luau, Config.SandboxUpgrades) run for real on sandbox_mock.luau's recorder, on a phone held
-- sideways (844 × 390: 844 × 354 under Roblox's top bar, the touch layout; and 667 × 375), a computer (1280 × 800) and a
-- big screen (1920 × 1080). 10.4 THE UPGRADE TREE: nothing when Config.Sandbox.On is false; the state asked at the
-- start; the window only on the server's "open"; the full-screen window on every screen with its header (the title,
-- your money, − / + and ✕; a computer's branch legend), THE TREE (a ScrollingFrame both ways) and THE DETAILS beside it;
-- the trunk's five tiles (Tier_1 … Tier_5: OWNED, the next one's price), every node of Config's order but the trunk
-- (Node_<id>: its icon, its name, what its next rank gives, its cost or MAX / 🔒 / SOON, its pips; its Status), the
-- lanes' names, the lines (the trunk's, a node's to its parents and a branch's first node to its tier); the grid's cells
-- unique, every node inside the canvas; a fresh window's node (the cheapest the money buys) selected and in view; a tap
-- on a node selects it (the details: its branch, rank, blurb, now / next, the checklist ✓ / ✗, the price and BUY, a
-- grey NEED $X, "🔒 why", "⏳ soon", a gold MAX); BUY's request ({ kind = "buy", id, level }) once for a double tap; a
-- NEED or a lock only says so; the "bought" toast (a rank, the trunk's tier); the money following the State remote in
-- place; no redraw for the same state; − / + zoom (the nodes bigger, the canvas too), a mouse's drag scrolls it; ✕, ESC,
-- the gamepad's B and a tap on the shade close it; on each screen the window on the screen, the texts fitting (a name
-- may be cut with "…", a cost or a price never), a phone's buttons a finger's size (44 px); a resize while open.
-- `luau upgrades.luau -a dump` prints the preview's scenes as JSON instead (sandbox_preview.py --scenes upgrades.luau).
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
local UpgradeRules = require("./UpgradeRules")
local MoveLayout = require("./MoveLayout")

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
local function key(code)
	M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode[code] }, false)
end
local box = M.box
local function show(b)
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end
local function inside(b)
	return MoveLayout.inside(b, M.width, M.height)
end
local function within(b, outer)
	return b.x0 >= outer.x0 - 0.5 and b.y0 >= outer.y0 - 0.5 and b.x1 <= outer.x1 + 0.5 and b.y1 <= outer.y1 + 0.5
end
local function overlaps(a, b)
	return a.x0 < b.x1 - 0.5 and b.x0 < a.x1 - 0.5 and a.y0 < b.y1 - 0.5 and b.y0 < a.y1 - 0.5
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
-- Does a one-line text fit its label (after the scales above it)? A name may run long and is cut with "…"; a cost, a
-- price, a rank or a button never.
local NEVER_CUT = { Cost = true, Price = true, Buy = true, Rank = true, Max = true, Tier = true, Title = true }
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		local truncated = object.TextTruncate and object.TextTruncate.Name == "AtEnd" and not NEVER_CUT[object.Name]
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
-- The buttons a finger taps on a phone: each at least 44 × 44 screen px.
local function smallButtons(root)
	local small = {}
	for _, object in all(root, function(o)
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false and o.Name ~= "UpgradeShade"
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end

-- ── Screens ─────────────────────────────────────────────────────────────────
local camera = M.workspace.CurrentCamera
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	camera.ViewportSize = M.Vector2.new(w, h + 36)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	M.flush()
end

-- ── The preview's scenes (sandbox_preview.py --scenes upgrades.luau) ────────
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
	elseif p.ClassName == "ScrollingFrame" then
		out.canvas = { (p.CanvasPosition or M.Vector2.zero).X, (p.CanvasPosition or M.Vector2.zero).Y }
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
		local TouchLayout = require("./TouchLayout")
		local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
		table.insert(overlay, { kind = "pill", box = cluster.sprint, label = "SPRINT" })
		table.insert(overlay, { kind = "minimap", box = M.leftColumn })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
M.services.UserInputService.InputChanged = M.signal() -- (a mouse's drag: the window listens when Roblox has it)
local UpgradeUi = require("./UpgradeUi")
screen(true, 844, 354)
Config.Sandbox.On = false
UpgradeUi.start()
check("Config.Sandbox.On false: UpgradeUi.start() does nothing", M.remotes.Upgrades == nil and #sentOn("Upgrades") == 0)
Config.Sandbox.On = true

-- ── On: the state asked, the window only on "open" ──────────────────────────
UpgradeUi.start()
local remote = M.remotes.Upgrades
check("on: the Upgrades remote asked for the state", remote ~= nil and #sentOn("Upgrades") == 1 and sentOn("Upgrades")[1][1].kind == "state")
-- a player some hours in: the Storehouse (tier 3), a few nodes in each branch
local MID = { warehouse = 2, lights = 3, idle = 1, rare = 1, showstands = 2, traffic = 1, engine = 3, clock = 1, danny = 1, toughness = 1, paint = 1, junk = 3 }
remote.OnClientEvent:Fire({ kind = "state", levels = MID, money = 14250 })
M.flush()
check("a state alone opens nothing (its junk id dropped)", not UpgradeUi.isOpen() and UpgradeUi.state() ~= nil and UpgradeUi.state().money == 14250 and UpgradeUi.state().levels.junk == nil)
remote.OnClientEvent:Fire({ kind = "open" })
M.flush()
local gui = M.gui:FindFirstChild("UpgradeUi")
local window = gui and named(gui, "Upgrades")
check("\"open\" (the desk's prompt): the window in its ScreenGui \"UpgradeUi\"", UpgradeUi.isOpen() and window ~= nil and gui.ClassName == "ScreenGui")
local shade = named(gui, "UpgradeShade")
check("… modal: its shade frees the mouse (Modal)", shade ~= nil and shade.Modal == true)

local P = Config.SandboxUpgrades.List
local cash = UpgradeRules.money
local function parts()
	window = named(gui, "Upgrades")
	return window, named(window, "Tree"), named(window, "Details")
end
local function nodeOf(id)
	local _, tree = parts()
	return tree:FindFirstChild(`Node_{id}`)
end
-- The window on this screen: on it, its tree and details inside it side by side, its texts fitting, the tree's nodes
-- and tiles all there (on the canvas, none on another), its lanes and lines; a phone's buttons a finger's size.
local function windowChecks(label)
	local frame, tree, details = parts()
	local wb, tb, db = box(frame), box(tree), box(details)
	check(`{label}: the window on the screen, the tree and the details inside it, side by side`, inside(wb) and within(tb, wb) and within(db, wb) and tb.x1 <= db.x0 + 0.5,
		`{show(wb)} / {show(tb)} / {show(db)}`)
	check(`{label}: … the window fills the screen (full-screen: its margins only)`, wb.x1 - wb.x0 >= M.width - 40 and wb.y1 - wb.y0 >= M.height - 40, show(wb))
	check(`{label}: … its texts fit`, #badTexts(frame) == 0, badTexts(frame)[1])
	check(`{label}: … the tree scrolls both ways`, tree.ClassName == "ScrollingFrame" and tree.ScrollingDirection.Name == "XY" and tree.ClipsDescendants == true)
	local count, every = 0, true
	for _, id in UpgradeRules.Order do
		if id ~= "warehouse" then
			count += 1
			every = every and tree:FindFirstChild(`Node_{id}`) ~= nil
		end
	end
	local tiles = 0
	for n = 1, #Config.Warehouse.Levels do
		tiles += if tree:FindFirstChild(`Tier_{n}`) then 1 else 0
	end
	check(`{label}: … every node of the tree ({count}) and the trunk's {#Config.Warehouse.Levels} tiles`, every and tiles == #Config.Warehouse.Levels)
	local lanes = true
	for _, branch in UpgradeRules.branches() do
		lanes = lanes and tree:FindFirstChild(`Lane_{branch.id}`) ~= nil
	end
	local lines = #all(tree, function(o)
		return string.match(o.Name, "^Line%d+[abc]$") ~= nil
	end)
	check(`{label}: … each branch's lane named, the lines drawn (the trunk's {#Config.Warehouse.Levels - 1}, {lines} of the nodes')`, lanes
		and tree:FindFirstChild(`Trunk{#Config.Warehouse.Levels - 1}`) ~= nil and lines >= #UpgradeRules.links())
	if M.touch then
		check(`{label}: … every button a finger's size (the nodes, BUY, − / +, ✕)`, #smallButtons(frame) == 0, smallButtons(frame)[1])
	end
end

-- ── The phone ───────────────────────────────────────────────────────────────
windowChecks("844 x 390")
do
	local zoom = UpgradeUi.zoom()
	local size = UpgradeUi.canvasSize(zoom)
	local cells, unique, onCanvas = {}, true, true
	local boxes = {}
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		local at = if id == "warehouse" then nil else def.at
		if at then
			local k = `{at[1]},{at[2]}`
			unique = unique and cells[k] == nil
			cells[k] = id
			local b = UpgradeUi.place(at, zoom)
			onCanvas = onCanvas and b.x >= 0 and b.y >= 0 and b.x + b.w <= size.X and b.y + b.h <= size.Y
			table.insert(boxes, { x0 = b.x, y0 = b.y, x1 = b.x + b.w, y1 = b.y + b.h, id = id })
		end
	end
	for n = 1, #Config.Warehouse.Levels do
		local b = UpgradeUi.place(UpgradeRules.trunkAt(n), zoom)
		local k = `{UpgradeRules.trunkAt(n)[1]},{UpgradeRules.trunkAt(n)[2]}`
		unique = unique and cells[k] == nil
		cells[k] = `tier {n}`
		table.insert(boxes, { x0 = b.x, y0 = b.y, x1 = b.x + b.w, y1 = b.y + b.h, id = `tier {n}` })
	end
	local apart = true
	for i = 1, #boxes do
		for j = i + 1, #boxes do
			apart = apart and not overlaps(boxes[i], boxes[j])
		end
	end
	check("the grid: every node and tier its own cell, none on another, all on the canvas", unique and apart and onCanvas)
	local rows = 0
	for _, branch in UpgradeRules.branches() do
		rows = math.max(rows, branch.row)
	end
	check("the lanes: LOOKS over the HALL over the trunk, the SHOWROOM, RUNS and the CREW under it", (UpgradeRules.branch("looks") :: any).row < (UpgradeRules.branch("hall") :: any).row
		and (UpgradeRules.branch("hall") :: any).row < Config.SandboxUpgrades.Grid.TrunkRow and (UpgradeRules.branch("showroom") :: any).row > Config.SandboxUpgrades.Grid.TrunkRow
		and (UpgradeRules.branch("showroom") :: any).row < (UpgradeRules.branch("runs") :: any).row and (UpgradeRules.branch("runs") :: any).row < (UpgradeRules.branch("crew") :: any).row
		and rows <= Config.SandboxUpgrades.Grid.Rows)
end
local frame, tree, details = parts()
check("the header: \"⬆ DELIVEROS UPGRADES\", your money", named(frame, "Title").Text == "⬆ DELIVEROS UPGRADES" and string.find(named(frame, "Subtitle").Text, "$14,250", 1, true) ~= nil,
	named(frame, "Subtitle").Text)
-- the nodes' states
local lights, engine, rare, haggle, truck, keyNode = nodeOf("lights"), nodeOf("engine"), nodeOf("rare"), nodeOf("haggle"), nodeOf("truck"), nodeOf("key")
local function lit(made, count)
	local n = 0
	for i = 1, count do
		local pip = made:FindFirstChild(`Pip{i}`)
		n += if pip and pip.BackgroundColor3 ~= M.MTheme.Contract.track then 1 else 0
	end
	return n
end
check("a node: its icon, its name, what its next rank gives, its cost, its pips (Hall spotlights: rank 3 of 5, three lit)", named(lights, "Icon").Text == P.lights.icon
	and named(lights, "NodeName").Text == "Hall spotlights" and named(lights, "Effect").Text == `→ {UpgradeRules.words("lights", 4, MID)}`
	and named(lights, "Cost").Text == cash(P.lights.prices[4]) and lights:FindFirstChild("Pip5") ~= nil and lit(lights, 5) == 3, named(lights, "Effect").Text)
check("… its Status: \"short\" (the money is missing), \"buy\" (Overtime's next rank: in reach)", lights:GetAttribute("Status") == "short" and nodeOf("clock"):GetAttribute("Status") == "buy"
	and named(nodeOf("clock"), "Cost").TextColor3 == require("./CardKit").Color.money)
check("… Van engine at its top: MAX in gold, what it gives", engine:GetAttribute("Status") == "max" and named(engine, "Cost").Text == "MAX" and named(engine, "Effect").Text == UpgradeRules.words("engine", 3, MID))
check("… Sales pitch (its parent Shop window there, the Storehouse too): in reach; Spare keys (Overtime there): the money is missing", haggle:GetAttribute("Status") == "buy"
	and keyNode:GetAttribute("Status") == "short", `{haggle:GetAttribute("Status")} {keyNode:GetAttribute("Status")}`)
check("… VIP buyers locked (Sales pitch rank 2): 🔒 and its price, grey", nodeOf("vip"):GetAttribute("Status") == "locked" and named(nodeOf("vip"), "Cost").Text == `🔒 {cash(P.vip.prices[1])}`)
check("… the bigger truck: SOON, grey", truck:GetAttribute("Status") == "soon" and named(truck, "Cost").Text == "SOON")
check("… a node at its rank 1 of 3 (Collector's corner): one pip lit", lit(rare, 3) == 1 and rare:FindFirstChild("Pip4") == nil)
local tier3, tier4 = tree:FindFirstChild("Tier_3"), tree:FindFirstChild("Tier_4")
check("the trunk: tiers 1 – 3 OWNED, the Big Warehouse's price next, its stands (hall · showroom)", named(tree:FindFirstChild("Tier_1"), "Cost").Text == "OWNED"
	and named(tier3, "Cost").Text == "OWNED" and tier3:GetAttribute("Owned") == true and named(tier4, "Cost").Text == cash(P.warehouse.prices[3]) and tier4:GetAttribute("Owned") == false
	and named(tier4, "NodeName").Text == "Big Warehouse" and named(tier4, "Effect").Text == `{Config.Warehouse.Levels[4].stands} hall · {Config.Showroom.Levels[4].Stands} showroom`)
-- a fresh window's node: the cheapest the money buys, in view
local first = UpgradeUi.selected()
local best, bestPrice = nil, math.huge
for _, row in UpgradeRules.rows(UpgradeUi.state().levels, 14250) do
	if row.status == "buy" and row.price < bestPrice then
		best, bestPrice = row.id, row.price
	end
end
check(`a fresh window selects the cheapest node the money buys ({best})`, first == best, first)
local function inView(made)
	return overlaps(box(made), box(tree))
end
local firstNode = if first == "warehouse" then tree:FindFirstChild("Tier_4") else nodeOf(first)
check("… and shows it in the tree's view", firstNode ~= nil and inView(firstNode), firstNode and show(box(firstNode)))
scene("upgrades-phone")

-- ── A tap on a node: the details ───────────────────────────────────────────
press(nodeOf("lights"))
M.flush()
frame, tree, details = parts()
local buy = named(details, "Buy")
check("a tap on Hall spotlights: the details (its icon, name, branch, RANK 3/5, its blurb, now and next)", UpgradeUi.selected() == "lights" and named(details, "NodeName").Text == "Hall spotlights"
	and named(details, "Branch").Text == "COLLECTION HALL" and named(details, "Rank").Text == "RANK 3/5" and named(details, "Blurb").Text == P.lights.blurb
	and named(details, "Now").Text == `Now: {UpgradeRules.words("lights", 3, MID)}` and named(details, "Next").Text == `Next: {UpgradeRules.words("lights", 4, MID)}`,
	named(details, "Rank").Text)
check(`… its price {cash(P.lights.prices[4])}, a grey NEED {cash(P.lights.prices[4] - 14250)}; its tier in the checklist (✓ The Storehouse)`, named(details, "Price").Text == cash(P.lights.prices[4])
	and buy ~= nil and buy.Text == `NEED {cash(P.lights.prices[4] - 14250)}` and buy.BackgroundColor3 == require("./CardKit").Buttons.shut.face
	and named(details, "Need1") ~= nil and named(details, "Need1").Text == "✓ The Storehouse", named(details, "Need1") and named(details, "Need1").Text)
check("… the node's edge white (selected)", (function()
	local stroke = nil
	for _, child in nodeOf("lights"):GetChildren() do
		if child.ClassName == "UIStroke" then
			stroke = child
		end
	end
	return stroke ~= nil and stroke.Color == M.MTheme.Contract.text
end)())
local before = #sentOn("Upgrades")
local toastsBefore = #M.toasts
press(buy)
check("a grey NEED sends nothing, it says how much is missing", #sentOn("Upgrades") == before and M.toasts[#M.toasts] == `Hall spotlights: you need {cash(P.lights.prices[4] - 14250)} more.`
	and #M.toasts == toastsBefore + 1, M.toasts[#M.toasts])
-- the money from the State remote (a sale while it is open): NEED follows in place, no rebuild
local sameTree = tree
M.remotes.State.OnClientEvent:Fire({ money = 14000 })
M.flush()
frame, tree, details = parts()
check("the money follows the State remote: NEED in place (no redraw: the same tree)", tree == sameTree and named(details, "Buy").Text == `NEED {cash(P.lights.prices[4] - 14000)}`
	and string.find(named(frame, "Subtitle").Text, "$14,000", 1, true) ~= nil, named(details, "Buy").Text)
-- a locked node: its reasons
press(nodeOf("vip"))
M.flush()
frame, tree, details = parts()
local locked = named(details, "Locked")
check("VIP buyers (locked): \"🔒 Needs Sales pitch rank 2\" grey in place of BUY, its checklist ✗", locked ~= nil and locked.Text == "🔒 Needs Sales pitch rank 2"
	and named(details, "Buy") == nil and named(details, "Need1").Text == "✗ Sales pitch rank 2" and named(details, "Need2").Text == "✗ The Big Warehouse",
	locked and locked.Text)
before = #sentOn("Upgrades")
press(locked)
check("… a tap on it sends nothing, only says why", #sentOn("Upgrades") == before and M.toasts[#M.toasts] == "VIP buyers: 🔒 Needs Sales pitch rank 2", M.toasts[#M.toasts])
scene("upgrades-phone-locked")
press(nodeOf("truck"))
M.flush()
frame, tree, details = parts()
check("the bigger truck: \"⏳ Comes with the bigger run trucks\", no price", named(details, "Locked").Text == `⏳ {P.truck.soon}` and named(details, "Price") == nil)
press(nodeOf("engine"))
M.flush()
frame, tree, details = parts()
check("Van engine at its top: a gold MAX, \"Top rank\", no BUY", named(details, "Max") ~= nil and named(details, "Max").Text == "MAX" and named(details, "Buy") == nil
	and named(details, "Next").Text == "Top rank" and named(details, "Rank").Text == "RANK 3/3")
-- the trunk's tile selects the trunk
press(tree:FindFirstChild("Tier_5"))
M.flush()
frame, tree, details = parts()
check("a tier's tile selects the trunk: \"TIER 3/5\", the Big Warehouse's price", UpgradeUi.selected() == "warehouse" and named(details, "Rank").Text == "TIER 3/5"
	and named(details, "Price").Text == cash(P.warehouse.prices[3]) and named(details, "NodeName").Text == "Deliveros Warehouse")
-- BUY
press(nodeOf("clock"))
M.flush()
frame, tree, details = parts()
buy = named(details, "Buy")
before = #sentOn("Upgrades")
press(buy)
press(buy)
local sent = sentOn("Upgrades")
check("Overtime's BUY sends { kind = \"buy\", id = \"clock\", level = 2 } once for a double tap; the button waits (…)", #sent == before + 1 and sent[#sent][1].kind == "buy"
	and sent[#sent][1].id == "clock" and sent[#sent][1].level == 2 and named(details, "Buy").Text == "…")
remote.OnClientEvent:Fire({ kind = "bought", id = "clock", level = 2 })
check("\"bought\": a toast with the rank and what it gives", M.toasts[#M.toasts] == `Overtime: rank 2 · {UpgradeRules.words("clock", 2, MID)}`, M.toasts[#M.toasts])
remote.OnClientEvent:Fire({ kind = "bought", id = "warehouse", level = 3 })
check("… the trunk's: its tier", string.find(M.toasts[#M.toasts], "Deliveros Warehouse: tier 4 · ", 1, true) == 1, M.toasts[#M.toasts])
local after = table.clone(MID)
after.junk = nil
after.clock = 2
remote.OnClientEvent:Fire({ kind = "state", levels = after, money = 2000 })
M.flush()
frame, tree, details = parts()
check("the new state: drawn again (Overtime RANK 2/3, the node's two pips lit), the selection kept", UpgradeUi.selected() == "clock" and named(details, "Rank").Text == "RANK 2/3"
	and lit(nodeOf("clock"), 3) == 2)
local same = named(gui, "Upgrades")
remote.OnClientEvent:Fire({ kind = "state", levels = after, money = 2000 })
M.flush()
check("the same state again: no redraw (a tap is never lost)", named(gui, "Upgrades") == same)

-- ── − / + and the drag ─────────────────────────────────────────────────────
do
	local zoom0 = UpgradeUi.zoom()
	local w0 = box(nodeOf("lights")).x1 - box(nodeOf("lights")).x0
	press(named(frame, "ZoomIn"))
	M.flush()
	local zoom1 = UpgradeUi.zoom()
	local w1 = box(nodeOf("lights")).x1 - box(nodeOf("lights")).x0
	frame, tree, details = parts()
	check("+ zooms in: a step up, the nodes bigger, the canvas too", zoom1 > zoom0 and w1 > w0 and tree.CanvasSize.X.Offset == UpgradeUi.canvasSize(zoom1).X, `{zoom0} → {zoom1}`)
	press(named(frame, "ZoomOut"))
	press(named(parts(), "ZoomOut"))
	M.flush()
	check("− twice: a step under where it was", UpgradeUi.zoom() < zoom0)
	UpgradeUi.zoom(#Config.SandboxUpgrades.Window.Zooms + 5)
	check("UpgradeUi.zoom past the steps: the last", UpgradeUi.zoom() == Config.SandboxUpgrades.Window.Zooms[#Config.SandboxUpgrades.Window.Zooms])
	UpgradeUi.zoom(Config.SandboxUpgrades.Window.DefaultZoom)
	M.flush()
end
UpgradeUi.close()

-- ── Closing ────────────────────────────────────────────────────────────────
UpgradeUi.open()
check("UpgradeUi.open() opens it again (the state kept)", UpgradeUi.isOpen() and named(gui, "Upgrades") ~= nil)
key("Escape")
check("ESC closes it", not UpgradeUi.isOpen() and named(gui, "Upgrades") == nil)
UpgradeUi.open()
key("ButtonB")
check("the gamepad's B closes it", not UpgradeUi.isOpen())
UpgradeUi.open()
press(named(gui, "UpgradeShade"))
check("a tap beside the window closes it", not UpgradeUi.isOpen())
UpgradeUi.open()
press(named(named(gui, "Upgrades"), "Close"))
check("✕ closes it", not UpgradeUi.isOpen())

-- ── A new player ────────────────────────────────────────────────────────────
remote.OnClientEvent:Fire({ kind = "state", levels = {}, money = 2000 })
remote.OnClientEvent:Fire({ kind = "open" })
M.flush()
windowChecks("844 x 390, a new player")
frame, tree, details = parts()
check("a new player: the trunk's next tier (the Workshop, $1,000) selected, BUY green; tier 1 OWNED", UpgradeUi.selected() == "warehouse"
	and named(details, "Rank").Text == "TIER 1/5" and named(details, "Buy").Text == "BUY" and named(details, "Price").Text == cash(P.warehouse.prices[1])
	and named(tree:FindFirstChild("Tier_1"), "Cost").Text == "OWNED" and named(tree:FindFirstChild("Tier_2"), "Cost").Text == cash(P.warehouse.prices[1]))
check("… a first node of each branch in reach (Hall spotlights, Showroom stands, Van engine, Danny's training: buy), their children locked",
	nodeOf("lights"):GetAttribute("Status") == "buy" and nodeOf("showstands"):GetAttribute("Status") == "short" and nodeOf("engine"):GetAttribute("Status") == "buy"
	and nodeOf("danny"):GetAttribute("Status") == "buy" and nodeOf("idle"):GetAttribute("Status") == "locked" and nodeOf("toughness"):GetAttribute("Status") == "locked",
	nodeOf("showstands"):GetAttribute("Status"))
before = #sentOn("Upgrades")
press(named(details, "Buy"))
sent = sentOn("Upgrades")
check("the trunk's BUY sends { kind = \"buy\", id = \"warehouse\", level = 1 }", #sent == before + 1 and sent[#sent][1].id == "warehouse" and sent[#sent][1].level == 1)
remote.OnClientEvent:Fire({ kind = "bought", id = "warehouse", level = 1 })
check("\"bought\": \"Deliveros Warehouse: tier 2 · Workshop · 4 stands\"", M.toasts[#M.toasts] == "Deliveros Warehouse: tier 2 · Workshop · 4 stands", M.toasts[#M.toasts])
scene("upgrades-phone-new")
UpgradeUi.close()

-- ── Everything bought ──────────────────────────────────────────────────────
remote.OnClientEvent:Fire({ kind = "state", levels = UpgradeRules.full(), money = 54000 })
remote.OnClientEvent:Fire({ kind = "open" })
M.flush()
windowChecks("844 x 390, everything bought")
frame, tree, details = parts()
local maxes, soon = 0, 0
for _, id in UpgradeRules.Order do
	local made = tree:FindFirstChild(`Node_{id}`)
	if made then
		maxes += if made:GetAttribute("Status") == "max" then 1 else 0
		soon += if made:GetAttribute("Status") == "soon" then 1 else 0
	end
end
local sold = 0
for _ in UpgradeRules.full() do
	sold += 1
end
check(`… every node MAX ({sold - 1}), the ones that come later SOON ({soon}); the trunk's five tiles OWNED`, maxes == sold - 1 and soon == #UpgradeRules.Order - sold
	and named(tree:FindFirstChild("Tier_5"), "Cost").Text == "OWNED" and named(details, "Max") ~= nil)
scene("upgrades-phone-max")
UpgradeUi.close()

-- ── A computer (1280 × 800) and a big screen (1920 × 1080) ─────────────────
local mid = table.clone(MID)
mid.junk = nil
remote.OnClientEvent:Fire({ kind = "state", levels = mid, money = 14250 })
for _, size in { { 1280, 764, "computer" }, { 1920, 1044, "big" } } do
	screen(false, size[1], size[2])
	UpgradeUi.open()
	M.flush()
	local label = `{size[1]} x {size[2] + 36}`
	windowChecks(label)
	frame, tree, details = parts()
	local plan = UpgradeUi.layout(M.width, M.height, false)
	check(`{label}: … centred`, math.abs((plan.x + plan.w * plan.scale / 2) - M.width / 2) <= 1 and math.abs((plan.y + plan.h * plan.scale / 2) - M.height / 2) <= 1)
	local legend = 0
	for _, branch in UpgradeRules.branches() do
		legend += if named(frame, `Legend_{branch.id}`) then 1 else 0
	end
	check(`{label}: … the branches' legend in the header (each its colour)`, legend == #UpgradeRules.branches(), legend)
	local tiles = 0
	for n = 1, #Config.Warehouse.Levels do
		tiles += if inView(tree:FindFirstChild(`Tier_{n}`)) then 1 else 0
	end
	local picked = UpgradeUi.selected()
	local pickedNode = if picked == "warehouse" then nil else nodeOf(picked)
	check(`{label}: … the trunk's row in view ({tiles} of its tiles) with the selected node ({picked})`, tiles >= 3 and (pickedNode == nil or inView(pickedNode)), tiles)
	scene(`upgrades-{size[3]}`)
	key("Escape")
end
-- a mouse's drag (the left button held on the tree) scrolls it
do
	screen(false, 1280, 764)
	UpgradeUi.open()
	M.flush()
	frame, tree = parts()
	UpgradeUi.zoom(#Config.SandboxUpgrades.Window.Zooms)
	M.flush()
	frame, tree = parts()
	local tb = box(tree)
	local from = tree.CanvasPosition
	local at = M.Vector2.new((tb.x0 + tb.x1) / 2, (tb.y0 + tb.y1) / 2)
	local UIS = M.services.UserInputService
	UIS.InputBegan:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1, Position = at }, false)
	UIS.InputChanged:Fire({ UserInputType = M.Enum.UserInputType.MouseMovement, Position = M.Vector2.new(at.X - 120, at.Y - 40) })
	local moved = tree.CanvasPosition
	UIS.InputEnded:Fire({ UserInputType = M.Enum.UserInputType.MouseButton1, Position = at })
	UIS.InputChanged:Fire({ UserInputType = M.Enum.UserInputType.MouseMovement, Position = M.Vector2.new(at.X - 300, at.Y) })
	check("a mouse's drag on the tree scrolls it (the canvas follows), the button let go: no more", moved.X > from.X and tree.CanvasPosition.X == moved.X, `{from.X} → {moved.X}`)
	UpgradeUi.zoom(Config.SandboxUpgrades.Window.DefaultZoom)
	UpgradeUi.close()
end

-- ── A resize while it is open; a smaller phone ─────────────────────────────
UpgradeUi.open()
screen(true, 844, 354)
window = named(gui, "Upgrades")
check("a resize to a phone while open: drawn again for it (a finger's buttons)", math.abs(M.uiScale(window) - UpgradeUi.layout(844, 354, true).scale) < 0.001 and #smallButtons(window) == 0)
UpgradeUi.close()
remote.OnClientEvent:Fire({ kind = "state", levels = {}, money = 900 })
screen(true, 667, 339)
UpgradeUi.open()
M.flush()
windowChecks("667 x 375, a new player")
local small = UpgradeUi.layout(667, 339, true)
check("… the details' panel never under a finger's BUY and its words (the tree takes the rest)", small.panelW * small.scale >= 150 and small.treeW > small.panelW, `{small.panelW} {small.treeW}`)
scene("upgrades-small-phone")
UpgradeUi.close()

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
	print("ALL UPGRADE UI CHECKS PASSED")
end
