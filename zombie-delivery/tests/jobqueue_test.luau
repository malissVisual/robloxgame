-- Logic test of 6.12.8, the NEXT UP queue (shared/JobQueue.luau, Config.Jobs.Queue): which jobs may queue, + ADD
-- against + QUEUE (the run's room and Orders.Max, the queue's limit), ADD ALL's plan, what the queue starts next, and
-- the words the phone and the J board share.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local JobQueue = require("./JobQueue")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Queue = Config.Jobs.Queue
local MAX = JobQueue.max()

-- The numbers ----------------------------------------------------------------------------------

check("Queue.Max is 6", Queue.Max == 6 and MAX == 6)
check("CheckEvery is a cheap 1 – 2 s check", Queue.CheckEvery >= 1 and Queue.CheckEvery <= 2)
check("RetryAfter is positive", Queue.RetryAfter > 0)
check("the JobQueue remote is rate limited", (Config.Robust.Limits :: any).JobQueue ~= nil and (Config.Robust.Limits :: any).JobQueue > 0)

-- Which kinds can queue ------------------------------------------------------------------------

check("an ordinary board job queues", JobQueue.queueable({}))
check("a special (a board special, an employer's, the Freight Run) never queues", not JobQueue.queueable({ special = true }))
check("a mission never queues", not JobQueue.queueable({ mission = true }))
check("the tutorial's job never queues", not JobQueue.queueable({ tutorial = true }))
check("DUO never queues", not JobQueue.queueable({ duo = true }))
check("review: the paper round never queues (one order on its own, its own hours)", not JobQueue.queueable({ round = true }))
check("review: StartDelay is a short pause before an idle start (about 4 s)", Queue.StartDelay >= 2 and Queue.StartDelay <= 8)

-- A job: on foot, by bike or a car tier --------------------------------------------------------

local function job(mode: string, pieces: number, pay: number, fields: { [string]: any }?): JobQueue.Job
	local f = fields or {}
	return {
		id = f.id,
		mode = mode,
		pieces = pieces,
		pay = pay,
		stackable = f.stackable ~= false,
		queueable = f.queueable ~= false,
		ready = f.ready ~= false,
		why = f.why,
		locked = f.locked == true,
		fits = f.fits,
	}
end
local function run(mode: string, open: number, free: number, stacks: boolean?): JobQueue.Run
	return { mode = mode, open = open, free = free, stacks = stacks ~= false }
end

-- Room and max: + ADD while it fits ------------------------------------------------------------

check("a foot job joins a foot run with room", JobQueue.fits(run("foot", 1, 3), job("foot", 2, 60)))
check("… not past the free room", not JobQueue.fits(run("foot", 1, 1), job("foot", 2, 60)))
local full, fullWhy = JobQueue.fits(run("foot", 2, 9), job("foot", 1, 60))
check("… not past Orders.Max (2 on foot)", not full and fullWhy == "when your run has room", fullWhy)
check("a bike run takes a third bike order (Max 3)", JobQueue.fits(run("bike", 2, 4), job("bike", 2, 90)))
check("a car run takes a fourth ★ order (Max 4)", JobQueue.fits(run("car", 3, 4), job("car", 1, 200)) and not JobQueue.fits(run("car", 4, 4), job("car", 1, 200)))
local other, otherWhy = JobQueue.fits(run("foot", 1, 5), job("bike", 1, 90))
check("another transport never joins: after your run", not other and otherWhy == "after your run", otherWhy)
local big, bigWhy = JobQueue.fits(run("car", 1, 5), job("car", 2, 900, { stackable = false }))
check("a ★★★ / ★★★★ car job never joins: after your run", not big and bigWhy == "after your run", bigWhy)
check("a run that takes no more (a mission) takes nothing", not JobQueue.fits(run("car", 1, 5, false), job("car", 1, 200)))
check("review: the server's stackCheck decides + ADD (a Roof Rack's light piece the run's numbers miss)", JobQueue.fits(run("car", 1, 1), job("car", 2, 200, { fits = true })))
local refused, refusedWhy = JobQueue.fits(run("car", 1, 5), job("car", 1, 200, { fits = false }))
check("review: … and refuses what it refuses: when your run has room", not refused and refusedWhy == "when your run has room", refusedWhy)
check("review: … never past another transport", not JobQueue.fits(run("foot", 1, 5), job("bike", 1, 90, { fits = true })))

