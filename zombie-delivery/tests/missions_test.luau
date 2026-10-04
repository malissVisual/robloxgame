-- Logic test of the missions (3.0, shared/Missions.luau): the ten campaigns of ten missions, every field valid against
-- Config (cargo kinds, lendable vehicles, twists, tiers) and Map.Places, the design rules of the spec (load modes,
-- co-op count, twist counts, finales, growing levels / tiers / rewards) and the helpers (unlocked, rate, stars, done,
-- twistPay).
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Economy = require("./Economy")
local Map = require("./Map")
local Missions = require("./Missions")

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

-- The NPC looks (server/Npcs.luau roles) and the vehicles the missions may lend (Config.Cars).
local ROLES = {
	attendant = true, banker = true, clerk = true, cook = true, doctor = true, farmer = true, foreman = true, grocer = true,
	guard = true, icecream = true, kid = true, mover = true, nurse = true, officer = true, patient = true, rancher = true,
	rider = true, shopkeeper = true, soldier = true, teacher = true, townsperson = true, worker = true,
}
local LENDABLE = { armored = true, bus = true, monster = true, icecream = true, movingtruck = true, livestock = true, ambulance = true, fueltruck = true }
local BOARD_KINDS = { kid = true, patient = true, survivor = true }
local SERVE_KINDS = { icebox = true, pizza = true, bread = true, soup = true }
-- The places 3.0 adds (stream "missions-world" builds them in shared/Map.luau).
local NEW_PLACES = {
	"pharmacy", "market", "warehouse", "firestation", "airfield", "powerplant", "waterworks", "lab", "prison", "lighthouse",
	"trainyard", "camp", "stadium", "police", "cityhall",
}

-- The campaigns ------------------------------------------------------------------------

