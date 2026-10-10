--!strict
-- 4.0, Freight (Stream V): the slow Old Van and its longer way up (Config.Cars van stages, StageDef.accel), the torque
-- curve of pulling away (Economy.torque / timeToTop, client/Drive.luau), the save migration of the van's stages
-- (Economy.migrateStage40), the pallets (CarDef / StageDef.pallets, Economy.palletsOf), the Hand Trolley
-- (4.6: Config.Gear "trolley", CarDef.trolley, Economy.gearFits / installedGear) and the Freight Truck.
-- (The bodies, the stretch and the slots of server/Vehicles.luau are checked as text by run_tests.py.)

local Config = require("./Config")
local Economy = require("./Economy")

local failed = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("  ok   " .. name)
	else
		failed += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

-- ── The Old Van: slow, and a longer way up ──────────────────────────────────

local van = Economy.findCar("van") :: Config.CarDef
local stages = van.stages or {}
check("the Rusty Van is slow: max about 42, accel about 11", van.maxSpeed >= 40 and van.maxSpeed <= 44 and van.accel >= 10 and van.accel <= 12, `{van.maxSpeed} / {van.accel}`)
local rusty = Economy.carStats("van", {})
local rustyTop = Economy.timeToTop(rusty.maxSpeed, rusty.accel)
print(`  the Rusty Van: 0 → 97 % of {rusty.maxSpeed} in {string.format("%.2f", rustyTop)} s`)
check("the Rusty Van takes about 3.5 – 4 s to its top speed", rustyTop >= 3.3 and rustyTop <= 4.2, rustyTop)
check("four stages: Rusty, Patched, Work, Long Cargo", #stages == 4 and stages[2].name == "Patched Van" and stages[3].name == "Work Van" and stages[4].name == "Long Cargo Van")
check("Patched Van: about $250 base (6.19: × Prices.Stages), level 4 (5.0), 2 slots", stages[2].price >= 200 * Config.Prices.Stages and stages[2].price <= 300 * Config.Prices.Stages and stages[2].level == 4 and stages[2].capacity == 2)
check("Work Van: about $700 base, level 5 (5.0), 3 slots", stages[3].price >= 600 * Config.Prices.Stages and stages[3].price <= 800 * Config.Prices.Stages and stages[3].level == 5 and stages[3].capacity == 3)
check("Long Cargo Van: about $2,200 base, level 6 (5.0), 4 slots", stages[4].price >= 2000 * Config.Prices.Stages and stages[4].price <= 2400 * Config.Prices.Stages and stages[4].level == 6 and stages[4].capacity == 4)
local WANT = { { 42, 11 }, { 48, 15 }, { 54, 19 }, { 56, 21 } } -- the brief's max / accel per stage (about)
local lastTop = math.huge
for stage = 0, 3 do
	local stats = Economy.carStats("van", { stage = stage })
	local want = WANT[stage + 1]
	local top = Economy.timeToTop(stats.maxSpeed, stats.accel)
	print(`  stage {stage} {stages[stage + 1].name}: max {stats.maxSpeed}, accel {stats.accel}, 0 → top in {string.format("%.2f", top)} s, health {stats.health}`)
	check(`stage {stage}: max about {want[1]}, accel about {want[2]}`, math.abs(stats.maxSpeed - want[1]) <= 2 and math.abs(stats.accel - want[2]) <= 1.5, `{stats.maxSpeed} / {stats.accel}`)
	check(`stage {stage}: quicker off the line than the one before`, top < lastTop, top)
	lastTop = top
end
check("the stages' accel adds to the car's (StageDef.accel)", Economy.carStats("van", { stage = 2 }).accel == van.accel + (stages[3].accel or 0))
local tuned = Economy.carStats("van", { engine = 1 })
check("the Engine is the other way up: +8 % speed and accel", near(tuned.maxSpeed, van.maxSpeed * 1.08) and near(tuned.accel, van.accel * 1.08))
check("a stage and the Engine multiply", near(Economy.carStats("van", { stage = 3, engine = 5 }).accel, (van.accel + (stages[4].accel or 0)) * 1.4))
check("a fully built Long Cargo Van is still no Courier Van off the line", Economy.carStats("van", { stage = 3 }).accel < (Economy.findCar("courier") :: Config.CarDef).accel)

-- ── The torque curve (client/Drive.luau) ────────────────────────────────────

check("pulling away is soft from a standstill", Economy.torque(0) <= 0.7 and Economy.torque(0) > 0.3, Economy.torque(0))
check("strongest in the mid-range", Economy.torque(0.5) >= 1.2 and Economy.torque(0.5) >= Economy.torque(0.1) and Economy.torque(0.5) >= Economy.torque(0.9))
check("a soft approach to the top speed", Economy.torque(0.98) < 0.6 and Economy.torque(1) > 0, Economy.torque(1))
local smooth, positive = true, true
for n = 0, 200 do
	local a, b = Economy.torque(n / 200), Economy.torque((n + 1) / 200)
	if math.abs(b - a) > 0.05 then
		smooth = false
	end
	if a <= 0 then
		positive = false
	end
end
check("the curve has no jumps (no instant speed changes)", smooth)
check("the curve always pulls", positive)
check("clamped outside 0 … 1", Economy.torque(-1) == Economy.torque(0) and Economy.torque(3) == Economy.torque(1))
check("on average about the car's accel (the curve does not make every car slower)", (function(): boolean
	local plain = Economy.timeToTop(60, 26)
	return plain > 60 / 26 * 0.8 and plain < 60 / 26 * 1.2
end)())
check("no time without a speed or an accel", Economy.timeToTop(0, 10) == 0 and Economy.timeToTop(40, 0) == 0)

-- ── The saves: the van's old stages keep their room ─────────────────────────

check("a 3.5 – 3.10 Rusty Van stays the Rusty Van", Economy.migrateStage40("van", 0) == 0)
check("an old Work Van (stage 1, 3 slots) is the Work Van (stage 2)", Economy.migrateStage40("van", 1) == 2 and Economy.stageCapacity("van", 2) == 3)
check("an old Cargo Van (stage 2, 4 slots) is the Long Cargo Van (stage 3)", Economy.migrateStage40("van", 2) == 3 and Economy.stageCapacity("van", 3) == 4)
check("the other cars keep their stage", Economy.migrateStage40("boxtruck", 2) == 2 and Economy.migrateStage40("courier", 1) == 1)
check("a 3.4 save's Old Van (4 slots) becomes the Long Cargo Van", Economy.legacyStage("van", 0) == 3)

-- ── Pallets ─────────────────────────────────────────────────────────────────

check("the Freight Truck takes 3 pallets", Economy.palletsOf("freight", 0) == 3)
check("the Box Truck takes a pallet only at its last stage", Economy.palletsOf("boxtruck", 0) == 0 and Economy.palletsOf("boxtruck", 1) == 0
	and Economy.palletsOf("boxtruck", 2) == 1 and Economy.palletsOf("boxtruck", Economy.maxStage("boxtruck")) == 1)
check("the Moving Truck takes a pallet", Economy.palletsOf("movingtruck", 0) == 1)
check("a van takes none, an unknown car none", Economy.palletsOf("van", 3) == 0 and Economy.palletsOf("spaceship", 0) == 0)
check("a stage out of range is clamped", Economy.palletsOf("boxtruck", 9) == 1 and Economy.palletsOf("boxtruck", -2) == 0)
local palletSlots = ((Config.Cargo :: any).PalletSlots or 4) :: number
local palletsFit = true
for _, def in Config.Cars do
	for stage = 0, Economy.maxStage(def.id) do
		if Economy.palletsOf(def.id, stage) * palletSlots > Economy.stageCapacity(def.id, stage) then
			palletsFit = false
			print(`  {def.id} stage {stage}: {Economy.palletsOf(def.id, stage)} pallets in {Economy.stageCapacity(def.id, stage)} slots`)
		end
	end
end
check("every car's pallets fit its slots", palletsFit)

-- ── The Hand Trolley ────────────────────────────────────────────────────────

-- 4.6: it is gear now (Config.Gear "trolley", the same id; tests/career_test.luau has the rest of the gear).
local trolley = Economy.findGear("trolley")
check("the Hand Trolley: gear, level 3, about $600 base (6.19: × Prices.Gear), no upgrade track any more", trolley ~= nil and trolley.level == 3
	and trolley.price >= 500 * Config.Prices.Gear and trolley.price <= 700 * Config.Prices.Gear and Economy.findUpgrade("trolley") == nil)
for _, id in { "van", "courier", "highroof", "boxtruck", "freight" } do
	check(`{id} may take the trolley`, Economy.gearFits(id, "trolley"))
end
for _, id in { "pickup", "muscle", "armorvan", "rallyvan", "movingtruck", "spaceship" } do
	check(`{id} may not take the trolley`, not Economy.gearFits(id, "trolley"))
end
check("every car track fits every car you own", Economy.upgradeFits("pickup", "engine") and Economy.upgradeFits("muscle", "handling")
	and not Economy.upgradeFits("ambulance", "engine"))
check("the trolley rides along once installed", Economy.installedGear({ van = { trolley = "installed" } }, "van").trolley == true
	and Economy.installedGear({ van = { trolley = "owned" } }, "van").trolley == nil and Economy.installedGear(nil, "van").trolley == nil)
check("not on a car that can't take one", Economy.installedGear({ muscle = { trolley = "installed" } }, "muscle").trolley == nil)

-- ── The upgrades you see ────────────────────────────────────────────────────

local handling = Economy.findUpgrade("handling")
check("Handling is Tyres & Suspension now (the id stays)", handling ~= nil and handling.name == "Tyres & Suspension" and string.find(handling.description, "tyres", 1, true) ~= nil)
local engine = Economy.findUpgrade("engine")
check("the Engine's card says the smoke stops", engine ~= nil and string.find(engine.description, "smoke", 1, true) ~= nil)

-- ── The Freight Truck ───────────────────────────────────────────────────────

local freight = Economy.findCar("freight")
check("the Freight Truck exists (style freighttruck)", freight ~= nil and freight.style == "freighttruck" and freight.name == "Freight Truck")
if freight then
	check("level 10 (5.0), about $45,000 base (6.19: × Prices.Vehicles)", freight.level == 10 and freight.price >= 40000 * Config.Prices.Vehicles and freight.price <= 50000 * Config.Prices.Vehicles)
	check("12 slots", freight.capacity == 12 and Economy.maxCapacity("freight") == 12)
	check("slow and heavy", freight.maxSpeed <= 47 and freight.accel <= 13 and freight.turn <= 1.3 and freight.health >= 850)
	check("no car gun, a trolley", freight.mount ~= true and freight.trolley == true)
	check("sold at Dead End Motors (not a company vehicle), a role", freight.company ~= true and type(freight.role) == "string")
end
-- The catalog lists the dealer's cars by their level.
local lastLevel, ordered = 0, true
for _, def in Config.Cars do
	if not def.company and not def.bike then -- (5.1: the bikes are Spoke & Chain's own catalog)
		if (def.level or 1) < lastLevel then
			ordered = false
		end
		lastLevel = def.level or 1
	end
end
check("the dealer's cars stay in the order of their level", ordered)

print(if failed == 0 then "ALL CHECKS PASSED" else `{failed} CHECK(S) FAILED`)
