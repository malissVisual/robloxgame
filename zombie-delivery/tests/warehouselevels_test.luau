-- 8.3 SANDBOX, the warehouse's levels (shared/WarehouseLevels.luau, Config.WarehouseLevels): the five levels as the
-- owner asked (bigger each time, more stands: 2, 4, 8, 12, 20), a level checked (junk: the start), the words (the card's
-- lines, the purchase's toast), the least level for a count of stands, the UPGRADES card (its prices rising, a real
-- goal: the first after a move or two, the top after hours), and the migration of a save from before the levels: only
-- a real save without the flag, at least level 4 (the building it had), level 5 for every More stands bought or a
-- piece on show past stand 12, never fewer stands than it had; More stands read only with the upgrades' flag, the pieces
-- only with the collection's; once (a save written with the flag is not migrated again).
-- Run with tests/run_tests.py (the server's: tests/upgrades_runtime_test.luau).
local Config = require("./Config")
local Levels = require("./WarehouseLevels")
local UpgradeRules = require("./UpgradeRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local L = Config.WarehouseLevels

-- ── The levels ──────────────────────────────────────────────────────────────
check("five levels, a new player's the first (Config.WarehouseLevels.Start = 1)", Levels.Count == 5 and Levels.Start == 1 and L.Start == 1)
local bigger, wider = true, true
for n = 2, Levels.Count do
	local a, b = L.List[n - 1], L.List[n]
	bigger = bigger and b.size[1] > a.size[1] and b.size[3] > a.size[3] and b.size[2] > a.size[2] and b.stands > a.stands and b.price > a.price
	wider = wider and b.door[1] >= a.door[1] and b.door[2] > a.door[2]
end
check("each level bigger than the one before (wider, deeper, higher), more stands, dearer; its door as wide at least", bigger and wider)
check("the Blender sizes: 26 × 12 × 22 … 104 × 28 × 84 (level 4 the 8.0 warehouse, 80 × 24 × 60)", L.List[1].size[1] == 26 and L.List[1].size[2] == 12 and L.List[1].size[3] == 22
	and L.List[4].size[1] == 80 and L.List[4].size[2] == 24 and L.List[4].size[3] == 60 and L.List[5].size[1] == 104 and L.List[5].size[3] == 84 and L.List[1].door[1] == 14)
check("a level: junk (nil, NaN, a string, inf) the start's, clamped 1 … 5, a fraction down", Levels.clamp(nil) == 1 and Levels.clamp(0 / 0) == 1 and Levels.clamp("3") == 1
	and Levels.clamp(math.huge) == 1 and Levels.clamp(0) == 1 and Levels.clamp(-4) == 1 and Levels.clamp(7) == 5 and Levels.clamp(3.9) == 3)
check("the stands: 2, 4, 8, 12, 20", Levels.stands(1) == 2 and Levels.stands(2) == 4 and Levels.stands(3) == 8 and Levels.stands(4) == 12 and Levels.stands(5) == 20 and Levels.stands(nil) == 2)
check("the words: \"Level 2 · Workshop\", \"… · 4 stands\", sized: \"Level 3 · Warehouse · 58×42 · 8 stands\"", Levels.title(2) == "Level 2 · Workshop"
	and Levels.summary(2) == "Level 2 · Workshop · 4 stands" and Levels.summary(3, true) == "Level 3 · Warehouse · 58×42 · 8 stands"
	and Levels.summary(5, true) == "Level 5 · Logistics centre · 104×84 · 20 stands" and Levels.title(1) == "Level 1 · Garage", Levels.summary(3, true))
check("the toast: \"🏗 Your warehouse grew: Workshop (4 stands)\"", Levels.grew(2) == "🏗 Your warehouse grew: Workshop (4 stands)" and Levels.grew(5) == "🏗 Your warehouse grew: Logistics centre (20 stands)", Levels.grew(2))
check("the least level for a count of stands (0 … 2: 1, 3: 2, 12: 4, 13: 5, more than any: the top)", Levels.forStands(0) == 1 and Levels.forStands(2) == 1 and Levels.forStands(3) == 2
	and Levels.forStands(12) == 4 and Levels.forStands(13) == 5 and Levels.forStands(20) == 5 and Levels.forStands(99) == 5 and Levels.forStands(nil) == 1)

-- ── The UPGRADES card ───────────────────────────────────────────────────────
local card = Levels.card()
local rising, total = true, 0
for n, price in card.prices do
	total += price
	rising = rising and price == math.floor(price) and (n == 1 or price > card.prices[n - 1])
end
check("the card: Warehouse, its icon, levels 1 … 5 (its start 1), prices[n] buys level n (the start's $0)", card.name == "Warehouse" and card.icon == L.Icon and card.max == 5 and card.start == 1
	and #card.prices == 5 and card.prices[1] == 0 and Levels.card() == card and UpgradeRules.def("warehouse") == card)
check(`the prices rising: $1,500, $5,000, $12,000, $30,000 (all of it {UpgradeRules.money(total)})`, rising and card.prices[2] == 1500 and card.prices[3] == 5000 and card.prices[4] == 12000 and card.prices[5] == 30000 and total == 48500, total)
-- a real goal (Config.Collection's tuning: a first haul's best two earn about $45 a minute, its best twelve about $100,
-- the rest of a haul sells for $850 – 1,470): the Workshop after a move or two, the top after hours at the 12 stands' rate
check("a real goal: the Workshop within a haul's sale and half an hour of two stands; the top more than three hours of twelve", card.prices[2] <= 850 + 45 * 30 and card.prices[5] >= 100 * 60 * 3
	and card.prices[5] > Config.SandboxUpgrades.List.lights.prices[5])

-- ── The migration ───────────────────────────────────────────────────────────
local function save(extra: { [string]: any }?): any
	local s: any = { money = 4200, xp = 0 }
	for k, v in extra or {} do
		s[k] = v
	end
	return s
end
local function onShow(stands: { number }): any
	local entries = {}
	for k, stand in stands do
		table.insert(entries, { uid = `1-{k}`, item = "box", condition = 1, stand = stand })
	end
	return { entries = entries, nextUid = #stands + 1 }
end
check("not migrated: a new player's nil, a lock-only record (no money), junk, a save written with the flag", Levels.migrate(nil) == nil and Levels.migrate({ lock = {} }) == nil
	and Levels.migrate("x") == nil and Levels.migrate(save({ [L.Flag] = true })) == nil)
check("a real save from before the levels (8.0, 8.1, 8.2: no More stands): level 4, the building it had", Levels.migrate(save()) == 4
	and Levels.migrate(save({ sandboxUpgradesKept = true, sandboxUpgrades = { lights = 3 } })) == 4 and Levels.migrate(save({ sandboxUpgradesKept = true, sandboxUpgrades = { stands = 0 } })) == 4)
local boughtOk = true
for bought = 1, 4 do
	boughtOk = boughtOk and Levels.migrate(save({ sandboxUpgradesKept = true, sandboxUpgrades = { stands = bought } })) == 5
end
check("… with More stands bought (1 … 4 levels: 14 … 20 stands): level 5 (20 stands)", boughtOk)
check("… More stands without the upgrades' flag is not read (an 8.0 save's stray field): level 4", Levels.migrate(save({ sandboxUpgrades = { stands = 4 } })) == 4)
check("… junk More stands (NaN, a string, -2: none; 99: the top, 4)", Levels.migrate(save({ sandboxUpgradesKept = true, sandboxUpgrades = { stands = 0 / 0 } })) == 4
	and Levels.migrate(save({ sandboxUpgradesKept = true, sandboxUpgrades = { stands = "4" } })) == 4 and Levels.migrate(save({ sandboxUpgradesKept = true, sandboxUpgrades = { stands = -2 } })) == 4
	and Levels.migrate(save({ sandboxUpgradesKept = true, sandboxUpgrades = { stands = 99 } })) == 5)
check("… a piece on show on stand 13 – 20 (the collection's flag): level 5; on 1 – 12: level 4", Levels.migrate(save({ collectionKept = true, collection = onShow({ 1, 15 }) })) == 5
	and Levels.migrate(save({ collectionKept = true, collection = onShow({ 3, 12 }) })) == 4)
check("… the pieces read only with the collection's flag; a stand past 20 (none ever stood there) or junk counts for nothing", Levels.migrate(save({ collection = onShow({ 18 }) })) == 4
	and Levels.migrate(save({ collectionKept = true, collection = onShow({ 40 }) })) == 4 and Levels.migrate(save({ collectionKept = true, collection = { entries = { 5, "x", { stand = "13" } } } })) == 4
	and Levels.migrate(save({ collectionKept = true, collection = "x" })) == 4)
-- never fewer stands than it had: every More stands level, every stand on show
local neverFewer = true
for bought = 0, 4 do
	for top = 0, 20 do
		local had = L.Old.Stands + L.Old.Step * bought
		local stands = if top > 0 then { top } else {}
		local level = Levels.migrate(save({ sandboxUpgradesKept = true, sandboxUpgrades = { stands = bought }, collectionKept = true, collection = onShow(stands) }))
		neverFewer = neverFewer and level ~= nil and level >= L.Old.Least and Levels.stands(level) >= had and Levels.stands(level) >= top
	end
end
check("… never fewer stands than it had (every More stands level × every stand on show), never under level 4", neverFewer)

-- UpgradeRules.fromSave: the level in the upgrades' levels, once
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
local old = save({ sandboxUpgradesKept = true, sandboxUpgrades = { stands = 2, lights = 1 } })
local migrated = UpgradeRules.fromSave(old)
check("fromSave: an 8.1 save with More stands 2: the warehouse at 5, its lights kept, More stands gone", same(migrated, { warehouse = 5, lights = 1 }), migrated.warehouse)
local again = UpgradeRules.fromSave(save({ sandboxUpgradesKept = true, [L.Flag] = true, sandboxUpgrades = migrated }))
check("… saved again (both flags): the same, not migrated again", same(again, migrated))
check("… an 8.0 save (no flags): the warehouse at 4 only", same(UpgradeRules.fromSave(save()), { warehouse = 4 }))
check("… a new player and a lock-only record: none (the start, the garage)", same(UpgradeRules.fromSave(nil), {}) and same(UpgradeRules.fromSave({ lock = {} }), {}))
check("… a save with the flag at the start (the garage): none, not migrated", same(UpgradeRules.fromSave(save({ sandboxUpgradesKept = true, [L.Flag] = true, sandboxUpgrades = {} })), {})
	and UpgradeRules.warehouseLevel({}) == 1)
check("… a level the admin left at 2 with the flag: 2", same(UpgradeRules.fromSave(save({ sandboxUpgradesKept = true, [L.Flag] = true, sandboxUpgrades = { warehouse = 2 } })), { warehouse = 2 }))

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
