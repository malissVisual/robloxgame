-- 8.1 grip: the real server/Moving.luau's grip hook and grip block on tests/runtime/MovingRuntime.luau's fakes (built by
-- tests/run_tests.py as MovingServer.luau), Config.CarryGrip.On turned on (the fake turns it off for the moves' other
-- tests). The lift check: a piece with a grip is not lifted by its prompt but by a hit of its check ("feeling for the
-- grip"): a miss (a press outside the zone, or none in the window + grace) knocks it and leaves it where it stood, a
-- moment before the next try; a hit lifts it balanced (the steady walk). The answers: only the sender's own open check
-- counts, "ok" only with a press time the server's clock could have seen and the needle in the zone (a forged success
-- outside a check, a stranger's, a wrong id, a made-up time: nothing or a miss). Wobbles: the clock opens one after
-- 7 – 12 s of walking (seldom standing); a hit keeps it steady; a sturdy piece's first miss staggers it (a knock, the
-- walk × 0.6 a moment, the next wobble sooner), the second in a row drops it; a fragile piece drops at once; no answer
-- is a miss. A pair piece: each carrier their own checks (a Help lift too), a stagger's knock half each, either one's
-- drop drops it whole. Danny's GripSteady and the Mover: bigger zones. A door trip takes the check off. The CarryGrip
-- attribute with the carry, gone with it.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local Config = require("./Config")
local Map = require("./Map")
local CarryGrip = require("./CarryGrip")

local failures = 0
local function check(name: string, ok: boolean, detail: any?)
	if ok then
		print("ok    " .. name)
	else
		failures += 1
		print("FAIL  " .. name .. (if detail ~= nil then "  (" .. tostring(detail) .. ")" else ""))
	end
end
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local T = Config.Moving
local G = Config.CarryGrip
G.On = true -- (the fake turns the checks off for the other tests)
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace

local depot = V3(Map.Depot.x, 3, Map.Depot.z)
local home = Map.home(T.Contracts[1].home) :: any
E.truckAt = V3(home.park.x, 2, home.park.z)
local ann = E.player(11, "Ann", depot)
local bob = E.player(22, "Bob", depot + V3(3, 0, 0))
local cid = E.player(33, "Cid", depot + V3(-3, 0, 0))
E.crew[ann] = { bob }
Moving.useArt(E.art)
-- 8.2: Moving.onGrip's listener (server/SandboxAnalytics.luau samples them): every outcome a client hears, it hears too
local heardGrips: { { player: any, what: string, outcome: string, item: string, fragile: boolean } } = {}
Moving.onGrip(function(player: any, facts: any)
	table.insert(heardGrips, { player = player, what = facts.what, outcome = facts.outcome, item = facts.item, fragile = facts.fragile })
end)
Moving.start()
local said = Moving.admin(ann, "start")
check("the admin's START: a move with Ann and Bob", string.find(said, "started", 1, true) ~= nil, said)
Moving.step()
check("the roles: Ann the Driver, Bob the Mover", ann:GetAttribute("MoveRole") == "driver" and bob:GetAttribute("MoveRole") == "mover")

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
local function pick(player: any, spot: number, action: string?)
	local model = itemModel(spot)
	E.place(player, model.PrimaryPart.Position + V3(1, 0, 0))
	promptIn(model, action or "Pick up").Triggered:Fire(player)
end
local function putDown(player: any)
	E.Net.get("PutDown").OnServerEvent:Fire(player)
end
local function state(): any
	E.clock += 0.3
	Moving.step()
	return E.last(ann, "Moving", "state").a
end
local function thingOf(spot: number): any
	for _, item in state().items do
		if item.spot == spot then
			return item
		end
	end
	return nil
end
local function grip(player: any): any
	return player.Character:GetAttribute("CarryGrip")
end
local function carrying(player: any): any
	return player.Character:GetAttribute("MoveCarry")
end
local function speedOf(player: any): number
	return player.Character:GetAttribute("CarrySpeed") or 0
