-- 6.1, what you hold (shared/Holding.luau): fists / bag / gun, the keys, who may take what, the d-pad's cycle, a new
-- body, B's holster, a bag leaving the hand (set down loaded, stowed empty), where a piece goes (6.6: the bike's own bag
-- within reach, the bag in your hand, the hands; no backpack), the room on foot (6.6: hands + bag) and what X says. Run with tests/run_tests.py.
local Holding = require("./Holding")
local Config = require("./Config")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- The hands and their keys -----------------------------------------------------------------------------------------

check("three hands: fists, bag, gun", #Holding.Order == 3 and Holding.Order[1] == "fists" and Holding.Order[2] == "bag" and Holding.Order[3] == "gun")
check("key 1 fists, 2 bag, 3 gun", Holding.ofKey(1) == "fists" and Holding.ofKey(2) == "bag" and Holding.ofKey(3) == "gun" and Holding.ofKey(4) == nil)
check("and back", Holding.keyOf("fists") == 1 and Holding.keyOf("bag") == 2 and Holding.keyOf("gun") == 3 and Holding.keyOf("phone") == nil)
check("valid hands only", Holding.valid("bag") and not Holding.valid("phone") and not Holding.valid(nil) and not Holding.valid(2))

-- Who may take what ------------------------------------------------------------------------------------------------

check("fists always", (Holding.can("fists", false, false, false)))
check("the bag only when you own it", not Holding.can("bag", false, true, false) and (Holding.can("bag", true, false, false)))
local ok, why = Holding.can("bag", true, true, true)
check("not while it lies on the ground", not ok and why == "bagdown", why)
ok, why = Holding.can("gun", true, false, false)
check("the gun only with a gun", not ok and why == "nogun" and (Holding.can("gun", false, true, false)), why)
check("an unknown hand never", not Holding.can("phone", true, true, false))
check("every refusal says why", string.find(Holding.whyText("bagdown"), "pick it up", 1, true) ~= nil and string.find(Holding.whyText("nogun"), "Lead & Co.", 1, true) ~= nil
	and string.find(Holding.whyText("nobag"), "ZDC Bags", 1, true) ~= nil and #Holding.whyText(nil) > 0)

-- The d-pad's cycle ------------------------------------------------------------------------------------------------

check("right: fists → bag → gun → fists", Holding.cycle("fists", 1, true, true, false) == "bag" and Holding.cycle("bag", 1, true, true, false) == "gun"
	and Holding.cycle("gun", 1, true, true, false) == "fists")
check("left: the other way", Holding.cycle("fists", -1, true, true, false) == "gun" and Holding.cycle("gun", -1, true, true, false) == "bag")
check("it skips what you can't take", Holding.cycle("fists", 1, false, true, false) == "gun" and Holding.cycle("fists", 1, true, false, true) == "fists"
	and Holding.cycle("gun", 1, true, true, true) == "fists")

-- A new body, B's holster ------------------------------------------------------------------------------------------

check("a new body holds the bag when it is yours and with you", Holding.atSpawn(true, false) == "bag" and Holding.atSpawn(false, false) == "fists"
	and Holding.atSpawn(true, true) == "fists")
check("B's holster goes back to the bag you held", Holding.afterHolster("bag", true, false) == "bag")
check("… not to a bag on the ground, nor without one", Holding.afterHolster("bag", true, true) == "fists" and Holding.afterHolster("bag", false, false) == "fists")
check("… else fists", Holding.afterHolster("fists", true, false) == "fists" and Holding.afterHolster(nil, true, false) == "fists")

-- The bag leaving the hand, the room -------------------------------------------------------------------------------

check("a loaded bag is set down", Holding.bagLeaves(1) == "down" and Holding.bagLeaves(2) == "down")
check("an empty one is stowed", Holding.bagLeaves(0) == "stow")
-- 6.6, the bike's own bag within reach (Config.Cargo.BikeReach studs, or you sit on it) --------------------------------

local reach = Config.Cargo.BikeReach
check("6.6: the reach is about 12 studs", reach == 12, reach)
check("6.6: on the bike: always within reach", Holding.bikeNear(true, nil, reach) and Holding.bikeNear(true, 500, reach))
check("6.6: standing by it: within reach", Holding.bikeNear(false, 0, reach) and Holding.bikeNear(false, 6, reach) and Holding.bikeNear(false, reach, reach))
check("6.6: farther: not", not Holding.bikeNear(false, reach + 0.5, reach) and not Holding.bikeNear(false, 80, reach))
-- 6.19: E at your bike's rack (the owner: "on bike jobs I can't put things onto the bike")
check("6.19: holding pieces that fit, room on the bike: load", Holding.bikeAction(1, true, 2, 0, false) == "load" and Holding.bikeAction(2, true, 1, 1, true) == "load")
check("6.19: no room, or a heavy piece: nothing to do there", Holding.bikeAction(1, true, 0, 3, false) == nil and Holding.bikeAction(1, false, 3, 0, false) == nil)
check("6.19: empty hands at a drop with pieces on the bike: take one off", Holding.bikeAction(0, false, 0, 2, true) == "take")
check("6.19: … not at a pick-up, nor with an empty bike", Holding.bikeAction(0, false, 2, 2, false) == nil and Holding.bikeAction(0, false, 3, 0, true) == nil)
local loadText, loadObject = Holding.bikeText("load", "pizza", 2, 3)
local takeText = Holding.bikeText("take", "pizza", 2, 3)
check("6.19: the prompt says it and counts", loadText == "Load onto bike" and takeText == "Take off bike" and loadObject == "Your bike: pizza 2 / 3")
check("6.6: no bike out (no distance), not; a broken distance, not", not Holding.bikeNear(false, nil, reach) and not Holding.bikeNear(false, 0 / 0, reach))

-- 6.6, where a pickup goes: the bike within reach, else the bag in your hand, else the hands -------------------------

local Bag = require("./Bag")
check("6.6: the bike near with room: onto the bike (even with the bag in your hand)", Holding.place(true, true, 1, true, 4) == "bike" and Holding.place(true, true, 3, false, 0) == "bike")
check("6.6: the bike near but full: into the bag in your hand", Holding.place(true, true, 0, true, 2) == "bag")
check("6.6: the bike too far: into the bag in your hand", Holding.place(true, false, 3, true, 1) == "bag")
check("6.6: … else the hands", Holding.place(true, false, 3, false, 4) == "hands" and Holding.place(true, false, 0, true, 0) == "hands" and Holding.place(true, true, 0, false, 2) == "hands")
check("6.6: a bouquet, a cake, groceries: like a pizza (every light look fits)", Holding.place(Bag.fitsBag("bouquet"), false, 0, true, 2) == "bag" and Holding.place(Bag.fitsBag("cake"), true, 1, true, 2) == "bike"
	and Holding.place(Bag.fitsBag("groceries"), false, 0, true, 1) == "bag" and Holding.place(Bag.fitsBag("pizza"), false, 0, true, 1) == "bag")
check("6.6: a heavy piece only the hands", Holding.place(Bag.fitsBag("crate"), true, 4, true, 4) == "hands" and Holding.place(Bag.fitsBag("barrel"), true, 4, true, 4) == "hands")
check("6.6: no backpack: never \"pack\"", (function()
	for _, light in { true, false } do
		for _, near in { true, false } do
			for _, held in { true, false } do
				for free = 0, 2 do
					local where = Holding.place(light, near, free, held, free)
					if where ~= "bike" and where ~= "bag" and where ~= "hands" then
						return false
					end
				end
			end
		end
	end
	return true
end)())

-- 6.6, your room on foot: the hands + the bag (one carrying item) ------------------------------------------------

local Transport = require("./Transport")
check("6.6: no bag: the hands", Transport.handsRoom({}, nil) == Config.Cargo.HandsMax)
check("6.6: room = hands + bag", Transport.handsRoom({ bag = true }, nil) == Config.Cargo.HandsMax + 2 and Transport.handsRoom({ bag = true, duffel = true }, "duffel") == Config.Cargo.HandsMax + 6)
check("6.6: the room over the hands is the bag's", Transport.packRoom({ tote = true }, nil) == 3 and Transport.packRoom({}, nil) == 0)
check("6.6: an old backpack in a kit adds nothing", Transport.handsRoom({ backpack = true, bigpack = true } :: any, nil) == Config.Cargo.HandsMax)

-- What X says -------------------------------------------------------------------------------------------------------

local range = Config.Throw.Range
local near = `Get within {range} studs of the delivery door to throw.`
check("at a door in range: aim", Holding.throwText("piece", true, false, false, range) == nil)
check("at a door too far: come closer", Holding.throwText("piece", true, true, false, range) == near)
check("at a door, only fragile pieces: too fragile", string.find(Holding.throwText(nil, true, false, true, range) or "", "Too fragile", 1, true) == 1)
check("no door here but something to throw: come within the range", Holding.throwText("piece", false, false, false, range) == near)
check("no door here, only fragile: too fragile", string.find(Holding.throwText("fragile", false, false, false, range) or "", "Too fragile", 1, true) == 1)
check("nothing to throw: says so", string.find(Holding.throwText(nil, false, false, false, range) or "", "Nothing to throw", 1, true) == 1)
check("the toast names the range (45)", string.find(near, tostring(range), 1, true) ~= nil and range == 45)

-- The numbers ---------------------------------------------------------------------------------------------------------

local H = Config.Hand
check("the hand's numbers", H.Cooldown > 0 and H.Cooldown < 1 and H.Predict > 0.5 and H.BagAhead > 0 and H.BagHold >= 0 and H.BagReach >= 6)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
