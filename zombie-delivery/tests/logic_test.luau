-- Logic test of the pure modules (shared/Economy.luau, shared/Map.luau: the world layout and the night clock) in the
-- standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local Map = require("./Map")

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

-- Economy ---------------------------------------------------------------------

check("upgrade cost level 0", Economy.upgradeCost("engine", 0) == 350, Economy.upgradeCost("engine", 0))
check("upgrade cost grows", (Economy.upgradeCost("engine", 1) :: number) > 350)
check("upgrade maxed", Economy.upgradeCost("engine", 5) == nil)
check("unknown upgrade", Economy.upgradeCost("nope", 0) == nil)

local van = Economy.carStats("van", {})
check("van base speed", van.maxSpeed == 60 and van.health == 300 and van.ramPower == 1)
local tuned = Economy.carStats("van", { engine = 2, armor = 1, plow = 3 })
check("engine upgrade", near(tuned.maxSpeed, 60 * 1.16), tuned.maxSpeed)
check("armor upgrade", tuned.health == math.floor(300 * 1.15), tuned.health)
check("plow upgrade", near(tuned.ramPower, 1.9), tuned.ramPower)
check("unknown car falls back", Economy.carStats("spaceship", {}).maxSpeed == 60)

local pistol = Economy.weaponStats("pistol", {})
check("pistol interval", near(pistol.interval, 1 / 3), pistol.interval)
local fast = Economy.weaponStats("pistol", { firerate = 5, damage = 5 })
check("fire rate upgrade", near(fast.interval, 1 / (3 * 1.6)), fast.interval)
check("damage upgrade", near(fast.damage, 20 * 2), fast.damage)

check("no ram damage when slow", Economy.ramDamage(Config.Horde.RamMinSpeed - 1, 1) == 0)
check("ram damage", near(Economy.ramDamage(30, 1), 30 * Config.Horde.RamDamagePerSpeed))
check("a fast van kills a walker", Economy.ramDamage(Config.Cars[1].maxSpeed * 0.6, 1) >= Config.Zombies.walker.health)
check("a fast van does not kill a brute", Economy.ramDamage(Config.Cars[1].maxSpeed, 1) < Config.Zombies.brute.health)

local tier1 = Config.Jobs.Tiers[1]
check("job pay rounded to 5", Economy.jobPay(tier1, 333) % 5 == 0)
check("job pay grows with distance", Economy.jobPay(tier1, 600) > Economy.jobPay(tier1, 200))
check("time limit", Economy.timeLimit(220) == math.floor(Config.Jobs.TimeBase + 10 + 0.5))

local perfect = Economy.payout(200, 1, 60, 100, 4)
check("perfect payout", perfect.conditionPay == 200 and perfect.fastBonus == 50 and perfect.killBonus == 4 * Config.Jobs.KillBonus)
check("perfect total", perfect.total == 200 + 50 + 4 * Config.Jobs.KillBonus, perfect.total)
local wrecked = Economy.payout(200, 0, 10, 100, 0)
check("wrecked cargo pays the minimum", wrecked.conditionPay == 100 and wrecked.fastBonus == 0 and wrecked.total == 100, wrecked.total)
check("condition is clamped", Economy.payout(200, 5, 0, 100, 0).conditionPay == 200)

check("pickKind r=0", Economy.pickKind({ walker = 1, runner = 1 }, 0) == "runner") -- sorted: runner, walker
check("pickKind r=0.99", Economy.pickKind({ walker = 1, runner = 1 }, 0.99) == "walker")
check("pickKind weights", Economy.pickKind({ walker = 9, brute = 1 }, 0.05) == "brute")
check("pickKind empty", Economy.pickKind({}, 0.5) == "walker")

-- Zombie waves, roamers, the people who only go after players on a job -----------

local tiers = Config.Jobs.Tiers
check("waves grow and are capped in every tier", (function()
	for _, tier in tiers do
		if Economy.waveSize(tier, 1) ~= tier.waveBase or tier.waveGrow <= 0 then
			return false
		end
		local last = 0
		for n = 1, 30 do
			local size = Economy.waveSize(tier, n)
			if size < last or size > tier.waveMax then
				return false
			end
			last = size
		end
		if last ~= tier.waveMax or Economy.waveSize(tier, 2) <= Economy.waveSize(tier, 1) then
			return false
		end
		if tier.waveMax > tier.waveAlive or tier.waveEvery <= 0 then
			return false -- a whole wave must fit under the cap of the alive ones
		end
	end
	return true
end)())
check("wave 3 of tier 2", Economy.waveSize(tiers[2], 3) == math.min(tiers[2].waveBase + 2 * tiers[2].waveGrow, tiers[2].waveMax))
check("tiers get harder: bigger, faster waves, more alive", (function()
	for i = 2, #tiers do
		local a, b = tiers[i - 1], tiers[i]
		if not (b.waveEvery < a.waveEvery and b.waveBase >= a.waveBase and b.waveMax > a.waveMax and b.waveAlive > a.waveAlive) then
			return false
		end
		for n = 1, 8 do
			if Economy.waveSize(b, n) <= Economy.waveSize(a, n) then
				return false
			end
		end
	end
	return true
end)())
local wanted = Economy.findModifier("horde")
check("WANTED: bigger and faster waves", wanted ~= nil and (function()
	local m = (wanted :: Config.ModifierDef).spawnMultiplier
	for _, tier in tiers do
		if Economy.waveSize(tier, 3, m) <= Economy.waveSize(tier, 3) or Economy.waveEvery(tier, m) >= Economy.waveEvery(tier)
			or Economy.waveAlive(tier, m) <= Economy.waveAlive(tier) or Economy.waveSize(tier, 99, m) > Economy.waveAlive(tier, m) then
			return false
		end
	end
	return true
end)())
check("the first wave comes ~15 s after accepting", Config.Jobs.FirstWave >= 10 and Config.Jobs.FirstWave <= 20)
check("the people only go after players on a job", Config.Zombies.bandit.jobOnly == true and Config.Zombies.gunner.jobOnly == true
	and Config.Zombies.soldier.jobOnly == true and not Config.Zombies.walker.jobOnly and not Config.Zombies.runner.jobOnly
	and not Config.Zombies.brute.jobOnly)
