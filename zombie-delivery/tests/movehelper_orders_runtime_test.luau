-- 8.6 Danny's bubble and the crew's orders (the owner: "Somewhere I'd like to see an indicator of what Danny is doing
-- right now, and to be able to tell him, for example, put it down on the ground, or get out of the car"): the real
-- server/Moving.luau and server/MoveHelper.luau on tests/runtime/MovingRuntime.luau's fakes (as
-- tests/movehelper_runtime_test.luau: his walk a straight step a tick, a carried piece moved with its carrier here).
--   * the bubble's words (the crew's MoveHelperBubble, MoveHelperAlert) always the same action's as the status line's
--     MoveHelperDoing (MoveHelperBrain.doing / bubble), for hire, waiting, going for a piece, carrying it, carrying with
--     you, at a two-person piece (orange), in the van, getting out, staying out; the orders that apply
--     (MoveHelperOrders) with them; all gone when the move ends
--   * PUT IT DOWN ("helper", "putdown"): a piece in his arms set down where he stands, its condition kept, off his
--     list ("Setting it down."); a two-person piece he holds with you: both ends down, your hands free, his hold off;
--     nothing in his hands: refused ("Danny isn't carrying anything."); not hired: refused
--   * GET OUT ("helper", "getout"): seated, out at once as a player gets out (8.5 boardOut: the door open, the slide
--     out, on his feet at his spot by the door), "Hopping out, boss."; while the owner stays at the wheel he does not
--     get back in (seconds later still out); the owner out of the seat and in again: in he gets; refused when he is not
--     in the van, and while the van rolls ("Stop the van first"); on his way to the van to ride: he stays out
--   * a player not of the crew: nothing; the rate limit (MoveHelperOrder, Config.Robust.Limits.MoveHelperOrder)
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local Map = require("./Map")
local Rules = require("./MovingRules")
local Brain = require("./MoveHelperBrain")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end

local T = Config.Moving
local H = Config.MoveHelper
local WALK = Config.Movement.Walk
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace

