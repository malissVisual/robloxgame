-- 8.7 trading between players: the real client/TradeUi.luau (the offer composer, the FOR SALE price picker, the buy
-- question), the real client/OfferCard.luau with a player's offer, and the real client/WarehouseUi.luau's STOCK list 🏷,
-- on sandbox_mock.luau's recorder beside the real client/SandboxHud.luau, at 844 × 390 and 667 × 375 (phones held
-- sideways: 844 × 354 and 667 × 339 under Roblox's top bar, the touch layout), 1280 × 800 and 1920 × 1080. Checked:
--   * nothing when Config.Sandbox.On is false;
--   * the composer ({ kind = "compose" }): its words (the piece, its rarity, condition, value and $ a minute, "📖 New for
--     your book!", the price with its × and bounds, the presets, SEND $X, the seller's clock), on the screen, its pieces
--     never on each other, every word fitting, a finger's size on a phone; −, +, the presets (always within the
--     bounds); SEND's request (the seller, the uid, the stand, the price) and the window closed; SEND with less money
--     than the price: a toast, nothing sent; ESC, a tap beside it, ✕: closed, nothing sent;
--   * the price picker ({ kind = "pricing" }): "🏷 On sale now at $2,000", what you get after the fee, SET's request,
--     TAKE OFF SALE's (price 0), CANCEL without a sign (nothing sent);
--   * the buy question ({ kind = "confirm" }): the price big, its ×, your money, CANCEL first for the gamepad, BUY's
--     request (only the price shown);
--   * the offer card with a player's offer (the "PlayerTrade" remote: "🤝 PLAYER OFFER", "🧑 Ann offers", "Worth $800 ·
--     +50%"), on the screen clear of the money block and the touch controls, its words fitting, a finger's size;
--     ACCEPT / DECLINE back on the PlayerTrade remote (never the Visitors one); a visitor's offer queued behind it
--     ("(+1)"), shown when it is answered; the server's closed message; a player's offer on the Visitors remote ignored;
--   * 8.7 review, one offer a click: with two offers queued, a double click on ACCEPT (on DECLINE too), a double ESC and a
--     double B each answer the first only; the card is gone a moment (Config.PlayerTrade.CardGap), then shows the next
--     one with its buttons off (no answer) for CardArm s; then it takes one;
--   * the STOCK list's 🏷 on a piece on show (only there), inside its picture, clear of the ON STAND ribbon and the
--     market's tags, gold with the price when it has a sign, a finger's size on a phone; a tap opens the price picker
--     for that piece (its value from the state), closing it goes back to the STOCK list;
--   * no warnings.
local M = require("./sandbox_mock")
local Config = require("./Config")
local TouchLayout = require("./TouchLayout")
local MoveLayout = require("./MoveLayout")
local Rules = require("./PlayerTradeRules")

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
local function press(object)
	object.Activated:Fire()
end
local UIS = M.services.UserInputService
local function key(code)
	UIS.InputBegan:Fire({ KeyCode = M.Enum.KeyCode[code], UserInputType = M.Enum.UserInputType.Keyboard, Position = M.Vector3.new(0, 0, 0) }, false)
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
		if not object.TextWrapped then
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
		return o.ClassName == "TextButton" and shown(o) and o.Selectable ~= false and o.Name ~= "TradeShade" and o.Name ~= "WarehouseShade"
	end) do
		local b = box(object)
		if b.x1 - b.x0 < 44 - 0.01 or b.y1 - b.y0 < 44 - 0.01 then
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
		if (class == "TextLabel" or class == "TextButton" or class == "Frame") and shown(child) then
			table.insert(pieces, child)
		end
	end
	local out = {}
	for i = 1, #pieces do
		for j = i + 1, #pieces do
			local a, b = box(pieces[i]), box(pieces[j])
			local inA = { x0 = a.x0 + 0.5, y0 = a.y0 + 0.5, x1 = a.x1 - 0.5, y1 = a.y1 - 0.5 } -- (a shared edge is no overlap)
			if overlap(inA, b) then
				table.insert(out, `{pieces[i].Name} {show(a)} on {pieces[j].Name} {show(b)}`)
			end
		end
	end
	return out
