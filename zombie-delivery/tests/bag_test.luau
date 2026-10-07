-- Logic test of 5.3, the bag (shared/Bag.luau): what fits a bag, the bike's own bag on a run, the HUD's chip and the
-- inventory's groups. 6.6: no backpack any more (no Bag.fits, Bag.room, Bag.makeRoom, Config.Cargo.PackLooks): every
-- light look fits your bag and the bike's, a heavy one only the hands.
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

-- 6.6: no backpack ---------------------------------------------------------------------------------

check("6.6: no backpack looks any more", (Cargo :: any).PackLooks == nil and (Bag :: any).fits == nil and (Bag :: any).room == nil and (Bag :: any).makeRoom == nil)

-- 6.3, a bag: every light look (a bouquet, a cake, groceries too), never a heavy one ----------------------------------

local bagOk = true
for look in Cargo.LightLooks do
	if not Bag.fitsBag(look) then
		bagOk = false
		print("  light, not in the bag: " .. look)
	end
end
check("6.3: every light look goes into a bag", bagOk)
for _, look in { "mail", "newspaper", "pizza", "bouquet", "cake", "gadget", "groceries", "icecream" } do
	check(`6.6: {look} goes into a bag (yours or the bike's)`, Bag.fitsBag(look))
end
for _, look in { "barrel", "crate", "furniture", "ammo", "cooler", "pallet" } do
	check(`6.3: {look} never goes into a bag`, not Bag.fitsBag(look) and not Cargo.LightLooks[look])
end
check("6.3: no look, no bag", not Bag.fitsBag(nil))

-- 6.6: the bike's own bag on a run (its rack / basket / box with its bike gear: Transport.bikeRoom) --------------------

check("rack: a bike run has the bike's own bag", Bag.rack("bike", false, 2) == 2 and Bag.rack("bike", true, 4) == 4)
check("rack: a foot run ridden too", Bag.rack("foot", true, 2) == 2)
check("rack: walking with a bike at home, none", Bag.rack("foot", false, 2) == 0)
check("rack: no bike, none", Bag.rack("bike", true, nil) == 0 and Bag.rack("foot", true, nil) == 0)
check("rack: never below 0, whole pieces", Bag.rack("bike", true, -1) == 0 and Bag.rack("bike", true, 2.7) == 2)
check("rack: a car run, none", Bag.rack("car", true, 5) == 0)

-- The chip and the groups ------------------------------------------------------------------------------

check("nothing carried: no chip", Bag.line({}) == nil and Bag.line(nil) == nil)
local carried = {
	{ order = 1, look = "newspaper", name = "newspaper", where = "pack" },
	{ order = 1, look = "newspaper", name = "newspaper", where = "pack" },
	{ order = 2, look = "pizza", name = "pizza stack", where = "hands" },
}
check("the chip counts by name (6.6: no backpack mark)", Bag.line(carried) == "📦 2 newspapers · 1 pizza stack", Bag.line(carried))
check("plurals from Config", Bag.plural("medicine box") == "medicine boxes" and Bag.plural("noodle box") == "noodle boxes" and Bag.plural("bouquet") == "bouquets")
check("a name Config does not know", Bag.plural("brush") == "brushes" and Bag.plural("cup") == "cups")
local many = {}
for _, name in { "a", "b", "c", "d", "d" } do
	table.insert(many, { name = name, where = "pack" })
