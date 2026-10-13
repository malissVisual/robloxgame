--!strict
-- 8.0 SANDBOX: the few services and server modules the real server/Admin.luau needs in the Luau CLI
-- (tests/adminsandbox_runtime_test.luau through tests/run_tests.py, which builds AdminServer.luau from
-- src/server/Admin.luau with these in place of its requires; Config, Economy, Levels, Map, Missions, SandboxMap,
-- SandboxAdmin and FurnitureLooks are the real ones). The instances and the CFrame maths are
-- tools/fixtures/item-mock.luau's recorder; the players, their bodies and cars are made here. The other 8.0 workers'
-- modules (Collection, Moving, SandboxPlots) are fakes shaped like design/sandbox/KONTRAKT.md's API that record every
-- call. os.clock is the test's (Runtime.clock); task.wait only yields inside task.spawn's threads (Admin.start's loop
-- waits there for good); Net.limit answers Runtime.limitOpen and records the call.
local Mock = require("./ItemMock") :: any
local SandboxMap = require("./SandboxMap")

local Runtime: any = {
	clock = 100,
	notices = {}, -- { { to, text } } every Notice
	money = {}, -- { { player, amount, reason } } PlayerData.addMoney
	notified = 0, -- PlayerData.notify calls
	profiles = {}, -- player → { money, earned }
	plots = {}, -- player → plot id (SandboxPlots.of)
	onMove = {}, -- player → true: Moving.busy says so
	moving = {}, -- { { player, arg } } Moving.admin
	cars = {}, -- player → the fake car (Vehicles.get)
	seated = {}, -- player → the car they drive (Vehicles.seatedIn)
	spawned = {}, -- { { player, id, ground, seat } } Vehicles.spawnAt
	limits = {}, -- { { player, name, rate } } Net.limit
	limitOpen = true,
	collection = { added = {}, shown = {}, sold = {}, cleared = 0, stock = {} },
}
Runtime.Mock = Mock

-- The recorder's CFrame has no LookVector: -Z of its rotation (the third column)
local F = getmetatable(Mock.CFrame.new())
local frameIndex = F.__index
F.__index = function(self: any, key: string): any
	if key == "LookVector" then
		local r = self.R
		return Mock.Vector3.new(-r[3], -r[6], -r[9])
	end
	return if type(frameIndex) == "table" then frameIndex[key] else frameIndex(self, key)
end

local function signal(): any
	local s: any = { handlers = {} }
	function s.Connect(self: any, fn: any)
		table.insert(self.handlers, fn)
		return { Disconnect = function() end }
	end
	function s.Fire(self: any, ...: any)
		for _, fn in table.clone(self.handlers) do
			fn(...)
		end
	end
	return s
end
Runtime.signal = signal

-- ── The services ────────────────────────────────────────────────────────────

local players = Mock.Instance.new("Players")
players.PlayerAdded = signal()
players.PlayerRemoving = signal()
players.GetPlayers = function(self: any)
	return self:GetChildren()
end
players.GetPlayerByUserId = function(self: any, id: number)
	for _, player in self:GetChildren() do
		if player.UserId == id then
			return player
		end
	end
	return nil
end

local workspace = Mock.Instance.new("Workspace")
workspace.Raycast = function()
	return nil
end
Runtime.workspace = workspace

