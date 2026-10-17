-- Logic test of the sandbox's daily tasks (8.2, shared/SandboxTasks.luau, Config.SandboxTasks): the pools (unique ids,
-- known events, sane ranges and rewards, the danny kind's item a real piece), the picks (the same all day for one
-- player, three distinct dailies of three groups + one weekly, other picks on other days and for other players, new
-- at 00:00 UTC, the weekly new on Monday 00:00 UTC, a skipped kind never picked), progress (a sum or the best one,
-- clamped to the target, the danny kind's item, nothing after a claim, garbage amounts), claims (once each, the bonus
-- only with every daily done, unknown slots), the weekly (bigger, its own claim), the reset (paying what was done and
-- not claimed, a clock that went back), a save checked (SandboxTasks.clean) and the migration (fromSave), the view.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local SandboxTasks = require("./SandboxTasks")
local FurnitureLooks = require("./FurnitureLooks")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.SandboxTasks
local DAY = 86400
local NOW = 1791331200 + 3600 -- 2026-10-07 01:00 UTC (a Wednesday)
local USER = 123456789

local function ids(slots: { SandboxTasks.Slot }): string
	local out = {}
	for _, slot in slots do
		table.insert(out, `{slot.id}:{slot.target}`)
	end
	return table.concat(out, ",")
end
local function slotOf(saved: SandboxTasks.Saved, id: string): (SandboxTasks.Slot?, number?)
	for index, slot in saved.daily do
		if slot.id == id then
			return slot, index
		end
	end
	return nil, nil
end
-- A save whose dailies are these kinds at these targets (the picks are random: the tests set their own).
local function made(daily: { { string | number } }, weekly: { string | number }?): SandboxTasks.Saved
	local saved = SandboxTasks.fresh(USER, NOW)
	saved.daily = {}
	for _, pair in daily do
		table.insert(saved.daily, { id = pair[1] :: string, target = pair[2] :: number, progress = 0, claimed = false })
	end
	saved.weekly = if weekly then { id = weekly[1] :: string, target = weekly[2] :: number, progress = 0, claimed = false } else nil
	return saved
end

