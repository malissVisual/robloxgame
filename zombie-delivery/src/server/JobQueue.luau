--!strict
-- 6.12.8, the NEXT UP queue (the owner: "once I take a job I can't add more … I want to add even all of them so I
-- don't have to keep taking them again. Somewhere show what I'll do next."). The rules are shared/JobQueue.luau's,
-- the numbers Config.Jobs.Queue's, the facts and the start paths server/Jobs.luau's (Jobs.queueApi).
--
--   * A player's queue: up to Queue.Max ordinary board jobs (on foot, by bike, the car tiers their level and licence
--     open; never a mission, a special, an employer's job, the Freight Run, DUO, the tutorial's or the paper round). A
--     queued job is a snapshot of its offer: it leaves the board (Board.taken: the board refills after the run, as
--     with ACCEPT) and keeps its pay; its clock does not run while it waits (Jobs.queueApi.take: the clock from when
--     it starts, from where you are then). Not saved: gone when you leave; kept through a death.
--   * The JobQueue remote (rate limited, Config.Robust.Limits.JobQueue): ("queue", offer id) the board's + QUEUE;
--     ("addAll") ADD ALL: every job on the board it can (shared/JobQueue.luau plan): into the run (a run started by
--     the first job that stacks when there is none: the transport you are on first, Rules.prefer) up to its room and
--     Orders.Max, the rest into the queue up to its limit, one toast for all (specials and the paper round skipped);
--     ("drop", id) NEXT UP's ✕; ("pause") / ("resume"); ("clear") CLEAR ALL; ("open") the queue again. The server
--     pushes ("state", { list, max, paused, pausedWhy }) whenever the queue, its pause or a reason changes, and the
--     board (its rows' + QUEUE, ADD ALL's total).
--   * Starting (step): the next job is the first one not locked for good (Rules.effectiveHead: a job locked for good,
--     e.g. its bike sold, is stepped past and keeps its reason until ✕). On a run it joins it at once when it stacks
--     and 5.2's own stackCheck takes it ("add": + ADD's path, addOrder). With no job it starts Queue.StartDelay s after
--     the toast "NEXT UP in 4 s: Pizza · Luigi's → … (JOBS to pause)" ("start": ACCEPT's path, takeOffer; PAUSE or ✕
--     meanwhile cancels it); the company vehicle of the job before goes back. A job whose place is shut by now is
--     dropped ("Luigi's Pizza is closed now: dropped from NEXT UP"). Then "NEXT UP: Pizza · Luigi's → 12 Elm St ·
--     $120", the GPS follows as with any job; the start paths tell nothing else (quiet). Else it waits and says why
--     ("needs your car: CALL CAR", "after your run" …). Jobs.onQueuePoke (after a drop, an order done or lost, the end
--     of a run: deferred, after the board's refill) and a check every Queue.CheckEvery s (a vehicle switched, a crew
--     left) run it. Not while the courier is down. A start that fails anyway waits Queue.RetryAfter s.
--   * PAUSED (Jobs.onQueuePause): a failed delivery (GIVE UP, a clock, the cargo lost, a wreck: Jobs.fail), a lost
--     order, a mission or an employer's job starting, or PAUSE: nothing starts until RESUME (an idle player never runs
--     through the queue). CLEAR ALL empties it (and un-pauses it).
--   * Jobs.onBoardSend: every board sent gets the rows' `queue` (+ QUEUE: during a run, a row that can't be added but
--     may wait), `queueButton` / `queueText` (the queue is full) and the info's `addAll` (ADD ALL's count and total)
--     and `queue` (its size and max).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.JobQueue)
local Jobs = require(script.Parent.Jobs)

local QueueConfig = Config.Jobs.Queue
local api: any = Jobs.queueApi

type Entry = { id: number, offer: any, why: string?, retryAt: number, starting: boolean? }
type Queue = {
	list: { Entry },
	nextId: number,
	sent: string,
	paused: boolean,
	pausedWhy: string?,
	startId: number?, -- the job the idle start waits StartDelay for …
	startAt: number, -- … until this os.clock()
}

local JobQueue = {}

local queues: { [Player]: Queue } = {}
local pending: { [Player]: boolean } = {}
local remote = Net.get("JobQueue")
local notice = Net.get("Notice")

local function queueOf(player: Player): Queue
	local queue = queues[player]
	if not queue then
		queue = { list = {}, nextId = 0, sent = "", paused = false, pausedWhy = nil, startId = nil, startAt = 0 }
		queues[player] = queue
	end
	return queue
