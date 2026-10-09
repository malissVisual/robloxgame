--!strict
-- 6.12, the daily and weekly tasks on the server (shared/Tasks.luau has the rules, Config.Tasks the numbers): keeps
-- profile.tasks (server/PlayerData.luau saves it; a save from before 6.12 starts fresh), resets it at 00:00 UTC (the
-- weekly on Monday) and pays then what was done and not claimed, counts what the game tells (Tasks.note), pays a
-- CLAIM through the economy's own path (PlayerData.addMoney / addXp, like a mission's or a challenge's reward; saved a
-- moment later) and tells the client (the Tasks remote).
--
-- What counts, one short call each where it happens (Tasks.note(player, kind, amount, info?)):
--   "order"    server/Jobs.luau payOrder: a delivered order (its pieces of its look, on a bike or a scooter, its ★★★,
--              its pay; Tasks.orderEvents) for the owner, and for each crew member paid (pieces and pay)
--   "tips"     server/Jobs.luau payOrder (the Courier Vest's tip, the round's tip), server/Cargo.luau (the TRICKSHOT and
--              PERFECT tips of a throw), server/RunEvents.luau (a survivor's tip)
--   "perfect"  server/Cargo.luau: a PERFECT throw at a door
--   "zip"      server/ZipLines.luau zip(): a ride starts
--   "wheelie"  server/Wheelie.luau: a wheelie comes down (its seconds)
--   "bus"      server/Buses.luau getOff: off at a stop after a ride (Config.Tasks.BusTrip seconds seated)
--   "kill"     Main (Zombies.onKillInfo): a zombie killed (not a bandit), `night` after dark
--   "mission"  server/Missions.luau onComplete: a mission finished (each credited player)
--   "shift"    6.14, server/Shift.luau: a shift finished (its deliveries in one go, Config.Jobs.Shift)
--   "regular"  6.14, server/Regulars.luau paid: an order for a business where you were a regular already (Bronze+)
--   "golden"   6.14, server/Regulars.luau paid: a golden order delivered (the owner and the crew)
-- A note never blocks or breaks its caller (deferred, guarded).
--
-- The "Tasks" remote (shared/Net.luau), rate-limited (Config.Robust.Limits.Tasks):
--   client → server  ("open")            send me my tasks
--                    ("claim", slot)     claim a reward: 1 … Config.Tasks.Daily, "bonus" or "weekly"
--   server → client  ("state", V)        V = shared/Tasks.luau view: daily, bonus, weekly, dayEnds, weekEnds, ready
--                    ("done", D)         D = { title, weekly, money, xp }: a task was finished just now
--                    ("claimed", C)      C = { title, money, xp }: a claim paid

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local TaskData = require(Shared.Tasks)

local PlayerData = require(script.Parent.PlayerData)

local Tasks = {}

local remote: RemoteEvent? = nil
local loaded: { [Player]: boolean } = {}
local sentAt: { [Player]: number } = {}
local pending: { [Player]: boolean } = {}
local saveQueued: { [Player]: boolean } = {}
local started = false

local function getRemote(): RemoteEvent
	if not remote then
		remote = Net.get("Tasks")
	end
	return remote :: RemoteEvent
end

local function say(player: Player, text: string)
	Net.get("Notice"):FireClient(player, text)
end

-- Saved a little later (one save for a burst of claims or a reset's pay).
local function saveSoon(player: Player)
	if saveQueued[player] then
		return
	end
	saveQueued[player] = true
	task.delay(Config.Tasks.SaveDelay, function()
		saveQueued[player] = nil
		if player.Parent then
			PlayerData.save(player)
		end
	end)
end

-- The player's tasks, brought to now (a new day or week: reset, and what was done and not claimed paid). Nil while
-- the save loads.
local function tasksOf(player: Player): TaskData.Saved?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local now = os.time()
	local level = PlayerData.level(player)
	local saved = profile.tasks
	if saved == nil then
		saved = TaskData.fresh(player.UserId, now, level)
		profile.tasks = saved
	end
	assert(saved)
	local changed, owed, dayNew = TaskData.roll(saved, player.UserId, now, level)
	if owed.money > 0 or owed.xp > 0 then
		PlayerData.addMoney(player, owed.money, "TaskReward", "Reset")
		PlayerData.addXp(player, owed.xp)
		say(player, `Tasks paid at the reset: {table.concat(owed.titles, ", ")} · +{TaskData.money(owed.money)} · +{owed.xp} XP`)
		saveSoon(player)
	end
	if changed and dayNew and loaded[player] then
		say(player, "New daily tasks in your phone: TASKS.")
	end
	return saved
end

-- The state now (`now` true: at once; else at most every StateGap seconds, the last one always arrives).
local function sendState(player: Player, now: boolean?)
	if not loaded[player] then
		return
	end
	local function flush()
		pending[player] = nil
		if not player.Parent then
			return
		end
		local saved = tasksOf(player)
		if saved then
			sentAt[player] = os.clock()
			getRemote():FireClient(player, "state", TaskData.view(saved, player.UserId, os.time()))
		end
	end
	if now then
		flush()
		return
	end
	if pending[player] then
		return
	end
	pending[player] = true
	local wait = (sentAt[player] or 0) + Config.Tasks.StateGap - os.clock()
	if wait > 0 then
		task.delay(wait, flush)
	else
		task.defer(flush)
	end
end

-- Counts one event for the player's tasks; the ones it finished are told ("done").
local function count(player: Player, saved: TaskData.Saved, event: string, amount: number, info: TaskData.Info?): boolean
	local finished, moved = TaskData.note(saved, player.UserId, event, amount, info)
	for _, pick in finished do
		getRemote():FireClient(player, "done", { title = pick.title, weekly = pick.weekly, money = pick.money, xp = pick.xp })
	end
	return moved
end

local function apply(player: Player, kind: string, amount: number, info: { [string]: any }?)
	if not loaded[player] then
		return
	end
	local saved = tasksOf(player)
	if not saved then
		return
	end
	local moved = false
	if kind == "order" then
		-- A delivered order (server/Jobs.luau): its pieces, the ride (a bike job, or the owner on their bike or scooter
		-- now: a ZDC RIDE rental on a foot run too), its ★★★, its pay.
		local look = if info and type(info.look) == "string" then info.look else nil
		local bike = info ~= nil and info.mode == "bike"
		if info and info.owner == true and not bike then
			local ok, mode = pcall(function(): string
				return require(script.Parent.Transport).of(player).mode
			end)
			bike = ok and mode == "bike"
		end
		local stars = if info and type(info.stars) == "number" then info.stars else nil
		local pay = if info and type(info.pay) == "number" then info.pay else nil
		for _, entry in TaskData.orderEvents(amount, { look = look, bike = bike, stars = stars, pay = pay }) do
			moved = count(player, saved, entry.event, entry.amount, { look = look }) or moved
		end
	else
		local night = info ~= nil and info.night == true
		moved = count(player, saved, kind, amount, { night = night })
	end
	if moved then
		sendState(player)
	end
end

-- ── The API ────────────────────────────────────────────────────────────────

-- Counts `amount` of `kind` (an event of Config.Tasks, or "order": a delivered order, see the top) for the player.
-- Deferred and guarded: it never blocks or breaks the caller.
function Tasks.note(player: Player, kind: string, amount: number, info: { [string]: any }?)
	if typeof(player) ~= "Instance" or type(kind) ~= "string" or type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	task.defer(function()
		local ok, err = pcall(function()
			apply(player, kind, amount, info)
		end)
		if not ok then
			warn(`[Tasks] {kind} failed: {err}`)
		end
	end)
end

-- ── The remote ─────────────────────────────────────────────────────────────

local function onRequest(player: Player, action: any, slot: any)
	if type(action) ~= "string" or not Net.limit(player, "Tasks", Config.Robust.Limits.Tasks) then
		return
	end
	if not loaded[player] then
		return
	end
	if action == "open" then
		sendState(player, true)
		return
	end
	if action ~= "claim" then
		return
	end
	local saved = tasksOf(player)
	if not saved then
		return
	end
	-- (only the slots there are: a number 1 … Daily, "bonus", "weekly")
	local which: any = if slot == "bonus" or slot == "weekly" then slot elseif type(slot) == "number" and slot == slot then math.floor(slot) else nil
	if which == nil then
		return
	end
	local paid, xp, title = TaskData.claim(saved, player.UserId, which)
	if paid == nil or xp == nil then
		say(player, title)
		sendState(player, true)
		return
	end
	PlayerData.addMoney(player, paid, "TaskReward", if type(which) == "number" then "Daily" else which)
	PlayerData.addXp(player, xp)
	getRemote():FireClient(player, "claimed", { title = title, money = paid, xp = xp })
	saveSoon(player)
	sendState(player, true)
end

local function onLoaded(player: Player)
	if loaded[player] or not PlayerData.get(player) then
		return
	end
	loaded[player] = true -- (first: the pay below fires PlayerData.Changed again)
	tasksOf(player) -- (a save from before 6.12 starts fresh; a day or a week gone by is reset, paid and told)
	sendState(player, true)
end

-- Every CheckEvery seconds: everybody's reset at 00:00 UTC (the state goes out when the day turned).
local function loop()
	while true do
		task.wait(Config.Tasks.CheckEvery)
		local today, week = TaskData.dayOf(os.time()), TaskData.weekOf(os.time())
		for player in loaded do
			local profile = PlayerData.get(player)
			local saved = profile and profile.tasks
			if player.Parent and saved and (saved.day < today or saved.week < week) then
				local ok, err = pcall(function()
					sendState(player, true) -- (tasksOf in it resets and pays)
				end)
				if not ok then
					warn(`[Tasks] the reset failed: {err}`)
				end
			end
		end
	end
end

function Tasks.start()
	if started then
		return
	end
	started = true
	getRemote().OnServerEvent:Connect(onRequest)
	PlayerData.Changed:Connect(function(player: Player)
		if not loaded[player] and PlayerData.get(player) then
			onLoaded(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		if PlayerData.get(player) then
			task.spawn(onLoaded, player)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		loaded[player] = nil
		sentAt[player] = nil
		pending[player] = nil
		-- (saveQueued stays until its delay runs: it checks player.Parent; PlayerData.release saves anyway)
	end)
	task.spawn(loop)
end

return Tasks
