-- 8.2 SANDBOX: the collection book (client/CollectionBookUi.luau, with client/CardKit.luau and the real shared data:
-- shared/CollectionBookRules.luau, Config.CollectionBook, the furniture's real catalogue) and its 📖 BOOK chip in the
-- real client/SandboxHud.luau, run for real on sandbox_mock.luau's recorder, on a phone held sideways (844 × 390:
-- 844 × 354 under Roblox's top bar, the touch layout), a computer (1280 × 800) and a big screen (1920 × 1080): the
-- state asked at the start; the chip beside "📦 N in stock" (a finger's size on a
-- phone, its key C on a computer, the HUD's block still clear of the touch buttons) opening and closing the book; the
-- key C (not when something else took it, not on the start screen); the book: "23 / 97 found" and its bar, the counts,
-- the milestones (✔ when paid, else how far, and the reward), the tabs ALL / COLLECTIBLES / FURNITURE with their counts,
-- a card a piece in the book's order (found: its name, rarity colour, ×n, best condition, value; unknown: "???", a "?"
-- or its dark silhouette), the 3D pictures only on the cards on screen and never more than Config.CollectionBook.MaxViews
-- (a found piece in its colours, an unknown one tinted to the silhouette; each model built once); the toasts (a new
-- piece, several, a milestone; held while the HUD is hidden); no redraw for the same state; ✕, ESC, the gamepad's B, the
-- menu, a tap beside it close it; opening it closes the warehouse's picker; on each screen the card on the screen, the
-- left column inside it, the texts fitting their room and a phone's buttons a finger's size (44 px); a resize while
-- open. `luau collectionbook.luau -a dump` prints the preview's scenes as JSON instead (sandbox_preview.py --scenes
-- collectionbook.luau). 8.7 review: a piece only bought from another player: its card with a gold BOUGHT tag, no find
-- (the progress, the tabs, no "new" toast), the side's hint saying why when there is room.
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
local Rules = require("./CollectionBookRules")
local TouchLayout = require("./TouchLayout")
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
local function key(code, processed)
	M.services.UserInputService.InputBegan:Fire({ KeyCode = M.Enum.KeyCode[code] }, processed == true)
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
		if node.Visible == false then
			return false
		end
		node = node.Parent
	end
	return true
end
local function padding(object)
	for _, child in object:GetChildren() do
		if child.ClassName == "UIPadding" then
			return (child.PaddingLeft and child.PaddingLeft.Offset or 0), (child.PaddingRight and child.PaddingRight.Offset or 0)
		end
	end
	return 0, 0
end
-- Does a one-line text fit its label (after the scales above it, its padding, a key chip in it)? A piece's or a
-- milestone's name may run long and is cut with "…"; a count, a value or a tab never.
local NEVER_CUT = { Progress = true, Count = true, Value = true, Reward = true, FurnitureCount = true, CollectibleCount = true }
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		local truncated = object.TextTruncate and object.TextTruncate.Name == "AtEnd" and not NEVER_CUT[object.Name]
		if not object.TextWrapped and not truncated then
			local b = box(object)
			local s = M.scaleOf(object)
			local left, right = padding(object)
			local room = (b.x1 - b.x0) - (left + right) * s
			local keyLabel = object:FindFirstChild("Key")
			if keyLabel and keyLabel.Visible then
				room -= (b.x1 - box(keyLabel).x0)
			end
			local need = M.textWidth(object.Text, (object.TextSize or 14) * s, object.Font)
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
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false and o.Name ~= "BookShade"
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
-- What the HUD's block must keep clear of (tools/phone-ui/sandbox.luau's): the touch buttons, the thumbstick, the jump,
-- the left column on touch; the health row and the key hints on a computer; the move's panel.
local function blocks()
	local list = {}
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		for _, b in TouchLayout.buttons(cluster) do
			table.insert(list, b)
		end
		table.insert(list, cluster.thumb)
		table.insert(list, cluster.jump)
		table.insert(list, M.leftColumn)
	else
		table.insert(list, { x0 = 16, y0 = M.height - 16 - 258 * S, x1 = 16 + 200 * S, y1 = M.height - 16 })
		table.insert(list, { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W - 260 * S, y0 = 0, x1 = M.width, y1 = 4 + 90 * S })
	end
	table.insert(list, MoveLayout.panel(M.width, S))
	return list
