-- 8.1 SANDBOX, the upgrades' rules (shared/UpgradeRules.luau, Config.SandboxUpgrades): the four upgrades as the owner
-- asked (More stands +2 a level up to 20, Showroom lights ×1.1 a level up to 5, Van engine +5 % a level up to 3,
-- Danny's training +10 % a level up to 3), their prices (rising, whole dollars), the caps, the effects in numbers and
-- words, the window's cards (the price, whether the money buys it, how much is missing), the save's levels checked and
-- migrated (only a real save written with the flag); what they do elsewhere: CollectionRules.standsFor with levels
-- (never past Config.Warehouse.MaxStands, the hall's: WarehouseLayout.capacity), CollectionRules' income with the
-- lights (income, view, totals, boost), MoveHelperBrain.trained (Danny's walk from the owner's attribute).
-- 8.3 (design/warehouse-levels/KONTRAKT.md): the ZDC Warehouse upgrade first (levels 1 … 5: its level + 1, a new
-- player's Garage, the prices), the warehouse's stands (each level's big stands + More stands' small ones from level 4:
-- 2, 4, 8, 12 … 20, 24 … 32, always within that level's hall), More stands locked below level 4, the effects' words, the
-- migration (a real save from before 8.3: level 4).
-- Run with tests/run_tests.py (the server's purchases: tests/upgrades_runtime_test.luau).
local Config = require("./Config")
local Rules = require("./UpgradeRules")
local CollectionRules = require("./CollectionRules")
local WarehouseLayout = require("./WarehouseLayout")
local MoveHelperBrain = require("./MoveHelperBrain")
local SandboxMap = require("./SandboxMap")

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
	return math.abs(a - b) <= (eps or 1e-9)
end
local function same(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local U = Config.SandboxUpgrades

-- ── The catalogue ───────────────────────────────────────────────────────────
check("five upgrades in the window's order: warehouse (8.3), stands, lights, engine, danny", same(Rules.Order, { "warehouse", "stands", "lights", "engine", "danny" }))
local shapeOk, rising, total = true, true, 0
for _, id in Rules.Order do
	local def = Rules.def(id)
	shapeOk = shapeOk and def ~= nil and #def.name > 0 and #def.icon > 0 and def.max >= 1 and #def.prices == def.max and def.step > 0
	if def then
		for n, price in def.prices do
			total += price
			rising = rising and price == math.floor(price) and price > 0 and (n == 1 or price > def.prices[n - 1])
		end
	end
end
check("each: a name, an icon, a top level, a step and one price a level", shapeOk)
check("the prices: whole dollars, each level dearer than the one before", rising)
local stands, lights, engine, danny = Rules.def("stands"), Rules.def("lights"), Rules.def("engine"), Rules.def("danny")
local warehouse = Rules.def("warehouse")
local wanted = 0 -- (every price of every card in Config, added up apart from Rules.price)
for _, id in Config.SandboxUpgrades.Order do
	for _, price in Config.SandboxUpgrades.List[id].prices do
		wanted += price
	end
end
check(`everything bought costs {Rules.money(total)} (Config's tuning, 8.3 economy: the warehouse's levels and More stands in it)`, total == wanted and total > 0, total)
check("8.3 ZDC Warehouse: 4 levels over the Garage (level 1 … 5), one price a level", warehouse ~= nil and warehouse.name == "ZDC Warehouse" and warehouse.max == 4
	and warehouse.step == 1 and #warehouse.prices == 4 and warehouse.max == #Config.Warehouse.Levels - 1)
check("More stands: +2 a level, 4 levels (12 → 20)", stands ~= nil and stands.step == 2 and stands.max == 4 and stands.name == "More stands")
check("Showroom lights: ×1.1 a level, 5 levels", lights ~= nil and near(lights.step, 0.1) and lights.max == 5 and lights.name == "Showroom lights")
check("Van engine: +5 % top speed a level, 3 levels (no bigger cargo bay)", engine ~= nil and near(engine.step, 0.05) and engine.max == 3 and engine.name == "Van engine")
check("Danny's training: +10 % walk a level, 3 levels", danny ~= nil and near(danny.step, 0.1) and danny.max == 3 and danny.name == "Danny's training")
check("no upgrade by any other name or type", Rules.def("nope") == nil and Rules.def(nil) == nil and Rules.def(5) == nil and Rules.def({}) == nil and Rules.def(string.rep("s", 40)) == nil)
check("the save's flag and Danny's attribute (Config)", Rules.Flag == "sandboxUpgradesKept" and U.Danny == "DannyTraining")
check("8.3: the warehouse level's save flag and player attribute", Rules.WarehouseFlag == "warehouseLevelKept" and Rules.WarehouseAttribute == "WarehouseLevel"
	and U.WarehouseFlag == Rules.WarehouseFlag and U.WarehouseAttribute == Rules.WarehouseAttribute)

-- ── Levels and prices ───────────────────────────────────────────────────────
check("a level: 0 … its top, junk 0", Rules.level({ stands = 3 }, "stands") == 3 and Rules.level({ stands = 9 }, "stands") == 4 and Rules.level({ stands = -2 }, "stands") == 0
	and Rules.level({ stands = 0 / 0 }, "stands") == 0 and Rules.level({ stands = "2" }, "stands") == 0 and Rules.level({ stands = 2.7 }, "stands") == 2
	and Rules.level(nil, "stands") == 0 and Rules.level({ stands = 2 }, "nope") == 0)
check("the next level's price: level 0 → the first, the top → none", Rules.price("stands", 0) == stands.prices[1] and Rules.price("stands", 3) == stands.prices[4]
	and Rules.price("stands", 4) == nil and Rules.price("stands", 99) == nil and Rules.price("lights", 4) == lights.prices[5] and Rules.price("nope", 0) == nil)
check("… a silly level asked: clamped (negative: the first, NaN: the first)", Rules.price("engine", -5) == engine.prices[1] and Rules.price("engine", 0 / 0) == engine.prices[1] and Rules.price("engine", 1.9) == engine.prices[2])

-- ── The effects ─────────────────────────────────────────────────────────────
local extraOk, boostOk, vanOk, dannyOk = true, true, true, true
for n = 0, 4 do
	extraOk = extraOk and Rules.extraStands({ stands = n, warehouse = 3 }) == 2 * n and Rules.extraStands({ stands = n, warehouse = 4 }) == 2 * n
end
for n = 0, 5 do
	boostOk = boostOk and near(Rules.incomeBoost({ lights = n }), 1.1 ^ n, 1e-12)
end
for n = 0, 3 do
	vanOk = vanOk and near(Rules.vanSpeed({ engine = n }), 1 + 0.05 * n)
	dannyOk = dannyOk and near(Rules.dannySpeed(n), 1 + 0.1 * n)
end
check("More stands: +0, 2, 4, 6, 8 stands from level 4 on; at most 8 (mostStands)", extraOk and Rules.extraStands({ stands = 9, warehouse = 3 }) == 8 and Rules.mostStands() == 8 and Rules.extraStands(nil) == 0)
check("8.3: … none below level 4 (a Garage, a Workshop, a Storehouse have no small stands)", Rules.extraStands({ stands = 4 }) == 0 and Rules.extraStands({ stands = 4, warehouse = 2 }) == 0)
local levelOk = true
for k = 0, 4 do
	levelOk = levelOk and Rules.warehouseLevel({ warehouse = k }) == k + 1
end
check("8.3: the warehouse's level is its upgrade's + 1 (none: the Garage, 1; junk: 1; too much: 5)", levelOk and Rules.warehouseLevel({}) == 1 and Rules.warehouseLevel(nil) == 1
	and Rules.warehouseLevel({ warehouse = 9 }) == 5 and Rules.warehouseLevel({ warehouse = -1 }) == 1 and Rules.warehouseLevel({ warehouse = "3" }) == 1)
check("8.3: More stands locked below the Big Warehouse (its reason), never above; the others never",
	Rules.locked({}, "stands") == "Needs the Big Warehouse" and Rules.locked({ warehouse = 2 }, "stands") == "Needs the Big Warehouse" and Rules.locked({ warehouse = 3 }, "stands") == nil
	and Rules.locked({ warehouse = 4 }, "stands") == nil and Rules.locked({}, "warehouse") == nil and Rules.locked({}, "lights") == nil and Rules.locked({}, "nope") == nil)
check("Showroom lights: ×1.1 a level, compounding (×1.61 at the top)", boostOk and near(Rules.incomeBoost({ lights = 5 }), 1.61051, 1e-9) and Rules.incomeBoost({}) == 1)
check("Van engine: ×1.05, 1.10, 1.15 top speed", vanOk and near(Rules.vanSpeed({ engine = 7 }), 1.15) and Rules.vanSpeed(nil) == 1)
check("Danny's training: ×1.1, 1.2, 1.3 walk; junk 1", dannyOk and near(Rules.dannySpeed(9), 1.3) and Rules.dannySpeed(nil) == 1 and Rules.dannySpeed("x") == 1 and Rules.dannySpeed(-2) == 1 and Rules.dannySpeed(0 / 0) == 1)
check("the effects in words", Rules.effect("stands", 0) == "12 display stands" and Rules.effect("stands", 2) == "16 display stands" and Rules.effect("lights", 0) == "Income ×1.00"
	and Rules.effect("lights", 2) == "Income ×1.21" and Rules.effect("lights", 5) == "Income ×1.61" and Rules.effect("engine", 0) == "Stock engine" and Rules.effect("engine", 2) == "Top speed +10%"
	and Rules.effect("danny", 0) == "Danny's own pace" and Rules.effect("danny", 3) == "Danny walks 30% faster" and Rules.effect("nope", 1) == "", Rules.effect("lights", 2))
check("8.3: the warehouse in words: each level's name and its stands", Rules.effect("warehouse", 0) == "Garage · 2 stands" and Rules.effect("warehouse", 1) == "Workshop · 4 stands"
	and Rules.effect("warehouse", 2) == "Storehouse · 8 stands" and Rules.effect("warehouse", 3) == "Big Warehouse · 12 stands" and Rules.effect("warehouse", 4) == "Logistics Center · 24 stands"
	and Rules.effect("warehouse", 9) == "Logistics Center · 24 stands", Rules.effect("warehouse", 0))
check("8.3: More stands in words on the player's warehouse (its big stands + the small ones; below level 4 only the big ones)",
	Rules.effect("stands", 1, { warehouse = 3, stands = 1 }) == "14 display stands" and Rules.effect("stands", 2, { warehouse = 4 }) == "28 display stands"
	and Rules.effect("stands", 1, { warehouse = 1 }) == "4 display stands", Rules.effect("stands", 2, { warehouse = 4 }))
check("money: $0, $750, $1,500, $54,250, junk $0", Rules.money(0) == "$0" and Rules.money(750) == "$750" and Rules.money(1500) == "$1,500" and Rules.money(54250) == "$54,250"
	and Rules.money(1234567) == "$1,234,567" and Rules.money(-5) == "$0" and Rules.money(0 / 0) == "$0" and Rules.money("x") == "$0")

-- ── The window's cards ──────────────────────────────────────────────────────
local rows = Rules.rows({ warehouse = 3, stands = 1, lights = 5 }, 2000)
check("the cards in order, each with its level and top", #rows == 5 and rows[1].id == "warehouse" and rows[2].id == "stands" and rows[3].id == "lights" and rows[4].id == "engine"
	and rows[5].id == "danny" and rows[1].level == 3 and rows[1].max == 4 and rows[2].level == 1 and rows[2].max == 4 and rows[3].level == 5 and rows[4].level == 0)
local top = warehouse.prices[4] -- (the Logistics Center's: Config's)
check(`8.3: the warehouse at level 4 with $2,000: now the Big Warehouse, next the Logistics Center, {Rules.money(top)}, {Rules.money(top - 2000)} short`, rows[1].now == "Big Warehouse · 12 stands"
	and rows[1].next == "Logistics Center · 24 stands" and rows[1].price == top and rows[1].can == false and rows[1].short == top - 2000 and rows[1].locked == nil)
check(`More stands at 1 with $2,000: now 14, next 16, {Rules.money(stands.prices[2])}, {Rules.money(stands.prices[2] - 2000)} short`, rows[2].now == "14 display stands"
	and rows[2].next == "16 display stands" and rows[2].price == stands.prices[2] and rows[2].can == false and rows[2].short == stands.prices[2] - 2000 and rows[2].locked == nil)
check("the lights at the top: no next, no price, nothing to buy", rows[3].next == nil and rows[3].price == nil and rows[3].can == false and rows[3].short == 0 and rows[3].now == "Income ×1.61")
check(`the engine at 0 with $2,000: next +5 %, {Rules.money(engine.prices[1])}, the money buys it`, rows[4].next == "Top speed +5%" and rows[4].price == engine.prices[1]
	and engine.prices[1] <= 2000 and rows[4].can == true and rows[4].short == 0)
check("8.3 economy: the first level of each upgrade $1,500, the tops $75,000 (lights), $15,000 (engine), $12,000 (Danny)", lights.prices[1] == 1500 and engine.prices[1] == 1500
	and danny.prices[1] == 1500 and lights.prices[5] == 75000 and engine.prices[3] == 15000 and danny.prices[3] == 12000)
check("no money (nil, NaN): nothing can be bought", not Rules.rows({}, nil)[1].can and not Rules.rows({}, 0 / 0)[5].can)
local fresh = Rules.rows({}, 99999)
check(`8.3: a new player's cards: the Garage (next the Workshop, {Rules.money(warehouse.prices[1])}, bought), More stands locked (its reason, not bought however rich)`,
	fresh[1].now == "Garage · 2 stands" and fresh[1].next == "Workshop · 4 stands" and fresh[1].price == warehouse.prices[1] and fresh[1].can == true and fresh[1].locked == nil
	and fresh[2].locked == "Needs the Big Warehouse" and fresh[2].can == false and fresh[2].now == "2 display stands" and fresh[3].can == true and fresh[3].locked == nil)
check("8.3: … a card at its top is never locked (nothing left to buy)", Rules.rows({ warehouse = 4 }, 0)[1].locked == nil and Rules.rows({ warehouse = 4 }, 0)[1].price == nil)

-- ── The save ────────────────────────────────────────────────────────────────
check("a new player: none", same(Rules.empty(), {}))
check("full: every upgrade at its top (the admin's MAX; 8.3: the Logistics Center)", same(Rules.full(), { warehouse = 4, stands = 4, lights = 5, engine = 3, danny = 3 }))
local cleaned = Rules.clean({ stands = 2, lights = 99, engine = 0, danny = 1.8, nitro = 3, [1] = 5, foo = "bar" })
check("clean: known ids only, whole levels 1 … top (more is the top, 0 dropped, a fraction down)", same(cleaned, { stands = 2, lights = 5, danny = 1 }))
check("… junk: nothing (never an error)", same(Rules.clean(nil), {}) and same(Rules.clean("x"), {}) and same(Rules.clean({ stands = 0 / 0, lights = -1, engine = "3" }), {}))
local saved = { money = 500, sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = { stands = 3, engine = 2, warehouse = 2, junk = 4 } }
check("the migration: a real save with the flags keeps its levels (cleaned)", same(Rules.fromSave(saved), { stands = 3, engine = 2, warehouse = 2 }))
check("8.3: … a real save with both flags and no warehouse: the Garage (none)", same(Rules.fromSave({ money = 50, sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = {} }), {}))
check("8.3: … a real save from before 8.3 (no warehouse flag): its levels and the Big Warehouse (level 4) it had",
	same(Rules.fromSave({ money = 500, sandboxUpgradesKept = true, sandboxUpgrades = { stands = 3, engine = 2 } }), { stands = 3, engine = 2, warehouse = 3 })
	and same(Rules.fromSave({ money = 500, sandboxUpgradesKept = true, sandboxUpgrades = { warehouse = 4 } }), { warehouse = 4 }))
check("… a save from before 8.1 (money, no flag): no upgrades (8.3: but the Big Warehouse it had)", same(Rules.fromSave({ money = 9000, sandboxUpgrades = { stands = 4 } }), { warehouse = 3 }))
check("… a lock-only record (no money), a new player's nil, junk: none", same(Rules.fromSave({ lock = {}, sandboxUpgradesKept = true, sandboxUpgrades = { stands = 4 } }), {})
	and same(Rules.fromSave(nil), {}) and same(Rules.fromSave("x"), {}) and same(Rules.fromSave({ money = 1, sandboxUpgradesKept = "yes", warehouseLevelKept = true, sandboxUpgrades = { stands = 1 } }), {}))
local again = Rules.fromSave({ money = 500, sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = Rules.fromSave(saved) })
check("… run again on what it gave (saved again): the same", same(again, Rules.fromSave(saved)))
check("8.3: … a save an older server wrote again (the level and its flag gone, rewards' key kept): its own level, the Garage's too",
	same(Rules.fromSave({ money = 9, sandboxUpgradesKept = true, sandboxUpgrades = { stands = 2 }, rewards = { ["warehouse:4"] = true } }), { stands = 2, warehouse = 4 })
		and same(Rules.fromSave({ money = 9, sandboxUpgradesKept = true, sandboxUpgrades = {}, rewards = { ["warehouse:0"] = true } }), {})
		and same(Rules.fromSave({ money = 9, rewards = { ["warehouse:1"] = true, ["warehouse:2"] = true, other = true } }), { warehouse = 2 }))
check("8.3: keptWarehouse and warehouseKey: the key round-trips; junk keys are no level", Rules.warehouseKey({ warehouse = 3 }) == "warehouse:3" and Rules.warehouseKey({}) == "warehouse:0"
	and Rules.keptWarehouse({ [Rules.warehouseKey({ warehouse = 3 })] = true }) == 3 and Rules.keptWarehouse(nil) == nil and Rules.keptWarehouse({ ["warehouse:x"] = true, ["warehouse:9"] = true, ["warehouse:1.5"] = true, ["warehouse:2"] = false }) == nil)
local old = Rules.fromSave({ money = 500, sandboxUpgradesKept = true, sandboxUpgrades = { lights = 1 } })
check("8.3: … a migrated save saved again (with the flag): still level 4", same(Rules.fromSave({ money = 500, sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = old }), { lights = 1, warehouse = 3 }))

-- ── The stands (CollectionRules.standsFor, the hall) ────────────────────────
local function profile(levels: any): any
	return { sandboxUpgrades = levels }
end
check("standsFor (8.3): the warehouse's big stands (Garage 2, Workshop 4, Storehouse 8, Big Warehouse 12, Logistics Center 24)",
	CollectionRules.standsFor(profile({})) == 2 and CollectionRules.standsFor(profile({ warehouse = 1 })) == 4 and CollectionRules.standsFor(profile({ warehouse = 2 })) == 8
	and CollectionRules.standsFor(profile({ warehouse = 3 })) == 12 and CollectionRules.standsFor(profile({ warehouse = 4 })) == 24 and CollectionRules.standsFor(nil) == 2)
check("… + 2 a More stands level from the Big Warehouse on (14, 16, 18, 20; the Logistics Center up to 32); none below",
	CollectionRules.standsFor(profile({ warehouse = 3, stands = 1 })) == 14 and CollectionRules.standsFor(profile({ warehouse = 3, stands = 3 })) == 18
	and CollectionRules.standsFor(profile({ warehouse = 3, stands = 4 })) == 20 and CollectionRules.standsFor(profile(Rules.full())) == 32
	and CollectionRules.standsFor(profile({ warehouse = 2, stands = 4 })) == 8 and CollectionRules.standsFor(profile({ stands = 4 })) == 2)
check("… junk levels: the Garage's", CollectionRules.standsFor(profile("x")) == 2 and CollectionRules.standsFor(profile({ stands = -3, warehouse = 0 / 0 })) == 2 and CollectionRules.standsFor({ sandboxUpgrades = { stands = 0 / 0 } }) == 2)
check("the Big Warehouse and every More stands level fit its hall: 12 + 8 = Config.Warehouse.MaxStands = WarehouseLayout.capacity()", Config.Warehouse.Stands + Rules.mostStands() == Config.Warehouse.MaxStands
	and WarehouseLayout.capacity() == Config.Warehouse.MaxStands and WarehouseLayout.capacity(4) == Config.Warehouse.MaxStands)
local layoutOk, fullOk = true, true
for k = 0, warehouse.max do
	for n = 0, stands.max do
		local levels = { warehouse = k, stands = n }
		local count = CollectionRules.standsFor(profile(levels))
		local site = WarehouseLayout.site(1, k + 1) :: any
		layoutOk = layoutOk and count <= WarehouseLayout.capacity(k + 1) and WarehouseLayout.stand(site, count) ~= nil and #WarehouseLayout.stands(site, count) == count
		if n == stands.max then
			fullOk = fullOk and count == WarehouseLayout.capacity(k + 1) -- (everything bought: the whole hall)
		end
	end
end
check("8.3: … every warehouse level's stands, with every More stands level, are in that level's hall (WarehouseLayout.site); all bought fills it", layoutOk and fullOk)
do
	local C: any = Config
	local before = C.Warehouse
	C.Warehouse = { Stands = 16, MaxStands = 20 }
	local capped = CollectionRules.standsFor(profile({ stands = 4 }))
	C.Warehouse = { Stands = 12 }
	local open = CollectionRules.standsFor(profile({ stands = 4 }))
	C.Warehouse = { Stands = 30, MaxStands = 20 }
	local over = CollectionRules.standsFor(profile({ stands = 2 }))
	C.Warehouse = before
	check("standsFor never past MaxStands (16 + 8 → 20); without MaxStands the start + 8; a start over it stays", capped == 20 and open == 20 and over == 30, `{capped} {open} {over}`)
end

-- ── The lights (CollectionRules' income) ────────────────────────────────────
local piano: CollectionRules.Entry = { uid = "1-1", item = "piano", variant = 1, condition = 0.9, name = "Piano", stand = 1, got = 0 }
local tv: CollectionRules.Entry = { uid = "1-2", item = "tv", variant = 1, condition = 1, name = "Old TV", stand = 2, got = 0 }
local broken: CollectionRules.Entry = { uid = "1-3", item = "sofa", variant = 1, condition = 0, name = "Sofa", stand = 3, got = 0 }
local boost = CollectionRules.boost(profile({ lights = 2 }))
check("boost: ×1.21 with the lights at 2, ×1 without (no profile, none bought)", near(boost, 1.21) and CollectionRules.boost(nil) == 1 and CollectionRules.boost(profile({})) == 1)
check("income × the boost (the piano: ×1.21)", near(CollectionRules.income(piano, boost), CollectionRules.income(piano) * 1.21) and CollectionRules.income(piano) > 0)
check("… a broken piece still earns nothing; a junk boost is ×1", CollectionRules.income(broken, boost) == 0 and CollectionRules.income(piano, 0 / 0) == CollectionRules.income(piano)
	and CollectionRules.income(piano, -2) == CollectionRules.income(piano) and CollectionRules.income(piano, "x" :: any) == CollectionRules.income(piano))
local view = CollectionRules.view(piano, boost)
check("view: its income × the boost (to the cent), its price unchanged (the lights are not a sale)", near(view.income, math.floor(CollectionRules.income(piano) * 1.21 * 100 + 0.5) / 100, 1e-9)
	and view.price == CollectionRules.sell(piano) and CollectionRules.view(piano).income < view.income)
local t1, t2 = CollectionRules.totals({ piano, tv, broken }), CollectionRules.totals({ piano, tv, broken }, boost)
check("totals: the income × the boost, the rest as it was", near(t2.income, t1.income * 1.21, 1e-9) and t2.sell == t1.sell and t2.value == t1.value and t2.shown == 3)

-- ── Danny (MoveHelperBrain.trained) ─────────────────────────────────────────
local function owner(level: any): any
	return {
		GetAttribute = function(_self: any, name: string): any
			return if name == U.Danny then level else nil
		end,
	}
end
check("Danny's walk × his training: the owner's attribute (0 … 3 levels: ×1, ×1.1, ×1.2, ×1.3)", MoveHelperBrain.trained(owner(nil)) == 1 and near(MoveHelperBrain.trained(owner(1)), 1.1)
	and near(MoveHelperBrain.trained(owner(3)), 1.3) and near(MoveHelperBrain.trained(owner(8)), 1.3))
check("… no owner, an owner without attributes, a junk level: ×1", MoveHelperBrain.trained(nil) == 1 and MoveHelperBrain.trained({}) == 1 and MoveHelperBrain.trained(owner("fast")) == 1)
local walk = 16
check("… on top of his own pace (MoveHelperBrain.speed's)", near(MoveHelperBrain.speed(walk, "fetch", nil, 0) * MoveHelperBrain.trained(owner(2)), walk * Config.MoveHelper.Speed * 1.2))

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
