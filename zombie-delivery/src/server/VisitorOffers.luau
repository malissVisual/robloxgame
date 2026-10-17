--!strict
-- 8.3 SANDBOX, the visitors' offers (shared/Visitors.luau has the rules, Config.Visitors.Offer the numbers; the visitors
-- of server/Visitors.luau make them). A visitor at one of your pieces on show may offer to buy it: the server prices the
-- offer from the piece's market price now (CollectionRules.sell with your market: today's hot and cold kinds, your own
-- demand) × Visitors.offerPrice, keeps it open Expire s (one a player at most, Every s apart) and tells you: a Notice
-- (the toast "🤝 The collector offers $340 for your Gramophone") and the "Visitors" remote (the card,
-- client/OfferCard.luau). ACCEPT sells the piece at the offer (Collection.sellAt, the money's reason "VisitorOffer": the
-- market's demand weighs one more of its kind, what the stands earned up to then counts, onPaid "sale", the "sold"
-- toast) and counts the daily task "offer" (SandboxTasks.note). Every answer is checked: the offer still open (its
-- clock not run out), its id, the piece still yours and on the stand it was offered at; the price is always the
-- server's (the client sends only the id). The piece taken down, moved, sold or gone while the offer is open closes it
-- ("gone"); leaving closes it ("left"). Analytics: VisitorOffer (the offer's $, how it ended, the piece's rarity).
-- 10.4 (the warehouse in two, Config.Showroom): only a piece in the SHOWROOM gets an offer (a collection hall's piece
-- is not for sale), priced from its showroom price (× Collection.showFactor: SellBonus and the tree's Sales pitch); a
-- VIP buyer (the tree's VIP buyers, Config.Showroom.Vip) offers Vip.Pay more for a Rare or rarer piece.
--
--   VisitorOffers.ready(player) -> boolean        may a visitor offer now (a save, no offer open, Every s since the last)
--   VisitorOffers.make(player, uid, kind, roll?, token?) -> Offer?, why
--                                                 an offer for the player's piece `uid` on show (not broken), from a
--                                                 visitor of that kind (Config.Visitors.Kinds' id: its title, its pay);
--                                                 roll: the price's dice (0 … 1; nil: a random one); token: the
--                                                 visitor's (handed back to onClosed's listeners)
--   VisitorOffers.current(player) -> Offer?       the open offer (a copy)
--   VisitorOffers.answer(player, id, accept) -> money?, why   the remote's ACCEPT / DECLINE
--   VisitorOffers.close(player, how)              closes the open offer for the server's reason ("left": the visitor
--                                                 went; nothing paid)
--   VisitorOffers.tick()                          closes the offers whose clock ran out ("expired"; server/Visitors.luau's
--                                                 loop calls it every Config.Visitors.Tick s)
--   VisitorOffers.onClosed(fn)                    fn(player, offer, how, money?) how: "sold", "declined", "expired",
--                                                 "gone" or "left" (the visitor's answer, server/Visitors.luau)
--   VisitorOffers.start()                         the remote, the collection's changes, leaving
--
-- The "Visitors" remote (Config.Robust.Limits.Visitors requests a second; every input checked):
--   server → client  { kind = "offer", id, name, item, price, base, who, seconds, rarity, market }   an offer opened
--                    { kind = "closed", id, how, money? }                                           it closed
--   client → server  { kind = "accept", id } | { kind = "decline", id }

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.Visitors)
local CollectionRules = require(Shared.CollectionRules)
local Market = require(Shared.Market)
local PlayerData = require(script.Parent.PlayerData)
local Collection = require(script.Parent.Collection)
local SandboxTasks = require(script.Parent.SandboxTasks)

local VisitorOffers = {}

export type Offer = {
	id: string,
	uid: string,
	item: string,
	name: string,
	stand: number,
	price: number,
	base: number, -- the piece's market price when it was made
	who: string, -- the visitor's kind's title ("Collector")
	rarity: string,
	market: string?, -- "hot", "cold" or nil
	at: number, -- os.clock() it opened
	expires: number, -- os.clock() its clock runs out
	token: any, -- the visitor's (server/Visitors.luau)
}

local MAX_ID = 40

local remote = Net.get("Visitors")
local notice = Net.get("Notice")
local open: { [Player]: Offer } = {}
local lastAt: { [Player]: number } = {} -- os.clock() of the player's last offer
local closedTo: { (Player, Offer, string, number?) -> () } = {}
local counter = 0
local started = false

local function tune()
	return Config.Visitors.Offer
end

local function copy(offer: Offer): Offer
	return table.clone(offer)
end

-- The player's piece with this uid (a copy), nil for none.
local function pieceOf(player: Player, uid: string): CollectionRules.Entry?
	for _, entry in Collection.stock(player) do
		if entry.uid == uid then
			return entry
		end
	end
	return nil
end

-- Closes the player's open offer: the client hears, the listeners (the visitor) hear, analytics.
local function finish(player: Player, offer: Offer, how: string, money: number?)
	if open[player] == offer then
		open[player] = nil
	end
	if player.Parent then
		remote:FireClient(player, { kind = "closed", id = offer.id, how = how, money = money })
	end
	PlayerData.track("event", player, "VisitorOffer", offer.price, how, offer.rarity)
	for _, fn in closedTo do
		task.spawn(fn, player, copy(offer), how, money)
	end
end

-- ── The API ────────────────────────────────────────────────────────────────

function VisitorOffers.ready(player: Player): boolean
	if open[player] or not PlayerData.get(player) then
		return false
	end
	local last = lastAt[player]
	return last == nil or os.clock() - last >= tune().Every
end

function VisitorOffers.make(player: Player, uid: string, kindId: string, roll: number?, token: any?): (Offer?, string?)
	if not player.Parent or not PlayerData.get(player) then
		return nil, "Their save isn't loaded."
	end
	if open[player] then
		return nil, "An offer is open already."
	end
	if not VisitorOffers.ready(player) then
		return nil, "Too soon after the last offer."
	end
	local entry =if type(uid) == "string" and #uid <= MAX_ID then pieceOf(player, uid) else nil
	if not entry or entry.stand == nil then
		return nil, "That piece isn't on show."
	end
	if not CollectionRules.isShow(entry.stand) then
		return nil, "That piece is in the collection hall: not for sale." -- (10.4: the visitors buy only in the showroom)
	end
	if CollectionRules.broken(entry) then
		return nil, "Nobody buys a broken piece."
	end
	local market = Collection.market(player)
	-- (the market's price now: the hot and cold kinds, the demand; 10.4: × the showroom's, Collection.showFactor)
	local base = CollectionRules.sell(entry, market, Collection.showFactor(player))
	local kind = Rules.kind(kindId)
	local rarity = CollectionRules.pieceRarity(entry) -- (9.x loot: its own roll)
	local tag = Market.tag(market, entry.item)
	local rank = CollectionRules.tier(rarity).rank
	local price = Rules.offerPrice(base, rank, tag == "hot", if kind then kind.pay else 0, roll or math.random())
	if kind and kind.id == Config.Showroom.Vip.Kind and rank >= 3 then
		-- (10.4: a VIP buyer pays Vip.Pay over a usual offer for a Rare or rarer piece, past the usual top)
		local step = if price >= 1000 then 10 elseif price >= 100 then 5 else 1
		price = math.ceil(price * (1 + Config.Showroom.Vip.Pay) / step) * step
	end
	counter += 1
	local now = os.clock()
	local offer: Offer = {
		id = `o{counter}`,
		uid = entry.uid,
		item = entry.item,
		name = entry.name,
		stand = entry.stand :: number,
		price = price,
		base = base,
		who = if kind then kind.title else "Visitor",
		rarity = rarity,
		market = tag,
		at = now,
		expires = now + tune().Expire,
		token = token,
	}
	open[player] = offer
	lastAt[player] = now
	notice:FireClient(player, Rules.toast(offer.who, price, offer.name))
	remote:FireClient(player, {
		kind = "offer",
		id = offer.id,
		name = offer.name,
		item = offer.item,
		price = price,
		base = base,
		who = offer.who,
		seconds = tune().Expire,
		rarity = rarity,
		market = tag,
	})
	PlayerData.track("event", player, "VisitorOffer", price, "made", rarity)
	return copy(offer), nil
end

function VisitorOffers.current(player: Player): Offer?
	local offer = open[player]
	return if offer then copy(offer) else nil
end

function VisitorOffers.answer(player: Player, id: any, accept: boolean): (number?, string?)
	local offer = open[player]
	if not offer or type(id) ~= "string" or id ~= offer.id then
		return nil, "That offer isn't open any more."
	end
	if os.clock() > offer.expires then
		finish(player, offer, "expired")
		return nil, "Too late: that offer has run out."
	end
	if not accept then
		finish(player, offer, "declined")
		return nil, nil
	end
	local entry = pieceOf(player, offer.uid)
	if not entry or entry.stand ~= offer.stand then
		finish(player, offer, "gone")
		return nil, `Your {offer.name} isn't on show any more.`
	end
	open[player] = nil -- (closed before the sale: the collection's change it makes is not "gone")
	local money, why = Collection.sellAt(player, offer.uid, offer.price, "VisitorOffer")
	if not money then
		finish(player, offer, "gone")
		return nil, why
	end
	finish(player, offer, "sold", money)
	SandboxTasks.note(player, "offer", 1) -- (the daily task "Accept an offer from a visitor")
	return money, nil
end

function VisitorOffers.close(player: Player, how: string)
	local offer = open[player]
	if offer then
		finish(player, offer, how)
	end
end

function VisitorOffers.tick()
	local now = os.clock()
	local due: { Player } = {}
	for player, offer in open do
		if now > offer.expires then
			table.insert(due, player)
		end
	end
	for _, player in due do
		local offer = open[player]
		if offer then
			finish(player, offer, "expired")
		end
	end
end

function VisitorOffers.onClosed(fn: (Player, Offer, string, number?) -> ())
	table.insert(closedTo, fn)
end

-- ── The remote, the collection's changes, leaving ──────────────────────────

local function onRemote(player: Player, message: any)
	if not Net.limit(player, "Visitors", Config.Robust.Limits.Visitors) or type(message) ~= "table" then
		return
	end
	local kind = message.kind
	if kind ~= "accept" and kind ~= "decline" then
		return
	end
	local _, why = VisitorOffers.answer(player, message.id, kind == "accept")
	if why then
		notice:FireClient(player, why)
	end
end

-- The collection changed: the piece of the open offer still on its stand? Else the offer is gone.
local function onCollection(player: Player)
	local offer = open[player]
	if not offer then
		return
	end
	local entry = pieceOf(player, offer.uid)
	if not entry or entry.stand ~= offer.stand then
		finish(player, offer, "gone")
	end
end

local function left(player: Player)
	local offer = open[player]
	if offer then
		finish(player, offer, "left")
	end
	open[player] = nil
	lastAt[player] = nil
end

function VisitorOffers.start()
	if started then
		return
	end
	started = true
	remote.OnServerEvent:Connect(onRemote)
	Collection.onChanged(onCollection)
	Players.PlayerRemoving:Connect(left)
end

return VisitorOffers
