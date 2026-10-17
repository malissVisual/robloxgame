-- 8.6 Danny's bubble and the crew's orders (the owner: "Somewhere I'd like to see an indicator of what Danny is doing
-- right now, and to be able to tell him, for example, put it down on the ground, or get out of the car"): the real
-- server/Moving.luau and server/MoveHelper.luau on tests/runtime/MovingRuntime.luau's fakes (as
-- tests/movehelper_runtime_test.luau: his walk a straight step a tick, a carried piece moved with its carrier here).
--   * the bubble's words (the crew's MoveHelperBubble, MoveHelperAlert) always the same action's as the status line's
--     MoveHelperDoing (MoveHelperBrain.doing / bubble), waiting (10.1: free, never "for hire"), going for a piece, carrying it, carrying with
--     you, at a two-person piece (orange), down in a run (orange); the orders that apply (MoveHelperOrders) with them;
--     all gone when the move ends
--   * PUT IT DOWN ("helper", "putdown"): a piece in his arms set down where he stands, its condition kept, off his
--     list ("Setting it down."); a two-person piece he holds with you: both ends down, your hands free, his hold off;
--     nothing in his hands: refused ("Danny isn't carrying anything.")
--   (10.6: nobody drives the van in a run, so he never rides in it: no GET OUT)
--   * a player not of the crew: nothing; the rate limit (MoveHelperOrder, Config.Robust.Limits.MoveHelperOrder)
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
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

local HOUSE = "lone_house" -- (10.6: a run on the lone house, the van at its curb)
local door, facing, outside = E.doorOf(SandboxMap.house(HOUSE))
local lobby = V3(SandboxMap.Lobby.spawn.x, 3, SandboxMap.Lobby.spawn.z)
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

local sol = E.player(44, "Sol", lobby)
local rex = E.player(66, "Rex", lobby + V3(8, 0, 0)) -- (not of the crew)
Moving.useArt(E.art)
Moving.parkVan = E.parkVan
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
			local text, alert = Brain.bubble(action, name, full)
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

-- The move; Danny with you from the start (10.1: free): his bubble says he waits, no orders ---------------------------------

local started = E.startRun(sol, HOUSE)
check("a solo run starts", started == nil, started)
local truck = E.cars[sol]
truck.model:SetAttribute("BackOpen", true)
Moving.step()
danny = MoveHelper.find(sol)
check("10.1 Danny comes, free: Sol's from the start", danny ~= nil and danny.body ~= nil and danny.hirer == sol)
check("8.6 his bubble for the crew: \"💤 Waiting by the van\" (10.1 no price), the same action as the status line's, no orders",
	sol:GetAttribute("MoveHelperBubble") == "💤 Waiting by the van" and sol:GetAttribute("MoveHelperPrice") == nil and agreed() == "wait"
	and sol:GetAttribute("MoveHelperOrders") == nil and sol:GetAttribute("MoveHelperAlert") == nil, sol:GetAttribute("MoveHelperBubble"))
check("8.6 …a player not of the crew gets none of it", rex:GetAttribute("MoveHelperBubble") == nil and rex:GetAttribute("MoveHelperOrders") == nil)
run(0.3)
local noticeAt = #E.messages
E.request(sol, "helper", "putdown")
check("8.6 PUT IT DOWN with nothing in his hands: refused, \"Danny isn't carrying anything.\"", told(sol, "Danny isn't carrying anything.", noticeAt)
	and danny.hirer == sol, E.lastNotice(sol))

-- PUT IT DOWN: a piece in his arms -------------------------------------------------------------------------------------------

local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{HOUSE}`)
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
	and told(sol, "Danny set the Lamp down here: off the list.", noticeAt) and #danny.queue == 0 and lamp:GetAttribute("DannyQueue") == nil, E.lastNotice(sol))
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
	E.Net.limit = realLimit
	check("8.6 every order asks its rate limit (MoveHelperOrder, Config.Robust.Limits.MoveHelperOrder: 3 a second); over it: dropped (not even a refusal)",
		asked and Config.Robust.Limits.MoveHelperOrder == 3 and not told(sol, "Danny", noticeAt))
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
	check("8.6 down in the run: \"🆘 Down! Hold E to revive\", orange, the status line's", danny.dead and sol:GetAttribute("MoveHelperBubble") == "🆘 Down! Hold E to revive"
		and sol:GetAttribute("MoveHelperAlert") == true and agreed() == "revive", sol:GetAttribute("MoveHelperBubble"))
	noticeAt = #E.messages
	E.request(sol, "helper", "putdown")
	run(4)
	E.request(sol, "helper", "putdown")
	local downTold = 0
	for index = noticeAt + 1, #E.messages do
		local m = E.messages[index]
		if m.player == sol and m.remote == "Notice" and m.kind == "Danny is down: get them up, or wait a moment." then
			downTold += 1
		end
	end
	check("8.6 …an order while he is down (lying there): refused, \"Danny is down: get them up, or wait a moment.\"", downTold == 2, downTold)
end

-- The end ------------------------------------------------------------------------------------------------------------------

Moving.endRun(sol)
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
