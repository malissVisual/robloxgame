--!strict
-- 3.4: cargo capacity (Config.Cars capacity, Economy.capacity / cargoNeed), what every job and every mission needs
-- against the cars that do them, the repair shop's time and fee (Economy.repairTime / repairFee).
-- 3.5: the stages (Config.Cars stages, Economy.stageOf / stageCapacity / legacyStage …) instead of the Cargo Rack.
-- 4.0: the Old Van has four stages (Rusty 2 → Patched 2 → Work 3 → Long Cargo 4), the Freight Truck (12) is the biggest.
-- 7.x, one car (Config.CompanyVan): the ZDC Van (4 slots, one stage) is the only car a player has; every special job and
-- every mission goes in it and carries at most its four slots; no job or mission lends a vehicle. The other cars are
-- bodies the world still builds (Config.AmbientCars): their stages stay sound for the traffic's looks, and Economy's
-- maths on them (the stages, the 3.4 saves' legacyStage) is checked as before.
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

-- ── The one car: the ZDC Van ─────────────────────────────────────────────────

check("the Cargo Rack is gone (3.5: stages)", Economy.findUpgrade("rack") == nil)
local start = Config.Cars[1]
local VAN = Config.CompanyVan.Car
local room = Economy.maxCapacity(VAN) -- what the van holds: every job and mission fits it
check("the first car is the ZDC Van, every courier's from level 1, never sold", start.id == VAN and start.id == "zdcvan" and start.starter == true
	and start.price == 0 and (start.level or 1) == 1 and start.mission == nil)
check("the ZDC Van holds 4 (one stage)", room == 4 and Economy.stageCapacity(VAN, 0) == 4 and Economy.maxStage(VAN) == 0, room)
check("a Roof Rack adds 2 light slots on it", Economy.capacity(VAN, {}, { roofrack = true }, "parcel") == 6
	and Economy.capacity(VAN, {}, { roofrack = true }, "ammo") == 4)
for _, def in Config.Cars do
	check(`{def.id}: a capacity`, type(def.capacity) == "number" and def.capacity >= 1, def.capacity)
	check(`{def.id}: a role`, type(def.role) == "string" and #(def.role :: string) > 3)
	if def.bike then
		-- 5.1: a bike has no stages (its bike gear adds the room) and holds what its body has: a rack 1, a box 4.
		check(`{def.id}: a bike has no stages`, def.stages == nil and Economy.maxStage(def.id) == 0)
		check(`{def.id}: a bike holds 1 – 4 light pieces of its own`, def.capacity >= 1 and def.capacity <= 4, def.capacity)
	elseif def.sandboxOnly then
		-- 8.0 SANDBOX: the ZDC Sprinter, the sandbox's van (tests/sprinter_test.luau): no stages, its own bay
		check(`{def.id}: the sandbox's van, no stages`, def.stages == nil and Economy.maxStage(def.id) == 0 and not def.company)
	else
		check(`{def.id}: the only car of Config.Cars is the van`, def.id == VAN and not def.company)
	end
end

-- ── The bodies nobody owns (Config.AmbientCars): their stages stay sound for the traffic ─────────────────────────

local old = Economy.findCar("van")
for _, def in Config.AmbientCars do
	check(`{def.id}: a body of the world (ambient), no player's car`, def.ambient == true and not Economy.isPlayerCar(def.id))
	local stages = def.stages
	if def.company then
		check(`{def.id}: a company vehicle has no stages`, stages == nil and Economy.maxStage(def.id) == 0)
		continue
	end
	if not stages then
		continue
	end
	local zero = stages[1]
	check(`{def.id}: stage 0 is the car as sold`, zero.price == 0 and zero.look == nil and zero.capacity == def.capacity and zero.level == nil)
	for n = 2, #stages do
		local stage, before = stages[n], stages[n - 1]
		check(`{def.id}: {stage.name} has a look`, stage.price > 0 and type(stage.look) == "string" and #stage.adds > 0)
		check(`{def.id}: {stage.name} holds at least as much as before`, stage.capacity >= before.capacity)
	end
end
check("the old van's body: Rusty Van 2 → Patched Van 2 → Work Van 3 → Long Cargo Van 4 (the traffic's looks)", old ~= nil and old.stages ~= nil
	and #(old.stages :: { Config.StageDef }) == 4 and (old.stages :: { Config.StageDef })[4].capacity == 4)

-- Economy: the stage of a car's levels, its capacity, its stats, the names (on the old van's body).
local van = if old and old.stages then old.stages else {}
check("capacity: stage 0", Economy.capacity("van", {}) == 2 and Economy.capacity("van", nil) == 2)
check("capacity: stages 1, 2 and 3", Economy.capacity("van", { stage = 1 }) == 2 and Economy.capacity("van", { stage = 2 }) == 3
	and Economy.capacity("van", { stage = 3 }) == 4)
check("capacity: a stage above the last counts the last", Economy.capacity("van", { stage = 9 }) == 4 and Economy.stageOf("van", { stage = 9 }) == 3)
check("capacity: a negative stage is stage 0", Economy.stageOf("van", { stage = -3 }) == 0)
check("capacity: a company vehicle has no stages", Economy.capacity("armored", { stage = 3 }) == 8)
check("capacity: an unknown car holds nothing", Economy.capacity("spaceship", {}) == 0)
check("the next stage's price", #van == 4 and Economy.stageCost("van", 0) == van[2].price and Economy.stageCost("van", 3) == nil)
check("the stage's health, speed and accel", old ~= nil and #van == 4 and Economy.carStats("van", { stage = 3 }).health == (old :: Config.CarDef).health + (van[4].health or 0)
	and Economy.carStats("van", { stage = 3 }).maxSpeed == (old :: Config.CarDef).maxSpeed + (van[4].speed or 0))
check("the car's title at a stage", Economy.carTitle("van", { stage = 2 }) == "Old Van · Work Van" and Economy.carTitle(VAN, {}) == "ZDC Van")
check("advice: the next stage that holds it", string.find(Economy.roomAdvice("van", 0, 4), "Long Cargo Van", 1, true) ~= nil)
check("advice: no bigger car any more (7.x: the Roof Rack's light slots)", string.find(Economy.roomAdvice(VAN, 0, 6), "Roof Rack", 1, true) ~= nil
	and string.find(Economy.roomAdvice(VAN, 0, 6), "Box Truck", 1, true) == nil)
check("need: carried and led pieces count", Economy.cargoNeed("carry", 5) == 5 and Economy.cargoNeed("lead", 2) == 2)
check("need: passengers and serving need no slot", Economy.cargoNeed("board", 8) == 0 and Economy.cargoNeed("serve", 6) == 0)

-- A 3.4 save's car becomes the first stage that holds the slots it had (its 3.4 capacity + its Cargo Rack); when none
-- holds that many, the first stage with the car's most room (0 when no stage adds any).
check("Old Van, no rack (4 in 3.4): the Long Cargo Van", Economy.legacyStage("van", 0) == 3)
check("Box Truck (6): rack 0 → stage 0, +1 → stage 1, +2 and +3 → stage 2", Economy.legacyStage("boxtruck", 0) == 0
	and Economy.legacyStage("boxtruck", 1) == 1 and Economy.legacyStage("boxtruck", 2) == 2 and Economy.legacyStage("boxtruck", 3) == 2)
check("Rally Van: no stage adds room, stays at stage 0", Economy.legacyStage("rallyvan", 0) == 0 and Economy.legacyStage("rallyvan", 3) == 0)
check("a company vehicle: nothing", Economy.legacyStage("ambulance", 2) == 0)
check("the ZDC Van: no stage to move to", Economy.legacyStage(VAN, 2) == 0)

-- ── The special jobs (Config.JobTypes) ───────────────────────────────────────

for _, def in Config.JobTypes do
	local need = Economy.cargoNeed(def.load, def.items)
	check(`job {def.id}: lends no vehicle (7.x: it goes in your ZDC Van)`, def.vehicle == nil, def.vehicle)
	check(`job {def.id}: the ZDC Van takes its {need} pieces`, need <= room, need)
	check(`job {def.id}: no pallets, no horses (7.x)`, def.load ~= "pallet" and def.load ~= "lead", def.load)
end

-- ── The job board's ordinary deliveries ──────────────────────────────────────

check("★ deliveries are capped at EasyMaxPieces (2)", Config.Jobs.EasyMaxPieces == 2)
for tier = 1, #Config.Jobs.Tiers do
	local most = 0
	for _, business in Config.Jobs.Businesses do
		if table.find(business.tiers, tier) then
			local high = business.pieces[2] or business.pieces[1]
			if tier == 1 then
				high = math.min(high, Config.Jobs.EasyMaxPieces)
			end
			most = math.max(most, high + (if (Config.Jobs.BulkChance[tier] or 0) > 0 then Config.Jobs.BulkExtra[tier][2] else 0))
		end
	end
	-- (server/Jobs.luau ordinaryOffer caps every car delivery at the van's slots: a bulk order over it brings four)
	check(`{string.rep("★", tier)}: the biggest load is a full van at most once capped`, math.min(most, room) <= room and most <= room + 2, most)
end
check("★★: bulk orders are rare", (Config.Jobs.BulkChance[2] or 0) <= 0.25)

-- ── The missions: every one, what it needs ───────────────────────────────────

local listed, lent = 0, 0
for _, mission in Missions.List do
	local need = Economy.cargoNeed(mission.load, mission.items)
	listed += 1
	if mission.vehicle then
		lent += 1
	end
	print(`  {mission.id} {mission.name} (level {mission.level or 1}): {need} slots`)
	check(`{mission.id}: fits the ZDC Van (7.x: its four slots at most)`, need <= room, need)
	check(`{mission.id}: no horses led any more (7.x: a horse does not fit a van)`, mission.load ~= "lead" and mission.itemKind ~= "horse")
end
check(`all {#Missions.List} missions listed (6.8: eleven chapters of six)`, listed == #Missions.List and listed == 66, listed)
check("no mission lends a vehicle (7.x: your ZDC Van does them all)", lent == 0, lent)

-- ── The repair shop ──────────────────────────────────────────────────────────

check("repair: a scratch takes the shortest time", Economy.repairTime(0) == Config.Repair.MinSeconds)
check("repair: a wreck takes the full minute", Economy.repairTime(1) == Config.Repair.Seconds and Config.Repair.Seconds == 60)
check("repair: half the damage, in between", Economy.repairTime(0.5) > Config.Repair.MinSeconds and Economy.repairTime(0.5) < Config.Repair.Seconds)
check("repair: the fee grows with the damage", Economy.repairFee(0.1) < Economy.repairFee(0.5) and Economy.repairFee(0.5) < Economy.repairFee(1))
check("repair: a small fee (round dollars)", Economy.repairFee(1) == Config.Repair.FeeFull and Economy.repairFee(0.37) % 5 == 0)
check("repair: out of range is clamped", Economy.repairTime(3) == Config.Repair.Seconds and Economy.repairFee(-1) == Config.Repair.FeeMin)
check("a wreck comes back damaged", Config.Repair.WreckedHealth > 0 and Config.Repair.WreckedHealth < 0.5)

-- ── The garages ──────────────────────────────────────────────────────────────

check("the depot holds the starting van (7.x: the ZDC Van, the one car)", Config.Estate.BaseCarSlots == 1)

print(if failed == 0 then "ALL CHECKS PASSED" else `{failed} CHECK(S) FAILED`)
