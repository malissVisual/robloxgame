-- 7.0, the depot's helper ("Danny from the depot"): his decisions (shared/MoveHelperBrain.luau, pure). Who gets him,
-- which piece he carries next (★ first, then the most value a second of the trip; one-hand and, 7.x, two-hands ones;
-- never a pair piece alone, a broken one, one you are about to lift (the reservation), one that no longer fits the van,
-- one waiting by the shut van), which lift he comes to help with, the other side of your heavy two-hands piece (7.x
-- assist), when he runs from a zombie, what he does now (the priority list), the van's back (he opens it), his speeds
-- (slower than a player, a sprint to your lift), stuck (a new path, a nudge), the far end of your piece (on the floor
-- there), the doorways he keeps out of, his place behind you and his words. tests/movehelper_runtime_test.luau and
-- tests/movehelper_art_runtime_test.luau run the server side.
local Brain = require("./MoveHelperBrain")
local Config = require("./Config")
local Rules = require("./MovingRules")
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
	return math.abs(a - b) < (eps or 1e-6)
end

local H = Config.MoveHelper
local WALK = Config.Movement.Walk

-- Who gets him -------------------------------------------------------------------------------------------------------------

check("a crew of one gets him", Brain.wanted(1))
check("two don't (Duo is off)", not Brain.wanted(2) and H.Duo == false)
check("nobody, three, four: no", not Brain.wanted(0) and not Brain.wanted(3) and not Brain.wanted(4))
H.Duo = true
check("Duo on: two get him too", Brain.wanted(2) and Brain.wanted(1) and not Brain.wanted(3))
H.Duo = false
H.Solo = false
check("Solo off: nobody gets him", not Brain.wanted(1))
H.Solo = true
check("the orders: help, carry, wait", Brain.validMode("help") and Brain.validMode("carry") and Brain.validMode("wait")
	and not Brain.validMode("dance") and not Brain.validMode(nil) and not Brain.validMode(3))

-- The way ------------------------------------------------------------------------------------------------------------------

local doors: Brain.Doors = { outX = 100, outZ = 0, inX = 5000, inZ = 0 }
check("the same world: straight", near(Brain.routeCost(false, 100, 30, false, 100, 70, doors), 40))
check("inside to the street: to the exit, from the front door", near(Brain.routeCost(true, 5000, 10, false, 100, 20, doors), 10 + 20))
check("the street to inside: to the front door, from the exit", near(Brain.routeCost(false, 100, 5, true, 5000, 12, doors), 5 + 12))
check("inside, from room to room", near(Brain.routeCost(true, 5000, 0, true, 5003, 4, doors), 5))

-- Which piece next ---------------------------------------------------------------------------------------------------------

local function thing(spot: number, class: string, cost: number, extra: { [string]: any }?): Brain.Candidate
	local c: Brain.Candidate = { spot = spot, class = class, state = "home", star = false, broken = false, cost = cost, haul = 20, value = 100, weight = 2, fits = true,
		byTruck = false, reserved = false }
	for key, value in extra or {} do
		(c :: any)[key] = value
	end
	return c
end

local list = {
	thing(1, "hand", 10), -- the lamp
	thing(3, "pair", 1), -- the sofa: never alone
	thing(5, "hand", 30, { star = true }), -- the box of memories (★)
	thing(6, "hand", 1, { broken = true }), -- a broken one pays nothing
	thing(7, "hand", 1, { state = "carried" }), -- somebody has it
	thing(8, "hand", 1, { state = "truck" }), -- in the van already
}
local pick, full = Brain.pickItem(list, true)
check("★ first: the box of memories, though the lamp is nearer", pick == 5 and full == false, pick)
list[3].star = false
pick = Brain.pickItem(list, true)
check("no ★ left: the same value nearer wins (the lamp)", pick == 1, pick)
list[1].cost = 40
pick = Brain.pickItem(list, true)
check("…the nearer one wins (the box)", pick == 5, pick)
list[1].value = 400
pick = Brain.pickItem(list, true)
check("7.x the most value a second of the trip: the lamp worth 4× is worth the walk", pick == 1, pick)
list[1].value, list[1].cost = 100, 10
list[3].fits = false
list[1].fits = false
pick, full = Brain.pickItem(list, true)
check("nothing fits: none, and the van is full", pick == nil and full == true)
list[1].fits = true
list[1].reserved = true
pick, full = Brain.pickItem(list, true)
check("7.x a piece you are about to lift is yours: he leaves it (the box does not fit: the van is full for him)", pick == nil and full == true)
local byTruck = { thing(9, "hand", 3, { state = "ground", byTruck = true }) }
pick, full = Brain.pickItem(byTruck, false)
check("set down by the shut van: it waits (not 'full')", pick == nil and full == false)
pick = Brain.pickItem(byTruck, true)
check("…the back open: he takes it in", pick == 9)
pick = Brain.pickItem({ thing(2, "both", 4, { weight = 4 }), thing(3, "pair", 1) }, true)
check("7.x a two-hands piece on his own too (never a pair one)", pick == 2, pick)
pick = Brain.pickItem({ thing(2, "both", 5, { weight = 6 }), thing(1, "hand", 5, { weight = 6 }) }, true)
check("…the same value, the same way: the quicker one-hand carry first", pick == 1, pick)
check("…worth: slower with two hands", Brain.worth(thing(2, "both", 5, { weight = 6 })) < Brain.worth(thing(1, "hand", 5, { weight = 6 })))
pick, full = Brain.pickItem({ thing(3, "pair", 1) }, true)
check("only a pair piece left: nothing for him alone", pick == nil and full == false)
pick = Brain.pickItem({ thing(1, "hand", 5, { state = "ground" }) }, true)
check("a piece on the ground counts", pick == 1)