end

-- The jobs waiting now (0 without a queue).
function JobQueue.size(player: Player): number
	local queue = queues[player]
	return if queue then #queue.list else 0
end

-- What the phone and the J board show: every queued job (what, from → to, pay …), its reason to wait, the next one's
-- "starting".
local function views(queue: Queue): { { [string]: any } }
	local out: { { [string]: any } } = {}
	for _, entry in queue.list do
		local view = api.view(entry.offer)
		view.id = entry.id
		view.why = entry.why
		view.starting = if entry.starting and not queue.paused then true else nil
		table.insert(out, view)
	end
	return out
end

-- Sends the queue to its player when it changed (`force`: anyway).
local function push(player: Player, force: boolean?)
	local queue = queues[player]
	local parts: { string } = {}
	local list: { Entry } = if queue then queue.list else {}
	for _, entry in list do
		table.insert(parts, `{entry.id}:{entry.why or ""}:{entry.starting == true}`)
	end
	local key = `{if queue and queue.paused then "P" else "-"}|{table.concat(parts, "|")}`
	if queue then
		if key == queue.sent and not force then
			return
		end
		queue.sent = key
	elseif not force then
		return
	end
	remote:FireClient(player, "state", {
		list = if queue then views(queue) else {},
		max = Rules.max(),
		paused = if queue and queue.paused then true else nil,
		pausedWhy = if queue and queue.paused then queue.pausedWhy else nil,
	})
end

local function findOffer(board: any, id: number): any
	for _, offer in board.list do
		if offer.id == id then
			return offer
		end
	end
	return nil
end

-- Is the courier up (a queued job does not start while they are down)?
local function alive(player: Player): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

-- An offer of the board into the queue (a snapshot; it leaves the board).
local function enqueue(player: Player, board: any, offer: any): Entry
	local queue = queueOf(player)
	queue.nextId += 1
	local entry: Entry = { id = queue.nextId, offer = table.clone(offer), why = nil, retryAt = 0 }
	table.insert(queue.list, entry)
	api.unlist(board, offer)
	return entry
end

-- The queue's next jobs start while they can (no job: after the StartDelay; a run that takes them: at once); the
-- next one that can't says why. One toast for what started.
local function step(player: Player)
	local queue = queues[player]
	if not queue or #queue.list == 0 or not player.Parent then
		return
	end
	if queue.paused then
		queue.startId = nil
		push(player)
		return
	end
	if not alive(player) then
		return -- (kept through a death: it goes on once you are up)
	end
	local started: { Entry } = {}
	for _ = 1, #queue.list + 1 do
		-- The first job not locked for good comes next (the locked ones keep their reason; ✕ drops them).
		local candidates = {}
		for _, entry in queue.list do
			local job = api.candidate(player, entry.offer)
			entry.starting = nil
			entry.why = if job.locked then job.why or "locked" else nil
			table.insert(candidates, job)
		end
		local at = Rules.effectiveHead(candidates)
		if not at then
			queue.startId = nil
			break
		end
		local head = queue.list[at]
		local how, why = Rules.nextStep(api.run(player), candidates[at])
		if how and os.clock() < head.retryAt then
			how, why = nil, "could not start: trying again soon"
		end
		local shut: string? = if how then api.closed(head.offer) else nil
		if shut then
			-- (its place is shut by now: dropped, the next one after it)
			table.remove(queue.list, at)
			notice:FireClient(player, Rules.closedText(shut))
			queue.startId = nil
			continue
		end
		if how == "start" then
			-- With no job running: StartDelay s after the toast (PAUSE or ✕ meanwhile cancels it).
			local now = os.clock()
			if queue.startId ~= head.id then
				queue.startId = head.id
				queue.startAt = now + QueueConfig.StartDelay
				notice:FireClient(player, Rules.startingText(api.view(head.offer), QueueConfig.StartDelay))
				task.delay(QueueConfig.StartDelay + 0.05, function()
					JobQueue.poke(player)
				end)
			end
			if now < queue.startAt then
				head.starting = true
				how = nil
			end
		elseif queue.startId == head.id then
			queue.startId = nil -- (it got a run meanwhile: it waits or joins it now)
		end
		head.why = why
		if not how then
			break
		end
		table.remove(queue.list, at)
		queue.startId = nil
		if how == "start" then
			Jobs.refillBoard(player) -- (the run before it is over: its taken offers come back first, as after any run)
		end
		local ok, result = pcall(api.take, player, nil, head.offer, how, true)
		if ok and result == true then
			table.insert(started, head)
		else
			if not ok then
				warn(`[JobQueue] a queued job failed to start for {player.Name}: {result}`)
			end
			head.retryAt = os.clock() + QueueConfig.RetryAfter
			head.why = "could not start: trying again soon"
			table.insert(queue.list, at, head)
			break
		end
	end
	if #started > 0 then
		local first = api.view(started[1].offer)
		local text = Rules.nextUpText(first)
		if #started > 1 then
			text ..= ` · +{#started - 1} more on your run`
		end
		notice:FireClient(player, text)
		api.sendBoard(player, api.boardOf(player)) -- (the rows' + ADD / + QUEUE follow the run)
	end
	push(player)
end

-- After a drop, an order done or lost, the end of a run (Jobs.onQueuePoke): the next step, deferred (after the board's
-- refill and the result), once however often it is poked in a frame.
function JobQueue.poke(player: Player)
	if pending[player] or JobQueue.size(player) == 0 then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		local ok, err = pcall(function()
			step(player)
		end)
		if not ok then
			warn(`[JobQueue] step failed for {player.Name}: {err}`)
		end
	end)