end

local camera = M.workspace.CurrentCamera
local function screen(touch, w, h)
	M.touch, M.width, M.height = touch, w, h
	M.placeHud()
	camera.ViewportSize = M.Vector2.new(w, h + 36)
	camera:GetPropertyChangedSignal("ViewportSize"):Fire()
	M.flush()
end
local SCREENS = {
	{ label = "844 x 390", touch = true, w = 844, h = 354 },
	{ label = "667 x 375", touch = true, w = 667, h = 339 },
	{ label = "1280 x 800", touch = false, w = 1280, h = 764 },
	{ label = "1920 x 1080", touch = false, w = 1920, h = 1044 },
}

-- ── Off: nothing ────────────────────────────────────────────────────────────
local TradeUi = require("./TradeUi")
local trade = M.Net.get("PlayerTrade")
screen(true, 844, 354)
Config.Sandbox.On = false
TradeUi.start()
local COMPOSE = { kind = "compose", seller = 22, sellerName = "Bob", uid = "22-5", stand = 3, name = "Gramophone", item = "gramophone", rarity = "rare",
	condition = 0.92, value = 800, income = 6.4, isNew = true, money = 3400 }
trade.OnClientEvent:Fire(COMPOSE)
check("Config.Sandbox.On false: TradeUi.start() does nothing (no window on a compose)", not TradeUi.isOpen() and M.gui:FindFirstChild("TradeUi") == nil)
Config.Sandbox.On = true

-- ── On ──────────────────────────────────────────────────────────────────────
local SandboxHud = require("./SandboxHud")
SandboxHud.start()
SandboxHud.setState({ money = 3400 })
M.flush()
TradeUi.start()
local opened = 0
TradeUi.onOpen = function()
	opened += 1
end
local function fire(message, extra)
	local m = table.clone(message)
	for k, v in extra or {} do
		m[k] = v
	end
	trade.OnClientEvent:Fire(m)
	M.flush()
end
local function card()
	local gui = M.gui:FindFirstChild("TradeUi")
	return gui and named(gui, "TradeCard")
end
local function text(name)
	local c = card()
	local found = c and named(c, name)
	return if found then found.Text else nil
