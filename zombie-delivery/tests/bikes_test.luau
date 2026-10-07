-- 5.1, Spoke & Chain and the bike jobs: the bike gear (Config.Gear bikeOnly) and its rules (Economy.gearFits,
-- Economy.capacity with the bike gear's room), shared/Transport.luau's mode "bike", the bike shop on the map, the
-- BIKE jobs' numbers (Config.Jobs.Bike through JobRules.footPay / footTime / footPieces, bikeXp) and the career road.
-- The bikes themselves are Config.Cars entries (stream V); when this copy has none, the test adds stubs of them here.
-- 5.1.1: the E-Scooter (escooter: a bike by the rules, style "scooter", the rider stands: shared/RiderPose.luau).
-- Run with tests/run_tests.py.
local Config = require("./Config")
local Economy = require("./Economy")
local Transport = require("./Transport")
local JobRules = require("./JobRules")
local Levels = require("./Levels")
local Map = require("./Map")
local Career = require("./Career")
local RiderPose = require("./RiderPose")

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
	{ id = "escooter", level = 4, price = 2800, capacity = 2, gearSlots = 1 }, -- 5.1.1 (5.7: two on its rack)
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

-- 5.1.1, the E-Scooter ---------------------------------------------------------------------------------------------------

local scooter = Economy.findCar("escooter") :: Config.CarDef
check("the E-Scooter: a bike, level 4, about $2,800", scooter ~= nil and scooter.bike == true and scooter.level == 4
	and math.abs(scooter.price - 2800) <= 300 and not scooter.company)
check("… style scooter, the rider stands, the badge", scooter.style == "scooter" and scooter.stand == true
	and string.find(scooter.badge or "", "ELECTRIC", 1, true) ~= nil and string.find(scooter.badge or "", "STAND-UP", 1, true) ~= nil)
check("… speed ~32 (6.0: not too fast), accel ~42 (a quick start), turn ~2.8, health ~110", math.abs(scooter.maxSpeed - 32) <= 2 and math.abs(scooter.accel - 42) <= 2
	and math.abs(scooter.turn - 2.8) <= 0.15 and math.abs(scooter.health - 110) <= 15)
local quickest, standing = true, 0
for _, def in Config.Cars do
	if def.bike and def.id ~= "escooter" then
		quickest = quickest and scooter.accel > def.accel and scooter.turn > def.turn
	end
	if def.stand then
		standing += 1
		check(`{def.id}: only a bike may stand`, def.bike == true and def.style == "scooter")
	end
end
check("… the nippiest of the two-wheelers (accel and turn), slower than the E-Bike", quickest and scooter.maxSpeed < (Economy.findCar("ebike") :: Config.CarDef).maxSpeed)
check("… the only stand-up one", standing == 1)
check("… no stages, no car gun, no trolley", scooter.stages == nil and not scooter.mount and not scooter.trolley)
check("… two light pieces of its own (5.7), one gear slot", scooter.capacity == 2 and Economy.gearSlots("escooter", 0) == 1 and Economy.capacity("escooter", {}) == 2)
check("… the basket fits (a handlebar bag), the panniers and the trailer do not", Economy.gearFits("escooter", "basket")
	and not Economy.gearFits("escooter", "panniers") and not Economy.gearFits("escooter", "trailer"))
check("… no car gear on it", not Economy.gearFits("escooter", "roofrack") and not Economy.gearFits("escooter", "straps"))
-- Slots = capacity + gear: its own rack's two, the basket's two (what Vehicles.cargoSlots lays out: bike-check.luau).
check("… room: 2, with the basket 4, the panniers never count", Economy.capacity("escooter", {}, { basket = true }, "parcel") == 4
	and Economy.capacity("escooter", {}, { basket = true, panniers = true, trailer = true }, "parcel") == 4
	and Economy.bikeRoom("escooter", { basket = true }) == 2)
local scooterGear: Economy.CarGear = { escooter = { basket = "installed", panniers = "installed" } }
check("… Transport mode bike: 4 on the scooter + the pack", Transport.isBike("escooter") and Transport.bikeRoom("escooter", scooterGear) == 4
	and Transport.bike(Transport.bikeRoom("escooter", scooterGear), { bigpack = true }).room == 4 + Transport.packRoom({ bigpack = true }))
-- 5.7: the speed ladder on two wheels (the owner: the scooter "a bit slower, so it isn't too much").
local function top(id: string): number
	return (Economy.findCar(id) :: Config.CarDef).maxSpeed
end
check("5.7: a free rental (capped) < the Rusty Bike < the E-Scooter < the Courier Bike < the E-Bike", Config.Rental.MaxSpeed < top("rustbike")
	and top("rustbike") < top("escooter") and top("escooter") < top("citybike") and top("citybike") < top("ebike"))
check("5.7: a rental's rack takes one piece, the bought scooter's two", Config.Rental.Room == 1 and Config.Rental.Room < scooter.capacity)
-- 6.0: quick off the line, slow at the top: both scooters out-accelerate every other two-wheeler.
local quickStart = true
for _, def in Config.Cars do
	if def.bike and not def.stand then
		quickStart = quickStart and Config.Rental.Accel > def.accel
	end
end
check("6.0: a rental's accel is capped (36), still the quickest start after the bought one", Config.Rental.Accel == 36
	and Config.Rental.Accel <= scooter.accel and quickStart)
check("… on the career road at level 4 (Spoke & Chain), never a car", has(4, "bike", "escooter") and not has(4, "car", "escooter"))
check("… not advice for a bigger car", string.find(Economy.roomAdvice("van", 0, 4), "Scooter", 1, true) == nil)

-- The rider (shared/RiderPose.luau): pedalling on a bike, standing on the scooter.
local deg = math.deg
local stand0, stand1 = RiderPose.pose(true, 0), RiderPose.pose(true, 2.1)
check("standing: no pedalling (the crank changes nothing)", stand0.rightHip.x == stand1.rightHip.x and stand0.leftKnee.x == stand1.leftKnee.x
	and stand0.rightKnee.x == stand1.rightKnee.x)
check("standing: the thighs turned down out of the sit (75° – 95°)", deg(stand0.rightHip.x) <= -75 and deg(stand0.rightHip.x) >= -95
	and deg(stand0.leftHip.x) <= -75 and deg(stand0.leftHip.x) >= -95, deg(stand0.rightHip.x))
check("standing: the knees opened (straight legs, a little soft)", deg(stand0.rightKnee.x) >= 60 and deg(stand0.rightKnee.x) <= 90
	and stand0.leftKnee.x == stand0.rightKnee.x)
check("standing: the legs straighter than a pedaller's", stand0.rightHip.x < RiderPose.pose(false, 0).rightHip.x)
check("standing: a slight forward lean (3° – 15°)", deg(stand0.waist.x) <= -3 and deg(stand0.waist.x) >= -15)
check("standing: both hands forward to the bar, turned in", deg(stand0.rightShoulder.x) >= 40 and stand0.rightShoulder.x == stand0.leftShoulder.x
	and stand0.rightShoulder.y > 0 and stand0.leftShoulder.y == -stand0.rightShoulder.y and stand0.elbow.x > 0)
local pedalA, pedalB = RiderPose.pose(false, math.pi / 2), RiderPose.pose(false, -math.pi / 2)
check("pedalling: the legs pump with the crank, in turn", pedalA.rightHip.x > pedalB.rightHip.x and pedalA.leftHip.x < pedalB.leftHip.x)
check("pedalling: 5.1's pose unchanged", math.abs(deg(RiderPose.pose(false, 0).rightHip.x) + 30) < 1e-6 and math.abs(deg(pedalA.waist.x) + 16) < 1e-6)

-- 5.8.2: the standing rider's two-bone reach (RiderPose.armIk): the hand lands on the point inside the arm's reach.
do
	type V = { x: number, y: number, z: number }
	local function v(x: number, y: number, z: number): V
		return { x = x, y = y, z = z }
	end
	-- The arm hangs along -Y; Rx(a) swings it forward (-Z), Ry(a) turns it.
	local function rx(p: V, a: number): V
		return v(p.x, p.y * math.cos(a) - p.z * math.sin(a), p.y * math.sin(a) + p.z * math.cos(a))
	end
	local function ry(p: V, a: number): V
		return v(p.x * math.cos(a) + p.z * math.sin(a), p.y, -p.x * math.sin(a) + p.z * math.cos(a))
	end
	local function handOf(pitch: number, yaw: number, bend: number, upper: number, lower: number): V
		local down = v(0, -1, 0)
		local e = ry(rx(down, pitch), yaw)
		local f = ry(rx(down, pitch + bend), yaw)
		return v(e.x * upper + f.x * lower, e.y * upper + f.y * lower, e.z * upper + f.z * lower)
	end
	local worst = 0
	for _, t in { v(0.4, -0.6, -1.3), v(-0.3, -0.2, -1.6), v(0.2, -1.2, -0.8) } do
		local pitch, yaw, bend = RiderPose.armIk(t.x, t.y, t.z, 1.1, 1.2)
		local h = handOf(pitch, yaw, bend, 1.1, 1.2)
		worst = math.max(worst, math.sqrt((h.x - t.x) ^ 2 + (h.y - t.y) ^ 2 + (h.z - t.z) ^ 2))
	end
	check("arm IK: the hand reaches points within the arm (error < 0.05)", worst < 0.05, worst)
	local p2, y2, b2 = RiderPose.armIk(0, -1, -9, 1.1, 1.2)
	check("arm IK: out of reach the arm points straight at it", b2 < 0.1 and p2 > math.rad(80) and math.abs(y2) < 1e-3, `{p2} {y2} {b2}`)
	local p3, _, b3 = RiderPose.armIk(0, 0, 0, 1.1, 1.2)
	check("arm IK: a degenerate point falls back", p3 == RiderPose.Upright.Reach and b3 == RiderPose.Upright.Elbow)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