local services: { [string]: any } = {
	Players = players,
	ReplicatedStorage = { WaitForChild = function()
		return {}
	end },
	RunService = { Heartbeat = signal(), IsStudio = function()
		return false
	end },
}
Runtime.Enum = { CreatorType = { User = "User", Group = "Group" }, RaycastFilterType = { Exclude = "Exclude", Include = "Include" } }
Runtime.game = {
	CreatorType = "User",
	CreatorId = 0,
	GetService = function(_: any, name: string)
		return assert(services[name], "no service " .. name)
	end,
}
Runtime.script = { Parent = {} }
Runtime.os = setmetatable({ clock = function()
	return Runtime.clock
end }, { __index = os })
Runtime.RaycastParams = { new = function()
	return {}
end }
local seed = 7
Runtime.Random = { new = function()
	local function step(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	return {
		NextNumber = function(_: any, low: number?, high: number?)
			local a, b = low or 0, high or 1
			return a + (b - a) * step()
		end,
		NextInteger = function(_: any, low: number, high: number)
			return low + math.floor(step() * (high - low + 1))
		end,
	}
end }

local threads: { [thread]: boolean } = {}
Runtime.task = {
	spawn = function(fn: any, ...: any)
		local co = coroutine.create(fn)
		threads[co] = true
		local ok, err = coroutine.resume(co, ...)
		assert(ok, err)
		return co
	end,
	wait = function()
		if threads[coroutine.running()] then
			coroutine.yield()
		end
		return 0
	end,
	defer = function(fn: any, ...: any)
		fn(...)
	end,
	delay = function(_: number, fn: any, ...: any)
		fn(...)
	end,
}

-- ── Net ─────────────────────────────────────────────────────────────────────

local remotes: { [string]: any } = {}
Runtime.Net = {
	get = function(name: string)
		if not remotes[name] then
			remotes[name] = {
				OnServerEvent = signal(),
				FireClient = function(_: any, to: any, text: any)
					if name == "Notice" then
						table.insert(Runtime.notices, { to = to, text = text })
					end
				end,
				FireAllClients = function() end,
			}
		end
		return remotes[name]
	end,
	limit = function(player: any, name: string, rate: number): boolean
		table.insert(Runtime.limits, { player = player, name = name, rate = rate })
		return Runtime.limitOpen
	end,
}

-- A command from a player's panel: (name, arg, target UserId)
function Runtime.fire(player: any, name: any, arg: any, target: any)
	Runtime.Net.get("Admin").OnServerEvent:Fire(player, name, arg, target)
end

-- The notices to a player since `from` (an index into Runtime.notices), joined.
function Runtime.said(player: any, from: number?): string
	local lines = {}
	for index = (from or 0) + 1, #Runtime.notices do
		local entry = Runtime.notices[index]
		if entry.to == player then
			table.insert(lines, tostring(entry.text))
		end
	end
	return table.concat(lines, " | ")
end

-- ── Players, bodies, cars ───────────────────────────────────────────────────

local function part(name: string, parent: any, at: any): any
	local made = Mock.Instance.new("Part")
	made.Name = name
	made.CFrame = at
	made.Parent = parent
	return made
end

function Runtime.player(id: number, name: string): any
	local player = Mock.Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = id
	player.CharacterAdded = signal()
	player.Kick = function() end
	local body = Mock.Instance.new("Model")
	body.Name = name
	local root = part("HumanoidRootPart", body, Mock.CFrame.new(0, 3, 0))
	body.PrimaryPart = root
	local humanoid = Mock.Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.MaxHealth = 100
	humanoid.Parent = body
	body.Parent = workspace
	player.Character = body
	player.Parent = players
	Runtime.profiles[player] = { money = 500, earned = 500 }
	players.PlayerAdded:Fire(player)
	return player
end

function Runtime.newCar(player: any, id: string, ground: any): any
	local model = Mock.Instance.new("Model")
	model.Name = `{player.Name}'s {id}`
	local chassis = part("Chassis", model, ground * Mock.CFrame.new(0, 3, 0))
	model.PrimaryPart = chassis
	model.Parent = workspace
	return { owner = player, id = id, model = model, chassis = chassis, wrecked = false, health = 100, stats = { health = 100 } }
end

-- ── The server modules ──────────────────────────────────────────────────────

Runtime.PlayerData = {
	get = function(player: any)
		return Runtime.profiles[player]
	end,
	addMoney = function(player: any, amount: number, reason: string?)
		table.insert(Runtime.money, { player = player, amount = amount, reason = reason })
		local profile = Runtime.profiles[player]
		if profile then
			profile.money += amount
			profile.earned += amount
		end
	end,
	notify = function()
		Runtime.notified += 1
	end,
}

Runtime.Vehicles = {
	get = function(player: any)
		return Runtime.cars[player]
	end,
	seatedIn = function(player: any)
		local car = Runtime.seated[player]
		return car, car ~= nil
	end,
	spawnAt = function(player: any, id: string, ground: any, seat: boolean)
		table.insert(Runtime.spawned, { player = player, id = id, ground = ground, seat = seat })
		local car = Runtime.newCar(player, id, ground)
		Runtime.cars[player] = car
		return car
	end,
	isBike = function()
		return false
	end,
}

-- server/SandboxPlots.luau's of(player)
Runtime.SandboxPlots = {
	of = function(player: any)
		local id = Runtime.plots[player]
		return if id then SandboxMap.Plots[id] else nil
	end,
}

-- server/Moving.luau's busy and admin (the MOVES buttons' arguments)
Runtime.Moving = {
	busy = function(player: any)
		return if Runtime.onMove[player] then "You are on a move." else nil
	end,
	admin = function(player: any, arg: any)
		table.insert(Runtime.moving, { player = player, arg = arg })
		if arg == "end" then
			Runtime.onMove[player] = nil
			return "ADMIN: the move is called off."
		end
		return `ADMIN: moving {arg}.`
	end,
}

-- server/Collection.luau (design/sandbox/KONTRAKT.md's API), a sale pays $100
local C = Runtime.collection
local serial = 0
local function stockOf(player: any): { any }
	C.stock[player] = C.stock[player] or {}
	return C.stock[player]
end
Runtime.Collection = {
	add = function(player: any, entry: any)
		serial += 1
		local uid = `p{serial}`
		table.insert(C.added, { player = player, entry = entry })
		table.insert(stockOf(player), { uid = uid, item = entry.item, variant = entry.variant or 1, condition = entry.condition, name = entry.item, stand = nil, got = 0 })
		return uid
	end,
	stock = function(player: any)
		return table.clone(stockOf(player))
	end,
	display = function(player: any, uid: string, stand: number)
		for _, entry in stockOf(player) do
			if entry.uid == uid then
				entry.stand = stand
				table.insert(C.shown, { player = player, uid = uid, stand = stand })
				return true, nil
			end
		end
		return false, "no such piece"
	end,
	sell = function(player: any, uid: string)
		local list = stockOf(player)
		for index, entry in list do
			if entry.uid == uid then
				table.remove(list, index)
				table.insert(C.sold, { player = player, uid = uid })
				Runtime.PlayerData.addMoney(player, 100, "CollectionSale")
				return 100, nil
			end
		end
		return nil, "no such piece"
	end,
}

-- The rest of Admin's requires: only what Admin.start touches (the others error with their name when a test calls them).
Runtime.World = { RoadTop = 0.4 }
Runtime.Zombies = { hunts = function()
	return false
end, frozen = false }
Runtime.BanditCars = { wanted = function()
	return false
end, frozen = false }
for _, name in { "Jobs", "DayNight", "Estate", "Missions", "Challenges", "Traffic", "Buddy" } do
	Runtime[name] = {}
end

return Runtime
