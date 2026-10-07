-- Logic test of the missions (3.0, shared/Missions.luau; 6.8: told as story chapters): eleven chapters of six (ten
-- stories and the DUO one, 66 missions), every field valid against Config (cargo kinds, lendable vehicles, twists,
-- tiers) and Map.Places, the design rules (load modes, twists, finales, growing levels / tiers / rewards; the chain
-- `requires`, the computed levels, the DUO rules) and the helpers (levelOf, rate, stars, done, twistPay). The chapter
-- rules (order, locks, replays, the cast, the saves) are in tests/missions_story_test.luau.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local Map = require("./Map")
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

-- Collects the offenders of a rule: check(name, #bad == 0, list) prints the first few.
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

-- The NPC looks (shared/NpcLooks.luau roles) and the vehicles the missions may lend (Config.Cars).
local ROLES: { [string]: boolean } = {}
for _, role in NpcLooks.Roles do
	ROLES[role] = true
end
local LENDABLE = { armored = true, bus = true, monster = true, icecream = true, movingtruck = true, livestock = true, ambulance = true, fueltruck = true }
local BOARD_KINDS = { kid = true, patient = true, survivor = true }
local SERVE_KINDS = { icebox = true, pizza = true, bread = true, soup = true }
-- The places 3.0 adds (stream "missions-world" builds them in shared/Map.luau).
local NEW_PLACES = {
	"pharmacy", "market", "warehouse", "firestation", "airfield", "powerplant", "waterworks", "lab", "prison", "lighthouse",
	"trainyard", "camp", "stadium", "police", "cityhall",
}
local CHAPTER = 6 -- 6.8: missions a chapter tells

-- The chapters ------------------------------------------------------------------------

check("eleven chapters: ten stories and the DUO one", #Missions.Campaigns == 11, #Missions.Campaigns)
do
	local duo = {}
	for _, campaign in Missions.Campaigns do
		if campaign.duo then
			table.insert(duo, campaign.id)
		end
	end
	check("one DUO chapter: duo", #duo == 1 and duo[1] == "duo", table.concat(duo, ", "))
	local campaign = Missions.findCampaign("duo")
	check("the DUO chapter: Partners in Crime, level 6, after First Shift, a reward, both twins",
		campaign ~= nil and campaign.name == "Partners in Crime" and campaign.level == 6 and campaign.icon == "🤝"
			and campaign.requires ~= nil and #campaign.requires == 1 and campaign.requires[1] == "dispatch" and campaign.reward > 0
			and campaign.clientId == "rosa" and campaign.partnerId == "rico")
	check("the DUO chapter has its 3.1 reward", Config.Rewards.Campaigns.duo ~= nil)
end
do
	local ids, bad = {}, {}
	local previousLevel = 0
	for _, campaign in Missions.Campaigns do
		if ids[campaign.id] then
			table.insert(bad, "duplicate " .. campaign.id)
		end
		ids[campaign.id] = true
		if not ROLES[campaign.clientRole] then
			table.insert(bad, campaign.id .. " role " .. campaign.clientRole)
		end
		if #campaign.color ~= 3 or campaign.name == "" or campaign.client == "" or campaign.pitch == "" or campaign.icon == "" then
			table.insert(bad, campaign.id .. " incomplete")
		end
		if #campaign.pitch < 100 or #campaign.pitch > 260 then
			table.insert(bad, `{campaign.id} pitch {#campaign.pitch} chars (two or three sentences)`)
		end
		if campaign.level < previousLevel or campaign.level < 1 or campaign.level > Config.Levels.MaxLevel then
			table.insert(bad, campaign.id .. " level " .. campaign.level)
		end
		previousLevel = campaign.level
		if campaign.reward <= 0 then
			table.insert(bad, campaign.id .. " reward")
		end
		if not Config.Rewards.Campaigns[campaign.id] then
			table.insert(bad, campaign.id .. " has no finale reward (Config.Rewards.Campaigns)")
		end
	end
	check("the chapters are complete, unique, open in level order and end in a big reward", #bad == 0, offenders(bad))
end

-- The missions: ids, steps ------------------------------------------------------------

check("66 missions", #Missions.List == 66, #Missions.List)

-- The chain ---------------------------------------------------------------------------------

do
	local bad = {}
	local story: { Missions.Campaign } = {}
	for _, campaign in Missions.Campaigns do
		if not campaign.duo then
			table.insert(story, campaign)
		end
	end
	check("ten story chapters", #story == 10, #story)
	for index, campaign in story do
		local requires: { string } = campaign.requires or {}
		if index == 1 then
			if #requires ~= 0 then
				table.insert(bad, campaign.id .. " (the first) requires something")
			end
		elseif index == #story then
			-- Exodus: every other story chapter.
			if #requires ~= #story - 1 then
				table.insert(bad, `{campaign.id} requires {#requires}`)
			end
			for other = 1, #story - 1 do
				if not table.find(requires, story[other].id) then
					table.insert(bad, `{campaign.id} misses {story[other].id}`)
				end
			end
		elseif #requires ~= 1 or requires[1] ~= story[index - 1].id then
			table.insert(bad, `{campaign.id} requires {table.concat(requires, ", ")}`)
		end
	end
	-- Every required chapter exists, opens earlier (no loops) and is not the DUO one.
	local position: { [string]: number } = {}
	for index, campaign in Missions.Campaigns do
		position[campaign.id] = index
	end
	for index, campaign in Missions.Campaigns do
		for _, id in campaign.requires or {} do
			local required = Missions.findCampaign(id)
			if not required or (position[id] or math.huge) >= index or required.duo then
				table.insert(bad, `{campaign.id} → {id}`)
			end
		end
	end
	check("every story chapter requires the one before it, Exodus all nine, nothing the DUO one", #bad == 0, offenders(bad))
end
do
	local seen, names, bad = {}, {}, {}
	for _, def in Missions.List do
		if seen[def.id] then
			table.insert(bad, "duplicate id " .. def.id)
		end
		seen[def.id] = true
		if names[def.name] then
			table.insert(bad, "duplicate name " .. def.name)
		end
		names[def.name] = true
		local campaignId, number = string.match(def.id, "^(%a+)_(%d+)$")
		if campaignId ~= def.campaign or tonumber(number) == nil or (tonumber(number) :: number) > 10 or def.mission ~= def.id then
			table.insert(bad, def.id .. " id / mission")
		end
		if not Missions.findCampaign(def.campaign) then
			table.insert(bad, def.id .. " campaign " .. def.campaign)
		end
		if Missions.find(def.id) ~= def then
			table.insert(bad, def.id .. " find")
		end
	end
	check("unique ids and names, id = <campaign>_<3.0 number 1 – 10> = mission", #bad == 0, offenders(bad))
end
do
	local bad = {}
	for _, campaign in Missions.Campaigns do
		local list = Missions.ofCampaign(campaign.id)
		if #list ~= CHAPTER or Missions.size(campaign.id) ~= CHAPTER then
			table.insert(bad, `{campaign.id} has {#list}`)
		end
		local lastNumber = 0
		for n, def in list do
			if def.number ~= n then
				table.insert(bad, `{campaign.id} step {def.number} at {n}`)
			end
			-- 6.8: the 3.0 numbers keep their order (a save's progress stays a prefix of the chapter)
			local old = tonumber(string.match(def.id, "_(%d+)$")) or 0
			if old <= lastNumber then
				table.insert(bad, `{def.id} after _{lastNumber}`)
			end
			lastNumber = old
		end
		-- The chapter starts and ends where the 3.0 campaign did (its finale is still the one `requires` means).
		if list[1] and list[1].id ~= `{campaign.id}_1` and campaign.id ~= "lab" then
			table.insert(bad, `{campaign.id} starts with {list[1].id}`)
		end
		local finale = Missions.finale(campaign.id)
		if not finale or finale.id ~= `{campaign.id}_10` then
			table.insert(bad, `{campaign.id} finale {finale and finale.id}`)
		end
	end
	check("6 missions per chapter, steps 1 – 6 in their 3.0 order, the finale is _10", #bad == 0, offenders(bad))
end
-- 3.2: the DUO missions: every one duo and co-op, nothing else duo.
do
	local bad = {}
	for _, def in Missions.List do
		local campaign = Missions.findCampaign(def.campaign)
		local inDuo = campaign ~= nil and campaign.duo == true
		if inDuo ~= (def.duo == true) then
			table.insert(bad, def.id .. " duo")
		end
		if def.duo and not def.coop then
			table.insert(bad, def.id .. " duo without coop")
		end
		if def.gates ~= nil and (def.gates ~= "pickup" and def.gates ~= "drop" or not table.find(def.twists or {}, "switches")) then
			table.insert(bad, def.id .. " gates")
		end
		if def.gates == "pickup" and def.pickups < 1 then
			table.insert(bad, def.id .. " gates at no pick-up")
		end
	end
	check("the DUO missions are duo and co-op (only they), gates only with switches", #bad == 0, offenders(bad))
end

-- Every field valid --------------------------------------------------------------------------

do
	local bad = {}
	local function need(def: Missions.MissionDef, ok: boolean, what: string)
		if not ok then
			table.insert(bad, `{def.id}: {what}`)
		end
	end
	for _, def in Missions.List do
		local kind = def.itemKind
		need(def, Config.Cargo.Kinds[kind] ~= nil, "cargo kind " .. kind)
		need(def, def.load == "carry" or def.load == "lead" or def.load == "board", "load " .. def.load)
		need(def, def.unload == "carry" or def.unload == "lead" or def.unload == "board" or def.unload == "serve", "unload " .. def.unload)
		-- Horses are led, people walk, serve is street selling.
		need(def, (kind == "horse") == (def.load == "lead") and (def.load == "lead") == (def.unload == "lead"), "horse = lead")
		need(def, (BOARD_KINDS[kind] == true) == (def.load == "board") and (def.load == "board") == (def.unload == "board"), "kid / patient / survivor = board")
		need(def, def.unload ~= "serve" or (SERVE_KINDS[kind] == true and def.load == "carry"), "serve only for street food")
		need(def, kind ~= "horse" or def.vehicle == "livestock", "horses ride the livestock truck")
		need(def, def.vehicle == nil or (LENDABLE[def.vehicle] == true and Economy.findCar(def.vehicle) ~= nil), "vehicle " .. tostring(def.vehicle))
		need(def, def.employer == nil and not def.board, "not an employer's / board job")
		need(def, def.pickups >= 0 and def.pickups <= 3 and def.drops >= 1 and def.drops <= 3, "pickups 0 – 3, drops 1 – 3")
		need(def, def.pickupAt == nil or def.pickups == 1, "pickupAt only with one pick-up")
		need(def, def.items >= math.max(def.pickups, def.drops) and def.items <= 10, "items " .. def.items)
		need(def, def.tier >= 1 and def.tier <= #Config.Jobs.Tiers, "tier " .. def.tier)
		need(def, def.loadTime > 0 and def.unloadTime > 0 and def.payPerStop > 0 and def.reward > 0, "times / pay")
		need(def, def.level ~= nil and def.level >= 1 and def.level <= Config.Levels.MaxLevel, "level")
		need(def, ROLES[def.giverRole or ""] == true and ROLES[def.receiverRole or ""] == true, "roles")
		need(def, def.giver ~= "" and def.receiver ~= "" and def.cargo ~= "" and def.description ~= "", "people / cargo / description")
		need(def, #def.briefing >= 80 and #def.debrief >= 15, "briefing / debrief")
		need(def, #def.description <= 140, "a one-line description (the story path shows it)")
		need(def, string.upper(def.pickupLabel) == def.pickupLabel and string.match(def.pickupLabel, " AT$") ~= nil, "pick-up label")
		need(def, string.upper(def.dropLabel) == def.dropLabel and #def.dropLabel > 0, "drop label")
		need(def, def.banditBoost == nil or def.banditBoost > 1, "banditBoost")
		-- A rush starts near you (no far pick-up place) and does not hold a defence on the clock.
		if def.timeLimit then
			need(def, def.timeLimit >= 120 and def.pickupAt == nil and not table.find(def.twists or {}, "defend"), "rush")
		end
		-- Twists: known, 0 – 2, no repeats; defend has its time; the crew twists are co-op; lift needs carrying.
		local twists: { string } = def.twists or {}
		need(def, #twists <= 2, "at most 2 twists")
		for n, twist in twists do
			need(def, Config.Missions.Twists[twist] ~= nil, "twist " .. twist)
			need(def, table.find(twists, twist) == n, "twist twice " .. twist)
		end
		local defend = table.find(twists, "defend") ~= nil
		need(def, defend == ((def.defendTime or 0) > 0), "defend = defendTime")
		need(def, (not table.find(twists, "lift") and not table.find(twists, "gunner")) or def.coop == true, "lift / gunner are co-op")
		need(def, not table.find(twists, "lift") or def.load == "carry" or def.unload == "carry", "lift carries")
		-- 3.2: the twists made for two only on DUO missions; pair carries and is not lift too.
		local pair, switches = table.find(twists, "pair") ~= nil, table.find(twists, "switches") ~= nil
		need(def, (not pair and not switches) or def.duo == true, "pair / switches only on DUO missions")
		need(def, not pair or (def.load == "carry" or def.unload == "carry") and not table.find(twists, "lift"), "pair carries, not with lift")
	end
	check("every mission's fields are valid against Config", #bad == 0, offenders(bad))
end

-- The places: Map.Places (the 15 new ones come from stream "missions-world") -------------------

do
	local places = {}
	for _, place in Map.Places do
		places[place.id] = true
	end
	local missing = {}
	for _, id in NEW_PLACES do
		if not places[id] then
			table.insert(missing, id)
		end
	end
	check("Map.Places has the 15 mission places", #missing == 0, offenders(missing))
	local bad = {}
	for _, def in Missions.List do
		for _, at in { def.pickupAt, def.dropAt } do
			if at and not places[at] then
				table.insert(bad, `{def.id} → {at}`)
			end
		end
	end
	check("every pickupAt / dropAt is a Map.Places id", #bad == 0, offenders(bad))
	local used = {}
	for _, def in Missions.List do
		used[def.pickupAt or ""] = true
		used[def.dropAt or ""] = true
	end
	local unused = {}
	for _, id in NEW_PLACES do
		if not used[id] then
			table.insert(unused, id)
		end
	end
	check("every mission place has a mission", #unused == 0, offenders(unused))
end

-- Variety --------------------------------------------------------------------------------------

do
	local kinds, vehicles, modes, unused = {}, {}, {}, {}
	local rushes, loaded, boosted = 0, 0, 0
	for _, def in Missions.List do
		kinds[def.itemKind] = true
		vehicles[def.vehicle or "own"] = true
		modes[def.unload] = true
		rushes += if def.timeLimit then 1 else 0
		loaded += if def.pickups == 0 then 1 else 0
		boosted += if def.banditBoost then 1 else 0
	end
	-- 6.8: a kind no chapter needs is fine when a special job carries it (the pizza: the Pizza Rush).
	for _, jobType in Config.JobTypes do
		kinds[jobType.itemKind] = true
	end
	for kind in Config.Cargo.Kinds do
		if not kinds[kind] and kind ~= "pallet" then -- (4.0: the pallets are the Freight Run's, not a mission's)
			table.insert(unused, kind)
		end
	end
	check("every cargo kind is used (a mission or a special job)", #unused == 0, offenders(unused))
	local vehicleCount = 0
	for _ in vehicles do
		vehicleCount += 1
	end
	check("every lendable vehicle and your own car", vehicleCount == 9, vehicleCount)
	check("all four load modes", modes.carry and modes.lead and modes.board and modes.serve or false)
	check("rushes", rushes >= 4, rushes)
	check("a vehicle that starts loaded, but rarely", loaded >= 1 and loaded <= 4, loaded)
	check("cargo the bandits want", boosted >= 3, boosted)
end

-- The design rules: co-op, twists, finales, growth --------------------------------------------

do
	local coop, bad = 0, {}
	for _, campaign in Missions.Campaigns do
		local count = 0
		for _, def in Missions.ofCampaign(campaign.id) do
			count += if def.coop then 1 else 0
		end
		coop += count
		if count < 1 then
			table.insert(bad, `{campaign.id}: {count}`)
		end
	end
	check("every chapter has a co-op mission", #bad == 0, offenders(bad))
	check("25+ co-op missions", coop >= 25, coop)
end
do
	local counts: { [string]: number } = {}
	for twist in Config.Missions.Twists do
		counts[twist] = 0
	end
	for _, def in Missions.List do
		for _, twist in def.twists or {} do
			counts[twist] = (counts[twist] or 0) + 1
		end
	end
	local bad = {}
	for twist, count in counts do
		if count < 3 then
			table.insert(bad, `{twist} {count}`)
		end
	end
	check("every twist is used at least 3 times", #bad == 0, offenders(bad))
	local mixed: { [string]: boolean } = {}
	for _, def in Missions.ofCampaign("duo") do
		for _, twist in def.twists or {} do
			mixed[twist] = true
		end
	end
	local missing = {}
	for _, twist in { "pair", "switches", "gunner", "hunted" } do
		if not mixed[twist] then
			table.insert(missing, twist)
		end
	end
	check("the DUO chapter: pair, switches, gunner, hunted", #missing == 0, offenders(missing))
	-- 6.8: only the next mission starts, so a NIGHT ONLY one makes the chapter wait for dark: a few, never a first.
	check("night at most 4 times", counts.night <= 4, counts.night)
	local nightFirst = {}
	for _, campaign in Missions.Campaigns do
		local first = Missions.ofCampaign(campaign.id)[1]
		if first and table.find(first.twists or {}, "night") then
			table.insert(nightFirst, first.id)
		end
	end
	check("no chapter opens with a NIGHT ONLY mission", #nightFirst == 0, offenders(nightFirst))
end
do
	local bad = {}
	for _, campaign in Missions.Campaigns do
		local list = Missions.ofCampaign(campaign.id)
		local finale = list[#list]
		if finale then
			local twists: { string } = finale.twists or {}
			if #twists ~= 2 or finale.pickups + finale.drops < 3 then
				table.insert(bad, finale.id .. " finale")
			end
			if (finale.level or 0) ~= Missions.levelOf(campaign.id, #list) or finale.tier < 3 then
				table.insert(bad, finale.id .. " finale level / tier")
			end
			if finale.reward < 2 * list[1].reward then
				table.insert(bad, finale.id .. " finale reward")
			end
		end
		local first = list[1]
		if first and ((first.level or 0) ~= campaign.level or first.tier > 2) then
			table.insert(bad, first.id .. " opening level / tier")
		end
		for n = 2, #list do
			local before, def = list[n - 1], list[n]
			if (def.level or 0) < (before.level or 0) or (def.level or 0) > Missions.levelOf(campaign.id, #list) then
				table.insert(bad, def.id .. " level")
			end
			if def.tier < before.tier then
				table.insert(bad, def.id .. " tier")
			end
			if def.reward <= before.reward then
				table.insert(bad, def.id .. " reward")
			end
		end
	end
	check("finales: 2 twists, multi-stop, the top level, tier 3 – 4, the biggest reward; levels, tiers, rewards grow", #bad == 0, offenders(bad))
	-- The levels grow inside a chapter up to the next story chapter's level (MaxLevel after the last; the DUO chapter
	-- 4 levels): the chapter's own level until the finale (6.8: rounded down).
	local spans = {}
	local story: { Missions.Campaign } = {}
	for _, campaign in Missions.Campaigns do
		if not campaign.duo then
			table.insert(story, campaign)
		end
	end
	for index, campaign in story do
		local following = story[index + 1]
		local top = if following then following.level else Config.Levels.MaxLevel
		local list = Missions.ofCampaign(campaign.id)
		if list[1].level ~= campaign.level or list[#list].level ~= top then
			table.insert(spans, `{campaign.id} {list[1].level} … {list[#list].level}`)
		end
	end
	local duo = Missions.ofCampaign("duo")
	if duo[1].level ~= 6 or duo[#duo].level ~= 10 then
		table.insert(spans, `duo {duo[1].level} … {duo[#duo].level}`)
	end
	check("the levels grow from the chapter's to the next one's", #spans == 0, offenders(spans))
	check("levelOf: First Shift 4 … 4, the finale 5; Smoke and Sirens 7 → 9", Missions.levelOf("dispatch", 1) == 4 and Missions.levelOf("dispatch", 5) == 4
		and Missions.levelOf("dispatch", 6) == 5 and Missions.levelOf("firehouse", 1) == 7 and Missions.levelOf("firehouse", 4) == 8 and Missions.levelOf("firehouse", 6) == 9)
	local last = story[#story]
	check("the last chapter ends at the top level", Missions.levelOf(last.id, Missions.size(last.id)) == Config.Levels.MaxLevel)
	local first = Missions.find("dispatch_1")
	local finale = Missions.find("exodus_10")
	check("first-time rewards from 400 to 10,000+", first ~= nil and first.reward == 400 and finale ~= nil and finale.reward >= 10000)
end

-- The helpers ----------------------------------------------------------------------------------

do
	local tuning = Config.Missions
	check("rate: perfect = 3 stars", Missions.rate(1, 1) == 3)
	check("rate: damaged cargo = 1 star", Missions.rate(tuning.TwoStarCondition - 0.01, 1) == 1)
	check("rate: good cargo, late = 2 stars", Missions.rate(0.9, tuning.ThreeStarTime - 0.01) == 2)
	check("rate: on the thresholds = 3 stars", Missions.rate(tuning.TwoStarCondition, tuning.ThreeStarTime) == 3)
	check("rate: wrecked cargo with time left = 1 star", Missions.rate(0, 1) == 1)
	local got, most = Missions.stars({ dispatch_1 = 3, dispatch_2 = 2, clinic_1 = 5 })
	check("stars: total, capped at 3 each, of 198 (3 a mission)", got == 8 and most == 3 * #Missions.List and most == 198, `{got}/{most}`)
	got, most = Missions.stars({ dispatch_1 = 3, clinic_1 = 1 }, "dispatch")
	check("stars of one chapter", got == 3 and most == 18, `{got}/{most}`)
	got, most = Missions.stars({ duo_1 = 3, dispatch_1 = 2 }, nil, true)
	check("stars of the story (the DUO chapter left out)", got == 2 and most == 180, `{got}/{most}`)
	local done, total = Missions.done({ dispatch_1 = 1, dispatch_2 = 3, clinic_1 = 2, dispatch_4 = 3 }, "dispatch")
	check("done of a chapter (a retired id does not count)", done == 2 and total == 6, `{done}/{total}`)
	done, total = Missions.doneCount({ dispatch_1 = 1, duo_1 = 2, dispatch_4 = 3 }, true)
	check("doneCount of the story", done == 1 and total == 60, `{done}/{total}`)
	local plain = Missions.find("dispatch_1")
	local finale = Missions.find("dispatch_10")
	check("twistPay: none = 1", plain ~= nil and Missions.twistPay(plain) == 1)
	if finale then
		local expected = 1
		for _, twist in finale.twists or {} do
			expected *= Config.Missions.Twists[twist].pay
		end
		check("twistPay: the product of the twists", math.abs(Missions.twistPay(finale) - expected) < 1e-9 and expected > 1)
	end
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
