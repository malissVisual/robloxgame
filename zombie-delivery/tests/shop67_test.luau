-- 6.7, the shops cleaned up, in the standalone Luau CLI: the Energy Drink (Config.Items "energy", client/Stamina.luau
-- energized / refill), the Baseball Bat (Config.Kit "bat", Config.Melee.Kinds bat, shared/Melee.luau), the Thermal
-- Jacket's refund (Config.RetiredKit, shared/Transport.luau retiredRefunds), the car-only items (Config.Items car,
-- shared/Economy.luau ownsCar / itemShown / itemsFor), the Courier Vest's tips (Config.Kit tips, Transport.tipShare,
-- shared/JobRules.luau kitTip), where each piece of kit is sold (Transport.kitShop), the gun upgrades at Lead & Co.
-- and the reworked numbers (the Ram Plow's guard, the Roof Rack, the Muscle Car, the Works Rally, the E-Scooter).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local Transport = require("./Transport")
local JobRules = require("./JobRules")
local Melee = require("./Melee")
local Stamina = require("./Stamina")
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
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) < (eps or 1e-6)
end
local function item(id: string): Config.ItemDef
	return Economy.findItem(id) :: Config.ItemDef
end

-- ── The Energy Drink ────────────────────────────────────────────────────────────────────────────────────────────

local drink = item("energy")
local T = Config.ItemTuning
check("the Energy Drink: $40 base (6.19: × Prices.Items), at most 5, not for a car, its words", drink ~= nil and drink.price == Config.priced(40, Config.Prices.Items) and drink.max == 5 and drink.car == nil
	and string.find(drink.description, "30 s", 1, true) ~= nil and string.find(drink.description, "1.3", 1, true) ~= nil)
check("… 30 s of ×1.3 breath (Config.ItemTuning)", T.EnergyTime == 30 and T.EnergyBreath == 1.3)
check("… sold with the items on foot, before the car items", (function()
	local at: { [string]: number } = {}
	for index, def in Config.Items do
		at[def.id] = index
	end
	return at.energy < at.repair and at.medkit < at.energy
end)())
local M = Config.Movement
local DT = 1 / 60
local function sprintFor(cost: number?): number
	local s, seconds = Stamina.new(), 0
	while s.breath > 0 and seconds < 60 do
		s = Stamina.step(s, DT, true, true, M, cost)
		seconds += DT
	end
	return seconds
end
local plain = sprintFor(nil)
local boosted = sprintFor(Stamina.energized(nil, true, T.EnergyBreath))
check("a full breath lasts Stamina seconds without it", near(plain, M.Stamina, 2 * DT), plain)
check("… and ×1.3 longer with it (7.8 s)", near(boosted, M.Stamina * T.EnergyBreath, 3 * DT), boosted)
check("energized: the drain ÷ 1.3 while it works, as it was after", near(Stamina.energized(nil, true, 1.3), 1 / 1.3) and Stamina.energized(nil, false, 1.3) == 1
	and Stamina.energized(1.15, false, 1.3) == 1.15)
check("… with the duffel's breath too: 1.15 ÷ 1.3", near(Stamina.energized(1.15, true, 1.3), 1.15 / 1.3))
local dry = Stamina.step(Stamina.new(), M.Stamina + 1, true, true, M)
local refilled = Stamina.refill(dry)
check("the drink fills an empty breath at once and the sprint may start again", dry.exhausted and refilled.breath == 1 and not refilled.exhausted
	and Stamina.canSprint(refilled))
check("… the given state is left as it was", dry.breath == 0 and dry.exhausted)
check("a drain under 1 is kept (not clamped back to 1)", Stamina.step(Stamina.new(), 1, true, true, M, 0.5).breath > Stamina.step(Stamina.new(), 1, true, true, M).breath)

-- ── The Baseball Bat ─────────────────────────────────────────────────────────────────────────────────────────────

local bat = Transport.findKit("bat") :: Config.KitDef
check("the Baseball Bat: $150 base (6.19: × Prices.Kit), level 1, at Lead & Co., a melee piece", bat ~= nil and bat.price == Config.priced(150, Config.Prices.Kit) and bat.level == 1 and bat.shop == "guns"
	and bat.melee == "bat" and Config.Melee.BatKit == "bat" and Transport.kitShop(bat) == "guns")
