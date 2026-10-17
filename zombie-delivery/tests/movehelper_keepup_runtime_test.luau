-- 8.3 keeping up (the owner, carrying a Grandfather Clock with Danny out on the road: "It still doesn't work, though
-- it's better. When I RUN, he then just goes behind me with his arms stretched out"): the real server/Moving.luau,
-- server/MoveHelper.luau and server/PairHold.luau on tests/runtime/MovingRuntime.luau's fakes, Config.MoveHelper.HoldLead
-- as the game has it (the runtime's default: off). Danny's hold is played as Roblox's constraints do it: each of his
-- steps his root goes toward where his hold aims it at the hold's top speed × dt at most (AlignPosition.MaxVelocity;
-- this mover has no `keep`, so server/MoveHelper.luau's keepAt steps him). Danny is Sol's from the start (10.1 free), she lifts the
-- sofa, he walks over to its far end.
--   * the 8.2 hold (his top speed from the carry's walk alone, MoveHelperBrain.holdSpeed(walk)): Sol faster than that
--     (a sprint: what nothing on her client stops if anything raises her walk) leaves him further behind every step:
--     the owner's report
--   * now: Sol at the pair's walk, 20% faster (a lag spike, a slope), at a sprint: his top speed follows her real speed
--     (MoveHelperBrain.holdPace / holdSpeed, HoldCap at most): every step he is where his hold aims him; a lag spike
--     (her root 6 studs on at once): he catches up within a few tenths, never put there (each step within his top
--     speed × dt); she stops: he is back at his end
--   * the lead: walking, he is aimed her velocity × leadTime ahead of his place (her screen shows his body that late);
--     standing, none
--   * his legs step at his real speed (MoveHelperBrain.holdLegs, Npcs.stride): a jog's steps when he jogs
--   * the server's side of the walk cap: Sol (the leader) carries CarryPair while Danny holds the far end, and it is
--     gone with the piece (client/PairSteer.luau holds her walk at CarrySpeed meanwhile: tests/pairsteer_test.luau)
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
local PAIR = WALK * T.Speed.Pair
local SPRINT = Config.Movement.Sprint
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace
H.HoldLead.Base, H.HoldLead.Ping = E.gameLead.Base, E.gameLead.Ping -- (the game's lead)
-- 9.2: the hold the SERVER keeps (Danny's when no leader's client drives him: a drive it took back, PairLead.On false;
-- a crew mate's always): Sol's client drives none here (tests/movehelper_backwards_runtime_test.luau drives him)
H.PairLead.On = false
T.Doors.Walk = false -- (the walk-in doors off: these walks stay in the living room)

local HOUSE = "lone_house" -- (10.6: a run on the lone house, the van at its curb)
local door, facing, outside = E.doorOf(SandboxMap.house(HOUSE))
local lobby = V3(SandboxMap.Lobby.spawn.x, 3, SandboxMap.Lobby.spawn.z)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0)
end

-- His own walk (to her call): straight toward the point, speed × dt a step. Holding the far end the mover has no
-- `keep`: MoveHelper's keepAt steps his root toward his hold's aim at its top speed × dt at most (the constraints).
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
Moving.useArt(E.art)
Moving.parkVan = E.parkVan
Moving.start()

local function promptIn(model: any, action: string?): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and (action == nil or d.ActionText == action or string.find(tostring(d.ActionText), action, 1, true) == 1) then
			return d
		end
	end
	return nil
end
local function trigger(prompt: any, player: any)
	prompt.Triggered:Fire(player)
end
local function itemModel(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
local function distance(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function helped(): boolean
	return math.abs((sol.Character:GetAttribute("CarrySpeed") or 0) - PAIR) < 1e-6
end
local danny: any = nil
local function holding(): boolean
	local _, role = Rules.holding(danny.s.move, danny.id)
	return role == "helper"
end

-- While he holds the far end: the most his root moved in a step over his top speed × dt (never put there), his
-- fastest top speed.
local record = { over = 0, fastest = 0, steps = 0 }
local lastAt: any = nil
local function watch()
	if not danny or not danny.body or not holding() then
		lastAt = nil
		return
	end
	local at = danny.body.root.Position
	if lastAt and (at - lastAt).Magnitude < 300 then
		record.over = math.max(record.over, (at - lastAt).Magnitude - danny.holdLimit * 0.1)
		record.fastest = math.max(record.fastest, danny.holdLimit)
		record.steps += 1
	end
	lastAt = at
end
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		MoveHelper.step(0.1)
		watch()
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

-- Danny comes; Sol lifts the sofa, he walks over and takes its far end --------------------------------------------------------

local started = E.startRun(sol, HOUSE)
check("a solo run starts", started == nil, started)
Moving.step()
danny = MoveHelper.find(sol)
check("Danny comes", danny ~= nil and danny.body ~= nil)
check("Danny is Sol's from the start (10.1 free)", danny.hirer == sol)
local body = danny.body
local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{HOUSE}`)
E.place(sol, outside)
trigger(promptIn(site, "Enter house"), sol)
local origin = E.interiors[1]
local sofa = itemModel(3)
local SOFA = E.items.sofa.size
E.place(sol, sofa.PrimaryPart.Position + V3(0, 0, 3)) -- (facing -Z: the sofa in front of her, Danny's end beyond it)
local character = sol.Character
-- The sofa in Sol's arms (the weld, in Roblox: 8.6 where Moving's weld keeps it, Runtime.welded: lengthwise), else 3
-- studs in front of her root.
local function follow()
	if not E.welded(sofa) then
		sofa.PrimaryPart.CFrame = E.rootOf(sol).CFrame * M.CFrame.new(0, 0, -3)
	end
end
-- His place: Standoff past the sofa's far face (8.6 holding it: his end decided at the lift, the far end of its length);
-- his aim: that plus his lead now (8.6 his end's velocity × leadTime toward which it moves at HoldLead.Rate: this
-- runtime's player has no ping).
local function place(): any
	local ends = danny and danny.gripped == sofa.PrimaryPart and danny.holdEnd
	if ends then
		return sofa.PrimaryPart.CFrame * ends
	end
	return (sofa.PrimaryPart.CFrame * M.CFrame.new(0, 0, -(SOFA.Z / 2 + H.Standoff))).Position
end
local function lead(): (number, number)
	return danny.trail.leadX, danny.trail.leadZ
end
local function aim(): any
	local x, z = lead()
	return place() + V3(x, 0, z)
end
trigger(promptIn(sofa, "Lift"), sol)
local lifted = run(25, function()
	follow()
	return helped()
end)
follow()
run(1)
check("Danny walked over and took its far end: at his place", lifted and holding() and distance(body.root.Position, place()) < 0.05,
	distance(body.root.Position, place()))
check("8.3 the server says it: Sol (the leader) carries CarryPair (no run: client/PairSteer.luau), PairTurn, the pair's walk",
	character:GetAttribute("CarryPair") == true and character:GetAttribute("PairTurn") == H.PairTurn and helped())

-- Sol walks `seconds` along +Z (backwards, away from Danny: he follows her) at `speed` studs a second, the sofa in her
-- arms; after each of his steps, how far he is from his aim. Returns the worst gap from `settle` s on, the last gap.
local away = V3(0, 0, 1)
local function walkAt(speed: number, seconds: number, settle: number?): (number, number)
	local worst, last = 0, 0
	local steps = math.floor(seconds / 0.1 + 0.5)
	for index = 1, steps do
		E.rootOf(sol).CFrame = E.rootOf(sol).CFrame + away * speed * 0.1
		follow()
		run(0.1)
		last = distance(body.root.Position, aim())
		if index * 0.1 > (settle or 0) + 1e-9 then
			worst = math.max(worst, last)
		end
	end
	return worst, last
end
local function stand(seconds: number): number
	for _ = 1, math.floor(seconds / 0.1 + 0.5) do
		follow()
		run(0.1)
	end
	return distance(body.root.Position, place())
end

-- The 8.2 hold: his top speed from the carry's walk alone; Sol sprints ---------------------------------------------------------

local holdSpeed = Brain.holdSpeed
Brain.holdSpeed = function(walk: number, _pace: number?): number
	return holdSpeed(walk) -- (8.2: the carry's walk × HoldMargin + HoldExtra, whatever she does)
end
local _, oldGap = walkAt(SPRINT, 2)
check(`8.2's hold: Sol at a sprint ({SPRINT}) for 2 s, his top speed the pair walk's ({holdSpeed(PAIR)}): he falls behind every step (the owner's report)`,
	oldGap > 15 and holding(), oldGap)
Brain.holdSpeed = holdSpeed
local back = stand(4)
check("…standing, he walks back to his end (never put there)", back < 0.05 and record.over <= 1e-6, back)

-- 8.3: his top speed follows her real speed ---------------------------------------------------------------------------------------

record.over, record.fastest = 0, 0
local pairWorst = walkAt(PAIR, 3, 0.2)
local leadX, leadZ = lead()
local ahead = distance(body.root.Position, place())
check(`8.3 Sol at the pair's walk ({string.format("%.1f", PAIR)}) for 3 s: every step he is where his hold aims him`, pairWorst < 0.05 and holding(), pairWorst)
-- 9.0 (the owner's screenshot: Danny inside the Sofa): following her his lead would take him toward the piece's middle,
-- into it: his body stays at his place (HoldLead.In 0), his hands reach on by that lead instead (her screen shows his body
-- that late: there his hands are on its edge; Config.MoveHelper.Edge.Reach at most)
local carryAt = body.model:GetAttribute("CarryAt")
local reach = if M.typeof(carryAt) == "Vector3" then -carryAt.Z - (H.Standoff + H.Edge.Depth / 2) else 0
check("8.3 …her velocity × leadTime his lead (her screen shows his body that late); 9.0 following her, never into the piece: his body at his place, his hands reaching on by it",
	ahead < 0.02 and math.abs(leadX) + math.abs(leadZ) <= H.HoldLead.In + 1e-6 and H.HoldLead.Base > 0
	and math.abs(reach - math.min(PAIR * Brain.leadTime(0), H.Edge.Reach)) < 0.06, `{ahead} studs ahead, hands {reach} on`)
local fasterWorst = walkAt(PAIR * 1.2, 3)
check("8.3 20% faster (a lag spike, a slope) for 3 s: every step at his aim, from the first", fasterWorst < 0.05 and holding(), fasterWorst)
local mark = #E.strides
local sprintWorst = walkAt(SPRINT, 2)
check(`8.3 a sprint ({SPRINT}) for 2 s: every step at his aim (his top speed {danny.holdLimit}: her real speed × HoldMargin + HoldExtra, HoldCap at most)`,
	sprintWorst < 0.05 and holding() and danny.holdLimit <= H.HoldCap + 1e-6 and danny.holdLimit > SPRINT, sprintWorst)
local legs = 0
for index = mark + 1, #E.strides do
	if E.strides[index].npc == body.model then
		legs = E.strides[index].speed
	end
end
check("8.3 …his legs step at his real speed (a jog's steps: forwards after her)", math.abs(legs - SPRINT) < 0.5, legs)
local stopped = stand(1)
local restX, restZ = lead()
check("8.3 she stops: within a second he is back at his place, his lead gone", stopped < 0.05 and math.abs(restX) + math.abs(restZ) < 0.05, stopped)
-- a lag spike: her root 6 studs on at once (the server hears her late, then all at once)
E.rootOf(sol).CFrame = E.rootOf(sol).CFrame + away * 6
follow()
local spikeAt = body.root.Position
run(0.1)
local firstStep = distance(body.root.Position, spikeAt)
local caughtIn = 0.1
while distance(body.root.Position, place()) > 0.05 and caughtIn < 3 do
	follow()
	run(0.1)
	caughtIn += 0.1
end
check("8.3 a lag spike (her root 6 studs on at once): he catches up within half a second, never put there (his first step his top speed's)",
	caughtIn <= 0.5 + 1e-6 and firstStep > 2.5 and firstStep <= H.HoldCap * 0.1 + 1e-6 and holding(), `{caughtIn} s, first step {firstStep}`)
check("8.3 all the way: every step of his within his top speed × 0.1 s, his top speed never over HoldCap", record.over <= 1e-6
	and record.fastest <= H.HoldCap + 1e-6 and record.fastest > holdSpeed(PAIR), `{record.over} over, {record.fastest} at most`)

-- Let go: CarryPair gone ---------------------------------------------------------------------------------------------------------

E.Net.get("PutDown").OnServerEvent:Fire(sol)
run(0.3)
check("8.3 put down: Sol's CarryPair gone with the piece (her walk hers again), Danny's hands free", character:GetAttribute("CarryPair") == nil
	and character:GetAttribute("MoveCarry") == nil and not holding())

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
