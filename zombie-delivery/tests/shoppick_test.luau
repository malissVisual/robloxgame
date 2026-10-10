-- Logic test of 6.18 wave 2 (shared/ShopPick.luau; client/ShopView.luau draws with it): which item a SHOP, BAG, GARAGE
-- or STYLE screen puts in its hero card (the screen's current one, the savings goal, the best buy, the cheapest to save
-- up for), how a row's price looks (green, dim, locked), the rows' order (the locked ones last), the hero's bar.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local ShopPick = require("./ShopPick")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local shop: { ShopPick.Entry } = {
	{ name = "Plastic Bag", owned = true },
	{ name = "Canvas Tote", price = 150, buyable = true, forSale = true },
	{ name = "Thermal Bag", price = 400, buyable = true, forSale = true },
	{ name = "Messenger Bag", price = 900, buyable = false, forSale = true },
	{ name = "Duffel", price = 2000, locked = true },
}

-- ── The hero ────────────────────────────────────────────────────────────────
check("the best buy: the dearest you can afford now", ShopPick.hero(shop, 500, nil) == 3)
check("… with less money the cheaper one", ShopPick.hero(shop, 200, nil) == 2)
check("nothing affordable: the cheapest to save up for", ShopPick.hero(shop, 50, nil) == 2)
check("the savings goal (6.14 Readiness) first while this shop sells it", ShopPick.hero(shop, 500, "Messenger Bag") == 4)
check("… a locked goal too (the level comes)", ShopPick.hero(shop, 500, "Duffel") == 5)
check("… a goal this shop does not sell changes nothing", ShopPick.hero(shop, 500, "Old Van") == 3)
check("… an owned one is no goal", ShopPick.hero(shop, 500, "Plastic Bag") == 3)
local garage: { ShopPick.Entry } = { { name = "Old Van", owned = true }, { name = "City Bike", owned = true, current = true } }
check("the screen's current one wins (your car, the bag in use)", ShopPick.hero(garage, 0, nil) == 2)
check("nothing to show: no hero", ShopPick.hero({ { name = "Old Van", owned = true } }, 0, nil) == nil and ShopPick.hero({}, 100, nil) == nil)
check("locked things are never the best buy", ShopPick.hero({ { name = "A", price = 10, locked = true, forSale = true } }, 100, nil) == nil)

-- ── The rows ────────────────────────────────────────────────────────────────
check("a price you can pay now is green", ShopPick.tone(shop[2], 500) == "money")
check("… too dear, or away from the counter: dim", ShopPick.tone(shop[3], 100) == "dim" and ShopPick.tone(shop[4], 5000) == "dim")
check("locked: the lock", ShopPick.tone(shop[5], 99999) == "lock")
check("no price: none", ShopPick.tone(shop[1], 500) == "none")
check("the rows keep the catalog's order, the locked ones last", table.concat(ShopPick.order(shop), ",") == "1,2,3,4,5"
	and table.concat(ShopPick.order({ shop[5], shop[2], shop[3] }), ",") == "2,3,1")
check("the hero's bar: your money toward the price", ShopPick.share(shop[4], 450) == 0.5 and ShopPick.share(shop[2], 900) == 1 and ShopPick.share(shop[1], 0) == 1)

-- 6.19: a gun or a car a mission unlocks ("🔒 Finish Mail Call"; its button opens MISSIONS, so client/ShopView.luau
-- never calls it buyable): the lock's tone, last, never the best buy nor the one to save up for; the goal only by name.
do
	local guns: { ShopPick.Entry } = {
		{ name = "SMG", price = 8000, forSale = true, locked = true, buyable = false },
		{ name = "Shotgun", price = 15000, forSale = true, locked = true, buyable = false },
	}
	check("6.19: a mission's lock reads as a lock and sorts last", ShopPick.tone(guns[1], 99999) == "lock" and table.concat(ShopPick.order(guns), ",") == "1,2")
	check("6.19: … never the best buy or the cheapest to save up for", ShopPick.hero(guns, 99999, nil) == nil)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