local punch, strike, swing = Melee.def("punch"), Melee.def("gun"), Melee.def("bat")
check("the bat's numbers: 30 damage, 0.7 s, push 44, 7 studs", swing.damage == 30 and swing.cooldown == 0.7 and swing.push == 44 and swing.reach == 7)
check("… stronger than a punch and the gun's strike, a little slower than a punch", swing.damage > strike.damage and strike.damage > punch.damage
	and swing.cooldown > punch.cooldown and swing.damage / swing.cooldown > strike.damage / strike.cooldown)
check("… a walker in two swings, a runner in two", math.ceil(Config.Zombies.walker.health / swing.damage) == 2 and math.ceil(Config.Zombies.runner.health / swing.damage) == 2)
check("… reaches further than the hands (Config.Melee.Reach)", Melee.reachOf("bat") == 7 and Melee.reachOf("punch") == Config.Melee.Reach and Melee.reachOf("gun") == Config.Melee.Reach)
check("owned, the gun away: a bat swing; the gun out: the strike; no bat: a punch", Melee.kindOf(true, true) == "bat" and Melee.kindOf(false, true) == "gun"
	and Melee.kindOf(true, false) == "punch" and Melee.kindOf(true) == "punch")
check("the bat swings like the gun's strike (the arm's pose), the others their own", Melee.pose("bat") == "gun" and Melee.pose("punch") == "punch" and Melee.pose("gun") == "gun")
check("hasBat reads the kit", Melee.hasBat({ bat = true }) and not Melee.hasBat({ bat = false } :: any) and not Melee.hasBat({}) and not Melee.hasBat(nil))
check("the bat's longer reach: 6.5 studs ahead is in reach of a bat, not a fist", Melee.reach(0, 0, 0, 0, -1, 0, 0, -6.5, Melee.reachOf("bat")) ~= nil
	and Melee.reach(0, 0, 0, 0, -1, 0, 0, -6.5, Melee.reachOf("punch")) == nil and Melee.reach(0, 0, 0, 0, -1, 0, 0, -7.5, 7) == nil)
check("the bat's look: a length, a thin handle, a thicker barrel", Config.Melee.BatLook.Length > 2 and Config.Melee.BatLook.Handle < Config.Melee.BatLook.Barrel)
check("on the career road at level 1 (personal gear)", (function()
	for _, unlock in Career.unlocksAt(1) do
		if unlock.kind == "kit" and unlock.id == "bat" then
			return true
		end
	end
	return false
end)())

-- ── The Thermal Jacket's refund ───────────────────────────────────────────────────────────────────────────────────

check("the Thermal Jacket is retired: not in the kit, its price kept for the refund", Transport.findKit("jacket") == nil and (function()
	for _, def in Config.RetiredKit do
		if def.id == "jacket" then
			return def.price == 300 and def.flag == "noJacket"
		end
	end
	return false
end)())
local a66 = Transport.retiredRefunds({ money = 900, noPacks = true, kit = { jacket = true, bag = true } })
check("a 6.6 save with the jacket (noPacks already): $300 back, once", a66.noJacket == 300 and a66.noPacks == nil)
local a65 = Transport.retiredRefunds({ money = 900, kit = { jacket = true, backpack = true, bigpack = true } })
check("a 6.5 save with both backpacks and the jacket: $550 + $300", a65.noPacks == 550 and a65.noJacket == 300)
check("a save paid back already (noJacket): nothing again", next(Transport.retiredRefunds({ money = 1, noPacks = true, noJacket = true, kit = { jacket = true } })) == nil)
check("no jacket: nothing", next(Transport.retiredRefunds({ money = 1, noPacks = true, noShoes = true, kit = { shoes = true, bag = true } })) == nil)
check("a lock-only record (no money: a new player) or a broken save: nothing", next(Transport.retiredRefunds({ kit = { jacket = true } })) == nil
	and next(Transport.retiredRefunds(nil)) == nil and next(Transport.retiredRefunds("jacket")) == nil and next(Transport.retiredRefunds({ money = 5, kit = "jacket" })) == nil)
