-- 8.8 no roles (the owner: "I don't want roles in the game. Everyone is simply the same."; shared/MoveRoles.luau
-- MoveRoles.on: Config.MoveRoles.On, the city's only): the real server/Moving.luau and server/MoveLobby.luau (MoveHelper,
-- MoveSites with them) on tests/runtime/MovingRuntime.luau's fakes in the sandbox (Config.Sandbox.On), a
-- crew of two: Ann, the move's owner, and Bob, her crew mate (then Cid joins mid-move).
--   * 9.7 runs: no contract kiosk on the plots and no planning (the lobby's portals start a run: server/Runs.luau);
--     a START asked opens nothing; the run (Moving.startRun) takes Ann's party as it is, nobody asked for a role.
--   * On the move: no MoveRole on anybody, nobody told one (a newcomer neither); the state's team says only whether the
--     van was called; a role switch or a barricade asked does nothing.
--   * The van's Load, Take out and the walk-in bay's Load hold no time (no MoveQuick): no wait for anybody; Bob, not
--     the owner, loads a piece at the back.
--   * Bob calls the van to the house's door (the first call, no Driver needed), Ann's call after his is refused: once a
--     move.
--   * Nobody carries a two-person piece alone: Bob's Lift on the sofa (10.1: the run's helper, Ann's Danny, is with
--     the party, but asked not to answer a Lift here: Config.MoveHelper.WaitForHelper off for it) drags it at
--     Moving.Speed.Drag (the Mover's Alone walk no more); Ann's Help lift makes it the pair's walk.
--   * No Guard's damage on a zombie by the house.
--   * The end: nobody holds a role.
-- The city's roles with the switch on: tests/moving_runtime_test.luau (and the farm's, the grip's, the art's); the rules
-- with the switch either way: tests/moveroles_test.luau.
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local MoveRoles = require("./MoveRoles")
local SandboxMap = require("./SandboxMap")

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
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
local House = SandboxMap.House
local plot1, plot2 = SandboxMap.Plots[1], SandboxMap.Plots[2]
E.Zombies.findSpot = function(center: any): any
	return center + V3(60, 0, 0)
end

local function promptIn(model: any, action: string?): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and not d.destroyed and (action == nil or string.find(tostring(d.ActionText), action, 1, true) == 1) then
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
local function heard(player: any, text: string, since: number?): boolean
	for index = math.max(since or 1, 1), #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then
			return true
		end
	end
	return false
end
local function newItem(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
local function stateOf(player: any, spot: number): any
	local view = E.last(player, "Moving", "state")
	for _, item in (view and view.a and view.a.items) or {} do
		if item.spot == spot then
			return item
		end
	end
	return nil
end
local function step(seconds: number?)
	E.clock += seconds or 0.3
	Moving.step()
end
local function park(truck: any, spot: any)
	truck.chassis.CFrame = CF(spot.x, 2, spot.z) * M.CFrame.Angles(0, math.rad(spot.yaw), 0)
end
local function flatDistance(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
-- No role anywhere in a lobby's view: not yours, not a member's, no doubles.
local function noRoleIn(view: any): boolean
	if type(view) ~= "table" or view.role ~= nil or view.doubles then
		return false
	end
	for _, member in view.members or {} do
		if member.role ~= nil then
			return false
		end
	end
	return true
end
-- The state's team: only whether the van was called (no role, no crew's roles, no switch, no barricades).
local function teamOf(player: any): any
	local view = E.last(player, "Moving", "state")
	return view and view.a and view.a.team
end
local function plainTeam(team: any): boolean
	if type(team) ~= "table" or type(team.called) ~= "boolean" then
		return false
	end
	for key in team do
		if key ~= "called" then
			return false
		end
	end
	return true
end

local ann = E.player(11, "Ann", V3(plot1.spawn.x, 3, plot1.spawn.z))
local bob = E.player(22, "Bob", V3(plot2.spawn.x, 3, plot2.spawn.z))
local cid = E.player(33, "Cid", V3(0, 3, 0))
E.plots[ann] = plot1
E.plots[bob] = plot2
E.carId = "sprinter"
E.crew[ann] = { bob }
-- server/SandboxBoot.luau's parkVan, as tests/sandboxmove_runtime_test.luau sets it (the player's van at the spot)
Moving.parkVan = function(player: any, spot: any, _seat: boolean, carId: string?): (string?, any)
	local old = E.cars[player]
	if old then
		old.model:Destroy()
	end
	local car = E.makeCar(player, carId or Config.Sandbox.Van, V3(spot.x, 2, spot.z))
	E.cars[player] = car
	return nil, car
