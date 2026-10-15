--!strict
-- 8.7 SANDBOX, trading between players: the rules (Config.PlayerTrade's numbers). Pure (no Roblox at its top level:
-- tests/playertrade_test.luau). server/PlayerTrade.luau decides every offer and sale with these; client/TradeUi.luau
-- shows the same prices before it asks (the composer, the price picker, the buy question), client/OfferCard.luau the
-- seller's card (its words: shared/Visitors.luau cardLines, a player's offer).
--   * A piece's value: what the game pays for it without the market (CollectionRules.sell: its tier's share of its
--     worth × its condition, scrap when broken). The same every day (no hot or cold kind, no demand), so a FOR SALE
--     sign's price stays allowed once set.
--   * A price: a whole number of dollars between MinTimes × and MaxTimes × the value (bounds).
--   * The fee: Fee × the price (rounded to the dollar), taken from the seller's side; the seller keeps the rest (net).
--   * The composer's and the picker's prices: the presets (Presets × the value, each clamped), the −/+ step (the
--     roundest of 1, 2, 5 × 10ⁿ at most StepShare × the price shown, never under the value's own step, $1 at least:
--     about 10 % a tap), every price clamped to the bounds.
--
--   PlayerTradeRules.value(entry)            $ the piece is worth to the game (a whole number, at least 1)
--   PlayerTradeRules.bounds(value)           (least, most) a price may be for a piece of that value
--   PlayerTradeRules.clamp(price, value)     a whole price within the bounds (junk: the least)
--   PlayerTradeRules.check(price, value)     ok, why: a whole number within the bounds?
--   PlayerTradeRules.fee(price)              $ the ZDC fee; net(price) $ the seller keeps
--   PlayerTradeRules.step(amount)            $ one − or + moves a price of that size (the roundest under StepShare of it)
--   PlayerTradeRules.nudge(price, value, dir)   the price a step up (dir 1) or down (−1), clamped (the step: the
--                                            price's, at least the value's)
--   PlayerTradeRules.presets(value)          { { label = "1.5×", times, price } } the quick prices, clamped
--   PlayerTradeRules.times(price, value)     "×1.5": the price over the value (a tenth)
--   PlayerTradeRules.offerToast(who, price, name, value)   the seller's toast "🧑 Ann offers $1,200 for your Gramophone
--                                            (worth $800)"
--   PlayerTradeRules.soldToast(name, buyer, price, fee) / boughtToast(name, seller, price)   the deal's toasts
--   PlayerTradeRules.news(seller, buyer, name, price)   a big sale's chat line
--   PlayerTradeRules.isBig(price)            a sale the whole server hears of (Config.PlayerTrade.BigSale)
--   PlayerTradeRules.readPiece(raw)          the server's compose / pricing / confirm message checked on the client (nil
--                                            for anything else): a Piece

local Config = require(script.Parent.Config)
local CollectionRules = require(script.Parent.CollectionRules)
local Market = require(script.Parent.Market) -- (Market.money: "$1,200")

local PlayerTradeRules = {}

