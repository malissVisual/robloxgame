-- Logic test of 4.8: shared/JobRules.luau's cargo with rules (fragile, food, heavy, cash, people; the jolts, the
-- freshness, the Ratchet Straps and the Cooler Box), the multi-drop deliveries and the road events, with their numbers
-- in Config.Jobs (CargoRules, MultiDrop, RoadEvents) and Config.GearTuning.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local JobRules = require("./JobRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

local Rules = Config.Jobs.CargoRules
local Gear = Config.GearTuning

-- Which cargo has which rules -----------------------------------------------------------------

local function same(list: { string }, expected: { string }): boolean
	if #list ~= #expected then
		return false
	end
	for index, rule in expected do
		if list[index] ~= rule then
			return false
		end
	end
	return true
end

check("pizza is food", same(JobRules.cargoRules("crate", "pizza", "pizzeria"), { "food" }))
check("a wedding cake is fragile food", same(JobRules.cargoRules("crate", "cake", "cake"), { "fragile", "food" }))
check("vaccine is fragile", same(JobRules.cargoRules("icebox", "vaccine", "lab"), { "fragile" }))
check("the electronics store's parts (the parcel look) are fragile", same(JobRules.cargoRules("crate", "parcel", "electronics"), { "fragile" }))
check("the post office's parcels have no rules", #JobRules.cargoRules("crate", "parcel", "post") == 0)
check("fuel barrels are heavy", same(JobRules.cargoRules("barrel", "barrel", "warehouse"), { "heavy" }))
check("the bank's strongboxes are heavy cash", same(JobRules.cargoRules("crate", "gold", "bank"), { "heavy", "cash" }))
check("the Cash Transport's sacks are cash (not heavy)", same(JobRules.cargoRules("cash", "gold", nil), { "cash" }))
check("kids, patients and survivors are passengers", same(JobRules.cargoRules("kid", "kid", nil), { "people" })
	and same(JobRules.cargoRules("patient", "patient", nil), { "people" }) and same(JobRules.cargoRules("survivor", "survivor", nil), { "people" }))
check("nothing given: no rules", #JobRules.cargoRules(nil, nil, nil) == 0)
check("hasRule", JobRules.hasRule({ "food" }, "food") and not JobRules.hasRule({ "food" }, "heavy") and not JobRules.hasRule(nil, "food"))

-- Every rule a look or a kind names is one the game knows, and every business's rules are known.
local known = true
for _, map in { Rules.Looks, Rules.Kinds, Rules.Businesses } do
	for _, list in map do
		for _, rule in list do
			if not JobRules.ruleInfo(rule) then
				known = false
			end
		end
	end
end
check("every rule in Config has its words", known)
local businessIds: { [string]: boolean } = {}
for _, business in Config.Jobs.Businesses do
	businessIds[business.id] = true
end
local businessesExist = true
for id in Rules.Businesses do
	if not businessIds[id] then
		businessesExist = false
	end
end
check("every CargoRules business exists", businessesExist)
local someFood, someFragile, someHeavy, someCash = false, false, false, false
for _, business in Config.Jobs.Businesses do
	local rules = JobRules.cargoRules(business.kind, business.look, business.id)
	someFood = someFood or JobRules.hasRule(rules, "food")
	someFragile = someFragile or JobRules.hasRule(rules, "fragile")
	someHeavy = someHeavy or JobRules.hasRule(rules, "heavy")
	someCash = someCash or JobRules.hasRule(rules, "cash")
end
check("the board has food, fragile, heavy and cash deliveries", someFood and someFragile and someHeavy and someCash)

check("the board's rules line", (JobRules.rulesText({ "fragile", "food" }) or ""):find("FRAGILE", 1, true) ~= nil and JobRules.rulesText({}) == nil)
check("the contract line: freshness first", JobRules.ruleLine({ "food" }, 0.824, false) == "Fresh 82%")
check("the contract line: with the cooler", JobRules.ruleLine({ "fragile", "food" }, 1, true) == "Fragile: brake gently · Fresh 100% (cooler)")
check("no rules: no contract line", JobRules.ruleLine({}, 1, false) == nil and JobRules.ruleLine(nil, nil, nil) == nil)

-- The jolts ---------------------------------------------------------------------------------

check("cruising is no jolt", JobRules.jolt(50, 49, 0.2) == nil)
check("coasting is no jolt", JobRules.jolt(50, 46, 0.2) == nil)
check("an Old Van's full brake is no jolt", JobRules.jolt(40, 40 - 28 * 0.2, 0.2) == nil)
check("hard braking from speed", JobRules.jolt(60, 60 - 75 * 0.2, 0.2) == "brake")
check("braking from a crawl is no jolt", JobRules.jolt(Rules.BrakeSpeed - 5, 0, 0.2) == nil)
check("a wall is a bump", JobRules.jolt(50, 5, 0.2) == "bump")
check("speeding up is no jolt", JobRules.jolt(10, 40, 0.2) == nil)
check("no time: no jolt", JobRules.jolt(50, 0, 0) == nil)

check("a fragile cargo: brake", near(JobRules.joltLoss({ "fragile" }, "brake", false), Rules.FragileBrake))
check("a fragile cargo: bump", near(JobRules.joltLoss({ "fragile" }, "bump", false), Rules.FragileBump))
check("passengers mind bumps only", near(JobRules.joltLoss({ "people" }, "bump", false), Rules.PeopleBump) and JobRules.joltLoss({ "people" }, "brake", false) == 0)
check("food minds no jolts", JobRules.joltLoss({ "food" }, "bump", false) == 0)
check("no jolt, no loss", JobRules.joltLoss({ "fragile" }, nil, false) == 0)
check("Ratchet Straps cut a jolt", near(JobRules.joltLoss({ "fragile" }, "bump", true), Rules.FragileBump * Gear.StrapsLoss))
check("straps are 0.6", Gear.StrapsLoss == 0.6 and Gear.CoolerDrain == 0.5)

check("a hit: the usual loss", near(JobRules.damageLoss({}, 0.1, 50, false), 0.1))
check("a hit on fragile cargo at speed costs more", near(JobRules.damageLoss({ "fragile" }, 0.1, Rules.HitSpeed + 1, false), 0.1 + Rules.FragileHit))
check("a hit on fragile cargo standing: the usual", near(JobRules.damageLoss({ "fragile" }, 0.1, 2, false), 0.1))
check("Ratchet Straps cut every hit", near(JobRules.damageLoss({}, 0.1, 50, true), 0.1 * Gear.StrapsLoss))

-- The freshness -----------------------------------------------------------------------------

check("a minute of a ★ job", near(JobRules.freshDrain(1, 60, false), Rules.FoodDrain[1]))
check("harder jobs drain faster", JobRules.freshDrain(4, 60, false) > JobRules.freshDrain(1, 60, false))
check("the Cooler Box halves it", near(JobRules.freshDrain(2, 60, true), Rules.FoodDrain[2] * Gear.CoolerDrain))
check("a tier past the list takes the last", near(JobRules.freshDrain(9, 60, false), Rules.FoodDrain[#Rules.FoodDrain]))
check("fresh food pays in full", near(JobRules.freshPay(1), 1))
check("stale food pays FreshPayMin", near(JobRules.freshPay(0), Rules.FreshPayMin))
check("half fresh in between", JobRules.freshPay(0.5) > Rules.FreshPayMin and JobRules.freshPay(0.5) < 1)
-- A ★ pizza job of about four minutes stays good; a ★★★★ food job of seven minutes without a cooler goes stale.
check("a short ★ food job stays fresh", 1 - JobRules.freshDrain(1, 240, false) >= Rules.GoodFresh)
check("a long ★★★★ food job without a cooler goes stale, with one it is fine", 1 - JobRules.freshDrain(4, 420, false) < Rules.GoodFresh
	and 1 - JobRules.freshDrain(4, 420, true) >= Rules.GoodFresh)

-- The rating with the freshness -------------------------------------------------------------

local fresh = JobRules.rate(1, 0.8, false, 0, 0.9)
check("fresh food: ★★★", fresh.stars == 3 and fresh.checks[3].text == "Fresh 90%" and fresh.checks[3].ok)
local stale = JobRules.rate(1, 0.8, false, 0, 0.5)
check("going stale: ★★", stale.stars == 2 and not stale.checks[3].ok)
local rotten = JobRules.rate(1, 0.8, false, 0, 0.1)
check("stale: ★", rotten.stars == 1)
local plain = JobRules.rate(1, 0.8, false, 0)
check("not food: no freshness check", #plain.checks == 3 and plain.stars == 3)

-- Multi-drop --------------------------------------------------------------------------------

check("★ and ★★ never multi-drop", JobRules.dropCount(1, 3, 3, 0, 0.9) == 1 and JobRules.dropCount(2, 3, 3, 0, 0.9) == 1)
check("★★★: two drops when it comes", JobRules.dropCount(3, 4, 3, 0, 0.99) == 2)
check("★★★★: up to three", JobRules.dropCount(4, 5, 3, 0, 0.99) == 3 and JobRules.dropCount(4, 5, 3, 0, 0) == 2)
check("not more drops than pieces", JobRules.dropCount(4, 2, 3, 0, 0.99) == 2 and JobRules.dropCount(4, 1, 3, 0, 0.99) == 1)
check("not more drops than receivers", JobRules.dropCount(4, 5, 1, 0, 0.99) == 1)
check("the chance", JobRules.dropCount(3, 4, 3, Config.Jobs.MultiDrop.Chance[3], 0) == 1)
local dests = JobRules.destinations({ 2, 1, 2 }, 2)
check("the pieces' stops", #dests == 5 and dests[1] == 2 and dests[2] == 2 and dests[3] == 3 and dests[4] == 4 and dests[5] == 4)
check("the extra drops pay", JobRules.multiDropPay(1) == 0 and JobRules.multiDropPay(3) == 2 * Config.Jobs.MultiDrop.PayPerStop)

-- Road events -------------------------------------------------------------------------------

local Events = Config.Jobs.RoadEvents
check("no event past the chance", JobRules.pickEvent(Events.Chance, 0.5) == nil and JobRules.pickEvent(0.99, 0) == nil)
local picked: { [string]: boolean } = {}
for n = 0, 9 do
	local id = JobRules.pickEvent(0, n / 10)
	if id then
		picked[id] = true
	end
end
check("every event can come", picked.survivor == true and picked.addon == true and picked.roadblock == true)
check("the event's time", near(JobRules.eventAfter(0), Events.After[1]) and near(JobRules.eventAfter(1), Events.After[2]))
check("the survivor's bonus", JobRules.survivorBonus(3) == 3 * Events.SurvivorBonus and JobRules.survivorBonus(0) == Events.SurvivorBonus)
check("an add-on needs room", JobRules.addOnFits(1, 0, 2) and not JobRules.addOnFits(2, 0, 2) and not JobRules.addOnFits(1, 1, 2))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
