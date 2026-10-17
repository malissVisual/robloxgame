-- 6.12.7, Dead End Motors sells the bikes too (the owner: "I wanted to merge the bike shop with Motors, so it's one
-- shop"), in the standalone Luau CLI: its two counters, CARS ("dealer", Sal) and BIKES ("bikes", Kip), side by side in
-- its building (Config.BikeShop: the layout server/World.luau buildDealer builds), Map.Shops.bikes at the BIKES
-- counter's front with a radius over the bike stands, the stands clear of the door, the counters, the showroom's
-- turntables and the walls, one shop on the map (no Spoke & Chain landmark; Dead End Motors names the bikes), Spoke &
-- Chain's old block (Map.FormerBikeShop) special and shopless, and the words players read.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Map = require("./Map")
local Style = require("./Style")
local Career = require("./Career")
local LocationTags = require("./LocationTags")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

local B = Config.BikeShop
local dealer, bikes = Map.Shops.dealer, Map.Shops.bikes
local W, D = B.Building.Width, B.Building.Depth
-- Dead End Motors' frame (World buildDealer: shopFrame facing west, the building's middle Back east of its block's
-- middle): its x runs north (the world's -z), its z east (the world's +x).
local function world(x: number, z: number): (number, number)
	return dealer.x + B.Building.Back + z, dealer.z - x
end
-- Inside the walls (1 thick) with its half sizes hx, hz.
local function inside(x: number, z: number, hx: number, hz: number): boolean
	return x - hx >= -W / 2 + 1 and x + hx <= W / 2 - 1 and z - hz >= -D / 2 + 1 and z + hz <= D / 2 - 1
end

-- ── The building ───────────────────────────────────────────────────────────

local district, i, j = Map.blockAt(dealer.x, dealer.z)
check("Dead End Motors on Downtown block (1, 0), its block's middle", district ~= nil and district.id == "downtown" and i == 1 and j == 0
	and dealer.x == Map.Cell and dealer.z == 0 and Map.special("downtown", 1, 0) == "dealer")
local x0, x1 = dealer.x + B.Building.Back - D / 2, dealer.x + B.Building.Back + D / 2
check("its building on its block, a sidewalk round it (the curbs and the roads untouched)", x0 > dealer.x - Map.BlockSize / 2 + 10 and x1 < dealer.x + Map.BlockSize / 2 - 5
	and W / 2 < Map.BlockSize / 2 - 10, `{x0} {x1}`)
check("the building as World built it before (84 × 52 × 18, 22 east of the middle)", W == 84 and D == 52 and B.Building.Height == 18 and B.Building.Back == 22)

-- ── The two counters ───────────────────────────────────────────────────────

local cars, desk = B.Cars, B.Desk
check("the CARS counter where World's counter() puts it (8 in from the back wall, 16 wide, in the middle)", cars.Z == D / 2 - 8 and cars.X == 0 and cars.Width == 16)
check("both counters in the building, at its back", inside(cars.X, cars.Z, cars.Width / 2, 1.5) and inside(desk.X, desk.Z, desk.Width / 2, desk.Deep / 2)
	and cars.Z > D / 4 and desk.Z > D / 4)
check("side by side like the gear stall's: one line, BIKES to the north, a gap between", desk.Z == cars.Z and desk.X - desk.Width / 2 >= cars.X + cars.Width / 2 + 2
	and desk.X - desk.Width / 2 - (cars.X + cars.Width / 2) <= 6)
check("room for each clerk behind (server/ShopClerks.luau: 1.6 behind the back face)", desk.Z + desk.Deep / 2 + 1.6 + 0.6 <= D / 2 - 1 and cars.Z + 1.5 + 1.6 + 0.6 <= D / 2 - 1)
local bx, bz = world(desk.X, desk.Z - desk.Deep / 2)
check("Map.Shops.bikes is the BIKES counter's front, with the bikes' radius", near(bikes.x, bx) and near(bikes.z, bz) and bikes.radius == B.Radius, `{bikes.x} {bikes.z}`)
local d2, i2, j2 = Map.blockAt(bikes.x, bikes.z)
check("… in Dead End Motors' building, on its block", d2 ~= nil and d2.id == "downtown" and i2 == 1 and j2 == 0 and bikes.x > x0 and bikes.x < x1
	and math.abs(bikes.z - dealer.z) < W / 2)
local cx = world(cars.X, cars.Z - 1.5)
check("the CARS counter's front where it always was (the bought car comes out where it did)", near(cx, Map.Cell + 22 + 16.5))
check("named as part of Dead End Motors", string.find(bikes.name, dealer.name, 1, true) == 1 and bikes.name ~= dealer.name)
check("its radius over the BIKES counter and the stands, not the dealer's whole block", B.Radius < Map.shopRadius("dealer") and B.Radius >= W / 2)

-- ── The bike stands ────────────────────────────────────────────────────────

local bikeCount = 0
for _, def in Config.Cars do
	if def.bike then
		bikeCount += 1
	end
