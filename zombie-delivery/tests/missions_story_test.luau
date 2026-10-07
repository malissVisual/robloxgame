-- 6.8, the missions as story chapters (shared/Missions.luau, shared/Cast.luau): the order and the locks (only the
-- next mission starts, the later ones say what they wait for, the done ones replay), the chapter locks, every
-- `requires` valid, every chapter finishable by playing the story in order (the levels never stop you), the first
-- time against a replay (Missions.creditFor, replayPay / replayXp), the saves of 3.0 – 6.7 (the same ids, the retired
-- ones), the cast (one name, one look, no old surnames) and the DUO chapter never in the main story's way.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Cast = require("./Cast")
local Levels = require("./Levels")
local Missions = require("./Missions")
local NpcLooks = require("./NpcLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function offenders(list: { string }): string?
	if #list == 0 then
		return nil
	end
	local shown = {}
	for n = 1, math.min(#list, 6) do
		table.insert(shown, list[n])
	end
	return table.concat(shown, ", ") .. (if #list > 6 then ` … ({#list} in all)` else "")
end

local MAX = Config.Levels.MaxLevel
local story: { Missions.Campaign } = {}
for _, campaign in Missions.Campaigns do
	if not campaign.duo then
		table.insert(story, campaign)
	end
end

-- Every chapter's requirements done (their finales), so only the chapter itself decides.
local function allFinales(except: string?): { [string]: number }
	local progress: { [string]: number } = {}
	for _, campaign in Missions.Campaigns do
		local finale = Missions.finale(campaign.id)
		if finale and campaign.id ~= except then
			progress[finale.id] = 1
		end
	end
	return progress
end

-- ── The cast ─────────────────────────────────────────────────────────────────

do
	local roles: { [string]: boolean } = {}
	for _, role in NpcLooks.Roles do
		roles[role] = true
	end
	local ids, names, bad = {}, {}, {}
	for _, person in Cast.People do
		if ids[person.id] then
			table.insert(bad, "id twice: " .. person.id)
		end
		if names[person.name] then
			table.insert(bad, "name twice: " .. person.name)
		end
		ids[person.id], names[person.name] = true, true
		if not roles[person.look] then
			table.insert(bad, `{person.id} look {person.look}`)
		end
		if string.sub(person.label, 1, #person.name) ~= person.name or person.job == "" or person.place == "" then
			table.insert(bad, person.id .. " label / job / place")
		end
	end
	check("the cast: unique ids and names, a known look, the label starts with the name", #bad == 0, offenders(bad))
	bad = {}
	for _, campaign in Missions.Campaigns do
		local main, partner = Missions.clientOf(campaign.id)
		if not main or campaign.client ~= main.label or campaign.clientRole ~= main.look then
			table.insert(bad, campaign.id .. " client")
		end
		if campaign.partnerId and not partner then
			table.insert(bad, campaign.id .. " partner")
		end
	end
	check("every chapter's client (and the twins) comes from the cast", #bad == 0, offenders(bad))
	check("the lock line's names: Raj, Rosa & Rico", Missions.clientName("market") == "Raj" and Missions.clientName("duo") == "Rosa & Rico", Missions.clientName("duo"))
end

-- A name that is a cast member's always comes with the cast's label and look (Npcs.look hashes name + role: the
-- same person, the same face in the world, at a mission's stop and in the portrait).
do
	local bad = {}
	local function person(text: string, role: string?, where: string)
		local name = string.match(text, "^(.-),") or text
		local known = Cast.named(name)
		if known and (role ~= known.look or (string.find(text, ",", 1, true) ~= nil and text ~= known.label)) then
			table.insert(bad, `{where}: {text} ({role}) is {known.label} ({known.look})`)
		end
	end
	for _, def in Missions.List do
		person(def.giver, def.giverRole, def.id)
		person(def.receiver, def.receiverRole, def.id)
	end
	-- The world's people with a cast name (Config's places, docks and shops).
	local jobs = Config.Jobs :: any
	for place, entry in jobs.PlacePeople do
		person(entry.name, entry.role, "PlacePeople." .. place)
	end
	for place, entry in jobs.FreightReceivers do
		person(entry.name, entry.role, "FreightReceivers." .. place)
	end
	for _, business in jobs.Businesses or {} do
		if business.giver then
			person(business.giver.name, business.giver.role, "Businesses." .. business.id)
		end
		for _, receiver in business.receivers or {} do
			person(receiver.name, receiver.role, "Businesses." .. business.id)
		end
	end
	check("a cast member is the same person everywhere (label and look)", #bad == 0, offenders(bad))
end

-- 6.3 gave everybody a first name and a role; 6.8 checks no surname of before came back.
do
	local OLD = {
		"Ellis", "Reyes", "Ramirez", "Daniels", "Diaz", "Shaw", "Hansen", "Holloway", "Ito", "Novak", "Volkov", "Grant",
		"Brown", "Delacroix", "Gold", "Haddad", "Kowalski", "Lindgren", "Novotny", "Okoro", "Patel", "Pruitt", "Sato",
		"Sterling", "Abara", "Albescu", "Fisher", "Gruber", "Lee", "Lindqvist", "Lopez", "Kline", "Parker",
		"Rivera", "Jenkins", "Moore", "Lang", "Hayes", "Kowalczyk", "Okafor", "Bertrand",
	}
	local texts: { { string } } = {}
	for _, campaign in Missions.Campaigns do
		table.insert(texts, { campaign.id, `{campaign.name} {campaign.client} {campaign.pitch}` })
	end
	for _, def in Missions.List do
		table.insert(texts, { def.id, `{def.name} {def.description} {def.briefing} {def.debrief} {def.giver} {def.receiver} {def.cargo}` })
	end
	for _, person in Cast.People do
		table.insert(texts, { person.id, `{person.label} {person.job} {person.place}` })
	end
	local bad = {}
	for _, entry in texts do
		local text = entry[2]
		for _, honorific in { "Mr. ", "Mrs. ", "Ms. ", "Dr. " } do
			if string.find(text, honorific, 1, true) then
				table.insert(bad, `{entry[1]}: {honorific}`)
			end
		end
		for _, surname in OLD do
			if string.find(" " .. text .. " ", "[^%a]" .. surname .. "[^%a]") then
				table.insert(bad, `{entry[1]}: {surname}`)
			end
		end
	end
	check("no old surname or Mr. / Mrs. / Dr. left in the missions' texts", #bad == 0, offenders(bad))
	-- The 6.8 review of the stories: one bank manager, the bandit boss is not Earl the van seller, Mayor Ruth is "she".
	local clash = {}
	for _, def in Missions.List do
		local all = `{def.briefing} {def.debrief} {def.description} {def.giver} {def.receiver} {def.cargo}`
		for _, word in { "Earl", "Diane", "Kenji", "Lucy", "Mama Rosa" } do
			if string.find(all, word, 1, true) then
				table.insert(clash, `{def.id}: {word}`)
			end
		end
		if def.campaign == "exodus" and (string.find(all, "as a father", 1, true) or string.find(all, " he's busy", 1, true)) then
			table.insert(clash, def.id .. ": the mayor")
		end
	end
	check("no name clashes (Earl, a second bank manager, a second Kenji / Lucy / Rosa)", #clash == 0, offenders(clash))
end

-- ── Requires ───────────────────────────────────────────────────────────────────

do
	local bad = {}
	for _, campaign in Missions.Campaigns do
		for _, id in campaign.requires or {} do
			if id == campaign.id then
				table.insert(bad, campaign.id .. " requires itself")
			elseif not Missions.findCampaign(id) then
				table.insert(bad, `{campaign.id} requires a missing {id}`)
			elseif not Missions.finale(id) then
				table.insert(bad, `{campaign.id} requires {id}, which has no finale`)
			end
		end
	end
	check("every `requires` names a chapter that exists and has a finale", #bad == 0, offenders(bad))
	-- Nothing of the main story (no story chapter, no property) needs the DUO chapter.
	local needsDuo = {}
	for _, campaign in story do
		if table.find(campaign.requires or {}, "duo") then
			table.insert(needsDuo, campaign.id)
		end
	end
	local estate = (Config :: any).Estate
	for _, def in if estate then estate.Properties else {} do
		local requires = if type(def.requires) == "table" then def.requires elseif type(def.requires) == "string" then { def.requires } else {}
		if table.find(requires, "duo") then
			table.insert(needsDuo, def.id)
		end
	end
	check("the DUO chapter never blocks the main story", #needsDuo == 0, offenders(needsDuo))
end

-- ── The order and the locks ───────────────────────────────────────────────────────

do
	local bad = {}
	for _, campaign in Missions.Campaigns do
		local list = Missions.ofCampaign(campaign.id)
		local progress = allFinales(campaign.id)
		for done = 0, #list do
			-- the first `done` missions are done
			local copy = table.clone(progress)
			for n = 1, done do
				copy[list[n].id] = 2
			end
			local nextDef = Missions.nextUp(copy, campaign.id)
			if (done < #list) ~= (nextDef ~= nil) or (nextDef and nextDef ~= list[done + 1]) then
				table.insert(bad, `{campaign.id} after {done}: next`)
			end
			for n, def in list do
				local open, why = Missions.unlocked(def.id, copy, MAX)
				local status, reason = Missions.statusOf(def.id, copy, MAX)
				if n <= done then
					if not open or status ~= "done" then
						table.insert(bad, `{def.id} done but {status}`)
					end
				elseif n == done + 1 then
					if not open or status ~= "next" then
						table.insert(bad, `{def.id} should be next ({why})`)
					end
				else
					local wants = `Finish "{list[done + 1].name}" first`
					if open or status ~= "locked" or reason ~= wants or why ~= wants .. "." then
						table.insert(bad, `{def.id} after {done}: {status} {reason}`)
					end
				end
			end
		end
	end
	check("only the next mission starts; later ones say \"Finish 'X' first\"; done ones replay", #bad == 0, offenders(bad))
end
do
	-- A mission's own level: the next one below it says so; a done one replays at any level.
	local list = Missions.ofCampaign("firehouse")
	local progress = allFinales("firehouse")
	for n = 1, 3 do
		progress[list[n].id] = 1
	end
	local fourth = list[4]
	local status, reason = Missions.statusOf(fourth.id, progress, (fourth.level or 1) - 1)
	local open, why = Missions.unlocked(fourth.id, progress, (fourth.level or 1) - 1)
	check("the next mission above your level: \"Level N\"", status == "locked" and reason == `Level {fourth.level}` and not open and why ~= nil, reason)
	check("… a done one replays below its level", (Missions.unlocked(list[2].id, progress, Missions.findCampaign("firehouse").level)))
	-- The chapter locks: what it waits for, then its level.
	local none: { [string]: number } = {}
	local state = Missions.chapterState("clinic", none, MAX)
	check("a chapter waits for the one before: \"Finish Marge's chapter first\"", not state.open and state.why == "Finish Marge's chapter first", state.why)
	state = Missions.chapterState("clinic", { dispatch_10 = 1 }, 4)
	check("… then its level: \"Level 5\"", not state.open and state.why == "Level 5", state.why)
	state = Missions.chapterState("clinic", { dispatch_10 = 1 }, 5)
	check("… open, NEW, 0 / 6, its first mission next", state.open and state.new and state.done == 0 and state.total == 6 and state.nextId == "clinic_1" and not state.complete)
	local all: { [string]: number } = {}
	for _, def in Missions.ofCampaign("clinic") do
		all[def.id] = 3
	end
	state = Missions.chapterState("clinic", all, 5)
	check("… DONE: 6 / 6, nothing next", state.open and state.complete and not state.new and state.nextId == nil and state.done == 6)
	local exodus = Missions.chapterState("exodus", { dispatch_10 = 1 }, MAX)
	check("Last Convoy waits for all nine: \"(and 7 more)\"", not exodus.open and exodus.why ~= nil and string.find(exodus.why, "and 7 more", 1, true) ~= nil, exodus.why)
	check("the DUO chapter opens after First Shift at level 6", (Missions.campaignOpen("duo", { dispatch_10 = 1 }, 6)) and not Missions.campaignOpen("duo", {}, MAX))
	check("Smoke and Sirens needs Empty Shelves only (not the DUO chapter)", (Missions.campaignOpen("firehouse", { market_10 = 2 }, MAX)))
	check("an unknown mission is refused", not Missions.unlocked("nope_1", none, MAX))
end

-- ── Every chapter finishable, in story order ─────────────────────────────────────────

do
	-- A player who starts the story with the first chapter's level and plays every story mission once, in order,
	-- with about 10 kills a mission (the job's XP and the first clear's bonus): no mission ever waits for a level, every
	-- chapter's reward is paid once, the story ends at the top level. Then the DUO chapter (with a partner).
	local progress: { [string]: number } = {}
	local rewarded: { [string]: boolean } = {}
	local xp = Levels.xpFor(Missions.Campaigns[1].level)
	local money, chapterRewards = 0, 0
	local stuck: string? = nil
	local played = 0
	local guard = 0
	while guard < 500 do
		guard += 1
		local level = Levels.levelFor(xp)
		local pick: Missions.MissionDef? = nil
		for _, campaign in story do
			local state = Missions.chapterState(campaign.id, progress, level)
			if state.open and state.nextId then
				pick = Missions.find(state.nextId)
				break
			end
		end
		if not pick then
			break
		end
		local open, why = Missions.unlocked(pick.id, progress, level)
		if not open then
			stuck = `{pick.id}: {why}`
			break
		end
		local plan = Missions.creditFor(progress, rewarded, pick.id, 3)
		if not plan or not plan.first or plan.replay then
			stuck = pick.id .. ": not a first clear"
			break
		end
		progress[pick.id] = plan.best
		local jobXp = Levels.jobXp(pick.tier, pick.items, 10, false, true)
		xp += jobXp + math.floor(plan.xpBonus * Levels.jobXp(pick.tier, pick.items, 0, false, true) + 0.5)
		money += plan.reward + plan.starBonus + plan.chapterReward
		if plan.chapterDone then
			rewarded[pick.campaign] = true
			chapterRewards += 1
		end
		played += 1
	end
	check("the whole story plays in order without waiting for a level", stuck == nil, stuck)
	local unfinished = {}
	for _, campaign in story do
		if not Missions.finished(progress, campaign.id) or not rewarded[campaign.id] then
			table.insert(unfinished, campaign.id)
		end
	end
	check("every story chapter finished, its reward paid once", #unfinished == 0 and chapterRewards == #story and played == 60, `{offenders(unfinished)} {chapterRewards} {played}`)
	check("the story ends at the top level", Levels.levelFor(xp) == MAX, Levels.levelFor(xp))
	-- The DUO chapter, after it.
	local duoPlayed = 0
	for _, def in Missions.ofCampaign("duo") do
		if Missions.unlocked(def.id, progress, Levels.levelFor(xp)) then
			local plan = Missions.creditFor(progress, rewarded, def.id, 2)
			if plan then
				progress[def.id] = plan.best
				if plan.chapterDone then
					rewarded.duo = true
				end
				duoPlayed += 1
			end
		end
	end
	check("the DUO chapter is finishable too", duoPlayed == 6 and rewarded.duo == true, duoPlayed)
	-- Without the kills the first clears still give most of the top level's XP (the board does the rest).
	local base = 0
	for _, def in Missions.List do
		if not def.duo then
			base += Levels.jobXp(def.tier, def.items, 0, false, true) * Config.Missions.FirstClearXp
		end
	end
	local top = Levels.xpFor(MAX)
	check("the story's first clears give 85 – 100 % of the top level's XP (no kills)", base >= top * 0.85 and base <= top, `{math.floor(base)} of {top}`)
end

-- ── First time and replays ────────────────────────────────────────────────────────

do
	local tuning = Config.Missions
	local def = Missions.find("clinic_4") :: Missions.MissionDef
	local progress: { [string]: number } = { clinic_1 = 2, clinic_2 = 1 }
	local rewarded: { [string]: boolean } = {}
	local first = Missions.creditFor(progress, rewarded, def.id, 2)
	check("first time: the mission's reward, the first-clear XP bonus, the new stars", first ~= nil and first.first and not first.replay
		and first.reward == def.reward and first.xpBonus == tuning.FirstClearXp - 1 and first.newStars == 2 and first.starBonus == 2 * tuning.StarBonus
		and not first.chapterDone)
	progress[def.id] = 2
	local again = Missions.creditFor(progress, rewarded, def.id, 2)
	check("a replay: no reward, no XP bonus, no star bonus without a new star", again ~= nil and again.replay and not again.first
		and again.reward == 0 and again.xpBonus == 0 and again.starBonus == 0 and again.newStars == 0 and not again.chapterDone)
	local better = Missions.creditFor(progress, rewarded, def.id, 3)
	check("… a better rating still pays its new star once", better ~= nil and better.replay and better.reward == 0 and better.newStars == 1 and better.starBonus == tuning.StarBonus)
	check("the replay's pay: a quarter, to $5", Missions.replayPay(1000) == 250 and Missions.replayPay(1234) == 310 and Missions.replayPay(0) == 0)
	check("the replay's XP: a quarter", Missions.replayXp(400) == 100 and Missions.replayXp(0) == 0)
	check("Config: a replay pays far less than the first time", tuning.ReplayPay > 0 and tuning.ReplayPay <= 0.35 and tuning.ReplayXp >= 0 and tuning.ReplayXp <= 0.35)
	-- The finale: the chapter's reward, once.
	local all: { [string]: number } = {}
	local list = Missions.ofCampaign("clinic")
	for n = 1, #list - 1 do
		all[list[n].id] = 1
	end
	local finale = list[#list]
	local plan = Missions.creditFor(all, {}, finale.id, 1)
	local campaign = Missions.findCampaign("clinic") :: Missions.Campaign
	check("the finale's first clear pays the chapter's big reward", plan ~= nil and plan.first and plan.chapterDone and plan.chapterReward == campaign.reward)
	all[finale.id] = 1
	plan = Missions.creditFor(all, { clinic = true }, finale.id, 3)
	check("… and never again (a replay of the finale)", plan ~= nil and plan.replay and not plan.chapterDone and plan.chapterReward == 0 and plan.reward == 0)
	plan = Missions.creditFor(all, { clinic = true }, list[1].id, 3)
	check("… nor on a replay of another mission", plan ~= nil and not plan.chapterDone)
	check("an unknown mission credits nothing", Missions.creditFor({}, {}, "nope_1", 3) == nil)
	check("cleared: a rating of 1 or more", Missions.cleared({ dispatch_1 = 1 }, "dispatch_1") and not Missions.cleared({ dispatch_1 = 0 }, "dispatch_1") and not Missions.cleared(nil, "dispatch_1"))
end

-- ── The saves of 3.0 – 6.7 ────────────────────────────────────────────────────────

do
	check("retired: a 3.0 id no chapter tells", Missions.isRetired("dispatch_4") and Missions.isRetired("lab_1") and Missions.isRetired("duo_3"))
	check("… not a chapter's mission, nor anything else", not Missions.isRetired("dispatch_1") and not Missions.isRetired("nope_3")
		and not Missions.isRetired("dispatch_11") and not Missions.isRetired("dispatch_0") and not Missions.isRetired("dispatch"))
	local retired = 0
	for _, campaign in Missions.Campaigns do
		for n = 1, 10 do
			if Missions.isRetired(`{campaign.id}_{n}`) then
				retired += 1
			end
		end
	end
	check("44 retired ids (4 of every old campaign of 10)", retired == 44, retired)
	-- A 3.0 – 6.7 campaign was played in order (mission n needed n - 1): its progress was missions 1 … k. Under the
	-- chapters that is still a run of the chapter's first missions (the ids kept their order), the next one is the
	-- first kept id after k, and the old finale done means the chapter is finished.
	local bad = {}
	for _, campaign in Missions.Campaigns do
		for k = 0, 10 do
			local progress: { [string]: number } = {}
			for n = 1, k do
				progress[`{campaign.id}_{n}`] = 2
			end
			local list = Missions.ofCampaign(campaign.id)
			local seenUndone = false
			for _, def in list do
				local done = (progress[def.id] or 0) >= 1
				if done and seenUndone then
					table.insert(bad, `{campaign.id} after {k}: {def.id} done after an undone one`)
				end
				seenUndone = seenUndone or not done
			end
			local nextDef = Missions.nextUp(progress, campaign.id)
			local old = if nextDef then tonumber(string.match(nextDef.id, "_(%d+)$")) else nil
			if nextDef and (old or 0) <= k then
				table.insert(bad, `{campaign.id} after {k}: next {nextDef.id}`)
			end
			if Missions.finished(progress, campaign.id) ~= (k == 10) then
				table.insert(bad, `{campaign.id} after {k}: finished`)
			end
		end
	end
	check("an old save's progress stays a run from the start, the old finale still finishes the chapter", #bad == 0, offenders(bad))
	-- Retired ratings are kept in a save but never counted.
	local save = { dispatch_1 = 3, dispatch_4 = 3, dispatch_6 = 2 }
	local got, most = Missions.stars(save, "dispatch")
	local done = Missions.done(save, "dispatch")
	check("retired ratings count nowhere (stars, done)", got == 3 and most == 18 and done == 1, `{got}/{most} {done}`)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