-- The reservation (7.x) ----------------------------------------------------------------------------------------------------

check("you within Reserve and nearer: yours", Brain.reserved(H.Reserve - 1, 20) and Brain.reserved(3, 4))
check("…farther than Reserve: still his to take", not Brain.reserved(H.Reserve + 1, 40))
check("…he is nearer: his", not Brain.reserved(5, 2))
check("…nobody with free hands: his", not Brain.reserved(nil, 20))

-- Which lift, which assist -------------------------------------------------------------------------------------------------

local function lift(spot: number, cost: number, extra: { [string]: any }?): Brain.Lift
	local l: Brain.Lift = { spot = spot, class = "pair", state = "carried", helped = false, crew = true, cost = cost, gaveUp = false, weight = 8, byBack = false }
	for key, value in extra or {} do
		(l :: any)[key] = value
	end
	return l
end
check("a crew player drags a pair piece alone: he comes", Brain.pickLift({ lift(3, 20) }) == 3)
check("the nearer of two", Brain.pickLift({ lift(3, 20), lift(6, 12) }) == 6)
check("not one somebody holds the other end of", Brain.pickLift({ lift(3, 20, { helped = true }) }) == nil)
check("not a stranger's", Brain.pickLift({ lift(3, 20, { crew = false }) }) == nil)
check("not one whose take failed a moment ago", Brain.pickLift({ lift(3, 20, { gaveUp = true }) }) == nil)
check("not from farther than HelpFar", Brain.pickLift({ lift(3, H.HelpFar + 1) }) == nil and Brain.pickLift({ lift(3, H.HelpFar) }) == 3)
check("not one on the ground, not a two-hands one (that's an assist)", Brain.pickLift({ lift(3, 5, { state = "ground" }), lift(2, 5, { class = "both" }) }) == nil)
check("7.x assist: a heavy two-hands piece you carry alone", Brain.pickAssist({ lift(2, 10, { class = "both", weight = H.AssistWeight }) }) == 2)
check("…not a light one", Brain.pickAssist({ lift(2, 10, { class = "both", weight = H.AssistWeight - 1 }) }) == nil)
check("…not farther than AssistFar", Brain.pickAssist({ lift(2, H.AssistFar + 1, { class = "both" }) }) == nil)
check("…not by the van's back already (you load it now)", Brain.pickAssist({ lift(2, 5, { class = "both", byBack = true }) }) == nil)
check("…not a pair piece, not one helped already", Brain.pickAssist({ lift(3, 5), lift(2, 5, { class = "both", helped = true }) }) == nil)

-- Running from zombies -----------------------------------------------------------------------------------------------------

check("no zombie: he stays", not Brain.shouldFlee(nil, false, nil))
check("a zombie within FleeRange: he runs", Brain.shouldFlee(H.FleeRange - 1, false, nil) and Brain.shouldFlee(H.FleeRange, false, "hand"))
check("farther: not yet", not Brain.shouldFlee(H.FleeRange + 2, false, nil))
check("running: on until none is within SafeRange", Brain.shouldFlee(H.SafeRange - 1, true, nil) and not Brain.shouldFlee(H.SafeRange + 1, true, nil))
check("never with the other end of your piece (you lead)", not Brain.shouldFlee(1, true, "pair"))
local fx, fz = Brain.fleeTo(0, 0, 5, 0)
check("he runs FleeStep studs straight away", near(fx, -H.FleeStep) and near(fz, 0), `{fx}, {fz}`)
fx, fz = Brain.fleeTo(3, 4, 3, 4)
check("…a zombie right on him: some way", near(math.sqrt((fx - 3) ^ 2 + (fz - 4) ^ 2), H.FleeStep))