end

-- ── The preview's scenes (sandbox_preview.py --scenes collectionbook.luau) ──
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
	elseif p.ClassName == "ViewportFrame" then
		out.emoji = n:GetAttribute("Emoji")
		out.sil = n:GetAttribute("Silhouette") == true -- (an unknown piece: drawn as its emoji's silhouette)
	elseif p.ClassName == "ScreenGui" then
		out.display = p.DisplayOrder or 0
		out.enabled = p.Enabled ~= false
	end
	local kids = {}
	if p.ClassName ~= "ViewportFrame" then -- (a 3D picture's model: the preview draws its emoji)
		for _, child in n:GetChildren() do
			table.insert(kids, node(child))
		end
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
	-- Hud's column: the block's spacer, then the toasts the scene asks for
	local slot = M.topStack:FindFirstChild("Slot_sandbox")
	local toastSlot = M.topStack:FindFirstChild("Slot_toasts") or M.make("Frame", { Name = "Slot_toasts", Size = M.UDim2.fromOffset(380, 0), BackgroundTransparency = 1 }, M.topStack)
	for _, child in toastSlot:GetChildren() do
		child:Destroy()
	end
	local spacer = slot and slot:FindFirstChild("SandboxSpace")
	if spacer then
		slot.Size = M.UDim2.fromOffset(380, spacer.Size.Y.Offset)
		local y = spacer.Size.Y.Offset + 8
		for _, text in M.sceneToasts or {} do
			local w = M.textWidth(text, 14, M.Enum.Font.GothamMedium) + 28
			local strip = M.make("Frame", { Name = "Toast", Size = M.UDim2.fromOffset(w, 30), Position = M.UDim2.fromOffset(0, y), BackgroundColor3 = M.MTheme.Contract.charcoal, BackgroundTransparency = 0.22 }, toastSlot)
			M.make("Frame", { Name = "Rule", Size = M.UDim2.fromOffset(2, 30), BackgroundColor3 = M.MTheme.Contract.text }, strip)
			M.make("TextLabel", { Name = "Text", Text = text, TextSize = 14, Font = M.Enum.Font.GothamMedium, TextColor3 = M.MTheme.Contract.text, TextXAlignment = M.Enum.TextXAlignment.Left, Size = M.UDim2.new(1, -14, 1, 0), Position = M.UDim2.fromOffset(14, 0), BackgroundTransparency = 1 }, strip)
			y += 38
		end
	end
	local overlay = {}
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
		table.insert(overlay, { kind = "pill", box = cluster.sprint, label = "SPRINT" })
		table.insert(overlay, { kind = "minimap", box = M.leftColumn })
	else
		table.insert(overlay, { kind = "minimap", box = { x0 = 16, y0 = M.height - 16 - 30 * S, x1 = 16 + 200 * S, y1 = M.height - 16 } })
		table.insert(overlay, { kind = "text", box = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W - 150, y0 = 4, x1 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y1 = 30 }, label = "? KEYS [F1]" }) -- (9.0: no MOUSE [ALT] in the sandbox)
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── The state the server sends ──────────────────────────────────────────────
-- 23 pieces found: 20 of the furniture (the first 20 in the book), 3 collectibles (the jukebox, the gold record, the
-- knight's armour: a legendary); found 10, found 20 and A legendary! paid.
local FOUND = {}
for index = 1, 20 do
	FOUND[Rules.Furniture[index]] = { n = 1 + index % 3, best = 0.5 + (index % 5) / 10 }
end
FOUND.jukebox = { n = 2, best = 0.92 }
FOUND.gold_record = { n = 1, best = 0.71 }
FOUND.knight_armour = { n = 1, best = 0.64 }
local function state(book, paid, new)
	return { kind = "state", book = book, paid = paid, new = new or {} }
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
local SandboxHud = require("./SandboxHud")
local Book = require("./CollectionBookUi")
local WarehouseUi = require("./WarehouseUi")
screen(true, 844, 354)

-- ── On: the HUD's chip, the state asked ────────────────────────────────────
SandboxHud.start() -- (client/Main.client.luau starts SandboxHud before the book)
Book.start()
local remote = M.remotes.CollectionBook
check("on: the CollectionBook remote asked for the state", remote ~= nil and #sentOn("CollectionBook") == 1 and sentOn("CollectionBook")[1][1].kind == "state")
SandboxHud.setState({ money = 12480 })
M.remotes.Collection.OnClientEvent:Fire({ kind = "state", stock = { { uid = "a1", item = "sofa", condition = 1, got = 1 } }, income = 0, stands = 12 })
M.flush()
local block = SandboxHud.block()
local stockChip = named(block, "StockChip")
local bookChip = named(block, "BookChip")
check("the HUD: a \"📖 BOOK\" chip beside \"📦 N in stock\"", bookChip ~= nil and bookChip.Text == "📖 BOOK" and bookChip.ClassName == "TextButton" and stockChip ~= nil)

local function chipChecks(label)
	local s, b = box(stockChip), box(bookChip)
	check(`{label}: the BOOK chip right of the stock chip, on its row, as tall`, b.x0 >= s.x1 - 0.5 and math.abs(b.y0 - s.y0) < 0.5 and math.abs((b.y1 - b.y0) - (s.y1 - s.y0)) < 0.5, `{show(s)} {show(b)}`)
	check(`{label}: … inside the HUD's block`, within(b, box(block)), `{show(b)} in {show(box(block))}`)
	local clear, hit = true, nil
	for _, other in blocks() do
		if overlap(box(block), other) then
			clear, hit = false, show(other)
		end
	end
	check(`{label}: … the block still clear of the touch buttons, the thumbstick, the jump, the left column and the move's panel`, clear and inside(box(block)), `{show(box(block))} on {hit}`)
	check(`{label}: … the chips' texts fit`, #badTexts(block) == 0, badTexts(block)[1])
	if M.touch then
		check(`{label}: … a finger's size (44 px), no key chip`, b.x1 - b.x0 >= 44 - 0.01 and b.y1 - b.y0 >= 44 - 0.01 and not named(bookChip, "Key").Visible, show(b))
	else
		check(`{label}: … its key C shown`, named(bookChip, "Key").Visible and named(bookChip, "Key").Text == "C")
	end
end
chipChecks("844 x 390")
M.sceneToasts = { "📖 New in your book: Jukebox", "🏆 Found 10 pieces · +$250" }
scene("book-hud-phone")
M.sceneToasts = nil

-- ── The book on the phone ──────────────────────────────────────────────────
remote.OnClientEvent:Fire(state(FOUND, { "found10", "found20", "legendary" }))
M.flush()
check("a state alone opens nothing, no toast (nothing new)", not Book.isOpen() and Book.state() ~= nil and #M.toasts == 0)
press(bookChip)
local gui = M.gui:FindFirstChild("CollectionBookUi")
local window = gui and named(gui, "Book")
check("the BOOK chip opens it: \"📖 COLLECTION BOOK\" in its ScreenGui \"CollectionBookUi\"", Book.isOpen() and window ~= nil and gui.ClassName == "ScreenGui" and named(window, "Title").Text == "📖 COLLECTION BOOK")
check("… modal: its shade frees the mouse (Modal)", named(gui, "BookShade").Modal == true)

local function cardsOf()
	local list = {}
	local grid = named(named(gui, "Book"), "Grid")
	for _, child in grid:GetChildren() do
		if string.sub(child.Name, 1, 5) == "Card_" then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		if a.Position.Y.Offset ~= b.Position.Y.Offset then
			return a.Position.Y.Offset < b.Position.Y.Offset
		end
		return a.Position.X.Offset < b.Position.X.Offset
	end)
	return list
end
local function bookChecks(label)
	window = named(gui, "Book")
	local cardBox = box(window)
	check(`{label}: the book's card on the screen`, inside(cardBox), show(cardBox))
	check(`{label}: … its texts fit`, #badTexts(window) == 0, badTexts(window)[1])
	local side = named(window, "Side")
	local last = named(side, `Milestone_{Rules.Milestones[#Rules.Milestones].id}`)
	check(`{label}: … the left column (the progress, every milestone) inside the card`, within(box(side), cardBox) and within(box(last), cardBox) and within(box(named(side, "Progress")), cardBox), `{show(box(last))} in {show(cardBox)}`)
	local grid = named(window, "Grid")
	local cards = cardsOf()
	local gridBox = box(grid)
	check(`{label}: … the grid beside the column (never on it), its cards inside its width`, box(side).x1 <= gridBox.x0 and box(cards[1]).x0 >= gridBox.x0 - 0.5 and box(cards[#cards]).x1 <= gridBox.x1 + 0.5)
	check(`{label}: … the tabs over the grid, side by side, inside the card`, within(box(named(window, "Tab_furniture")), cardBox) and box(named(window, "Tab_all")).y1 <= gridBox.y0
		and box(named(window, "Tab_collectibles")).x0 >= box(named(window, "Tab_all")).x1 and box(named(window, "Tab_furniture")).x0 >= box(named(window, "Tab_collectibles")).x1)
	if M.touch then
		check(`{label}: … every button a finger's size (the tabs, ✕)`, #smallButtons(window) == 0, smallButtons(window)[1])
	end
end
bookChecks("844 x 390")
window = named(gui, "Book")
check("the progress: \"23 / 97 found\", its bar 23/97 full", named(window, "Progress").Text == "23 / 97 found" and math.abs(named(window, "Fill").Size.X.Scale - 23 / 97) < 1e-6, named(window, "Progress").Text)
check("… the counts: Furniture 20 / 73, Collectibles 3 / 24", named(window, "FurnitureCount").Text == "Furniture 20 / 73" and named(window, "CollectibleCount").Text == "Collectibles 3 / 24")
local rowFound10, rowFurniture = named(window, "Milestone_found10"), named(window, "Milestone_furniture")
check("the milestones: a paid one ✔ \"Paid · +$250\"", named(rowFound10, "Check").Text == "✔" and named(rowFound10, "Reward").Text == "Paid · +$250" and named(rowFound10, "MilestoneName").Text == "Found 10 pieces")
check("… an open one: how far and its reward (\"20 / 73 · +$2,000\": 8.3 economy)", named(rowFurniture, "Check").Text == "○" and named(rowFurniture, "Reward").Text == "20 / 73 · +$2,000", named(rowFurniture, "Reward").Text)
check("… every collectible: 3 / 24 · +$10,000; A legendary! ✔", named(named(window, "Milestone_collectibles24"), "Reward").Text == "3 / 24 · +$10,000" and named(named(window, "Milestone_legendary"), "Check").Text == "✔")
check("the tabs: ALL 23/97 (lit), COLLECTIBLES 3/24, FURNITURE 20/73", named(window, "Tab_all").Text == "ALL 23/97" and named(window, "Tab_collectibles").Text == "COLLECTIBLES 3/24" and named(window, "Tab_furniture").Text == "FURNITURE 20/73"
	and named(window, "Tab_all"):FindFirstChild("Underline") ~= nil and named(window, "Tab_furniture"):FindFirstChild("Underline") == nil)
local cards = cardsOf()
check("ALL: a card a piece of the book (97), in its order", #cards == 97 and cards[1].Name == `Card_{Rules.Pieces[1]}` and cards[97].Name == `Card_{Rules.Pieces[97]}`)
local first = cards[1]
local def1 = M.FurnitureLooks.Items[Rules.Pieces[1]]
local found1 = FOUND[Rules.Pieces[1]]
check("a found card: #1, its name, its rarity's word and colour, ×n, its best condition, its value", named(first, "Number").Text == "#1" and named(first, "PieceName").Text == def1.name
	and named(first, "Rarity").Text == string.upper(Config.Collection.Tiers[Rules.rarityOf(Rules.Pieces[1])].name) and named(first, "Count").Text == `×{found1.n}`
	and named(first, "Best").Text == `Best {math.floor(found1.best * 100 + 0.5)}%` and named(first, "Value").Text == M.MUi.money(def1.value) and first:GetAttribute("Found") == true)
local tier = Config.Collection.Tiers[Rules.rarityOf(Rules.Pieces[1])]
local bar = named(first, "RarityBar").BackgroundColor3
check("… its rarity bar in the tier's colour", math.abs(bar.R * 255 - tier.color[1]) < 0.6 and math.abs(bar.G * 255 - tier.color[2]) < 0.6)
local unknown = named(window, `Card_{Rules.Furniture[21]}`)
check("an unknown card: \"???\", NOT FOUND YET, no name, no value", named(unknown, "PieceName").Text == "???" and named(unknown, "Hint").Text == "NOT FOUND YET" and named(unknown, "Value") == nil and unknown:GetAttribute("Found") == false)
local legend = named(window, "Card_knight_armour")
check("a found legendary: LEGENDARY in gold, ×1, $5,500", named(legend, "Rarity").Text == "LEGENDARY" and named(legend, "Count").Text == "×1" and named(legend, "Value").Text == "$5,500")

-- the 3D pictures
local plan = Book.layout(M.width, M.height, M.touch)
local grid = named(window, "Grid")
local function withModel()
	local list = {}
	for index, made in cardsOf() do
		if named(made, "Model") ~= nil then
			table.insert(list, index)
		end
	end
	return list
end
local function onScreen(index)
	local top = grid.CanvasPosition.Y
	local line = (index - 1) // plan.cols
	local y0 = line * (plan.tileH + plan.gap)
	return y0 < top + plan.gridH and y0 + plan.tileH > top
end
local modelled = withModel()
local allOn = #modelled > 0
for _, index in modelled do
	allOn = allOn and onScreen(index)
end
check("3D pictures only on the cards on screen", allOn and #modelled == Book.views(), table.concat(modelled, ","))
check(`… never more than Config.CollectionBook.MaxViews ({Config.CollectionBook.MaxViews})`, Book.views() <= Config.CollectionBook.MaxViews)
local view1 = named(first, "Model")
check("… a found piece's: in its colours (no tint), its emoji kept for the fallback", view1 ~= nil and view1.ImageColor3.R == 1 and view1:GetAttribute("Silhouette") == false and view1:GetAttribute("Emoji") == def1.icon and not named(first, "Emoji").Visible)
grid.CanvasPosition = M.Vector2.new(0, 5 * (plan.tileH + plan.gap))
grid:GetPropertyChangedSignal("CanvasPosition"):Fire()
M.flush()
local scrolled = withModel()
local stillOn = #scrolled > 0
for _, index in scrolled do
	stillOn = stillOn and onScreen(index)
end
check("scrolled five rows down: the top cards gave theirs back, the cards on screen have theirs", stillOn and not table.find(scrolled, 1) and Book.views() <= Config.CollectionBook.MaxViews, table.concat(scrolled, ","))
local darkView = nil
for _, index in scrolled do
	local made = cardsOf()[index]
	if made:GetAttribute("Found") == false then
		darkView = named(made, "Model")
		break
	end
end
local sil = Config.CollectionBook.Silhouette
check("… an unknown piece's picture: its model tinted to the dark silhouette (Config.CollectionBook.Silhouette)", darkView ~= nil and darkView:GetAttribute("Silhouette") == true
	and math.abs(darkView.ImageColor3.R * 255 - sil[1]) < 0.6 and math.abs(darkView.ImageColor3.B * 255 - sil[3]) < 0.6)
local onceEach = true
for _, count in M.builds do
	onceEach = onceEach and count == 1
end
check("… each piece's model built once", onceEach)
remote.OnClientEvent:Fire(state(FOUND, { "found10", "found20", "legendary" }))
check("the same state again: not drawn again (its scroll and pictures stay)", named(gui, "Book") == window and grid.CanvasPosition.Y == 5 * (plan.tileH + plan.gap))
grid.CanvasPosition = M.Vector2.new(0, 0)
grid:GetPropertyChangedSignal("CanvasPosition"):Fire()
M.flush()
scene("book-phone")

-- the tabs
press(named(window, "Tab_collectibles"))
window = named(gui, "Book")
cards = cardsOf()
check("COLLECTIBLES: the 24 collectibles (3 found), the tab lit", #cards == 24 and cards[1].Name == `Card_{Rules.Collectibles[1]}` and named(window, "Tab_collectibles"):FindFirstChild("Underline") ~= nil)
bookChecks("844 x 390, COLLECTIBLES")
scene("book-phone-collectibles")
press(named(window, "Tab_furniture"))
cards = cardsOf()
check("FURNITURE: the 73 pieces of furniture", #cards == 73 and cards[1].Name == `Card_{Rules.Furniture[1]}`)
press(named(named(gui, "Book"), "Tab_all"))
check("ALL: every piece again", #cardsOf() == 97)

-- a discovery and a milestone while it is open
local more = table.clone(FOUND)
more.oil_painting = { n = 1, best = 0.8 }
remote.OnClientEvent:Fire(state(more, { "found10", "found20", "legendary" }, { "oil_painting" }))
M.flush()
check("a new piece: the toast \"📖 New in your book: Oil Painting\"", M.toasts[#M.toasts] == "📖 New in your book: Oil Painting", M.toasts[#M.toasts])
check("… the open book drawn again: 24 / 97, its card found", named(named(gui, "Book"), "Progress").Text == "24 / 97 found" and named(named(gui, "Book"), "Card_oil_painting"):GetAttribute("Found") == true)
more.ship_bottle = { n = 1, best = 0.5 }
more.old_globe = { n = 1, best = 0.5 }
more.bowling_trophy = { n = 1, best = 0.5 }
remote.OnClientEvent:Fire(state(more, { "found10", "found20", "legendary" }, { "ship_bottle", "old_globe", "bowling_trophy", "nope" }))
check("several new pieces: \"📖 3 new pieces in your book\" (an id not in the book ignored)", M.toasts[#M.toasts] == "📖 3 new pieces in your book", M.toasts[#M.toasts])
remote.OnClientEvent:Fire({ kind = "milestone", id = "furniture", name = "All the furniture", money = 2000 })
check("a milestone: the toast \"🏆 All the furniture · +$2,000\"", M.toasts[#M.toasts] == "🏆 All the furniture · +$2,000", M.toasts[#M.toasts])
check("… its ✔ at once in the open book", named(named(named(gui, "Book"), "Milestone_furniture"), "Check").Text == "✔")
local toastsBefore = #M.toasts
remote.OnClientEvent:Fire({ kind = "milestone", id = "nope", money = 1e9 })
remote.OnClientEvent:Fire("junk")
remote.OnClientEvent:Fire({ kind = "state", book = "x", paid = 5 })
check("garbage from the remote: no toast, no error (a junk state: an empty book)", #M.toasts == toastsBefore and named(named(gui, "Book"), "Progress").Text == "0 / 97 found")
-- 8.7 review: a piece only bought from another player (a legendary): shown, tagged, no find
local withBought = table.clone(FOUND)
withBought.oil_painting = { n = 1, best = 0.8, bought = true }
toastsBefore = #M.toasts
remote.OnClientEvent:Fire(state(withBought, { "found10", "found20", "legendary" }, { "oil_painting" }))
M.flush()
window = named(gui, "Book")
local boughtCard = named(window, "Card_oil_painting")
local boughtTag = boughtCard and named(boughtCard, "Bought")
check("8.7 review: a bought piece: its card with its name and a gold \"BOUGHT\" tag on its picture (Bought, not Found), its texts fitting", boughtCard ~= nil
	and named(boughtCard, "PieceName").Text == "Oil Painting" and boughtTag ~= nil and boughtTag.Text == "BOUGHT" and boughtTag.Parent == named(boughtCard, "Picture")
	and boughtCard:GetAttribute("Bought") == true and boughtCard:GetAttribute("Found") == false and #badTexts(boughtCard) == 0, boughtCard and badTexts(boughtCard)[1])
local sideHint = named(named(window, "Side"), "Hint")
check("… no find: still \"23 / 97 found\", COLLECTIBLES 3/24, no \"new\" toast; the side's hint (where there is room) says why", named(window, "Progress").Text == "23 / 97 found"
	and string.find(named(window, "Tab_collectibles").Text, " 3/24", 1, true) ~= nil and #M.toasts == toastsBefore
	and (sideHint == nil or sideHint.Text == "BOUGHT pieces show but don't count: bring one home to find it."), named(window, "Tab_collectibles").Text)
remote.OnClientEvent:Fire(state(FOUND, { "found10", "found20", "legendary" }))

-- closing
key("Escape")
check("ESC closes it", not Book.isOpen() and named(gui, "Book") == nil and Book.views() == 0)
key("C")
check("C opens it", Book.isOpen())
key("C")
check("C again closes it", not Book.isOpen())
key("C", true)
check("C taken by something else (gameProcessed): left alone", not Book.isOpen())
press(bookChip)
key("ButtonB")
check("the gamepad's B closes it", not Book.isOpen())
press(bookChip)
press(named(gui, "BookShade"))
check("a tap beside the card closes it", not Book.isOpen())
press(bookChip)
press(named(named(gui, "Book"), "Close"))
check("✕ closes it", not Book.isOpen())
press(bookChip)
M.services.GuiService.MenuOpened:Fire()
check("the Roblox menu opening closes it", not Book.isOpen())
press(bookChip)
press(bookChip)
check("the BOOK chip again closes it", not Book.isOpen())
M.remotes.Collection.OnClientEvent:Fire({ kind = "pick", stand = 2 })
check("(the warehouse's picker open)", WarehouseUi.isOpen())
key("C")
check("opening the book closes the warehouse's picker (one window at a time)", Book.isOpen() and not WarehouseUi.isOpen())
Book.close()

-- the start screen: C does nothing, the toasts wait
local ownGui = SandboxHud.gui()
M.hudGui.Enabled = false
M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
key("C")
check("the HUD hidden (the start screen): C does nothing", not ownGui.Enabled and not Book.isOpen())
toastsBefore = #M.toasts
remote.OnClientEvent:Fire({ kind = "milestone", id = "collectibles24", name = "Found every collectible", money = 10000 })
check("… a milestone's toast waits", #M.toasts == toastsBefore)
M.hudGui.Enabled = true
M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
ownGui:GetPropertyChangedSignal("Enabled"):Fire()
check("… and comes when the HUD shows", #M.toasts == toastsBefore + 1 and M.toasts[#M.toasts] == "🏆 Found every collectible · +$10,000", M.toasts[#M.toasts])
remote.OnClientEvent:Fire(state(FOUND, { "found10", "found20", "legendary" }))

-- ── A computer (1280 × 800) and a big screen (1920 × 1080) ─────────────────
for _, size in { { 1280, 764, "computer" }, { 1920, 1044, "big" } } do
	screen(false, size[1], size[2])
	local label = `{size[1]} x {size[2] + 36}`
	chipChecks(label)
	if size[3] == "computer" then
		scene("book-hud-computer")
	end
	press(bookChip)
	M.flush()
	bookChecks(label)
	local layout = Book.layout(M.width, M.height, false)
	check(`{label}: … centred, {layout.cols} cards across, two rows at least in view`, math.abs((layout.x + layout.w * layout.scale / 2) - M.width / 2) <= 1 and math.abs((layout.y + layout.h * layout.scale / 2) - M.height / 2) <= 1
		and layout.cols >= 4 and layout.gridH >= 2 * layout.tileH, `{layout.cols} {layout.gridH} {layout.tileH}`)
	check(`{label}: … the left column's hint where there is room`, named(named(gui, "Book"), "Hint") ~= nil)
	scene(`book-{size[3]}`)
	key("Escape")
end

-- ── A resize while it is open ───────────────────────────────────────────────
press(bookChip)
screen(true, 844, 354)
window = named(gui, "Book")
check("a resize to a phone while open: drawn again for it (a finger's buttons)", math.abs(M.uiScale(window) - Book.layout(844, 354, true).scale) < 0.001 and #smallButtons(window) == 0)
Book.close()
-- a smaller phone (667 × 375) and a tablet (1024 × 768)
for _, size in { { 667, 339 }, { 1024, 732 } } do
	screen(true, size[1], size[2])
	press(bookChip)
	bookChecks(`{size[1]} x {size[2] + 36}`)
	Book.close()
end

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
				local firstKey = true
				for k, v in value do
					if not firstKey then
						table.insert(out, ",")
					end
					firstKey = false
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
	print("ALL COLLECTION BOOK UI CHECKS PASSED")
end
