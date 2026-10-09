--!strict
-- 6.14, the fun grind (the owner: "Jobs are the obvious daily work: you have to grind ... I want it to be a bit MORE
-- grind, but a FUN grind"): the shift's pay and how the streak of good jobs reads on the HUD. Pure Luau (no Roblox
-- API), Config.Jobs.Shift holds the numbers; server/Shift.luau keeps the shifts, client/GrindChips.luau draws the
-- chips and the SHIFT DONE moment, client/Hud.luau's result and client/DispatchUi.luau's caption use the words;
-- tested in tests/shift_test.luau.
--
-- The shift: every job finished and paid to a courier counts one (server/Jobs.luau payOrder: a board job, on foot, by
-- bike, an employer's job, a mission; a run of stacked orders once, at its last order (6.14 review); a crew member
-- there with you counts their own; not a road event's add-on).
-- Config.Jobs.Shift.Jobs of them in one go (never more than IdleReset seconds from one to the next) pay the shift
-- (Money and Xp × (1 + LevelScale × (level − 1))) and a new one starts at 0. A failed job does not count and does
-- not reset it: the streak already punishes a failure, the shift only rewards keeping at it. One play session: the
-- server keeps it per player and never saves it.
--   Shift.new()                    a courier's shift as the session starts
--   Shift.current(state, now)      the deliveries toward the shift now (0 once IdleReset has passed since the last)
--   Shift.count(state, now)        one delivery paid; true when it finished the shift (then 0 again)
--   Shift.set(state, count, now)   the count set (the admin panel), 0 … Jobs − 1
--   Shift.pay(level)               the shift's pay at a driver level: (money, xp)
--   Shift.view(state, now)         the client's table { count, target, idleUntil?, shifts } (the State, the result)
--   Shift.bar(count)               the bar's segments: { true, true, true, false, false } for 3 of 5
--
-- The streak on the HUD (4.7's streak of good jobs, shared/JobRules.luau, its rules unchanged: a job rated ★★ or
-- better makes it one longer and pays StreakStep × its length, at most StreakMax; a ★ job or a failed one ends it):
--   Shift.nextBonus(streak)        the share the next ★★+ job's pay gets (the streak is one longer then)
--   Shift.times(bonus)             "×1.2": the pay × this
--   Shift.streakChip(streak)       the ON A ROLL chip's two lines (nil at 0): "ON A ROLL ×1.2", "4 GOOD JOBS IN A ROW"
--   Shift.lostChip(lost, failed)   the chip as it breaks: "STREAK LOST · 4", why
--   Shift.boardText(streak)        the job board's caption part: "ON A ROLL: next ★★+ job ×1.2" ("" without a streak)

local Config = require(script.Parent.Config)
local JobRules = require(script.Parent.JobRules)

local Shift = {}

export type State = {
	count: number, -- deliveries toward the shift
	lastAt: number?, -- when the last one counted (server time)
	shifts: number, -- shifts finished this session
}

export type View = {
	count: number,
	target: number,
	idleUntil: number?, -- the shift starts over after this (server time; nil at 0)
	shifts: number,
}

function Shift.new(): State
	return { count = 0, lastAt = nil, shifts = 0 }
end

local function target(): number
	return math.max(1, math.floor(Config.Jobs.Shift.Jobs))
end

-- The deliveries toward the shift at `now`: the count, or 0 once more than IdleReset seconds passed since the last.
function Shift.current(state: State, now: number): number
	local last = state.lastAt
	if state.count > 0 and last ~= nil and now - last > Config.Jobs.Shift.IdleReset then
		return 0
	end
	return math.clamp(math.floor(state.count), 0, target() - 1)
end

-- One delivery paid at `now`: the shift one further (from 0 after an idle gap). True when it finished the shift: the
-- count is back at 0 and `shifts` one up.
function Shift.count(state: State, now: number): boolean
	state.count = Shift.current(state, now) + 1
	state.lastAt = now
	if state.count >= target() then
		state.count = 0
		state.shifts += 1
		return true
	end
	return false
end

-- The admin panel's count (0 … Jobs − 1), as if the last delivery was just now.
function Shift.set(state: State, count: number, now: number)
	local n = if count == count then math.floor(count) else 0
	state.count = math.clamp(n, 0, target() - 1)
	state.lastAt = now
end

-- The shift's pay at a driver level: Money (rounded to MoneyStep) and Xp, × (1 + LevelScale × (level − 1)).
function Shift.pay(level: number): (number, number)
	local tuning = Config.Jobs.Shift
	local at = if level == level then math.clamp(math.floor(level), 1, Config.Levels.MaxLevel) else 1
	local scale = 1 + tuning.LevelScale * (at - 1)
	local step = math.max(1, tuning.MoneyStep)
	return math.floor(tuning.Money * scale / step + 0.5) * step, math.floor(tuning.Xp * scale + 0.5)
end

function Shift.view(state: State, now: number): View
	local count = Shift.current(state, now)
	local last = state.lastAt
	return {
		count = count,
		target = target(),
		idleUntil = if count > 0 and last ~= nil then last + Config.Jobs.Shift.IdleReset else nil,
		shifts = state.shifts,
	}
end

-- The bar under SHIFT 3/5: one segment a delivery of the shift, the done ones true.
function Shift.bar(count: number): { boolean }
	local segments: { boolean } = {}
	for index = 1, target() do
		segments[index] = index <= count
	end
	return segments
end

-- ── The streak, as it reads ────────────────────────────────────────────────

-- The share of the pay the next job rated ★★ or better gets (the streak is one longer then).
function Shift.nextBonus(streak: number): number
	return JobRules.streakBonus(math.max(0, math.floor(streak)) + 1)
end

-- "×1.2", "×1.05", "×1.25": the pay × (1 + bonus), no trailing zeros.
function Shift.times(bonus: number): string
	local text = string.format("%.2f", 1 + math.max(0, bonus))
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return "×" .. text
end

-- The ON A ROLL chip from one good job on (nil at 0): its big line (what the next ★★+ job's pay is multiplied by)
-- and its small line (the streak; MAX once the bonus cannot grow).
function Shift.streakChip(streak: number): { title: string, sub: string, max: boolean }?
	local n = math.max(0, math.floor(streak))
	if n < 1 then
		return nil
	end
	local max = JobRules.streakBonus(n) >= Config.Jobs.Rating.StreakMax
	return {
		title = `ON A ROLL {Shift.times(Shift.nextBonus(n))}`,
		sub = if max then `{n} IN A ROW · MAX` else `{n} GOOD {if n == 1 then "JOB" else "JOBS"} IN A ROW`,
		max = max,
	}
end

-- The chip as the streak breaks: how long it was, and why (a failed job, else a ★ one).
function Shift.lostChip(lost: number, failed: boolean): { title: string, sub: string }
	return {
		title = `STREAK LOST · {math.max(0, math.floor(lost))}`,
		sub = if failed then "A FAILED JOB ENDS IT" else "A ★ JOB ENDS IT",
	}
end

-- The job board's caption part (client/DispatchUi.luau): "" without a streak.
function Shift.boardText(streak: number): string
	if math.floor(streak) < 1 then
		return ""
	end
	return `ON A ROLL: next ★★+ job {Shift.times(Shift.nextBonus(streak))}`
end

return Shift
