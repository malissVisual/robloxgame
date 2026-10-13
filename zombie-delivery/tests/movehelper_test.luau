-- 7.0, the depot's helper ("Danny from the depot"): his decisions (shared/MoveHelperBrain.luau, pure). Who gets him,
-- which thing he carries next (★ first, then the nearest; never a "both" or a pair thing, a broken one, one that no
-- longer fits the truck, one waiting by the shut truck), which lift he comes to help with, when he runs from a zombie,
-- what he does now (the priorities), the truck's back, his speeds (slower than a player), stuck and left behind, his
-- place behind you and his words. tests/movehelper_runtime_test.luau runs the server side.
local Brain = require("./MoveHelperBrain")
local Config = require("./Config")
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
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
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

-- Which thing next ---------------------------------------------------------------------------------------------------------

local function thing(spot: number, class: string, cost: number, extra: { [string]: any }?): Brain.Candidate
	local c: Brain.Candidate = { spot = spot, class = class, state = "home", star = false, broken = false, cost = cost, fits = true, byTruck = false }
	for key, value in extra or {} do
		(c :: any)[key] = value
	end
	return c
end

local list = {
	thing(1, "hand", 10), -- the lamp
	thing(2, "both", 2), -- the TV: never alone
	thing(3, "pair", 1), -- the sofa: never alone
	thing(4, "both", 3, { star = true }), -- Grandpa's clock (★, both): never alone
	thing(5, "hand", 30, { star = true }), -- the box of memories (★)
	thing(6, "hand", 1, { broken = true }), -- a broken one pays nothing
	thing(7, "hand", 1, { state = "carried" }), -- somebody has it
	thing(8, "hand", 1, { state = "truck" }), -- in the truck already
}
local pick, full = Brain.pickItem(list, true)
check("★ first: the box of memories, though the lamp is nearer", pick == 5 and full == false, pick)
list[5].star = false
pick = Brain.pickItem(list, true)
check("no ★ left: the nearest one-hand thing (the lamp)", pick == 1, pick)
list[1].cost = 40
pick = Brain.pickItem(list, true)
check("…the nearer one wins (the box)", pick == 5, pick)
list[5].fits = false
pick, full = Brain.pickItem(list, true)
check("one that no longer fits the truck: the next one", pick == 1 and full == false, pick)
list[1].fits = false
pick, full = Brain.pickItem(list, true)
check("nothing fits: none, and the truck is full", pick == nil and full == true)
local byTruck = { thing(9, "hand", 3, { state = "ground", byTruck = true }) }
pick, full = Brain.pickItem(byTruck, false)
check("set down by the shut truck: it waits (not 'full')", pick == nil and full == false)
pick = Brain.pickItem(byTruck, true)
check("…the back open: he takes it in", pick == 9)
pick, full = Brain.pickItem({ thing(2, "both", 1), thing(3, "pair", 1) }, true)
check("only 'both' and pair things left: nothing for him alone", pick == nil and full == false)
pick = Brain.pickItem({ thing(1, "hand", 5, { state = "ground" }) }, true)
check("a thing on the ground counts", pick == 1)

-- Which lift ---------------------------------------------------------------------------------------------------------------

local function lift(spot: number, cost: number, extra: { [string]: any }?): Brain.Lift
	local l: Brain.Lift = { spot = spot, class = "pair", state = "carried", helped = false, crew = true, cost = cost, gaveUp = false }
	for key, value in extra or {} do
		(l :: any)[key] = value
	end
	return l