-- What he does now: the priority list ----------------------------------------------------------------------------------------

local function decide(fields: { [string]: any }): (string, number?)
	local input: Brain.Input = { mode = "carry", dead = false, holding = nil, threat = nil, fleeing = false, lift = nil, assist = nil, pick = nil, open = false, atHouse = true }
	for key, value in fields do
		(input :: any)[key] = value
	end
	return Brain.decide(input)
end
check("down", decide({ dead = true, holding = "hand" }) == "down")
check("the other end of your piece first, zombies or not", decide({ holding = "pair", threat = 2, lift = 3, open = true }) == "hold")
check("a zombie near: he runs, with his piece", decide({ holding = "hand", threat = 3, lift = 3 }) == "flee")
local action, spot = decide({ lift = 3, pick = 1, assist = 2 })
check("(a) your two-person lift before anything of his own", action == "help" and spot == 3)
action, spot = decide({ lift = 3, holding = "hand" })
check("…even with a piece in his arms (he loads it or sets it down first)", action == "help" and spot == 3)
check("…and on Help me", decide({ mode = "help", lift = 3 }) == "help")
check("Wait at the van: no lifting", decide({ mode = "wait", lift = 3 }) == "wait")
check("(b) a piece in his arms: to the van (on every order), before an assist", decide({ holding = "hand", pick = 1 }) == "deliver"
	and decide({ holding = "hand", mode = "wait" }) == "deliver" and decide({ holding = "hand", assist = 2 }) == "deliver")
check("(d) the van's back for somebody coming with a piece, before his next piece", decide({ open = true, pick = 1, assist = 2 }) == "open"
	and decide({ open = true, mode = "wait" }) == "open")
action, spot = decide({ assist = 2, pick = 5 })
check("(c) the other side of your heavy two-hands piece before his next one", action == "assist" and spot == 2)
check("…on Help me too, not on Wait at the van", decide({ mode = "help", assist = 2 }) == "assist" and decide({ mode = "wait", assist = 2 }) == "wait")
check("Help me: he follows you", decide({ mode = "help", pick = 1 }) == "follow")
action, spot = decide({ pick = 5 })
check("Carry small stuff: the next piece", action == "fetch" and spot == 5)
check("…only while the van stands by the house", decide({ pick = 5, atHouse = false }) == "wait")
check("nothing to carry: he waits at the van", decide({}) == "wait")

-- The van's back -----------------------------------------------------------------------------------------------------------

check("open and standing: in it goes", Brain.atTruck(true, true, 0, true) == "load" and Brain.atTruck(true, true, 0) == "load")
check("7.x shut: he opens it himself (OpenBack)", Brain.atTruck(false, true, 0, true) == "open" and H.OpenBack == true)
check("…not allowed: he waits a while", Brain.atTruck(false, true, 0, false) == "wait" and Brain.atTruck(false, true, H.WaitShut - 0.1) == "wait")
check("…then sets it down beside the van", Brain.atTruck(false, true, H.WaitShut) == "drop")
check("the van moving: not yet", Brain.atTruck(true, false, 0, true) == "wait")

-- Speeds -------------------------------------------------------------------------------------------------------------------

check("empty-handed: 0.7 × a player's walk", near(Brain.speed(WALK, "fetch", nil, 0), WALK * 0.7) and H.Speed == 0.7)
check("with the lamp: 0.7 × a player's lamp walk", near(Brain.speed(WALK, "deliver", "hand", 1), Rules.carrySpeed(WALK, "hand", 1) * 0.7))
check("…slower than a player with it", Brain.speed(WALK, "deliver", "hand", 3) < Rules.carrySpeed(WALK, "hand", 3))
check("7.x a two-hands piece of his own: slower still", near(Brain.speed(WALK, "deliver", "both", 4), Rules.carrySpeed(WALK, "both", 4) * 0.7)
	and Brain.speed(WALK, "deliver", "both", 4) < Brain.speed(WALK, "deliver", "hand", 4))
check("7.x to your lift: a sprint, faster than your two-person walk", near(Brain.speed(WALK, "help", nil, 0), WALK * H.Sprint)
	and Brain.speed(WALK, "assist", nil, 0) == Brain.speed(WALK, "help", nil, 0) and Brain.speed(WALK, "help", nil, 0) > Rules.carrySpeed(WALK, "pair", 8) * 1.1)