end
local function layoutChecks(label)
	local c = card()
	check(`{label}: the card on the screen`, c ~= nil and inside(box(c)), c and show(box(c)))
	local clash = clashes(c)
	check(`{label}: … its pieces never on each other`, #clash == 0, clash[1])
	local bad = badTexts(c)
	check(`{label}: … every word fits`, #bad == 0, bad[1])
	if M.touch then
		local small = smallButtons(c)
		check(`{label}: … a finger's size (44 × 44 px) every button`, #small == 0, small[1])
	end
end
local function last(remote)
	local list = sentOn(remote)
	local entry = list[#list]
	return if entry then entry[1] else nil
end
-- 8.7 review: the offer card's CardArm s pass (it takes answers from then on)
local function arm()
	M.now += Config.PlayerTrade.CardArm
	M.resume()
end

for _, s in SCREENS do
	screen(s.touch, s.w, s.h)
	local L = s.label
	-- the composer
	local before = #sentOn("PlayerTrade")
	fire(COMPOSE)
	check(`{L}: the composer opens ("offer"), its onOpen runs`, TradeUi.isOpen() and TradeUi.showing() == "offer" and opened >= 1)
	check(`{L}: … "🤝 MAKE AN OFFER", Bob's stand, the piece, its facts, "📖 New for your book!"`, text("Title") == "🤝 MAKE AN OFFER" and text("Sub") == "Bob's warehouse · stand 3"
		and text("PieceName") == "Gramophone" and text("Facts") == "RARE · 92% · worth $800 · +$6.4/min" and text("Note") == "📖 New for your book!", `{text("Title")} | {text("Sub")} | {text("PieceName")} | {text("Note")}`)
	check(`{L}: … the price 1.5 × to start, its × and bounds, SEND, the seller's clock`, text("Price") == "$1,200" and text("Range") == "×1.5 · $800 – $8,000"
		and text("Send") == "SEND $1,200" and text("Foot") == "Bob has 45 s to answer." and TradeUi.price() == 1200, text("Range"))
	check(`{L}: … the presets 1×, 1.5×, 2×, 3×`, text("Preset_1") == "1×" and text("Preset_2") == "1.5×" and text("Preset_3") == "2×" and text("Preset_4") == "3×")
	layoutChecks(`{L} composer`)
	local drawn = box(card())
	print(string.format("      %s: the composer %.0f × %.0f px at scale %.2f", L, drawn.x1 - drawn.x0, drawn.y1 - drawn.y0, M.uiScale(card())))
	press(named(card(), "Plus"))
	check(`{L}: + a step ($1,300), − back`, TradeUi.price() == 1300 and text("Price") == "$1,300")
	press(named(card(), "Minus"))
	check(`{L}: … $1,200 again`, TradeUi.price() == 1200)
	press(named(card(), "Preset_1"))
	press(named(card(), "Minus"))
	check(`{L}: 1× and −: never under the value ($800)`, TradeUi.price() == 800 and text("Range") == "×1 · $800 – $8,000")
	press(named(card(), "Preset_4"))
	check(`{L}: 3×: $2,400`, TradeUi.price() == 2400 and text("Send") == "SEND $2,400")
	for _ = 1, 40 do
		press(named(card(), "Plus"))
	end
	check(`{L}: + many times: never over 10 × ($8,000); still more money than she has: SEND grey`, TradeUi.price() == 8000 and named(card(), "Send"):GetAttribute("Short") == true)
	layoutChecks(`{L} composer at $8,000`)
	local toasts = #M.toasts
	press(named(card(), "Send"))
	check(`{L}: … SEND then: a toast, nothing sent, still open`, #sentOn("PlayerTrade") == before and #M.toasts == toasts + 1 and TradeUi.isOpen(), M.toasts[#M.toasts])
	press(named(card(), "Preset_2"))
	press(named(card(), "Send"))
	local sent = last("PlayerTrade")
	check(`{L}: SEND: \{ kind = "offer", seller, uid, stand, price \}, closed`, #sentOn("PlayerTrade") == before + 1 and sent.kind == "offer" and sent.seller == 22 and sent.uid == "22-5"
		and sent.stand == 3 and sent.price == 1200 and not TradeUi.isOpen() and card() == nil)
	-- without the book's line, a sign on it
	fire(COMPOSE, { isNew = false, sale = 2000 })
	check(`{L}: a piece with a sign: "🏷 For sale at $2,000", the price starts there`, text("Note") == "🏷 For sale at $2,000" and TradeUi.price() == 2000)
	layoutChecks(`{L} composer, a sign`)
	fire(COMPOSE, { isNew = false })
	check(`{L}: nothing to note: no note line`, text("Note") == nil)
	layoutChecks(`{L} composer, no note`)
	key("Escape")
	check(`{L}: ESC closes it, nothing sent`, not TradeUi.isOpen() and #sentOn("PlayerTrade") == before + 1)
	fire(COMPOSE)
	press(M.gui:FindFirstChild("TradeUi"):FindFirstChild("TradeShade"))
	check(`{L}: a tap beside it closes it, nothing sent`, not TradeUi.isOpen() and #sentOn("PlayerTrade") == before + 1)
	fire(COMPOSE)
	press(named(card(), "Close"))
	check(`{L}: ✕ closes it, nothing sent`, not TradeUi.isOpen() and #sentOn("PlayerTrade") == before + 1)
	-- the price picker
	local PRICING = { kind = "pricing", seller = 1, sellerName = "Me", uid = "1-7", stand = 2, name = "Gramophone", item = "gramophone", rarity = "rare",
		condition = 0.92, value = 800, income = 6.4, sale = 2000 }
	fire(PRICING)
	check(`{L}: the price picker ("price"): "🏷 FOR SALE SIGN", your stand, "🏷 On sale now at $2,000", what you get`, TradeUi.showing() == "price" and text("Title") == "🏷 FOR SALE SIGN"
		and text("Sub") == "Your warehouse · stand 2" and text("Note") == "🏷 On sale now at $2,000" and text("Foot") == "You get $1,840 after the 8% Deliveros fee."
		and text("TakeOff") == "TAKE OFF SALE" and text("SetPrice") == "SET $2,000", text("Foot"))
	layoutChecks(`{L} price picker`)
	press(named(card(), "Plus"))
	press(named(card(), "SetPrice"))
	sent = last("PlayerTrade")
	check(`{L}: SET: \{ kind = "price", uid, price \}`, sent.kind == "price" and sent.uid == "1-7" and sent.price == 2200 and not TradeUi.isOpen(), sent.price)
	fire(PRICING)
	press(named(card(), "TakeOff"))
	sent = last("PlayerTrade")
	check(`{L}: TAKE OFF SALE: price 0`, sent.kind == "price" and sent.uid == "1-7" and sent.price == 0 and not TradeUi.isOpen())
	local count = #sentOn("PlayerTrade")
	fire(PRICING, { sale = false })
	check(`{L}: no sign yet: CANCEL, the price 2 × to start`, text("Cancel") == "CANCEL" and text("Note") == nil and TradeUi.price() == 1600)
	layoutChecks(`{L} price picker, no sign`)
	press(named(card(), "Cancel"))
	check(`{L}: CANCEL: nothing sent`, not TradeUi.isOpen() and #sentOn("PlayerTrade") == count)
	-- the buy question
	local CONFIRM = table.clone(COMPOSE)
	CONFIRM.kind, CONFIRM.price, CONFIRM.sale = "confirm", 2000, 2000
	M.gamepad = true
	fire(CONFIRM)
	check(`{L}: the buy question ("buy"): "🛒 BUY", the price big, its ×, your money, CANCEL and BUY`, TradeUi.showing() == "buy" and text("Title") == "🛒 BUY"
		and text("Price") == "$2,000" and text("Range") == "×2.5 its value" and text("Foot") == "You have $3,400 · it goes into your stock." and text("Cancel") == "CANCEL"
		and text("Buy") == "BUY $2,000" and named(card(), "Minus") == nil and named(card(), "Preset_1") == nil, text("Range"))
	check(`{L}: … the gamepad's selection on CANCEL (a buy never on A by habit)`, M.focus == named(card(), "Cancel"))
	M.gamepad = false
	layoutChecks(`{L} buy question`)
	press(named(card(), "Buy"))
	sent = last("PlayerTrade")
	check(`{L}: BUY: \{ kind = "buy", seller, uid, stand, price \} (the price shown)`, sent.kind == "buy" and sent.seller == 22 and sent.uid == "22-5" and sent.stand == 3
		and sent.price == 2000 and not TradeUi.isOpen())
end

-- junk from the remote
local junkCount = #sentOn("PlayerTrade")
for _, junk in { "compose", { kind = "compose" }, { kind = "confirm", uid = "x" }, { kind = "news", text = "x" }, { kind = "result", how = "sold" } } do
	trade.OnClientEvent:Fire(junk)
end
M.flush()
check("junk from the remote: no window, nothing sent", not TradeUi.isOpen() and #sentOn("PlayerTrade") == junkCount)

-- ── The offer card with a player's offer ──────────────────────────────────
local OfferCard = require("./OfferCard")
OfferCard.start()
OfferCard.covered = function()
	return false
end
local visitors = M.Net.get("Visitors")
local PLAYER_OFFER = { kind = "offer", id = "t1", name = "Gramophone", item = "gramophone", price = 1200, base = 800, who = "Ann", seconds = 45, rarity = "rare", player = true }
for _, s in SCREENS do
	screen(s.touch, s.w, s.h)
	local L = s.label
	fire(PLAYER_OFFER)
	local c = OfferCard.card()
	check(`{L}: a player's offer: the card ("🤝 PLAYER OFFER", "🧑 Ann offers", "$1,200", "for your Gramophone", "Worth $800 · +50%")`, OfferCard.isOpen()
		and named(c, "Title").Text == "🤝 PLAYER OFFER" and named(c, "Who").Text == "🧑 Ann offers" and named(c, "Price").Text == "$1,200"
		and named(c, "Item").Text == "for your Gramophone" and named(c, "Market").Text == "Worth $800 · +50%", named(c, "Market").Text)
	local b = box(c)
	check(`{L}: … on the screen, clear of the money block`, inside(b) and not overlap(b, box(SandboxHud.block())), show(b))
	if M.touch then
		local S = M.MUi.scaleFor(M.Vector2.new(M.width, M.height))
		local cluster = TouchLayout.cluster(M.width, M.height, S)
		local clear = not overlap(b, cluster.thumb) and not overlap(b, cluster.jump)
		for _, button in TouchLayout.buttons(cluster) do
			clear = clear and not overlap(b, button)
		end
		check(`{L}: … clear of the touch controls; a finger's size`, clear and #smallButtons(c) == 0, smallButtons(c)[1])
	end
	check(`{L}: … its words fit`, #badTexts(c) == 0, badTexts(c)[1])
	local visitorsBefore = #sentOn("Visitors")
	arm()
	press(named(c, "Accept"))
	local answer = last("PlayerTrade")
	check(`{L}: ACCEPT: \{ kind = "answer", id, accept = true \} on the PlayerTrade remote, nothing on the Visitors one`, answer.kind == "answer" and answer.id == "t1"
		and answer.accept == true and #sentOn("Visitors") == visitorsBefore and not OfferCard.isOpen())
end
-- a queue: a player's offer, a visitor's behind it
fire(PLAYER_OFFER, { id = "t2", who = "Cid" })
visitors.OnClientEvent:Fire({ kind = "offer", id = "o1", name = "Sofa", item = "sofa", price = 340, base = 260, who = "Collector", seconds = 30, rarity = "common" })
M.flush()
local c = OfferCard.card()
check("a visitor's offer behind a player's: the player's shown, \"(+1)\" in its title", OfferCard.isOpen() and named(c, "Title").Text == "🤝 PLAYER OFFER (+1)"
	and named(c, "Who").Text == "🧑 Cid offers", named(c, "Title").Text)
arm()
press(named(c, "Decline"))
local answer = last("PlayerTrade")
M.now += Config.PlayerTrade.CardGap
M.resume()
check("… DECLINE answers the player's (accept false); the visitor's comes next", answer.kind == "answer" and answer.id == "t2" and answer.accept == false
	and OfferCard.isOpen() and named(c, "Title").Text == "🤝 OFFER" and named(c, "Who").Text == "The collector offers")
arm()
press(named(c, "Decline"))
local visitorAnswer = last("Visitors")
check("… and its DECLINE goes to the Visitors remote", visitorAnswer.kind == "decline" and visitorAnswer.id == "o1" and not OfferCard.isOpen())
fire(PLAYER_OFFER, { id = "t3" })
fire({ kind = "closed", id = "t3", how = "gone" })
check("the server's closed message for a player's offer: the card goes, nothing sent", not OfferCard.isOpen() and OfferCard.pending() == nil)
visitors.OnClientEvent:Fire(PLAYER_OFFER)
M.flush()
check("a player's offer on the Visitors remote: ignored", not OfferCard.isOpen())

-- 8.7 review: one offer a click. Ann's and Cid's offers queued; each way of answering twice in a row answers Ann's only.
local ARM, GAP = Config.PlayerTrade.CardArm, Config.PlayerTrade.CardGap
local function answers(): { any }
	local out = {}
	for _, args in sentOn("PlayerTrade") do
		if type(args[1]) == "table" and args[1].kind == "answer" then
			table.insert(out, args[1])
		end
	end
	return out
end
local function lit(button): boolean
	return button:GetAttribute("Armed") == true and button.TextTransparency == 0
end
for _, way in { "accept", "decline", "escape", "gamepad" } do
	screen(true, 844, 354)
	fire(PLAYER_OFFER, { id = `{way}1`, who = "Ann" })
	fire(PLAYER_OFFER, { id = `{way}2`, who = "Cid", price = 900 })
	c = OfferCard.card()
	local before = #answers()
	local function act() -- (one answer this way: a click, ESC (client/Main.client.luau closes the windows), the gamepad's B)
		if way == "accept" then
			press(named(c, "Accept"))
		elseif way == "decline" then
			press(named(c, "Decline"))
		elseif way == "escape" then
			OfferCard.close()
		else
			key("ButtonB")
		end
	end
	check(`{way}: just opened: its buttons off (not Armed, faded)`, OfferCard.isOpen() and named(c, "Who").Text == "🧑 Ann offers"
		and named(c, "Accept"):GetAttribute("Armed") == false and named(c, "Decline"):GetAttribute("Armed") == false and not lit(named(c, "Accept")))
	act()
	check(`{way}: … an answer at once does nothing (nothing sent, Ann's offer still shown)`, #answers() == before and OfferCard.isOpen() and OfferCard.pending().id == `{way}1`)
	arm()
	check(`{way}: CardArm s on: its buttons lit`, lit(named(c, "Accept")) and lit(named(c, "Decline")))
	act()
	act()
	local afterTwice = #answers()
	local list = answers()
	check(`{way}: twice in a row answers Ann's offer only ({if way == "accept" then "accept" else "decline"}), Cid's still waits`, afterTwice == before + 1
		and list[#list].id == `{way}1` and list[#list].accept == (way == "accept") and OfferCard.pending() ~= nil and OfferCard.pending().id == `{way}2`, afterTwice - before)
	check(`{way}: … the card gone a moment, Cid's offer waiting (not at the same spot at once)`, not OfferCard.isOpen() and not c.Visible and OfferCard.pending() ~= nil
		and OfferCard.pending().id == `{way}2`)
	M.resume()
	check(`{way}: … still gone before CardGap s`, not OfferCard.isOpen() and OfferCard.pending() ~= nil and OfferCard.pending().id == `{way}2`)
	M.now += GAP
	M.resume()
	check(`{way}: CardGap s on: Cid's offer on the card ("🧑 Cid offers", "$900"), its buttons off`, OfferCard.isOpen() and named(c, "Who").Text == "🧑 Cid offers"
		and named(c, "Price").Text == "$900" and named(c, "Accept"):GetAttribute("Armed") == false, named(c, "Who").Text)
	act()
	act()
	check(`{way}: … answers now: none (it only just showed)`, #answers() == before + 1 and OfferCard.isOpen() and OfferCard.pending().id == `{way}2`)
	M.now += ARM / 2
	M.resume()
	press(named(c, "Accept"))
	check(`{way}: … half of CardArm on: still none`, #answers() == before + 1 and OfferCard.isOpen())
	M.now += ARM / 2 + 0.01
	M.resume()
	press(named(c, "Accept"))
	list = answers()
	check(`{way}: … CardArm s on: ACCEPT answers Cid's (once): one answer an offer`, afterTwice == before + 1 and #list == before + 2 and list[#list].id == `{way}2`
		and list[#list].accept == true and not OfferCard.isOpen() and OfferCard.pending() == nil)
end

-- ── The STOCK list's 🏷 ─────────────────────────────────────────────────────
local WarehouseUi = require("./WarehouseUi")
WarehouseUi.start()
WarehouseUi.onOpen = function()
	TradeUi.close()
end
TradeUi.onOpen = function()
	WarehouseUi.close()
end
WarehouseUi.onPrice = TradeUi.openPrice
TradeUi.onBack = WarehouseUi.openStock
local collection = M.remotes.Collection
local MARKET = { day = 20372, hot = { "gramophone" }, cold = { "sofa" }, left = 3600, demand = { gramophone = { n = 1, sold = 2 } } }
local STOCK = {
	{ uid = "s1", item = "gramophone", variant = 1, condition = 0.92, name = "Gramophone", got = 1, stand = 12, rarity = "rare", income = 6.4, price = 120, base = 800, sale = 12000, market = "hot" },
	{ uid = "s2", item = "sofa", variant = 1, condition = 1, name = "Sofa", got = 2, stand = 3, rarity = "uncommon", income = 2.1, price = 80, base = 90 },
	{ uid = "s3", item = "piano", variant = 1, condition = 1, name = "Upright Piano", got = 3, rarity = "rare", income = 9.6, price = 144, base = 144 },
}
for _, s in SCREENS do
	screen(s.touch, s.w, s.h)
	local L = s.label
	collection.OnClientEvent:Fire({ kind = "state", stock = STOCK, income = 8.5, stands = 12, market = MARKET })
	M.flush()
	WarehouseUi.openStock()
	M.flush()
	local gui = M.gui:FindFirstChild("WarehouseUi")
	local onShow, plain, inStock = named(gui, "Tile_s1"), named(gui, "Tile_s2"), named(gui, "Tile_s3")
	local tag, untagged = named(onShow, "Price"), named(plain, "Price")
	check(`{L}: the STOCK list's 🏷 on the pieces on show only`, tag ~= nil and untagged ~= nil and named(inStock, "Price") == nil)
	local picture = box(named(onShow, "Picture"))
	local t = box(tag)
	check(`{L}: … inside the picture`, t.x0 >= picture.x0 - 0.5 and t.x1 <= picture.x1 + 0.5 and t.y0 >= picture.y0 - 0.5 and t.y1 <= picture.y1 + 0.5, `{show(t)} in {show(picture)}`)
	for _, name in { "OnStand", "MarketTag", "DemandTag" } do
		local other = named(onShow, name)
		check(`{L}: … clear of {name}`, other == nil or not overlap(t, box(other)), other and show(box(other)))
	end
	local gold = require("./CardKit").Color.gold
	check(`{L}: … with a sign: a gold 🏷, its price line "🏷 For sale $12,000" in gold; without: a grey 🏷, "Sell $80"`, tag:GetAttribute("Sale") == 12000 and tag.Text == "🏷"
		and tag.BackgroundColor3 == gold and named(onShow, "SellPrice").Text == "🏷 For sale $12,000" and named(onShow, "SellPrice").TextColor3 == gold
		and untagged.Text == "🏷" and untagged:GetAttribute("Sale") == nil and untagged.BackgroundColor3 ~= gold and named(plain, "SellPrice").Text == "Sell $80",
		named(onShow, "SellPrice").Text)
	check(`{L}: … its words fit (the sign's price uncut)`, #badTexts(onShow) == 0 and #badTexts(plain) == 0, badTexts(onShow)[1])
	if M.touch then
		check(`{L}: … a finger's size`, #smallButtons(onShow) == 0, smallButtons(onShow)[1])
	end
	press(tag)
	M.flush()
	check(`{L}: a tap: the price picker for that piece (its value from the state: $800; its sign $12,000), the STOCK list closed`, TradeUi.showing() == "price"
		and (TradeUi.piece() :: any).uid == "s1" and (TradeUi.piece() :: any).value == 800 and TradeUi.price() == 8000 and not WarehouseUi.isOpen())
	layoutChecks(`{L} the picker from the STOCK list`)
	local count = #sentOn("PlayerTrade")
	press(named(card(), "Close"))
	M.flush()
	check(`{L}: … ✕ goes back to the STOCK list (nothing sent)`, not TradeUi.isOpen() and WarehouseUi.showing() == "stock" and #sentOn("PlayerTrade") == count)
	press(named(M.gui:FindFirstChild("WarehouseUi"), "Tile_s2"):FindFirstChild("Picture"):FindFirstChild("Price"))
	M.flush()
	key("Escape")
	M.flush()
	check(`{L}: … ESC closes the picker without going back`, not TradeUi.isOpen() and not WarehouseUi.isOpen())
end

check("no warnings", #M.warnings == 0, M.warnings[1])
print("ALL TRADE CHECKS PASSED")
