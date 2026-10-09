-- Logic test of 6.14's fun grind (shared/Shift.luau, Config.Jobs.Shift): the shift (counting, finishing and starting
-- over at 0, the idle reset, the admin's count), its pay by the driver level (the steps, rounded money, growing with
-- the level), the client's view and bar, and how the 4.7 streak of good jobs reads (the next job's multiplier, the
-- chip's lines, the broken chip, the board's caption) with JobRules' own rules unchanged.
-- Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local JobRules = require("./JobRules")
local Shift = require("./Shift")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Jobs.Shift
local R = Config.Jobs.Rating

-- ── The tuning ────────────────────────────────────────────────────────────
check("the tuning: Jobs, Money, Xp, LevelScale, MoneyStep, IdleReset", T.Jobs >= 2 and T.Money > 0 and T.Xp > 0 and T.LevelScale >= 0 and T.MoneyStep >= 1 and T.IdleReset >= 300, `{T.Jobs} {T.Money} {T.Xp} {T.LevelScale} {T.MoneyStep} {T.IdleReset}`)
check("the shift is 5 jobs (the owner's pick)", T.Jobs == 5, T.Jobs)
-- The idle reset is longer than the longest ordinary job's clock (Economy.timeLimit: TimeBase + 4000 studs / 22 s ≈ 3.5 min).
check("idle reset longer than any job's clock", T.IdleReset > Config.Jobs.TimeBase + 4000 * Config.Jobs.TimePerStud + 120, T.IdleReset)

-- ── Counting ──────────────────────────────────────────────────────────────
do
	local s = Shift.new()
	check("a new shift: 0, no shift done", s.count == 0 and s.shifts == 0 and s.lastAt == nil and Shift.current(s, 0) == 0)
	local now = 1000
	local finished = {}
	for i = 1, T.Jobs - 1 do
		now += 120
		table.insert(finished, Shift.count(s, now))
		check(`delivery {i}: {i}/{T.Jobs}`, s.count == i and Shift.current(s, now) == i, s.count)
	end
	check("not done before the last", table.find(finished, true) == nil)
	now += 120
	check("the last one finishes the shift", Shift.count(s, now) == true)
	check("… back at 0, one shift done", s.count == 0 and s.shifts == 1 and Shift.current(s, now) == 0, `{s.count} {s.shifts}`)
	now += 60
	check("a new shift goes on", Shift.count(s, now) == false and s.count == 1)
	-- A second shift in a row.
	for _ = 2, T.Jobs do
		now += 60
		Shift.count(s, now)
	end
	check("two shifts done", s.shifts == 2 and s.count == 0, `{s.shifts} {s.count}`)
end

-- ── The idle reset ────────────────────────────────────────────────────────
do
	local s = Shift.new()
	Shift.count(s, 0)
	Shift.count(s, 100)
	Shift.count(s, 200)
	check("3 in", Shift.current(s, 200) == 3)
	check("right at IdleReset: still 3", Shift.current(s, 200 + T.IdleReset) == 3)
	check("past IdleReset: 0 (without a count)", Shift.current(s, 200 + T.IdleReset + 1) == 0)
	check("the next delivery after the gap starts over at 1", Shift.count(s, 200 + T.IdleReset + 5) == false and s.count == 1, s.count)
	-- A long gap never finishes a shift on its own.
	local t = Shift.new()
	for i = 1, T.Jobs - 1 do
		Shift.count(t, i * 10)
	end
	check("4 of 5, then a long break: the fifth is 1, not done", Shift.count(t, 10 * T.Jobs + T.IdleReset + 1) == false and t.count == 1 and t.shifts == 0)
	-- A gap just under the reset each time still counts: "in one go" is between two deliveries.
	local u = Shift.new()
	local now = 0
	local done = false
	for _ = 1, T.Jobs do
		now += T.IdleReset - 1
		done = Shift.count(u, now)
	end
	check("every gap under IdleReset: done", done and u.shifts == 1)