end
local function heard(player: any, text: string, since: number): boolean
	for index = since + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then
			return true
		end
	end
	return false
end
-- The grip messages to `player` since message `since` (("grip", sub, payload): { sub, payload }).
local function grips(player: any, since: number?): { any }
	local list = {}
	for index = (since or 0) + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Moving" and m.kind == "grip" then
			table.insert(list, { sub = m.a, data = m.b })
		end
	end
	return list
end
local function lastGrip(player: any, sub: string): any
	for index = #E.messages, 1, -1 do
		local m = E.messages[index]
		if m.player == player and m.remote == "Moving" and m.kind == "grip" and m.a == sub then
			return m.b
		end
	end
	return nil
end
local function countGrip(player: any, sub: string, since: number): number
	local n = 0
	for _, g in grips(player, since) do
		n += if g.sub == sub then 1 else 0
	end
	return n
end
-- Answers the check `wire` with a press `at` s into it, the server's clock `lag` s later (an "ok" by default).
local function answer(player: any, wire: any, at: number, verdict: string?, lag: number?)
	E.now += at + (lag or 0.08)
	E.request(player, "grip", wire.id, verdict or "ok", at)
end
local function hitAt(wire: any): number
	return CarryGrip.firstHit(CarryGrip.fromWire(wire) :: CarryGrip.Check)
end
local function hit(player: any, wire: any)
	answer(player, wire, hitAt(wire))
end
-- `player` walks along +X at their carry's walk for `seconds` (the server's ticks every 0.2 s); returns the s walked
-- until a wobble opened (nil: none).
local function walk(player: any, seconds: number, standing: boolean?): number?
	local since = #E.messages
	local t = 0
	while t < seconds do
		t += 0.2
		E.now += 0.2
		E.clock += 0.2
		if not standing then
			E.place(player, E.rootOf(player).Position + V3(speedOf(player) * 0.2, 0, 0))
		end
		Moving.step()
		if countGrip(player, "open", since) > 0 then
			return t
		end
	end
	return nil
end
local annBody = ann.Character

-- Which carries have checks ------------------------------------------------------------------------------------------

pick(ann, 5) -- the box of memories: one hand, not fragile
check("a plain one-hand thing: lifted at once, no check, no CarryGrip", carrying(ann) == 5 and grip(ann) == nil and lastGrip(ann, "open") == nil)
putDown(ann)

-- The lift check: feeling for the grip ------------------------------------------------------------------------------

local holsters = E.holstered
local since = #E.messages
pick(ann, 1) -- the lamp: one hand, fragile, weight 1
local lift = lastGrip(ann, "open")
check("the fragile lamp's Pick up: a lift check, not a carry", lift ~= nil and lift.what == "lift" and lift.spot == 1 and carrying(ann) == nil
	and thingOf(1).state ~= "carried", lift and lift.what)
check("…its numbers: an easy zone (a third of the sweep or so), a slow needle, 3 s", lift.zone >= 0.27 and lift.zone <= 0.4 and lift.speed <= 0.76 and lift.window >= G.Lift.Window
	and lift.zone0 >= G.Zone.Start - 1e-9 and lift.name == "Lamp" and lift.icon == "💡", `{lift.zone} {lift.speed} {lift.window}`)
check("…the gun away (both hands on it)", E.holstered > holsters)
pick(ann, 1)
check("E again during the check: no second check", countGrip(ann, "open", since) == 1)
local lamp0 = thingOf(1).condition
since = #E.messages
answer(ann, lift, 0.02) -- (an instant press: the needle at the left end, the zone further on)
local knock = lastGrip(ann, "result")
check("a lift miss: the lamp knocked (4% × fragile 1.25 = 5%), not lifted, still where it stood", carrying(ann) == nil and thingOf(1).state == "home"
	and near(thingOf(1).condition, lamp0 - 0.05, 0.006) and knock ~= nil and knock.outcome == "knock" and knock.id == lift.id, `{lamp0} → {thingOf(1).condition}`)
