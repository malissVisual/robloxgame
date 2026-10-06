-- Driver levels (shared/Levels.luau): the XP curve, ranks and job XP. Run with tests/run_tests.py.
local Config = require("./Config")
local Levels = require("./Levels")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

check("level 1 needs no XP", Levels.xpFor(1) == 0)
check("level 2 needs XpBase", Levels.xpFor(2) == Config.Levels.XpBase, Levels.xpFor(2))
local rising = true
for level = 2, Config.Levels.MaxLevel do
	if Levels.xpFor(level) <= Levels.xpFor(level - 1) then
		rising = false
	end
end
check("every level needs more XP", rising)
check("0 XP is level 1", Levels.levelFor(0) == 1)
check("exactly the threshold reaches the level", Levels.levelFor(Levels.xpFor(5)) == 5)
check("one XP short stays below", Levels.levelFor(Levels.xpFor(5) - 1) == 4)
check("capped at MaxLevel", Levels.levelFor(10 ^ 9) == Config.Levels.MaxLevel)
check("rank of level 1", Levels.rank(1) == "Rookie Courier", Levels.rank(1))
check("rank between steps", Levels.rank(7) == Levels.rank(6), Levels.rank(7))
check("progress in range", Levels.progress(Levels.xpFor(3) + 1) > 0 and Levels.progress(Levels.xpFor(3) + 1) < 1)
check("job XP grows with stars", Levels.jobXp(3, 2, 0, false, true) > Levels.jobXp(1, 2, 0, false, true))
check("night bonus", Levels.jobXp(2, 2, 2, true, true) > Levels.jobXp(2, 2, 2, false, true))
check("a failed job gives less", Levels.jobXp(2, 2, 2, false, false) < Levels.jobXp(2, 2, 2, false, true))
for _, tier in Config.Jobs.Tiers do
	check(`tier {tier.stars} has a reachable level`, tier.level >= 1 and tier.level <= Config.Levels.MaxLevel)
end
local tierRising = true
for n = 2, #Config.Jobs.Tiers do
	if Config.Jobs.Tiers[n].level < Config.Jobs.Tiers[n - 1].level then
		tierRising = false
	end
end
check("the danger tiers open in order", tierRising)

-- 3.2, the progression ------------------------------------------------------------------------------------------

local Economy = require("./Economy")
local Missions = require("./Missions")
local MAX = Config.Levels.MaxLevel

-- The XP curve against the campaign path: every mission's first clear (its job XP without kills, × FirstClearXp)
-- should carry you most of the way to the top level, not past it (the job board, the replays and the kills do the rest).
local campaignXp = 0
for _, def in Missions.List do
	if not def.duo then
		campaignXp += Levels.jobXp(def.tier, def.items, 0, false, true) * Config.Missions.FirstClearXp
	end
end
local top = Levels.xpFor(MAX)
check("the campaigns give 85 - 100 % of the top level's XP (no kills)", campaignXp >= top * 0.85 and campaignXp <= top, `{math.floor(campaignXp)} of {top}`)
-- Played in order with about 10 kills a mission, no story mission is ever above your level, and you end at the top.
-- 5.0: the story starts at the first campaign's level (the levels before it are the foot and the first car jobs).
do
	local xp, blocked = Levels.xpFor(Missions.Campaigns[1].level), nil :: string?
	for _, campaign in Missions.Campaigns do
		if not campaign.duo then
			for _, def in Missions.ofCampaign(campaign.id) do
				if not blocked and Levels.levelFor(xp) < def.level then
					blocked = `{def.id} needs {def.level}, you are {Levels.levelFor(xp)}`
				end
				xp += Levels.jobXp(def.tier, def.items, 10, false, true) * Config.Missions.FirstClearXp
			end
		end
	end
	check("the story path with ~10 kills a mission never waits for a level", blocked == nil, blocked)
	check("the story path with ~10 kills reaches the top level", Levels.levelFor(xp) == MAX, Levels.levelFor(xp))
