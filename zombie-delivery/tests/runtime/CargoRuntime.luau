--!strict
-- Minimal services for exercising the real server/Cargo module in the Luau CLI. No physics or Studio emulation.
local Mock = require("./RobloxMock")
local Runtime: any = { messages = {}, spawnFailures = 0, spawnAttempts = 0 }

Mock.workspace.GetServerTimeNow = function() return 100 end
Mock.workspace.Raycast = function() return nil end
Mock.Random = { new = function()
	return { NextInteger = function(_, low) return low end, NextNumber = function(_, low) return low or 0.5 end }
end }
Mock.RaycastParams = { new = function() return {} end }
Mock.UDim2.fromOffset = function(x, y) return { x, y } end

local create = Mock.Instance.new
Mock.Instance.new = function(class)
	-- Fail before the allocation, after a chosen number of successful cargo/NPC model allocations.
	if class == "Model" and Runtime.failModelAfter ~= nil then
		if Runtime.failModelAfter == 0 then
			Runtime.failModelAfter = nil
			error("test: model creation failed")
		end
		Runtime.failModelAfter -= 1
	end
	local obj = create(class)
	obj.FindFirstChildWhichIsA = function(self, kind)
		for _, child in self:GetChildren() do
			if child:IsA(kind) then return child end
		end
		return nil
	end
	obj.GetExtentsSize = function(self)
		local _, size = self:GetBoundingBox()
		return size
	end
	obj.Triggered = { Connect = function(_, cb)
		obj.trigger = cb
		return { Disconnect = function() obj.trigger = nil end }
	end }
	if class == "ProximityPrompt" then obj.Enabled = true end
	return obj
end

Runtime.Net = { get = function()
	return { FireClient = function(_, _, message) table.insert(Runtime.messages, message) end }
end }
Runtime.Vehicles = { get = function() return nil end, seatedIn = function() return nil end }
Runtime.Equipment = { pushing = function() return nil end }
Runtime.Npcs = {
	spawn = function(look, _at)
		Runtime.spawnAttempts += 1
		local onSpawn = Runtime.onSpawn
		Runtime.onSpawn = nil
		if onSpawn then onSpawn() end
		if Runtime.spawnFailures > 0 then
			Runtime.spawnFailures -= 1
			error("test: NPC spawn failed")
		end
		local npc = Mock.Instance.new("Model")
		npc.Name = look.name
		npc.Parent = Mock.workspace
		return npc
	end,
	act = function() end,
	say = function() end,
	remove = function(npc) npc:Destroy() end,
}
Runtime.Animals = {}
Runtime.task = { delay = function(_, cb) cb() end } -- These tests only schedule stop cleanup.
local services = {
	Players = { GetPlayers = function() return {} end },
	ReplicatedStorage = { WaitForChild = function() return {} end },
	StarterPlayer = {},
	CollectionService = { AddTag = function() end },
}
Runtime.game = { GetService = function(_, name)
	assert(services[name], `unmocked service: {name}`)
	return services[name]
end }
Runtime.Mock = Mock
return Runtime
