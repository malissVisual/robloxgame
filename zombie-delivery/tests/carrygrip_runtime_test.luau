-- 7.0 grip: the real server/Moving.luau's grip hook and grip block on tests/runtime/MovingRuntime.luau's fakes (built by
-- tests/run_tests.py as MovingServer.luau): the character attribute CarryGrip while a thing with a bar is carried (a
-- fragile one-hand thing, both hands, a pair thing by two, dragged, a Mover's alone; none for a plain one-hand thing),
-- gone with the carry; the Moving remote's ("grip", spot, quality, steady) wearing the thing a little (capped, one a
-- second or so, a long gap counted short, nonsense nothing) and the steady walk (× 1.1, back when not steady); ("slip",
-- spot) dropping it with the slip's damage (fragile more), a pair thing whole when either carrier slips; and both
-- refused for what the sender does not hold: a stranger, a crew mate's thing, another spot, a thing without a bar.
-- 7.1 review: a "slip" sooner than any bar runs out (HeavyStart / Drain × 0.9 s after the bar began: an old bar's
-- "slip" asked again for a piece picked up again) refused, the bar's start kept when only the kind changes (a helper
-- takes the other end); steady only once a meter could have filled, gone again when the reports stop (2 × Report s);
-- a pair thing by two worn half by each one's reports; nothing from either end while either is on a door trip.
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

local T = Config.Moving
local G = Config.CarryGrip
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
Moving.start()
local said = Moving.admin(ann, "start")
check("the admin's START: a move with Ann and Bob", string.find(said, "started", 1, true) ~= nil, said)
Moving.step()

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
local function heard(player: any, text: string, since: number): boolean
	for index = since + 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then
			return true
		end
	end
	return false
end
local annBody = ann.Character
local bobBody = bob.Character

-- Which carries have a bar ---------------------------------------------------------------------------------------------

pick(ann, 1) -- the lamp: one hand, fragile, weight 1
check("a fragile one-hand thing: a gentle bar (CarryGrip \"hand 1 fragile\")", annBody:GetAttribute("MoveCarry") == 1 and grip(ann) == "hand 1 fragile", grip(ann))
putDown(ann)
check("put down: the bar goes with the carry", annBody:GetAttribute("MoveCarry") == nil and grip(ann) == nil)
pick(ann, 5) -- the box of memories: one hand, not fragile
check("a plain one-hand thing: no bar", annBody:GetAttribute("MoveCarry") == 5 and grip(ann) == nil)
local box0 = thingOf(5).condition
E.request(ann, "slip", 5)
E.now += 1
E.request(ann, "grip", 5, 1, false)
check("…its \"slip\" and \"grip\" do nothing (no bar on it)", annBody:GetAttribute("MoveCarry") == 5 and thingOf(5).condition == box0)
putDown(ann)

-- The wear and the steady walk ------------------------------------------------------------------------------------------

pick(ann, 2) -- the TV: both hands, fragile, weight 4
local walk = Config.Movement.Walk * T.Speed.Both
check("both hands: a bar (\"both 4 fragile\"), the plain walk", grip(ann) == "both 4 fragile" and math.abs(annBody:GetAttribute("CarrySpeed") - walk) < 1e-9, grip(ann))
local tv0 = thingOf(2).condition
E.request(cid, "slip", 2)
E.request(bob, "slip", 2)
E.request(ann, "slip", 3)
E.request(cid, "grip", 2, 1, false)
E.request(bob, "grip", 2, 1, false)
check("a stranger's, a crew mate's or another spot's slip and grip: refused", annBody:GetAttribute("MoveCarry") == 2 and thingOf(2).condition == tv0)
E.now += 1
E.request(ann, "grip", 2, 1, false)
local worn = thingOf(2).condition
local perSecond = math.min(G.Server.Wear * G.Server.WearFragile, G.Server.WearCap)
check("a report fully outside: a little wear (fragile)", worn < tv0 and math.abs(worn - (tv0 - perSecond)) <= 0.006, `{tv0} → {worn}`)
E.now += 0.2
E.request(ann, "grip", 2, 1, false)
check("…another one at once: dropped (about one a second)", thingOf(2).condition == worn)
E.now += 30
E.request(ann, "grip", 2, 99, false)
local afterGap = thingOf(2).condition
check("…after a long gap: counted Gap s at most, the quality capped at 1", math.abs(afterGap - (worn - perSecond * G.Server.Gap)) <= 0.006, `{worn} → {afterGap}`)
E.now += 1
E.request(ann, "grip", 2, 0 / 0, "yes")
E.now += 1
E.request(ann, "grip", 2, "lots", nil)
check("…nonsense wears nothing", thingOf(2).condition == afterGap)
E.now += 1
E.request(ann, "grip", 2, 0, true)
check("steady (nothing outside): the carry's walk × 1.1", math.abs(annBody:GetAttribute("CarrySpeed") - walk * G.Meter.SteadySpeed) < 1e-9, annBody:GetAttribute("CarrySpeed"))
check("…and no wear", thingOf(2).condition == afterGap)
E.now += 1
E.request(ann, "grip", 2, 0.5, true)
check("a \"steady\" that was half outside: not steady, the plain walk again", math.abs(annBody:GetAttribute("CarrySpeed") - walk) < 1e-9, annBody:GetAttribute("CarrySpeed"))

