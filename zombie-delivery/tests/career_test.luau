-- Logic test of 4.6, the career and the gear: shared/Career.luau (the road built from Config, the rewards, what is
-- pending), Config.Levels.Rewards, Config.Gear and the gear API in shared/Economy.luau (gearSlots, gearFits,
-- installedGear, the Roof Rack's light slot in Economy.capacity, the move of a 4.0 – 4.5 save's Hand Trolley).
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local Levels = require("./Levels")
local Career = require("./Career")
local Freight = require("./Freight")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function has(unlocks: { Career.Unlock }, kind: string, id: string): boolean
	for _, unlock in unlocks do
		if unlock.kind == kind and unlock.id == id then
			return true
		end
	end
	return false
end

-- ── The road ────────────────────────────────────────────────────────────────

local road = Career.road()
local max = Config.Levels.MaxLevel
check("the road has every level, 1 first", #road == max and road[1].level == 1 and road[max].level == max, #road)
local rising = true
for n = 2, #road do
	rising = rising and road[n].xp > road[n - 1].xp and road[n].level == n
end
check("the XP rises level by level (Levels.xpFor)", rising and road[1].xp == 0 and road[5].xp == Levels.xpFor(5))
check("the XP curve is untouched (575 × 1.2^n, 34 037 at 15)", Config.Levels.XpBase == 575 and Config.Levels.XpGrowth == 1.2 and Levels.xpFor(15) == 34037, Levels.xpFor(15))
for _, step in road do
	if step.level >= 2 then
		check(`level {step.level} unlocks something`, #step.unlocks > 0)
	end
	check(`level {step.level}: its rank`, step.rank == Levels.rank(step.level))
end
check("a new rank is marked where it starts", road[1].newRank and road[5].newRank and not road[7].newRank and road[8].newRank)
-- 5.0: you start on foot; the Old Van, the ★ car jobs and First Shift come at level 4.
check("level 1: the Pistol (on foot: no car, no car jobs)", has(road[1].unlocks, "gun", "pistol") and not has(road[1].unlocks, "car", "van")
	and not has(road[1].unlocks, "tier", "1"))
check("level 2: the Rented Lockup", has(road[2].unlocks, "garage", "garage_rented"))
-- 5.7: the Hand Trolley (gear for a car, level 3) shows on the road with the first car, at level 4.
check("level 4: the Hand Trolley (car gear: not before the first car)", has(road[4].unlocks, "gear", "trolley") and not has(road[3].unlocks, "gear", "trolley")
	and Career.gearLevel((Economy.findGear("trolley") :: any)) == 4)
check("bike gear keeps its level on the road", has(road[2].unlocks, "gear", "basket"))
-- 5.7: the levels before a car give kit, not car items; a kit owned already pays its price instead.
for level = 2, 4 do
	local reward = Career.reward(level) :: Config.LevelReward
	for id in reward.items or {} do
		check(`level {level}: no car items before a car ({id})`, id ~= "repair" and id ~= "nitro" and id ~= "mine" and id ~= "jerrycan")
	end
end
check("level 3 gives the Canvas Tote (6.6: no backpack), level 4 the Running Shoes", (Career.kitOf(Career.reward(3)) :: any).id == "tote" and (Career.kitOf(Career.reward(4)) :: any).id == "shoes")
check("the kit in words", string.find(table.concat(Career.rewardParts(Career.reward(3)), ", "), "the Canvas Tote", 1, true) ~= nil)
local ownedKit: { [string]: boolean } = {}
check("a kit reward: yours, nothing to pay", Career.grantKit(Career.reward(3), ownedKit) == 0 and ownedKit.tote == true)
check("6.6: no level gives a backpack", (function()
	for level = 2, 20 do
		local reward = Career.reward(level)
		if reward and (reward.kit == "backpack" or reward.kit == "bigpack") then
			return false
		end
	end
	return true
end)())
check("owned already: its price instead", Career.grantKit(Career.reward(3), ownedKit) == (Career.kitOf(Career.reward(3)) :: any).price)
check("no kit, nothing", Career.grantKit(Career.reward(2), ownedKit) == 0 and Career.grantKit(nil, ownedKit) == 0)
check("level 4: the Old Van, the Patched Van stage, ★ jobs, First Shift, the Ratchet Straps", has(road[4].unlocks, "car", "van") and has(road[4].unlocks, "stage", "van:1")
	and has(road[4].unlocks, "tier", "1") and has(road[4].unlocks, "campaign", "dispatch") and has(road[4].unlocks, "gear", "straps"))
check("level 5: the Courier Van, the High-Roof Van, ★★ jobs", has(road[5].unlocks, "car", "courier") and has(road[5].unlocks, "car", "highroof") and has(road[5].unlocks, "tier", "2"))
check("level 6: the Pickup, the Long Cargo Van stage, ★★★ jobs", has(road[6].unlocks, "car", "pickup") and has(road[6].unlocks, "stage", "van:3") and has(road[6].unlocks, "tier", "3"))
check("level 5: the Cooler Box, the Roof Machine Gun, the Cash Transport", has(road[5].unlocks, "gear", "cooler") and has(road[5].unlocks, "cargun", "roofmg")
	and has(road[5].unlocks, "job", "cashrun"))
check("level 7: the Roof Rack, Birch Cottage, the Box Truck", has(road[7].unlocks, "gear", "roofrack") and has(road[7].unlocks, "estate", "birch")
	and has(road[7].unlocks, "car", "boxtruck"))
check("level 9: ★★★★ jobs", has(road[9].unlocks, "tier", "4"))
check("level 15: the Hilltop Mansion and the Penthouse", has(road[15].unlocks, "estate", "hilltop") and has(road[15].unlocks, "estate", "office_penthouse"))
check("an employer's job says where", (function()
	for _, unlock in road[4].unlocks do -- (5.0: a company vehicle from level 4)
		if unlock.id == "schoolrun" then
			return string.find(unlock.name, "(", 1, true) ~= nil
		end
	end
	return false
end)())
check("no mission is listed as a job", (function()
	for _, step in road do
		for _, unlock in step.unlocks do
			if unlock.kind == "job" and Economy.findJobType(unlock.id) == nil then
				return false
			end
		end
	end
	return true
end)())
-- Everything with a level is somewhere on the road, exactly once.
local seen: { [string]: number } = {}
for _, step in road do
	for _, unlock in step.unlocks do
		local key = `{unlock.kind}:{unlock.id}`
		seen[key] = (seen[key] or 0) + 1
	end
end
local everywhere = true
for _, def in Config.Cars do
	if not def.company and seen[`{if def.bike then "bike" else "car"}:{def.id}`] ~= 1 then -- (5.1: a bike's kind is "bike")
		everywhere = false
		print(`  missing car {def.id}`)
	end
end
for _, gear in Config.Gear do
	if seen[`gear:{gear.id}`] ~= 1 then
		everywhere = false
		print(`  missing gear {gear.id}`)
	end
end
for _, def in Config.CarGuns do
	if seen[`cargun:{def.id}`] ~= 1 then
		everywhere = false
	end
end
for _, def in Config.Estate.Properties do
	if seen[`{if def.kind == "garage" then "garage" else "estate"}:{def.id}`] ~= 1 then
		everywhere = false
		print(`  missing estate {def.id}`)
	end
end
check("every car, gear, car gun and property is on the road once", everywhere)
check("the order inside a level: the board first, the real estate last", road[4].unlocks[1].kind == "tier" and road[15].unlocks[#road[15].unlocks].kind == "estate")

-- ── The rewards ─────────────────────────────────────────────────────────────

check("level 1 has no reward", Career.reward(1) == nil)
local money, previous, sane = 0, 0, true
for level = 2, max do
	local reward = Career.reward(level)
	check(`level {level} has a reward`, reward ~= nil)
	if reward then
		local amount = reward.money or 0
		sane = sane and amount >= previous
		previous = amount
		money += amount
		for id, count in reward.items or {} do
			local def = Economy.findItem(id)
			check(`level {level}: {id} is an item, a sane count`, def ~= nil and count >= 1 and count <= (if def then def.max else 0))
		end
		if reward.paint then
			local paint = Economy.findPaint(reward.paint)
			check(`level {level}: {reward.paint} is a career paint, never sold`, paint ~= nil and paint.exclusive == "career" and paint.price == 0)
		end
	end
end
check("the money grows from $500 to $15,000", sane and (Career.reward(2) :: any).money == 500 and (Career.reward(max) :: any).money == 15000)
print(`  all the rewards together: {Career.money(money)}`)
for _, level in { 5, 10, 15 } do
	local reward = Career.reward(level) :: any
	check(`level {level}: a paint or a title`, reward.paint ~= nil or reward.title ~= nil)
end
check("the rewards in words", table.concat(Career.rewardParts(Career.reward(2)), ", ") == "$500, 2 Medkits"
	and table.concat(Career.rewardParts(Career.reward(5)), ", ") == "$1,500, 2 Repair Kits, Hi-Vis Orange paint"
	and string.find(table.concat(Career.rewardParts(Career.reward(15)), ", "), "Legend of the Last Road", 1, true) ~= nil)
check("money in words", Career.money(15000) == "$15,000" and Career.money(500) == "$500" and Career.money(1234567) == "$1,234,567")

-- Given once: pending is what is not given yet; a save from before 4.6 counts what it reached as given.
local given: { [string]: boolean } = {}
check("a new player at level 1: nothing pending", #Career.pending(1, given) == 0)
local first = Career.pending(3, given)
check("level 3 reached: 2 and 3 pending, lowest first", #first == 2 and first[1] == 2 and first[2] == 3)
for _, level in first do
	given[tostring(level)] = true
end
check("given once: nothing pending at the same level", #Career.pending(3, given) == 0)
check("a jump to 6: 4, 5 and 6", #Career.pending(6, given) == 3 and Career.pending(6, given)[1] == 4)
local old = Career.reached(7)
check("an old save at level 7: 2 … 7 given, nothing pending", old["2"] and old["7"] and not old["8"] and old["1"] == nil and #Career.pending(7, old) == 0)
check("… and level 8 is paid when it comes", #Career.pending(8, old) == 1 and Career.pending(8, old)[1] == 8)
check("never past the top", #Career.pending(99, Career.reached(99)) == 0 and Career.reached(99)[tostring(max)] == true)

-- The level-up card's line.
local steps = Career.road()
check("a short summary with … when there is more", string.find(Career.summary(steps[4].unlocks, 2), " …", 1, true) ~= nil
	and string.find(Career.summary(steps[3].unlocks, 99), "…", 1, true) == nil)
check("the summary leaves out the stages of cars you do not own", string.find(Career.summary(steps[6].unlocks, 99, { van = false } :: any), "Long Cargo Van", 1, true) == nil
	and string.find(Career.summary(steps[6].unlocks, 99, { van = true }), "Long Cargo Van", 1, true) ~= nil)

-- ── The gear ────────────────────────────────────────────────────────────────

local function gear(id: string): Config.GearDef
	return Economy.findGear(id) :: Config.GearDef
end
local carGearCount = 0 -- (5.1: the bike gear, GearDef.bikeOnly, is tests/bikes_test.luau's)
for _, def in Config.Gear do
	if not def.bikeOnly then
		carGearCount += 1
	end
end
check("four pieces: trolley 3 · straps 4 · cooler 5 · roof rack 7", carGearCount == 4 and gear("trolley").level == 3 and gear("straps").level == 4
	and gear("cooler").level == 5 and gear("roofrack").level == 7)
check("the prices: $600, about $900, $1,400, $2,500", gear("trolley").price == 600 and math.abs(gear("straps").price - 900) <= 200
	and math.abs(gear("cooler").price - 1400) <= 300 and math.abs(gear("roofrack").price - 2500) <= 500)
check("what the gear does is tuned in Config", Config.GearTuning.StrapsLoss == 0.6 and Config.GearTuning.CoolerDrain == 0.5 and Config.GearTuning.RoofRackSlots == 2) -- (6.7: the rack takes two)
check("the Hand Trolley is no upgrade track any more", Economy.findUpgrade("trolley") == nil)

-- The slots: the stage wins over the car; the company vehicles have none.
local SLOTS: { [string]: { number } } = {
	van = { 1, 1, 2, 3 },
	courier = { 2, 2 },
	highroof = { 3, 3 },
	boxtruck = { 3, 3, 4 },
	freight = { 4 },
	pickup = { 2, 2 },
	armorvan = { 3, 3 },
	rallyvan = { 2, 2 },
	muscle = { 1, 1 },
}
for carId, list in SLOTS do
	local ok = true
	for stage = 0, Economy.maxStage(carId) do
		ok = ok and Economy.gearSlots(carId, stage) == (list[stage + 1] or -1)
	end
	check(`{carId}: gear slots {table.concat(list, " / ")}`, ok)
end
for _, def in Config.Cars do
	if def.company then
		check(`{def.id}: a company vehicle has no gear slots, takes no gear`, Economy.gearSlots(def.id, 0) == 0 and not Economy.gearFits(def.id, "straps"))
	end
end
check("an unknown car or piece fits nothing", Economy.gearSlots("spaceship", 0) == 0 and not Economy.gearFits("spaceship", "straps") and not Economy.gearFits("van", "jetpack"))
check("the trolley only on the cars that take one (CarDef.trolley)", Economy.gearFits("van", "trolley") and Economy.gearFits("freight", "trolley")
	and not Economy.gearFits("pickup", "trolley") and not Economy.gearFits("muscle", "trolley"))
check("straps and a cooler in every car with a back", Economy.gearFits("muscle", "straps") and Economy.gearFits("pickup", "cooler") and Economy.gearFits("rallyvan", "straps"))
check("no roof rack on the muscle car or the pickup", not Economy.gearFits("muscle", "roofrack") and not Economy.gearFits("pickup", "roofrack")
	and Economy.gearFits("van", "roofrack") and Economy.gearFits("courier", "roofrack") and Economy.gearFits("freight", "roofrack"))

-- Owned and installed.
local carGear: Economy.CarGear = { van = { trolley = "installed", straps = "owned", cooler = "lost" }, muscle = { trolley = "installed", straps = "installed" } }
local installed = Economy.installedGear(carGear, "van")
check("installed: only what is installed", installed.trolley == true and installed.straps == nil and installed.cooler == nil)
check("a piece's state", Economy.gearState(carGear, "van", "straps") == "owned" and Economy.gearState(carGear, "van", "cooler") == nil
	and Economy.gearState(carGear, "van", "trolley") == "installed" and Economy.gearState(nil, "van", "trolley") == nil)
check("a piece that does not fit counts for nothing", Economy.installedGear(carGear, "muscle").trolley == nil and Economy.gearUsed(carGear, "muscle") == 1)
check("slots used", Economy.gearUsed(carGear, "van") == 1 and Economy.gearUsed({}, "van") == 0)

-- The Roof Rack: one more slot, a light piece only.
local rack = { roofrack = true }
check("no rack: the stage's slots", Economy.capacity("van", { stage = 3 }, {}, "parcel") == 4)
check("a rack takes two more light pieces (6.7: one before)", Economy.capacity("van", { stage = 3 }, rack, "parcel") == 6 and Economy.capacity("van", { stage = 3 }, rack, "pizza") == 6)
check("… not a heavy one, not without a look", Economy.capacity("van", { stage = 3 }, rack, "crate") == 4 and Economy.capacity("van", { stage = 3 }, rack) == 4)
check("… not on a car it does not fit", Economy.capacity("pickup", {}, rack, "parcel") == Economy.capacity("pickup", {}))
check("the old calls stay the same", Economy.capacity("boxtruck", { stage = 2 }) == 8 and Economy.capacity("nope", {}) == 0)

-- A 4.0 – 4.5 save's Hand Trolley (carUpgrades[car].trolley ≥ 1) becomes installed gear, on the cars it owns.
local moved = Economy.migrateGear({ van = { trolley = 1, engine = 3 }, highroof = { trolley = 1 }, courier = { engine = 2 }, muscle = { trolley = 1 }, boxtruck = { trolley = 0 } },
	{ van = true, courier = true, muscle = true, boxtruck = true })
check("the trolley moves to the gear, installed", moved.van ~= nil and moved.van.trolley == "installed")
check("not for a car the save does not own, none without it", moved.highroof == nil and moved.courier == nil and moved.boxtruck == nil)
check("not on a car that cannot take it", moved.muscle == nil)
check("a broken save moves nothing", next(Economy.migrateGear(nil, { van = true })) == nil and next(Economy.migrateGear({ van = "x" }, { van = true })) == nil)

-- The board's tip.
check("the tip without a trolley: where to get it, from level 3", string.find(Freight.trolleyTip("crate", 4, "carry") or "", "level 3", 1, true) ~= nil)
check("the tip with one: use it", string.find(Freight.trolleyTip("crate", 4, "carry", true) or "", "Use your hand trolley", 1, true) ~= nil)

-- ── 5.0: the road starts on foot ────────────────────────────────────────────

local road50 = Career.road()
check("5.0 level 1: the on-foot runs come first", road50[1].unlocks[1].kind == "foot")
local kitEverywhere = true
for _, kit in Config.Kit do
	local at = road50[kit.level]
	kitEverywhere = kitEverywhere and at ~= nil and has(at.unlocks, "kit", kit.id)
end
check("5.0: every piece of personal gear (Config.Kit) is on the road at its level", kitEverywhere and #Config.Kit >= 4)
-- 5.1: the bikes are on the road (kind "bike", at Spoke & Chain), no "coming in 5.1" line any more.
local bikes = false
for _, def in Config.Cars do
	bikes = bikes or def.bike == true
end
local bikeAt, soon = 0, 0
for _, step in road50 do
	for _, unlock in step.unlocks do
		if unlock.kind == "soon" then
			soon += 1
		elseif unlock.kind == "bike" and step.level == Career.BIKE_LEVEL then
			bikeAt += 1
		end
	end
end
check("5.1: no line about the next release", soon == 0)
check("5.1: level 2 opens the bikes at Spoke & Chain", bikeAt >= 1 and string.find(road50[Career.BIKE_LEVEL].unlocks[1].name .. Career.summary(road50[Career.BIKE_LEVEL].unlocks, 9), "Spoke & Chain", 1, true) ~= nil)
check("5.1: … and no bike counts as a car", not has(road50[Career.BIKE_LEVEL].unlocks, "car", "rustbike") and (not bikes or has(road50[Career.BIKE_LEVEL].unlocks, "bike", "rustbike")))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
