--!strict
-- 6.12.8, the NEXT UP queue (the owner: "once I take a job I can't add more. I want a list where I have the jobs and
-- how much I earn, and add even all of them so I don't have to keep taking them again. Somewhere show what I'll do
-- next."): what goes where on the board's + ADD, + QUEUE and ADD ALL, what the queue starts next, and the words the
-- phone, the J board and the HUD share. Pure Luau (no Roblox API): server/JobQueue.luau decides with it (the facts
-- from server/Jobs.luau), client/PhoneApps.luau, client/DispatchUi.luau, client/Phone.luau and client/Objective.luau
-- show it; tested in tests/jobqueue_test.luau. Config.Jobs.Queue holds its numbers.
--
--   JobQueue.max()                        jobs waiting at most (Queue.Max)
--   JobQueue.queueable(kind)              may a board job of this kind wait in the queue (Kind)?
--   JobQueue.fits(run, job)               may it join the run now (5.2's + ADD rules: the same transport, both
--                                         stack, fewer than Orders.Max open, its pieces in the free room)?
--   JobQueue.place(run, job, queued)      one row: "start" (no run: ACCEPT) | "add" | "queue" | nil, and why not
--   JobQueue.plan(run, rooms, jobs, queued)   ADD ALL: every job in board order into the run (a run started by the
--                                         first one that can start when there is none), the rest into the queue
--   JobQueue.prefer(jobs, mode)           ADD ALL with no run: the jobs of the transport you are on first
--   JobQueue.nextStep(run, head)          what the queue's next job does now: "start" | "add" | nil and why it waits
--   JobQueue.effectiveHead(jobs)          (review) the first queued job not locked for good (the locked ones are
--                                         stepped past: they keep their reason, ✕ drops them)
--   JobQueue.runLines(job)                YOUR RUN: the open orders of a Job payload as lines, their pay, the next stop
--   JobQueue.jobsLine(open, queued, fresh)   the phone's JOBS tile ("Your run · 2 orders · 3 next")
--   JobQueue.money(n), route(from, to), nextUpText(entry), startingText(entry, s), closedText(place),
--   addAllText(started, added, queued, total), pausedLine(why)   the words
-- 6.12.8 review: a failed delivery, a lost order, a mission or an employer's job PAUSE the queue (RESUME, CLEAR ALL);
-- with no job a queued job starts after Queue.StartDelay s ("NEXT UP in 4 s: …"); ADD ALL never starts a run with a
-- job that does not stack, and never takes a special or the paper round.

local Config = require(script.Parent.Config)
local JobRules = require(script.Parent.JobRules)

local JobQueue = {}

-- What kind of offer a board row is (server/Jobs.luau fills it): a job type of its own (a board special, an employer's,
-- the Freight Run), a mission, the tutorial's, DUO.
-- 6.12.8 review: and the paper round (one order on its own, its own hours: it never waits in the queue).
export type Kind = { special: boolean?, mission: boolean?, tutorial: boolean?, duo: boolean?, round: boolean? }

-- The run as the queue sees it (nil: no run): its transport, the orders open, the free room (5.2's orderRoom) and
-- whether it takes more orders at all (5.2's runStacks).
export type Run = { mode: string, open: number, free: number, stacks: boolean }

-- One job (a board row or the queue's head): `ready` = nothing but the run keeps it from starting now (its vehicle is
-- there, it fits what you carry, you are not in somebody's crew); `why` = what it waits for when it is not;
-- `locked` = it may not be taken at all (the level, the licence, no vehicle / bike of your own, too big);
-- `queueable` = it may wait in the queue (an ordinary board job, not locked). `fits` (review): the server's own 5.2
-- stackCheck against the run as it is now (nil without a run): it decides + ADD; the run's numbers only plan ahead.
export type Job = {
	id: number?,
	mode: string,
	pieces: number,
	pay: number,
	stackable: boolean,
	queueable: boolean,
	ready: boolean,
	why: string?,
	locked: boolean?,
	fits: boolean?,
}

export type Step = { id: number?, how: string } -- "start" | "add" | "queue"
export type Plan = { steps: { Step }, started: number, added: number, queued: number, total: number, count: number }

-- Jobs waiting at most.
function JobQueue.max(): number
	return math.max(1, math.floor(Config.Jobs.Queue.Max))
end

-- May a board job of this kind wait in the queue? The ordinary board jobs only (on foot, by bike, a car tier): never a
-- special, a mission, the tutorial's, DUO or (review) the paper round.
function JobQueue.queueable(kind: Kind): boolean
	return not (kind.special or kind.mission or kind.tutorial or kind.duo or kind.round)
end

-- May `job` join the run now: a run that takes more, a job that stacks, the same transport, and then the server's own
-- check (`job.fits`: 5.2's stackCheck), else 5.2's room and Orders.Max from the run's numbers (JobRules.canAddOrder)?
-- Else why: "after your run" (it never joins this run) or "when your run has room".
function JobQueue.fits(run: Run?, job: Job): (boolean, string?)
	if not run then
		return false, "no run"
	end
	if not run.stacks or not job.stackable or job.mode ~= run.mode then
		return false, "after your run"
	end
	local ok = if job.fits ~= nil then job.fits else JobRules.canAddOrder(run.mode, run.open, job.pieces, run.free)
	if not ok then
		return false, "when your run has room"
	end
	return true, nil
end

-- One board row: with no run "start" (ACCEPT) when it can start now; on a run "add" (+ ADD) when it joins; else
-- "queue" (+ QUEUE) when it may wait and the queue has room (`queued` waiting now); else nil and why not.
function JobQueue.place(run: Run?, job: Job, queued: number): (string?, string?)
	if job.locked then
		return nil, "locked"
	end
	if not run then
		if job.ready then
			return "start", nil
		end
	elseif job.ready and JobQueue.fits(run, job) then
		return "add", nil
	end
	if not job.queueable then
		return nil, "one at a time"
	elseif queued >= JobQueue.max() then
		return nil, "queue full"
	end
	return "queue", nil
end

-- ADD ALL: the jobs in board order. Without a run the first one that can start AND stacks starts it (its transport,
-- one order, the room `rooms[mode]` minus its pieces; review: never a one-at-a-time job, which would take nothing
-- more); then every job that joins that run is added (Orders.Max, the room; the server's `fits` may veto the first),
-- the rest queue up to Queue.Max (`queued` waiting already). Locked jobs, specials and the paper round (not
-- queueable) are skipped. `total` is what the jobs taken pay.
function JobQueue.plan(run: Run?, rooms: { [string]: number }, jobs: { Job }, queued: number): Plan
	local plan: Plan = { steps = {}, started = 0, added = 0, queued = 0, total = 0, count = 0 }
	local current: Run? = if run then { mode = run.mode, open = run.open, free = run.free, stacks = run.stacks } else nil
	local waiting = queued
	for _, job in jobs do
		if job.locked or not job.queueable then
			continue
		end
		local how: string? = nil
		if current == nil then
			if job.ready and job.stackable then
				how = "start"
				current = { mode = job.mode, open = 1, free = math.max(0, math.floor(rooms[job.mode] or 0) - job.pieces), stacks = true }
				plan.started += 1
			end
		elseif job.ready and job.fits ~= false and JobQueue.fits(current, { mode = job.mode, pieces = job.pieces, pay = job.pay, stackable = job.stackable, queueable = true, ready = true }) then
			how = "add"
			current.open += 1
			current.free = math.max(0, current.free - job.pieces)
			plan.added += 1
		end
		if not how and job.queueable and waiting < JobQueue.max() then
			how = "queue"
			waiting += 1
			plan.queued += 1
		end
		if how then
			table.insert(plan.steps, { id = job.id, how = how })
			plan.total += math.max(0, job.pay)
		end
	end
	plan.count = #plan.steps
	return plan
end

-- ADD ALL with no run: the jobs of the transport you are on (`mode`: "bike" on your bike, "car" in your car; nil on
-- foot: the board's order) first, the rest after them in the board's order, so the run it starts is one you can do now.
function JobQueue.prefer(jobs: { Job }, mode: string?): { Job }
	if not mode then
		return jobs
	end
	local first: { Job }, rest: { Job } = {}, {}
	for _, job in jobs do
		table.insert(if job.mode == mode then first else rest, job)
	end
	for _, job in rest do
		table.insert(first, job)
	end
	return first
end

-- (review) The queued job that comes next: the first one not locked for good (its index), else nil; the locked ones
-- before it are stepped past (they keep their reason until ✕ drops them).
function JobQueue.effectiveHead(jobs: { Job }): number?
	for index, job in jobs do
		if not job.locked then
			return index
		end
	end
	return nil
end

-- What the queue's next job (`head`) does now: no run, "start" when it is ready; on a run, "add" when it joins it;
-- else nil and why it waits (the run first: "after your run" / "when your run has room"; then its own `why`).
function JobQueue.nextStep(run: Run?, head: Job?): (string?, string?)
	if not head then
		return nil, nil
	end
	if run then
		local fits, why = JobQueue.fits(run, head)
		if not fits then
			return nil, why
		end
		if not head.ready then
			return nil, head.why or "waiting"
		end
		return "add", nil
	end
	if not head.ready then
		return nil, head.why or "waiting"
	end
	return "start", nil
end

-- "$1,240".
function JobQueue.money(amount: number): string
	local text = tostring(math.floor(amount))
	local formatted = string.reverse((string.gsub(string.reverse(text), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return "$" .. formatted
end

-- "Luigi's Pizza → 12 Elm St" (what is known of it).
function JobQueue.route(from: string?, to: string?): string
	if from and to then
		return `{from} → {to}`
	end
	return from or to or ""
end

-- 🚶 on foot, 🚲 by bike, else the job's stars.
function JobQueue.icon(mode: any, stars: any): string
	if mode == "foot" then
		return "🚶"
	elseif mode == "bike" then
		return "🚲"
	end
	return string.rep("★", math.max(1, math.floor(tonumber(stars) or 1)))
end

-- The toast when a queued job starts: "NEXT UP: Pizza · Luigi's → 12 Elm St · $120".
function JobQueue.nextUpText(entry: { [string]: any }): string
	local route = JobQueue.route(entry.from, entry.to)
	return `NEXT UP: {entry.cargo or "Delivery"}{if route ~= "" then ` · {route}` else ""} · {JobQueue.money(tonumber(entry.pay) or 0)}`
end

-- (review) The toast when the queue will start a job with no run going: "NEXT UP in 4 s: Pizza · Luigi's → 12 Elm St ·
-- $120 (JOBS to pause)" (PAUSE or ✕ meanwhile cancels it).
function JobQueue.startingText(entry: { [string]: any }, seconds: number): string
	local text = (string.gsub(JobQueue.nextUpText(entry), "^NEXT UP:", `NEXT UP in {math.max(0, math.ceil(seconds))} s:`))
	return `{text} (JOBS to pause)`
end

-- (review) A queued job whose place is shut by now: "Luigi's Pizza is closed now: dropped from NEXT UP".
function JobQueue.closedText(place: string): string
	return `{place} is closed now: dropped from NEXT UP`
end

-- (review) NEXT UP's line while it is paused.
function JobQueue.pausedLine(why: string?): string
	return `⏸ Paused{if why and why ~= "" then ` {why}` else ""} · RESUME to go on`
end

-- ADD ALL's toast: what started, joined the run and queued, and what it pays.
function JobQueue.addAllText(started: number, added: number, queued: number, total: number): string
	if started + added + queued == 0 then
		return "Nothing to add: the board's jobs are locked, or NEXT UP is full."
	end
	local parts: { string } = {}
	if started > 0 then
		table.insert(parts, `{started} started`)
	end
	if added > 0 then
		table.insert(parts, `{added} added to your run`)
	end
	if queued > 0 then
		table.insert(parts, `{queued} queued`)
	end
	return `ADD ALL · {table.concat(parts, ", ")} · {JobQueue.money(total)}`
end

-- YOUR RUN from a Job payload (server/Jobs.luau: its `orders`, `stopLabel`): one line an open order (its icon, what,
-- from → to, pay, clock end), what they pay together and the next stop. A payload without orders (an older server, a
-- short payload) is one line of its own fields.
export type RunLine = { id: number?, icon: string, title: string, route: string, pay: number, endsAt: number?, focused: boolean }
function JobQueue.runLines(job: any): ({ RunLine }, number, string?)
	local lines: { RunLine } = {}
	local total = 0
	if type(job) ~= "table" then
		return lines, 0, nil
	end
	local orders = if type(job.orders) == "table" then job.orders else nil
	if orders and #orders > 0 then
		for _, entry in orders do
			if type(entry) ~= "table" or entry.state ~= "open" then
				continue
			end
			local pay = tonumber(entry.pay) or 0
			total += pay
			table.insert(lines, {
				id = tonumber(entry.id),
				icon = JobQueue.icon(entry.mode or job.mode, entry.stars or job.stars),
				title = tostring(entry.title or entry.cargo or "Order"),
				route = JobQueue.route(entry.from, entry.to),
				pay = pay,
				endsAt = tonumber(entry.endsAt),
				focused = entry.focused == true,
			})
		end
	else
		local pay = tonumber(job.pay) or 0
		total = pay
		table.insert(lines, {
			id = nil,
			icon = JobQueue.icon(job.mode, job.stars),
			title = `{job.cargo or "Cargo"} → {job.customer or "a customer"}`,
			route = JobQueue.route(nil, job.address),
			pay = pay,
			endsAt = tonumber(job.endsAt),
			focused = true,
		})
	end
	local nextStop = if type(job.stopLabel) == "string" and job.stopLabel ~= "" then job.stopLabel else nil
	return lines, total, nextStop
end

-- The phone's JOBS tile: during a run its orders and the jobs waiting ("Your run · 2 orders · 3 next"), off duty the
-- jobs waiting, the new runs on the board, or what to do.
function JobQueue.jobsLine(open: number, queued: number, fresh: number, paused: boolean?): string
	local tail = if queued > 0 then ` · {queued} next{if paused then " (paused)" else ""}` else ""
	if open > 0 then
		return `Your run · {if open > 1 then `{open} orders` else "orders"}{tail}`
	elseif queued > 0 then
		return `Next up · {queued} {if paused then "paused" else "waiting"}`
	elseif fresh > 0 then
		return `{fresh} new {if fresh == 1 then "run" else "runs"} on the board`
	end
	return "Take a delivery"
end

return JobQueue