check("…told it slipped back down, the outcome with the % left", heard(ann, "slipped back down", since) and knock.left == math.floor(thingOf(1).condition * 100 + 0.5))
pick(ann, 1)
check("…a try at once (within Lift.Again): nothing", countGrip(ann, "open", since) == 0)
E.now += G.Lift.Again + 0.05
pick(ann, 1)
local again = lastGrip(ann, "open")
check("…a moment later: a new lift check", countGrip(ann, "open", since) == 1 and again.id ~= lift.id)
local lamp1 = thingOf(1).condition
E.now += again.window + G.Server.Grace + 0.1
state()
check("no press in the window (+ grace): a miss, the same knock", carrying(ann) == nil and near(thingOf(1).condition, lamp1 - 0.05, 0.006)
	and lastGrip(ann, "result").outcome == "knock")
E.now += G.Lift.Again + 0.05
pick(ann, 1)
local third = lastGrip(ann, "open")
local lampBefore = thingOf(1).condition
since = #E.messages
hit(ann, third)
local balanced = lastGrip(ann, "result")
check("a lift hit: the lamp in Ann's hands (MoveCarry, \"hand 1 fragile\"), no damage", carrying(ann) == 1 and grip(ann) == "hand 1 fragile"
	and thingOf(1).state == "carried" and thingOf(1).condition == lampBefore)
check("…balanced: the outcome, the steady walk (× 1.1)", balanced ~= nil and balanced.outcome == "balanced" and balanced.id == third.id
	and near(speedOf(ann), Config.Movement.Walk * (1 - T.Speed.HandPerWeight) * G.SteadySpeed, 1e-6), speedOf(ann))
putDown(ann)
state()
check("put down: the grip goes with the carry", carrying(ann) == nil and grip(ann) == nil)

-- Forged answers ---------------------------------------------------------------------------------------------------------

local tv0 = thingOf(2).condition
E.request(ann, "grip", third.id + 50, "ok", 1)
E.request(ann, "grip", third.id, "ok", hitAt(third))
check("a forged success with no check open (a made-up id, the last check's again): nothing", carrying(ann) == nil and thingOf(2).condition == tv0)
E.now += 1
pick(ann, 2) -- the TV: both hands, fragile, weight 4
local tvLift = lastGrip(ann, "open")
check("the TV's Pick up: a lift check (\"both\")", tvLift ~= nil and tvLift.what == "lift" and tvLift.spot == 2 and carrying(ann) == nil)
E.now += hitAt(tvLift) + 0.05
E.request(cid, "grip", tvLift.id, "ok", hitAt(tvLift))
E.request(bob, "grip", tvLift.id, "ok", hitAt(tvLift))
E.request(ann, "grip", tvLift.id + 1, "ok", hitAt(tvLift))
check("…a stranger's, a crew mate's or a wrong id's \"ok\": nothing (still open, not lifted)", carrying(ann) == nil and carrying(bob) == nil and thingOf(2).state == "home")
E.request(ann, "grip", tvLift.id, "ok", hitAt(tvLift) + 5)
check("…Ann's \"ok\" with a press time the server never reached (made up): a miss, a knock", carrying(ann) == nil and lastGrip(ann, "result").outcome == "knock"
	and thingOf(2).condition < tv0)
E.now += G.Lift.Again + 0.05
pick(ann, 2)
local outside = lastGrip(ann, "open")
-- (an "ok" with the needle short of the zone on its first sweep: the zone starts at Zone.Start or later, so this is
-- always outside; past the zone the needle could have swung back into it)
answer(ann, outside, (outside.zone0 - 0.1) / outside.speed)
check("…an \"ok\" with the needle outside the zone (the client's lie): a miss", carrying(ann) == nil and lastGrip(ann, "result").outcome == "knock")
E.now += G.Lift.Again + 0.05
pick(ann, 2)
hit(ann, lastGrip(ann, "open"))
local bothWalk = Config.Movement.Walk * T.Speed.Both
check("a hit at last: the TV in Ann's hands (\"both 4 fragile\"), balanced (× 1.1)", carrying(ann) == 2 and grip(ann) == "both 4 fragile"
	and near(speedOf(ann), bothWalk * G.SteadySpeed), speedOf(ann))

