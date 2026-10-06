-- Logic test of 5.3, the bag (shared/Bag.luau, Config.Cargo.PackLooks): what fits a backpack, how many pieces of a look
-- an order may have on foot, by bike and by car, the HUD's chip and the inventory's groups.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Bag = require("./Bag")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Cargo = Config.Cargo

-- What fits ----------------------------------------------------------------------------------------

for _, look in { "mail", "newspaper", "documents", "medicine", "pizza", "burger", "noodles", "bread", "parcel" } do
	check(`{look} fits a backpack`, Bag.fits(look))
end
for _, look in { "bouquet", "cake", "gadget", "groceries", "icecream", "barrel", "crate" } do
	check(`{look} does not`, not Bag.fits(look))
end
check("nothing fits for no look", not Bag.fits(nil))
check("every look that fits a backpack is light", (function()
	for look in Cargo.PackLooks do
		if not Cargo.LightLooks[look] then
			print("  heavy in the pack: " .. look)
			return false
		end
	end
	return true
end)())

-- The room of one order ------------------------------------------------------------------------------

check("on foot a pack look takes the hands and the backpack", Bag.room("pizza", "foot", 4, nil) == 4)
check("on foot a bouquet only the hands", Bag.room("bouquet", "foot", 4, nil) == Cargo.HandsMax)
check("on foot without a backpack: the hands either way", Bag.room("bouquet", "foot", 2, nil) == 2 and Bag.room("mail", "foot", 2, nil) == 2)
check("by bike a pack look takes it all", Bag.room("parcel", "bike", 5, 1) == 5)
check("on the e-scooter (1 on the rack): one bouquet", Bag.room("bouquet", "bike", 4, 1) == 1)
check("the cargo bike's box takes four", Bag.room("groceries", "bike", 7, 4) == 4)
check("a car takes its room", Bag.room("bouquet", "car", 6, nil) == 6)

-- 5.3 review: the rack (the bike's own room) only on a bike run, or a foot run while you ride; walking, none.
check("rack: a bike run has the bike's own room", Bag.rack("bike", false, 5, 3) == 2 and Bag.rack("bike", true, 5, 3) == 2)
check("rack: a foot run ridden too", Bag.rack("foot", true, 5, 3) == 2)
check("rack: walking with a bike at home, none", Bag.rack("foot", false, 5, 3) == 0)
check("rack: no bike, none", Bag.rack("bike", true, nil, 3) == 0 and Bag.rack("foot", true, nil, 3) == 0)
check("rack: never below 0", Bag.rack("bike", true, 2, 3) == 0)
check("rack: a car run, none", Bag.rack("car", true, 5, 3) == 0)

-- 5.3 review: hands full of pizzas, a bouquet next (it does not fit the backpack): pizzas go into the backpack first.
check("makeRoom: two pizzas in hand, hands for two: one goes in", Bag.makeRoom({ "pizza", "pizza" }, 2, 3) == 1)
check("makeRoom: … a piece that takes both hands: both go in", Bag.makeRoom({ "pizza", "pizza" }, 1, 3) == 2)
check("makeRoom: … not with the backpack full", Bag.makeRoom({ "pizza", "pizza" }, 2, 0) == 0)
check("makeRoom: … nor room for only one of two", Bag.makeRoom({ "pizza", "pizza" }, 1, 1) == 0)
check("makeRoom: a cake in hand does not go in", Bag.makeRoom({ "cake", "cake" }, 2, 3) == 0)
check("makeRoom: one of each: the pizza goes", Bag.makeRoom({ "cake", "pizza" }, 2, 3) == 1)
check("makeRoom: a free hand already: nothing", Bag.makeRoom({ "pizza" }, 2, 3) == 0 and Bag.makeRoom({}, 1, 3) == 0)
check("makeRoom: a horse (no look) never goes in", Bag.makeRoom({ nil }, 1, 3) == 0)

-- The chip and the groups ------------------------------------------------------------------------------

check("nothing carried: no chip", Bag.line({}) == nil and Bag.line(nil) == nil)
local carried = {
	{ order = 1, look = "newspaper", name = "newspaper", where = "pack" },
	{ order = 1, look = "newspaper", name = "newspaper", where = "pack" },
	{ order = 2, look = "pizza", name = "pizza stack", where = "hands" },
}
check("the chip counts by name", Bag.line(carried) == "🎒 2 newspapers · 1 pizza stack", Bag.line(carried))
check("plurals from Config", Bag.plural("medicine box") == "medicine boxes" and Bag.plural("noodle box") == "noodle boxes" and Bag.plural("bouquet") == "bouquets")
check("a name Config does not know", Bag.plural("brush") == "brushes" and Bag.plural("cup") == "cups")
local many = {}
for _, name in { "a", "b", "c", "d", "d" } do
	table.insert(many, { name = name, where = "pack" })
end
check("three kinds at most, then +N more", Bag.line(many) == "🎒 1 a · 1 b · 1 c · +2 more", Bag.line(many))
local groups = Bag.groups({
	{ name = "bouquet", where = "rack" },
	{ name = "pizza stack", where = "hands" },
	{ name = "parcel", where = "pack" },
	{ name = "crate", where = "vehicle" },
	{ name = "odd", where = "moon" },
}, "bike")
check("the groups: hands, backpack, rack, vehicle", #groups == 4 and groups[1].where == "hands" and groups[2].where == "pack" and groups[3].where == "rack" and groups[4].where == "vehicle")
check("an unknown place goes with the backpack", #groups[2].pieces == 2)
check("the rack of a bike says so", groups[3].title == "On your bike")
check("no pieces, no groups", #Bag.groups(nil, nil) == 0)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