end
-- 3.1 saves (the old curve) keep their level and their share of the way to the next.
do
	local legacy = Config.Levels.Legacy
	local function oldXpFor(level: number): number
		local total = 0
		for n = 2, level do
			total += math.floor(legacy.XpBase * legacy.XpGrowth ^ (n - 2) + 0.5)
		end
		return total
	end
	local same = true
	for level = 1, MAX do
		if Levels.levelFor(Levels.fromLegacy(oldXpFor(level))) ~= level then
			same = false
		end
	end
	check("an old save keeps its level on the new curve", same)
	local halfway = Levels.fromLegacy(math.floor((oldXpFor(10) + oldXpFor(11)) / 2))
	check("an old save keeps its share of the level", Levels.levelFor(halfway) == 10 and math.abs(Levels.progress(halfway) - 0.5) < 0.02, Levels.progress(halfway))
	check("the move never takes XP away", Levels.fromLegacy(10 ^ 6) == 10 ^ 6 and Levels.fromLegacy(0) == 0)
end
check("level 2 takes a few deliveries, not one", Levels.xpFor(2) >= 4 * Levels.jobXp(1, 2, 5, false, true), Levels.xpFor(2))
check("the last level is the longest step", Levels.xpFor(MAX) - Levels.xpFor(MAX - 1) > Levels.xpFor(MAX - 1) - Levels.xpFor(MAX - 2))

-- The garage: the cars, guns and car guns open with the levels (the pickup at 4, the muscle car at 8), and a higher
-- level never sells for less.
local function car(id: string): Config.CarDef
	return Economy.findCar(id) :: Config.CarDef
end
check("the van is the first vehicle: $1,800 at level 4 (5.0)", car("van").price == 1800 and car("van").level == 4)
check("the pickup opens at level 6", car("pickup").level == 6, car("pickup").level)
check("the muscle car opens at level 9", car("muscle").level == 9, car("muscle").level)
local function ordered(list: { any }, skip: (any) -> boolean): (boolean, string?)
	local lastLevel, lastPrice = 0, -1
	for _, def in list do
		if not skip(def) then
			local level = def.level or 1
			if level < 1 or level > MAX then
				return false, `{def.id}: level {level}`
			end
			if level < lastLevel or def.price <= lastPrice then
				return false, def.id
			end
			lastLevel, lastPrice = level, def.price
		end
	end
	return true, nil
