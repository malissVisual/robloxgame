--!nocheck
-- 8.0 SANDBOX: the world the real server/Main.server.luau and server/SandboxBoot.luau boot in, in the Luau CLI
-- (tests/boot_runtime_test.luau through tests/run_tests.py, which builds MainServer.luau and SandboxBootServer.luau
-- from them: each source wrapped in a function that runs it again, its globals and `require` these). Every service
-- and Roblox object is a RECORDER: any field read is another recorder (named by its path, "World.build"), any call is
-- logged (Runtime.log, in order, with its arguments) and returns a recorder, any assignment is kept (a hook: read back
-- as set; Runtime.log has "set World.x"). A few names are answered: GetService, WaitForChild / FindFirstChild (nil for
-- a name in Runtime.absent), GetPlayers / GetChildren, IsA (true), Connect (the handler kept: Runtime.fire runs it).
-- Config, Economy and SandboxMap are the real modules (SandboxMap.cframe on tools/vehicle-preview/roblox-mock's
-- CFrame); a test replaces a module's functions with Runtime.override. task.spawn / defer / delay only record (a
-- server loop never ends); task.wait returns at once.
local Mock = require("./rbxmock")
local Config = require("./Config")
local Economy = require("./Economy")
local SandboxMap = require("./SandboxMap")

local Runtime = {}
Runtime.CFrame = Mock.CFrame
Runtime.Vector3 = Mock.Vector3
Runtime.Config = Config
Runtime.SandboxMap = SandboxMap

local NIL = {} -- an assignment of nil (read back as nil, not as a new recorder)
local info = setmetatable({}, { __mode = "k" }) -- recorder → { path, children, values }
local Recorder = {}

local function leaf(path: string): string
	return string.match(path, "([%w_]+)$") or path
end

local function recorder(path: string): any
	local node = setmetatable({}, Recorder)
	info[node] = { path = path, children = {}, values = {} }
	return node
end
Runtime.isRecorder = function(x: any): boolean
	return type(x) == "table" and info[x] ~= nil
end
Runtime.pathOf = function(x: any): string?
	return if info[x] then info[x].path else nil
end

local function record(path: string, args: { any })
	table.insert(Runtime.log, path)
	table.insert(Runtime.args, args)
end

-- the names answered (called as methods: self first)
local SPECIAL = {}
function SPECIAL.GetService(_self: any, name: string): any
	return Runtime.service(name)
end
local function child(self: any, name: string, finding: boolean): any
	if finding and Runtime.absent[name] then
		return nil
	end
	local i = info[self]
	local key = "child:" .. name
	if not i.children[key] then
		i.children[key] = recorder(i.path .. "." .. name)
	end
	return i.children[key]
end
function SPECIAL.WaitForChild(self: any, name: string): any
	return child(self, name, true)
end
function SPECIAL.FindFirstChild(self: any, name: string): any
	return child(self, name, true)
end
function SPECIAL.GetPlayers(): { any }
	return table.clone(Runtime.players)
end
function SPECIAL.GetChildren(self: any): { any }
	return if self == Runtime.workspace then table.clone(Runtime.worldChildren) else {}
end
function SPECIAL.IsA(): boolean
	return true
end
function SPECIAL.Connect(self: any, fn: any): any
	local path = info[self].path
	record(path .. ".Connect", { self, fn })
	Runtime.handlers[path] = Runtime.handlers[path] or {}
	table.insert(Runtime.handlers[path], fn)
	return recorder(path .. ".Connection")
end

Recorder.__index = function(self: any, key: any): any
	local i = info[self]
	local value = i.values[key]
	if value == NIL then
		return nil
	elseif value ~= nil then
		return value
	end
	if SPECIAL[key] then
		return SPECIAL[key]
	end
	if not i.children[key] then
		i.children[key] = recorder(i.path .. "." .. tostring(key))
	end
	return i.children[key]
end
Recorder.__newindex = function(self: any, key: any, value: any)
	local i = info[self]
	i.values[key] = if value == nil then NIL else value
	record("set " .. i.path .. "." .. tostring(key), { value })
end
Recorder.__call = function(self: any, ...: any): any
	local i = info[self]
	local args = table.pack(...)
	record(i.path, args)
	local words = {}
	for n = 1, args.n do
		if type(args[n]) == "string" then
			table.insert(words, args[n])
		end
	end
	return recorder(i.path .. "(" .. table.concat(words, ",") .. ")")
end
Recorder.__iter = function(): any
	return next, {}
end
Recorder.__tostring = function(self: any): string
	return info[self].path
end

-- ── The world of one run ───────────────────────────────────────────────────

local REAL = { Config = true, Economy = true, SandboxMap = true }

