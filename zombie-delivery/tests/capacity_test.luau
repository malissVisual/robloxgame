--!strict
-- 3.4: cargo capacity (Config.Cars capacity, Economy.capacity / cargoNeed), what every job and every mission needs
-- against the cars that do them, the repair shop's time and fee (Economy.repairTime / repairFee).
-- 3.5: the stages (Config.Cars stages, Economy.stageOf / stageCapacity / legacyStage …) instead of the Cargo Rack:
-- the Old Van grows 2 → 3 → 4 and no further, the Box Truck is the only way to 6 and more, every job and mission fits
-- a car (and a stage) you can have at its level, the early campaigns the Old Van. 4.0: the Old Van has four stages
-- (Rusty 2 → Patched 2 → Work 3 → Long Cargo 4), the Freight Truck (12) is the biggest.
-- (That every car's capacity is its body's slot count, and every stage's its look's, is checked by run_tests.py:
-- Vehicles.luau is not loadable here.)

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

-- ── The cars and their stages ────────────────────────────────────────────────

check("the Cargo Rack is gone (3.5: stages)", Economy.findUpgrade("rack") == nil)
local start = Config.Cars[1]
local biggest = 0 -- the most any dealer car holds (at its last stage)
local biggestId = ""
for _, def in Config.Cars do
	check(`{def.id}: a capacity`, type(def.capacity) == "number" and def.capacity >= 1, def.capacity)
	local stages = def.stages
	if def.company then
		check(`{def.id}: a company vehicle has no stages`, stages == nil and Economy.maxStage(def.id) == 0)
		continue
	end
	check(`{def.id}: a role`, type(def.role) == "string" and #(def.role :: string) > 3)
	if def.bike then
		-- 5.1: a bike has no stages (its bike gear adds the room) and holds what its body has: a rack 1, a box 4.
		check(`{def.id}: a bike has no stages`, stages == nil and Economy.maxStage(def.id) == 0)
		check(`{def.id}: a bike holds 1 – 4 light pieces of its own`, def.capacity >= 1 and def.capacity <= 4, def.capacity)
		continue
	end
	local most = if def.id == "van" then 4 else 3 -- 4.0: the Old Van has the longer way up
	check(`{def.id}: stages, at most {most - 1} to buy`, stages ~= nil and #stages >= 1 and #stages <= most, if stages then #stages else nil)
	if not stages then
		continue
	end
	local zero = stages[1]
	check(`{def.id}: stage 0 is the car as sold`, zero.price == 0 and zero.look == nil and zero.capacity == def.capacity and zero.level == nil)
	for n = 2, #stages do
		local stage, before = stages[n], stages[n - 1]
		check(`{def.id}: {stage.name} costs something and has a look`, stage.price > 0 and type(stage.look) == "string" and #stage.adds > 0)
		check(`{def.id}: {stage.name} holds at least as much as before`, stage.capacity >= before.capacity)
		check(`{def.id}: {stage.name} opens at or after the car`, (stage.level or 1) >= (def.level or 1) and (stage.level or 1) >= (before.level or 1))
		-- (4.0: the Old Van's stages rebuild a slow van: up to a third more speed and accel over its own.)
		local speedMax = if def.id == "van" then def.maxSpeed / 3 else 4
		check(`{def.id}: {stage.name}'s tweaks are small`, math.abs(stage.speed or 0) <= speedMax and math.abs(stage.accel or 0) <= def.accel
			and (stage.health or 0) <= 0.25 * def.health)
	end
	check(`{def.id}: a dealer car holds at least 2 at its last stage`, Economy.maxCapacity(def.id) >= 2, Economy.maxCapacity(def.id))
	if Economy.maxCapacity(def.id) > biggest then
		biggest, biggestId = Economy.maxCapacity(def.id), def.id
	end
end

-- The Old Van: 2 → 2 → 3 → 4 (4.0: the Patched Van first), and 4 is where a van ends ("6 needs a bigger vehicle").
local van = start.stages or {}
-- 5.0: you start on foot; the Old Van is the first vehicle you buy (level 4, $1,800).
check("the first vehicle is the Old Van, bought at level 4", start.id == "van" and start.price == 1800 and start.level == 4)
check("the Old Van: Rusty Van 2 → Patched Van 2 → Work Van 3 → Long Cargo Van 4", #van == 4 and van[1].name == "Rusty Van" and van[1].capacity == 2
	and van[2].name == "Patched Van" and van[2].capacity == 2 and van[3].name == "Work Van" and van[3].capacity == 3
	and van[4].name == "Long Cargo Van" and van[4].capacity == 4)
check("the Patched Van and the Work Van are cheap and early (5.0: levels 4 and 5)", #van == 4 and van[2].price <= 300 and (van[2].level or 1) <= 4
	and van[3].price <= 800 and (van[3].level or 1) <= 5)
check("the Freight Truck is the biggest (12), the Box Truck the big one before it (8)", biggestId == "freight" and biggest == 12
	and Economy.maxCapacity("boxtruck") == 8 and Economy.stageCapacity("boxtruck", 0) == 6, `{biggestId} {biggest}`)
for _, def in Config.Cars do
	if not def.company and def.id ~= "boxtruck" and def.id ~= "freight" then
		check(`{def.id}: below 6 even at its last stage (6+ needs the Box Truck)`, Economy.maxCapacity(def.id) <= 5, Economy.maxCapacity(def.id))
	end
end
check("the High-Roof Van is the in-between (4 → 5)", Economy.stageCapacity("highroof", 0) == 4 and Economy.maxCapacity("highroof") == 5)
check("the Muscle Car takes 2 – 3 (6.7: 1 – 2 before)", Economy.stageCapacity("muscle", 0) == 2 and Economy.maxCapacity("muscle") == 3)
check("the Rally Van stays at 2", Economy.maxCapacity("rallyvan") == 2)

-- Economy: the stage of a car's levels, its capacity, its stats, the names.
check("capacity: stage 0", Economy.capacity("van", {}) == 2 and Economy.capacity("van", nil) == 2)
check("capacity: stages 1, 2 and 3", Economy.capacity("van", { stage = 1 }) == 2 and Economy.capacity("van", { stage = 2 }) == 3
	and Economy.capacity("van", { stage = 3 }) == 4)
check("capacity: a stage above the last counts the last", Economy.capacity("van", { stage = 9 }) == 4 and Economy.stageOf("van", { stage = 9 }) == 3)
check("capacity: a negative stage is stage 0", Economy.stageOf("van", { stage = -3 }) == 0)
check("capacity: a company vehicle has no stages", Economy.capacity("armored", { stage = 3 }) == 8)
check("capacity: an unknown car holds nothing", Economy.capacity("spaceship", {}) == 0)
check("the next stage's price", Economy.stageCost("van", 0) == van[2].price and Economy.stageCost("van", 3) == nil)
check("the stage's health, speed and accel", Economy.carStats("van", { stage = 3 }).health == start.health + (van[4].health or 0)
	and Economy.carStats("van", { stage = 3 }).maxSpeed == start.maxSpeed + (van[4].speed or 0)
	and Economy.carStats("van", { stage = 3 }).accel == start.accel + (van[4].accel or 0))
check("the stage and the upgrades together", Economy.carStats("van", { stage = 1, armor = 2 }).health == math.floor((start.health + (van[2].health or 0)) * 1.3))
check("the car's title at a stage", Economy.carTitle("van", { stage = 2 }) == "Old Van · Work Van" and Economy.carTitle("courier", {}) == "Courier Van")
check("advice: the next stage that holds it", string.find(Economy.roomAdvice("van", 0, 4), "Long Cargo Van", 1, true) ~= nil
	and string.find(Economy.roomAdvice("van", 0, 3), "Work Van", 1, true) ~= nil)
check("advice: a bigger vehicle beyond the last stage", string.find(Economy.roomAdvice("van", 3, 6), "Box Truck", 1, true) ~= nil
	and string.find(Economy.roomAdvice("van", 3, 6), "High-Roof", 1, true) == nil)
check("need: carried and led pieces count", Economy.cargoNeed("carry", 5) == 5 and Economy.cargoNeed("lead", 2) == 2)
check("need: passengers and serving need no slot", Economy.cargoNeed("board", 8) == 0 and Economy.cargoNeed("serve", 6) == 0)

-- A 3.4 save's car becomes the first stage that holds the slots it had (its 3.4 capacity + its Cargo Rack); when none
-- holds that many, the first stage with the car's most room (0 when no stage adds any).
check("Old Van, no rack (4 in 3.4): the Long Cargo Van", Economy.legacyStage("van", 0) == 3)
check("Old Van with a rack: the Long Cargo Van (the most a van holds)", Economy.legacyStage("van", 1) == 3 and Economy.legacyStage("van", 3) == 3)
check("Box Truck (6): rack 0 → stage 0, +1 → stage 1, +2 and +3 → stage 2", Economy.legacyStage("boxtruck", 0) == 0
	and Economy.legacyStage("boxtruck", 1) == 1 and Economy.legacyStage("boxtruck", 2) == 2 and Economy.legacyStage("boxtruck", 3) == 2)
check("Muscle Car (2) and Armored Van (4): the stage that holds it (6.7: the Muscle Car holds 2 at stage 0)", Economy.legacyStage("muscle", 0) == 0 and Economy.legacyStage("muscle", 1) == 1 and Economy.legacyStage("armorvan", 0) == 1)
check("High-Roof, Courier, Pickup: their last stage (the most they hold)", Economy.legacyStage("highroof", 0) == 1
	and Economy.legacyStage("courier", 2) == 1 and Economy.legacyStage("pickup", 1) == 1)
check("Rally Van: no stage adds room, stays at stage 0", Economy.legacyStage("rallyvan", 0) == 0 and Economy.legacyStage("rallyvan", 3) == 0)
check("a company vehicle: nothing", Economy.legacyStage("ambulance", 2) == 0)
local legacyOk = true
for _, def in Config.Cars do
	for rack = 0, 3 do
		local stage = Economy.legacyStage(def.id, rack)
		local capacity = Economy.stageCapacity(def.id, stage)
		if stage < 0 or stage > Economy.maxStage(def.id)
			or (capacity < Economy.stageCapacity(def.id, 0) + rack and capacity < Economy.maxCapacity(def.id)) then
			legacyOk = false
		end
	end
end
check("every car, rack 0 – 3: one of its stages, the rack on top of stage 0 or its most room", legacyOk)

-- The level a load of `need` pieces can first be carried at: a dealer car at a stage that holds it (the later of the
-- car's level and the stage's), nil when nothing holds it.
local function levelFor(need: number): number?
	local best: number? = nil
	for _, def in Config.Cars do
		if def.company then
			continue
		end
		for stage = 0, Economy.maxStage(def.id) do
			local stageDef = Economy.stageDef(def.id, stage)
			if Economy.stageCapacity(def.id, stage) >= need then
				local level = math.max(def.level or 1, if stageDef then stageDef.level or 1 else 1)
				best = if best then math.min(best, level) else level
			end
		end
	end
	return best
end
-- The level the Old Van holds `need` at (nil: never).
local function vanLevelFor(need: number): number?
	for stage = 0, Economy.maxStage("van") do
		if Economy.stageCapacity("van", stage) >= need then
			local stageDef = Economy.stageDef("van", stage)
			return if stageDef then stageDef.level or 1 else 1
		end
	end
	return nil
end

-- ── The special jobs (Config.JobTypes) ───────────────────────────────────────

for _, def in Config.JobTypes do
	local need = Economy.cargoNeed(def.load, def.items)
	if def.vehicle then
		local holds = Economy.capacity(def.vehicle, {})
		check(`job {def.id}: its {def.vehicle} holds the {need} pieces`, holds >= need, `{need} > {holds}`)
	else
		check(`job {def.id}: the Rusty Van takes it`, need <= start.capacity, need)
	end
end

-- ── The job board's ordinary deliveries ──────────────────────────────────────

check("★ deliveries are capped at the Rusty Van's slots", Config.Jobs.EasyMaxPieces == start.capacity)
for tier = 1, #Config.Jobs.Tiers do
	local most, baseMost = 0, 0
	for _, business in Config.Jobs.Businesses do
		if table.find(business.tiers, tier) then
			local high = business.pieces[2] or business.pieces[1]
			if tier == 1 then
				high = math.min(high, Config.Jobs.EasyMaxPieces)
			end
			baseMost = math.max(baseMost, high)
			most = math.max(most, high + (if (Config.Jobs.BulkChance[tier] or 0) > 0 then Config.Jobs.BulkExtra[tier][2] else 0))
		end
	end
	if tier == 1 then
		check("★: every ordinary delivery fits the Rusty Van (stage 0)", most <= start.capacity, most)
	elseif tier == 2 then
		check("★★: without a bulk order every delivery fits the Work Van", baseMost <= Economy.stageCapacity("van", 2), baseMost)
		check("★★: even a bulk order fits the Long Cargo Van", most <= Economy.maxCapacity("van"), most)
		check("★★: bulk orders are rare", (Config.Jobs.BulkChance[2] or 0) <= 0.25)
	end
	check(`{string.rep("★", tier)}: the biggest load fits the biggest car at its last stage`, most <= biggest, most)
	check(`{string.rep("★", tier)}: a car for the usual load at the tier's level`, (levelFor(baseMost) or 99) <= Config.Jobs.Tiers[tier].level, baseMost)
end
check("bigger loads on the dangerous jobs", Config.Jobs.BulkExtra[4][2] > Config.Jobs.BulkExtra[2][2] and Config.Jobs.BulkChance[4] > Config.Jobs.BulkChance[2])

-- ── The missions: every one, what it needs ───────────────────────────────────

local EARLY = { dispatch = true, clinic = true, market = true } -- First Shift, Code Red, Empty Shelves
local listed, lent, early, big = 0, 0, 0, 0
for _, mission in Missions.List do
	local need = Economy.cargoNeed(mission.load, mission.items)
	local level = mission.level or 1
	listed += 1
	if mission.vehicle then
		lent += 1
		local holds = Economy.capacity(mission.vehicle, {})
		print(`  {mission.id} {mission.name}: {need} slots · lends the {mission.vehicle} ({holds})`)
		check(`{mission.id}: the lent {mission.vehicle} holds it`, holds >= need, `{need} > {holds}`)
		continue
	end
	local from = levelFor(need)
	print(`  {mission.id} {mission.name} (level {level}): {need} slots · a car for it from level {from or "never"}`)
	check(`{mission.id}: no mission needs more than the Box Truck's last stage`, need <= Economy.maxCapacity("boxtruck"), need)
	check(`{mission.id}: a car (and a stage) that holds it opens by the mission's level`, from ~= nil and (from :: number) <= level, from)
	if EARLY[mission.campaign] then
		early += 1
		local vanFrom = vanLevelFor(need)
		check(`{mission.id}: an early mission fits the Old Van by its level`, vanFrom ~= nil and (vanFrom :: number) <= level, vanFrom)
	end
	if mission.campaign == "dispatch" then
		check(`{mission.id}: First Shift fits the Rusty Van, or the Work Van`, need <= Economy.stageCapacity("van", 2) and (level > 1 or need <= start.capacity), need)
	elseif mission.campaign == "clinic" or mission.campaign == "market" or mission.campaign == "duo" then
		check(`{mission.id}: at most the Long Cargo Van`, need <= Economy.stageCapacity("van", 3), need)
	end
	if need >= 5 then
		big += 1
		-- 5 and more is a big load (a Tall Hauler or the Box Truck): the story says so.
		check(`{mission.id}: a big load says so`, string.find(string.lower(mission.description), "load", 1, true) ~= nil, mission.description)
	end
end
check(`all {#Missions.List} missions listed (6.8: eleven chapters of six)`, listed == #Missions.List and listed == 66, listed)
check("some missions lend a vehicle, the early ones mostly do not", lent > 0 and early >= 12, `{lent} lent, {early} early`)
check("a few big loads later on (the Box Truck's missions)", big >= 3 and big <= 8, big)

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
check("a stage needs no garage: the Old Van grows in its depot slot", (van[2] and van[2].level or 1) <= (start.level or 1))

print(if failed == 0 then "ALL CHECKS PASSED" else `{failed} CHECK(S) FAILED`)
