--!strict
-- 7.x, one car (the owner: "dej pryč auta, ostatní, nech ve hře jen van"; Config.CompanyVan): the ZDC Van is the only
-- car a player has, every other car is a body of the world (Config.AmbientCars), and an old save is put right once
-- (server/PlayerData.luau with the pure Economy.carRefund and Economy.vanCarry): its other cars paid back at the price
-- they sold at (and the stages bought on them), the van taking over their best car tracks, gear, paint and roof gun,
-- a car it drove that is gone falling back to the van. Also: no job or mission lends a vehicle, the employers pay a
-- bonus instead of their car, the money's reasons. Run with tests/run_tests.py.

local Config = require("./Config")
local Economy = require("./Economy")
local AnalyticsPlan = require("./AnalyticsPlan")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local VAN = Config.CompanyVan.Car
local van = Economy.findCar(VAN) :: Config.CarDef

-- ── The one car ─────────────────────────────────────────────────────────────

check("the ZDC Van is Config.CompanyVan's car and Config.Cars[1]", VAN == "zdcvan" and Config.Cars[1].id == VAN and van ~= nil)
check("everybody's from level 1: never sold (price 0, starter), no mission", van.starter == true and van.price == 0 and (van.level or 1) == 1 and van.mission == nil)
check("its old price is kept to pay back: $16,000 × the Vehicles knob = $48,000", van.refund == Config.priced(16000, Config.Prices.Vehicles) and van.refund == 48000, van.refund)
check("it keeps its Blender style, its four slots, a roof gun on its rack, the trolley", van.style == "zdcvan" and van.capacity == 4 and van.mount == true and van.trolley == true)
local others: { string } = {}
for _, def in Config.Cars do
	if def.id ~= VAN and not def.bike and not def.sandboxOnly then -- (8.0: and the sandbox's ZDC Sprinter, tests/sprinter_test.luau)
		table.insert(others, def.id)
	end
end
check("Config.Cars holds the van and the bikes only (8.0: and the sandbox's van)", #others == 0, table.concat(others, ", "))
check("a player's vehicles: the van and the bikes", Economy.isPlayerCar(VAN) and Economy.isPlayerCar("rustbike") and Economy.isPlayerCar("escooter"))
check("… never a body of the world (the old cars, the company vehicles), nor nothing", not Economy.isPlayerCar("van") and not Economy.isPlayerCar("courier")
	and not Economy.isPlayerCar("rallyvan") and not Economy.isPlayerCar("bus") and not Economy.isPlayerCar(nil) and not Economy.isPlayerCar("nope"))
check("Economy.findCar still finds the bodies (the traffic, the buses, Earl's old van): ambient", (Economy.findCar("van") :: Config.CarDef).ambient == true
	and (Economy.findCar("bus") :: Config.CarDef).ambient == true and (Economy.findCar("boxtruck") :: Config.CarDef).stages ~= nil)
local ambientOk = true
for _, def in Config.AmbientCars do
	ambientOk = ambientOk and def.ambient == true and def.mission == nil and not def.bike
end
check("every ambient body is marked, waits for no mission, is no bike", ambientOk)

-- ── The refund (Economy.carRefund) ──────────────────────────────────────────

local function price(id: string): number
	return (Economy.findCar(id) :: Config.CarDef).price
end
local function stagePrice(id: string, n: number): number
	return (Economy.stageDef(id, n) :: Config.StageDef).price
end
check("today's prices: the Old Van $5,400, the Courier Van $10,500, the Rally Van $240,000", price("van") == 5400 and price("courier") == 10500 and price("rallyvan") == 240000,
	`{price("van")} {price("courier")} {price("rallyvan")}`)
check("the Old Van's stages: $650, $1,800, $5,500", stagePrice("van", 1) == 650 and stagePrice("van", 2) == 1800 and stagePrice("van", 3) == 5500)

local function refund(saved: any): (number, { string })
	return Economy.carRefund(saved)
end
check("a new profile (no money saved): nothing", (refund({ cars = { van = true } })) == 0 and (refund(nil)) == 0 and (refund("x")) == 0)
check("a save without cars: nothing", (refund({ money = 10 })) == 0 and (refund({ money = 10, cars = {} })) == 0)
check("the flag: paid once, never again", (refund({ money = 10, cars = { van = true }, [Config.CompanyVan.Flag] = true })) == 0 and Config.CompanyVan.Flag == "vanOnly")
local money, names = refund({ money = 10, cars = { van = true } })
check("a Rusty Old Van: its price, $5,400", money == 5400 and #names == 1 and names[1] == "Old Van", money)
money = refund({ money = 10, cars = { van = true }, carUpgrades = { van = { stage = 3, engine = 2 } } })
check("a Long Cargo Van: the van and its three stages, $13,350 (no money for the car tracks: the ZDC Van takes them)", money == 5400 + 650 + 1800 + 5500 and money == 13350, money)
money = refund({ money = 10, cars = { van = true }, carUpgrades = { van = { stage = 99 } } })
check("a stage above the last counts the last", money == 13350, money)
money = refund({ money = 10, cars = { van = true }, carUpgrades = { van = { stage = -2 } } })
local nan = refund({ money = 10, cars = { van = true }, carUpgrades = { van = { stage = 0 / 0 } } })
check("a broken stage counts none", money == 5400 and nan == 5400)
local full, fleet = refund({ money = 10, cars = { [VAN] = true, van = true, courier = true, bus = true, armored = true, rustbike = true },
	carUpgrades = { courier = { stage = 1 } } })
check("a fleet: the ZDC Van bought ($48,000), the Old Van, the Express Courier; the bus and the armored truck were free, the bike stays",
	full == 48000 + 5400 + 10500 + stagePrice("courier", 1) and full == 66900, full)
check("… the names in Config order (the van first)", table.concat(fleet, ", ") == "ZDC Van, Old Van, Courier Van", table.concat(fleet, ", "))
check("only cars owned count (false is not owned)", (refund({ money = 10, cars = { van = false, courier = "yes" } })) == 0)

-- ── What the van takes over (Economy.vanCarry) ──────────────────────────────

check("a new profile or a flagged save: nothing", Economy.vanCarry({ cars = { van = true } }) == nil and Economy.vanCarry({ money = 1, cars = { van = true }, vanOnly = true }) == nil
	and Economy.vanCarry(nil) == nil)
local carry = Economy.vanCarry({
	money = 10,
	car = "courier",
	cars = { van = true, courier = true, rustbike = true },
	carUpgrades = { van = { engine = 3, armor = 1, stage = 3 }, courier = { engine = 1, plow = 5, handling = 9 } },
	carGear = { van = { trolley = "installed", straps = "owned" }, courier = { straps = "installed", roofrack = "owned", basket = "installed" } },
	carPaint = { van = "gold", courier = "red" },
	carGuns = { van = "roofminigun" },
}) :: Economy.VanCarry
check("every car track at its highest level (clamped), never the stage", carry ~= nil and carry.levels.engine == 3 and carry.levels.armor == 1 and carry.levels.plow == 5
	and carry.levels.handling == 5 and carry.levels.stage == nil)
check("their gear that fits the van: installed wins over owned, no bike gear", carry.gear.trolley == "installed" and carry.gear.straps == "installed" and carry.gear.roofrack == "owned"
	and carry.gear.basket == nil)
check("the paint of the car it drove (the courier's red), the first roof gun (the old van's minigun)", carry.paint == "red" and carry.gun == "roofminigun")
check("two cars gone (the bike and the van itself not counted)", carry.retired == 2, carry.retired)
local own = Economy.vanCarry({ money = 10, car = VAN, cars = { [VAN] = true, van = true }, carPaint = { van = "gold", [VAN] = "black" }, carGuns = { van = "roofmg", [VAN] = "rooflauncher" } }) :: Economy.VanCarry
check("driving the ZDC Van already: its own paint and gun stay first", own.paint == "black" and own.gun == "rooflauncher" and own.retired == 1)
local bike = Economy.vanCarry({ money = 10, car = "rustbike", lastCar = "van", cars = { van = true, rustbike = true }, carPaint = { van = "toxic" } }) :: Economy.VanCarry
check("riding a bike: the car CALL CAR brought back counts as the one driven", bike.paint == "toxic")
check("unknown paints and guns are left out", (Economy.vanCarry({ money = 1, cars = { van = true }, carPaint = { van = "plaid" }, carGuns = { van = "laser" } }) :: Economy.VanCarry).paint == nil)

-- ── A car that is gone falls back to the van (server/PlayerData.luau, server/Vehicles.luau spawnAt) ────────────

local fallback = 0
for _, id in { "van", "courier", "highroof", "pickup", "boxtruck", "muscle", "freight", "armorvan", "rallyvan", "bus", "ambulance" } do
	-- the save's `car` is kept only when it is a vehicle a player may have; else the new profile's van stays
	local equipped = if Economy.isPlayerCar(id) then id else VAN
	if equipped == VAN then
		fallback += 1
	end
end
check("every car that is gone falls back to the ZDC Van when it was the one equipped", fallback == 11)

-- ── No vehicle lent any more; the employers' bonus; the money's reasons ───────────────────────────────────────

local lends = 0
for _, def in Config.JobTypes do
	if def.vehicle ~= nil then
		lends += 1
	end
end
check("no special job lends a company vehicle", lends == 0)
local bonusOk = true
for _, employer in Config.Employers do
	bonusOk = bonusOk and employer.reward == "bonus" and (employer.bonus or 0) > 0 and Economy.findCar(employer.reward) == nil
end
check("every employer pays a bonus instead of a car", bonusOk)
check("the money's reasons: CarRefund (a refund), EmployerBonus (gameplay)", AnalyticsPlan.Sources.CarRefund == "Refund" and AnalyticsPlan.Sources.EmployerBonus == "Gameplay")
check("Marge's words", string.find(Config.CompanyVan.Refunded, "{money}", 1, true) ~= nil and string.find(Config.CompanyVan.Kept, "ZDC Van", 1, true) ~= nil
	and string.find(Config.CompanyVan.Hello, "{level}", 1, true) ~= nil and string.find(Config.CompanyVan.Bonus, "{employer}", 1, true) ~= nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
