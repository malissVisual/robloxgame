-- 7.0 prototype, MOVES: the real server/Moving.luau run in the Luau CLI (tests/run_tests.py builds MovingServer.luau
-- with tests/runtime/MovingRuntime.luau's fakes in place of its server modules; the art is a fake shaped like the art
-- branch's FurnitureLooks / HouseLayout / HouseInterior). A whole move: the board's card, START (the truck, the
-- interior), the crew, the door in and out with its fades, picking up, dragging and lifting in two, the truck's back,
-- loading and the no-room refusal, unloading, the damage, a death, a helper too far, a teleport with a thing, the horde,
-- the delivery's pay split, and the edges: a stranger, the owner leaving, the truck lost, the admin's commands.
-- 7.0 planning: START opens the lobby (the real server/MoveLobby.luau: roles, READY, LAUNCH, the quick chat, a solo
-- lobby, CANCEL, the owner leaving), and the roles on the move: the Driver's call and truck, the locked door (the
-- Technician's pick, a kick), the fuse box, a role switch and its cooldown, the Mover's pair thing alone, the climb, the
-- Guard's hits and barricades.
-- 7.0 review (server): nothing replaces the truck mid-move (Vehicles' spawn / placeNear / placeAt / spawnAt), Moving.busy
-- and Crew.hasJob, a door trip whose move ends meanwhile, Load's pace check, Unload's full hands, the end's pay failing
-- (the cleanup still runs), the late grace, LAUNCH at the board, the Guard's range, the plan made once.
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
local R = Config.MoveRoles
local Lobby = require("./MoveLobbyServer")
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

local plans = 0 -- (7.0 review: the contract's plan is made once: every card and START reuse it)
local planOf = E.art.layout.plan
E.art.layout.plan = function(...: any): any
	plans += 1
	return planOf(...)
end
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
local function lobbyRequest(player: any, ...: any)
	E.Net.get("MoveLobby").OnServerEvent:Fire(player, ...)
end
-- Did `player` get a notice with `text` (since message number `since`)?
local function heard(player: any, text: string, since: number?): boolean
	for index = since or 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then
			return true
		end
	end
	return false
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

-- START: the planning lobby (7.0 planning) ----------------------------------------------------------------------------

E.request(ann, "start", "marge")
local lobbyAnn = E.last(ann, "MoveLobby", "lobby")
check("START opens the planning lobby (no truck yet)", lobbyAnn ~= nil and lobbyAnn.a ~= nil and E.cars[ann] == nil and E.built == 0, E.lastNotice(ann))
local lobbyBob = E.last(bob, "MoveLobby", "lobby")
check("…for the crew too, each with a free role", lobbyBob ~= nil and lobbyBob.a ~= nil and lobbyAnn.a.role == "driver" and lobbyBob.a.role == "mover"
	and bob:GetAttribute("MoveLobby") == 11 and ann:GetAttribute("MoveLobby") == 11)
check("the card's summary in it", lobbyAnn.a.card.name == "Marge's House" and lobbyAnn.a.card.estimate > 0 and lobbyAnn.a.mine == true and lobbyBob.a.mine == false
	and #lobbyAnn.a.members == 2 and lobbyAnn.a.canLaunch == false and lobbyAnn.a.waiting == 1)
lobbyRequest(ann, "launch")
check("LAUNCH waits for the crew's READY", E.cars[ann] == nil and string.find(E.lastNotice(ann), "READY", 1, true) ~= nil, E.lastNotice(ann))
lobbyRequest(bob, "role", "driver")
check("one role each: Bob can't take Ann's", string.find(E.lastNotice(bob), "crew mate", 1, true) ~= nil and E.last(bob, "MoveLobby", "lobby").a.role == "mover")
lobbyRequest(bob, "role", "tech")
lobbyRequest(bob, "ready", true)
check("Bob: the Technician, READY; LAUNCH may go", E.last(bob, "MoveLobby", "lobby").a.role == "tech" and E.last(bob, "MoveLobby", "lobby").a.ready == true
	and E.last(ann, "MoveLobby", "lobby").a.canLaunch == true)
lobbyRequest(bob, "launch")
check("only the owner launches", E.cars[ann] == nil and E.cars[bob] == nil)
lobbyRequest(cid, "role", "guard")
check("a stranger is not in it", E.last(cid, "MoveLobby", "lobby") == nil)
lobbyRequest(bob, "chat", 3)
local said = E.last(ann, "MoveLobby", "chat")
check("the quick chat in the lobby: the crew hears it, a stranger not", said ~= nil and said.a.index == 3 and said.a.from == 22 and E.last(bob, "MoveLobby", "chat") ~= nil
	and E.last(cid, "MoveLobby", "chat") == nil)
lobbyRequest(cid, "chat", 2)
lobbyRequest(ann, "chat", 9)
check("…not from a stranger, nor a line it doesn't have", E.last(ann, "MoveLobby", "chat") == said)
local launchedAt = #E.messages
lobbyRequest(ann, "launch")
local truck = E.cars[ann]
check("LAUNCH: the truck is lent", truck ~= nil and truck.id == T.Truck, E.lastNotice(ann))
check("…and the interior is built", E.built == 1 and #E.interiors == 1)
check("everybody of the crew hears it", heard(bob, "Move started", launchedAt))
check("the lobby closes for everybody", E.last(ann, "MoveLobby", "lobby").a == nil and E.last(bob, "MoveLobby", "lobby").a == nil and bob:GetAttribute("MoveLobby") == nil)
check("the lobby's roles on the move (MoveRole), each told", ann:GetAttribute("MoveRole") == "driver" and bob:GetAttribute("MoveRole") == "tech" and heard(bob, "Technician", launchedAt))
Moving.step()
check("the crew is on the move (MoveWith)", ann:GetAttribute("MoveWith") == 11 and bob:GetAttribute("MoveWith") == 11 and cid:GetAttribute("MoveWith") == nil)
local view = E.last(ann, "Moving", "state")
check("the state: 6 things, 3 ★, the clock", view ~= nil and view.a ~= nil and #view.a.items == 6 and view.a.counts.stars == 3 and view.a.endsAt == E.now + T.Time and view.a.mine == true)
check("…and Bob's says it is Ann's", E.last(bob, "Moving", "state") ~= nil and E.last(bob, "Moving", "state").a.mine == false)
check("the state: the roles", view.a.team.role == "driver" and E.last(bob, "Moving", "state").a.team.role == "tech" and #view.a.team.crew == 2 and view.a.team.locked == true)
E.request(ann, "start", "marge")
check("no second move at once", string.find(E.lastNotice(ann), "already", 1, true) ~= nil, E.lastNotice(ann))
lobbyRequest(ann, "chat", 1)
check("the quick chat on a move: the crew hears it", E.last(bob, "MoveLobby", "chat").a.index == 1 and E.last(bob, "MoveLobby", "chat").a.from == 11 and E.last(cid, "MoveLobby", "chat") == nil)

-- The Driver: the call, the truck (7.0 planning) ---------------------------------------------------------------------------

truck.chassis.CFrame = M.CFrame.new(depot.X + 40, 2, depot.Z)
E.request(bob, "call")
check("only the Driver calls the truck", string.find(E.lastNotice(bob), "Driver", 1, true) ~= nil and (truck.chassis.Position - depot).Magnitude < 60, E.lastNotice(bob))
E.seated[bob] = truck
E.request(ann, "call")
check("not with somebody in it", string.find(E.lastNotice(ann), "sits in the truck", 1, true) ~= nil, E.lastNotice(ann))
E.seated[bob] = nil
E.request(ann, "call")
check("Call truck to door: at the house's curb, stood up, with a fade", V3(truck.chassis.Position.X - door.X, 0, truck.chassis.Position.Z - door.Z).Magnitude < 45 and E.stoodUp == 1
	and E.last(ann, "Moving", "fade") ~= nil and E.last(bob, "Moving", "fade") == nil, truck.chassis.Position)
E.request(ann, "call")
check("…once a move", string.find(E.lastNotice(ann), "once", 1, true) ~= nil, E.lastNotice(ann))
E.Vehicles.damage(truck, 100)
E.seated[ann] = truck
E.Vehicles.damage(truck, 100)
E.seated[ann] = nil
check("the truck takes less with a Driver at its wheel", E.carHits[#E.carHits - 1].amount == 100 and math.abs(E.carHits[#E.carHits].amount - 100 * R.Driver.TruckDamage) < 1e-6)

-- 7.0 review: nothing of the old game takes the truck's place mid-move; the move's people are busy -------------------------

do
	local calls = E.vehicleCalls or 0
	local out = "Your moving truck is out"
	check("CAR / MY BIKE / a car job (Vehicles.spawn): refused, the truck stays", string.find(E.Vehicles.spawn(ann, false, nil) or "", out, 1, true) ~= nil
		and string.find(E.Vehicles.spawn(ann, true, "van") or "", out, 1, true) ~= nil and E.cars[ann] == truck)
	check("…the phone's CALL CAR in the truck (Vehicles.placeNear): refused", string.find(E.Vehicles.placeNear(ann, nil) or "", out, 1, true) ~= nil and E.cars[ann] == truck)
	check("…a garage's or a dealer's car (placeAt), ZDC RIDE's (spawnAt): refused, said", E.Vehicles.placeAt(ann, nil, M.CFrame.new(0, 0, 0)) == nil
		and E.Vehicles.spawnAt(ann, "escooter", M.CFrame.new(0, 0, 0), false) == nil and string.find(E.lastNotice(ann), out, 1, true) ~= nil and (E.vehicleCalls or 0) == calls)
	E.Vehicles.spawn(bob, false, nil)
	check("…a crew mate's own car is theirs to call", (E.vehicleCalls or 0) == calls + 1)
	check("no job, no mission, no rental on a move (Moving.busy): its owner and its crew, a stranger free", type(Moving.busy(ann)) == "string" and type(Moving.busy(bob)) == "string"
		and Moving.busy(cid) == nil)
	check("the crews see the move's owner busy (Crew.hasJob), not its crew", E.Crew.hasJob(ann) == true and E.Crew.hasJob(bob) == false and E.Crew.hasJob(cid) == false)
end
check("no wait at the truck's back for a Driver (the prompts' MoveQuick)", promptIn(truck.model, "Load"):GetAttribute("MoveQuick") == "driver"
	and promptIn(truck.model, "Take out"):GetAttribute("MoveQuick") == "driver")

-- The door ---------------------------------------------------------------------------------------------------------------

local site = moves:FindFirstChild("Move_marge")
local enter = promptIn(site, "Enter house")
-- 7.0 planning: the door is locked (no keys): the Technician picks it
local pickLock = promptIn(site, "Pick lock")
local kickDoor = promptIn(site, "Kick door")
check("locked: Pick lock for the Technician (3 s), Kick door for the rest", pickLock ~= nil and kickDoor ~= nil and pickLock:GetAttribute("MoveOnly") == 22
	and kickDoor:GetAttribute("MoveSkip") == 22 and pickLock.Enabled and kickDoor.Enabled and pickLock.HoldDuration == R.Tech.Pick and pickLock:GetAttribute("MoveOwner") == 11)
check("…and the move's own Enter house: its crew's only (MoveOwner), shut while locked", enter ~= nil and enter:GetAttribute("MoveOwner") == 11 and not enter.Enabled
	and ann:GetAttribute("MoveLocked") == true and bob:GetAttribute("MoveLocked") == true and cid:GetAttribute("MoveLocked") == nil)
E.place(ann, outside)
trigger(enter, ann)
check("Enter house refused while it is locked", string.find(E.lastNotice(ann), "locked", 1, true) ~= nil and (E.rootOf(ann).Position - outside).Magnitude < 1, E.lastNotice(ann))
trigger(pickLock, ann)
check("only the Technician picks it", string.find(E.lastNotice(ann), "Technician", 1, true) ~= nil and pickLock.Enabled, E.lastNotice(ann))
local zombiesBefore = #E.zombies
local pickedAt = #E.messages
E.place(bob, outside)
trigger(pickLock, bob)
check("the Technician picks it: open and quiet (no zombies)", not pickLock.Enabled and not kickDoor.Enabled and enter.Enabled and ann:GetAttribute("MoveLocked") == nil and #E.zombies == zombiesBefore
	and heard(ann, "picked", pickedAt))
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
-- 7.0 planning: the lights stay off until the Technician fixes the fuse box in the garage
local interior = workspace:FindFirstChild("Interior")
local lamp0 = interior:FindFirstChild("Lamp")
local fuse = interior:FindFirstChild("FuseBox")
local fixFuse = fuse and promptIn(fuse, "Fix fuse box")
check("dark inside: the lights off, the porch's daylight on", lamp0:FindFirstChildOfClass("PointLight").Enabled == false and lamp0.Material == "SmoothPlastic"
	and interior:FindFirstChild("Daylight"):FindFirstChildOfClass("SpotLight").Enabled == true)
check("a fuse box on the garage's back wall, for the Technician", fuse ~= nil and fixFuse ~= nil and fixFuse:GetAttribute("MoveOnly") == 22 and fixFuse.Enabled
	and math.abs(fuse.Position.Z - (origin.Position.Z + 26 - 0.3)) < 1e-6 and fixFuse.HoldDuration == R.Tech.Fuse)
E.place(ann, fuse.Position + V3(2, 0, 0))
trigger(fixFuse, ann)
check("only the Technician fixes it", lamp0:FindFirstChildOfClass("PointLight").Enabled == false and string.find(E.lastNotice(ann), "Technician", 1, true) ~= nil)
E.place(bob, fuse.Position + V3(2, 0, 0))
trigger(fixFuse, bob)
check("fixed: the lights come on", lamp0:FindFirstChildOfClass("PointLight").Enabled == true and lamp0.Material == "Neon" and not fixFuse.Enabled)
E.place(ann, outside)
trigger(enter, ann)

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
local unload = promptIn(truck.model, "Take out")
check("Unload (Z, \"Take out\") shows the last one in", unload ~= nil and unload.Enabled and unload.KeyboardKeyCode == "Z" and string.find(unload.ActionText, "Lamp", 1, true) ~= nil)
-- the owner's report: Unload sat on the door's own attachment with Load and the back's E (all stacked)
check("Unload on its own spot beside the door, not stacked with Load and the back's E", unload.Parent ~= cargoDoor and unload.Parent.Name == "MoveTakeOut"
	and unload.Parent.Parent == truck.chassis and (unload.Parent.WorldPosition - cargoDoor.WorldPosition).Magnitude > 2 and not load.Enabled and backPrompt.Enabled)
character:SetAttribute("Pushing", "trolley")
trigger(unload, ann)
check("7.0 review: Unload with your hands full (a trolley): refused", character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(ann), "hands are full", 1, true) ~= nil
	and lampRoot:FindFirstChildOfClass("WeldConstraint").Part0 == truck.chassis, E.lastNotice(ann))
character:SetAttribute("Pushing", nil)
trigger(unload, ann)
check("unloaded into your hands", character:GetAttribute("MoveCarry") == 1 and lampRoot:FindFirstChildOfClass("WeldConstraint").Part0 == E.rootOf(ann))
-- 7.0 review: Load checks the carry's pace (a teleport to the truck's back with it does not count)
E.place(ann, cargoDoor.WorldPosition + V3(200, 0, 0))
E.clock += 0.2
Moving.step()
check("a carrier away from the back: Load off, the back's own E free to close it", not load.Enabled and backPrompt.Enabled)
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
E.clock += 0.05
trigger(load, ann)
check("Load right after a teleport with it: refused, down where it was", character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(ann), "Too fast", 1, true) ~= nil
	and (lampRoot.Position - cargoDoor.WorldPosition).Magnitude > 150, E.lastNotice(ann))
E.place(ann, lampRoot.Position + V3(1, 0, 0))
trigger(pick, ann)
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
E.clock += 0.2
Moving.step()
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
-- the owner's report: with something in the truck already, Unload showed beside Load and E fumbled
check("the lamp inside, the sofa carried at the back: Load only (no Unload, the back's E waits)", load.Enabled and not unload.Enabled and not backPrompt.Enabled
	and lampRoot:FindFirstChildOfClass("WeldConstraint").Part0 == truck.chassis)
trigger(load, ann)
check("the helper doesn't load", string.find(E.lastNotice(ann), "front", 1, true) ~= nil, E.lastNotice(ann))
trigger(load, bob)
check("the carrier loads it; both hands free", bobBody:GetAttribute("MoveCarry") == nil and character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(bob), "Sofa", 1, true) ~= nil, E.lastNotice(bob))

-- A role switch, the Mover, the climb (7.0 planning) ---------------------------------------------------------------------

E.request(bob, "role", "driver")
check("a switch to a crew mate's role: refused", string.find(E.lastNotice(bob), "crew mate", 1, true) ~= nil and bob:GetAttribute("MoveRole") == "tech", E.lastNotice(bob))
E.request(bob, "role", "mover")
check("a switch to a free role: Bob is the Mover", bob:GetAttribute("MoveRole") == "mover" and heard(ann, "Mover now"))
E.request(bob, "role", "guard")
check("…not again within the cooldown", string.find(E.lastNotice(bob), "Wait", 1, true) ~= nil and bob:GetAttribute("MoveRole") == "mover", E.lastNotice(bob))
check("no Technician now: the fuse box's prompt is nobody's", fixFuse:GetAttribute("MoveOnly") == nil)
E.place(bob, outside)
trigger(enter, bob)
local slab0 = itemModel(6)
E.place(bob, slab0.PrimaryPart.Position + V3(2, 0, 0))
trigger(promptIn(slab0, "Lift"), bob)
check("the Mover lifts a pair thing alone at 0.6 (not dragged at 0.35)", bobBody:GetAttribute("MoveCarry") == 6 and math.abs((bobBody:GetAttribute("CarrySpeed") or 0) - 14 * R.Mover.Alone) < 1e-6,
	bobBody:GetAttribute("CarrySpeed"))
check("…held up in front, not low", math.abs(((bobBody:GetAttribute("CarryAt") :: any) or V3()).Y - (Config.Cargo.CarryLow + 3.6 / 2)) < 1e-6)
E.Net.get("PutDown").OnServerEvent:Fire(bob)
-- the others go up stairs slower with a thing in both hands: the TV up a step
E.place(ann, outside)
trigger(enter, ann)
local tv0 = itemModel(2)
E.place(ann, tv0.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(tv0, "Pick up"), ann)
local flatWalk = 14 * T.Speed.Both
check("the TV in both hands", math.abs((character:GetAttribute("CarrySpeed") or 0) - flatWalk) < 1e-6, character:GetAttribute("CarrySpeed"))
E.clock += 0.2
Moving.step()
E.place(ann, E.rootOf(ann).Position + V3(2, 3, 0))
E.clock += 0.2
Moving.step()
check("up the stairs with it: slower (× Climb)", math.abs((character:GetAttribute("CarrySpeed") or 0) - flatWalk * R.Mover.Climb) < 1e-6, character:GetAttribute("CarrySpeed"))
E.clock += R.Mover.Hold + 0.2
Moving.step()
check("…and back to its walk on the flat", math.abs((character:GetAttribute("CarrySpeed") or 0) - flatWalk) < 1e-6, character:GetAttribute("CarrySpeed"))
E.Net.get("PutDown").OnServerEvent:Fire(ann)

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
-- 7.0 planning: the admin's start gives free roles; the door kicked in; the Guard
check("the admin's start: free roles", ann:GetAttribute("MoveRole") == "driver" and bob:GetAttribute("MoveRole") == "mover")
kickDoor = promptIn(site, "Kick door")
zombiesBefore = #E.zombies
pickedAt = #E.messages
local noisesBefore = E.noises
trigger(kickDoor, ann)
check("Kick door: open, LOUD, zombies come at the door", #E.zombies - zombiesBefore == R.Tech.KickZombies and E.noises > noisesBefore and heard(bob, "LOUD", pickedAt)
	and ann:GetAttribute("MoveLocked") == nil and E.zombies[#E.zombies].march ~= nil)
E.request(ann, "role", "guard")
check("Ann switches to the Guard", ann:GetAttribute("MoveRole") == "guard")
local z0 = E.zombies[#E.zombies]
E.Zombies.damage(z0, 10, ann, {})
local hitGun = E.zombieHits[#E.zombieHits].amount
E.Zombies.damage(z0, 10, ann, { cause = "car" })
local hitCar = E.zombieHits[#E.zombieHits].amount
E.Zombies.damage(z0, 10, bob, {})
check("the Guard hits harder (not with the car); the others as ever", math.abs(hitGun - 10 * R.Guard.Damage) < 1e-6 and hitCar == 10 and E.zombieHits[#E.zombieHits].amount == 10)
do -- 7.0 review: only round the move: a zombie far from its house and truck takes the plain damage
	local far = E.Zombies.spawn("walker", depot + V3(0, 0, -400), ann)
	E.Zombies.damage(far, 10, ann, {})
	check("…but only round the move (Guard.Range of its house or truck)", E.zombieHits[#E.zombieHits].amount == 10)
end
E.request(bob, "barricade")
check("only the Guard puts up barricades", string.find(E.lastNotice(bob), "Guard", 1, true) ~= nil and moves:FindFirstChild("MoveBarricade") == nil, E.lastNotice(bob))
E.request(ann, "barricade")
local barricade = moves:FindFirstChild("MoveBarricade")
check("a plank barricade by the door", barricade ~= nil and barricade:GetAttribute("Hp") == R.Guard.Hp and #barricade:GetChildren() == 6
	and E.last(ann, "Moving", "state") ~= nil)
z0.root.CFrame = barricade.PrimaryPart.CFrame
for _ = 1, math.ceil(R.Guard.Hp / R.Guard.Bite) + 1 do
	E.now += 1
	E.clock += 1
	Moving.step()
end
check("a zombie at it wears it down", barricade.Parent == nil and heard(ann, "broke a barricade"))
E.request(ann, "barricade")
E.request(ann, "barricade")
check("…two at most", string.find(E.lastNotice(ann), "No barricades left", 1, true) ~= nil, E.lastNotice(ann))
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
check("the horde at HordeAt left: zombies march on the house", E.marched > 0 and heard(ann, "HORDE") and E.last(ann, "Moving", "state").a.horde == true) -- (7.0 planning: a barricade's end may be the last word)
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
check("…the truck's Load and Take out gone, Take out's own spot too", promptIn(truck.model, "Load") == nil and promptIn(truck.model, "Take out") == nil
	and truck.chassis:FindFirstChild("MoveTakeOut") == nil and truck.chassis:FindFirstChild("CargoDoor") ~= nil)
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

-- A solo lobby, CANCEL, the owner leaving the planning (7.0 planning) --------------------------------------------------------

local dan = E.player(44, "Dan", board + V3(-3, 0, 1))
check("the barricades went with the move", moves:FindFirstChild("MoveBarricade") == nil and ann:GetAttribute("MoveRole") == nil and bob:GetAttribute("MoveRole") == nil)
E.place(cid, board + V3(-3, 0, -1))
trigger(boardPrompt, cid)
E.request(cid, "start", "marge")
local solo = E.last(cid, "MoveLobby", "lobby")
check("a solo lobby: READY is LAUNCH", solo ~= nil and solo.a ~= nil and solo.a.canLaunch == true and #solo.a.members == 1 and solo.a.role == "driver")
lobbyRequest(cid, "cancel")
check("CANCEL closes it", E.last(cid, "MoveLobby", "lobby").a == nil and cid:GetAttribute("MoveLobby") == nil and E.cars[cid] == nil)
trigger(boardPrompt, cid)
E.request(cid, "start", "marge")
lobbyRequest(cid, "role", "tech")
E.place(cid, home.park and V3(home.park.x, 3, home.park.z) or depot)
lobbyRequest(cid, "launch")
check("7.0 review: LAUNCH away from the board (at the house): refused, the truck comes to the board", E.cars[cid] == nil and string.find(E.lastNotice(cid), "board", 1, true) ~= nil,
	E.lastNotice(cid))
E.place(cid, board + V3(-3, 0, -1))
lobbyRequest(cid, "launch")
check("solo LAUNCH starts the move at once, with the role picked", E.cars[cid] ~= nil and cid:GetAttribute("MoveRole") == "tech")
E.request(cid, "giveup")
check("…given up: no role any more", cid:GetAttribute("MoveRole") == nil)
E.crew[cid] = { dan }
trigger(boardPrompt, cid)
E.request(cid, "start", "marge")
check("Dan is in Cid's lobby", E.last(dan, "MoveLobby", "lobby") ~= nil and E.last(dan, "MoveLobby", "lobby").a ~= nil and dan:GetAttribute("MoveLobby") == 33)
E.crew[cid] = {}
Lobby.step()
check("a member who leaves the crew leaves the lobby", E.last(dan, "MoveLobby", "lobby").a == nil and dan:GetAttribute("MoveLobby") == nil
	and #E.last(cid, "MoveLobby", "lobby").a.members == 1)
E.crew[cid] = { dan }
Lobby.step()
check("…and comes back with the crew, NOT READY", E.last(dan, "MoveLobby", "lobby").a ~= nil and E.last(dan, "MoveLobby", "lobby").a.ready == false
	and E.last(cid, "MoveLobby", "lobby").a.canLaunch == false)
E.leave(cid)
check("the owner left: the planning closes for the crew", E.last(dan, "MoveLobby", "lobby").a == nil and dan:GetAttribute("MoveLobby") == nil and heard(dan, "left"))

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
E.clock += 0.3
Moving.step()
check("0:00: 7.0 review: LateGrace s to reach the Wall, no end yet", E.last(ann, "Moving", "result") == result and heard(ann, "Time's up")
	and E.last(ann, "Moving", "state").a.graceEndsAt ~= nil)
E.now += T.LateGrace
Moving.step()
result = E.last(ann, "Moving", "result")
check("…the Wall not reached in time: the load is lost, nothing paid", result ~= nil and result.a.how == "failed" and result.a.pay == 0, result and result.a.how)
-- 7.0 review: the end's pay fails (a save down): the cleanup runs anyway, the slot frees
do
	Moving.admin(ann, "start")
	Moving.step()
	local addXp = E.PlayerData.addXp
	E.PlayerData.addXp = function()
		error("the save is down")
	end
	Moving.admin(ann, "deliver")
	E.PlayerData.addXp = addXp
	check("the end's pay failed: the cleanup ran anyway (the interior gone, nobody on the move, the HUD told)", E.destroyed == E.built and ann:GetAttribute("MoveWith") == nil
		and E.last(ann, "Moving", "state").a == nil, `{E.destroyed} of {E.built}`)
	check("…and the next move starts", string.find(Moving.admin(ann, "start"), "started", 1, true) ~= nil)
	Moving.admin(ann, "end")
end
-- 7.0 review: a door trip while the move ends: out at the house's door, never into the void; the fade lifts
do
	Moving.admin(ann, "start")
	Moving.step()
	E.place(ann, outside)
	trigger(promptIn(site, "Kick door"), ann)
	E.onStream = function()
		E.request(ann, "giveup") -- (the move ends while the screen is dark)
	end
	trigger(promptIn(site, "Enter house"), ann)
	check("the move ended during the door's fade: out at the house's door, the fade lifted", (E.rootOf(ann).Position - outside).Magnitude < 6
		and E.last(ann, "Moving", "fade").a == "in" and E.last(ann, "Moving", "result").a.how == "cancelled", E.rootOf(ann).Position)
	Moving.admin(ann, "start")
	Moving.step()
	trigger(promptIn(site, "Kick door"), ann)
	trigger(promptIn(site, "Enter house"), ann)
	check("…and the next trip goes in (nothing stuck)", (E.rootOf(ann).Position - E.interiors[#E.interiors].Position).Magnitude < 10)
	Moving.admin(ann, "end")
end
check("7.0 review: the contract's plan was made once (every card and START reuse it)", plans == 1, plans)
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
