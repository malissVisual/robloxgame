-- Logic test of the pure modules (shared/Economy.luau, shared/Map.luau) in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

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
check("job types use real cars and places", (function()
	for _, t in Config.JobTypes do
		if t.vehicle and not Economy.findCar(t.vehicle) then
			return false
		end
		if t.place then
			local found = false
			for _, place in Map.Places do
				found = found or place.id == t.place
			end
			if not found then
				return false
			end
		end
	end
	return true
end)())
check("bandits shoot", Config.Zombies.bandit.ranged == true and (Config.Zombies.bandit.range or 0) > 0)

local district, i, j = Map.blockAt(Map.Cell, 0)
check("blockAt finds the dealer block", district ~= nil and district.id == "downtown" and i == 1 and j == 0)
check("blockAt on a road is nil", (Map.blockAt(Map.Cell / 2, 0)) == nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
