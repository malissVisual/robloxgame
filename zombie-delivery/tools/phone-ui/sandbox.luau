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
-- 8.2 (the warehouse's quality of life): the STOCK list's header buttons (⭐ FILL BEST, 💰 SELL…, ↩ TAKE ALL DOWN) on each
-- screen: inside the card, clear of the title, the ✕, the chips and the grid, a finger's size on a phone; their requests
-- (fillbest, undisplayall, a double tap one request), grey with nothing to do (a tap says why, nothing sent); SELL…'s menu
-- (each filter's count and price as shared/StockPlan.luau picks them, its texts fitting, asked first: CANCEL sends
-- nothing, SELL only { kind = "sellmany", filter }); the server's bulk and sold answers as toasts; the sort toggle
-- ($/MIN → VALUE → NEWEST → RARITY, kept for the picker); the search box on a computer only (every word, any case, the
-- card and the box not drawn again while typing, 40 letters at most, cleared with the window); THE PICKER at a small
-- upgrade stand (the bed, the hay wagon and the wheelbarrow greyed with "Too big for this stand" and TOO BIG, last;
-- TOO BIG sends nothing and says where it goes) and at a big one (nothing greyed).
-- 8.3 (the market, shared/Market.luau): on each screen the STOCK list's and the picker's line "Today's market: 🔥 … ·
-- ❄ … · new in 5 h" (whole, clear of the header's buttons, the chips and the grid), the tags on the pieces' pictures
-- (🔥 HOT ×1.6, ❄ COLD, 📉 −10%; under ON STAND n), the prices the server's (the market's); SELL's question says why
-- (the demand's line, hot, cold) and sends the price it showed (expect), SELL…'s totals one piece after the other with
-- the demand's hint and the total sent (expect), never a guessed price; the HUD's "🔥 Hot today: …" toast once a day,
-- held back while the HUD is hidden.
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
local WarehouseLayout = require("./WarehouseLayout")
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
	if p.ClassName == "TextBox" and (p.Text == nil or p.Text == "") and p.PlaceholderText then
		-- 8.2: an empty search box shows its placeholder
		out.text, out.ts = p.PlaceholderText, p.TextSize
		out.tc = color(p.PlaceholderColor3 or p.TextColor3)
		out.xa = if p.TextXAlignment then p.TextXAlignment.Name else nil
		out.font = if p.Font then p.Font.Name else nil
	elseif p.Text and p.Text ~= "" then
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
	local rate = tonumber((string.gsub(string.match(named(tile, "PerMinute").Text, "%$([%d,%.]+)") or "", ",", ""))) -- (8.0.1: "+$0.2/min" too)
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
check("the clock's tile: 87%, its values (WarehouseUi.values)", named(clock, "Condition").Text == "87%" and named(clock, "PerMinute").Text == `+{WarehouseLayout.money(clockValues.perMinute)}/min` and named(clock, "SellPrice").Text == `Sell {M.MUi.money(clockValues.sell)}`)
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

-- ── 8.0.1: cheap pieces (under $1 a minute) ─────────────────────────────────
-- Their $/min to a tenth, as the stands' tags write it (shared/WarehouseLayout.luau's money): never "+$0/min" for a
-- piece that earns, and the best earners sorted on the exact numbers (rounded to whole dollars the radio's $0.44 and
-- the mirror's $0.2 tied, and the uncommon mirror went first).
local CHEAP = {
	{ uid = "c1", item = "mirror", variant = 1, condition = 0.9, name = "Brass Mirror", got = 11, rarity = "uncommon", perMinute = 0.2, sell = 30 },
	{ uid = "c2", item = "radio", variant = 1, condition = 0.6, name = "Old Radio", got = 12, rarity = "common", perMinute = 0.44, sell = 12 },
	{ uid = "c3", item = "toy_box", variant = 1, condition = 0.3, name = "Toy Box", got = 13, rarity = "common", perMinute = 0.06, sell = 3 },
	{ uid = "c4", item = "tv", variant = 1, condition = 1, name = "Old TV", got = 14, rarity = "rare", perMinute = 1, sell = 90, stand = 1 },
}
collection.OnClientEvent:Fire(state(CHEAP, 1))
collection.OnClientEvent:Fire({ kind = "pick", stand = 4 })
M.flush()
picker = named(gui, "Picker")
grid = named(picker, "Grid")
local cheap = tilesOf()
local cheapRates = {}
for index, tile in cheap do
	cheapRates[index] = `{tile.Name} {named(tile, "PerMinute").Text}`
end
check("8.0.1: cheap pieces' $/min to a tenth, as the stands' tags: +$0.4/min, +$0.2/min, +$0.1/min (never +$0/min)", #cheap == 3
	and named(cheap[1], "PerMinute").Text == "+$0.4/min" and named(cheap[2], "PerMinute").Text == "+$0.2/min" and named(cheap[3], "PerMinute").Text == "+$0.1/min", table.concat(cheapRates, ", "))
check("… sorted on the exact numbers: the radio's $0.44 before the (uncommon) mirror's $0.2", cheap[1].Name == "Tile_c2" and cheap[2].Name == "Tile_c1" and cheap[3].Name == "Tile_c3", table.concat(cheapRates, ", "))
check("… WarehouseUi.values keeps the exact $/min, WarehouseUi.rate writes it", WarehouseUi.values(CHEAP[1]).perMinute == 0.2 and WarehouseUi.rate(0.2) == "+$0.2/min" and WarehouseUi.rate(36) == "+$36/min" and WarehouseUi.rate(1234.4) == "+$1,234/min")
check("… its texts fit", #badTexts(picker) == 0, badTexts(picker)[1])
press(named(cheap[2], "Sell"))
local cheapHint = named(named(picker, "Confirm"), "Hint")
check("… SELL's question: \"On show it would earn +$0.2/min.\"", cheapHint ~= nil and cheapHint.Text == "On show it would earn +$0.2/min.", cheapHint and cheapHint.Text)
key("Escape")
key("Escape")
check("… ESC twice: the question, then the picker", not WarehouseUi.isOpen())
collection.OnClientEvent:Fire(state(CHEAP, 0.64))
M.flush()
check("… the HUD's line: \"+$0.6/min\" (not +$0/min)", incomeLabel.Visible and incomeLabel.Text == "+$0.6/min", incomeLabel.Text)
WarehouseUi.openStock()
check("… the STOCK list's subtitle: 4 pieces · 1 on show · +$0.6/min", named(named(gui, "Picker"), "Subtitle").Text == "4 pieces · 1 on show · +$0.6/min", named(named(gui, "Picker"), "Subtitle").Text)
WarehouseUi.close()
collection.OnClientEvent:Fire(state(STOCK, 36))
M.flush()

-- ── 8.2: the warehouse's quality of life ────────────────────────────────────
local StockPlan = require("./StockPlan")
local function withStands(stock, income, stands)
	return { kind = "state", stock = stock, income = income, stands = stands }
end
-- (the pieces as the window hands them to shared/StockPlan.luau: its values, broken from the condition)
local function piecesFor(stock)
	local list = {}
	for _, entry in stock do
		local v = WarehouseUi.values(entry)
		local condition = entry.condition or 1
		table.insert(list, { uid = entry.uid, item = entry.item, stand = entry.stand, got = entry.got or 0, rarity = v.rarity, income = v.perMinute, price = v.sell, broken = if entry.broken ~= nil then entry.broken else condition <= Config.Collection.BrokenAt + 1e-6, condition = condition })
	end
	return list
end
local function within(inner, outer)
	return inner.x0 >= outer.x0 - 0.5 and inner.y0 >= outer.y0 - 0.5 and inner.x1 <= outer.x1 + 0.5 and inner.y1 <= outer.y1 + 0.5
end
-- The STOCK list's header buttons: there, inside the card, clear of each other, the title, its line, the ✕, the chips
-- (the sort toggle, the search box) and the grid.
local function headerChecks(label)
	picker = named(gui, "Picker")
	local buttons = { named(picker, "FillBest"), named(picker, "SellMenu"), named(picker, "TakeAllDown") }
	check(`{label}: the STOCK list's header: ⭐ FILL BEST, 💰 SELL…, ↩ TAKE ALL DOWN`, buttons[1] ~= nil and buttons[2] ~= nil and buttons[3] ~= nil
		and string.find(buttons[1].Text, "BEST", 1, true) ~= nil and string.find(buttons[2].Text, "SELL", 1, true) ~= nil and string.find(buttons[3].Text, "DOWN", 1, true) ~= nil)
	local cardBox = box(picker)
	local others = { named(picker, "Title"), named(picker, "Subtitle"), named(picker, "Close"), named(picker, "Grid"), named(picker, "Sort"), named(picker, "Filter_all") }
	if named(picker, "Search") then
		table.insert(others, named(picker, "Search"))
	end
	local clear, hit = true, nil
	for i, button in buttons do
		local b = box(button)
		if not within(b, cardBox) then
			clear, hit = false, `{button.Name} outside the card`
		end
		for _, other in others do
			if overlap(b, box(other)) then
				clear, hit = false, `{button.Name} on {other.Name}`
			end
		end
		for j = i + 1, #buttons do
			if overlap(b, box(buttons[j])) then
				clear, hit = false, `{button.Name} on {buttons[j].Name}`
			end
		end
	end
	check(`{label}: … inside the card, clear of the title, its line, the ✕, the chips, the sort toggle and the grid`, clear, hit)
	local sortBox, chipBox = box(named(picker, "Sort")), box(named(picker, "Filter_all"))
	check(`{label}: … the sort toggle on the chips' row at its right, inside the card`, within(sortBox, cardBox) and math.abs(sortBox.y0 - chipBox.y0) < 1 and sortBox.x0 > chipBox.x1)
end

-- the phone: the STOCK list with pieces of every kind to sell
local SELLS = table.clone(STOCK)
for _, extra in {
	{ uid = "d1", item = "dining_chair", variant = 1, condition = 0.9, name = "Chair", got = 20 },
	{ uid = "d2", item = "dining_chair", variant = 2, condition = 0.7, name = "Chair", got = 21 },
	{ uid = "d3", item = "tv", variant = 1, condition = 0.05, name = "Old TV", got = 22, broken = true },
	{ uid = "d4", item = "box", variant = 1, condition = 1, name = "Moving Box", got = 23 },
} do
	table.insert(SELLS, extra)
end
collection.OnClientEvent:Fire(withStands(SELLS, 36, 6))
WarehouseUi.openStock()
picker = named(gui, "Picker")
check("8.2, the STOCK list (844 x 390): drawn with the header buttons", WarehouseUi.showing() == "stock" and named(picker, "FillBest") ~= nil)
headerChecks("844 x 390")
pickerChecks("844 x 390, the STOCK list with its header (8.2)")
check("… no search box on a touch screen", named(picker, "Search") == nil)
check("… FILL BEST green (free stands, pieces that earn), SELL… and TAKE ALL DOWN quiet: all live", named(picker, "FillBest"):GetAttribute("Live") == true and named(picker, "SellMenu"):GetAttribute("Live") == true and named(picker, "TakeAllDown"):GetAttribute("Live") == true
	and named(picker, "FillBest").BackgroundColor3 == require("./CardKit").Buttons.good.face)
scene("phone-stock-tools")

-- 💰 SELL…: the menu, each filter's count and price (shared/StockPlan.luau on the window's values), asked first
before = #sentOn("Collection")
press(named(picker, "SellMenu"))
local menu = named(picker, "Menu")
local menuBox = menu and named(menu, "MenuBox")
check("💰 SELL… opens its menu over the card (nothing sent)", menu ~= nil and menuBox ~= nil and #sentOn("Collection") == before)
local pieces = piecesFor(SELLS)
local menuRight = true
local menuDetail = nil
for _, id in StockPlan.Filters do
	local option = named(menuBox, `Sell_{id}`)
	local chosen = StockPlan.toSell(pieces, id)
	local count = named(option, "Count")
	local price = named(option, "Price")
	local want = `{#chosen} {if #chosen == 1 then "piece" else "pieces"} · `
	if not (option and named(option, "What").Text == StockPlan.filterName(id) and #chosen > 0 and string.sub(count.Text, 1, #want) == want and price and price.Text == M.MUi.money(StockPlan.price(chosen))) then
		menuRight = false
		menuDetail = `{id}: {count and count.Text} {price and price.Text}`
	end
end
check("… ALL COMMON, ALL BROKEN, DUPLICATES: each with how many and their price (as the server picks them)", menuRight, menuDetail)
check("… its texts fit, its options and CANCEL a finger's size, the menu inside the card", #badTexts(menu) == 0 and #smallButtons(menuBox) == 0 and within(box(menuBox), box(picker)), badTexts(menu)[1] or smallButtons(menuBox)[1])
scene("phone-sellmenu")
key("Escape")
check("… ESC closes the menu first (the list stays)", named(picker, "Menu") == nil and WarehouseUi.isOpen())
press(named(picker, "SellMenu"))
local commons = StockPlan.toSell(pieces, "common")
press(named(named(picker, "Menu"), "Sell_common"))
local ask = named(picker, "Confirm")
local commonTotal = M.MUi.money(StockPlan.price(commons))
check(`ALL COMMON asks first: "SELL {#commons} PIECES FOR {commonTotal}?" (the menu gone, nothing sent)`, ask ~= nil and named(picker, "Menu") == nil and named(ask, "Question").Text == `SELL {#commons} PIECES FOR {commonTotal}?` and #sentOn("Collection") == before, ask and named(ask, "Question").Text)
check("… the pieces named, the hint: pieces on show stay; texts fit, buttons a finger's size", string.find(named(ask, "What").Text, ",", 1, true) ~= nil and string.find(named(ask, "Hint").Text, "on show", 1, true) ~= nil and #badTexts(ask) == 0 and #smallButtons(named(ask, "ConfirmBox")) == 0, badTexts(ask)[1])
scene("phone-sellconfirm")
press(named(ask, "Cancel"))
check("… CANCEL: nothing sent", named(picker, "Confirm") == nil and #sentOn("Collection") == before)
press(named(picker, "SellMenu"))
press(named(named(picker, "Menu"), "Sell_duplicates"))
press(named(named(picker, "Confirm"), "ConfirmSell"))
sent = sentOn("Collection")
check("… SELL: { kind = \"sellmany\", filter = \"duplicates\" } and nothing else (the server picks the pieces)", #sent == before + 1 and sent[#sent][1].kind == "sellmany" and sent[#sent][1].filter == "duplicates" and sent[#sent][1].uid == nil and sent[#sent][1].uids == nil)
check("… 💰 SELL… waits (…)", named(picker, "SellMenu").Text == "…")

-- ⭐ FILL BEST and ↩ TAKE ALL DOWN
before = #sentOn("Collection")
press(named(picker, "FillBest"))
press(named(picker, "FillBest"))
sent = sentOn("Collection")
check("⭐ FILL BEST: { kind = \"fillbest\" } once (a double tap is one request), it waits (…)", #sent == before + 1 and sent[#sent][1].kind == "fillbest" and named(picker, "FillBest").Text == "…")
press(named(picker, "TakeAllDown"))
sent = sentOn("Collection")
check("↩ TAKE ALL DOWN: { kind = \"undisplayall\" }", #sent == before + 2 and sent[#sent][1].kind == "undisplayall")
-- the server's answers: toasts
collection.OnClientEvent:Fire({ kind = "bulk", action = "fillbest", count = 3, income = 42.5 })
check("the server's fillbest: \"⭐ 3 pieces put on show · +$X/min\"", M.toasts[#M.toasts] == `⭐ 3 pieces put on show · {WarehouseUi.rate(42.5)}`, M.toasts[#M.toasts])
collection.OnClientEvent:Fire({ kind = "bulk", action = "undisplayall", count = 1 })
check("… undisplayall: \"↩ 1 piece back in your stock\"", M.toasts[#M.toasts] == "↩ 1 piece back in your stock", M.toasts[#M.toasts])
collection.OnClientEvent:Fire({ kind = "sold", name = "4 pieces", money = 120, count = 4 })
check("… a sellmany's sold: \"Sold 4 pieces · +$120\"", M.toasts[#M.toasts] == "Sold 4 pieces · +$120", M.toasts[#M.toasts])
local toastCount = #M.toasts
collection.OnClientEvent:Fire({ kind = "bulk", action = "nope", count = 3 })
collection.OnClientEvent:Fire({ kind = "bulk", action = "fillbest", count = "x" })
check("… junk: no toast", #M.toasts == toastCount)

-- nothing to do: grey, a tap says why and sends nothing
local FULL = {
	{ uid = "f1", item = "painting", variant = 1, condition = 0.95, name = "Painting", got = 5, stand = 1 },
	{ uid = "f2", item = "sofa", variant = 2, condition = 0.64, name = "Sofa", got = 2, stand = 2 },
}
collection.OnClientEvent:Fire(withStands(FULL, 12, 2))
picker = named(gui, "Picker")
before = #sentOn("Collection")
check("every stand full, nothing in the stock: FILL BEST and SELL… grey, TAKE ALL DOWN live", named(picker, "FillBest"):GetAttribute("Live") == false and named(picker, "SellMenu"):GetAttribute("Live") == false and named(picker, "TakeAllDown"):GetAttribute("Live") == true)
press(named(picker, "FillBest"))
check("… FILL BEST's tap: \"Every display stand you have already shows a piece.\", nothing sent", M.toasts[#M.toasts] == "Every display stand you have already shows a piece." and #sentOn("Collection") == before, M.toasts[#M.toasts])
press(named(picker, "SellMenu"))
check("… SELL…'s tap: \"Your stock is empty: nothing to sell.\" (no menu)", M.toasts[#M.toasts] == "Your stock is empty: nothing to sell." and named(picker, "Menu") == nil)
-- (14 stands, the 12 big ones taken: only small 13 and 14 free; a bed and a broken TV in the stock)
local BIGFULL = {}
for i = 1, 12 do
	table.insert(BIGFULL, { uid = `k{i}`, item = "radio", variant = 1, condition = 1, name = "Kitchen Radio", got = i, stand = i })
end
table.insert(BIGFULL, { uid = "k13", item = "bed", variant = 1, condition = 1, name = "Double Bed", got = 13 })
table.insert(BIGFULL, { uid = "k14", item = "tv", variant = 1, condition = 0, name = "Old TV", got = 14 })
collection.OnClientEvent:Fire(withStands(BIGFULL, 12, 14))
picker = named(gui, "Picker")
press(named(picker, "FillBest"))
check("only small stands free and a bed: FILL BEST grey, \"What's in your stock is too big for your free small stands.\"", named(picker, "FillBest"):GetAttribute("Live") == false and M.toasts[#M.toasts] == "What's in your stock is too big for your free small stands.", M.toasts[#M.toasts])
collection.OnClientEvent:Fire(withStands({}, 0, 12))
picker = named(gui, "Picker")
press(named(picker, "TakeAllDown"))
check("an empty stock: all three grey; TAKE ALL DOWN's tap: \"Nothing is on show.\"", named(picker, "TakeAllDown"):GetAttribute("Live") == false and named(picker, "FillBest"):GetAttribute("Live") == false and M.toasts[#M.toasts] == "Nothing is on show." and #sentOn("Collection") == before)
pickerChecks("844 x 390, an empty STOCK list")
WarehouseUi.close()

-- the sort toggle: $/MIN → VALUE → NEWEST → RARITY → $/MIN, kept while you play
collection.OnClientEvent:Fire(withStands(SELLS, 36, 6))
WarehouseUi.openStock()
picker = named(gui, "Picker")
grid = named(picker, "Grid")
local function firstTile()
	return tilesOf()[1].Name
end
local function best(by)
	local list = piecesFor(SELLS)
	table.sort(list, StockPlan.order(by))
	return `Tile_{list[1].uid}`
end
check("the sort toggle: \"SORT · $/MIN\", the best earners first", named(picker, "Sort").Text == "SORT · $/MIN" and WarehouseUi.sorting() == "income" and firstTile() == best("income"), firstTile())
local orderOk, orderDetail = true, nil
for _, by in { "value", "newest", "rarity", "income" } do
	press(named(picker, "Sort"))
	picker = named(gui, "Picker")
	grid = named(picker, "Grid")
	if not (named(picker, "Sort").Text == `SORT · {StockPlan.sortLabel(by)}` and WarehouseUi.sorting() == by and firstTile() == best(by)) then
		orderOk, orderDetail = false, `{by}: {named(picker, "Sort").Text} {firstTile()} vs {best(by)}`
	end
	if by == "value" then
		scene("phone-sort-value")
	end
end
check("… a tap goes on: VALUE (the dearest first), NEWEST (came home last), RARITY (the rarest), back to $/MIN", orderOk, orderDetail)
press(named(picker, "Sort"))
WarehouseUi.close()
collection.OnClientEvent:Fire({ kind = "pick", stand = 3 })
picker = named(gui, "Picker")
grid = named(picker, "Grid")
check("… kept: the picker opens sorted by VALUE too", named(picker, "Sort").Text == "SORT · VALUE" and firstTile() == (function()
	local list = {}
	for _, p in piecesFor(SELLS) do
		if not p.stand then
			table.insert(list, p)
		end
	end
	table.sort(list, StockPlan.order("value"))
	return `Tile_{list[1].uid}`
end)())
for _ = 1, 3 do
	press(named(named(gui, "Picker"), "Sort"))
end
check("… round to $/MIN again", WarehouseUi.sorting() == "income")
WarehouseUi.close()

-- THE PICKER at a small upgrade stand: the pieces too big for it greyed, "Too big for this stand", last
local SMALL = {
	{ uid = "s1", item = "bed", variant = 1, condition = 1, name = "Double Bed", got = 1, rarity = "rare", perMinute = 9.9, sell = 90 },
	{ uid = "s2", item = "hay_wagon", variant = 1, condition = 1, name = "Hay Wagon", got = 2, rarity = "epic", perMinute = 16.9, sell = 156 },
	{ uid = "s3", item = "radio", variant = 1, condition = 1, name = "Kitchen Radio", got = 3, rarity = "common", perMinute = 0.9, sell = 8 },
	{ uid = "s4", item = "piano", variant = 1, condition = 1, name = "Upright Piano", got = 4, rarity = "epic", perMinute = 31.2, sell = 288 },
	{ uid = "s5", item = "wheelbarrow", variant = 1, condition = 1, name = "Wheelbarrow", got = 5, rarity = "common", perMinute = 1, sell = 10 },
}
collection.OnClientEvent:Fire(withStands(SMALL, 0, 14))
collection.OnClientEvent:Fire({ kind = "pick", stand = 13 })
picker = named(gui, "Picker")
grid = named(picker, "Grid")
local order = {}
for _, tile in tilesOf() do
	table.insert(order, tile.Name)
end
check("small stand 13: the pieces that fit first (the piano, the radio), the bed, the hay wagon and the wheelbarrow last", table.concat(order, ",") == "Tile_s4,Tile_s3,Tile_s2,Tile_s1,Tile_s5", table.concat(order, ","))
local bed = named(grid, "Tile_s1")
check("… a bed's tile greyed: \"Too big for this stand\" over its picture, TOO BIG for DISPLAY", bed:GetAttribute("TooBig") == true and named(bed, "TooBigWords").Text == "Too big for this stand" and named(bed, "TooBigWords").TextWrapped and named(bed, "Display").Text == "TOO BIG"
	and named(bed, "PieceName").TextTransparency > 0 and bed.BackgroundTransparency > 0)
check("… the piano's not: DISPLAY", named(named(grid, "Tile_s4"), "Display").Text == "DISPLAY" and named(grid, "Tile_s4"):GetAttribute("TooBig") == false and named(named(grid, "Tile_s4"), "TooBig") == nil)
pickerChecks("844 x 390, small stand 13")
scene("phone-toobig")
before = #sentOn("Collection")
press(named(bed, "Display"))
check("… TOO BIG sends nothing, says where it goes (stands 1 – 12), the picker stays", #sentOn("Collection") == before and WarehouseUi.isOpen() and M.toasts[#M.toasts] == "Your Double Bed is too big for small stand 13: show it on stands 1 – 12.", M.toasts[#M.toasts])
press(named(bed, "Sell"))
check("… its SELL still asks", named(picker, "Confirm") ~= nil)
key("Escape")
press(named(named(grid, "Tile_s4"), "Display"))
sent = sentOn("Collection")
check("… DISPLAY on a piece that fits: { kind = \"display\", uid, stand = 13 }", sent[#sent][1].kind == "display" and sent[#sent][1].uid == "s4" and sent[#sent][1].stand == 13)
collection.OnClientEvent:Fire({ kind = "pick", stand = 3 })
picker = named(gui, "Picker")
grid = named(picker, "Grid")
local greyed = 0
for _, tile in tilesOf() do
	if tile:GetAttribute("TooBig") then
		greyed += 1
	end
end
check("big stand 3: nothing greyed (every piece fits)", greyed == 0 and #tilesOf() == 5)
WarehouseUi.close()
collection.OnClientEvent:Fire(state(STOCK, 36))
M.flush()

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
	-- 8.2: the header's buttons, the sort toggle, the search box (a computer), the SELL… menu
	headerChecks(label)
	picker = named(gui, "Picker")
	local search = named(picker, "Search")
	check(`{label}: … the 🔍 search box on the chips' row (a computer), left of the sort toggle, clear of the chips`, search ~= nil and search.ClassName == "TextBox" and search.PlaceholderText == "🔍 Search" and search.ClearTextOnFocus == false
		and box(search).x1 <= box(named(picker, "Sort")).x0 and not overlap(box(search), box(named(picker, "Filter_all"))) and within(box(search), box(picker)))
	press(named(picker, "SellMenu"))
	local menu2 = named(picker, "Menu")
	check(`{label}: … SELL…'s menu: its texts fit, inside the card`, menu2 ~= nil and #badTexts(menu2) == 0 and within(box(named(menu2, "MenuBox")), box(picker)), menu2 and badTexts(menu2)[1])
	if size[3] ~= "chat" then
		scene(`{size[3]}-sellmenu`)
	end
	key("Escape")
	key("Escape")
	check(`{label}: ESC closes it`, not WarehouseUi.isOpen())
end

-- 8.2, the search box (a computer): typing redraws only the grid (the box keeps its focus), every word in the name
collection.OnClientEvent:Fire(withStands(SELLS, 36, 6))
WarehouseUi.openStock()
picker = named(gui, "Picker")
grid = named(picker, "Grid")
local searchBox = named(picker, "Search")
local function typeIn(text)
	searchBox.Text = text
	searchBox:GetPropertyChangedSignal("Text"):Fire()
	grid = named(picker, "Grid")
end
local tilesBefore = #tilesOf()
typeIn("clock")
check("search \"clock\": only Grandpa's Clock; the card and the box not drawn again (the focus kept)", #tilesOf() == 1 and tilesOf()[1].Name == "Tile_a1" and named(gui, "Picker") == picker and named(picker, "Search") == searchBox and WarehouseUi.search() == "clock", #tilesOf())
typeIn("CHAIR")
check("… any case: \"CHAIR\" finds the two chairs and the armchair", #tilesOf() == 3, #tilesOf())
typeIn("rec")
check("… a word anywhere in the name: \"rec\" finds the Gold Record and the Old Record Player", #tilesOf() == 2, #tilesOf())
typeIn("record pla")
check("… every word: \"record pla\" only the Old Record Player", #tilesOf() == 1 and tilesOf()[1].Name == "Tile_a7", #tilesOf())
scene("computer-search")
typeIn("zzz")
check("… nothing matches: no tile, \"No piece here matches \\\"zzz\\\".\"", #tilesOf() == 0 and named(picker, "Empty") ~= nil and named(picker, "Empty").Text == "No piece here matches \"zzz\".")
typeIn(string.rep("x", 60))
check("… at most 40 letters", #searchBox.Text == 40)
collection.OnClientEvent:Fire(withStands(SELLS, 36, 6))
check("… the same state again: nothing drawn again (the search box keeps its words and focus)", named(gui, "Picker") == picker)
typeIn("")
check("… emptied: every piece again", #tilesOf() == tilesBefore and named(picker, "Empty") == nil, #tilesOf())
press(named(picker, "Filter_common"))
picker = named(gui, "Picker")
searchBox = named(picker, "Search")
grid = named(picker, "Grid")
typeIn("chair")
local commonChairs = true
for _, tile in tilesOf() do
	commonChairs = commonChairs and named(tile, "Rarity").Text == "COMMON"
end
check("… with a rarity chip: both (COMMON and \"chair\")", commonChairs and #tilesOf() >= 1, #tilesOf())
typeIn("")
press(named(picker, "Filter_all"))
picker = named(gui, "Picker")
searchBox = named(picker, "Search")
typeIn("clock")
WarehouseUi.close()
collection.OnClientEvent:Fire({ kind = "pick", stand = 4 })
picker = named(gui, "Picker")
grid = named(picker, "Grid")
check("… closing the window clears the search (a picker opened next lists every piece)", WarehouseUi.search() == "" and named(picker, "Search").Text == "" and #tilesOf() > 1, #tilesOf())
WarehouseUi.close()
collection.OnClientEvent:Fire(state(STOCK, 36))
M.flush()
M.chatOpen = false

-- ── A resize while it is open ───────────────────────────────────────────────
WarehouseUi.openStock()
screen(true, 844, 354)
picker = named(gui, "Picker")
check("a resize to a phone while open: drawn again for it (a finger's buttons)", math.abs(M.uiScale(picker) - WarehouseUi.layout(844, 354, true).scale) < 0.001 and #smallButtons(picker) == 0)
WarehouseUi.close()

-- ── 8.3: the market ─────────────────────────────────────────────────────────
-- The server's state with the player's market (shared/Market.luau's View): today's hot and cold kinds and the demand
-- of what they sold today; every view's price and income the market's (CollectionRules.view with it, as
-- server/Collection.luau sends them).
do
	local Market = require("./Market")
	local CollectionRules = require("./CollectionRules")
	local MK = Config.Market
	local view = { day = 20375, hot = { "record_player", "old_globe", "jukebox" }, cold = { "wardrobe" }, left = 5 * 3600 + 600,
		demand = { vintage_radio = { n = 2, sold = 2, back = 600 }, dining_chair = { n = 1, sold = 1, back = 300 } } }
	local raw = {
		{ uid = "m1", item = "record_player", variant = 1, condition = 0.92, name = "Old Record Player", got = 31 },
		{ uid = "m2", item = "old_globe", variant = 1, condition = 1, name = "Old Globe", got = 32, stand = 1 },
		{ uid = "m3", item = "wardrobe", variant = 2, condition = 0.85, name = "Wardrobe", got = 33 },
		{ uid = "m4", item = "vintage_radio", variant = 1, condition = 0.9, name = "Vintage Radio", got = 34 },
		{ uid = "m5", item = "dining_chair", variant = 1, condition = 0.9, name = "Chair", got = 35 },
		{ uid = "m6", item = "dining_chair", variant = 2, condition = 0.8, name = "Chair", got = 36 },
		{ uid = "m7", item = "dining_chair", variant = 3, condition = 0.7, name = "Chair", got = 37 },
		{ uid = "m8", item = "jukebox", variant = 1, condition = 0.95, name = "Jukebox", got = 38, stand = 12 },
		{ uid = "m9", item = "sofa", variant = 1, condition = 0.9, name = "Sofa", got = 39 },
	}
	local stock = {}
	for _, entry in raw do
		table.insert(stock, CollectionRules.view(entry :: any, 1, view :: any))
	end
	local byUid = {}
	for _, v in stock do
		byUid[v.uid] = v
	end
	local function marketState(market)
		return { kind = "state", stock = stock, income = 64.2, stands = 12, market = market }
	end
	check("8.3: the server's views carry the market (a hot piece × 1.6, the cold one × 0.7, the radio −10 %)", byUid.m1.market == "hot" and byUid.m1.price == math.floor(byUid.m1.base * MK.HotSell + 0.5)
		and byUid.m3.market == "cold" and byUid.m3.price == math.floor(byUid.m3.base * MK.ColdSell + 0.5) and byUid.m4.price == math.floor(byUid.m4.base * 0.9 + 0.5))

	-- the toast: once after joining (for the day), held while the HUD is hidden
	screen(true, 844, 354)
	local toastsAt = #M.toasts
	local function hotToasts(): { string }
		local out = {}
		for index = toastsAt + 1, #M.toasts do
			if string.sub(M.toasts[index], 1, #"🔥 Hot today") == "🔥 Hot today" then
				table.insert(out, M.toasts[index])
			end
		end
		return out
	end
	collection.OnClientEvent:Fire(marketState(view))
	M.flush()
	local hotToast = "🔥 Hot today: Old Record Player, Old Globe, Jukebox (sell ×1.6, on show ×1.25)"
	check("the first state with a market: the toast \"🔥 Hot today: … (sell ×1.6, on show ×1.25)\"", #hotToasts() == 1 and hotToasts()[1] == hotToast and Market.hotToast(view :: any) == hotToast, hotToasts()[1])
	collection.OnClientEvent:Fire(marketState(view))
	M.flush()
	check("… the same day's next states: no toast again", #hotToasts() == 1)
	M.hudGui.Enabled = false
	M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
	local tomorrow = table.clone(view)
	tomorrow.day = view.day + 1
	tomorrow.hot = { "sofa", "piano", "jukebox" }
	collection.OnClientEvent:Fire(marketState(tomorrow))
	M.flush()
	check("… a new day while the HUD is hidden (the start screen): held back", #hotToasts() == 1)
	M.hudGui.Enabled = true
	M.hudGui:GetPropertyChangedSignal("Enabled"):Fire()
	ownGui:GetPropertyChangedSignal("Enabled"):Fire()
	M.flush()
	check("… told when the HUD shows: \"🔥 Hot today: Sofa, Upright Piano, Jukebox …\"", #hotToasts() == 2 and string.find(hotToasts()[2], "Sofa, Upright Piano, Jukebox", 1, true) ~= nil, hotToasts()[2])
	collection.OnClientEvent:Fire(marketState(view))
	M.flush()
	check("… an older day after it (a clock that went back): no toast", #hotToasts() == 2)

	-- the STOCK list on each screen: the market's line, the tags, the prices
	local function marketChecks(label)
		picker = named(gui, "Picker")
		grid = named(picker, "Grid")
		local line = named(picker, "Market")
		check(`{label}: the market's line "Today's market: 🔥 … · ❄ Wardrobe · new in 5 h"`, line ~= nil and line.Text == "Today's market: 🔥 Old Record Player, Old Globe, Jukebox · ❄ Wardrobe · new in 5 h", line and line.Text)
		local room, need = textRoom(line)
		local lineBox = box(line)
		local clear, hit = within(lineBox, box(picker)), nil
		for _, name in { "Title", "Subtitle", "Close", "FillBest", "SellMenu", "TakeAllDown", "Filter_all", "Sort", "Grid" } do
			local other = named(picker, name)
			if other and overlap(lineBox, box(other)) then
				clear, hit = false, name
			end
		end
		check(`{label}: … whole on one line, inside the card, clear of the title, its line, the ✕, the bulk buttons, the chips and the grid`, need <= room + 0.5 and clear, hit or `{math.floor(need)} > {math.floor(room)}`)
		local longest, longestW = "", 0
		for day = 20300, 20664 do
			local text = Market.line(Market.today(day), 23 * 3600 + 3000)
			local width = M.textWidth(text, 12 * M.scaleOf(line), line.Font)
			if width > longestW then
				longest, longestW = text, width
			end
		end
		check(`{label}: … a year's longest line whole too`, longestW <= room + 0.5, `{math.floor(longestW)} > {math.floor(room)}: {longest}`)
		local function tag(uid, name)
			local tile = named(grid, `Tile_{uid}`)
			return tile and named(tile, name), tile
		end
		local hotTag, hotTile = tag("m1", "MarketTag")
		local coldTag = tag("m3", "MarketTag")
		local dropTag = tag("m4", "DemandTag")
		local plainTag = tag("m9", "MarketTag")
		check(`{label}: the tags: "🔥 HOT ×1.6" on a hot kind, "❄ COLD" on the cold one, "📉 −10%" on the radio, none on the sofa`, hotTag ~= nil and hotTag.Text == "🔥 HOT ×1.6" and coldTag ~= nil and coldTag.Text == "❄ COLD"
			and dropTag ~= nil and dropTag.Text == "📉 −10%" and plainTag == nil and tag("m9", "DemandTag") == nil)
		check(`{label}: … each on its piece's picture, its words fitting`, within(box(hotTag), box(named(hotTile, "Picture"))) and #badTexts(hotTile) == 0 and #badTexts(named(grid, "Tile_m4")) == 0, badTexts(hotTile)[1])
		local onStand = named(grid, "Tile_m8")
		local ribbon, juke = named(onStand, "OnStand"), named(onStand, "MarketTag")
		check(`{label}: … on a piece on show: under ON STAND n, not on it`, ribbon ~= nil and juke ~= nil and not overlap(box(ribbon), box(juke)) and box(juke).y0 >= box(ribbon).y1 - 0.5
			and within(box(juke), box(named(onStand, "Picture"))))
		local chairs = named(grid, "Tile_m5")
		check(`{label}: … the prices are the market's (the server's): the record player's "Sell {M.MUi.money(byUid.m1.price)}"`, named(hotTile, "SellPrice").Text == `Sell {M.MUi.money(byUid.m1.price)}`
			and named(chairs, "SellPrice").Text == `Sell {M.MUi.money(byUid.m5.price)}`)
	end
	for _, size in { { true, 844, 354, "phone" }, { false, 1280, 764, "computer" }, { false, 1920, 1044, "big" } } do
		screen(size[1], size[2], size[3])
		collection.OnClientEvent:Fire(marketState(view))
		WarehouseUi.openStock()
		local label = `8.3, {size[2]} x {size[3] + 36}`
		marketChecks(label)
		pickerChecks(`{label}, the STOCK list with the market`)
		headerChecks(label)
		scene(`{size[4]}-market`)
		WarehouseUi.close()
		collection.OnClientEvent:Fire({ kind = "pick", stand = 4 })
		picker = named(gui, "Picker")
		grid = named(picker, "Grid")
		local pickLine = named(picker, "Market")
		check(`{label}: the picker has the market's line too, its hot pieces tagged`, pickLine ~= nil and string.sub(pickLine.Text, 1, 16) == "Today's market: " and named(named(grid, "Tile_m1"), "MarketTag") ~= nil)
		pickerChecks(`{label}, the picker with the market`)
		WarehouseUi.close()
	end

	-- SELL's question: why the price is what it is; the price it showed goes with the request
	screen(true, 844, 354)
	collection.OnClientEvent:Fire(marketState(view))
	WarehouseUi.openStock()
	picker = named(gui, "Picker")
	grid = named(picker, "Grid")
	press(named(named(grid, "Tile_m4"), "Sell"))
	local ask = named(picker, "Confirm")
	check("SELL the radio: \"SELL FOR $Y?\" at the market's price, the hint \"Market: Vintage Radio −10% (you sold 2 today)\"", ask ~= nil and named(ask, "Question").Text == `SELL FOR {M.MUi.money(byUid.m4.price)}?`
		and named(ask, "Hint").Text == "Market: Vintage Radio −10% (you sold 2 today)", ask and named(ask, "Hint").Text)
	local hintRoom, hintNeed = textRoom(named(ask, "Hint"))
	check("… its texts fit, the demand's line whole (not cut)", #badTexts(ask) == 0 and hintNeed <= hintRoom + 0.5, badTexts(ask)[1] or `{math.floor(hintNeed)} > {math.floor(hintRoom)}`)
	scene("phone-market-confirm")
	local before = #sentOn("Collection")
	press(named(ask, "ConfirmSell"))
	local sent = sentOn("Collection")
	check("… SELL: { kind = \"sell\", uid, expect = the price it showed }", #sent == before + 1 and sent[#sent][1].kind == "sell" and sent[#sent][1].uid == "m4" and sent[#sent][1].expect == byUid.m4.price)
	WarehouseUi.close()
	collection.OnClientEvent:Fire(marketState(view))
	WarehouseUi.openStock()
	picker = named(gui, "Picker")
	grid = named(picker, "Grid")
	press(named(named(grid, "Tile_m1"), "Sell"))
	check("… a hot piece's hint: \"🔥 Hot today: it sells for ×1.6, earns ×1.25 on show.\"", named(named(picker, "Confirm"), "Hint").Text == "🔥 Hot today: it sells for ×1.6, earns ×1.25 on show.", named(named(picker, "Confirm"), "Hint").Text)
	key("Escape")
	press(named(named(grid, "Tile_m3"), "Sell"))
	check("… the cold one's: \"❄ Cold today: it sells for ×0.7. Keep it on show till tomorrow?\"", named(named(picker, "Confirm"), "Hint").Text == "❄ Cold today: it sells for ×0.7. Keep it on show till tomorrow?", named(named(picker, "Confirm"), "Hint").Text)
	key("Escape")
	press(named(named(grid, "Tile_m9"), "Sell"))
	check("… a piece the market doesn't touch: the hint as before", named(named(picker, "Confirm"), "Hint").Text == `On show it would earn {WarehouseUi.rate(byUid.m9.income)}.`)
	key("Escape")

	-- 💰 SELL…: the market's totals, one piece after the other (the chairs: −5 %, −10 %, −15 %), the total expected
	press(named(picker, "SellMenu"))
	local menuBox = named(named(picker, "Menu"), "MenuBox")
	local pieces = {}
	for _, v in stock do
		table.insert(pieces, { uid = v.uid, item = v.item, stand = v.stand, got = v.got, rarity = v.rarity, income = v.income, price = v.price, broken = v.broken, condition = v.condition, base = v.base })
	end
	local commons = StockPlan.toSell(pieces, "common")
	local total = StockPlan.price(commons, view :: any)
	check("SELL…'s ALL COMMON: the three chairs at the market's total (each next one 5 % lower: under their single prices)", #commons == 3 and total < StockPlan.price(commons)
		and named(named(menuBox, "Sell_common"), "Price").Text == M.MUi.money(total), named(named(menuBox, "Sell_common"), "Price").Text)
	press(named(menuBox, "Sell_common"))
	ask = named(picker, "Confirm")
	check(`… asked: "SELL 3 PIECES FOR {M.MUi.money(total)}?", the hint: each piece of a kind lowers the next one's price`, named(ask, "Question").Text == `SELL 3 PIECES FOR {M.MUi.money(total)}?`
		and named(ask, "Hint").Text == "Market: each next piece of a kind sells 5% lower." and #badTexts(ask) == 0, named(ask, "Hint").Text)
	local room, need = textRoom(named(ask, "Hint"))
	check("… the hint whole on a phone (not cut)", need <= room + 0.5, `{math.floor(need)} > {math.floor(room)}`)
	scene("phone-market-sellconfirm")
	local from = os.clock()
	while os.clock() - from < 0.65 do -- (WarehouseUi's double-tap guard: a kind's request once in 0.6 s; 8.2's sellmany was just now)
	end
	before = #sentOn("Collection")
	press(named(ask, "ConfirmSell"))
	sent = sentOn("Collection")
	check("… SELL: { kind = \"sellmany\", filter, expect = that total }", #sent == before + 1 and sent[#sent][1].kind == "sellmany" and sent[#sent][1].filter == "common" and sent[#sent][1].expect == total)
	WarehouseUi.close()

	-- a guessed price is never expected (only the server's)
	collection.OnClientEvent:Fire(state(STOCK, 36))
	WarehouseUi.openStock()
	picker = named(gui, "Picker")
	grid = named(picker, "Grid")
	press(named(named(grid, "Tile_a2"), "Sell"))
	before = #sentOn("Collection")
	press(named(named(picker, "Confirm"), "ConfirmSell"))
	sent = sentOn("Collection")
	check("a state without a market or prices: no line, no tags, SELL sends no expect (the server's price stands)", named(picker, "Market") == nil and #sent == before + 1 and sent[#sent][1].expect == nil
		and named(grid, "MarketTag") == nil)
	WarehouseUi.close()
	check("Market.readView: junk from the remote is no market (no line)", (function(): boolean
		collection.OnClientEvent:Fire(marketState({ day = "x", hot = 5 }))
		WarehouseUi.openStock()
		local none = named(named(gui, "Picker"), "Market") == nil
		WarehouseUi.close()
		return none
	end)())
	collection.OnClientEvent:Fire(state(STOCK, 36))
	M.flush()
end

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
