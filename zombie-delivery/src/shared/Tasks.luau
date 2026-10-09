--!strict
-- 6.12, the daily and weekly tasks (the owner: "daily and weekly tasks so players come back"). Pure data and rules,
-- Config.Tasks holds the pool and the numbers:
--   * the picks: Daily tasks for a UTC day from DailyPool and one weekly task for a UTC week (weeks start on Monday
--     00:00 UTC) from WeeklyPool, seeded by the day's (week's) number and the UserId: the same all day for one
--     courier, new at 00:00 UTC; no two of one group a day; only the kinds open at the level the day started at.
--     The target comes from the kind's range (in steps, grown with the level for some), the reward is scaled by it.
--   * the save (Tasks.Saved, profile.tasks): only numbers, the picks' ids and flags; the picks are derived again from
--     the day, the UserId and the level (Tasks.daily / weekly). Tasks.clean checks a save, Tasks.fresh starts one.
--   * Tasks.roll: a new day (week) resets the dailies (the weekly) and pays what was done but not claimed;
--     Tasks.note: progress (clamped to the target), the tasks it finished; Tasks.claim: one reward, once (the dailies,
--     "bonus" once every daily is done, "weekly"); Tasks.claimable: how many wait; Tasks.view: the client's table;
--     Tasks.orderEvents: what one delivered order counts for.
-- server/Tasks.luau keeps profile.tasks and answers the Tasks remote, client/TasksApp.luau draws the phone's TASKS app,
-- tests/tasks_test.luau checks this module.

local Config = require(script.Parent.Config)

local Tasks = {}

local DAY = 86400
local MOD = 2147483647 -- the Park–Miller generator (2^31 − 1, × 48271): every product stays below 2^53
local MUL = 48271

export type Pick = {
	id: string,
	event: string,
	look: string?,
	night: boolean?,
	title: string,
	target: number,
	money: number,
	xp: number,
	weekly: boolean,
}

export type Saved = {
	day: number, -- the UTC day number (Tasks.dayOf) of the dailies
	level: number, -- the level the day started at (the picks and the rewards)
	ids: { string }, -- the dailies' kind ids (a Config change re-derives other picks: their progress goes)
	progress: { number },
	claimed: { boolean },
	bonus: boolean, -- the all-dailies bonus claimed
	week: number, -- the UTC week number (Tasks.weekOf) of the weekly
	weekLevel: number,
	weekId: string,
	weekProgress: number,
	weekClaimed: boolean,
}

export type Info = { look: string?, night: boolean?, bike: boolean?, stars: number?, pay: number? }

-- ── Time ────────────────────────────────────────────────────────────────────

-- The UTC day number of a Unix time (1970-01-01 is day 0).
function Tasks.dayOf(now: number): number
	return math.floor(now / DAY)
end

-- The UTC week number: weeks start on Monday 00:00 UTC (day 0 was a Thursday, so day 4 is the first Monday).
function Tasks.weekOf(now: number): number
	return math.floor((Tasks.dayOf(now) + 3) / 7)
end