-- One row: ACCEPT, + ADD, + QUEUE --------------------------------------------------------------

check("off duty a ready job is ACCEPT (start)", JobQueue.place(nil, job("foot", 1, 60), 0) == "start")
check("off duty a job waiting for its car may queue", JobQueue.place(nil, job("car", 2, 200, { ready = false, why = "needs your car: CALL CAR" }), 0) == "queue")
check("on a run with room: + ADD", JobQueue.place(run("foot", 1, 3), job("foot", 1, 60), 0) == "add")
check("on a full run: + QUEUE", JobQueue.place(run("foot", 2, 3), job("foot", 1, 60), 0) == "queue")
check("a ★★★ car job on a run: + QUEUE", JobQueue.place(run("car", 1, 4), job("car", 2, 900, { stackable = false }), 2) == "queue")
check("another transport on a run: + QUEUE", JobQueue.place(run("foot", 1, 3), job("bike", 2, 120), 0) == "queue")
check("a car job on a foot run waits in the queue (not ready)", JobQueue.place(run("foot", 1, 3), job("car", 1, 200, { ready = false }), 0) == "queue")
local fullQueue, fullQueueWhy = JobQueue.place(run("foot", 2, 0), job("foot", 1, 60), MAX)
check("the queue's limit: nothing past Queue.Max", fullQueue == nil and fullQueueWhy == "queue full", fullQueueWhy)
local special, specialWhy = JobQueue.place(run("foot", 2, 0), job("car", 1, 400, { stackable = false, queueable = false }), 0)
check("a special on a run: neither (one at a time)", special == nil and specialWhy == "one at a time", specialWhy)
check("a locked job: nothing", JobQueue.place(run("foot", 1, 3), job("foot", 1, 60, { locked = true }), 0) == nil)
check("a room that fits still adds even with the queue full", JobQueue.place(run("foot", 1, 3), job("foot", 1, 60), MAX) == "add")

-- ADD ALL --------------------------------------------------------------------------------------

local rooms = { foot = 5, bike = 8, car = 4 }
local board = {
	job("foot", 2, 60, { id = 1 }),
	job("foot", 2, 70, { id = 2 }),
	job("foot", 1, 55, { id = 3 }),
	job("bike", 3, 120, { id = 4 }),
	job("car", 2, 200, { id = 5, ready = false, why = "needs your car: CALL CAR" }),
	job("car", 3, 900, { id = 6, stackable = false, locked = true }),
	job("car", 2, 400, { id = 7, stackable = false, queueable = false }), -- (a special)
}
local plan = JobQueue.plan(nil, rooms, board, 0)
local how: { [number]: string } = {}
for _, step in plan.steps do
	how[step.id :: number] = step.how
end
check("off duty: the first job starts the run", how[1] == "start" and plan.started == 1)
check("… the next foot job joins it (room 5: 2 + 2)", how[2] == "add" and plan.added == 1)
check("… the third foot job queues: 2 orders at most on foot", how[3] == "queue")
check("… the bike and the car job queue (another transport, waiting for the car)", how[4] == "queue" and how[5] == "queue")
check("… a locked job and a special are skipped", how[6] == nil and how[7] == nil)
check("… the count and the pay", plan.count == 5 and plan.queued == 3 and plan.total == 60 + 70 + 55 + 120 + 200, plan.total)

local onRun = JobQueue.plan(run("foot", 1, 2), rooms, { job("foot", 2, 60, { id = 1 }), job("foot", 1, 50, { id = 2 }), job("foot", 1, 40, { id = 3 }) }, 0)
check("on a run: into the run up to the room and the max, the rest queue", onRun.steps[1].how == "add" and onRun.steps[2].how == "queue" and onRun.steps[3].how == "queue" and onRun.added == 1 and onRun.queued == 2)
local many: { JobQueue.Job } = {}
for n = 1, 10 do
	table.insert(many, job("car", 2, 100, { id = n, stackable = false }))
