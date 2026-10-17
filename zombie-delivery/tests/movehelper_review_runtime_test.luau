-- 8.3 review (Danny and the moves): the real server/Moving.luau and server/MoveHelper.luau on tests/runtime/
-- MovingRuntime.luau's fakes (as tests/movehelper_runtime_test.luau), the crew Studio's Local Server test players: Player1
-- (UserId -1, the move's owner) and Player2 (-2, a crew mate).
--   * negative ids are players: a click on a piece gives it to Danny (no "Get closer"); a two-person Lift calls him and
--     he walks over (never stands still for want of the caller's root), up together
--   * a crew mate's Lift on the piece the owner waits at with Danny ("Stop waiting" on its prompt for the whole crew):
--     refused, told who waits, nothing lifted, the owner's call still on
--   * the lift check Danny's arrival opens, never answered: closed without a knock ("waits at the other end"), the call
--     still ready; the next Lift opens a new check, and that one, a press's, unanswered is a miss as ever (a knock)
--   (10.5: nobody drives the van in a run, so he never rides in it: no seats of his)
--   * the move's end with the crew inside: the interior goes only after the trip out (FadeOut + Margin + Stream + 0.5 s
--     at least: the floor never vanishes under somebody still in the dark)
-- (Each fix taken back on its own, its checks here fail.)
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local Rules = require("./MovingRules")

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

local HOUSE = "lone_house" -- (10.5: a run on the lone house, the van at its curb)
local door, facing, outside = E.doorOf(SandboxMap.house(HOUSE))
local lobby = V3(SandboxMap.Lobby.spawn.x, 3, SandboxMap.Lobby.spawn.z)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0)
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

