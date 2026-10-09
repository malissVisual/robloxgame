-- Logic test of 6.14, the regulars (shared/Regulars.luau, Config.Regulars): the tiers (a long, visible grind), the
-- businesses (the job pictures' 25: shared/JobThumbs.luau), which business a delivery counts for (never a mission),
-- a save checked, a delivery counted (the tier reached), a job row's badge, the REGULARS app's view (every business, met
-- or not, sorted), the toast's words and where a REGULAR'S ORDER may come from.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local JobThumbs = require("./JobThumbs")
local Regulars = require("./Regulars")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Tiers = Config.Regulars.Tiers

-- ── The tiers ────────────────────────────────────────────────────────────────
do
	local bad = {}
	local seen: { [string]: boolean } = {}
	for index, tier in Tiers do
		if seen[tier.id] or tier.id == "" or tier.name == "" or tier.icon == "" then
			table.insert(bad, `{index}: id / name / icon`)
		end
		seen[tier.id] = true
		local before = Tiers[index - 1]
		if before and not (tier.at > before.at and tier.bonus > before.bonus) then
			table.insert(bad, `{tier.id}: not above {before.id}`)
		end
		if tier.at ~= math.floor(tier.at) or tier.at < 1 or tier.bonus <= 0 or tier.bonus > 0.25 then
			table.insert(bad, `{tier.id}: at {tier.at}, bonus {tier.bonus}`)
		end
	end
	check("the tiers: unique, each higher and better paid than the one before, a bonus of at most 25 %", #bad == 0 and #Tiers >= 3, table.concat(bad, ", "))
	check("Bronze at 5 (+5 %), Silver at 15 (+10 %), Gold at 40 (+15 %)", Tiers[1].id == "bronze" and Tiers[1].at == 5 and Tiers[1].bonus == 0.05
		and Tiers[2].id == "silver" and Tiers[2].at == 15 and Tiers[2].bonus == 0.1 and Tiers[3].id == "gold" and Tiers[3].at == 40 and Tiers[3].bonus == 0.15)
	check("a long, visible grind: the top tier needs at least 80 deliveries for one business", Tiers[#Tiers].at >= 80, Tiers[#Tiers].at)
	check("the cap is far above the top tier", Config.Regulars.Cap >= Tiers[#Tiers].at * 100)
	check("a REGULAR'S ORDER needs a tier there is (Silver)", Tiers[Config.Regulars.Order.Tier] ~= nil and Tiers[Config.Regulars.Order.Tier].id == "silver")
	local order = Config.Regulars.Order
	check("a REGULAR'S ORDER pays more, rarely, for a few minutes", order.Pay > 1 and order.Pay < 3 and order.Chance > 0 and order.Chance < 1 and order.Seconds >= 60 and order.Seconds <= 900 and order.Every >= 30 and order.Xp >= 1)
end

-- ── tierOf, bonusOf, nextOf, progress ────────────────────────────────────────
do
	local tier, index = Regulars.tierOf(0)
	check("0 deliveries: no tier", tier == nil and index == 0 and Regulars.bonusOf(0) == 0)
	tier, index = Regulars.tierOf(4)
	check("4: still none", tier == nil and index == 0)
	tier, index = Regulars.tierOf(5)
	check("5: Bronze, +5 %", tier ~= nil and tier.id == "bronze" and index == 1 and Regulars.bonusOf(5) == 0.05)
	tier = Regulars.tierOf(14)
	check("14: Bronze", tier ~= nil and tier.id == "bronze")
	tier, index = Regulars.tierOf(15)
	check("15: Silver, +10 %", tier ~= nil and tier.id == "silver" and index == 2 and Regulars.bonusOf(15) == 0.1)
	tier = Regulars.tierOf(40)
	check("40: Gold, +15 %", tier ~= nil and tier.id == "gold" and Regulars.bonusOf(40) == 0.15)
	tier, index = Regulars.tierOf(100000)
	check("a huge count: the top tier", tier ~= nil and index == #Tiers)
	local nextTier, toGo = Regulars.nextOf(0)
	check("next from 0: Bronze in 5", nextTier ~= nil and nextTier.id == "bronze" and toGo == 5)
	nextTier, toGo = Regulars.nextOf(12)
	check("next from 12: Silver in 3", nextTier ~= nil and nextTier.id == "silver" and toGo == 3)
	nextTier, toGo = Regulars.nextOf(Tiers[#Tiers].at)
	check("at the top: nothing next", nextTier == nil and toGo == 0)
	check("progress: 0 at 0, half way from Bronze to Silver at 10, 1 at the top",
		Regulars.progress(0) == 0 and math.abs(Regulars.progress(10) - 0.5) < 1e-9 and Regulars.progress(Tiers[#Tiers].at + 5) == 1)
	check("progress starts again at each tier", Regulars.progress(15) == 0 and Regulars.progress(5) == 0)
	check("percent: 0.1 → 10, 0.15 → 15", Regulars.percent(0.1) == 10 and Regulars.percent(0.15) == 15)
end

-- ── The businesses ───────────────────────────────────────────────────────────
do
	local ids = Regulars.ids()
	local count = 0
	for _ in JobThumbs.Assets do
		count += 1
	end
	check("every job picture's business is a business (25)", #ids == count and count == 25, #ids)
	local sorted = true
	for index = 2, #ids do
		sorted = sorted and Regulars.nameOf(ids[index - 1]) < Regulars.nameOf(ids[index])
	end
	check("by name", sorted)
	check("its name and emoji: Luigi's Pizza 🍕", Regulars.nameOf("pizzeria") == "Luigi's Pizza" and Regulars.emojiOf("pizzeria") == "🍕")
	local bad = {}
	for _, id in ids do
		if JobThumbs.assetFor(Regulars.infoOf(id)) ~= id then
			table.insert(bad, id)
		end
	end
	check("infoOf: every business's picture (the REGULARS app draws it with client/JobThumbUi.luau)", #bad == 0, table.concat(bad, ", "))
end

-- ── Which business a delivery counts for ─────────────────────────────────────
do
	check("an ordinary delivery: its business", Regulars.businessOf({ business = "pizzeria" }) == "pizzeria")
	check("shared pictures share the business: the lab's samples, the bakery's cakes", Regulars.businessOf({ business = "samples" }) == "lab" and Regulars.businessOf({ business = "cake" }) == "bakery")
	check("an employer's job: its workplace (the Ambulance Run: the City Clinic)", Regulars.businessOf({ jobType = { id = "ambulance" } }) == "clinic")
	check("a board special: the Pizza Rush counts for Luigi's", Regulars.businessOf({ jobType = { id = "pizzarush" } }) == "pizzeria")
	check("a board row's special (its id)", Regulars.businessOf({ special = "schoolrun" }) == "school")
	check("the paper round: The Daily Undead; the tutorial's letters: the Post Office", Regulars.businessOf({ round = true }) == "news" and Regulars.businessOf({ tutorial = true }) == "post")
	check("a mission never counts", Regulars.businessOf({ mission = "m1", business = "pizzeria" }) == nil and Regulars.businessOf({ mission = { id = "m1" }, jobType = { id = "ambulance" } }) == nil)
	check("nothing known: none", Regulars.businessOf({}) == nil and Regulars.businessOf(nil) == nil and Regulars.businessOf({ business = "nowhere" }) == nil)
end

-- ── A save checked ───────────────────────────────────────────────────────────
do
	local cleaned = Regulars.clean({ pizzeria = 12.7, clinic = 3, nowhere = 5, bakery = -2, lab = 0, post = 0 / 0, bank = "9", farm = math.huge, [5] = 4 })
	check("known businesses, whole counts, nothing else", cleaned.pizzeria == 12 and cleaned.clinic == 3 and cleaned.nowhere == nil and cleaned.bakery == nil
		and cleaned.lab == nil and cleaned.post == nil and cleaned.bank == nil and (cleaned :: any)[5] == nil)
	check("a count kept under the cap", cleaned.farm == Config.Regulars.Cap)
	check("an old save without one (or junk): empty", next(Regulars.clean(nil)) == nil and next(Regulars.clean("x")) == nil and next(Regulars.clean({})) == nil)
end

-- ── A delivery counted ───────────────────────────────────────────────────────
do
	local mine: { [string]: number } = {}
	local before, after, reached = Regulars.add(mine, "pizzeria")
	check("the first delivery: met (1), no tier yet", before == 0 and after == 1 and reached == nil and mine.pizzeria == 1)
	for _ = 1, 3 do
		Regulars.add(mine, "pizzeria")
	end
	before, after, reached = Regulars.add(mine, "pizzeria")
	check("the fifth: Bronze reached now", before == 4 and after == 5 and reached ~= nil and reached.id == "bronze")
	_, _, reached = Regulars.add(mine, "pizzeria")
	check("the sixth: no new tier", reached == nil and mine.pizzeria == 6)
	_, after, reached = Regulars.add(mine, "pizzeria", 9)
	check("nine more at once: Silver", after == 15 and reached ~= nil and reached.id == "silver")
	before, after = Regulars.add(mine, "nowhere")
	check("an unknown business: nothing counted", before == 0 and after == 0 and mine.nowhere == nil)
	local full: { [string]: number } = { clinic = Config.Regulars.Cap }
	_, after = Regulars.add(full, "clinic")
	check("never past the cap", after == Config.Regulars.Cap)
	check("the toast's words", Regulars.tierUpText("pizzeria", Tiers[2]) == "Luigi's Pizza: you're a SILVER regular · +10% pay")
end

-- ── A job row's badge ────────────────────────────────────────────────────────
do
	local counts = { pizzeria = 3, clinic = 15, lab = 40 }
	check("never met: no badge", Regulars.badge(counts, { business = "post" }) == nil and Regulars.badge(nil, { business = "pizzeria" }) == nil)
	local text, tier = Regulars.badge(counts, { business = "pizzeria" })
	check("met, no tier: the way to Bronze", text == "🤝 3/5 TO BRONZE" and tier == "", text)
	text, tier = Regulars.badge(counts, { jobType = { id = "ambulance" } })
	check("Silver at the City Clinic (the Ambulance Run)", text == "🥈 SILVER REGULAR +10%" and tier == "silver", text)
	text, tier = Regulars.badge(counts, { business = "samples" })
	check("Gold at the lab (its samples)", text == "🥇 GOLD REGULAR +15%" and tier == "gold", text)
	check("a mission: no badge", Regulars.badge(counts, { mission = "m1", business = "pizzeria" }) == nil)
end

-- ── The REGULARS app's view ──────────────────────────────────────────────────
do
	local view = Regulars.view({ pizzeria = 3, clinic = 15, lab = 40, post = 15, bank = 1 })
	check("every business, met or not", #view.list == 25 and view.total == 25 and view.met == 5, `{#view.list} {view.met}`)
	local order = {}
	for index = 1, 5 do
		table.insert(order, view.list[index].id)
	end
	check("the highest tier first, then the most deliveries, then by name", table.concat(order, ",") == "lab,clinic,post,pizzeria,bank", table.concat(order, ","))
	local unmet = view.list[6]
	check("then the ones never met, by name", not unmet.met and unmet.count == 0 and unmet.rank == 0 and unmet.tier == nil and unmet.nextName == "Bronze" and unmet.toGo == 5)
	local sorted = true
	for index = 7, #view.list do
		sorted = sorted and not view.list[index].met and view.list[index - 1].name < view.list[index].name
	end
	check("… all of them", sorted)
	local lab = view.list[1]
	check("a card: its tier, medal, bonus, the next tier and the progress", lab.tier == "gold" and lab.icon == "🥇" and lab.bonus == 0.15 and lab.nextName == Tiers[4].name
		and lab.toGo == Tiers[4].at - 40 and lab.progress == 0 and lab.name == "Research Lab")
	check("the tiers held", view.tiers.gold == 1 and view.tiers.silver == 2 and view.tiers.bronze == nil)
	check("no counts yet: nobody met", Regulars.view(nil).met == 0 and #Regulars.view({}).list == 25)
end

-- ── Where a REGULAR'S ORDER may come from ────────────────────────────────────
do
	local pizza = Regulars.ordinaryOf("pizzeria")
	check("Luigi's sends the pizzas", pizza.pizzeria == true and next(pizza, "pizzeria") == nil)
	local lab = Regulars.ordinaryOf("lab")
	check("the lab sends its vaccines and its samples", lab.lab == true and lab.samples == true)
	check("a workplace without board deliveries: none (the school)", next(Regulars.ordinaryOf("school")) == nil)
	local known: { [string]: boolean } = {}
	for _, def in Config.Jobs.Businesses do
		known[def.id] = true
	end
	local bad = {}
	for _, id in Regulars.ids() do
		for business in Regulars.ordinaryOf(id) do
			if not known[business] then
				table.insert(bad, business)
			end
		end
	end
	check("every one is a Config.Jobs.Businesses delivery", #bad == 0, table.concat(bad, ", "))
	local orderable = Regulars.orderable({ pizzeria = 15, clinic = 40, lab = 14, post = 100 })
	check("only Silver or better, and only where the board has deliveries (not the clinic)", table.concat(orderable, ",") == "pizzeria,post", table.concat(orderable, ","))
	check("none without a Silver", #Regulars.orderable({ pizzeria = 14 }) == 0 and #Regulars.orderable(nil) == 0)
end

-- ── The daily tasks (6.14) ───────────────────────────────────────────────────
do
	local regular, golden = nil, nil
	for _, def in Config.Tasks.DailyPool do
		if def.event == "regular" then
			regular = def
		elseif def.event == "golden" then
			golden = def
		end
	end
	check("a daily: deliver where you're a regular", regular ~= nil and (regular.level or 1) >= 2)
	check("a daily: finish a golden order (from the golden orders' level)", golden ~= nil and (golden.level or 1) >= Config.Jobs.Golden.Level and golden.target[2] == 1)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
