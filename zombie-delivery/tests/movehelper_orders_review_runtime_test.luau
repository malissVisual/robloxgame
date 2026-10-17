-- 8.6 review (Danny's bubble and the crew's orders): the real server/Moving.luau and server/MoveHelper.luau on
-- tests/runtime/MovingRuntime.luau's fakes (as tests/movehelper_orders_runtime_test.luau: his walk a straight step a
-- tick, a carried piece moved with its carrier here), Sol's run with Bob of her crew far off in the lobby.
--   * PUT IT DOWN (putDown, who asked): a piece for two only from whoever carries it with him; a crew mate's elsewhere
--     does nothing (the piece still carried, a wobble check open on the carrier's end not a miss: no knock), and tells
--     them who can ("Sol carries the Sofa with Danny: only they can set it down."); the carrier's own sets it down as
--     ever. A piece in his arms alone: anybody's, the rest of the crew told who asked ("Bob had Danny set the Lamp
--     down: off his list.")
-- (10.6: nobody drives the van in a run, so he never rides in it: no GET OUT.)
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
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace

local HOUSE = "lone_house" -- (10.6: a run on the lone house, the van at its curb)
local _, _, outside = E.doorOf(SandboxMap.house(HOUSE))
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
local bob = E.player(77, "Bob", lobby + V3(400, 0, 400)) -- (of Sol's crew, far off)
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
local function stateNow(spot: number): string
	return danny.s.move.things[spot].state
end

-- The move; Danny Sol's (10.1 free); Bob joins Sol's crew --------------------------------------------------------------------------------

local started = E.startRun(sol, HOUSE)
check("a solo run starts", started == nil, started)
local truck = E.cars[sol]
truck.model:SetAttribute("BackOpen", true)
Moving.step()
danny = MoveHelper.find(sol)
run(0.3)
E.crew[sol] = { bob }
Moving.step()
check("Danny Sol's (10.1 free); Bob of her crew (far off in the lobby): the same Danny, with him too", danny ~= nil and danny.hirer == sol
	and MoveHelper.find(bob) == danny and bob:GetAttribute("MoveHelper") == "hired", bob:GetAttribute("MoveHelper"))

-- PUT IT DOWN from a crew mate elsewhere (putDown, who asked) ---------------------------------------------------------------

E.place(sol, outside)
promptIn(workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{HOUSE}`), "Enter house").Triggered:Fire(sol)

do
	local lamp = itemModel(1)
	local was = E.rootOf(sol).Position
	E.place(sol, lamp.PrimaryPart.Position + V3(3, 0, 0))
	sol.Character:SetAttribute("ClipboardHeld", true)
	E.request(sol, "helper", "assign", lamp) -- (a click on it with the clipboard out: on his list)
	E.place(sol, was + V3(6, 0, 0))
	local holds = run(60, function()
		return Rules.holding(danny.s.move, danny.id) == 1
	end)
	run(0.4)
	local noticeAt = #E.messages
	E.request(bob, "helper", "putdown")
	run(0.6) -- (9.0 his setting down: the Lamp glides down to the floor first)
	check("Bob (far off) has Danny put down the Lamp in his arms: on the ground, out of his hands, off his list", holds and stateNow(1) == "ground"
		and Rules.holding(danny.s.move, danny.id) == nil and #danny.queue == 0, stateNow(1))
	check("8.6 review: …Sol told who asked: \"Bob had Danny set the Lamp down: off the list.\"", told(sol, "🧑‍🔧 Bob had Danny set the Lamp down: off the list.", noticeAt)
		and not told(sol, "Danny set the Lamp down here", noticeAt), E.lastNotice(sol))
	check("…Bob, who asked: \"Danny set the Lamp down here: off the list.\"", told(bob, "🧑‍🔧 Danny set the Lamp down here: off the list.", noticeAt), E.lastNotice(bob))
end

do
	local sofa = itemModel(3)
	Config.CarryGrip.On = true -- (the wobbles on: a wobble check open on Sol's end as Bob gives his order)
	E.place(sol, sofa.PrimaryPart.Position + V3(0, 0, 3))
	promptIn(sofa, "Lift").Triggered:Fire(sol)
	local lifted = run(40, function()
		return select(2, Rules.holding(danny.s.move, danny.id)) == "helper"
	end)
	run(0.4)
	local wobble = Moving.gripCheck(sol)
	local condition = danny.s.move.things[3].condition
	local noticeAt = #E.messages
	E.request(bob, "helper", "putdown")
	run(0.5)
	check("8.6 review: Bob, far off, PUT IT DOWN on the Sofa Sol carries with Danny: nothing goes down (Sol carries it, Danny holds his end)",
		lifted and stateNow(3) == "carried" and Rules.holding(danny.s.move, sol.UserId) == 3 and select(2, Rules.holding(danny.s.move, danny.id)) == "helper",
		stateNow(3))
	check("8.6 review: …the wobble check open on Sol's end no miss for it: the Sofa's condition as it was", wobble
		and danny.s.move.things[3].condition == condition, `{condition} → {danny.s.move.things[3].condition}`)
	check("8.6 review: …Bob told who can: \"Sol carries the Sofa with Danny: only they can set it down.\"; Sol told nothing",
		told(bob, "🧑‍🔧 Sol carries the Sofa with Danny: only they can set it down.", noticeAt) and not told(sol, "Sofa", noticeAt), E.lastNotice(bob))
	noticeAt = #E.messages
	E.request(sol, "helper", "putdown")
	check("…Sol's own PUT IT DOWN: both ends down at once, Sol told \"You and Danny set the Sofa down.\", Bob \"Sol and Danny set the Sofa down.\"",
		stateNow(3) == "ground" and Rules.holding(danny.s.move, danny.id) == nil and Rules.holding(danny.s.move, sol.UserId) == nil
		and told(sol, "🧑‍🔧 You and Danny set the Sofa down.", noticeAt) and told(bob, "🧑‍🔧 Sol and Danny set the Sofa down.", noticeAt), stateNow(3))
	Config.CarryGrip.On = false
end

-- The end ------------------------------------------------------------------------------------------------------------------

Moving.endRun(sol)
run(0.2)
check("the move ends: Danny gone", MoveHelper.find(sol) == nil and MoveHelper.find(bob) == nil)
E.leave(bob)
E.leave(sol)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
