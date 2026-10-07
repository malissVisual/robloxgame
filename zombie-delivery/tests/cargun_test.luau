-- Logic test of the guns in and on the cars (Config.CarGuns, Economy.carGunStats / fireMode, the one-handed guns,
-- the cars that can carry a car gun) in the standalone Luau CLI.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")

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

-- The car guns -------------------------------------------------------------------

check("three car guns", #Config.CarGuns == 3, #Config.CarGuns)
for _, id in { "roofmg", "roofminigun", "rooflauncher" } do
	check(`car gun {id} exists`, Economy.findCarGun(id) ~= nil)
end
check("unknown car gun", Economy.findCarGun("nope") == nil)
check("a hand gun is not a car gun", Economy.findCarGun("minigun") == nil)
check("every car gun is sane", (function()
	local seen = {}
	for _, gun in Config.CarGuns do
		if seen[gun.id] or Economy.findWeapon(gun.id) or gun.price <= 0 or gun.damage <= 0 or gun.fireRate <= 0 then
			return false
		end
		if gun.range <= 0 or gun.pellets < 1 or gun.spread < 0 or gun.splash < 0 or #gun.color ~= 3 or gun.name == "" then
			return false
		end
		seen[gun.id] = true
	end
	return true
end)())
check("car guns get pricier down the list", (function()
	local last = 0
	for _, gun in Config.CarGuns do
		if gun.price <= last then
			return false
		end
		last = gun.price
	end
	return true
end)())

local mg = Economy.carGunStats("roofmg", {})
check("roof MG stats", near(mg.damage, 14) and near(mg.interval, 1 / 8) and mg.splash == 0, mg.damage)
local minigun = Economy.carGunStats("roofminigun", {})
check("roof minigun fires twice as fast as the MG", near(minigun.interval * 2, mg.interval), minigun.interval)
local launcher = Economy.carGunStats("rooflauncher", {})
check("roof launcher blows up", launcher.splash == 14 and launcher.damage >= 60, launcher.splash)
local tuned = Economy.carGunStats("roofmg", { damage = 5, firerate = 5 })
check("damage upgrade works for car guns", near(tuned.damage, 14 * 2), tuned.damage)
check("fire rate upgrade works for car guns", near(tuned.interval, 1 / (8 * 1.6)), tuned.interval)
check("unknown car gun falls back to the first", near(Economy.carGunStats("nope", {}).damage, Config.CarGuns[1].damage))

-- Balance: damage per second against the hand guns.
local function dps(stats: Economy.WeaponStats): number
	return stats.damage * stats.pellets / stats.interval
end
check("the roof MG beats the pistol", dps(mg) > dps(Economy.weaponStats("pistol", {})))
check("the roof minigun beats the roof MG", dps(minigun) > dps(mg))
check("the roof minigun is not far over the hand minigun", dps(minigun) <= dps(Economy.weaponStats("minigun", {})) * 1.25)
check("the roof launcher costs less than the hand launcher", (Economy.findCarGun("rooflauncher") :: Config.CarGunDef).price < (Economy.findWeapon("launcher") :: Config.WeaponDef).price)

-- The one-handed guns ------------------------------------------------------------

local oneHanded = {}
for _, def in Config.Weapons do
	if def.oneHanded then
		table.insert(oneHanded, def.id)
	end
end
table.sort(oneHanded)
check("one-handed: pistol, revolver, smg (and the golden pistol)", table.concat(oneHanded, ",") == "goldpistol,pistol,revolver,smg", table.concat(oneHanded, ","))
for _, id in { "shotgun", "rifle", "carbine", "minigun", "launcher" } do
	check(`{id} is two-handed`, not Economy.oneHanded(id))
end
check("an unknown gun is not one-handed", not Economy.oneHanded("nope"))
check("the start gun is the pistol, one-handed", Config.Weapons[1].id == "pistol" and Economy.oneHanded(Config.Weapons[1].id))

-- The cars that carry a car gun --------------------------------------------------

local mountable = {}
for _, def in Config.Cars do
	if def.mount then
		table.insert(mountable, def.id)
	end
end
table.sort(mountable)
check("mountable cars", table.concat(mountable, ",") == "armored,armorvan,boxtruck,courier,highroof,monster,muscle,pickup,rallyvan,van", table.concat(mountable, ","))
for _, def in Config.Cars do
	if not def.company and not def.bike and def.id ~= "freight" then -- (5.1: no car gun on a bike)
		check(`every dealer car carries a car gun: {def.id}`, Economy.canMount(def.id))
	end
end
check("4.0: the Freight Truck carries no car gun", not Economy.canMount("freight"))
for _, id in { "bus", "icecream", "movingtruck", "livestock", "fueltruck" } do
	check(`{id} cannot mount a gun`, not Economy.canMount(id))
end
check("an unknown car cannot mount a gun", not Economy.canMount("spaceship"))
check("the bandits' pickup is no player car", not Economy.canMount(Config.BanditCar.car.id))
check("the start car can mount a gun", Economy.canMount(Config.Cars[1].id))

-- What fires ---------------------------------------------------------------------

check("on foot: the hand gun", Economy.fireMode(false, false, "minigun", nil) == "hand")
check("on foot: a car gun does not matter", Economy.fireMode(false, false, "pistol", "roofmg") == "hand")
check("driver with a car gun: the car gun", Economy.fireMode(true, true, "launcher", "roofminigun") == "cargun")
check("driver with a car gun and a pistol: the car gun", Economy.fireMode(true, true, "pistol", "roofmg") == "cargun")
check("driver without a car gun: pistol out of the window", Economy.fireMode(true, true, "pistol", nil) == "window")
check("driver without a car gun: the SMG out of the window", Economy.fireMode(true, true, "smg", nil) == "window")
check("driver without a car gun: no shotgun", Economy.fireMode(true, true, "shotgun", nil) == nil)
check("driver with an unknown car gun: no minigun", Economy.fireMode(true, true, "minigun", "nope") == nil)
check("passenger: the revolver out of the window", Economy.fireMode(true, false, "revolver", nil) == "window")
check("passenger: never the car gun", Economy.fireMode(true, false, "pistol", "roofmg") == "window")
check("passenger: no rifle", Economy.fireMode(true, false, "rifle", "roofmg") == nil)
check("passenger: no carbine", Economy.fireMode(true, false, "carbine", nil) == nil)
-- 6.0: no free gun (a new courier: fists only, weapon nil).
check("6.0: no gun on foot: nothing fires", Economy.fireMode(false, false, nil, nil) == nil and Economy.fireMode(false, false, "nope", nil) == nil)
check("6.0: no gun in a seat: no window shot", Economy.fireMode(true, false, nil, nil) == nil and Economy.fireMode(true, true, nil, nil) == nil)
check("6.0: no gun, a car gun: the driver still fires it", Economy.fireMode(true, true, nil, "roofmg") == "cargun")
check("6.0: no gun is not one-handed, finds nothing", not Economy.oneHanded(nil) and Economy.findWeapon(nil) == nil)
check("6.0: no gun's stats read as the pistol's (nothing fires anyway)", Economy.weaponStats(nil, {}).damage == Economy.weaponStats("pistol", {}).damage)
check("6.0: the first gun owned, in the shop's order", Economy.firstWeapon({}) == nil and Economy.firstWeapon({ smg = true, pistol = true }) == "pistol"
	and Economy.firstWeapon({ rifle = true, nope = true } :: any) == "rifle" and Economy.firstWeapon({ pistol = false } :: any) == nil)
local starter = Economy.findWeapon(Config.Arms.Starter) :: Config.WeaponDef
check("6.7: the pistol is the starter: level 1, never sold ($0, STARTER · yours)", starter ~= nil and starter.id == "pistol" and starter.price == 0
	and starter.starter == true and starter.level == 1 and starter.earned == nil and starter.exclusive == nil)
check("6.7: Marge's 'buy a pistol' tip is gone (every courier starts with it)", (Config.Arms :: any).Tip == nil)
check("6.7: only the pistol is a starter, every other gun is sold or a reward", (function()
	for _, def in Config.Weapons do
		if def.starter and def.id ~= Config.Arms.Starter then
			return false
		end
		if not def.starter and def.price <= 0 and not Economy.rewardOnly(def) then
			return false
		end
	end
	return true
end)())
check("6.7: the reward-only guns (the REWARDS section)", Economy.rewardOnly(Economy.findWeapon("revolver") :: Config.WeaponDef) and Economy.rewardOnly(Economy.findWeapon("deadend") :: Config.WeaponDef)
	and not Economy.rewardOnly(Economy.findWeapon("smg") :: Config.WeaponDef) and not Economy.rewardOnly(starter))
local function gunDps(id: string): number
	local stats = Economy.weaponStats(id, {})
	return stats.damage * stats.pellets / stats.interval
end
check("6.7: the Hunting Rifle out-hits the SMG (132 > 117 a second, and at range the SMG's spread misses)", gunDps("rifle") > gunDps("smg") and Economy.weaponStats("rifle", {}).range > Economy.weaponStats("smg", {}).range, `{gunDps("rifle")} {gunDps("smg")}`)
check("6.7: … one rifle shot drops a walker or a runner", Economy.weaponStats("rifle", {}).damage >= Config.Zombies.walker.health and Economy.weaponStats("rifle", {}).damage >= Config.Zombies.runner.health)

check("version 2.1+", (function()
	local major, minor = string.match(Config.Version, "^(%d+)%.(%d+)")
	local a, b = tonumber(major) or 0, tonumber(minor) or 0
	return a > 2 or (a == 2 and b >= 1)
end)(), Config.Version)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
