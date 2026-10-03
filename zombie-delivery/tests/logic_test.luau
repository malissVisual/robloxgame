-- Logic test of the pure modules (shared/Economy.luau, shared/CityGrid.luau) in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local CityGrid = require("./CityGrid")

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
	for i, car in Config.Cars do
		if car.price < 0 or car.style == "" or (i > 1 and car.price <= Config.Cars[i - 1].price) then
			return false
		end
	end
	return Config.Cars[1].price == 0 and Config.Weapons[1].price == 0
end)())

-- CityGrid --------------------------------------------------------------------

local x, z, axis = CityGrid.nearestRoad(0, 26)
check("road in front of the depot", x == 0 and near(z, CityGrid.Cell / 2) and axis == "x", `{x} {z} {axis}`)

local seed = CityGrid.lcg(42)
local allOnRoad = true
for _ = 1, 2000 do
	local px = (seed() - 0.5) * CityGrid.Edge * 2.4
	local pz = (seed() - 0.5) * CityGrid.Edge * 2.4
	local rx, rz = CityGrid.nearestRoad(px, pz)
	if not CityGrid.onRoad(rx, rz) then
		allOnRoad = false
		print("  off road:", px, pz, "->", rx, rz)
		break
	end
end
check("nearestRoad is always on a road", allOnRoad)

check("block centre is in a block", CityGrid.inBlock(CityGrid.Cell, 0, 0))
check("road centre is not in a block", not CityGrid.inBlock(CityGrid.Cell / 2, 0, 0))

local addresses = CityGrid.addresses()
local blocks = (CityGrid.Blocks * 2 + 1) ^ 2
check("two addresses per block", #addresses == (blocks - 1) * 2, #addresses)
local good = true
for _, a in addresses do
	if not CityGrid.onRoad(a.x, a.z) or math.sqrt(a.x * a.x + a.z * a.z) < Config.City.SafeRadius then
		good = false
		print("  bad address:", a.name, a.x, a.z)
	end
end
check("addresses are on roads, out of the depot", good)
check("addresses are cached", CityGrid.addresses() == addresses)

for index, tier in Config.Jobs.Tiers do
	local count = 0
	for _, a in addresses do
		local d = CityGrid.manhattan(0, 26, a.x, a.z)
		if d >= tier.minDistance and d <= tier.maxDistance then
			count += 1
		end
	end
	check(`tier {index} has jobs from the depot`, count >= 5, count)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
