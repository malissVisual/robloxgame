-- Logic test of 6.17, the JOBS app at a glance (shared/JobPick.luau): the hero card's choice (a golden order, else a
-- regular's order, else the best-paying job you can take; an expired one never), the rows under it (the specials, the
-- open ones, then the shut ones), what can't be taken off duty and during a run, and the short words of the rows, the
-- hero and the top bar.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local JobPick = require("./JobPick")
local Config = require("./Config")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local NOW = 1000
local function golden(index: number, payOf: number, expiresAt: number?): any
	return { index = index, mode = "car", stars = 3, pay = payOf, distance = 1240, time = 210, business = "bank",
		specialOrder = { kind = "golden", expiresAt = expiresAt or NOW + 100, pay = 3, xp = 2 } }
end
local function regular(index: number, payOf: number): any
	return { index = index, mode = "foot", stars = 1, pay = payOf, business = "pizzeria", specialOrder = { kind = "regular", expiresAt = NOW + 60, pay = 1.5, xp = 1 } }
end
local function plain(index: number, payOf: number, extra: any?): any
	local row = { index = index, mode = "car", stars = 2, pay = payOf, distance = 420, time = 130 }
	for key, value in extra or {} do
		row[key] = value
	end
	return row
end

-- ── The hero ────────────────────────────────────────────────────────────────
do
	local a, b, c = plain(1, 300), plain(2, 900, { locked = true, level = 9 }), plain(3, 500)
	local hero, kind = JobPick.hero({ a, b, c }, false, NOW)
	check("off duty: the best-paying job you can take (a locked richer one is passed over)", hero == c and kind == "best")
	local g1, g2, r = golden(4, 1140), golden(5, 2100), regular(6, 4000)
	hero, kind = JobPick.hero({ a, r, g1, g2, c }, false, NOW)
	check("a golden order beats everything, the best paid golden one", hero == g2 and kind == "golden")
	hero, kind = JobPick.hero({ a, r, c }, false, NOW)
	check("no golden: a regular's order", hero == r and kind == "regular")
	hero, kind = JobPick.hero({ a, golden(7, 5000, NOW - 1), c }, false, NOW)
	check("an expired golden order is never the hero", hero == c and kind == "best")
	local locked = golden(8, 3000)
	locked.locked, locked.level = true, 12
	hero, kind = JobPick.hero({ a, locked }, false, NOW)
	check("a golden order heads even while locked (its button says why)", hero == locked and kind == "golden")
	hero, kind = JobPick.hero({ b }, false, NOW)
	check("every row locked: no hero", hero == nil and kind == nil)
	hero = JobPick.hero(nil, false, NOW)
	check("no board yet: no hero", hero == nil)
	-- during a run: only + ADD or + QUEUE rows can be the best one
	local full = plain(9, 800) -- (no addOrder, no queue: FINISH YOUR RUN)
	local adds = plain(10, 200, { addOrder = true })
	local waits = plain(11, 400, { queue = true, tooBig = true })
	hero, kind = JobPick.hero({ full, adds, waits }, true, NOW)
	check("during a run: a row that waits in NEXT UP counts, one that can't join doesn't", hero == waits and kind == "best")
	check("blocked: off duty only the locks", not JobPick.blocked(full, false) and JobPick.blocked(b, false) and JobPick.blocked(plain(12, 1, { tooBig = true }), false))
	check("blocked: during a run neither + ADD nor + QUEUE", JobPick.blocked(full, true) and not JobPick.blocked(adds, true) and not JobPick.blocked(waits, true))
end

