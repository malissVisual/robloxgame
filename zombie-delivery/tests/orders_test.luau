-- Logic test of 5.2: several orders at once (shared/JobRules.luau's orders, Config.Jobs.Orders): which offers stack,
-- how many orders may be open, the free room, the board's button, which stops are open and the stop the GPS shows.
-- Standalone Luau CLI. Run: python3 tests/run_tests.py [path to the luau binary]

local Config = require("./Config")
local JobRules = require("./JobRules")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local Orders = Config.Jobs.Orders

-- The numbers ----------------------------------------------------------------------------------

check("Orders.Max: foot 2, bike 3, car 4", Orders.Max.foot == 2 and Orders.Max.bike == 3 and Orders.Max.car == 4)
check("the ★ and ★★ car tiers stack", Orders.CarTiers == 2)
check("AtStop, Hysteresis, SwitchEvery, AddOnTime are positive", Orders.AtStop > 0 and Orders.Hysteresis > 0 and Orders.SwitchEvery > 0 and Orders.AddOnTime > 0)
check("ordersMax by mode", JobRules.ordersMax("foot") == 2 and JobRules.ordersMax("bike") == 3 and JobRules.ordersMax("car") == 4)
check("ordersMax of an unknown mode is 1", JobRules.ordersMax("boat") == 1)

-- Which offers stack ---------------------------------------------------------------------------

local function info(mode: string, tier: number, fields: { [string]: boolean }?): JobRules.StackInfo
	local f = fields or {}
	return {
		mode = mode,
		tier = tier,
		special = f.special == true,
		mission = f.mission == true,
		tutorial = f.tutorial == true,
		duo = f.duo == true,
		carried = f.carried ~= false,
	}
end

check("a foot run stacks", JobRules.stackable(info("foot", 1)))
check("a bike run stacks", JobRules.stackable(info("bike", 1)))
check("a ★ car delivery stacks", JobRules.stackable(info("car", 1)))
check("a ★★ car delivery stacks", JobRules.stackable(info("car", 2)))
check("a ★★★ car delivery does not", not JobRules.stackable(info("car", 3)))
check("a ★★★★ car delivery does not", not JobRules.stackable(info("car", 4)))
check("a special does not", not JobRules.stackable(info("car", 1, { special = true })))
check("a mission does not", not JobRules.stackable(info("car", 1, { mission = true })))
check("the tutorial's run does not", not JobRules.stackable(info("foot", 1, { tutorial = true })))
check("a DUO job does not", not JobRules.stackable(info("car", 2, { duo = true })))
check("horses, people or pallets do not", not JobRules.stackable(info("car", 1, { carried = false })))

-- The free room --------------------------------------------------------------------------------

check("nothing open: all the room", JobRules.orderRoom(4, {}) == 4)
check("open orders take their pieces", JobRules.orderRoom(6, { 2, 1 }) == 3)
check("never below zero", JobRules.orderRoom(3, { 2, 2 }) == 0)
check("negative outstanding counts as none", JobRules.orderRoom(3, { -1 }) == 3)

local ok, why = JobRules.canAddOrder("car", 1, 2, 3)
check("a fitting order is added", ok and why == nil)
ok, why = JobRules.canAddOrder("car", 1, 4, 3)
check("too many pieces: room", not ok and why == "room")
ok, why = JobRules.canAddOrder("foot", 2, 1, 5)
check("foot: two open is full", not ok and why == "full")
ok, why = JobRules.canAddOrder("bike", 2, 1, 5)
check("bike: a third one fits", ok)
ok, why = JobRules.canAddOrder("bike", 3, 1, 5)
check("bike: a fourth one does not", not ok and why == "full")
ok = JobRules.canAddOrder("car", 3, 2, 2)
check("car: the fourth order with exactly the room left", ok)

check("the board's NO ROOM button", JobRules.orderButton("room", 3, 4, 1, 4) == "NO ROOM (3/4 slots)")
check("the board's ORDERS FULL button", JobRules.orderButton("full", 2, 5, 2, 2) == "ORDERS FULL (2/2)")

-- Which stops are open -------------------------------------------------------------------------

-- Two orders: order 1 picked up at A (done), drops at B and C; order 2 picks up at D, drops at E.
local stops: { JobRules.StopState } = {
	{ kind = "pickup", order = 1, done = true, x = 0, z = 0 }, -- 1 A
	{ kind = "drop", order = 1, done = false, x = 500, z = 0 }, -- 2 B
	{ kind = "drop", order = 1, done = false, x = 900, z = 0 }, -- 3 C
	{ kind = "pickup", order = 2, done = false, x = 100, z = 100 }, -- 4 D
	{ kind = "drop", order = 2, done = false, x = 120, z = 600 }, -- 5 E
}
local withYou = { [2] = 1, [3] = 2 }

check("a done stop is done", JobRules.stopOpen(stops, 1, withYou) == "done")
check("a drop with its pieces with you is open", JobRules.stopOpen(stops, 2, withYou) == "open")
check("an undone pick-up is open", JobRules.stopOpen(stops, 4, withYou) == "open")
check("a drop of an order not picked up yet waits", JobRules.stopOpen(stops, 5, withYou) == "wait")
check("a drop whose pieces are all gone is empty", JobRules.stopOpen(stops, 2, { [3] = 2 }) == "empty")
check("an index out of range is done", JobRules.stopOpen(stops, 9, withYou) == "done")

-- The stop the GPS shows -----------------------------------------------------------------------

check("the nearest open stop", JobRules.nextOpenStop(stops, withYou, { x = 0, z = 0 }) == 4)
check("never a waiting drop", JobRules.nextOpenStop(stops, withYou, { x = 120, z = 590 }) ~= 5)
check("at a circle: that stop, pinned or not", JobRules.nextOpenStop(stops, withYou, { x = 495, z = 5 }, 2) == 2)
check("the pinned order's stop first", JobRules.nextOpenStop(stops, withYou, { x = 400, z = 0 }, 2) == 4)
check("pinned order 1: its nearest drop", JobRules.nextOpenStop(stops, withYou, { x = 0, z = 0 }, 1) == 2)
check("a pinned order with nothing open: the nearest", JobRules.nextOpenStop(stops, { [3] = 2 }, { x = 150, z = 600 }, 7) == 4)
-- The current stop stays unless another is Hysteresis nearer.
local mid = { x = 300 + Orders.Hysteresis / 4, z = 0 } -- a little nearer to B (500) than D's (100, 100) distance allows
check("the current stop stays when another is only a little nearer", JobRules.nextOpenStop(stops, withYou, { x = 310, z = 50 }, nil, 4) == 4)
check("(without a current one there it is the nearer drop)", JobRules.nextOpenStop(stops, withYou, { x = 310, z = 50 }) == 2)
check("the current stop gives way when another is much nearer", JobRules.nextOpenStop(stops, withYou, { x = 520, z = 0 }, nil, 4) == 2)
check("a current stop that is not open is not kept", JobRules.nextOpenStop(stops, withYou, mid, nil, 5) ~= 5)
check("nothing open: nil", JobRules.nextOpenStop({ { kind = "drop", order = 1, done = true, x = 0, z = 0 } }, {}, { x = 0, z = 0 }) == nil)
-- A single ordinary job (one pick-up, one drop) goes in order.
local single: { JobRules.StopState } = {
	{ kind = "pickup", order = 1, done = false, x = 0, z = 0 },
	{ kind = "drop", order = 1, done = false, x = 10, z = 0 },
}
check("a single job: the pick-up first, even standing at the drop", JobRules.nextOpenStop(single, {}, { x = 10, z = 0 }) == 1)
single[1].done = true
check("then the drop", JobRules.nextOpenStop(single, { [2] = 2 }, { x = 0, z = 0 }) == 2)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
