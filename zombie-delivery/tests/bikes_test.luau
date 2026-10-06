-- 5.1, Spoke & Chain and the bike jobs: the bike gear (Config.Gear bikeOnly) and its rules (Economy.gearFits,
-- Economy.capacity with the bike gear's room), shared/Transport.luau's mode "bike", the bike shop on the map, the
-- BIKE jobs' numbers (Config.Jobs.Bike through JobRules.footPay / footTime / footPieces, bikeXp) and the career road.
-- The bikes themselves are Config.Cars entries (stream V); when this copy has none, the test adds stubs of them here.
-- Run with tests/run_tests.py.
local Config = require("./Config")
local Economy = require("./Economy")
local Transport = require("./Transport")
local JobRules = require("./JobRules")
local Levels = require("./Levels")
local Map = require("./Map")
local Career = require("./Career")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- The bikes (stubs only when Config.Cars has none yet).
local STUBS = {
	{ id = "rustbike", level = 2, price = 300, capacity = 1, gearSlots = 1 },
	{ id = "citybike", level = 2, price = 1100, capacity = 1, gearSlots = 2 },
	{ id = "cargobike", level = 3, price = 2400, capacity = 4, gearSlots = 2 },
	{ id = "ebike", level = 5, price = 6500, capacity = 1, gearSlots = 2 },
}
for _, stub in STUBS do
	if not Economy.findCar(stub.id) then
		table.insert(Config.Cars, {
			id = stub.id, name = stub.id, bike = true, level = stub.level, price = stub.price, capacity = stub.capacity, gearSlots = stub.gearSlots,
			style = "bike", maxSpeed = 30, accel = 16, turn = 2, health = 100, ramPower = 0.2, color = { 150, 60, 40 }, description = "a stub",
		} :: any)
	end
end
for _, stub in STUBS do
	local def = Economy.findCar(stub.id) :: Config.CarDef
	check(`{stub.id}: a bike, level {stub.level}, ${stub.price}, room {stub.capacity}, {stub.gearSlots} gear slots`, def.bike == true and def.level == stub.level
		and def.price == stub.price and def.capacity == stub.capacity and def.gearSlots == stub.gearSlots)
end
check("the van is still the first car", Config.Cars[1].id == "van" and not Config.Cars[1].bike)

-- The bike gear ------------------------------------------------------------------------------------------------------

local function gear(id: string): Config.GearDef
	return Economy.findGear(id) :: Config.GearDef
end
check("basket L2 $150 +2, panniers L3 $450 +3, trailer L4 $1,200 +4", gear("basket").level == 2 and gear("basket").price == 150 and gear("basket").room == 2
	and gear("panniers").level == 3 and gear("panniers").price == 450 and gear("panniers").room == 3
	and gear("trailer").level == 4 and gear("trailer").price == 1200 and gear("trailer").room == 4)
check("all three are bike gear", gear("basket").bikeOnly == true and gear("panniers").bikeOnly == true and gear("trailer").bikeOnly == true)
check("bike gear fits a bike", Economy.gearFits("rustbike", "basket") and Economy.gearFits("citybike", "panniers") and Economy.gearFits("ebike", "trailer"))
check("… not a car", not Economy.gearFits("van", "basket") and not Economy.gearFits("courier", "panniers") and not Economy.gearFits("freight", "trailer"))
check("no trailer on the Cargo Bike", not Economy.gearFits("cargobike", "trailer") and Economy.gearFits("cargobike", "basket"))
local carGearOnBike = false
for _, def in Config.Gear do
	if not def.bikeOnly then
		for _, stub in STUBS do
			carGearOnBike = carGearOnBike or Economy.gearFits(stub.id, def.id)
		end
	end
end
check("the car gear never goes on a bike", not carGearOnBike)
check("the slots: Rusty 1, the others 2", Economy.gearSlots("rustbike", 0) == 1 and Economy.gearSlots("citybike", 0) == 2 and Economy.gearSlots("cargobike", 0) == 2)

-- The room -------------------------------------------------------------------------------------------------------------

local basket = { basket = true }
local both = { basket = true, panniers = true }
check("a bike's own room", Economy.capacity("rustbike", {}) == 1 and Economy.capacity("cargobike", {}) == 4)
check("the gear adds its room for a light look or none", Economy.capacity("rustbike", {}, basket) == 3 and Economy.capacity("rustbike", {}, basket, "pizza") == 3
	and Economy.capacity("citybike", {}, both, "parcel") == 6)
check("… not for a heavy look", Economy.capacity("rustbike", {}, basket, "crate") == 1)
check("… not a piece that does not fit", Economy.capacity("cargobike", {}, { trailer = true }) == 4)
check("bike gear in a car's list counts for nothing", Economy.capacity("van", { stage = 3 }, basket, "parcel") == 4)
check("Economy.bikeRoom", Economy.bikeRoom("citybike", both) == 5 and Economy.bikeRoom("van", both) == 0 and Economy.bikeRoom("citybike", nil) == 0)
check("no bike is advice for a bigger car", string.find(Economy.roomAdvice("van", 0, 4), "bike", 1, true) == nil)

-- shared/Transport.luau, mode "bike" ------------------------------------------------------------------------------------

check("isBike", Transport.isBike("rustbike") and Transport.isBike("ebike") and not Transport.isBike("van") and not Transport.isBike(nil) and not Transport.isBike("nope"))
local carGear: Economy.CarGear = { rustbike = { basket = "installed" }, citybike = { basket = "owned" } }
check("bikeRoom: the bike and its installed gear", Transport.bikeRoom("rustbike", carGear) == 3 and Transport.bikeRoom("citybike", carGear) == 1
	and Transport.bikeRoom("van", carGear) == 0 and Transport.bikeRoom(nil, carGear) == 0)
local plain = Transport.bike(3, {})
local packed = Transport.bike(3, { bigpack = true, shoes = true })
check("on a bike: its room + the pack, light only, no kit speed", plain.mode == "bike" and plain.room == 3 and plain.lightOnly and plain.speedMult == 1
	and packed.room == 3 + (4 - Config.Cargo.HandsMax) and packed.speedMult == 1)

-- The shop -------------------------------------------------------------------------------------------------------------

local shop = Map.Shops.bikes
check("Spoke & Chain is Downtown block (-1, 1)", shop ~= nil and shop.x == -Map.Cell and shop.z == Map.Cell and Map.special("downtown", -1, 1) == "bikes")
local landmark = false
for _, entry in Map.Landmarks do
	landmark = landmark or (entry.id == "bikes" and entry.kind == "shop")
end
check("… a landmark (the GPS, the location tag)", landmark)
check("… in the safe zone", Map.isSafe(shop.x, shop.z))
check("Marge's text names the price", string.find(Config.BikeShop.Unlock, "{price}", 1, true) ~= nil and string.find(Config.BikeShop.Unlock, Config.BikeShop.Street, 1, true) ~= nil)

-- The BIKE jobs ---------------------------------------------------------------------------------------------------------

local bike = Config.Jobs.Bike
check("from level 2, 2 – 6 pieces, 300 – 1,000 studs", bike.Level == 2 and bike.Pieces[1] == 2 and bike.Pieces[2] == 6 and bike.MinDistance == 300 and bike.MaxDistance == 1000)
check("pay $45 + $0.15 / stud", bike.BasePay == 45 and bike.PayPerStud == 0.15)
local short, long = JobRules.footPay(400, 2, 1, bike), JobRules.footPay(1000, 4, 1, bike)
check("a longer ride pays more, $5 steps, within PayMin … PayMax × PayTop", short < long and short % 5 == 0 and long % 5 == 0 and short >= bike.PayMin
	and JobRules.footPay(5000, 6, 3, bike) <= bike.PayMax * bike.PayTop, `{short} {long}`)
check("better than a walk of the same length", JobRules.footPay(400, 2, 1, bike) >= JobRules.footPay(400, 2, 1))
check("the clock expects a ride, not a walk", JobRules.footTime(800, 10, nil, bike) < JobRules.footTime(800, 10))
check("pieces: Bike.Pieces by the bike's room", JobRules.footPieces(6, 4, bike) == 4 and JobRules.footPieces(1, 9, bike) == 2 and JobRules.footPieces(9, 9, bike) == 6
	and JobRules.footPieces(3, 1, bike) == 1)
check("the foot jobs' numbers stay the default", JobRules.footPieces(9, 9) == Config.Jobs.Foot.Pieces[2])
local xpLow = JobRules.bikeXp(Levels.jobXp(1, 2, 0, false, true))
local xpHigh = JobRules.bikeXp(Levels.jobXp(1, 6, 0, false, true))
check("XP about 100 – 130", xpLow >= 95 and xpLow <= 110 and xpHigh >= 120 and xpHigh <= 145, `{xpLow} {xpHigh}`)

-- The career road -------------------------------------------------------------------------------------------------------

local road = Career.road()
local function has(level: number, kind: string, id: string): boolean
	for _, unlock in road[level].unlocks do
		if unlock.kind == kind and unlock.id == id then
			return true
		end
	end
	return false
end
check("L2: the Rusty and the Courier Bike at Spoke & Chain", has(2, "bike", "rustbike") and has(2, "bike", "citybike"))
check("L3 the Cargo Bike, L5 the E-Bike", has(3, "bike", "cargobike") and has(5, "bike", "ebike"))
check("the bike gear at its levels", has(2, "gear", "basket") and has(3, "gear", "panniers") and has(4, "gear", "trailer"))
check("a bike is never a car on the road", not has(2, "car", "rustbike"))
check("Career.BIKE_LEVEL is the BIKE jobs' level", Career.BIKE_LEVEL == bike.Level)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