check("running from a zombie: Flee × the walk", near(Brain.speed(WALK, "flee", nil, 0), WALK * H.Flee))

-- Stuck ----------------------------------------------------------------------------------------------------------------------

local stuck = Brain.stuck(0, 1, 0.1, 9.8)
check("walking on: not stuck", stuck == 0)
stuck = Brain.stuck(0, 0.05, 0.1, 9.8)
stuck = Brain.stuck(stuck, 0.05, 0.1, 9.8)
check("no progress: the seconds add up", near(stuck, 0.2))
check("…and progress again clears them", Brain.stuck(stuck, 1, 0.1, 9.8) == 0)
check("7.x stuck under StuckRepath s: he walks on", Brain.unstuck(H.StuckRepath - 0.1) == "walk" and H.StuckRepath == 2)
check("…StuckRepath s: a new path", Brain.unstuck(H.StuckRepath) == "repath" and Brain.unstuck(H.StuckSnap - 0.1) == "repath")
check("…StuckSnap s: a nudge to his way's next point", Brain.unstuck(H.StuckSnap) == "nudge" and H.StuckSnap == 4)

-- The far end of your piece (7.x) ------------------------------------------------------------------------------------------

check("his root Standoff past the far face", near(Brain.farEnd(3.2), 1.6 + H.Standoff))
check("on the floor there: level with you", near(Brain.endRise(-1.75, -1.75), -1.75))
check("…a step up or down: with the floor", near(Brain.endRise(-1, -1.75), -1) and near(Brain.endRise(-3, -1.75), -3))
check("…never off his hands' reach (HoldStep at most)", near(Brain.endRise(9, -1.75), -1.75 + H.HoldStep) and near(Brain.endRise(-40, -1.75), -1.75 - H.HoldStep))
check("…no floor read: level with you", near(Brain.endRise(0 / 0, -1.75), -1.75))

-- 8.1 holding the far end: never put there (the owner: "when I turn around he teleports") ------------------------------

local pairWalk = Rules.carrySpeed(WALK, "pair", 8)
check("8.1 his top speed holding it: the pair's walk × HoldMargin + HoldExtra (about the pair's walk and a margin)",
	near(Brain.holdSpeed(pairWalk), pairWalk * H.HoldMargin + H.HoldExtra) and Brain.holdSpeed(pairWalk) > pairWalk and Brain.holdSpeed(pairWalk) < WALK * H.Sprint * 1.2)
check("…faster with a faster leader (a steady grip, a Mover, the admin's speed), never under HoldExtra", Brain.holdSpeed(pairWalk * 2) > Brain.holdSpeed(pairWalk)
	and near(Brain.holdSpeed(-3), H.HoldExtra))
check("8.1 his body turns to you at HoldTurn × PairTurn at most", near(Brain.holdTurn(), math.rad(H.PairTurn) * H.HoldTurn))
do
	local top = Brain.holdSpeed(pairWalk)
	local trail = Brain.newTrail()
	local snapped, faster = false, false
	for _ = 1, 20 do -- (2 s a step behind his place: a slow swing)
		local limit, snap = Brain.holdTrack(trail, 1.5, false, top, 0.1)
		snapped = snapped or snap
		faster = faster or limit ~= top
	end
	check("8.1 close behind (under HoldBehind studs): his top speed, never put there", not snapped and not faster and trail.behind == 0)
	snapped, faster = false, false
	for _ = 1, 600 do -- (a minute 200 studs behind, far off: still never put there)
		local _, snap = Brain.holdTrack(trail, 200, false, top, 0.1)
		snapped = snapped or snap
	end
	check("…far behind for a minute (200 studs): never put there at once", not snapped)
	trail = Brain.newTrail()
	local first: number? = nil
	local easeSteps, easeSpeed = 0, 0
	for step = 1, 80 do -- (20 studs off, 8 s: stuck behind a wall)
		local limit, snap = Brain.holdTrack(trail, 20, false, top, 0.1)
		snapped = snapped or snap
		if limit > top + 1e-9 then
			first = first or step
			easeSteps += 1
			easeSpeed = limit
		end
	end
	check("8.1 more than HoldBehind studs off for HoldStuck s: eased back (20 studs over HoldEase s: 40 a second), not put there", not snapped and first ~= nil
		and near((first :: number) * 0.1, H.HoldStuck, 0.11) and near(easeSpeed, 20 / H.HoldEase) and easeSpeed > top)
	check("…the ease lasts HoldEase s, then his top speed again (and another ease HoldStuck s later if still stuck)", easeSteps == 2 * math.floor(H.HoldEase / 0.1 + 0.5), easeSteps)
	trail = Brain.newTrail()
	local limit, snap = Brain.holdTrack(trail, 4000, true, top, 0.1)
	check("8.1 only a door's fade puts him there: the piece in the other world", snap and near(limit, top) and trail.behind == 0)
	local _, again = Brain.holdTrack(trail, 0.2, false, top, 0.1)
	check("…and holding on from there: never again", not again)
