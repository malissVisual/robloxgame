-- 8.0 SANDBOX, moves (design/sandbox/KONTRAKT.md): the real server/Moving.luau (MoveLobby, MoveGreeters, MoveHelper,
-- MoveSites with it) on tests/runtime/MovingRuntime.luau's fakes with Config.Sandbox.On (tests/run_tests.py builds
-- them; the fake art's plan records its seeds and gives each piece a colour variant).
--   * Moving.start in the sandbox: a Moving contracts kiosk on every plot (SandboxMap plot.board), no depot board, no
--     Wall, no dressing, no soldier, no Marge or Walt: one contract, "The Old Chalet" (SandboxMap.House).
--   * The card (any plot's board, not from afar): the house, its pieces' worth, 20 minutes, no horde by default, no
--     story, the note; its seed a new one each move. START → the solo lobby → LAUNCH at a board: the owner's own van
--     (the Sprinter, its walk-in bay Config.Moving.Beds.sprinter), the house built with the card's seed.
--   * "Enter house" on the map's front door (the part with the attribute SandboxDoor), out at the door; the Driver's
--     call parks the van at House.curb (its nose to the road, its back to the door).
--   * Load at the back doors, and from inside the walk-in bay (its own Load, the back shut), every piece inside the
--     bay; Danny on a solo move.
--   * The drop-off: not another player's plot; the van's back in the owner's plot's unload circle: a trip, every piece
--     in the van into the owner's stock (Collection.add with its item, variant, condition, name), no pay; a second
--     trip; FINISH: the result card says what came home (pieces, value, trips), no money, no XP.
--   * The edges: a piece still in the van at FINISH is lost (never collected), a Collection.add that refuses is said,
--     no plot: no START, no van out: the van comes to the plot's vanSpot, the admin's start / time / horde / end /
--     refill, a new seed every move, the horde and the roamers switched on (Config.Moving.Sandbox).
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local Greeters = require("./MoveGreetersServer")
local MoveHelper = require("./MoveHelperServer")
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
local S = T.Sandbox
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
	for index = since or 1, #E.messages do
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
-- A van parked at a spot ({ x, z, yaw }: SandboxMap's, its nose that way; y over the ground).
local function park(truck: any, spot: any)
	truck.chassis.CFrame = CF(spot.x, 2, spot.z) * M.CFrame.Angles(0, math.rad(spot.yaw), 0)
end
local function flatDistance(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- the fake art's plan: its seeds kept, every piece a colour variant (its spot + 2)
local seeds: { number } = {}
local planOf = E.art.layout.plan
E.art.layout.plan = function(seed: number, kind: string): any
	table.insert(seeds, seed)
	local plan = planOf(seed, kind)
	local spots = {}
	for _, spot in plan.spots do
		local copy = table.clone(spot)
		copy.variant = spot.id + 2
		table.insert(spots, copy)
	end
	plan.spots = spots
	return plan
end
local built: { number } = {} -- the seeds of the interiors built
local buildOf = E.art.interior.build
E.art.interior.build = function(plan: any, origin: any): (any, any)
	table.insert(built, plan.seed)
	return buildOf(plan, origin)
end

local ann = E.player(11, "Ann", V3(plot1.spawn.x, 3, plot1.spawn.z))
local bob = E.player(22, "Bob", V3(plot2.spawn.x, 3, plot2.spawn.z))
local cid = E.player(33, "Cid", V3(0, 3, 0))
E.plots[ann] = plot1
E.plots[bob] = plot2 -- (Cid has none: a fifth player)
E.carId = "sprinter"

-- the map's front door (server/SandboxWorld.luau's FrontDoor: the attribute SandboxDoor), built before the move
local frontDoor = M.Instance.new("Part")
frontDoor.Name = "FrontDoor"
frontDoor.Size = V3(4, 7, 0.4)
frontDoor.CFrame = CF(House.door.x, 3.5, House.door.z + 0.5)
frontDoor:SetAttribute("SandboxDoor", true)
frontDoor.Parent = workspace

Moving.useArt(E.art)
Moving.start()
Greeters.step()

-- The world ----------------------------------------------------------------------------------------------------------------

local moves = workspace:FindFirstChild("Moves")
check("the sandbox: a kiosk on every plot, no depot board, no Wall, no dressing", moves ~= nil and moves:FindFirstChild("MovingBoard1") ~= nil
	and moves:FindFirstChild("MovingBoard4") ~= nil and moves:FindFirstChild("MovingBoard") == nil and moves:FindFirstChild("MovingDropOff") == nil
	and moves:FindFirstChild("MoveDressing") == nil)
check("one contract: The Old Chalet (no Marge, no Walt)", moves:FindFirstChild("Move_sandbox_house") ~= nil and moves:FindFirstChild("Move_marge") == nil
	and moves:FindFirstChild("Move_walt") == nil)
check("no soldier at a Wall", Greeters.soldier() == nil)
local kiosk1 = moves:FindFirstChild("MovingBoard1")
local cork1 = kiosk1:FindFirstChild("Board")
check("plot 1's kiosk: its corkboard by the plot's board spot (Plot 1), streamed in for good", cork1 ~= nil and cork1:GetAttribute("Plot") == 1
	and flatDistance(cork1.Position, V3(plot1.board.x, 0, plot1.board.z)) < 1.2 and kiosk1.ModelStreamingMode == "Persistent", cork1 and cork1.Position)

-- The card ---------------------------------------------------------------------------------------------------------------------

local board1 = promptIn(kiosk1, "Moving contracts")
local board2 = promptIn(moves:FindFirstChild("MovingBoard2"), "Moving contracts")
check("every kiosk has its Moving contracts prompt", board1 ~= nil and board2 ~= nil)
local before = #E.messages
trigger(board1, ann)
check("not from across the plot", #E.messages == before)
E.place(ann, cork1.Position + V3(0, 0, 4))
trigger(board1, ann)
local card = E.last(ann, "Moving", "contract")
local worth = 0
for _, item in E.items do
	worth += item.value
end
check("the board's card: The Old Chalet, its pieces' worth, 20 minutes", card ~= nil and card.a.id == House.id and card.a.name == House.name and card.a.items == 6
	and card.a.estimate == worth and card.a.time == 20 * 60 and card.a.busy == nil and card.a.address == S.Address, card and card.a.busy)
check("…no horde by default (no guns in the sandbox), no roamers", S.Horde == false and S.Roam == 0 and card.a.hordeAt == 0)
check("…no story, the note (no pay per piece), one contract", card.a.story == false and type(card.a.note) == "string" and #card.a.contracts == 1
	and card.a.contracts[1].id == House.id and E.last(ann, "Tutorial", "message") == nil)
check("…its house planned with a seed (a kind house)", #seeds == 1 and seeds[1] > 0)
trigger(board1, ann)
check("the same card again: the same house (no new plan)", #seeds == 1)
E.place(ann, moves:FindFirstChild("MovingBoard2"):FindFirstChild("Board").Position + V3(0, 0, 4))
trigger(board2, ann)
check("any plot's board opens it (Bob's too), the same house", E.last(ann, "Moving", "contract").a.id == House.id and #seeds == 1)
E.place(cid, cork1.Position + V3(1, 0, 4))
trigger(board1, cid)
check("no plot (a fifth player): the card says why", string.find(tostring(E.last(cid, "Moving", "contract").a.busy), "warehouse", 1, true) ~= nil,
	E.last(cid, "Moving", "contract").a.busy)
E.request(cid, "start", House.id)
check("…and START is refused", E.last(cid, "MoveLobby", "lobby") == nil and string.find(E.lastNotice(cid), "warehouse", 1, true) ~= nil, E.lastNotice(cid))

-- START, LAUNCH ---------------------------------------------------------------------------------------------------------------

E.truckAt = V3(plot1.vanSpot.x, 2, plot1.vanSpot.z)
E.Vehicles.placeNear(ann, "sprinter") -- (PLAY: the player's Sprinter at their plot)
local truck = E.cars[ann]
park(truck, plot1.vanSpot)
E.place(ann, cork1.Position + V3(0, 0, 4))
trigger(board1, ann)
E.request(ann, "start", House.id)
local lobby = E.last(ann, "MoveLobby", "lobby")
check("START opens the solo lobby on the card (the Sprinter's bay)", lobby ~= nil and lobby.a ~= nil and lobby.a.canLaunch == true and lobby.a.card.name == House.name
	and lobby.a.card.bed[1] == T.Beds.sprinter.Width and lobby.a.card.bed[2] == T.Beds.sprinter.Length)
E.place(ann, V3(House.door.x, 3, House.door.z))
lobbyRequest(ann, "launch")
check("LAUNCH away from every board: refused", E.built == 0 and string.find(E.lastNotice(ann), "board", 1, true) ~= nil, E.lastNotice(ann))
E.place(ann, cork1.Position + V3(0, 0, 4))
lobbyRequest(ann, "launch")
check("LAUNCH at the board: the move, with the owner's own Sprinter", E.built == 1 and E.cars[ann] == truck and heard(ann, "Move started") and heard(ann, "warehouse"))
local firstSeed = seeds[1] -- (Ann's card's: Cid's card planned the second)
check("…the house built with the card's seed (planned once)", #built == 1 and built[1] == firstSeed and #seeds == 2 and seeds[2] ~= firstSeed, `{built[1]} {firstSeed} {#seeds}`)
step()
local view = E.last(ann, "Moving", "state")
check("the state: the drop-off is the owner's plot's unload circle, in the HUD's words; no horde", view.a.drop == "your warehouse" and view.a.dropOff.x == plot1.unload.x
	and view.a.dropOff.z == plot1.unload.z and view.a.hordeAt == nil and view.a.endsAt == E.now + 20 * 60 and view.a.mine == true)
check("the GPS's house: the van's curb", view.a.house.x == House.curb.x and view.a.house.z == House.curb.z)
local porch = false
for _, child in workspace:GetChildren() do
	if child:GetAttribute("MoveGreeter") == "porch" then
		porch = true
	end
end
check("nobody on the porch, no Marge's text (no story)", not porch and E.last(ann, "Tutorial", "message") == nil)
local danny = MoveHelper.find(ann)
check("Danny joins a crew of one", danny ~= nil and danny.body ~= nil)
check("the van's prompts say Sprinter (or the car's name), and a Load for the walk-in bay", promptIn(truck.model, "Load") ~= nil
	and truck.chassis:FindFirstChild("MoveLoadBay") ~= nil and truck.chassis:FindFirstChild("MoveTakeOut") ~= nil)

-- The house: the front door, the curb -------------------------------------------------------------------------------------------

local enter = promptIn(frontDoor, "Enter house")
check("Enter house on the map's front door (SandboxDoor), the move's own", enter ~= nil and enter:GetAttribute("MoveOwner") == 11)
local facing = V3(0, 0, -1) -- (House.door yaw 0: out to the road, north)
local outside = V3(House.door.x, 3, House.door.z) + facing * 3
E.place(ann, outside)
trigger(enter, ann)
local origin = E.interiors[1]
check("…into the interior", (E.rootOf(ann).Position - origin.Position).Magnitude < 6, E.rootOf(ann).Position)
E.request(ann, "call")
check("Call truck to door: the van at the house's curb, its nose to the road, its back to the door", flatDistance(truck.chassis.Position, V3(House.curb.x, 0, House.curb.z)) < 1
	and truck.chassis.CFrame.LookVector.Z < -0.99, truck.chassis.Position)
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
check("…its back doors toward the house", cargoDoor.WorldPosition.Z > truck.chassis.Position.Z)

-- Carry and load at the back doors ---------------------------------------------------------------------------------------------

local lamp = newItem(1)
E.place(ann, lamp.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(lamp, "Pick up"), ann)
step()
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(promptIn(workspace, "Leave house"), ann)
check("Leave house: out at the house's door with the lamp", flatDistance(E.rootOf(ann).Position, V3(House.door.x, 0, House.door.z)) < 4
	and ann.Character:GetAttribute("MoveCarry") == 1, E.rootOf(ann).Position)
truck.model:SetAttribute("BackOpen", true)
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
step()
local load = promptIn(truck.model, "Load")
local bayLoad = truck.chassis:FindFirstChild("MoveLoadBay"):FindFirstChildOfClass("ProximityPrompt")
check("at the open back with the lamp: the doors' Load (the bay's waits)", load.Enabled and not bayLoad.Enabled and string.find(load.ActionText, "Lamp", 1, true) ~= nil
	and string.find(load.ObjectText, "% full", 1, true) ~= nil, load.ObjectText)
trigger(load, ann)
step()
check("loaded at the back doors", ann.Character:GetAttribute("MoveCarry") == nil and stateOf(ann, 1).state == "truck", E.lastNotice(ann))
local BED = T.Beds.sprinter
local cz = cargoDoor.Position.Z - BED.Back - BED.Length / 2 -- (the bay's middle: Back in front of the doors)
local function inBay(model: any): boolean
	local p = truck.chassis.CFrame:PointToObjectSpace(model.PrimaryPart.Position)
	return math.abs(p.X) <= BED.Width / 2 and math.abs(p.Z - cz) <= BED.Length / 2 and p.Y > 0.6 and p.Y < 0.6 + BED.Height
end
check("…welded inside the Sprinter's bay", inBay(lamp) and lamp.PrimaryPart:FindFirstChildOfClass("WeldConstraint") ~= nil)

-- Load from inside the walk-in bay ----------------------------------------------------------------------------------------------

E.place(ann, outside)
trigger(enter, ann)
local tv = newItem(2)
E.place(ann, tv.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(tv, "Pick up"), ann)
step()
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(promptIn(workspace, "Leave house"), ann)
truck.model:SetAttribute("BackOpen", false) -- (shut: in by the side door)
local inside = truck.chassis.CFrame * V3(0, 0.6 + 3, cz - BED.Length / 2 + 2) -- (up at the bay's front end)
E.place(ann, inside)
step()
local backPrompt = cargoDoor:FindFirstChild("BackPrompt")
check("inside the bay with the TV, the back shut: the bay's own Load (the doors' not)", bayLoad.Enabled and not load.Enabled and string.find(bayLoad.ActionText, "TV", 1, true) ~= nil,
	`{bayLoad.Enabled} {load.Enabled} {bayLoad.ActionText}`)
check("…the back's own E free to open it, Take out waits", backPrompt.Enabled and not promptIn(truck.model, "Take out").Enabled)
check("…the bay's Load reaches the whole bay", bayLoad.MaxActivationDistance >= BED.Length / 2 + 1)
trigger(bayLoad, ann)
step()
check("Load from inside the bay: the TV in, hands free", ann.Character:GetAttribute("MoveCarry") == nil and stateOf(ann, 2).state == "truck" and inBay(tv), E.lastNotice(ann))
E.place(ann, inside + V3(0, 0, 3))
step()
check("…a carrier no more: the bay's Load off", not bayLoad.Enabled)
-- outside the bay and away from the doors: no Load from anywhere
E.place(ann, outside)
trigger(enter, ann)
local sofa = newItem(3)
E.place(ann, sofa.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(sofa, "Lift"), ann)
step()
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(promptIn(workspace, "Leave house"), ann)
E.place(ann, truck.chassis.CFrame * V3(BED.Width / 2 + 3, 3, cz)) -- (beside the van, by its side wall)
step()
trigger(bayLoad, ann)
check("beside the van (outside the bay), the back shut: no Load", ann.Character:GetAttribute("MoveCarry") == 3 and stateOf(ann, 3).state == "carried")
E.Net.get("PutDown").OnServerEvent:Fire(ann)

-- The drop-off: the owner's plot -------------------------------------------------------------------------------------------------

park(truck, plot2.vanSpot)
step()
check("the van at another player's plot: no trip", #E.collected == 0 and E.last(ann, "Moving", "state").a.trips == 0)
park(truck, { x = 0, z = 200, yaw = 180 })
step()
check("…nor on Main Street", #E.collected == 0)
park(truck, plot1.vanSpot)
check("(the van's back inside the owner's unload circle)", flatDistance(cargoDoor.WorldPosition, V3(plot1.unload.x, 0, plot1.unload.z)) <= plot1.unload.r)
local tripAt = #E.messages
step()
check("home: a trip, the move goes on", E.last(ann, "Moving", "result") == nil and E.last(ann, "Moving", "state").a.trips == 1 and heard(ann, "Trip 1 home", tripAt))
check("…every piece in the van into the owner's stock (Collection.add)", #E.collected == 2 and E.collected[1].player == ann and E.collected[2].player == ann)
local lampIn, tvIn = E.collected[1].entry, E.collected[2].entry
check("…with its item, variant, condition and name", lampIn.item == "lamp" and lampIn.name == "Lamp" and lampIn.variant == 3 and lampIn.condition == stateOf(ann, 1).condition
	and tvIn.item == "tv" and tvIn.name == "TV" and tvIn.variant == 4 and type(tvIn.condition) == "number", `{lampIn.item} {lampIn.variant} {lampIn.condition}`)
check("…the pieces leave the van (their models go), the state says delivered", lamp.destroyed == true and tv.destroyed == true and stateOf(ann, 1).state == "delivered"
	and stateOf(ann, 2).state == "delivered")
check("…no pay per piece", #E.money == 0)
step(20)
check("the empty van at home: no second trip, no nag", E.last(ann, "Moving", "state").a.trips == 1 and #E.collected == 2 and not heard(ann, "The van is empty", tripAt))

-- A second trip ----------------------------------------------------------------------------------------------------------------

E.request(ann, "call") -- (once a move: drive it yourself)
check("the call is once a move", string.find(E.lastNotice(ann), "once", 1, true) ~= nil, E.lastNotice(ann))
park(truck, { x = House.curb.x, z = House.curb.z, yaw = 0 })
E.place(ann, outside)
trigger(enter, ann)
local box = newItem(5)
E.place(ann, box.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(box, "Pick up"), ann)
step()
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(promptIn(workspace, "Leave house"), ann)
truck.model:SetAttribute("BackOpen", true)
E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
step()
trigger(load, ann)
step()
check("the box of memories (★) loaded", stateOf(ann, 5).state == "truck")
park(truck, plot1.vanSpot)
step()
check("trip 2: home, into the stock", E.last(ann, "Moving", "state").a.trips == 2 and #E.collected == 3 and E.collected[3].entry.item == "box" and heard(ann, "Trip 2 home"))

-- FINISH -----------------------------------------------------------------------------------------------------------------------

local value = E.items.lamp.value * stateOf(ann, 1).condition + E.items.tv.value * stateOf(ann, 2).condition + E.items.box.value * stateOf(ann, 5).condition
E.request(ann, "finish")
local result = E.last(ann, "Moving", "result")
check("FINISH: the result card says what came home: 3 pieces, their value, 2 trips", result ~= nil and result.a.how == "done" and result.a.home ~= nil
	and result.a.home.pieces == 3 and result.a.home.value == math.floor(value + 0.5) and result.a.trips == 2 and result.a.delivered == 3, result and result.a.home and result.a.home.value)
check("…no money, no XP (the warehouse earns)", result.a.money == 0 and result.a.pay == 0 and result.a.xp == 0 and #E.money == 0 and #E.xp == 0)
check("…the analytics' MoveDone", (function()
	for _, entry in E.tracked do
		if entry.name == "event" and entry.args[2] == "MoveDone" and entry.args[4] == House.id then
			return true
		end
	end
	return false
end)())
check("…the move is over: the interior gone, the van's prompts gone (the bay's too), nobody on it", E.destroyed == 1 and truck.chassis:FindFirstChild("MoveLoadBay") == nil
	and promptIn(truck.model, "Load") == nil and ann:GetAttribute("MoveWith") == nil and enter.destroyed == true)

-- A new house every move; what is left in the van is lost --------------------------------------------------------------------

E.place(ann, cork1.Position + V3(0, 0, 4))
local planned = #seeds
trigger(board1, ann)
check("the next card: a new seed (the house refilled)", #seeds == planned + 1 and seeds[#seeds] ~= firstSeed)
check("admin: start picks the sandbox house (the card's new seed)", string.find(Moving.admin(ann, "start"), "started", 1, true) ~= nil and E.built == 2 and #seeds == planned + 1
	and built[2] == seeds[#seeds] and Moving.busy(ann) ~= nil)
step()
park(truck, { x = House.curb.x, z = House.curb.z, yaw = 0 })
local function loadOne(spot: number, action: string?)
	E.place(ann, outside)
	trigger(promptIn(frontDoor, "Enter house"), ann)
	local model = newItem(spot)
	E.place(ann, model.PrimaryPart.Position + V3(1, 0, 0))
	trigger(promptIn(model, action or "Pick up"), ann)
	step()
	E.place(ann, E.interiors[#E.interiors].Position + V3(0, 3, 1))
	trigger(promptIn(workspace, "Leave house"), ann)
	truck.model:SetAttribute("BackOpen", true)
	E.place(ann, cargoDoor.WorldPosition + V3(0, 0, 2))
	step()
	trigger(promptIn(truck.model, "Load"), ann)
	step()
	return model
end
loadOne(1)
park(truck, plot1.vanSpot)
step()
check("move 2, trip 1 home", E.last(ann, "Moving", "state").a.trips == 1 and #E.collected == 4)
park(truck, { x = House.curb.x, z = House.curb.z, yaw = 0 })
loadOne(4)
check("…the clock in the van", stateOf(ann, 4).state == "truck")
E.request(ann, "finish")
result = E.last(ann, "Moving", "result")
check("FINISH with the clock still in the van: it is lost (never collected)", result.a.home.pieces == 1 and #E.collected == 4
	and string.find(result.a.howText, "stayed behind", 1, true) ~= nil, result.a.howText)
planned = #seeds
check("admin: start again: a new house (a fresh seed)", string.find(Moving.admin(ann, "start"), "started", 1, true) ~= nil and #seeds == planned + 1
	and built[3] == seeds[#seeds] and built[3] ~= built[2] and built[3] ~= built[1])
check("admin: time leaves one minute", string.find(Moving.admin(ann, "time"), "minute", 1, true) ~= nil
	and E.last(ann, "Moving", "state") ~= nil)
step()
check("…its clock", math.abs(E.last(ann, "Moving", "state").a.endsAt - (E.now + 60)) < 1e-6)
local marched = E.marched
check("admin: horde (the house without one keeps its clock)", string.find(Moving.admin(ann, "horde"), "horde", 1, true) ~= nil
	and math.abs(E.last(ann, "Moving", "state").a.endsAt - (E.now + 60)) < 1e-6)
step(T.Horde.Every + 0.1)
check("…the horde marches on the house", E.marched > marched)
check("admin: end calls it off cleanly", string.find(Moving.admin(ann, "end"), "called off", 1, true) ~= nil and E.last(ann, "Moving", "result").a.how == "cancelled"
	and Moving.busy(ann) == nil and E.destroyed == E.built)
trigger(board1, ann)
local cardSeed = seeds[#seeds]
check("admin: refill: a new house for the next move, its card", string.find(Moving.admin(ann, "refill"), "refilled", 1, true) ~= nil and seeds[#seeds] ~= cardSeed
	and E.last(ann, "Moving", "contract").a.id == House.id)

-- No van out: it comes to the plot; a refusing collection; the horde and roamers switched on --------------------------------------

E.cars[bob] = nil
S.Horde, S.Roam = true, 2
local said = Moving.admin(bob, "start")
local van = E.cars[bob]
local wanted = if Economy.findCar(Config.Sandbox.Van) then Config.Sandbox.Van else T.Van
check("no van out: the player's own comes to their plot's vanSpot (the Sprinter, else the ZDC Van)", string.find(said, "started", 1, true) ~= nil and van ~= nil
	and van.id == wanted and flatDistance(van.chassis.Position, V3(plot2.vanSpot.x, 0, plot2.vanSpot.z)) < 1, said)
step()
check("…its clock 20 minutes, the horde switched on at HordeAt", E.last(bob, "Moving", "state").a.hordeAt == E.last(bob, "Moving", "state").a.endsAt - S.HordeAt)
local zombies = #E.zombies
E.place(bob, outside)
step(T.Roam.Every + 0.1)
local roamers = 0
for index = zombies + 1, #E.zombies do
	if E.zombies[index].roamer then
		roamers += 1
	end
end
check("…a few roamers round the house (Roam)", roamers > 0 and roamers <= S.Roam, roamers)
E.now += 20 * 60 - S.HordeAt + 1
step()
check("…the horde comes", E.last(bob, "Moving", "state").a.horde == true and heard(bob, "HORDE"))
S.Horde, S.Roam = false, 0
E.refuse = true
local bobVan = van
bobVan.model:SetAttribute("BackOpen", true)
park(bobVan, { x = House.curb.x, z = House.curb.z, yaw = 0 })
local bobDoor = bobVan.chassis:FindFirstChild("CargoDoor")
E.place(bob, outside)
trigger(promptIn(frontDoor, "Enter house"), bob)
local bobLamp = newItem(1)
E.place(bob, bobLamp.PrimaryPart.Position + V3(1, 0, 0))
trigger(promptIn(bobLamp, "Pick up"), bob)
step()
E.place(bob, E.interiors[#E.interiors].Position + V3(0, 3, 1))
trigger(promptIn(workspace, "Leave house"), bob)
E.place(bob, bobDoor.WorldPosition + V3(0, 0, 2))
step()
trigger(promptIn(bobVan.model, "Load"), bob)
park(bobVan, plot2.vanSpot)
step()
check("a Collection.add that refuses (no save yet): the trip says so", heard(bob, "could not be stored") and #E.collected == 4)
E.refuse = false
Moving.admin(bob, "end")

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
