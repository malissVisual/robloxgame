--!strict
-- 8.7 SANDBOX, trading between players (the owner: "I'd like customers to be players too … I want selling to make
-- sense"; Config.PlayerTrade's numbers, shared/PlayerTradeRules.luau's rules). The server decides everything: the
-- client only asks through the "PlayerTrade" remote and the stands' prompts (server/Warehouse.luau: Warehouse.onTrade,
-- set by server/SandboxBoot.luau to PlayerTrade.prompt).
--   * An offer: another player's "Make an offer" at one of your pieces on show sends them the composer
--     ({ kind = "compose" }: the piece, its value, its $ a minute in THEIR warehouse, whether it is new in THEIR book, the
--     bounds); its SEND makes the offer (PlayerTrade.offer): checked (both here with their saves, not yourself, a
--     warehouse of your own to put it in, room in your stock, the money, the piece still on that stand, a price within
--     the bounds, one open offer a buyer, PerSeller a seller), kept open Expire s, and shown to the seller: a Notice
--     ("🧑 Ann offers $1,200 for your Gramophone (worth $800)") and the offer card (client/OfferCard.luau: the same card
--     as a visitor's, { kind = "offer", player = true }). ACCEPT (PlayerTrade.answer) makes the deal; DECLINE, the
--     clock run out, the piece taken down, moved, sold or gone (Collection.onChanged: a level down too) and either of
--     them leaving close it ("declined", "expired", "gone", "left"; "failed" when the deal itself was refused at
--     ACCEPT: the buyer short of money, their stock full, no warehouse): the seller's card closes ({ kind = "closed" }),
--     the buyer hears ({ kind = "result" } and a Notice in words).
--   * A FOR SALE sign: the owner's "Set price" at a piece on show (or the STOCK list's 🏷: client/WarehouseUi.luau) opens
--     the price picker ({ kind = "pricing" }); its SET puts the price on the piece (PlayerTrade.setPrice →
--     Collection.setSale: within the bounds; 0 takes it off). Everybody else then has "Buy $X" there: the buy question
--     ({ kind = "confirm" }), then BUY (PlayerTrade.buy: only at the price the question showed; the owner may be away
--     on a move, only online: their plot exists only then).
--   * The deal (Collection.transfer, one step with no yield: every check again, then the money and the piece): the
--     piece into the buyer's stock (not on show), their collection book marks it found (CollectionBook.record), the
--     seller's stand free (their income counted at the old rates first); the price from the buyer ("PlayerBuy"), to the
--     seller ("PlayerSale") less the ZDC fee ("TradeFee": it disappears); a visitor's offer for that piece closed
--     ("gone": VisitorOffers.close) and every other player's offer for it ("gone"; its own buyer's quietly); both saved
--     soon (Collection.transfer); the toasts "🤝 Sold Gramophone to Ann for $1,200 (fee $96)" and "📦 Bought Gramophone
--     from Bob for $1,200"; the badge firstDeal for both (SandboxBadges.give: off while its id is 0); a big sale
--     (Config.PlayerTrade.BigSale) a chat line for the whole server ({ kind = "news" }: client/TradePrompts.luau).
--     Analytics: PlayerTrade on the buyer (the price; how: "made", "sold", "declined", "expired", "gone", "left",
--     "failed", "bought" (closed as its buyer bought the piece by its sign), "sign" (a sign bought); the piece's rarity).
--
--   PlayerTrade.prompt(by, owner, stand, action)    a stand's trade prompt: "offer" (compose), "buy" (askBuy), "price"
--                                                  (pricing: the owner's only)
--   PlayerTrade.compose(buyer, seller, stand) -> Piece?, why    the composer's piece sent to the buyer
--   PlayerTrade.offer(buyer, seller, uid, stand, price) -> Offer?, why   an offer made (a copy)
--   PlayerTrade.answer(seller, id, accept) -> money?, why       ACCEPT / DECLINE
--   PlayerTrade.pricing(owner, stand) -> why?                   the price picker sent to the owner
--   PlayerTrade.setPrice(owner, uid, price?) -> ok, why          the sign (nil or 0: off)
--   PlayerTrade.askBuy(buyer, seller, stand) -> why?            the buy question sent to the buyer
--   PlayerTrade.buy(buyer, seller, uid, stand, price) -> money?, why   a sign bought
--   PlayerTrade.open(player?) -> { Offer }                      the open offers (copies; to or from that player)
--   PlayerTrade.tick()                                          closes the offers whose clock ran out
--   PlayerTrade.start()                                         the remote, the collections' changes, leaving, the clock
--
-- The "PlayerTrade" remote (Config.Robust.Limits.PlayerTrade requests a second, a new offer TradeOffer a second on top;
-- every input checked): see shared/Net.luau.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.PlayerTradeRules)
local CollectionRules = require(Shared.CollectionRules)
local BookRules = require(Shared.CollectionBookRules)
local Market = require(Shared.Market)
local PlayerData = require(script.Parent.PlayerData)
local Collection = require(script.Parent.Collection)
local CollectionBook = require(script.Parent.CollectionBook)
local VisitorOffers = require(script.Parent.VisitorOffers)
local SandboxBadges = require(script.Parent.SandboxBadges)

local PlayerTrade = {}

export type Offer = {
	id: string,
	buyer: Player,
	seller: Player,
	uid: string,
	item: string,
	name: string,
	stand: number,
	price: number,
	value: number,
	rarity: string,
	at: number, -- os.clock() it opened
	expires: number, -- os.clock() its clock runs out
	closed: boolean,
}
type Entry = CollectionRules.Entry

local MAX_ID = 64

local remote = Net.get("PlayerTrade")
local notice = Net.get("Notice")
local offers: { [string]: Offer } = {}
local counter = 0
local started = false
local dealing: { seller: Player, uid: string }? = nil -- the deal in progress (its own collection changes close nothing)

local function tune()
	return Config.PlayerTrade
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function say(player: Player, text: string?)
	if text and text ~= "" and player.Parent then
		notice:FireClient(player, text)
	end
end

local function send(player: Player, message: { [string]: any })
	if player.Parent then
		remote:FireClient(player, message)
	end
end

-- The name the other player sees (the display name; the user name when there is none).
local function nameOf(player: Player): string
	local name: any = player.DisplayName
	return if type(name) == "string" and name ~= "" then name else player.Name
end

local function rarityOf(entry: { item: string }): string
	return CollectionRules.rarityOf(CollectionRules.defOf(entry.item))
end

-- The player's piece on stand `stand` (a copy), nil for none.
local function pieceOn(player: Player, stand: any): Entry?
	if not finite(stand) then
		return nil
	end
	for _, entry in Collection.stock(player) do
		if entry.stand == stand then
			return entry
		end
	end
	return nil
end

-- The player's piece with this uid (a copy), nil for none.
local function pieceOf(player: Player, uid: any): Entry?
	if type(uid) ~= "string" or #uid > MAX_ID then
		return nil
	end
	for _, entry in Collection.stock(player) do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end

-- The open offers, oldest first (a list: closing one while going through it is safe).
local function openList(): { Offer }
	local list: { Offer } = {}
	for _, offer in offers do
		table.insert(list, offer)
	end
	table.sort(list, function(a: Offer, b: Offer): boolean
		return a.at < b.at or (a.at == b.at and a.id < b.id)
	end)
	return list
end

local function offerFrom(buyer: Player): Offer?
	for _, offer in offers do
		if offer.buyer == buyer then
			return offer
		end
	end
	return nil
end

local function countTo(seller: Player): number
	local n = 0
	for _, offer in offers do
		if offer.seller == seller then
			n += 1
		end
	end
	return n
end

local function copy(offer: Offer): Offer
	return table.clone(offer)
end

-- What the buyer hears when their offer closes (the seller's card just closes; a deal's toasts are the deal's).
local function buyerWords(offer: Offer, how: string): string?
	local seller, name = nameOf(offer.seller), offer.name
	if how == "declined" then
		return `{seller} declined your offer for the {name}.`
	elseif how == "expired" then
		return `{seller} didn't answer: your offer for the {name} ran out.`
	elseif how == "gone" then
		return `Your offer is off: the {name} isn't on show at {seller}'s any more.`
	elseif how == "left" then
		return `{seller} left: your offer for the {name} is off.`
	end
	return nil
end

-- Closes an offer (once): the seller's card closes, the buyer hears (`text` in place of the usual words; "": nothing),
-- analytics.
local function finish(offer: Offer, how: string, money: number?, text: string?)
	if offer.closed then
		return
	end
	offer.closed = true
	if offers[offer.id] == offer then
		offers[offer.id] = nil
	end
	send(offer.seller, { kind = "closed", id = offer.id, how = how, money = money })
	send(offer.buyer, { kind = "result", id = offer.id, how = how })
	say(offer.buyer, text or buyerWords(offer, how))
	PlayerData.track("event", offer.buyer, "PlayerTrade", offer.price, how, offer.rarity)
end

-- Why `buyer` may not deal with `seller` now (nil: they may).
local function cannotBuy(buyer: Player, seller: Player?): string?
	if tune().On ~= true then
		return "Trading between players is off on this server."
	end
	if not seller or not seller.Parent then
		return "They aren't on this server any more."
	end
	if buyer == seller then
		return "That's your own piece."
	end
	if not PlayerData.get(buyer) then
		return "Your save isn't loaded yet."
	end
	if not PlayerData.get(seller) then
		return "Their save isn't loaded yet."
	end
	local housed = Collection.hasWarehouse
	if housed and not housed(buyer) then
		return "You need a warehouse of your own to buy: wait for a free plot."
	end
	if housed and not housed(seller) then
		return "That piece isn't on show."
	end
	return nil
end

-- Room in the buyer's stock?
local function stockFull(buyer: Player): string?
	if #Collection.stock(buyer) >= Config.Collection.MaxStock then
		return `Your warehouse is full ({Config.Collection.MaxStock} pieces): sell some first.`
	end
	return nil
end

local function moneyOf(player: Player): number
	local profile = PlayerData.get(player)
	return if profile then profile.money else 0
end

-- The piece as the client's windows show it (shared/PlayerTradeRules.luau readPiece): `viewer`'s $ a minute for it.
local function pieceMessage(kind: string, seller: Player, viewer: Player, entry: Entry): { [string]: any }
	local book = CollectionBook.book(viewer)
	return {
		kind = kind,
		seller = seller.UserId,
		sellerName = nameOf(seller),
		uid = entry.uid,
		stand = entry.stand,
		name = entry.name,
		item = entry.item,
		rarity = rarityOf(entry),
		condition = entry.condition,
		value = Rules.value(entry),
		income = math.floor(CollectionRules.income(entry, Collection.boost(viewer), Collection.market(viewer)) * 100 + 0.5) / 100,
		isNew = book ~= nil and book[entry.item] == nil and BookRules.inBook(entry.item),
		sale = entry.sale,
		money = moneyOf(viewer),
	}
end

-- ── The deal ───────────────────────────────────────────────────────────────

-- The deal itself (Collection.transfer: every check again, then the money and the piece, with no yield), and after it
-- the other offers and a visitor's offer for that piece, the book, the toasts, the badge, a big sale's chat line.
-- → the price paid, or nil and the refusal.
local function deal(buyer: Player, seller: Player, uid: string, stand: number, price: number): (number?, Collection.Refusal?)
	local fee = Rules.fee(price)
	dealing = { seller = seller, uid = uid }
	local ok, piece, refused = pcall(Collection.transfer, seller, buyer, uid, stand, price, fee)
	dealing = nil
	if not ok then
		warn(`[PlayerTrade] the deal failed: {piece}`)
		return nil, { code = "gone", text = "Something went wrong: nothing was traded." }
	end
	if not piece then
		return nil, refused
	end
	for _, other in openList() do
		if other.seller == seller and other.uid == uid then
			finish(other, if other.buyer == buyer then "bought" else "gone", nil, if other.buyer == buyer then nil else `{nameOf(seller)} sold the {other.name} to somebody else: your offer is off.`)
		end
	end
	local visitor = VisitorOffers.current(seller)
	if visitor and visitor.uid == uid then
		VisitorOffers.close(seller, "gone")
	end
	CollectionBook.record(buyer, piece.item, piece.condition)
	say(seller, Rules.soldToast(piece.name, nameOf(buyer), price, fee))
	say(buyer, Rules.boughtToast(piece.name, nameOf(seller), price))
	SandboxBadges.give(seller, "firstDeal")
	SandboxBadges.give(buyer, "firstDeal")
	if Rules.isBig(price) then
		remote:FireAllClients({ kind = "news", text = Rules.news(nameOf(seller), nameOf(buyer), piece.name, price) })
	end
	return price, nil
end

-- The words for each side when ACCEPT's deal is refused.
local function refusedWords(offer: Offer, refused: Collection.Refusal): (string, string)
	local buyer, name = nameOf(offer.buyer), offer.name
	local code = refused.code
	if code == "money" then
		return `{buyer} can't pay {Market.money(offer.price)} any more: the deal is off.`, `You couldn't pay {Market.money(offer.price)} for the {name}: the deal is off.`
	elseif code == "full" then
		return `{buyer}'s warehouse is full: the deal is off.`, refused.text
	elseif code == "house" then
		return `{buyer} has no warehouse of their own yet: the deal is off.`, refused.text
	elseif code == "left" then
		return `{buyer} left the server: the deal is off.`, refused.text
	end
	return `Your {name} isn't on show there any more: the deal is off.`, `The {name} isn't on show any more: the deal is off.`
end

-- ── The API ────────────────────────────────────────────────────────────────

function PlayerTrade.compose(buyer: Player, seller: Player, stand: number): ({ [string]: any }?, string?)
	local why = cannotBuy(buyer, seller)
	if why then
		return nil, why
	end
	local entry = pieceOn(seller, stand)
	if not entry then
		return nil, "Nothing is on show on this stand."
	end
	local mine = offerFrom(buyer)
	if mine then
		return nil, `Your offer for the {mine.name} is still open: wait for {nameOf(mine.seller)}'s answer.`
	end
	if countTo(seller) >= tune().PerSeller then
		return nil, `{nameOf(seller)} has {tune().PerSeller} offers open already: try again in a moment.`
	end
	why = stockFull(buyer)
	if why then
		return nil, why
	end
	local message = pieceMessage("compose", seller, buyer, entry)
	send(buyer, message)
	return message, nil
end

function PlayerTrade.offer(buyer: Player, seller: Player, uid: any, stand: any, price: any): (Offer?, string?)
	local why = cannotBuy(buyer, seller)
	if why then
		return nil, why
	end
	local entry = pieceOf(seller, uid)
	if not entry or entry.stand == nil or entry.stand ~= stand then
		return nil, "That piece isn't on show there any more."
	end
	local value = Rules.value(entry)
	local ok, bad = Rules.check(price, value)
	if not ok then
		return nil, bad
	end
	local mine = offerFrom(buyer)
	if mine then
		return nil, `Your offer for the {mine.name} is still open: wait for {nameOf(mine.seller)}'s answer.`
	end
	if countTo(seller) >= tune().PerSeller then
		return nil, `{nameOf(seller)} has {tune().PerSeller} offers open already: try again in a moment.`
	end
	why = stockFull(buyer)
	if why then
		return nil, why
	end
	if moneyOf(buyer) < price then
		return nil, `You have {Market.money(moneyOf(buyer))}: not enough for {Market.money(price)}.`
	end
	counter += 1
	local now = os.clock()
	local offer: Offer = {
		id = `t{counter}`,
		buyer = buyer,
		seller = seller,
		uid = entry.uid,
		item = entry.item,
		name = entry.name,
		stand = entry.stand :: number,
		price = price,
		value = value,
		rarity = rarityOf(entry),
		at = now,
		expires = now + tune().Expire,
		closed = false,
	}
	offers[offer.id] = offer
	say(seller, Rules.offerToast(nameOf(buyer), price, entry.name, value))
	send(seller, {
		kind = "offer",
		id = offer.id,
		name = offer.name,
		item = offer.item,
		price = price,
		base = value,
		who = nameOf(buyer),
		seconds = tune().Expire,
		rarity = offer.rarity,
		player = true,
	})
	send(buyer, { kind = "sent", id = offer.id, seconds = tune().Expire })
	say(buyer, `Offer sent: {Market.money(price)} for {nameOf(seller)}'s {entry.name}. They have {tune().Expire} s to answer.`)
	PlayerData.track("event", buyer, "PlayerTrade", price, "made", offer.rarity)
	return copy(offer), nil
end

function PlayerTrade.answer(seller: Player, id: any, accept: boolean): (number?, string?)
	local offer = if type(id) == "string" then offers[id] else nil
	if not offer or offer.seller ~= seller then
		return nil, "That offer isn't open any more."
	end
	if os.clock() > offer.expires then
		finish(offer, "expired")
		return nil, "Too late: that offer has run out."
	end
	if not accept then
		finish(offer, "declined")
		return nil, nil
	end
	offers[offer.id] = nil -- (out of the open ones before the deal: the collection's change it makes closes others only)
	local money, refused = deal(offer.buyer, seller, offer.uid, offer.stand, offer.price)
	if not money then
		local why = refused or { code = "gone", text = "" }
		local sellerText, buyerText = refusedWords(offer, why)
		finish(offer, if why.code == "left" then "left" elseif why.code == "gone" then "gone" else "failed", nil, buyerText)
		return nil, sellerText
	end
	finish(offer, "sold", money)
	return money, nil
end

function PlayerTrade.pricing(owner: Player, stand: number): string?
	if tune().On ~= true then
		return "Trading between players is off on this server."
	end
	if not PlayerData.get(owner) then
		return "Your save isn't loaded yet."
	end
	local entry = pieceOn(owner, stand)
	if not entry then
		return "Nothing is on show on this stand."
	end
	send(owner, pieceMessage("pricing", owner, owner, entry))
	return nil
end

function PlayerTrade.setPrice(owner: Player, uid: any, price: any): (boolean, string?)
	if tune().On ~= true then
		return false, "Trading between players is off on this server."
	end
	local entry = pieceOf(owner, uid)
	if not entry then
		return false, "That piece isn't in your stock."
	end
	if price == nil or price == 0 or price == false then
		if entry.sale == nil then
			return true, nil
		end
		local ok, why = Collection.setSale(owner, entry.uid, nil)
		if ok then
			say(owner, `Your {entry.name} is off sale.`)
		end
		return ok, why
	end
	if entry.stand == nil then
		return false, `Put your {entry.name} on show first: a FOR SALE sign stands on its stand.`
	end
	local value = Rules.value(entry)
	local fine, bad = Rules.check(price, value)
	if not fine then
		return false, bad
	end
	local ok, why = Collection.setSale(owner, entry.uid, price)
	if ok then
		say(owner, `🏷 FOR SALE: your {entry.name} at {Market.money(price)} (you get {Market.money(Rules.net(price))} after the ZDC fee).`)
	end
	return ok, why
end

function PlayerTrade.askBuy(buyer: Player, seller: Player, stand: number): string?
	local why = cannotBuy(buyer, seller)
	if why then
		return why
	end
	local entry = pieceOn(seller, stand)
	if not entry then
		return "Nothing is on show on this stand."
	end
	local price = entry.sale
	if price == nil then
		return "That piece isn't for sale: make an offer instead."
	end
	why = stockFull(buyer)
	if why then
		return why
	end
	if moneyOf(buyer) < price then
		return `You have {Market.money(moneyOf(buyer))}: not enough for {Market.money(price)}.`
	end
	local message = pieceMessage("confirm", seller, buyer, entry)
	message.price = price
	send(buyer, message)
	return nil
end

function PlayerTrade.buy(buyer: Player, seller: Player, uid: any, stand: any, price: any): (number?, string?)
	local why = cannotBuy(buyer, seller)
	if why then
		return nil, why
	end
	local entry = pieceOf(seller, uid)
	if not entry or entry.stand == nil or entry.stand ~= stand then
		return nil, "That piece isn't on show there any more."
	end
	local sale = entry.sale
	if sale == nil then
		return nil, `{nameOf(seller)} took the {entry.name} off sale.`
	end
	if not finite(price) or price ~= sale then
		return nil, `The price changed: the {entry.name} is {Market.money(sale)} now. Look again.`
	end
	if not Rules.check(sale, Rules.value(entry)) then
		return nil, "That price isn't allowed any more: the owner must price it again."
	end
	local money, refused = deal(buyer, seller, entry.uid, stand, sale)
	if not money then
		return nil, if refused then refused.text else "Nothing was traded."
	end
	PlayerData.track("event", buyer, "PlayerTrade", money, "sign", rarityOf(entry))
	return money, nil
end

function PlayerTrade.open(player: Player?): { Offer }
	local out: { Offer } = {}
	for _, offer in openList() do
		if player == nil or offer.buyer == player or offer.seller == player then
			table.insert(out, copy(offer))
		end
	end
	return out
end

function PlayerTrade.tick()
	local now = os.clock()
	for _, offer in openList() do
		if now > offer.expires then
			finish(offer, "expired")
		end
	end
end

function PlayerTrade.prompt(by: Player, owner: Player, stand: number, action: string)
	local why: string? = nil
	if action == "price" then
		if by ~= owner then
			why = `This is {nameOf(owner)}'s warehouse.`
		else
			why = PlayerTrade.pricing(by, stand)
		end
	elseif action == "offer" then
		local _, refused = PlayerTrade.compose(by, owner, stand)
		why = refused
	elseif action == "buy" then
		why = PlayerTrade.askBuy(by, owner, stand)
	end
	say(by, why)
end

-- ── The remote, the collections' changes, leaving ──────────────────────────

local function playerOf(userId: any): Player?
	if not finite(userId) then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player
		end
	end
	return nil
end

local function onRemote(player: Player, message: any)
	if not Net.limit(player, "PlayerTrade", Config.Robust.Limits.PlayerTrade) or type(message) ~= "table" then
		return
	end
	local kind = message.kind
	local why: string? = nil
	if kind == "offer" then
		if not Net.limit(player, "TradeOffer", Config.Robust.Limits.TradeOffer) then
			why = "One offer every few seconds: try again in a moment."
		else
			local seller = playerOf(message.seller)
			if seller then
				local _, refused = PlayerTrade.offer(player, seller, message.uid, message.stand, message.price)
				why = refused
			else
				why = "They aren't on this server any more."
			end
		end
	elseif kind == "answer" then
		local _, refused = PlayerTrade.answer(player, message.id, message.accept == true)
		why = refused
	elseif kind == "price" then
		local price = message.price
		if price ~= nil and not finite(price) then
			why = "That's no price."
		else
			local _, refused = PlayerTrade.setPrice(player, message.uid, price)
			why = refused
		end
	elseif kind == "buy" then
		local seller = playerOf(message.seller)
		if seller then
			local _, refused = PlayerTrade.buy(player, seller, message.uid, message.stand, message.price)
			why = refused
		else
			why = "They aren't on this server any more."
		end
	end
	say(player, why)
end

-- A seller's collection changed: an open offer whose piece is no longer on its stand is off.
local function onCollection(player: Player)
	local busy = dealing
	for _, offer in openList() do
		if offer.seller == player and not (busy and busy.seller == player and busy.uid == offer.uid) then
			local entry = pieceOf(player, offer.uid)
			if not entry or entry.stand ~= offer.stand then
				finish(offer, "gone")
			end
		end
	end
end

local function left(player: Player)
	for _, offer in openList() do
		if offer.buyer == player then
			finish(offer, "left", nil, "") -- (the buyer is going: nothing to tell them)
			say(offer.seller, `{nameOf(player)} left: their offer for your {offer.name} is off.`)
		elseif offer.seller == player then
			finish(offer, "left")
		end
	end
end

function PlayerTrade.start()
	if started then
		return
	end
	started = true
	remote.OnServerEvent:Connect(onRemote)
	Collection.onChanged(onCollection)
	Players.PlayerRemoving:Connect(left)
	task.spawn(function()
		while true do
			task.wait(tune().Tick)
			local ok, err = pcall(PlayerTrade.tick :: () -> ...any)
			if not ok then
				warn(`[PlayerTrade] the offers' clock failed: {err}`)
			end
		end
	end)
end

return PlayerTrade