end
-- the map's front door (server/SandboxWorld.luau's: the attribute SandboxDoor, a door leaf)
local frontDoor = M.Instance.new("Part")
frontDoor.Name = "FrontDoor"
frontDoor.Size = V3(4, 7, 0.4)
frontDoor.CFrame = CF(House.door.x, 3.5, House.door.z + 0.5)
frontDoor:SetAttribute("SandboxDoor", true)
frontDoor:SetAttribute("DoorLeaf", 1)
frontDoor:SetAttribute("DoorSwing", 1)
frontDoor:SetAttribute("DoorDark", true)
frontDoor.Parent = workspace

Moving.useArt(E.art)
Moving.start()

check("the switch: the city's roles on (Config.MoveRoles.On), none in the sandbox", R.On == true and Config.Sandbox.On == true and not MoveRoles.on())

-- The run (9.7: no kiosk, no planning: the lobby's portals start it) -----------------------------------------------------

local moves = workspace:FindFirstChild("Moves")
check("9.7: no Moving contracts kiosk on the plots (the lobby's portals start the runs)", moves ~= nil and moves:FindFirstChild("MovingBoard1") == nil
	and promptIn(moves, "Moving contracts") == nil)
Moving.parkVan(ann, plot1.vanSpot) -- (Ann's Sprinter at her plot's old van spot)
local truck = E.cars[ann]
park(truck, plot1.vanSpot)
E.request(ann, "start", House.id)
check("…a START asked opens no planning and starts nothing", E.last(ann, "MoveLobby", "lobby") == nil and E.last(bob, "MoveLobby", "lobby") == nil and E.built == 0)
lobbyRequest(bob, "role", "driver")
check("…a role asked: nothing", bob:GetAttribute("MoveRole") == nil and E.built == 0)
local launchedAt = #E.messages
check("the run (Moving.startRun: Ann the host, Bob in her party): the crew hears it", Moving.startRun(ann, House.id, "normal") == nil and E.built == 1
	and heard(bob, "NORMAL", launchedAt), E.lastNotice(ann))

-- On the move: nobody has a role ------------------------------------------------------------------------------------------

step()
check("Bob on it (MoveWith)", bob:GetAttribute("MoveWith") == 11 and ann:GetAttribute("MoveWith") == 11)
check("no MoveRole on anybody, nobody told one", ann:GetAttribute("MoveRole") == nil and bob:GetAttribute("MoveRole") == nil
	and not heard(ann, "You are the", launchedAt) and not heard(bob, "You are the", launchedAt))
check("the state's team says only whether the van was called (not yet)", plainTeam(teamOf(ann)) and plainTeam(teamOf(bob)) and teamOf(ann).called == false)
E.request(bob, "role", "driver")
E.request(bob, "barricade")
E.request(ann, "barricade")
step()
check("a role switch or a barricade asked: nothing", bob:GetAttribute("MoveRole") == nil and moves:FindFirstChild("MoveBarricade") == nil and plainTeam(teamOf(bob)))
E.crew[ann] = { bob, cid }
local joinedAt = #E.messages
step()
check("Cid joins mid-move: on it, no role, not told one", cid:GetAttribute("MoveWith") == 11 and cid:GetAttribute("MoveRole") == nil and not heard(cid, "You are the", joinedAt)
	and plainTeam(teamOf(cid)))
E.crew[ann] = { bob }
step()

-- The van: no wait at its back for anybody; the call, whoever is first --------------------------------------------------

local load = promptIn(truck.model, "Load")
local takeOut = promptIn(truck.model, "Take out")
local bay = truck.chassis:FindFirstChild("MoveLoadBay")
local bayLoad = bay and bay:FindFirstChildOfClass("ProximityPrompt")
check("the van's Load, Take out and the bay's Load hold no time, for anybody (no MoveQuick)", load ~= nil and takeOut ~= nil and bayLoad ~= nil
	and load.HoldDuration == 0 and takeOut.HoldDuration == 0 and bayLoad.HoldDuration == 0 and load:GetAttribute("MoveQuick") == nil
	and takeOut:GetAttribute("MoveQuick") == nil and bayLoad:GetAttribute("MoveQuick") == nil)
local facing = V3(0, 0, -1) -- (House.door yaw 0: out to the road, north)
local outside = V3(House.door.x, 3, House.door.z) + facing * 3
E.place(bob, outside)
local calledAt = #E.messages
E.request(bob, "call")
check("Bob (no Driver) calls the van to the door: at the house's curb, its back to the door", flatDistance(truck.chassis.Position, V3(House.curb.x, 0, House.curb.z)) < 1
	and truck.chassis.CFrame.LookVector.Z < -0.99 and heard(ann, "Bob called the van", calledAt) and E.last(bob, "Moving", "fade") ~= nil, truck.chassis.Position)
step()
check("…the state says it was called", teamOf(ann).called == true and teamOf(bob).called == true and plainTeam(teamOf(ann)))
park(truck, plot1.vanSpot)
E.request(ann, "call")
check("…once a move: Ann's call after his is refused, the van stays", string.find(E.lastNotice(ann), "once", 1, true) ~= nil
	and flatDistance(truck.chassis.Position, V3(plot1.vanSpot.x, 0, plot1.vanSpot.z)) < 1, E.lastNotice(ann))
park(truck, { x = House.curb.x, z = House.curb.z, yaw = 0 })

-- Bob loads at the back (not the owner: the crew's prompt, no wait) -------------------------------------------------------

local enter = promptIn(frontDoor, "Enter house")
trigger(enter, bob)
local origin = E.interiors[1]
local lamp = newItem(1)
E.place(bob, lamp.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(lamp, "Pick up"), bob)
step()
E.place(bob, origin.Position + V3(0, 3, 1))
trigger(promptIn(workspace, "Leave house"), bob)
truck.model:SetAttribute("BackOpen", true)
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
E.place(bob, cargoDoor.WorldPosition + V3(0, 0, 2))
step()
check("Bob at the open back with the lamp: Load for him, no hold", load.Enabled and load.HoldDuration == 0 and string.find(load.ActionText, "Lamp", 1, true) ~= nil)
trigger(load, bob)
step()
check("…loaded", bob.Character:GetAttribute("MoveCarry") == nil and stateOf(ann, 1).state == "truck", E.lastNotice(bob))

-- A two-person piece: nobody alone ------------------------------------------------------------------------------------------

E.place(bob, outside)
trigger(enter, bob)
local sofa = newItem(3)
local sofaRoot = sofa.PrimaryPart
local liftAt = #E.messages
E.place(bob, sofaRoot.Position + V3(0, 0, -3))
Config.MoveHelper.WaitForHelper = false -- (10.1: Danny comes with every run's party; here nobody calls him)
trigger(promptIn(sofa, "Lift"), bob)
Config.MoveHelper.WaitForHelper = true
local bobBody = bob.Character
local walk = Config.Movement.Walk
check("Bob's Lift on the sofa alone: dragged at Drag (no Mover's Alone walk, held up)", bobBody:GetAttribute("MoveCarry") == 3
	and math.abs((bobBody:GetAttribute("CarrySpeed") or 0) - walk * T.Speed.Drag) < 1e-6 and math.abs(walk * R.Mover.Alone - walk * T.Speed.Drag) > 0.5
	and heard(bob, "needs two", liftAt), bobBody:GetAttribute("CarrySpeed"))
E.place(ann, outside)
trigger(enter, ann)
E.place(ann, sofaRoot.Position + V3(0, 0, 3))
trigger(promptIn(sofa, "Help lift"), ann)
check("…a crew mate takes its other end: the pair's walk for both", math.abs((bobBody:GetAttribute("CarrySpeed") or 0) - walk * T.Speed.Pair) < 1e-6
	and ann.Character:GetAttribute("MoveCarry") == 3 and bobBody:GetAttribute("CarryPair") == true)
E.Net.get("PutDown").OnServerEvent:Fire(ann)
E.Net.get("PutDown").OnServerEvent:Fire(bob)
step()

-- The hits: nobody's role --------------------------------------------------------------------------------------------------

local z = E.Zombies.spawn("walker", V3(House.door.x + 6, 3, House.door.z - 6), ann)
E.Zombies.damage(z, 10, ann, {})
local byAnn = E.zombieHits[#E.zombieHits].amount
E.Zombies.damage(z, 10, bob, { cause = "melee" })
check("a zombie by the house takes a hit as it was (no Guard's damage)", byAnn == 10 and E.zombieHits[#E.zombieHits].amount == 10)

-- The end ------------------------------------------------------------------------------------------------------------------

check("the run's end (the admin's END RUN: Moving.endRun)", Moving.endRun(ann, "Ended by the admin") == true and Moving.busy(ann) == nil)
check("…nobody holds a role", ann:GetAttribute("MoveRole") == nil and bob:GetAttribute("MoveRole") == nil and moves:FindFirstChild("MoveBarricade") == nil)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