check("ten campaigns", #Missions.Campaigns == 10, #Missions.Campaigns)
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
		if campaign.level < previousLevel or campaign.level < 1 or campaign.level > Config.Levels.MaxLevel then
			table.insert(bad, campaign.id .. " level " .. campaign.level)
		end
		previousLevel = campaign.level
		if campaign.reward <= 0 then
			table.insert(bad, campaign.id .. " reward")
		end
	end
	check("the campaigns are complete, unique and open in level order", #bad == 0, offenders(bad))
end

-- The missions: ids, numbering ------------------------------------------------------------

check("100 missions", #Missions.List == 100, #Missions.List)
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
		if def.id ~= `{def.campaign}_{def.number}` or def.mission ~= def.id then
			table.insert(bad, def.id .. " id / mission")
		end
		if not Missions.findCampaign(def.campaign) then
			table.insert(bad, def.id .. " campaign " .. def.campaign)
		end
		if Missions.find(def.id) ~= def then
			table.insert(bad, def.id .. " find")
		end
	end
	check("unique ids and names, id = <campaign>_<number> = mission", #bad == 0, offenders(bad))
end
do
	local bad = {}
	for _, campaign in Missions.Campaigns do
		local list = Missions.ofCampaign(campaign.id)
		if #list ~= 10 then
			table.insert(bad, `{campaign.id} has {#list}`)
		end
		for n, def in list do
			if def.number ~= n then
				table.insert(bad, `{campaign.id} number {def.number} at {n}`)
			end
		end
	end
	check("10 missions per campaign, numbered 1 – 10", #bad == 0, offenders(bad))
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
	check("Map.Places has the 15 new mission places", #missing == 0,
		if #missing > 0 then "missing " .. table.concat(missing, ", ") .. " — expected until stream missions-world (shared/Map.luau) lands" else nil)
	local bad = {}
	for _, def in Missions.List do
		for _, at in { def.pickupAt, def.dropAt } do
			if at and not places[at] then
				table.insert(bad, `{def.id} → {at}`)
			end
		end
	end
	check("every pickupAt / dropAt is a Map.Places id", #bad == 0,
		if #bad > 0 then (offenders(bad) or "") .. " — the new places come with stream missions-world (shared/Map.luau)" else nil)
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
	check("every new place has a mission", #unused == 0, offenders(unused))
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
	for kind in Config.Cargo.Kinds do
		if not kinds[kind] then
			table.insert(unused, kind)
		end
	end
	check("every cargo kind is used", #unused == 0, offenders(unused))
	local vehicleCount = 0
	for _ in vehicles do
		vehicleCount += 1
	end
	check("every lendable vehicle and your own car", vehicleCount == 9, vehicleCount)
	check("all four load modes", modes.carry and modes.lead and modes.board and modes.serve or false)
	check("rushes", rushes >= 6, rushes)
	check("a vehicle that starts loaded, but rarely", loaded >= 1 and loaded <= 5, loaded)
	check("cargo the bandits want", boosted >= 4, boosted)
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
		if count < 3 then
			table.insert(bad, `{campaign.id}: {count}`)
		end
	end
	check("at least 3 co-op missions per campaign", #bad == 0, offenders(bad))
	check("30+ co-op missions", coop >= 30, coop)
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
		if count < 6 then
			table.insert(bad, `{twist} {count}`)
		end
	end
	check("every twist is used at least 6 times", #bad == 0, offenders(bad))
	check("night at most 10 times", counts.night <= 10, counts.night)
end
do
	local bad = {}
	for _, campaign in Missions.Campaigns do
		local list = Missions.ofCampaign(campaign.id)
		local finale = list[10]
		if finale then
			local twists: { string } = finale.twists or {}
			if #twists ~= 2 or finale.pickups + finale.drops < 3 then
				table.insert(bad, finale.id .. " finale")
			end
			if (finale.level or 0) ~= campaign.level + 2 or finale.tier < 3 then
				table.insert(bad, finale.id .. " finale level / tier")
			end
		end
		local first = list[1]
		if first and ((first.level or 0) ~= campaign.level or first.tier > 2) then
			table.insert(bad, first.id .. " opening level / tier")
		end
		for n = 2, #list do
			local before, def = list[n - 1], list[n]
			if (def.level or 0) < (before.level or 0) or (def.level or 0) > campaign.level + 2 then
				table.insert(bad, def.id .. " level")
			end
			if def.tier < before.tier then
				table.insert(bad, def.id .. " tier")
			end
			if def.reward < before.reward then
				table.insert(bad, def.id .. " reward")
			end
		end
	end
	check("finales: 2 twists, multi-stop, level +2, tier 3 – 4", #bad == 0, offenders(bad))
	local first = Missions.find("dispatch_1")
	local last = Missions.find("exodus_10")
	check("rewards from 300 to 8000+", first ~= nil and first.reward == 300 and last ~= nil and last.reward >= 8000)
end

-- The helpers ----------------------------------------------------------------------------------

do
	local none: { [string]: number } = {}
	local open, why = Missions.unlocked("dispatch_1", none, 1)
	check("the first mission is open at level 1", open and why == nil)
	open, why = Missions.unlocked("dispatch_2", none, 15)
	check("the next one waits for the one before", not open and why ~= nil)
	open = Missions.unlocked("dispatch_2", { dispatch_1 = 1 }, 1)
	check("… and opens when it is done", open)
	open, why = Missions.unlocked("clinic_1", none, 1)
	check("a campaign above your level is locked, saying why", not open and why ~= nil and string.find(why or "", "level") ~= nil, why)
	open = Missions.unlocked("clinic_1", none, 2)
	check("… and opens at its level", open)
	local clinic4 = Missions.find("clinic_4")
	if clinic4 and clinic4.level and clinic4.level > 2 then
		open = Missions.unlocked("clinic_4", { clinic_3 = 2 }, clinic4.level - 1)
		check("a mission above your level is locked", not open)
	end
	open, why = Missions.unlocked("nope_1", none, 15)
	check("an unknown mission is refused", not open and why ~= nil)
end
do
	local tuning = Config.Missions
	check("rate: perfect = 3 stars", Missions.rate(1, 1) == 3)
	check("rate: damaged cargo = 1 star", Missions.rate(tuning.TwoStarCondition - 0.01, 1) == 1)
	check("rate: good cargo, late = 2 stars", Missions.rate(0.9, tuning.ThreeStarTime - 0.01) == 2)
	check("rate: on the thresholds = 3 stars", Missions.rate(tuning.TwoStarCondition, tuning.ThreeStarTime) == 3)
	check("rate: wrecked cargo with time left = 1 star", Missions.rate(0, 1) == 1)
	local got, most = Missions.stars({ dispatch_1 = 3, dispatch_2 = 2, clinic_1 = 5 })
	check("stars: total, capped at 3 each, of 300", got == 8 and most == 300, `{got}/{most}`)
	got, most = Missions.stars({ dispatch_1 = 3, clinic_1 = 1 }, "dispatch")
	check("stars of one campaign", got == 3 and most == 30, `{got}/{most}`)
	local done, total = Missions.done({ dispatch_1 = 1, dispatch_2 = 3, clinic_1 = 2 }, "dispatch")
	check("done of a campaign", done == 2 and total == 10, `{done}/{total}`)
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
