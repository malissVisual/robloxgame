--!strict
-- 6.18 wave 2, the kit's shop lists (the owner: "I need it unified so the phone looks like that [6.17's JOBS], and the
-- other popups too"): which item a SHOP / BAG / GARAGE / STYLE screen puts in its HERO card and how a row's big price
-- looks. Pure Luau (tests/shoppick_test.luau); client/ShopView.luau draws what it says.
--   ShopPick.hero(entries, money, goal)  the hero's index (nil: no hero): the screen's `current` one (your car, the bag
--                                        in use, the look you try), else the savings goal (6.14's Readiness goal, by
--                                        its name) while that shop sells it, else the best thing you can buy now (the
--                                        dearest you afford), else the cheapest one to save up for, else nil
--   ShopPick.tone(entry, money)          a row's price: "money" (green: you can buy it now), "dim" (not yet: the money,
--                                        the counter), "lock" (a level or a campaign first), "none" (no price)
--   ShopPick.order(entries)              the rows' order: the catalog's, the locked ones last
--   ShopPick.share(entry, money)         how far your money is toward its price (the hero's bar), 0 .. 1

local ShopPick = {}

-- What the maths needs of an item: its name, its price (nil: none, e.g. a thing you own), whether its action works now
-- (`buyable`: at the counter, the money, the level), whether it is locked (a level, a campaign), whether it is yours and
-- whether the screen is about it (`current`).
export type Entry = {
	name: string,
	price: number?,
	buyable: boolean?, -- its BUY works now
	forSale: boolean?, -- it is sold here (BUY, now or once you have the money / walk in)
	locked: boolean?,
	owned: boolean?,
	current: boolean?,
}

function ShopPick.hero(entries: { Entry }, money: number, goal: string?): number?
	for index, entry in entries do
		if entry.current then
			return index
		end
	end
	if goal then
		for index, entry in entries do
			if entry.name == goal and not entry.owned and (entry.forSale or entry.locked) then
				return index
			end
		end
	end
	local best, bestPrice = nil, -1
	for index, entry in entries do
		local price = entry.price
		if entry.buyable and price and price <= money and price > bestPrice then
			best, bestPrice = index, price
		end
	end
	if best then
		return best
	end
	local save, savePrice = nil, math.huge
	for index, entry in entries do
		local price = entry.price
		if entry.forSale and not entry.locked and not entry.owned and price and price < savePrice then
			save, savePrice = index, price
		end
	end
	return save
end

function ShopPick.tone(entry: Entry, money: number): string
	if entry.locked then
		return "lock"
	end
	local price = entry.price
	if price == nil then
		return "none"
	end
	return if entry.buyable and money >= price then "money" else "dim"
end

function ShopPick.order(entries: { Entry }): { number }
	local out: { number } = {}
	for index, entry in entries do
		if not entry.locked then
			table.insert(out, index)
		end
	end
	for index, entry in entries do
		if entry.locked then
			table.insert(out, index)
		end
	end
	return out
end

function ShopPick.share(entry: Entry, money: number): number
	local price = entry.price
	if price == nil or price <= 0 then
		return 1
	end
	return math.clamp(money / price, 0, 1)
end

return ShopPick