local words = string.gsub(Config.Courier.JacketRefund, "{money}", "$300")
check("Marge's words name the money and the Thermal Delivery Bag", string.find(words, "$300", 1, true) ~= nil and string.find(words, "Thermal Delivery Bag", 1, true) ~= nil, words)
check("the thermal bag still keeps food hot", (Transport.findKit("thermal") :: Config.KitDef).bagWarm == 0.35)

-- ── The car-only items ───────────────────────────────────────────────────────────────────────────────────────────

local carOnly: { string } = {}
for _, def in Config.Items do
	if def.car then
		table.insert(carOnly, def.id)
		check(`{def.name}: its words say "Car only"`, string.find(def.description, "Car only", 1, true) == 1, def.description)
	end
end
check("the car-only items: the repair kit, nitro, the landmine, the jerry can", table.concat(carOnly, ",") == "repair,nitro,mine,jerrycan", table.concat(carOnly, ","))
check("no car: none (nothing, or only bikes)", not Economy.ownsCar({}) and not Economy.ownsCar(nil) and not Economy.ownsCar({ rustbike = true, escooter = true }))
check("a car of your own, or an employer's: yes", Economy.ownsCar({ van = true }) and Economy.ownsCar({ rustbike = true, muscle = true }) and Economy.ownsCar({ ambulance = true }))
check("a false entry or an unknown id: no", not Economy.ownsCar({ van = false } :: any) and not Economy.ownsCar({ spaceship = true }))
check("itemShown: on foot always, a car item only with a car", Economy.itemShown(item("medkit"), {}) and Economy.itemShown(item("energy"), nil)
	and not Economy.itemShown(item("nitro"), { citybike = true }) and Economy.itemShown(item("nitro"), { van = true }))