check("every ranged enemy is one of the people", (function()
	for _, def in Config.Zombies do
		if def.ranged and not def.jobOnly then
			return false
		end
	end
	return true
end)())
local roam = Config.Horde.Roam
check("roamers are zombies only (no bandit, gunner, soldier)", (function()
	local any = false
	for kind, weight in roam.kinds do
		local def = Config.Zombies[kind]
		if not def or def.jobOnly or def.ranged or kind == "bandit" or kind == "gunner" or kind == "soldier" or weight <= 0 then
			return false
		end
		any = true
	end
	return any
end)())
check("the waves are zombies only", (function()
	for _, tier in tiers do
		for kind in tier.waveKinds do
			local def = Config.Zombies[kind]
			if not def or def.ranged or kind == "bandit" or kind == "gunner" then
				return false
			end
		end
	end
	return true
end)())
check("roam numbers make sense", roam.min >= 1 and roam.min <= roam.max and roam.near < roam.far and roam.far < roam.despawn
	and roam.aggro < roam.gunHearing and roam.aggroCar <= roam.aggroCarMax and roam.chase > roam.aggroCarMax
	and roam.reserve < Config.Horde.MaxTotal and roam.think >= 0.2 and roam.think <= 0.5)

check("every car has a style and a price", (function()
	local last = -1
	for _, car in Config.Cars do
		if car.style == "" or car.price < 0 then
			return false
		end
		if not car.company then
			if car.price <= last then
				return false -- the dealer's cars get pricier down the list
			end
			last = car.price
		end
	end
	return Config.Cars[1].price == 0 and Config.Weapons[1].price == 0
end)())

-- Economy v2 -------------------------------------------------------------------

check("handling upgrade", near(Economy.carStats("van", { handling = 5 }).turn, 1.8 * 1.4))
check("launcher splash", Economy.weaponStats("launcher", {}).splash == 14)
check("items exist", Economy.findItem("nitro") ~= nil and Economy.findItem("nope") == nil)
check("paints exist", Economy.findPaint("factory") ~= nil and (Economy.findPaint("factory") :: any).price == 0)
check("modifier exists", Economy.findModifier("rush") ~= nil)
check("pay multiplier", Economy.jobPay(tier1, 400, 1.5) > Economy.jobPay(tier1, 400))
check("time multiplier", Economy.timeLimit(400, 0.7) < Economy.timeLimit(400))
local solo, none = Economy.crewSplit(300, 0)
check("solo crew split", solo == 300 and none == 0)
local driver, share = Economy.crewSplit(300, 2)
check("crew split", driver == 300 + 90 and share == 150, `{driver} {share}`)
check("items have unique ids", (function()
	local seen = {}
	for _, item in Config.Items do
		if seen[item.id] then
			return false
		end
		seen[item.id] = true
	end
	return #Config.Items == 5
end)())

-- Map -------------------------------------------------------------------------

local seed = Map.lcg(42)
local allOnRoad = true
local b = Map.Bounds
for _ = 1, 3000 do
	local px = b.x0 + seed() * (b.x1 - b.x0)
	local pz = b.z0 + seed() * (b.z1 - b.z0)
	local rx, rz, dx, dz, width = Map.nearestRoad(px, pz)
	if not Map.onRoad(rx, rz) or math.abs(dx * dx + dz * dz - 1) > 1e-6 or width < Config.City.RoadWidth then
		allOnRoad = false
		print("  off road:", px, pz, "->", rx, rz)
		break
	end
end
check("nearestRoad is always on a road", allOnRoad)

local rx, rz = Map.nearestRoad(0, 26)
check("road in front of the depot", near(rx, 0) and near(rz, Map.Cell / 2), `{rx} {rz}`)
check("depot is safe", Map.isSafe(0, 0) and not Map.isSafe(400, 0))
check("river is water", Map.inWater(840, 0) and not Map.inWater(0, 0) and Map.inWater(1800, 0))

local bridgesOk = true
for _, s in Map.Connectors do
	if s.kind == "bridge" then
		-- a bridge spans the river and ends on land at both sides
		if not (math.min(s.ax, s.bx) < Map.River.x0 and math.max(s.ax, s.bx) > Map.River.x1) then
			bridgesOk = false
		end
	elseif Map.inWater(s.ax, s.az) or Map.inWater(s.bx, s.bz) then
		bridgesOk = false
	end
end
check("only bridges cross water", bridgesOk)

