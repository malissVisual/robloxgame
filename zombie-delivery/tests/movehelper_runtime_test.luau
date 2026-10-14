-- 7.0, the depot's helper ("Danny from the depot"): the real server/Moving.luau and server/MoveHelper.luau in the Luau
-- CLI (tests/run_tests.py builds MovingServer.luau and MoveHelperServer.luau on tests/runtime/MovingRuntime.luau's
-- fakes). The runtime has no physics and no pathfinding: his walk here is a straight step of speed × dt (useMover, no
-- `keep`: carrying together he is put at your piece's far end each step, as the constraints hold him in Roblox), and a
-- carried piece is moved with its carrier by the test (a weld is only a record).
-- 8.3 Danny for hire: a solo move; Danny comes with the van and waits there for hire ("Hire Danny · $100" over his
-- head; the house's 6 pieces: Hire.Min). Not hired: the sofa is dragged alone, no call, he does not come; a click on a
-- piece: "Hire Danny first". HIRE without the money: refused, nothing taken; a stranger's HIRE: nothing; with the
-- money: $100 taken (PlayerData.spend, HelperHire), he works for the move; HIRE again: nothing more taken. Then: the
-- player's Lift on the sofa calls him ("Danny, give me a hand!": no drag alone, the player waits at their end, "Stop
-- waiting" on its prompt) and he WALKS over from the van (through the front door his own way, never faded over), "On
-- three... lift!" at its far end and up it goes with him there (no pause, no snap), turned to the player, his arms on
-- it, the player's grip steadied; he moves with it (a walk that goes nowhere changes nothing: no "too far apart" any
-- more), out through the door; set down; a call stopped (Lift again, G, STOP, walking away); lifted again (he sprints
-- over); the player loads it. A two-hands piece the player carries is theirs (no other side taken). His list: the
-- lamp, the box, the clock clicked (markers 1, 2, 3; a click again takes one back), carried to the van in that order
-- (the clock slower, in both arms), "All done."; the refusals (too far, in the van, held, his list full, not a piece,
-- a stranger, the rate limit); a piece of his list the player picks up leaves it ("All yours, boss."); the van's back
-- (he opens it himself, or, not allowed, asks and sets the piece down after WaitShut s); he opens it for the player
-- coming with a piece; a bite, his death (his piece back on his list) and comeback, running from a zombie; garbage
-- requests, the rate limits, CLEAR QUEUE; his door trips (8.1 walk-in doors); the van parked far off; the crew growing
-- (a hired Danny stays; the crew mate gives him a piece too). Riding with you: the player at the wheel, he walks out of
-- the house round the van (8.5: never over its footprint, though the straight way runs through it) to his spot by
-- the passenger door and gets in as a player does (the seat his, the door swung open, a step to the handle facing the
-- van, the slide in, ducking, posed every frame; BoardSeconds later Seat:Sit, massless, no hold, the door shut; no
-- fade), rides while the van goes, gets out the same way back when the player gets out and the van stands (the door,
-- the slide out to his spot) and goes on with his list; the van driven off without him: RideFar studs off, the last
-- resort fades him into the seat; the van driving off while he gets in: called off (at his spot, the door shut), he
-- goes after it, and in once it stops; the seat taken by a crew mate: he follows on foot; the van wrecked: out at once.
-- The end of the move ends the hire. A second move (for hire again) where the room goes while he carries his piece ("Van's
-- full, boss - drive it to the Wall?": set down beside the van), a third where nothing of his list fits, a fourth with
-- the marble slab (two people) on his list: he waits at it ("needs you", the toast, "Lift with Danny"), long, and the
-- player lifts it with him through the grip's lift check; stuck (a new path, a nudge); his body taken away while he
-- carries; an unhired Danny heads back when the crew grows; a crew mate's hire ends when they leave the move.
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

-- His walk: straight toward the point, speed × dt a step (the last speed asked is kept to check it). 8.5 every fade-in
-- where he was just put (the last resorts: a fade over, a fade into the van's seat) counted.
local lastSpeed = 0
local fades = 0
local walker = {
	appear = function(_body: any)
		fades += 1
	end,
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
local function told(player: any, text: string, from: number): boolean
	for index = from + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) then
			return true
		end
	end
	return false
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
-- 8.3 a click on a piece (its model: the Moving remote's ("helper", "assign", model)) by `who` (Sol), from beside it.
local function give(model: any, who: any?)
	local player = who or sol
	local was = E.rootOf(player).Position
	E.place(player, model.PrimaryPart.Position + V3(3, 0, 0))
	player.Character:SetAttribute("ClipboardHeld", true) -- (8.5 orders mode: the clipboard out, server/Clipboard.luau's)
	E.request(player, "helper", "assign", model)
	E.place(player, was)
end
local function markOf(model: any): string?
	local gui = model.PrimaryPart:FindFirstChild("DannyMark")
	local label = gui and gui:FindFirstChild("Label")
	return if label then label.Text else nil
end
local function listIs(list: { number }): boolean
	if #danny.queue ~= #list then
		return false
	end
	for index, spot in list do
		if danny.queue[index] ~= spot then
			return false
		end
	end
	return true
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

-- Danny comes: for hire ------------------------------------------------------------------------------------------------------

local started = Moving.admin(sol, "start")
check("a solo move starts", string.find(started, "started", 1, true) ~= nil, started)
local truck = E.cars[sol]
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
Moving.step()
danny = MoveHelper.find(sol)
check("8.3 Danny comes with a crew of one: for hire, not working (nobody hired him, nothing on his list)", danny ~= nil and danny.body ~= nil and danny.hirer == nil
	and #danny.queue == 0)
local body = danny.body
local npc = body.model
check("his body: Danny, ZDC Moving, his id in the rules (no player's)", npc.Name == "Danny" and npc:GetAttribute("MoveHelper") == danny.id and danny.id < -1000000
	and body.humanoid.MaxHealth == H.Health and body.humanoid.Health == H.Health)
check("…at the van's back", distance(body.root.Position, cargoDoor.WorldPosition) < 8, distance(body.root.Position, cargoDoor.WorldPosition))
check("he says: Need a hand? Hire me!", E.saidSince("Danny from the depot. Need a hand? Hire me!", 0))
check("the player hears it: he waits by the van for hire ($100)", string.find(E.lastNotice(sol), "waits by your van", 1, true) ~= nil
	and string.find(E.lastNotice(sol), "$100", 1, true) ~= nil, E.lastNotice(sol))
check("8.3 the status line: MoveHelper = offer, the price (6 pieces: Hire.Min, $100), what he does; his id (his card finds his body by it)",
	sol:GetAttribute("MoveHelper") == "offer" and sol:GetAttribute("MoveHelperPrice") == 100 and danny.price == Brain.hirePrice(6) and danny.price == H.Hire.Min
	and sol:GetAttribute("MoveHelperDoing") == "Waiting by the van for hire" and sol:GetAttribute("MoveHelperId") == danny.id and sol:GetAttribute("MoveHelperQueue") == nil
	and sol:GetAttribute("MoveHelperCall") == nil, sol:GetAttribute("MoveHelperDoing"))
local sign = body.root:FindFirstChild("HireSign")
check("8.3 a sign over his head: \"🧑‍🔧 Hire Danny · $100\"", sign ~= nil and sign:FindFirstChild("Label") ~= nil and sign:FindFirstChild("Label").Text == "🧑‍🔧 Hire Danny · $100")
check("his name in the rules' list", MoveHelper.nameOf(danny.id) == "Danny" and MoveHelper.nameOf(44) == nil)
local targets = E.Zombies.extraTargets()
local hunted = false
for _, t in targets do
	if t.humanoid == body.humanoid and t.player == sol then
		hunted = true
	end
end
check("the zombies go after him too (Zombies.extraTargets)", hunted)

-- Not hired: today's rules ---------------------------------------------------------------------------------------------------

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
local character = sol.Character
E.place(sol, sofa.PrimaryPart.Position + V3(0, 0, 3))
trigger(promptIn(sofa, "Lift"), sol)
check("8.3 not hired: the sofa's Lift is today's: dragged alone, no call, nobody waits", character:GetAttribute("MoveCarry") == 3 and danny.call == nil
	and sol:GetAttribute("MoveHelperCall") == nil and not helped())
run(4)
check("…and he does not come to it: he waits by the van for hire", Rules.holding(danny.s.move, danny.id) == nil and distance(body.root.Position, cargoDoor.WorldPosition) < 8)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
local noticeAt = #E.messages
give(sofa)
check("8.3 …a click on a piece: \"Hire Danny first\", nothing on his list", #danny.queue == 0 and told(sol, "Hire Danny first", noticeAt) and sofa:GetAttribute("DannyQueue") == nil)

-- 8.3 the hire -----------------------------------------------------------------------------------------------------------------

E.wallet[sol] = 50
E.request(sol, "helper", "hire")
check("8.3 HIRE without the money ($50 of $100): refused, nothing taken, still for hire", danny.hirer == nil and #E.spent == 0 and E.wallet[sol] == 50
	and E.lastNotice(sol) == "Not enough money: Danny costs $100 for this move." and sol:GetAttribute("MoveHelper") == "offer", E.lastNotice(sol))
local rex = E.player(66, "Rex", outside)
E.request(rex, "helper", "hire")
check("8.3 a player not of the move's crew: nothing (no hire, nothing taken, no word)", danny.hirer == nil and #E.spent == 0 and E.lastNotice(rex) == "")
-- 8.4 (the owner: "Danny always has to be hired, he isn't free"): not hired and far from the van (left at the warehouse),
-- he stays there: he never turns up at the house by himself
body.root.CFrame = body.root.CFrame + V3(0, 0, 400)
run(3)
check("8.4 not hired, left far from the van: he stays (no turning up at the house)", distance(body.root.Position, cargoDoor.WorldPosition) > 300)
E.wallet[sol] = 500
noticeAt = #E.messages
local said = #E.said
E.request(sol, "helper", "hire")
check("8.3 HIRE with the money: $100 taken (PlayerData.spend: HelperHire, the contract's id), he works for the move", danny.hirer == sol and #E.spent == 1
	and E.spent[1].player == sol and E.spent[1].amount == 100 and E.spent[1].reason == "HelperHire" and E.spent[1].sku == "marge" and E.wallet[sol] == 400)
check("…the crew hears it, he says so; the status line: hired, nothing to carry, the price gone; the sign gone", told(sol, "Sol hired Danny for this move ($100)", noticeAt)
	and E.saidSince(Brain.Lines.hired, said) and sol:GetAttribute("MoveHelper") == "hired" and sol:GetAttribute("MoveHelperPrice") == nil
	and sol:GetAttribute("MoveHelperQueue") == 0 and body.root:FindFirstChild("HireSign") == nil)
E.request(sol, "helper", "hire")
check("8.3 once a move: HIRE again takes nothing more", #E.spent == 1 and E.wallet[sol] == 400 and E.lastNotice(sol) == "Danny works for this move already.", E.lastNotice(sol))
E.wallet[sol] = 2000 -- (the moves below hire him again)
run(3, function()
	return distance(body.root.Position, cargoDoor.WorldPosition) < 8
end)
check("8.4 …hired: he comes to the van at the house", distance(body.root.Position, cargoDoor.WorldPosition) < 8)

-- The sofa: lifted together, carried together -------------------------------------------------------------------------------

E.place(sol, sofa.PrimaryPart.Position + V3(0, 0, 3))
said = #E.said
local outsideAt = body.root.Position
trigger(promptIn(sofa, "Lift"), sol)
check("8.3 hired: Lift calls him, no drag alone, Sol waits at her end", character:GetAttribute("MoveCarry") == nil
	and character:GetAttribute("CarrySpeed") == nil and danny.s.move.things[3].state == "ground" and danny.call ~= nil and danny.call.spot == 3
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

-- A two-hands piece you carry is yours (8.3: no other side taken on his own) ------------------------------------------------

local tv = itemModel(2)
E.place(sol, outside)
trigger(enter, sol)
E.place(sol, tv.PrimaryPart.Position + V3(0, 0, 2))
trigger(promptIn(tv, "Pick up"), sol)
follow(tv, sol)
check("Sol picks up the TV (two hands, weight 4) alone", character:GetAttribute("MoveCarry") == 2
	and math.abs((character:GetAttribute("CarrySpeed") or 0) - Rules.carrySpeed(WALK, "both", 4)) < 1e-6, character:GetAttribute("CarrySpeed"))
run(6, function()
	follow(tv, sol)
	return Rules.holding(danny.s.move, danny.id) ~= nil
end)
check("8.3 Danny never takes its other side on his own (nothing on his list: he waits at the van)", Rules.holding(danny.s.move, danny.id) == nil
	and character:GetAttribute("MoveCarry") == 2 and danny.action == "wait")
E.place(sol, origin.Position + V3(0, 3, 1))
follow(tv, sol)
trigger(leave, sol)
follow(tv, sol)
run(0.2)
walk(tv, back)
run(0.2)
trigger(load, sol)
check("…Sol carries it out and loads it alone", danny.s.move.things[2].state == "truck" and character:GetAttribute("MoveCarry") == nil, E.lastNotice(sol))

-- 8.3 his list: the lamp, the box, the clock -----------------------------------------------------------------------------------

E.place(sol, outside)
trigger(enter, sol)
local lamp, box, clock = itemModel(1), itemModel(5), itemModel(4)
-- 8.5 orders mode: without the clipboard out (its ClipboardHeld, server/Clipboard.luau's) the click gives him nothing
noticeAt = #E.messages
sol.Character:SetAttribute("ClipboardHeld", nil)
E.place(sol, lamp.PrimaryPart.Position + V3(3, 0, 0))
E.request(sol, "helper", "assign", lamp)
check("8.5 a click on the Lamp with the clipboard away: not on his list, \"📋 Take out your clipboard (Q)\"", #danny.queue == 0 and lamp:GetAttribute("DannyQueue") == nil
	and told(sol, "📋 Take out your clipboard (Q) to give Danny pieces.", noticeAt), E.lastNotice(sol))
noticeAt = #E.messages
said = #E.said
give(lamp)
give(box)
give(clock)
check("8.3 a click on the Lamp, the Box, the Clock: on his list in that order, a toast each, his word", listIs({ 1, 5, 4 }) and told(sol, "Danny will take the Lamp.", noticeAt)
	and told(sol, "Danny will take the Box of memories.", noticeAt) and told(sol, "Danny will take the Grandpa's Clock.", noticeAt) and E.saidSince(Brain.Lines.queued, said))
check("…a marker over each with its number (DannyMark), the pieces' DannyQueue", markOf(lamp) == "🧑‍🔧 Danny · 1" and markOf(box) == "🧑‍🔧 Danny · 2"
	and markOf(clock) == "🧑‍🔧 Danny · 3" and lamp:GetAttribute("DannyQueue") == 1 and clock:GetAttribute("DannyQueue") == 3
	and lamp.PrimaryPart:FindFirstChild("DannyMark").AlwaysOnTop == true, markOf(lamp))
check("…the status line: 3 pieces to carry", sol:GetAttribute("MoveHelperQueue") == 3)
noticeAt = #E.messages
give(lamp)
check("8.3 a click on the Lamp again: off his list (\"Danny leaves the Lamp to you.\"), its marker gone, the box's number 1", listIs({ 5, 4 })
	and told(sol, "Danny leaves the Lamp to you.", noticeAt) and markOf(lamp) == nil and lamp:GetAttribute("DannyQueue") == nil and markOf(box) == "🧑‍🔧 Danny · 1")
give(lamp)
check("…and on again, last", listIs({ 5, 4, 1 }) and markOf(lamp) == "🧑‍🔧 Danny · 3")
sol.Character:SetAttribute("ClipboardHeld", nil)
E.place(sol, lamp.PrimaryPart.Position + V3(3, 0, 0))
E.request(sol, "helper", "assign", lamp)
check("8.5 …a click on it with the clipboard away: still on his list (no stray take-back)", listIs({ 5, 4, 1 }) and markOf(lamp) == "🧑‍🔧 Danny · 3")
sol.Character:SetAttribute("ClipboardHeld", true)
E.place(sol, back + V3(30, 0, 0)) -- (out of the way)
local loadedAt: { [number]: number } = {}
local clockSpeed = 0
local loadShown = false
local n = 0
local arms: any = nil
local function look()
	n += 1
	local spot, role = Rules.holding(danny.s.move, danny.id)
	loadShown = loadShown or (spot ~= nil and role == "carrier" and load.Enabled)
	if spot == 4 and role == "carrier" and danny.action == "deliver" then
		clockSpeed = lastSpeed
		arms = arms or { npc:GetAttribute("Carrying"), npc:GetAttribute("CarryHands") }
	end
	for _, s in { 1, 4, 5 } do
		if stateNow(s) == "truck" and not loadedAt[s] then
			loadedAt[s] = n
		end
	end
end
said = #E.said
run(300, function()
	look()
	return loadedAt[1] ~= nil and loadedAt[4] ~= nil and loadedAt[5] ~= nil
end)
check("8.3 he carries his list to the van and loads it, in its order: the box, the clock, the lamp", loadedAt[1] ~= nil and loadedAt[4] ~= nil and loadedAt[5] ~= nil
	and loadedAt[5] < loadedAt[4] and loadedAt[4] < loadedAt[1], `{loadedAt[5]} {loadedAt[4]} {loadedAt[1]}`)
check("…Grandpa's Clock (two hands, weight 6) at 0.7 × a player's two-hands walk, in both arms", math.abs(clockSpeed - Rules.carrySpeed(WALK, "both", 6) * 0.7) < 1e-6
	and arms ~= nil and arms[1] == "furniture" and arms[2] == 2, clockSpeed)
check("…the van's Load prompt stays off for what he carries (the back's own E stays free)", not loadShown)
check("Sol hears what he loaded", told(sol, "Danny loaded", 0))
check("…each off his list as he took it, the markers gone", #danny.queue == 0 and markOf(lamp) == nil and markOf(clock) == nil and markOf(box) == nil
	and sol:GetAttribute("MoveHelperQueue") == 0)
run(3)
check("…his list empty: \"All done. Anything else, boss?\", he waits at the van, the marble slab (not his) untouched", E.saidSince(Brain.Lines.empty, said)
	and danny.action == "wait" and sol:GetAttribute("MoveHelperDoing") == "Waiting at the van" and distance(body.root.Position, cargoDoor.WorldPosition) < 8
	and stateNow(6) == "home", sol:GetAttribute("MoveHelperDoing"))

-- 8.3 the refusals ----------------------------------------------------------------------------------------------------------------

local slab = itemModel(6)
noticeAt = #E.messages
E.request(sol, "helper", "assign", slab) -- (Sol by the van, the slab in the house: another world)
check("8.3 a piece out of sight (Sol outside, the slab inside): \"Get closer\", not on his list", #danny.queue == 0 and told(sol, "Get closer to the Marble slab", noticeAt))
noticeAt = #E.messages
give(lamp)
check("…a piece in the van: \"The Lamp is in the van already.\"", #danny.queue == 0 and told(sol, "The Lamp is in the van already.", noticeAt))
local unload = promptIn(truck.model, "Take out")
E.place(sol, back)
trigger(unload, sol)
check("Sol takes the lamp back out", character:GetAttribute("MoveCarry") == 1, E.lastNotice(sol))
noticeAt = #E.messages
E.request(sol, "helper", "assign", lamp)
check("…a piece somebody holds: \"Somebody holds the Lamp.\"", #danny.queue == 0 and told(sol, "Somebody holds the Lamp.", noticeAt))
E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
local queueMost = H.Queue
H.Queue = 1
give(lamp)
noticeAt = #E.messages
give(slab)
check("…his list full (Queue: 1 here): \"Danny's list is full\", not on it", listIs({ 1 }) and told(sol, "Danny's list is full", noticeAt))
H.Queue = queueMost
give(lamp)
check("…(the lamp off again)", #danny.queue == 0)
E.request(sol, "helper", "assign", truck.model)
E.request(sol, "helper", "assign", 3)
E.request(sol, "helper", "assign", "Lamp")
E.request(sol, "helper", "assign")
E.request(sol, "helper", "assign", { lamp })
check("8.3 not a piece (the van, a number, a name, nothing, a table): nothing", #danny.queue == 0)
noticeAt = #E.messages
give(lamp, rex)
check("8.3 a player not of the move's crew: nothing (no word)", #danny.queue == 0 and not told(rex, "Danny", noticeAt))
local limits: { any } = {}
local allow = false
local realLimit = E.Net.limit
E.Net.limit = function(player: any, name: string, rate: number): boolean
	table.insert(limits, { player = player, name = name, rate = rate })
	return if name == "MoveHelperAssign" then allow else true
end
give(lamp)
local asked = false
for _, l in limits do
	asked = asked or (l.player == sol and l.name == "MoveHelperAssign" and l.rate == Config.Robust.Limits.MoveHelperAssign)
end
check("8.3 every click asks its rate limit (MoveHelperAssign, Config.Robust.Limits.MoveHelperAssign); over it: dropped", asked and #danny.queue == 0
	and Config.Robust.Limits.MoveHelperAssign == 5)
E.Net.limit = realLimit

-- 8.3 a piece of his list you pick up yourself leaves it ---------------------------------------------------------------------

give(lamp)
check("8.3 the lamp on his list", listIs({ 1 }) and markOf(lamp) == "🧑‍🔧 Danny · 1")
E.place(sol, lamp.PrimaryPart.Position + V3(2, 0, 0))
noticeAt = #E.messages
said = #E.said
trigger(promptIn(lamp, "Pick up"), sol)
check("8.3 Sol picks it up first: off his list (\"You took the Lamp: off Danny's list.\", \"All yours, boss.\"), its marker gone", character:GetAttribute("MoveCarry") == 1
	and #danny.queue == 0 and told(sol, "You took the Lamp: off Danny's list.", noticeAt) and E.saidSince("All yours, boss.", said) and markOf(lamp) == nil
	and lamp:GetAttribute("DannyQueue") == nil and sol:GetAttribute("MoveHelperQueue") == 0)
run(2)
check("…and he leaves it to Sol", Rules.holding(danny.s.move, danny.id) == nil and character:GetAttribute("MoveCarry") == 1)

-- The van's back: he opens it himself; not allowed, he asks --------------------------------------------------------------------

E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, back + V3(30, 0, 0))
truck.model:SetAttribute("BackOpen", false)
give(lamp)
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
give(lamp)
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
check("…and leaves it there while the back stays shut (off his list: he had taken it)", Rules.holding(danny.s.move, danny.id) == nil and stateNow(1) == "ground"
	and #danny.queue == 0)
H.OpenBack = true
truck.model:SetAttribute("BackOpen", true)
give(lamp)
inAgain = run(20, function()
	return stateNow(1) == "truck"
end)
check("the back open, the lamp given again: he takes it in", inAgain)

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

-- Down and back up -----------------------------------------------------------------------------------------------------------

E.place(sol, back)
trigger(unload, sol)
E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, back + V3(30, 0, 0))
give(lamp)
carried = run(15, function()
	return Rules.holding(danny.s.move, danny.id) == 1
end)
check("he picks the lamp up again (his list's)", carried and #danny.queue == 0)
danny.s.move.things[1].condition = 1 -- (as good as new again: the bites and this fall would break it)
local before = 1
said = #E.said
body.humanoid.Health = 0
body.humanoid.HealthChanged:Fire(0)
run(0.3)
check("killed: the lamp falls, knocked", stateNow(1) == "ground" and stateOf(1).condition < before - 0.1 and Rules.holding(danny.s.move, danny.id) == nil, stateOf(1).condition)
check("…he is down (\"I'll be back!\"), the player hears it", danny.dead and E.saidSince("Ugh... I'll be back!", said)
	and string.find(E.lastNotice(sol), "Danny is down", 1, true) ~= nil and sol:GetAttribute("MoveHelperDoing") == "Down: back at the van soon")
check("8.3 …the lamp back at the head of his list (he finishes it when he is back)", listIs({ 1 }) and markOf(lamp) == "🧑‍🔧 Danny · 1")
run(3.2)
check("…his body goes a moment later", npc.Parent == nil and danny.body == nil)
local backUp = run(H.Respawn, function()
	return danny.body ~= nil
end)
check("Respawn s later he is back at the van", backUp and not danny.dead and distance(danny.body.root.Position, cargoDoor.WorldPosition) < 8 and E.saidSince("Back on my feet!", said))
body = danny.body
npc = body.model
check("8.3 …still hired: no sign over his head", danny.hirer == sol and body.root:FindFirstChild("HireSign") == nil)
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

-- 8.3 the requests: garbage, the rate limit, CLEAR QUEUE ---------------------------------------------------------------------

said = #E.said
local spentBefore = #E.spent
for _, kind in { "dance", "auto", "help", "stay", "van", "carry", 3 } do
	E.request(sol, "helper", kind)
end
E.request(sol, "helper")
E.request(sol, "helper", { "hire" })
check("8.3 the old orders and garbage change nothing (AUTO, HELP ME, WAIT HERE, WAIT AT VAN: gone)", danny.hirer == sol and #danny.queue == 0
	and #E.spent == spentBefore and sol:GetAttribute("MoveHelper") == "hired")
limits = {}
allow = false
E.Net.limit = function(player: any, name: string, rate: number): boolean
	table.insert(limits, { player = player, name = name, rate = rate })
	return if name == "MoveHelper" then allow else true
end
give(slab)
E.request(sol, "helper", "clear")
asked = false
for _, l in limits do
	asked = asked or (l.player == sol and l.name == "MoveHelper" and l.rate == Config.Robust.Limits.MoveHelper)
end
check("8.3 HIRE, CLEAR QUEUE and STOP ask their rate limit (MoveHelper, Config.Robust.Limits.MoveHelper); over it: dropped", asked and listIs({ 6 })
	and Config.Robust.Limits.MoveHelper == 4)
allow = true
noticeAt = #E.messages
E.request(sol, "helper", "clear")
E.Net.limit = realLimit
check("8.3 CLEAR QUEUE: his list empty, the markers gone, \"Okay, my list is empty.\", the crew told", #danny.queue == 0 and markOf(slab) == nil
	and E.saidSince(Brain.Lines.cleared, said) and told(sol, "Sol cleared Danny's list", noticeAt) and sol:GetAttribute("MoveHelperQueue") == 0)
E.request(sol, "helper", "clear")
check("…again: \"Danny's list is empty already.\"", E.lastNotice(sol) == "Danny's list is empty already.")
E.Net.get("MoveLobby").OnServerEvent:Fire(sol, "chat", 2)
check("7.0 planning: \"Need a hand here\" in the quick chat no longer orders him about (8.3)", danny.hirer == sol and #danny.queue == 0 and danny.action ~= "follow")
-- 8.1 walk-in doors: his door trips go by the players' rule: in facing into the room, out facing away from the door and
-- clear of its reach, not back through a door before Config.Moving.Doors.Rearm s (8.3: the slab given, then his list
-- cleared)
do
	give(slab)
	local inside = run(20, function()
		return (body.root.Position - origin.Position).Magnitude < 60
	end)
	local cameIn = danny.doorAt
	check("8.3 the slab on his list: he goes in to it", inside and listIs({ 6 }))
	check("8.1 walk-in doors: he comes in facing into the room, away from the door", body.root.CFrame.LookVector:Dot(V3(0, 0, 1)) > 0.99, body.root.CFrame.LookVector)
	E.request(sol, "helper", "clear")
	run(math.max(0.1, cameIn + T.Doors.Rearm - 0.4 - E.clock)) -- (past the old 1 s, short of Rearm)
	check("…his list cleared at once: back out to the van, but not through the door before Rearm s", (body.root.Position - origin.Position).Magnitude < 60
		and E.clock - cameIn > 1.2 and E.clock - cameIn < T.Doors.Rearm, E.clock - cameIn)
	local out = run(4, function()
		return (body.root.Position - origin.Position).Magnitude > 60
	end)
	local through = danny.s.site.outside
	local spot = body.root.Position
	check("…then out, Rearm s after he came in", out and danny.doorAt - cameIn >= T.Doors.Rearm, danny.doorAt - cameIn)
	check("…facing away from the door, clear of its reach (beside where the players come out)", body.root.CFrame.LookVector:Dot(facing) > 0.99
		and distance(spot, through.Position) > H.DoorReach and distance(spot, through.Position) < H.DoorReach + 1.5, distance(spot, through.Position))
end
run(20, function()
	return distance(body.root.Position, cargoDoor.WorldPosition) < 8
end)

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

-- The crew grows: a hired Danny stays ----------------------------------------------------------------------------------------

local bob = E.player(55, "Bob", outside)
E.crew[sol] = { bob }
Moving.step()
check("8.3 a crew of two: a hired Danny stays (paid for the move; Duo off), Bob gets his status line too", MoveHelper.find(sol) == danny and npc.Parent ~= nil
	and bob:GetAttribute("MoveHelper") == "hired" and bob:GetAttribute("MoveHelperId") == danny.id and sol:GetAttribute("MoveHelper") == "hired")
E.place(bob, outside)
trigger(enter, bob)
noticeAt = #E.messages
give(slab, bob)
check("8.3 …Bob, of the crew, gives him a piece too", listIs({ 6 }) and told(bob, "Danny will take the Marble slab.", noticeAt))

-- 8.3 riding with you (8.5: round the van to its door, in and out as a player gets in and out) ---------------------------
-- (a do-block: its locals end with it; the test's top level is at the 200-register limit)
do
	local seat = truck.passengers[1]
	local halfX, halfZ = truck.size.X / 2, truck.size.Z / 2
	local CARGO = Config.Cargo
	local heartbeat = E.services.RunService.Heartbeat
	-- 8.5 his root in the van's frame (+X the passenger's side, -Z its front) and his heading there; his body over the
	-- van's footprint (a stud round his root; the house's interior is far off); at his spot by the passenger door
	-- (RideStand studs out of the van's right side where its seat is, `aside` more); the passenger door's swings since
	-- `from` (Vehicles.swingDoor); is a per-frame pose hooked (RunService.Heartbeat)?
	local function inVan(): any
		return truck.chassis.CFrame:PointToObjectSpace(body.root.Position)
	end
	local function lookInVan(): any
		return truck.chassis.CFrame:ToObjectSpace(body.root.CFrame).LookVector
	end
	local function onVan(): boolean
		local rel = inVan()
		return math.abs(rel.X) < halfX + 1 and math.abs(rel.Z) < halfZ + 1 and math.abs(rel.Y) < 20
	end
	local function atSpot(aside: number?): boolean
		local rel = inVan()
		return math.abs(rel.X - (halfX + H.RideStand + (aside or 0))) < 0.3 and math.abs(rel.Z + 3) < 0.3
	end
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
	local function hooked(): boolean
		for _, handler in heartbeat.handlers do
			if handler.on then
				return true
			end
		end
		return false
	end
	local inHouse = run(20, function()
		return (body.root.Position - origin.Position).Magnitude < 60 and danny.needs == 6 and danny.needsAt > 0
	end)
	check("8.3 (the slab: he is in the house, waiting at it for you)", inHouse and slab:GetAttribute("DannyNeeds") == true and markOf(slab) == "🙋 Danny needs you")
	E.place(sol, truck.chassis.Position + V3(-5, 1, -3))
	E.seated[sol] = truck
	said = #E.said
	local swingsAt, fadesAt = #E.doorSwings, fades
	local walkedOut, longestRide, rideAt, overVan = 0, 0, body.root.Position, 0
	local cameOut: any = nil
	local started = run(40, function()
		local now = body.root.Position
		if (now - rideAt).Magnitude > 300 then
			walkedOut += 1
			cameOut = inVan()
		else
			longestRide = math.max(longestRide, distance(now, rideAt))
		end
		rideAt = now
		if danny.board == nil and onVan() then
			overVan += 1
		end
		return danny.board ~= nil or danny.seat ~= nil
	end)
	local b0 = danny.board
	local startRel = inVan()
	check("8.5 Sol at the van's wheel: Danny leaves the slab, walks out of the house to his spot by the passenger door (RideStand out of its side)",
		started and b0 ~= nil and not b0.out and math.abs(startRel.X - (halfX + H.RideStand)) <= H.RideReach + 1e-6 and math.abs(startRel.Z + 3) <= H.RideReach + 1e-6
		and E.saidSince(Brain.Lines.ride, said), `{startRel.X} {startRel.Z}`)
	local straightOver = false -- (the straight way from where he came out of the house to his spot)
	for k = 0, 200 do
		local x = cameOut.X + (halfX + H.RideStand - cameOut.X) * k / 200
		local z = cameOut.Z + (-3 - cameOut.Z) * k / 200
		straightOver = straightOver or (math.abs(x) < halfX and math.abs(z) < halfZ)
	end
	check("…round the van, never over its footprint (the straight way from the house's door runs through it), each step his sprint's at most",
		straightOver and overVan == 0 and walkedOut == 1 and longestRide <= WALK * H.Sprint * 0.1 + 1e-6, `{straightOver} {overVan} {walkedOut} {longestRide}`)
	check("…no fade into the seat (it's his last resort only)", fades == fadesAt and danny.seat == nil and seat.Occupant == nil)
	local doorIn = swingsSince(swingsAt)[1]
	check("8.5 he gets in as a player does: the seat his meanwhile (Reserved: nobody else's boarding takes it), the passenger door swung for everybody: open as his hand reaches the handle, shut as he sits",
		b0 ~= nil and seat:GetAttribute("Reserved") == danny.id and #swingsSince(swingsAt) == 1 and doorIn.openAt ~= nil
		and math.abs(doorIn.openAt - doorIn.now - CARGO.BoardStepSeconds * 0.7) < 1e-6 and math.abs(doorIn.closeAt - doorIn.now - CARGO.BoardSeconds) < 1e-6
		and sol:GetAttribute("MoveHelperDoing") == "Getting in the van", sol:GetAttribute("MoveHelperDoing"))
	check("…his pose every frame meanwhile (Heartbeat hooked)", hooked())
	-- (his frames: os.clock is the test's; the Heartbeat poses him where his move is now)
	E.clock = b0.at + CARGO.BoardStepSeconds
	heartbeat:Fire(1 / 60)
	local handle, handleLook = inVan(), lookInVan()
	check("…a step to the door's handle (DoorStandOut out of the van's side), facing the van", math.abs(handle.X - (halfX + CARGO.DoorStandOut)) < 0.01
		and math.abs(handle.Z + 3) < 0.01 and handleLook.X < -0.99, `{handle.X} {handleLook.X}`)
	E.clock = b0.at + (CARGO.BoardStepSeconds + CARGO.BoardSeconds) / 2
	heartbeat:Fire(1 / 60)
	local through, throughLook = inVan(), lookInVan()
	check("…then the slide in through the door: halfway, between the handle and the seat, over the step's height, ducking", through.X < handle.X - 0.5
		and through.X > 1.4 + 0.3 and through.Y > handle.Y and throughLook.Y < -0.05 and danny.seat == nil, `{through.X} {through.Y} {throughLook.Y}`)
	local slideX, slid = through.X, true
	local seated = run(2, function()
		local x = inVan().X
		if danny.seat == nil and x > slideX + 1e-6 then
			slid = false -- (never back out on the way in)
		end
		slideX = x
		return danny.seat ~= nil
	end)
	check("8.3 …and BoardSeconds after his move began he sits (Seat:Sit)", seated and danny.seat == seat and seat.Occupant == body.humanoid and body.humanoid.SeatPart == seat
		and body.humanoid.Sit == true and seat:FindFirstChild("SeatWeld") ~= nil and E.clock - b0.at >= CARGO.BoardSeconds - 1e-6 and E.clock - b0.at <= CARGO.BoardSeconds + 0.1 + 1e-6
		and slid, E.clock - b0.at)
	local seatRel = inVan()
	check("8.5 …the order: the door opened, he sat, the door shut (the slide ends at the seat; the seat's reservation gone, no frame hook left, no fade)",
		doorIn.openAt - doorIn.now < E.clock - b0.at and doorIn.closeAt - doorIn.now >= CARGO.BoardSeconds - 1e-6 and math.abs(seatRel.X - 1.4) < 0.01
		and math.abs(seatRel.Z + 3) < 0.01 and seat:GetAttribute("Reserved") == nil and not hooked() and danny.board == nil and fades == fadesAt, `{seatRel.X} {seatRel.Z}`)
	run(0.3)
	local massless = true
	for _, d in npc:GetDescendants() do
		if d.ClassName == "Part" and d.Massless ~= true then
			massless = false
		end
	end
	check("…seated: massless (the van drives as ever), no hold (no constraints, no Npcs.carried), the status line: Riding in the van",
		massless and body.grip == nil and danny.gripped == nil and sol:GetAttribute("MoveHelperDoing") == "Riding in the van")
	check("…the slab still his (the marker back to its number: he is not at it)", listIs({ 6 }) and slab:GetAttribute("DannyNeeds") == nil and markOf(slab) == "🧑‍🔧 Danny · 1")
	truck.speed = 40
	local rode = body.root.Position
	run(3)
	check("8.3 the van drives: he rides (nothing of his own: the van carries him)", danny.seat == seat and danny.action == "seat" and (body.root.Position - rode).Magnitude < 1e-6)
	E.seated[sol] = nil
	run(1)
	check("…Sol out of the seat while the van still rolls: he stays in", danny.seat == seat)
	truck.speed = 0
	said = #E.said
	swingsAt = #E.doorSwings
	run(0.1)
	local b1 = danny.board
	local doorOut = swingsSince(swingsAt)[1]
	check("8.5 the van stands, nobody at its wheel: he gets out as a player does (the seat free at once, the passenger door open now and shut AlightSeconds later)",
		b1 ~= nil and b1.out and danny.seat == nil and seat.Occupant == nil and seat:FindFirstChild("SeatWeld") == nil and body.humanoid.Sit == false
		and doorOut ~= nil and doorOut.openAt == doorOut.now and math.abs(doorOut.closeAt - doorOut.now - (CARGO.AlightSeconds + 0.05)) < 1e-6
		and sol:GetAttribute("MoveHelperDoing") == "Getting out of the van" and hooked(), sol:GetAttribute("MoveHelperDoing"))
	E.clock = b1.at + CARGO.AlightSeconds / 2
	heartbeat:Fire(1 / 60)
	local halfway = inVan()
	check("…the slide out through the door (halfway: between the seat and his spot, over the seat's height)", halfway.X > 1.4 + 0.3
		and halfway.X < halfX + H.RideStand - 0.3 and halfway.Y > seatRel.Y, `{halfway.X} {halfway.Y}`)
	local outAt = b1.at
	run(1, function()
		return danny.board == nil
	end)
	local outLook = lookInVan()
	check("8.3 …and on his feet at his spot by the door (where he got in), facing away from the van, his body as before (not massless), AlightSeconds after",
		danny.board == nil and atSpot() and outLook.X > 0.5 and npc:FindFirstChild("HumanoidRootPart").Massless == false and body.weights == nil
		and E.clock - outAt >= CARGO.AlightSeconds - 1e-6 and not hooked() and fades == fadesAt, `{inVan().X} {inVan().Z} {outLook.X}`)
	local back2 = run(20, function()
		return (body.root.Position - origin.Position).Magnitude < 60
	end)
	check("…and goes on with his list (the slab: back into the house)", back2 and E.saidSince(Brain.Lines.out, said) and listIs({ 6 }))
	-- Sol drives off with him left behind (40 studs a second, faster than his sprint): he walks after the van, and once it
	-- is RideFar studs or more off on foot (8.5: the last resort, not his patience) he fades into the seat
	local parkedAt = truck.chassis.CFrame
	E.seated[sol] = truck
	truck.speed = 40
	local fadeAt = E.clock
	local walkedAfter = 0
	fadesAt = fades
	local faded = run(H.RideBlink + 3, function()
		truck.chassis.CFrame = truck.chassis.CFrame * M.CFrame.new(4, 0, 0)
		if danny.action == "ride" and danny.seat == nil then
			walkedAfter += 1
		end
		return danny.seat ~= nil
	end)
	check("8.3 the van drives off with him left behind: he goes after it, and once it is RideFar studs off (the last resort) he fades into the seat",
		faded and danny.seat == seat and walkedAfter > 10 and fades == fadesAt + 1 and E.clock - fadeAt < H.RideBlink, E.clock - fadeAt)
	truck.chassis.CFrame = parkedAt
	truck.speed = 0
	E.seated[sol] = nil
	run(1, function()
		return danny.seat == nil and danny.board == nil
	end)
	check("…the van back and standing, Sol out: he gets out again (at his spot)", danny.seat == nil and danny.board == nil and atSpot())
	-- 8.5 the van drives off while he gets in: his move is called off (on his feet at his spot, the seat free, the door
	-- shut), he goes after it on foot; it stops, and in he gets
	E.seated[sol] = truck
	started = run(10, function()
		return danny.board ~= nil
	end)
	run(0.2)
	swingsAt, fadesAt = #E.doorSwings, fades
	truck.speed = CARGO.BoardMaxSpeed + 4
	run(0.1)
	local shut = swingsSince(swingsAt)[1]
	check("8.5 the van drives off while he gets in: called off at once (on his feet at his spot outside the van, the seat free and his no more, its door shut from then)",
		started and danny.board == nil and danny.seat == nil and seat.Occupant == nil and seat:GetAttribute("Reserved") == nil and atSpot() and shut ~= nil
		and shut.openAt == nil and shut.closeAt == shut.now and not hooked(), inVan())
	local followed, overWhile = 0, 0
	run(2, function()
		truck.chassis.CFrame = truck.chassis.CFrame * M.CFrame.new(0, 0, -1.2)
		if danny.action == "ride" and danny.seat == nil and danny.board == nil then
			followed += 1
		end
		if onVan() then
			overWhile += 1
		end
		return false
	end)
	check("…the van rolling on (12 studs a second, over BoardMaxSpeed): he goes after it on foot beside it, never in, never over it, no fade", followed >= 15
		and danny.seat == nil and overWhile == 0 and fades == fadesAt and distance(body.root.Position, truck.chassis.Position) < halfZ + H.RideStand + 2, followed)
	truck.speed = 0
	seated = run(10, function()
		return danny.seat ~= nil
	end)
	check("…it stops: in he gets (his move again: the door, the slide, the seat), no fade", seated and danny.seat == seat and #swingsSince(swingsAt) >= 2 and fades == fadesAt)
	E.seated[sol] = nil
	run(1, function()
		return danny.seat == nil and danny.board == nil
	end)
	-- the passenger seat taken by a crew mate (Bob): he follows the van on foot
	E.place(bob, truck.chassis.Position + V3(5, 1, -3))
	seat:Sit(bob.Character:FindFirstChildOfClass("Humanoid"))
	E.seated[sol] = truck
	overVan = 0
	run(25, function()
		if onVan() then
			overVan += 1
		end
		return danny.action == "ride" and distance(body.root.Position, cargoDoor.WorldPosition) < 8
	end)
	check("8.3 the seat taken by Bob: Danny never sits (he goes to the van's back on foot; 8.5 round it)", danny.seat == nil and danny.action == "ride" and seat.Occupant ~= body.humanoid
		and distance(body.root.Position, cargoDoor.WorldPosition) < 8 and overVan == 0, distance(body.root.Position, cargoDoor.WorldPosition))
	seat:FindFirstChild("SeatWeld"):Destroy()
	seated = run(10, function()
		return danny.seat ~= nil
	end)
	check("…Bob out of it: he gets in", seated and danny.seat == seat)
	truck.wrecked = true
	run(0.3)
	check("8.3 the van wrecked: out at once", danny.seat == nil and seat.Occupant == nil and body.humanoid.Sit == false)
	truck.wrecked = false
	E.seated[sol] = nil
	E.crew[sol] = {}
	Moving.step()
	danny = MoveHelper.find(sol)
	check("Bob left: Danny stays for Sol, Bob's strip goes", danny ~= nil and bob:GetAttribute("MoveHelper") == nil and sol:GetAttribute("MoveHelper") == "hired"
		and bob:GetAttribute("MoveHelperId") == nil)
	npc = danny.body.model
end

-- The end ------------------------------------------------------------------------------------------------------------------

Moving.admin(sol, "end")
run(0.2)
check("the move ends: the hire with it, he goes, the strip goes, his marker off the slab", MoveHelper.find(sol) == nil and npc.Parent == nil and sol:GetAttribute("MoveHelper") == nil
	and sol:GetAttribute("MoveHelperDoing") == nil and sol:GetAttribute("MoveHelperId") == nil and sol:GetAttribute("MoveHelperQueue") == nil and markOf(slab) == nil)

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
check("8.3 the next move: Danny again, for hire again (the end of the last one ended its hire)", danny ~= nil and danny.body ~= nil and danny.hirer == nil
	and sol:GetAttribute("MoveHelper") == "offer")
local spent = #E.spent
E.request(sol, "helper", "hire")
check("…hired for this one: its price taken again", danny.hirer == sol and #E.spent == spent + 1)
E.place(sol, outside)
trigger(promptIn(workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge"), "Enter house"), sol)
give(itemModel(1))
give(itemModel(5))
E.place(sol, cargoDoor.WorldPosition + V3(30, 0, 0))
carried = run(40, function()
	return Rules.holding(danny.s.move, danny.id) == 5
end)
check("8.3 the lamp never fits the low bed: he skips it for the next of his list (the box of memories)", carried and listIs({ 1 }))
danny.s.move.packing.height = 0.7 -- (the room went while he walked: the box is 1.5 high)
said = #E.said
local refused = run(40, function()
	return E.saidSince("Van's full, boss - drive it to the Wall?", said)
end)
check("no room at the van: \"Van's full, boss - drive it to the Wall?\"", refused)
run(40, function()
	return Rules.holding(danny.s.move, danny.id) == nil and danny.action == "wait"
end)
box = itemModel(5)
check("…the box set down beside the van, not in it", stateNow(5) == "ground" and distance(box.PrimaryPart.Position, cargoDoor.WorldPosition) < 14)
check("…nothing of his list fits: he waits, the van full", Rules.holding(danny.s.move, danny.id) == nil and stateNow(1) == "home" and listIs({ 1 })
	and sol:GetAttribute("MoveHelperDoing") == "Waiting: the van is full", sol:GetAttribute("MoveHelperDoing"))
Moving.admin(sol, "end")
run(0.2)

-- A third move: a van with no room for anything of his list ---------------------------------------------------------------------

T.Beds[E.carId].Height = 0.7 -- (lower than any of his pieces, the TV on its side too: Pack.Lie)
Moving.admin(sol, "start")
T.Beds[E.carId].Height = bedHeight
Moving.step()
danny = MoveHelper.find(sol)
E.request(sol, "helper", "hire")
E.place(sol, outside)
trigger(promptIn(workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge"), "Enter house"), sol)
give(itemModel(1))
give(itemModel(2))
E.place(sol, outside)
said = #E.said
local full = run(8, function()
	return E.saidSince("Van's full, boss - drive it to the Wall?", said)
end)
check("nothing of his list fits: he says so and waits at the van", full and danny.action == "wait" and sol:GetAttribute("MoveHelperDoing") == "Waiting: the van is full"
	and Rules.holding(danny.s.move, danny.id) == nil and listIs({ 1, 2 }))
Moving.admin(sol, "end")
run(0.2)

-- 8.3 a two-person piece on his list: the ★ marble slab; he waits at it for you, then Sol lifts it with him ---------------------

Moving.admin(sol, "start")
truck = E.cars[sol]
cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
truck.model:SetAttribute("BackOpen", true)
Moving.step()
danny = MoveHelper.find(sol)
body = danny.body
npc = body.model
E.request(sol, "helper", "hire")
site = workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge")
E.place(sol, outside)
trigger(promptIn(site, "Enter house"), sol)
slab = itemModel(6)
local SLAB = E.items.slab.size
give(slab)
local backAsk = cargoDoor.WorldPosition + V3(0, 0, 2)
E.place(sol, backAsk + V3(30, 0, 0)) -- (out of the house: nobody at the slab)
noticeAt = #E.messages
said = #E.said
local asking = run(40, function()
	return danny.needs == 6 and danny.needsAt > 0
end)
check("8.3 the slab on his list (two people): he goes to it and waits at one end", asking and danny.action == "needs"
	and distance(body.root.Position, slab.PrimaryPart.Position) <= math.max(SLAB.X, SLAB.Z) / 2 + H.PickReach + 0.6)
check("…\"This one's too heavy for me alone, give me a hand!\"", E.saidSince("This one's too heavy for me alone, give me a hand!", said))
check("…the crew's toast, the marker \"🙋 Danny needs you\", its prompt \"Lift with Danny\", the strip", told(sol, "Danny is at the Marble slab: lift it with him.", noticeAt)
	and markOf(slab) == "🙋 Danny needs you" and slab:GetAttribute("DannyNeeds") == true and promptIn(slab, "Lift with Danny") ~= nil
	and sol:GetAttribute("MoveHelperDoing") == "Waiting for you at the Marble slab", sol:GetAttribute("MoveHelperDoing"))
noticeAt = #E.messages
run(60)
check("8.3 …nobody comes for a minute: he still waits at it (no timeout: it is yours to lift with him), the crew told once", danny.needs == 6 and danny.action == "needs"
	and listIs({ 6 }) and not told(sol, "Danny is at the Marble slab", noticeAt))
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
check("8.3 Sol answers (\"Lift with Danny\"): a call, no lift check yet, still on his list", danny.call ~= nil and danny.call.spot == 6
	and sol:GetAttribute("MoveHelperCall") == "Marble slab" and gripOpened(gripFrom) == nil and listIs({ 6 }))
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
noticeAt = #E.messages
E.request(sol, "grip", retry.id, "ok", hitAt)
check("…its hit: up together at once (never dragged alone), Sol leading, Danny at the far end", sol.Character:GetAttribute("MoveCarry") == 6
	and select(2, Rules.holding(danny.s.move, danny.id)) == "helper" and danny.call == nil and sol:GetAttribute("MoveHelperCall") == nil)
check("8.3 …off his list (no \"You took\": lifted with him), the marker gone", #danny.queue == 0 and markOf(slab) == nil and slab:GetAttribute("DannyNeeds") == nil
	and not told(sol, "You took", noticeAt))
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
E.request(sol, "helper", "hire")
E.place(sol, outside)
trigger(promptIn(workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge"), "Enter house"), sol)
give(itemModel(1))
E.place(sol, outside)
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
E.request(sol, "helper", "hire")
E.place(sol, outside)
trigger(promptIn(workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge"), "Enter house"), sol)
give(itemModel(5))
E.place(sol, outside)
local holds = run(40, function()
	return danny.body ~= nil and Rules.holding(danny.s.move, danny.id) ~= nil
end)
local held = Rules.holding(danny.s.move, danny.id)
check("a later move: Danny carries the piece of his list", holds and held == 5)
danny.body.model:Destroy()
run(0.5)
check("his body gone: what he held fell (never 'carried' by nobody)", Rules.holding(danny.s.move, danny.id) == nil and held ~= nil
	and danny.s.move.things[held].state == "ground", held and danny.s.move.things[held].state)
Moving.admin(sol, "end")
run(0.2)

-- 8.3 an unhired Danny heads back when the crew grows; a crew mate's hire ends when they leave the move -------------------------

Moving.admin(sol, "start")
Moving.step()
danny = MoveHelper.find(sol)
npc = danny.body.model
E.crew[sol] = { bob }
Moving.step()
check("8.3 not hired, a crew of two: Danny heads home (Duo is off: your crew has it now)", MoveHelper.find(sol) == nil and npc.Parent == nil
	and sol:GetAttribute("MoveHelper") == nil and string.find(E.lastNotice(sol), "your crew has it now", 1, true) ~= nil)
H.Duo = true
Moving.step()
danny = MoveHelper.find(sol)
check("Duo on: he comes for two as well, for hire", danny ~= nil and sol:GetAttribute("MoveHelper") == "offer" and bob:GetAttribute("MoveHelper") == "offer"
	and bob:GetAttribute("MoveHelperId") == danny.id)
E.wallet[bob] = 300
E.request(bob, "helper", "hire")
check("8.3 Bob (the crew mate) hires him: Bob's money, Bob's hire", danny.hirer == bob and E.wallet[bob] == 300 - danny.price and sol:GetAttribute("MoveHelper") == "hired")
H.Duo = false
E.crew[sol] = {}
Moving.step()
check("8.3 Bob leaves the move: his hire with him (whoever hired him owns it), Danny for hire again for Sol", MoveHelper.find(sol) == danny and danny.hirer == nil
	and sol:GetAttribute("MoveHelper") == "offer" and string.find(E.lastNotice(sol), "Bob left the move", 1, true) ~= nil, E.lastNotice(sol))
E.leave(sol)
run(0.2)
check("the owner leaves: the move and Danny are gone", MoveHelper.find(sol) == nil and E.destroyed == E.built)
E.leave(rex)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
