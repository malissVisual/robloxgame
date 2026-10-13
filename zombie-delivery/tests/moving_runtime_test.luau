-- 7.0 prototype, MOVES: the real server/Moving.luau run in the Luau CLI (tests/run_tests.py builds MovingServer.luau
-- with tests/runtime/MovingRuntime.luau's fakes in place of its server modules; the art is a fake shaped like the art
-- branch's FurnitureLooks / HouseLayout / HouseInterior). A whole move: the board's card, START (the truck, the
-- interior), the crew, the door in and out with its fades, picking up, dragging and lifting in two, the truck's back,
-- loading and the no-room refusal, unloading, the damage, a death, a helper too far, a teleport with a thing, the horde,
-- the delivery's pay split, and the edges: a stranger, the owner leaving, the truck lost, the admin's commands.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local Config = require("./Config")
local Map = require("./Map")

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
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace

-- the places
local depot = V3(Map.Depot.x, 3, Map.Depot.z)
local board = V3(Map.Depot.x + T.Board[1], 3, Map.Depot.z + T.Board[2])
local home = Map.home(T.Contracts[1].home) :: any
local door = V3(home.door.x, 3, home.door.z)
local facing = V3(home.facing.x, 0, home.facing.z)
local outside = door + facing * 3
E.truckAt = V3(home.park.x, 2, home.park.z) -- (placeNear's spot: the test drives it to the house at once)

local ann = E.player(11, "Ann", board + V3(-3, 0, 0))
local bob = E.player(22, "Bob", board + V3(-4, 0, 2))
local cid = E.player(33, "Cid", depot)
E.crew[ann] = { bob }

Moving.useArt(E.art)
Moving.start()

local moves = workspace:FindFirstChild("Moves")
check("the Moves folder: the board, the drop-off, the house's door", moves ~= nil and moves:FindFirstChild("MovingBoard") ~= nil and moves:FindFirstChild("MovingDropOff") ~= nil
	and moves:FindFirstChild("Move_marge") ~= nil)

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

-- The contract card ------------------------------------------------------------------------------------------------------

local boardPrompt = promptIn(moves:FindFirstChild("MovingBoard"), "Moving contracts")
check("the board's prompt", boardPrompt ~= nil)
trigger(boardPrompt, ann)
local card = E.last(ann, "Moving", "contract")
check("the board opens the contract card", card ~= nil and card.a.id == "marge" and card.a.name == "Marge's House")
check("the card: the ★ must-haves, the things, the pay, the time", card ~= nil and #card.a.stars == 3 and card.a.items == 6 and card.a.estimate > 0 and card.a.time == T.Time and card.a.busy == nil,
	card and card.a.busy)
local cardFromFar = #E.messages
E.place(cid, depot + V3(-80, 0, 0))
trigger(boardPrompt, cid)
check("not from across the yard", #E.messages == cardFromFar)
E.request(cid, "start", "marge")
check("START without the card: refused", string.find(E.lastNotice(cid), "board", 1, true) ~= nil and E.cars[cid] == nil, E.lastNotice(cid))
E.request(bob, "start", "marge")
check("a crew member does not take it (their owner does)", string.find(E.lastNotice(bob), "crew", 1, true) ~= nil, E.lastNotice(bob))

-- START ------------------------------------------------------------------------------------------------------------------

E.request(ann, "start", "marge")
local truck = E.cars[ann]
check("START: the truck is lent", truck ~= nil and truck.id == T.Truck, E.lastNotice(ann))
check("…and the interior is built", E.built == 1 and #E.interiors == 1)
check("everybody of the crew hears it", string.find(E.lastNotice(bob), "Move started", 1, true) ~= nil)
Moving.step()
check("the crew is on the move (MoveWith)", ann:GetAttribute("MoveWith") == 11 and bob:GetAttribute("MoveWith") == 11 and cid:GetAttribute("MoveWith") == nil)
local view = E.last(ann, "Moving", "state")
check("the state: 6 things, 3 ★, the clock", view ~= nil and view.a ~= nil and #view.a.items == 6 and view.a.counts.stars == 3 and view.a.endsAt == E.now + T.Time and view.a.mine == true)
check("…and Bob's says it is Ann's", E.last(bob, "Moving", "state") ~= nil and E.last(bob, "Moving", "state").a.mine == false)
E.request(ann, "start", "marge")
check("no second move at once", string.find(E.lastNotice(ann), "already", 1, true) ~= nil, E.lastNotice(ann))

-- The door ---------------------------------------------------------------------------------------------------------------

local site = moves:FindFirstChild("Move_marge")
local enter = promptIn(site, "Enter house")
E.place(cid, outside)
trigger(enter, cid)
check("a stranger's door is locked", string.find(E.lastNotice(cid), "Locked", 1, true) ~= nil and (E.rootOf(cid).Position - outside).Magnitude < 1)
E.place(ann, outside)
local before = #E.messages
trigger(enter, ann)
local origin = E.interiors[1]
local inside = origin * M.CFrame.new(0, 0, 1)
check("Enter house: in the interior", (E.rootOf(ann).Position - inside.Position).Magnitude < 4, E.rootOf(ann).Position)
local fades = 0
for index = before + 1, #E.messages do
	if E.messages[index].kind == "fade" and E.messages[index].player == ann then
		fades += 1
	end
end
check("…with a fade out and in", fades == 2)
E.place(bob, door + facing * 30)
trigger(enter, bob)
check("not from the street", (E.rootOf(bob).Position - door).Magnitude > 20)

-- Pick up, carry, the truck ------------------------------------------------------------------------------------------------

local items = workspace:FindFirstChild("Interior"):FindFirstChild("Items")
local function itemModel(spot: number): any
	for _, model in items:GetChildren() do
		if model:GetAttribute("Spot") == spot then
			return model
		end
	end
	for _, model in moves:GetChildren() do
		if model:GetAttribute("MoveSpot") == spot then
			return model
		end
	end
	return nil
end
local lamp = itemModel(1)
local lampRoot = lamp.PrimaryPart
local pick = promptIn(lamp, "Pick up")
check("a thing has its Pick up", pick ~= nil and pick.Enabled and pick:GetAttribute("MoveOwner") == 11)
E.place(cid, lampRoot.Position)
trigger(pick, cid)
check("a stranger can't take it", pick.Enabled and ann.Character:GetAttribute("MoveCarry") == nil)
E.place(ann, lampRoot.Position + V3(2, 0, 0))
trigger(pick, ann)
local character = ann.Character
check("picked up: the carry's attributes", character:GetAttribute("Carrying") == "crate" and character:GetAttribute("MoveCarry") == 1 and character:GetAttribute("CarryHands") == 1)
check("the lamp's walk: 14 × 0.97", math.abs((character:GetAttribute("CarrySpeed") or 0) - 14 * 0.97) < 1e-6, character:GetAttribute("CarrySpeed"))
check("welded to the root, out of the interior's model", lampRoot:FindFirstChildOfClass("WeldConstraint") ~= nil and lamp.Parent == moves and not lampRoot.Anchored)
check("the gun goes away", E.holstered >= 1)
check("a Put down (G) only for its carrier", (function()
	local down = promptIn(lamp, "Put down")
	return down ~= nil and down:GetAttribute("MoveOnly") == 11 and down.KeyboardKeyCode == "G"
end)())
local tv = itemModel(2)
trigger(promptIn(tv, "Pick up"), ann)
check("one thing at a time", string.find(E.lastNotice(ann), "full", 1, true) ~= nil)
E.clock += 1
Moving.step()
local leave = promptIn(workspace, "Leave house")
check("the Leave house prompt by the door inside", leave ~= nil)
E.place(ann, origin.Position + V3(0, 3, 1))
E.clock += 0.2
Moving.step()
trigger(leave, ann)
check("Leave house: out at the door with the lamp", (E.rootOf(ann).Position - outside).Magnitude < 4 and character:GetAttribute("MoveCarry") == 1, E.rootOf(ann).Position)
-- at the truck's back
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
E.clock += 0.2
Moving.step()
local load = promptIn(truck.model, "Load")
check("the truck's Load prompt waits while the back is shut", load ~= nil and not load.Enabled)
trigger(load, ann)
check("Load with the back shut says so", string.find(E.lastNotice(ann), "Open the back", 1, true) ~= nil, E.lastNotice(ann))
truck.model:SetAttribute("BackOpen", true)
E.clock += 0.2
Moving.step()
local backPrompt = cargoDoor:FindFirstChild("BackPrompt")
check("back open, a thing carried: Load shows, the back's own E waits", load.Enabled and not backPrompt.Enabled and string.find(load.ActionText, "Lamp", 1, true) ~= nil, load.ActionText)
check("the crew may open the back (BackCrew, backAllowed)", truck.model:GetAttribute("BackCrew") == "22")
trigger(load, ann)
check("loaded: hands free, in the truck", character:GetAttribute("MoveCarry") == nil and character:GetAttribute("Carrying") == nil and string.find(E.lastNotice(ann), "loaded", 1, true) ~= nil, E.lastNotice(ann))
local weld = lampRoot:FindFirstChildOfClass("WeldConstraint")
check("…welded to the truck, inside its box", weld ~= nil and weld.Part0 == truck.chassis and (lampRoot.Position - truck.chassis.Position).Magnitude < 12)
E.clock += 0.2
Moving.step()
local unload = promptIn(truck.model, "Unload")
check("Unload (Z) shows the last one in", unload ~= nil and unload.Enabled and unload.KeyboardKeyCode == "Z" and string.find(unload.ActionText, "Lamp", 1, true) ~= nil)
trigger(unload, ann)
check("unloaded into your hands", character:GetAttribute("MoveCarry") == 1 and lampRoot:FindFirstChildOfClass("WeldConstraint").Part0 == E.rootOf(ann))
trigger(load, ann)
check("and back in", character:GetAttribute("MoveCarry") == nil)

-- Two people: the sofa ----------------------------------------------------------------------------------------------------

E.place(ann, outside)
trigger(enter, ann)
E.place(bob, outside)
trigger(enter, bob)
local sofa = itemModel(3)
local sofaRoot = sofa.PrimaryPart
local lift = promptIn(sofa, "Lift")
check("a pair thing says Lift", lift ~= nil)
E.place(bob, sofaRoot.Position + V3(0, 0, -3))
trigger(lift, bob)
local bobBody = bob.Character
check("alone: dragged at 0.35", bobBody:GetAttribute("MoveCarry") == 3 and math.abs((bobBody:GetAttribute("CarrySpeed") or 0) - 14 * 0.35) < 1e-6)
local help = promptIn(sofa, "Help lift")
check("Help lift shows for the others, not the carrier", help ~= nil and help.Enabled and help:GetAttribute("MoveSkip") == 22)
trigger(help, bob)
check("you can't help yourself", string.find(E.lastNotice(bob), "already", 1, true) ~= nil, E.lastNotice(bob))
E.place(ann, sofaRoot.Position + V3(0, 0, 3))
trigger(help, ann)
check("two carry it at 0.8", math.abs((bobBody:GetAttribute("CarrySpeed") or 0) - 14 * 0.8) < 1e-6 and math.abs((character:GetAttribute("CarrySpeed") or 0) - 14 * 0.8) < 1e-6
	and character:GetAttribute("MoveCarry") == 3)
check("…and Help lift is gone", not help.Enabled)
-- the carrier leaves the house: the helper comes along
E.place(bob, origin.Position + V3(0, 3, 1))
trigger(leave, ann)
check("the helper does not lead the way", string.find(E.lastNotice(ann), "front", 1, true) ~= nil)
trigger(leave, bob)
check("the carrier leads out, the helper comes along", (E.rootOf(bob).Position - outside).Magnitude < 4 and (E.rootOf(ann).Position - outside).Magnitude < 6)
-- too far apart for Grace s: it goes down
E.clock += 0.2
Moving.step()
E.place(ann, E.rootOf(bob).Position + V3(30, 0, 0))
E.clock += 0.2
Moving.step()
E.place(bob, E.rootOf(bob).Position + V3(0, 0, 0.5))
E.clock += T.Grace + 0.3
Moving.step()
check("the pair too far apart: it went down", bobBody:GetAttribute("MoveCarry") == nil and character:GetAttribute("MoveCarry") == nil and sofaRoot.Anchored and string.find(E.lastNotice(bob), "apart", 1, true) ~= nil,
	E.lastNotice(bob))
-- picked up again and loaded by two
E.place(ann, sofaRoot.Position + V3(1, 0, 0))
E.place(bob, sofaRoot.Position + V3(-1, 0, 0))
trigger(lift, bob)
trigger(help, ann)
E.place(bob, cargoDoor.WorldPosition + V3(0, 0, 2))
E.place(ann, cargoDoor.WorldPosition + V3(1, 0, 3))
E.clock += 0.2
Moving.step()
trigger(load, ann)
check("the helper doesn't load", string.find(E.lastNotice(ann), "front", 1, true) ~= nil, E.lastNotice(ann))
trigger(load, bob)
check("the carrier loads it; both hands free", bobBody:GetAttribute("MoveCarry") == nil and character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(bob), "Sofa", 1, true) ~= nil, E.lastNotice(bob))

-- Damage, a death, a teleport, no room -------------------------------------------------------------------------------------

E.place(ann, outside)
trigger(enter, ann)
local clock = itemModel(4)
E.place(ann, clock.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(clock, "Pick up"), ann)
local humanoid = character:FindFirstChildOfClass("Humanoid")
humanoid.Health = 80
humanoid.HealthChanged:Fire(80)
local function stateOf(player: any, spot: number): any
	local v = E.last(player, "Moving", "state")
	for _, item in (v and v.a and v.a.items) or {} do
		if item.spot == spot then
			return item
		end
	end
	return nil
end
E.clock += 0.3
Moving.step()
local hit = stateOf(ann, 4)
check("a bite knocks the fragile clock", hit ~= nil and hit.condition < 1 and math.abs(hit.condition - (1 - 20 * T.Damage.PerHp * T.Damage.Fragile)) < 0.01, hit and hit.condition)
humanoid.Health = 0
humanoid.Died:Fire()
E.clock += 0.3
Moving.step()
local dead = stateOf(ann, 4)
check("its carrier died: it lies on the floor, knocked again", dead ~= nil and dead.state == "ground" and dead.condition < hit.condition and character:GetAttribute("MoveCarry") == nil)
check("…anchored where it fell", clock.PrimaryPart.Anchored and clock.PrimaryPart:FindFirstChildOfClass("WeldConstraint") == nil)
humanoid.Health = 100
-- a teleport with a thing in your hands: it goes down where you were
E.place(ann, clock.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(clock, "Pick up"), ann)
E.clock += 0.2
Moving.step()
E.place(ann, E.rootOf(ann).Position + V3(300, 0, 0))
E.clock += 0.2
Moving.step()
check("too fast with it (a teleport): down where you were", character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(ann), "Too fast", 1, true) ~= nil and (clock.PrimaryPart.Position - E.rootOf(ann).Position).Magnitude > 200,
	E.lastNotice(ann))
-- the big slab: no room after the sofa
local slab = itemModel(6)
E.place(ann, slab.PrimaryPart.Position + V3(2, 0, 0))
trigger(promptIn(slab, "Lift"), ann)
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(leave, ann)
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
E.clock += 0.2
Moving.step()
trigger(load, ann)
check("no room: it stays in your hands, the words say so", character:GetAttribute("MoveCarry") == 6 and string.find(E.lastNotice(ann), "No room", 1, true) ~= nil, E.lastNotice(ann))
E.Net.get("PutDown").OnServerEvent:Fire(ann)
check("the touch PUT DOWN (the PutDown remote) sets it down", character:GetAttribute("MoveCarry") == nil and slab.PrimaryPart.Anchored)
E.request(bob, "giveup")
check("only the owner gives up", E.last(bob, "Moving", "result") == nil)
E.request(ann, "giveup")
check("GIVE UP calls it off", E.last(ann, "Moving", "result") ~= nil and E.last(ann, "Moving", "result").a.how == "cancelled" and E.last(bob, "Moving", "result") ~= nil)
check("called off: no pay, the interior gone, nobody on it", #E.money == 0 and E.destroyed == 1 and ann:GetAttribute("MoveWith") == nil and bob:GetAttribute("MoveWith") == nil)

-- The horde, the delivery ------------------------------------------------------------------------------------------------

E.place(ann, depot)
local said = Moving.admin(ann, "start")
check("the admin's START", string.find(said, "started", 1, true) ~= nil and E.built == 2, said)
truck = E.cars[ann]
cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
load = promptIn(truck.model, "Load")
Moving.step()
E.place(ann, outside)
enter = promptIn(site, "Enter house")
trigger(enter, ann)
items = workspace:FindFirstChild("Interior") -- (the new interior: the first is gone)
local function newItem(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
local box = newItem(5)
E.place(ann, box.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(box, "Pick up"), ann)
origin = E.interiors[2]
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(promptIn(workspace, "Leave house"), ann)
truck.model:SetAttribute("BackOpen", true)
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
E.clock += 0.2
Moving.step()
trigger(load, ann)
check("the box of memories (★) in the truck", ann.Character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(ann), "loaded", 1, true) ~= nil, E.lastNotice(ann))
check("during the move the truck stays: no CAR swap, no taking it back", E.Jobs.returnLent(ann) == false and string.find(E.Vehicles.callCar(ann, nil) or "", "moving truck", 1, true) ~= nil)
check("the crew is hunted (no ordinary roamers round them), a stranger not", E.Zombies.hunts(bob) == true and E.Zombies.hunts(ann) == true and E.Zombies.hunts(cid) == false)
check("the crew may open the truck's back, a stranger not", E.Vehicles.backAllowed(bob, truck) == true and E.Vehicles.backAllowed(cid, truck) == false)
E.Zombies.onCarDamaged(ann, 100)
E.clock += 0.3
Moving.step()
local knocked = stateOf(ann, 5)
check("the truck's knocks knock its load", knocked ~= nil and math.abs(knocked.condition - (1 - 100 * T.Damage.PerTruckHp)) < 0.01, knocked and knocked.condition)
E.now += T.Time - T.HordeAt + 1
E.clock += 1
Moving.step()
check("the horde at HordeAt left: zombies march on the house", E.marched > 0 and string.find(E.lastNotice(ann), "HORDE", 1, true) ~= nil and E.last(ann, "Moving", "state").a.horde == true)
local roamers = 0
for _, z in E.zombies do
	if z.roamer then
		roamers += 1
	end
end
check("a few roam round the house while you are outside", roamers > 0 and roamers <= T.Roam.Count)
-- drive to the Wall: the truck within DropRadius of the drop-off
local wall = V3(Map.Depot.x + T.DropOff[1], 2, Map.Depot.z + T.DropOff[2])
truck.chassis.CFrame = M.CFrame.new(wall.X + 5, wall.Y, wall.Z)
E.place(ann, wall + V3(0, 1, 0))
E.place(bob, wall + V3(4, 1, 0))
E.clock += 0.2
Moving.step()
local result = E.last(ann, "Moving", "result")
check("delivered at the Wall: the result card", result ~= nil and result.a.how == "done" and result.a.delivered == 1 and result.a.stars >= 1)
local paidAnn, paidBob = 0, 0
for _, entry in E.money do
	if entry.reason == "MovePay" then
		if entry.player == ann then
			paidAnn += entry.amount
		elseif entry.player == bob then
			paidBob += entry.amount
		end
	end
end
check("the pay split with the crew at the truck (MovePay)", paidAnn > 0 and paidBob > 0 and paidAnn > paidBob and result.a.money == paidAnn, `{paidAnn} {paidBob}`)
check("XP for both", #E.xp >= 2)
local tracked = false
for _, entry in E.tracked do
	if entry.name == "event" and entry.args[2] == "MoveDone" then
		tracked = true
	end
end
check("analytics: MoveDone", tracked)
check("the session is gone: the hooks let the truck go again", ann:GetAttribute("MoveWith") == nil and E.destroyed == 2 and E.Jobs.returnLent(ann) == true
	and E.Vehicles.callCar(ann, nil) == "called" and E.Zombies.hunts(bob) == false)
check("the horde let go", (function()
	for _, z in E.zombies do
		if z.march ~= nil then
			return false
		end
	end
	return true
end)())

-- The owner leaves; the truck lost; the admin's other commands ---------------------------------------------------------------

check("no move: the admin says so", string.find(Moving.admin(ann, "horde"), "not running", 1, true) ~= nil)
Moving.admin(ann, "start")
Moving.step()
truck = E.cars[ann]
E.cars[ann] = nil -- (another vehicle took its place)
Moving.step()
result = E.last(ann, "Moving", "result")
check("the truck gone: the move is lost", result ~= nil and result.a.how == "failed" and string.find(result.a.howText, "truck", 1, true) ~= nil)
Moving.admin(ann, "start")
Moving.step()
local timeSaid = Moving.admin(ann, "time")
check("the admin's one minute left", string.find(timeSaid, "minute", 1, true) ~= nil)
E.now += 61
Moving.step()
result = E.last(ann, "Moving", "result")
check("the clock ran out: late (nothing loaded: nothing paid)", result ~= nil and result.a.how == "late" and result.a.pay == 0)
Moving.admin(ann, "start")
Moving.step()
E.leave(ann)
result = E.last(bob, "Moving", "result")
check("the owner left: called off for the crew", result ~= nil and result.a.how == "cancelled" and string.find(E.lastNotice(bob), "Ann left", 1, true) ~= nil)
check("every interior went (slots free again)", E.destroyed == E.built, `{E.destroyed} of {E.built}`)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
