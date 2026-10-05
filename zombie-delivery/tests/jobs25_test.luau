-- Logic test of the 2.5 jobs (shared/Economy.luau, Config.Jobs, Config.Cargo, Config.JobTypes): the new special jobs
-- (Cash Transport, Ambulance Run, Pizza Rush), the night scaling, the level locks, the night bonus in the payout and
-- the crew split.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
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

-- The new job types ------------------------------------------------------------------

local cashrun = Economy.findJobType("cashrun")
local ambulance = Economy.findJobType("ambulance")
local pizzarush = Economy.findJobType("pizzarush")
local winter = Economy.findJobType("winter")
local army = Economy.findJobType("armysupply")

check("the three new job types exist", cashrun ~= nil and ambulance ~= nil and pizzarush ~= nil)
if cashrun and ambulance and pizzarush and winter and army then
	check("the cash transport is a board special the bandits want", Economy.onBoard(cashrun) and (cashrun.banditBoost or 1) > 1)
	check("the cash rides in the armored truck as gold strongboxes", cashrun.vehicle == "armored" and Config.Cargo.Kinds[cashrun.itemKind].look == "gold")
	check("the ambulance run is the clinic's, not on the board", not Economy.onBoard(ambulance) and ambulance.employer == "clinic")
	check("the patient walks in and out (board) on a clock", ambulance.load == "board" and ambulance.unload == "board" and (ambulance.timeLimit or 0) > 0)
	check("one patient, with the patient look", ambulance.items == 1 and Config.Cargo.Kinds[ambulance.itemKind].look == "patient")
	check("the pizza rush is a board special on a 3 minute clock", Economy.onBoard(pizzarush) and pizzarush.timeLimit == 180)
	check("the winter run is still on the board", Economy.onBoard(winter))
	check("an employer's job is not on the board", not Economy.onBoard(army))
	check("the clinic lends a real ambulance", Economy.findCar(ambulance.vehicle or "") ~= nil)
	local employer = Economy.findEmployer("clinic")
	check("the clinic employer gives the ambulance job", employer ~= nil and employer.jobType == "ambulance")

	-- Levels.
	check("cash transport from level 5", Economy.jobLevel(cashrun, cashrun.tier) == 5)
	check("ambulance from level 3", Economy.jobLevel(ambulance, ambulance.tier) == 3)
	check("pizza rush from level 1", Economy.jobLevel(pizzarush, pizzarush.tier) == 1)
	check("a board special without a level needs its tier's", Economy.jobLevel(winter, winter.tier) == Config.Jobs.Tiers[winter.tier].level)
	check("army supply from level 7 (3.2)", Economy.jobLevel(army, army.tier) == 7)
end

check("the new jobs have their people", (function()
	for _, id in { "cashrun", "ambulance", "pizzarush" } do
		local people = Config.Jobs.People[id]
		if not people or people.giver == "" or people.receiver == "" then
			return false
		end
	end
	return true
end)())

check("the new cargo kinds are there", Config.Cargo.Kinds.cash ~= nil and Config.Cargo.Kinds.patient ~= nil and Config.Cargo.Kinds.pizza ~= nil)
check("a patient shuffles slower than anybody", Config.Cargo.PatientWalkSpeed > 0 and Config.Cargo.PatientWalkSpeed < 8)
check("… and gets more time to arrive", Config.Cargo.PatientWalkTimeout >= Config.Cargo.WalkTimeout)

check("board special chances are chances", (function()
	for _, chance in Config.Jobs.BoardSpecials do
		if chance < 0 or chance > 1 then
			return false
		end
	end
	return #Config.Jobs.BoardSpecials >= 1
end)())

check("every rush clock is long enough to play", (function()
	for _, jobType in Config.JobTypes do
		if jobType.timeLimit and jobType.timeLimit < 60 then
			return false
		end
	end
	return true
end)())

check("every job level can be reached", (function()
	for _, jobType in Config.JobTypes do
		if Economy.jobLevel(jobType, jobType.tier) > Config.Levels.MaxLevel then
			return false
		end
	end
	return true
end)())

-- Danger levels ------------------------------------------------------------------------

local tiers = Config.Jobs.Tiers
check("the easy deliveries are open at level 1", Economy.jobLevel(nil, 1) == 1)
check("danger levels unlock in order", (function()
	for n = 2, #tiers do
		if tiers[n].level < tiers[n - 1].level then
			return false
		end
	end
	return true
end)())
check("an ordinary delivery needs its tier's level", Economy.jobLevel(nil, 3) == tiers[3].level)

-- Night ------------------------------------------------------------------------------

local N = Config.DayNight
check("day scales nothing", Economy.nightScale(N.NightPay, 0) == 1)
check("deep night scales fully", math.abs(Economy.nightScale(N.NightPay, 1) - N.NightPay) < 1e-9)
check("dusk is in between", math.abs(Economy.nightScale(2, 0.5) - 1.5) < 1e-9)
check("night factor is clamped", Economy.nightScale(2, 3) == 2 and Economy.nightScale(2, -1) == 1)
check("night means more of everything", N.NightPay > 1 and N.NightWaves > 1 and N.NightRoam > 1)

local day = Economy.payout(200, 1, 60, 100, 4)
local night = Economy.payout(200, 1, 60, 100, 4, N.NightPay)
check("no night bonus by day", day.nightBonus == 0 and day.total == day.conditionPay + day.fastBonus + day.killBonus)
check("the night bonus is on top", night.nightBonus == math.floor((day.total) * (N.NightPay - 1) + 0.5) and night.total == day.total + night.nightBonus, night.nightBonus)

-- The night waves use the same maths as WANTED: bigger, more often, a higher cap.
local tier = tiers[2]
check("night waves are bigger", Economy.waveSize(tier, 3, N.NightWaves) >= Economy.waveSize(tier, 3))
check("night waves come more often", Economy.waveEvery(tier, N.NightWaves) < Economy.waveEvery(tier))
check("more of them may be alive at night", Economy.waveAlive(tier, N.NightWaves) > Economy.waveAlive(tier))

-- XP and the crew -----------------------------------------------------------------------

check("a failed job gives less XP", Levels.jobXp(2, 2, 3, false, false) < Levels.jobXp(2, 2, 3, false, true))
check("a night job gives more XP", Levels.jobXp(2, 2, 3, true, true) > Levels.jobXp(2, 2, 3, false, true))
local owner, share = Economy.crewSplit(400, Config.Crew.MaxMembers)
check("a full crew: the owner gets a bonus, everybody a share", owner > 400 and share > 0 and share < owner, `{owner} / {share}`)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
