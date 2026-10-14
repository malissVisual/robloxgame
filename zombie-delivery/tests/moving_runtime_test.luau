-- 7.0 prototype, MOVES: the real server/Moving.luau run in the Luau CLI (tests/run_tests.py builds MovingServer.luau
-- with tests/runtime/MovingRuntime.luau's fakes in place of its server modules; the art is a fake shaped like the art
-- branch's FurnitureLooks / HouseLayout / HouseInterior). A whole move: the board's card, START (the truck, the
-- interior), the crew, the door in and out with its fades, picking up, dragging and lifting in two, the truck's back,
-- loading and the no-room refusal, unloading, the damage, a death, a helper too far, a teleport with a thing, the horde,
-- the delivery's pay split, and the edges: a stranger, the owner leaving, the truck lost, the admin's commands.
-- 7.0 planning: START opens the lobby (the real server/MoveLobby.luau: roles, READY, LAUNCH, the quick chat, a solo
-- lobby, CANCEL, the owner leaving), and the three roles on the move: the Driver's call and truck, a role switch and its
-- cooldown, the Mover's pair thing alone, the climb, the Guard's hits and barricades. The owner took the Technician out:
-- the front door is open from the start (no Pick lock / Kick door), the house lit (no fuse box).
-- 7.0 greeters (the real server/MoveGreeters.luau, tests/movegreeters_runtime_test.luau has the rest): Marge on the
-- porch from LAUNCH, gone at the end; the soldier's welcome at the Wall on the delivery.
-- 7.0 review (server): nothing replaces the truck mid-move (Vehicles' spawn / placeNear / placeAt / spawnAt), Moving.busy
-- and Crew.hasJob, a door trip whose move ends meanwhile, Load's pace check, Unload's full hands, the end's pay failing
-- (the cleanup still runs), the late grace, LAUNCH at the board, the Guard's range, the plan made once.
-- 8.0 SANDBOX off (tests/runtime/MovingRuntime.luau: Config.Sandbox.On false): the city's game as it was: the depot's
-- board, the Wall, Marge and Walt, the story, the pay; no plot kiosks, no walk-in bay's Load, no sandbox fields
-- (tests/sandboxmove_runtime_test.luau has the sandbox).
-- 8.1 walk-in doors (Config.Moving.Doors; the E prompts there but off): walking into the door's zone facing it goes in
-- after the dwell (not a stranger, not from a seat, not walking past, not brushing past, not beside the doorway), out by
-- the doorway inside, no ping-pong (shut until you left the zone you came out in and Rearm s went by, whichever later),
-- in and out with a piece in your hands, a pair piece's back end does not lead (said once), its front end takes it along;
-- the doormats (▲ IN outside while a move uses the house, ▲ OUT inside).
-- 8.3 Danny for hire: a crew of players has no Danny (an unhired one is never called either), so a two-person Lift is today's
-- (dragged alone, Help lift).
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
local Greeters = require("./MoveGreetersServer") -- 7.0 greeters
local MoveStory = require("./MoveStory")
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
check("8.0 SANDBOX off: the city's world (no plot kiosks, no sandbox house)", Config.Sandbox.On == false and moves:FindFirstChild("MovingBoard1") == nil
	and moves:FindFirstChild("Move_sandbox_house") == nil and moves:FindFirstChild("MoveDressing") ~= nil)
-- 8.0.1, the city unchanged: the depot's corkboard (Marge's, Walt's, Go to the Wall), not the sandbox's chalet
local cityWords: { string } = {}
for _, d in moves:FindFirstChild("MovingBoard"):GetDescendants() do
	if d.ClassName == "TextLabel" then
		table.insert(cityWords, tostring(d.Text))
	end
end
local cityBoard = table.concat(cityWords, " | ")
check("8.0.1: the city's kiosk keeps its corkboard (MARGE, WALT'S RANCH, Go to the Wall, ZDC MOVING & EVACUATION; no chalet)",
	string.find(cityBoard, "MARGE", 1, true) ~= nil and string.find(cityBoard, "WALT'S RANCH", 1, true) ~= nil and string.find(cityBoard, "Go to the Wall", 1, true) ~= nil
	and string.find(cityBoard, "ZDC MOVING & EVACUATION", 1, true) ~= nil and string.find(cityBoard, "CHALET", 1, true) == nil, cityBoard)
Greeters.step() -- (the greeters' loop: the soldier at the Wall)
check("7.0 greeters: the soldier stands at the Wall", Greeters.soldier() ~= nil and Greeters.soldier().Parent ~= nil)
-- The porch greeter of `owner`'s move (her body in the world), or nil.
local function porchOf(owner: any): any
	for _, child in workspace:GetChildren() do
		if child:GetAttribute("MoveGreeter") == "porch" and child:GetAttribute("MoveGreeterOf") == owner.UserId and not child.destroyed then
			return child
		end
	end
	return nil
end

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
check("8.0 SANDBOX off: the card as ever (Marge's and Walt's, the story, the pay; no note)", card ~= nil and #card.a.contracts == 2 and card.a.story == nil
	and card.a.note == nil and card.a.hordeAt == T.HordeAt)
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
check("no Technician to pick any more", string.find(E.lastNotice(bob), "No such role", 1, true) ~= nil and E.last(bob, "MoveLobby", "lobby").a.role == "mover", E.lastNotice(bob))
lobbyRequest(bob, "role", "guard")
lobbyRequest(bob, "ready", true)
check("Bob: the Guard, READY; LAUNCH may go", E.last(bob, "MoveLobby", "lobby").a.role == "guard" and E.last(bob, "MoveLobby", "lobby").a.ready == true
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
check("LAUNCH: 7.x van moves: the owner's own van (none was out: placed by them)", truck ~= nil and truck.id == E.carId and not truck.lent, E.lastNotice(ann))
check("…and the interior is built", E.built == 1 and #E.interiors == 1)
check("everybody of the crew hears it", heard(bob, "Move started", launchedAt))
check("the lobby closes for everybody", E.last(ann, "MoveLobby", "lobby").a == nil and E.last(bob, "MoveLobby", "lobby").a == nil and bob:GetAttribute("MoveLobby") == nil)
check("the lobby's roles on the move (MoveRole), each told", ann:GetAttribute("MoveRole") == "driver" and bob:GetAttribute("MoveRole") == "guard" and heard(bob, "Guard", launchedAt))
Moving.step()
local marge = porchOf(ann)
check("7.0 greeters: Marge on the porch from the move's start (the crew still at the depot: no hello yet)", marge ~= nil and marge.Name == "Marge"
	and not E.saidSince(MoveStory.greeterOf("marge").hello[1], 0))
check("the crew is on the move (MoveWith)", ann:GetAttribute("MoveWith") == 11 and bob:GetAttribute("MoveWith") == 11 and cid:GetAttribute("MoveWith") == nil)
local view = E.last(ann, "Moving", "state")
check("8.0 SANDBOX off: the state's drop-off is the Wall (no drop words), the horde at HordeAt", view ~= nil and view.a ~= nil and view.a.drop == nil
	and view.a.hordeAt == view.a.endsAt - T.HordeAt and view.a.dropOff.x == Map.Depot.x + T.DropOff[1])
check("the state: 6 things, 3 ★, the clock", view ~= nil and view.a ~= nil and #view.a.items == 6 and view.a.counts.stars == 3 and view.a.endsAt == E.now + T.Time and view.a.mine == true)
check("…and Bob's says it is Ann's", E.last(bob, "Moving", "state") ~= nil and E.last(bob, "Moving", "state").a.mine == false)
check("the state: the roles (no lock, no lights to fix)", view.a.team.role == "driver" and E.last(bob, "Moving", "state").a.team.role == "guard" and #view.a.team.crew == 2
	and view.a.team.locked == nil and view.a.team.lit == nil and view.a.team.fuse == nil)
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
check("not with somebody in it", string.find(E.lastNotice(ann), "sits in the van", 1, true) ~= nil, E.lastNotice(ann))
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
	local out = "Your van is out"
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
-- the owner took the Technician out: the front door is never locked
check("the move's own Enter house: its crew's only (MoveOwner), open from the start (8.1 walk-in doors: walked through, the prompt off)", enter ~= nil
	and enter:GetAttribute("MoveOwner") == 11 and not enter.Enabled
	and ann:GetAttribute("MoveLocked") == nil and bob:GetAttribute("MoveLocked") == nil)
check("no Pick lock, no Kick door", promptIn(site, "Pick lock") == nil and promptIn(site, "Kick door") == nil)
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
-- no fuse box any more: the house is lit from the start
local interior = workspace:FindFirstChild("Interior")
local lamp0 = interior:FindFirstChild("Lamp")
check("lit inside from the start: the lights on, the porch's daylight on, no fuse box", lamp0:FindFirstChildOfClass("PointLight").Enabled == true and lamp0.Material == "Neon"
	and interior:FindFirstChild("Daylight"):FindFirstChildOfClass("SpotLight").Enabled == true and interior:FindFirstChild("FuseBox") == nil)
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
check("8.0 SANDBOX off: the prompts say ZDC Van, no walk-in bay's Load", string.find(load.ObjectText, "ZDC Van ·", 1, true) == 1 and truck.chassis:FindFirstChild("MoveLoadBay") == nil,
	load.ObjectText)
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
check("8.3 a crew of players (no Danny on the move): today's rules, no call, nobody waits (Config.MoveHelper.WaitForHelper on)",
	Config.MoveHelper.WaitForHelper == true and bob:GetAttribute("MoveHelperCall") == nil and lift.ActionText == "Lift")
local help = promptIn(sofa, "Help lift")
check("Help lift shows for the others, not the carrier", help ~= nil and help.Enabled and help:GetAttribute("MoveSkip") == 22)
trigger(help, bob)
check("you can't help yourself", string.find(E.lastNotice(bob), "already", 1, true) ~= nil, E.lastNotice(bob))
E.place(ann, sofaRoot.Position + V3(0, 0, 3))
trigger(help, ann)
check("two carry it at the pair's walk (8.1: 0.7)", math.abs((bobBody:GetAttribute("CarrySpeed") or 0) - 14 * T.Speed.Pair) < 1e-6
	and math.abs((character:GetAttribute("CarrySpeed") or 0) - 14 * T.Speed.Pair) < 1e-6 and character:GetAttribute("MoveCarry") == 3 and T.Speed.Pair < 0.8)
check("…and Help lift is gone", not help.Enabled)
-- 8.1 carrying in two: the leader's heading turns slowly (client/PairSteer.luau), the helper is held at the far end by
-- the server (server/PairHold.luau), as Danny is
local H = Config.MoveHelper
local Brain = require("./MoveHelperBrain")
local PairHold = require("./PairHoldServer")
check("8.1 the leader (Bob, who lifted it) gets PairTurn: their heading turns that slowly; the helper none", bobBody:GetAttribute("PairTurn") == H.PairTurn
	and character:GetAttribute("PairTurn") == nil)
E.clock += 0.2
Moving.step()
local mateHold = PairHold.of(ann)
local annRoot = E.rootOf(ann)
check("8.1 the helper held at the sofa's far end by the server: constraints on Ann's root to an attachment on the sofa", mateHold ~= nil
	and mateHold.align.Parent == annRoot and mateHold.align.Attachment1.Parent == sofaRoot and mateHold.orient.Attachment1 == mateHold.far
	and math.abs(mateHold.far.CFrame.Position.Z + (E.items.sofa.size.Z / 2 + H.Standoff)) < 1e-6)
check("…at the pair's top speed (never put there), along the ground only (Ann stands on the floor herself)", mateHold ~= nil
	and math.abs(mateHold.align.MaxVelocity - Brain.holdSpeed(14 * T.Speed.Pair)) < 1e-6 and mateHold.align.MaxAxesForce.Y == 0
	and mateHold.align.MaxAxesForce.X > 0 and math.abs(mateHold.orient.MaxAngularVelocity - Brain.holdTurn()) < 1e-6)
check("…the server owns Ann's body meanwhile (its positions, whatever the lag)", annRoot.NetworkOwner == false)
-- the carrier leaves the house: the helper comes along
E.place(bob, origin.Position + V3(0, 3, 1))
trigger(leave, ann)
check("the helper does not lead the way", string.find(E.lastNotice(ann), "front", 1, true) ~= nil)
trigger(leave, bob)
check("the carrier leads out, the helper comes along", (E.rootOf(bob).Position - outside).Magnitude < 4 and (E.rootOf(ann).Position - outside).Magnitude < 6)
-- too far apart for Grace s: it goes down (8.1: held, the tether waits for the hold's ease back too)
sofaRoot.CFrame = E.rootOf(bob).CFrame * M.CFrame.new(0, 0, -3) -- (the weld, in Roblox: it came out with Bob)
E.clock += 0.2
Moving.step()
E.place(ann, E.rootOf(bob).Position + V3(30, 0, 0))
E.clock += 0.2
Moving.step()
E.place(bob, E.rootOf(bob).Position + V3(0, 0, 0.5))
sofaRoot.CFrame = E.rootOf(bob).CFrame * M.CFrame.new(0, 0, -3)
E.clock += T.Grace + 0.3
Moving.step()
check("8.1 held: Grace s apart is not yet the end (the hold eases her back after HoldStuck s)", bobBody:GetAttribute("MoveCarry") == 3 and character:GetAttribute("MoveCarry") == 3)
E.clock += H.HoldStuck + H.HoldEase
Moving.step()
check("the pair too far apart: it went down", bobBody:GetAttribute("MoveCarry") == nil and character:GetAttribute("MoveCarry") == nil and sofaRoot.Anchored and string.find(E.lastNotice(bob), "apart", 1, true) ~= nil,
	E.lastNotice(bob))
check("8.1 …the hold let go: its constraints gone, Ann's body hers again, Bob's PairTurn gone", PairHold.of(ann) == nil and mateHold ~= nil and mateHold.align.Parent == nil
	and mateHold.far.Parent == nil and annRoot.NetworkOwner == ann and bobBody:GetAttribute("PairTurn") == nil)
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
check("a switch to a crew mate's role: refused", string.find(E.lastNotice(bob), "crew mate", 1, true) ~= nil and bob:GetAttribute("MoveRole") == "guard", E.lastNotice(bob))
E.request(bob, "role", "tech")
check("…nor to the Technician (no role any more)", string.find(E.lastNotice(bob), "No such role", 1, true) ~= nil and bob:GetAttribute("MoveRole") == "guard", E.lastNotice(bob))
E.request(bob, "role", "mover")
check("a switch to a free role: Bob is the Mover", bob:GetAttribute("MoveRole") == "mover" and heard(ann, "Mover now"))
E.request(bob, "role", "guard")
check("…not again within the cooldown", string.find(E.lastNotice(bob), "Wait", 1, true) ~= nil and bob:GetAttribute("MoveRole") == "mover", E.lastNotice(bob))
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
-- the big slab: no room after the sofa (the movers' repack off: Config.Moving.Pack.Repack)
local slab = itemModel(6)
E.place(ann, slab.PrimaryPart.Position + V3(2, 0, 0))
trigger(promptIn(slab, "Lift"), ann)
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(leave, ann)
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
E.clock += 0.2
T.Pack.Repack = false
Moving.step()
check("the packing fix: Load shows the carried slab won't fit before it is pressed", load.Enabled and load.ActionText == "Load Marble slab"
	and string.find(load.ObjectText, "won't fit", 1, true) == 1, load.ObjectText)
trigger(load, ann)
check("no room: it stays in your hands, the words say so", character:GetAttribute("MoveCarry") == 6 and string.find(E.lastNotice(ann), "No room", 1, true) ~= nil, E.lastNotice(ann))
E.Net.get("PutDown").OnServerEvent:Fire(ann)
check("the touch PUT DOWN (the PutDown remote) sets it down", character:GetAttribute("MoveCarry") == nil and slab.PrimaryPart.Anchored)
-- the packing fix: with the repack on, the slab goes in: the movers pack it first (the whole floor), the lamp and the
-- sofa welded again on its top
T.Pack.Repack = true
E.place(ann, slab.PrimaryPart.Position + V3(2, 0, 0))
trigger(promptIn(slab, "Lift"), ann)
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
E.clock += 0.2
Moving.step()
check("…repacked, it would go in: Load says nothing of \"won't fit\"", load.Enabled and string.find(load.ObjectText, "won't fit", 1, true) == nil, load.ObjectText)
trigger(load, ann)
local function bottomOf(model: any): number -- (over the chassis, its root unturned)
	return (truck.chassis.CFrame:Inverse() * model.PrimaryPart.Position).Y - model.PrimaryPart.Size.Y / 2
end
local lampIn, sofaIn = itemModel(1), itemModel(3)
check("…Load repacks the van: the slab in, the words say so", character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(ann), "Van repacked", 1, true) == 1, E.lastNotice(ann))
check("…the lamp and the sofa welded again on the slab's top", math.abs(bottomOf(lampIn) - bottomOf(slab) - E.items.slab.size.Y) < 1e-6
	and math.abs(bottomOf(sofaIn) - bottomOf(slab) - E.items.slab.size.Y) < 1e-6 and lampIn.PrimaryPart:FindFirstChildOfClass("WeldConstraint") ~= nil
	and sofaIn.PrimaryPart:FindFirstChildOfClass("WeldConstraint") ~= nil, `{bottomOf(lampIn)} {bottomOf(sofaIn)} {bottomOf(slab)}`)
E.clock += 0.2
Moving.step()
check("…Take out offers a top one, not the slab under them", unload.ActionText ~= "Take out Marble slab" and string.find(unload.ActionText, "Take out ", 1, true) == 1, unload.ActionText)
E.request(bob, "giveup")
check("only the owner gives up", E.last(bob, "Moving", "result") == nil)
E.request(ann, "giveup")
check("GIVE UP calls it off", E.last(ann, "Moving", "result") ~= nil and E.last(ann, "Moving", "result").a.how == "cancelled" and E.last(bob, "Moving", "result") ~= nil)
check("called off: no pay, the interior gone, nobody on it", #E.money == 0 and E.destroyed == 1 and ann:GetAttribute("MoveWith") == nil and bob:GetAttribute("MoveWith") == nil)
check("7.0 greeters: Marge leaves the porch with the move (called off: no welcome at the Wall)", porchOf(ann) == nil and marge.destroyed == true
	and not E.saidSince(MoveStory.Wall.welcome, 0))

-- The horde, the delivery ------------------------------------------------------------------------------------------------

E.place(ann, depot)
local zombiesBefore = #E.zombies -- (8.1: this move's roamers only, the called-off one's are not counted)
local said = Moving.admin(ann, "start")
check("the admin's START", string.find(said, "started", 1, true) ~= nil and E.built == 2, said)
truck = E.cars[ann]
cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
load = promptIn(truck.model, "Load")
Moving.step()
E.place(ann, outside)
enter = promptIn(site, "Enter house")
-- 7.0 planning: the admin's start gives free roles; the door open at once (nothing to kick in, no noise); the Guard
check("the admin's start: free roles", ann:GetAttribute("MoveRole") == "driver" and bob:GetAttribute("MoveRole") == "mover")
check("the door open at once: Enter house (off: 8.1 walk-in doors), no Kick door, no noise", enter ~= nil and not enter.Enabled and promptIn(site, "Kick door") == nil and E.noises == 0)
check("7.0 greeters: a new Marge on the porch for the new move", porchOf(ann) ~= nil and porchOf(ann) ~= marge)
E.clock += T.Roam.Every + 0.1
Moving.step() -- (Ann outside by the house: the move's few roamers come round it)
E.request(ann, "role", "guard")
check("Ann switches to the Guard", ann:GetAttribute("MoveRole") == "guard")
local z0 = E.zombies[#E.zombies]
check("…a roamer of this move round the house", z0 ~= nil and z0.roamer == true)
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
check("during the move the truck stays: no CAR swap, no taking it back", E.Jobs.returnLent(ann) == false and string.find(E.Vehicles.callCar(ann, nil) or "", "van is out", 1, true) ~= nil)
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
for index = zombiesBefore + 1, #E.zombies do
	if E.zombies[index].roamer then
		roamers += 1
	end
end
check("a few roam round the house while you are outside", roamers > 0 and roamers <= T.Roam.Count)
-- drive to the Wall: the truck within DropRadius of the drop-off
local resultBefore = E.last(ann, "Moving", "result") -- (an earlier move's)
local wall = V3(Map.Depot.x + T.DropOff[1], 2, Map.Depot.z + T.DropOff[2])
truck.chassis.CFrame = M.CFrame.new(wall.X + 5, wall.Y, wall.Z)
E.place(ann, wall + V3(0, 1, 0))
E.place(bob, wall + V3(4, 1, 0))
E.clock += 0.3
Moving.step()
-- 7.x van moves: the Wall unloads the van (a trip) and the move goes on until the owner's FINISH
check("7.x van moves: at the Wall the van's load is delivered (trip 1), the move goes on", E.last(ann, "Moving", "result") == resultBefore and heard(ann, "Trip 1")
	and stateOf(ann, 5) ~= nil and stateOf(ann, 5).state == "delivered" and E.last(ann, "Moving", "state").a.trips == 1 and box.destroyed == true,
	`{E.last(ann, "Moving", "result") ~= nil} {heard(ann, "Trip 1")} {stateOf(ann, 5) and stateOf(ann, 5).state} {E.last(ann, "Moving", "state").a and E.last(ann, "Moving", "state").a.trips} {box.destroyed} {E.lastNotice(ann)}`)
check("7.0 greeters: the soldier at the Wall welcomes the van (every trip)", E.saidSince(MoveStory.Wall.welcome, 0))
E.request(bob, "finish")
check("…FINISH is the owner's", E.last(ann, "Moving", "result") == resultBefore)
E.request(ann, "finish")
local result = E.last(ann, "Moving", "result")
check("FINISH: the result card, paid for what was delivered", result ~= nil and result.a.how == "done" and result.a.delivered == 1 and result.a.stars >= 1 and result.a.trips == 1)
check("8.0 SANDBOX off: no warehouse on the card, nothing collected", result.a.home == nil and #E.collected == 0)
-- 7.2 review: one ★ thing of three and FINISH is no chapter done (every ★ thing at the Wall whole: MovingRules.starsHome)
check("7.2 review: one thing (a ★ of three) and FINISH: the prologue is not done for anybody", (E.story[ann] or {})["done:prologue"] ~= true and (E.story[bob] or {})["done:prologue"] ~= true
	and MoveStory.forContract("marge") ~= nil and MoveStory.forContract("marge").id == "prologue")
check("…Marge left the porch", porchOf(ann) == nil)
check("…the van's Load and Take out gone, Take out's own spot too", promptIn(truck.model, "Load") == nil and promptIn(truck.model, "Take out") == nil
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
lobbyRequest(cid, "role", "guard")
E.place(cid, home.park and V3(home.park.x, 3, home.park.z) or depot)
lobbyRequest(cid, "launch")
check("7.0 review: LAUNCH away from the board (at the house): refused, the truck comes to the board", E.cars[cid] == nil and string.find(E.lastNotice(cid), "board", 1, true) ~= nil,
	E.lastNotice(cid))
E.place(cid, board + V3(-3, 0, -1))
lobbyRequest(cid, "launch")
check("solo LAUNCH starts the move at once, with the role picked", E.cars[cid] ~= nil and cid:GetAttribute("MoveRole") == "guard")
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
-- 7.x van moves: a thing carried out of the house into `player`'s move's van (its back opened; 7.2 review: `owner`'s
-- move, Ann's without one)
local function loadOne(player: any, spot: number, owner: any?)
	local van = E.cars[owner or ann]
	van.chassis.CFrame = M.CFrame.new(home.park.x, 2, home.park.z) -- (the owner's van, out already: at the house)
	E.place(player, outside)
	trigger(promptIn(site, "Enter house"), player)
	local model = newItem(spot)
	E.place(player, model.PrimaryPart.Position + V3(1, 0, 0))
	trigger(promptIn(model, "Pick up"), player)
	E.place(player, E.interiors[#E.interiors].Position + V3(0, 3, 1))
	trigger(promptIn(workspace, "Leave house"), player)
	van.model:SetAttribute("BackOpen", true)
	E.place(player, van.chassis:FindFirstChild("CargoDoor").WorldPosition + V3(0, 0, 2))
	E.clock += 0.3
	Moving.step()
	trigger(promptIn(van.model, "Load"), player)
	E.clock += 0.3
	Moving.step()
end
Moving.admin(ann, "start")
Moving.step()
loadOne(ann, 1)
truck = E.cars[ann]
check("7.x van moves: the lamp in the new move's van", stateOf(ann, 1) ~= nil and stateOf(ann, 1).state == "truck", `{stateOf(ann, 1) and stateOf(ann, 1).state} {E.lastNotice(ann)}`)
E.cars[ann] = nil -- (another vehicle took its place: the van gone)
E.clock += 0.3
Moving.step()
check("the van gone: what was in it is lost (condition 0), the move goes on", E.last(ann, "Moving", "result") == result and heard(ann, "The van is gone")
	and stateOf(ann, 1).state == "lost" and stateOf(ann, 1).condition == 0)
check("…CAR waits VanAgain s", string.find(E.Vehicles.spawn(ann, false, nil) or "", "comes back", 1, true) ~= nil
	and string.find(E.Vehicles.placeNear(ann, nil) or "", "comes back", 1, true) ~= nil and E.cars[ann] == nil)
do
	local calls = E.vehicleCalls or 0
	local before = #E.messages
	check("7.2 review: …the garage's TAKE OUT (placeAt) and a ZDC RIDE scooter (spawnAt) wait too, said", E.Vehicles.placeAt(ann, nil, M.CFrame.new(0, 0, 0)) == nil
		and E.Vehicles.spawnAt(ann, "escooter", M.CFrame.new(0, 0, 0), false) == nil and (E.vehicleCalls or 0) == calls and heard(ann, "comes back", before + 1),
		`{(E.vehicleCalls or 0) - calls} calls`)
end
E.now += T.VanAgain
E.Vehicles.placeNear(ann, nil)
E.clock += 0.3
Moving.step()
check("…then CAR brings it and the move takes it over (its prompts on it)", E.cars[ann] ~= nil and E.cars[ann] ~= truck and promptIn(E.cars[ann].model, "Load") ~= nil
	and heard(ann, "van is back") and E.last(ann, "Moving", "state").a.truck == true)
Moving.admin(ann, "end")
Moving.admin(ann, "start")
Moving.step()
local timeSaid = Moving.admin(ann, "time")
check("the admin's one minute left", string.find(timeSaid, "minute", 1, true) ~= nil)
E.now += 61
E.clock += 0.3
Moving.step()
result = E.last(ann, "Moving", "result")
check("7.x van moves: 0:00, an empty van and nothing delivered: the end at once, nothing paid", result ~= nil and result.a.how == "failed" and result.a.pay == 0, result and result.a.how)
-- 7.2 review: 0:00 with a trip delivered in time and the van empty: nothing reached the Wall late, so not "late"
Moving.admin(ann, "start")
Moving.step()
loadOne(ann, 1)
Moving.admin(ann, "trip")
Moving.admin(ann, "time")
E.now += 61
E.clock += 0.3
Moving.step()
result = E.last(ann, "Moving", "result")
check("7.2 review: 0:00, a trip in time, the van empty: the end as delivered (not late), paid in full", result ~= nil and result.a.how == "done" and result.a.delivered == 1
	and result.a.pay > 0, result and result.a.how)
Moving.admin(ann, "start")
Moving.step()
loadOne(ann, 1)
Moving.admin(ann, "time")
E.now += 61
E.clock += 0.3
Moving.step()
check("0:00 with a load in the van: 7.0 review: LateGrace s to reach the Wall, no end yet", E.last(ann, "Moving", "result") == result and heard(ann, "Time's up")
	and E.last(ann, "Moving", "state").a.graceEndsAt ~= nil)
E.now += T.LateGrace
Moving.step()
result = E.last(ann, "Moving", "result")
check("…the Wall not reached in time: nothing delivered, nothing paid", result ~= nil and result.a.how == "failed" and result.a.pay == 0, result and result.a.how)
-- 7.2 review: a trip in time, then 0:00 with a load in the van and FINISH in the grace: nothing reached the Wall late
Moving.admin(ann, "start")
Moving.step()
loadOne(ann, 1)
Moving.admin(ann, "trip")
loadOne(ann, 2)
Moving.admin(ann, "time")
E.now += 61
E.clock += 0.3
Moving.step()
E.request(ann, "finish")
result = E.last(ann, "Moving", "result")
check("7.2 review: FINISH in the grace after 0:00, the trip before in time: delivered (not late)", result ~= nil and result.a.how == "done" and result.a.delivered == 1,
	result and result.a.how)
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
	E.onStream = function()
		E.request(ann, "giveup") -- (the move ends while the screen is dark)
	end
	trigger(promptIn(site, "Enter house"), ann)
	check("the move ended during the door's fade: out at the house's door, the fade lifted", (E.rootOf(ann).Position - outside).Magnitude < 6
		and E.last(ann, "Moving", "fade").a == "in" and E.last(ann, "Moving", "result").a.how == "cancelled", E.rootOf(ann).Position)
	Moving.admin(ann, "start")
	Moving.step()
	trigger(promptIn(site, "Enter house"), ann)
	check("…and the next trip goes in (nothing stuck)", (E.rootOf(ann).Position - E.interiors[#E.interiors].Position).Magnitude < 10)
	Moving.admin(ann, "end")
end
check("7.0 review: the contract's plan was made once (every card and START reuse it)", plans == 1, plans)
-- 7.2 review: GIVE UP after a trip: what reached the Wall is paid (the end as FINISH's), not called off for nothing
do
	Moving.admin(ann, "start")
	Moving.step()
	loadOne(ann, 1)
	Moving.admin(ann, "trip")
	local paidBefore = #E.money
	E.request(ann, "giveup")
	result = E.last(ann, "Moving", "result")
	local paid = 0
	for index = paidBefore + 1, #E.money do
		paid += if E.money[index].player == ann and E.money[index].reason == "MovePay" then E.money[index].amount else 0
	end
	check("7.2 review: GIVE UP after a trip: the trip is paid (not called off)", result ~= nil and result.a.how == "done" and result.a.delivered == 1 and paid > 0
		and result.a.money == paid, result and `{result.a.how} {paid}`)
	check("8.0.1, the city unchanged: its words (the Wall paid what reached it)", result ~= nil and result.a.howText == "You called it off: the Wall paid what reached it",
		result and result.a.howText)
end
-- A bike is never the move's van (7.2 review: no back, nothing could be loaded; CAR, MY BIKE and the garage were shut)
do
	local eve = E.player(88, "Eve", board + V3(-3, 0, 3))
	E.profiles[eve] = { car = "rustbike" }
	E.Vehicles.placeNear(eve, nil) -- (MY BIKE: her bike by the kerb, the vehicle she rides)
	local bike = E.cars[eve]
	check("(Eve rides her bike: her profile's car, out, no back)", bike ~= nil and bike.id == "rustbike" and E.Vehicles.isBike(bike) and not E.Vehicles.hasBack(bike))
	Moving.admin(eve, "start")
	local van = E.cars[eve]
	check("7.2 review: a move started on a bike goes with the ZDC Van, put out for it (not the bike)", van ~= nil and van ~= bike and van.id == T.Van and E.Vehicles.hasBack(van)
		and bike.model.destroyed == true, van and van.id)
	check("…and CAR brings the van from now on (her car the van, the bike her bike of choice)", E.profiles[eve].car == T.Van and E.profiles[eve].bike == "rustbike"
		and E.profiles[eve].lastCar == T.Van, E.profiles[eve].car)
	E.clock += 0.3
	Moving.step()
	check("…the van's Load is there", van ~= nil and promptIn(van.model, "Load") ~= nil)
	-- MY BIKE while the van is out: refused (the van stays), but server/Shops.luau's ride made the bike her car already
	E.profiles[eve].car = "rustbike"
	check("(MY BIKE mid-move: refused, the van stays)", string.find(E.Vehicles.spawn(eve, false, nil) or "", "Your van is out", 1, true) ~= nil and E.cars[eve] == van)
	-- the van gone; her bike out after the wait (MY BIKE): the move never takes a bike over
	E.cars[eve] = nil
	E.clock += 0.3
	Moving.step()
	check("7.2 review: the van lost: CAR brings the van again (her car the van once more, the bike her bike of choice)", E.profiles[eve].car == T.Van
		and E.profiles[eve].bike == "rustbike", E.profiles[eve].car)
	E.now += T.VanAgain
	local since = #E.messages
	E.Vehicles.placeNear(eve, "rustbike")
	E.clock += 0.3
	Moving.step()
	check("7.2 review: the van lost, her bike out: the move does not take the bike over", E.cars[eve] ~= nil and E.cars[eve].id == "rustbike"
		and E.last(eve, "Moving", "state").a.truck == false and not heard(eve, "van is back", since + 1))
	E.Vehicles.placeNear(eve, nil) -- (CAR: her profile's car, the van)
	E.clock += 0.3
	Moving.step()
	check("…CAR brings the van and the move takes it", E.cars[eve].id == T.Van and E.last(eve, "Moving", "state").a.truck == true and heard(eve, "van is back", since + 1))
	Moving.admin(eve, "end")
end
-- 7.2 review: the owner leaves after a trip: the trip pays the crew there (not called off for nothing)
do
	Moving.admin(ann, "start")
	Moving.step()
	loadOne(ann, 1)
	Moving.admin(ann, "trip")
	E.place(bob, E.cars[ann].chassis.Position + V3(4, 1, 0))
	check("8.0.1, the city unchanged: a respawn mid-move goes where it always did (no Moving.respawnAt spot)", Moving.respawnAt(ann) == nil and Moving.respawnAt(bob) == nil)
	local paidBefore = #E.money
	local leftAt = #E.messages
	E.leave(ann)
	result = E.last(bob, "Moving", "result")
	local paid = 0
	for index = paidBefore + 1, #E.money do
		paid += if E.money[index].player == bob and E.money[index].reason == "MovePay" then E.money[index].amount else 0
	end
	check("7.2 review: the owner left after a trip: the trip pays the crew there", result ~= nil and result.a.how == "done" and result.a.delivered == 1 and paid > 0
		and string.find(E.lastNotice(bob), "Ann left", 1, true) ~= nil, result and `{result.a.how} {paid} {E.lastNotice(bob)}`)
	check("8.0.1, the city unchanged: its words (The Wall paid what reached it)", heard(bob, "The move ended: Ann left. The Wall paid what reached it.", leftAt)
		and result.a.howText == "Ann left the game: the Wall paid what reached it", result and result.a.howText)
end
do
	local fay = E.player(66, "Fay", board + V3(-3, 0, -3))
	local gus = E.player(77, "Gus", board + V3(-4, 0, -3))
	E.crew[fay] = { gus }
	Moving.admin(fay, "start")
	Moving.step()
	E.leave(fay)
	result = E.last(gus, "Moving", "result")
	check("the owner left with nothing delivered: called off for the crew", result ~= nil and result.a.how == "cancelled" and string.find(E.lastNotice(gus), "Fay left", 1, true) ~= nil)
end
-- 8.0.1, the city unchanged: the planning left open too long sends you back to the depot's board
do
	local hal = E.player(99, "Hal", board + V3(-2, 0, 2))
	trigger(boardPrompt, hal)
	E.request(hal, "start", "marge")
	check("(Hal's planning open)", E.last(hal, "MoveLobby", "lobby") ~= nil and E.last(hal, "MoveLobby", "lobby").a ~= nil, E.lastNotice(hal))
	E.now += R.Lobby.Timeout + 1
	local since = #E.messages
	Lobby.step()
	check("8.0.1, the city unchanged: the planning's timeout says the depot's board", heard(hal, "take the contract again at the depot's board", since), E.lastNotice(hal))
end
-- 8.1 walk-in doors (the owner: "no E at the house, neither in nor out"; Config.Moving.Doors): walk into the zone in
-- front of the door and through it after Dwell s facing it; brushing past or walking by is no way in; out the same way
-- by the doorway inside; after a trip no way back until you stepped out of the zone you came out in and Rearm s went by;
-- a piece in your hands and a pair piece's other end come along; only the move's crew on foot; the doormats.
do
	local D = T.Doors
	local ivy = E.player(111, "Ivy", board + V3(-2, 0, -4))
	local jo = E.player(112, "Jo", board + V3(-3, 0, -5))
	local kim = E.player(113, "Kim", depot)
	E.crew[ivy] = { jo }
	check("(the walk-in doors on: a dwell, a longer re-arm, the zone shallower than where you come out)", D.Walk == true and D.Dwell > 0 and D.Rearm > D.Dwell
		and D.Depth < 4 and D.Every <= T.Tick)
	Moving.admin(ivy, "start")
	Moving.step()
	local origin = E.interiors[#E.interiors]
	local up = V3(0, Config.Furniture.EntryUp, 0)
	local foot = V3(home.door.x, Map.WalkTop, home.door.z) -- (the door's foot outside, the server's)
	local side = V3(-facing.Z, 0, facing.X)
	local front = foot + up + facing * 2 -- (in front of the door, in its zone)
	local into = V3(0, 0, 1) -- (the fake plan's +Z: from its exit to its entry)
	local exitAt = origin * V3(0, 0, 0.5) + up -- (the fake plan's exit, a body's height over the floor)
	local function stand(player: any, at: any, look: any)
		E.rootOf(player).CFrame = M.CFrame.lookAt(at, at + look)
	end
	local function wait(seconds: number)
		E.clock += seconds
		Moving.step()
	end
	local function isIn(player: any): boolean
		return (E.rootOf(player).Position - origin.Position).Magnitude < 100
	end
	local function fades(player: any, since: number): number
		local n = 0
		for index = since + 1, #E.messages do
			n += if E.messages[index].player == player and E.messages[index].kind == "fade" then 1 else 0
		end
		return n
	end
	local function said(player: any, text: string, since: number): number
		local n = 0
		for index = since + 1, #E.messages do
			local m = E.messages[index]
			n += if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then 1 else 0
		end
		return n
	end
	local function matsIn(model: any): { any }
		local found = {}
		for _, d in model:GetDescendants() do
			if d.Name == "WalkInMat" and not d.destroyed then
				table.insert(found, d)
			end
		end
		return found
	end
	local function words(mat: any): string
		local gui = mat:FindFirstChildOfClass("SurfaceGui")
		local label = gui and gui:FindFirstChildOfClass("TextLabel")
		return if label then tostring(label.Text) else ""
	end

	check("8.1 walk-in doors: no E at the doors (Enter house and Leave house there, off)", not promptIn(site, "Enter house").Enabled
		and not promptIn(workspace, "Leave house").Enabled)
	local outMats = matsIn(site)
	local mat = outMats[1]
	local matAt = if mat then mat.Position - foot else V3()
	check("a doormat in front of the door (▲ IN), in its zone, shown while a move uses the house", #outMats == 1 and words(mat) == "▲ IN" and mat.Transparency == 0
		and mat:FindFirstChildOfClass("SurfaceGui").Enabled == true and matAt:Dot(facing) > 0.5 and matAt:Dot(facing) < D.Depth and math.abs(matAt:Dot(side)) < 0.1
		and mat.CanCollide == false and mat.CanQuery == false, `{#outMats} {mat and words(mat)}`)
	local inMat = nil
	for _, d in matsIn(workspace) do
		if words(d) == "▲ OUT" and (d.Position - origin.Position).Magnitude < 20 then
			inMat = d
		end
	end
	check("…and one inside by the way out (▲ OUT), in the interior", inMat ~= nil and inMat.Parent ~= nil and inMat.Parent.Name == "Interior")

	-- a stranger, a seated crew mate: nothing
	local since = #E.messages
	stand(kim, front, -facing)
	wait(0.1)
	wait(0.5)
	wait(0.5)
	check("a stranger in the zone facing the door: stays out (only the move's crew)", not isIn(kim) and fades(kim, since) == 0)
	E.place(kim, depot)
	E.seated[jo] = E.cars[ivy]
	E.rootOf(jo).Parent:FindFirstChildOfClass("Humanoid").SeatPart = E.cars[ivy].chassis
	stand(jo, front, -facing)
	wait(0.1)
	wait(0.5)
	check("…nor a crew mate sitting (in a seat)", not isIn(jo) and fades(jo, since) == 0)
	E.rootOf(jo).Parent:FindFirstChildOfClass("Humanoid").SeatPart = nil
	E.seated[jo] = nil
	E.place(jo, foot + up + facing * 12)

	-- walking past, brushing past: no way in
	stand(ivy, front, side)
	wait(0.1)
	wait(0.4)
	wait(0.4)
	check("walking past the door (in its zone, looking along the wall): no way in", not isIn(ivy) and fades(ivy, since) == 0)
	stand(ivy, front, -facing)
	wait(0.1)
	wait(D.Dwell * 0.5)
	stand(ivy, front + facing * 4, -facing)
	wait(0.1)
	wait(D.Dwell + 0.2)
	check("brushing past (in it facing the door for less than the dwell, then out of it): no way in", not isIn(ivy) and fades(ivy, since) == 0)
	stand(ivy, front + side * (2 / 2 + D.Side + 1.5), -facing)
	wait(0.1)
	wait(D.Dwell + 0.2)
	check("…nor beside the doorway (past its jambs)", not isIn(ivy))

	-- walk in
	stand(ivy, front, -facing)
	wait(0.1)
	check("in the zone facing the door: not before the dwell", not isIn(ivy))
	wait(D.Dwell)
	local entry = origin * M.CFrame.new(0, 0, 1)
	check("walked in after the dwell: in the house at its entry, no E", isIn(ivy) and (E.rootOf(ivy).Position - entry.Position).Magnitude < 4, E.rootOf(ivy).Position)
	check("…with the fade out and in", fades(ivy, since) == 2, fades(ivy, since))
	check("…facing into the room, away from the door", E.rootOf(ivy).CFrame.LookVector:Dot(into) > 0.99)
	local state = E.last(ivy, "Moving", "state")
	check("…the state says inside (the HUD, the guide)", state ~= nil and state.a ~= nil and state.a.inside == true)

	-- no ping-pong: the zone she came out in stays shut until she has left it, Rearm s at least
	stand(ivy, exitAt + into * 0.5, -into) -- (turned straight back to the door, still in the zone)
	since = #E.messages
	for _ = 1, 6 do
		wait(0.5)
	end
	check("no ping-pong: turned back to the door in its zone, past Rearm s: still in (she never left it)", isIn(ivy) and fades(ivy, since) == 0)
	stand(ivy, exitAt + into * 8, -into)
	wait(0.1)
	stand(ivy, exitAt + into * 1, -into)
	wait(0.1)
	check("…out of the zone and back in: not before the dwell", isIn(ivy))
	wait(D.Dwell)
	local outside4 = foot + facing * 4
	check("walked out by the doorway inside: at the house's door, a few studs out", not isIn(ivy) and math.abs(V3(E.rootOf(ivy).Position.X - foot.X, 0, E.rootOf(ivy).Position.Z - foot.Z).Magnitude - 4) < 0.5,
		E.rootOf(ivy).Position)
	check("…facing away from the door, with the fade", E.rootOf(ivy).CFrame.LookVector:Dot(facing) > 0.99 and fades(ivy, since) == 2)
	check("…where she came out is clear of the zone (Depth)", (E.rootOf(ivy).Position - foot):Dot(facing) > D.Depth and (outside4 - foot):Dot(facing) > D.Depth)
	-- Rearm s, whichever is later: she steps back into the zone at once, facing the door
	local arrived = E.clock
	stand(ivy, front, -facing)
	while E.clock - arrived < D.Rearm - 0.15 do
		wait(0.1)
	end
	check("…stepped back into the zone at once: shut for Rearm s (whichever is later)", not isIn(ivy))
	wait(0.2)
	wait(0.1)
	wait(D.Dwell)
	check("…then in again after the dwell", isIn(ivy))

	-- carrying: out with a piece in the hands, in with it
	local tvModel = newItem(2)
	E.place(ivy, tvModel.PrimaryPart.Position + V3(1, 0, 0))
	trigger(promptIn(tvModel, "Pick up"), ivy)
	wait(1)
	check("(Ivy holds the TV)", ivy.Character:GetAttribute("MoveCarry") == 2)
	stand(ivy, exitAt + into * 2, -into)
	wait(1) -- (no teleport: a second for the way there)
	wait(D.Dwell)
	check("carrying: out by the door with the TV in her hands", not isIn(ivy) and ivy.Character:GetAttribute("MoveCarry") == 2 and stateOf(ivy, 2).state == "carried")
	stand(ivy, foot + up + facing * 9, -facing)
	wait(D.Rearm)
	stand(ivy, front, -facing)
	wait(0.6)
	wait(D.Dwell)
	check("…and in again with it", isIn(ivy) and ivy.Character:GetAttribute("MoveCarry") == 2)
	E.Net.get("PutDown").OnServerEvent:Fire(ivy)

	-- a pair piece: the back end does not lead; the front end walks out and the other end comes along
	stand(jo, front, -facing)
	wait(0.1)
	wait(D.Dwell)
	check("Jo walks in too", isIn(jo))
	local sofaModel = newItem(3)
	local sofaAt = sofaModel.PrimaryPart.Position
	E.place(ivy, sofaAt + V3(0, 0, -3))
	E.place(jo, sofaAt + V3(0, 0, 3))
	trigger(promptIn(sofaModel, "Lift"), ivy)
	trigger(promptIn(sofaModel, "Help lift"), jo)
	wait(1)
	check("(Ivy and Jo carry the sofa: Ivy at the front)", ivy.Character:GetAttribute("MoveCarry") == 3 and jo.Character:GetAttribute("MoveCarry") == 3)
	since = #E.messages
	stand(jo, exitAt + into * 1 + V3(1.5, 0, 0), -into)
	stand(ivy, exitAt + into * 9, -into)
	wait(1)
	wait(D.Dwell)
	wait(0.4)
	check("the back end in the doorway first: it does not lead (said once), nobody goes", isIn(jo) and isIn(ivy) and said(jo, "front leads", since) == 1)
	stand(ivy, exitAt + into * 2, -into)
	stand(jo, exitAt + into * 6, -into)
	wait(0.6)
	wait(D.Dwell)
	check("the front end walks out: both out with the sofa, side by side", not isIn(ivy) and not isIn(jo) and ivy.Character:GetAttribute("MoveCarry") == 3
		and jo.Character:GetAttribute("MoveCarry") == 3 and (E.rootOf(jo).Position - E.rootOf(ivy).Position).Magnitude < 5)
	-- 8.1 carrying in two (client/PairSteer.luau): the leader walks backwards, facing the sofa and Jo: she backs through
	-- the door, her back to it
	check("8.1 (Ivy leads the sofa in two: PairTurn on her, none on Jo)", ivy.Character:GetAttribute("PairTurn") == Config.MoveHelper.PairTurn
		and jo.Character:GetAttribute("PairTurn") == nil)
	stand(jo, foot + up + facing * 10, -facing)
	stand(ivy, foot + up + facing * 7, facing)
	wait(D.Rearm)
	wait(0.2)
	since = #E.messages
	stand(ivy, front, facing) -- (her back to the door, standing: a drift back to it)
	E.rootOf(ivy).AssemblyLinearVelocity = V3(0, 0, 0)
	wait(0.1)
	wait(D.Dwell + 0.1)
	check("8.1 review: the leader standing in the zone, her back to the door, is not taken through (only walking into it)",
		not isIn(ivy) and not isIn(jo) and fades(ivy, since) == 0)
	E.rootOf(ivy).AssemblyLinearVelocity = -facing * (D.PairWalk + 2) -- (backing into it)
	wait(0.1)
	wait(D.Dwell + 0.1)
	check("8.1 the leader of a pair piece backs through the door (her back to it): both in with the sofa", isIn(ivy) and isIn(jo)
		and ivy.Character:GetAttribute("MoveCarry") == 3 and jo.Character:GetAttribute("MoveCarry") == 3 and fades(ivy, since) == 2)
	E.rootOf(ivy).AssemblyLinearVelocity = V3(0, 0, 0)
	E.Net.get("PutDown").OnServerEvent:Fire(ivy)
	-- …nobody else goes through backwards: Jo, hands free, her back to the doorway inside
	wait(D.Rearm)
	stand(jo, exitAt + into * 12, into)
	wait(0.2)
	since = #E.messages
	stand(jo, exitAt + into * 1, into)
	wait(0.1)
	wait(D.Dwell + 0.2)
	check("…but hands free, the back to the door is no way through (facing it, as ever)", isIn(jo) and fades(jo, since) == 0)
	stand(jo, exitAt + into * 1, -into)
	wait(0.1)
	wait(D.Dwell + 0.1)
	check("…turned to it: out", not isIn(jo))
	E.place(ivy, foot + up + facing * 12)
	E.Net.get("PutDown").OnServerEvent:Fire(ivy)

	Moving.admin(ivy, "end")
	check("the move over: the doormat outside hidden again", mat ~= nil and mat.Transparency == 1 and mat:FindFirstChildOfClass("SurfaceGui").Enabled == false)
	E.leave(ivy)
	E.leave(jo)
	E.leave(kim)
end
check("every interior went (slots free again)", E.destroyed == E.built, `{E.destroyed} of {E.built}`)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