-- ── The pools ───────────────────────────────────────────────────────────────
local EVENTS = { home = true, rare = true, clean = true, moves = true, trips = true, shown = true, sell = true, income = true, upgrade = true, danny = true, hotsell = true, hotincome = true, offer = true } -- (8.3: the market's two, the visitors' offer)
do
	local seen: { [string]: boolean } = {}
	local bad = {}
	for poolIndex, pool in { T.DailyPool, T.WeeklyPool } do
		for _, def in pool do
			if seen[def.id] then
				table.insert(bad, `{def.id}: twice`)
			end
			seen[def.id] = true
			if not EVENTS[def.event] then
				table.insert(bad, `{def.id}: event {def.event}`)
			end
			if (poolIndex == 2) ~= (string.sub(def.id, 1, 2) == "w_") then
				table.insert(bad, `{def.id}: a weekly's id starts with w_, a daily's never`)
			end
			if #def.target ~= 2 or def.target[1] < 1 or def.target[2] < def.target[1] or (def.step or 1) < 1 then
				table.insert(bad, `{def.id}: range`)
			end
			if def.money <= 0 or def.money % 10 ~= 0 or def.icon == "" or def.text == "" then
				table.insert(bad, `{def.id}: reward, icon or text`)
			end
			if def.target[2] > 1 and not string.find(def.text, "{n}", 1, true) then
				table.insert(bad, `{def.id}: a range without {"{n}"} in its text`)
			end
			if def.item and not FurnitureLooks.Items[def.item] then
				table.insert(bad, `{def.id}: item {def.item}`)
			end
			local def2, weekly = SandboxTasks.def(def.id)
			if def2 ~= def or weekly ~= (poolIndex == 2) then
				table.insert(bad, `{def.id}: SandboxTasks.def`)
			end
		end
	end
	check("the pools: unique ids (w_ for the weekly), known events, sane ranges, rewards, icons; the danny kind's item a real piece", #bad == 0, table.concat(bad, "; "))
	local groups: { [string]: boolean } = {}
	local kinds = 0
	for _, def in T.DailyPool do
		local group = def.group or def.id
		if not groups[group] then
			groups[group] = true
			kinds += 1
		end
	end
	check("enough groups for three dailies (and one skipped)", kinds >= T.Daily + 1, kinds)
	check("the danny kind is the sofa (a two-person piece Danny lifts with you)", (SandboxTasks.def("danny") :: any).item == "sofa" and FurnitureLooks.Items.sofa.class == "pair")
	local hotsell, hotincome = SandboxTasks.def("hotsell"), SandboxTasks.def("hotincome")
	check("8.3, the market's kinds: \"Sell a hot item\" and \"Earn $N from hot items on show\", one group (never both a day)", hotsell ~= nil and hotincome ~= nil
		and SandboxTasks.titleOf(hotsell :: SandboxTasks.Def, 1) == "Sell a hot item" and SandboxTasks.titleOf(hotincome :: SandboxTasks.Def, 150) == "Earn $150 from hot items on show"
		and (hotsell :: SandboxTasks.Def).group == "market" and (hotincome :: SandboxTasks.Def).group == "market")
	check("the bonus and the high end's share: positive", T.AllDaily > 0 and T.TopShare >= 0)
	check("SandboxTasks.def: unknown ids and garbage are nil", SandboxTasks.def("nope") == nil and SandboxTasks.def(5) == nil and SandboxTasks.def(nil) == nil)
end

-- ── Time ────────────────────────────────────────────────────────────────────
do
	check("the day and its end (00:00 UTC)", SandboxTasks.dayOf(NOW) == SandboxTasks.dayOf(NOW - 3600) and SandboxTasks.dayLeft(NOW) == DAY - 3600)
	local monday = NOW - 2 * DAY - 3600 -- 2026-10-05 00:00 UTC
	check("the week starts on Monday 00:00 UTC", SandboxTasks.weekOf(monday) == SandboxTasks.weekOf(NOW) and SandboxTasks.weekOf(monday - 1) == SandboxTasks.weekOf(NOW) - 1
		and SandboxTasks.weekLeft(NOW) == 5 * DAY - 3600)
end

-- ── The picks ───────────────────────────────────────────────────────────────
do
	local day = SandboxTasks.dayOf(NOW)
	local a = SandboxTasks.pickDaily(day, USER)
	local b = SandboxTasks.pickDaily(day, USER)
	check("the same day, the same player: the same three (kinds and targets)", ids(a) == ids(b) and #a == T.Daily, ids(a))
	check("… and the same all day (any hour gives that day)", ids(SandboxTasks.fresh(USER, NOW + 20 * 3600).daily) == ids(a))
	local fine, distinct = true, true
	local seenSets: { [string]: boolean } = {}
	local kinds: { [string]: number } = {}
	for d = 0, 199 do
		local picks = SandboxTasks.pickDaily(day + d, USER)
		seenSets[ids(picks)] = true
		local groups: { [string]: boolean } = {}
		local idsSeen: { [string]: boolean } = {}
		if #picks ~= T.Daily then
			fine = false
		end
		for _, slot in picks do
			local def = SandboxTasks.def(slot.id) :: SandboxTasks.Def
			local group = def.group or def.id
			if groups[group] or idsSeen[slot.id] then
				distinct = false
			end
			groups[group], idsSeen[slot.id] = true, true
			kinds[slot.id] = (kinds[slot.id] or 0) + 1
			local step = def.step or 1
			if slot.target < def.target[1] or slot.target > def.target[2] or slot.target % step ~= 0 or slot.progress ~= 0 or slot.claimed then
				fine = false
			end
		end
	end
	local setCount, kindCount = 0, 0
	for _ in seenSets do
		setCount += 1
	end
	for _ in kinds do
		kindCount += 1
	end
	check("200 days: three a day, each target in its range and steps, no progress", fine)
	check("… never two of one kind or one group a day (no duplicates)", distinct)
	check("… other picks on other days, every daily kind comes up", setCount > 100 and kindCount == #T.DailyPool, `{setCount} sets, {kindCount} kinds`)
	local other = 0
	for user = 1, 50 do
		if ids(SandboxTasks.pickDaily(day, user)) ~= ids(a) then
			other += 1
		end
	end
	check("other players get other picks the same day", other >= 40, other)
	local skip = { upgrade = true }
	local never = true
	for d = 0, 199 do
		for _, slot in SandboxTasks.pickDaily(day + d, USER, skip) do
			if slot.id == "upgrade" then
				never = false
			end
		end
	end
	check("a skipped kind (every upgrade bought: \"upgrade\") is never picked, still three a day", never and #SandboxTasks.pickDaily(day, USER, skip) == T.Daily)
	local weekly = SandboxTasks.pickWeekly(SandboxTasks.weekOf(NOW), USER)
	check("the weekly: one of WeeklyPool, the same all week", weekly ~= nil and select(2, SandboxTasks.def((weekly :: any).id)) == true
		and SandboxTasks.pickWeekly(SandboxTasks.weekOf(NOW + 3 * DAY), USER) ~= nil and (SandboxTasks.pickWeekly(SandboxTasks.weekOf(NOW + 3 * DAY), USER) :: any).id == (weekly :: any).id)
	local bigger = true
	for _, def in T.WeeklyPool do
		local daily = nil
		for _, d in T.DailyPool do
			if d.event == def.event and not d.best then
				daily = d
			end
		end
		if daily and (def.target[1] <= daily.target[2] or def.money <= daily.money * 2) then
			bigger = false
		end
	end
	check("the weekly is a bigger one: more to do than a daily of its event, more than twice its reward", bigger)
	-- 8.3 economy (saving up): the dailies and the weekly about 0.6 × what they paid, the rare pieces' targets rarer
	local sum, n = 0, 0
	for _, def in T.DailyPool do
		sum += def.money
		n += 1
	end
	local rare, wRare = SandboxTasks.def("rare") :: SandboxTasks.Def, SandboxTasks.def("w_rare") :: SandboxTasks.Def
	check(`8.3 economy: the bonus $300, the dailies $120 – 200 (mean {math.floor(sum / n + 0.5)}), the weekly $1,200 – 2,000; rare 1-2 a day, 10-20 a week`,
		T.AllDaily == 300 and sum / n >= 120 and sum / n <= 160 and rare.target[1] == 1 and rare.target[2] == 2 and wRare.target[1] == 10 and wRare.target[2] == 20
		and SandboxTasks.def("clean").money == 200 and SandboxTasks.def("w_clean").money == 2000 and SandboxTasks.def("w_sell").money == 1200)
end

-- ── Rewards and titles ──────────────────────────────────────────────────────
do
	local home = SandboxTasks.def("home") :: SandboxTasks.Def
	check("the reward: money at the range's low end, TopShare more at its high end, $10 steps", SandboxTasks.rewardOf(home, home.target[1]) == home.money
		and SandboxTasks.rewardOf(home, home.target[2]) == math.floor(home.money * (1 + T.TopShare) / 10 + 0.5) * 10
		and SandboxTasks.rewardOf(home, 11) % 10 == 0 and SandboxTasks.rewardOf(home, 11) > home.money)
	local sell = SandboxTasks.def("sell") :: SandboxTasks.Def
	check("… in steps (sell: $150 … $400 in $50s)", SandboxTasks.rewardOf(sell, 150) == sell.money and SandboxTasks.rewardOf(sell, 400) > SandboxTasks.rewardOf(sell, 250))
	local clean = SandboxTasks.def("clean") :: SandboxTasks.Def
	check("titles: {n} the target, `one` at 1", SandboxTasks.titleOf(home, 12) == "Bring 12 pieces home" and SandboxTasks.titleOf(clean, 1) == "Finish a move with nothing broken"
		and SandboxTasks.titleOf(SandboxTasks.def("w_income") :: SandboxTasks.Def, 4500) == "Earn $4,500 from your stands")
	check("money reads with commas", SandboxTasks.money(1234567) == "$1,234,567" and SandboxTasks.money(80) == "$80")
end

-- ── Progress per event ──────────────────────────────────────────────────────
do
	local saved = made({ { "home", 10 }, { "trips", 3 }, { "sell", 200 } }, { "w_income", 4000 })
	local done, moved = SandboxTasks.note(saved, "home", 4)
	check("home +4: 4/10, nothing done", moved and #done == 0 and saved.daily[1].progress == 4)
	done = SandboxTasks.note(saved, "home", 9)
	check("home +9: clamped to 10, done (once: its title and reward)", saved.daily[1].progress == 10 and #done == 1 and done[1].id == "home" and done[1].title == "Bring 10 pieces home"
		and done[1].money == SandboxTasks.rewardOf(SandboxTasks.def("home") :: SandboxTasks.Def, 10) and done[1].weekly == false)
	done, moved = SandboxTasks.note(saved, "home", 3)
	check("… a done task moves no more", not moved and #done == 0 and saved.daily[1].progress == 10)
	SandboxTasks.note(saved, "trips", 1)
	done, moved = SandboxTasks.note(saved, "trips", 1)
	check("9.7 trips is a sum of the truckloads home (one a run): 1 then 1 is 2", moved and saved.daily[2].progress == 2 and #done == 0)
	done = SandboxTasks.note(saved, "trips", 1)
	check("… a third: done", saved.daily[2].progress == 3 and #done == 1 and done[1].id == "trips")
	SandboxTasks.note(saved, "sell", 120)
	SandboxTasks.note(saved, "income", 1500)
	check("sell sums money; income goes to the weekly only", saved.daily[3].progress == 120 and (saved.weekly :: any).progress == 1500)
	done = SandboxTasks.note(saved, "income", 3000)
	check("the weekly done: listed as weekly, clamped", (saved.weekly :: any).progress == 4000 and #done == 1 and done[1].weekly == true and done[1].id == "w_income")
	local before = saved.daily[3].progress
	local junk = true
	for _, amount in { 0, -5, 0 / 0, math.huge, "12" :: any, nil :: any } do
		local d, m = SandboxTasks.note(saved, "sell", amount)
		junk = junk and #d == 0 and not m
	end
	local d, m = SandboxTasks.note(saved, 7 :: any, 5)
	check("garbage amounts and events count nothing (0, < 0, NaN, ∞, a string, nil, a number for the event)", junk and #d == 0 and not m and saved.daily[3].progress == before)
	d, m = SandboxTasks.note(saved, "explode", 5)
	check("an unknown event: nothing", #d == 0 and not m)

	local danny = made({ { "danny", 1 }, { "shown", 8 }, { "upgrade", 1 } })
	d, m = SandboxTasks.note(danny, "danny", 1, { item = "armchair" })
	check("danny: another piece with Danny counts nothing", not m and danny.daily[1].progress == 0)
	d, m = SandboxTasks.note(danny, "danny", 1)
	check("… nor one without its item", not m)
	check("SandboxTasks.itemFor: the sofa while open", SandboxTasks.itemFor(danny, "danny") == "sofa" and SandboxTasks.itemFor(danny, "home") == nil)
	d = SandboxTasks.note(danny, "danny", 1, { item = "sofa" })
	check("… the sofa: done", #d == 1 and danny.daily[1].progress == 1 and d[1].title == "Carry the sofa with Danny")
	check("… then none asked for", SandboxTasks.itemFor(danny, "danny") == nil)
	SandboxTasks.note(danny, "shown", 5)
	SandboxTasks.note(danny, "shown", 3)
	check("shown: the most on show at once (5, then 3: 5)", danny.daily[2].progress == 5)
	SandboxTasks.note(danny, "upgrade", 2)
	check("upgrade: two levels bought, clamped to 1", danny.daily[3].progress == 1)
end

-- ── Claims ──────────────────────────────────────────────────────────────────
do
	local saved = made({ { "home", 10 }, { "clean", 1 }, { "income", 300 } }, { "w_moves", 5 })
	local money, why = SandboxTasks.claim(saved, 1)
	check("a claim before it is done: refused, says why", money == nil and why == "Not done yet.")
	SandboxTasks.note(saved, "home", 10)
	check("claimable: 1", SandboxTasks.claimable(saved) == 1)
	money, why = SandboxTasks.claim(saved, 1)
	check("claim slot 1: its reward and title", money == SandboxTasks.rewardOf(SandboxTasks.def("home") :: SandboxTasks.Def, 10) and why == "Bring 10 pieces home" and saved.daily[1].claimed)
	money, why = SandboxTasks.claim(saved, 1)
	check("… once: claimed already", money == nil and why == "Claimed already.")
	local junk = true
	for _, which in { 0, 4, 1.5, -1, "1", "weeklyx", {}, nil, 0 / 0 } :: { any } do
		local paid, said = SandboxTasks.claim(saved, which)
		junk = junk and paid == nil and said == "No such task."
	end
	check("no such slot (0, 4, 1.5, -1, \"1\", junk, a table, nil, NaN): refused", junk)
	money, why = SandboxTasks.claim(saved, "bonus")
	check("the bonus before every daily is done: refused", money == nil and why == "Finish every daily task first.")
	SandboxTasks.note(saved, "clean", 1)
	SandboxTasks.note(saved, "income", 999)
	check("claimable: the two dailies and the bonus", SandboxTasks.claimable(saved) == 3)
	local paid2 = SandboxTasks.claim(saved, 2)
	local paid3 = SandboxTasks.claim(saved, 3)
	money, why = SandboxTasks.claim(saved, "bonus")
	check("every daily done: the bonus pays AllDaily, once", paid2 ~= nil and paid3 ~= nil and money == T.AllDaily and why == "All the dailies" and saved.bonus
		and SandboxTasks.claim(saved, "bonus") == nil and SandboxTasks.claimable(saved) == 0)
	money, why = SandboxTasks.claim(saved, "weekly")
	check("the weekly before it is done: refused", money == nil and why == "Not done yet.")
	for _ = 1, 5 do
		SandboxTasks.note(saved, "moves", 1)
	end
	money, why = SandboxTasks.claim(saved, "weekly")
	check("the weekly done: its own claim, a bigger reward, once", money == SandboxTasks.rewardOf(SandboxTasks.def("w_moves") :: SandboxTasks.Def, 5) and (money :: number) >= 1000
		and why == "Finish 5 moves" and SandboxTasks.claim(saved, "weekly") == nil)
	local noWeek = made({ { "home", 8 } })
	check("no weekly: claiming it refused", SandboxTasks.claim(noWeek, "weekly") == nil)
	SandboxTasks.note(saved, "home", 5)
	check("a claimed task counts no more", saved.daily[1].progress == 10)
end

-- ── The reset ───────────────────────────────────────────────────────────────
do
	local saved = SandboxTasks.fresh(USER, NOW)
	local first = ids(saved.daily)
	local changed, owed, dayNew, weekNew = SandboxTasks.roll(saved, USER, NOW + 3600)
	check("the same day: no change", not changed and owed.money == 0 and not dayNew and not weekNew and ids(saved.daily) == first)
	-- done two, claimed one; the third not done
	local slotA, slotB = saved.daily[1], saved.daily[2]
	slotA.progress, slotA.claimed = slotA.target, true
	slotB.progress = slotB.target
	saved.daily[3].progress = 0
	changed, owed, dayNew, weekNew = SandboxTasks.roll(saved, USER, NOW + DAY)
	local def = SandboxTasks.def(slotB.id) :: SandboxTasks.Def
	check("the next day (00:00 UTC): new dailies, the done-not-claimed one paid (no bonus: one undone)", changed and dayNew and not weekNew and owed.money == SandboxTasks.rewardOf(def, slotB.target)
		and #owed.titles == 1 and saved.day == SandboxTasks.dayOf(NOW + DAY) and ids(saved.daily) == ids(SandboxTasks.pickDaily(saved.day, USER)) and not saved.bonus, owed.money)
	check("… the new ones start at 0", saved.daily[1].progress == 0 and not saved.daily[1].claimed)
	for _, slot in saved.daily do
		slot.progress = slot.target
	end
	changed, owed = SandboxTasks.roll(saved, USER, NOW + 2 * DAY)
	local all = T.AllDaily
	for _, slot in SandboxTasks.pickDaily(SandboxTasks.dayOf(NOW + DAY), USER) do
		all += SandboxTasks.rewardOf(SandboxTasks.def(slot.id) :: SandboxTasks.Def, slot.target)
	end
	check("all three done, none claimed: the reset pays them and the bonus", changed and owed.money == all and #owed.titles == 4, owed.money)
	local week = saved.week
	local weekly = saved.weekly :: SandboxTasks.Slot
	weekly.progress = weekly.target
	changed, owed, dayNew, weekNew = SandboxTasks.roll(saved, USER, NOW + 5 * DAY) -- (Monday 01:00 UTC)
	check("Monday 00:00 UTC: a new weekly, the done one paid; new dailies too", changed and weekNew and dayNew and saved.week == week + 1
		and owed.money == SandboxTasks.rewardOf(SandboxTasks.def(weekly.id) :: SandboxTasks.Def, weekly.target) and saved.weekly ~= nil and (saved.weekly :: any).progress == 0)
	local now = ids(saved.daily)
	changed, owed = SandboxTasks.roll(saved, USER, NOW + 3 * DAY)
	check("a clock that went back: nothing changes, nothing is paid", not changed and owed.money == 0 and ids(saved.daily) == now)
	local skipSave = SandboxTasks.fresh(USER, NOW, { upgrade = true })
	SandboxTasks.roll(skipSave, USER, NOW + 40 * DAY, { upgrade = true })
	check("the reset's picks take the skip", slotOf(skipSave, "upgrade") == nil)
end

-- ── The save ────────────────────────────────────────────────────────────────
do
	local saved = SandboxTasks.fresh(USER, NOW)
	saved.daily[1].progress = math.min(2, saved.daily[1].target)
	saved.daily[2].claimed = true
	local copy = SandboxTasks.clean(saved) :: SandboxTasks.Saved
	check("a clean save comes back the same", copy ~= nil and ids(copy.daily) == ids(saved.daily) and copy.daily[1].progress == saved.daily[1].progress and copy.daily[2].claimed and copy.day == saved.day
		and copy.week == saved.week and (copy.weekly :: any).id == (saved.weekly :: any).id and copy.bonus == false)
	check("garbage is no save", SandboxTasks.clean(nil) == nil and SandboxTasks.clean(5) == nil and SandboxTasks.clean({}) == nil and SandboxTasks.clean({ day = "x", week = 1 }) == nil
		and SandboxTasks.clean({ day = 0 / 0, week = 1 }) == nil)
	local raw = {
		day = 20000.7, week = -3, bonus = "yes",
		daily = {
			{ id = "home", target = 10, progress = 99, claimed = "true" }, -- (progress past its target: clamped)
			{ id = "home", target = 8, progress = 1 }, -- (twice: dropped)
			{ id = "nope", target = 3 }, -- (unknown)
			{ id = "w_home", target = 60 }, -- (a weekly kind among the dailies)
		},
		weekly = { id = "home", target = 5 }, -- (a daily kind as the weekly: dropped)
	}
	local cleaned = SandboxTasks.clean(raw) :: SandboxTasks.Saved
	check("a garbled save checked: whole day / week, flags as booleans, progress clamped, a kind once, unknown and wrong-pool kinds dropped",
		cleaned ~= nil and cleaned.day == 20000 and cleaned.week == 0 and cleaned.bonus == false and #cleaned.daily == 1 and cleaned.daily[1].progress == 10
		and cleaned.daily[1].claimed == false and cleaned.weekly == nil)
	local negative = SandboxTasks.clean({ day = 1, week = 1, daily = { { id = "sell", target = 0, progress = -4 }, { id = "income", target = 300, progress = 0 / 0 } } }) :: SandboxTasks.Saved
	check("… a 0 target and a NaN progress: no slot / 0", #negative.daily == 1 and negative.daily[1].id == "income" and negative.daily[1].progress == 0)
	local real = { money = 100, sandboxTasksKept = true, sandboxTasks = saved }
	check("fromSave: a real save with the flag has its tasks", SandboxTasks.fromSave(real) ~= nil)
	check("… one without the flag (from before 8.2), a lock-only record (no money) or garbage has none",
		SandboxTasks.fromSave({ money = 100, sandboxTasks = saved }) == nil and SandboxTasks.fromSave({ sandboxTasksKept = true, sandboxTasks = saved }) == nil
		and SandboxTasks.fromSave(nil) == nil and SandboxTasks.fromSave({ money = 1, sandboxTasksKept = true, sandboxTasks = "x" }) == nil)
	check("the flag is Config's", T.Flag == "sandboxTasksKept")
end

-- ── The view ────────────────────────────────────────────────────────────────
do
	local saved = made({ { "home", 10 }, { "sell", 200 }, { "danny", 1 } }, { "w_income", 4000 })
	SandboxTasks.note(saved, "home", 10)
	SandboxTasks.note(saved, "sell", 50)
	local view = SandboxTasks.view(saved, NOW)
	local home, sell = view.daily[1], view.daily[2]
	check("the view: three rows, the bonus (1 of 3), the weekly, the resets, one to claim", #view.daily == 3 and view.bonus.money == T.AllDaily and view.bonus.count == 1
		and view.bonus.total == 3 and not view.bonus.done and view.weekly ~= nil and view.dayLeft == DAY - 3600 and view.weekLeft == 5 * DAY - 3600 and view.ready == 1)
	check("… a row: slot, icon, title, progress, reward, done", home.slot == 1 and home.icon == "📦" and home.title == "Bring 10 pieces home" and home.progress == 10 and home.done
		and not home.claimed and home.unit == nil and home.money == SandboxTasks.rewardOf(SandboxTasks.def("home") :: SandboxTasks.Def, 10))
	check("… money tasks read in $ (unit)", sell.unit == "$" and sell.progress == 50 and not sell.done and (view.weekly :: any).unit == "$" and (view.weekly :: any).slot == "weekly"
		and (view.weekly :: any).weekly == true)
	-- 8.3: the market's: the hot pieces sold a count, what the hot pieces on show earned in $
	local market = made({ { "hotsell", 2 }, { "hotincome", 150 }, { "home", 10 } })
	local done = SandboxTasks.note(market, "hotsell", 1)
	SandboxTasks.note(market, "hotincome", 40)
	local rows = SandboxTasks.view(market, NOW).daily
	check("8.3: hotsell counts the hot pieces sold, hotincome the dollars (unit $)", #done == 0 and rows[1].progress == 1 and rows[1].unit == nil and rows[2].progress == 40 and rows[2].unit == "$")
end

print(if failures == 0 then "ALL CHECKS PASSED" else `{failures} CHECK(S) FAILED`)
