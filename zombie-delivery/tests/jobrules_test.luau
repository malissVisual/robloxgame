-- Logic test of 4.7, real jobs: shared/JobRules.luau (the board's choice of three trade-offs, the REROLL fee, the
-- rating ★ … ★★★ with its pay and XP, the streak, the licences and the grandfather rule) and its numbers in
-- Config.Jobs (Choice, Rating, Licences).
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local JobRules = require("./JobRules")
local Career = require("./Career")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Jobs = Config.Jobs
local Choice = Jobs.Choice
local Rating = Jobs.Rating

-- The choice ------------------------------------------------------------------------------

local function sequence(values: { number }): () -> number
	local n = 0
	return function(): number
		n += 1
		return values[(n - 1) % #values + 1]
	end
end

local seen: { [string]: boolean } = {}
local allDistinct, alwaysShort, rightCount = true, true, true
for a = 0, 9 do
	for b = 0, 9 do
		local roles = JobRules.roles(sequence({ a / 10, b / 10 }))
		if #roles ~= Choice.Offers then
			rightCount = false
		end
		if roles[1] ~= "short" then
			alwaysShort = false
		end
		local here: { [string]: boolean } = {}
		for _, role in roles do
			if here[role] then
				allDistinct = false
			end
			here[role] = true
			seen[role] = true
		end
	end
end
check("three offers a tier", Choice.Offers == 3 and rightCount)
check("the short & safe one always, first", alwaysShort)
check("never the same trade-off twice in a tier", allDistinct)
check("every trade-off comes up (short, long, risky, bulk)", seen.short == true and seen.long == true and seen.risky == true and seen.bulk == true)
local edge = JobRules.roles(function()
	return 0.9999
end)
check("an r near 1 still picks a role", #edge == 3, #edge)

for index, tier in Jobs.Tiers do
	local sLow, sHigh = JobRules.window("short", tier.minDistance, tier.maxDistance)
	local lLow, lHigh = JobRules.window("long", tier.minDistance, tier.maxDistance)
	local rLow, rHigh = JobRules.window("risky", tier.minDistance, tier.maxDistance)
	check(`tier {index}: the short drop band is below the long one`, sLow == tier.minDistance and sHigh < lLow and lHigh <= tier.maxDistance, `{sHigh} {lLow}`)
	check(`tier {index}: the other roles take the whole range`, rLow == tier.minDistance and rHigh == tier.maxDistance)
	check(`tier {index}: the long band stays a sane drive (MaxSpan)`, lHigh <= tier.minDistance + Choice.MaxSpan)
	local risky = Choice.RiskyModifiers[index]
	local known = risky ~= nil and #risky > 0
	for _, id in risky or {} do
		local found = false
		for _, modifier in Jobs.Modifiers do
			if modifier.id == id then
				found = true
			end
		end
		known = known and found
	end
	check(`tier {index}: the risky modifiers exist`, known)
end
check("★ risky: only RUSH (★ stays calm, no WANTED)", #Choice.RiskyModifiers[1] == 1 and Choice.RiskyModifiers[1][1] == "rush")
check("the long and risky ones pay more", Choice.LongPay > 1 and Choice.RiskyPay > 1 and Choice.RiskyBoost > 1)
check("every role has a name, an icon and a why", (function()
	for _, role in { "short", "long", "risky", "bulk" } do
		local info = JobRules.roleInfo(role)
		if not info or info.name == "" or info.icon == "" or info.why == "" then
			return false
		end
	end
	return JobRules.roleInfo(nil) == nil
end)())
check("REROLL: $50 × the tier", JobRules.rerollFee(1) == 50 and JobRules.rerollFee(2) == 100 and JobRules.rerollFee(4) == 200)

-- The rating ------------------------------------------------------------------------------

local perfect = JobRules.rate(1, 0.6, false, 0)
check("on time, cargo whole, no wreck: ★★★", perfect.stars == 3 and perfect.misses == 0)
check("the checks say why (3 lines, all ok)", #perfect.checks == 3 and perfect.checks[1].ok and perfect.checks[2].ok and perfect.checks[3].ok)
check("late only: ★★", JobRules.rate(1, 0.1, false, 0).stars == 2)
check("knocked about only: ★★", JobRules.rate(0.7, 0.6, false, 0).stars == 2)
check("a wreck only: ★★", JobRules.rate(0.95, 0.6, true, 0).stars == 2)
check("a lost piece only: ★★, and it is listed", (function()
	local r = JobRules.rate(1, 0.6, false, 1)
	return r.stars == 2 and #r.checks == 4 and not r.checks[4].ok
end)())
check("badly damaged cargo alone: ★", JobRules.rate(0.4, 0.9, false, 0).stars == 1)
check("late and knocked about: ★", JobRules.rate(0.7, 0.1, false, 0).stars == 1)
check("everything wrong: still ★ (never 0)", JobRules.rate(0, 0, true, 3).stars == 1)
check("the borders count as good", JobRules.rate(Rating.GoodCondition, Rating.OnTime, false, 0).stars == 3)

-- The pay and the XP ----------------------------------------------------------------------

local total, ratingPart, streakPart = JobRules.ratedPay(1000, 3, 0)
check("★★★: +20 % pay", total == 1200 and ratingPart == 200 and streakPart == 0, total)
total, ratingPart, streakPart = JobRules.ratedPay(1000, 1, 4)
check("★: −10 % pay, no streak bonus", total == 900 and ratingPart == -100 and streakPart == 0, total)
total, ratingPart, streakPart = JobRules.ratedPay(1000, 2, 3)
check("★★ with a streak of 3: +15 %", total == 1150 and ratingPart == 0 and streakPart == 150, total)
total = JobRules.ratedPay(1000, 3, 12)
check("★★★ with a long streak: +20 % + 25 % (the streak's cap)", total == 1450, total)
check("★★★: × 1.25 XP; ★ and ★★ as they are", JobRules.ratedXp(200, 3) == 250 and JobRules.ratedXp(200, 2) == 200 and JobRules.ratedXp(200, 1) == 200)
check("Config: ★★★ 1.2, ★ 0.9, XP 1.25", Rating.Pay[3] == 1.2 and Rating.Pay[1] == 0.9 and Rating.Pay[2] == 1 and Rating.Xp[3] == 1.25)

-- The streak ------------------------------------------------------------------------------

local streak = 0
for _ = 1, 3 do
	streak = JobRules.nextStreak(streak, 2)
end
check("three good jobs: a streak of 3", streak == 3)
check("+5 % a job, +25 % at most", JobRules.streakBonus(1) == 0.05 and JobRules.streakBonus(5) == 0.25 and JobRules.streakBonus(9) == 0.25 and JobRules.streakBonus(0) == 0)
check("a ★ job ends it", JobRules.nextStreak(streak, 1) == 0)
check("★★★ counts like ★★", JobRules.nextStreak(4, 3) == 5)

-- The licences ----------------------------------------------------------------------------

local three, four = JobRules.licence(3), JobRules.licence(4)
check("★★★: level 4 and 5 good jobs at ★★", three ~= nil and three.level == 4 and three.jobs == 5 and three.atTier == 2)
check("★★★★: level 7 and 10 good jobs at ★★★", four ~= nil and four.level == 7 and four.jobs == 10 and four.atTier == 3)
check("★ and ★★ need no licence", JobRules.licence(1) == nil and JobRules.licence(2) == nil and JobRules.hasLicence(2, 2, {}, {}))
check("the licences' levels are their tiers' levels", three ~= nil and four ~= nil and Jobs.Tiers[3].level == three.level and Jobs.Tiers[4].level == four.level)

local counts: { [string]: number } = {}
JobRules.countJob(counts, 2, 1)
check("a ★ job counts for nothing", next(counts) == nil)
JobRules.countJob(counts, 1, 3)
check("a ★ danger job counts for nothing", next(counts) == nil)
for _ = 1, 4 do
	JobRules.countJob(counts, 2, 2)
end
local have, need = JobRules.progress(3, counts)
check("four good ★★ jobs: LICENCE 4 / 5", have == 4 and need == 5)
check("not yet at 4 / 5", not JobRules.hasLicence(3, 6, {}, counts))
local grew = JobRules.countJob(counts, 2, 3)
check("the fifth counts (★★ jobs never count for ★★★★)", #grew == 1 and grew[1] == 3 and (counts["4"] or 0) == 0)
check("5 / 5 at level 4: the ★★★ licence", JobRules.hasLicence(3, 4, {}, counts))
check("5 / 5 below level 4: not yet", not JobRules.hasLicence(3, 3, {}, counts))
for _ = 1, 3 do
	JobRules.countJob(counts, 2, 2)
end
check("the count stops at what the licence needs", counts["3"] == 5, counts["3"])
for _ = 1, 10 do
	JobRules.countJob(counts, 3, 2)
end
have, need = JobRules.progress(4, counts)
check("ten good ★★★ jobs: 10 / 10 for ★★★★", have == 10 and need == 10)
check("★★★★ at level 7 with them", JobRules.hasLicence(4, 7, {}, counts) and not JobRules.hasLicence(4, 6, {}, counts))
check("a licence held stays held", JobRules.hasLicence(4, 1, { ["4"] = true }, {}))

-- The grandfather rule ----------------------------------------------------------------------

local old = JobRules.grandfather(8, 40)
check("an old save at level 8 with deliveries keeps ★★★ and ★★★★", old["3"] == true and old["4"] == true)
old = JobRules.grandfather(5, 12)
check("an old save at level 5 keeps ★★★ only", old["3"] == true and old["4"] == nil)
old = JobRules.grandfather(9, 0)
check("no deliveries: no licence given", next(old) == nil)
old = JobRules.grandfather(3, 50)
check("below level 4: nothing to keep", next(old) == nil)

local function tierName(level: number, id: string): string
	for _, unlock in Career.unlocksAt(level) do
		if unlock.kind == "tier" and unlock.id == id then
			return unlock.name
		end
	end
	return ""
end
check("the CAREER road says what the ★★★ and ★★★★ licences need", string.find(tierName(4, "3"), "licence: 5 jobs", 1, true) ~= nil
	and string.find(tierName(7, "4"), "licence: 10 jobs", 1, true) ~= nil and string.find(tierName(2, "2"), "licence", 1, true) == nil, tierName(4, "3"))

check("stars in words", JobRules.stars(2) == "★★☆" and JobRules.stars(3) == "★★★" and JobRules.stars(0) == "☆☆☆")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