function Runtime.reset()
	Runtime.log = {} -- every call and assignment, in order ("World.build", "set Zombies.ambient")
	Runtime.args = {} -- each one's arguments (table.pack), at the same index
	Runtime.handlers = {} -- a signal's path → its handlers
	Runtime.modules = {} -- name → the module's recorder (only the ones required this run)
	Runtime.services = {}
	Runtime.absent = { Cars = true, Zombies = true, Effects = true } -- (the place starts without them)
	Runtime.players = {}
	Runtime.spawned = {} -- task.spawn / defer / delay's functions, not run
	Runtime.deferred = {}
	Runtime.warnings = {}
	Runtime.printed = {}
	Runtime.made = {} -- Instance.new's
	Runtime.workspace = Runtime.service("Workspace")
	Runtime.script = recorder("script")
	Runtime.server = Runtime.script.Parent
	local baseplate = recorder("Baseplate")
	info[baseplate].values.Name = "Baseplate"
	Runtime.baseplate = baseplate
	Runtime.worldChildren = { baseplate }
	-- (SandboxMap.cframe needs Roblox's CFrame: the mock's)
	Runtime.fakeMap = setmetatable({
		cframe = function(spot: any): any
			return Mock.CFrame.new(spot.x, spot.y, spot.z) * Mock.CFrame.Angles(0, math.rad(spot.yaw), 0)
		end,
	}, { __index = SandboxMap })
	Runtime.fakes = { SandboxMap = Runtime.fakeMap } -- name → a module of the test's own (instead of a recorder)
end

function Runtime.service(name: string): any
	if not Runtime.services[name] then
		Runtime.services[name] = recorder(name)
	end
	return Runtime.services[name]
end

-- A module's recorder (its calls logged as "Name.fn").
function Runtime.module(name: string): any
	if not Runtime.modules[name] then
		Runtime.modules[name] = recorder(name)
	end
	return Runtime.modules[name]
end

-- A plain recorder object (a player, a body), its fields set (not logged).
function Runtime.object(name: string, fields: { [string]: any }?): any
	local obj = recorder(name)
	for key, value in fields or {} do
		info[obj].values[key] = value
	end
	return obj
end

-- Sets fields of a recorder (a module's functions, a player's Character) without logging them; nil clears.
function Runtime.override(target: any, fields: { [string]: any })
	local i = info[if type(target) == "string" then Runtime.module(target) else target]
	for key, value in fields do
		i.values[key] = if value == Runtime.Nil then NIL else value
	end
end
Runtime.Nil = {} -- (Runtime.override(x, { Character = Runtime.Nil }))

function Runtime.require(target: any): any
	local path = info[target] and info[target].path
	assert(path, "require of something that is not a recorder: " .. tostring(target))
	local name = leaf(path)
	if Runtime.fakes[name] ~= nil then
		return Runtime.fakes[name]
	elseif REAL[name] then
		return ({ Config = Config, Economy = Economy, SandboxMap = SandboxMap })[name]
	end
	return Runtime.module(name)
end

-- Runs a signal's handlers (by its recorder's path: "Players.PlayerAdded", "Net.get(Play).OnServerEvent").
function Runtime.fire(path: string, ...: any): number
	local list = Runtime.handlers[path] or {}
	for _, fn in list do
		fn(...)
	end
	return #list
end

-- The index of the first logged entry equal to `path` (nil: never), and how many there are.
function Runtime.find(path: string): (number?, number)
	local first, count = nil, 0
	for index, entry in Runtime.log do
		if entry == path then
			first = first or index
			count += 1
		end
	end
	return first, count
end

function Runtime.called(path: string): boolean
	return (Runtime.find(path)) ~= nil
end

-- Every logged call's arguments for `path`.
function Runtime.callsOf(path: string): { any }
	local out = {}
	for index, entry in Runtime.log do
		if entry == path then
			table.insert(out, Runtime.args[index])
		end
	end
	return out
end

-- The modules whose start() (or build()) ran this run, by name.
function Runtime.started(): { [string]: number }
	local out = {}
	for index, entry in Runtime.log do
		local name = string.match(entry, "^([%w_]+)%.start$") or string.match(entry, "^([%w_]+)%.build$")
		if name and out[name] == nil then
			out[name] = index
		end
	end
	return out
end

-- ── The globals the built sources see ──────────────────────────────────────

Runtime.game = recorder("game")
info[Runtime.game].values.GetService = function(_self: any, name: string): any
	return Runtime.service(name)
end
Runtime.task = {
	spawn = function(fn: any, ...: any)
		table.insert(Runtime.spawned, fn)
	end,
	defer = function(fn: any, ...: any)
		table.insert(Runtime.deferred, fn)
	end,
	delay = function(_: number, fn: any, ...: any)
		table.insert(Runtime.spawned, fn)
	end,
	wait = function(seconds: number?): number
		return seconds or 0
	end,
}
Runtime.warn = function(...: any)
	local parts = {}
	for _, part in { ... } do
		table.insert(parts, tostring(part))
	end
	table.insert(Runtime.warnings, table.concat(parts, " "))
end
Runtime.print = function(...: any)
	local parts = {}
	for _, part in { ... } do
		table.insert(parts, tostring(part))
	end
	table.insert(Runtime.printed, table.concat(parts, " "))
end
Runtime.Instance = {
	new = function(class: string): any
		local obj = recorder("new " .. class)
		info[obj].values.ClassName = class
		table.insert(Runtime.made, obj)
		return obj
	end,
}

Runtime.reset()

return Runtime
