-- 7.0, the depot's helper ("Danny from the depot"): the real server/Moving.luau and server/MoveHelper.luau in the Luau
-- CLI (tests/run_tests.py builds MovingServer.luau and MoveHelperServer.luau on tests/runtime/MovingRuntime.luau's
-- fakes). The runtime has no physics and no pathfinding: his walk here is a straight step of speed × dt (useMover, no
-- `keep`: carrying together he is put at your piece's far end each step, as the constraints hold him in Roblox), and a
-- carried piece is moved with its carrier by the test (a weld is only a record). A solo move: Danny comes with the van;
-- 8.3 the player's Lift on the sofa calls him ("Danny, give me a hand!": no drag alone, the player waits at their end,
-- "Stop waiting" on its prompt) and he WALKS over from the van (through the front door his own way, never faded over),
-- "On three... lift!" at its far end and up it goes with him there (no pause, no snap), turned to the player, his arms
-- on it, the player's grip steadied; he moves with it (a walk that goes nowhere changes nothing: no "too far apart" any
-- more), out through the door; set down; 8.3 a call stopped (Lift again, G, STOP, walking away); lifted again (he
-- sprints over); the player loads it; he carries the ★ pieces first, a light two-hands one too (slower), then the
-- others, never a heavy one alone; he opens the van's back himself (or, not allowed, asks
-- and sets the piece down after WaitShut s); he opens it for the player coming with a piece; a piece the player is about
-- to lift is theirs; the other side of the player's heavy two-hands piece (the pair's walk); stuck: a new path after 2 s,
-- a nudge after 4 s; a bite, his death and comeback, running from a zombie, the orders (Help me: he follows you through
-- the door), the van parked far off, the crew growing (he goes) and Duo, the end of the move; a second move where the
-- room goes while he carries his piece ("Van's full, boss - drive it to the Wall?": set down beside the van), a third
-- where nothing he may carry fits, a fourth where his body goes. 8.3 the orders checked (his crew only, the four
-- orders, the rate limit), WAIT HERE; AUTO's ask on a move of its own: he goes to the heavy marble slab, "give me a
-- hand!" (the toast, the 🙋 marker, "Lift with Danny"), nobody comes: back to the light pieces, AskAgain s later he asks
-- again and the player answers: lifted together, carried to the van and loaded.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local Map = require("./Map")
local Rules = require("./MovingRules")
local PairCarry = require("./PairCarry") -- 8.1 carrying in two: the leader's steering (client/PairSteer.luau's)
local CarryGrip = require("./CarryGrip") -- 8.3: your lift check once Danny is in place
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
E.truckAt = V3(home.door.x + 30, 2, home.door.z - 20) -- (placeNear's spot: the van is at the house at once, its back
-- 30 studs from the front door)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (the move's own roamers far off: this test brings its zombie itself)
end

-- His walk: straight toward the point, speed × dt a step (the last speed asked is kept to check it).
local lastSpeed = 0
local walker = {
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
		lastSpeed = speed
	end,
	halt = function(body: any)
		body.walking = false
	end,
}
MoveHelper.useMover(walker)

local sol = E.player(44, "Sol", V3(Map.Depot.x, 3, Map.Depot.z))
Moving.useArt(E.art)
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
local function stateOf(spot: number): any
	local view = E.last(sol, "Moving", "state")
	for _, item in (view and view.a and view.a.items) or {} do
		if item.spot == spot then
			return item
		end
	end
	return nil
end
-- A carried piece stays in front of its carrier (the weld, in Roblox; its root set straight: the recorder's PivotTo
-- adds its rounding up step after step).
local function follow(model: any, player: any)
	model.PrimaryPart.CFrame = E.rootOf(player).CFrame * M.CFrame.new(0, 0, -3)
end
local danny: any = nil
-- What he carries alone stays in front of him (the weld, in Roblox).
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
end
-- 8.1 while he holds the far end: the most his root moved in one of his steps over what his top speed allows then
-- (never put there: only a door's fade does, the piece in the other world), and his top speed's range.
local jump = { over = 0, most = 0, fastest = 0, slowest = math.huge, steps = 0 }
local lastHeld: any = nil
local function watchJump()
	local h = danny
	local role: string? = nil
	if h and h.body then
		role = select(2, Rules.holding(h.s.move, h.id))
	end
	if role ~= "helper" then
		lastHeld = nil
		return
	end
	local at = h.body.root.Position
	if lastHeld and (at - lastHeld).Magnitude < 300 then -- (not a door's fade: the house's interior is far off the map)
		local moved = (at - lastHeld).Magnitude
		jump.over = math.max(jump.over, moved - h.holdLimit * 0.1)
		jump.most = math.max(jump.most, moved)
		jump.fastest = math.max(jump.fastest, h.holdLimit)
		jump.slowest = math.min(jump.slowest, h.holdLimit)
		jump.steps += 1
	end
	lastHeld = at
end
-- Steps of 0.1 s (his loop's), the move's tick every other one; until `done` (true when it came), or `seconds` long.
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		MoveHelper.step(0.1)
		watchJump()
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
-- A piece's state now (the rules'; the list the player was sent comes a tick later).
local function stateNow(spot: number): string
	return danny.s.move.things[spot].state
end
local function distance(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function helped(): boolean
	return math.abs((sol.Character:GetAttribute("CarrySpeed") or 0) - WALK * T.Speed.Pair) < 1e-6
end
-- Where his root belongs: the far end of the piece (Standoff past its far face).
local function farEnd(model: any, depth: number): any
	return (model.PrimaryPart.CFrame * M.CFrame.new(0, 0, -(depth / 2 + H.Standoff))).Position
end

-- 8.1 the leader's client (client/PairSteer.luau) while two carry: the heading turns toward the way at PairTurn at most
-- (shared/PairCarry.luau steer; a way behind is walked backwards), the walk the pair's × the turn's factor. The most
-- the heading turned in one step, and the steps walked backwards (the velocity against the facing).
local steer = PairCarry.newSteer(0)
local steerFor: any = nil
local turnedMost, backSteps = 0, 0
local function heading(): number
	local look = E.rootOf(sol).CFrame.LookVector
	return PairCarry.yawOf(look.X, look.Z)
end
-- Sol walks to `to` with the piece (alone: a stud every 0.1 s, facing the way; 8.1 carried in two: the pair's walk, the
-- heading the steering's), the run's steps between; returns the most his root was off the piece's far end while he
-- held it.
local function walk(model: any, to: any): number
	local worst = 0
	local depth = model.PrimaryPart.Size.Z
	for _ = 1, 400 do
		local here = E.rootOf(sol).Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		if way.Magnitude < 0.05 then
			break
		end
		local rate = sol.Character:GetAttribute("PairTurn")
		if type(rate) == "number" then
			if steerFor ~= model then
				steerFor, steer.back = model, false
			end
			local before = heading()
			steer.heading = before
			local factor = PairCarry.steer(steer, way.X, way.Z, 0.1, math.rad(rate))
			turnedMost = math.max(turnedMost, math.abs(PairCarry.wrap(steer.heading - before)))
			local stepLength = (sol.Character:GetAttribute("CarrySpeed") or 0) * factor * 0.1
			local nextAt = here + way.Unit * math.min(stepLength, way.Magnitude)
			E.rootOf(sol).CFrame = M.CFrame.new(nextAt) * M.CFrame.Angles(0, steer.heading, 0)
			if way:Dot(E.rootOf(sol).CFrame.LookVector) < 0 then
				backSteps += 1
			end
		else
			local nextAt = here + way.Unit * math.min(1, way.Magnitude)
			E.rootOf(sol).CFrame = M.CFrame.lookAt(nextAt, nextAt + way.Unit)
		end
		follow(model, sol)
		run(0.1)
		local _, role = Rules.holding(danny.s.move, danny.id)
		if role == "helper" then
			worst = math.max(worst, distance(danny.body.root.Position, farEnd(model, depth)))
		end
	end
	return worst
end

-- Danny comes ----------------------------------------------------------------------------------------------------------------

local started = Moving.admin(sol, "start")
check("a solo move starts", string.find(started, "started", 1, true) ~= nil, started)
local truck = E.cars[sol]
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
Moving.step()
danny = MoveHelper.find(sol)
check("Danny comes with a crew of one, on AUTO (8.3: the default)", danny ~= nil and danny.body ~= nil and danny.mode == "auto")
danny.askAgain = math.huge -- (8.3 his asks for a hand wait for their own move below)
local body = danny.body
local npc = body.model
check("his body: Danny, ZDC Moving, his id in the rules (no player's)", npc.Name == "Danny" and npc:GetAttribute("MoveHelper") == danny.id and danny.id < -1000000
	and body.humanoid.MaxHealth == H.Health and body.humanoid.Health == H.Health)
check("…at the van's back", distance(body.root.Position, cargoDoor.WorldPosition) < 8, distance(body.root.Position, cargoDoor.WorldPosition))
check("he says: Got your back!", E.saidSince("Danny from the depot. Got your back!", 0))
check("the player hears it", string.find(E.lastNotice(sol), "Danny from the depot joins", 1, true) ~= nil, E.lastNotice(sol))
check("the orders' strip: MoveHelper = auto, what he does; 8.3 his id (his card finds his body by it)", sol:GetAttribute("MoveHelper") == "auto"
	and type(sol:GetAttribute("MoveHelperDoing")) == "string" and sol:GetAttribute("MoveHelperId") == danny.id and sol:GetAttribute("MoveHelperCall") == nil)
check("his name in the rules' list", MoveHelper.nameOf(danny.id) == "Danny" and MoveHelper.nameOf(44) == nil)
local targets = E.Zombies.extraTargets()
local hunted = false
for _, t in targets do
	if t.humanoid == body.humanoid and t.player == sol then
		hunted = true
	end
end
check("the zombies go after him too (Zombies.extraTargets)", hunted)

-- The sofa: lifted together, carried together -------------------------------------------------------------------------------

local site = workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge")
local enter = promptIn(site, "Enter house")
-- the owner took the Technician out: the front door is open from the start (no lock for Danny to wait at)
E.place(sol, outside)
check("the front door is open: in at once (8.1: walked through, Enter house off), no Pick lock", enter ~= nil and not enter.Enabled and promptIn(site, "Pick lock") == nil and sol:GetAttribute("MoveRole") == "driver")
trigger(enter, sol)
local origin = E.interiors[1]
check("Sol is inside", (E.rootOf(sol).Position - origin.Position).Magnitude < 10)
local sofa = itemModel(3)
local SOFA = E.items.sofa.size
E.place(sol, sofa.PrimaryPart.Position + V3(0, 0, 3))
local character = sol.Character
local said = #E.said
local outsideAt = body.root.Position
trigger(promptIn(sofa, "Lift"), sol)
check("8.3 Lift with Danny on the move: no drag alone, Sol calls him and waits at her end", character:GetAttribute("MoveCarry") == nil
	and character:GetAttribute("CarrySpeed") == nil and danny.s.move.things[3].state == "home" and danny.call ~= nil and danny.call.spot == 3
	and sol:GetAttribute("MoveHelperCall") == "Sofa")
check("…\"Danny, give me a hand!\" (her toast; a bubble over her head) and his answer", string.find(E.lastNotice(sol), "\"Danny, give me a hand!\"", 1, true) ~= nil
	and E.saidSince("Hold it, I'll get the other end!", said), E.lastNotice(sol))
local waitPrompt = promptIn(sofa, "Stop waiting")
check("…its prompt: \"Stop waiting\" · \"Waiting for Danny…\" (E again stops it)", waitPrompt ~= nil and waitPrompt.ObjectText == "Waiting for Danny…")
-- he walks there: from the van, through the front door (his own way in), to its far end as Sol will hold it
local took, longest, alone, crossed = 0, 0, false, 0
local lastAt = body.root.Position
local strip: string? = nil
local lifted = run(20, function()
	took += 0.1
	local at = body.root.Position
	if (at - lastAt).Magnitude > 300 then
		crossed += 1 -- (the front door: the interior is far off the map)
	elseif not helped() then
		longest = math.max(longest, distance(at, lastAt))
	end
	lastAt = at
	strip = strip or (if danny.action == "come" then sol:GetAttribute("MoveHelperDoing") else nil)
	alone = alone or (character:GetAttribute("MoveCarry") == 3 and not helped())
	return helped()
end)
check("8.3 Danny WALKS over (every step his sprint's at most: never faded over), in by the front door, and up it goes with him",
	lifted and took > 1 and longest <= WALK * H.Sprint * 0.1 + 1e-6 and crossed == 1 and (outsideAt - origin.Position).Magnitude > 1000,
	`{took} s, longest step {longest}, {crossed} door(s)`)
check("…never dragged alone meanwhile: straight into the two-person walk (8.1: 0.7)", not alone and helped())
check("…\"On three... lift!\" once he was there; the strip said he was coming", E.saidSince("On three... lift!", said)
	and strip == "Coming to lift the Sofa with you", strip)
check("…the call over: its prompt back as ever, her MoveHelperCall gone", danny.call == nil and sol:GetAttribute("MoveHelperCall") == nil
	and promptIn(sofa, "Lift") ~= nil and promptIn(sofa, "Stop waiting") == nil)
check("…the lift's moment: he stood within CallReady of the far end (the hold walks him the rest: no snap)",
	distance(body.root.Position, farEnd(sofa, SOFA.Z)) <= H.CallReady + 0.05 and jump.over <= 1e-6, distance(body.root.Position, farEnd(sofa, SOFA.Z)))
follow(sofa, sol)
run(0.6)
check("…inside, at the sofa's far end, turned to Sol", (body.root.Position - origin.Position).Magnitude < 40 and distance(body.root.Position, farEnd(sofa, SOFA.Z)) < 0.05
	and body.root.CFrame.LookVector:Dot(E.rootOf(sol).Position - body.root.Position) > 0, distance(body.root.Position, farEnd(sofa, SOFA.Z)))
check("Sol hears it", string.find(E.lastNotice(sol), "Danny took the other end of the Sofa", 1, true) ~= nil, E.lastNotice(sol))
check("the list says who: Sol + Danny", stateOf(3) ~= nil and stateOf(3).by == "Sol + Danny", stateOf(3) and stateOf(3).by)
check("he has no G prompt (only players do)", (function()
	for _, d in sofa:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d:GetAttribute("MoveOnly") == danny.id then
			return false
		end
	end
	return true
end)())
local at = npc:GetAttribute("CarryAt")
check("7.x his arms on its edge (Carrying, two hands, CarryAt in front of him)", npc:GetAttribute("Carrying") == "furniture" and npc:GetAttribute("CarryHands") == 2
	and M.typeof(at) == "Vector3" and at.Z < 0 and at.Z > -2 and M.typeof(npc:GetAttribute("CarrySize")) == "Vector3", at and at.Z)
check("7.x Sol's grip steadied (GripSteady: a bigger box)", character:GetAttribute("GripSteady") == true)
said = #E.said
run(H.ThreeAfter + 0.2)
check("8.3 …\"On three... lift!\" said once (before the lift, not again after it)", not E.saidSince("On three... lift!", said))
check("…the strip: carrying the Sofa with you", sol:GetAttribute("MoveHelperDoing") == "Carrying the Sofa with you", sol:GetAttribute("MoveHelperDoing"))
-- walking and turning together: he moves with it, every step at its far end (8.1 walk-in doors off meanwhile: these
-- walks turn round by the house's door; it is the Leave prompt's below)
T.Doors.Walk = false
local worst = walk(sofa, origin.Position + V3(6, 3, 8))
worst = math.max(worst, walk(sofa, origin.Position + V3(0, 3, 2)))
check("7.x walking and turning together: he stays at its far end", worst < 0.05 and helped(), worst)
check("8.1 Sol (the leader) gets PairTurn while Danny holds the far end: the heading turns that slowly (client/PairSteer.luau)",
	character:GetAttribute("PairTurn") == H.PairTurn)
check("8.1 …walking and turning together the heading turned PairTurn degrees a second at most", turnedMost > 0 and turnedMost <= math.rad(H.PairTurn) * 0.1 + 1e-9,
	math.deg(turnedMost) * 10)
-- 8.1 the way behind Sol: walked backwards, facing the sofa and Danny (no swing at all), Danny walking forwards after him
local function stridesSince(from: number, sign: number): number
	local n = 0
	for index = from + 1, #E.strides do
		if E.strides[index].npc == npc and E.strides[index].speed * sign > 0.5 then
			n += 1
		end
	end
	return n
end
local h0 = heading()
local strides = #E.strides
local backBefore = backSteps
local look0 = E.rootOf(sol).CFrame.LookVector
worst = walk(sofa, E.rootOf(sol).Position - look0 * 6)
check("8.1 the way behind: Sol walks backwards, the heading stays (no swing), Danny at the far end walking forwards after him",
	backSteps - backBefore >= 5 and math.abs(PairCarry.wrap(heading() - h0)) < 1e-6 and worst < 0.05 and stridesSince(strides, 1) >= 4
	and stridesSince(strides, -1) == 0, `{backSteps - backBefore} back, {stridesSince(strides, 1)} forward strides, {worst}`)
-- …the way ahead (toward Danny): Sol forwards, Danny walking backwards (his walk played in reverse)
strides = #E.strides
backBefore = backSteps
worst = walk(sofa, E.rootOf(sol).Position + look0 * 4)
check("8.1 the way ahead: Sol walks forwards, the heading stays, Danny walks backwards", backSteps == backBefore and math.abs(PairCarry.wrap(heading() - h0)) < 1e-6
	and worst < 0.05 and stridesSince(strides, -1) >= 3, `{stridesSince(strides, -1)} backward strides`)
-- 8.1 turning round: the way to Sol's right, twice (180° in all): PairTurn degrees a second at most, slower meanwhile
turnedMost = 0
local slowest = math.huge
local turnFrom, turnAt = heading(), E.clock
for _ = 1, 2 do
	local look = E.rootOf(sol).CFrame.LookVector
	local right = V3(-look.Z, 0, look.X)
	local before = E.rootOf(sol).Position
	local t = E.clock
	worst = math.max(worst, walk(sofa, before + right * 14))
	slowest = math.min(slowest, distance(E.rootOf(sol).Position, before) / (E.clock - t))
end
local turned = math.abs(PairCarry.wrap(heading() - turnFrom))
check("8.1 the player turns 180° holding the sofa: the heading turns PairTurn degrees a second at most (never at once)",
	turned > math.pi - 0.05 and turnedMost <= math.rad(H.PairTurn) * 0.1 + 1e-9 and E.clock - turnAt >= math.pi / math.rad(H.PairTurn) - 0.05,
	`{math.deg(turned)}° in {E.clock - turnAt} s, at most {math.deg(turnedMost) * 10}°/s`)
check("…the pair walks slower while it turns, Danny at the far end all the way", slowest < WALK * T.Speed.Pair * 0.95 and worst < 0.05 and helped(), `{slowest} {worst}`)
-- 8.1 Sol's body spun round at once (a client without the steering): Danny walks round at his top speed, never put there
E.rootOf(sol).CFrame = E.rootOf(sol).CFrame * M.CFrame.Angles(0, math.pi, 0)
follow(sofa, sol)
local spunFrom = body.root.Position
run(0.1)
local firstStep = distance(body.root.Position, spunFrom)
local caught = run(3, function()
	return distance(body.root.Position, farEnd(sofa, SOFA.Z)) < 0.05
end)
check("8.1 spun round at once: no snap, his first step his top speed's (the pair's walk and a margin), at the far end again within a second",
	caught and firstStep <= Brain.holdSpeed(WALK * T.Speed.Pair) * 0.1 + 1e-6 and firstStep > 1 and jump.over <= 1e-6, `{firstStep} {jump.over}`)
-- 8.1 stuck far behind (his constraints can't move him: a mover that keeps nothing): HoldStuck s, then eased back over
-- HoldEase s at the gap / HoldEase a second, never put there
local kept: { any } = {}
MoveHelper.useMover({ move = walker.move, halt = walker.halt, keep = function(b: any, anchor: any, offset: any, _dt: number, limit: number, snap: boolean)
	table.insert(kept, { at = E.clock, limit = limit, snap = snap, gap = ((anchor.CFrame * offset).Position - b.root.Position).Magnitude })
end })
walk(sofa, E.rootOf(sol).Position - E.rootOf(sol).CFrame.LookVector * 15)
run(H.HoldStuck + H.HoldEase + 0.5)
local hold = Brain.holdSpeed(WALK * T.Speed.Pair)
local behindAt, easeAt, eased, snapped, easeLimit, easeGap = nil, nil, 0, false, 0, 0
for _, k in kept do
	snapped = snapped or k.snap
	if not behindAt and k.gap > H.HoldBehind then
		behindAt = k.at
	end
	if k.limit > hold + 1e-6 then
		eased += 1
		if not easeAt then
			easeAt, easeLimit, easeGap = k.at, k.limit, k.gap
		end
	end
end
check("8.1 stuck far behind: never put there; HoldStuck s behind, then eased back over HoldEase s at the gap / HoldEase", not snapped and behindAt ~= nil
	and easeAt ~= nil and easeAt - behindAt >= H.HoldStuck - 0.15 and easeAt - behindAt <= H.HoldStuck + 0.25 and math.abs(easeLimit - easeGap / H.HoldEase) < 1e-6
	and eased == math.floor(H.HoldEase / 0.1 + 0.5), `{behindAt} → {easeAt}, {eased} steps at {easeLimit}`)
MoveHelper.useMover(walker)
caught = run(3, function()
	return distance(body.root.Position, farEnd(sofa, SOFA.Z)) < 0.05
end)
check("…free to move again: he walks back to the far end", caught and helped())
-- out of the door with it: he comes through with Sol
T.Doors.Walk = true
local leave = promptIn(workspace, "Leave house")
E.place(sol, origin.Position + V3(0, 3, 1))
follow(sofa, sol)
trigger(leave, sol)
follow(sofa, sol)
run(0.2)
check("out of the door: Danny comes through with the sofa, at its far end", (E.rootOf(sol).Position - origin.Position).Magnitude > 1000 and distance(body.root.Position, farEnd(sofa, SOFA.Z)) < 0.05
	and character:GetAttribute("MoveCarry") == 3, distance(body.root.Position, E.rootOf(sol).Position))
check("…still two on it", helped())
local back = cargoDoor.WorldPosition + V3(0, 0, 2)
worst = walk(sofa, back + V3(24, 0, 0))
check("…across the yard together", worst < 0.05 and helped(), worst)
-- a walk that goes nowhere (in Roblox: his own walk is off while he carries with you): nothing changes, no drop
MoveHelper.useMover({ move = function() end, halt = function() end })
worst = walk(sofa, back + V3(24, 0, 24))
check("7.x never a \"too far apart\" drop: 24 studs on he still holds the far end", helped() and Rules.holding(danny.s.move, danny.id) == 3 and worst < 0.05
	and string.find(E.lastNotice(sol), "let go", 1, true) == nil, E.lastNotice(sol))
MoveHelper.useMover(walker)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
run(0.2)
check("Sol sets it down: Danny's hands free, his arms down, Sol's grip as before", Rules.holding(danny.s.move, danny.id) == nil and npc:GetAttribute("Carrying") == nil
	and npc:GetAttribute("CarryAt") == nil and character:GetAttribute("GripSteady") == nil and stateNow(3) == "ground")
-- 8.3 a call stopped: Lift again, G, the status line's STOP, walking away (him far off: on his way each time)
local function waitingNow(): boolean
	return danny.call ~= nil and sol:GetAttribute("MoveHelperCall") == "Sofa" and promptIn(sofa, "Stop waiting") ~= nil
end
local function stopped(): boolean
	return danny.call == nil and sol:GetAttribute("MoveHelperCall") == nil and promptIn(sofa, "Stop waiting") == nil and promptIn(sofa, "Lift") ~= nil
		and character:GetAttribute("MoveCarry") == nil and stateNow(3) == "ground"
end
body.root.CFrame = M.CFrame.new(back.X - 40, 3, back.Z - 40)
trigger(promptIn(sofa, "Lift"), sol)
run(0.2)
check("8.3 Lift: Sol waits, Danny on his way", waitingNow() and danny.action == "come")
trigger(promptIn(sofa, "Stop waiting"), sol)
check("…Lift again (its prompt says Stop waiting): the call is off, nothing lifted (\"You stopped waiting for Danny.\")", stopped()
	and E.lastNotice(sol) == "You stopped waiting for Danny.", E.lastNotice(sol))
trigger(promptIn(sofa, "Lift"), sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
check("…G with empty hands (the PutDown remote): off", stopped())
trigger(promptIn(sofa, "Lift"), sol)
E.request(sol, "helper", "stop")
check("…the status line's STOP (the Moving remote's (\"helper\", \"stop\")): off", stopped())
trigger(promptIn(sofa, "Lift"), sol)
run(0.3)
local solAt = E.rootOf(sol).Position
E.place(sol, solAt + V3(40, 0, 0))
run(0.2)
check("…walking away (CallLeave studs past the Lift's reach): off (\"You walked away\")", stopped() and string.find(E.lastNotice(sol), "walked away", 1, true) ~= nil, E.lastNotice(sol))
E.place(sol, solAt)
run(0.5)
check("…and he is back about his work (no call left for him)", danny.call == nil and danny.action ~= "come", danny.action)
-- lifted again with Danny near: he sprints over (no fade)
body.root.CFrame = M.CFrame.new(back.X + 18, 3, back.Z + 14)
said = #E.said
trigger(promptIn(sofa, "Lift"), sol)
took = 0
local sprint = 0
lifted = run(5, function()
	took += 0.1
	if danny.action == "come" then
		sprint = math.max(sprint, lastSpeed)
	end
	return helped()
end)
check("8.3 lifted again, Danny near: he sprints over (Sprint × the walk) and it is up together within 2 s", lifted and took <= 2 + 1e-6 and math.abs(sprint - WALK * H.Sprint) < 1e-6
	and E.saidSince("On three... lift!", said), `{took} s, {sprint}`)
follow(sofa, sol)
run(0.4)
worst = walk(sofa, back)
check("…to the van's back together", worst < 0.05 and helped(), worst)
truck.model:SetAttribute("BackOpen", true)
run(0.4)
local load = promptIn(truck.model, "Load")
trigger(load, sol)
check("Sol loads the sofa: in the van, both hands free", character:GetAttribute("MoveCarry") == nil and danny.s.move.things[3].state == "truck", E.lastNotice(sol))
run(0.3)
check("…and Danny's hands are free", Rules.holding(danny.s.move, danny.id) == nil and npc:GetAttribute("Carrying") == nil and character:GetAttribute("GripSteady") == nil)
check("8.1 …and Sol's PairTurn gone with it (his body turns where he walks again)", character:GetAttribute("PairTurn") == nil)
check("8.1 all the way with the sofa Danny was never put at its far end (only the door's fade did): every step of his within his top speed × 0.1 s",
	jump.steps > 100 and jump.over <= 1e-6 and jump.most > 1, `{jump.steps} steps, {jump.over} over, the longest {jump.most}`)
check("8.1 …his top speed: the pair's walk × HoldMargin + HoldExtra (more only while eased back)", math.abs(jump.slowest - Brain.holdSpeed(WALK * T.Speed.Pair)) < 1e-6
	and math.abs(Brain.holdSpeed(WALK * T.Speed.Pair) - (WALK * T.Speed.Pair * H.HoldMargin + H.HoldExtra)) < 1e-6, jump.slowest)

-- (c) the other side of your heavy two-hands piece ----------------------------------------------------------------------------------

local tv = itemModel(2)
E.place(sol, outside)
trigger(enter, sol)
E.place(sol, tv.PrimaryPart.Position + V3(0, 0, 2))
trigger(promptIn(tv, "Pick up"), sol)
follow(tv, sol)
check("Sol picks up the TV (two hands, weight 4) alone", character:GetAttribute("MoveCarry") == 2
	and math.abs((character:GetAttribute("CarrySpeed") or 0) - Rules.carrySpeed(WALK, "both", 4)) < 1e-6, character:GetAttribute("CarrySpeed"))
said = #E.said
local assisted = run(6, function()
	return Rules.holding(danny.s.move, danny.id) == 2
end)
check("7.x Danny takes its other side (\"Here, let me take the other side.\"): the pair's walk for both (8.1: 0.7)", assisted and helped()
	and E.saidSince("Here, let me take the other side.", said) and select(2, Rules.holding(danny.s.move, danny.id)) == "helper")
follow(tv, sol)
run(0.3)
check("…at its far side, Sol's grip steadied", distance(body.root.Position, farEnd(tv, E.items.tv.size.Z)) < 0.05 and character:GetAttribute("GripSteady") == true)
E.place(sol, origin.Position + V3(0, 3, 1))
follow(tv, sol)
trigger(leave, sol)
follow(tv, sol)
run(0.2)
worst = walk(tv, back)
check("…out through the door and to the van together", worst < 0.05 and helped(), worst)
run(0.2)
trigger(load, sol)
check("…Sol loads it, both pairs of hands free", danny.s.move.things[2].state == "truck" and Rules.holding(danny.s.move, danny.id) == nil and character:GetAttribute("MoveCarry") == nil)

-- On his own: the ★ pieces first, then the others, a light two-hands one too, never a heavy one ---------------------------

E.place(sol, back + V3(30, 0, 0)) -- (out of the way: no piece of his is "about to be lifted" by Sol)
local loadedAt: { [number]: number } = {}
local clockSpeed = 0
local loadShown = false
local n = 0
local arms: any = nil
local heavyTaken = false
-- (a): the ★ box first, never the heavy clock (two hands, weight 6 ≥ LightWeight) nor the slab (two people); then (b) the
-- bar raised over the clock's weight (H.LightWeight 7): the clock is light, his alone (★: before the lamp)
local function look()
	n += 1
	local spot, role = Rules.holding(danny.s.move, danny.id)
	heavyTaken = heavyTaken or (H.LightWeight == 5 and (spot == 4 or spot == 6))
	loadShown = loadShown or (spot ~= nil and role == "carrier" and load.Enabled)
	if spot == 4 and role == "carrier" and danny.action == "deliver" then
		clockSpeed = lastSpeed
		arms = arms or { npc:GetAttribute("Carrying"), npc:GetAttribute("CarryHands") }
	end
	for _, s in { 1, 4, 5 } do
		local item = stateOf(s)
		if item and item.state == "truck" and not loadedAt[s] then
			loadedAt[s] = n
		end
	end
end
run(160, function()
	look()
	return loadedAt[5] ~= nil
end)
check("8.3 AUTO: the ★ box of memories first, never a heavy piece alone (Grandpa's Clock: two hands, weight 6 ≥ LightWeight; the slab)",
	loadedAt[5] ~= nil and not heavyTaken and stateNow(4) == "home" and stateNow(6) == "home" and loadedAt[1] == nil)
H.LightWeight = 7
run(160, function()
	look()
	return loadedAt[1] ~= nil and loadedAt[4] ~= nil
end)
H.LightWeight = 5
check("7.x a two-hands piece under LightWeight (the bar raised to 7): Danny carries Grandpa's Clock (★) to the van and loads it", loadedAt[4] ~= nil)
check("…at 0.7 × a player's two-hands walk (slower than a one-hand piece)", math.abs(clockSpeed - Rules.carrySpeed(WALK, "both", 6) * 0.7) < 1e-6, clockSpeed)
check("…in both arms (his Carrying: furniture, two hands)", arms ~= nil and arms[1] == "furniture" and arms[2] == 2)
check("the ★ ones first (the box of memories, the clock), then the lamp", loadedAt[4] ~= nil and loadedAt[5] ~= nil and loadedAt[1] ~= nil
	and math.max(loadedAt[4], loadedAt[5]) < loadedAt[1], `{loadedAt[4]} {loadedAt[5]} {loadedAt[1]}`)
check("…the van's Load prompt stays off for what he carries (the back's own E stays free)", not loadShown)
check("Sol hears what he loaded", (function()
	for _, m in E.messages do
		if m.player == sol and m.remote == "Notice" and string.find(tostring(m.kind), "Danny loaded", 1, true) then
			return true
		end
	end
	return false
end)())
run(4)
check("only the marble slab (two people) left: he never takes it alone", Rules.holding(danny.s.move, danny.id) == nil and stateNow(6) == "home")
check("…he waits at the van", danny.action == "wait" and sol:GetAttribute("MoveHelperDoing") == "Waiting at the van" and distance(body.root.Position, cargoDoor.WorldPosition) < 8,
	sol:GetAttribute("MoveHelperDoing"))

-- The van's back: he opens it himself; not allowed, he asks --------------------------------------------------------------------

local lamp = itemModel(1)
local unload = promptIn(truck.model, "Take out")
E.place(sol, back)
trigger(unload, sol)
check("Sol takes the lamp back out", character:GetAttribute("MoveCarry") == 1, E.lastNotice(sol))
E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, back + V3(30, 0, 0))
truck.model:SetAttribute("BackOpen", false)
said = #E.said
local opened = E.backSet or 0
local inAgain = run(30, function()
	return stateNow(1) == "truck"
end)
check("7.x the back shut: he opens it himself (\"I'll get the doors!\") and loads the lamp", inAgain and E.saidSince("I'll get the doors!", said) and (E.backSet or 0) > opened)
H.OpenBack = false
E.place(sol, back)
trigger(unload, sol)
E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, back + V3(30, 0, 0))
truck.model:SetAttribute("BackOpen", false)
said = #E.said
local carried = run(30, function()
	return Rules.holding(danny.s.move, danny.id) == 1
end)
check("not allowed to open it: Danny goes for the lamp", carried)
body.humanoid.Health = 80
body.humanoid.HealthChanged:Fire(80)
run(0.3)
local bitten = stateOf(1)
check("a bite knocks the fragile lamp in his arms", bitten ~= nil and math.abs(bitten.condition - (1 - 20 * T.Damage.PerHp * T.Damage.Fragile)) < 0.011, bitten and bitten.condition)
local shut = run(30, function()
	return E.saidSince("Open the back, boss!", said)
end)
check("…the back shut: \"Open the back, boss!\"", shut)
local down = run(H.WaitShut + 5, function()
	return Rules.holding(danny.s.move, danny.id) == nil
end)
check("…WaitShut s later he sets it down beside the van", down and stateNow(1) == "ground" and distance(lamp.PrimaryPart.Position, cargoDoor.WorldPosition) < 14,
	distance(lamp.PrimaryPart.Position, cargoDoor.WorldPosition))
run(3)
check("…and leaves it there while the back stays shut", Rules.holding(danny.s.move, danny.id) == nil and stateNow(1) == "ground")
H.OpenBack = true
truck.model:SetAttribute("BackOpen", true)
inAgain = run(20, function()
	return stateNow(1) == "truck"
end)
check("the back open: he takes it in", inAgain)

-- (d) the back for you: you come with a piece, the back shut, he opens it ---------------------------------------------------------

run(3)
E.place(sol, back)
trigger(unload, sol)
truck.model:SetAttribute("BackOpen", false)
said = #E.said
walk(lamp, back + V3(6, 0, 4))
local forYou = run(10, function()
	return truck.model:GetAttribute("BackOpen") == true
end)
check("7.x Sol at the van with the lamp, the back shut: Danny opens it (\"I'll get the doors!\")", forYou and E.saidSince("I'll get the doors!", said)
	and Rules.holding(danny.s.move, danny.id) == nil)
walk(lamp, back)
run(0.2)
trigger(load, sol)
check("…and Sol loads it", danny.s.move.things[1].state == "truck", E.lastNotice(sol))

-- The reservation: the piece you are about to lift is yours ------------------------------------------------------------------------

trigger(unload, sol)
E.place(sol, outside + V3(6, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, lamp.PrimaryPart.Position + V3(2, 0, 0)) -- (right by it, hands free)
run(6)
check("7.x Sol stands by the lamp, hands free: he leaves it to Sol", Rules.holding(danny.s.move, danny.id) == nil and stateNow(1) == "ground" and danny.action ~= "fetch",
	danny.action)
trigger(promptIn(lamp, "Pick up"), sol)
check("…Sol's lift wins", character:GetAttribute("MoveCarry") == 1)
walk(lamp, back)
run(0.2)
trigger(load, sol)
check("…and Sol loads it", danny.s.move.things[1].state == "truck", E.lastNotice(sol))

-- Down and back up -----------------------------------------------------------------------------------------------------------

E.place(sol, back)
trigger(unload, sol)
E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, back + V3(30, 0, 0))
carried = run(15, function()
	return Rules.holding(danny.s.move, danny.id) == 1
end)
check("he picks the lamp up again", carried)
danny.s.move.things[1].condition = 1 -- (as good as new again: the bites and this fall would break it)
local before = 1
said = #E.said
body.humanoid.Health = 0
body.humanoid.HealthChanged:Fire(0)
run(0.3)
check("killed: the lamp falls, knocked", stateNow(1) == "ground" and stateOf(1).condition < before - 0.1 and Rules.holding(danny.s.move, danny.id) == nil, stateOf(1).condition)
check("…he is down (\"I'll be back!\"), the player hears it", danny.dead and E.saidSince("Ugh... I'll be back!", said)
	and string.find(E.lastNotice(sol), "Danny is down", 1, true) ~= nil and sol:GetAttribute("MoveHelperDoing") == "Down: back at the van soon")
run(3.2)
check("…his body goes a moment later", npc.Parent == nil and danny.body == nil)
local backUp = run(H.Respawn, function()
	return danny.body ~= nil
end)
check("Respawn s later he is back at the van", backUp and not danny.dead and distance(danny.body.root.Position, cargoDoor.WorldPosition) < 8 and E.saidSince("Back on my feet!", said))
body = danny.body
npc = body.model
local again = run(20, function()
	return stateNow(1) == "truck"
end)
check("…and takes the lamp in", again)

-- A zombie: he runs ----------------------------------------------------------------------------------------------------------

local here = body.root.Position
local z = E.Zombies.spawn("walker", here + V3(6, 0, 0), sol)
run(0.2)
check("a zombie near: he runs", danny.action == "flee" and danny.fleeing)
run(1)
local away = distance(body.root.Position, z.root.Position)
check("…away from it", away > 6 + 5, away)
z.dead = true
run(4)
check("…it's gone: he goes back to the van", danny.action == "wait" and not danny.fleeing)

-- The orders -----------------------------------------------------------------------------------------------------------------

said = #E.said
E.request(sol, "helper", "dance")
check("a wrong order changes nothing", danny.mode == "auto")
E.request(sol, "helper", "carry")
E.request(sol, "helper", "wait")
E.request(sol, "helper", { "van" })
E.request(sol, "helper", 3)
E.request(sol, "helper")
check("8.3 …nor the old ones (carry, wait), nor garbage (a table, a number, nothing)", danny.mode == "auto" and sol:GetAttribute("MoveHelper") == "auto")
local rex = E.player(66, "Rex", outside)
E.request(rex, "helper", "van")
check("8.3 a player who is not on his move: refused (only his crew commands him)", danny.mode == "auto" and rex:GetAttribute("MoveHelper") == nil)
E.leave(rex)
-- 8.3 every command through the server's rate limit (Net.limit "MoveHelper" at Config.Robust.Limits.MoveHelper)
local limits: { any } = {}
local allow = false
local realLimit = E.Net.limit
E.Net.limit = function(player: any, name: string, rate: number): boolean
	table.insert(limits, { player = player, name = name, rate = rate })
	return if name == "MoveHelper" then allow else true
end
E.request(sol, "helper", "van")
local asked = false
for _, l in limits do
	asked = asked or (l.player == sol and l.name == "MoveHelper" and l.rate == Config.Robust.Limits.MoveHelper)
end
check("8.3 each command asks the rate limit (MoveHelper, Config.Robust.Limits.MoveHelper); over it: dropped", asked and danny.mode == "auto"
	and Config.Robust.Limits.MoveHelper == 4)
allow = true
E.request(sol, "helper", "van")
E.Net.limit = realLimit
check("WAIT AT VAN: the order, the strip, his word", danny.mode == "van" and sol:GetAttribute("MoveHelper") == "van" and E.saidSince("Waiting at the van.", said))
-- 8.3 WAIT HERE: where he stands now (out of the doorways)
body.root.CFrame = M.CFrame.new(outside.X + 12, 3, outside.Z + 6)
local stayAt = body.root.Position
E.request(sol, "helper", "stay")
run(4)
check("8.3 WAIT HERE: he stays where he stood when told, the strip says so, his word", danny.mode == "stay" and danny.action == "stay"
	and distance(body.root.Position, stayAt) < 1.5 and sol:GetAttribute("MoveHelper") == "stay" and sol:GetAttribute("MoveHelperDoing") == "Waiting here"
	and E.saidSince("I'll wait right here.", said), distance(body.root.Position, stayAt))
E.request(sol, "helper", "help")
E.place(sol, outside + V3(-3, 0, 0) + facing * 6)
local followed = run(15, function()
	return distance(body.root.Position, E.rootOf(sol).Position) <= H.Follow + 2
end)
check("HELP ME: he follows you", followed and danny.mode == "help" and danny.action == "follow" and sol:GetAttribute("MoveHelperDoing") == "Right behind you")
E.place(sol, outside)
trigger(enter, sol)
local inside = run(15, function()
	return (body.root.Position - origin.Position).Magnitude < 60
end)
check("…through the door too", inside)
-- 8.1 walk-in doors: his door trips go by the players' rule: in facing into the room, out facing away from the door and
-- clear of its reach, not back through a door before Config.Moving.Doors.Rearm s
do
	local cameIn = danny.doorAt
	check("8.1 walk-in doors: he comes in facing into the room, away from the door", body.root.CFrame.LookVector:Dot(V3(0, 0, 1)) > 0.99, body.root.CFrame.LookVector)
	E.place(sol, origin.Position + V3(0, 3, 1))
	trigger(promptIn(workspace, "Leave house"), sol)
	run(math.max(0.1, cameIn + T.Doors.Rearm - 0.4 - E.clock)) -- (past the old 1 s, short of Rearm)
	check("…Sol back out at once: he follows, but not through the door before Rearm s", (body.root.Position - origin.Position).Magnitude < 60
		and E.clock - cameIn > 1.2 and E.clock - cameIn < T.Doors.Rearm, E.clock - cameIn)
	local out = run(4, function()
		return (body.root.Position - origin.Position).Magnitude > 60
	end)
	local through = danny.s.site.outside
	local spot = body.root.Position
	check("…then out, Rearm s after he came in", out and danny.doorAt - cameIn >= T.Doors.Rearm, danny.doorAt - cameIn)
	check("…facing away from the door, clear of its reach (beside where the players come out)", body.root.CFrame.LookVector:Dot(facing) > 0.99
		and distance(spot, through.Position) > H.DoorReach and distance(spot, through.Position) < H.DoorReach + 1.5, distance(spot, through.Position))
	E.place(sol, outside)
	trigger(enter, sol)
	run(15, function()
		return (body.root.Position - origin.Position).Magnitude < 60
	end)
end
E.request(sol, "helper", "auto")
check("AUTO again", danny.mode == "auto" and sol:GetAttribute("MoveHelper") == "auto")
E.Net.get("MoveLobby").OnServerEvent:Fire(sol, "chat", 2)
check("7.0 planning: \"Need a hand here\" in the quick chat calls him over (HELP ME)", danny.mode == "help" and sol:GetAttribute("MoveHelper") == "help")
E.request(sol, "helper", "auto")

-- The van parked far off (driven somewhere else), then back by the house -------------------------------------------------------

local parked = truck.chassis.CFrame
truck.chassis.CFrame = M.CFrame.new(Map.Depot.x - 60, 2, Map.Depot.z)
local stayed = body.root.Position
run(3)
check("the van parked far off, not by the house: he stays where he is (no popping along its way)", distance(body.root.Position, stayed) < 1)
truck.chassis.CFrame = parked
local rejoined = run(20, function()
	return distance(body.root.Position, cargoDoor.WorldPosition) < 8
end)
check("…parked by the house again: he goes to it", rejoined)

-- The crew grows: he goes; Duo ---------------------------------------------------------------------------------------------

local bob = E.player(55, "Bob", outside)
E.crew[sol] = { bob }
Moving.step()
check("a crew of two: Danny heads back (Duo is off)", MoveHelper.find(sol) == nil and npc.Parent == nil and sol:GetAttribute("MoveHelper") == nil
	and string.find(E.lastNotice(sol), "heads back", 1, true) ~= nil)
H.Duo = true
Moving.step()
danny = MoveHelper.find(sol)
check("Duo on: he comes for two as well", danny ~= nil and sol:GetAttribute("MoveHelper") == "auto" and bob:GetAttribute("MoveHelper") == "auto"
	and bob:GetAttribute("MoveHelperId") == danny.id)
H.Duo = false
E.crew[sol] = {}
Moving.step()
danny = MoveHelper.find(sol)
check("Bob left: Danny stays for Sol alone, Bob's strip goes", danny ~= nil and bob:GetAttribute("MoveHelper") == nil and sol:GetAttribute("MoveHelper") == "auto"
	and bob:GetAttribute("MoveHelperId") == nil)
npc = danny.body.model

-- The end ------------------------------------------------------------------------------------------------------------------

Moving.admin(sol, "end")
run(0.2)
check("the move ends: he goes, the strip goes", MoveHelper.find(sol) == nil and npc.Parent == nil and sol:GetAttribute("MoveHelper") == nil
	and sol:GetAttribute("MoveHelperDoing") == nil and sol:GetAttribute("MoveHelperId") == nil)

-- A second move: no room for his piece ----------------------------------------------------------------------------------------

E.place(sol, V3(Map.Depot.x, 3, Map.Depot.z))
local bedHeight = T.Beds[E.carId].Height
T.Beds[E.carId].Height = 1.6 -- (a low bed: the box of memories fits, the lamp never does)
Moving.admin(sol, "start")
T.Beds[E.carId].Height = bedHeight
truck = E.cars[sol]
cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
truck.model:SetAttribute("BackOpen", true)
Moving.step()
danny = MoveHelper.find(sol)
check("the next move: Danny again", danny ~= nil and danny.body ~= nil)
danny.askAgain = math.huge -- (8.3 no ask on this one: his own pieces)
carried = run(40, function()
	return Rules.holding(danny.s.move, danny.id) == 5
end)
check("he goes for the box of memories (★)", carried)
danny.s.move.packing.height = 0.7 -- (the room went while he walked: the box is 1.5 high, the TV 0.8 on its side)
said = #E.said
local refused = run(40, function()
	return E.saidSince("Van's full, boss - drive it to the Wall?", said)
end)
check("no room at the van: \"Van's full, boss - drive it to the Wall?\"", refused)
-- (8.3: the clock is not his alone any more, so the TV he thought fits comes next; it is refused and set down too)
run(40, function()
	return Rules.holding(danny.s.move, danny.id) == nil and danny.action == "wait"
end)
local box = itemModel(5)
check("…the box set down beside the van, not in it", stateNow(5) == "ground" and distance(box.PrimaryPart.Position, cargoDoor.WorldPosition) < 14)
check("…nothing else fits: he waits, the van full", Rules.holding(danny.s.move, danny.id) == nil and stateNow(1) == "home"
	and sol:GetAttribute("MoveHelperDoing") == "Waiting: the van is full", sol:GetAttribute("MoveHelperDoing"))
Moving.admin(sol, "end")
run(0.2)

-- A third move: a van with no room for anything he carries ------------------------------------------------------------------

T.Beds[E.carId].Height = 0.7 -- (lower than any of his pieces, the TV on its side too: Pack.Lie)
said = #E.said
Moving.admin(sol, "start")
T.Beds[E.carId].Height = bedHeight
Moving.step()
danny = MoveHelper.find(sol)
local full = run(8, function()
	return E.saidSince("Van's full, boss - drive it to the Wall?", said)
end)
check("nothing fits: he says so and waits at the van", full and danny.action == "wait" and sol:GetAttribute("MoveHelperDoing") == "Waiting: the van is full"
	and Rules.holding(danny.s.move, danny.id) == nil)
run(H.AskGap + 2)
check("8.3 …and never asks a hand for a heavy piece that does not fit either", danny.ask == nil and danny.action == "wait")
Moving.admin(sol, "end")
run(0.2)

-- 8.3 AUTO's ask for a hand: the ★ marble slab (two people), nobody comes, then Sol does ----------------------------------

local function told(player: any, text: string, from: number): boolean
	for index = from + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) then
			return true
		end
	end
	return false
end
Moving.admin(sol, "start")
truck = E.cars[sol]
cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
truck.model:SetAttribute("BackOpen", true)
Moving.step()
danny = MoveHelper.find(sol)
body = danny.body
npc = body.model
local backAsk = cargoDoor.WorldPosition + V3(0, 0, 2)
E.place(sol, backAsk + V3(30, 0, 0)) -- (out of the way: nobody handles the slab)
local slab = itemModel(6)
local SLAB = E.items.slab.size
local noticeAt = #E.messages
said = #E.said
local askStart = E.clock
local asking = run(40, function()
	return danny.ask ~= nil and danny.askAt > 0
end)
check("8.3 AUTO: the heavy piece nobody handles (the ★ marble slab: two people), AskGap s after he came, he goes to it and asks",
	asking and danny.ask == 6 and danny.action == "ask" and E.clock - askStart >= H.AskGap - 0.15, `{danny.ask} after {E.clock - askStart} s`)
check("…beside it: \"This one's too heavy for me alone, give me a hand!\"", E.saidSince("This one's too heavy for me alone, give me a hand!", said)
	and distance(body.root.Position, slab.PrimaryPart.Position) <= math.max(SLAB.X, SLAB.Z) / 2 + H.PickReach + 0.5)
check("…the crew's toast, the 🙋 marker over it, its prompt \"Lift with Danny\", the strip", told(sol, "Danny needs a hand with the Marble slab", noticeAt)
	and slab.PrimaryPart:FindFirstChild("DannyAsk") ~= nil and promptIn(slab, "Lift with Danny") ~= nil
	and sol:GetAttribute("MoveHelperDoing") == "Needs a hand with the Marble slab", sol:GetAttribute("MoveHelperDoing"))
-- nobody comes: AskWait s, then the light pieces; no new ask before AskAgain s
local askedAt = E.clock
said = #E.said
local gaveUp = run(H.AskWait + 2, function()
	return danny.ask == nil
end)
local endedAt = E.clock
check("…nobody came within AskWait s: \"No takers? I'll grab the small stuff.\", the marker gone, the prompt as ever", gaveUp
	and endedAt - askedAt >= H.AskWait - 0.15 and E.saidSince(Brain.Lines.askOff, said) and slab.PrimaryPart:FindFirstChild("DannyAsk") == nil
	and promptIn(slab, "Lift") ~= nil and promptIn(slab, "Lift with Danny") == nil, endedAt - askedAt)
local light = run(30, function()
	return Rules.holding(danny.s.move, danny.id) ~= nil
end)
local first = Rules.holding(danny.s.move, danny.id)
check("…back to the light pieces (one-hand, or two-hands under LightWeight)", light and first ~= nil and Brain.light(danny.s.move.things[first].class, danny.s.move.things[first].weight), first)
local nagged = false
local again = run(H.AskAgain + 30, function()
	if danny.ask ~= nil and E.clock - endedAt < H.AskAgain - 0.15 then
		nagged = true
	end
	return danny.ask == 6 and danny.askAt > 0
end)
check("…no nagging: AskAgain s later (not sooner) he asks again", again and not nagged and E.clock - endedAt >= H.AskAgain - 0.15, E.clock - endedAt)
-- Sol answers: Lift with Danny at its other end (a call he answers at once); 8.3 with the grip on (Config.CarryGrip.On:
-- the runtime turns it off for the moves' other tests) his "On three... lift!" opens her lift check (the 8.1 grip), a
-- miss lets it slip back down (he waits at its far end), Lift again and its hit: up together; to the van, in
local interior = E.interiors[#E.interiors]
E.place(sol, outside)
trigger(promptIn(site, "Enter house"), sol)
E.place(sol, slab.PrimaryPart.Position + V3(0, 0, SLAB.Z / 2 + 2))
said = #E.said
Config.CarryGrip.On = true
local function gripOpened(from: number): any
	for index = #E.messages, from + 1, -1 do
		local m = E.messages[index]
		if m.player == sol and m.remote == "Moving" and m.kind == "grip" and m.a == "open" then
			return m.b
		end
	end
	return nil
end
local gripFrom = #E.messages
trigger(promptIn(slab, "Lift with Danny"), sol)
check("8.3 Sol answers (\"Lift with Danny\"): a call, his ask over (the marker gone), no lift check yet", danny.call ~= nil and danny.call.spot == 6 and danny.ask == nil
	and slab.PrimaryPart:FindFirstChild("DannyAsk") == nil and sol:GetAttribute("MoveHelperCall") == "Marble slab" and gripOpened(gripFrom) == nil)
local ready = run(8, function()
	return danny.call ~= nil and danny.call.ready
end)
local wire = gripOpened(gripFrom)
check("…he steps to its far end, \"On three... lift!\": Sol's lift check opens (her grip steadied: Danny there), nothing up yet", ready and wire ~= nil
	and wire.what == "lift" and wire.help == false and wire.spot == 6 and sol.Character:GetAttribute("GripSteady") == true
	and sol.Character:GetAttribute("MoveCarry") == nil and E.saidSince("On three... lift!", said) and sol:GetAttribute("MoveHelperReady") == true)
E.now += 0.6
E.request(sol, "grip", wire.id, "miss", 0.5)
run(0.3)
check("…a miss: it slips back down, Danny waits at its far end (the call still on), its prompt Lift again", sol.Character:GetAttribute("MoveCarry") == nil
	and danny.call ~= nil and danny.call.ready and promptIn(slab, "Lift") ~= nil and Rules.holding(danny.s.move, danny.id) == nil)
E.now += Config.CarryGrip.Lift.Again + 0.1
gripFrom = #E.messages
trigger(promptIn(slab, "Lift"), sol)
local retry = gripOpened(gripFrom)
check("…Lift again: a new lift check at once (no new call, no wait)", retry ~= nil and retry.id ~= wire.id and danny.call ~= nil and danny.call.ready)
-- G with the check open: the call off, the check closed (never a lift alone after it)
local closeFrom = #E.messages
E.Net.get("PutDown").OnServerEvent:Fire(sol)
local closed = false
for index = closeFrom + 1, #E.messages do
	local m = E.messages[index]
	closed = closed or (m.player == sol and m.remote == "Moving" and m.kind == "grip" and m.a == "close" and m.b == retry.id)
end
local hitAt = CarryGrip.firstHit(CarryGrip.fromWire(retry) :: any)
E.now += hitAt + 0.08
E.request(sol, "grip", retry.id, "ok", hitAt)
check("…G with its check open: the call off, the check closed, a late hit lifts nothing (no lift alone)", closed and danny.call == nil
	and sol:GetAttribute("MoveHelperCall") == nil and sol:GetAttribute("MoveHelperReady") == nil and sol.Character:GetAttribute("MoveCarry") == nil
	and danny.s.move.things[6].state == "home")
-- Lift once more: a call, he is right there: in place at once, a new check
said = #E.said
gripFrom = #E.messages
trigger(promptIn(slab, "Lift"), sol)
local readyAgain = run(2, function()
	return danny.call ~= nil and danny.call.ready
end)
retry = gripOpened(gripFrom)
check("…Lift once more: a call he answers at once (he is there), \"On three... lift!\", a new check", readyAgain and retry ~= nil and E.saidSince("On three... lift!", said))
hitAt = CarryGrip.firstHit(CarryGrip.fromWire(retry) :: any)
E.now += hitAt + 0.08
E.request(sol, "grip", retry.id, "ok", hitAt)
check("…its hit: up together at once (never dragged alone), Sol leading, Danny at the far end", sol.Character:GetAttribute("MoveCarry") == 6
	and select(2, Rules.holding(danny.s.move, danny.id)) == "helper" and danny.call == nil and sol:GetAttribute("MoveHelperCall") == nil)
Config.CarryGrip.On = false
local function together(): boolean
	return select(2, Rules.holding(danny.s.move, danny.id)) == "helper" and sol.Character:GetAttribute("MoveCarry") == 6
end
follow(slab, sol)
run(0.6)
check("…at its far end", distance(body.root.Position, farEnd(slab, SLAB.Z)) < 0.05, distance(body.root.Position, farEnd(slab, SLAB.Z)))
E.place(sol, interior.Position + V3(0, 3, 1))
follow(slab, sol)
trigger(promptIn(workspace, "Leave house"), sol)
follow(slab, sol)
run(0.2)
worst = walk(slab, backAsk)
check("…out of the door and to the van together", worst < 0.05 and together(), worst)
run(0.2)
trigger(promptIn(truck.model, "Load"), sol)
check("…Sol loads it: the slab in the van, both pairs of hands free", danny.s.move.things[6].state == "truck" and Rules.holding(danny.s.move, danny.id) == nil
	and sol.Character:GetAttribute("MoveCarry") == nil, E.lastNotice(sol))
Moving.admin(sol, "end")
run(0.2)

-- Stuck: a new path after StuckRepath s, a nudge to the way's next point after StuckSnap s -------------------------------------

Moving.admin(sol, "start")
Moving.step()
danny = MoveHelper.find(sol)
danny.askAgain = math.huge -- (8.3 no ask on this one)
local routes: { any } = {}
local spawn = E.task.spawn
E.task.spawn = function(callback: any, ...: any) -- (the path in the background: at once here)
	callback(...)
end
MoveHelper.useMover({
	move = function(b: any, _to: any, speed: number)
		b.walking = true -- (blocked: he goes nowhere)
		lastSpeed = speed
	end,
	halt = function(b: any)
		b.walking = false
	end,
	route = function(_b: any, from: any, to: any): any
		table.insert(routes, from)
		return { from, from + V3(3, 0, 0), to }
	end,
})
local stuckAt = danny.body.root.Position
local repath, nudged = 0, 0
local t = 0
run(5, function()
	t += 0.1
	if repath == 0 and #routes >= 2 then
		repath = t
	end
	if nudged == 0 and distance(danny.body.root.Position, stuckAt) > 2 then
		nudged = t
	end
	return nudged > 0
end)
E.task.spawn = spawn
MoveHelper.useMover(walker)
check("7.x stuck: a new path after StuckRepath (2) s", repath >= H.StuckRepath - 0.15 and repath <= H.StuckRepath + 0.35, repath)
check("…a nudge to his way's next point after StuckSnap (4) s", nudged >= H.StuckSnap - 0.15 and nudged <= H.StuckSnap + 0.35
	and distance(danny.body.root.Position, stuckAt + V3(3, 0, 0)) < 0.05, `{nudged} s at {danny.body.root.Position}`)
Moving.admin(sol, "end")
run(0.2)

-- 7.0 review: his body taken away (by something else) while he carries a piece: it falls, nobody holds it -----------------

Moving.admin(sol, "start")
Moving.step()
danny = MoveHelper.find(sol)
danny.askAgain = math.huge -- (8.3 no ask on this one: his own pieces)
local holds = run(40, function()
	return danny.body ~= nil and Rules.holding(danny.s.move, danny.id) ~= nil
end)
local held = Rules.holding(danny.s.move, danny.id)
check("a fifth move: Danny carries a piece", holds and held ~= nil)
danny.body.model:Destroy()
run(0.5)
check("his body gone: what he held fell (never 'carried' by nobody)", Rules.holding(danny.s.move, danny.id) == nil and held ~= nil
	and danny.s.move.things[held].state == "ground", held and danny.s.move.things[held].state)
E.leave(sol)
run(0.2)
check("the owner leaves: the move and Danny are gone", MoveHelper.find(sol) == nil and E.destroyed == E.built)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