end
local capped = JobQueue.plan(run("foot", 2, 0), rooms, many, 2)
check("the queue's limit: ADD ALL queues only up to Queue.Max", capped.queued == MAX - 2 and capped.count == MAX - 2 and capped.total == (MAX - 2) * 100)
local nothing = JobQueue.plan(run("foot", 2, 0), rooms, many, MAX)
check("a full queue and a full run: nothing", nothing.count == 0 and nothing.total == 0)
local waitingFirst = JobQueue.plan(nil, rooms, { job("car", 2, 200, { id = 1, ready = false }), job("foot", 1, 60, { id = 2 }) }, 0)
check("off duty a job that can't start yet queues; the first ready one starts", waitingFirst.steps[1].how == "queue" and waitingFirst.steps[2].how == "start")
local bigFirst = JobQueue.plan(nil, rooms, { job("car", 3, 900, { id = 1, stackable = false }), job("car", 1, 150, { id = 2 }) }, 0)
check("review: ADD ALL never starts a run with a job that does not stack: it queues, the stacking one starts", bigFirst.steps[1].how == "queue" and bigFirst.steps[2].how == "start")
local onlyBig = JobQueue.plan(nil, rooms, { job("car", 3, 900, { id = 1, stackable = false }), job("car", 2, 700, { id = 2, stackable = false }) }, 0)
check("review: only one-at-a-time jobs: none starts, they queue", onlyBig.started == 0 and onlyBig.queued == 2)
local withSpecials = JobQueue.plan(nil, rooms, {
	job("foot", 8, 95, { id = 1, stackable = false, queueable = false }), -- the paper round
	job("car", 2, 700, { id = 2, stackable = false, queueable = false }), -- a board special (Cash Transport)
	job("foot", 1, 60, { id = 3 }),
	job("foot", 1, 50, { id = 4 }),
}, 0)
local special: { [number]: string } = {}
for _, entry in withSpecials.steps do
	special[entry.id :: number] = entry.how
end
check("review: ADD ALL skips the paper round and a special: never started, never queued", special[1] == nil and special[2] == nil)
check("review: … the first ordinary job starts the run, the next joins it", special[3] == "start" and special[4] == "add" and withSpecials.total == 110)
local vetoed = JobQueue.plan(run("foot", 1, 5), rooms, { job("foot", 1, 60, { id = 1, fits = false }), job("foot", 1, 50, { id = 2, fits = true }) }, 0)
check("review: the server's own check (fits) vetoes an add the run's numbers allow", vetoed.steps[1].how == "queue" and vetoed.steps[2].how == "add")

local mixed = { job("foot", 1, 60, { id = 1 }), job("car", 2, 200, { id = 2 }), job("bike", 2, 90, { id = 3 }), job("car", 1, 150, { id = 4 }) }
local inCar = JobQueue.prefer(mixed, "car")
check("in your car ADD ALL starts with the car jobs, the rest in the board's order", inCar[1].id == 2 and inCar[2].id == 4 and inCar[3].id == 1 and inCar[4].id == 3)
check("on foot the board's order stays", JobQueue.prefer(mixed, nil)[1].id == 1)
local carPlan = JobQueue.plan(nil, rooms, inCar, 0)
check("… so the run it starts is a car run the other car job joins", carPlan.steps[1].how == "start" and carPlan.steps[1].id == 2 and carPlan.steps[2].how == "add" and carPlan.steps[2].id == 4)

-- What starts next -----------------------------------------------------------------------------

check("no head: nothing", JobQueue.nextStep(nil, nil) == nil)
check("no job: the head starts", JobQueue.nextStep(nil, job("foot", 1, 60)) == "start")
local carHow, carWhy = JobQueue.nextStep(nil, job("car", 2, 200, { ready = false, why = "needs your car: CALL CAR" }))
check("no job, the head needs the car: it waits and says why", carHow == nil and carWhy == "needs your car: CALL CAR", carWhy)
check("a run with room and a head that stacks: it joins", JobQueue.nextStep(run("bike", 1, 5), job("bike", 2, 90)) == "add")
local roomHow, roomWhy = JobQueue.nextStep(run("bike", 3, 5), job("bike", 2, 90))
check("a full run: the head waits for room", roomHow == nil and roomWhy == "when your run has room", roomWhy)
local afterHow, afterWhy = JobQueue.nextStep(run("foot", 1, 5), job("car", 2, 900, { stackable = false }))
check("a head that never stacks waits for the end of the run", afterHow == nil and afterWhy == "after your run", afterWhy)
local readyHow, readyWhy = JobQueue.nextStep(run("bike", 1, 5), job("bike", 2, 90, { ready = false, why = "needs your bike: MY BIKE" }))
check("a head that joins but is not ready says why", readyHow == nil and readyWhy == "needs your bike: MY BIKE", readyWhy)

