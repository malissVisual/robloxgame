--!strict
-- 8.2 SANDBOX, showing off: what the real server/SandboxLeaders.luau needs besides tests/runtime/CollectionRuntime.luau
-- (tests/sandboxleaders_runtime_test.luau through tests/run_tests.py, which builds SandboxLeadersServer.luau with these
-- in place of `game`, `UDim2`, `UDim` and `Vector2`; its PlayerData and Collection are the real ones on that runtime):
--   * an OrderedDataStore (DataStoreService:GetOrderedDataStore): Leaders.ordered[name] = { key → value }; every
--     GetAsync and UpdateAsync is counted (Leaders.gets, Leaders.updates; Leaders.writes: the ones that stored a value)
--     with the test's clock (Leaders.writeTimes); Leaders.down = true makes every call fail, Leaders.noStore = true makes
--     GetOrderedDataStore itself fail (no API access); an UpdateAsync value must be a whole number (as Roblox's);
--   * a `game` whose DataStoreService has both kinds of store (the rest of the services CollectionRuntime's);
--   * UDim2 (new, fromScale, fromOffset), UDim (new): plain tables the test can read.
local E = require("./CollectionRuntime") :: any

local Leaders: any = {
	E = E,
	ordered = {}, -- store name → { key → value }
	gets = 0,
	updates = 0,
	writes = 0,
	writeTimes = {}, -- { { key, clock } } every UpdateAsync that stored a value
	down = false,
	noStore = false,
	asked = {}, -- the store names asked for
}

local function orderedStore(name: string): any
	local data = Leaders.ordered[name] or {}
	Leaders.ordered[name] = data
	local ordered: any = {}
	function ordered.GetAsync(_self: any, key: string): any
		Leaders.gets += 1
		if Leaders.down then
			error("DataStore request failed (the test's outage)")
		end
		return data[key]
	end
	function ordered.UpdateAsync(_self: any, key: string, transform: (any) -> any): any
		Leaders.updates += 1
		if Leaders.down then
			error("DataStore request failed (the test's outage)")
		end
		local new = transform(data[key])
		if new ~= nil then
			assert(type(new) == "number" and new == math.floor(new), "an OrderedDataStore keeps whole numbers only")
			data[key] = new
			Leaders.writes += 1
			table.insert(Leaders.writeTimes, { key = key, clock = E.clock })
		end
		return new
	end
	return ordered
end

local base = E.game:GetService("DataStoreService")
local dataStoreService: any = {
	GetDataStore = base.GetDataStore,
	GetOrderedDataStore = function(_self: any, name: string): any
		table.insert(Leaders.asked, name)
		if Leaders.noStore then
			error("You must publish this place to the web to access DataStore (the test's Studio)")
		end
		return orderedStore(name)
	end,
}

Leaders.game = {
	JobId = E.game.JobId,
	GetService = function(_self: any, name: string): any
		if name == "DataStoreService" then
			return dataStoreService
		end
		return E.game:GetService(name)
	end,
	BindToClose = function(_self: any, fn: any)
		E.game:BindToClose(fn)
	end,
}

Leaders.UDim = {
	new = function(scale: number, offset: number): any
		return { Scale = scale, Offset = offset }
	end,
}
Leaders.UDim2 = {
	new = function(xs: number, xo: number, ys: number, yo: number): any
		return { X = { Scale = xs, Offset = xo }, Y = { Scale = ys, Offset = yo } }
	end,
	fromScale = function(x: number, y: number): any
		return { X = { Scale = x, Offset = 0 }, Y = { Scale = y, Offset = 0 } }
	end,
	fromOffset = function(x: number, y: number): any
		return { X = { Scale = 0, Offset = x }, Y = { Scale = 0, Offset = y } }
	end,
}

return Leaders