local onFoot, driving = Economy.itemsFor({ rustbike = true }), Economy.itemsFor({ van = true })
check("itemsFor: 3 kinds on foot (medkit, energy, molotov), all 7 with a car", #onFoot == 3 and #driving == #Config.Items and #driving == 7, `{#onFoot} {#driving}`)
check("… a supply crate's pool on foot has no car item", (function()
	for _, def in onFoot do
		if def.car then
			return false
		end
	end
	return true
end)())
check("the medkit, the molotov and the energy drink fit the touch bar's 2 slots + MORE", #onFoot > 2 and Config.ItemTuning.BarSlots == 5)
check("the mine's words give its limit (5 down)", string.find(item("mine").description, "5 at most", 1, true) ~= nil and Config.ItemTuning.MineMax == 5)

-- ── The Courier Vest's tips ──────────────────────────────────────────────────────────────────────────────────────

local vest = Transport.findKit(Config.Courier.VestKit) :: Config.KitDef
check("the Courier Vest: +5% tips, its words say so", vest.tips == 0.05 and string.find(vest.description, "5%", 1, true) ~= nil)
check("tipShare: the vest's 5%, nothing without it, the best one counts", Transport.tipShare({ hivis = true }) == 0.05 and Transport.tipShare({}) == 0
	and Transport.tipShare({ hivis = false } :: any) == 0 and Transport.tipShare({ hivis = true, kevlar = true }) == 0.05)
check("kitTip: 5% of $200 is $10, of $90 is $5 (rounded), nothing without a share", JobRules.kitTip(200, 0.05) == 10 and JobRules.kitTip(90, 0.05) == 5
	and JobRules.kitTip(200, 0) == 0)
check("kitTip: nothing on no pay, a NaN or a negative", JobRules.kitTip(0, 0.05) == 0 and JobRules.kitTip(-50, 0.05) == 0 and JobRules.kitTip(0 / 0, 0.05) == 0
	and JobRules.kitTip(100, 0 / 0) == 0)
local line = JobRules.kitTipCheck(10)
check("the result card's line", line.ok == true and string.find(line.text, "+$10", 1, true) ~= nil and string.find(line.text, "Courier Vest", 1, true) ~= nil, line.text)

-- ── Where each piece is sold, the starters ───────────────────────────────────────────────────────────────────────

local shops: { [string]: { string } } = {}
for _, def in Config.Kit do
	local shop = Transport.kitShop(def)
	shops[shop] = shops[shop] or {}
	table.insert(shops[shop], def.id)
end
check("ZDC Bags: the five bags", table.concat(shops.bags or {}, ",") == "bag,tote,thermal,padded,duffel", table.concat(shops.bags or {}, ","))
check("Last Stop Supplies: the vest, the armour (6.12.2: no shoes)", table.concat(shops.supplies or {}, ",") == "hivis,kevlar,heavy", table.concat(shops.supplies or {}, ","))
check("Lead & Co.: the bat", table.concat(shops.guns or {}, ",") == "bat")
check("the starters are never sold ($0): the plastic bag and the pistol", (Transport.findKit("bag") :: Config.KitDef).starter == true
	and (Transport.findKit("bag") :: Config.KitDef).price == 0 and (Economy.findWeapon("pistol") :: Config.WeaponDef).starter == true
	and (Economy.findWeapon("pistol") :: Config.WeaponDef).price == 0)
check("every other piece of kit has a price", (function()
	for _, def in Config.Kit do
		if not def.starter and def.price <= 0 then
			return false
		end
	end
	return true
end)())

-- ── The gun upgrades at Lead & Co. (the save keys stay) ──────────────────────────────────────────────────────────

check("Gun Damage and Fire Rate: gun tracks, their ids kept", Economy.findUpgrade("damage") ~= nil and Economy.findUpgrade("firerate") ~= nil
	and not Economy.isCarUpgrade("damage") and not Economy.isCarUpgrade("firerate"))
check("… they still work for the guns and the car guns", near(Economy.weaponStats("pistol", { damage = 1 }).damage, 20 * 1.2) and near(Economy.carGunStats("roofmg", { damage = 1 }).damage, 14 * 1.2))

-- ── The reworked numbers ─────────────────────────────────────────────────────────────────────────────────────────

check("the Ram Plow: −12% of the dent a level (Lv 5: 40%), never under RamGuardMin", Economy.ramGuard({}) == 1 and near(Economy.ramGuard({ plow = 1 }), 0.88)
	and near(Economy.ramGuard({ plow = 5 }), 0.4) and Economy.ramGuard({ plow = 99 }) >= Config.Horde.RamGuardMin)
check("… in the car's stats (a company vehicle: the whole dent)", near(Economy.carStats("van", { plow = 5 }).ramGuard, 0.4) and Economy.carStats("ambulance", {}).ramGuard == 1)
check("… and its words say so", string.find((Economy.findUpgrade("plow") :: Config.UpgradeDef).description, "dent", 1, true) ~= nil)
check("the Roof Rack: +2 light pieces", Config.GearTuning.RoofRackSlots == 2 and Economy.capacity("van", { stage = 3 }, { roofrack = true }, "parcel") == 6
	and Economy.capacity("van", { stage = 3 }, { roofrack = true }, "crate") == 4)
check("the Muscle Car: 2 slots, 3 as a Street Machine", Economy.stageCapacity("muscle", 0) == 2 and Economy.stageCapacity("muscle", 1) == 3)
local rally = Economy.carStats("rallyvan", { stage = 1 })
check("the Works Rally: +100 health on top of its speed", rally.health == (Economy.findCar("rallyvan") :: Config.CarDef).health + 100
	and rally.maxSpeed > Economy.carStats("rallyvan", {}).maxSpeed)
local scooter, cargo = Economy.findCar("escooter") :: Config.CarDef, Economy.findCar("cargobike") :: Config.CarDef
check("the E-Scooter: 3 slots for less than the Cargo Bike", scooter.capacity == 3 and scooter.price < cargo.price and (scooter.level or 1) <= (cargo.level or 1))
check("the Hunting Rifle: 60 a shot", (Economy.findWeapon("rifle") :: Config.WeaponDef).damage == 60)
check("bike runs: up to 8 pieces (the trailer counts)", Config.Jobs.Bike.Pieces[2] == 8)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
