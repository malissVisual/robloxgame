-- 8.0 SANDBOX: the sandbox's HUD (client/SandboxHud.luau) and the warehouse picker (client/WarehouseUi.luau, with
-- client/CardKit.luau and the real shared data) run for real on sandbox_mock.luau's recorder, on a phone held sideways
-- (844 × 390: 844 × 354 under Roblox's top bar, the touch layout), a computer (1280 × 800) and a big screen (1920 × 1080):
-- nothing when Config.Sandbox.On is false; the money (big, money green, counted up) from the player's State
-- (SandboxHud.setState, as client/Main.client.luau passes it), "+$X/min"
-- only while pieces are on show, the "📦 N in stock" chip (the pieces not on show) opening the STOCK list, the key B
-- (and not when another thing took it), in a ScreenGui named "SandboxHud" (the guide's hint finds it) where
-- client/Hud.luau's left column starts (a spacer first in that column, followed: the chat, a resize); the toasts (a piece sold, pieces brought
-- home, none for the first state); "pick" opening THE PICKER for that stand (only the pieces not on show, the best
-- earners first, a tile's picture, rarity colour, condition, name, $/min and price), DISPLAY and SELL (asked first,
-- CANCEL, ESC) sending the right requests, the rarity chips, no redraw for the same state, the STOCK list (ON STAND n,
-- TAKE DOWN), the 3D pictures only on the tiles on screen and never more than Config.SandboxHud.MaxViews (each model built
-- once), scrolling; on each screen nothing of it on the touch buttons, the thumbstick, the jump button, what the HUD
-- still shows in the sandbox (the health row: the left column on touch, bottom left on a computer; MOUSE [ALT] and the
-- key hints at the top right; the toasts, which flow under it in Hud's column) or the move's panel, the texts fitting
-- their room and a phone's buttons a finger's size (44 px); a second
-- SandboxHud without client/Hud.luau (its own column and toasts). `luau sandbox.luau -a dump` prints the preview's scenes
-- as JSON instead (sandbox_preview.py).
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
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

-- Does a one-line text fit its label (after the scales above it, its padding, a key chip beside it)?
local function padding(object)
	for _, child in object:GetChildren() do
		if child.ClassName == "UIPadding" then
			return (child.PaddingLeft and child.PaddingLeft.Offset or 0), (child.PaddingRight and child.PaddingRight.Offset or 0)
		end
	end
	return 0, 0
end
local function textRoom(label)
	local b = box(label)
	local s = M.scaleOf(label)
	local left, right = padding(label)
	return (b.x1 - b.x0) - (left + right) * s, M.textWidth(label.Text, (label.TextSize or 14) * s, label.Font)
end
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		-- (a name may run long and is cut with "…"; a value or a price never)
		local truncated = object.TextTruncate and object.TextTruncate.Name == "AtEnd" and object.Name ~= "PerMinute" and object.Name ~= "SellPrice"
		if not object.TextWrapped and not truncated then
			local room, need = textRoom(object)
			if object.Name == "StockChip" then
				local keyLabel = named(object, "Key")
				if keyLabel and keyLabel.Visible then
					room -= (box(object).x1 - box(keyLabel).x0)
				end
			end
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
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false and o.Name ~= "WarehouseShade" and o.Name ~= "Confirm"
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end

-- ── The stock ───────────────────────────────────────────────────────────────
local STOCK = {
	{ uid = "a1", item = "grandfather_clock", variant = 1, condition = 0.87, name = "Grandpa's Clock", got = 1 },
	{ uid = "a2", item = "sofa", variant = 2, condition = 0.64, name = "Sofa", got = 2 },
	{ uid = "a3", item = "piano", variant = 1, condition = 0.71, name = "Upright Piano", got = 3 },
	{ uid = "a4", item = "gold_record", variant = 1, condition = 1, name = "Gold Record", got = 4, rarity = "legendary", perMinute = 60, sell = 2400 },
	{ uid = "a5", item = "painting", variant = 1, condition = 0.95, name = "Painting", got = 5, stand = 2 },
	{ uid = "a6", item = "floor_lamp", variant = 3, condition = 0.5, name = "Floor Lamp", got = 6 },
	{ uid = "a7", item = "record_player", variant = 1, condition = 0.92, name = "Old Record Player", got = 7, rarity = "epic", perMinute = 24, sell = 980 },
	{ uid = "a8", item = "armchair", variant = 1, condition = 0.8, name = "Armchair", got = 8 },
}
local function state(stock, income)
	return { kind = "state", stock = stock, income = income, stands = 6 }
end
local function more(count, from)
	local list = table.clone(STOCK)
	local items = { "bookshelf", "tv", "guitar", "cuckoo_clock", "accordion", "carved_chest", "beehive", "mirror", "radio", "toy_box" }
	for i = 1, count do
		table.insert(list, { uid = `b{from + i}`, item = items[(i - 1) % #items + 1], variant = 1 + (i % 3), condition = 0.4 + (i % 6) / 10, got = 100 + i })
	end
	return list
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
-- What the block must keep clear of: the touch buttons, the thumbstick's corner, the jump button, what the HUD still
-- shows in the sandbox (the health row: the left column on touch, bottom left on a computer; MOUSE [ALT] and the key
-- hints at the top right, about Roblox's player list's width and two rows) and the move's panel at the top in the middle.
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

-- ── The preview's scenes (sandbox_preview.py) ──────────────────────────────
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
	-- Hud's column: its slots one over the other (the block's height after its scale), the toasts under it
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
	if M.touch then
		local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
		table.insert(overlay, { kind = "round", box = cluster.fire, label = "FIRE" })
		table.insert(overlay, { kind = "pill", box = cluster.sprint, label = "SPRINT" })
		table.insert(overlay, { kind = "pill", box = cluster.act, label = "PUNCH" })
		table.insert(overlay, { kind = "pill", box = cluster.holster, label = "DRAW" })
		table.insert(overlay, { kind = "minimap", box = M.leftColumn })
	else
		-- what the HUD still shows on a computer: the health row bottom left, MOUSE [ALT] and the key hints top right
		local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		table.insert(overlay, { kind = "minimap", box = { x0 = 16, y0 = M.height - 16 - 30 * S, x1 = 16 + 200 * S, y1 = M.height - 16 } })
		table.insert(overlay, { kind = "text", box = { x0 = M.width - 16 - MoveLayout.PLAYER_LIST_W - 150, y0 = 4, x1 = M.width - 16 - MoveLayout.PLAYER_LIST_W, y1 = 30 }, label = "MOUSE [ALT]" })
		if M.chatOpen then
			table.insert(overlay, { kind = "chat", box = { x0 = 8, y0 = 0, x1 = 400, y1 = 200 }, label = "Roblox chat" })
		end
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── Off: nothing ────────────────────────────────────────────────────────────
local SandboxHud = require("./SandboxHud")
local WarehouseUi = require("./WarehouseUi")
screen(true, 844, 354)
Config.Sandbox.On = false
SandboxHud.start()
WarehouseUi.start()
check("Config.Sandbox.On false: SandboxHud.start() and WarehouseUi.start() do nothing", SandboxHud.block() == nil and M.remotes.Collection == nil and M.slotsMade == nil)
Config.Sandbox.On = true

-- ── The phone: the HUD ──────────────────────────────────────────────────────
SandboxHud.start()
local collection = M.remotes.Collection
local block = SandboxHud.block()
local slot = M.topStack:FindFirstChild("Slot_sandbox")
local spacer = slot and slot:FindFirstChild("SandboxSpace")
local ownGui = SandboxHud.gui()
check("on: the block in a ScreenGui named \"SandboxHud\" (the guide's hint finds it by that name)", block ~= nil and ownGui ~= nil and ownGui.ClassName == "ScreenGui" and ownGui.Name == "SandboxHud" and block.Parent == ownGui and ownGui.Parent == M.gui)
check("… its spacer first in client/Hud.luau's left column (its slot, LayoutOrder 0): the HUD's toasts flow under it", spacer ~= nil and slot.LayoutOrder == 0)
local function follows()
	local a, b = box(block), box(spacer)
	return math.abs(a.x0 - b.x0) < 1 and math.abs(a.y0 - b.y0) < 1 and math.abs(a.x1 - b.x1) < 1.5 and math.abs(a.y1 - b.y1) < 1.5, `{show(a)} / {show(b)}`
end
check("… WarehouseUi started with it: the Collection remote asked for the state", collection ~= nil and #sentOn("Collection") == 1 and sentOn("Collection")[1][1].kind == "state")
SandboxHud.setState({ money = 12480, level = 4 })
M.flush()
local moneyLabel = named(block, "Money")
check("… the block where the spacer is, as big (in the column's place and scale)", follows())
check("the money from the player's State (SandboxHud.setState), counted up (Juice.countMoney)", moneyLabel.Text == "$12,480" and M.counted[#M.counted] == 12480, moneyLabel.Text)
SandboxHud.setState(nil)
SandboxHud.setState({})
check("… a State without money changes nothing", moneyLabel.Text == "$12,480")
check("… big, in the money green", moneyLabel.TextSize >= 30 and moneyLabel.TextColor3 == require("./CardKit").Color.money)
local incomeLabel = named(block, "Income")
collection.OnClientEvent:Fire(state(STOCK, 0))
M.flush()
check("no pieces on show earning: no +$/min line", not incomeLabel.Visible)
check("the first state: no toast", #M.toasts == 0)
collection.OnClientEvent:Fire(state(STOCK, 36))
M.flush()
check("pieces on show: \"+$36/min\" in green under the money", incomeLabel.Visible and incomeLabel.Text == "+$36/min" and incomeLabel.TextColor3 == M.MTheme.Contract.good, incomeLabel.Text)
local chip = named(block, "StockChip")
check("the chip: \"📦 7 in stock\" (the pieces not on show)", chip.Text == "📦 7 in stock", chip.Text)
check("… no key chip on a touch screen", not named(chip, "Key").Visible)

local function hudChecks(label)
	check(`{label}: the block where client/Hud.luau's column starts (its spacer: place and size)`, follows())
	local all0 = box(block)
	local b = { x0 = all0.x0, y0 = all0.y0, x1 = all0.x1, y1 = all0.y1 }
	local clear = true
	local hit = nil
	for _, other in blocks() do
		if overlap(b, other) then
			clear, hit = false, show(other)
		end
	end
	check(`{label}: the block on the screen at the top left{if M.chatOpen then " (under the chat)" else ""}`, inside(b) and b.x0 < M.width * 0.35 and b.y0 < (if M.chatOpen then 216 else 60), show(b))
	check(`{label}: … clear of the touch buttons, the thumbstick, the jump, the left column and the move's panel`, clear, `{show(b)} on {hit}`)
	local moneyBox = box(moneyLabel)
	check(`{label}: … the money big on this screen (24 px and more)`, moneyLabel.TextSize * M.scaleOf(moneyLabel) >= 24, moneyLabel.TextSize * M.scaleOf(moneyLabel))
	check(`{label}: … its texts fit`, #badTexts(block) == 0, badTexts(block)[1])
	local chipBox = box(chip)
	if M.touch then
		check(`{label}: … the stock chip a finger's size (44 px)`, chipBox.x1 - chipBox.x0 >= 44 - 0.01 and chipBox.y1 - chipBox.y0 >= 44 - 0.01, show(chipBox))
	end
	check(`{label}: … the money's card over the chip`, moneyBox.y1 <= chipBox.y0 + 0.5)
end
hudChecks("844 x 390")

-- ── Toasts ──────────────────────────────────────────────────────────────────
collection.OnClientEvent:Fire(state(more(5, 0), 36))
M.flush()
check("the stock grew by 5: \"+5 pieces in your warehouse\" (Hud.toast)", M.toasts[#M.toasts] == "+5 pieces in your warehouse", M.toasts[#M.toasts])
check("… the chip counts them", chip.Text == "📦 12 in stock", chip.Text)
collection.OnClientEvent:Fire({ kind = "sold", name = "Grandpa's Clock", money = 420 })
M.flush()
check("a piece sold: \"Sold Grandpa's Clock · +$420\"", M.toasts[#M.toasts] == "Sold Grandpa's Clock · +$420", M.toasts[#M.toasts])
local toastsBefore = #M.toasts
collection.OnClientEvent:Fire(state(STOCK, 36))
collection.OnClientEvent:Fire(state(more(1, 50), 36))
M.flush()
check("fewer pieces: no toast; one more: \"+1 piece in your warehouse\"", #M.toasts == toastsBefore + 1 and M.toasts[#M.toasts] == "+1 piece in your warehouse", M.toasts[#M.toasts])
collection.OnClientEvent:Fire(state(STOCK, 36))
M.flush()
M.sceneToasts = { "Sold Grandpa's Clock · +$420", "+5 pieces in your warehouse" }
scene("phone-hud")
M.sceneToasts = nil

-- ── The picker ──────────────────────────────────────────────────────────────
local gui = M.gui:FindFirstChild("WarehouseUi")
check("before \"pick\": no picker", gui == nil or #gui:GetChildren() == 0)
collection.OnClientEvent:Fire({ kind = "pick", stand = 3 })
M.flush()
gui = M.gui:FindFirstChild("WarehouseUi")
local picker = named(gui, "Picker")
check("\"pick\" stand 3 opens the picker: STAND 3 · CHOOSE A PIECE", WarehouseUi.showing() == "picker" and picker ~= nil and named(picker, "Title").Text == "STAND 3 · CHOOSE A PIECE")
local grid = named(picker, "Grid")
local function tilesOf()
	local list = {}
	for _, child in grid:GetChildren() do
		if string.sub(child.Name, 1, 5) == "Tile_" then
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
local tiles = tilesOf()
check("… a tile for each piece not on show (7; the painting on stand 2 is not offered)", #tiles == 7 and named(grid, "Tile_a5") == nil, #tiles)
local rates = {}
local sorted = true
for index, tile in tiles do
	local rate = tonumber((string.gsub(named(tile, "PerMinute").Text, "[^%d]", "")))
	rates[index] = rate
	if index > 1 and rate > rates[index - 1] then
		sorted = false
	end
end
check("… the best earners first ($/min, highest first): the Gold Record (+$60/min) leads", sorted and tiles[1].Name == "Tile_a4" and named(tiles[1], "PerMinute").Text == "+$60/min", table.concat(rates, ","))
local gold = tiles[1]
check("a tile: the piece's picture (its emoji or its 3D model), its name", named(gold, "Picture") ~= nil and named(gold, "Emoji") ~= nil and named(gold, "PieceName").Text == "Gold Record")
check("… its rarity's colour bar and word (legendary gold)", named(gold, "RarityBar").BackgroundColor3 == WarehouseUi.Rarity.legendary and named(gold, "Rarity").Text == "LEGENDARY")
check("… its condition and its price", named(gold, "Condition").Text == "100%" and named(gold, "SellPrice").Text == "Sell $2,400", named(gold, "SellPrice").Text)
local clock = named(grid, "Tile_a1")
local clockValues = WarehouseUi.values(STOCK[1])
check("the clock's tile: 87%, its values (WarehouseUi.values)", named(clock, "Condition").Text == "87%" and named(clock, "PerMinute").Text == `+{M.MUi.money(clockValues.perMinute)}/min` and named(clock, "SellPrice").Text == `Sell {M.MUi.money(clockValues.sell)}`)
check("… its rarity colour (WarehouseUi.Rarity)", named(clock, "RarityBar").BackgroundColor3 == WarehouseUi.Rarity[clockValues.rarity])
check("… DISPLAY and SELL", named(clock, "Display") ~= nil and named(clock, "Sell") ~= nil and named(clock, "Display").Text == "DISPLAY" and named(clock, "Sell").Text == "SELL")

local function pickerChecks(label)
	picker = named(gui, "Picker")
	local cardBox = box(picker)
	check(`{label}: the picker's card on the screen`, inside(cardBox), show(cardBox))
	check(`{label}: … its texts fit`, #badTexts(picker) == 0, badTexts(picker)[1])
	if M.touch then
		check(`{label}: … every button a finger's size (DISPLAY, SELL, ✕, the chips)`, #smallButtons(picker) == 0, smallButtons(picker)[1])
	end
	local first = tilesOf()[1]
	if first then
		local tileBox, gridBox = box(first), box(named(picker, "Grid"))
		check(`{label}: … the tiles inside the grid's width`, tileBox.x0 >= gridBox.x0 - 0.5 and box(tilesOf()[#tilesOf()]).x1 <= gridBox.x1 + 0.5)
	end
end
pickerChecks("844 x 390")
check("… the 3D pictures: on the tiles on screen only", WarehouseUi.views() > 0 and WarehouseUi.views() <= Config.SandboxHud.MaxViews, WarehouseUi.views())
scene("phone-picker")

-- DISPLAY
press(named(clock, "Display"))
local sent = sentOn("Collection")
check("DISPLAY sends { kind = \"display\", uid, stand = 3 } and closes the picker", sent[#sent][1].kind == "display" and sent[#sent][1].uid == "a1" and sent[#sent][1].stand == 3 and not WarehouseUi.isOpen())
check("… its pictures given back", WarehouseUi.views() == 0)

-- SELL: asked first
collection.OnClientEvent:Fire({ kind = "pick", stand = 3 })
picker = named(gui, "Picker")
grid = named(picker, "Grid")
local sofa = named(grid, "Tile_a2")
local before = #sentOn("Collection")
press(named(sofa, "Sell"))
local confirm = named(picker, "Confirm")
local sofaValues = WarehouseUi.values(STOCK[2])
check("SELL asks first: \"SELL FOR $Y?\" (nothing sent)", confirm ~= nil and named(confirm, "Question").Text == `SELL FOR {M.MUi.money(sofaValues.sell)}?` and #sentOn("Collection") == before)
check("… the question's texts fit, its buttons a finger's size", #badTexts(confirm) == 0 and #smallButtons(named(confirm, "ConfirmBox")) == 0, badTexts(confirm)[1] or smallButtons(named(confirm, "ConfirmBox"))[1])
scene("phone-confirm")
press(named(confirm, "Cancel"))
check("… CANCEL: nothing sent, the picker stays", named(picker, "Confirm") == nil and WarehouseUi.isOpen() and #sentOn("Collection") == before)
press(named(sofa, "Sell"))
key("Escape")
check("… ESC closes the question first", named(picker, "Confirm") == nil and WarehouseUi.isOpen())
press(named(sofa, "Sell"))
press(named(named(picker, "Confirm"), "ConfirmSell"))
sent = sentOn("Collection")
check("… SELL: { kind = \"sell\", uid }", #sent == before + 1 and sent[#sent][1].kind == "sell" and sent[#sent][1].uid == "a2")
check("… the tile waits (…)", named(sofa, "Sell").Text == "…")
press(named(sofa, "Sell"))
check("… a second tap sends nothing more", #sentOn("Collection") == before + 1)

-- the rarity chips
local chips = named(picker, "Filter_all")
check("the rarity chips: ALL with the count", chips ~= nil and chips.Text == "ALL 7", chips and chips.Text)
local legendary = named(picker, "Filter_legendary")
press(legendary)
picker = named(gui, "Picker")
grid = named(picker, "Grid")
local legendaries = 0
for _, entry in STOCK do
	if not entry.stand and WarehouseUi.values(entry).rarity == "legendary" then
		legendaries += 1
	end
end
local onlyThem = #tilesOf() == legendaries and legendaries >= 1
for _, tile in tilesOf() do
	onlyThem = onlyThem and named(tile, "Rarity").Text == "LEGENDARY"
end
check("LEGENDARY: only the legendary pieces (the chip lit)", onlyThem and named(picker, "Filter_legendary"):FindFirstChild("Underline") ~= nil, #tilesOf())
press(named(picker, "Filter_all"))
picker = named(gui, "Picker")
grid = named(picker, "Grid")
check("ALL: every piece again", #tilesOf() == 7)

-- the same state: no redraw
collection.OnClientEvent:Fire(state(STOCK, 36))
check("the same state again: the picker is not drawn again (a tap is never lost)", named(gui, "Picker") == picker)
local changed = table.clone(STOCK)
table.remove(changed, 2)
collection.OnClientEvent:Fire(state(changed, 36))
check("the sofa sold (a new state): drawn again without it", named(gui, "Picker") ~= picker and named(named(gui, "Picker"), "Tile_a2") == nil)
M.services.GuiService.MenuOpened:Fire()
check("the Roblox menu opening closes it", not WarehouseUi.isOpen() and named(gui, "Picker") == nil)

-- ── The STOCK list ──────────────────────────────────────────────────────────
collection.OnClientEvent:Fire(state(STOCK, 36))
press(chip)
picker = named(gui, "Picker")
grid = named(picker, "Grid")
check("the stock chip opens the STOCK list: YOUR STOCK, every piece", WarehouseUi.showing() == "stock" and named(picker, "Title").Text == "YOUR STOCK" and #tilesOf() == 8)
local painting = named(grid, "Tile_a5")
check("… a piece on show marked ON STAND 2, with TAKE DOWN and SELL", named(painting, "OnStand").Text == "ON STAND 2" and named(painting, "TakeDown") ~= nil and named(painting, "Sell") ~= nil and named(painting, "Display") == nil)
check("… the others: SELL only", named(named(grid, "Tile_a1"), "Display") == nil and named(named(grid, "Tile_a1"), "Sell") ~= nil)
check("… its subtitle: 8 pieces · 1 on show · +$36/min", named(picker, "Subtitle").Text == "8 pieces · 1 on show · +$36/min", named(picker, "Subtitle").Text)
pickerChecks("844 x 390, the STOCK list")
scene("phone-stock")
press(named(painting, "TakeDown"))
sent = sentOn("Collection")
check("TAKE DOWN: { kind = \"undisplay\", uid }", sent[#sent][1].kind == "undisplay" and sent[#sent][1].uid == "a5")
press(named(picker, "Close"))
check("✕ closes it", not WarehouseUi.isOpen())

-- the key B
key("B")
check("B opens the STOCK list", WarehouseUi.showing() == "stock")
key("B")
check("B again closes it", not WarehouseUi.isOpen())
key("B", true)
check("B taken by something else (gameProcessed): left alone", not WarehouseUi.isOpen())
M.hudGui.Enabled = false
M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
key("B")
check("the HUD hidden (the start screen): the block hidden with it, B does nothing", not ownGui.Enabled and not WarehouseUi.isOpen())
M.hudGui.Enabled = true
M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
check("… shown again with the HUD", ownGui.Enabled)

-- ── The 3D pictures: only on screen, capped ─────────────────────────────────
for key2 in M.builds do
	M.builds[key2] = nil
end
collection.OnClientEvent:Fire(state(more(40, 200), 36))
WarehouseUi.openStock()
picker = named(gui, "Picker")
grid = named(picker, "Grid")
local plan = WarehouseUi.layout(M.width, M.height, M.touch)
local function withModel()
	local list = {}
	for index, tile in tilesOf() do
		if named(tile, "Model") ~= nil then
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
local allOnScreen = #modelled > 0
for _, index in modelled do
	allOnScreen = allOnScreen and onScreen(index)
end
check("48 pieces: 3D pictures only on the tiles on screen", allOnScreen and #modelled == WarehouseUi.views(), table.concat(modelled, ","))
check(`… never more than Config.SandboxHud.MaxViews ({Config.SandboxHud.MaxViews})`, WarehouseUi.views() <= Config.SandboxHud.MaxViews and #grid:GetChildren() > Config.SandboxHud.MaxViews)
local onceEach = true
for _, count in M.builds do
	onceEach = onceEach and count == 1
end
check("… each piece's model built once (a piece and variant)", onceEach)
local emojiShown = true
for index, tile in tilesOf() do
	local hasModel = named(tile, "Model") ~= nil
	emojiShown = emojiShown and (named(tile, "Emoji").Visible == not hasModel)
	if index > 30 then
		break
	end
end
check("… the others show the piece's emoji", emojiShown)
check("… a picture's model is inert (its SurfaceGui stripped)", #all(grid, function(o)
	return o.ClassName == "SurfaceGui"
end) == 0)
grid.CanvasPosition = M.Vector2.new(0, 3 * (plan.tileH + plan.gap))
grid:GetPropertyChangedSignal("CanvasPosition"):Fire()
M.flush()
local scrolled = withModel()
local stillOnScreen = #scrolled > 0
for _, index in scrolled do
	stillOnScreen = stillOnScreen and onScreen(index)
end
check("scrolled three rows down: the top tiles gave theirs back, the tiles on screen have theirs", stillOnScreen and not table.find(scrolled, 1) and WarehouseUi.views() <= Config.SandboxHud.MaxViews, table.concat(scrolled, ","))
local rebuilt = false
for _, count in M.builds do
	rebuilt = rebuilt or count > 1
end
check("… no model built twice", not rebuilt)
collection.OnClientEvent:Fire(state(more(40, 200), 50))
check("a new state for an open list: its scroll kept", named(named(gui, "Picker"), "Grid").CanvasPosition.Y == 3 * (plan.tileH + plan.gap))
WarehouseUi.close()
check("closed: every picture given back", WarehouseUi.views() == 0)
collection.OnClientEvent:Fire(state(STOCK, 36))

-- ── The values ──────────────────────────────────────────────────────────────
local served = WarehouseUi.values(STOCK[4])
check("the server's values in an entry come first (rarity, perMinute, sell)", served.rarity == "legendary" and served.perMinute == 60 and served.sell == 2400)
local kept = WarehouseUi.Rules
WarehouseUi.Rules = {
	rarity = function(entry)
		return if entry.item == "sofa" then "Epic" else nil
	end,
	incomePerMinute = function(entry)
		return if type(entry) == "table" then 17 else nil
	end,
	sellPrice = function(item, condition)
		return if type(item) == "string" then math.floor(1000 * condition) else nil
	end,
}
local asked = WarehouseUi.values(STOCK[2])
check("else shared/CollectionRules.luau's (with the entry, or with item and condition)", asked.rarity == "epic" and asked.perMinute == 17 and asked.sell == 640, `{asked.rarity} {asked.perMinute} {asked.sell}`)
WarehouseUi.Rules = nil
local guessed = WarehouseUi.values(STOCK[2])
check("else Config.SandboxHud.Fallback's guess from the catalogue (the sofa)", guessed.sell > 0 and guessed.perMinute >= 1 and WarehouseUi.Rarity[guessed.rarity] ~= nil)
WarehouseUi.Rules = kept
if M.rulesFound then
	check("shared/CollectionRules.luau is there: found by WarehouseUi.start()", WarehouseUi.Rules ~= nil)
end

-- ── A computer (1280 × 800) and a big screen (1920 × 1080) ─────────────────
for _, size in { { 1280, 764, "computer" }, { 1920, 1044, "big" }, { 1280, 764, "chat" } } do
	M.chatOpen = size[3] == "chat"
	screen(false, size[1], size[2])
	local label = `{size[1]} x {size[2] + 36}{if M.chatOpen then " (the chat open: Hud's column under it)" else ""}`
	check(`{label}: the key chip shows (B)`, named(chip, "Key").Visible and named(chip, "Key").Text == "B")
	hudChecks(label)
	collection.OnClientEvent:Fire(state(STOCK, 36))
	M.sceneToasts = { "+3 pieces in your warehouse" }
	scene(`{size[3]}-hud`)
	M.sceneToasts = nil
	collection.OnClientEvent:Fire({ kind = "pick", stand = 3 })
	pickerChecks(label)
	local plan2 = WarehouseUi.layout(M.width, M.height, false)
	check(`{label}: … the grid {plan2.cols} across, two rows at least in view`, plan2.cols >= 4 and plan2.gridH >= 2 * plan2.tileH, `{plan2.cols} {plan2.gridH} {plan2.tileH}`)
	scene(`{size[3]}-picker`)
	WarehouseUi.openStock()
	pickerChecks(`{label}, the STOCK list`)
	scene(`{size[3]}-stock`)
	key("Escape")
	check(`{label}: ESC closes it`, not WarehouseUi.isOpen())
end
M.chatOpen = false

-- ── A resize while it is open ───────────────────────────────────────────────
WarehouseUi.openStock()
screen(true, 844, 354)
picker = named(gui, "Picker")
check("a resize to a phone while open: drawn again for it (a finger's buttons)", math.abs(M.uiScale(picker) - WarehouseUi.layout(844, 354, true).scale) < 0.001 and #smallButtons(picker) == 0)
WarehouseUi.close()

-- ── Without client/Hud.luau: its own column and toasts ─────────────────────
local Alone = require("./SandboxHudAlone")
Alone.start()
local own = Alone.gui()
local aloneBlock = Alone.block()
check("no client/Hud.luau: its ScreenGui \"SandboxHud\", the block at the top left", own ~= nil and own.Name == "SandboxHud" and aloneBlock ~= nil and aloneBlock.Parent == own and inside(box(aloneBlock)) and box(aloneBlock).x0 < 40 and box(aloneBlock).y0 < 40)
Alone.toast("Sold Old TV · +$150")
local toasts = own:FindFirstChild("Toasts")
local strip = toasts and toasts:FindFirstChild("Toast")
check("… its own toast under the block", strip ~= nil and box(toasts).y0 >= box(aloneBlock).y1 and named(strip, "Text").Text == "Sold Old TV · +$150")
for i = 1, 4 do
	Alone.toast(`toast {i}`)
end
local count = 0
for _, child in toasts:GetChildren() do
	if child.Name == "Toast" and child.Parent then
		count += 1
	end
end
check(`… never more than Config.SandboxHud.MaxToasts ({Config.SandboxHud.MaxToasts})`, count <= Config.SandboxHud.MaxToasts, count)
M.flush()
M.flush()
local left = 0
for _, child in toasts:GetChildren() do
	if child.Name == "Toast" then
		left += 1
	end
end
check("… and they go", left == 0, left)
check("… the phone: its chip a finger's size, clear of the touch buttons", box(named(aloneBlock, "StockChip")).y1 - box(named(aloneBlock, "StockChip")).y0 >= 44 - 0.01 and not overlap(box(aloneBlock), TouchLayout.cluster(844, 354, M.MUi.scaleFor(M.Vector2.new(844, 354))).thumb))

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
	print("ALL SANDBOX UI CHECKS PASSED")
end
