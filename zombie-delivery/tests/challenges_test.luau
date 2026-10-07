-- Logic test of the challenges (3.1, shared/Challenges.luau): the list (unique snake_case ids, known categories and
-- stats, positive goals, money in range, the must-have goals: every campaign, every star, every secret, every place,
-- the top level; no "every challenge" challenge), the titles (about ten, unique, no clash with the reward titles),
-- the hidden ones, and the helpers (value, progress, doneCount, find, allTitles) on a fake profile.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Levels = require("./Levels")
local Map = require("./Map")
local Missions = require("./Missions")
local Challenges = require("./Challenges")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

-- Collects the offenders of a rule: check(name, #bad == 0, list) prints the first few.
local function offenders(list: { string }): string?
	if #list == 0 then
		return nil
	end
	local shown = {}
	for n = 1, math.min(#list, 6) do
		table.insert(shown, list[n])
	end
	return table.concat(shown, ", ") .. (if #list > 6 then ` … ({#list})` else "")
end

local List = Challenges.List

-- ── The list ──────────────────────────────────────────────────────────────
check("about 40 challenges", #List >= 36 and #List <= 46, #List)

local counters: { [string]: boolean } = {}
for _, name in Challenges.Counters do
	counters[name] = true
end
local derived: { [string]: boolean } = {}
for _, name in { "kills", "deliveries", "earned", "level", "stars", "missions", "campaigns", "secrets", "visited", "titles", "properties", "cars", "weapons" } do
	derived[name] = true
end
local categories: { [string]: boolean } = {}
for _, category in Challenges.Categories do
	categories[category.id] = true
end
check("six categories", #Challenges.Categories == 6, #Challenges.Categories)

do
	local seen: { [string]: boolean } = {}
	local badId, dupId, badCategory, badStat, badGoal, badMoney, badText, noNumber = {}, {}, {}, {}, {}, {}, {}, {}
	local perCategory: { [string]: number } = {}
	for _, def in List do
		if not string.match(def.id, "^[a-z][a-z0-9_]*$") then
			table.insert(badId, def.id)
		end
		if seen[def.id] then
			table.insert(dupId, def.id)
		end
		seen[def.id] = true
		if not categories[def.category] then
			table.insert(badCategory, def.id .. ":" .. def.category)
		end
		perCategory[def.category] = (perCategory[def.category] or 0) + 1
		if not (counters[def.stat] or derived[def.stat]) then
			table.insert(badStat, def.id .. ":" .. def.stat)
		end
		if not (def.goal > 0 and def.goal == math.floor(def.goal)) then
			table.insert(badGoal, def.id)
		end
		if not (def.money >= 200 and def.money <= 20000) then
			table.insert(badMoney, def.id)
		end
		if def.name == "" or def.description == "" then
			table.insert(badText, def.id)
		end
		-- the number is in the description (written with thousands separators)
		local plain = string.gsub(def.description, ",", "")
		if not string.find(plain, tostring(def.goal), 1, true) then
			table.insert(noNumber, def.id)
		end
	end
	check("ids snake_case", #badId == 0, offenders(badId))
	check("ids unique", #dupId == 0, offenders(dupId))
	check("categories known", #badCategory == 0, offenders(badCategory))
	check("stats are counters or derived", #badStat == 0, offenders(badStat))
	check("goals positive whole numbers", #badGoal == 0, offenders(badGoal))
	check("money 200 … 20,000", #badMoney == 0, offenders(badMoney))
	check("names and descriptions", #badText == 0, offenders(badText))
	check("the goal is in the description", #noNumber == 0, offenders(noNumber))
	local empty = {}
	for _, category in Challenges.Categories do
		if (perCategory[category.id] or 0) < 3 then
			table.insert(empty, category.id)
		end
	end
	check("every category has at least 3", #empty == 0, offenders(empty))
end

-- Is there a challenge on `stat` with exactly `goal`?
local function has(stat: string, goal: number): boolean
	for _, def in List do
		if def.stat == stat and def.goal == goal then
			return true
		end
	end
	return false
end
-- 6.8: the "every …" goals count the story chapters (the DUO chapter needs a partner: a solo player can finish them).
local _, mostStars = Missions.stars({}, nil, true)
local _, storyMissions = Missions.doneCount({}, true)
local storyChapters = 0
for _, campaign in Missions.Campaigns do
	if not campaign.duo then
		storyChapters += 1
	end
end
local secretList = (Map :: any).Secrets :: { any }?
local secretsTotal = if secretList and #secretList > 0 then #secretList else 30
check("every story chapter done (10: not the DUO one)", has("campaigns", storyChapters) and storyChapters == 10, storyChapters)
check("every story star (180, from the data)", has("stars", mostStars) and mostStars == 3 * storyMissions and mostStars == 180, mostStars)
check("every secret (#Map.Secrets)", has("secrets", secretsTotal), secretsTotal)
check("every place (#Map.Places)", has("visited", #Map.Places), #Map.Places)
check("level 15", has("level", 15) and Config.Levels.MaxLevel == 15)
check("every story mission (60)", has("missions", storyMissions) and storyMissions == 60, storyMissions)
do
	local bad = {}
	for _, def in List do
		if def.stat == "challenges" or string.find(string.lower(def.name), "every challenge", 1, true) then
			table.insert(bad, def.id)
		end
	end
	check("no every-challenge challenge (that is Dead End)", #bad == 0, offenders(bad))
end
do
	-- goals a player can reach: a level goal within MaxLevel, a derived goal within what exists
	local bad = {}
	local limits: { [string]: number } = {
		level = Config.Levels.MaxLevel,
		stars = mostStars,
		missions = storyMissions,
		campaigns = storyChapters,
		visited = #Map.Places,
		secrets = secretsTotal,
		cars = #Config.Cars,
		weapons = #Config.Weapons,
		properties = #Config.Estate.Properties,
	}
	for _, def in List do
		local limit = limits[def.stat]
		if limit and def.goal > limit then
			table.insert(bad, def.id)
		end
	end
	check("goals reachable", #bad == 0, offenders(bad))
end
do
	-- harder goals on the same stat pay more
	local bad = {}
	for _, a in List do
		for _, b in List do
			if a.stat == b.stat and a.goal < b.goal and a.money > b.money then
				table.insert(bad, a.id .. ">" .. b.id)
			end
		end
	end
	check("harder pays more", #bad == 0, offenders(bad))
end

-- ── Hidden and titles ─────────────────────────────────────────────────────
do
	local hidden, titled = 0, 0
	for _, def in List do
		if def.hidden then
			hidden += 1
		end
		if def.title then
			titled += 1
		end
	end
	check("3 or 4 hidden", hidden >= 3 and hidden <= 4, hidden)
	check("about 10 titles", titled >= 8 and titled <= 12, titled)
end
do
	local rewardTitles: { [string]: boolean } = {}
	for _, reward in Config.Rewards.Campaigns do
		rewardTitles[reward.title] = true
	end
	rewardTitles[Config.Rewards.Secrets.title] = true
	rewardTitles[Config.Rewards.Challenges.title] = true
	local clash, dup = {}, {}
	local seen: { [string]: boolean } = {}
	for _, def in List do
		local title = def.title
		if title then
			if rewardTitles[title] then
				table.insert(clash, title)
			end
			if seen[title] then
				table.insert(dup, title)
			end
			seen[title] = true
		end
	end
	check("titles don't clash with reward titles", #clash == 0, offenders(clash))
	check("challenge titles unique", #dup == 0, offenders(dup))
	local all = Challenges.allTitles()
	local seenAll: { [string]: boolean } = {}
	local dupAll = {}
	for _, title in all do
		if seenAll[title] then
			table.insert(dupAll, title)
		end
		seenAll[title] = true
	end
	check("allTitles unique", #dupAll == 0, offenders(dupAll))
	check("allTitles has the final ones", seenAll[Config.Rewards.Challenges.title] == true and seenAll[Config.Rewards.Secrets.title] == true)
	check("allTitles has every campaign title", seenAll[Config.Rewards.Campaigns.army.title] == true and seenAll[Config.Rewards.Campaigns.exodus.title] == true)
end

-- ── Helpers on a fake profile ─────────────────────────────────────────────
do
	local fresh: Challenges.ProfileLike = {}
	local bad = {}
	for _, def in List do
		local share, reached = Challenges.progress(def, fresh)
		-- a new profile: level 1 is the only stat above 0; nothing is reached
		if reached or share < 0 or share > 1 then
			table.insert(bad, def.id)
		end
	end
	check("a fresh profile reaches nothing", #bad == 0, offenders(bad))
	local done, total = Challenges.doneCount(fresh)
	check("doneCount on a fresh profile", done == 0 and total == #List, `{done}/{total}`)
end
do
	local progress: { [string]: number } = {}
	for _, def in Missions.ofCampaign("dispatch") do
		progress[def.id] = 3
	end
	progress[Missions.ofCampaign("clinic")[1].id] = 2
	progress.duo_1 = 3 -- 6.8: the DUO chapter counts for none of these
	progress.dispatch_4 = 3 -- 6.8: a retired id of an old save counts for none either
	local profile: Challenges.ProfileLike = {
		kills = 12,
		deliveries = 7,
		earned = 15000,
		xp = Levels.xpFor(5),
		stats = { headshots = 30, distance = 1234, quietMissions = 1 },
		missions = progress,
		secrets = { secret_base = true, secret_gas = false },
		visited = { base = true, gas = true, docks = true },
		titles = { Headhunter = true },
		properties = { elm = true },
		cars = { [Config.Cars[1].id] = true, [Config.Cars[2].id] = true },
		weapons = { pistol = true },
		challenges = { first_blood = true, sharpshooter = true, not_a_challenge = true },
	}
	local value = Challenges.value
	check("value kills", value(profile, "kills") == 12)
	check("value deliveries", value(profile, "deliveries") == 7)
	check("value earned", value(profile, "earned") == 15000)
	check("value level", value(profile, "level") == 5, value(profile, "level"))
	check("value stars (the story's)", value(profile, "stars") == 20, value(profile, "stars"))
	check("value missions (the story's, no retired id)", value(profile, "missions") == 7, value(profile, "missions"))
	check("value campaigns", value(profile, "campaigns") == 1, value(profile, "campaigns"))
	check("value secrets counts only found ones", value(profile, "secrets") == 1)
	check("value visited", value(profile, "visited") == 3)
	check("value titles", value(profile, "titles") == 1)
	check("value properties / cars / weapons", value(profile, "properties") == 1 and value(profile, "cars") == 2 and value(profile, "weapons") == 1)
	check("value counter", value(profile, "headshots") == 30 and value(profile, "distance") == 1234)
	check("value missing counter is 0", value(profile, "brutes") == 0 and value({}, "headshots") == 0)

	local firstBlood = Challenges.find("first_blood")
	check("find", firstBlood ~= nil and firstBlood.stat == "kills")
	check("find unknown", Challenges.find("nope") == nil)
	if firstBlood then
		local share, reached = Challenges.progress(firstBlood, profile)
		check("progress reached and clamped", reached and share == 1, share)
	end
	local ghost = Challenges.find("ghost")
	if ghost then
		local _, reached = Challenges.progress(ghost, profile)
		check("hidden ghost reached", reached and ghost.hidden == true)
	end
	local storyTime = Challenges.find("story_time")
	if storyTime then
		local _, reached = Challenges.progress(storyTime, profile)
		check("one campaign done reaches story_time", reached)
	end
	local legend = Challenges.find("legendary_courier")
	if legend then
		local share, reached = Challenges.progress(legend, profile)
		check("partial progress", not reached and math.abs(share - 7 / storyMissions) < 1e-9, share)
	end
	local done, total = Challenges.doneCount(profile)
	check("doneCount counts only real challenges", done == 2 and total == #List, `{done}/{total}`)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