-- ── The rows ────────────────────────────────────────────────────────────────
do
	local a, b, c, g, r = plain(1, 300), plain(2, 900, { locked = true, level = 9 }), plain(3, 500), golden(4, 1140), regular(5, 80)
	local rows = JobPick.rows({ a, b, r, c, g }, g, false)
	check("the rows: not the hero, the specials first, the open ones in the server's order, the locked last",
		#rows == 4 and rows[1] == r and rows[2] == a and rows[3] == c and rows[4] == b)
	check("no hero: every row", #JobPick.rows({ a, b }, nil, false) == 2)
end

-- ── The words ───────────────────────────────────────────────────────────────
do
	local text, level = JobPick.danger({ mode = "foot" })
	check("on foot: 🚶", text == "🚶" and level == 0)
	text, level = JobPick.danger({ mode = "bike" })
	check("by bike: 🚲", text == "🚲" and level == 0)
	text, level = JobPick.danger({ mode = "car", stars = 3 })
	check("a car job: its stars and level", text == "★★★" and level == 3)
	text, level = JobPick.danger({ stars = 9 })
	check("the stars stay 1 .. 4", text == "★★★★" and level == 4)
	check("a row's facts: the distance and the time", JobPick.facts(plain(1, 1)) == "📍 420 · ⏱ 2:10", JobPick.facts(plain(1, 1)))
	local facts = JobPick.heroFacts(golden(1, 1))
	check("the hero's facts: distance, time, the golden XP", #facts == 3 and facts[1] == "📍 1240" and facts[2] == "⏱ 3:30" and facts[3] == "+2× XP")
	check("… no XP fact for a plain job", #JobPick.heroFacts(plain(1, 1)) == 2)
	check("a lock's short words: the level", JobPick.lockShort({ locked = true, level = 9 }) == "🔒 LV 9")
	check("… the licence", JobPick.lockShort({ locked = true, lockReason = "licence", licence = { have = 3, need = 5 } }) == "🪪 3/5")
	check("… the slots", JobPick.lockShort({ tooBig = true, slots = 6 }) == "📦 6 SLOTS")
	check("… none for an open row", JobPick.lockShort(plain(1, 1)) == nil)
	check("the ribbon: golden ×3", JobPick.ribbon(golden(1, 1)) == "★ GOLDEN ORDER ×3")
	check("… a regular's order ×1.5", JobPick.ribbon(regular(1, 1)) == "★ REGULAR'S ORDER ×1.5")
	check("… none for a plain job", JobPick.ribbon(plain(1, 1)) == nil)
	check("the hero's button off duty", JobPick.button(golden(1, 1), false) == "TAKE GOLDEN ORDER" and JobPick.button(plain(1, 1), false) == "TAKE JOB")
	check("… during a run: + ADD or + QUEUE", JobPick.button(plain(1, 1, { addOrder = true }), true) == "+ ADD" and JobPick.button(plain(1, 1, { queue = true }), true) == "+ QUEUE")
	local silver = Config.Regulars.Tiers[2]
	check("a row's medal: the tier held with its business", JobPick.medal({ pizzeria = silver.at }, { business = "pizzeria" }) == silver.icon)
	check("… none below the first tier, none unmet, none for a mission",
		JobPick.medal({ pizzeria = 1 }, { business = "pizzeria" }) == nil and JobPick.medal({}, { business = "pizzeria" }) == nil
		and JobPick.medal({ pizzeria = 99 }, { business = "pizzeria", mission = true }) == nil)
	check("the top bar's chips", JobPick.runChip(2, "$340") == "▶ YOUR RUN · 2 · $340" and JobPick.runChip(2, "$340", true) == "▶ RUN · 2 · $340" and JobPick.nextChip(1) == "NEXT UP · 1")
	check("rush hour's chip", JobPick.rushPrefix("rush") == "🕑 RUSH ×1.5 · ", JobPick.rushPrefix("rush"))
	check("… none for an event that doesn't pay, none without one", JobPick.rushPrefix("supply") == nil and JobPick.rushPrefix(nil) == nil)
	check("the list's title", JobPick.more(7, true) == "7 MORE JOBS" and JobPick.more(1, true) == "1 MORE JOB" and JobPick.more(3, false) == "3 JOBS")
	local view = Config.UiKit
	check("Config.UiKit (6.18, was Config.JobsView): the hero's heights in order, sizes set", view.HeroMin > 0 and view.HeroMin < view.HeroMax and view.Row >= view.Add and view.HeroShare > 0 and view.HeroShare < 1)
end

-- ── 6.18: the phone home's JOBS row ─────────────────────────────────────────
do
	local count, top, gold = JobPick.summary({ plain(1, 300), plain(2, 900, { locked = true }), plain(3, 500) }, false, NOW)
	check("6.18 summary: the jobs you can take and the best pay (a locked one not counted)", count == 2 and top == 500 and not gold, `{count} {top}`)
	count, top, gold = JobPick.summary({ plain(1, 300), golden(2, 1140) }, false, NOW)
	check("… a golden order the best: its pay, in gold", count == 2 and top == 1140 and gold)
	count, top = JobPick.summary({ golden(2, 1140, NOW - 1), plain(1, 300) }, false, NOW)
	check("… an expired one is not counted", count == 1 and top == 300)
	count = JobPick.summary({ plain(1, 300), plain(3, 500, { addOrder = true }) }, true, NOW)
	check("… during a run only what joins it", count == 1)
	check("… nothing without a board", JobPick.summary(nil, false, NOW) == 0)
	check("its line", JobPick.homeLine(7) == "7 jobs · best " and JobPick.homeLine(1) == "1 job · best " and JobPick.homeLine(0) == nil)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECKS FAILED`)
end