-- What the client's windows show: one piece and its prices (the server's compose, pricing and confirm messages).
export type Piece = {
	kind: string, -- "compose" (make an offer), "pricing" (your FOR SALE sign), "confirm" (buy at a sign's price)
	seller: number, -- the seller's UserId (yours on "pricing")
	sellerName: string,
	uid: string,
	stand: number,
	name: string,
	item: string,
	rarity: string,
	condition: number,
	value: number, -- $ the game pays (PlayerTradeRules.value)
	income: number, -- $ a minute on show (the buyer's: in their warehouse; the owner's on "pricing")
	least: number,
	most: number,
	isNew: boolean, -- not in the buyer's collection book yet
	sale: number?, -- the sign's price (nil: none)
	price: number?, -- "confirm": the price to pay
	money: number?, -- the buyer's money now (nil: not sent)
}
export type Preset = { label: string, times: number, price: number }

local MAX_PRICE = 2 ^ 40
local MAX_ID = 64
local MAX_NAME = 60

local function tune()
	return Config.PlayerTrade
end

local function finite(n: any): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function shortString(value: any, most: number): boolean
	return type(value) == "string" and #value >= 1 and #value <= most
end

-- ── The prices ─────────────────────────────────────────────────────────────

function PlayerTradeRules.value(entry: { item: string, condition: number }): number
	return CollectionRules.sell(entry)
end

function PlayerTradeRules.bounds(value: number): (number, number)
	local v = if finite(value) then math.max(1, value) else 1
	local least = math.max(1, math.ceil(v * math.max(0, tune().MinTimes) - 1e-9))
	local most = math.max(least, math.floor(v * math.max(0, tune().MaxTimes) + 1e-9))
	return math.min(least, MAX_PRICE - 1), math.min(most, MAX_PRICE - 1)
end

function PlayerTradeRules.clamp(price: any, value: number): number
	local least, most = PlayerTradeRules.bounds(value)
	if not finite(price) then
		return least
	end
	return math.clamp(math.floor(price + 0.5), least, most)
end

function PlayerTradeRules.check(price: any, value: number): (boolean, string?)
	local least, most = PlayerTradeRules.bounds(value)
	if not finite(price) or price ~= math.floor(price) then
		return false, "That's no price."
	end
	if price < least or price > most then
		return false, `Price it between {Market.money(least)} and {Market.money(most)}.`
	end
	return true, nil
end

function PlayerTradeRules.fee(price: number): number
	if not finite(price) or price <= 0 then
		return 0
	end
	return math.clamp(math.floor(price * math.clamp(tune().Fee, 0, 1) + 0.5), 0, math.floor(price))
end

function PlayerTradeRules.net(price: number): number
	return math.max(0, math.floor(if finite(price) then price else 0) - PlayerTradeRules.fee(price))
end

-- The roundest step (1, 2, 5 × 10ⁿ) at most StepShare × the amount; $1 at least.
function PlayerTradeRules.step(amount: number): number
	local want = (if finite(amount) then math.max(1, amount) else 1) * math.max(0, tune().StepShare)
	if want < 2 then
		return 1
	end
	local power = 10 ^ math.floor(math.log10(want) + 1e-9)
	local best = 1
	for _, m in { 1, 2, 5, 10 } do
		if m * power <= want + 1e-9 then
			best = m * power
		end
	end
	return math.max(1, math.floor(best + 0.5))
end

function PlayerTradeRules.nudge(price: any, value: number, dir: number): number
	local now = PlayerTradeRules.clamp(price, value)
	local step = math.max(PlayerTradeRules.step(value), PlayerTradeRules.step(now))
	if dir < 0 then
		-- (down by the step of the price it lands on: back the way it went up)
		local below = math.max(PlayerTradeRules.step(value), PlayerTradeRules.step(now - step))
		return PlayerTradeRules.clamp(now - below, value)
	end
	return PlayerTradeRules.clamp(now + step, value)
end

-- "1×", "1.5×", "2×".
local function label(times: number): string
	local text = string.format("%.1f", times)
	text = string.gsub(text, "%.0$", "")
	return text .. "×"
end

function PlayerTradeRules.presets(value: number): { Preset }
	local out: { Preset } = {}
	for _, times in tune().Presets do
		if finite(times) and times > 0 then
			local v = if finite(value) then math.max(1, value) else 1
			table.insert(out, { label = label(times), times = times, price = PlayerTradeRules.clamp(v * times, v) })
		end
	end
	return out
end

function PlayerTradeRules.times(price: number, value: number): string
	if not finite(price) or not finite(value) or value <= 0 then
		return "×1"
	end
	return "×" .. string.gsub(string.format("%.1f", price / value), "%.0$", "")
end

-- ── The words ──────────────────────────────────────────────────────────────

function PlayerTradeRules.offerToast(who: string, price: number, name: string, value: number): string
	return `🧑 {who} offers {Market.money(price)} for your {name} (worth {Market.money(value)})`
end

function PlayerTradeRules.soldToast(name: string, buyer: string, price: number, fee: number): string
	return `🤝 Sold {name} to {buyer} for {Market.money(price)} (fee {Market.money(fee)})`
end

function PlayerTradeRules.boughtToast(name: string, seller: string, price: number): string
	return `📦 Bought {name} from {seller} for {Market.money(price)}`
end

function PlayerTradeRules.news(seller: string, buyer: string, name: string, price: number): string
	return `🤝 {seller} sold the {name} to {buyer} for {Market.money(price)}!`
end

function PlayerTradeRules.isBig(price: number): boolean
	local big = tune().BigSale
	return finite(big) and big > 0 and finite(price) and price >= big
end

-- ── The client's reading of the server's messages ─────────────────────────

function PlayerTradeRules.readPiece(raw: any): Piece?
	if type(raw) ~= "table" or (raw.kind ~= "compose" and raw.kind ~= "pricing" and raw.kind ~= "confirm") then
		return nil
	end
	if not shortString(raw.uid, MAX_ID) or not shortString(raw.name, MAX_NAME) or not shortString(raw.item, MAX_ID)
		or not shortString(raw.sellerName, MAX_NAME) or not finite(raw.seller) or not finite(raw.stand) or raw.stand < 1 then
		return nil
	end
	local value = raw.value
	if not finite(value) or value < 1 or value >= MAX_PRICE then
		return nil
	end
	local least, most = PlayerTradeRules.bounds(value)
	local sale = if finite(raw.sale) and raw.sale >= 1 and raw.sale < MAX_PRICE then math.floor(raw.sale) else nil
	local price = if finite(raw.price) and raw.price >= 1 and raw.price < MAX_PRICE then math.floor(raw.price) else nil
	if raw.kind == "confirm" and price == nil then
		return nil
	end
	return {
		kind = raw.kind :: string,
		seller = raw.seller,
		sellerName = raw.sellerName,
		uid = raw.uid,
		stand = math.floor(raw.stand),
		name = raw.name,
		item = raw.item,
		rarity = if shortString(raw.rarity, MAX_ID) then raw.rarity else "common",
		condition = if finite(raw.condition) then math.clamp(raw.condition, 0, 1) else 1,
		value = value,
		income = if finite(raw.income) and raw.income >= 0 then raw.income else 0,
		least = least,
		most = most,
		isNew = raw.isNew == true,
		sale = sale,
		price = price,
		money = if finite(raw.money) and raw.money >= 0 then raw.money else nil,
	}
end

return PlayerTradeRules
