--!strict
-- 8.8 SANDBOX, the auction's rules (design/auction/PLAN.md; the owner: a piece on show earns $/min, so selling it to the
-- game, about a quarter of an hour of its income, is pointless). Pure (no Roblox at its top level; tests/auction_test.luau);
-- Config.Auction holds the numbers. This is the groundwork: nothing here pays or moves a piece. The server's part (the
-- round's loop, the atomic transfer of a piece between two players, the payments, the saves) comes next and uses these;
-- client/AuctionUi.luau shows the remote's view with them.
--   * The round: every Every s from 00:00 UTC + Offset (on every server at once), up to MaxLots lots one after the other,
--     the cheapest first. Before it each player consigns one piece (Rarities: rare, epic, legendary; never a broken
--     one) at the Auction House's desk; the consignments close Close s before the start.
--   * A lot: it opens at the piece's worth (value × condition × Reserve, rounded up to a step) and runs LotSeconds; a
--     bid with less than Snipe.Window s left puts the clock back to Window s (Snipe.Most s past its planned end at most);
--     Gap s between two lots.
--   * A bid: always the next step (Steps, by the price's band), never on your own piece, never while you lead, never
--     more than your money.
--   * The collectors (NPCs): Collectors.Count a lot, each with a max from the piece's worth × its rarity's × the day's
--     market (hot, cold) × a die in Spread; the keenest's at least the opening price, so every lot sells. One of them
--     answers a bid after a short wait (Delay), never past its max: a pure bidding model, seeded by the lot (the same
--     lot always plays the same).
--   * The settlement: the top bid whose bidder can pay wins (a collector always can); no bid at all: the keenest
--     collector at the opening price. The seller gets the price less the fee: the trades' own (8.7, Config.PlayerTrade.Fee
--     through shared/PlayerTradeRules.luau fee: one fee for both, rounded the same); the money's reasons AuctionSale,
--     AuctionFee and AuctionBuy (shared/AnalyticsPlan.luau).
--   * The Grand Auction (later): a daily round of the house's own lots (no seller): Config.Auction.Grand's hooks.
--
-- The round's schedule:
--   AuctionRules.roundOf(now) / startOf(round)   the round under way at `now` (its start ≤ now) / when round n starts
--   AuctionRules.span(lots?)                      s a round's lots take at most (MaxLots, every lot extended to the most)
--   AuctionRules.phase(now, endedAt?)             { name, round, startsAt, endsAt, left }: "live" (round `round`'s lots;
--                                                 endedAt: when its last lot really closed, else at most span), "results"
--                                                 (Results s after), "consign" (until Close s before the next start, the
--                                                 round it fills: `round`), "closing" (the last Close s)
-- A lot (Lot: the piece, its seller, the opening price, its seed, its clock, its bids):
--   AuctionRules.worthOf(entry)                   $ a piece is worth: its value × its condition (whole)
--   AuctionRules.reserve(worth) / opening(worth)  the lowest it sells for / the price it opens at (up to a step)
--   AuctionRules.step(price) / roundUp(amount)    a bid's step at that price / an amount up to a whole step
--   AuctionRules.lotOf(entry, seller, name, market?, seed)   a player's piece as a lot (CollectionRules Entry)
--   AuctionRules.houseLot(item, condition, seed, reserve?)   a lot of the house's own (no seller: the Grand Auction's)
--   AuctionRules.seedOf(round, index, key?)       a lot's seed (whole, ≥ 1)
--   AuctionRules.order(lots)                      the round's lots in order (the cheapest first), their ids 1 … n
--   AuctionRules.open(lot, now) / extend(lot, now) / left(lot, now) / isOpen(lot, now)   its clock
--   AuctionRules.leader(lot) / nextBid(lot)       the top bid (nil: none) / the amount the next bid must be
--   AuctionRules.canBid(lot, by, amount, money, now)   ok, why (a player's bid, checked)
--   AuctionRules.place(lot, bid)                  a bid on the lot (checked before: canBid, or a collector's npcNext)
-- The collectors:
--   AuctionRules.collectors(lot)                  { Collector } (name, max, index), seeded by the lot
--   AuctionRules.npcKey(index)                    a collector's bidder key ("npc:2")
--   AuctionRules.npcNext(lot, collectors)         the collector's bid that comes next if nobody else bids first: { index,
--                                                 name, amount, at } (nil: none of them goes on)
--   AuctionRules.play(lot, collectors, players?)  the lot played to its end (the tests' and the design's numbers): the
--                                                 collectors and players { by, name, max, delay } bidding by the rules
-- The settlement:
--   AuctionRules.feeRate() / fee(price)           the seller's fee's share (Config.PlayerTrade.Fee) / $ on a sale
--                                                 (PlayerTradeRules.fee: rounded, never over the price)
--   AuctionRules.settle(lot, collectors, canPay?) Result: who buys it, the price, the fee, the seller's net
--   AuctionRules.payments(result)                 { { userId, reason, delta } } the money it moves (the server's step)
--   AuctionRules.Reasons                          { Sale = "AuctionSale", Fee = "AuctionFee", Buy = "AuctionBuy" }
-- Who may consign what:
--   AuctionRules.allowed(rarity)                  one of Config.Auction.Rarities
--   AuctionRules.consignable(entry)               ok, why (the piece alone: its rarity, broken)
--   AuctionRules.canConsign(lots, userId, entry, phaseName)   ok, why (the round: only while "consign", one a player,
--                                                 MaxLots)
-- The Grand Auction (hooks):
--   AuctionRules.grandAt(now) / isGrand(startsAt)   the next Grand Auction's start (nil: Grand.On false) / is it one
-- The client's view (the "Auction" remote) and its words:
--   AuctionRules.lotView(lot, me?, fresh?)        what a client sees of a lot (LotView)
--   AuctionRules.resultView(lot, result, me?)     a settled lot's line (ResultView)
--   AuctionRules.readView(raw)                    the remote's view checked (nil for anything else; the client's)
--   AuctionRules.money(n) / clock(s) / rarityName(id) / percent(condition)   "$1,234" / "0:45" / "Legendary" / "92%"
--   AuctionRules.phaseLine(view, now)             "Next auction in 12:34 · consign a rare, epic or legendary piece"
--   AuctionRules.leaderLine(lot)                  "Leading: you", "Leading: Lady Fairbanks", "No bids yet"
--   AuctionRules.bidButton(lot, money, now)       the BID button's words, its face ("good" / "shut") and why not
--   AuctionRules.resultLine(result)               "Sold to Lady Fairbanks for $3,450"
--   AuctionRules.Fresh                            "📖 New for your book!"

local Config = require(script.Parent.Config)
local CollectionRules = require(script.Parent.CollectionRules)
local Market = require(script.Parent.Market)
local PlayerTradeRules = require(script.Parent.PlayerTradeRules) -- (8.7: the trades' fee, the auction's too)

local AuctionRules = {}

export type Bid = { by: number | string, name: string, npc: boolean, amount: number, at: number }
export type Lot = {
	id: number, -- its place in the round (1 … n: AuctionRules.order)
	uid: string?, -- the piece's uid in its seller's collection (nil: the house's own)
	item: string,
	name: string,
	variant: number,
	condition: number,
	rarity: string,
	worth: number, -- $: its value × its condition
	income: number, -- $ a minute on show (no boost; the day's market)
	market: string?, -- "hot", "cold" or nil
	seller: number?, -- the seller's UserId (nil: the house)
	sellerName: string,
	opening: number, -- $ it opens at (≥ its reserve)
	seed: number,
	opened: boolean, -- on the podium (AuctionRules.open)
	opensAt: number,
	endsAt: number,
	latest: number, -- the latest its clock may run to (the planned end + Snipe.Most)
	price: number, -- the top bid's amount (0: none)
	bids: { Bid },
}
export type Collector = { index: number, name: string, max: number }
export type NpcBid = { index: number, name: string, amount: number, at: number }
export type Player = { by: number, name: string, max: number, delay: number }
export type Result = {
	price: number,
	fee: number,
	net: number, -- the seller's: the price less the fee (a house lot's: 0)
	winner: string,
	npc: boolean,
	buyer: number?, -- the winner's UserId (nil: a collector)
	seller: number?,
	house: boolean,
}
export type Payment = { userId: number, reason: string, delta: number }
export type Phase = { name: string, round: number, startsAt: number, endsAt: number, left: number }
export type LotView = {
	id: number,
	item: string,
	name: string,
	rarity: string,
	condition: number,
	income: number,
	worth: number,
	opening: number,
	price: number, -- the top bid (0: none yet)
	next: number, -- the next bid's amount
	step: number,
	leader: string?, -- the top bidder's name (nil: none)
	leaderMe: boolean,
	leaderNpc: boolean,
	endsAt: number, -- (the server's clock: workspace:GetServerTimeNow())
	seller: string,
	mine: boolean, -- your own piece
	fresh: boolean, -- new for your collection book
	market: string?,
}
export type ResultView = {
	item: string,
	name: string,
	rarity: string,
	price: number,
	winner: string,
	npc: boolean,
	sold: boolean, -- yours, sold
	won: boolean, -- you bought it
	fee: number, -- (yours: the fee)
	net: number, -- (yours: what you got)
}
export type Piece = { uid: string, item: string, name: string, rarity: string, opening: number }
export type View = {
	phase: string, -- "consign" | "closing" | "live" | "results"
	round: number,
	startsAt: number, -- the round's start (the next one's while consigning)
	endsAt: number, -- the phase's end
	lot: LotView?, -- the lot on the podium (live)
	index: number, -- its place (1 … count)
	count: number, -- the round's lots
	upcoming: { { item: string, name: string, rarity: string } }, -- the lots after it
	mine: Piece?, -- your consigned piece (nil: none)
	results: { ResultView },
	grand: boolean,
}

AuctionRules.Reasons = { Sale = "AuctionSale", Fee = "AuctionFee", Buy = "AuctionBuy" }
AuctionRules.Fresh = "📖 New for your book!"

local MOD = 2147483647 -- the Park–Miller generator (2^31 − 1, × 48271): every product stays below 2^53
local MUL = 48271
local MAX_ID = 40 -- an id or a uid longer than this is no piece of ours
local MAX_NAME = 60
local MAX_LIST = 12 -- the lots and results a view holds at most
local MAX_MONEY = 1e12
local GUARD = 400 -- AuctionRules.play's bids at most (a lot always ends long before)
local EPS = 1e-6

local function tune()
	return Config.Auction
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function shortString(value: any, most: number): boolean
	return type(value) == "string" and #value >= 1 and #value <= most
end

-- A stream of numbers in [0, 1) from a seed (no Random: the same on every server and in the tests).
local function stream(seed: number): () -> number
	local state = math.floor(math.abs(if finite(seed) then seed else 1)) % (MOD - 1) + 1
	state = (state * MUL + tune().Salt % MOD) % MOD
	if state == 0 then
		state = 1
	end
	return function(): number
		state = (state * MUL) % MOD
		return (state - 1) / (MOD - 1)
	end
end

-- ── The round's schedule ────────────────────────────────────────────────────

function AuctionRules.roundOf(now: number): number
	return math.floor((now - tune().Offset) / tune().Every)
end

function AuctionRules.startOf(round: number): number
	return tune().Offset + round * tune().Every
end

function AuctionRules.span(lots: number?): number
	local n = math.clamp(math.floor(if finite(lots) then lots :: number else tune().MaxLots), 0, 100)
	if n <= 0 then
		return 0
	end
	return n * (tune().LotSeconds + tune().Snipe.Most) + (n - 1) * tune().Gap
end

function AuctionRules.phase(now: number, endedAt: number?): Phase
	local round = AuctionRules.roundOf(now)
	local start = AuctionRules.startOf(round)
	local liveEnd = start + AuctionRules.span()
	if finite(endedAt) and (endedAt :: number) >= start and (endedAt :: number) <= liveEnd then
		liveEnd = endedAt :: number
	end
	if now < liveEnd then
		return { name = "live", round = round, startsAt = start, endsAt = liveEnd, left = liveEnd - now }
	end
	-- (a round without lots, ended at its start: no results to show)
	local results = if liveEnd > start then liveEnd + tune().Results else liveEnd
	if now < results then
		return { name = "results", round = round, startsAt = start, endsAt = results, left = results - now }
	end
	local nextStart = AuctionRules.startOf(round + 1)
	local closes = nextStart - tune().Close
	if now < closes then
		return { name = "consign", round = round + 1, startsAt = nextStart, endsAt = closes, left = closes - now }
	end
	return { name = "closing", round = round + 1, startsAt = nextStart, endsAt = nextStart, left = nextStart - now }
end

-- ── A lot's price ───────────────────────────────────────────────────────────

function AuctionRules.worthOf(entry: { item: string, condition: number }): number
	local condition = if finite(entry.condition) then math.clamp(entry.condition, 0, 1) else 0
	return math.floor(CollectionRules.valueOf(entry) * condition + 0.5)
end

function AuctionRules.step(price: number): number
	local steps = tune().Steps
	local step = steps[1][2]
	for _, band in steps do
		if price >= band[1] then
			step = band[2]
		end
	end
	return step
end

-- An amount up to a whole step of its own band (never under 1).
function AuctionRules.roundUp(amount: number): number
	local value = math.max(1, if finite(amount) then amount else 1)
	local step = AuctionRules.step(value)
	return math.max(step, math.ceil(value / step - EPS) * step)
end

function AuctionRules.reserve(worth: number): number
	return math.max(1, math.ceil((if finite(worth) then worth else 0) * tune().Reserve - EPS))
end

function AuctionRules.opening(worth: number): number
	return AuctionRules.roundUp(AuctionRules.reserve(worth))
end

function AuctionRules.seedOf(round: number, index: number, key: string?): number
	local h = (math.floor(math.abs(if finite(round) then round else 0)) % MOD) * 31 % MOD
	h = (h + math.floor(math.abs(if finite(index) then index else 0))) % MOD
	local text = key or ""
	for i = 1, math.min(#text, MAX_ID) do
		h = (h * 131 + string.byte(text, i)) % MOD
	end
	return h + 1
end

local function newLot(item: string, name: string, variant: number, condition: number, worth: number, opening: number, seed: number): Lot
	return {
		id = 0,
		uid = nil,
		item = item,
		name = name,
		variant = variant,
		condition = condition,
		rarity = CollectionRules.rarityOf(CollectionRules.defOf(item)),
		worth = worth,
		income = 0,
		market = nil,
		seller = nil,
		sellerName = "The house",
		opening = opening,
		seed = seed,
		opened = false,
		opensAt = 0,
		endsAt = 0,
		latest = 0,
		price = 0,
		bids = {},
	}
end

function AuctionRules.lotOf(entry: CollectionRules.Entry, seller: number?, sellerName: string, market: Market.View?, seed: number): Lot
	local worth = AuctionRules.worthOf(entry)
	local lot = newLot(entry.item, entry.name, entry.variant, entry.condition, worth, AuctionRules.opening(worth), seed)
	lot.uid = entry.uid
	lot.seller = seller
	lot.sellerName = sellerName
	lot.income = math.floor(CollectionRules.income(entry, 1, market) * 100 + 0.5) / 100
	lot.market = Market.tag(market, entry.item)
	return lot
end

-- A lot of the house's own (the Grand Auction's: no seller, nobody paid), opening at `reserve` × its worth
-- (Config.Auction.Grand.Reserve without one).
function AuctionRules.houseLot(item: string, condition: number, seed: number, reserve: number?): Lot
	local def = CollectionRules.defOf(item)
	local clean = if finite(condition) then math.clamp(condition, 0, 1) else 1
	local worth = AuctionRules.worthOf({ item = item, condition = clean })
	local times = if finite(reserve) then reserve :: number else tune().Grand.Reserve
	local lot = newLot(item, if def then def.name else item, 1, clean, worth, AuctionRules.roundUp(math.max(1, worth * times)), seed)
	lot.income = math.floor(CollectionRules.income({ item = item, condition = clean }) * 100 + 0.5) / 100
	return lot
end

-- The round's lots in order: the cheapest first, the best last (a tie: the one consigned first stays first); their ids.
function AuctionRules.order(lots: { Lot }): { Lot }
	local list = table.clone(lots)
	local place: { [Lot]: number } = {}
	for index, lot in lots do
		place[lot] = index
	end
	table.sort(list, function(a: Lot, b: Lot): boolean
		if a.opening ~= b.opening then
			return a.opening < b.opening
		end
		return place[a] < place[b]
	end)
	for index, lot in list do
		lot.id = index
	end
	return list
end

-- ── A lot's clock and its bids ──────────────────────────────────────────────

function AuctionRules.open(lot: Lot, now: number)
	lot.opened = true
	lot.opensAt = now
	lot.endsAt = now + tune().LotSeconds
	lot.latest = lot.endsAt + tune().Snipe.Most
end

-- A bid at `now`: with less than Snipe.Window s left the clock goes back to Window s (never past `latest`). True when
-- it moved.
function AuctionRules.extend(lot: Lot, now: number): boolean
	local window = tune().Snipe.Window
	if not lot.opened or lot.endsAt - now >= window then
		return false
	end
	local later = math.min(now + window, lot.latest)
	if later > lot.endsAt then
		lot.endsAt = later
		return true
	end
	return false
end

function AuctionRules.left(lot: Lot, now: number): number
	return if lot.opened then math.max(0, lot.endsAt - now) else 0
end

function AuctionRules.isOpen(lot: Lot, now: number): boolean
	return lot.opened and now >= lot.opensAt and now < lot.endsAt
end

function AuctionRules.leader(lot: Lot): Bid?
	return lot.bids[#lot.bids]
end

function AuctionRules.nextBid(lot: Lot): number
	if #lot.bids == 0 then
		return lot.opening
	end
	return lot.price + AuctionRules.step(lot.price)
end

function AuctionRules.canBid(lot: Lot, by: number, amount: number, money: number, now: number): (boolean, string?)
	if not lot.opened or now < lot.opensAt then
		return false, "This lot isn't up yet."
	elseif now >= lot.endsAt then
		return false, "Too late: the hammer has fallen on this lot."
	elseif lot.seller ~= nil and by == lot.seller then
		return false, "You can't bid on your own piece."
	end
	local top = AuctionRules.leader(lot)
	if top and top.by == by then
		return false, "You're the top bidder already."
	end
	local want = AuctionRules.nextBid(lot)
	if not finite(amount) or amount ~= want then
		return false, `Someone bid first: the next bid is {AuctionRules.money(want)}.`
	end
	if not finite(money) or money < amount then
		return false, `You need {AuctionRules.money(amount - (if finite(money) then money else 0))} more.`
	end
	return true, nil
end

function AuctionRules.place(lot: Lot, bid: Bid)
	table.insert(lot.bids, bid)
	lot.price = bid.amount
	AuctionRules.extend(lot, bid.at)
end

-- ── The collectors ──────────────────────────────────────────────────────────

function AuctionRules.npcKey(index: number): string
	return `npc:{index}`
end

function AuctionRules.collectors(lot: Lot): { Collector }
	local C = tune().Collectors
	local roll = stream(lot.seed)
	local names = table.clone(C.Names)
	local keen = C.Rarity[lot.rarity] or 1
	local market = if lot.market == "hot" then C.Hot elseif lot.market == "cold" then C.Cold else 1
	local list: { Collector } = {}
	for index = 1, C.Count do
		local name = "A collector"
		if #names > 0 then
			name = table.remove(names, math.clamp(1 + math.floor(roll() * #names), 1, #names)) :: string
		end
		local spread = C.Spread[1] + (C.Spread[2] - C.Spread[1]) * roll()
		table.insert(list, { index = index, name = name, max = math.floor(lot.worth * keen * market * spread) })
	end
	-- the keenest goes at least to the opening price: every lot sells, never under its worth
	local top = list[1]
	for _, c in list do
		if c.max > top.max then
			top = c
		end
	end
	if top then
		top.max = math.max(top.max, lot.opening)
	end
	return list
end

local function keenest(collectors: { Collector }): Collector?
	local top: Collector? = nil
	for _, c in collectors do
		if top == nil or c.max > top.max then
			top = c
		end
	end
	return top
end

function AuctionRules.npcNext(lot: Lot, collectors: { Collector }): NpcBid?
	if not lot.opened then
		return nil
	end
	local amount = AuctionRules.nextBid(lot)
	local top = AuctionRules.leader(lot)
	local willing: { Collector } = {}
	for _, c in collectors do
		if c.max >= amount and not (top ~= nil and top.by == AuctionRules.npcKey(c.index)) then
			table.insert(willing, c)
		end
	end
	if #willing == 0 then
		return nil
	end
	local roll = stream(lot.seed + #lot.bids * 7919 + 17)
	local who = willing[math.clamp(1 + math.floor(roll() * #willing), 1, #willing)]
	local D = tune().Collectors.Delay
	local from = if top then top.at else lot.opensAt
	local at = math.min(from + D[1] + (D[2] - D[1]) * roll(), lot.endsAt - tune().Collectors.Last)
	return { index = who.index, name = who.name, amount = amount, at = math.max(at, from) }
end

-- The lot (opened) played to its end: the collectors by npcNext, each player bidding the next step `delay` s after the
-- top bid while it is not theirs and the step is at most their max; whichever comes first bids. The lot as it ends.
function AuctionRules.play(lot: Lot, collectors: { Collector }, players: { Player }?): Lot
	for _ = 1, GUARD do
		local best: Bid? = nil
		local npc = AuctionRules.npcNext(lot, collectors)
		if npc and npc.at < lot.endsAt then
			best = { by = AuctionRules.npcKey(npc.index), name = npc.name, npc = true, amount = npc.amount, at = npc.at }
		end
		local top = AuctionRules.leader(lot)
		local amount = AuctionRules.nextBid(lot)
		local list: { Player } = players or {}
		for _, p in list do
			if (top == nil or top.by ~= p.by) and amount <= p.max and p.by ~= lot.seller then
				local at = (if top then top.at else lot.opensAt) + math.max(0, p.delay)
				if at < lot.endsAt and (best == nil or at < (best :: Bid).at) then
					best = { by = p.by, name = p.name, npc = false, amount = amount, at = at }
				end
			end
		end
		if not best then
			break
		end
		AuctionRules.place(lot, best :: Bid)
	end
	return lot
end

-- ── The settlement ──────────────────────────────────────────────────────────

-- The seller's fee: the trades' between players (8.7, Config.PlayerTrade.Fee), one fee for both.
function AuctionRules.feeRate(): number
	return math.clamp(Config.PlayerTrade.Fee, 0, 1)
end

function AuctionRules.fee(price: number): number
	return PlayerTradeRules.fee(price)
end

-- Who buys the lot (closed): the top bid whose bidder can pay (canPay(userId, amount); nil: every player can; a
-- collector always can), else the keenest collector at the opening price.
function AuctionRules.settle(lot: Lot, collectors: { Collector }, canPay: ((number, number) -> boolean)?): Result
	local winner: Bid? = nil
	for index = #lot.bids, 1, -1 do
		local bid = lot.bids[index]
		if bid.npc or type(bid.by) ~= "number" then
			winner = bid
			break
		elseif canPay == nil or canPay(bid.by :: number, bid.amount) then
			winner = bid
			break
		end
	end
	if winner == nil then
		local top = keenest(collectors)
		winner = { by = AuctionRules.npcKey(if top then top.index else 1), name = if top then top.name else "A collector", npc = true, amount = lot.opening, at = lot.endsAt }
	end
	local won = winner :: Bid
	local price = if won.npc then math.max(won.amount, lot.opening) else won.amount
	local house = lot.seller == nil
	local fee = if house then 0 else AuctionRules.fee(price)
	return {
		price = price,
		fee = fee,
		net = if house then 0 else price - fee,
		winner = won.name,
		npc = won.npc,
		buyer = if won.npc then nil else won.by :: number,
		seller = lot.seller,
		house = house,
	}
end

function AuctionRules.payments(result: Result): { Payment }
	local list: { Payment } = {}
	local seller = result.seller
	if seller ~= nil then
		table.insert(list, { userId = seller, reason = AuctionRules.Reasons.Sale, delta = result.price })
		if result.fee > 0 then
			table.insert(list, { userId = seller, reason = AuctionRules.Reasons.Fee, delta = -result.fee })
		end
	end
	local buyer = result.buyer
	if buyer ~= nil then
		table.insert(list, { userId = buyer, reason = AuctionRules.Reasons.Buy, delta = -result.price })
	end
	return list
end

-- ── Who may consign what ────────────────────────────────────────────────────

function AuctionRules.allowed(rarity: string?): boolean
	return rarity ~= nil and table.find(tune().Rarities, rarity) ~= nil
end

-- "rare, epic or legendary" (Config's rarities in words)
local function rarityWords(): string
	local names: { string } = {}
	for _, id in tune().Rarities do
		table.insert(names, string.lower(AuctionRules.rarityName(id)))
	end
	if #names <= 1 then
		return names[1] or ""
	end
	return `{table.concat(names, ", ", 1, #names - 1)} or {names[#names]}`
end
AuctionRules.rarityWords = rarityWords

function AuctionRules.consignable(entry: { item: string, condition: number }): (boolean, string?)
	local def = CollectionRules.defOf(entry.item)
	if not def then
		return false, "This piece can't go to auction."
	end
	if not AuctionRules.allowed(CollectionRules.rarityOf(def)) then
		return false, `Only {rarityWords()} pieces go to auction.`
	end
	if CollectionRules.broken(entry) then
		return false, "A broken piece can't go to auction."
	end
	return true, nil
end

function AuctionRules.canConsign(lots: { Lot }, userId: number, entry: { uid: string, item: string, condition: number }, phaseName: string): (boolean, string?)
	if phaseName == "live" then
		return false, "The auction is on: consign for the next round."
	elseif phaseName == "closing" then
		return false, "Consignments are closed: the auction starts in a moment."
	elseif phaseName == "results" then
		return false, "The round's results are up: consignments open in a moment."
	elseif phaseName ~= "consign" then
		return false, "The Auction House is closed."
	end
	for _, lot in lots do
		if lot.seller == userId then
			return false, `One piece a round: your {lot.name} is in already.`
		end
	end
	if #lots >= tune().MaxLots then
		return false, "This round is full: try the next one."
	end
	return AuctionRules.consignable(entry)
end

-- ── The Grand Auction (hooks) ───────────────────────────────────────────────

function AuctionRules.grandAt(now: number): number?
	local G = tune().Grand
	if not G.On then
		return nil
	end
	local at = math.floor(now / 86400) * 86400 + G.Hour * 3600
	return if at > now then at else at + 86400
end

function AuctionRules.isGrand(startsAt: number): boolean
	local G = tune().Grand
	return G.On and (startsAt - G.Hour * 3600) % 86400 == 0
end

-- ── The client's view ───────────────────────────────────────────────────────

function AuctionRules.lotView(lot: Lot, me: number?, fresh: boolean?): LotView
	local top = AuctionRules.leader(lot)
	return {
		id = lot.id,
		item = lot.item,
		name = lot.name,
		rarity = lot.rarity,
		condition = lot.condition,
		income = lot.income,
		worth = lot.worth,
		opening = lot.opening,
		price = lot.price,
		next = AuctionRules.nextBid(lot),
		step = if #lot.bids == 0 then 0 else AuctionRules.step(lot.price),
		leader = if top then top.name else nil,
		leaderMe = top ~= nil and me ~= nil and top.by == me,
		leaderNpc = top ~= nil and top.npc,
		endsAt = lot.endsAt,
		seller = lot.sellerName,
		mine = me ~= nil and lot.seller == me,
		fresh = fresh == true,
		market = lot.market,
	}
end

function AuctionRules.resultView(lot: Lot, result: Result, me: number?): ResultView
	local sold = me ~= nil and result.seller == me
	return {
		item = lot.item,
		name = lot.name,
		rarity = lot.rarity,
		price = result.price,
		winner = result.winner,
		npc = result.npc,
		sold = sold,
		won = me ~= nil and result.buyer == me,
		fee = if sold then result.fee else 0,
		net = if sold then result.net else 0,
	}
end

local function amountOf(value: any): number?
	return if finite(value) and value >= 0 and value <= MAX_MONEY then value else nil
end

local function rarityOk(value: any): string
	return if type(value) == "string" and Config.Collection.Tiers[value] then value else Config.Collection.Order[1]
end

local function readLot(raw: any): LotView?
	if type(raw) ~= "table" or not shortString(raw.item, MAX_ID) or not amountOf(raw.price) or not amountOf(raw.next) or not finite(raw.endsAt) then
		return nil
	end
	local market: string? = if raw.market == "hot" or raw.market == "cold" then raw.market else nil
	return {
		id = if finite(raw.id) then math.floor(raw.id) else 0,
		item = raw.item,
		name = if shortString(raw.name, MAX_NAME) then raw.name else raw.item,
		rarity = rarityOk(raw.rarity),
		condition = if finite(raw.condition) then math.clamp(raw.condition, 0, 1) else 1,
		income = amountOf(raw.income) or 0,
		worth = amountOf(raw.worth) or 0,
		opening = amountOf(raw.opening) or raw.next,
		price = raw.price,
		next = raw.next,
		step = amountOf(raw.step) or 0,
		leader = if shortString(raw.leader, MAX_NAME) then raw.leader else nil,
		leaderMe = raw.leaderMe == true,
		leaderNpc = raw.leaderNpc == true,
		endsAt = raw.endsAt,
		seller = if shortString(raw.seller, MAX_NAME) then raw.seller else "The house",
		mine = raw.mine == true,
		fresh = raw.fresh == true,
		market = market,
	}
end

local function readResult(raw: any): ResultView?
	if type(raw) ~= "table" or not shortString(raw.item, MAX_ID) or not amountOf(raw.price) then
		return nil
	end
	return {
		item = raw.item,
		name = if shortString(raw.name, MAX_NAME) then raw.name else raw.item,
		rarity = rarityOk(raw.rarity),
		price = raw.price,
		winner = if shortString(raw.winner, MAX_NAME) then raw.winner else "A collector",
		npc = raw.npc == true,
		sold = raw.sold == true,
		won = raw.won == true,
		fee = amountOf(raw.fee) or 0,
		net = amountOf(raw.net) or 0,
	}
end

local PHASES = { consign = true, closing = true, live = true, results = true }

function AuctionRules.readView(raw: any): View?
	if type(raw) ~= "table" or not PHASES[raw.phase] or not finite(raw.startsAt) or not finite(raw.endsAt) then
		return nil
	end
	local upcoming = {}
	if type(raw.upcoming) == "table" then
		for _, u in raw.upcoming do
			if #upcoming >= MAX_LIST then
				break
			end
			if type(u) == "table" and shortString(u.item, MAX_ID) then
				table.insert(upcoming, { item = u.item, name = if shortString(u.name, MAX_NAME) then u.name else u.item, rarity = rarityOk(u.rarity) })
			end
		end
	end
	local results: { ResultView } = {}
	if type(raw.results) == "table" then
		for _, r in raw.results do
			if #results >= MAX_LIST then
				break
			end
			local read = readResult(r)
			if read then
				table.insert(results, read)
			end
		end
	end
	local mine: Piece? = nil
	local m = raw.mine
	if type(m) == "table" and shortString(m.uid, MAX_ID) and shortString(m.item, MAX_ID) then
		mine = { uid = m.uid, item = m.item, name = if shortString(m.name, MAX_NAME) then m.name else m.item, rarity = rarityOk(m.rarity), opening = amountOf(m.opening) or 0 }
	end
	local lot = if raw.phase == "live" then readLot(raw.lot) else nil
	local count = if finite(raw.count) then math.clamp(math.floor(raw.count), 0, MAX_LIST) else 0
	return {
		phase = raw.phase,
		round = if finite(raw.round) then math.floor(raw.round) else 0,
		startsAt = raw.startsAt,
		endsAt = raw.endsAt,
		lot = lot,
		index = if lot and finite(raw.index) then math.clamp(math.floor(raw.index), 1, math.max(1, count)) else 0,
		count = count,
		upcoming = upcoming,
		mine = mine,
		results = results,
		grand = raw.grand == true,
	}
end

-- ── The words ───────────────────────────────────────────────────────────────

function AuctionRules.money(n: number): string
	return Market.money(n)
end

-- "0:45", "12:34", "1:02:03" (never under 0)
function AuctionRules.clock(seconds: number): string
	local s = math.max(0, math.ceil((if finite(seconds) then seconds else 0) - EPS))
	local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

function AuctionRules.rarityName(id: string): string
	local tier = Config.Collection.Tiers[id]
	return if tier then tier.name else id
end

function AuctionRules.percent(condition: number): string
	return `{math.floor(math.clamp(if finite(condition) then condition else 0, 0, 1) * 100 + 0.5)}%`
end

function AuctionRules.phaseLine(view: View?, now: number): string
	if view == nil then
		local p = AuctionRules.phase(now)
		if p.name == "live" then
			return `The auction is on · the next round in {AuctionRules.clock(AuctionRules.startOf(p.round + 1) - now)}`
		end
		return `Next auction in {AuctionRules.clock(p.startsAt - now)}`
	end
	local left = AuctionRules.clock(view.endsAt - now)
	if view.phase == "live" then
		return if view.lot then `LIVE · lot {view.index} of {view.count}` else "LIVE · the next lot is coming up"
	elseif view.phase == "results" then
		return `The round is over · consignments open in {left}`
	elseif view.phase == "closing" then
		return `Consignments closed · the auction starts in {AuctionRules.clock(view.startsAt - now)}`
	end
	return `Next auction in {AuctionRules.clock(view.startsAt - now)} · consign a {rarityWords()} piece`
end

function AuctionRules.leaderLine(lot: LotView): string
	if lot.leader == nil then
		return `No bids yet · opens at {AuctionRules.money(lot.opening)}`
	elseif lot.leaderMe then
		return "Leading: you"
	end
	return `Leading: {lot.leader}`
end

-- The BID button: its words, its face ("good": a bid goes; "shut": it says why not) and the reason (nil: it bids).
function AuctionRules.bidButton(lot: LotView, money: number, now: number): (string, string, string?)
	if now >= lot.endsAt then
		return "SOLD", "shut", "The hammer has fallen on this lot."
	elseif lot.mine then
		return "YOUR PIECE", "shut", "You can't bid on your own piece."
	elseif lot.leaderMe then
		return "YOU LEAD", "shut", "You're the top bidder: wait for the hammer."
	elseif money < lot.next then
		return `NEED {AuctionRules.money(lot.next - money)}`, "shut", `You need {AuctionRules.money(lot.next - money)} more to bid {AuctionRules.money(lot.next)}.`
	end
	local up = if lot.price > 0 then ` +{AuctionRules.money(lot.next - lot.price)}` else ""
	return `BID{up} · {AuctionRules.money(lot.next)}`, "good", nil
end

function AuctionRules.resultLine(result: ResultView): string
	if result.won then
		return `You bought it for {AuctionRules.money(result.price)}`
	elseif result.sold then
		return `Sold to {result.winner} for {AuctionRules.money(result.price)} · you got {AuctionRules.money(result.net)}`
	end
	return `Sold to {result.winner} for {AuctionRules.money(result.price)}`
end

return AuctionRules
