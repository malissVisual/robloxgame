--!strict
-- 8.3 SANDBOX, the market (the owner: selling should be a decision, not a reflex). Pure (no Roblox at its top level;
-- tests/market_test.luau); Config.Market holds the numbers. server/Collection.luau prices every sale and the stands'
-- income with it (through shared/CollectionRules.luau), client/WarehouseUi.luau shows the same (the "Collection"
-- remote's state carries the player's View), shared/StockPlan.luau totals a bulk sale with it.
--   * Hot and cold kinds: every UTC day Config.Market.Hot kinds are hot (HotCollectibles of them collectibles, the rest
--     ordinary furniture) and Cold kinds of furniture are cold, drawn from the day's number alone (the same on every
--     server and for everybody, like the daily tasks) out of the sandbox house's kinds (Market.pool: the catalogue of
--     shared/FurnitureLooks.luau without Walt's farm pieces, worth MinValue or more; read when first asked, so a new piece
--     in the catalogue joins the market by itself). A hot kind sells for × HotSell and earns × HotIncome on show; a cold
--     one sells for × ColdSell.
--   * Demand: every piece of a kind you sell lowers that kind's price for you by Drop (MaxDrop at most: the pressure
--     stops at MaxDrop / Drop pieces); one piece's Drop comes back every Recover s, and all of it at 00:00 UTC. A bulk
--     sale prices its pieces one after the other (Market.batch: the second radio of a sale already sells for 5 % less).
--     Per player, in the save (profile.market: server/PlayerData.luau, only from a real save written with Flag).
--
--   Market.dayOf(now)                  the UTC day number of a Unix time (1970-01-01 is day 0)
--   Market.left(day, now)              s from `now` until that day's end (the next market), never under 0
--   Market.pool()                      the kinds the market picks from: furniture, collectibles ({ id }, catalogue order)
--   Market.pick(day)                   that day's { hot = { id }, cold = { id } } (catalogue order; the same every time)
--   Market.today(day, now?)            the day's View with no demand of anybody's (the hot and cold kinds alone)
--   Market.tag(view?, item)            "hot", "cold" or nil (no view: nil)
--   Market.sellFactor(view?, item)     HotSell, ColdSell or 1; Market.incomeFactor(view?, item): HotIncome or 1
--   Market.demandFactor(n)             the price's × after n pieces of a kind sold: 1 − Drop × n, at least 1 − MaxDrop
--   Market.pressure(view?, item)       the pieces of that kind that weigh on its price now (the view's demand)
--   Market.price(base, view?, item, before?)   $ a piece sells for now (whole, at least 1): its price without the market
--                                      (`base`, CollectionRules.sell's) × the kind's factor × the demand's, `before` more
--                                      pieces of its kind sold just before it in the same sale
--   Market.batch(pieces, view?)        the total and each one's price of pieces { item, base? (else price) } sold in this
--                                      order (Market.price with the ones before of their kind)
-- The save (profile.market = { day, kinds = { [item] = { n, at, sold } } }: n the pieces weighing on the price at `at`
-- (from then a Recover s brings one back), sold how many were sold that day):
--   Market.Flag / Market.empty() / Market.clean(raw) / Market.fromSave(saved)   the flag, a new player's, a saved one
--                                      checked (never trusted), the migration (only a real save written with the flag)
--   Market.note(saved, item, day, now, count?)   `count` (1) pieces of `item` sold now (a new day starts afresh)
--   Market.view(saved?, day, now)      the player's View now: { day, hot, cold, left, demand = { [item] = { n, sold,
--                                      back } } } (back: s until one piece's Drop comes back; a kind sold today only)
--   Market.nextChange(saved?, day, now)   s until a demand comes back a step (the server sends the state again then),
--                                      nil for none
--   Market.readView(raw)               a View from the remote, checked (nil for anything else; the client's)
-- The words (the client's):
--   Market.factor(x)                   "×1.6", "×1.25"; Market.percent(view?, item): how much under its price a kind sells
--                                      for now because of the demand (0 … MaxDrop × 100, whole)
--   Market.wait(s)                     "5 h", "40 min", "1 min"; Market.money(n): "$1,234" (the server's notices)
--   Market.nameOf(item)                its catalogue name (else the id)
--   Market.line(view, left?)           "Today's market: 🔥 Old Globe, Jukebox, Sofa · ❄ Wardrobe · new in 5 h"
--   Market.badge(view?, item)          "🔥 HOT ×1.6", "❄ COLD" or nil
--   Market.demandLine(view?, item, name?)   "Market: Vintage Radio −10% (you sold 2 today)" (nil: its price is whole)
--   Market.hotToast(view)              "🔥 Hot today: Old Globe, Jukebox, Sofa (sell ×1.6, on show ×1.25)"

local Config = require(script.Parent.Config)
local FurnitureLooks = require(script.Parent.FurnitureLooks)

local Market = {}

local DAY = 86400
local MOD = 2147483647 -- the Park–Miller generator (2^31 − 1, × 48271): every product stays below 2^53
local MUL = 48271
local MAX_ID = 40 -- a longer item id in a save or from the remote is no piece of ours
local MAX_KINDS = 120 -- the kinds a save keeps at most
local MAX_SOLD = 1_000_000
local MAX_LIST = 8 -- the hot or cold kinds the remote's view may hold
local MINUS = "−" -- (U+2212: the minus of a price going down)

export type Picks = { hot: { string }, cold: { string } }
export type Demand = { n: number, at: number, sold: number }
export type Saved = { day: number, kinds: { [string]: Demand } }
export type DemandView = { n: number, sold: number, back: number }
export type View = {
	day: number,
	hot: { string },
	cold: { string },
	left: number, -- s until the next market (00:00 UTC) when the view was made
	demand: { [string]: DemandView },
}
export type Priced = { item: string, base: number?, price: number? }

local function tune()
	return Config.Market
end

Market.Flag = Config.Market.Flag

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- The pressure the price stops at (MaxDrop / Drop pieces: more sold weighs no more).
local function most(): number
	local drop = tune().Drop
	return if drop > 0 then math.max(1, math.ceil(tune().MaxDrop / drop - 1e-9)) else 0
end

-- ── Time ────────────────────────────────────────────────────────────────────

function Market.dayOf(now: number): number
	return math.floor(now / DAY)
end

function Market.left(day: number, now: number): number
	return math.max(0, (day + 1) * DAY - now)
end

-- ── The kinds ───────────────────────────────────────────────────────────────

local furniture: { string }? = nil
local collectibles: { string }? = nil
local order: { [string]: number } = {}

-- The sandbox house's kinds (worth MinValue or more), read from the catalogue the first time they are asked for.
local function readPool(): ({ string }, { string })
	if furniture and collectibles then
		return furniture, collectibles
	end
	local farm: { [string]: boolean } = {}
	for _, id in (FurnitureLooks :: any).FarmPieces or {} do
		farm[id] = true
	end
	local plain: { string } = {}
	local rare: { string } = {}
	for index, id in FurnitureLooks.Order do
		local def = FurnitureLooks.Items[id]
		if def and not farm[id] and order[id] == nil and finite(def.value) and def.value >= tune().MinValue then
			order[id] = index
			table.insert(if type((def :: any).rarity) == "string" then rare else plain, id)
		end
	end
	furniture, collectibles = plain, rare
	return plain, rare
end

function Market.pool(): ({ string }, { string })
	local plain, rare = readPool()
	return table.clone(plain), table.clone(rare)
end

-- A stream of numbers in [0, 1) from the day (no Random: the same on every server and in the tests).
local function stream(day: number): () -> number
	local state = math.floor(day) % MOD + 1
	state = (state * MUL + tune().Salt % MOD) % MOD
	if state == 0 then
		state = 1
	end
	for _ = 1, 4 do
		state = state * MUL % MOD
	end
	return function(): number
		state = state * MUL % MOD
		return (state - 1) / (MOD - 1)
	end
end

-- `count` ids drawn from `list` (taken out of it).
local function draw(list: { string }, count: number, next: () -> number, into: { string })
	for _ = 1, count do
		if #list == 0 then
			return
		end
		local index = math.min(#list, 1 + math.floor(next() * #list))
		table.insert(into, table.remove(list, index) :: string)
	end
end

local function byCatalogue(a: string, b: string): boolean
	return (order[a] or 0) < (order[b] or 0)
end

local picked: { [number]: Picks } = {}
local pickedCount = 0

function Market.pick(day: number): Picks
	day = math.floor(day)
	local known = picked[day]
	if known then
		return known
	end
	local plain, rare = readPool()
	local left, gems = table.clone(plain), table.clone(rare)
	local next = stream(day)
	local hot: { string } = {}
	local hotCount = math.max(0, math.floor(tune().Hot))
	draw(gems, math.min(hotCount, math.max(0, math.floor(tune().HotCollectibles))), next, hot)
	draw(left, hotCount - #hot, next, hot)
	draw(gems, hotCount - #hot, next, hot) -- (too little furniture: more collectibles)
	local cold: { string } = {}
	draw(left, math.max(0, math.floor(tune().Cold)), next, cold)
	table.sort(hot, byCatalogue)
	table.sort(cold, byCatalogue)
	local picks: Picks = { hot = hot, cold = cold }
	if pickedCount >= 16 then -- (a few days kept: the server asks for today's all day)
		table.clear(picked)
		pickedCount = 0
	end
	picked[day] = picks
	pickedCount += 1
	return picks
end

function Market.today(day: number, now: number?): View
	local picks = Market.pick(day)
	return {
		day = math.floor(day),
		hot = table.clone(picks.hot),
		cold = table.clone(picks.cold),
		left = Market.left(day, now or day * DAY),
		demand = {},
	}
end

function Market.tag(view: View?, item: string): string?
	if not view then
		return nil
	end
	if table.find(view.hot, item) then
		return "hot"
	elseif table.find(view.cold, item) then
		return "cold"
	end
	return nil
end

function Market.sellFactor(view: View?, item: string): number
	local tag = Market.tag(view, item)
	return if tag == "hot" then tune().HotSell elseif tag == "cold" then tune().ColdSell else 1
end

function Market.incomeFactor(view: View?, item: string): number
	return if Market.tag(view, item) == "hot" then tune().HotIncome else 1
end

-- ── Demand ──────────────────────────────────────────────────────────────────

function Market.demandFactor(n: number): number
	if not finite(n) or n <= 0 then
		return 1
	end
	return math.max(1 - tune().MaxDrop, 1 - tune().Drop * math.floor(n))
end

function Market.pressure(view: View?, item: string): number
	local demand = if view then view.demand[item] else nil
	return if demand and finite(demand.n) then math.max(0, demand.n) else 0
end

function Market.price(base: number, view: View?, item: string, before: number?): number
	local plain = if finite(base) then math.max(0, base) else 0
	if not view then
		return math.max(1, math.floor(plain + 0.5))
	end
	local factor = Market.sellFactor(view, item) * Market.demandFactor(Market.pressure(view, item) + math.max(0, before or 0))
	return math.max(1, math.floor(plain * factor + 0.5))
end

function Market.batch(pieces: { Priced }, view: View?): (number, { number })
	local seen: { [string]: number } = {}
	local prices: { number } = table.create(#pieces)
	local total = 0
	for _, piece in pieces do
		local item = piece.item
		local base = if finite(piece.base) then piece.base :: number elseif finite(piece.price) then piece.price :: number else 0
		local before = seen[item] or 0
		local price = Market.price(base, view, item, before)
		seen[item] = before + 1
		table.insert(prices, price)
		total += price
	end
	return total, prices
end

-- One kind's demand brought to `now`: the pressure left and the moment its next step starts counting.
local function settled(demand: Demand, now: number): (number, number)
	if demand.n <= 0 then
		return 0, now
	end
	local recover = math.max(1, tune().Recover)
	local steps = math.max(0, math.floor((now - demand.at) / recover))
	if steps >= demand.n then
		return 0, now
	end
	return demand.n - steps, demand.at + steps * recover
end

-- ── The save ────────────────────────────────────────────────────────────────

function Market.empty(): Saved
	return { day = 0, kinds = {} }
end

local function whole(value: any, low: number, high: number): number?
	if not finite(value) then
		return nil
	end
	return math.clamp(math.floor(value), low, high)
end

function Market.clean(raw: any): Saved
	local out = Market.empty()
	if type(raw) ~= "table" then
		return out
	end
	out.day = whole(raw.day, 0, 1e7) or 0
	local kinds = raw.kinds
	if type(kinds) ~= "table" then
		return out
	end
	local count = 0
	for item, d in kinds do
		if count >= MAX_KINDS then
			break
		end
		if type(item) == "string" and #item <= MAX_ID and FurnitureLooks.Items[item] ~= nil and type(d) == "table" then
			local n = whole(d.n, 0, most()) or 0
			local sold = whole(d.sold, 0, MAX_SOLD) or 0
			local at = if finite(d.at) then math.clamp(d.at, 0, 2 ^ 40) else 0
			if n > 0 or sold > 0 then
				out.kinds[item] = { n = n, at = at, sold = sold }
				count += 1
			end
		end
	end
	return out
end

-- The migration (server/PlayerData.luau applySaved): only a real save (money in it) written with the flag has a market
-- of its own; an older one, a new player or a lock-only record start with the empty one.
function Market.fromSave(saved: any): Saved
	if type(saved) ~= "table" or saved.money == nil or saved[Market.Flag] ~= true then
		return Market.empty()
	end
	return Market.clean(saved.market)
end

-- A new day forgets the old one's demand.
local function onDay(saved: Saved, day: number)
	if saved.day ~= day then
		table.clear(saved.kinds)
		saved.day = day
	end
end

function Market.note(saved: Saved, item: string, day: number, now: number, count: number?)
	local n = math.floor(count or 1)
	if type(item) ~= "string" or #item > MAX_ID or n <= 0 or not finite(now) then
		return
	end
	onDay(saved, math.floor(day))
	local demand = saved.kinds[item]
	if not demand then
		local kinds = 0
		for _ in saved.kinds do
			kinds += 1
		end
		if kinds >= MAX_KINDS then
			return
		end
		demand = { n = 0, at = now, sold = 0 }
		saved.kinds[item] = demand
	end
	assert(demand)
	local pressure, at = settled(demand, now)
	demand.n = math.min(pressure + n, most())
	demand.at = if pressure > 0 then at else now
	demand.sold = math.min(demand.sold + n, MAX_SOLD)
end

function Market.view(saved: Saved?, day: number, now: number): View
	local view = Market.today(day, now)
	if saved and saved.day == math.floor(day) then
		local recover = math.max(1, tune().Recover)
		for item, demand in saved.kinds do
			local n, at = settled(demand, now)
			if n > 0 or demand.sold > 0 then
				view.demand[item] = { n = n, sold = demand.sold, back = if n > 0 then math.max(0, at + recover - now) else 0 }
			end
		end
	end
	return view
end

function Market.nextChange(saved: Saved?, day: number, now: number): number?
	if not saved or saved.day ~= math.floor(day) then
		return nil
	end
	local recover = math.max(1, tune().Recover)
	local soonest: number? = nil
	for _, demand in saved.kinds do
		local n, at = settled(demand, now)
		if n > 0 then
			local wait = math.max(0, at + recover - now)
			if soonest == nil or wait < soonest then
				soonest = wait
			end
		end
	end
	return soonest
end

local function idList(raw: any): { string }?
	if type(raw) ~= "table" then
		return nil
	end
	local out: { string } = {}
	for index, id in raw do
		if type(index) ~= "number" or type(id) ~= "string" or #id > MAX_ID or #out >= MAX_LIST then
			return nil
		end
		table.insert(out, id)
	end
	return out
end

function Market.readView(raw: any): View?
	if type(raw) ~= "table" or not finite(raw.day) or not finite(raw.left) then
		return nil
	end
	local hot, cold = idList(raw.hot), idList(raw.cold)
	if not hot or not cold then
		return nil
	end
	local demand: { [string]: DemandView } = {}
	if type(raw.demand) == "table" then
		local count = 0
		for item, d in raw.demand do
			if count >= MAX_KINDS then
				break
			end
			if type(item) == "string" and #item <= MAX_ID and type(d) == "table" then
				demand[item] = {
					n = whole(d.n, 0, most()) or 0,
					sold = whole(d.sold, 0, MAX_SOLD) or 0,
					back = if finite(d.back) then math.max(0, d.back) else 0,
				}
				count += 1
			end
		end
	end
	return { day = math.floor(raw.day), hot = hot, cold = cold, left = math.max(0, raw.left), demand = demand }
end

-- ── The words ───────────────────────────────────────────────────────────────

function Market.factor(x: number): string
	local text = string.format("%.2f", x)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return "×" .. text
end

function Market.percent(view: View?, item: string): number
	local n = Market.pressure(view, item)
	return if n > 0 then math.floor((1 - Market.demandFactor(n)) * 100 + 0.5) else 0
end

function Market.wait(seconds: number): string
	local s = if finite(seconds) then math.max(0, seconds) else 0
	if s >= 3600 then
		return `{math.floor(s / 3600)} h`
	end
	return `{math.max(1, math.ceil(s / 60))} min`
end

function Market.money(n: number): string
	local out = tostring(math.floor(if finite(n) then n else 0))
	repeat
		local made, count = string.gsub(out, "^(-?%d+)(%d%d%d)", "%1,%2")
		out = made
	until count == 0
	return "$" .. out
end

function Market.nameOf(item: string): string
	local def = FurnitureLooks.Items[item]
	return if def then def.name else item
end

local function names(list: { string }): string
	local out: { string } = {}
	for _, id in list do
		table.insert(out, Market.nameOf(id))
	end
	return table.concat(out, ", ")
end

function Market.line(view: View, left: number?): string
	local parts: { string } = {}
	if #view.hot > 0 then
		table.insert(parts, `🔥 {names(view.hot)}`)
	end
	if #view.cold > 0 then
		table.insert(parts, `❄ {names(view.cold)}`)
	end
	table.insert(parts, `new in {Market.wait(left or view.left)}`)
	return "Today's market: " .. table.concat(parts, " · ")
end

function Market.badge(view: View?, item: string): string?
	local tag = Market.tag(view, item)
	if tag == "hot" then
		return `🔥 HOT {Market.factor(tune().HotSell)}`
	elseif tag == "cold" then
		return "❄ COLD"
	end
	return nil
end

function Market.demandLine(view: View?, item: string, name: string?): string?
	local percent = Market.percent(view, item)
	if percent <= 0 or not view then
		return nil
	end
	local sold = view.demand[item].sold
	return `Market: {name or Market.nameOf(item)} {MINUS}{percent}% (you sold {sold} today)`
end

function Market.hotToast(view: View): string?
	if #view.hot == 0 then
		return nil
	end
	return `🔥 Hot today: {names(view.hot)} (sell {Market.factor(tune().HotSell)}, on show {Market.factor(tune().HotIncome)})`
end

return Market
