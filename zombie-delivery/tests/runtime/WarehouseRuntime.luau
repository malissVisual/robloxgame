--!strict
-- 8.0 SANDBOX, the warehouse: the few server modules the real server/Warehouse.luau needs in the Luau CLI
-- (tests/warehouse_runtime_test.luau through tests/run_tests.py, which builds WarehouseServer.luau from
-- src/server/Warehouse.luau with these in place of its requires; Config, FurnitureLooks, SandboxMap and WarehouseLayout
-- are the real ones, FurnitureMesh the real one without an import). The recorder, the players, the signals (a prompt's
-- Triggered), the remotes (Runtime.messages, Runtime.lastNotice) and task.delay (at once) are
-- tests/runtime/MovingRuntime.luau's. Here: a fake SandboxPlots (Runtime.claim, Runtime.free) and a fake Collection
-- (a stock per player the test fills, Runtime.give / Runtime.changed; it records Runtime.calls). 8.1: the fake
-- Collection's stands (Runtime.standCount: player → how many, else Config.Warehouse.Stands) and boost (Runtime.boosts),
-- a fake Upgrades (its open recorded in Runtime.calls as "openUpgrades").
local E = require("./MovingRuntime") :: any
local SandboxMap = require("./SandboxMap")
local Config = require("./Config")

local Mock = E.Mock
local Runtime: any = {
	Mock = Mock,
	Net = E.Net,
	task = E.task,
	os = E.os,
	player = E.player,
	leave = E.leave,
	messages = E.messages,
	lastNotice = E.lastNotice,
	calls = {}, -- { { name, player, a } } every Collection call that changes something (and openPicker)
	income = {}, -- player → Collection.incomePerMinute
	stocks = {}, -- player → { Entry }
	standCount = {}, -- 8.1: player → Collection.stands (else Config.Warehouse.Stands)
	boosts = {}, -- 8.1: player → Collection.boost (else 1)
}

-- The Shared folder (empty: no CollectionRules) under the services MovingRuntime fakes.
local shared = Mock.Instance.new("Folder")
shared.Name = "Shared"
Runtime.game = {
	GetService = function(_, name: string): any
		if name == "ReplicatedStorage" then
			return {
				WaitForChild = function()
					return shared
				end,
			}
		end
		return E.game:GetService(name)
	end,
}

-- ── SandboxPlots ───────────────────────────────────────────────────────────

local owners: { [number]: any } = {}
local plotListeners: { (number, any) -> () } = {}
Runtime.SandboxPlots = {
	of = function(player: any): any
		for id, owner in owners do
			if owner == player then
				return SandboxMap.Plots[id]
			end
		end
		return nil
	end,
	owner = function(id: number): any
		return owners[id]
	end,
	onChanged = function(fn: (number, any) -> ())
		table.insert(plotListeners, fn)
	end,
}
function Runtime.claim(id: number, player: any)
	owners[id] = player
	player:SetAttribute("Plot", id)
	for _, fn in plotListeners do
		fn(id, player)
	end
end
function Runtime.free(id: number)
	owners[id] = nil
	for _, fn in plotListeners do
		fn(id, nil)
	end
end

-- ── Collection ─────────────────────────────────────────────────────────────

local changedListeners: { (any) -> () } = {}
function Runtime.changed(player: any)
	for _, fn in changedListeners do
		fn(player)
	end
end
local function find(player: any, uid: string): (any, number?)
	for index, entry in Runtime.stocks[player] or {} do
		if entry.uid == uid then
			return entry, index
		end
	end
	return nil, nil
end
-- One piece into the player's stock (stand: on show there) and the change told.
function Runtime.give(player: any, entry: any)
	Runtime.stocks[player] = Runtime.stocks[player] or {}
	table.insert(Runtime.stocks[player], entry)
	Runtime.changed(player)
end
Runtime.Collection = {
	stock = function(player: any): any
		local list = {}
		for _, entry in Runtime.stocks[player] or {} do
			table.insert(list, table.clone(entry))
		end
		return list
	end,
	incomePerMinute = function(player: any): number
		return Runtime.income[player] or 0
	end,
	openPicker = function(player: any, stand: number)
		table.insert(Runtime.calls, { "openPicker", player, stand })
	end,
	display = function(player: any, uid: string, stand: number): (boolean, string?)
		table.insert(Runtime.calls, { "display", player, uid })
		local entry = find(player, uid)
		if not entry then
			return false, "No such piece."
		end
		entry.stand = stand
		Runtime.changed(player)
		return true, nil
	end,
	undisplay = function(player: any, uid: string): (boolean, string?)
		table.insert(Runtime.calls, { "undisplay", player, uid })
		local entry = find(player, uid)
		if not entry or entry.stand == nil then
			return false, "It isn't on show."
		end
		entry.stand = nil
		Runtime.changed(player)
		return true, nil
	end,
	sell = function(player: any, uid: string): (number?, string?)
		table.insert(Runtime.calls, { "sell", player, uid })
		local _, index = find(player, uid)
		if not index then
			return nil, "No such piece."
		end
		table.remove(Runtime.stocks[player], index)
		Runtime.changed(player)
		return 100, nil
	end,
	onChanged = function(fn: (any) -> ())
		table.insert(changedListeners, fn)
	end,
	stands = function(player: any): number
		return Runtime.standCount[player] or Config.Warehouse.Stands
	end,
	boost = function(player: any): number
		return Runtime.boosts[player] or 1
	end,
	marketIncome = function(): number -- (8.3: no hot kinds here)
		return 1
	end,
}

-- 8.1: server/Upgrades.luau's open (the UPGRADES desk's prompt)
Runtime.Upgrades = {
	open = function(player: any)
		table.insert(Runtime.calls, { "openUpgrades", player })
	end,
}

-- A second later on os.clock (a player's prompts are a short moment apart at least).
function Runtime.later()
	E.clock += 1
end

-- The last Collection call of this name.
function Runtime.lastCall(name: string): any
	for index = #Runtime.calls, 1, -1 do
		if Runtime.calls[index][1] == name then
			return Runtime.calls[index]
		end
	end
	return nil
end

return Runtime