-- A slip ------------------------------------------------------------------------------------------------------------------

E.now += 1
E.request(ann, "grip", 2, 0, true)
local beforeSlip = thingOf(2).condition
local since = #E.messages
E.request(ann, "slip", 2)
local dropped = thingOf(2)
check("\"slip\": the TV drops (on the ground, the hands free, the bar and the steady walk gone)", dropped.state == "ground" and annBody:GetAttribute("MoveCarry") == nil
	and grip(ann) == nil and annBody:GetAttribute("CarrySpeed") == nil)
check("…with the slip's damage, fragile more", math.abs(dropped.condition - (beforeSlip - CarryGrip.slipDamage(true))) <= 0.006 and CarryGrip.slipDamage(true) > CarryGrip.slipDamage(false),
	`{beforeSlip} → {dropped.condition}`)
check("…and Ann is told", heard(ann, "slipped", since))
check("…anchored on the floor, no weld", itemModel(2).PrimaryPart.Anchored and itemModel(2).PrimaryPart:FindFirstChildOfClass("WeldConstraint") == nil)
E.request(ann, "slip", 2)
check("a slip for a thing on the ground: nothing more", thingOf(2).condition == dropped.condition)
pick(ann, 2)
check("picked up again: a new bar, the plain walk (the steady starts over)", grip(ann) == "both 4 fragile" and math.abs(annBody:GetAttribute("CarrySpeed") - walk) < 1e-9)

-- 7.1 review: the server trusts the bar less ---------------------------------------------------------------------------------

