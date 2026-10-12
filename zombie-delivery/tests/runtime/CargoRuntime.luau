--!strict
-- 6.23 (from Codex's codex/cargo-missions-fix): the few services and server modules the real server/Cargo.luau needs
-- in the Luau CLI (tests/cargo_runtime_test.luau through tests/run_tests.py, which builds CargoServer.luau from
-- src/server/Cargo.luau with these in place of its requires). The instances are tools/fixtures/item-mock.luau's
-- recorder (the same world shared/CargoLooks.luau builds the pieces in). No physics, no proximity distances, no
-- Studio: an unmocked server function errors with its name.
local Mock = require("./ItemMock") :: any
local Runtime: any = { messages = {}, spawnFailures = 0, spawnAttempts = 0, models = 0, failModelAfter = nil, onSpawn = nil }

Mock.workspace.GetServerTimeNow = function()
	return 100
end
Mock.workspace.Raycast = function()
	return nil
end
Mock.Random = {
	new = function()
		return {
			NextInteger = function(_, low)
				return low
			end,
			NextNumber = function(_, low)
				return low or 0.5
			end,
		}
	end,
}
Mock.RaycastParams = { new = function()
	return {}
end }
Mock.UDim2.fromOffset = function(x, y)
	return { x, y }
end
Mock.UDim2.new = function(a, b, c, d)
	return { a, b, c, d }
end
Mock.UDim = { new = function(a, b)
	return { a, b }
end }
Mock.Vector2 = Mock.Vector2 or { new = function(x, y)
	return { X = x, Y = y }
end }
Mock.NumberRange = { new = function(a, b)
	return { a, b }
end }
Mock.TweenInfo = { new = function(...)
	return { ... }
end }

local create = Mock.Instance.new
Mock.Instance.new = function(class: string)
	-- A chosen number of Model allocations succeed, then one fails (a piece or a person that could not be made).
	if class == "Model" and Runtime.failModelAfter ~= nil then
		if Runtime.failModelAfter == 0 then
			Runtime.failModelAfter = nil
			error("test: model creation failed")
		end
		Runtime.failModelAfter -= 1
	end
	if class == "Model" then
		Runtime.models += 1
	end
	local obj = create(class)
	-- Events: Connect keeps the callback (a prompt's Triggered is fired by the test: obj.fire(...)).
	local function event(name: string)
		return {
			Connect = function(_, callback)
				obj[name .. "Callback"] = callback
				return { Disconnect = function()
					obj[name .. "Callback"] = nil
				end, Connected = true }
			end,
		}
	end
	obj.Triggered = event("Triggered")
	obj.PromptButtonHoldBegan = event("HoldBegan")
	obj.Destroying = event("Destroying")
	obj.Touched = event("Touched")
	if class == "ProximityPrompt" then
		obj.Enabled = true
	end
	return obj
end

-- The remotes (shared/Net.luau): every message to a client kept in Runtime.messages.
Runtime.Net = { get = function()
	return {
		FireClient = function(_, _, message)
			table.insert(Runtime.messages, message)
		end,
		FireAllClients = function() end,
		OnServerEvent = { Connect = function() end },
	}
end }

-- An unmocked server function says which one (the harness then needs it).
local function stub(name: string, fields: { [string]: any }): any
	return setmetatable(fields, { __index = function(_, key)
		error(`CargoRuntime: unmocked {name}.{tostring(key)}`, 2)
	end })
end

local noop = function() end
-- Runtime.car: the owner's vehicle (nil: on foot), Runtime.parkedCar(player) makes one parked at the origin.
Runtime.car = nil
function Runtime.parkedCar(owner: any): any
	local model = Mock.Instance.new("Model")
	model.Parent = Mock.workspace
	local chassis = Mock.Instance.new("Part")
	chassis.Parent = model
	model.PrimaryPart = chassis
	return { model = model, chassis = chassis, owner = owner, id = "van", wrecked = false, size = Mock.Vector3.new(6, 6, 14) }
end
Runtime.Vehicles = stub("Vehicles", {
	get = function()
		return Runtime.car
	end,
	seatedIn = function()
		return nil
	end,
	isDriving = function()
		return false
	end,
	bikeStows = function()
		return false
	end,
	speed = function()
		return 0
	end,
	cargoEntry = function(car)
		return car.chassis.Position + Mock.Vector3.new(0, 0, 8)
	end,
	cargoSlots = function()
		return {} -- (nothing drawn in the vehicle)
	end,
	capacity = function()
		return 0
	end,
	hasBack = function()
		return false
	end,
	backOpen = function()
		return true
	end,
	backPrompt = function()
		return nil
	end,
	setBack = noop,
})
Runtime.Npcs = stub("Npcs", {
	spawn = function(look, _at)
		Runtime.spawnAttempts += 1
		local onSpawn = Runtime.onSpawn
		Runtime.onSpawn = nil
		if onSpawn then
			onSpawn() -- (a spawn that yields: the stop may move on meanwhile)
		end
		if Runtime.spawnFailures > 0 then
			Runtime.spawnFailures -= 1
			error("test: NPC spawn failed")
		end
		local npc = Mock.Instance.new("Model")
		npc.Name = look.name
		npc.Parent = Mock.workspace
		return npc
	end,
	look = function(role, name, title)
		return { role = role, name = name, title = title }
	end,
	act = noop,
	say = noop,
	walkTo = noop,
	remove = function(npc)
		npc:Destroy()
	end,
})
Runtime.HandItem = stub("HandItem", { hold = noop, release = noop, pass = noop, drop = noop })
Runtime.Animals = stub("Animals", {})
Runtime.Equipment = stub("Equipment", {
	pushing = function()
		return nil
	end,
	start = noop,
})
Runtime.PlayerData = stub("PlayerData", {
	get = function()
		return nil
	end,
	addMoney = noop,
	Changed = { Connect = noop },
})
Runtime.Hand = stub("Hand", {
	get = function()
		return "free"
	end,
	set = function()
		return true
	end,
	onChanged = noop,
})
Runtime.KitWear = stub("KitWear", { bagArt = noop, bagDrop = noop })
Runtime.Skills = stub("Skills", {
	effect = function()
		return 0
	end,
	hands = function()
		return 0
	end,
	bag = function()
		return 0
	end,
})
Runtime.Tasks = stub("Tasks", { note = noop })

-- task: a delay runs at once (the stop's lingering cleanup, a gesture's moment); spawn and defer too.
Runtime.task = {
	delay = function(_, callback, ...)
		callback(...)
	end,
	spawn = function(callback, ...)
		callback(...)
	end,
	defer = function(callback, ...)
		callback(...)
	end,
	wait = function()
		return 0
	end,
}

local services: { [string]: any } = {
	Players = { GetPlayers = function()
		return {}
	end, PlayerRemoving = { Connect = noop } },
	ReplicatedStorage = { WaitForChild = function()
		return {}
	end },
	StarterPlayer = {},
	CollectionService = { AddTag = noop, RemoveTag = noop },
	TweenService = { Create = function()
		return { Play = noop }
	end },
}
Runtime.game = { GetService = function(_, name)
	assert(services[name], `CargoRuntime: unmocked service {name}`)
	return services[name]
end }
Runtime.Mock = Mock
return Runtime
