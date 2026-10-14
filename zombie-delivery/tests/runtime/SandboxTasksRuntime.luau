--!strict
-- 8.2 SANDBOX: the two stand-ins the real server/SandboxTasks.luau needs beside tests/runtime/CollectionRuntime.luau's
-- services (tests/sandboxtasks_runtime_test.luau through tests/run_tests.py, which builds SandboxTasksServer.luau with
-- these in place of server/Moving.luau and server/MoveHelper.luau; PlayerData, Collection and Upgrades are the real
-- ones):
--   * Moving: onStored / onResult keep the fns the way the real one does (its SB.listeners); Runtime.trip and
--     Runtime.finish call them the way SB.store and SB.result do (task.spawn each), then the deferred work runs;
--   * MoveHelper: find(player) gives Runtime.helpers[player], Danny's state on the player's move ({ s = { move }, id }:
--     what the real find returns, read with the real shared/MovingRules.luau holding).
local E = require("./CollectionRuntime")

local Runtime: any = {
	listeners = { trip = {}, finish = {} },
	helpers = {}, -- player → Danny's state
}

Runtime.Moving = {
	onStored = function(fn: any)
		table.insert(Runtime.listeners.trip, fn)
	end,
	onResult = function(fn: any)
		table.insert(Runtime.listeners.finish, fn)
	end,
}

Runtime.MoveHelper = {
	find = function(player: any): any
		return Runtime.helpers[player]
	end,
}

-- A trip home of `owner`'s move (SB.store's call).
function Runtime.trip(owner: any, move: any, spots: { number })
	for _, fn in Runtime.listeners.trip do
		E.task.spawn(fn, owner, move, spots)
	end
	E.flush()
end

-- A move's end (SB.result's call).
function Runtime.finish(owner: any, move: any, result: any, crew: { any })
	for _, fn in Runtime.listeners.finish do
		E.task.spawn(fn, owner, move, result, crew)
	end
	E.flush()
end

return Runtime