end
local stands = B.Stands
check("a stand for every bike (World.BikeSlots, Config.Cars' order)", #stands.X >= bikeCount and bikeCount >= 4, `{#stands.X} / {bikeCount}`)
-- A stand: 2.6 × 7.4 (World's BikeStand), turned Turn degrees; its half extents.
local turn = math.rad(stands.Turn)
local hx = 1.3 * math.abs(math.cos(turn)) + 3.7 * math.abs(math.sin(turn))
local hz = 1.3 * math.abs(math.sin(turn)) + 3.7 * math.abs(math.cos(turn))
-- World buildDealer's showroom: the three turntables (the car showroom slots, World.DealerSlots) at x -25, 0, 25, z 6,
-- 19 across (the cars on them stay on the discs: the longest, the Box Truck, is 17); the door 16 wide in the middle of
-- the front.
local TURNTABLES = { -25, 0, 25 }
local inRoom, clearDoor, clearCars, clearDesks, covered, apart = true, true, true, true, true, true
local farthest = 0
for n, x in stands.X do
	local z = stands.Z
	inRoom = inRoom and inside(x, z, hx, hz)
	clearDoor = clearDoor and (x - hx >= 16 / 2 + 1 or x + hx <= -16 / 2 - 1)
	for _, tx in TURNTABLES do
		-- the stand's box to the turntable's middle, at least its radius and a walkway apart
		local dx = math.max(math.abs(x - tx) - hx, 0)
		local dz = math.max(math.abs(z - 6) - hz, 0)
		clearCars = clearCars and math.sqrt(dx * dx + dz * dz) >= 19 / 2 + 3
	end
	clearDesks = clearDesks and z + hz <= desk.Z - desk.Deep / 2 - 6 and z + hz <= cars.Z - 1.5 - 6
	local wx, wz = world(x, z)
	local far = math.sqrt((wx - bikes.x) ^ 2 + (wz - bikes.z) ^ 2)
	farthest = math.max(farthest, far)
	covered = covered and far + 6 <= B.Radius -- (a customer round the stand is still at the counter's shop)
	if n > 1 then
		apart = apart and (x - stands.X[n - 1]) * math.cos(turn) >= 4.5 -- (two bikes side by side, handlebars and all)
	end
end
check("every stand inside the showroom's walls", inRoom)
check("… clear of the door (16 wide in the front's middle)", clearDoor)
check("… clear of the three turntables, a walkway round them (the car showroom slots)", clearCars)
check("… clear of the counters, room for the customers in front of them", clearDesks)
check("… behind the front glass, on the bikes' side (north: the BIKES counter's)", stands.Z < 0 and stands.X[1] > 0 and desk.X > 0)
check("… within the BIKES counter's radius, a customer round each too", covered, math.floor(farthest))
check("… the bikes on them apart", apart)

-- ── One shop on the map ────────────────────────────────────────────────────

local bikeLandmark, spoke, dealerSaysBikes = false, false, false
for _, landmark in Map.Landmarks do
	bikeLandmark = bikeLandmark or landmark.id == "bikes"
	spoke = spoke or string.find(landmark.name .. landmark.description, "Spoke", 1, true) ~= nil
	if landmark.id == "dealer" then
		dealerSaysBikes = landmark.kind == "shop" and string.find(landmark.description, "BIKES counter", 1, true) ~= nil
			and string.find(landmark.description, "Cars", 1, true) ~= nil
	end
end
check("no Spoke & Chain landmark: the map, the GPS list and the tags show Dead End Motors", not bikeLandmark and not spoke and dealerSaysBikes)
local dealerTag = nil
for _, tag in LocationTags.build() do
	if tag.id == "dealer" then
		dealerTag = tag
	end
end
check("its tag reads like its board: DEAD END MOTORS, CARS · VANS · BIKES", dealerTag ~= nil and dealerTag.name == "Dead End Motors" and dealerTag.sub == "CARS · VANS · BIKES")

-- ── Spoke & Chain's old building ───────────────────────────────────────────

local F = Map.FormerBikeShop
check("its old block stays special (its dice as before, no lots)", Map.special("downtown", F.i, F.j) == "bikes" and F.x == F.i * Map.Cell and F.z == F.j * Map.Cell
	and #Map.lotsAt("downtown", F.i, F.j) == 0)
check("no shop on it any more", (function()
	for _, shop in Map.Shops do
		local d, a, b = Map.blockAt(shop.x, shop.z)
		if d and d.id == "downtown" and a == F.i and b == F.j then
			return false
		end
	end
	return true
end)())

-- ── The words players read ─────────────────────────────────────────────────

local bikePaint = Style.find("bike_mint")
local words = {
	Config.BikeShop.Unlock, Config.BikeShop.Reminder, Config.BikeShop.Bought, Config.Jobs.Bike.NeedsBike, Config.Levels.Rewards[2].text or "",
	Config.Cosmetics.Counters.bikes.place, Style.say("where", bikePaint), Style.atLabel("bikepaint"), Style.soldBy("vehicle"),
	Career.summary(Career.unlocksAt(Career.BIKE_LEVEL), 9),
}
local stale = {}
for _, text in words do
	if string.find(text, "Spoke", 1, true) or string.find(text, "SPOKE", 1, true) or string.find(text, "Main St", 1, true) then
		table.insert(stale, text)
	end
end
check("no Spoke & Chain (nor its Main St) in what players read", #stale == 0, table.concat(stale, " | "))
check("Marge sends you to Dead End Motors' BIKES counter", string.find(Config.BikeShop.Unlock, "Dead End Motors", 1, true) ~= nil
	and string.find(Config.BikeShop.Unlock, "BIKES counter", 1, true) ~= nil and string.find(Config.BikeShop.Reminder, "Dead End Motors", 1, true) ~= nil)
check("Kip keeps his bike paint, at Dead End Motors", Config.Cosmetics.Counters.bikes.clerk == "Kip" and Style.counterFor("bikepaint") == Config.Cosmetics.Counters.bikes
	and Style.say("where", bikePaint) == "Kip sells it at Dead End Motors. It's on your GPS.")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