end

check("7.x your grip bar while he holds the other end: the box Steadied (1.3) × bigger", near(CarryGrip.profile("pair", 8, false, false, true).zone,
	CarryGrip.profile("pair", 8, false, false).zone * Config.CarryGrip.Steadied) and Config.CarryGrip.Steadied == 1.3
	and near(CarryGrip.profile("pair", 8, false, false, false).zone, CarryGrip.profile("pair", 8, false, false).zone))

-- Doorways (7.x: he never stands where you walk through) --------------------------------------------------------------------

local door: Brain.Doorway = { x = 10, z = 0, half = 2, dirX = 0, dirZ = 1, depth = H.Aside.Depth } -- a wall along X, through along Z
local x, z, moved = Brain.aside(10.5, 1, door)
check("in the doorway: beside it, along the wall on his side", moved and near(x, 10 + 2 + H.Aside.Step) and near(z, H.Aside.Off), `{x}, {z}`)
x, z, moved = Brain.aside(9, -2, door)
check("…the other side: the other way", moved and near(x, 10 - 2 - H.Aside.Step) and near(z, -2), `{x}, {z}`)
x, z, moved = Brain.aside(17, 0, door)
check("beside the wall already: where he is", not moved and x == 17 and z == 0)
x, z, moved = Brain.aside(10, 6, door)
check("well into the room: where he is", not moved and x == 10 and z == 6)
local front: Brain.Doorway = { x = 0, z = 0, half = 2, dirX = 1, dirZ = 0, depth = H.Aside.FrontDepth }
x, z, moved = Brain.aside(4, 0.5, front)
check("the porch in front of the front door: beside it", moved and near(x, 4) and near(z, 2 + H.Aside.Step), `{x}, {z}`)

-- His place behind you ------------------------------------------------------------------------------------------------------

local bx, bz = Brain.followSpot(10, 10, 0, -1)
check("Follow studs behind your back", near(bx, 10) and near(bz, 10 + H.Follow))
bx, bz = Brain.followSpot(0, 0, 3, 4)
check("…along your look", near(bx, -3 / 5 * H.Follow) and near(bz, -4 / 5 * H.Follow))

-- Words --------------------------------------------------------------------------------------------------------------------

check("what he does, in words (the van)", Brain.doing("deliver", "Lamp") == "Carrying the Lamp to the van" and Brain.doing("hold", "Sofa") == "Carrying the Sofa with you"
	and Brain.doing("follow") == "Right behind you" and Brain.doing("wait") == "Waiting at the van" and Brain.doing("open") == "Opening the van's back"
	and Brain.doing("assist", "Armchair") == "Taking the other side of the Armchair" and Brain.doing("help", "Sofa") == "Coming to lift the Sofa")
check("…the van full", Brain.doing("wait", nil, true) == "Waiting: the van is full")
check("…something unknown: waiting", Brain.doing("dance") == "Waiting at the van")
check("his lines: Got the other end! On three... lift! Watch the doorframe! That's going in the van.", Brain.Lines.lift == "Got the other end!"
	and Brain.Lines.three == "On three... lift!" and Brain.Lines.door == "Watch the doorframe!" and Brain.Lines.van == "That's going in the van."
	and string.find(Brain.Lines.full, "Van's full, boss", 1, true) == 1 and string.find(Brain.Lines.full, "Wall", 1, true) ~= nil)
local orders = 0
for _, mode in { "help", "carry", "wait" } do
	if type(Brain.Lines[mode .. "Mode"]) == "string" then
		orders += 1
	end
end
check("a line for every order", orders == 3)
local ascii, short, truck = true, true, false
for _, text in Brain.Lines do
	if string.find(text, "[\128-\255]") then
		ascii = false
	end
	if #text > Config.MoveStory.Limits.Bubble then
		short = false
	end
	if string.find(string.lower(text), "truck", 1, true) then
		truck = true
	end
end
check("his lines are plain text (a bubble's font shows them), short, the van's (no truck)", ascii and short and not truck)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