end
check("three kinds at most, then +N more", Bag.line(many) == "📦 1 a · 1 b · 1 c · +2 more", Bag.line(many))
local groups = Bag.groups({
	{ name = "bouquet", where = "rack" },
	{ name = "pizza stack", where = "hands" },
	{ name = "cake", where = "bag" },
	{ name = "parcel", where = "pack" },
	{ name = "crate", where = "vehicle" },
	{ name = "odd", where = "moon" },
}, "bike")
check("the groups: hands, bag, the bike's bag, the satchel, vehicle", #groups == 5 and groups[1].where == "hands" and groups[2].where == "bag" and groups[3].where == "rack" and groups[4].where == "pack" and groups[5].where == "vehicle")
check("an unknown place goes with the satchel's", #groups[4].pieces == 2)
check("6.6: the marks ✋ 🛍 🚲, no backpack", groups[1].icon == "✋" and groups[2].icon == "🛍" and groups[3].icon == "🚲" and groups[3].title == "In your bike's bag")
for _, group in groups do
	check(`6.6: the {group.where} group never says backpack`, string.find(string.lower(group.title), "backpack", 1, true) == nil, group.title)
end
check("no pieces, no groups", #Bag.groups(nil, nil) == 0)

-- 6.0.1, the bottom bar (6.6: hands, the bag, the bike's bag, a round's satchel) ----------------------------------

local places = Bag.places("foot", 4, 0, 4)
check("places: hands, bag, the bike's bag, the satchel", #places == 4 and places[1].where == "hands" and places[2].where == "bag" and places[3].where == "rack" and places[4].where == "pack")
check("6.6: room on foot = the hands + the bag", places[1].room == Cargo.HandsMax and places[2].room == 4 and places[3].room == 0 and places[4].room == 0)
local bike = Bag.places("bike", 6, 2, 4)
check("places by bike: the bike's bag and your bag", bike[3].room == 2 and bike[2].room == 4 and bike[4].room == 0)
local round = Bag.places("foot", 8, 0, 2)
check("a round: the satchel takes the rest", round[2].room == 2 and round[4].room == 6)
local squeezed = Bag.places("bike", 3, 2, 5)
check("the bag never more than the room left over the bike's", squeezed[3].room == 2 and squeezed[2].room == 1 and squeezed[4].room == 0)
local car = Bag.places("car", 6, 0, 2)
check("places in a car: the hands only", car[1].room == Cargo.HandsMax and car[2].room == 0 and car[3].room == 0 and car[4].room == 0)

local carried = {
	{ order = 1, look = "pizza", name = "pizza stack", where = "hands" },
	{ order = 2, look = "mail", name = "letter", where = "pack" },
	{ order = 1, look = "bouquet", name = "bouquet", where = "rack" },
	{ order = 1, look = "crate", name = "crate", where = "vehicle" },
}
local tiles, more = Bag.strip(carried, Bag.places("bike", 3, 2, 1), 1, 8)
check("strip: a tile a piece and a free place, no vehicle", #tiles == 5 and more == 0, #tiles)
check("strip: hands first, then the free hand", tiles[1].where == "hands" and tiles[1].piece ~= nil and tiles[2].where == "hands" and tiles[2].piece == nil)
check("strip: a piece without a place yet fills the bag", tiles[3].where == "bag" and tiles[3].piece ~= nil and tiles[3].piece.name == "letter")
check("strip: another order's piece is marked", tiles[3].other and not tiles[1].other and not tiles[4].other)
check("strip: the bike's bag after the bag, then its free room", tiles[4].where == "rack" and tiles[4].piece ~= nil and tiles[5].where == "rack" and tiles[5].piece == nil)
check("strip: no focus, nothing is another order's", not (Bag.strip(carried, Bag.places("bike", 3, 2, 1), nil, 8))[3].other)

local many = {}
for i = 1, 6 do
	table.insert(many, { order = 1, look = "mail", name = "letter", where = if i <= 2 then "hands" else "bag" })
end
local full, cut, cutPieces = Bag.strip(many, Bag.places("foot", 8, 0, 8), 1, 8)
check("strip over 8: 7 tiles and +N", #full == 7 and cut == 3, `{#full} +{cut}`)
check("strip over 8: the free room goes first", cutPieces == 0 and full[6].piece ~= nil and full[7].piece == nil)
for i = 1, 6 do
	table.insert(many, { order = 1, look = "mail", name = "letter", where = "bag" })
end
local packed, cut2, cutPieces2 = Bag.strip(many, Bag.places("foot", 8, 0, 8), 1, 8)
check("strip with more pieces than tiles: the last pieces go too", #packed == 7 and cut2 == 5 and cutPieces2 == 5, `{#packed} +{cut2} ({cutPieces2})`)
local overflow = Bag.strip({ { where = "rack" }, { where = "moon" } }, Bag.places("foot", 0, 0, 0), nil, 8)
check("strip: a piece with no room still shows", #overflow == 4 and overflow[3].where == "rack" and overflow[4].where == "pack", #overflow)
check("strip of nothing: the free hands", #(Bag.strip(nil, Bag.places("car", 0, 0, 0), nil, 8)) == Cargo.HandsMax)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