end

-- PAUSED (Jobs.onQueuePause: a failed delivery, a lost order, a mission or an employer's job; or PAUSE): nothing
-- starts until RESUME; an idle start waiting is cancelled. Only a queue that holds jobs pauses.
function JobQueue.pause(player: Player, why: string?)
	local queue = queues[player]
	if not queue or #queue.list == 0 or queue.paused then
		return
	end
	queue.paused = true
	queue.pausedWhy = why
	queue.startId = nil
	for _, entry in queue.list do
		entry.starting = nil
	end
	push(player)
	if why ~= "" then
		notice:FireClient(player, `NEXT UP paused{if why then ` {why}` else ""}: RESUME in JOBS when you're ready.`)
	end
end

local function resume(player: Player)
	local queue = queues[player]
	if not queue or not queue.paused then
		push(player, true)
		return
	end
	queue.paused = false
	queue.pausedWhy = nil
	push(player)
	JobQueue.poke(player)
end

-- CLEAR ALL: the queue empties (and is not paused any more).
local function clear(player: Player)
	local queue = queues[player]
	local count = if queue then #queue.list else 0
	if queue then
		table.clear(queue.list)
		queue.paused = false
		queue.pausedWhy = nil
		queue.startId = nil
	end
	if count > 0 then
		notice:FireClient(player, `NEXT UP cleared ({count} {if count == 1 then "job" else "jobs"}).`)
	end
	push(player, true)
	api.sendBoard(player, api.boardOf(player))
end

-- + QUEUE (the board's row, by its offer id).
local function queueOffer(player: Player, id: number)
	local board = api.boardOf(player)
	local offer = findOffer(board, id)
	if not offer then
		notice:FireClient(player, "That job is no longer on the board.")
		api.sendBoard(player, board)
		return
	end
	local queue = queueOf(player)
	local job = api.candidate(player, offer)
	if not job.queueable then
		notice:FireClient(player, if job.locked then `Locked: {job.why or "this job isn't open to you yet"}.` else "Specials, missions, the Freight Run and paper rounds are one at a time: they never wait in NEXT UP.")
		api.sendBoard(player, board)
		return
	elseif #queue.list >= Rules.max() then
		notice:FireClient(player, `NEXT UP is full ({#queue.list}/{Rules.max()}). Drop one (✕) or finish a job first.`)
		api.sendBoard(player, board)
		return
	end
	enqueue(player, board, offer)
	local view = api.view(offer)
	notice:FireClient(player, `QUEUED · NEXT UP {#queue.list}: {view.cargo} · {Rules.route(view.from, view.to)} · {Rules.money(view.pay)}`)
	push(player)
	api.sendBoard(player, board)
	JobQueue.poke(player) -- (it may join the run now; off duty it starts after the StartDelay)
end

-- ADD ALL: the board's jobs in their order (Rules.plan): started, added to the run (each checked again against the run
-- as it is then: a refused one waits in the queue instead), queued. Silent paths; one toast for all.
local function addAll(player: Player)
	local board = api.boardOf(player)
	local queue = queueOf(player)
	local candidates = {}
	local byId: { [number]: any } = {}
	for _, offer in board.list do
		table.insert(candidates, api.candidate(player, offer))
		byId[offer.id] = offer
	end
	local run = api.run(player)
	local plan = Rules.plan(run, api.rooms(player), if run then candidates else Rules.prefer(candidates, api.transport(player)), #queue.list)
	local started, added, queued, total = 0, 0, 0, 0
	for _, entry in plan.steps do
		local offer = if entry.id then byId[entry.id] else nil
		if not offer or not table.find(board.list, offer) then
			continue
		end
		local how = entry.how
		local job = api.candidate(player, offer)
		if not job.queueable then
			continue -- (never a special or the paper round)
		end
		local done = false
		if how == "start" or how == "add" then
			local now = Rules.place(api.run(player), job, #queue.list)
			if now == how and (how == "add" or job.stackable) then
				local ok, result = pcall(api.take, player, board, offer, how, true)
				done = ok and result == true
				if not ok then
					warn(`[JobQueue] ADD ALL failed to take a job for {player.Name}: {result}`)
				end
			end
			if done then
				if how == "start" then
					started += 1
				else
					added += 1
				end
			end
		end
		if not done and #queue.list < Rules.max() then
			enqueue(player, board, offer)
			queued += 1
			done = true
		end
		if done then
			total += tonumber(offer.pay) or 0
		end
	end
	notice:FireClient(player, Rules.addAllText(started, added, queued, total))
	require(script.Parent.PlayerData).track("event", player, "QueueAddAll", started + added + queued) -- 6.13
	push(player)
	api.sendBoard(player, board)
	JobQueue.poke(player)
end

-- NEXT UP's ✕ (an idle start waiting for it is cancelled with it).
local function drop(player: Player, id: number)
	local queue = queues[player]
	if not queue then
		return
	end
	for index, entry in queue.list do
		if entry.id == id then
			table.remove(queue.list, index)
			if queue.startId == id then
				queue.startId = nil
			end
			if #queue.list == 0 then
				queue.paused = false
				queue.pausedWhy = nil
			end
			notice:FireClient(player, `Dropped from NEXT UP: {entry.offer.cargo}.`)
			push(player)
			api.sendBoard(player, api.boardOf(player))
			JobQueue.poke(player)
			return
		end
	end
	push(player, true)
end

function JobQueue.start()
	Jobs.onQueuePoke = JobQueue.poke
	Jobs.onQueuePause = JobQueue.pause
	Jobs.onBoardSend = function(player: Player, board: any, rows: { { [string]: any } }, info: { [string]: any })
		local size = JobQueue.size(player)
		local max = Rules.max()
		local run = api.run(player)
		local candidates = {}
		for index, offer in board.list do
			local job = api.candidate(player, offer)
			table.insert(candidates, job)
			local row = rows[index]
			-- During a run a row that can't join it now may wait in the queue (+ QUEUE), or says the queue is full.
			if row and info.onDuty and row.addOrder ~= true and job.queueable then
				if size < max then
					row.queue = true
				else
					row.queueButton = `QUEUE FULL ({size}/{max})`
					row.queueText = `NEXT UP holds {max} jobs. Drop one (✕) or finish a job first.`
				end
			end
		end
		local plan = Rules.plan(run, api.rooms(player), if run then candidates else Rules.prefer(candidates, api.transport(player)), size)
		info.addAll = { count = plan.count, total = plan.total, started = plan.started, added = plan.added, queued = plan.queued }
		info.queue = { size = size, max = max }
	end
	remote.OnServerEvent:Connect(function(player: Player, action: any, arg: any)
		if not Net.limit(player, "JobQueue", Config.Robust.Limits.JobQueue) then
			return
		end
		if action == "queue" and type(arg) == "number" then
			queueOffer(player, arg)
		elseif action == "addAll" then
			addAll(player)
		elseif action == "drop" and type(arg) == "number" then
			drop(player, arg)
		elseif action == "pause" then
			JobQueue.pause(player, "")
			push(player, true)
		elseif action == "resume" then
			resume(player)
		elseif action == "clear" then
			clear(player)
		elseif action == "open" then
			push(player, true)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		queues[player] = nil -- (never saved: gone when you leave)
		pending[player] = nil
	end)
	-- The cheap check: every CheckEvery s the queues that wait (a vehicle switched, a crew left, the clock of a retry).
	task.spawn(function()
		while true do
			task.wait(math.max(0.5, QueueConfig.CheckEvery))
			for player, queue in queues do
				if #queue.list > 0 and not queue.paused then
					local ok, err = pcall(function()
						step(player)
					end)
					if not ok then
						warn(`[JobQueue] check failed for {player.Name}: {err}`)
					end
				end
			end
		end
	end)
end

return JobQueue