local home = Map.home(T.Contracts[1].home) :: any
local door = V3(home.door.x, 3, home.door.z)
local facing = V3(home.facing.x, 0, home.facing.z)
local outside = door + facing * 3
E.truckAt = V3(home.door.x + 30, 2, home.door.z - 20)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (the move's own roamers far off)
end
MoveHelper.useMover({
	move = function(body: any, to: any, speed: number, dt: number)
		local root = body.root
		local here = root.Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		local length = way.Magnitude
		if length > 1e-6 then
			local step = math.min(length, speed * dt)
			root.CFrame = M.CFrame.new(here.X + way.X / length * step, here.Y, here.Z + way.Z / length * step)
		end
		body.walking = true
	end,
	halt = function(body: any)
		body.walking = false
	end,
})

local sol = E.player(44, "Sol", V3(Map.Depot.x, 3, Map.Depot.z))
local rex = E.player(66, "Rex", V3(Map.Depot.x + 8, 3, Map.Depot.z)) -- (not of the crew)
Moving.useArt(E.art)
Moving.start()

local function promptIn(model: any, action: string): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and string.find(tostring(d.ActionText), action, 1, true) == 1 then
			return d
		end
	end
	return nil
end
local function itemModel(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
local function told(player: any, text: string, from: number): boolean
	for index = from + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) then
			return true
		end
	end
	return false
end
local danny: any = nil
-- What he carries alone stays in front of him; what Sol carries in front of her (the welds, in Roblox).
local function carryAlong()
	local h = danny
	if not h or not h.body then
		return
	end
	local spot, role = Rules.holding(h.s.move, h.id)
	local model = if spot and role == "carrier" then itemModel(spot) else nil
	if model then
		model.PrimaryPart.CFrame = h.body.root.CFrame * M.CFrame.new(0, 0, -1.5)
	end
	local own = Rules.holding(h.s.move, sol.UserId)
	local held = if own then itemModel(own) else nil
	if held then
		held.PrimaryPart.CFrame = E.rootOf(sol).CFrame * M.CFrame.new(0, 0, -3)
	end
end
-- Steps of 0.1 s (his loop's), the move's tick every other one, until `done` (true when it came) or `seconds` long.
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		MoveHelper.step(0.1)
		carryAlong()
		if index % 2 == 0 then
			Moving.step()
		end
		if done and done() then
			Moving.step()
			return true
		end
	end
	Moving.step()
	return done == nil
end
local function helped(): boolean
	return math.abs((sol.Character:GetAttribute("CarrySpeed") or 0) - WALK * T.Speed.Pair) < 1e-6
end
-- A click on a piece with the clipboard out (8.5 orders mode), from beside it.
local function give(model: any)
	local was = E.rootOf(sol).Position
	E.place(sol, model.PrimaryPart.Position + V3(3, 0, 0))
	sol.Character:SetAttribute("ClipboardHeld", true)
	E.request(sol, "helper", "assign", model)
	E.place(sol, was)
end
-- The bubble and the status line say the same action now (the server's attributes; MoveHelperBrain's words for one
-- action, the piece he is at): returns that action (nil: they disagree, or no words).
local function agreed(): string?
	local line, bubble = sol:GetAttribute("MoveHelperDoing"), sol:GetAttribute("MoveHelperBubble")
	if type(line) ~= "string" or type(bubble) ~= "string" then
		return nil
	end
	local name: string? = nil
	if danny.spot then
		local thing = danny.s.move.things[danny.spot]
		name = if thing then thing.name else nil
	end
	for action in Brain.Doing do
		for _, full in { false, true } do
			local text, alert = Brain.bubble(action, name, full, danny.price)
			if Brain.doing(action, name, full) == line and text == bubble and (sol:GetAttribute("MoveHelperAlert") == true) == alert then
				return action
			end
		end
	end
	return nil
end
local function stateNow(spot: number): string
	return danny.s.move.things[spot].state
end

-- The move; Danny for hire: his bubble says so, no orders ---------------------------------------------------------------------

local started = Moving.admin(sol, "start")
check("a solo move starts", string.find(started, "started", 1, true) ~= nil, started)
local truck = E.cars[sol]
truck.model:SetAttribute("BackOpen", true)
Moving.step()
danny = MoveHelper.find(sol)
check("Danny comes, for hire", danny ~= nil and danny.body ~= nil and danny.hirer == nil)
check("8.6 his bubble for the crew: \"🧑‍🔧 For hire · $100\" (the status line: for hire, $100), the same action as the status line's, no orders",
	sol:GetAttribute("MoveHelperBubble") == "🧑‍🔧 For hire · $100" and sol:GetAttribute("MoveHelperPrice") == 100 and agreed() == "offer"
	and sol:GetAttribute("MoveHelperOrders") == nil and sol:GetAttribute("MoveHelperAlert") == nil, sol:GetAttribute("MoveHelperBubble"))
check("8.6 …a player not of the crew gets none of it", rex:GetAttribute("MoveHelperBubble") == nil and rex:GetAttribute("MoveHelperOrders") == nil)
local noticeAt = #E.messages
E.request(sol, "helper", "putdown")
check("8.6 PUT IT DOWN before the hire: refused (\"Hire Danny first\")", told(sol, "Hire Danny first: then he takes your orders.", noticeAt), E.lastNotice(sol))
E.request(sol, "helper", "hire")
run(0.3)
check("hired: \"💤 Waiting by the van\", the status line's waiting", danny.hirer == sol and sol:GetAttribute("MoveHelperBubble") == "💤 Waiting by the van"
	and agreed() == "wait", sol:GetAttribute("MoveHelperBubble"))
noticeAt = #E.messages
E.request(sol, "helper", "putdown")
check("8.6 PUT IT DOWN with nothing in his hands: refused, \"Danny isn't carrying anything.\"", told(sol, "Danny isn't carrying anything.", noticeAt)
	and danny.hirer == sol, E.lastNotice(sol))
noticeAt = #E.messages
E.request(sol, "helper", "getout")
check("8.6 GET OUT, him not in the van: refused, \"Danny isn't in the van.\"", told(sol, "Danny isn't in the van.", noticeAt) and not danny.stayOut, E.lastNotice(sol))

-- PUT IT DOWN: a piece in his arms -------------------------------------------------------------------------------------------

local site = workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge")
local enter = promptIn(site, "Enter house")
E.place(sol, outside)
enter.Triggered:Fire(sol)
local lamp = itemModel(1)
give(lamp)
E.place(sol, outside + V3(6, 0, 0))
local going = run(10, function()
	return danny.action == "fetch"
end)
check("8.6 the Lamp given: \"🚶 Going for: Lamp\", the status line's going for it", going and sol:GetAttribute("MoveHelperBubble") == "🚶 Going for: Lamp" and agreed() == "fetch",
	sol:GetAttribute("MoveHelperBubble"))
check("8.6 …\"list: 1\" beside it on the client (his list's count, the server's MoveHelperQueue)", sol:GetAttribute("MoveHelperQueue") == 1 and Brain.listChip(1) == "list: 1")
local holds = run(30, function()
	return Rules.holding(danny.s.move, danny.id) == 1
end)
run(0.4)
check("8.6 in his arms: \"📦 Carrying: Lamp → van\", the orders: PUT IT DOWN", holds and sol:GetAttribute("MoveHelperBubble") == "📦 Carrying: Lamp → van"
	and agreed() == "deliver" and sol:GetAttribute("MoveHelperOrders") == "putdown", sol:GetAttribute("MoveHelperBubble"))
local condition = danny.s.move.things[1].condition
local standing = danny.body.root.Position
local said = #E.said
noticeAt = #E.messages
E.request(sol, "helper", "putdown")
run(0.6) -- (9.0 his setting down: the Lamp glides down to the floor first)
local onGround = stateNow(1) == "ground"
local lampAt = lamp.PrimaryPart.Position
check("8.6 PUT IT DOWN: the Lamp on the ground where he stands (a step in front of him), out of his hands, its condition kept",
	onGround and Rules.holding(danny.s.move, danny.id) == nil and V3(lampAt.X - standing.X, 0, lampAt.Z - standing.Z).Magnitude < 2.5
	and danny.s.move.things[1].condition == condition and danny.body.model:GetAttribute("Carrying") == nil,
	`{stateNow(1)} {V3(lampAt.X - standing.X, 0, lampAt.Z - standing.Z).Magnitude} {danny.s.move.things[1].condition}`)
check("8.6 …\"Setting it down.\", the crew told: off his list (your word beats the list)", E.saidSince(Brain.Lines.putDown, said)
	and told(sol, "Danny set the Lamp down here: off his list.", noticeAt) and #danny.queue == 0 and lamp:GetAttribute("DannyQueue") == nil, E.lastNotice(sol))
run(4)
check("8.6 …and it stays there: he never picks it up again by himself (nothing on his list: he waits), no orders now",
	stateNow(1) == "ground" and Rules.holding(danny.s.move, danny.id) == nil and danny.action == "wait" and sol:GetAttribute("MoveHelperOrders") == nil
	and agreed() == "wait")

-- PUT IT DOWN: a two-person piece he holds with you ------------------------------------------------------------------------

local sofa = itemModel(3)
E.place(sol, sofa.PrimaryPart.Position + V3(0, 0, 3))
promptIn(sofa, "Lift").Triggered:Fire(sol)
run(0.3)
check("8.6 Sol calls him to the Sofa: \"🏃 Coming to lift: Sofa\", the status line's", danny.call ~= nil and agreed() == "come"
	and sol:GetAttribute("MoveHelperBubble") == "🏃 Coming to lift: Sofa", sol:GetAttribute("MoveHelperBubble"))
local lifted = run(40, function()
	return helped()
end)
run(0.4)
check("8.6 up together: \"🤝 Carrying: Sofa with you\", the orders: PUT IT DOWN", lifted and select(2, Rules.holding(danny.s.move, danny.id)) == "helper"
	and sol:GetAttribute("MoveHelperBubble") == "🤝 Carrying: Sofa with you" and agreed() == "hold" and sol:GetAttribute("MoveHelperOrders") == "putdown",
	sol:GetAttribute("MoveHelperBubble"))
condition = danny.s.move.things[3].condition
said = #E.said
noticeAt = #E.messages
E.request(rex, "helper", "putdown")
check("8.6 a player not of the crew: PUT IT DOWN does nothing (no word either)", select(2, Rules.holding(danny.s.move, danny.id)) == "helper"
	and stateNow(3) == "carried" and not told(rex, "Danny", noticeAt))
E.request(sol, "helper", "putdown")
check("8.6 PUT IT DOWN with the Sofa between them: both ends down at once (on the ground, nobody holds it, Sol's hands free), its condition kept",
	stateNow(3) == "ground" and Rules.holding(danny.s.move, danny.id) == nil and Rules.holding(danny.s.move, sol.UserId) == nil
	and sol.Character:GetAttribute("MoveCarry") == nil and danny.s.move.things[3].condition == condition, stateNow(3))
check("8.6 …his hold off (on his feet), Sol's grip as before, \"Easy... setting it down.\", Sol told", danny.gripped == nil and danny.body.grip == nil
	and sol.Character:GetAttribute("GripSteady") == nil and E.saidSince(Brain.Lines.putTogether, said) and told(sol, "You and Danny set the Sofa down.", noticeAt),
	E.lastNotice(sol))
run(1)
check("8.6 …and it stays down", stateNow(3) == "ground" and Rules.holding(danny.s.move, danny.id) == nil)

-- The rate limit -------------------------------------------------------------------------------------------------------------

do
	local asked = false
	local realLimit = E.Net.limit
	E.Net.limit = function(player: any, name: string, rate: number): boolean
		asked = asked or (player == sol and name == "MoveHelperOrder" and rate == Config.Robust.Limits.MoveHelperOrder)
		return name ~= "MoveHelperOrder"
	end
	noticeAt = #E.messages
	E.request(sol, "helper", "putdown")
	E.request(sol, "helper", "getout")
	E.Net.limit = realLimit
	check("8.6 every order asks its rate limit (MoveHelperOrder, Config.Robust.Limits.MoveHelperOrder: 3 a second); over it: dropped (not even a refusal)",
		asked and Config.Robust.Limits.MoveHelperOrder == 3 and not told(sol, "Danny", noticeAt))
end

-- GET OUT -------------------------------------------------------------------------------------------------------------------

do
	local seat = truck.passengers[1]
	local function swingsSince(from: number): { any }
		local list = {}
		for index = from + 1, #E.doorSwings do
			local swing = E.doorSwings[index]
			if swing.car == truck and swing.door == 2 then
				table.insert(list, swing)
			end
		end
		return list
	end
	E.place(sol, truck.chassis.Position + V3(-5, 1, -3))
	E.seated[sol] = truck
	local riding = run(1, function()
		return danny.action == "ride"
	end)
	run(0.2)
	check("8.6 Sol at the wheel: \"🚐 Getting in the van\", GET OUT applies already (on his way)", riding and sol:GetAttribute("MoveHelperBubble") == "🚐 Getting in the van"
		and agreed() == "ride" and sol:GetAttribute("MoveHelperOrders") == "getout", sol:GetAttribute("MoveHelperBubble"))
	local sat = run(40, function()
		return danny.seat ~= nil
	end)
	run(0.4)
	check("8.6 seated: \"🪑 Riding\", the orders: GET OUT", sat and danny.seat == seat and sol:GetAttribute("MoveHelperBubble") == "🪑 Riding" and agreed() == "seat"
		and sol:GetAttribute("MoveHelperOrders") == "getout", sol:GetAttribute("MoveHelperBubble"))
	truck.speed = 20
	noticeAt = #E.messages
	E.request(sol, "helper", "getout")
	check("8.6 GET OUT while the van rolls (20 studs/s): refused, \"Stop the van first: then Danny can get out.\", he stays in", danny.seat == seat
		and danny.board == nil and told(sol, "Stop the van first: then Danny can get out.", noticeAt) and not danny.stayOut, E.lastNotice(sol))
	truck.speed = 0
	local swingsAt = #E.doorSwings
	said = #E.said
	noticeAt = #E.messages
	E.request(sol, "helper", "getout")
	local b = danny.board
	local open = swingsSince(swingsAt)[1]
	check("8.6 GET OUT, the van standing: out of the seat now as a player gets out (8.5: the seat free, the door open now, the slide out), \"Hopping out, boss.\"",
		b ~= nil and b.out and danny.seat == nil and seat.Occupant == nil and open ~= nil and open.openAt == open.now and E.saidSince(Brain.Lines.getOut, said)
		and told(sol, "Danny gets out and stays out of the van until the driver leaves the wheel.", noticeAt), E.lastNotice(sol))
	run(0.3)
	check("8.6 …\"🚪 Getting out of the van\" meanwhile, GET OUT no more (he is on his way out)", sol:GetAttribute("MoveHelperBubble") == "🚪 Getting out of the van"
		and agreed() == "alight" and sol:GetAttribute("MoveHelperOrders") == nil, sol:GetAttribute("MoveHelperBubble"))
	noticeAt = #E.messages
	E.request(sol, "helper", "getout")
	check("8.6 …GET OUT again then: \"Danny is getting out already.\"", told(sol, "Danny is getting out already.", noticeAt), E.lastNotice(sol))
	local out = run(2, function()
		return danny.board == nil
	end)
	local stayed = true
	run(8, function()
		stayed = stayed and danny.seat == nil and danny.board == nil and danny.action ~= "ride"
		return false
	end)
	check("8.6 …on his feet by the van, and while Sol stays at the wheel he does not get back in (8 s later still out: no ride)", out and stayed
		and danny.seat == nil and seat.Occupant == nil and danny.stayOut)
	check("8.6 …his bubble: \"✋ Staying out of the van\" (the status line: staying out, your order), no orders", sol:GetAttribute("MoveHelperBubble") == "✋ Staying out of the van"
		and agreed() == "stay" and sol:GetAttribute("MoveHelperDoing") == "Staying out of the van (your order)" and sol:GetAttribute("MoveHelperOrders") == nil,
		sol:GetAttribute("MoveHelperBubble"))
	E.seated[sol] = nil
	run(0.4)
	check("8.6 Sol leaves the wheel: the order is over (he waits by the van as ever)", not danny.stayOut and agreed() == "wait")
	E.seated[sol] = truck
	sat = run(40, function()
		return danny.seat ~= nil
	end)
	check("8.6 …Sol at the wheel again: in he gets (as a player gets in)", sat and danny.seat == seat)
	-- on his way to the van to ride: GET OUT keeps him out
	E.seated[sol] = nil
	run(2, function()
		return danny.seat == nil and danny.board == nil
	end)
	danny.body.root.CFrame = M.CFrame.new(truck.chassis.Position + V3(30, 0, 30)) -- (a way off: he walks to the van)
	E.seated[sol] = truck
	run(0.3)
	said = #E.said
	noticeAt = #E.messages
	local walking = danny.action == "ride" and danny.board == nil and danny.seat == nil
	E.request(sol, "helper", "getout")
	check("8.6 GET OUT while he walks to the van to ride: he stays out (\"Okay, I'll stay out.\")", walking and danny.stayOut and E.saidSince(Brain.Lines.stayOut, said)
		and told(sol, "Danny stays out of the van until the driver leaves the wheel.", noticeAt), E.lastNotice(sol))
	stayed = true
	run(6, function()
		stayed = stayed and danny.seat == nil and danny.board == nil and danny.action ~= "ride"
		return false
	end)
	check("8.6 …never in while Sol stays at the wheel", stayed)
	E.seated[sol] = nil
	run(0.3)
end

-- The two-person piece of his list: he needs you (orange) ------------------------------------------------------------------

do
	local slab = itemModel(6)
	E.place(sol, outside)
	enter.Triggered:Fire(sol)
	give(slab)
	E.place(sol, outside + V3(6, 0, 0))
	local waits = run(60, function()
		return danny.needs == 6 and danny.needsAt > 0
	end)
	run(0.3)
	check("8.6 the Marble slab on his list: \"⏳ Needs you: Marble slab\" in the movers' orange (MoveHelperAlert), the status line's",
		waits and sol:GetAttribute("MoveHelperBubble") == "⏳ Needs you: Marble slab" and sol:GetAttribute("MoveHelperAlert") == true
		and agreed() == "needs", sol:GetAttribute("MoveHelperBubble"))
	noticeAt = #E.messages
	E.request(sol, "helper", "putdown")
	check("8.6 …PUT IT DOWN then: nothing in his hands (refused)", told(sol, "Danny isn't carrying anything.", noticeAt) and danny.needs == 6)
	local body = danny.body
	body.humanoid.Health = 0
	body.humanoid.HealthChanged:Fire(0)
	run(0.3)
	check("8.6 down: \"🤕 Down: back at the van soon\", orange, the status line's", danny.dead and sol:GetAttribute("MoveHelperBubble") == "🤕 Down: back at the van soon"
		and sol:GetAttribute("MoveHelperAlert") == true and agreed() == "down", sol:GetAttribute("MoveHelperBubble"))
	noticeAt = #E.messages
	E.request(sol, "helper", "getout")
	run(4) -- (his body gone meanwhile)
	E.request(sol, "helper", "putdown")
	local downTold = 0
	for index = noticeAt + 1, #E.messages do
		local m = E.messages[index]
		if m.player == sol and m.remote == "Notice" and m.kind == "Danny is down: he is back at the van soon." then
			downTold += 1
		end
	end
	check("8.6 …an order while he is down (lying there, or his body gone): refused, \"Danny is down: he is back at the van soon.\"", downTold == 2
		and danny.body == nil, downTold)
end

-- The end ------------------------------------------------------------------------------------------------------------------

Moving.admin(sol, "end")
run(0.2)
check("8.6 the move ends: the bubble's words and the orders go with the rest", MoveHelper.find(sol) == nil and sol:GetAttribute("MoveHelperBubble") == nil
	and sol:GetAttribute("MoveHelperAlert") == nil and sol:GetAttribute("MoveHelperOrders") == nil and sol:GetAttribute("MoveHelperDoing") == nil)
E.leave(sol)
E.leave(rex)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