end
check("a crew player drags a pair thing alone: he comes", Brain.pickLift({ lift(3, 20) }) == 3)
check("the nearer of two", Brain.pickLift({ lift(3, 20), lift(6, 12) }) == 6)
check("not one somebody holds the other end of", Brain.pickLift({ lift(3, 20, { helped = true }) }) == nil)
check("not a stranger's", Brain.pickLift({ lift(3, 20, { crew = false }) }) == nil)
check("not one he gave up on", Brain.pickLift({ lift(3, 20, { gaveUp = true }) }) == nil)
check("not from farther than HelpFar", Brain.pickLift({ lift(3, H.HelpFar + 1) }) == nil and Brain.pickLift({ lift(3, H.HelpFar) }) == 3)
check("not one on the ground or a both thing", Brain.pickLift({ lift(3, 5, { state = "ground" }), lift(2, 5, { class = "both" }) }) == nil)

-- Running from zombies -----------------------------------------------------------------------------------------------------

check("no zombie: he stays", not Brain.shouldFlee(nil, false, nil))
check("a zombie within FleeRange: he runs", Brain.shouldFlee(H.FleeRange - 1, false, nil) and Brain.shouldFlee(H.FleeRange, false, "hand"))
check("farther: not yet", not Brain.shouldFlee(H.FleeRange + 2, false, nil))
check("running: on until none is within SafeRange", Brain.shouldFlee(H.SafeRange - 1, true, nil) and not Brain.shouldFlee(H.SafeRange + 1, true, nil))
check("never with his end of a pair thing (the player leads)", not Brain.shouldFlee(1, true, "pair"))
local fx, fz = Brain.fleeTo(0, 0, 5, 0)
check("he runs FleeStep studs straight away", near(fx, -H.FleeStep) and near(fz, 0), `{fx}, {fz}`)
fx, fz = Brain.fleeTo(3, 4, 3, 4)
check("…a zombie right on him: some way", near(math.sqrt((fx - 3) ^ 2 + (fz - 4) ^ 2), H.FleeStep))

-- What he does now ---------------------------------------------------------------------------------------------------------

local function decide(fields: { [string]: any }): (string, number?)
	local input: Brain.Input = { mode = "carry", dead = false, holding = nil, threat = nil, fleeing = false, lift = nil, pick = nil, atHouse = true }
	for key, value in fields do
		(input :: any)[key] = value
	end
	return Brain.decide(input)
end
check("down", decide({ dead = true, holding = "hand" }) == "down")
check("his end of a pair thing first, zombies or not", decide({ holding = "pair", threat = 2, lift = 3 }) == "hold")
check("a zombie near: he runs, with his thing", decide({ holding = "hand", threat = 3, lift = 3 }) == "flee")
local action, spot = decide({ lift = 3, pick = 1 })
check("the player's lift before his own work", action == "help" and spot == 3)
action, spot = decide({ lift = 3, holding = "hand" })
check("…even with a thing in his arms (he sets it down first)", action == "help" and spot == 3)
check("…and on Help me", decide({ mode = "help", lift = 3 }) == "help")
check("Wait at the truck: no lifting", decide({ mode = "wait", lift = 3 }) == "wait")
check("a thing in his arms: to the truck (on every order)", decide({ holding = "hand", pick = 1 }) == "deliver" and decide({ holding = "hand", mode = "wait" }) == "deliver")
check("Help me: he follows you", decide({ mode = "help", pick = 1 }) == "follow")
action, spot = decide({ pick = 5 })
check("Carry small stuff: the next thing", action == "fetch" and spot == 5)
check("…only while the truck stands by the house", decide({ pick = 5, atHouse = false }) == "wait")
check("nothing to carry: he waits at the truck", decide({}) == "wait")

-- The truck's back ---------------------------------------------------------------------------------------------------------

check("open and standing: in it goes", Brain.atTruck(true, true, 0) == "load")
check("shut: he waits a while", Brain.atTruck(false, true, 0) == "wait" and Brain.atTruck(false, true, H.WaitShut - 0.1) == "wait")
check("…then sets it down beside the truck", Brain.atTruck(false, true, H.WaitShut) == "drop")
check("the truck moving: not yet", Brain.atTruck(true, false, 0) == "wait")

-- Speeds -------------------------------------------------------------------------------------------------------------------

