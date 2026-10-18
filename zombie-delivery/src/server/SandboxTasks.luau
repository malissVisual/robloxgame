--!strict
-- 8.2 SANDBOX, the daily tasks on the server (the owner: "daily tasks that bring players back"; shared/SandboxTasks.luau
-- has the rules, Config.SandboxTasks the numbers; the city's server/Tasks.luau does not run in the sandbox). Keeps
-- profile.sandboxTasks (server/PlayerData.luau saves it with its flag; a save from before 8.2 starts fresh), picks new
-- dailies at 00:00 UTC (a new weekly on Monday) and pays then what was done and not claimed, counts what the game tells
-- it, pays a CLAIM (PlayerData.addMoney, the reason "SandboxTask", the task's id its SKU; saved a moment later) and
-- tells the client (the "SandboxTasks" remote). Never picked: "upgrade" once every upgrade is at its top.
--
-- What counts, from the signals that are there (no polling of the world but Danny's hands, see below):
--   home, rare  Collection.onChanged: the new pieces in your stock since the last look (once a frame: a van unloaded
--               is one look), and how many of them are Config.SandboxTasks.RareRank or rarer (CollectionRules.tierOf).
--               8.7 review: a piece bought from another player never came home: Collection.onTransferred marks its new
--               uid seen at once (two friends passing one piece back and forth finish no task)
--   shown       Collection.onChanged: the pieces on your stands now (the best counts)
--   sell        Collection.onPaid "sale": the money a piece sold for
--   income      Collection.onPaid "income": what the stands paid (CollectionIncome)
--   hotsell     8.3: Collection.onPaid "sale": the pieces of today's hot kinds in it (Config.Market)
--   hotincome   8.3: Collection.onPaid "income": the dollars of it the hot pieces on show earned
--   upgrade     Upgrades.onChanged: the levels bought since the last look (your levels in all went up)
--   trips       Moving.onStored: a truckload home (the owner's; 9.7: one a run's end; a sum)
--   moves       Moving.onResult: a move done (or late) with pieces home, for everybody in its crew
--   clean       … and nothing of it broken (MovingRules' result.broken)
--   danny       every DannyEvery s while a danny task is open: Danny (server/MoveHelper.luau find) holds the other end of
--               the piece you carry (MovingRules.holding) and it is the task's item (the sofa)
-- A note never blocks or breaks its caller (guarded); a player whose save has not loaded counts nothing.
--
-- The "SandboxTasks" remote (shared/Net.luau), rate-limited (Config.Robust.Limits.SandboxTasks), every input checked:
--   client → server  { kind = "state" }                 send me my tasks
--                    { kind = "claim", slot }           claim a reward: 1 … Config.SandboxTasks.Daily, "bonus" or "weekly"
--   server → client  { kind = "state", daily, bonus, weekly, dayLeft, weekLeft, ready }   shared/SandboxTasks.luau's view
--                    { kind = "done", title, money, weekly }   a task was finished just now (the client's toast)
--                    { kind = "claimed", title, money }        a claim paid
--
--   SandboxTasks.start()                         the remote, the hooks, joining and leaving, the loops
--   SandboxTasks.note(player, event, amount, info?)   counts an event (Config.SandboxTasks' events) for the player
--   SandboxTasks.state(player)                   the player's view now (nil: no save yet; the tests, the admin)
--   SandboxTasks.useProbe(fn)                    the Danny look (a test's): fn(player) → the item whose far end Danny
--                                                holds while the player carries it, or nil

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.SandboxTasks)
local CollectionRules = require(Shared.CollectionRules)
local MovingRules = require(Shared.MovingRules)
local UpgradeRules = require(Shared.UpgradeRules)
local PlayerData = require(script.Parent.PlayerData)
local Collection = require(script.Parent.Collection)
local Upgrades = require(script.Parent.Upgrades)

local SandboxTasks = {}

local T = Config.SandboxTasks

local remote = Net.get("SandboxTasks")
local notice = Net.get("Notice")

local loaded: { [Player]: boolean } = {}
local stockSeen: { [Player]: { [string]: boolean } } = {} -- the uids in the stock at the last look (a new one came home)
local levelsSeen: { [Player]: number } = {} -- the upgrade levels in all at the last look
local looking: { [Player]: boolean } = {} -- a look at the collection waits for the frame's end
local sentAt: { [Player]: number } = {}
local pending: { [Player]: boolean } = {}
local saveQueued: { [Player]: boolean } = {}
local started = false

local function say(player: Player, text: string)
	notice:FireClient(player, text)
end

-- Saved a little later (one save for a burst of claims or a reset's pay).
local function saveSoon(player: Player)
	if saveQueued[player] then
		return
	end
	saveQueued[player] = true
	task.delay(T.SaveDelay, function()
		saveQueued[player] = nil
		if player.Parent then
			PlayerData.save(player)
		end
	end)
end

-- The kinds that can't be done now: "upgrade" once every upgrade is at its top (10.4: every one the tree sells); 8.3: "offer" while the visitors are off;
-- 8.4: "shown" while the warehouse has fewer stands than its highest target (the Garage, the Workshop, the Storehouse).
local function skipFor(profile: PlayerData.Profile): { [string]: boolean }?
	local skip: { [string]: boolean }? = if Config.Visitors.On then nil else { offer = true }
	for _, def in T.DailyPool do
		if def.event == "shown" and CollectionRules.standsFor(profile) < def.target[2] then
			skip = skip or {}
			;(skip :: { [string]: boolean }).shown = true
		end
	end
	for _, id in UpgradeRules.Order do
		local def = UpgradeRules.def(id)
		if def and UpgradeRules.offered(id) and UpgradeRules.level(profile.sandboxUpgrades, id) < def.max then -- (10.4: the tree's)
			return skip
		end
	end
	local all: { [string]: boolean } = skip or {}
	all.upgrade = true
	return all
end

-- The upgrade levels in all.
local function levelsOf(profile: PlayerData.Profile): number
	local total = 0
	for _, id in UpgradeRules.Order do
		total += UpgradeRules.level(profile.sandboxUpgrades, id)
	end
	return total
end

-- The player's tasks, brought to now (a new day or week: new picks, and what was done and not claimed paid). Nil while
-- the save loads.
local function tasksOf(player: Player): Rules.Saved?
	local profile = PlayerData.get(player)
	if not profile then
		return nil
	end
	local now = os.time()
	local saved = profile.sandboxTasks
	if saved == nil then
		saved = Rules.fresh(player.UserId, now, skipFor(profile))
		profile.sandboxTasks = saved
	end
	assert(saved)
	local _, owed, dayNew = Rules.roll(saved, player.UserId, now, skipFor(profile))
	if owed.money > 0 then
		PlayerData.addMoney(player, owed.money, "SandboxTask", "Reset")
		say(player, `📋 Tasks paid at the reset: {table.concat(owed.titles, ", ")} · +{Rules.money(owed.money)}`)
		saveSoon(player)
	end
	if dayNew and loaded[player] then
		say(player, "🌅 New daily tasks: open 📋 TASKS.") -- (8.3: no key here: each client adds its own, client/SandboxHud.luau notice)
	end
	return saved
end

-- The state now (`now` true: at once; else at most every StateGap s, the last one always arrives).
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
			local message: any = Rules.view(saved, os.time())
			message.kind = "state"
			remote:FireClient(player, message)
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
	local wait = (sentAt[player] or 0) + T.StateGap - os.clock()
	if wait > 0 then
		task.delay(wait, flush)
	else
		task.defer(flush)
	end
end

local function count(player: Player, event: string, amount: number, info: Rules.Info?)
	if not loaded[player] then
		return
	end
	local saved = tasksOf(player)
	if not saved then
		return
	end
	local finished, moved = Rules.note(saved, event, amount, info)
	for _, done in finished do
		remote:FireClient(player, { kind = "done", title = done.title, money = done.money, weekly = done.weekly })
	end
	if moved then
		sendState(player)
	end
end

-- ── The API ────────────────────────────────────────────────────────────────

-- Counts `amount` of `event` for the player at once (a leave's last payout still counts: Collection pays before this
-- module forgets the player). Only a player whose save has loaded here counts; guarded: it never breaks the caller.
function SandboxTasks.note(player: Player, event: string, amount: number, info: Rules.Info?)
	if type(event) ~= "string" then
		return
	end
	local ok, err = pcall(function()
		count(player, event, amount, info)
	end)
	if not ok then
		warn(`[SandboxTasks] {event} failed: {err}`)
	end
end

function SandboxTasks.state(player: Player): Rules.View?
	if not loaded[player] then
		return nil
	end
	local saved = tasksOf(player)
	return if saved then Rules.view(saved, os.time()) else nil
end

-- ── What counts ────────────────────────────────────────────────────────────

-- The collection changed (once a frame): the pieces that came home (new uids), how many are rare or better, how many
-- stand on show now.
local function lookAtStock(player: Player)
	looking[player] = nil
	local seen = stockSeen[player]
	if not loaded[player] or not seen or not player.Parent then
		return
	end
	local stands = Collection.stands(player)
	local housed = Collection.hasWarehouse -- (8.2 review: no warehouse of their own, nothing of theirs is on show)
	if housed and not housed(player) then
		stands = 0
	end
	local now: { [string]: boolean } = {}
	local home, rare, shown = 0, 0, 0
	for _, entry in Collection.stock(player) do
		now[entry.uid] = true
		if not seen[entry.uid] then
			home += 1
			if CollectionRules.tierOf(entry).rank >= T.RareRank then
				rare += 1
			end
		end
		if entry.stand ~= nil and entry.stand <= stands then
			shown += 1
		end
	end
	stockSeen[player] = now
	if home > 0 then
		SandboxTasks.note(player, "home", home)
	end
	if rare > 0 then
		SandboxTasks.note(player, "rare", rare)
	end
	if shown > 0 then
		SandboxTasks.note(player, "shown", shown)
	end
end

local function onCollection(player: Player)
	if looking[player] or not loaded[player] then
		return
	end
	looking[player] = true
	task.defer(lookAtStock, player)
end

-- 8.7 review: a deal between players (Collection.transfer, before its onChanged): the buyer's new uid is seen already.
local function onTransferred(buyer: Player, _seller: Player, entry: Collection.Entry)
	local seen = stockSeen[buyer]
	if seen then
		seen[entry.uid] = true
	end
end

local function onPaid(player: Player, kind: string, money: number, paid: Collection.Paid?)
	local hot = if type(paid) == "table" and type(paid.hot) == "number" then paid.hot else 0 -- (8.3: the market's)
	if kind == "sale" then
		SandboxTasks.note(player, "sell", money)
		if hot > 0 then
			SandboxTasks.note(player, "hotsell", hot)
		end
	elseif kind == "income" then
		SandboxTasks.note(player, "income", money)
		if hot > 0 then
			SandboxTasks.note(player, "hotincome", hot)
		end
	end
end

-- The upgrades changed: the levels bought since the last look (an admin's RESET lowers the mark).
local function onUpgrades(player: Player)
	local profile = PlayerData.get(player)
	local was = levelsSeen[player]
	if not loaded[player] or not profile or was == nil then
		return
	end
	local now = levelsOf(profile)
	levelsSeen[player] = now
	if now > was then
		SandboxTasks.note(player, "upgrade", now - was)
	end
end

-- A trip home (Moving.onStored, the move's owner; 9.7: a run's truck at its end): one truckload more.
local function onTrip(owner: Player, move: MovingRules.Move, _spots: { number })
	if type(move) == "table" and type(move.trips) == "number" then
		SandboxTasks.note(owner, "trips", 1)
	end
end

-- A move's end (Moving.onResult): done or late with pieces home is a move finished, and a clean one without anything
-- broken; for everybody in its crew.
local function onFinish(owner: Player, move: MovingRules.Move, result: MovingRules.Result, crew: { Player })
	if type(move) ~= "table" or type(result) ~= "table" or (result.how ~= "done" and result.how ~= "late") then
		return
	end
	local home = 0
	for _, spot in move.order do
		local thing = move.things[spot]
		if thing and thing.state == "delivered" then
			home += 1
		end
	end
	if home == 0 then
		return
	end
	local everybody: { Player } = { owner }
	local list: { Player } = if type(crew) == "table" then crew else {}
	for _, member in list do
		if not table.find(everybody, member) then
			table.insert(everybody, member)
		end
	end
	for _, member in everybody do
		SandboxTasks.note(member, "moves", 1)
		if result.broken == 0 then
			SandboxTasks.note(member, "clean", 1)
		end
	end
end

-- The piece whose far end Danny holds while `player` carries it (its item id), else nil: server/MoveHelper.luau's find
-- (his state on the player's move), MovingRules.holding (what he holds).
local function dannyHolds(player: Player): string?
	local helper = require(script.Parent.MoveHelper).find(player)
	local move = if type(helper) == "table" and type(helper.s) == "table" then helper.s.move else nil
	if type(move) ~= "table" or type(helper.id) ~= "number" then
		return nil
	end
	local spot, role = MovingRules.holding(move, helper.id)
	local thing = if spot and role == "helper" then move.things[spot] else nil
	return if thing and thing.carrier == player.UserId then thing.item else nil
end
local probe: (Player) -> string? = dannyHolds

function SandboxTasks.useProbe(fn: (Player) -> string?)
	probe = fn
end

-- One look at everybody with a danny task open.
local function lookForDanny()
	for player in loaded do
		local profile = PlayerData.get(player)
		local saved = profile and profile.sandboxTasks
		local item = if saved then Rules.itemFor(saved, "danny") else nil
		if item and player.Parent then
			local ok, held = pcall(probe, player)
			if ok and held == item then
				SandboxTasks.note(player, "danny", 1, { item = held })
			end
		end
	end
end

-- ── The remote ─────────────────────────────────────────────────────────────

local function onRequest(player: Player, message: any)
	if not Net.limit(player, "SandboxTasks", Config.Robust.Limits.SandboxTasks) then
		return
	end
	if type(message) ~= "table" or not loaded[player] then
		return
	end
	if message.kind == "state" then
		sendState(player, true)
		return
	elseif message.kind ~= "claim" then
		return
	end
	-- (only the slots there are: a whole number, "bonus", "weekly")
	local slot = message.slot
	local which: any = if slot == "bonus" or slot == "weekly" then slot
		elseif type(slot) == "number" and slot == math.floor(slot) and slot >= 1 and slot <= T.Daily then slot
		else nil
	local saved = tasksOf(player)
	if which == nil or not saved then
		return
	end
	local picked = if which == "bonus" then nil elseif which == "weekly" then saved.weekly else saved.daily[which]
	local sku = if picked then picked.id else "AllDaily"
	local money, title = Rules.claim(saved, which)
	if money == nil then
		say(player, title)
		sendState(player, true)
		return
	end
	PlayerData.addMoney(player, money, "SandboxTask", sku)
	remote:FireClient(player, { kind = "claimed", title = title, money = money })
	saveSoon(player)
	sendState(player, true)
end

-- ── Joining, leaving ───────────────────────────────────────────────────────

local function onLoaded(player: Player)
	local profile = PlayerData.get(player)
	if loaded[player] or not profile or not player.Parent then
		return
	end
	loaded[player] = true -- (first: a reset's pay fires PlayerData.Changed again)
	-- what is there now is the mark (nothing of it counts)
	local seen: { [string]: boolean } = {}
	for _, entry in Collection.stock(player) do
		seen[entry.uid] = true
	end
	stockSeen[player] = seen
	levelsSeen[player] = levelsOf(profile)
	tasksOf(player) -- (a save from before 8.2 starts fresh; a day or a week gone by is reset, paid and told)
	sendState(player, true)
end

local function left(player: Player)
	loaded[player] = nil
	stockSeen[player] = nil
	levelsSeen[player] = nil
	looking[player] = nil
	sentAt[player] = nil
	pending[player] = nil
	-- (saveQueued stays until its delay runs: it checks player.Parent; PlayerData's leave save writes the tasks anyway)
end

-- Every CheckEvery s: everybody's reset at 00:00 UTC (the state goes out when the day turned).
local function resetLoop()
	while true do
		task.wait(T.CheckEvery)
		local now = os.time()
		local today, week = Rules.dayOf(now), Rules.weekOf(now)
		for player in loaded do
			local profile = PlayerData.get(player)
			local saved = profile and profile.sandboxTasks
			if player.Parent and saved and (saved.day < today or saved.week < week) then
				local ok, err = pcall(function()
					sendState(player, true) -- (tasksOf in it resets and pays)
				end)
				if not ok then
					warn(`[SandboxTasks] the reset failed: {err}`)
				end
			end
		end
	end
end

local function dannyLoop()
	while true do
		task.wait(T.DannyEvery)
		local ok, err = pcall(function()
			lookForDanny()
		end)
		if not ok then
			warn(`[SandboxTasks] Danny's look failed: {err}`)
		end
	end
end

function SandboxTasks.start()
	if started then
		return
	end
	started = true
	remote.OnServerEvent:Connect(onRequest)
	Collection.onChanged(onCollection)
	Collection.onTransferred(onTransferred) -- 8.7 review
	Collection.onPaid(onPaid)
	Upgrades.onChanged(onUpgrades)
	local Moving = require(script.Parent.Moving)
	Moving.onStored(onTrip)
	Moving.onResult(onFinish)
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
	Players.PlayerRemoving:Connect(left)
	task.spawn(resetLoop)
	task.spawn(dannyLoop)
end

return SandboxTasks