local slipGate = G.Meter.HeavyStart / G.Meter.Drain * 0.9
check("no bar runs out sooner than the slip gate (the lowest start at the fastest drain)", slipGate > 1.5 and slipGate < math.min(G.Meter.HeavyStart, G.Meter.Start) / G.Meter.Drain)
local tvAgain = thingOf(2).condition
E.now += 0.3
E.request(ann, "slip", 2) -- (the old bar's "slip" asked again, the piece picked up again a moment ago)
check("a \"slip\" right after the lift (an old bar's, asked again): refused, still in Ann's hands", annBody:GetAttribute("MoveCarry") == 2 and thingOf(2).state == "carried"
	and thingOf(2).condition == tvAgain)
E.request(ann, "grip", 2, 0, true)
check("steady sooner than a meter fills ((1 − 0.85) / Fill s): not yet, the plain walk", math.abs(annBody:GetAttribute("CarrySpeed") - walk) < 1e-9, annBody:GetAttribute("CarrySpeed"))
E.now += 1
E.request(ann, "grip", 2, 0, true)
check("…a second later: steady, × 1.1", math.abs(annBody:GetAttribute("CarrySpeed") - walk * G.Meter.SteadySpeed) < 1e-9, annBody:GetAttribute("CarrySpeed"))
E.now += 1.5
state()
check("no report for 1.5 s: still steady", math.abs(annBody:GetAttribute("CarrySpeed") - walk * G.Meter.SteadySpeed) < 1e-9)
E.now += 1
state()
check("none for more than 2 × Report s (the client's reports stopped): the +10% goes", math.abs(annBody:GetAttribute("CarrySpeed") - walk) < 1e-9, annBody:GetAttribute("CarrySpeed"))
E.request(ann, "grip", 2, 0, true)
check("…the next steady report: back", math.abs(annBody:GetAttribute("CarrySpeed") - walk * G.Meter.SteadySpeed) < 1e-9)
putDown(ann)

-- A pair thing: dragged, by two, either slips ----------------------------------------------------------------------------

check("the roles: Ann the Driver, Bob the Mover", ann:GetAttribute("MoveRole") == "driver" and bob:GetAttribute("MoveRole") == "mover")
pick(ann, 3, "Lift") -- the sofa: a pair thing, weight 8
check("a pair thing alone (not a Mover): dragged, a calm bar (\"drag 8\")", annBody:GetAttribute("MoveCarry") == 3 and grip(ann) == "drag 8", grip(ann))
E.now += 2.5 -- (Ann drags it a while)
local sofa = itemModel(3)
E.place(bob, sofa.PrimaryPart.Position + V3(-1, 0, 0))
promptIn(sofa, "Help lift").Triggered:Fire(bob)
check("Bob takes the other end: each their own bar (\"pair 8\")", bobBody:GetAttribute("MoveCarry") == 3 and grip(ann) == "pair 8" and grip(bob) == "pair 8")
E.request(bob, "slip", 3)
check("7.1 review: Bob's \"slip\" as his bar has just begun: refused", thingOf(3).state == "carried" and bobBody:GetAttribute("MoveCarry") == 3)
local sofaWorn = thingOf(3).condition
for _ = 1, 10 do
	E.now += 1
	E.request(ann, "grip", 3, 1, false)
end
local drop = sofaWorn - thingOf(3).condition
check("7.1 review: by two, each one's report wears it half (10 of Ann's: 10 × Wear / 2)", math.abs(drop - 10 * G.Server.Wear / 2) <= 0.011 and drop < 10 * G.Server.Wear * 0.75,
	`{sofaWorn} → {thingOf(3).condition}`)

-- 7.1 review: a door trip: nothing from either end while either is on it (the other end's fade comes a moment later)
local pairWalk = annBody:GetAttribute("CarrySpeed")
E.now += 1
E.request(ann, "grip", 3, 0, true) -- (Ann steady: the walk waits for Bob's)
check("Ann steady, Bob not (yet): the plain walk", math.abs(annBody:GetAttribute("CarrySpeed") - pairWalk) < 1e-9)
local leave = promptIn(workspace, "Leave house")
local queued: { () -> () } = {}
local runAtOnce = E.task.delay
E.task.delay = function(_: any, callback: any, ...: any) -- (the fades' delays wait: the trips are on until run)
	local args = table.pack(...)
	table.insert(queued, function()
		callback(table.unpack(args, 1, args.n))
	end)
end
E.place(ann, leave.Parent.Position)
leave.Triggered:Fire(ann)
check("Ann at the door with the sofa: her trip begins (its fade)", #queued == 1 and E.last(ann, "Moving", "fade").a == "out")
E.request(bob, "slip", 3)
E.request(bob, "grip", 3, 0, true)
check("…Bob's \"slip\" and steady report during her trip: refused (the sofa in their hands, the plain walk)", thingOf(3).state == "carried"
	and bobBody:GetAttribute("MoveCarry") == 3 and math.abs(annBody:GetAttribute("CarrySpeed") - pairWalk) < 1e-9)
table.remove(queued, 1)() -- (Ann's trip: out of the house; Bob comes along: his own trip begins)
check("Ann's trip done, Bob's on (his fade)", #queued == 1 and E.last(bob, "Moving", "fade").a == "out")
E.request(ann, "slip", 3)
check("…Ann's \"slip\" during Bob's trip: refused", thingOf(3).state == "carried" and annBody:GetAttribute("MoveCarry") == 3)
table.remove(queued, 1)()
E.task.delay = runAtOnce
E.place(bob, sofa.PrimaryPart.Position + V3(-1, 0, 0)) -- (no physics here: the sofa stayed where it was)
E.request(bob, "grip", 3, 0, true)
check("both trips done: Bob's steady report counts, both steady: × 1.1", math.abs(annBody:GetAttribute("CarrySpeed") - pairWalk * G.Meter.SteadySpeed) < 1e-9,
	annBody:GetAttribute("CarrySpeed"))
local sofa0 = thingOf(3).condition
since = #E.messages
E.request(bob, "slip", 3)
local sofaNow = thingOf(3)
check("the helper slips: the whole sofa goes down, both hands free", sofaNow.state == "ground" and annBody:GetAttribute("MoveCarry") == nil and bobBody:GetAttribute("MoveCarry") == nil
	and grip(ann) == nil and grip(bob) == nil)
check("…the slip's damage (not fragile), both told", math.abs(sofaNow.condition - (sofa0 - CarryGrip.slipDamage(false))) <= 0.006 and heard(bob, "slipped", since)
	and heard(ann, "lost their grip", since), sofaNow.condition)
pick(bob, 6, "Lift") -- the marble slab: a pair thing, weight 10
check("a Mover lifts a pair thing alone: a harder bar (\"solo 10\")", bobBody:GetAttribute("MoveCarry") == 6 and grip(bob) == "solo 10", grip(bob))
local slab0 = thingOf(6).condition
E.now += 1
E.request(ann, "grip", 6, 1, false)
E.request(ann, "slip", 6)
check("Ann's grip and slip for Bob's slab: refused", bobBody:GetAttribute("MoveCarry") == 6 and thingOf(6).condition == slab0)
E.now += 1
E.request(bob, "grip", 6, 1, false)
check("Bob's own report wears it (not fragile: less)", thingOf(6).condition < slab0 and math.abs(thingOf(6).condition - (slab0 - G.Server.Wear)) <= 0.006)
local slab = itemModel(6)
E.place(ann, slab.PrimaryPart.Position + V3(-1, 0, 0))
promptIn(slab, "Help lift").Triggered:Fire(ann)
check("7.1 review: Ann takes the slab's other end: another kind for Bob (\"pair 10\"), the same carry", grip(bob) == "pair 10" and grip(ann) == "pair 10", grip(bob))
E.request(bob, "slip", 6)
check("…his bar's start kept: his \"slip\" lands at once (it began 2 s ago), the slab down, both bars gone", thingOf(6).state == "ground" and grip(bob) == nil
	and grip(ann) == nil and bobBody:GetAttribute("MoveCarry") == nil)

Moving.admin(ann, "end")
check("the move ends: nobody keeps a bar", grip(ann) == nil and grip(bob) == nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