end
check("the dealer's cars: level and price rise together", ordered(Config.Cars, function(def)
	return def.company == true or def.bike == true -- (5.1: the bikes are Spoke & Chain's, below)
end))
-- 5.1: the bikes (CarDef.bike, sold at Spoke & Chain) rise the same way among themselves, from level 2.
check("the bikes: level and price rise together", ordered(Config.Cars, function(def)
	return def.bike ~= true
end))
check("the guns: level and price rise together", ordered(Config.Weapons, function(def)
	return def.earned ~= nil or def.exclusive ~= nil
end))
check("the car guns: level and price rise together", ordered(Config.CarGuns, function()
	return false
end))
local roofmg = Economy.findCarGun("roofmg") :: Config.CarGunDef
local launcher = Economy.findCarGun("rooflauncher") :: Config.CarGunDef
check("the first car gun around level 5", (roofmg.level or 1) >= 4 and (roofmg.level or 1) <= 6, roofmg.level)
check("the roof launcher late (level 11+)", (launcher.level or 1) >= 11, launcher.level)
-- What a car costs against what a mission pays around its level: never less than a few missions' first-clear money.
local function rewardsUpTo(level: number): number
	local sum = 0
	for _, def in Missions.List do
		if (def.level or 1) <= level then
			sum += def.reward
		end
	end
	return sum
end
check("the pickup is not free money (more than the first missions' rewards)", car("pickup").price > rewardsUpTo(1), rewardsUpTo(1))
check("the muscle car costs real money", car("muscle").price >= 3 * car("pickup").price)
-- 3.3: five more vans between the start van and the endgame.
for _, want in { { "courier", 5 }, { "highroof", 5 }, { "boxtruck", 7 }, { "armorvan", 11 }, { "rallyvan", 13 } } do
	local def = Economy.findCar(want[1] :: string)
	check(`the {want[1]} is at the dealer from level {want[2]}`, def ~= nil and not def.company and def.level == want[2] and def.mount == true, def and def.level)
end
local dealer = 0
for _, def in Config.Cars do
	if not def.company and not def.bike then
		dealer += 1
	end
end
check("nine cars at the dealer (4.0: the Freight Truck)", dealer == 9, dealer)
check("the courier van is cheap, a few missions' money", car("courier").price <= rewardsUpTo(car("courier").level :: number) and car("courier").price > rewardsUpTo(car("van").level :: number - 1), car("courier").price)
check("the rally van is the dealer's last and dearest", car("rallyvan").price >= 2 * car("muscle").price, car("rallyvan").price)
check("the armored van is tough, the rally van fast", car("armorvan").health >= 2 * car("van").health and car("rallyvan").maxSpeed > car("pickup").maxSpeed)
-- The employers' company cars: the strong ones come with a level too (the monster truck no earlier than the muscle car).
local farm = Economy.findJobType("farmrun")
check("the monster truck's job needs the muscle car's level", farm ~= nil and Economy.jobLevel(farm, farm.tier) >= car("muscle").level :: number)
for _, jobType in Config.JobTypes do
	check(`{jobType.id}: a reachable level`, Economy.jobLevel(jobType, jobType.tier) <= MAX)
end

-- The real estate: the endgame -----------------------------------------------------------------------------------

local lowest: { [string]: number } = {}
local highest: { [string]: number } = {}
local cheapest: { [string]: number } = {}
for _, def in Config.Estate.Properties do
	local level = def.level or 1
	lowest[def.kind] = math.min(lowest[def.kind] or MAX, level)
	highest[def.kind] = math.max(highest[def.kind] or 1, level)
	cheapest[def.kind] = math.min(cheapest[def.kind] or math.huge, def.price)
	check(`{def.id}: a reachable level`, level >= 1 and level <= MAX, level)
	for _, campaignId in def.requires or {} do
		check(`{def.id}: requires a real campaign ({campaignId})`, Missions.findCampaign(campaignId) ~= nil)
	end
end
-- 3.4: the first garage comes early (the Courier Van at level 2 needs its slot), the big ones stay up to 7.
check("garages from level 2 - 7", lowest.garage == 2 and highest.garage <= 7, `{lowest.garage} - {highest.garage}`)
check("the first garage is cheap (a few deliveries)", cheapest.garage <= 3000, cheapest.garage)
do
	-- Every dealer car can be bought at its level: a garage open by then gives it a slot (the depot holds only the
	-- starting van). You keep and upgrade a car more than you collect them: more cars need the bigger garages.
	for _, def in Config.Cars do
		if def.company or def.price == 0 then
			continue
		end
		local slots = Config.Estate.BaseCarSlots
		for _, estate in Config.Estate.Properties do
			if estate.kind == "garage" and (estate.level or 1) <= (def.level or 1) then
				slots += estate.garageSlots
			end
		end
		check(`{def.id}: a garage open by level {def.level or 1} has a slot for it`, slots >= 2, slots)
	end
end
check("houses from level 6", lowest.house >= 6, lowest.house)
check("villas at 10 - 11", lowest.villa >= 10 and highest.villa <= 11, `{lowest.villa} - {highest.villa}`)
check("mansions at 13 - 15", lowest.mansion >= 13 and highest.mansion == MAX, `{lowest.mansion} - {highest.mansion}`)
check("offices at 12 - 15", lowest.office >= 12 and highest.office == MAX, `{lowest.office} - {highest.office}`)
check("a mansion costs millions", cheapest.mansion >= 1000000, cheapest.mansion)
check("a garage costs less than the muscle car", cheapest.garage < car("muscle").price)
local firstOffice: Config.EstateDef? = nil
for _, def in Config.Estate.Properties do
	if def.kind == "office" and (firstOffice == nil or def.price < firstOffice.price) then
		firstOffice = def
	end
end
check("the first office needs Iron Supply (army) done", firstOffice ~= nil and table.find(firstOffice.requires or {}, "army") ~= nil)
local penthouse: Config.EstateDef? = nil
for _, def in Config.Estate.Properties do
	if def.id == "office_penthouse" then
		penthouse = def
	end
end
check("the penthouse is at the top level", penthouse ~= nil and penthouse.level == MAX)

-- Economy.missingCampaign: what Estate.buy and EstateUi ask.
check("nothing required, nothing missing", Economy.missingCampaign(nil, {}) == nil)
check("a required campaign not done is missing", Economy.missingCampaign({ "army" }, {}) == "army")
check("a required campaign done is not", Economy.missingCampaign({ "army" }, { army = true }) == nil)
check("the first missing one is named", Economy.missingCampaign({ "army", "lab" }, { army = true }) == "lab")

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
