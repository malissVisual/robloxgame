-- 7.0 prototype, MOVES (10.5: every move a run): the real server/Moving.luau run in the Luau CLI (tests/run_tests.py
-- builds MovingServer.luau with tests/runtime/MovingRuntime.luau's fakes in place of its server modules; the art is a
-- fake shaped like the art branch's FurnitureLooks / HouseLayout / HouseInterior). A whole run of a crew: its start
-- (the van at the house's curb, the interior), the crew, the door in and out with its fades, picking up, dragging and
-- lifting in two, the truck's back, loading and the no-room refusal, unloading, the damage, a death, a helper too far, a
-- teleport with a thing, the horde, the run's end (FINISH, GIVE UP, the clock, the host leaving: what is in the truck
-- goes home), and the edges: a stranger, the truck lost, the admin's commands.
-- 7.0 planning: the quick chat on a run (the real server/MoveLobby.luau: the crew hears it, a stranger not).
-- 7.0 review (server): nothing replaces the truck mid-move (Vehicles' spawn / placeNear / placeAt / spawnAt), Moving.busy
-- and Crew.hasJob, a door trip whose move ends meanwhile, Load's pace check, Unload's full hands, the end's listeners
-- failing (the cleanup still runs), the plan made once a seed.
-- 8.8 no roles: anybody of the crew calls the van to the door, once a run (tests/noroles_runtime_test.luau has the rest).
-- 8.1 walk-in doors (Config.Moving.Doors; the E prompts there but off): walking into the door's zone facing it goes in
-- after the dwell (not a stranger, not from a seat, not walking past, not brushing past, not beside the doorway), out by
-- the doorway inside, no ping-pong (shut until you left the zone you came out in and Rearm s went by, whichever later),
-- in and out with a piece in your hands, a pair piece's back end does not lead (said once), its front end takes it along;
-- the doormats (▲ IN outside while a move uses the house, ▲ OUT inside).
-- 8.3 the doors swing (Config.Moving.Doors, shared/DoorSwing.luau): the leaves found and tagged at the start, shut;
-- walking up facing a door opens its leaf before its zone, the trip waits until it has been open Open s; the fade out's
-- FadeOut, the move FadeOut + Margin s later, the fade in's arrival (where you are, the way you face, Dark, Wait), the
-- walk carried on; the door behind you open, both shut Shut s after their zones emptied; a pair piece's crew mate lands
-- at its far end in front of the leader in the same moment.
-- (Danny is on every run: Config.MoveHelper.WaitForHelper off here, so the crew's two-person lifts are the players';
-- tests/movehelper_runtime_test.luau has his. tests/sandboxmove_runtime_test.luau has the run's own words and facts.)
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local Economy = require("./Economy")

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
Config.MoveHelper.WaitForHelper = false -- (the crew lifts its two-person pieces itself: nobody waits for Danny)

-- the places: the lone house (one way in and out), the lobby
local HOUSE = "lone_house"
local House = SandboxMap.house(HOUSE) :: any
local door, facing, outside = E.doorOf(House)
local lobby = V3(SandboxMap.Lobby.spawn.x, 3, SandboxMap.Lobby.spawn.z)
-- the big slab fills the Sprinter's whole floor (6.5 × 13.5 of its 6.6 × 13.7), its top low enough for the lamp and the
-- sofa on it: no room as the bay is once they stand on the floor, room once repacked (the movers' Pack.Repack)
E.items.slab.size = V3(6.5, 3.6, 13.5)

local ann = E.player(11, "Ann", lobby + V3(-3, 0, 0))
local bob = E.player(22, "Bob", lobby + V3(-4, 0, 2))
local cid = E.player(33, "Cid", lobby)
E.crew[ann] = { bob }

local plans = 0 -- (7.0 review: a house's plan is made once a seed: every run on it reuses it)
local planOf = E.art.layout.plan
E.art.layout.plan = function(...: any): any
	plans += 1
	return planOf(...)
end
Moving.useArt(E.art)
Moving.parkVan = E.parkVan
Moving.start()
-- what each run's end told (server/Runs.luau's results card: Moving.onRunEnd)
local ends: { { host: any, facts: any } } = {}
Moving.onRunEnd(function(host: any, facts: any)
	table.insert(ends, { host = host, facts = facts })
end)
local function lastEnd(): any
	local entry = ends[#ends]
	return if entry then entry.facts else nil
end

local moves = workspace:FindFirstChild("Moves")
local site = moves and moves:FindFirstChild(`Move_{HOUSE}`)
check("the Moves folder: a site a house to empty (its door), no board, no drop-off", moves ~= nil and site ~= nil and moves:FindFirstChild("Move_sandbox_house") ~= nil
	and moves:FindFirstChild("MovingBoard") == nil and moves:FindFirstChild("MovingDropOff") == nil)

local function promptIn(model: any, action: string?): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and (action == nil or d.ActionText == action or string.find(tostring(d.ActionText), action, 1, true) == 1) then
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
	for index = math.max(since or 1, 1), #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then
			return true
		end
	end
	return false
end
local function stateOf(player: any, spot: number): any
	local v = E.last(player, "Moving", "state")
	for _, item in (v and v.a and v.a.items) or {} do
		if item.spot == spot then
			return item
		end
	end
	return nil
end

-- The run's start --------------------------------------------------------------------------------------------------------

check("a crew member does not start a run (their owner does)", string.find(Moving.startRun(bob, HOUSE, "normal") or "", "crew", 1, true) ~= nil and E.built == 0)
local startedAt = #E.messages
check("the run: Ann's own van at the house's curb (the Sprinter), the interior built", E.startRun(ann, HOUSE) == nil and E.cars[ann] ~= nil
	and E.cars[ann].id == Config.Sandbox.Van and E.built == 1 and #E.interiors == 1)
local truck = E.cars[ann]
check("everybody of the crew hears it", heard(bob, "on the clock", startedAt))
Moving.step()
check("the crew is on the move (MoveWith)", ann:GetAttribute("MoveWith") == 11 and bob:GetAttribute("MoveWith") == 11 and cid:GetAttribute("MoveWith") == nil)
local view = E.last(ann, "Moving", "state")
check("the state: 6 things, 3 ★, the clock (the house's at Normal), Ann's", view ~= nil and view.a ~= nil and #view.a.items == 6 and view.a.counts.stars == 3
	and view.a.endsAt == E.now + T.Sandbox.Houses[HOUSE].Time and view.a.mine == true)
check("…and Bob's says it is Ann's", E.last(bob, "Moving", "state") ~= nil and E.last(bob, "Moving", "state").a.mine == false)
check("no second move at once", string.find(Moving.startRun(ann, HOUSE, "normal") or "", "already", 1, true) ~= nil)
lobbyRequest(ann, "chat", 1)
local chat = E.last(bob, "MoveLobby", "chat")
check("the quick chat on a run: the crew hears it, a stranger not", chat ~= nil and chat.a.index == 1 and chat.a.from == 11 and E.last(cid, "MoveLobby", "chat") == nil)
lobbyRequest(cid, "chat", 2)
lobbyRequest(ann, "chat", 9)
check("…not from a stranger, nor a line it doesn't have", E.last(bob, "MoveLobby", "chat") == chat)

-- Call the van to the door (8.8: anybody of the crew, once a run) ------------------------------------------------------------

local curb = V3(House.curb.x, 2, House.curb.z)
truck.chassis.CFrame = M.CFrame.new(curb.X + 60, 2, curb.Z + 40)
E.seated[bob] = truck
E.request(ann, "call")
check("not with somebody in it", string.find(E.lastNotice(ann), "sits in the van", 1, true) ~= nil, E.lastNotice(ann))
E.seated[bob] = nil
E.request(bob, "call")
check("a crew mate calls the van: at the house's curb, stood up, with a fade for the caller", V3(truck.chassis.Position.X - curb.X, 0, truck.chassis.Position.Z - curb.Z).Magnitude < 1
	and E.stoodUp == 1 and E.last(bob, "Moving", "fade") ~= nil and E.last(ann, "Moving", "fade") == nil, truck.chassis.Position)
E.request(ann, "call")
check("…once a run", string.find(E.lastNotice(ann), "once", 1, true) ~= nil, E.lastNotice(ann))

-- 7.0 review: nothing takes the truck's place mid-move; the move's people are busy -------------------------------------------

do
	local calls = E.vehicleCalls or 0
	local out = "Your van is out"
	check("CAR (Vehicles.spawn): refused, the truck stays", string.find(E.Vehicles.spawn(ann, false, nil) or "", out, 1, true) ~= nil
		and string.find(E.Vehicles.spawn(ann, true, "van") or "", out, 1, true) ~= nil and E.cars[ann] == truck)
	check("…a van next to you (Vehicles.placeNear): refused", string.find(E.Vehicles.placeNear(ann, nil) or "", out, 1, true) ~= nil and E.cars[ann] == truck)
	check("…a van parked at a spot (placeAt, spawnAt): refused, said", E.Vehicles.placeAt(ann, nil, M.CFrame.new(0, 0, 0)) == nil
		and E.Vehicles.spawnAt(ann, "sprinter", M.CFrame.new(0, 0, 0), false) == nil and string.find(E.lastNotice(ann), out, 1, true) ~= nil and (E.vehicleCalls or 0) == calls)
	E.Vehicles.spawn(bob, false, nil)
	check("…a crew mate's own van is theirs to call", (E.vehicleCalls or 0) == calls + 1)
	check("the run's people are busy (Moving.busy): its owner and its crew, a stranger free", type(Moving.busy(ann)) == "string" and type(Moving.busy(bob)) == "string"
		and Moving.busy(cid) == nil)
	check("the crews see the move's owner busy (Crew.hasJob), not its crew", E.Crew.hasJob(ann) == true and E.Crew.hasJob(bob) == false and E.Crew.hasJob(cid) == false)
end

-- The door ---------------------------------------------------------------------------------------------------------------

local enter = promptIn(site, "Enter house")
check("the move's own Enter house: its crew's only (MoveOwner), open from the start (8.1 walk-in doors: walked through, the prompt off)", enter ~= nil
	and enter:GetAttribute("MoveOwner") == 11 and not enter.Enabled)
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
check("…with a fade out and in", fades == 2, fades)
E.place(bob, door + facing * 30)
trigger(enter, bob)
check("not from across the yard", (E.rootOf(bob).Position - door).Magnitude > 20)
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
check("the truck's Load prompt waits while the back is shut", load ~= nil and load.Parent == cargoDoor and not load.Enabled)
trigger(load, ann)
check("Load with the back shut says so", string.find(E.lastNotice(ann), "Open the back", 1, true) ~= nil, E.lastNotice(ann))
truck.model:SetAttribute("BackOpen", true)
E.clock += 0.2
Moving.step()
local backPrompt = cargoDoor:FindFirstChild("BackPrompt")
check("back open, a thing carried: Load shows, the back's own E waits", load.Enabled and not backPrompt.Enabled and string.find(load.ActionText, "Lamp", 1, true) ~= nil, load.ActionText)
local vanName = (Economy.findCar(truck.id) :: any).name
check("the prompts say the van's name (the Sprinter's), its walk-in bay its own Load", string.find(load.ObjectText, `{vanName} ·`, 1, true) == 1
	and truck.chassis:FindFirstChild("MoveLoadBay") ~= nil, load.ObjectText)
check("the crew may open the back (BackCrew, backAllowed)", truck.model:GetAttribute("BackCrew") == "22")
trigger(load, ann)
check("loaded: hands free, in the truck", character:GetAttribute("MoveCarry") == nil and character:GetAttribute("Carrying") == nil and string.find(E.lastNotice(ann), "loaded", 1, true) ~= nil, E.lastNotice(ann))
local weld = lampRoot:FindFirstChildOfClass("WeldConstraint")
check("…welded to the truck, inside its box", weld ~= nil and weld.Part0 == truck.chassis and (lampRoot.Position - truck.chassis.Position).Magnitude < 12, `{weld and weld.Part0 and weld.Part0.Name} {(lampRoot.Position - truck.chassis.Position).Magnitude} {truck.chassis.CFrame:PointToObjectSpace(lampRoot.Position).X} {truck.chassis.CFrame:PointToObjectSpace(lampRoot.Position).Y} {truck.chassis.CFrame:PointToObjectSpace(lampRoot.Position).Z}`)
E.clock += 0.2
Moving.step()
local unload = promptIn(truck.model, "Take out")
check("Unload (Z, \"Take out\") shows the last one in", unload ~= nil and unload.Enabled and unload.KeyboardKeyCode == "Z" and string.find(unload.ActionText, "Lamp", 1, true) ~= nil)
-- the owner's report: Unload sat on the door's own attachment with Load and the back's E (all stacked)
check("Unload on its own spot beside the door, not stacked with Load and the back's E", unload.Parent ~= cargoDoor and unload.Parent.Name == "MoveTakeOut"
	and unload.Parent.Parent == truck.chassis and (unload.Parent.WorldPosition - cargoDoor.WorldPosition).Magnitude > 2 and not load.Enabled and backPrompt.Enabled)
character:SetAttribute("Pushing", "trolley")
trigger(unload, ann)
check("7.0 review: Unload with your hands full: refused", character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(ann), "hands are full", 1, true) ~= nil
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
-- (9.0: one attachment each, Ann's own, nothing on the sofa: no constraint joins her body to Bob's; the server sets the
-- goals, the sofa's far end, from where it is)
local mateGoal = sofaRoot.CFrame * (mateHold and mateHold.offset or M.CFrame.new())
check("8.1 the helper held at the sofa's far end by the server: constraints on Ann's root aimed there (9.0 one attachment, hers: nothing on the sofa)",
	mateHold ~= nil and mateHold.align.Parent == annRoot and mateHold.align.Mode == "OneAttachment" and mateHold.align.Attachment1 == nil
	and mateHold.orient.Mode == "OneAttachment" and mateHold.orient.Attachment1 == nil and mateHold.align.Attachment0 == mateHold.own
	and mateHold.own.Parent == annRoot and (mateHold.align.props.Position - mateGoal.Position).Magnitude < 1e-6
	-- (8.6: the sofa lies along the carry, its +X ahead of Bob: Ann's end the far end of its length, Standoff past it)
	and math.abs(mateHold.offset.Position.X - (E.items.sofa.size.X / 2 + H.Standoff)) < 1e-6 and math.abs(mateHold.offset.Position.Z) < 1e-6)
check("…at the pair's top speed (never put there), along the ground only (Ann stands on the floor herself)", mateHold ~= nil
	and math.abs(mateHold.align.MaxVelocity - Brain.holdSpeed(14 * T.Speed.Pair)) < 1e-6 and mateHold.align.MaxAxesForce.Y == 0
	and mateHold.align.MaxAxesForce.X > 0 and math.abs(mateHold.orient.MaxAngularVelocity - Brain.holdTurn()) < 1e-6)
check("…the server owns Ann's body meanwhile (its positions, whatever the lag)", annRoot.NetworkOwner == false)
-- 8.3 keeping up (the owner: "when I run, he just goes behind me"): both carry CarryPair (no run for either:
-- client/PairSteer.luau), and the far end's top speed follows the leader's real speed (her root held there each look, as
-- the constraints would)
check("8.3 two carry it: CarryPair on the leader and on the far end's crew mate (nobody runs)", bobBody:GetAttribute("CarryPair") == true
	and character:GetAttribute("CarryPair") == true)
local pairWalk = 14 * T.Speed.Pair
local bobWas, annWas, sofaWas = E.rootOf(bob).CFrame, annRoot.CFrame, sofaRoot.CFrame
local function bobWalks(speed: number, looks: number)
	for _ = 1, looks do
		local bobRoot = E.rootOf(bob)
		bobRoot.CFrame = bobRoot.CFrame + V3(0, 0, speed * 0.2)
		E.welded(sofa) -- (8.6: where the weld keeps it)
		annRoot.CFrame = sofaRoot.CFrame * mateHold.offset
		E.clock += 0.2
		Moving.step()
	end
end
bobWalks(pairWalk * 1.2, 3)
check("8.3 the leader 20% faster: the crew mate's top speed follows the leader's real speed (× HoldMargin + HoldExtra)",
	math.abs(mateHold.align.MaxVelocity - Brain.holdSpeed(pairWalk, pairWalk * 1.2)) < 1e-6 and mateHold.align.MaxVelocity > Brain.holdSpeed(pairWalk),
	mateHold.align.MaxVelocity)
bobWalks(28, 3)
check("8.3 …at a sprint: more than the sprint, HoldCap at most", mateHold.align.MaxVelocity > 28 and mateHold.align.MaxVelocity <= H.HoldCap + 1e-6
	and bobBody:GetAttribute("MoveCarry") == 3, mateHold.align.MaxVelocity)
bobWalks(0, 15)
check("8.3 …standing 3 s: the carry's own top speed again", math.abs(mateHold.align.MaxVelocity - Brain.holdSpeed(pairWalk)) < 0.1, mateHold.align.MaxVelocity)
E.rootOf(bob).CFrame, annRoot.CFrame, sofaRoot.CFrame = bobWas, annWas, sofaWas -- (back where they stood)
-- the carrier leaves the house: the helper comes along
E.place(bob, origin.Position + V3(0, 3, 1))
trigger(leave, ann)
check("the helper does not lead the way", string.find(E.lastNotice(ann), "front", 1, true) ~= nil)
trigger(leave, bob)
check("the carrier leads out, the helper comes along", (E.rootOf(bob).Position - outside).Magnitude < 4
	and (E.rootOf(ann).Position - outside).Magnitude < 4 + Config.Cargo.CarryFront + E.items.sofa.size.X + H.Standoff) -- (8.6: at its length's far end)
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
	and mateHold.own.Parent == nil and annRoot.NetworkOwner == ann and bobBody:GetAttribute("PairTurn") == nil)
check("8.3 …and both CarryPair gone (their walks theirs again)", bobBody:GetAttribute("CarryPair") == nil and character:GetAttribute("CarryPair") == nil)
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

-- Damage, a death, a teleport, no room -------------------------------------------------------------------------------------

E.place(ann, outside)
trigger(enter, ann)
local clock = itemModel(4)
E.place(ann, clock.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(clock, "Pick up"), ann)
local humanoid = character:FindFirstChildOfClass("Humanoid")
humanoid.Health = 80
humanoid.HealthChanged:Fire(80)
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
-- the big slab: no room after the lamp and the sofa (the movers' repack off: Config.Moving.Pack.Repack)
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

-- GIVE UP: what is in the truck goes home ------------------------------------------------------------------------------------

E.request(bob, "giveup")
check("only the host gives up", #ends == 0)
E.request(ann, "giveup")
local over = lastEnd()
check("GIVE UP ends the run: what was in the truck went home (done), into the stock of whoever loaded it", over ~= nil and over.phase == "done" and #over.pieces == 3
	and #E.collected == 3 and over.crew ~= nil and #over.crew == 2, over and `{over.phase} {#over.pieces}`)
local toOf: { [string]: number } = {}
for _, piece in (over and over.pieces) or {} do
	toOf[piece.item] = piece.to
end
check("…the lamp and the slab Ann's, the sofa Bob's (he loaded it)", toOf.lamp == 11 and toOf.slab == 11 and toOf.sofa == 22, `{toOf.lamp} {toOf.slab} {toOf.sofa}`)
check("no pay (the warehouse earns), the interior gone, nobody on it", #E.money == 0 and E.destroyed == 1 and ann:GetAttribute("MoveWith") == nil and bob:GetAttribute("MoveWith") == nil)

-- The horde (the admin's HORDE NOW), the roamers, FINISH ---------------------------------------------------------------------

local zombiesBefore = #E.zombies
T.Sandbox.Roam = 2 -- (switched on for the test: a few round the house)
check("the admin's start", E.startRun(ann, HOUSE) == nil and E.built == 2)
truck = E.cars[ann]
cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
load = promptIn(truck.model, "Load")
Moving.step()
E.place(ann, outside)
enter = promptIn(site, "Enter house")
check("the door open at once: Enter house (off: 8.1 walk-in doors), no Kick door, no noise", enter ~= nil and not enter.Enabled and promptIn(site, "Kick door") == nil and E.noises == 0)
E.clock += T.Roam.Every + 0.1
Moving.step() -- (Ann outside by the house: the run's few roamers come round it)
local z0 = E.zombies[#E.zombies]
check("…a roamer of this run round the house (Config.Moving.Sandbox.Roam)", z0 ~= nil and z0.roamer == true and #E.zombies - zombiesBefore <= T.Sandbox.Roam)
trigger(enter, ann)
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
check("during the run the truck stays: CAR does not swap it", string.find(E.Vehicles.callCar(ann, nil) or "", "van is out", 1, true) ~= nil)
check("the crew is hunted (no ordinary roamers round them), a stranger not", E.Zombies.hunts(bob) == true and E.Zombies.hunts(ann) == true and E.Zombies.hunts(cid) == false)
check("the crew may open the truck's back, a stranger not", E.Vehicles.backAllowed(bob, truck) == true and E.Vehicles.backAllowed(cid, truck) == false)
E.Zombies.onCarDamaged(ann, 100)
E.clock += 0.3
Moving.step()
local knocked = stateOf(ann, 5)
check("the truck's knocks knock its load", knocked ~= nil and math.abs(knocked.condition - (1 - 100 * T.Damage.PerTruckHp)) < 0.01, knocked and knocked.condition)
local hordeSaid = Moving.admin(ann, "horde")
E.clock += 1
Moving.step()
check("the admin's HORDE NOW: zombies march on the house", string.find(hordeSaid, "horde", 1, true) ~= nil and E.marched > 0 and heard(ann, "HORDE")
	and E.last(ann, "Moving", "state").a.horde == true)
E.request(bob, "finish")
check("FINISH is the host's", #ends == 1)
E.request(ann, "finish")
over = lastEnd()
check("FINISH: the run's end, what was in the truck home", #ends == 2 and over.phase == "done" and #over.pieces == 1 and over.pieces[1].item == "box" and over.pieces[1].to == 11)
local tracked = false
for _, entry in E.tracked do
	if entry.name == "event" and entry.args[2] == "MoveDone" then
		tracked = true
	end
end
check("analytics: MoveDone", tracked)
check("…the van's Load and Take out gone, Take out's own spot too", promptIn(truck.model, "Load") == nil and promptIn(truck.model, "Take out") == nil
	and truck.chassis:FindFirstChild("MoveTakeOut") == nil and truck.chassis:FindFirstChild("CargoDoor") ~= nil)
check("the session is gone: the hooks let the truck go again", ann:GetAttribute("MoveWith") == nil and E.destroyed == 2 and E.Vehicles.callCar(ann, nil) == "called"
	and E.Zombies.hunts(bob) == false)
check("the horde let go", (function()
	for _, z in E.zombies do
		if z.march ~= nil then
			return false
		end
	end
	return true
end)())
T.Sandbox.Roam = 0

-- The truck lost; the clock; the admin's other commands --------------------------------------------------------------------

check("no run: the admin says so", string.find(Moving.admin(ann, "horde"), "not on a run", 1, true) ~= nil)
-- a thing carried out of the house into `owner`'s run's van (its back opened; Ann's without one)
local function loadOne(player: any, spot: number, owner: any?)
	local van = E.cars[owner or ann]
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
E.startRun(ann, HOUSE)
Moving.step()
loadOne(ann, 1)
truck = E.cars[ann]
check("the lamp in the new run's van", stateOf(ann, 1) ~= nil and stateOf(ann, 1).state == "truck", `{stateOf(ann, 1) and stateOf(ann, 1).state} {E.lastNotice(ann)}`)
E.cars[ann] = nil -- (another vehicle took its place: the van gone)
E.clock += 0.3
Moving.step()
check("the van gone: what was in it is lost (condition 0), the run goes on", #ends == 2 and heard(ann, "The van is gone")
	and stateOf(ann, 1).state == "lost" and stateOf(ann, 1).condition == 0)
check("…CAR waits VanAgain s", string.find(E.Vehicles.spawn(ann, false, nil) or "", "comes back", 1, true) ~= nil
	and string.find(E.Vehicles.placeNear(ann, nil) or "", "comes back", 1, true) ~= nil and E.cars[ann] == nil)
do
	local calls = E.vehicleCalls or 0
	local since = #E.messages
	check("7.2 review: …a van parked at a spot (placeAt, spawnAt) waits too, said", E.Vehicles.placeAt(ann, nil, M.CFrame.new(0, 0, 0)) == nil
		and E.Vehicles.spawnAt(ann, "sprinter", M.CFrame.new(0, 0, 0), false) == nil and (E.vehicleCalls or 0) == calls and heard(ann, "comes back", since + 1),
		`{(E.vehicleCalls or 0) - calls} calls`)
end
E.now += T.VanAgain
E.Vehicles.placeNear(ann, nil)
E.clock += 0.3
Moving.step()
check("…then CAR brings it and the run takes it over (its prompts on it)", E.cars[ann] ~= nil and E.cars[ann] ~= truck and promptIn(E.cars[ann].model, "Load") ~= nil
	and heard(ann, "van is back") and E.last(ann, "Moving", "state").a.truck == true)
Moving.endRun(ann)
check("(ended: nothing home, called off)", lastEnd().phase == "cancelled", lastEnd().phase)
-- the clock: one minute left, then 0:00
local plansBefore = plans
E.startRun(ann, HOUSE)
check("7.0 review: the house's plan is made once a seed (nothing came home: the same seed, no new plan)", plans == plansBefore, `{plans} {plansBefore}`)
Moving.step()
local timeSaid = Moving.admin(ann, "time")
check("the admin's one minute left", string.find(timeSaid, "minute", 1, true) ~= nil)
E.now += 61
E.clock += 0.3
Moving.step()
check("0:00 with nothing in the truck: the run ends at once, nothing home (lost)", #ends == 4 and lastEnd().phase == "failed" and #lastEnd().pieces == 0, lastEnd().phase)
E.startRun(ann, HOUSE)
Moving.step()
loadOne(ann, 1)
Moving.admin(ann, "time")
E.now += 61
E.clock += 0.3
Moving.step()
check("0:00 with a load in the truck: the run ends late, the load home", #ends == 5 and lastEnd().phase == "late" and #lastEnd().pieces == 1, lastEnd().phase)
-- 7.0 review: the end's listeners fail (the analytics down): the cleanup runs anyway, the slot frees
do
	E.startRun(ann, HOUSE)
	Moving.step()
	loadOne(ann, 1)
	local track = E.PlayerData.track
	E.PlayerData.track = function()
		error("the analytics are down")
	end
	Moving.endRun(ann)
	E.PlayerData.track = track
	check("the end's listeners failed: the cleanup ran anyway (the interior gone, nobody on the move, the HUD told)", E.destroyed == E.built and ann:GetAttribute("MoveWith") == nil
		and E.last(ann, "Moving", "state").a == nil, `{E.destroyed} of {E.built}`)
	check("…and the next run starts", E.startRun(ann, HOUSE) == nil)
	Moving.endRun(ann)
end
-- 7.0 review: a door trip while the move ends: out at the house's door, never into the void; the fade lifts
do
	E.startRun(ann, HOUSE)
	Moving.step()
	E.place(ann, outside)
	E.onStream = function()
		E.request(ann, "giveup") -- (the run ends while the screen is dark)
	end
	trigger(promptIn(site, "Enter house"), ann)
	check("the run ended during the door's fade: out at the house's door, the fade lifted", (E.rootOf(ann).Position - outside).Magnitude < 6
		and E.last(ann, "Moving", "fade").a == "in" and lastEnd().phase == "cancelled", E.rootOf(ann).Position)
	E.startRun(ann, HOUSE)
	Moving.step()
	trigger(promptIn(site, "Enter house"), ann)
	check("…and the next trip goes in (nothing stuck)", (E.rootOf(ann).Position - E.interiors[#E.interiors].Position).Magnitude < 10)
	Moving.endRun(ann)
end
-- the host leaves: the run ends, what is in the truck goes home
do
	E.startRun(ann, HOUSE)
	Moving.step()
	loadOne(ann, 1)
	local leftAt = #E.messages
	E.leave(ann)
	over = lastEnd()
	check("the host left: the run ended, what was in the truck went home, the crew told", over ~= nil and over.phase == "done" and #over.pieces == 1
		and heard(bob, "The run ended: Ann (the host) left. What was in the truck went home.", leftAt), over and over.phase)
end
do
	local fay = E.player(66, "Fay", lobby + V3(-3, 0, -3))
	local gus = E.player(77, "Gus", lobby + V3(-4, 0, -3))
	E.crew[fay] = { gus }
	E.startRun(fay, HOUSE)
	Moving.step()
	E.leave(fay)
	check("the host left with nothing in the truck: called off for the crew", lastEnd().phase == "cancelled" and heard(gus, "Fay (the host) left"))
end
-- 8.1 walk-in doors (the owner: "no E at the house, neither in nor out"; Config.Moving.Doors): walk into the zone in
-- front of the door and through it after Dwell s facing it; brushing past or walking by is no way in; out the same way
-- by the doorway inside; after a trip no way back until you stepped out of the zone you came out in and Rearm s went by;
-- a piece in your hands and a pair piece's other end come along; only the move's crew on foot; the doormats.
do
	local D = T.Doors
	local THROUGH = math.max(D.Dwell, D.Open) + 0.01 -- (8.3: in the zone facing the door Dwell s, its leaf open Open s)
	local ivy = E.player(111, "Ivy", lobby + V3(-2, 0, -4))
	local jo = E.player(112, "Jo", lobby + V3(-3, 0, -5))
	local kim = E.player(113, "Kim", lobby)
	E.crew[ivy] = { jo }
	check("(the walk-in doors on: a dwell, a longer re-arm, the zone shallower than where you come out)", D.Walk == true and D.Dwell > 0 and D.Rearm > D.Dwell
		and D.Depth < 4 and D.Every <= T.Tick)
	E.startRun(ivy, HOUSE)
	Moving.step()
	local origin = E.interiors[#E.interiors]
	local up = V3(0, Config.Furniture.EntryUp, 0)
	local foot = V3(House.door.x, House.door.y, House.door.z) -- (the door's foot outside, the server's)
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
	local function fadesOf(player: any, since: number): number
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
	check("a stranger in the zone facing the door: stays out (only the move's crew)", not isIn(kim) and fadesOf(kim, since) == 0)
	E.place(kim, lobby)
	E.seated[jo] = E.cars[ivy]
	E.rootOf(jo).Parent:FindFirstChildOfClass("Humanoid").SeatPart = E.cars[ivy].chassis
	stand(jo, front, -facing)
	wait(0.1)
	wait(0.5)
	check("…nor a crew mate sitting (in a seat)", not isIn(jo) and fadesOf(jo, since) == 0)
	E.rootOf(jo).Parent:FindFirstChildOfClass("Humanoid").SeatPart = nil
	E.seated[jo] = nil
	E.place(jo, foot + up + facing * 12)

	-- walking past, brushing past: no way in
	stand(ivy, front, side)
	wait(0.1)
	wait(0.4)
	wait(0.4)
	check("walking past the door (in its zone, looking along the wall): no way in", not isIn(ivy) and fadesOf(ivy, since) == 0)
	stand(ivy, front, -facing)
	wait(0.1)
	wait(D.Dwell * 0.5)
	stand(ivy, front + facing * 4, -facing)
	wait(0.1)
	wait(THROUGH + 0.2)
	check("brushing past (in it facing the door for less than the dwell, then out of it): no way in", not isIn(ivy) and fadesOf(ivy, since) == 0)
	stand(ivy, front + side * (2 / 2 + D.Side + 1.5), -facing)
	wait(0.1)
	wait(THROUGH + 0.2)
	check("…nor beside the doorway (past its jambs)", not isIn(ivy))

	-- walk in
	stand(ivy, front, -facing)
	wait(0.1)
	check("in the zone facing the door: not before the dwell", not isIn(ivy))
	wait(THROUGH)
	local entry = origin * M.CFrame.new(0, 0, 1)
	check("walked in after the dwell: in the house at its entry, no E", isIn(ivy) and (E.rootOf(ivy).Position - entry.Position).Magnitude < 4, E.rootOf(ivy).Position)
	check("…with the fade out and in", fadesOf(ivy, since) == 2, fadesOf(ivy, since))
	check("…facing into the room, away from the door", E.rootOf(ivy).CFrame.LookVector:Dot(into) > 0.99)
	local state = E.last(ivy, "Moving", "state")
	check("…the state says inside (the HUD, the guide)", state ~= nil and state.a ~= nil and state.a.inside == true)

	-- no ping-pong: the zone she came out in stays shut until she has left it, Rearm s at least
	stand(ivy, exitAt + into * 0.5, -into) -- (turned straight back to the door, still in the zone)
	since = #E.messages
	for _ = 1, 6 do
		wait(0.5)
	end
	check("no ping-pong: turned back to the door in its zone, past Rearm s: still in (she never left it)", isIn(ivy) and fadesOf(ivy, since) == 0)
	stand(ivy, exitAt + into * 8, -into)
	wait(0.1)
	stand(ivy, exitAt + into * 1, -into)
	wait(0.1)
	check("…out of the zone and back in: not before the dwell", isIn(ivy))
	wait(THROUGH)
	local outside4 = foot + facing * 4
	check("walked out by the doorway inside: at the house's door, a few studs out", not isIn(ivy) and math.abs(V3(E.rootOf(ivy).Position.X - foot.X, 0, E.rootOf(ivy).Position.Z - foot.Z).Magnitude - 4) < 0.5,
		E.rootOf(ivy).Position)
	check("…facing away from the door, with the fade", E.rootOf(ivy).CFrame.LookVector:Dot(facing) > 0.99 and fadesOf(ivy, since) == 2)
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
	wait(THROUGH)
	check("…then in again after the dwell", isIn(ivy))

	-- carrying: out with a piece in the hands, in with it
	local tvModel = newItem(2)
	E.place(ivy, tvModel.PrimaryPart.Position + V3(1, 0, 0))
	trigger(promptIn(tvModel, "Pick up"), ivy)
	wait(1)
	check("(Ivy holds the TV)", ivy.Character:GetAttribute("MoveCarry") == 2)
	stand(ivy, exitAt + into * 2, -into)
	wait(1) -- (no teleport: a second for the way there)
	wait(THROUGH)
	check("carrying: out by the door with the TV in her hands", not isIn(ivy) and ivy.Character:GetAttribute("MoveCarry") == 2 and stateOf(ivy, 2).state == "carried")
	stand(ivy, foot + up + facing * 9, -facing)
	wait(D.Rearm)
	stand(ivy, front, -facing)
	wait(0.6)
	wait(THROUGH)
	check("…and in again with it", isIn(ivy) and ivy.Character:GetAttribute("MoveCarry") == 2)
	E.Net.get("PutDown").OnServerEvent:Fire(ivy)

	-- a pair piece: the back end does not lead; the front end walks out and the other end comes along
	stand(jo, front, -facing)
	wait(0.1)
	wait(THROUGH)
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
	wait(THROUGH)
	wait(0.4)
	check("the back end in the doorway first: it does not lead (said once), nobody goes", isIn(jo) and isIn(ivy) and said(jo, "front leads", since) == 1)
	stand(ivy, exitAt + into * 2, -into)
	stand(jo, exitAt + into * 6, -into)
	wait(0.6)
	wait(THROUGH)
	local apart = E.rootOf(jo).Position - E.rootOf(ivy).Position
	check("the front end walks out: both out with the sofa (8.3: Jo at its far end, straight in front of Ivy)", not isIn(ivy) and not isIn(jo)
		and ivy.Character:GetAttribute("MoveCarry") == 3 and jo.Character:GetAttribute("MoveCarry") == 3 and V3(apart.X, 0, apart.Z).Magnitude < 8
		and apart:Dot(E.rootOf(ivy).CFrame.LookVector) > 3, apart)
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
	wait(THROUGH + 0.1)
	check("8.1 review: the leader standing in the zone, her back to the door, is not taken through (only walking into it)",
		not isIn(ivy) and not isIn(jo) and fadesOf(ivy, since) == 0)
	E.rootOf(ivy).AssemblyLinearVelocity = -facing * (D.PairWalk + 2) -- (backing into it)
	wait(0.1)
	wait(THROUGH + 0.1)
	check("8.1 the leader of a pair piece backs through the door (her back to it): both in with the sofa", isIn(ivy) and isIn(jo)
		and ivy.Character:GetAttribute("MoveCarry") == 3 and jo.Character:GetAttribute("MoveCarry") == 3 and fadesOf(ivy, since) == 2)
	E.rootOf(ivy).AssemblyLinearVelocity = V3(0, 0, 0)
	E.Net.get("PutDown").OnServerEvent:Fire(ivy)
	-- …nobody else goes through backwards: Jo, hands free, her back to the doorway inside
	wait(D.Rearm)
	stand(jo, exitAt + into * 12, into)
	wait(0.2)
	since = #E.messages
	stand(jo, exitAt + into * 1, into)
	wait(0.1)
	wait(THROUGH + 0.2)
	check("…but hands free, the back to the door is no way through (facing it, as ever)", isIn(jo) and fadesOf(jo, since) == 0)
	stand(jo, exitAt + into * 1, -into)
	wait(0.1)
	wait(THROUGH + 0.1)
	check("…turned to it: out", not isIn(jo))
	E.place(ivy, foot + up + facing * 12)
	E.Net.get("PutDown").OnServerEvent:Fire(ivy)

	Moving.endRun(ivy)
	check("the move over: the doormat outside hidden again", mat ~= nil and mat.Transparency == 1 and mat:FindFirstChildOfClass("SurfaceGui").Enabled == false)
	E.leave(ivy)
	E.leave(jo)
	E.leave(kim)
end
-- 8.3 the doors swing and the trip is smooth (Config.Moving.Doors; shared/DoorSwing.luau's attributes): the house's
-- leaves found at the move's start and tagged for the clients, shut; walking past is no opening, walking up to the door
-- facing it opens its leaf (DoorOpen) before its zone; the trip waits until it has been open Open s; the fade out
-- carries FadeOut, the move comes FadeOut + Margin s after it, the fade in carries where you are (a step past the door,
-- facing into the house) and the black's hold (Dark, Wait); the door behind you opens too, and each shuts Shut s after
-- its zone emptied (Moving.doors' sweep); out the same way by the interior's leaf; a crew mate at a pair piece's far end
-- lands at that end in the same moment, lined up in front of the leader, facing them.
do
	local D = T.Doors
	local foot = V3(House.door.x, House.door.y, House.door.z)
	local up = V3(0, Config.Furniture.EntryUp, 0)
	local side = V3(-facing.Z, 0, facing.X)
	-- a leaf at the house's door (the map's: this test's, its -Z out of the door) and one in the interior at its way out
	-- (a model, as server/HouseInterior.luau's)
	local outLeaf = M.Instance.new("Part")
	outLeaf.Name = "TestFrontDoor"
	outLeaf.Size = V3(4, 7, 0.4)
	outLeaf.CFrame = M.CFrame.lookAt(foot + V3(0, 3.5, 0), foot + V3(0, 3.5, 0) + facing)
	outLeaf:SetAttribute("DoorLeaf", 1)
	outLeaf:SetAttribute("DoorSwing", 1)
	outLeaf.Parent = workspace
	local build = E.art.interior.build
	local inLeaf: any = nil
	E.art.interior.build = function(plan: any, at: any): (any, any)
		local model, pieces = build(plan, at)
		local leaf = M.Instance.new("Model")
		leaf.Name = "FrontDoorLeaf"
		local part = M.Instance.new("Part")
		part.Name = "DoorLeaf"
		part.Size = V3(3.5, 8.8, 0.24)
		part.CFrame = at * M.CFrame.new(1.75, 4.4, -0.3)
		part.Parent = leaf
		leaf.PrimaryPart = part
		leaf:SetAttribute("DoorLeaf", 1)
		leaf:SetAttribute("DoorSwing", -1)
		leaf.Parent = model
		inLeaf = leaf
		return model, pieces
	end
	local kit = E.player(121, "Kit", lobby + V3(-2, 0, -4))
	local lou = E.player(122, "Lou", lobby + V3(-3, 0, -5))
	E.crew[kit] = { lou }
	E.startRun(kit, HOUSE)
	Moving.step()
	E.art.interior.build = build
	local origin = E.interiors[#E.interiors]
	local into = V3(0, 0, 1) -- (the fake plan's +Z)
	local exitAt = origin * V3(0, 0, 0.5) + up
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
	local function open(leaf: any): boolean
		return leaf:GetAttribute("DoorOpen") == true
	end
	check("8.3 the house's leaves found at the move's start, tagged for the clients (DoorLeaf), shut", outLeaf:GetAttribute("Tag_DoorLeaf") == true
		and inLeaf ~= nil and inLeaf:GetAttribute("Tag_DoorLeaf") == true and not open(outLeaf) and not open(inLeaf))

	-- walking past in its approach: shut; walking up to it facing it, out of its zone still: open, nobody goes
	local since = #E.messages
	stand(kit, foot + up + facing * 6, side)
	wait(0.1)
	check("walking past the door in its approach (looking along the wall): its leaf stays shut", not open(outLeaf))
	stand(kit, foot + up + facing * 6, -facing)
	wait(0.1)
	local openedAt = E.clock
	check("walking up to it facing it (Approach studs: out of its zone still): the leaf swings open, nobody goes yet", open(outLeaf) and not isIn(kit)
		and D.Approach > 6 and D.Depth < 6)
	local delays: { number } = {}
	local runAtOnce = E.task.delay
	E.task.delay = function(seconds: any, callback: any, ...: any)
		table.insert(delays, seconds)
		return runAtOnce(seconds, callback, ...)
	end
	stand(kit, foot + up + facing * 2, -facing)
	E.rootOf(kit).AssemblyLinearVelocity = -facing * 10 -- (walking on into the doorway)
	wait(0.05)
	wait(D.Dwell + 0.01)
	check("…in its zone the dwell done, the leaf open less than Open s: not yet", not isIn(kit) and E.clock - openedAt < D.Open)
	wait(D.Open - (E.clock - openedAt) + 0.01)
	E.task.delay = runAtOnce
	local fadeOut, fadeIn = nil, nil
	for index = since + 1, #E.messages do
		local m = E.messages[index]
		if m.player == kit and m.kind == "fade" then
			if m.a == "out" then
				fadeOut = m
			else
				fadeIn = m
			end
		end
	end
	local entry = origin * M.CFrame.new(0, 0, 1)
	check("…the leaf open Open s: in, at the entry", isIn(kit) and (E.rootOf(kit).Position - entry.Position).Magnitude < 4, E.rootOf(kit).Position)
	check("the fade out says FadeOut s; the move comes FadeOut + Margin s after it was sent (the client's screen black)", fadeOut ~= nil and fadeOut.b == D.FadeOut
		and table.find(delays, D.FadeOut + D.Margin) ~= nil, table.concat(delays, ", "))
	local arrival = if fadeIn then fadeIn.c else nil
	check("the fade in says FadeIn s and where you are: the client holds the black until it sees you there (Wait), then Dark s", fadeIn ~= nil
		and fadeIn.b == D.FadeIn and type(arrival) == "table" and (arrival.at - E.rootOf(kit).Position).Magnitude < 1e-6 and arrival.dark == D.Dark
		and arrival.wait == D.Wait and arrival.near == D.Arrive)
	check("…and the way you face there: into the house, away from the door (the camera goes behind you)", arrival ~= nil and arrival.look:Dot(into) > 0.99
		and E.rootOf(kit).CFrame.LookVector:Dot(into) > 0.99)
	local stateFirst = false
	for index = since + 1, #E.messages do
		local m = E.messages[index]
		if m.player == kit and m.kind == "fade" and m.a == "in" then
			break
		end
		stateFirst = stateFirst or (m.player == kit and m.kind == "state" and type(m.a) == "table" and m.a.inside == true)
	end
	check("…the move's state (inside) reaches you before the fade in: the HUD, the sounds and the eyes adapt while it is black", stateFirst)
	local walking = E.rootOf(kit).AssemblyLinearVelocity
	check("…still walking: the walk's speed carried on the way you face there (no stop, no turn of the momentum)", walking ~= nil
		and math.abs(walking:Dot(into) - 10) < 1e-6 and math.abs(walking:Dot(V3(1, 0, 0))) < 1e-6)
	E.rootOf(kit).AssemblyLinearVelocity = V3(0, 0, 0)
	check("the door you came in by opens behind you (the interior's leaf), the yard's stays open a moment", open(inLeaf) and open(outLeaf))
	-- their zones empty: both shut Shut s after the last want (the sweep)
	stand(kit, exitAt + into * 12, into)
	E.clock += D.Shut + 0.05
	Moving.doors()
	check("…both shut Shut s after their zones emptied (Moving.doors' sweep)", not open(outLeaf) and not open(inLeaf))

	-- out by the interior's leaf with a pair piece and Lou at its far end: both out in the same moment, lined up
	stand(lou, foot + up + facing * 2, -facing)
	wait(0.1)
	wait(math.max(D.Dwell, D.Open) + 0.05)
	check("(Lou walks in too)", isIn(lou))
	local sofaModel = newItem(3)
	local sofaAt = sofaModel.PrimaryPart.Position
	E.clock += D.Rearm
	E.place(kit, sofaAt + V3(0, 0, -3))
	E.place(lou, sofaAt + V3(0, 0, 3))
	trigger(promptIn(sofaModel, "Lift"), kit)
	trigger(promptIn(sofaModel, "Help lift"), lou)
	wait(1)
	check("(Kit leads the sofa, Lou at its far end)", kit.Character:GetAttribute("MoveCarry") == 3 and lou.Character:GetAttribute("MoveCarry") == 3)
	since = #E.messages
	stand(kit, exitAt + into * 6, -into)
	stand(lou, exitAt + into * 12, -into)
	wait(0.1)
	check("the interior's leaf opens as Kit walks up to it", open(inLeaf) and isIn(kit))
	stand(kit, exitAt + into * 1, -into)
	wait(0.05)
	wait(math.max(D.Dwell, D.Open) + 0.05)
	local kitRoot, louRoot = E.rootOf(kit), E.rootOf(lou)
	local ahead = (louRoot.Position - kitRoot.Position)
	local look = kitRoot.CFrame.LookVector
	local fades2 = 0
	for index = since + 1, #E.messages do
		local m = E.messages[index]
		fades2 += if m.kind == "fade" and (m.player == kit or m.player == lou) then 1 else 0
	end
	check("out together: Kit a step past the door facing away from it, Lou at the sofa's far end in front of him, facing him", not isIn(kit) and not isIn(lou)
		and math.abs(V3(kitRoot.Position.X - foot.X, 0, kitRoot.Position.Z - foot.Z).Magnitude - 4) < 0.5 and look:Dot(facing) > 0.99
		and ahead:Dot(look) > 3 and math.abs(ahead:Dot(V3(-look.Z, 0, look.X))) < 0.5 and louRoot.CFrame.LookVector:Dot(look) < -0.99, ahead)
	check("…in the same moment: one fade out and one fade in each", fades2 == 4, fades2)
	E.Net.get("PutDown").OnServerEvent:Fire(kit)
	Moving.endRun(kit)
	outLeaf:Destroy()
	E.leave(kit)
	E.leave(lou)
end
check("every interior went (slots free again)", E.destroyed == E.built, `{E.destroyed} of {E.built}`)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