end

-- ── The admin's count ─────────────────────────────────────────────────────
do
	local s = Shift.new()
	Shift.set(s, T.Jobs - 1, 50)
	check("set to Jobs − 1", s.count == T.Jobs - 1 and Shift.current(s, 60) == T.Jobs - 1)
	check("… the next one finishes it", Shift.count(s, 70) == true and s.shifts == 1)
	Shift.set(s, 99, 80)
	check("set clamps to Jobs − 1", s.count == T.Jobs - 1)
	Shift.set(s, -3, 90)
	check("set clamps to 0", s.count == 0)
	Shift.set(s, 0 / 0, 95)
	check("set: NaN is 0", s.count == 0)
end

-- ── The pay ───────────────────────────────────────────────────────────────
do
	local money1, xp1 = Shift.pay(1)
	check("level 1: Money and Xp", money1 == T.Money and xp1 == T.Xp, `{money1} {xp1}`)
	local last = 0
	local grows = true
	for level = 1, Config.Levels.MaxLevel do
		local money, xp = Shift.pay(level)
		local scale = 1 + T.LevelScale * (level - 1)
		if money % T.MoneyStep ~= 0 or math.abs(money - T.Money * scale) > T.MoneyStep / 2 or math.abs(xp - T.Xp * scale) > 0.5 then
			check(`level {level}: × {scale}`, false, `{money} {xp}`)
		end
		if money < last then
			grows = false
		end
		last = money
	end
	check("the pay grows with the level, rounded to MoneyStep", grows)
	local money7, xp7 = Shift.pay(7)
	check("level 7: $300 and 250 XP (the README's numbers)", money7 == 300 and xp7 == 250, `{money7} {xp7}`)
	local high, highXp = Shift.pay(99)
	local top, topXp = Shift.pay(Config.Levels.MaxLevel)
	check("past the top level: the top level's pay", high == top and highXp == topXp)
	local low, lowXp = Shift.pay(0 / 0)
	check("NaN or below 1: level 1's pay", low == money1 and lowXp == xp1 and Shift.pay(-5) == money1)
	-- A shift is worth having but no jackpot: at level 1 about a quarter to a half of five foot jobs' pay.
	local footFive = 5 * (Config.Jobs.Foot.PayMin + Config.Jobs.Foot.PayMax) / 2
	check("level 1: 15 – 50 % of five foot jobs", money1 >= footFive * 0.15 and money1 <= footFive * 0.5, `{money1} of {footFive}`)
end

