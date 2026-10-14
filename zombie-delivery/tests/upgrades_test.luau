-- 8.1 SANDBOX, the upgrades' rules (shared/UpgradeRules.luau, Config.SandboxUpgrades): the four upgrades as the owner
-- asked (8.3: the Warehouse's levels 1 … 5 in place of More stands, Showroom lights ×1.1 a level up to 5, Van engine
-- +5 % a level up to 3, Danny's training +10 % a level up to 3), their prices (rising, whole dollars), the caps, the
-- effects in numbers and words, the window's cards (the price, whether the money buys it, how much is missing), the
-- save's levels checked and migrated (only a real save written with the flag; 8.3: the warehouse's own migration,
-- tests/warehouselevels_test.luau); what they do elsewhere: CollectionRules.standsFor with levels (the warehouse level's
-- stands, every one in that level's layout: WarehouseLayout), CollectionRules' income with the lights (income, view,
-- totals, boost), MoveHelperBrain.trained (Danny's walk from the owner's attribute).
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
check("four upgrades in the window's order: warehouse (8.3), lights, engine, danny", same(Rules.Order, { "warehouse", "lights", "engine", "danny" }))
local shapeOk, rising, total = true, true, 0
for _, id in Rules.Order do
	local def = Rules.def(id)
	local start = if def then def.start or 0 else 0
	shapeOk = shapeOk and def ~= nil and #def.name > 0 and #def.icon > 0 and def.max >= 1 and #def.prices == def.max and (def.step > 0 or id == "warehouse")
	if def then
		for n, price in def.prices do
			if n > start then -- (the warehouse's prices[1]: its start, never bought)
				total += price
				rising = rising and price == math.floor(price) and price > 0 and (n == start + 1 or price > def.prices[n - 1])
			end
		end
	end
end
check("each: a name, an icon, a top level, a step (the warehouse: its levels) and one price a level", shapeOk)
check("the prices: whole dollars, each level dearer than the one before", rising)
check(`everything bought costs $84,250 (Config's tuning: $35,750 + the warehouse's $48,500; {Rules.money(total)})`, total == 84250, total)
local warehouse, lights, engine, danny = Rules.def("warehouse"), Rules.def("lights"), Rules.def("engine"), Rules.def("danny")
check("the Warehouse: levels 1 → 5 (its start 1: the garage), More stands gone into it", warehouse ~= nil and warehouse.start == 1 and warehouse.max == 5 and warehouse.name == "Warehouse"
	and Rules.def("stands") == nil)
check("Showroom lights: ×1.1 a level, 5 levels", lights ~= nil and near(lights.step, 0.1) and lights.max == 5 and lights.name == "Showroom lights")
check("Van engine: +5 % top speed a level, 3 levels (no bigger cargo bay)", engine ~= nil and near(engine.step, 0.05) and engine.max == 3 and engine.name == "Van engine")
check("Danny's training: +10 % walk a level, 3 levels", danny ~= nil and near(danny.step, 0.1) and danny.max == 3 and danny.name == "Danny's training")
check("no upgrade by any other name or type", Rules.def("nope") == nil and Rules.def(nil) == nil and Rules.def(5) == nil and Rules.def({}) == nil and Rules.def(string.rep("s", 40)) == nil)
check("the save's flag and Danny's attribute (Config)", Rules.Flag == "sandboxUpgradesKept" and U.Danny == "DannyTraining")

-- ── Levels and prices ───────────────────────────────────────────────────────
check("a level: 0 … its top, junk 0 (the warehouse's: its start 1 … 5, junk 1)", Rules.level({ engine = 3 }, "engine") == 3 and Rules.level({ engine = 9 }, "engine") == 3 and Rules.level({ engine = -2 }, "engine") == 0
	and Rules.level({ engine = 0 / 0 }, "engine") == 0 and Rules.level({ engine = "2" }, "engine") == 0 and Rules.level({ engine = 2.7 }, "engine") == 2
	and Rules.level(nil, "engine") == 0 and Rules.level({ engine = 2 }, "nope") == 0
	and Rules.level({ warehouse = 3 }, "warehouse") == 3 and Rules.level({ warehouse = 9 }, "warehouse") == 5 and Rules.level({ warehouse = -2 }, "warehouse") == 1
	and Rules.level({ warehouse = 0 / 0 }, "warehouse") == 1 and Rules.level(nil, "warehouse") == 1 and Rules.warehouseLevel({ warehouse = 4.5 }) == 4)
check("the next level's price: level 0 → the first, the top → none (the warehouse at 1 → level 2's $1,500)", Rules.price("engine", 0) == engine.prices[1] and Rules.price("engine", 2) == engine.prices[3]
	and Rules.price("engine", 3) == nil and Rules.price("engine", 99) == nil and Rules.price("lights", 4) == lights.prices[5] and Rules.price("nope", 0) == nil
	and Rules.price("warehouse", 1) == 1500 and Rules.price("warehouse", 4) == 30000 and Rules.price("warehouse", 5) == nil and Rules.price("warehouse", -3) == 1500)
check("… a silly level asked: clamped (negative: the first, NaN: the first)", Rules.price("engine", -5) == engine.prices[1] and Rules.price("engine", 0 / 0) == engine.prices[1] and Rules.price("engine", 1.9) == engine.prices[2])

-- ── The effects ─────────────────────────────────────────────────────────────
local extraOk, boostOk, vanOk, dannyOk = true, true, true, true
for n, want in { 2, 4, 8, 12, 20 } do
	extraOk = extraOk and Rules.stands({ warehouse = n }) == want
end
for n = 0, 5 do
	boostOk = boostOk and near(Rules.incomeBoost({ lights = n }), 1.1 ^ n, 1e-12)
end
for n = 0, 3 do
	vanOk = vanOk and near(Rules.vanSpeed({ engine = n }), 1 + 0.05 * n)
	dannyOk = dannyOk and near(Rules.dannySpeed(n), 1 + 0.1 * n)
end
check("the Warehouse: 2, 4, 8, 12, 20 stands (levels 1 … 5); junk the start's 2", extraOk and Rules.stands({ warehouse = 9 }) == 20 and Rules.stands(nil) == 2 and Rules.stands({ warehouse = "x" }) == 2)
check("Showroom lights: ×1.1 a level, compounding (×1.61 at the top)", boostOk and near(Rules.incomeBoost({ lights = 5 }), 1.61051, 1e-9) and Rules.incomeBoost({}) == 1)
check("Van engine: ×1.05, 1.10, 1.15 top speed", vanOk and near(Rules.vanSpeed({ engine = 7 }), 1.15) and Rules.vanSpeed(nil) == 1)
check("Danny's training: ×1.1, 1.2, 1.3 walk; junk 1", dannyOk and near(Rules.dannySpeed(9), 1.3) and Rules.dannySpeed(nil) == 1 and Rules.dannySpeed("x") == 1 and Rules.dannySpeed(-2) == 1 and Rules.dannySpeed(0 / 0) == 1)
check("the effects in words", Rules.effect("warehouse", 1) == "Level 1 · Garage · 2 stands" and Rules.effect("warehouse", 4) == "Level 4 · Big warehouse · 12 stands" and Rules.effect("lights", 0) == "Income ×1.00"
	and Rules.effect("lights", 2) == "Income ×1.21" and Rules.effect("lights", 5) == "Income ×1.61" and Rules.effect("engine", 0) == "Stock engine" and Rules.effect("engine", 2) == "Top speed +10%"
	and Rules.effect("danny", 0) == "Danny's own pace" and Rules.effect("danny", 3) == "Danny walks 30% faster" and Rules.effect("nope", 1) == "", Rules.effect("lights", 2))
check("money: $0, $750, $1,500, $54,250, junk $0", Rules.money(0) == "$0" and Rules.money(750) == "$750" and Rules.money(1500) == "$1,500" and Rules.money(54250) == "$54,250"
	and Rules.money(1234567) == "$1,234,567" and Rules.money(-5) == "$0" and Rules.money(0 / 0) == "$0" and Rules.money("x") == "$0")

-- ── The window's cards ──────────────────────────────────────────────────────
local rows = Rules.rows({ warehouse = 2, lights = 5 }, 2000)
check("the cards in order, each with its level and top", #rows == 4 and rows[1].id == "warehouse" and rows[2].id == "lights" and rows[3].id == "engine" and rows[4].id == "danny"
	and rows[1].level == 2 and rows[1].max == 5 and rows[2].level == 5 and rows[3].level == 0)
check("the Warehouse at 2 with $2,000: now Level 2 · Workshop, next Level 3 with its size and stands, $5,000, $3,000 short", rows[1].now == "Level 2 · Workshop · 4 stands"
	and rows[1].next == "Level 3 · Warehouse · 58×42 · 8 stands" and rows[1].price == 5000 and rows[1].can == false and rows[1].short == 3000, rows[1].next)
check("… a new player's garage (none bought): level 1, next the Workshop for $1,500", Rules.rows({}, 1500)[1].level == 1 and Rules.rows({}, 1500)[1].can == true
	and Rules.rows({}, 0)[1].next == "Level 2 · Workshop · 40×30 · 4 stands" and Rules.rows({ warehouse = 5 }, 0)[1].next == nil)
check("the lights at the top: no next, no price, nothing to buy", rows[2].next == nil and rows[2].price == nil and rows[2].can == false and rows[2].short == 0 and rows[2].now == "Income ×1.61")
check("the engine at 0 with $2,000: next +5 %, $600, the money buys it", rows[3].next == "Top speed +5%" and rows[3].price == 600 and rows[3].can == true and rows[3].short == 0)
check("no money (nil, NaN): nothing can be bought", not Rules.rows({}, nil)[1].can and not Rules.rows({}, 0 / 0)[4].can)

-- ── The save ────────────────────────────────────────────────────────────────
check("a new player: none", same(Rules.empty(), {}))
check("full: every upgrade at its top (the admin's MAX: the Logistics centre)", same(Rules.full(), { warehouse = 5, lights = 5, engine = 3, danny = 3 }))
local cleaned = Rules.clean({ warehouse = 3, stands = 2, lights = 99, engine = 0, danny = 1.8, nitro = 3, [1] = 5, foo = "bar" })
check("clean: known ids only (8.1's More stands no more), whole levels over the start … top (more is the top, the start dropped, a fraction down)", same(cleaned, { warehouse = 3, lights = 5, danny = 1 }))
check("… junk: nothing (never an error); the warehouse at its start (1) is not kept", same(Rules.clean(nil), {}) and same(Rules.clean("x"), {}) and same(Rules.clean({ warehouse = 1, stands = 0 / 0, lights = -1, engine = "3" }), {}))
local saved = { money = 500, sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = { warehouse = 3, engine = 2, junk = 4 } }
check("the migration: a real save with the flags keeps its levels (cleaned)", same(Rules.fromSave(saved), { warehouse = 3, engine = 2 }))
check("… a save from before 8.1 (money, no flag): none but its warehouse's level (8.3: at least 4, the building it had)", same(Rules.fromSave({ money = 9000, sandboxUpgrades = { stands = 4 } }), { warehouse = 4 }))
check("… a lock-only record (no money), a new player's nil, junk: none", same(Rules.fromSave({ lock = {}, sandboxUpgradesKept = true, sandboxUpgrades = { stands = 4 } }), {})
	and same(Rules.fromSave(nil), {}) and same(Rules.fromSave("x"), {}) and same(Rules.fromSave({ money = 1, sandboxUpgradesKept = "yes", warehouseLevelKept = true, sandboxUpgrades = { warehouse = 3 } }), {}))
check("… an 8.1 save with More stands (the flag, no warehouse flag): the warehouse at 5, More stands gone", same(Rules.fromSave({ money = 1, sandboxUpgradesKept = true, sandboxUpgrades = { stands = 1, engine = 1 } }), { warehouse = 5, engine = 1 }))
local again = Rules.fromSave({ money = 500, sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = Rules.fromSave(saved) })
check("… run again on what it gave (saved again): the same", same(again, Rules.fromSave(saved)))

-- ── The stands (CollectionRules.standsFor, the warehouse's level) ────────────
local function profile(levels: any): any
	return { sandboxUpgrades = levels }
end
check("standsFor: the warehouse level's stands (the garage's 2, then 4, 8, 12, 20); no profile: the start's", CollectionRules.standsFor(profile({})) == 2 and CollectionRules.standsFor(profile({ warehouse = 2 })) == 4
	and CollectionRules.standsFor(profile({ warehouse = 4 })) == 12 and CollectionRules.standsFor(profile(Rules.full())) == 20 and CollectionRules.standsFor(nil) == 2)
check("… junk levels: the start's; 8.1's More stands counts for nothing now", CollectionRules.standsFor(profile("x")) == 2 and CollectionRules.standsFor(profile({ warehouse = -3 })) == 2
	and CollectionRules.standsFor({ sandboxUpgrades = { warehouse = 0 / 0 } }) == 2 and CollectionRules.standsFor(profile({ stands = 4 })) == 2)
local layoutOk = true
for n = 1, warehouse.max do
	local count = CollectionRules.standsFor(profile({ warehouse = n }))
	layoutOk = layoutOk and count == Config.WarehouseLevels.List[n].stands and WarehouseLayout.stand(SandboxMap.Plots[1], count, n) ~= nil
		and WarehouseLayout.stand(SandboxMap.Plots[1], count + 1, n) == nil and #WarehouseLayout.stands(1, n) == count
end
check("… every level's stands are in that level's layout (WarehouseLayout.stand)", layoutOk)

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
