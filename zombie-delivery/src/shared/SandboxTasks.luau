--!strict
-- 8.2 SANDBOX, the daily tasks (the owner: "daily tasks that bring players back"). Pure data and rules (no Roblox at its
-- top level: tests/sandboxtasks_test.luau); Config.SandboxTasks holds the pools and the numbers. The city's tasks
-- (shared/Tasks.luau, the phone's TASKS app) do not run in the sandbox: this is the sandbox's own, the same ideas.
--   * The picks: Config.SandboxTasks.Daily tasks for a UTC day from DailyPool and one weekly task for a UTC week (weeks
--     start on Monday 00:00 UTC) from WeeklyPool, seeded by the day's (the week's) number and the UserId: the same all
--     day for one player, new at 00:00 UTC; never two of one `group` a day; a kind the server says cannot be done
--     (`skip`: its event or its id, e.g. "upgrade" once every upgrade is bought) is never picked. The target comes from
--     the kind's range (in its steps), the reward grows with it (SandboxTasks.rewardOf).
--   * The save (SandboxTasks.Saved, profile.sandboxTasks): the day and the week, each pick as { id, target, progress,
--     claimed }, the bonus's flag. A pick keeps its target all day; its title and reward come from Config (by its id).
--     SandboxTasks.fresh starts one, SandboxTasks.clean checks one (never trusted), SandboxTasks.fromSave is the
--     migration (only a real save written with Config.SandboxTasks.Flag has one).
--   * SandboxTasks.roll: a later UTC day picks new dailies (a later week a new weekly) and pays what was done but not
--     claimed (`owed`); SandboxTasks.note: an event's progress (a sum, or the best one for a `best` kind; never past the
--     target, never on a claimed task) and the tasks it finished; SandboxTasks.claim: one reward, once (a daily's slot,
--     "bonus" once every daily is done, "weekly"); SandboxTasks.claimable: how many wait; SandboxTasks.view: the
--     client's table.
-- server/SandboxTasks.luau keeps profile.sandboxTasks and answers the "SandboxTasks" remote, client/SandboxTasksUi.luau
-- draws the TASKS panel.

local Config = require(script.Parent.Config)

local SandboxTasks = {}

local DAY = 86400
local MOD = 2147483647 -- the Park–Miller generator (2^31 − 1, × 48271): every product stays below 2^53
local MUL = 48271
local MAX_ID = 40 -- a longer id in a save is no task of ours
local MAX_COUNT = 1e9

export type Def = Config.SandboxTaskDef
export type Slot = { id: string, target: number, progress: number, claimed: boolean }
export type Saved = {
	day: number, -- the UTC day number (SandboxTasks.dayOf) of the dailies
	daily: { Slot },
	bonus: boolean, -- the all-dailies bonus claimed
	week: number, -- the UTC week number (SandboxTasks.weekOf) of the weekly
	weekly: Slot?,
}
export type Info = { item: string? }
export type Done = { id: string, title: string, money: number, weekly: boolean }
export type Owed = { money: number, titles: { string } }
export type Row = {
	slot: any, -- 1 … Daily, or "weekly"
	id: string,
	icon: string,
	title: string,
	target: number,
	progress: number,
	unit: string?, -- "$": money (sell, income), else a count
	money: number,
	done: boolean,
	claimed: boolean,
	weekly: boolean,
}
export type View = {
	daily: { Row },
	bonus: { money: number, done: boolean, claimed: boolean, count: number, total: number },
	weekly: Row?,
	dayLeft: number, -- s until the dailies are new
	weekLeft: number, -- s until the weekly is new
	ready: number, -- rewards waiting to be claimed
}

local function tune()
	return Config.SandboxTasks
end

-- ── Time ────────────────────────────────────────────────────────────────────

-- The UTC day number of a Unix time (1970-01-01 is day 0).
function SandboxTasks.dayOf(now: number): number
	return math.floor(now / DAY)
end

-- The UTC week number: weeks start on Monday 00:00 UTC (day 0 was a Thursday, so day 4 is the first Monday).
function SandboxTasks.weekOf(now: number): number
	return math.floor((SandboxTasks.dayOf(now) + 3) / 7)
end

