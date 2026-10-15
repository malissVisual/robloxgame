-- 8.9: the first-time hints for the 8.5 – 8.7 features (client/SandboxHintsUi.luau, shared/SandboxHints.luau), run for
-- real on sandbox_mock.luau's recorder (sandboxhintsenv.py's folder) beside the real client/SandboxHud.luau (the money
-- block; the hints' toasts are its toasts), client/SandboxTasksUi.luau (the TASKS chip), client/DannyOrders.luau (orders
-- mode's line at the bottom and the touch 📋 button), client/MoveHelperHud.luau (Danny's status line),
-- client/MoveHelperCard.luau (his card), client/OfferCard.luau (a player's offer) and client/TradeUi.luau, a stand-in
-- move's panel and Hud's groups where client/Hud.luau puts them:
--   * when each comes: your clipboard out (your character's ClipboardHeld) "orders"; another player's warehouse with a
--     piece of theirs on show (a stand's trade prompt on, tagged TradePrompt with its owner's UserId; the building of
--     its level, workspace.Warehouses' Level<id>) "visit"; three pieces of yours on show and no FOR SALE sign (the
--     Collection remote's state) "price"; a player's offer on the PlayerTrade remote "deal"; each once, one at a time,
--     never while a window covers the screen (Danny's card, the offer card), a hint no longer true when its turn comes
--     left out (the clipboard put away, the warehouse left, a sign set) and said the next time; their words for the
--     device; nothing for your own warehouse, a warehouse with nothing on show, a visitor's offer;
--   * where they show: client/Hud.luau's toast (its words 340 px at most, wrapped, 14 px; its padding; the column under
--     the money block and the TASKS chip, at the HUD's scale; the toast before it over it) at 844 × 390 and 667 × 375
--     (phones held sideways: the touch layout), 1280 × 800 and 1920 × 1080 (a computer's words and a gamepad's): on the
--     screen, three lines at most, clear of the touch buttons, the jump button and where the thumbstick rests (Hud's
--     column itself, every toast in it, starts in the top right corner of the thumbstick's zone), the minimap's
--     column, the HUD's chips, Hud's groups, the move's panel, Danny's status line, orders mode's line and 📋 button,
--     and the toast before it;
--   * no warnings.
local M = require("./sandbox_mock")
local Config = require("./Config")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local TasksRules = require("./SandboxTasks")
local SandboxHints = require("./SandboxHints")
local SandboxMap = require("./SandboxMap")
local WarehouseLayout = require("./WarehouseLayout")

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
local UIS = M.services.UserInputService
local box, overlap = M.box, TouchLayout.overlap
local function show(b)
	return string.format("%.0f,%.0f-%.0f,%.0f", b.x0, b.y0, b.x1, b.y1)
end
local function shown(object)
	local node = object
	while node do
		if node.Visible == false or node.Enabled == false then
			return false
		end
		node = node.Parent
	end
	return true
end
local function attribute(name, value)
	M.player:SetAttribute(name, value)
	M.player:GetAttributeChangedSignal(name):Fire()
end

-- ── The stand-ins (dannyorders.luau's) ──────────────────────────────────────
UIS.TouchTapInWorld = M.signal()
UIS.LastInputTypeChanged = M.signal()
UIS.MouseBehavior = M.Enum.MouseBehavior.Default
UIS.GetMouseLocation = function()
	return M.Vector2.new(400, 236)
end
local make = M.make
M.make = function(class, props, parent)
	local made = make(class, props, parent)
	if class == "ProximityPrompt" then
		made.Triggered = M.signal()
	end
	return made
end
local vmeta = getmetatable(M.Vector3.new(0, 0, 0))
local vindex = vmeta.__index
vmeta.__add = function(a, b)
	return M.Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
vmeta.__mul = function(a, k)
	return M.Vector3.new(a.X * k, a.Y * k, a.Z * k)
end
vmeta.__index = function(a, name)
	if name == "Unit" then
		local m = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
		return M.Vector3.new(a.X / m, a.Y / m, a.Z / m)
	elseif name == "Dot" then
		return function(self, b)
			return self.X * b.X + self.Y * b.Y + self.Z * b.Z
		end
	end
	return vindex(a, name)
end
M.methods.IsDescendantOf = function(self, ancestor)
	local node = self.Parent
	while node do
		if node == ancestor then
			return true
		end
		node = node.Parent
	end
	return false
end
M.methods.FindFirstAncestorOfClass = function(self, class)
	local node = self.Parent
	while node do
		if node.ClassName == class then
			return node
		end
		node = node.Parent
	end
	return nil
end
M.RaycastParams = { new = function()
	return {}
end }
M.workspace.Raycast = function()
	return nil
end
local gamepad = false
M.MUi.gamepadActive = function()
	return gamepad
end
M.MUi.gamepadRelease = function(container)
	local selected = M.focus
	if selected and container and selected:IsDescendantOf(container) then
		M.focus = nil
	end
end
local DANNY_ID = -2000000001
local npcs = M.make("Folder", { Name = "Npcs" }, M.workspace)
local body = M.make("Model", { Name = "Danny" }, npcs)
body:SetAttribute("MoveHelper", DANNY_ID)
body.PrimaryPart = M.make("BasePart", { Name = "HumanoidRootPart", Position = M.Vector3.new(8, 3, -6) }, body)
M.player:SetAttribute("MoveWith", 14)
local movingGui = M.make("ScreenGui", { Name = "MovingHud", DisplayOrder = 6 }, M.gui)
local panel = M.make("Frame", { Name = "MovePanel", BackgroundColor3 = M.MTheme.Contract.charcoal, BackgroundTransparency = 0.12 }, movingGui)
M.make("UIScale", { Name = "Scale", Scale = 1 }, panel)
local groups = {}
for _, name in { "LeftStack", "HudButtons" } do
	groups[name] = M.make("Frame", { Name = name, BackgroundTransparency = 1 }, M.hudGui)
end
local function place(object, b)
	object.Position = M.UDim2.fromOffset(b.x0, b.y0)
	object.Size = M.UDim2.fromOffset(b.x1 - b.x0, b.y1 - b.y0)
end
local camera = M.workspace.CurrentCamera
camera.ScreenPointToRay = function()
	return { Origin = M.Vector3.new(0, 20, 30), Direction = M.Vector3.new(0, -0.5, -1) }
end
camera.ViewportPointToRay = camera.ScreenPointToRay
local TopBlocks = require("./TopBlocks")
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	local S = M.MUi.scaleFor(M.Vector2.new(w, h))
	panel.Size = M.UDim2.fromOffset(MoveLayout.PANEL_W, MoveLayout.PANEL_H)
	panel:FindFirstChild("Scale").Scale = S
	local p = MoveLayout.panel(w, S)
	panel.Position = M.UDim2.fromOffset(p.x0, p.y0)
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
	TopBlocks.set("MovePanel", panel)
	M.flush()
	M.resume() -- (DannyOrders' look: placed for the new screen)
end
local function setPad(on)
	gamepad = on
	M.gamepad = on
	UIS.LastInputTypeChanged:Fire()
	M.inputChanged()
	M.flush()
end

-- ── Start: a phone, the HUD's chips, the hints ──────────────────────────────
local SandboxHud = require("./SandboxHud")
local SandboxTasksUi = require("./SandboxTasksUi")
local MoveHelperHud = require("./MoveHelperHud")
local MoveHelperCard = require("./MoveHelperCard")
local DannyOrders = require("./DannyOrders")
local OfferCard = require("./OfferCard")
local Hints = require("./SandboxHintsUi")
screen(true, 844, 354)
M.player:SetAttribute("Plot", 1) -- (your plot; Ann's is plot 2)
local halls = M.make("Folder", { Name = "Warehouses" }, M.workspace)
halls:SetAttribute("Level1", 4)
halls:SetAttribute("Level2", 4)
SandboxHud.start()
SandboxHud.setState({ money = 12480 })
M.flush()
SandboxTasksUi.start()
local NOW = 20372 * 86400 + 18 * 3600
local view = TasksRules.view(TasksRules.fresh(42, NOW), NOW) :: any
view.kind = "state"
M.remotes.SandboxTasks.OnClientEvent:Fire(view)
M.flush()
local tasksChip = named(M.gui:FindFirstChild("SandboxTasksChip"), "TasksChip")
MoveHelperHud.start()
MoveHelperCard.start()
DannyOrders.start()
OfferCard.start()
OfferCard.covered = function()
	return false
end
attribute("MoveHelperId", DANNY_ID)
attribute("MoveHelperDoing", "Carrying the Lamp to the van")
attribute("MoveHelperQueue", 2)
attribute("MoveHelper", "hired")
M.flush()
M.resume()
local strip = MoveHelperHud.strip()
local queue = Hints.queue()
local H = Config.SandboxHud.Hints
check("(the HUD's chips there, Danny hired: his status line; the hints started by SandboxHud, their toasts its toasts)", SandboxHud.block() ~= nil and tasksChip ~= nil
	and shown(tasksChip) and strip ~= nil and shown(strip) and Hints.notify == SandboxHud.toast)
check("(trading between players on)", SandboxHints.tradeOn())
local function after(seconds)
	M.now += seconds
	M.resume()
	M.flush()
end
local function lastToast()
	return M.toasts[#M.toasts]
end
local function said(text) -- (how many toasts said it: the HUD's own toasts, "+1 piece in your warehouse", come between)
	local n = 0
	for _, toast in M.toasts do
		if toast == text then
			n += 1
		end
	end
	return n
end
local function clipboard(out) -- (the server's answer: your character's ClipboardHeld)
	M.player.Character:SetAttribute("ClipboardHeld", if out then true else nil)
	M.resume()
	M.flush()
end
local function stand(x, z)
	M.root.Position = M.Vector3.new(x, 3, z)
end
local away = { x = 0, z = 200 } -- (Main Street: no warehouse)
stand(away.x, away.z)

-- ── The clipboard out: "orders" ─────────────────────────────────────────────
local ordersTouch = "📋 Orders mode: tap a piece to give it to Danny. Tap Danny for his orders. Tap 📋 to put it away."
clipboard(true)
check("your clipboard out (ClipboardHeld): the orders mode's hint waits", SandboxHints.waiting(queue, "orders"))
clipboard(false)
after(H.Delay + 0.5)
check("… put away before its turn: left out (not said, not seen)", said(ordersTouch) == 0 and not SandboxHints.waiting(queue, "orders") and not SandboxHints.seen(queue, "orders"))
clipboard(true)
check("… out again: it waits again", SandboxHints.waiting(queue, "orders"))
MoveHelperCard.open({ x = 300, y = 170 })
after(H.Delay + 1)
check("… not while Danny's card covers the screen", said(ordersTouch) == 0 and SandboxHints.waiting(queue, "orders") and Hints.isCovered())
MoveHelperCard.close()
after(H.Every)
check(`… then (a phone): "{ordersTouch}"`, said(ordersTouch) == 1 and lastToast() == ordersTouch and SandboxHints.seen(queue, "orders"), lastToast())
clipboard(false)
clipboard(true)
after(H.Gap + H.Delay)
check("… once: out again later, no second hint", said(ordersTouch) == 1 and not SandboxHints.waiting(queue, "orders"))
clipboard(false)

-- ── Another player's warehouse with a piece of theirs on show: "visit" ──────
local ME, ANN = M.player.UserId, 22
local function hallMiddle(plotId)
	local floor = WarehouseLayout.inside(WarehouseLayout.site(plotId, 4))
	return { x = (floor.x0 + floor.x1) / 2, z = (floor.z0 + floor.z1) / 2 }
end
local mine, hers = hallMiddle(1), hallMiddle(2)
local function tradePrompt(seller, at, on)
	local podium = M.make("BasePart", { Name = "Podium", Position = M.Vector3.new(at.x, 1, at.z) }, M.workspace)
	local anchor = M.make("Attachment", { Name = "Prompts", WorldPosition = M.Vector3.new(at.x, 2, at.z + 1.6) }, podium)
	local prompt = M.make("ProximityPrompt", { Name = "MakeOffer", ActionText = "Make an offer", Enabled = on }, anchor)
	prompt:SetAttribute(Config.PlayerTrade.SellerAttribute, seller)
	M.tagged[Config.PlayerTrade.PromptTag] = M.tagged[Config.PlayerTrade.PromptTag] or {}
	table.insert(M.tagged[Config.PlayerTrade.PromptTag], prompt)
	return prompt
end
tradePrompt(ME, { x = mine.x - 8, z = mine.z }, true)
local annsPrompt = tradePrompt(ANN, { x = hers.x + 8, z = hers.z }, false)
local visitWords = "🤝 Like a piece here? Make the owner an offer."
stand(mine.x, mine.z)
after(H.Look)
check("in your own warehouse (your pieces on show): no hint", not SandboxHints.waiting(queue, "visit"))
stand(hers.x, hers.z)
after(H.Look)
check("in Ann's warehouse with nothing on show (her prompts off): no hint", not SandboxHints.waiting(queue, "visit"))
annsPrompt.Enabled = true
after(H.Look)
check("… a piece of hers on show (its Make an offer on): the hint waits", SandboxHints.waiting(queue, "visit"))
local plot2 = SandboxMap.Plots[2]
stand(plot2.vanSpot.x, plot2.vanSpot.z)
after(H.Delay + 0.5)
check("… walked out before its turn: left out (not said, not seen)", said(visitWords) == 0 and not SandboxHints.waiting(queue, "visit") and not SandboxHints.seen(queue, "visit"))
halls:SetAttribute("Level2", 1) -- (her warehouse a Garage now: its own small building, her piece's stand in it)
annsPrompt.Parent.WorldPosition = M.Vector3.new(plot2.warehouse.x + 3, 2, plot2.warehouse.z + plot2.warehouse.sz / 2 - 8)
stand(plot2.warehouse.x - 3, plot2.warehouse.z + plot2.warehouse.sz / 2 - 8)
after(H.Look)
check("… in again (her Garage: the building of her level): it waits again", SandboxHints.waiting(queue, "visit"))
after(H.Delay)
check(`… then: "{visitWords}"`, said(visitWords) == 1 and lastToast() == visitWords and SandboxHints.seen(queue, "visit"), lastToast())
stand(away.x, away.z)
after(H.Look)
stand(plot2.warehouse.x - 3, plot2.warehouse.z + plot2.warehouse.sz / 2 - 8)
after(H.Gap + H.Delay)
check("… once: in again later, no second hint", said(visitWords) == 1 and not SandboxHints.waiting(queue, "visit"))
stand(away.x, away.z)

-- ── Three pieces of yours on show, no sign: "price" ─────────────────────────
local collection = M.remotes.Collection
local function piece(uid, stand, sale)
	return { uid = uid, item = "chair", variant = 1, condition = 0.9, name = "Chair", got = 1, stand = stand, rarity = "common", income = 1.5, price = 60, base = 60, broken = false, sale = sale }
end
local function stockState(list)
	return { kind = "state", stock = list, income = 4.5, stands = 12 }
end
local priceWords = "🏷 Put a price on a piece and other players can buy it, even while you're away."
collection.OnClientEvent:Fire(stockState({ piece("p1", 1), piece("p2", 2), piece("p3") }))
check("two pieces on show: no hint", not SandboxHints.waiting(queue, "price"))
collection.OnClientEvent:Fire(stockState({ piece("p1", 1, 900), piece("p2", 2), piece("p3", 3) }))
check("three on show, one with a FOR SALE sign: no hint (the player knows it)", not SandboxHints.waiting(queue, "price"))
collection.OnClientEvent:Fire(stockState({ piece("p1", 1), piece("p2", 2), piece("p3", 3) }))
check("three on show, no sign: the hint waits", SandboxHints.waiting(queue, "price"))
collection.OnClientEvent:Fire(stockState({ piece("p1", 1, 900), piece("p2", 2), piece("p3", 3) }))
after(H.Gap + H.Delay)
check("… a sign set before its turn: left out", said(priceWords) == 0 and not SandboxHints.waiting(queue, "price") and not SandboxHints.seen(queue, "price"))
collection.OnClientEvent:Fire(stockState({ piece("p1", 1), piece("p2", 2), piece("p3", 3), piece("p4", 4) }))
after(H.Delay)
check(`… the sign taken off, four on show: "{priceWords}"`, said(priceWords) == 1 and lastToast() == priceWords and SandboxHints.seen(queue, "price"), lastToast())
collection.OnClientEvent:Fire(stockState({ piece("p1", 1), piece("p2", 2), piece("p3", 3), piece("p4", 4), piece("p5", 5) }))
check("… once", not SandboxHints.waiting(queue, "price"))

-- ── A player's offer: "deal" (after its card) ───────────────────────────────
local trade = M.Net.get("PlayerTrade")
local visitors = M.Net.get("Visitors")
local dealWords = "Players pay more than the game: a piece they lack is worth more to them."
after(H.Gap)
visitors.OnClientEvent:Fire({ kind = "offer", id = "o1", name = "Sofa", item = "sofa", price = 340, base = 260, who = "Collector", seconds = 30, rarity = "common" })
M.flush()
check("a visitor's offer (the Visitors remote): no hint (the players' is about players)", not SandboxHints.waiting(queue, "deal") and OfferCard.isOpen())
after(Config.PlayerTrade.CardArm + 0.05) -- (8.7 review: the card takes an answer only CardArm s after it showed)
named(OfferCard.card(), "Decline").Activated:Fire()
M.flush()
trade.OnClientEvent:Fire({ kind = "offer", id = "t1", name = "Gramophone", item = "gramophone", price = 1200, base = 800, who = "Ann", seconds = 45, rarity = "rare", player = true })
M.flush()
check("Ann's offer (the PlayerTrade remote): its card opens, the hint waits", OfferCard.isOpen() and SandboxHints.waiting(queue, "deal"))
after(H.Delay + 2)
check("… not while the offer card covers the screen", said(dealWords) == 0 and SandboxHints.waiting(queue, "deal") and Hints.window() == "OfferCard")
named(OfferCard.card(), "Decline").Activated:Fire()
M.flush()
after(H.Every)
check(`… answered: "{dealWords}"`, said(dealWords) == 1 and lastToast() == dealWords and SandboxHints.seen(queue, "deal"), lastToast())
trade.OnClientEvent:Fire({ kind = "offer", id = "t2", name = "Gramophone", item = "gramophone", price = 1300, base = 800, who = "Bob", seconds = 45, rarity = "rare", player = true })
M.flush()
check("… once (another offer: no hint)", not SandboxHints.waiting(queue, "deal"))
after(Config.PlayerTrade.CardArm + 0.05) -- (8.7 review: armed first)
OfferCard.close()
M.flush()
-- the trade's window covers the screen too (its composer)
local TradeUi = require("./TradeUi")
TradeUi.start()
trade.OnClientEvent:Fire({ kind = "compose", seller = 22, sellerName = "Ann", uid = "22-5", stand = 3, name = "Gramophone", item = "gramophone", rarity = "rare",
	condition = 0.92, value = 800, income = 6.4, isNew = true, money = 3400 })
M.flush()
check("the trade's window (TradeUi) covers the screen for the hints (and the guide's soft steps)", TradeUi.isOpen() and Hints.isCovered() and Hints.window() == "TradeUi",
	Hints.window())
TradeUi.close()
M.flush()
check("… shut: not", not Hints.isCovered())
after(10 * H.Gap)
check("nothing more waits", #queue.waiting == 0)

-- ── Where they show: Hud.toast's strip in Hud's column ──────────────────────
-- (client/Hud.luau's toast: its words 14 px, 340 px wide at most and wrapped, 14 px padding at its sides and 7 px over
-- and under; the column's scale; the toasts under the TASKS chip, the newest last, 8 px apart)
local WORDS_W, PAD_X, PAD_Y, LINE_H, GAP = 340, 14, 7, 18, 8
local FONT = M.Enum.Font.GothamMedium
local function wrap(text)
	local lines, line, widest = 0, "", 0
	for word in string.gmatch(text, "%S+") do
		local try = if line == "" then word else line .. " " .. word
		if line ~= "" and M.textWidth(try, 14, FONT) > WORDS_W then
			lines += 1
			widest = math.max(widest, M.textWidth(line, 14, FONT))
			line = word
		else
			line = try
		end
	end
	if line ~= "" then
		lines += 1
		widest = math.max(widest, M.textWidth(line, 14, FONT))
	end
	return lines, math.min(widest, WORDS_W)
end
local function strips(texts)
	local S = M.uiScale(M.topStack)
	local column = box(M.topStack)
	local y = math.max(box(SandboxHud.block()).y1, box(tasksChip).y1) + GAP * S
	local out = {}
	for _, text in texts do
		local lines, w = wrap(text)
		local h = (lines * LINE_H + 2 * PAD_Y) * S
		table.insert(out, { x0 = column.x0, y0 = y, x1 = column.x0 + (w + 2 * PAD_X) * S, y1 = y + h, lines = lines })
		y += h + GAP * S
	end
	return out
end
local function blocks(orders)
	local list = {}
	local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
	if M.touch then
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		for index, b in TouchLayout.buttons(cluster) do
			list[`a touch button {index}`] = b
		end
		list["the jump button"] = cluster.jump -- (the thumbstick's zone: below)
		list["the left column (the minimap)"] = M.leftColumn
	else
		list["the health row"] = box(groups.LeftStack)
		list["the key hints (9.0: no MOUSE [ALT])"] = box(groups.HudButtons)
	end
	list["the money block"] = box(SandboxHud.block())
	list["the TASKS chip"] = box(tasksChip)
	list["the move's panel"] = box(panel)
	if shown(strip) then
		list["Danny's status line"] = box(strip)
	end
	if orders then
		local line, button = DannyOrders.hint(), DannyOrders.button()
		if line and shown(line) then
			list["orders mode's line"] = box(line)
		end
		if button and shown(button) then
			list["the 📋 button"] = box(button)
		end
	end
	return list
end
local OLDER = "+3 pieces in your warehouse" -- (a toast before it, over it)
local SCREENS = {
	{ touch = true, w = 844, h = 354, label = "844 x 390" },
	{ touch = true, w = 667, h = 339, label = "667 x 375" },
	{ touch = false, w = 1280, h = 764, label = "1280 x 800" },
	{ touch = false, w = 1920, h = 1044, label = "1920 x 1080" },
}
for _, size in SCREENS do
	screen(size.touch, size.w, size.h)
	for _, device in (if size.touch then { "touch" } else { "keys", "pad" }) do
		setPad(device == "pad")
		for _, id in { "orders", "visit", "price", "deal" } do
			local orders = id == "orders"
			clipboard(orders) -- (orders mode's line and its 📋 button while it is out)
			local text = SandboxHints.text(id, device)
			local label = `{size.label}, {device}, {id}`
			check(`{label}: the words ({text})`, text ~= "" and (device ~= "touch" or string.find(text, "%(%u%)") == nil), text)
			local made = strips({ OLDER, text })
			local older, hint = made[1], made[2]
			check(`{label}: the toast on the screen ({hint.lines} lines)`, MoveLayout.inside(hint, M.width, M.height) and hint.lines <= 3, show(hint))
			check(`{label}: … under the toast before it, never on it`, hint.y0 >= older.y1 and not overlap(hint, older), `{show(hint)} / {show(older)}`)
			for name, other in blocks(orders) do
				check(`{label}: … clear of {name}`, not overlap(hint, other) and not overlap(older, other), `{show(hint)} on {show(other)}`)
			end
			if M.touch then
				-- (client/Hud.luau's column on a phone: every toast in it, the 8.3 ones and the toast before it too, starts
				-- beside the minimap, in the top right corner of TouchLayout's thumbstick zone (Hud keeps its column clear
				-- of the buttons, not of that zone); the hints' toasts stay out of where the stick rests, the zone's left
				-- two thirds under its top third)
				local thumb = TouchLayout.cluster(M.width, M.height, M.MUi.scaleFor(M.Vector2.new(M.width, M.height))).thumb
				local rest = { x0 = thumb.x0, y0 = thumb.y0 + (thumb.y1 - thumb.y0) / 3, x1 = thumb.x0 + (thumb.x1 - thumb.x0) * 2 / 3, y1 = thumb.y1 }
				check(`{label}: … clear of the thumbstick's resting place (its zone's lower two thirds, left two thirds)`, not overlap(hint, rest) and not overlap(older, rest),
					`{show(hint)} on {show(rest)}`)
			end
		end
	end
	setPad(false)
	clipboard(false)
end

check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL SANDBOX HINTS CHECKS PASSED")
