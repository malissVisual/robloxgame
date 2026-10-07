-- 6.1, what you hold (shared/Holding.luau): fists / bag / gun, the keys, who may take what, the d-pad's cycle, a new
-- body, B's holster, a bag leaving the hand (set down loaded, stowed empty), the room that is yours, where a piece goes
-- and what X says. Run with tests/run_tests.py.
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
	and string.find(Holding.whyText("nobag"), "Last Stop", 1, true) ~= nil and #Holding.whyText(nil) > 0)

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
check("the bag's room is yours while you hold it", Holding.packRoom(3, 2, true) == 3 and Holding.packRoom(3, 2, false) == 1)
check("only the bag: none without it", Holding.packRoom(2, 2, false) == 0 and Holding.packRoom(2, 2, true) == 2)
check("never below zero, a bag bigger than the room counts as the room", Holding.packRoom(1, 2, false) == 0 and Holding.packRoom(0, 2, true) == 0)
check("a piece goes into the bag in your hand while it has room and the piece fits", Holding.place(true, 0, 2, true) == "bag" and Holding.place(true, 1, 2, true) == "bag")
check("… else the backpack", Holding.place(true, 2, 2, true) == "pack" and Holding.place(false, 0, 2, true) == "pack" and Holding.place(true, 0, 2, false) == "pack")

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
