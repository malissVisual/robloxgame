--!strict
-- 8.0 SANDBOX: the few services the real server/PlayerData.luau and server/Collection.luau need in the Luau CLI
-- (tests/collection_runtime_test.luau through tests/run_tests.py, which builds PlayerDataServer.luau and
-- CollectionServer.luau from them with these in place of `game`, `task`, `os`, `Instance`, `warn` and shared/Net.luau;
-- every other module they require is the real one). No Roblox simulator:
--   * players are recorder instances (tools/fixtures/item-mock.luau) that join (Runtime.join) and leave (Runtime.leave)
--     on cue, under a Players service with PlayerAdded / PlayerRemoving / GetPlayers;
--   * one DataStore (Runtime.saves: key → the stored value) keeps what UpdateAsync returns as JSON would: a copy, and a
--     value a DataStore cannot hold (NaN, a function, an instance, a table with mixed or number keys) is an error;
--   * the clock is the test's: Runtime.clock (os.clock) and Runtime.now (os.time) move only with Runtime.advance, which
--     wakes the threads waiting in task.wait at their exact times; task.defer waits for Runtime.flush (advance flushes
--     too); task.spawn runs at once (a coroutine: task.wait inside it waits for advance);
--   * Net: Net.get gives a fake remote (FireClient is recorded in Runtime.sent; Runtime.fire sends a client's request),
--     Net.limit is shared/Net.luau's token bucket on the test's clock.
local Mock = require("./ItemMock") :: any

local Runtime: any = {
	clock = 100, -- os.clock()
	now = 1760000000, -- os.time()
	studio = false, -- RunService:IsStudio()
	saves = {}, -- the DataStore: key → value
	writes = 0, -- UpdateAsync calls that wrote
	sent = {}, -- { { remote, player, args } } every FireClient
	warnings = {},
	sleeping = {}, -- { { co, wake, args? } } threads in task.wait / task.delay
	deferred = {}, -- { { fn, args } } task.defer
}
Runtime.Mock = Mock

-- ── Signals ─────────────────────────────────────────────────────────────────

local function signal(): any
	local s: any = { handlers = {} }
	function s.Connect(self: any, fn: any)
		local handler = { fn = fn, on = true }
		table.insert(self.handlers, handler)
		return {
			Connected = true,
			Disconnect = function()
				handler.on = false
			end,
		}
	end
	function s.Fire(self: any, ...: any)
		for _, handler in table.clone(self.handlers) do
			if handler.on then
				handler.fn(...)
			end
		end
	end
	function s.Wait()
		return nil
	end
	return s
end
Runtime.signal = signal

-- ── task, os, warn ──────────────────────────────────────────────────────────

local function resume(co: thread, ...: any)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error(tostring(err), 0)
	end
end

local task: any = {}
function task.spawn(fn: any, ...: any): thread
	local co = coroutine.create(fn)
	resume(co, ...)
	return co
end
function task.wait(seconds: number?): number
	local wait = seconds or 0
	if coroutine.isyieldable() then
		table.insert(Runtime.sleeping, { co = coroutine.running(), wake = Runtime.clock + wait })
		coroutine.yield()
	else
		Runtime.clock += wait -- (the main thread: the time just passes)
		Runtime.now += wait
	end
	return wait
end
function task.defer(fn: any, ...: any)
	table.insert(Runtime.deferred, { fn = fn, args = table.pack(...) })
end
function task.delay(seconds: number, fn: any, ...: any)
	table.insert(Runtime.sleeping, { co = coroutine.create(fn), wake = Runtime.clock + seconds, args = table.pack(...) })
end
Runtime.task = task

-- Runs every deferred function (and the ones they defer).
function Runtime.flush()
	local guard = 0
	while #Runtime.deferred > 0 do
		guard += 1
		assert(guard < 10000, "task.defer loops")
		local job = table.remove(Runtime.deferred, 1)
		task.spawn(job.fn, table.unpack(job.args, 1, job.args.n))
	end
end

-- Moves the clock `seconds` on, waking every waiting thread at its own time (in order), the deferred ones after each.
function Runtime.advance(seconds: number)
	local target = Runtime.clock + seconds
	Runtime.flush()
	while true do
		local first, at = nil, math.huge
		for index, entry in Runtime.sleeping do
			if entry.wake <= target + 1e-9 and entry.wake < at then
				first, at = index, entry.wake
			end
		end
		if not first then
			break
		end
		local entry = table.remove(Runtime.sleeping, first)
		Runtime.now += math.max(0, entry.wake - Runtime.clock)
		Runtime.clock = math.max(Runtime.clock, entry.wake)
		if entry.args then
			resume(entry.co, table.unpack(entry.args, 1, entry.args.n))
		else
			resume(entry.co)
		end
		Runtime.flush()
	end
	Runtime.now += math.max(0, target - Runtime.clock)
	Runtime.clock = target
end

Runtime.os = setmetatable({
	clock = function(): number
		return Runtime.clock
	end,
	time = function(): number
		return math.floor(Runtime.now)
	end,
}, { __index = os })

function Runtime.warn(...: any)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	table.insert(Runtime.warnings, table.concat(parts, " "))
	print("WARN", ...)
end

-- ── Instances ──────────────────────────────────────────────────────────────

local create = Mock.Instance.new
Runtime.Instance = {
	new = function(class: string): any
		local obj = create(class)
		if class == "BindableEvent" then
			local event = signal()
			obj.Event = event
			obj.Fire = function(_self: any, ...: any)
				event:Fire(...)
			end
		end
		return obj
	end,
}

-- ── The DataStore (stored as JSON would) ──────────────────────────────────

-- A copy of what a DataStore would keep; an error for what it could not.
local function stored(value: any, path: string): any
	local kind = type(value)
	if kind == "nil" or kind == "boolean" or kind == "string" then
		return value
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error(`a DataStore cannot keep {value} at {path}`)
		end
		return value
	elseif kind ~= "table" or getmetatable(value) ~= nil then
		error(`a DataStore cannot keep a {kind} at {path}`)
	end
	local count, strings = 0, 0
	for key in value do
		count += 1
		if type(key) == "string" then
			strings += 1
		end
	end
	local out = {}
	if strings == count then
		for key, item in value do
			out[key] = stored(item, `{path}.{key}`)
		end
	elseif strings == 0 and #value == count then
		for index, item in value do
			out[index] = stored(item, `{path}[{index}]`)
		end
	else
		error(`a DataStore cannot keep the mixed or sparse table at {path}`)
	end
	return out
end
Runtime.stored = stored

local dataStore: any = {}
function dataStore.UpdateAsync(_self: any, key: string, transform: (any) -> any): any
	local old = Runtime.saves[key]
	local new = transform(if old ~= nil then stored(old, key) else nil)
	if new ~= nil then
		Runtime.saves[key] = stored(new, key)
		Runtime.writes += 1
	end
	return new
end
function dataStore.GetAsync(_self: any, key: string): any
	return Runtime.saves[key]
end

-- ── The services ───────────────────────────────────────────────────────────

local players = create("Players")
players.PlayerAdded = signal()
players.PlayerRemoving = signal()
players.GetPlayers = function(self: any)
	return table.clone(self.children)
end
Runtime.Players = players

local services: { [string]: any } = {
	Players = players,
	ReplicatedStorage = {
		WaitForChild = function()
			return {}
		end,
	},
	RunService = {
		IsStudio = function()
			return Runtime.studio
		end,
		IsServer = function()
			return true
		end,
		IsClient = function()
			return false
		end,
	},
	DataStoreService = {
		GetDataStore = function()
			return dataStore
		end,
	},
}
Runtime.game = {
	JobId = "test-server",
	GetService = function(_self: any, name: string): any
		return services[name] or {}
	end,
	BindToClose = function(_self: any, fn: any)
		Runtime.onClose = fn
	end,
}

-- A player (not in the game yet): Runtime.join puts them in.
function Runtime.player(userId: number, name: string?): any
	local player = create("Player")
	player.Name = name or `Player{userId}`
	player.UserId = userId
	player.Kick = function(self: any, why: string?)
		self.kicked = why or true
	end
	return player
end

-- The player joins (PlayerAdded: PlayerData loads their save at once); the deferred work runs.
function Runtime.join(userId: number, name: string?): any
	local player = Runtime.player(userId, name)
	player.Parent = players
	players.PlayerAdded:Fire(player)
	Runtime.flush()
	return player
end

-- The player leaves (PlayerRemoving while still in the game, then out); the deferred work (the leave save) runs.
function Runtime.leave(player: any)
	players.PlayerRemoving:Fire(player)
	player.Parent = nil
	Runtime.flush()
end

-- ── Net ────────────────────────────────────────────────────────────────────

local remotes: { [string]: any } = {}
local Net: any = {}
function Net.get(name: string): any
	local remote = remotes[name]
	if not remote then
		remote = { Name = name, OnServerEvent = signal() }
		function remote.FireClient(self: any, player: any, ...: any)
			table.insert(Runtime.sent, { remote = self.Name, player = player, args = table.pack(...) })
		end
		function remote.FireAllClients(self: any, ...: any)
			for _, player in players.children do
				self:FireClient(player, ...)
			end
		end
		remotes[name] = remote
	end
	return remote
end
-- shared/Net.luau's token bucket, on the test's clock
local buckets: { [any]: { [string]: { tokens: number, at: number } } } = {}
function Net.limit(player: any, name: string, perSecond: number): boolean
	local mine = buckets[player] or {}
	buckets[player] = mine
	local bucket = mine[name]
	if not bucket then
		bucket = { tokens = math.max(1, perSecond), at = Runtime.clock }
		mine[name] = bucket
	else
		bucket.tokens = math.min(math.max(1, perSecond), bucket.tokens + (Runtime.clock - bucket.at) * perSecond)
		bucket.at = Runtime.clock
	end
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end
function Net.latest(player: any, name: string, perSecond: number, fn: any, ...: any)
	if Net.limit(player, name, perSecond) then
		fn(player, ...)
	end
end
Runtime.Net = Net

-- A client's request on a remote (OnServerEvent), the deferred work after it.
function Runtime.fire(player: any, name: string, ...: any)
	Net.get(name).OnServerEvent:Fire(player, ...)
	Runtime.flush()
end

-- What the server sent this player on this remote since `from` (an index into Runtime.sent; 0: all): the first
-- arguments (the Collection remote's messages, the Notice texts).
function Runtime.received(player: any, name: string, from: number?): { any }
	local out = {}
	for index = (from or 0) + 1, #Runtime.sent do
		local sent = Runtime.sent[index]
		if sent.player == player and sent.remote == name then
			table.insert(out, sent.args[1])
		end
	end
	return out
end

return Runtime
