-- 8.1 SANDBOX, the upgrades' rules (shared/UpgradeRules.luau, Config.SandboxUpgrades). 10.4 THE UPGRADE TREE: the
-- nodes (each a known branch and effect, whole prices rising rank by rank, a place of its own in the tree's grid, its
-- parents known and earlier in the tree's order, its tiers 1 … 5 and never falling), the trunk (the warehouse's tiers:
-- 8.3's levels and prices), the requirements (the parents at their ranks, the warehouse tier a rank needs, soon nodes,
-- the auction while the Auction House is closed) and their words, the status of every node, the checklist, the effects
-- other systems read (UpgradeRules.effect: its base, adding up, compounding, clamped), the looks, the tree's lines, the
-- rows the window draws, the save (clean, the migration from the five tracks of 8.1 – 10.3 with its flag: nothing lost,
-- the mirror in `rewards` an older server keeps), the totals; and what the legacy five still do: the hall's stands
-- (2, 4, 8, 12 … 20, 24 … 32), the lights' income, the van's engine, Danny's walk; 10.4 the showroom's stands by level
-- (WarehouseLayout's room). The prices against the incomes: tests/upgradebalance_test.luau.
-- Run with tests/run_tests.py (the server's purchases: tests/upgrades_runtime_test.luau).
local Config = require("./Config")
local Rules = require("./UpgradeRules")
local CollectionRules = require("./CollectionRules")
local WarehouseLayout = require("./WarehouseLayout")
local MoveHelperBrain = require("./MoveHelperBrain")

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
do
	local branches: { [string]: boolean } = {}
	for _, b in U.Branches do
		branches[b.id] = true
	end
	check("six branches: the trunk, looks, the hall, the showroom, runs, the crew", branches.warehouse and branches.looks and branches.hall and branches.showroom and branches.runs and branches.crew and #U.Branches == 6)
	local bad: { string } = {}
	local cells: { [string]: string } = {}
	local placeOf: { [string]: number } = {}
	for n, id in Rules.Order do
		placeOf[id] = n
	end
	for _, id in Rules.Order do
		local def = Rules.def(id)
		if not def then
			table.insert(bad, `{id}: no def`)
			continue
		end
		if #def.name == 0 or #def.icon == 0 or def.max < 1 or #def.prices ~= def.max or not branches[def.branch or ""] or U.Effects[def.effect or ""] == nil then
			table.insert(bad, `{id}: its shape`)
		end
		for n, price in def.prices do
			if price ~= math.floor(price) or price <= 0 or (n > 1 and price <= def.prices[n - 1]) then
				table.insert(bad, `{id}: price {n}`)
			end
		end
		local at = def.at
		if not at or at[1] < 1 or at[1] > U.Grid.Columns or at[2] < 1 or at[2] > U.Grid.Rows then
			table.insert(bad, `{id}: off the grid`)
		elseif id ~= "warehouse" then
			local key = `{at[1]},{at[2]}`
			if cells[key] then
				table.insert(bad, `{id} on {cells[key]}'s cell`)
			end
			cells[key] = id
			if at[2] == U.Grid.TrunkRow then
				table.insert(bad, `{id} on the trunk's row`)
			end
		end
		for parent, rank in def.needs or {} do
			local pdef = Rules.def(parent)
			if not pdef or rank < 1 or rank > pdef.max or (placeOf[parent] or math.huge) > placeOf[id] then
				table.insert(bad, `{id}: needs {parent} {rank}`)
			elseif pdef.at and at and pdef.at[1] >= at[1] then
				table.insert(bad, `{id}: left of its parent {parent}`)
			end
		end
		local tiers = def.tiers
		if tiers then
			for n, tier in tiers do
				if tier < 1 or tier > #Config.Warehouse.Levels or (n > 1 and tier < tiers[n - 1]) or #tiers ~= def.max then
					table.insert(bad, `{id}: tier {n}`)
				end
			end
		end
	end
	check("every node: a name and icon, ranks with whole prices that rise, a known branch and effect, its own cell of the grid (never the trunk's row), parents known, earlier in the order and left of it, tiers 1 … 5 never falling", #bad == 0, table.concat(bad, "; "))
	check("the trunk first; the legacy five keep their 8.1 – 8.3 prices", Rules.Order[1] == "warehouse" and same(Rules.def("warehouse").prices, { 1000, 7500, 30000, 100000 })
		and same(Rules.def("stands").prices, { 4000, 8000, 15000, 25000 }) and same(Rules.def("lights").prices, { 1500, 4000, 12000, 30000, 75000 })
		and same(Rules.def("engine").prices, { 1500, 5000, 15000 }) and same(Rules.def("danny").prices, { 1500, 4000, 12000 }))
	local looks = 0
	for _, id in Rules.Order do
		local def = Rules.def(id) :: Config.SandboxUpgradeDef
		if def.branch == "looks" then
			looks += 1
			check(`a LOOKS node is cosmetic: {id} paints the {def.look and def.look.kind or "?"}`, def.look ~= nil and (def.look.kind == "wall" or def.look.kind == "sign") and #def.look.color == 3)
		end
	end
	check("two LOOKS nodes now (the walls' paint, the sign), a lane for more", looks == 2)
	check("Rules.def: nil for junk", Rules.def("nope") == nil and Rules.def(7) == nil and Rules.def(string.rep("x", 40)) == nil)
end

-- ── Requirements ────────────────────────────────────────────────────────────
do
	local none = {}
	check("a new player: the trunk, Hall spotlights, Showroom stands, Van engine, Danny's training and Fresh paint open",
		Rules.locked(none, "warehouse") == nil and Rules.locked(none, "lights") == nil and Rules.locked(none, "showstands") == nil
		and Rules.locked(none, "engine") == nil and Rules.locked(none, "danny") == nil and Rules.locked(none, "paint") == nil)
	check("… a parent first: \"Needs Hall spotlights\", \"Needs Hall spotlights rank 2\", \"Needs Showroom stands\", \"Needs Danny's training\"",
		Rules.locked(none, "idle") == "Needs Hall spotlights" and Rules.locked(none, "rare") == "Needs Hall spotlights rank 2"
		and Rules.locked(none, "traffic") == "Needs Showroom stands" and Rules.locked(none, "toughness") == "Needs Danny's training", Rules.locked(none, "rare"))
	check("… a tier first: More hall stands \"Needs the Big Warehouse\" (8.3's words), Overtime \"Needs the Workshop\"",
		Rules.locked(none, "stands") == "Needs the Big Warehouse" and Rules.locked(none, "clock") == "Needs the Workshop")
	check("… soon nodes never: Bigger truck, Second helper (their reason); the auction while the Auction House is closed",
		Rules.locked({ clock = 3, key = 1, luck = 2, warehouse = 4 }, "truck") == U.List.truck.soon and Rules.locked({ luck = 1, warehouse = 4 }, "helperslot") == U.List.helperslot.soon
		and (Config.Auction.On or Rules.locked({ vip = 1, warehouse = 4 }, "auction") == "The Auction House opens later"))
	local parents = { lights = 1, warehouse = 1 }
	check("Night watchman: open with Hall spotlights 1 at the Workshop; its rank 2 needs the Storehouse", Rules.locked(parents, "idle") == nil
		and Rules.locked({ lights = 1, warehouse = 1, idle = 1 }, "idle") == "Needs the Storehouse" and Rules.locked({ lights = 1, warehouse = 2, idle = 1 }, "idle") == nil)
	check("Collector's corner: Hall spotlights 1 is not enough (rank 2), and the Workshop", Rules.locked({ lights = 1, warehouse = 1 }, "rare") == "Needs Hall spotlights rank 2"
		and Rules.locked({ lights = 2 }, "rare") == "Needs the Workshop" and Rules.locked({ lights = 2, warehouse = 1 }, "rare") == nil)
	check("a parent only gates rank 1: a rank owned stays and the next asks only its tier", Rules.locked({ rare = 1, warehouse = 2 }, "rare") == nil)
	check("Showroom stands: rank 1 at the Garage, rank 2 needs the Storehouse, rank 3 the Logistics Center",
		Rules.locked({}, "showstands") == nil and Rules.locked({ showstands = 1 }, "showstands") == "Needs the Storehouse"
		and Rules.locked({ showstands = 1, warehouse = 2 }, "showstands") == nil and Rules.locked({ showstands = 2, warehouse = 3 }, "showstands") == "Needs the Logistics Center")
	check("the legacy lights' deeper ranks need a bigger warehouse (rank 3 the Workshop … rank 5 the Big Warehouse)", Rules.locked({ lights = 2 }, "lights") == "Needs the Workshop"
		and Rules.locked({ lights = 4, warehouse = 2 }, "lights") == "Needs the Big Warehouse" and Rules.locked({ lights = 4, warehouse = 3 }, "lights") == nil)
	check("at the top: nothing locks it (Rules.locked nil, the price nil)", Rules.locked({ danny = 3 }, "danny") == nil and Rules.price("danny", 3) == nil)
	local list = Rules.needs({ lights = 1 }, "rare")
	check("the checklist: Collector's corner for a player with Hall spotlights 1 at the Garage: ✗ its parent at rank 2, ✗ the Workshop",
		#list == 2 and list[1].text == "Hall spotlights rank 2" and list[1].ok == false and list[2].text == "The Workshop" and list[2].ok == false, #list)
	list = Rules.needs({ lights = 2, warehouse = 1 }, "rare")
	check("… both ✓ once met; a node at its top has none", list[1].ok and list[2].ok and #Rules.needs({ danny = 3 }, "danny") == 0 and #Rules.needs({}, "lights") == 0)
	check("status: max / buy / short / locked / soon", Rules.status({ danny = 3 }, "danny", 0) == "max" and Rules.status({}, "danny", 1500) == "buy"
		and Rules.status({}, "danny", 1499) == "short" and Rules.status({}, "idle", 1e9) == "locked" and Rules.status({ warehouse = 4 }, "truck", 1e9) == "soon")
end

-- ── The effects ─────────────────────────────────────────────────────────────
do
	local E = Rules.effect
	local base = true
	for key, spec in U.Effects do
		local value = E({}, key)
		base = base and (value == math.clamp(spec.base, spec.min or -math.huge, spec.max or math.huge) or key == "tier")
	end
	check("no rank: every effect at its base (the tier 1)", base and E({}, "tier") == 1 and E({}, "nope") == 0 and E(nil, "hallIncome") == 1)
	check("Hall spotlights: ×1.1 a rank, compounding (×1.61 at rank 5); incomeBoost the same", near(E({ lights = 5 }, "hallIncome"), 1.61051) and near(Rules.incomeBoost({ lights = 2 }), 1.21))
	check("adding up: Collector's corner +20% a rank, Room sets +4% a set a rank, Night watchman +0.15 of idle pay", near(E({ rare = 3 }, "rareIncome"), 1.6)
		and near(E({ sets = 2 }, "setBonus"), 0.08) and near(E({ idle = 2 }, "idleShare"), 0.3))
	check("the showroom: Shop window ×1.2 / 1.4 / 1.6, Sales pitch +6% a rank, VIP buyers on", near(E({ traffic = 3 }, "visitorRate"), 1.6) and near(E({ haggle = 2 }, "showPrice"), 1.12)
		and E({ vip = 1 }, "vip") == 1 and E({}, "vip") == 0)
	check("runs: Overtime +8% a rank (×1.24), Spare keys, Keen eye +3% a rank; the van's engine +5% a rank (vanSpeed the same)", near(E({ clock = 3 }, "runClock"), 1.24)
		and E({ key = 1 }, "startKey") == 1 and near(E({ luck = 2 }, "lootLuck"), 0.06) and near(Rules.vanSpeed({ engine = 3 }), 1.15) and near(E({ engine = 2 }, "vanSpeed"), 1.1))
	check("the crew: Pads & helmets +15% health a rank, Running shoes +5%, First aid and Good doctors −25% a rank", near(E({ toughness = 3 }, "helperHealth"), 1.45)
		and near(E({ pace = 2 }, "helperSpeed"), 1.1) and near(E({ medic = 2 }, "reviveTime"), 0.5) and near(E({ hospital = 1 }, "hospital"), 0.75))
	check("Danny's training: +10% a rank (dannySpeed from a level, junk is none; MoveHelperBrain.trained reads the attribute)", near(Rules.dannySpeed(3), 1.3)
		and Rules.dannySpeed("x") == 1 and Rules.dannySpeed(99) == 1.3 and near(E({ danny = 2 }, "dannySpeed"), 1.2)
		and near(MoveHelperBrain.trained({ GetAttribute = function(_, key) return if key == U.Danny then 2 else nil end }), 1.2))
	check("the trunk's tier: 1 + its rank (5 at the top), warehouseLevel the same", E({ warehouse = 4 }, "tier") == 5 and Rules.warehouseLevel({ warehouse = 2 }) == 3 and Rules.warehouseLevel({}) == 1)
	check("clamped: junk ranks are none, a rank past the top is the top", E({ lights = "x" }, "hallIncome") == 1 and near(E({ medic = 99 }, "reviveTime"), 0.5) and near(E({ clock = 99 }, "runClock"), 1.24))
	check("looks: none bought, nothing; Fresh paint the walls, Gold sign the sign", next(Rules.looks({})) == nil and same(Rules.looks({ paint = 1 }), { wall = U.List.paint.look.color })
		and same(Rules.looks({ paint = 1, sign = 1 }), { wall = U.List.paint.look.color, sign = U.List.sign.look.color }))
end

-- ── The stands: the hall's (the legacy More stands) and the showroom's ──────
do
	local hall = {}
	for k = 0, 4 do
		table.insert(hall, Rules.totalStands({ warehouse = k }))
	end
	check("the hall's stands by tier (8.3): 2, 4, 8, 12, 24", same(hall, { 2, 4, 8, 12, 24 }), table.concat(hall, ","))
	check("More hall stands +2 a rank from the Big Warehouse (12 … 20, 24 … 32), nothing below it", Rules.totalStands({ warehouse = 3, stands = 4 }) == 20
		and Rules.totalStands({ warehouse = 4, stands = 4 }) == 32 and Rules.totalStands({ warehouse = 2, stands = 4 }) == 8 and Rules.extraStands({ stands = 2 }) == 0)
	check("CollectionRules.standsFor: the hall's (a profile's levels)", CollectionRules.standsFor({ sandboxUpgrades = { warehouse = 3, stands = 1 } }) == 14 and CollectionRules.standsFor(nil) == 2)
	local own, room = {}, true
	for tier = 1, 5 do
		local def = Config.Showroom.Levels[tier]
		table.insert(own, Rules.showStands({ warehouse = tier - 1 }))
		room = room and def.Most == WarehouseLayout.showCapacity(tier) and def.Stands <= def.Most
	end
	check("the showroom's stands by tier: its own (1, 1, 2, 2, 3); Config's Most is WarehouseLayout's room", same(own, { 1, 1, 2, 2, 3 }) and room, table.concat(own, ","))
	check("… Showroom stands +1 a rank, never past the level's room", Rules.showStands({ showstands = 1 }) == 2 and Rules.showStands({ showstands = 3 }) == 2
		and Rules.showStands({ warehouse = 4, showstands = 3 }) == 6 and Rules.showStands({ warehouse = 2, showstands = 2 }) == 4)
	check("CollectionRules.showStandsFor and open: the hall 1 … n, the showroom Base + 1 … Base + m", CollectionRules.showStandsFor({ sandboxUpgrades = { warehouse = 2 } }) == 2
		and CollectionRules.open({ sandboxUpgrades = {} }, 2) and not CollectionRules.open({ sandboxUpgrades = {} }, 3) and CollectionRules.open({ sandboxUpgrades = {} }, Config.Showroom.Base + 1)
		and not CollectionRules.open({ sandboxUpgrades = {} }, Config.Showroom.Base + 2) and not CollectionRules.open({}, 0) and not CollectionRules.open({}, 1.5))
end

-- ── Words ───────────────────────────────────────────────────────────────────
do
	local W = Rules.words
	check("the trunk's words: \"Garage · 2 stands\" … \"Logistics Center · 24 stands\"", W("warehouse", 0) == "Garage · 2 stands" and W("warehouse", 4) == "Logistics Center · 24 stands")
	check("the legacy words: Income ×1.21, Stock engine, Top speed +10%, Danny's own pace, Danny walks 30% faster, 14 hall stands (with the levels)",
		W("lights", 2) == "Income ×1.21" and W("engine", 0) == "Stock engine" and W("engine", 2) == "Top speed +10%" and W("danny", 0) == "Danny's own pace"
		and W("danny", 3) == "Danny walks 30% faster" and W("stands", 1, { warehouse = 3 }) == "14 hall stands" and W("stands", 1, {}) == "2 hall stands")
	check("the tree's words: Run clock +16%, Showroom prices +12%, Visitors ×1.4, Epic & Legendary +40%, Revive 50% faster, Hospital 25% shorter, Pays 55% while idle",
		W("clock", 2) == "Run clock +16%" and W("haggle", 2) == "Showroom prices +12%" and W("traffic", 2) == "Visitors ×1.4" and W("rare", 2) == "Epic & Legendary +40%"
		and W("medic", 2) == "Revive 50% faster" and W("hospital", 1) == "Hospital 25% shorter" and W("idle", 2) == "Pays 55% while idle", W("idle", 2))
	check("rank 0 of a tree node: \"Not bought yet\"; junk: \"\"", W("clock", 0) == "Not bought yet" and W("nope", 1) == "")
	check("the money's words: $1,234 (whole, never negative)", Rules.money(1234.4) == "$1,234" and Rules.money(-5) == "$0" and Rules.money(1000000) == "$1,000,000" and Rules.money("x") == "$0")
end

-- ── The tree: lines and rows ────────────────────────────────────────────────
do
	local links = Rules.links()
	local into: { [string]: number } = {}
	local okTrunk = true
	for _, link in links do
		into[link.to] = (into[link.to] or 0) + 1
		if link.from == "warehouse" then
			okTrunk = okTrunk and link.tier >= 1 and link.tier <= 5 and (Rules.def(link.to) :: any).needs == nil
		end
	end
	local every = true
	for _, id in Rules.Order do
		if id ~= "warehouse" then
			every = every and (into[id] or 0) >= 1
		end
	end
	check("the lines: every node has one in (from its parents, or a branch's first from the trunk's tier it needs)", every and okTrunk)
	check("the trunk's tiles at the odd columns of its row", same(Rules.trunkAt(1), { 1, U.Grid.TrunkRow }) and same(Rules.trunkAt(5), { 9, U.Grid.TrunkRow }))
	local rows = Rules.rows({ warehouse = 3, lights = 5, stands = 1 }, 2000)
	local byId: { [string]: Rules.Row } = {}
	for _, row in rows do
		byId[row.id] = row
	end
	check("rows: one a node in the tree's order", #rows == #Rules.Order and rows[1].id == "warehouse")
	local lights, stands, engine, rare = byId.lights, byId.stands, byId.engine, byId.rare
	check("… at its top: MAX, no price, no next", lights.status == "max" and lights.price == nil and lights.next == nil and lights.now == "Income ×1.61")
	check("… short of money: its price, NEED's amount, can false", stands.status == "short" and stands.price == 8000 and stands.short == 6000 and not stands.can and stands.next == "16 hall stands")
	check("… the money buys it: buy, can", engine.status == "buy" and engine.can and engine.price == 1500 and engine.short == 0)
	check("… a row carries its branch, place, blurb and checklist", rare.branch == "hall" and same(rare.at, U.List.rare.at) and #rare.blurb > 10 and #rare.needs >= 1 and rare.tier == 2)
	check("… a soon node: soon, its reason as locked, never can", byId.truck.soon and byId.truck.status == "soon" and not byId.truck.can and byId.truck.locked == U.List.truck.soon)
end

-- ── The save ────────────────────────────────────────────────────────────────
do
	check("empty: none", next(Rules.empty()) == nil)
	local full = Rules.full()
	local fullOk = full.warehouse == 4 and full.lights == 5 and full.truck == nil and full.helperslot == nil and full.paint == 1
	check("full: every node at its top but the soon ones (the admin's MAX)", fullOk)
	check("clean: known ids, whole ranks 1 … top, never a soon one", same(Rules.clean({ stands = 2.7, lights = 9, danny = 1, junk = 3, clock = -1, truck = 1, engine = "x" }), { stands = 2, lights = 5, danny = 1 }))
	-- the migration
	local old = { money = 500, sandboxUpgradesKept = true, warehouseLevelKept = true, sandboxUpgrades = { warehouse = 2, stands = 3, lights = 4, engine = 2, danny = 1, junk = 4 } }
	check("10.4 migration: a real save of the five tracks (no upgradeTreeKept): each track's level is its node's rank, nothing lost",
		same(Rules.fromSave(old), { warehouse = 2, stands = 3, lights = 4, engine = 2, danny = 1 }))
	local tree = { money = 500, sandboxUpgradesKept = true, warehouseLevelKept = true, upgradeTreeKept = true, sandboxUpgrades = { warehouse = 2, lights = 2, rare = 1, clock = 2, paint = 1 } }
	check("… a save of the tree (its flag): its nodes, cleaned", same(Rules.fromSave(tree), tree.sandboxUpgrades))
	check("… running it again on what it gave gives the same", same(Rules.fromSave({ money = 1, sandboxUpgradesKept = true, warehouseLevelKept = true, upgradeTreeKept = true, sandboxUpgrades = Rules.fromSave(old) }), Rules.fromSave(old)))
	check("no flag (before 8.1), a new player, a lock-only record: none (8.3: a real save from before 8.3 the Big Warehouse)", same(Rules.fromSave({ money = 1 }), { warehouse = 3 })
		and next(Rules.fromSave(nil)) == nil and next(Rules.fromSave({ lock = {} })) == nil and next(Rules.fromSave({ money = 1, warehouseLevelKept = true })) == nil)
	-- the mirror an older server keeps
	local rewards: { [any]: any } = { ["up:clock:1"] = true, ["book:x"] = true }
	Rules.mirror(rewards, { warehouse = 2, lights = 3, clock = 2, rare = 1, paint = 1 })
	check("mirror: the tree's own nodes as rewards' short keys (never the five tracks an older server keeps), the stale ones gone, others kept",
		rewards["up:clock:2"] == true and rewards["up:rare:1"] == true and rewards["up:paint:1"] == true and rewards["up:clock:1"] == nil
		and rewards["up:lights:3"] == nil and rewards["up:warehouse:2"] == nil and rewards["book:x"] == true)
	-- an older server wrote it again: its sandboxUpgrades the five tracks only, its rewards (and the tree's flag, an unknown key) kept
	local through = { money = 9, sandboxUpgradesKept = true, warehouseLevelKept = true, upgradeTreeKept = true, sandboxUpgrades = { warehouse = 2, lights = 3 }, rewards = rewards }
	check("… a save an older server wrote again: the tree's nodes come back from the mirror", same(Rules.fromSave(through), { warehouse = 2, lights = 3, clock = 2, rare = 1, paint = 1 }))
	check("… a mirror of a soon node or junk is nothing", next(Rules.fromSave({ money = 1, warehouseLevelKept = true, rewards = { ["up:truck:1"] = true, ["up:nope:2"] = true, ["up:clock:x"] = true } })) == nil)
	check("8.3's rewards key of the warehouse: \"warehouse:<k>\" and back", Rules.warehouseKey({ warehouse = 2 }) == "warehouse:2" and Rules.keptWarehouse({ ["warehouse:2"] = true }) == 2)
	-- the totals
	local sum = 0
	for _, id in Rules.Order do
		local def = Rules.def(id) :: Config.SandboxUpgradeDef
		if not def.soon then
			for _, price in def.prices do
				sum += price
			end
		end
	end
	check("total: every rank's price but the soon nodes'; cost(full) is the total, cost(none) 0", Rules.total() == sum and Rules.cost(Rules.full()) == sum and Rules.cost({}) == 0, Rules.total())
	local auctionOn = (Config :: any).Auction.On
	check("offered: a node the tree sells (the lights, More hall stands), never a soon one (the bigger truck, the helper slot), the auction's only while the Auction House is open",
		Rules.offered("lights") and Rules.offered("stands") and not Rules.offered("truck") and not Rules.offered("helperslot") and not Rules.offered("nope")
		and Rules.offered("auction") == (auctionOn == true))
end

if failures > 0 then
	error(`{failures} check(s) failed`)
end
print("ALL CHECKS PASSED")