check("empty-handed: 0.7 × a player's walk", near(Brain.speed(WALK, "fetch", nil, 0), WALK * 0.7) and H.Speed == 0.7)
check("with the lamp: 0.7 × a player's lamp walk", near(Brain.speed(WALK, "deliver", "hand", 1), Rules.carrySpeed(WALK, "hand", 1) * 0.7))
check("…slower than a player with it", Brain.speed(WALK, "deliver", "hand", 3) < Rules.carrySpeed(WALK, "hand", 3))
check("his end of the sofa: he keeps up with the pair's walk", Brain.speed(WALK, "hold", nil, 8) >= Rules.carrySpeed(WALK, "pair", 8)
	and near(Rules.carrySpeed(WALK, "pair", 8), WALK * 0.8))
check("running from a zombie: Flee × the walk", near(Brain.speed(WALK, "flee", nil, 0), WALK * H.Flee))

-- Stuck, left behind -------------------------------------------------------------------------------------------------------

local stuck = Brain.stuck(0, 1, 0.1, 9.8)
check("walking on: not stuck", stuck == 0)
stuck = Brain.stuck(0, 0.05, 0.1, 9.8)
stuck = Brain.stuck(stuck, 0.05, 0.1, 9.8)
check("no progress: the seconds add up", near(stuck, 0.2))
check("…and progress again clears them", Brain.stuck(stuck, 1, 0.1, 9.8) == 0)
local apartFor, letGo = Brain.apart(0, 3, 6, 0.1)
check("his end within reach", apartFor == 0 and not letGo)
apartFor, letGo = 0, false
for _ = 1, 29 do
	apartFor, letGo = Brain.apart(apartFor, 9, 6, 0.1)
end
check("out of reach for 2.9 s: he still holds on", not letGo and math.abs(apartFor - 2.9) < 1e-3)
apartFor, letGo = Brain.apart(apartFor, 9, 6, 0.1)
apartFor, letGo = Brain.apart(apartFor, 9, 6, 0.1)
check("…over HelpWait (3 s): he lets go (the player drags alone)", letGo and H.HelpWait == 3)
check("back within reach: the count starts again", (Brain.apart(apartFor, 2, 6, 0.1)) == 0)

-- His place behind you ------------------------------------------------------------------------------------------------------

local bx, bz = Brain.followSpot(10, 10, 0, -1)
check("Follow studs behind your back", near(bx, 10) and near(bz, 10 + H.Follow))
bx, bz = Brain.followSpot(0, 0, 3, 4)
check("…along your look", near(bx, -3 / 5 * H.Follow) and near(bz, -4 / 5 * H.Follow))

-- Words --------------------------------------------------------------------------------------------------------------------

check("what he does, in words", Brain.doing("deliver", "Lamp") == "Carrying the Lamp to the truck" and Brain.doing("hold", "Sofa") == "Lifting the Sofa with you"
	and Brain.doing("follow") == "Right behind you" and Brain.doing("wait") == "Waiting at the truck")
check("…the truck full", Brain.doing("wait", nil, true) == "Waiting: the truck is full")
check("…something unknown: waiting", Brain.doing("dance") == "Waiting at the truck")
check("his lines: Got your back! Lift on three! Truck's full, boss.", string.find(Brain.Lines.hello, "Got your back!", 1, true) ~= nil and Brain.Lines.help == "Got your back!"
	and Brain.Lines.lift == "Lift on three!" and Brain.Lines.full == "Truck's full, boss.")
local orders = 0
for _, mode in { "help", "carry", "wait" } do
	if type(Brain.Lines[mode .. "Mode"]) == "string" then
		orders += 1
	end
end
check("a line for every order", orders == 3)
local ascii = true
for _, text in Brain.Lines do
	if string.find(text, "[\128-\255]") then
		ascii = false
	end
end
check("his lines are plain text (a bubble's font shows them)", ascii)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
