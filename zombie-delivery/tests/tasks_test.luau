-- Logic test of the daily and weekly tasks (6.12, shared/Tasks.luau, Config.Tasks): the pool (unique ids, known
-- events, sane ranges and rewards, enough kinds at level 1), the picks (stable for one day and one courier, three
-- distinct dailies of three groups + one weekly, other picks on other days and for other couriers, new at 00:00 UTC,
-- the weekly new on Monday 00:00 UTC, only the kinds open at the level), progress (clamped to the target, the look and
-- the night filters, nothing after a claim), claims (once each, the all-dailies bonus only with every daily done),
-- the reset (paying what was done and not claimed), a save checked (Tasks.clean) and what an order counts for.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local Tasks = require("./Tasks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Tasks
local DAY = 86400
local NOW = 1791331200 -- 2026-10-07 00:00 UTC (a Wednesday)
local USER = 123456789

-- ── The pool ──────────────────────────────────────────────────────────────
local EVENTS = { deliver = true, ride = true, stars3 = true, perfect = true, zip = true, bus = true, kill = true, tips = true, earn = true, mission = true, shift = true, regular = true, golden = true } -- (6.14: shift, server/Shift.luau; regular, golden)
do
	local seen: { [string]: boolean } = {}
	local bad = {}
	for _, pool in { T.DailyPool, T.WeeklyPool } do
		for _, def in pool do
			if seen[def.id] then
				table.insert(bad, `{def.id}: twice`)
			end
			seen[def.id] = true
			if not EVENTS[def.event] then
				table.insert(bad, `{def.id}: event {def.event}`)
			end
			local step = def.step or 1
			if not (def.target[1] >= 1 and def.target[2] >= def.target[1] and math.floor(def.target[2] / step) * step >= def.target[1]) then
				table.insert(bad, `{def.id}: target`)
			end
			if not (def.money > 0 and def.xp > 0) then
				table.insert(bad, `{def.id}: reward`)
			end
			if not string.find(def.text, "{n}", 1, true) then
				table.insert(bad, `{def.id}: no {"{n}"} in its text`)
			end
		end
	end
	check("every kind: a unique id, a known event, a target range, a reward, {n} in its text", #bad == 0, table.concat(bad, ", "))
	local groups: { [string]: boolean } = {}
	local count = 0
	for _, def in T.DailyPool do
		if (def.level or 1) <= 1 and not groups[def.group or def.id] then
			groups[def.group or def.id] = true
			count += 1
		end
	end
	check("at level 1 at least six groups of dailies (three a day, variety)", count >= 6, count)
	local weekly = 0
	for _, def in T.WeeklyPool do
		if (def.level or 1) <= 1 then
			weekly += 1
		end
	end
	check("at level 1 at least four weekly kinds", weekly >= 4, weekly)
	local dailyMax, weeklyMin = 0, math.huge
	for _, def in T.DailyPool do
		dailyMax = math.max(dailyMax, def.money)
	end
	for _, def in T.WeeklyPool do
		weeklyMin = math.min(weeklyMin, def.money)
	end
	check("a weekly pays more than any daily", weeklyMin > dailyMax, `{weeklyMin} vs {dailyMax}`)
end

-- ── Time ──────────────────────────────────────────────────────────────────
check("the day number at 00:00 UTC", Tasks.dayOf(NOW) == NOW / DAY and Tasks.dayOf(NOW + DAY - 1) == NOW / DAY and Tasks.dayOf(NOW + DAY) == NOW / DAY + 1)
check("the day ends at the next 00:00 UTC", Tasks.dayEnds(NOW + 3600) == NOW + DAY)
do
	-- 2026-10-05 was a Monday: the week runs Monday 00:00 → Monday 00:00 UTC.
	local monday = NOW - 2 * DAY
	check("the week starts on Monday 00:00 UTC", Tasks.weekOf(monday) == Tasks.weekOf(monday + 7 * DAY - 1) and Tasks.weekOf(monday - 1) == Tasks.weekOf(monday) - 1)
	check("the week ends on the next Monday", Tasks.weekEnds(NOW) == monday + 7 * DAY)
end

-- ── The picks ─────────────────────────────────────────────────────────────
local function ids(picks: { Tasks.Pick }): string
	local out = {}
	for _, pick in picks do
		table.insert(out, `{pick.id}:{pick.target}`)
	end
	return table.concat(out, ",")
end
local day = Tasks.dayOf(NOW)
do
	local a, b = Tasks.pickDaily(day, USER, 3), Tasks.pickDaily(day, USER, 3)
	check("the same day, the same courier: the same dailies", ids(a) == ids(b), ids(a))
	check("three dailies", #a == T.Daily, #a)
	local week = Tasks.pickWeekly(Tasks.weekOf(NOW), USER, 3)
	check("one weekly from the weekly pool", week ~= nil and week.weekly and string.sub(week.id, 1, 2) == "w_", week and week.id)
	check("the same week: the same weekly", ids({ week }) == ids({ Tasks.pickWeekly(Tasks.weekOf(NOW + 3 * DAY), USER, 3) }))
end
do
	local bad, changedDays, kinds = {}, 0, {}
	local before = ""
	for n = 0, 59 do
		for _, user in { USER, 1, 98765, -1 } do
			for _, level in { 1, 4, 8, 15 } do
				local picks = Tasks.pickDaily(day + n, user, level)
				local groups: { [string]: boolean } = {}
				if #picks ~= T.Daily then
					table.insert(bad, `day {n} user {user}: {#picks} picks`)
				end
				for _, pick in picks do
					local def
					for _, entry in T.DailyPool do
						if entry.id == pick.id then
							def = entry
						end
					end
					local group = if def then def.group or def.id else "?"
					if groups[group] then
						table.insert(bad, `day {n} user {user}: two of {group}`)
					end
					groups[group] = true
					if not def or (def.level or 1) > level then
						table.insert(bad, `day {n} user {user} level {level}: {pick.id} not open`)
					end
					if pick.target < 1 or pick.money <= 0 or pick.xp <= 0 or pick.title == "" or string.find(pick.title, "{", 1, true) then
						table.insert(bad, `{pick.id}: {pick.title} {pick.target}`)
					end
				end
				if user == USER and level == 4 then
					for _, pick in picks do
						kinds[pick.id] = true
					end
				end
			end
		end
		local now = ids(Tasks.pickDaily(day + n, USER, 4))
		if n > 0 and now ~= before then
			changedDays += 1
		end
		before = now
	end
	check("60 days × 4 couriers × 4 levels: three distinct groups, only open kinds, real titles", #bad == 0, table.concat(bad, "; "))
	check("new dailies on most days", changedDays >= 50, changedDays)
	local seen = 0
	for _ in kinds do
		seen += 1
	end
	check("over 60 days most kinds come up", seen >= 9, seen)
	check("another courier, other dailies", ids(Tasks.pickDaily(day, USER, 4)) ~= ids(Tasks.pickDaily(day, USER + 1, 4)) or ids(Tasks.pickDaily(day + 1, USER, 4)) ~= ids(Tasks.pickDaily(day + 1, USER + 1, 4)))
end
do
	local low = Tasks.pickDaily(day, USER, 1)
	local missionAt1 = false
	for n = 0, 199 do
		for _, pick in Tasks.pickDaily(day + n, USER, 1) do
			missionAt1 = missionAt1 or pick.id == "mission" or pick.id == "ride"
		end
	end
	check("no mission or ride task at level 1", not missionAt1 and #low == 3)
	local top = Tasks.pickDaily(day, USER, 15)
	local lowMoney, topMoney = 0, 0
	for _, pick in low do
		lowMoney += pick.money
	end
	for _, pick in top do
		topMoney += pick.money
	end
	check("the rewards grow with the level", topMoney / #top > lowMoney / #low, `{lowMoney} vs {topMoney}`)
end

-- ── A save: progress, claims, the bonus ───────────────────────────────────
local saved = Tasks.fresh(USER, NOW + 3600, 3)
local picks = Tasks.daily(saved, USER)
check("a fresh save: today, level 3, nothing done", saved.day == day and saved.level == 3 and saved.progress[1] == 0 and not saved.claimed[1] and not saved.bonus and Tasks.claimable(saved, USER) == 0)
check("the save's ids are its picks'", saved.ids[1] == picks[1].id and saved.ids[3] == picks[3].id and saved.weekId == Tasks.weekly(saved, USER).id)

-- An event that fits the first daily (its look, at night).
local function infoFor(pick: Tasks.Pick): Tasks.Info
	return { look = pick.look, night = pick.night, bike = true, stars = 3, pay = 100 }
end
local first = picks[1]
local finished = Tasks.note(saved, USER, first.event, first.target * 5, infoFor(first))
check("progress clamps at the target", saved.progress[1] == first.target, saved.progress[1])
local found = false
for _, pick in finished do
	found = found or pick.id == first.id
end
check("note says which task it finished", found)
local again = Tasks.note(saved, USER, first.event, 1, infoFor(first))
check("a finished task does not finish again", #again == 0 or again[1].id ~= first.id)
check("nothing for a bad amount", select(2, Tasks.note(saved, USER, first.event, -3, infoFor(first))) == false and select(2, Tasks.note(saved, USER, first.event, 0 / 0, infoFor(first))) == false)
check("one waits to be claimed", Tasks.claimable(saved, USER) >= 1)
do
	local money, xp = Tasks.claim(saved, USER, 1)
	check("CLAIM pays its money and XP", money == first.money and xp == first.xp, money)
	local again2 = Tasks.claim(saved, USER, 1)
	check("… once", again2 == nil)
	local before = saved.progress[1]
	Tasks.note(saved, USER, first.event, 3, infoFor(first))
	check("a claimed task counts no more", saved.progress[1] == before)
end
check("an unfinished task cannot be claimed", Tasks.claim(saved, USER, 2) == nil and not saved.claimed[2])
check("nonsense slots are refused", Tasks.claim(saved, USER, 7) == nil and Tasks.claim(saved, USER, 1.5) == nil and Tasks.claim(saved, USER, "x") == nil)
check("no bonus before every daily is done", Tasks.claim(saved, USER, "bonus") == nil and not saved.bonus)
for index = 2, 3 do
	local pick = picks[index]
	Tasks.note(saved, USER, pick.event, pick.target, infoFor(pick))
end
check("every daily done: the two and the bonus wait", Tasks.claimable(saved, USER) == 3, Tasks.claimable(saved, USER))
do
	local money, xp = Tasks.claim(saved, USER, "bonus")
	local bonusMoney, bonusXp = Tasks.bonusOf(3)
	check("the all-dailies bonus pays once", money == bonusMoney and xp == bonusXp and Tasks.claim(saved, USER, "bonus") == nil and money ~= nil and money > 0)
end

-- The filters: a look of its own, the night.
do
	local pizza = { id = "pizza", event = "deliver", look = "pizza", title = "", target = 3, money = 1, xp = 1, weekly = false } :: Tasks.Pick
	local night = { id = "night", event = "kill", night = true, title = "", target = 3, money = 1, xp = 1, weekly = false } :: Tasks.Pick
	check("a pizza task counts pizza only", Tasks.matches(pizza, "deliver", { look = "pizza" }) and not Tasks.matches(pizza, "deliver", { look = "parcel" }) and not Tasks.matches(pizza, "deliver", nil))
	check("a night task counts at night only", Tasks.matches(night, "kill", { night = true }) and not Tasks.matches(night, "kill", { night = false }))
	check("another event never counts", not Tasks.matches(pizza, "zip", { look = "pizza" }))
end

-- The weekly.
do
	local s = Tasks.fresh(USER, NOW + 3600, 3) -- (a save of its own: the dailies' events above may have counted for it)
	local week = Tasks.weekly(s, USER)
	Tasks.note(s, USER, week.event, week.target - 1, infoFor(week))
	check("the weekly counts", s.weekProgress == week.target - 1 and Tasks.claim(s, USER, "weekly") == nil, s.weekProgress)
	Tasks.note(s, USER, week.event, 10, infoFor(week))
	local money = Tasks.claim(s, USER, "weekly")
	check("the weekly claimed once", money == week.money and Tasks.claim(s, USER, "weekly") == nil and s.weekProgress == week.target)
end

-- ── The reset ─────────────────────────────────────────────────────────────
do
	local s = Tasks.fresh(USER, NOW + 60, 2)
	local p = Tasks.daily(s, USER)
	Tasks.note(s, USER, p[2].event, p[2].target, infoFor(p[2])) -- done, not claimed
	local changed = Tasks.roll(s, USER, NOW + DAY - 1, 2)
	check("the same day: no reset", changed == false and s.day == day)
	local changed2, owed, dayNew, weekNew = Tasks.roll(s, USER, NOW + DAY + 5, 6)
	check("00:00 UTC: new dailies at the level now", changed2 and dayNew and not weekNew and s.day == day + 1 and s.level == 6 and s.progress[2] == 0 and not s.claimed[2])
	check("the reset pays what was done and not claimed", owed.money == p[2].money and owed.xp == p[2].xp and owed.titles[1] == p[2].title)
	check("the dailies of the new day are its picks", s.ids[1] == Tasks.pickDaily(day + 1, USER, 6)[1].id)
	local _, owed2, _, weekNew2 = Tasks.roll(s, USER, Tasks.weekEnds(NOW) + 10, 6)
	check("Monday 00:00 UTC: a new weekly", weekNew2 and s.week == Tasks.weekOf(NOW) + 1 and s.weekProgress == 0 and owed2.money == 0)
	-- all three done and none claimed: the three and the bonus are paid
	local t = Tasks.fresh(USER, NOW, 1)
	local total = 0
	for index, pick in Tasks.daily(t, USER) do
		Tasks.note(t, USER, pick.event, pick.target, infoFor(pick))
		total += pick.money
		check(`daily {index} done`, t.progress[index] == pick.target)
	end
	local _, owed3 = Tasks.roll(t, USER, NOW + DAY, 1)
	check("a reset pays the bonus too when every daily was done", owed3.money == total + (Tasks.bonusOf(1)), owed3.money)
end

-- ── A save checked ────────────────────────────────────────────────────────
do
	check("no save: nil", Tasks.clean(nil) == nil and Tasks.clean("x") == nil and Tasks.clean({}) == nil)
	local raw = { day = day, level = 99, ids = { "zip", 5, "x" }, progress = { -4, 0 / 0, 1e30 }, claimed = { true, "yes" }, bonus = 1, week = Tasks.weekOf(NOW), weekLevel = -3, weekId = 7, weekProgress = 3, weekClaimed = true }
	local s = Tasks.clean(raw)
	check("a bad save is cleaned", s ~= nil and s.level == Config.Levels.MaxLevel and s.progress[1] == 0 and s.progress[2] == 0 and s.progress[3] <= 1e9
		and s.claimed[1] == true and s.claimed[2] == false and s.bonus == false and s.weekLevel == 1 and s.weekId == "" and s.weekClaimed == true and s.ids[2] == "")
	if s then
		local changed = Tasks.roll(s, USER, NOW + 10, 3)
		local p = Tasks.daily(s, USER)
		check("a save whose ids are not its picks keeps no stray progress", changed and s.ids[1] == p[1].id and s.weekId == Tasks.weekly(s, USER).id and s.weekProgress == 0 and s.weekClaimed == false)
		for index, pick in p do
			check(`slot {index}: progress within its target`, s.progress[index] <= pick.target)
		end
	end
	local good = Tasks.fresh(USER, NOW, 4)
	local copy = Tasks.clean(good)
	check("a good save survives the check", copy ~= nil and copy.day == good.day and copy.ids[2] == good.ids[2] and copy.weekId == good.weekId and select(1, Tasks.roll(copy :: any, USER, NOW + 5, 4)) == false)
end

-- ── What an order counts for, the view ────────────────────────────────────
do
	local events = Tasks.orderEvents(3, { look = "pizza", bike = true, stars = 3, pay = 120 })
	local by: { [string]: number } = {}
	for _, e in events do
		by[e.event] = e.amount
	end
	check("an order: its pieces, the ride, the ★★★, the pay", by.deliver == 3 and by.ride == 1 and by.stars3 == 1 and by.earn == 120)
	local plain = Tasks.orderEvents(2, { stars = 2 })
	check("a ★★ order on foot: only its pieces", #plain == 1 and plain[1].event == "deliver")
	local s = Tasks.fresh(USER, NOW, 4)
	local view = Tasks.view(s, USER, NOW + 30)
	check("the view: three dailies, the bonus, the weekly, the resets", #view.daily == 3 and view.bonus.money > 0 and view.weekly ~= nil and view.dayEnds == NOW + DAY and view.weekEnds == Tasks.weekEnds(NOW) and view.ready == 0)
	check("the view's daily card", view.daily[1].slot == 1 and view.daily[1].title ~= "" and view.daily[1].progress == 0 and view.daily[1].done == false)
	check("money reads with commas", Tasks.money(1234567) == "$1,234,567" and Tasks.money(80) == "$80")
	local earn = Tasks.pickWeekly(0, 0, 1)
	for week = 0, 400 do
		local pick = Tasks.pickWeekly(week, USER, 9)
		if pick.id == "w_earn" then
			earn = pick
			break
		end
	end
	check("a big target reads with commas (the weekly's pay task)", earn.id ~= "w_earn" or string.find(earn.title, "%$%d+,%d%d%d") ~= nil, earn.title)
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