-- The tunnel: the north highway runs straight through the mountain.
local mountain = Map.Mountain
local mx, mz = Map.nearestRoad(mountain.x, mountain.z)
check("a road goes through the mountain", near(mx, mountain.x) and near(mz, mountain.z), `{mx} {mz}`)

for _, place in Map.Places do
	check(`place {place.name} is reachable`, Map.onRoad(place.x, place.z) and not Map.inWater(place.x, place.z))
end
for id, shop in Map.Shops do
	check(`shop {id} is in the safe zone`, Map.isSafe(shop.x, shop.z))
end

local addresses = Map.addresses()
check("addresses are cached", Map.addresses() == addresses)
local good = true
local poiCount = 0
for _, a in addresses do
	if not Map.onRoad(a.x, a.z) or Map.isSafe(a.x, a.z) or Map.inWater(a.x, a.z) then
		good = false
		print("  bad address:", a.name, a.x, a.z)
	end
	if a.poi then
		poiCount += 1
	end
end
check("addresses are on roads, out of the safe zone, not in water", good)
check("every place is an address", poiCount == #Map.Places)
check("plenty of addresses", #addresses > 200, #addresses)

local depotX, depotZ = 0, 26
for index, tier in Config.Jobs.Tiers do
	local count = 0
	for _, a in addresses do
		local d = Map.manhattan(depotX, depotZ, a.x, a.z)
		if d >= tier.minDistance and d <= tier.maxDistance then
			count += 1
		end
	end
	check(`tier {index} has jobs from the depot`, count >= 4, count)
end

check("the lodge is in winter, across the ice", Map.isWinter(-655, -2200) and Map.onIce(-300, -2200) and not Map.isWinter(0, 0))
local ix, iz = Map.nearestRoad(-300, -2150)
check("an ice road crosses the lake", Map.onIce(ix, iz), `{ix} {iz}`)
check("company cars are not for sale", (function()
	for _, car in Config.Cars do
		if car.company and car.price ~= 0 then
			return false
		end
	end
	return Economy.findCar("icecream") ~= nil and (Economy.findCar("icecream") :: any).company == true
end)())
local function placeExists(id: string?): boolean
	if not id then
		return true
	end
	for _, place in Map.Places do
		if place.id == id then
			return true
		end
	end
	return false
end
check("job types use real cars and places", (function()
	for _, t in Config.JobTypes do
		if t.vehicle and not Economy.findCar(t.vehicle) then
			return false
		end
		if not placeExists(t.pickupAt) or not placeExists(t.dropAt) or t.drops < 1 then
			return false
		end
	end
	return true
end)())
check("every employer has a job, a reward car and a board", (function()
	for _, e in Config.Employers do
		local found = false
		for _, t in Config.JobTypes do
			found = found or (t.id == e.jobType and t.employer == e.id)
		end
		local car = Economy.findCar(e.reward)
		local spot = Map.EmployerSpots[e.id]
		if not found or not car or not car.company or car.employer ~= e.id or not spot then
			return false
		end
	end
	return true
end)())
check("landmarks list the shops and the employers", #Map.Landmarks >= 5 + #Config.Employers)
check("bandits shoot", Config.Zombies.bandit.ranged == true and (Config.Zombies.bandit.range or 0) > 0)

-- Zombie Delivery 2.0: the ranch, the riding school, the fuel depot, where the cargo is loaded ------------------

local function findPlace(id: string): Map.Place?
	for _, place in Map.Places do
		if place.id == id then
			return place
		end
	end
	return nil
end
for _, id in { "ranch", "stables", "fueldepot" } do
	local place = findPlace(id)
	check(`new place {id} exists, in a yard`, place ~= nil and Map.inYard(place.x, place.z) ~= nil)
end
check("the ranch and the gas station have a board", Map.EmployerSpots.ranch ~= nil and Map.EmployerSpots.gas ~= nil)

-- Every special job's pick-up and drop place has a cargo spot.
check("special jobs have cargo spots", (function()
	for _, t in Config.JobTypes do
		for _, id in { t.pickupAt, t.dropAt } do
			if id and not Map.CargoSpots[id] then
				print("  no cargo spot:", id)
				return false
			end
		end
	end
	return true
end)())
local function inBounds(x: number, z: number): boolean
	return x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1
end
local spotsOk = true
for id, spot in Map.CargoSpots do
	local park, pile = spot.park, spot.pile
	local gap = math.sqrt((park.x - pile.x) ^ 2 + (park.z - pile.z) ^ 2)
	local facingLength = math.sqrt(spot.facing.x ^ 2 + spot.facing.z ^ 2)
	local toPark = ((park.x - pile.x) * spot.facing.x + (park.z - pile.z) * spot.facing.z) / gap
	local place = findPlace(id)
	local problem: string? = nil
	if not place then
		problem = "not a place"
	elseif not inBounds(park.x, park.z) or not inBounds(pile.x, pile.z) then
		problem = "out of bounds"
	elseif Map.inWater(park.x, park.z) or Map.inWater(pile.x, pile.z) or Map.onIce(pile.x, pile.z) then
		problem = "in water"
	elseif not Map.onRoad(park.x, park.z) then
		problem = "park is not on a road or a yard"
	elseif gap < 8 or gap > 20 then
		problem = `pile {gap} studs from the park`
	elseif math.abs(facingLength - 1) > 1e-6 or toPark < 0.99 then
		problem = "facing does not point at the park"
	elseif math.sqrt((place.x - park.x) ^ 2 + (place.z - park.z) ^ 2) > 90 and (Map.inYard(park.x, park.z) == nil or Map.inYard(park.x, park.z) ~= Map.inYard(place.x, place.z)) then
		problem = "far from its place"
	end
	if problem then
		spotsOk = false
		print("  bad cargo spot:", id, problem)
	end
end
check("cargo spots: park on a road, pile 8-20 studs away on dry land, facing the park", spotsOk)

-- The country roads start on another road (a T-junction) and end in their yard.
local function onSegment(s: Map.Segment, x: number, z: number): boolean
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local length2 = dx * dx + dz * dz
	local t = math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1)
	return (x - s.ax - dx * t) ^ 2 + (z - s.az - dz * t) ^ 2 < 1e-6
end
for _, name in { "Ranch Road", "Riding School Lane" } do
	local road: Map.Segment? = nil
	for _, s in Map.Connectors do
		if s.name == name then
			road = s
		end
	end
	local connected, reachesYard = false, false
	if road then
		for _, s in Map.Segments do
			if s ~= road and (onSegment(s, road.ax, road.az) or onSegment(s, road.bx, road.bz)) then
				connected = true
			end
		end
		reachesYard = Map.inYard(road.bx, road.bz) ~= nil
	end
	check(`{name} joins the road network and reaches its yard`, connected and reachesYard)
end
check("the ranch road leaves the West Highway", (function()
	for _, s in Map.Connectors do
		if s.name == "West Highway" and onSegment(s, -900, Map.Cell * 1.5) then
			return true
		end
	end
	return false
end)())
check("yards are dry, apart and in bounds", (function()
	for _, yard in Map.Yards do
		for _, x in { yard.x0, yard.x1 } do
			for _, z in { yard.z0, yard.z1 } do
				if Map.inWater(x, z) or not inBounds(x, z) then
					return false
				end
			end
		end
		for _, other in Map.Yards do
			if other ~= yard and yard.x0 < other.x1 and other.x0 < yard.x1 and yard.z0 < other.z1 and other.z0 < yard.z1 then
				return false
			end
		end
	end
	return true
end)())
check("clearings are dry and off the roads", (function()
	for _, area in Map.Clearings do
		local cx, cz = (area.x0 + area.x1) / 2, (area.z0 + area.z1) / 2
		if Map.onRoad(cx, cz) or Map.inWater(area.x0, cz) or Map.inWater(area.x1, cz) then
			return false
		end
	end
	return true
end)())
check("landmark ids are unique", (function()
	local seen = {}
	for _, landmark in Map.Landmarks do
		if seen[landmark.id] then
			print("  duplicate landmark:", landmark.id)
			return false
		end
		seen[landmark.id] = true
	end
	return seen.ranch == true and seen.gas == true and seen.stables == true and seen.fueldepot == true
end)())
check("employer landmarks tell the car and the gun reward", (function()
	for _, landmark in Map.Landmarks do
		if landmark.id == "ranch" then
			return landmark.description:find("Ranch Revolver", 1, true) ~= nil and landmark.description:find("Livestock", 1, true) ~= nil
		end
	end
	return false
end)())

-- Zombie Delivery 2.5: the First Zombie Bank, the City Clinic, day and night ----------------------------------

local bank, clinic = findPlace("bank"), findPlace("clinic")
check("the bank and the clinic are places", bank ~= nil and clinic ~= nil)
if bank and clinic then
	local half = Config.City.SafeHalf
	local bankDistrict = Map.blockAt(bank.x - bank.nx * 20, bank.z - bank.nz * 20)
	check("the bank is downtown, on its own block", bankDistrict ~= nil and bankDistrict.id == "downtown"
		and Map.special("downtown", 1, -2) == "bank")
	check("the bank is out of the safe zone, at its edge", not Map.isSafe(bank.x, bank.z)
		and math.max(math.abs(bank.x), math.abs(bank.z)) < half + Map.Cell)
	local clinicDistrict = Map.blockAt(clinic.x - clinic.nx * 20, clinic.z - clinic.nz * 20)
	check("the clinic is in the city, on its own block", clinicDistrict ~= nil and Map.special(clinicDistrict.id, -2, 2) == "clinic")
	check("the bank and the clinic face their road", Map.onRoad(bank.x, bank.z) and Map.onRoad(clinic.x, clinic.z)
		and not Map.onRoad(bank.x - bank.nx * 20, bank.z) and not Map.onRoad(clinic.x - clinic.nx * 20, clinic.z))
	check("the bank and the clinic are not in a yard", Map.inYard(bank.x, bank.z) == nil and Map.inYard(clinic.x, clinic.z) == nil)
end
check("the clinic has a board (Dr. Novak), on its sidewalk", (function()
	local spot = Map.EmployerSpots.clinic
	if not spot or not clinic then
		return false
	end
	local d = Map.blockAt(spot.x, spot.z)
	return d ~= nil and Map.special(d.id, -2, 2) == "clinic" and not Map.onRoad(spot.x, spot.z)
		and math.sqrt((spot.x - clinic.x) ^ 2 + (spot.z - clinic.z) ^ 2) < Map.EmployerRadius + 20
end)())
check("the bank and the clinic have cargo spots, the pile on their own block", (function()
	for _, id in { "bank", "clinic" } do
		local spot = Map.CargoSpots[id]
		if not spot then
			return false
		end
		local d = Map.blockAt(spot.pile.x, spot.pile.z)
		if not d or Map.special(d.id, if id == "bank" then 1 else -2, if id == "bank" then -2 else 2) ~= id then
			return false
		end
	end
	return true
end)())
check("the board and the pile at the clinic stand apart", (function()
	local spot, board = Map.CargoSpots.clinic, Map.EmployerSpots.clinic
	return spot ~= nil and board ~= nil and math.sqrt((spot.pile.x - board.x) ^ 2 + (spot.pile.z - board.z) ^ 2) > 20
end)())
check("the cash run loads at the bank, the ambulance drops at the clinic", (function()
	local cash, ambulance = Economy.findJobType("cashrun"), Economy.findJobType("ambulance")
	return cash ~= nil and cash.pickupAt == "bank" and ambulance ~= nil and ambulance.dropAt == "clinic" and ambulance.employer == "clinic"
end)())
check("the bank and the clinic are landmarks", (function()
	local found = {}
	for _, landmark in Map.Landmarks do
		found[landmark.id] = landmark.kind
	end
	return found.bank == "place" and found.clinic == "employer"
end)())
check("the clinic's landmark names the ambulance", (function()
	for _, landmark in Map.Landmarks do
		if landmark.id == "clinic" then
			return landmark.description:find("Ambulance", 1, true) ~= nil and landmark.description:find("Dr. Novak", 1, true) ~= nil
		end
	end
	return false
end)())
check("special blocks do not hold addresses", (function()
	for _, a in Map.addresses() do
		local d, bi, bj = Map.blockAt(a.x - a.nx * 20, a.z - a.nz * 20)
		if not a.poi and d and Map.special(d.id, bi, bj) then
			return false
		end
	end
	return true
end)())

local dn = Config.DayNight
check("night: the clock", Map.isNight(dn.NightFrom) and Map.isNight(0) and Map.isNight(dn.NightTo - 0.01)
	and not Map.isNight(dn.NightTo) and not Map.isNight(12) and not Map.isNight(dn.NightFrom - 0.01) and Map.isNight(24 + 1))
check("night factor: day 0, deep night 1", Map.nightFactor(12) == 0 and Map.nightFactor(9) == 0 and Map.nightFactor(0) == 1
	and Map.nightFactor(dn.NightFrom + 2) == 1 and Map.nightFactor(dn.NightTo - 2) == 1, Map.nightFactor(0))
check("night factor: half way at dusk and dawn", near(Map.nightFactor(dn.NightFrom), 0.5) and near(Map.nightFactor(dn.NightTo), 0.5))
check("night factor: smooth and in order through dusk and dawn", (function()
	local last = Map.nightFactor(14)
	for step = 1, 200 do
		local hour = 14 + step * 0.05 -- 14:00 … 24:00
		local f = Map.nightFactor(hour)
		if f < last - 1e-9 or f - last > 0.08 or f < 0 or f > 1 then
			return false
		end
		last = f
	end
	for step = 1, 200 do
		local hour = step * 0.05 -- 0:00 … 10:00: only falls
		local f = Map.nightFactor(hour)
		if f > last + 1e-9 or last - f > 0.08 then
			return false
		end
		last = f
	end
	return last == 0
end)())
check("night numbers make sense", dn.DayLength >= 120 and dn.NightFrom > 12 and dn.NightTo < 12 and dn.NightPay > 1
	and dn.NightWaves >= 1 and dn.NightRoam >= 1 and not Map.isNight(dn.StartHour))

-- Zombie Delivery 2.6: the real estate (Map.EstatePlots, Map.Towers, Sunset Hills) ------------------------------

local Roads = require("./Roads")
local estate = Config.Estate.Properties
local defs: { [string]: Config.EstateDef } = {}
local kinds: { [string]: number } = {}
for _, def in estate do
	defs[def.id] = def
	kinds[def.kind] = (kinds[def.kind] or 0) + 1
end
check("3 mansions, 2 villas, 4 houses, 3 garages, 3 offices", kinds.mansion == 3 and kinds.villa == 2 and kinds.house == 4
	and kinds.garage == 3 and kinds.office == 3)
check("every property has a plot, every plot a property", (function()
	for _, def in estate do
		if not Map.EstatePlots[def.id] then
			print("  no plot:", def.id)
			return false
		end
	end
	for id in Map.EstatePlots do
		if not defs[id] then
			print("  plot of nothing:", id)
			return false
		end
	end
	return true
end)())

-- The lot of a plot as a box on the map (the facings run along X or Z, so it is axis-aligned).
local function lotBox(plot: Map.EstatePlot, grow: number): (number, number, number, number)
	local ax, az = Map.plotPoint(plot, -plot.w / 2 - grow, -plot.front - grow)
	local bx, bz = Map.plotPoint(plot, plot.w / 2 + grow, plot.back + grow)
	return math.min(ax, bx), math.min(az, bz), math.max(ax, bx), math.max(az, bz)
end
-- Somewhere on the lot (u, v from 0 to 1 across and along it).
local function onLot(plot: Map.EstatePlot, u: number, v: number): (number, number)
	return Map.plotPoint(plot, -plot.w / 2 + plot.w * u, -plot.front + (plot.front + plot.back) * v)
end
local function toSegmentDistance(s: Map.Segment, x: number, z: number): number
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local length2 = dx * dx + dz * dz
	local t = if length2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / length2, 0, 1) else 0
	return math.sqrt((x - s.ax - dx * t) ^ 2 + (z - s.az - dz * t) ^ 2)
end
local function distanceToRoad(x: number, z: number): number
	local rx, rz = Map.nearestRoad(x, z)
	return math.sqrt((x - rx) ^ 2 + (z - rz) ^ 2)
end

for id, plot in Map.EstatePlots do
	local def = defs[id]
	local problem: string? = nil
	local fx, fz = plot.facing.x, plot.facing.z
	if math.abs(fx) + math.abs(fz) ~= 1 or fx * fz ~= 0 then
		problem = "facing is not along X or Z"
	end
	-- The whole lot: in bounds, dry, off the roads, the ice and the yards.
	for a = 0, 8 do
		for c = 0, 8 do
			local x, z = onLot(plot, a / 8, c / 8)
			if problem then
				break
			elseif not inBounds(x, z) or x < b.x0 + 20 or x > b.x1 - 20 or z < b.z0 + 20 or z > b.z1 - 20 then
				problem = `out of bounds at {x}, {z}`
			elseif Map.inWater(x, z) or Map.onIce(x, z) then
				problem = `in the water at {x}, {z}`
			elseif Map.onRoad(x, z) then
				problem = `on a road at {x}, {z}`
			elseif not plot.tower and Map.inYard(x, z) then
				problem = `in a yard at {x}, {z}`
			end
		end
	end
	-- Its road: straight out of the front, a few strides from the door.
	local reaches = false
	for k = 0, 45, 1 do
		local x, z = Map.plotPoint(plot, 0, -plot.front - k)
		if Map.onRoad(x, z) then
			reaches = true
			break
		end
	end
	if not problem and not reaches then
		problem = "no road in front"
	end
	-- Homes and garages: the car comes out of the garage onto its road.
	if not problem and def and def.kind ~= "office" then
		local gx, gz = Map.plotPoint(plot, 0, -plot.front - Map.GarageApron)
		if distanceToRoad(gx, gz) > 40 or Map.inWater(gx, gz) then
			problem = `garage apron {math.floor(distanceToRoad(gx, gz))} studs from the road`
		end
	end
	if problem then
		print("  bad plot:", id, problem)
	end
	check(`plot {id}: in bounds, dry, off the roads, a road in front`, problem == nil, problem)
end

check("plots do not overlap (but offices share their tower)", (function()
	local list = {}
	for id, plot in Map.EstatePlots do
		table.insert(list, { id = id, plot = plot })
	end
	for n, a in list do
		for m = n + 1, #list do
			local other = list[m]
			if a.plot.tower and a.plot.tower == other.plot.tower then
				continue
			end
			local ax0, az0, ax1, az1 = lotBox(a.plot, 2)
			local bx0, bz0, bx1, bz1 = lotBox(other.plot, 2)
			if ax0 < bx1 and bx0 < ax1 and az0 < bz1 and bz0 < az1 then
				print("  overlap:", a.id, other.id)
				return false
			end
		end
	end
	return true
end)())

local hills = Map.SunsetHills
local function inHills(x: number, z: number): boolean
	return x >= hills.x0 and x <= hills.x1 and z >= hills.z0 and z <= hills.z1
end
local function plotDistance(a: Map.EstatePlot, c: Map.EstatePlot): number
	return math.sqrt((a.x - c.x) ^ 2 + (a.z - c.z) ^ 2)
end
check("Sunset Hills holds the Hilltop Mansion and at most one mansion and one villa", (function()
	local count = { mansion = 0, villa = 0, other = 0 }
	for _, def in estate do
		local plot = Map.EstatePlots[def.id]
		if plot and plot.district == "sunsethills" then
			local x0, z0, x1, z1 = lotBox(plot, 0)
			if not inHills(x0, z0) or not inHills(x1, z1) then
				print("  not inside the hills:", def.id)
				return false
			end
			local k = if def.kind == "mansion" or def.kind == "villa" then def.kind else "other"
			count[k] += 1
		end
	end
	local hilltop = Map.EstatePlots.hilltop
	return hilltop ~= nil and hilltop.district == "sunsethills" and count.mansion == 1 and count.villa <= 1 and count.other == 0
end)())
check("the homes are spread: every mansion and villa in its own area, far apart", (function()
	local homes: { { id: string, plot: Map.EstatePlot } } = {}
	local areas: { [string]: boolean } = {}
	for _, def in estate do
		local plot = Map.EstatePlots[def.id]
		if plot and (def.kind == "mansion" or def.kind == "villa") then
			if areas[plot.district] and plot.district ~= "sunsethills" then
				print("  two homes in", plot.district)
				return false
			end
			areas[plot.district] = true
			table.insert(homes, { id = def.id, plot = plot })
		end
	end
	for n, a in homes do
		for m = n + 1, #homes do
			local c = homes[m]
			if plotDistance(a.plot, c.plot) < 500 then
				print("  too close:", a.id, c.id, plotDistance(a.plot, c.plot))
				return false
			end
		end
	end
	return #homes == 5
end)())
check("a mansion on the coast, one in the countryside, a villa by the frozen lake", (function()
	local ocean, pines, lake = Map.EstatePlots.oceanview, Map.EstatePlots.pinecrest, Map.EstatePlots.lakeside
	if not ocean or not pines or not lake then
		return false
	end
	local ox1 = math.max((Map.plotPoint(ocean, 0, ocean.back)), (Map.plotPoint(ocean, 0, -ocean.front)))
	local lx0 = math.min((Map.plotPoint(lake, -lake.w / 2, 0)), (Map.plotPoint(lake, lake.w / 2, 0)))
	return Map.Sea.x0 - ox1 < 150 and ocean.x > Map.River.x1 and Map.blockAt(ocean.x, ocean.z) == nil
		and pines.x < -1200 and Map.blockAt(pines.x, pines.z) == nil
		and lx0 - Map.Lake.x1 < 40 and lx0 > Map.Lake.x1 and math.abs(lake.z - (Map.Lake.z0 + Map.Lake.z1) / 2) < 200
end)())
check("Sunset Hills is dry, in bounds and off the other yards", not Map.inWater(hills.x0, hills.z0) and not Map.inWater(hills.x1 - 15, hills.z1)
	and inBounds(hills.x0, hills.z0) and inBounds(hills.x1, hills.z1) and (function()
		for _, yard in Map.Yards do
			if yard.x0 < hills.x1 and hills.x0 < yard.x1 and yard.z0 < hills.z1 and hills.z0 < yard.z1 then
				return false
			end
		end
		return true
	end)())
check("the houses: on Suburbs blocks (inside their block) or at the edge of town, each on its own street", (function()
	local streets: { [string]: boolean } = {}
	local suburbs = Map.Districts[3]
	local sx0, sx1, sz0, sz1 = Map.districtEdges(suburbs)
	for _, def in estate do
		local plot = Map.EstatePlots[def.id]
		if def.kind ~= "house" or not plot then
			continue
		end
		local d, i, j = Map.blockAt(plot.x, plot.z)
		if d then
			if d.id ~= "suburbs" or Map.special(d.id, i, j) then
				print("  on a special block:", def.id)
				return false
			end
			local x0, z0, x1, z1 = lotBox(plot, 0)
			local cx, cz = d.ox + i * Map.Cell, d.oz + j * Map.Cell
			local half = Map.BlockSize / 2
			if x0 < cx - half or x1 > cx + half or z0 < cz - half or z1 > cz + half then
				print("  off its block:", def.id)
				return false
			end
		elseif plot.x < sx0 - 250 or plot.x > sx1 + 250 or plot.z < sz0 - 250 or plot.z > sz1 + 250 then
			print("  not at the edge of town:", def.id)
			return false
		end
		-- the road in front of it: its centre line (a street along X is keyed by its z, along Z by its x)
		local fx, fz = Map.plotPoint(plot, 0, -plot.front - 12)
		local rx, rz, dx = Map.nearestRoad(fx, fz)
		local key = if math.abs(dx) > 0.5 then `z{math.floor(rz + 0.5)}` else `x{math.floor(rx + 0.5)}`
		if streets[key] then
			print("  two houses on one street:", def.id, key)
			return false
		end
		streets[key] = true
	end
	return true
end)())
check("the garages: at the harbor, on the North Highway and downtown", (function()
	local lockup, parking = Map.EstatePlots.garage_harbor, Map.EstatePlots.garage_downtown
	local north = Map.EstatePlots.garage_north
	if not lockup or not parking or not north then
		return false
	end
	local d1, i1, j1 = Map.blockAt(lockup.x, lockup.z)
	local d2, i2, j2 = Map.blockAt(parking.x, parking.z)
	local onHighway = false
	for _, s in Map.Connectors do
		local gx, gz = Map.plotPoint(north, 0, -north.front - Map.GarageApron)
		if s.name == "North Highway" and toSegmentDistance(s, gx, gz) < s.width / 2 + 12 then
			onHighway = true
		end
	end
	return d1 ~= nil and d1.id == "harbor" and Map.special("harbor", i1, j1) == "lockup"
		and d2 ~= nil and d2.id == "downtown" and Map.special("downtown", i2, j2) == "parking" and onHighway
end)())
check("the towers: 10+ floors, on their own block, the offices on their upper floors", (function()
	local count = 0
	for id, tower in Map.Towers do
		count += 1
		local d, i, j = Map.blockAt(tower.x, tower.z)
		if tower.floors < 10 or tower.id ~= id or not d or Map.special(d.id, i, j) ~= id or tower.w > Map.BlockSize - 20 then
			print("  bad tower:", id)
			return false
		end
	end
	local floors: { [string]: boolean } = {}
	for _, def in estate do
		local plot = Map.EstatePlots[def.id]
		if def.kind == "office" then
			local tower = plot and plot.tower and Map.Towers[plot.tower]
			local floor = plot and plot.floor
			if not plot or not tower or not floor or floor < 2 or floor > tower.floors or floors[`{tower.id}:{floor}`] then
				print("  bad office:", def.id)
				return false
			end
			floors[`{tower.id}:{floor}`] = true
			if plot.x ~= tower.x or plot.z ~= tower.z then
				return false
			end
		end
	end
	return count == 2 and Map.Towers.dispatchtower ~= nil and Map.Towers.harborpoint ~= nil
		and Map.floorHeight(Map.Towers.dispatchtower, 1) == 0 and Map.floorHeight(Map.Towers.dispatchtower, 3) == 2 * Map.Towers.dispatchtower.floorHeight
end)())
check("the penthouse is the top floor", (function()
	local plot = Map.EstatePlots.office_penthouse
	local tower = plot and plot.tower and Map.Towers[plot.tower]
	return tower ~= nil and plot.floor == tower.floors
end)())

-- Sunset Drive: joins the network at Downtown, stays dry and in bounds, winds up into the hills. The lanes to the other
-- homes join the network too.
do
	local pieces: { Map.Segment } = {}
	for _, s in Map.Connectors do
		if s.name == "Sunset Drive" then
			table.insert(pieces, s)
		end
	end
	local function joins(s: Map.Segment): boolean
		for _, o in Map.Segments do
			if o.name ~= s.name and onSegment(o, s.ax, s.az) then
				return true
			end
		end
		return false
	end
	local first = pieces[1]
	check("Sunset Drive joins Downtown's roads", #pieces >= 5 and first ~= nil and joins(first))
	local dry, bends = true, 0
	for n, s in pieces do
		for t = 0, 1, 0.1 do
			local x, z = s.ax + (s.bx - s.ax) * t, s.az + (s.bz - s.az) * t
			if Map.inWater(x, z) or not inBounds(x, z) or Map.inYard(x, z) then
				dry = false
			end
		end
		local nextPiece = pieces[n + 1]
		if nextPiece then
			if nextPiece.ax ~= s.bx or nextPiece.az ~= s.bz then
				dry = false -- a gap
			end
			local ux, uz = s.bx - s.ax, s.bz - s.az
			local vx, vz = nextPiece.bx - nextPiece.ax, nextPiece.bz - nextPiece.az
			if math.abs(ux * vz - uz * vx) > 1e-6 then
				bends += 1
			end
		end
	end
	check("Sunset Drive is dry, in bounds and winds", dry and bends >= 4, bends)
	local last = pieces[#pieces]
	check("Sunset Drive ends in the hills", last ~= nil and inHills(last.bx, last.bz))
	-- No other road through the hills.
	local crossed = false
	for _, s in Map.Segments do
		if s.name ~= "Sunset Drive" and (inHills(s.ax, s.az) or inHills(s.bx, s.bz)) then
			crossed = true
		end
	end
	check("the hills are the drive's alone", not crossed)
	for _, name in Map.EstateRoads do
		local found, ok = false, true
		for _, s in Map.Connectors do
			if s.name == name then
				if not found and not joins(s) then
					ok = false
				end
				found = true
				for t = 0, 1, 0.1 do
					local x, z = s.ax + (s.bx - s.ax) * t, s.az + (s.bz - s.az) * t
					if Map.inWater(x, z) or not inBounds(x, z) or Map.inYard(x, z) then
						ok = false
					end
				end
			end
		end
		check(`{name} joins the network, dry and in bounds`, found and ok)
	end
end

check("every property is reachable by road from the depot", (function()
	for id, plot in Map.EstatePlots do
		local x, z = Map.plotPoint(plot, 0, -plot.front - Map.GarageApron)
		local route = Roads.route(0, 26, x, z)
		local gap = distanceToRoad(x, z)
		local straight = math.sqrt(x * x + (z - 26) ^ 2)
		if #route < 2 or gap > 45 or Roads.length(route) > 3 * straight + 600 then
			print("  no route to:", id, gap, Roads.length(route))
			return false
		end
	end
	return true
end)())
check("the estate is on the map: Sunset Hills, the homes on their own, the towers and the garages are landmarks", (function()
	local found = {}
	for _, landmark in Map.Landmarks do
		found[landmark.id] = landmark
	end
	for _, id in { "sunsethills", "dispatchtower", "harborpoint", "garage_harbor", "garage_north", "garage_downtown", "oceanview", "pinecrest", "lakeside", "sunset" } do
		local landmark = found[id]
		if not landmark or not inBounds(landmark.x, landmark.z) or Map.inWater(landmark.x, landmark.z) or distanceToRoad(landmark.x, landmark.z) > 40 then
			print("  missing or off the road:", id)
			return false
		end
	end
	local hillsMark = found.sunsethills
	return hillsMark ~= nil and inHills(hillsMark.x, hillsMark.z)
end)())
check("the suburbs lots match the lots of the blocks", (function()
	local x, z = Map.suburbLot(0, 0, 0, 0)
	return near(x, -Map.BlockSize / 2 + Map.SuburbInset + Map.SuburbLot / 2) and near(z, 900 - Map.BlockSize / 2 + Map.SuburbInset + Map.SuburbLot / 2)
end)())
check("plotPoint: right and back of the front", (function()
	local plot: Map.EstatePlot = { x = 10, z = 20, facing = { x = 0, z = -1 }, district = "test", w = 10, front = 5, back = 5 }
	local rx, rz = Map.plotPoint(plot, 3, 0) -- looking north, the right is east
	local bx, bz = Map.plotPoint(plot, 0, 4) -- behind is south
	return near(rx, 13) and near(rz, 20) and near(bx, 10) and near(bz, 24)
end)())

local district, i, j = Map.blockAt(Map.Cell, 0)
check("blockAt finds the dealer block", district ~= nil and district.id == "downtown" and i == 1 and j == 0)
check("blockAt on a road is nil", (Map.blockAt(Map.Cell / 2, 0)) == nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
