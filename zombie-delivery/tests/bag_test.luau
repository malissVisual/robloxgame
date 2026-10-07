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

-- 6.3, the plastic bag in your hand: every light look (a bouquet, a cake, groceries too), never a heavy one ------------

local bagOk = true
for look in Cargo.LightLooks do
	if not Bag.fitsBag(look) then
		bagOk = false
		print("  light, not in the bag: " .. look)
	end
end
check("6.3: every light look goes into the bag", bagOk)
for _, look in { "barrel", "crate", "furniture", "ammo", "cooler", "pallet" } do
	check(`6.3: {look} never goes into the bag`, not Bag.fitsBag(look) and not Cargo.LightLooks[look])
end
check("6.3: no look, no bag", not Bag.fitsBag(nil))
check("6.3: the bag takes what the backpack does not (the backpack keeps its looks)", Bag.fitsBag("bouquet") and Bag.fitsBag("cake") and Bag.fitsBag("groceries") and Bag.fitsBag("icecream") and not Bag.fits("bouquet") and not Bag.fits("cake"))
check("6.3: everything the backpack takes, the bag takes", (function()
	for look in Cargo.PackLooks do
		if not Bag.fitsBag(look) then
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

-- 6.0.1, the bottom bar's carried strip ----------------------------------------------------------

local places = Bag.places("foot", 5, 0, 2)
check("places: hands, bag, backpack, rack", #places == 4 and places[1].where == "hands" and places[2].where == "bag" and places[3].where == "pack" and places[4].where == "rack")
check("places on foot: the hands, the bag's 2, the backpack's rest", places[1].room == Cargo.HandsMax and places[2].room == 2 and places[3].room == 3 and places[4].room == 0)
local bike = Bag.places("bike", 4, 2, 5)
check("places by bike: the rack is its part, the bag no more than the rest", bike[4].room == 2 and bike[2].room == 2 and bike[3].room == 0)
local car = Bag.places("car", 6, 0, 2)
check("places in a car: the hands only", car[1].room == Cargo.HandsMax and car[2].room == 0 and car[3].room == 0 and car[4].room == 0)

local carried = {
	{ order = 1, look = "pizza", name = "pizza stack", where = "hands" },
	{ order = 2, look = "mail", name = "letter", where = "pack" },
	{ order = 1, look = "parcel", name = "parcel", where = "pack" },
	{ order = 1, look = "crate", name = "crate", where = "vehicle" },
}
local tiles, more = Bag.strip(carried, Bag.places("foot", 3, 0, 1), 1, 8)
check("strip: a tile a piece and a free place, no vehicle", #tiles == 5 and more == 0, #tiles)
check("strip: hands first, then the free hand", tiles[1].where == "hands" and tiles[1].piece ~= nil and tiles[2].where == "hands" and tiles[2].piece == nil)
check("strip: the pack's first piece fills the bag", tiles[3].where == "bag" and tiles[3].piece ~= nil and tiles[3].piece.name == "letter")
check("strip: another order's piece is marked", tiles[3].other and not tiles[1].other and not tiles[4].other)
check("strip: the backpack after the bag, then its free room", tiles[4].where == "pack" and tiles[4].piece ~= nil and tiles[5].where == "pack" and tiles[5].piece == nil)
check("strip: no focus, nothing is another order's", not (Bag.strip(carried, Bag.places("foot", 3, 0, 1), nil, 8))[3].other)

local many = {}
for i = 1, 6 do
	table.insert(many, { order = 1, look = "mail", name = "letter", where = if i <= 2 then "hands" else "pack" })
end
local full, cut, cutPieces = Bag.strip(many, Bag.places("foot", 8, 0, 0), 1, 8)
check("strip over 8: 7 tiles and +N", #full == 7 and cut == 3, `{#full} +{cut}`)
check("strip over 8: the free room goes first", cutPieces == 0 and full[6].piece ~= nil and full[7].piece == nil)
for i = 1, 6 do
	table.insert(many, { order = 1, look = "mail", name = "letter", where = "pack" })
end
local packed, cut2, cutPieces2 = Bag.strip(many, Bag.places("foot", 8, 0, 0), 1, 8)
check("strip with more pieces than tiles: the last pieces go too", #packed == 7 and cut2 == 5 and cutPieces2 == 5, `{#packed} +{cut2} ({cutPieces2})`)
local overflow = Bag.strip({ { where = "rack" }, { where = "moon" } }, Bag.places("foot", 0, 0, 0), nil, 8)
check("strip: a piece with no room still shows", #overflow == 4 and overflow[3].where == "pack" and overflow[4].where == "rack", #overflow)
check("strip of nothing: the free hands", #(Bag.strip(nil, Bag.places("car", 0, 0, 0), nil, 8)) == Cargo.HandsMax)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