-- When the dailies (the weekly) are new again: the next 00:00 UTC (the next Monday's).
function Tasks.dayEnds(now: number): number
	return (Tasks.dayOf(now) + 1) * DAY
end

function Tasks.weekEnds(now: number): number
	return ((Tasks.weekOf(now) + 1) * 7 - 3) * DAY
end

-- ── The picks ───────────────────────────────────────────────────────────────

-- A stream of numbers in [0, 1) from (a, b, salt): the same seed, the same stream (no Random: tests run outside Roblox).
local function stream(a: number, b: number, salt: number): () -> number
	local state = math.floor(a) % MOD + 1
	state = (state * MUL + math.floor(b) % MOD) % MOD
	state = (state * MUL + salt * 7919) % MOD
	if state == 0 then
		state = 1
	end
	for _ = 1, 4 do
		state = state * MUL % MOD
	end
	return function(): number
		state = state * MUL % MOD
		return (state - 1) / (MOD - 1)
	end
end

local function scaleOf(level: number): number
	return 1 + Config.Tasks.LevelScale * (math.max(1, level) - 1)
end

-- 1234567 → "1,234,567"
local function commas(n: number): string
	local text = tostring(math.floor(n))
	local out = text
	repeat
		local made, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = made
	until count == 0
	return out
end

-- 1234 → "$1,234" (the server's notices)
function Tasks.money(n: number): string
	return "$" .. commas(n)
end

local function titleOf(def: Config.TaskDef, target: number): string
	if target == 1 and def.one then
		return def.one
	end
	return (string.gsub(def.text, "{n}", commas(target)))
end

-- The pick of one kind: its target (in steps from the range, grown with the level) and its reward.
local function make(def: Config.TaskDef, next: () -> number, level: number, weekly: boolean): Pick
	local step = def.step or 1
	local low, high = math.ceil(def.target[1] / step), math.max(math.ceil(def.target[1] / step), math.floor(def.target[2] / step))
	local target = (low + math.min(high - low, math.floor(next() * (high - low + 1)))) * step
	if def.grow then
		target = math.max(step, math.floor(target * (1 + def.grow * (math.max(1, level) - 1)) / step + 0.5) * step)
	end
	local scale = scaleOf(level)
	return {
		id = def.id,
		event = def.event,
		look = def.look,
		night = def.night,
		title = titleOf(def, target),
		target = target,
		money = math.floor(def.money * scale / 5 + 0.5) * 5,
		xp = math.floor(def.xp * scale + 0.5),
		weekly = weekly,
	}
end

-- `count` kinds of `pool` open at `level`, drawn from the stream, never two of one group (or id).
local function draw(pool: { Config.TaskDef }, count: number, next: () -> number, level: number, weekly: boolean): { Pick }
	local open: { Config.TaskDef } = {}
	for _, def in pool do
		if level >= (def.level or 1) then
			table.insert(open, def)
		end
	end
	local picks: { Pick } = {}
	local groups: { [string]: boolean } = {}
	while #picks < count and #open > 0 do
		local index = math.min(#open, 1 + math.floor(next() * #open))
		local def = table.remove(open, index) :: Config.TaskDef
		local group = def.group or def.id
		if not groups[group] then
			groups[group] = true
			table.insert(picks, make(def, next, level, weekly))
		end
	end
	return picks
end

-- The dailies of a UTC day for a courier (UserId) at a level: Config.Tasks.Daily of them, deterministic.
function Tasks.pickDaily(day: number, userId: number, level: number): { Pick }
	return draw(Config.Tasks.DailyPool, Config.Tasks.Daily, stream(day, userId, 1), level, false)
end

-- The weekly of a UTC week for a courier at a level.
function Tasks.pickWeekly(week: number, userId: number, level: number): Pick
	return draw(Config.Tasks.WeeklyPool, 1, stream(week, userId, 2), level, true)[1]
end

-- The picks a save stands for (its day / week, the UserId, its levels).
function Tasks.daily(saved: Saved, userId: number): { Pick }
	return Tasks.pickDaily(saved.day, userId, saved.level)
end

function Tasks.weekly(saved: Saved, userId: number): Pick
	return Tasks.pickWeekly(saved.week, userId, saved.weekLevel)
end

-- The all-dailies bonus at a level.
function Tasks.bonusOf(level: number): (number, number)
	local scale = scaleOf(level)
	return math.floor(Config.Tasks.AllDaily.money * scale / 5 + 0.5) * 5, math.floor(Config.Tasks.AllDaily.xp * scale + 0.5)
end

-- ── The save ────────────────────────────────────────────────────────────────

local function idsOf(picks: { Pick }): { string }
	local ids = {}
	for index, pick in picks do
		ids[index] = pick.id
	end
	return ids
end

local function newDay(saved: Saved, userId: number, day: number, level: number)
	saved.day, saved.level = day, level
	saved.ids = idsOf(Tasks.daily(saved, userId))
	saved.progress, saved.claimed, saved.bonus = {}, {}, false
	for index = 1, #saved.ids do
		saved.progress[index], saved.claimed[index] = 0, false
	end
end

local function newWeek(saved: Saved, userId: number, week: number, level: number)
	saved.week, saved.weekLevel = week, level
	saved.weekId = Tasks.weekly(saved, userId).id
	saved.weekProgress, saved.weekClaimed = 0, false
end

-- A new save for a courier at `now` and their level.
function Tasks.fresh(userId: number, now: number, level: number): Saved
	local saved: Saved = {
		day = 0, level = 1, ids = {}, progress = {}, claimed = {}, bonus = false,
		week = 0, weekLevel = 1, weekId = "", weekProgress = 0, weekClaimed = false,
	}
	newDay(saved, userId, Tasks.dayOf(now), math.max(1, level))
	newWeek(saved, userId, Tasks.weekOf(now), math.max(1, level))
	return saved
end

local function count(value: any, high: number): number
	if type(value) ~= "number" or value ~= value or value <= 0 then
		return 0
	end
	return math.min(value, high)
end

local function whole(value: any, low: number, high: number): number?
	if type(value) ~= "number" or value ~= value then
		return nil
	end
	return math.clamp(math.floor(value), low, high)
end

-- A saved table checked, never trusted: numbers in range, flags as booleans, short ids; nil when it is no save of
-- tasks (Tasks.fresh then). Tasks.roll squares it with the picks.
function Tasks.clean(raw: any): Saved?
	if type(raw) ~= "table" then
		return nil
	end
	local day, week = whole(raw.day, 0, 10 ^ 7), whole(raw.week, 0, 10 ^ 7)
	if not day or not week then
		return nil
	end
	local max = Config.Levels.MaxLevel
	local saved: Saved = {
		day = day,
		level = whole(raw.level, 1, max) or 1,
		ids = {},
		progress = {},
		claimed = {},
		bonus = raw.bonus == true,
		week = week,
		weekLevel = whole(raw.weekLevel, 1, max) or 1,
		weekId = if type(raw.weekId) == "string" and #raw.weekId <= 40 then raw.weekId else "",
		weekProgress = count(raw.weekProgress, 1e9),
		weekClaimed = raw.weekClaimed == true,
	}
	local ids = if type(raw.ids) == "table" then raw.ids else {}
	local progress = if type(raw.progress) == "table" then raw.progress else {}
	local claimed = if type(raw.claimed) == "table" then raw.claimed else {}
	for index = 1, Config.Tasks.Daily do
		saved.ids[index] = if type(ids[index]) == "string" and #ids[index] <= 40 then ids[index] else ""
		saved.progress[index] = count(progress[index], 1e9)
		saved.claimed[index] = claimed[index] == true
	end
	return saved
end

-- What a reset pays: the tasks done and not claimed (and the bonus, every daily done), their titles.
export type Owed = { money: number, xp: number, titles: { string } }

-- Brings a save to `now`: a new UTC day resets the dailies (picked at `level`), a new week the weekly; what was done
-- and not claimed is paid (`owed`). A save whose ids no longer match its picks (Config changed) keeps only the
-- matching slots' progress. Returns whether anything changed, what is owed, and the new-day / new-week flags.
function Tasks.roll(saved: Saved, userId: number, now: number, level: number): (boolean, Owed, boolean, boolean)
	local owed: Owed = { money = 0, xp = 0, titles = {} }
	local changed, dayNew, weekNew = false, false, false
	local picks = Tasks.daily(saved, userId)
	-- (a pick that is not the saved one: its progress is not this task's)
	for index = 1, Config.Tasks.Daily do
		local pick = picks[index]
		if (if pick then pick.id else "") ~= (saved.ids[index] or "") then
			saved.ids[index] = if pick then pick.id else ""
			saved.progress[index], saved.claimed[index] = 0, false
			changed = true
		end
		if pick then
			saved.progress[index] = math.min(saved.progress[index] or 0, pick.target)
		end
	end
	local weekPick = Tasks.weekly(saved, userId)
	if weekPick and weekPick.id ~= saved.weekId then
		saved.weekId, saved.weekProgress, saved.weekClaimed = weekPick.id, 0, false
		changed = true
	end
	if weekPick then
		saved.weekProgress = math.min(saved.weekProgress, weekPick.target)
	end
	local today = Tasks.dayOf(now)
	if today > saved.day then
		local all = #picks > 0
		for index, pick in picks do
			local done = (saved.progress[index] or 0) >= pick.target
			all = all and done
			if done and not saved.claimed[index] then
				owed.money += pick.money
				owed.xp += pick.xp
				table.insert(owed.titles, pick.title)
			end
		end
		if all and not saved.bonus then
			local money, xp = Tasks.bonusOf(saved.level)
			owed.money += money
			owed.xp += xp
			table.insert(owed.titles, "All the dailies")
		end
		newDay(saved, userId, today, math.max(1, level))
		changed, dayNew = true, true
	end
	local thisWeek = Tasks.weekOf(now)
	if thisWeek > saved.week then
		if weekPick and saved.weekProgress >= weekPick.target and not saved.weekClaimed then
			owed.money += weekPick.money
			owed.xp += weekPick.xp
			table.insert(owed.titles, weekPick.title)
		end
		newWeek(saved, userId, thisWeek, math.max(1, level))
		changed, weekNew = true, true
	end
	return changed, owed, dayNew, weekNew
end

-- ── Progress, claims ────────────────────────────────────────────────────────

-- Does an event count for this pick? The same event; a look of its own: only that look; a night one: only at night.
function Tasks.matches(pick: Pick, event: string, info: Info?): boolean
	if pick.event ~= event then
		return false
	end
	if pick.look ~= nil and (info == nil or info.look ~= pick.look) then
		return false
	end
	if pick.night == true and (info == nil or info.night ~= true) then
		return false
	end
	return true
end

-- Counts `amount` of `event` for the save's tasks (not claimed ones, never past the target). Returns the picks it
-- finished just now (the dailies first) and whether any progress moved.
function Tasks.note(saved: Saved, userId: number, event: string, amount: number, info: Info?): ({ Pick }, boolean)
	local finished: { Pick } = {}
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return finished, false
	end
	local moved = false
	for index, pick in Tasks.daily(saved, userId) do
		local have = saved.progress[index] or 0
		if not saved.claimed[index] and have < pick.target and Tasks.matches(pick, event, info) then
			saved.progress[index] = math.min(pick.target, have + amount)
			moved = true
			if saved.progress[index] >= pick.target then
				table.insert(finished, pick)
			end
		end
	end
	local weekly = Tasks.weekly(saved, userId)
	if weekly and not saved.weekClaimed and saved.weekProgress < weekly.target and Tasks.matches(weekly, event, info) then
		saved.weekProgress = math.min(weekly.target, saved.weekProgress + amount)
		moved = true
		if saved.weekProgress >= weekly.target then
			table.insert(finished, weekly)
		end
	end
	return finished, moved
end

-- Is every daily done (the bonus may be claimed)?
function Tasks.allDone(saved: Saved, userId: number): boolean
	local picks = Tasks.daily(saved, userId)
	for index, pick in picks do
		if (saved.progress[index] or 0) < pick.target then
			return false
		end
	end
	return #picks > 0
end

-- Claims one reward: `slot` a daily's index (1 … Daily), "bonus" (every daily done) or "weekly". Once each. Returns
-- the money, the XP and the title, or nil and why not.
function Tasks.claim(saved: Saved, userId: number, slot: any): (number?, number?, string)
	if slot == "bonus" then
		if saved.bonus then
			return nil, nil, "The bonus is yours already."
		elseif not Tasks.allDone(saved, userId) then
			return nil, nil, "Finish every daily task first."
		end
		saved.bonus = true
		local money, xp = Tasks.bonusOf(saved.level)
		return money, xp, "All the dailies"
	elseif slot == "weekly" then
		local pick = Tasks.weekly(saved, userId)
		if not pick or saved.weekClaimed then
			return nil, nil, "Claimed already."
		elseif saved.weekProgress < pick.target then
			return nil, nil, "Not done yet."
		end
		saved.weekClaimed = true
		return pick.money, pick.xp, pick.title
	end
	local index = if type(slot) == "number" and slot == math.floor(slot) then slot else nil
	local pick = if index then Tasks.daily(saved, userId)[index] else nil
	if not index or not pick then
		return nil, nil, "No such task."
	elseif saved.claimed[index] then
		return nil, nil, "Claimed already."
	elseif (saved.progress[index] or 0) < pick.target then
		return nil, nil, "Not done yet."
	end
	saved.claimed[index] = true
	return pick.money, pick.xp, pick.title
end

-- How many rewards wait to be claimed (the phone's dot).
function Tasks.claimable(saved: Saved, userId: number): number
	local waiting = 0
	for index, pick in Tasks.daily(saved, userId) do
		if not saved.claimed[index] and (saved.progress[index] or 0) >= pick.target then
			waiting += 1
		end
	end
	if not saved.bonus and Tasks.allDone(saved, userId) then
		waiting += 1
	end
	local weekly = Tasks.weekly(saved, userId)
	if weekly and not saved.weekClaimed and saved.weekProgress >= weekly.target then
		waiting += 1
	end
	return waiting
end

-- What one delivered order counts for (server/Jobs.luau payOrder through server/Tasks.luau): its pieces (of its
-- look), a ride on a bike or a scooter, a ★★★ rating, its pay.
function Tasks.orderEvents(pieces: number, info: Info): { { event: string, amount: number } }
	local events = {}
	if pieces > 0 then
		table.insert(events, { event = "deliver", amount = pieces })
		if info.bike == true then
			table.insert(events, { event = "ride", amount = 1 })
		end
		if (info.stars or 0) >= 3 then
			table.insert(events, { event = "stars3", amount = 1 })
		end
	end
	if (info.pay or 0) > 0 then
		table.insert(events, { event = "earn", amount = info.pay or 0 })
	end
	return events
end

-- How a task's progress reads: "$" before money (tips, pay), else a count.
local function unitOf(pick: Pick): string?
	return if pick.event == "tips" or pick.event == "earn" then "$" else nil
end

-- The client's table (the Tasks remote's "state"): every task's title, progress, unit, reward and flags, the bonus,
-- when the dailies and the weekly are new, how many rewards wait.
function Tasks.view(saved: Saved, userId: number, now: number): { [string]: any }
	local daily = {}
	for index, pick in Tasks.daily(saved, userId) do
		local have = math.min(saved.progress[index] or 0, pick.target)
		table.insert(daily, {
			slot = index,
			id = pick.id,
			title = pick.title,
			target = pick.target,
			progress = math.floor(have),
			unit = unitOf(pick),
			money = pick.money,
			xp = pick.xp,
			done = have >= pick.target,
			claimed = saved.claimed[index] == true,
		})
	end
	local money, xp = Tasks.bonusOf(saved.level)
	local weekly = Tasks.weekly(saved, userId)
	return {
		daily = daily,
		bonus = { money = money, xp = xp, done = Tasks.allDone(saved, userId), claimed = saved.bonus },
		weekly = if weekly then {
			slot = "weekly",
			id = weekly.id,
			title = weekly.title,
			target = weekly.target,
			progress = math.floor(math.min(saved.weekProgress, weekly.target)),
			unit = unitOf(weekly),
			money = weekly.money,
			xp = weekly.xp,
			done = saved.weekProgress >= weekly.target,
			claimed = saved.weekClaimed,
		} else nil,
		dayEnds = Tasks.dayEnds(now),
		weekEnds = Tasks.weekEnds(now),
		ready = Tasks.claimable(saved, userId),
	}
end

return Tasks