-- s until the dailies (the weekly) are new: the next 00:00 UTC (the next Monday's).
function SandboxTasks.dayLeft(now: number): number
	return (SandboxTasks.dayOf(now) + 1) * DAY - now
end

function SandboxTasks.weekLeft(now: number): number
	return ((SandboxTasks.weekOf(now) + 1) * 7 - 3) * DAY - now
end

-- ── The kinds ───────────────────────────────────────────────────────────────

-- A kind by its id (the dailies' and the weekly's ids differ: "w_" first) and whether it is a weekly one.
function SandboxTasks.def(id: any): (Def?, boolean)
	if type(id) ~= "string" then
		return nil, false
	end
	for _, def in tune().DailyPool do
		if def.id == id then
			return def, false
		end
	end
	for _, def in tune().WeeklyPool do
		if def.id == id then
			return def, true
		end
	end
	return nil, false
end

-- 1234567 → "1,234,567"
local function commas(n: number): string
	local out = tostring(math.floor(n))
	repeat
		local made, count = string.gsub(out, "^(%d+)(%d%d%d)", "%1,%2")
		out = made
	until count == 0
	return out
end

-- 1234 → "$1,234"
function SandboxTasks.money(n: number): string
	return "$" .. commas(n)
end

-- A kind's range in its steps: the lowest and the highest target.
local function rangeOf(def: Def): (number, number, number)
	local step = math.max(1, def.step or 1)
	local low = math.max(1, math.ceil(def.target[1] / step))
	local high = math.max(low, math.floor((def.target[2] or def.target[1]) / step))
	return low, high, step
end

-- The title of a kind at a target ("Bring 12 pieces home"; `one` at 1).
function SandboxTasks.titleOf(def: Def, target: number): string
	if target == 1 and def.one then
		return def.one
	end
	return (string.gsub(def.text, "{n}", commas(target)))
end

-- The reward of a kind at a target: its `money` at the range's low end, TopShare more at its high end ($10 steps).
function SandboxTasks.rewardOf(def: Def, target: number): number
	local low, high, step = rangeOf(def)
	local share = if high > low then math.clamp((target / step - low) / (high - low), 0, 1) else 0
	return math.floor(def.money * (1 + tune().TopShare * share) / 10 + 0.5) * 10
end

-- Is the event's amount money ("$" in the views)?
local function unitOf(def: Def): string?
	return if def.event == "sell" or def.event == "income" then "$" else nil
end

-- ── The picks ───────────────────────────────────────────────────────────────

-- A stream of numbers in [0, 1) from (a, b, salt): the same seed, the same stream (no Random: tests run outside Roblox).
local function stream(a: number, b: number, salt: number): () -> number
	local state = math.floor(a) % MOD + 1
	state = (state * MUL + math.floor(math.abs(b)) % MOD) % MOD
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

-- `count` kinds of `pool` drawn from the stream, never two of one group, none that `skip` names (its event or id).
local function draw(pool: { Def }, count: number, next: () -> number, skip: { [string]: boolean }?): { Slot }
	local open: { Def } = {}
	for _, def in pool do
		if not (skip and (skip[def.event] or skip[def.id])) then
			table.insert(open, def)
		end
	end
	local picks: { Slot } = {}
	local groups: { [string]: boolean } = {}
	while #picks < count and #open > 0 do
		local index = math.min(#open, 1 + math.floor(next() * #open))
		local def = table.remove(open, index) :: Def
		local group = def.group or def.id
		if not groups[group] then
			groups[group] = true
			local low, high, step = rangeOf(def)
			local target = (low + math.min(high - low, math.floor(next() * (high - low + 1)))) * step
			table.insert(picks, { id = def.id, target = target, progress = 0, claimed = false })
		end
	end
	return picks
end

-- The dailies of a UTC day for a player (UserId): Config.SandboxTasks.Daily of them, deterministic.
function SandboxTasks.pickDaily(day: number, userId: number, skip: { [string]: boolean }?): { Slot }
	return draw(tune().DailyPool, tune().Daily, stream(day, userId, 11), skip)
end

-- The weekly of a UTC week for a player (nil: the pool has none open).
function SandboxTasks.pickWeekly(week: number, userId: number, skip: { [string]: boolean }?): Slot?
	return draw(tune().WeeklyPool, 1, stream(week, userId, 12), skip)[1]
end

-- ── The save ────────────────────────────────────────────────────────────────

-- A new save for a player at `now`.
function SandboxTasks.fresh(userId: number, now: number, skip: { [string]: boolean }?): Saved
	local day, week = SandboxTasks.dayOf(now), SandboxTasks.weekOf(now)
	return {
		day = day,
		daily = SandboxTasks.pickDaily(day, userId, skip),
		bonus = false,
		week = week,
		weekly = SandboxTasks.pickWeekly(week, userId, skip),
	}
end

local function whole(value: any, low: number, high: number): number?
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end
	return math.clamp(math.floor(value), low, high)
end

-- One saved pick checked: a known kind of the right pool, a whole target, progress within it; nil for anything else.
local function cleanSlot(raw: any, weekly: boolean): Slot?
	if type(raw) ~= "table" or type(raw.id) ~= "string" or #raw.id > MAX_ID then
		return nil
	end
	local def, isWeekly = SandboxTasks.def(raw.id)
	local target = if type(raw.target) == "number" and raw.target >= 1 then whole(raw.target, 1, MAX_COUNT) else nil
	if not def or isWeekly ~= weekly or not target then
		return nil
	end
	local progress = raw.progress
	if type(progress) ~= "number" or progress ~= progress or progress < 0 then
		progress = 0
	end
	return { id = def.id, target = target, progress = math.min(progress, target), claimed = raw.claimed == true }
end

-- A saved table checked, never trusted: the day and the week whole numbers, known picks (Daily at most, no kind
-- twice), progress within each target, flags as booleans. Nil when it is no save of tasks (fresh then).
function SandboxTasks.clean(raw: any): Saved?
	if type(raw) ~= "table" then
		return nil
	end
	local day, week = whole(raw.day, 0, 1e7), whole(raw.week, 0, 1e7)
	if not day or not week then
		return nil
	end
	local daily: { Slot } = {}
	local seen: { [string]: boolean } = {}
	if type(raw.daily) == "table" then
		for index = 1, tune().Daily do
			local slot = cleanSlot(raw.daily[index], false)
			if slot and not seen[slot.id] then
				seen[slot.id] = true
				table.insert(daily, slot)
			end
		end
	end
	return { day = day, daily = daily, bonus = raw.bonus == true, week = week, weekly = cleanSlot(raw.weekly, true) }
end

-- The migration (server/PlayerData.luau applySaved): only a real save (money in it) written with the flag has tasks;
-- an older one, a new player or a lock-only record has none (nil: the server starts them fresh).
function SandboxTasks.fromSave(saved: any): Saved?
	if type(saved) ~= "table" or saved.money == nil or saved[tune().Flag] ~= true then
		return nil
	end
	return SandboxTasks.clean(saved.sandboxTasks)
end

-- Is every daily done (the bonus may be claimed)?
function SandboxTasks.allDone(saved: Saved): boolean
	for _, slot in saved.daily do
		if slot.progress < slot.target then
			return false
		end
	end
	return #saved.daily > 0
end

local function titleOfSlot(slot: Slot): string
	local def = SandboxTasks.def(slot.id)
	return if def then SandboxTasks.titleOf(def, slot.target) else slot.id
end

local function rewardOfSlot(slot: Slot): number
	local def = SandboxTasks.def(slot.id)
	return if def then SandboxTasks.rewardOf(def, slot.target) else 0
end

-- Brings a save to `now`: a later UTC day picks new dailies, a later week a new weekly (a clock that went back changes
-- nothing); what was done and not claimed is owed (the bonus too, every daily done). Returns whether anything changed,
-- what is owed, and the new-day / new-week flags.
function SandboxTasks.roll(saved: Saved, userId: number, now: number, skip: { [string]: boolean }?): (boolean, Owed, boolean, boolean)
	local owed: Owed = { money = 0, titles = {} }
	local dayNew, weekNew = false, false
	local today = SandboxTasks.dayOf(now)
	if today > saved.day then
		for _, slot in saved.daily do
			if slot.progress >= slot.target and not slot.claimed then
				owed.money += rewardOfSlot(slot)
				table.insert(owed.titles, titleOfSlot(slot))
			end
		end
		if SandboxTasks.allDone(saved) and not saved.bonus then
			owed.money += tune().AllDaily
			table.insert(owed.titles, "All the dailies")
		end
		saved.day, saved.daily, saved.bonus = today, SandboxTasks.pickDaily(today, userId, skip), false
		dayNew = true
	end
	local thisWeek = SandboxTasks.weekOf(now)
	if thisWeek > saved.week then
		local slot = saved.weekly
		if slot and slot.progress >= slot.target and not slot.claimed then
			owed.money += rewardOfSlot(slot)
			table.insert(owed.titles, titleOfSlot(slot))
		end
		saved.week, saved.weekly = thisWeek, SandboxTasks.pickWeekly(thisWeek, userId, skip)
		weekNew = true
	end
	return dayNew or weekNew, owed, dayNew, weekNew
end

-- ── Progress, claims ────────────────────────────────────────────────────────

-- One slot's progress by an event: a sum, or the best (a `best` kind); never past the target, never once claimed.
-- Whether it moved and whether this finished it.
local function advance(slot: Slot, event: string, amount: number, info: Info?): (boolean, boolean)
	local def = SandboxTasks.def(slot.id)
	if not def or def.event ~= event or slot.claimed or slot.progress >= slot.target then
		return false, false
	end
	if def.item ~= nil and (info == nil or info.item ~= def.item) then
		return false, false
	end
	local now = if def.best then math.max(slot.progress, amount) else slot.progress + amount
	now = math.min(now, slot.target)
	if now == slot.progress then
		return false, false
	end
	slot.progress = now
	return true, now >= slot.target
end

-- Counts `amount` of `event` for the save's tasks. Returns the tasks it finished just now (the dailies first) and
-- whether any progress moved. An amount that is no positive finite number counts nothing.
function SandboxTasks.note(saved: Saved, event: string, amount: number, info: Info?): ({ Done }, boolean)
	local finished: { Done } = {}
	if type(event) ~= "string" or type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then
		return finished, false
	end
	local moved = false
	for _, slot in saved.daily do
		local changed, done = advance(slot, event, amount, info)
		moved = moved or changed
		if done then
			table.insert(finished, { id = slot.id, title = titleOfSlot(slot), money = rewardOfSlot(slot), weekly = false })
		end
	end
	local weekly = saved.weekly
	if weekly then
		local changed, done = advance(weekly, event, amount, info)
		moved = moved or changed
		if done then
			table.insert(finished, { id = weekly.id, title = titleOfSlot(weekly), money = rewardOfSlot(weekly), weekly = true })
		end
	end
	return finished, moved
end

-- The item an open task of this event asks for (the danny kind's sofa), nil for none (server/SandboxTasks.luau looks
-- for Danny only then).
function SandboxTasks.itemFor(saved: Saved, event: string): string?
	local slots = table.clone(saved.daily)
	if saved.weekly then
		table.insert(slots, saved.weekly :: Slot)
	end
	for _, slot in slots do
		local def = SandboxTasks.def(slot.id)
		if def and def.event == event and def.item and slot.progress < slot.target then
			return def.item
		end
	end
	return nil
end

-- Claims one reward: `which` a daily's index (1 … Daily), "bonus" (every daily done) or "weekly". Once each. Returns
-- the money and the title, or nil and why not.
function SandboxTasks.claim(saved: Saved, which: any): (number?, string)
	if which == "bonus" then
		if saved.bonus then
			return nil, "The bonus is yours already."
		elseif not SandboxTasks.allDone(saved) then
			return nil, "Finish every daily task first."
		end
		saved.bonus = true
		return tune().AllDaily, "All the dailies"
	end
	local slot: Slot? = nil
	if which == "weekly" then
		slot = saved.weekly
	elseif type(which) == "number" and which == math.floor(which) then
		slot = saved.daily[which]
	end
	if not slot then
		return nil, "No such task."
	elseif slot.claimed then
		return nil, "Claimed already."
	elseif slot.progress < slot.target then
		return nil, "Not done yet."
	end
	slot.claimed = true
	return rewardOfSlot(slot), titleOfSlot(slot)
end

-- How many rewards wait to be claimed (the chip's badge).
function SandboxTasks.claimable(saved: Saved): number
	local waiting = 0
	for _, slot in saved.daily do
		if not slot.claimed and slot.progress >= slot.target then
			waiting += 1
		end
	end
	if not saved.bonus and SandboxTasks.allDone(saved) then
		waiting += 1
	end
	local weekly = saved.weekly
	if weekly and not weekly.claimed and weekly.progress >= weekly.target then
		waiting += 1
	end
	return waiting
end

local function rowOf(slot: Slot, key: any, weekly: boolean): Row?
	local def = SandboxTasks.def(slot.id)
	if not def then
		return nil
	end
	return {
		slot = key,
		id = slot.id,
		icon = def.icon,
		title = SandboxTasks.titleOf(def, slot.target),
		target = slot.target,
		progress = math.floor(math.min(slot.progress, slot.target)),
		unit = unitOf(def),
		money = SandboxTasks.rewardOf(def, slot.target),
		done = slot.progress >= slot.target,
		claimed = slot.claimed,
		weekly = weekly,
	}
end

-- The client's table (the "SandboxTasks" remote's state): every task's row, the bonus, how long until the dailies and
-- the weekly are new, how many rewards wait.
function SandboxTasks.view(saved: Saved, now: number): View
	local daily: { Row } = {}
	local count = 0
	for index, slot in saved.daily do
		local row = rowOf(slot, index, false)
		if row then
			table.insert(daily, row)
			count += if row.done then 1 else 0
		end
	end
	return {
		daily = daily,
		bonus = { money = tune().AllDaily, done = SandboxTasks.allDone(saved), claimed = saved.bonus, count = count, total = #daily },
		weekly = if saved.weekly then rowOf(saved.weekly, "weekly", true) else nil,
		dayLeft = math.max(0, SandboxTasks.dayLeft(now)),
		weekLeft = math.max(0, SandboxTasks.weekLeft(now)),
		ready = SandboxTasks.claimable(saved),
	}
end

return SandboxTasks