-- review: a head locked for good is stepped past
check("the first queued job not locked for good comes next", JobQueue.effectiveHead({ job("bike", 1, 90, { locked = true, why = "needs a bike" }), job("foot", 1, 60), job("foot", 1, 50) }) == 2)
check("… the first one when none is locked", JobQueue.effectiveHead({ job("foot", 1, 60), job("car", 1, 90, { ready = false }) }) == 1)
check("… nothing when every one is locked", JobQueue.effectiveHead({ job("bike", 1, 90, { locked = true }) }) == nil and JobQueue.effectiveHead({}) == nil)

-- The words ------------------------------------------------------------------------------------

check("money", JobQueue.money(120) == "$120" and JobQueue.money(1240) == "$1,240" and JobQueue.money(1000000) == "$1,000,000")
check("NEXT UP's toast", JobQueue.nextUpText({ cargo = "Pizza", from = "Luigi's", to = "12 Elm St", pay = 120 }) == "NEXT UP: Pizza · Luigi's → 12 Elm St · $120")
check("ADD ALL's toast", JobQueue.addAllText(1, 1, 3, 505) == "ADD ALL · 1 started, 1 added to your run, 3 queued · $505")
check("review: the idle start's toast", JobQueue.startingText({ cargo = "Pizza", from = "Luigi's", to = "12 Elm St", pay = 120 }, 4) == "NEXT UP in 4 s: Pizza · Luigi's → 12 Elm St · $120 (JOBS to pause)")
check("review: a shut place's toast", JobQueue.closedText("Luigi's Pizza") == "Luigi's Pizza is closed now: dropped from NEXT UP")
check("review: the paused line", JobQueue.pausedLine("after a failed delivery") == "⏸ Paused after a failed delivery · RESUME to go on" and JobQueue.pausedLine(nil) == "⏸ Paused · RESUME to go on")
check("review: the JOBS tile says paused", JobQueue.jobsLine(2, 3, 0, true) == "Your run · 2 orders · 3 next (paused)" and JobQueue.jobsLine(0, 2, 0, true) == "Next up · 2 paused")
check("ADD ALL with nothing to add says so", string.find(JobQueue.addAllText(0, 0, 0, 0), "Nothing to add", 1, true) ~= nil)
check("the JOBS tile during a run", JobQueue.jobsLine(2, 3, 0) == "Your run · 2 orders · 3 next" and JobQueue.jobsLine(1, 0, 4) == "Your run · orders")
check("the JOBS tile off duty", JobQueue.jobsLine(0, 2, 5) == "Next up · 2 waiting" and JobQueue.jobsLine(0, 0, 3) == "3 new runs on the board" and JobQueue.jobsLine(0, 0, 0) == "Take a delivery")
local lines, total, nextStop = JobQueue.runLines({
	stopLabel = "PICK UP at Luigi's Pizza",
	orders = {
		{ id = 1, state = "open", title = "Pizza → Bob", pay = 120, endsAt = 400, mode = "foot", from = "Luigi's Pizza", to = "3 Oak Ave", focused = true },
		{ id = 2, state = "done", title = "Letters → Ann", pay = 40 },
		{ id = 3, state = "open", title = "Parcels → Cid", pay = 80, endsAt = 500, mode = "foot", from = "Post Office", to = "9 Elm St" },
	},
})
check("YOUR RUN: the open orders, their pay together, the next stop", #lines == 2 and total == 200 and nextStop == "PICK UP at Luigi's Pizza" and lines[1].route == "Luigi's Pizza → 3 Oak Ave" and lines[1].icon == "🚶" and lines[2].endsAt == 500)
local single, singleTotal = JobQueue.runLines({ cargo = "Gold", customer = "Dee", pay = 900, stars = 3, endsAt = 50, address = "Vault" })
check("YOUR RUN of a payload without orders: one line", #single == 1 and singleTotal == 900 and single[1].icon == "★★★")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
