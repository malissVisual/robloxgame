-- 8.8 SANDBOX, the auction: the Auction House's window (the real client/AuctionUi.luau with client/CardKit.luau and the
-- real shared data: shared/AuctionRules.luau, Config.Auction) on sandbox_mock.luau's recorder, at 844 × 390 and
-- 667 × 375 (phones held sideways: 844 × 354 and 667 × 339 under Roblox's top bar, the touch layout), 1280 × 800 and
-- 1920 × 1080. Checked:
--   * nothing at all while Config.Auction.On is false (the default): no remote asked, no window, no prompt heard;
--   * on: the Auction remote asked for the state; the window only when opened (the desk's prompt, attribute
--     AuctionDesk: on CONSIGN; the server's "open");
--   * the live lot (a view from the remote): the piece (its picture in its rarity's colour, name, rarity and the day's
--     market, condition and $/min, "📖 New for your book!", the seller, its worth), the current price, the leading
--     bidder, the countdown (red in its last 10 s), BID +$250 · $7,500, the lots after it, the anti-snipe line and the
--     round's strip (the lots sold and their prices, this one, the ones to come); on each screen the card on
--     the screen, its pieces never on each other, the words that matter fitting, a phone's buttons a finger's size
--     (Ui.MinTouch, 44 px); BID's request ({ kind = "bid", lot, amount }) once for a double tap, "…" while it waits; the
--     stub: no answer, the request given up with a toast; you lead: YOU LEAD, "Leading: you" and no rebuild; the
--     money short: NEED $X (a tap only says so); your own piece: YOUR PIECE; the hammer: SOLD; no lot: CONSIGN A PIECE;
--   * the consign picker: only the pieces that may go (rare, epic, legendary, not broken), the best first, each tile in
--     the grid's width and a finger's size; PICK A PIECE ABOVE, a tile picked: CONSIGN <name> · opens at $X and its
--     request; a piece consigned: WITHDRAW and a tile only says so; the consignments closed; an empty stock;
--   * the results: a row a lot, yours marked, the words fitting;
--   * the building's sign and lot display painted from the view (only where the building stands);
--   * ✕, ESC, the gamepad's B, a tap beside it and the Roblox menu close it; the gamepad's selection inside; a resize;
--   * no warnings.
-- `luau auction.luau -a dump` prints the scenes as JSON instead (the shape sandbox_preview.mjs draws).
local dump = select(1, ...) == "dump"
local M = require("./sandbox_mock")
local Config = require("./Config")
local Rules = require("./AuctionRules")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local CardKit = require("./CardKit")

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
local function isRgb(c, want)
	return c ~= nil and math.floor(c.R * 255 + 0.5) == want[1] and math.floor(c.G * 255 + 0.5) == want[2] and math.floor(c.B * 255 + 0.5) == want[3]
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
-- The words that must fit whole (a name or a line may be cut with "…"; these never): every button's, the price, the
-- clock, the rarity, the fresh line, the leader, the facts, a tile's opening price, a result's price.
local WHOLE = { Price = true, Clock = true, Rarity = true, Fresh = true, Leader = true, Facts = true, Opens = true, PriceLabel = true, Title = true, Round = true, Empty = true }
local function badTexts(root)
	local bad = {}
	for _, object in all(root, function(o)
		return (o.ClassName == "TextLabel" or o.ClassName == "TextButton") and type(o.Text) == "string" and o.Text ~= "" and shown(o)
	end) do
		local cut = object.TextTruncate and object.TextTruncate.Name == "AtEnd"
		if not object.TextWrapped and (object.ClassName == "TextButton" or not cut or WHOLE[object.Name]) then
			local b = box(object)
			local need = M.textWidth(object.Text, (object.TextSize or 14) * M.scaleOf(object), object.Font)
			if need > b.x1 - b.x0 + 0.5 then
				table.insert(bad, `{object.Name} "{object.Text}" {math.floor(need)} > {math.floor(b.x1 - b.x0)}`)
			end
		end
	end
	return bad
end
-- The buttons a finger taps on a phone: each at least Ui.MinTouch (44) screen px both ways.
local function smallButtons(root)
	local small = {}
	for _, object in all(root, function(o)
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false and o.Name ~= "AuctionShade"
	end) do
		local b = box(object)
		if b.x1 - b.x0 < M.MUi.MinTouch - 0.01 or b.y1 - b.y0 < M.MUi.MinTouch - 0.01 then
			table.insert(small, `{object.Name} {math.floor(b.x1 - b.x0)}x{math.floor(b.y1 - b.y0)}`)
		end
	end
	return small
end
-- The card's own pieces (its direct children that draw): any two on each other?
local function clashes(card)
	local pieces = {}
	for _, child in card:GetChildren() do
		local class = child.ClassName
		if (class == "TextLabel" or class == "TextButton" or class == "Frame" or class == "ScrollingFrame") and shown(child) then
			table.insert(pieces, child)
		end
	end
	local out = {}
	for i = 1, #pieces do
		for j = i + 1, #pieces do
			local a, b = box(pieces[i]), box(pieces[j])
			local inA = { x0 = a.x0 + 0.5, y0 = a.y0 + 0.5, x1 = a.x1 - 0.5, y1 = a.y1 - 0.5 } -- (a shared edge is no overlap)
			if TouchLayout.overlap(inA, b) then
				table.insert(out, `{pieces[i].Name} {show(a)} on {pieces[j].Name} {show(b)}`)
			end
		end
	end
	return out
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
local SCREENS = { { true, 844, 354, "phone" }, { true, 667, 339, "small" }, { false, 1280, 764, "computer" }, { false, 1920, 1044, "big" } }

-- ── The preview's scenes (`-a dump`) ────────────────────────────────────────
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
		local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		table.insert(overlay, { kind = "stick", box = cluster.thumb })
		table.insert(overlay, { kind = "round", box = cluster.jump, label = "JUMP" })
		table.insert(overlay, { kind = "pill", box = cluster.sprint, label = "SPRINT" })
		table.insert(overlay, { kind = "minimap", box = M.leftColumn })
	end
	table.insert(scenes, { name = name, width = M.width, height = M.height + 36, inset = 36, touch = M.touch, overlay = overlay, tree = node(M.gui) })
end

-- ── The data ────────────────────────────────────────────────────────────────
-- (the server's clock in the consign window of a round far from 0)
local round = 1000000
M.now = Rules.startOf(round) + Rules.span() + Config.Auction.Results + 300
local stockList = {
	{ uid = "14-1", item = "ski_trophy", name = "Golden Ski Trophy", condition = 0.94, rarity = "legendary", income = 81.8, stand = 1 },
	{ uid = "14-2", item = "antique_vase", name = "Antique Vase", condition = 1, rarity = "epic", income = 30 },
	{ uid = "14-3", item = "jewellery_box", name = "Grandma's Jewellery Box", condition = 0.88, rarity = "rare", income = 13.4 },
	{ uid = "14-4", item = "sofa", name = "Sofa", condition = 1, rarity = "common", income = 0.6 },
	{ uid = "14-5", item = "old_globe", name = "Old Globe", condition = 1, rarity = "uncommon", income = 5.1 },
	{ uid = "14-6", item = "jukebox", name = "Jukebox", condition = 0.1, rarity = "epic", income = 0 },
	{ uid = "14-7", item = "piano", name = "Upright Piano", condition = 0.75, rarity = "rare", income = 7.2 },
}
local function liveView(fields)
	local lot = {
		id = 2, item = "trex_skull", name = "T. Rex Skull", rarity = "legendary", condition = 0.92, income = 96.6, worth = 6440, opening = 6500,
		price = 7250, next = 7500, step = 250, leader = "Lady Fairbanks", leaderMe = false, leaderNpc = true, endsAt = M.now + 32, seller = "Ann",
		mine = false, fresh = true, market = "hot",
	}
	for k, v in fields or {} do
		lot[k] = v
	end
	return {
		phase = "live", round = round, startsAt = M.now - 60, endsAt = M.now + 200, index = 2, count = 4, grand = false, lot = lot,
		upcoming = { { item = "oil_painting", name = "Oil Painting", rarity = "legendary" }, { item = "ski_trophy", name = "Golden Ski Trophy", rarity = "legendary" } },
		results = { { item = "gramophone", name = "Gramophone", rarity = "rare", price = 1900, winner = "Madame Duval", npc = true } }, -- (this round's so far)
	}
end
local consignView = { phase = "consign", round = round + 1, startsAt = M.now + 754, endsAt = M.now + 734, upcoming = {}, results = {}, grand = false }

-- ── Off: nothing ────────────────────────────────────────────────────────────
M.services.ProximityPromptService = { PromptTriggered = M.signal() }
local AuctionUi = require("./AuctionUi")
local toasts = M.toasts
AuctionUi.notify = function(text)
	table.insert(toasts, text)
end
screen(true, 844, 354)
check("Config.Auction.On is false by default", Config.Auction.On == false)
AuctionUi.start()
local desk = M.make("ProximityPrompt", { Name = "AuctionDeskPrompt" })
desk:SetAttribute("AuctionDesk", true)
M.services.ProximityPromptService.PromptTriggered:Fire(desk, M.player)
check("off: AuctionUi.start() does nothing: no remote asked, no request, the desk's prompt heard by nobody", M.remotes.Auction == nil and #sentOn("Auction") == 0 and not AuctionUi.isOpen())
AuctionUi.open()
check("off: even opened by hand, nothing is sent", #sentOn("Auction") == 0)
AuctionUi.close()

-- ── On ──────────────────────────────────────────────────────────────────────
Config.Auction.On = true
AuctionUi.start()
local remote = M.remotes.Auction
check("on: the Auction remote asked for the state", remote ~= nil and #sentOn("Auction") == 1 and sentOn("Auction")[1][1].kind == "state")
M.remotes.Collection.OnClientEvent:Fire({ kind = "state", stock = stockList, income = 120, stands = 4 })
M.remotes.State.OnClientEvent:Fire({ money = 9000 })
M.flush()
check("a state alone opens nothing", not AuctionUi.isOpen())
M.services.ProximityPromptService.PromptTriggered:Fire(desk, M.player)
local gui = M.gui:FindFirstChild("AuctionUi")
local function window()
	return named(gui, "Auction")
end
check("the desk's prompt (AuctionDesk) opens the window on CONSIGN, in its ScreenGui \"AuctionUi\", modal", AuctionUi.isOpen() and AuctionUi.view().tab == "consign" and gui ~= nil and window() ~= nil
	and named(gui, "AuctionShade").Modal == true)
check("…without the server's view: the schedule alone (the next auction's countdown)", string.find(named(window(), "Subtitle").Text, "^Next auction in ") ~= nil, named(window(), "Subtitle").Text)
AuctionUi.close()
local other = M.make("ProximityPrompt", { Name = "SomethingElse" })
M.services.ProximityPromptService.PromptTriggered:Fire(other, M.player)
check("another prompt opens nothing", not AuctionUi.isOpen())

local function cardChecks(label)
	local frame = window()
	local cardBox = box(frame)
	check(`{label}: the card on the screen`, inside(cardBox), show(cardBox))
	check(`{label}: …its pieces never on each other`, #clashes(frame) == 0, clashes(frame)[1])
	check(`{label}: …the words fit`, #badTexts(frame) == 0, badTexts(frame)[1])
	if M.touch then
		check(`{label}: …every button a finger's size (the tabs, BID / CONSIGN, the tiles, ✕)`, #smallButtons(frame) == 0, smallButtons(frame)[1])
	end
end

-- ── The live lot ────────────────────────────────────────────────────────────
remote.OnClientEvent:Fire({ kind = "state", view = liveView() })
M.flush()
for _, size in SCREENS do
	screen(size[1], size[2], size[3])
	AuctionUi.open("live")
	M.flush()
	local label = `LIVE {size[2]} x {size[3] + 36}`
	local frame = window()
	check(`{label}: the piece: its picture in its rarity's colour, name, LEGENDARY · 🔥 HOT, condition and $/min, fresh, the seller, its worth`,
		named(frame, "Emoji").Text == "🦖" and isRgb(named(frame, "RarityEdge").Color, Config.Collection.Tiers.legendary.color) and named(frame, "PieceName").Text == "T. Rex Skull"
		and named(frame, "Rarity").Text == "LEGENDARY · 🔥 HOT" and named(frame, "Facts").Text == "92% condition · +$97/min" and named(frame, "Fresh").Text == "📖 New for your book!"
		and named(frame, "Seller").Text == "From Ann" and named(frame, "Worth").Text == "Worth $6,440 · opened at $6,500", named(frame, "Facts").Text)
	check(`{label}: the price, the leader, the clock, BID +$250 · $7,500 (green), the lots after it, the round's line`,
		named(frame, "PriceLabel").Text == "CURRENT PRICE" and named(frame, "Price").Text == "$7,250" and named(frame, "Leader").Text == "Leading: Lady Fairbanks" and named(frame, "Clock").Text == "0:32"
		and named(frame, "Bid").Text == "BID +$250 · $7,500" and named(frame, "Bid").BackgroundColor3 == CardKit.Buttons.good.face
		and named(frame, "Upcoming").Text == "Next: 🎨 Oil Painting · ⛷️ Golden Ski Trophy" and string.find(named(frame, "Subtitle").Text, "LIVE · lot 2 of 4", 1, true) == 1, named(frame, "Bid").Text)
	check(`{label}: the anti-snipe line; the round's lots: LOT 1 sold for $1,900, LOT 2 now, LOT 3 and 4 to come`, named(frame, "Snipe").Text == "A bid in the last 8 s puts the clock back to 0:08"
		and named(named(frame, "Lot_1"), "What").Text == "✓ $1,900 · Gramophone" and named(named(frame, "Lot_2"), "What").Text == "● NOW · T. Rex Skull" and named(named(frame, "Lot_2"), "Now") ~= nil
		and named(named(frame, "Lot_3"), "What").Text == "🎨 Oil Painting" and named(named(frame, "Lot_4"), "Number").Text == "LOT 4" and named(frame, "Lot_5") == nil)
	cardChecks(label)
	scene(`lot-{size[4]}`)
	if size[4] ~= "big" then
		AuctionUi.close()
	end
end
-- (the big screen, open)
local frame = window()
M.gamepad = true
AuctionUi.close()
AuctionUi.open("live")
check("a gamepad: the selection lands on BID, kept inside the window (a selection group)", M.focus ~= nil and M.focus.Name == "Bid" and window().SelectionGroup == true, M.focus and M.focus.Name)
M.gamepad = false
frame = window()
local before = #sentOn("Auction")
press(named(frame, "Bid"))
press(named(frame, "Bid"))
local sent = sentOn("Auction")
check("BID: { kind = \"bid\", lot = 2, amount = 7500 } once for a double tap; the button waits (…)", #sent == before + 1 and sent[#sent][1].kind == "bid" and sent[#sent][1].lot == 2 and sent[#sent][1].amount == 7500
	and named(window(), "Bid").Text == "…")
-- the stub: nobody answers
AuctionUi.Wait = -1
local toastsBefore = #toasts
M.resume()
check("the stub: no answer, the request given up with a toast, BID live again", #toasts == toastsBefore + 1 and toasts[#toasts] == "The Auction House didn't answer: try again in a moment."
	and named(window(), "Bid").Text == "BID +$250 · $7,500", toasts[#toasts])
AuctionUi.Wait = 4
-- the server's answer: you lead (no rebuild)
frame = window()
remote.OnClientEvent:Fire({ kind = "state", view = liveView({ price = 7500, next = 7750, leader = "Courier", leaderMe = true, leaderNpc = false }) })
M.flush()
check("you lead: YOU LEAD (grey), \"Leading: you\" in green, the price; drawn in place (a tap is never lost)", window() == frame and named(frame, "Bid").Text == "YOU LEAD"
	and named(frame, "Bid").BackgroundColor3 == CardKit.Buttons.shut.face and named(frame, "Leader").Text == "Leading: you" and named(frame, "Leader").TextColor3 == CardKit.Color.money
	and named(frame, "Price").Text == "$7,500")
toastsBefore = #toasts
press(named(frame, "Bid"))
check("…a tap only says why", #toasts == toastsBefore + 1 and toasts[#toasts] == "You're the top bidder: wait for the hammer." and #sentOn("Auction") == #sent)
-- the last seconds
remote.OnClientEvent:Fire({ kind = "state", view = liveView({ endsAt = M.now + 8 }) })
M.flush()
check("the last 10 s: the clock red", named(window(), "Clock").Text == "0:08" and named(window(), "Clock").TextColor3 == M.MTheme.Contract.red)
M.remotes.State.OnClientEvent:Fire({ money = 7000 })
M.flush()
check("the money short: NEED $500 (grey)", named(window(), "Bid").Text == "NEED $500" and named(window(), "Bid").BackgroundColor3 == CardKit.Buttons.shut.face)
toastsBefore = #toasts
press(named(window(), "Bid"))
check("…a tap only says how much is missing", toasts[#toasts] == "You need $500 more to bid $7,500." and #sentOn("Auction") == #sent)
M.remotes.State.OnClientEvent:Fire({ money = 9000 })
remote.OnClientEvent:Fire({ kind = "state", view = liveView({ mine = true, seller = "Courier" }) })
M.flush()
check("your own piece: YOUR PIECE, \"Your piece\"", named(window(), "Bid").Text == "YOUR PIECE" and named(window(), "Seller").Text == "Your piece")
remote.OnClientEvent:Fire({ kind = "state", view = liveView({ endsAt = M.now - 1 }) })
M.flush()
check("the hammer: SOLD", named(window(), "Bid").Text == "SOLD" and named(window(), "Clock").Text == "0:00")
-- the building's sign and lot display, painted from the view
local world = M.make("Folder", { Name = "Sandbox" }, M.workspace)
local house = M.make("Model", { Name = "AuctionHouse" }, world)
local signWords = M.make("SurfaceGui", { Name = "Words" }, M.make("Part", { Name = "AuctionSign" }, house))
local screenWords = M.make("SurfaceGui", { Name = "Words" }, M.make("Part", { Name = "AuctionScreen" }, house))
for _, name in { "Title", "Next" } do
	M.make("TextLabel", { Name = name, Text = "" }, signWords)
end
for _, name in { "Title", "Piece", "Facts", "Price", "Leader", "Clock" } do
	M.make("TextLabel", { Name = name, Text = "" }, screenWords)
end
remote.OnClientEvent:Fire({ kind = "state", view = liveView() })
M.flush()
check("the building's sign: LIVE NOW · lot 2 of 4; its lot display: the lot, its facts, the price, the leader, the clock",
	named(signWords, "Next").Text == "LIVE NOW · lot 2 of 4" and named(screenWords, "Title").Text == "LOT 2 OF 4" and named(screenWords, "Piece").Text == "🦖 T. Rex Skull"
	and named(screenWords, "Facts").Text == "LEGENDARY · 92% · +$97/min" and named(screenWords, "Price").Text == "$7,250" and named(screenWords, "Leader").Text == "Lady Fairbanks leads"
	and named(screenWords, "Clock").Text == "0:32", named(screenWords, "Facts").Text)
-- no lot on the podium
remote.OnClientEvent:Fire({ kind = "state", view = consignView })
M.flush()
check("no lot: the building's display says so and counts down to the next auction", named(screenWords, "Piece").Text == "No lot on the podium" and named(screenWords, "Price").Text == ""
	and named(signWords, "Next").Text == "Next auction in 12:34 · consign a rare, epic or legendary piece", named(signWords, "Next").Text)
AuctionUi.close()
for _, size in SCREENS do
	screen(size[1], size[2], size[3])
	AuctionUi.open("live")
	local label = `LIVE, no lot {size[2]} x {size[3] + 36}`
	check(`{label}: "No lot on the podium", the round's line and CONSIGN A PIECE`, named(window(), "Empty").Text == "No lot on the podium"
		and named(window(), "Round").Text == "Next auction in 12:34 · consign a rare, epic or legendary piece" and named(window(), "GoConsign") ~= nil)
	cardChecks(label)
	AuctionUi.close()
end
AuctionUi.open("live")
press(named(window(), "GoConsign"))
check("CONSIGN A PIECE: the consign picker", AuctionUi.view().tab == "consign" and named(window(), "Grid") ~= nil)
AuctionUi.close()

-- ── The consign picker ──────────────────────────────────────────────────────
local function tiles()
	local grid = named(window(), "Grid")
	local out = {}
	for _, child in grid:GetChildren() do
		if string.sub(child.Name, 1, 5) == "Tile_" then
			table.insert(out, child)
		end
	end
	table.sort(out, function(a, b)
		return a.Position.Y.Offset < b.Position.Y.Offset or (a.Position.Y.Offset == b.Position.Y.Offset and a.Position.X.Offset < b.Position.X.Offset)
	end)
	return out
end
for _, size in SCREENS do
	screen(size[1], size[2], size[3])
	AuctionUi.open("consign")
	M.flush()
	local label = `CONSIGN {size[2]} x {size[3] + 36}`
	local list = tiles()
	local order = {}
	for _, t in list do
		table.insert(order, string.sub(t.Name, 6))
	end
	check(`{label}: only the pieces that may go (rare, epic, legendary, not broken), the best first`, table.concat(order, ",") == "14-1,14-2,14-3,14-7", table.concat(order, ","))
	local gridBox = box(named(window(), "Grid"))
	local fits = true
	for _, t in list do
		local b = box(t)
		fits = fits and b.x0 >= gridBox.x0 - 0.5 and b.x1 <= gridBox.x1 + 0.5
	end
	local last = list[#list]
	check(`{label}: …every tile in the grid's width, the canvas holds them all`, fits and last.Position.Y.Offset + last.Size.Y.Offset <= named(window(), "Grid").CanvasSize.Y.Offset + 0.5)
	check(`{label}: …a tile's words: the name, rarity and condition, $/min (on show), the opening price`, named(list[1], "ItemName").Text == "Golden Ski Trophy" and named(list[1], "Rarity").Text == "Legendary · 94%"
		and named(list[1], "Income").Text == "+$82/min · on show" and named(list[1], "Opens").Text == "Opens at $5,500" and named(list[3], "Opens").Text == `Opens at {Rules.money(Rules.opening(math.floor(1900 * 0.88 + 0.5)))}`)
	check(`{label}: the countdown and the rules; PICK A PIECE ABOVE (grey)`, string.find(named(window(), "Subtitle").Text, "Next auction in 12:34", 1, true) == 1
		and named(window(), "Info").Text == "One piece a round · rare, epic or legendary · the house keeps 8% of a sale" and named(window(), "Action").Text == "PICK A PIECE ABOVE"
		and named(window(), "Action").BackgroundColor3 == CardKit.Buttons.shut.face)
	cardChecks(label)
	if size[4] == "phone" then
		press(named(window(), "Tile_14-2"))
		check(`{label}: a tile tapped: picked (its frame lit), CONSIGN Antique Vase · opens at $3,000 (green)`, AuctionUi.view().selected == "14-2" and named(named(window(), "Tile_14-2"), "Edge").Thickness == 2
			and named(window(), "Action").Text == "CONSIGN Antique Vase · opens at $3,000" and named(window(), "Action").BackgroundColor3 == CardKit.Buttons.good.face)
		cardChecks(`{label}, picked`)
		scene("consign-phone-picked")
	end
	scene(`consign-{size[4]}`)
	AuctionUi.close()
end
screen(true, 844, 354)
AuctionUi.open("consign")
press(named(window(), "Tile_14-3"))
before = #sentOn("Auction")
press(named(window(), "Action"))
press(named(window(), "Action"))
sent = sentOn("Auction")
check("CONSIGN: { kind = \"consign\", uid = \"14-3\" } once; the button waits (…)", #sent == before + 1 and sent[#sent][1].kind == "consign" and sent[#sent][1].uid == "14-3" and named(window(), "Action").Text == "…")
local mineView = table.clone(consignView)
mineView.mine = { uid = "14-3", item = "jewellery_box", name = "Grandma's Jewellery Box", rarity = "rare", opening = 1700 }
remote.OnClientEvent:Fire({ kind = "state", view = mineView })
M.flush()
check("consigned (the server's view): WITHDRAW Grandma's Jewellery Box, the line says it goes under the hammer", named(window(), "Action").Text == "WITHDRAW Grandma's Jewellery Box"
	and named(window(), "Info").Text == "Your Grandma's Jewellery Box goes under the hammer · opens at $1,700")
cardChecks("CONSIGN with a piece consigned 844 x 390")
scene("consign-phone-mine")
toastsBefore = #toasts
press(named(window(), "Tile_14-2"))
check("…a tile tapped only says one piece a round", toasts[#toasts] == "One piece a round: withdraw your Grandma's Jewellery Box first." and AuctionUi.view().selected ~= "14-2")
press(named(window(), "Action"))
sent = sentOn("Auction")
check("WITHDRAW: { kind = \"withdraw\" }", sent[#sent][1].kind == "withdraw")
local closing = table.clone(consignView)
closing.phase = "closing"
closing.endsAt = closing.startsAt
remote.OnClientEvent:Fire({ kind = "state", view = closing })
M.flush()
press(named(window(), "Tile_14-2"))
check("the consignments closed: CONSIGNMENTS CLOSED (grey), a tap says why", named(window(), "Action").Text == "CONSIGNMENTS CLOSED")
toastsBefore = #toasts
press(named(window(), "Action"))
check("…\"Consignments are closed: the auction starts in a moment.\"", toasts[#toasts] == "Consignments are closed: the auction starts in a moment." and #sentOn("Auction") == #sent)
M.remotes.Collection.OnClientEvent:Fire({ kind = "state", stock = { stockList[4], stockList[5] }, income = 0, stands = 2 })
M.flush()
check("nothing to consign: the grid says what to bring home, NOTHING TO CONSIGN", named(named(window(), "Grid"), "Empty").Text == "No piece to consign yet: bring home a rare, epic or legendary piece."
	and named(window(), "Action").Text == "NOTHING TO CONSIGN")
cardChecks("CONSIGN, nothing to consign 844 x 390")
M.remotes.Collection.OnClientEvent:Fire({ kind = "state", stock = stockList, income = 120, stands = 4 })
AuctionUi.close()

-- ── The results ─────────────────────────────────────────────────────────────
local resultsView = {
	phase = "results", round = round, startsAt = M.now - 300, endsAt = M.now + 60, upcoming = {}, grand = false,
	results = {
		{ item = "jewellery_box", name = "Grandma's Jewellery Box", rarity = "rare", price = 1900, winner = "Madame Duval", npc = true, sold = true, won = false, fee = 152, net = 1748 },
		{ item = "antique_vase", name = "Antique Vase", rarity = "epic", price = 3400, winner = "Mr. Okonkwo", npc = true },
		{ item = "trex_skull", name = "T. Rex Skull", rarity = "legendary", price = 8250, winner = "Courier", npc = false, won = true },
		{ item = "oil_painting", name = "Oil Painting", rarity = "legendary", price = 7250, winner = "Ann", npc = false },
	},
}
remote.OnClientEvent:Fire({ kind = "state", view = resultsView })
for _, size in SCREENS do
	screen(size[1], size[2], size[3])
	AuctionUi.open()
	M.flush()
	local label = `RESULTS {size[2]} x {size[3] + 36}`
	local list = named(window(), "Results")
	check(`{label}: opened after a round: its results, a row a lot, yours marked (sold: what you got; bought)`, AuctionUi.view().tab == "results" and named(list, "Result_4") ~= nil
		and named(named(list, "Result_1"), "Outcome").Text == "Sold to Madame Duval for $1,900 · you got $1,748" and named(named(list, "Result_1"), "Yours") ~= nil
		and named(named(list, "Result_3"), "Outcome").Text == "You bought it for $8,250" and named(named(list, "Result_2"), "Yours") == nil and named(named(list, "Result_4"), "Price").Text == "$7,250")
	cardChecks(label)
	scene(`results-{size[4]}`)
	AuctionUi.close()
end

-- ── Closing, a resize ───────────────────────────────────────────────────────
screen(true, 844, 354)
AuctionUi.open("live")
key("Escape")
check("ESC closes it", not AuctionUi.isOpen() and named(gui, "Auction") == nil)
AuctionUi.open()
key("ButtonB")
check("the gamepad's B closes it", not AuctionUi.isOpen())
AuctionUi.open()
press(named(gui, "AuctionShade"))
check("a tap beside the card closes it", not AuctionUi.isOpen())
AuctionUi.open()
press(named(window(), "Close"))
check("✕ closes it", not AuctionUi.isOpen())
AuctionUi.open()
M.services.GuiService.MenuOpened:Fire()
check("the Roblox menu closes it", not AuctionUi.isOpen())
screen(false, 1280, 764)
AuctionUi.open("consign")
screen(true, 667, 339)
check("a resize to a phone while open: drawn again for it (a finger's buttons)", math.abs(M.uiScale(window()) - AuctionUi.layout(667, 339, true).scale) < 0.001 and #smallButtons(window()) == 0)
AuctionUi.close()

check("no warnings", #M.warnings == 0, M.warnings[1])
Config.Auction.On = false
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
	print("ALL AUCTION UI CHECKS PASSED")
end