local one = E.player(-1, "Player1", lobby) -- (Studio's Local Server test players)
local two = E.player(-2, "Player2", lobby + V3(4, 0, 0))
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
local function grips(player: any, from: number, a: string): { any }
	local list = {}
	for index = from + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Moving" and m.kind == "grip" and m.a == a then
			table.insert(list, m.b)
		end
	end
	return list
end
local danny: any = nil
-- Steps of 0.1 s (his loop's), the move's tick every other one, until `done` (true when it came) or `seconds` long.
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		MoveHelper.step(0.1)
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
local function helped(player: any): boolean
	return math.abs((player.Character:GetAttribute("CarrySpeed") or 0) - WALK * T.Speed.Pair) < 1e-6
end
-- The move, Danny with Player1 (10.1 free) --------------------------------------------------------------------------------------------------------

local started = E.startRun(one, HOUSE)
check("a run starts for Player1 (UserId -1)", started == nil, started)
local truck = E.cars[one]
truck.model:SetAttribute("BackOpen", true)
Moving.step()
danny = MoveHelper.find(one)
check("Danny comes, Player1's from the start (10.1 free)", danny ~= nil and danny.hirer == one and danny.body ~= nil)
local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{HOUSE}`)
local enter = promptIn(site, "Enter house")
E.place(one, outside)
enter.Triggered:Fire(one)
local origin = E.interiors[#E.interiors]
check("Player1 is inside", (E.rootOf(one).Position - origin.Position).Magnitude < 10)

-- 4. negative ids are players ---------------------------------------------------------------------------------------------------

local lamp, sofa = itemModel(1), itemModel(3)
local noticeAt = #E.messages
E.place(one, lamp.PrimaryPart.Position + V3(3, 0, 0))
one.Character:SetAttribute("ClipboardHeld", true) -- (8.5 orders mode: the clipboard out, server/Clipboard.luau's)
E.request(one, "helper", "assign", lamp)
check("4. Player1 (-1) clicks the Lamp beside it: on Danny's list (never \"Get closer\")", #danny.queue == 1 and danny.queue[1] == 1
	and told(one, "Danny will take the Lamp.", noticeAt) and not told(one, "Get closer", noticeAt), E.lastNotice(one))
E.request(one, "helper", "assign", lamp)
check("…a click again takes it back", #danny.queue == 0)
E.place(one, sofa.PrimaryPart.Position + V3(0, 0, 3))
local from = danny.body.root.Position
promptIn(sofa, "Lift").Triggered:Fire(one)
check("4. Player1's Lift on the Sofa calls him", danny.call ~= nil and danny.call.player == one and one:GetAttribute("MoveHelperCall") == "Sofa")
local lifted = run(30, function()
	return helped(one)
end)
check("…he walks over (the caller's root found by their body, not a positive id) and it is up together", lifted
	and (danny.body.root.Position - from).Magnitude > 20 and select(2, Rules.holding(danny.s.move, danny.id)) == "helper", danny.action)
E.Net.get("PutDown").OnServerEvent:Fire(one)
run(0.3)
check("…set down", Rules.holding(danny.s.move, danny.id) == nil and danny.s.move.things[3].state == "ground")

-- 5. a crew mate's Lift on the piece somebody waits at -------------------------------------------------------------------------

E.crew[one] = { two }
Moving.step()
check("Player2 (-2) of the crew", two:GetAttribute("MoveHelper") == "hired" and MoveHelper.find(two) == danny)
danny.body.root.CFrame = E.cars[one].chassis.CFrame * M.CFrame.new(40, 1, 40) -- (far off: the call stays waiting)
E.place(one, sofa.PrimaryPart.Position + V3(0, 0, 3))
E.place(two, sofa.PrimaryPart.Position + V3(0, 0, -3))
promptIn(sofa, "Lift").Triggered:Fire(one)
local waiting = promptIn(sofa, "Stop waiting")
check("Player1 waits for Danny at the Sofa (its prompt: Stop waiting, for the whole crew)", danny.call ~= nil and danny.call.player == one and waiting ~= nil)
noticeAt = #E.messages
waiting.Triggered:Fire(two)
check("5. Player2 presses it: refused, told who waits (\"Player1 is waiting for Danny with the Sofa.\")",
	told(two, "Player1 is waiting for Danny with the Sofa.", noticeAt), E.lastNotice(two))
check("…nothing lifted (never dragged alone from under the call), Player1's call still on", two.Character:GetAttribute("MoveCarry") == nil
	and danny.s.move.things[3].state == "ground" and danny.call ~= nil and danny.call.player == one and one:GetAttribute("MoveHelperCall") == "Sofa"
	and not told(one, "stopped waiting", noticeAt))
waiting.Triggered:Fire(one)
check("…Player1's own press still stops it", danny.call == nil)
E.place(two, outside + V3(6, 0, 0))

-- 6. the lift check his arrival opens -------------------------------------------------------------------------------------------

Config.CarryGrip.On, Config.MoveHelper.CallCheck = true, true -- (8.6: the lift check after his arrival is CallCheck's; the game lifts at once)
local gripFrom = #E.messages
noticeAt = #E.messages
local condition = danny.s.move.things[3].condition
promptIn(sofa, "Lift").Triggered:Fire(one)
local ready = run(40, function()
	return danny.call ~= nil and danny.call.ready
end)
local opened = grips(one, gripFrom, "open")
local first = opened[1]
check("Player1 calls him again: he comes, \"On three... lift!\", her lift check opens on his arrival", ready and #opened == 1 and first.what == "lift")
E.now += first.window + Config.CarryGrip.Server.Grace + 0.2
run(0.4)
local knocked = false
for _, result in grips(one, gripFrom, "result") do
	knocked = knocked or result.id == first.id
end
local closed = table.find(grips(one, gripFrom, "close"), first.id) ~= nil
check("6. never answered: closed without an outcome (no knock, no \"slipped back\"), the Sofa as it was", closed and not knocked
	and danny.s.move.things[3].condition == condition and danny.s.move.things[3].state == "ground" and not told(one, "slipped back", noticeAt))
check("…told he waits, the call still ready (he stays at its far end)", told(one, "Danny waits at the other end of the Sofa: lift it when you're ready.", noticeAt)
	and danny.call ~= nil and danny.call.ready and one:GetAttribute("MoveHelperReady") == true)
gripFrom = #E.messages
promptIn(sofa, "Lift").Triggered:Fire(one)
opened = grips(one, gripFrom, "open")
local second = opened[1]
check("…the next Lift opens a new check at once", second ~= nil and second.id ~= first.id and danny.call ~= nil and danny.call.ready)
E.now += second.window + Config.CarryGrip.Server.Grace + 0.2
run(0.4)
local outcome: string? = nil
for _, result in grips(one, gripFrom, "result") do
	if result.id == second.id then
		outcome = result.outcome
	end
end
check("…that one, opened by her press, unanswered is a miss as ever (its knock)", outcome == "knock" and danny.s.move.things[3].condition < condition, outcome)
Config.CarryGrip.On, Config.MoveHelper.CallCheck = false, false
E.Net.get("PutDown").OnServerEvent:Fire(one)
check("(the call off)", danny.call == nil)

-- 2. the move ends with the crew inside -----------------------------------------------------------------------------------------

-- (task.delay deferred here, as in Roblox: the callbacks run afterwards in their time's order; the runtime's own runs
-- them at once, a trip over before anything else is decided)
local runAtOnce = E.task.delay
-- `finish` ends the move; returns the delay the interior went after and whether Player1 was out of it by then.
local function ending(finish: () -> ()): (number?, boolean)
	local queue: { any } = {}
	local at = 0
	E.task.delay = function(seconds: any, callback: any, ...: any)
		local wait = tonumber(seconds) or 0
		table.insert(queue, { at = at + wait, seconds = wait, fn = callback, args = table.pack(...) })
	end
	finish()
	local tore: number? = nil
	local outFirst = false
	local ran = 0
	while #queue > 0 and ran < 500 do
		local index = 1
		for i, q in queue do
			if q.at < queue[index].at then
				index = i
			end
		end
		local q = table.remove(queue, index)
		at, ran = q.at, ran + 1
		local before = E.destroyed
		local out = (E.rootOf(one).Position - origin.Position).Magnitude > 1000
		q.fn(table.unpack(q.args, 1, q.args.n))
		if E.destroyed > before then
			tore, outFirst = q.seconds, out
		end
	end
	E.task.delay = runAtOnce
	return tore, outFirst
end
E.place(one, outside)
enter.Triggered:Fire(one)
check("Player1 inside again", (E.rootOf(one).Position - origin.Position).Magnitude < 10)
local D = T.Doors
local tore, outFirst = ending(function()
	Moving.endRun(one)
end)
check("2. the move ends with Player1 inside: out at the house's door, the fade lifted", (E.rootOf(one).Position - origin.Position).Magnitude > 1000
	and E.last(one, "Moving", "fade") ~= nil and E.last(one, "Moving", "fade").a == "in" and E.destroyed == E.built)
check("…the interior went FadeOut + Margin + Stream + 0.5 s after (the trip out over first: never under them)", tore ~= nil
	and tore >= D.FadeOut + D.Margin + D.Stream + 0.5 - 1e-9 and outFirst, tore)
run(0.2)
check("Danny goes with the move", MoveHelper.find(one) == nil)
E.startRun(one, HOUSE)
Moving.step()
origin = E.interiors[#E.interiors]
E.place(one, outside + V3(4, 0, 0))
tore = ending(function()
	Moving.endRun(one)
end)
check("…a move ending with nobody inside: its interior goes T.Fade + 0.5 s after, as ever (nothing waits)", tore ~= nil
	and math.abs(tore - (T.Fade + 0.5)) < 1e-9 and E.destroyed == E.built, tore)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