-- ── The view and the bar ──────────────────────────────────────────────────
do
	local s = Shift.new()
	local v = Shift.view(s, 0)
	check("view of a new shift", v.count == 0 and v.target == T.Jobs and v.idleUntil == nil and v.shifts == 0)
	Shift.count(s, 500)
	Shift.count(s, 600)
	v = Shift.view(s, 650)
	check("view: 2 of 5, ends IdleReset after the last", v.count == 2 and v.idleUntil == 600 + T.IdleReset, v.idleUntil)
	v = Shift.view(s, 600 + T.IdleReset + 1)
	check("view after the gap: 0, no end", v.count == 0 and v.idleUntil == nil)
	local bar = Shift.bar(3)
	check("the bar: 3 of 5 lit", #bar == T.Jobs and bar[1] and bar[3] and not bar[4] and not bar[5])
	local empty, full = Shift.bar(0), Shift.bar(T.Jobs)
	check("the bar: none and all", not empty[1] and full[T.Jobs])
end

-- ── The streak, as it reads (JobRules' rules unchanged) ───────────────────
do
	check("JobRules: a ★★ job makes the streak one longer, a ★ one ends it", JobRules.nextStreak(3, 2) == 4 and JobRules.nextStreak(3, 3) == 4 and JobRules.nextStreak(3, 1) == 0)
	check("JobRules: StreakStep a job, StreakMax at most", math.abs(JobRules.streakBonus(3) - 3 * R.StreakStep) < 1e-9 and JobRules.streakBonus(100) == R.StreakMax)
	check("the next job's share is the streak one longer", math.abs(Shift.nextBonus(3) - JobRules.streakBonus(4)) < 1e-9 and math.abs(Shift.nextBonus(0) - R.StreakStep) < 1e-9)
	-- What the next ★★+ job pays matches what the result then says (JobRules.ratedPay with the streak after it).
	local streak = 3
	local after = JobRules.nextStreak(streak, 2)
	local _, _, streakPart = JobRules.ratedPay(1000, 2, after)
	check("the chip's promise is the pay's streak part", streakPart == math.floor(1000 * Shift.nextBonus(streak) + 0.5), streakPart)
	check("times: ×1.05 ×1.1 ×1.2 ×1.25 ×1", Shift.times(0.05) == "×1.05" and Shift.times(0.1) == "×1.1" and Shift.times(0.2) == "×1.2" and Shift.times(0.25) == "×1.25" and Shift.times(0) == "×1", `{Shift.times(0.05)} {Shift.times(0.1)} {Shift.times(0.2)} {Shift.times(0.25)} {Shift.times(0)}`)
	check("no chip at 0", Shift.streakChip(0) == nil and Shift.streakChip(-2) == nil)
	local one = Shift.streakChip(1) :: { title: string, sub: string, max: boolean }
	check("streak 1: ON A ROLL ×1.1, 1 GOOD JOB", one.title == "ON A ROLL ×1.1" and one.sub == "1 GOOD JOB IN A ROW" and not one.max, `{one.title} / {one.sub}`)
	local three = Shift.streakChip(3) :: { title: string, sub: string, max: boolean }
	check("streak 3: ×1.2, 3 GOOD JOBS", three.title == "ON A ROLL ×1.2" and three.sub == "3 GOOD JOBS IN A ROW", `{three.title} / {three.sub}`)
	local maxAt = math.ceil(R.StreakMax / R.StreakStep - 1e-9)
	local top = Shift.streakChip(maxAt) :: { title: string, sub: string, max: boolean }
	check("at the top: MAX, ×1.25", top.max and top.title == `ON A ROLL {Shift.times(R.StreakMax)}` and string.find(top.sub, "MAX", 1, true) ~= nil, `{top.title} / {top.sub}`)
	local before = Shift.streakChip(maxAt - 1) :: { title: string, sub: string, max: boolean }
	check("one under the top: not MAX yet, but the next pays the most", not before.max and before.title == `ON A ROLL {Shift.times(R.StreakMax)}`, before.title)
	local long = Shift.streakChip(12) :: { title: string, sub: string, max: boolean }
	check("a long streak stays at the top", long.max and long.sub == "12 IN A ROW · MAX", long.sub)
	local lost = Shift.lostChip(4, false)
	local failed = Shift.lostChip(4, true)
	check("the broken chip", lost.title == "STREAK LOST · 4" and string.find(lost.sub, "★", 1, true) ~= nil and failed.sub == "A FAILED JOB ENDS IT", `{lost.title} / {lost.sub} / {failed.sub}`)
	check("the board's caption", Shift.boardText(0) == "" and Shift.boardText(2) == "ON A ROLL: next ★★+ job ×1.15", Shift.boardText(2))
	-- The chip's lines fit its 168 px (the title at 15 px: about 20 characters; the caps at 10 px: about 22).
	local longest = 0
	for n = 1, 120 do
		local chip = Shift.streakChip(n) :: { title: string, sub: string, max: boolean }
		longest = math.max(longest, utf8.len(chip.sub) or #chip.sub)
		if (utf8.len(chip.title) or #chip.title) > 20 then
			check(`streak {n}: a short title`, false, chip.title)
		end
	end
	check("the small line stays short", longest <= 22, longest)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