-- Wobbles ------------------------------------------------------------------------------------------------------------------

since = #E.messages
local stood = walk(ann, 20, true)
check("standing still 20 s with it: no wobble yet (the clock runs at a fifth)", stood == nil, stood)
local walked = walk(ann, 30)
local clockRan = (walked or 0) + 20 * G.Wobble.Still
check("walking: a wobble after 7 – 12 s of the clock (the 20 s standing counted a fifth)", walked ~= nil and clockRan >= 7 - 0.3 and clockRan <= 12 + 0.3, clockRan)
local wobble = lastGrip(ann, "open")
check("…a WOBBLE! check: a slightly smaller zone, a fragile piece: its miss drops it", wobble.what == "wobble" and wobble.drop == true and wobble.window >= G.Wobble.Window
	and wobble.zone < tvLift.zone + 1e-9, `{wobble.zone} {tvLift.zone}`)
hit(ann, wobble)
check("a wobble hit: steady, still carried, the steady walk", lastGrip(ann, "result").outcome == "steady" and carrying(ann) == 2 and near(speedOf(ann), bothWalk * G.SteadySpeed))
local tvNow = thingOf(2).condition
since = #E.messages
check("Moving.gripCheck: a wobble now", Moving.gripCheck(ann) and countGrip(ann, "open", since) == 1)
check("…not a second while one is on", not Moving.gripCheck(ann))
answer(ann, lastGrip(ann, "open"), 0.01, "miss")
local dropped = thingOf(2)
check("a fragile piece's first wobble miss: it drops (the slip's damage, fragile)", dropped.state == "ground" and carrying(ann) == nil and grip(ann) == nil
	and near(dropped.condition, tvNow - CarryGrip.slipDamage(true), 0.006) and lastGrip(ann, "result").outcome == "drop", `{tvNow} → {dropped.condition}`)
check("…told it slipped", heard(ann, "It slipped", since))
check("…anchored on the floor, no weld", itemModel(2).PrimaryPart.Anchored and itemModel(2).PrimaryPart:FindFirstChildOfClass("WeldConstraint") == nil)

-- A sturdy piece: a stagger, then a drop -------------------------------------------------------------------------------

pick(ann, 3, "Lift") -- the sofa: a pair thing, weight 8, not fragile
local sofaLift = lastGrip(ann, "open")
check("the sofa's Lift: a lift check (dragged alone: \"drag\", a wide zone)", sofaLift.what == "lift" and sofaLift.zone >= 0.33)
hit(ann, sofaLift)
local dragWalk = Config.Movement.Walk * T.Speed.Drag
check("…a hit: Ann drags it (\"drag 8\"), balanced", carrying(ann) == 3 and grip(ann) == "drag 8" and near(speedOf(ann), dragWalk * G.SteadySpeed), speedOf(ann))
local sofa0 = thingOf(3).condition
since = #E.messages
Moving.gripCheck(ann)
local first = lastGrip(ann, "open")
check("a sturdy piece's wobble: its miss does not drop it (yet)", first.drop == false)
answer(ann, first, 0.01, "miss")
local stagger = lastGrip(ann, "result")
check("its first miss: a stagger (a 3% knock, still in Ann's hands)", stagger.outcome == "stagger" and carrying(ann) == 3 and near(thingOf(3).condition, sofa0 - 0.03, 0.006),
	`{sofa0} → {thingOf(3).condition}`)
