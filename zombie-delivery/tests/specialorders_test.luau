-- Logic test of 6.14, the golden orders and the regulars' orders (shared/SpecialOrders.luau, Config.Jobs.Golden,
-- Config.Regulars.Order): the numbers, the roll, which transport and tier a golden order is for, a regular's order's
-- tries, an offer's Spec (its pay, XP, clock and danger by tier), the pay rounded, the clock, the words on the board
-- and in the result, and a light golden run's stray walkers. They queue like any ordinary board job
-- (shared/JobQueue.luau).
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local JobQueue = require("./JobQueue")
local SpecialOrders = require("./SpecialOrders")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Golden = Config.Jobs.Golden
local Tiers = Config.Jobs.Tiers

-- ── The numbers ──────────────────────────────────────────────────────────────
do
	check("a golden order pays much more (×3) and gives more XP (×2)", Golden.Pay == 3 and Golden.Xp == 2)
	check("rare: a small chance every board refresh", Golden.Chance > 0 and Golden.Chance <= 0.3 and Golden.Every >= 60)
	check("a few minutes on the board (1 – 10)", Golden.Seconds >= 60 and Golden.Seconds <= 600)
	check("from an early level", Golden.Level >= 1 and Golden.Level <= 5)
	check("its danger for every tier: bigger waves (≥ ×1.5), bandits at least as often", #Golden.Waves == #Tiers and #Golden.Bandits == #Tiers)
	local grows = true
	for index = 1, #Tiers do
		grows = grows and Golden.Waves[index] >= 1.5 and Golden.Bandits[index] >= 1
		if index > 1 then
			grows = grows and Golden.Waves[index] >= Golden.Waves[index - 1] and Golden.Bandits[index] >= Golden.Bandits[index - 1]
		end
	end
	check("… scaled to the tier (never less at a harder one)", grows)
	check("a light run's own lighter danger: closer strays, more likely, one more, some runners", Golden.Light.Every > 0 and Golden.Light.Every < 1 and Golden.Light.Chance > 0 and Golden.Light.Max >= 1 and Golden.Light.Runner > 0 and Golden.Light.Runner < 1)
	local golden, regular = SpecialOrders.tuning("golden"), SpecialOrders.tuning("regular")
	check("tuning: a kind's numbers", golden.pay == Golden.Pay and golden.seconds == Golden.Seconds and golden.level == Golden.Level
		and regular.pay == Config.Regulars.Order.Pay and regular.seconds == Config.Regulars.Order.Seconds)
	check("the roll: under the chance only", SpecialOrders.roll("golden", 0) and SpecialOrders.roll("golden", Golden.Chance - 0.001) and not SpecialOrders.roll("golden", Golden.Chance) and not SpecialOrders.roll("regular", 0.999))
end

-- ── A golden order's transport and tier ──────────────────────────────────────
do
	local mode, tier = SpecialOrders.goldenPlan({ level = 6, tiers = { 1, 2, 3 }, car = true, bike = true, riding = true }, 0)
	check("riding your bike: a bike run", mode == "bike" and tier == 1)
	mode, tier = SpecialOrders.goldenPlan({ level = 6, tiers = { 1, 2, 3 }, car = true, bike = true, riding = false }, 0)
	check("a car of your own: your hardest open tier …", mode == "car" and tier == 3)
	mode, tier = SpecialOrders.goldenPlan({ level = 6, tiers = { 1, 2, 3 }, car = true, bike = false, riding = false }, 0.99)
	check("… or the one under it", mode == "car" and tier == 2)
	mode, tier = SpecialOrders.goldenPlan({ level = 4, tiers = { 1 }, car = true, bike = false, riding = false }, 0.99)
	check("one open tier: that one", mode == "car" and tier == 1)
	mode = SpecialOrders.goldenPlan({ level = 3, tiers = {}, car = false, bike = true, riding = false }, 0)
	check("a bike, no car: a bike run", mode == "bike")
	mode = SpecialOrders.goldenPlan({ level = 3, tiers = {}, car = false, bike = false, riding = false }, 0)
	check("nothing yet: on foot", mode == "foot")
	mode = SpecialOrders.goldenPlan({ level = 3, tiers = { 1 }, car = true, bike = false, riding = true }, 0)
	check("riding, below the bike runs' level: never a car job (CALL CAR), a walk", mode == "foot")
end

-- ── A regular's order's tries ────────────────────────────────────────────────
do
	local reach = { level = 6, tiers = { 1, 2, 3 }, car = true, bike = true, riding = false }
	local plans = SpecialOrders.regularPlans(reach, { { tiers = { 1, 2 }, light = true } })
	local words = {}
	for _, plan in plans do
		table.insert(words, `{plan.mode}{plan.tier}`)
	end
	check("in your car: the business's hardest tier open to you first, then the bike, then on foot", table.concat(words, ",") == "car2,car1,bike1,foot1", table.concat(words, ","))
	plans = SpecialOrders.regularPlans({ level = 6, tiers = { 1, 2, 3 }, car = true, bike = true, riding = true }, { { tiers = { 1, 2 }, light = true } })
	check("riding your bike: the bike first", plans[1].mode == "bike")
	plans = SpecialOrders.regularPlans(reach, { { tiers = { 2, 3, 4 }, light = false } })
	words = {}
	for _, plan in plans do
		table.insert(words, `{plan.mode}{plan.tier}`)
	end
	check("a heavy business: only its car tiers open to you", table.concat(words, ",") == "car3,car2", table.concat(words, ","))
	plans = SpecialOrders.regularPlans({ level = 2, tiers = {}, car = false, bike = false, riding = false }, { { tiers = { 1 }, light = true }, { tiers = { 3 }, light = false } })
	check("on foot: a walk", #plans == 1 and plans[1].mode == "foot")
end

-- ── An offer's Spec ──────────────────────────────────────────────────────────
do
	local now = 1000
	local spec = SpecialOrders.make("golden", now, 3, "car")
	check("a golden ★★★ car run: its clock, ×3 pay, ×2 XP", spec.kind == "golden" and spec.expiresAt == now + Golden.Seconds and spec.pay == 3 and spec.xp == 2)
	check("… bigger waves and the bandits more often", spec.waves == Golden.Waves[3] and spec.boost == Golden.Bandits[3] and not spec.light)
	spec = SpecialOrders.make("golden", now, 1, "car")
	check("a golden ★ car run: bigger waves, no bandits on that tier", spec.waves == Golden.Waves[1] and spec.boost == 1 and Tiers[1].ambushEvery == 0)
	spec = SpecialOrders.make("golden", now, 1, "foot")
	check("a golden walk: its lighter danger, no waves", spec.waves == 1 and spec.boost == 1 and spec.light)
	spec = SpecialOrders.make("regular", now, 2, "car", "pizzeria")
	check("a regular's order: ×1.5 pay, no danger, its business", spec.kind == "regular" and spec.pay == Config.Regulars.Order.Pay and spec.xp == Config.Regulars.Order.Xp
		and spec.waves == 1 and spec.boost == 1 and not spec.light and spec.business == "pizzeria" and spec.expiresAt == now + Config.Regulars.Order.Seconds)
	check("the pay × it, rounded to $5", SpecialOrders.pay(100, SpecialOrders.make("golden", now, 1, "car")) == 300 and SpecialOrders.pay(83, spec) == 125 and SpecialOrders.pay(140, spec) == 210)
	check("never less than it was", SpecialOrders.pay(2, spec) >= 2)
	check("the clock: its seconds left, then expired", SpecialOrders.left(spec, now + 10) == Config.Regulars.Order.Seconds - 10 and not SpecialOrders.expired(spec, now + 10)
		and SpecialOrders.expired(spec, spec.expiresAt) and SpecialOrders.left(spec, spec.expiresAt + 5) == 0)
	check("no spec: nothing", not SpecialOrders.expired(nil, now) and SpecialOrders.left(nil, now) == 0)
end

-- ── The words ────────────────────────────────────────────────────────────────
do
	local golden = SpecialOrders.make("golden", 0, 2, "car")
	local regular = SpecialOrders.make("regular", 0, 1, "foot", "bakery")
	check("the labels", SpecialOrders.label(golden) == "★ GOLDEN ORDER" and SpecialOrders.label(regular) == "★ REGULAR'S ORDER")
	check("the perks", SpecialOrders.perks(golden) == "×3 PAY · ×2 XP · MORE DANGER" and SpecialOrders.perks(regular) == "×1.5 PAY", SpecialOrders.perks(golden) .. " / " .. SpecialOrders.perks(regular))
	check("the toast when a golden one comes", SpecialOrders.appearText(golden) == "★ A GOLDEN ORDER is on your board · 3:00 · ×3 PAY · ×2 XP · MORE DANGER · JOBS", SpecialOrders.appearText(golden))
	check("… with the time it has left", string.find(SpecialOrders.appearText(golden, nil, 95), "1:35", 1, true) ~= nil)
	check("… and a regular's", SpecialOrders.appearText(regular, "Daily Bread Bakery") == "★ A REGULAR'S ORDER from Daily Bread Bakery is on your board · 5:00 · ×1.5 PAY")
end

-- ── A light golden run's stray walkers ───────────────────────────────────────
do
	local every, chance, most, runners = SpecialOrders.strays(40, 0.5, 1, false)
	check("an ordinary run: as it was, no runners", every == 40 and chance == 0.5 and most == 1 and runners == 0)
	every, chance, most, runners = SpecialOrders.strays(40, 0.5, 1, true)
	check("a golden one: closer together, likelier, one more, some runners", every == 40 * Golden.Light.Every and chance == math.min(0.95, 0.5 + Golden.Light.Chance) and most == 1 + Golden.Light.Max and runners == Golden.Light.Runner)
	_, chance = SpecialOrders.strays(30, 0.9, 2, true)
	check("never a certainty", chance <= 0.95)
end

-- ── The result's lines ───────────────────────────────────────────────────────
do
	check("a failed job: none", #SpecialOrders.resultLines({ success = false, special = { golden = { pay = 3, xp = 2 } } }) == 0)
	check("an ordinary job: none", #SpecialOrders.resultLines({ success = true }) == 0)
	local lines = SpecialOrders.resultLines({ success = true, special = { golden = { pay = 3, xp = 2 }, regular = { name = "Luigi's Pizza", tier = "Silver", money = 8 } } })
	check("a golden order: its line in gold", #lines == 2 and lines[1].text == "★ GOLDEN ORDER ×3 · ×2 XP" and lines[1].gold and lines[1].money == nil, lines[1] and lines[1].text)
	check("the regular's bonus: Regular · Luigi's Pizza (Silver) +$8", lines[2].text == "Regular · Luigi's Pizza (Silver)" and lines[2].money == 8 and not lines[2].gold)
	lines = SpecialOrders.resultLines({ success = true, special = { regularOrder = { pay = 1.5, name = "Bloom" }, regular = { name = "Bloom", tier = "Gold", money = 0 } } })
	check("a regular's order (and no bonus line for $0)", #lines == 1 and lines[1].text == "★ REGULAR'S ORDER · Bloom ×1.5" and lines[1].gold)
end

-- ── NEXT UP ──────────────────────────────────────────────────────────────────
check("a golden or a regular's order is an ordinary board job: it may wait in NEXT UP", JobQueue.queueable({ special = false, mission = false, tutorial = false, duo = false, round = false }))

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
