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
check("the campaigns give 60 - 115 % of the top level's XP (no kills)", campaignXp >= top * 0.6 and campaignXp <= top * 1.15, `{math.floor(campaignXp)} of {top}`)
check("level 2 takes a few deliveries, not one", Levels.xpFor(2) >= 4 * Levels.jobXp(1, 2, 5, false, true), Levels.xpFor(2))
check("the last level is the longest step", Levels.xpFor(MAX) - Levels.xpFor(MAX - 1) > Levels.xpFor(MAX - 1) - Levels.xpFor(MAX - 2))

-- The garage: the cars, guns and car guns open with the levels (the pickup at 4, the muscle car at 8), and a higher
-- level never sells for less.
local function car(id: string): Config.CarDef
	return Economy.findCar(id) :: Config.CarDef
end
check("the van is free at level 1", car("van").price == 0 and (car("van").level or 1) == 1)
check("the pickup opens at level 4", car("pickup").level == 4, car("pickup").level)
check("the muscle car opens at level 8", car("muscle").level == 8, car("muscle").level)
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
	return def.company == true
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
check("garages from level 5 - 7", lowest.garage >= 5 and highest.garage <= 7, `{lowest.garage} - {highest.garage}`)
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