check("…the walk × 0.6 a moment (and no steady +10%)", near(speedOf(ann), dragWalk * G.Miss.Slow), speedOf(ann))
check("…told: miss the next one and it drops", heard(ann, "miss the next one", since))
E.now += G.Miss.SlowFor + 0.1
state()
check("…SlowFor s later: the plain walk again", near(speedOf(ann), dragWalk), speedOf(ann))
local sooner = walk(ann, 30)
local soonest = G.Wobble.Every[1] * G.Kinds.drag.Every -- (a drag's wobble without a stagger: 10.5 s at the soonest)
check("the next wobble sooner (× Sooner: the drag's 10.5 – 18 s down to 5.25 – 9 s)", sooner ~= nil and sooner <= soonest * G.Miss.Sooner * 12 / 7 + 0.2
	and sooner < soonest, sooner)
local second = lastGrip(ann, "open")
check("…shaky: this one's miss drops it", second.drop == true)
local sofa1 = thingOf(3).condition
E.now += second.window + G.Server.Grace + 0.1
state()
local sofaDown = thingOf(3)
check("no answer at all: a miss, the second in a row: the sofa drops (the slip's damage)", sofaDown.state == "ground" and carrying(ann) == nil
	and near(sofaDown.condition, sofa1 - CarryGrip.slipDamage(false), 0.006) and lastGrip(ann, "result").outcome == "drop", `{sofa1} → {sofaDown.condition}`)

-- A pair piece by two: each their own checks, half each ---------------------------------------------------------------

pick(ann, 3, "Lift")
hit(ann, lastGrip(ann, "open"))
check("the sofa lifted again (a new lift, balanced)", carrying(ann) == 3 and grip(ann) == "drag 8")
local sofa = itemModel(3)
E.place(bob, sofa.PrimaryPart.Position + V3(-1, 0, 0))
promptIn(sofa, "Help lift").Triggered:Fire(bob)
local helpLift = lastGrip(bob, "open")
check("Bob's Help lift: his own lift check (\"pair\"), the Mover's bigger zone; not his end yet", helpLift ~= nil and helpLift.what == "lift" and helpLift.help == true
	and carrying(bob) == nil and near(helpLift.zone, CarryGrip.profile("pair", 8, false, true).zone), helpLift and helpLift.zone)
local sofa2 = thingOf(3).condition
answer(bob, helpLift, 0.01)
check("…his miss: his end slips (the knock half: the other end is in Ann's hands), Ann still drags it", carrying(bob) == nil and carrying(ann) == 3
	and near(thingOf(3).condition, sofa2 - 0.02, 0.006), `{sofa2} → {thingOf(3).condition}`)
E.now += G.Lift.Again + 0.05
E.place(bob, sofa.PrimaryPart.Position + V3(-1, 0, 0))
promptIn(sofa, "Help lift").Triggered:Fire(bob)
hit(bob, lastGrip(bob, "open"))
check("…his hit: Bob holds the other end, both \"pair 8\"", carrying(bob) == 3 and grip(ann) == "pair 8" and grip(bob) == "pair 8")
local pairWalk = Config.Movement.Walk * T.Speed.Pair
check("…both balanced: the pair's walk × 1.1", near(speedOf(ann), pairWalk * G.SteadySpeed), speedOf(ann))
local sofa3 = thingOf(3).condition
Moving.gripCheck(ann)
answer(ann, lastGrip(ann, "open"), 0.01, "miss")
check("Ann's wobble miss with the sofa by two: a stagger, the knock half (1.5%), both still hold it", lastGrip(ann, "result").outcome == "stagger"
	and near(thingOf(3).condition, sofa3 - 0.015, 0.006) and carrying(ann) == 3 and carrying(bob) == 3, `{sofa3} → {thingOf(3).condition}`)
check("…the stagger slows the pair (× 0.6, Bob's end the same)", near(speedOf(ann), pairWalk * G.Miss.Slow) and near(speedOf(bob), pairWalk * G.Miss.Slow), speedOf(ann))
local sofa4 = thingOf(3).condition
Moving.gripCheck(bob)
local bobWobble = lastGrip(bob, "open")
check("Bob's own wobble: his own misses (none yet: not a drop)", bobWobble.what == "wobble" and bobWobble.drop == false)
answer(bob, bobWobble, 0.01, "miss")
check("…his miss: his own stagger, half the knock", lastGrip(bob, "result").outcome == "stagger" and near(thingOf(3).condition, sofa4 - 0.015, 0.006) and carrying(bob) == 3)
E.now += G.Miss.SlowFor + 0.1
state()
since = #E.messages
Moving.gripCheck(ann)
local annDrop = lastGrip(ann, "open")
check("Ann shaky: her next wobble's miss drops it", annDrop.drop == true)
local sofa5 = thingOf(3).condition
answer(ann, annDrop, 0.01, "miss")
local sofaNow = thingOf(3)
check("…her second miss in a row: the whole sofa goes down, both hands free, both told", sofaNow.state == "ground" and carrying(ann) == nil and carrying(bob) == nil
	and grip(ann) == nil and grip(bob) == nil and near(sofaNow.condition, sofa5 - CarryGrip.slipDamage(false), 0.006) and heard(ann, "It slipped", since)
	and heard(bob, "lost their grip", since))
state()
check("…Bob's grip record goes with it (no wobble on nothing)", not Moving.gripCheck(bob))

-- Danny's steadying and the Mover ------------------------------------------------------------------------------------------

pick(bob, 6, "Lift") -- the marble slab: a pair thing, weight 10; Bob is a Mover: held up alone ("solo")
hit(bob, lastGrip(bob, "open"))
check("a Mover lifts the slab alone: \"solo 10\"", carrying(bob) == 6 and grip(bob) == "solo 10", grip(bob))
Moving.gripCheck(bob)
local plain = lastGrip(bob, "open")
answer(bob, plain, hitAt(plain))
bob.Character:SetAttribute("GripSteady", true) -- (server/MoveHelper.luau sets it while Danny holds the other end)
Moving.gripCheck(bob)
local steadied = lastGrip(bob, "open")
answer(bob, steadied, hitAt(steadied))
check("Danny steadies it (GripSteady): the wobble's zone × 1.3", near(steadied.zone, math.min(G.Zone.Max, plain.zone * G.Steadied), 1e-6), `{plain.zone} → {steadied.zone}`)
check("…the Mover's zone: × 1.35 of a non-Mover's", near(plain.zone, CarryGrip.check(CarryGrip.profile("solo", 10, false, true), "wobble", 0).zone)
	and plain.zone > CarryGrip.check(CarryGrip.profile("solo", 10, false, false), "wobble", 0).zone)
bob.Character:SetAttribute("GripSteady", nil)
putDown(bob)

-- A door trip takes the check off ---------------------------------------------------------------------------------------

E.now += 1
pick(ann, 4) -- the clock: both hands, fragile, weight 6
hit(ann, lastGrip(ann, "open"))
check("the clock lifted (\"both 6 fragile\")", carrying(ann) == 4 and grip(ann) == "both 6 fragile")
Moving.gripCheck(ann)
local onDoor = lastGrip(ann, "open")
local leave = promptIn(workspace, "Leave house")
local queued: { () -> () } = {}
local runAtOnce = E.task.delay
E.task.delay = function(_: any, callback: any, ...: any) -- (the fade's delay waits: the trip is on until run)
	local args = table.pack(...)
	table.insert(queued, function()
		callback(table.unpack(args, 1, args.n))
	end)
end
since = #E.messages
E.place(ann, leave.Parent.Position)
leave.Triggered:Fire(ann)
state()
check("a door trip: the open wobble is taken off (\"close\"), no outcome", countGrip(ann, "close", since) == 1 and lastGrip(ann, "close") == onDoor.id
	and countGrip(ann, "result", since) == 0)
local clock0 = thingOf(4).condition
answer(ann, onDoor, 0.01, "miss")
E.now += 10
state()
check("…its answer during the trip does nothing, no wobble opens on the way", thingOf(4).condition == clock0 and carrying(ann) == 4 and countGrip(ann, "open", since) == 0)
table.remove(queued, 1)()
E.task.delay = runAtOnce
since = #E.messages
state()
local owed = lastGrip(ann, "open")
check("8.1 review: the trip done, the wobble the fade took off opens again (no dodging it through a door)", countGrip(ann, "open", since) == 1
	and owed.what == "wobble" and owed.id ~= onDoor.id)
hit(ann, owed)
check("the trip done: checks again", Moving.gripCheck(ann))
hit(ann, lastGrip(ann, "open"))
putDown(ann)

-- 8.1 review: a miss cannot be dodged by putting the piece down (or loading it) with a wobble open ---------------------

E.now += 1
pick(ann, 3, "Lift")
hit(ann, lastGrip(ann, "open"))
check("(Ann drags the sofa again, balanced)", carrying(ann) == 3 and grip(ann) == "drag 8")
Moving.gripCheck(ann)
local dodge1 = lastGrip(ann, "open")
check("(a sturdy piece's first wobble: no drop)", dodge1.drop == false)
local sofaA = thingOf(3).condition
since = #E.messages
putDown(ann)
local sofaAfter = thingOf(3)
local forfeit1 = lastGrip(ann, "result")
check("8.1 review: put down with a wobble open: a miss all the same (the stagger's knock)", carrying(ann) == nil and sofaAfter.state == "ground"
	and forfeit1 ~= nil and forfeit1.id == dodge1.id and forfeit1.outcome == "stagger" and near(sofaAfter.condition, sofaA - G.Miss.Knock, 0.006),
	`{sofaA} → {sofaAfter.condition}`)
check("…told it wobbled as it went down", heard(ann, "wobbled as it went down", since))
pick(ann, 3, "Lift")
hit(ann, lastGrip(ann, "open"))
Moving.gripCheck(ann)
local dodge2 = lastGrip(ann, "open")
check("…lifted again at once: its miss came with it (this wobble's miss drops it)", carrying(ann) == 3 and dodge2.drop == true)
local sofaB = thingOf(3).condition
putDown(ann)
local sofaGone = thingOf(3)
check("…put down with that one open too: the drop's damage (the slip)", lastGrip(ann, "result").id == dodge2.id and lastGrip(ann, "result").outcome == "drop"
	and near(sofaGone.condition, sofaB - CarryGrip.slipDamage(false), 0.006), `{sofaB} → {sofaGone.condition}`)
pick(ann, 3, "Lift")
hit(ann, lastGrip(ann, "open"))
Moving.gripCheck(ann)
check("…the drop spent the misses: the next lift starts fresh", carrying(ann) == 3 and lastGrip(ann, "open").drop == false)
hit(ann, lastGrip(ann, "open"))
putDown(ann)
E.now += G.Miss.Remember + 1

-- Off: the carry as before ------------------------------------------------------------------------------------------------

G.On = false
E.now += 1
pick(ann, 4)
check("Config.CarryGrip.On false: a Pick up lifts at once, no check, no CarryGrip", carrying(ann) == 4 and grip(ann) == nil)
putDown(ann)
G.On = true

Moving.admin(ann, "end")
check("the move ends: nobody keeps a grip", grip(ann) == nil and grip(bob) == nil)

-- 8.2: Moving.onGrip heard every outcome the clients heard, in their order, with what, the piece and fragile
do
	local results = {}
	for _, m in E.messages do
		if m.remote == "Moving" and m.kind == "grip" and m.a == "result" then
			table.insert(results, { player = m.player, what = m.b.what, outcome = m.b.outcome })
		end
	end
	local same, kinds = #results == #heardGrips and #results > 0, {}
	for index, result in results do
		local mine = heardGrips[index]
		same = same and mine ~= nil and mine.player == result.player and mine.what == result.what and mine.outcome == result.outcome
			and type(mine.item) == "string" and type(mine.fragile) == "boolean"
		kinds[result.outcome] = true
	end
	check("8.2: Moving.onGrip hears every check's outcome (each one its player's, lift or wobble, the piece's id and fragile)", same, `{#results} {#heardGrips}`)
	check("8.2: …of every kind (balanced, knock, steady, stagger, drop)", kinds.balanced and kinds.knock and kinds.steady and kinds.stagger and kinds.drop or false)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
