--!strict
-- 3.4: cargo capacity (Config.Cars capacity, the Cargo Rack, Economy.capacity / cargoNeed), what every job and every
-- mission needs against the cars that do them, the repair shop's time and fee (Economy.repairTime / repairFee).
-- (That every car's capacity is its body's slot count is checked by run_tests.py: Vehicles.luau is not loadable here.)

local Config = require("./Config")
local Economy = require("./Economy")
local Missions = require("./Missions")

local failed = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("  ok   " .. name)
	else
		failed += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- ── The cars and the rack ────────────────────────────────────────────────────

local rack = Economy.findUpgrade("rack")
check("the Cargo Rack is a car track of 3 levels, +1 slot each", rack ~= nil and rack.car == true and rack.maxLevel == 3 and rack.perLevel == 1)
local RACK_MAX = if rack then rack.maxLevel * rack.perLevel else 0

local biggest = 0 -- the biggest dealer car's capacity
local start = Config.Cars[1]
for _, def in Config.Cars do
	check(`{def.id}: a capacity`, type(def.capacity) == "number" and def.capacity >= 1, def.capacity)
	if not def.company then
		check(`{def.id}: a dealer car takes at least 2 pieces`, def.capacity >= 2, def.capacity)
		biggest = math.max(biggest, def.capacity)
	end
end
check("the starting van holds 4", start.id == "van" and start.capacity == 4, start.capacity)
check("the High-Roof Van and the Box Truck are the haulers (6)", (Economy.findCar("highroof") :: any).capacity == 6 and (Economy.findCar("boxtruck") :: any).capacity == 6)
check("capacity: no rack", Economy.capacity("van", {}) == 4 and Economy.capacity("van", nil) == 4)
check("capacity: rack 2", Economy.capacity("van", { rack = 2 }) == 6)
check("capacity: a rack above its max counts its max", Economy.capacity("van", { rack = 9 }) == 4 + RACK_MAX)
check("capacity: a company vehicle takes no rack", Economy.capacity("armored", { rack = 3 }) == 8)
check("capacity: an unknown car holds nothing", Economy.capacity("spaceship", {}) == 0)
check("need: carried and led pieces count", Economy.cargoNeed("carry", 5) == 5 and Economy.cargoNeed("lead", 2) == 2)
check("need: passengers and serving need no slot", Economy.cargoNeed("board", 8) == 0 and Economy.cargoNeed("serve", 6) == 0)
check("the rack's first level is cheap", (Economy.upgradeCost("rack", 0) :: number) <= 400, Economy.upgradeCost("rack", 0))

-- ── The special jobs (Config.JobTypes) ───────────────────────────────────────

for _, def in Config.JobTypes do
	local need = Economy.cargoNeed(def.load, def.items)
	if def.vehicle then
		local holds = Economy.capacity(def.vehicle, {})
		check(`job {def.id}: its {def.vehicle} holds the {need} pieces`, holds >= need, `{need} > {holds}`)
	else
		check(`job {def.id}: the starting van takes it`, need <= start.capacity, need)
	end
end

-- ── The job board's ordinary deliveries ──────────────────────────────────────

for tier = 1, #Config.Jobs.Tiers do
	local most, baseMost = 0, 0
	for _, business in Config.Jobs.Businesses do
		if table.find(business.tiers, tier) then
			local high = business.pieces[2] or business.pieces[1]
			baseMost = math.max(baseMost, high)
			most = math.max(most, high + (if (Config.Jobs.BulkChance[tier] or 0) > 0 then Config.Jobs.BulkExtra[tier][2] else 0))
		end
	end
	if tier == 1 then
		check("★: every ordinary delivery fits the starting van", most <= start.capacity, most)
	elseif tier == 2 then
		check("★★: without a bulk order every delivery fits the starting van", baseMost <= start.capacity, baseMost)
		check("★★: bulk orders are rare", (Config.Jobs.BulkChance[2] or 0) <= 0.25)
	end
	check(`{string.rep("★", tier)}: the biggest load fits the biggest car with a rack`, most <= biggest + RACK_MAX, most)
end
check("bigger loads on the dangerous jobs", Config.Jobs.BulkExtra[4][2] > Config.Jobs.BulkExtra[2][2] and Config.Jobs.BulkChance[4] > Config.Jobs.BulkChance[2])

-- ── The missions: every one, what it needs ───────────────────────────────────

local EARLY = { dispatch = true, clinic = true, market = true } -- First Shift, Code Red, Empty Shelves
local listed, lent, early = 0, 0, 0
for _, mission in Missions.List do
	local need = Economy.cargoNeed(mission.load, mission.items)
	listed += 1
	if mission.vehicle then
		lent += 1
		local holds = Economy.capacity(mission.vehicle, {})
		print(`  {mission.id} {mission.name}: {need} slots · lends the {mission.vehicle} ({holds})`)
		check(`{mission.id}: the lent {mission.vehicle} holds it`, holds >= need, `{need} > {holds}`)
	else
		local rackLevels = math.max(0, need - start.capacity)
		local how = if rackLevels == 0 then "" elseif rackLevels <= RACK_MAX then ` · the Old Van with rack {rackLevels}` else ` · a {biggest}-slot car with rack {need - biggest}`
		print(`  {mission.id} {mission.name}: {need} slots{how}`)
		check(`{mission.id}: no mission needs more than the biggest car with a full rack`, need <= biggest + RACK_MAX, need)
		if EARLY[mission.campaign] then
			early += 1
			check(`{mission.id}: an early mission fits the starting van with at most two rack levels`, need <= start.capacity + 2, need)
		end
	end
end
check("all 110 missions listed", listed == 110, listed)
check("some missions lend a vehicle, the early ones mostly do not", lent > 0 and early >= 20, `{lent} lent, {early} early`)

-- ── The repair shop ──────────────────────────────────────────────────────────

check("repair: a scratch takes the shortest time", Economy.repairTime(0) == Config.Repair.MinSeconds)
check("repair: a wreck takes the full minute", Economy.repairTime(1) == Config.Repair.Seconds and Config.Repair.Seconds == 60)
check("repair: half the damage, in between", Economy.repairTime(0.5) > Config.Repair.MinSeconds and Economy.repairTime(0.5) < Config.Repair.Seconds)
check("repair: the fee grows with the damage", Economy.repairFee(0.1) < Economy.repairFee(0.5) and Economy.repairFee(0.5) < Economy.repairFee(1))
check("repair: a small fee (round dollars)", Economy.repairFee(1) == Config.Repair.FeeFull and Economy.repairFee(0.37) % 5 == 0)
check("repair: out of range is clamped", Economy.repairTime(3) == Config.Repair.Seconds and Economy.repairFee(-1) == Config.Repair.FeeMin)
check("a wreck comes back damaged", Config.Repair.WreckedHealth > 0 and Config.Repair.WreckedHealth < 0.5)

-- ── The garages ──────────────────────────────────────────────────────────────

check("the depot holds only the starting van", Config.Estate.BaseCarSlots == 1)
local firstGarage: Config.EstateDef? = nil
for _, def in Config.Estate.Properties do
	if def.kind == "garage" and (firstGarage == nil or (def.level or 1) < ((firstGarage :: Config.EstateDef).level or 1)) then
		firstGarage = def
	end
end
local courier = Economy.findCar("courier")
check("the Courier Van's level opens a garage for it", firstGarage ~= nil and courier ~= nil and (firstGarage.level or 1) <= (courier.level or 1))

print(if failed == 0 then "ALL CHECKS PASSED" else `{failed} CHECK(S) FAILED`)
