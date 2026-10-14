-- 8.0 SANDBOX, moves (design/sandbox/KONTRAKT.md): the real server/Moving.luau (MoveLobby, MoveGreeters, MoveHelper,
-- MoveSites with it) on tests/runtime/MovingRuntime.luau's fakes with Config.Sandbox.On (tests/run_tests.py builds
-- them; the fake art's plan records its seeds and gives each piece a colour variant).
--   * Moving.start in the sandbox: a Moving contracts kiosk on every plot (SandboxMap plot.board), no depot board, no
--     Wall, no dressing, no soldier, no Marge or Walt: one contract, "The Old Chalet" (SandboxMap.House).
--   * The card (any plot's board, not from afar): the house, its pieces' worth, 8.3 25 minutes, no horde by default, no
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
-- 8.0.1 (the review's moves findings):
--   * nose-in at home unloads (the van's middle in the circle, its back out of it); loaded in your plot but away from
--     the roller door: no trip, the driver hears "Back the van up to the roller door to unload" (once, then every
--     BackEvery s); never at another player's plot or with an empty van;
--   * START without a van out parks it the sandbox's way (server/SandboxBoot.luau's parkVan through the hook
--     Moving.parkVan: at the vanSpot, not seated, the player's own van repaired), never a bare spawnAt;
--   * a death mid-move (Moving.respawnAt, SandboxBoot's spawn): beside the van's back on the ground, the van wrecked:
--     outside the house's front door; off a move: home;
--   * the Sprinter bed's Center (SHOW ZONES' box) the bay's real middle from its CargoDoor;
--   * the words: GIVE UP after a trip, the owner leaving, the planning's timeout, the plot kiosks' corkboard (the
--     chalet, no Marge, Walt or Wall), Danny's lines; nothing a crew hears or reads at the end mentions the Wall, pay
--     or XP.
-- 8.1 walk-in doors: the chalet's front door walked through both ways (no E: its Enter house off), out 4 studs from it
-- facing the road, no way straight back, its doormat over the garden path while a move runs. 8.3 the big move: its plan
-- HouseLayout's kind "big" (Config.Moving.Sandbox.Kind); its back door (House.back) a second way in, its own doormat
-- and walk-in zone.
-- 8.2 analytics: Moving's listeners (onStart, onEnterHouse, onLoad, onTrip, onFinish; server/SandboxAnalytics.luau's)
-- hear each moment with its numbers, and every real end's words come out as AnalyticsPlan.moveHow's word (FINISH, the
-- admin's end, GIVE UP after a trip, the owner leaving).
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local Greeters = require("./MoveGreetersServer")
local MoveHelper = require("./MoveHelperServer")
local Lobby = require("./MoveLobbyServer")
local SandboxMap = require("./SandboxMap")
local SprinterLooks = require("./SprinterLooks")
local Brain = require("./MoveHelperBrain")
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
local kinds: { string } = {} -- (8.3: the kind of every plan asked for)
local planOf = E.art.layout.plan
E.art.layout.plan = function(seed: number, kind: string): any
	table.insert(seeds, seed)
	table.insert(kinds, kind)
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

-- server/SandboxBoot.luau's parkVan, set as its hook before Moving.start (as SandboxBoot.sandbox does): the player's van
-- (no carId: their own, Config.Sandbox.Van) at the spot, the old one gone, repaired (the save's damage, E.carHealth, only
-- for another car); every call kept. (tests/boot_runtime_test.luau runs the real one: its repair.)
local parked: { any } = {}
E.carHealth = {} -- player → the save's share of the van's health (0.2: wrecked before)
Moving.parkVan = function(player: any, spot: any, seat: boolean, carId: string?): (string?, any)
	table.insert(parked, { player = player, spot = spot, seat = seat, carId = carId })
	local old = E.cars[player]
	if old then
		old.model:Destroy()
	end
	local car = E.makeCar(player, carId or Config.Sandbox.Van, V3(spot.x, 2, spot.z))
	car.health = if carId == nil then 1 else E.carHealth[player] or 1
	E.cars[player] = car
	return nil, car
end

-- the map's front door (server/SandboxWorld.luau's FrontDoor: the attribute SandboxDoor), built before the move
local frontDoor = M.Instance.new("Part")
frontDoor.Name = "FrontDoor"
frontDoor.Size = V3(4, 7, 0.4)
frontDoor.CFrame = CF(House.door.x, 3.5, House.door.z + 0.5)
frontDoor:SetAttribute("SandboxDoor", true)
frontDoor.Parent = workspace

Moving.useArt(E.art)
-- 8.2: Moving's listeners (server/SandboxAnalytics.luau's: the funnel's steps, the moves' events), registered before
-- Moving.start as SandboxBoot does: what each heard, in order
local Plan = require("./AnalyticsPlan")
local told: { { kind: string, player: any, facts: any } } = {}
for kind, register in { start = Moving.onStart, enter = Moving.onEnterHouse, load = Moving.onLoad, trip = Moving.onTrip, finish = Moving.onFinish } :: { [string]: any } do
	register(function(player: any, facts: any)
		table.insert(told, { kind = kind, player = player, facts = facts })
	end)
end
-- The last `kind` a listener heard (since entry `since`), and how many.
local function lastTold(kind: string, since: number?): (any, number)
	local found, n = nil, 0
	for index = (since or 0) + 1, #told do
		if told[index].kind == kind then
			found, n = told[index], n + 1
		end
	end
	return found, n
end
-- How the last end was put in a word (AnalyticsPlan.moveHow on what Moving.onFinish heard, as SandboxAnalytics does).
local function howOf(entry: any): string
	local f = entry.facts
	return Plan.moveHow(f.phase, f.why, f.left, f.home + f.lost >= f.total)
end
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
-- Every text on a model (its signs' SurfaceGui labels).
local function textsOf(model: any): { string }
	local list = {}
	for _, d in model:GetDescendants() do
		if d.ClassName == "TextLabel" and type(d.Text) == "string" then
			table.insert(list, d.Text)
		end
	end
	return list
end
local function anyText(list: { string }, word: string): boolean
	for _, text in list do
		if string.find(string.lower(text), string.lower(word), 1, true) then
			return true
		end
	end
	return false
end
local corkWords = textsOf(kiosk1)
check("8.0.1: the plot kiosk's corkboard is the sandbox's: THE OLD CHALET, bring it home to your warehouse", anyText(corkWords, "THE OLD CHALET")
	and anyText(corkWords, "Bring it home to your warehouse") and anyText(corkWords, "MOVING CONTRACTS"), table.concat(corkWords, " | "))
check("…no Marge, no Walt, no Wall, no evacuation on it", not anyText(corkWords, "Marge") and not anyText(corkWords, "Walt") and not anyText(corkWords, "Wall")
	and not anyText(corkWords, "evacuat"), table.concat(corkWords, " | "))

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
check("the board's card: The Old Chalet, its pieces' worth, 8.3: 25 minutes (several trips)", card ~= nil and card.a.id == House.id and card.a.name == House.name and card.a.items == 6
	and card.a.estimate == worth and S.Time == 25 * 60 and card.a.time == S.Time and card.a.busy == nil and card.a.address == S.Address, card and card.a.busy)
check("…no horde by default (no guns in the sandbox), no roamers", S.Horde == false and S.Roam == 0 and card.a.hordeAt == 0)
check("…no story, the note (no pay per piece), one contract", card.a.story == false and type(card.a.note) == "string" and #card.a.contracts == 1
	and card.a.contracts[1].id == House.id and E.last(ann, "Tutorial", "message") == nil)
check("…its house planned with a seed, 8.3: the big house's plan (kind big)", #seeds == 1 and seeds[1] > 0 and kinds[1] == "big" and S.Kind == "big")
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
local began, starts = lastTold("start")
check("8.2: Moving.onStart: the owner, the house, its 6 pieces, solo, nothing home yet", starts == 1 and began.player == ann and began.facts.owner == ann
	and began.facts.contract == House.id and began.facts.total == 6 and began.facts.crew == 1 and began.facts.trips == 0 and began.facts.home == 0
	and began.facts.left > 0 and began.facts.minutes == 0, began and began.facts.crew)
local firstSeed = seeds[1] -- (Ann's card's: Cid's card planned the second)
check("…the house built with the card's seed (planned once)", #built == 1 and built[1] == firstSeed and #seeds == 2 and seeds[2] ~= firstSeed, `{built[1]} {firstSeed} {#seeds}`)
step()
local view = E.last(ann, "Moving", "state")
check("the state: the drop-off is the owner's plot's unload circle, in the HUD's words; no horde", view.a.drop == "your warehouse" and view.a.dropOff.x == plot1.unload.x
	and view.a.dropOff.z == plot1.unload.z and view.a.hordeAt == nil and view.a.endsAt == E.now + S.Time and view.a.mine == true)
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
check("8.0.1: Danny says hello without the city's depot; his full van's line names no Wall", E.saidSince(Brain.line("hello", true) :: string, 0)
	and not E.saidSince(Brain.Lines.hello, 0) and string.find(Brain.line("full", true) :: string, "Wall", 1, true) == nil)

-- A death mid-move (server/SandboxBoot.luau's spawn asks Moving.respawnAt) ------------------------------------------------

local cargoBack = truck.chassis:FindFirstChild("CargoDoor")
local again = Moving.respawnAt(ann)
local rel = if again then truck.chassis.CFrame:PointToObjectSpace(again.Position) else nil
check("8.0.1: a death on a move, the van out: the new body beside the van's back (out of its body), on the ground", again ~= nil and rel ~= nil
	and math.abs(rel.X) > T.Beds.sprinter.Width / 2 + 1 and math.abs(rel.Z - truck.chassis.CFrame:PointToObjectSpace(cargoBack.WorldPosition).Z) < 3
	and math.abs(again.Position.Y - 3) < 1e-6
	and flatDistance(again.Position, cargoBack.WorldPosition) < 10, rel and `{rel.X}, {rel.Y}, {rel.Z} at {again.Position.X}, {again.Position.Y}, {again.Position.Z}`)
local toBack = V3(cargoBack.WorldPosition.X - again.Position.X, 0, cargoBack.WorldPosition.Z - again.Position.Z).Unit
check("…looking at the back doors", again.LookVector:Dot(toBack) > 0.95, `{again.LookVector.X}, {again.LookVector.Y}, {again.LookVector.Z}`)
truck.wrecked = true
local out = Moving.respawnAt(ann)
check("…the van wrecked: 6 studs out of the house's front door (SandboxMap.House.door), looking out", out ~= nil
	and flatDistance(out.Position, V3(House.door.x, 0, House.door.z - 6)) < 1e-6 and math.abs(out.Position.Y - 3) < 1e-6 and out.LookVector.Z < -0.99, out and out.Position)
truck.wrecked = false
check("…off a move: nil (home, the plot's spawn)", Moving.respawnAt(bob) == nil and Moving.respawnAt(cid) == nil)
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
local cameIn, ins = lastTold("enter")
check("8.2: Moving.onEnterHouse: Ann came into her move's house", ins == 1 and cameIn.player == ann and cameIn.facts.owner == ann, ins)
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
check("Leave house: out at the house's door with the lamp (8.1 walk-in doors: 4 studs out, facing away from it)", math.abs(flatDistance(E.rootOf(ann).Position, V3(House.door.x, 0, House.door.z)) - 4) < 0.5
	and E.rootOf(ann).CFrame.LookVector.Z < -0.99 and ann.Character:GetAttribute("MoveCarry") == 1, E.rootOf(ann).Position)
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
local loaded, loads = lastTold("load")
check("8.2: Moving.onLoad: Ann loaded the lamp into her move's van (one piece in it)", loads == 1 and loaded.player == ann and loaded.facts.owner == ann
	and loaded.facts.item == "lamp" and loaded.facts.out == 1, loads)
local BED = T.Beds.sprinter
local cz = cargoDoor.Position.Z - BED.Back - BED.Length / 2 -- (the bay's middle: Back in front of the doors)
check("8.0.1: the Sprinter bed's Center (SHOW ZONES' box without a door) is its bay's middle from the real CargoDoor", BED.Center[1] == 0
	and math.abs(BED.Center[2] - (SprinterLooks.CargoDoor[3] - BED.Back - BED.Length / 2)) < 1e-6 and math.abs(BED.Center[2] - 3.85) < 1e-6, BED.Center[2])
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
Config.MoveHelper.WaitForHelper = false -- (8.3 the switch off: today's rule, the sofa dragged alone; Danny's call is movehelper_runtime_test's)
trigger(promptIn(sofa, "Lift"), ann)
Config.MoveHelper.WaitForHelper = true
check("8.3 WaitForHelper off: a two-person Lift is a drag alone as before (no call)", ann.Character:GetAttribute("MoveCarry") == 3
	and ann:GetAttribute("MoveHelperCall") == nil and MoveHelper.find(ann).call == nil)
step()
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(promptIn(workspace, "Leave house"), ann)
E.place(ann, truck.chassis.CFrame * V3(BED.Width / 2 + 3, 3, cz)) -- (beside the van, by its side wall)
step()
trigger(bayLoad, ann)
check("beside the van (outside the bay), the back shut: no Load", ann.Character:GetAttribute("MoveCarry") == 3 and stateOf(ann, 3).state == "carried")
E.Net.get("PutDown").OnServerEvent:Fire(ann)

-- The drop-off: the owner's plot -------------------------------------------------------------------------------------------------

local BACK_UP = "Back the van up to the roller door to unload"
-- How many times `player` heard `text` (since message `since`).
local function times(player: any, text: string, since: number?): number
	local n = 0
	for index = since or 1, #E.messages do
		local m = E.messages[index]
		if m.player == player and m.remote == "Notice" and string.find(tostring(m.kind), text, 1, true) ~= nil then
			n += 1
		end
	end
	return n
end
park(truck, plot2.vanSpot)
step()
check("the van at another player's plot: no trip (and no word on backing up: not your plot)", #E.collected == 0 and E.last(ann, "Moving", "state").a.trips == 0
	and not heard(ann, BACK_UP))
park(truck, { x = 0, z = 200, yaw = 180 })
step()
check("…nor on Main Street", #E.collected == 0 and not heard(ann, BACK_UP))
park(truck, plot1.vanSpot)
check("(the van's back inside the owner's unload circle)", flatDistance(cargoDoor.WorldPosition, V3(plot1.unload.x, 0, plot1.unload.z)) <= plot1.unload.r)
local tripAt = #E.messages
step()
check("home: a trip, the move goes on", E.last(ann, "Moving", "result") == nil and E.last(ann, "Moving", "state").a.trips == 1 and heard(ann, "Trip 1 home", tripAt))
check("…every piece in the van into the owner's stock (Collection.add)", #E.collected == 2 and E.collected[1].player == ann and E.collected[2].player == ann)
local trip, trips = lastTold("trip")
check("8.2: Moving.onTrip: the owner's trip 1, its 2 pieces stored, 2 home, the van empty", trips == 1 and trip.player == ann and trip.facts.trips == 1
	and trip.facts.pieces == 2 and trip.facts.stored == 2 and trip.facts.home == 2 and trip.facts.out == 0 and trip.facts.value > 0, trips)
check("8.2: …and the move's not over (no onFinish yet)", select(2, lastTold("finish")) == 0)
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
-- 8.0.1: home, but parked in the plot away from the roller door (its side to the warehouse): no trip; how to unload
local away = { x = plot1.unload.x + 40, z = plot1.unload.z + 24, yaw = 90 }
E.seated[ann] = truck -- (Ann drives)
park(truck, away)
local hintAt = #E.messages
step()
check("8.0.1: loaded, in your plot away from the roller door: no trip, the driver hears how to unload", E.last(ann, "Moving", "state").a.trips == 1
	and #E.collected == 2 and times(ann, BACK_UP, hintAt) == 1, E.lastNotice(ann))
step(5)
step(5)
check("…once (not every tick)", times(ann, BACK_UP, hintAt) == 1)
step(20)
check("…again after a while if the van stays there", times(ann, BACK_UP, hintAt) == 2)
-- nose-in to the roller door: the van's back out of the unload circle, its middle in it
park(truck, { x = plot1.unload.x, z = plot1.unload.z + 8, yaw = 0 })
local unloadAt = V3(plot1.unload.x, 0, plot1.unload.z)
check("(nose-in: the van's back outside the unload circle, its middle inside)", flatDistance(cargoDoor.WorldPosition, unloadAt) > plot1.unload.r
	and flatDistance(truck.chassis.Position, unloadAt) <= plot1.unload.r, flatDistance(cargoDoor.WorldPosition, unloadAt))
step()
check("trip 2: home nose-in (8.0.1: the van's middle in the circle), into the stock", E.last(ann, "Moving", "state").a.trips == 2 and #E.collected == 3
	and E.collected[3].entry.item == "box" and heard(ann, "Trip 2 home"))
park(truck, away)
hintAt = #E.messages
step(25)
check("…the van empty, away in the plot: no word on backing up", times(ann, BACK_UP, hintAt) == 0)
E.seated[ann] = nil

-- FINISH -----------------------------------------------------------------------------------------------------------------------

local value = E.items.lamp.value * stateOf(ann, 1).condition + E.items.tv.value * stateOf(ann, 2).condition + E.items.box.value * stateOf(ann, 5).condition
E.request(ann, "finish")
local result = E.last(ann, "Moving", "result")
check("FINISH: the result card says what came home: 3 pieces, their value, 2 trips", result ~= nil and result.a.how == "done" and result.a.home ~= nil
	and result.a.home.pieces == 3 and result.a.home.value == math.floor(value + 0.5) and result.a.trips == 2 and result.a.delivered == 3, result and result.a.home and result.a.home.value)
check("…no money, no XP (the warehouse earns)", result.a.money == 0 and result.a.pay == 0 and result.a.xp == 0 and #E.money == 0 and #E.xp == 0)
local ended, ends = lastTold("finish")
check("8.2: Moving.onFinish: the owner, done by FINISH (\"finish\"), 2 trips, 3 pieces home worth the result card's value", ends == 1 and ended.player == ann
	and ended.facts.phase == "done" and ended.facts.event == "deliver" and howOf(ended) == "finish" and ended.facts.trips == 2 and ended.facts.home == 3
	and ended.facts.value == result.a.home.value and ended.facts.total == 6 and ended.facts.left > 0 and ended.facts.minutes >= 0, ended and howOf(ended))
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
check("8.2: …onFinish: \"finish\", 1 piece home (the clock still in the van)", howOf((lastTold("finish"))) == "finish" and (lastTold("finish")).facts.home == 1
	and (lastTold("finish")).facts.out == 1)
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
check("8.2: …onFinish: cancelled, nothing home, \"admin\"", (lastTold("finish")).facts.phase == "cancelled" and (lastTold("finish")).facts.home == 0
	and howOf((lastTold("finish"))) == "admin", howOf((lastTold("finish"))))
trigger(board1, ann)
local cardSeed = seeds[#seeds]
check("admin: refill: a new house for the next move, its card", string.find(Moving.admin(ann, "refill"), "refilled", 1, true) ~= nil and seeds[#seeds] ~= cardSeed
	and E.last(ann, "Moving", "contract").a.id == House.id)

-- No van out: it comes to the plot; a refusing collection; the horde and roamers switched on --------------------------------------

E.cars[bob] = nil -- (wrecked before: the save keeps its damage)
E.carHealth[bob] = 0.2
S.Horde, S.Roam = true, 2
local parkedBefore, callsBefore = #parked, E.vehicleCalls or 0
local said = Moving.admin(bob, "start")
local van = E.cars[bob]
local wanted = if Economy.findCar(Config.Sandbox.Van) then Config.Sandbox.Van else T.Van
check("no van out: the player's own comes to their plot's vanSpot (the Sprinter, else the ZDC Van)", string.find(said, "started", 1, true) ~= nil and van ~= nil
	and van.id == wanted and flatDistance(van.chassis.Position, V3(plot2.vanSpot.x, 0, plot2.vanSpot.z)) < 1, said)
local how = parked[#parked]
check("8.0.1: …the sandbox's way (SandboxBoot.parkVan, the hook Moving.parkVan): at his vanSpot, not seated, his own van, repaired (not the save's 0.2)",
	#parked == parkedBefore + 1 and how.player == bob and how.spot == plot2.vanSpot and how.seat == false and how.carId == nil and van.health == 1, van.health)
check("…never a bare spawnAt / placeAt / placeNear (they would skip the repair)", (E.vehicleCalls or 0) == callsBefore, E.vehicleCalls)
step()
check("…its clock 25 minutes, the horde switched on at HordeAt", E.last(bob, "Moving", "state").a.hordeAt == E.last(bob, "Moving", "state").a.endsAt - S.HordeAt)
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
E.now += S.Time - S.HordeAt + 1
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

-- 8.0.1: the words -------------------------------------------------------------------------------------------------------------

E.request(bob, "giveup")
local bobResult = E.last(bob, "Moving", "result")
-- (8.2 e2e: the refused piece never came home, it is lost: so this GIVE UP calls off a move with nothing home)
check("8.2: the piece the warehouse refused is lost, not home (the result, the facts and the tasks never count it)", bobResult ~= nil
	and bobResult.a.delivered == 0 and bobResult.a.how ~= "done", bobResult and `{bobResult.a.how} {bobResult.a.delivered}`)
check("8.0.1: GIVE UP: \"You called it off\" (no Wall), no pay, no XP", bobResult ~= nil and string.find(bobResult.a.howText, "You called it off", 1, true) == 1
	and string.find(bobResult.a.howText, "Wall", 1, true) == nil and bobResult.a.money == 0 and bobResult.a.xp == 0, bobResult and bobResult.a.howText)
check("8.2: …onFinish: Bob's, \"giveup\"", (lastTold("finish")).player == bob and howOf((lastTold("finish"))) == "giveup", howOf((lastTold("finish"))))

-- the planning left open past Config.MoveRoles.Lobby.Timeout
E.place(bob, moves:FindFirstChild("MovingBoard2"):FindFirstChild("Board").Position + V3(0, 0, 4))
trigger(board2, bob)
E.request(bob, "start", House.id)
check("(Bob's planning open)", E.last(bob, "MoveLobby", "lobby") ~= nil and E.last(bob, "MoveLobby", "lobby").a ~= nil, E.lastNotice(bob))
E.now += Config.MoveRoles.Lobby.Timeout + 1
local lobbyAt = #E.messages
Lobby.step()
check("8.0.1: the planning ran out of time: take it again at a Moving contracts board (by your warehouse), not the depot's", heard(bob, "ran out of time", lobbyAt)
	and heard(bob, "Moving contracts board", lobbyAt) and not heard(bob, "depot", lobbyAt), E.lastNotice(bob))

-- the owner leaves after a trip: the crew hears that what came home is in the warehouse
E.crew[ann] = { cid }
check("(Ann's move with Cid in her crew)", string.find(Moving.admin(ann, "start"), "started", 1, true) ~= nil)
E.place(cid, outside)
step()
park(truck, { x = House.curb.x, z = House.curb.z, yaw = 0 })
loadOne(1)
park(truck, plot1.vanSpot)
step()
check("(a trip home)", E.last(ann, "Moving", "state").a.trips == 1, E.lastNotice(ann))
E.place(cid, truck.chassis.Position + V3(4, 1, 0))
local leftAt = #E.messages
E.leave(ann)
local cidResult = E.last(cid, "Moving", "result")
check("8.0.1: the owner left after a trip: the crew hears what came home is in the warehouse (no Wall)", heard(cid, "What came home is in their warehouse", leftAt)
	and not heard(cid, "Wall", leftAt) and cidResult ~= nil and cidResult.a.how == "done"
	and cidResult.a.howText == "Ann left the game: what came home is in their warehouse", cidResult and cidResult.a.howText)
check("8.2: …onFinish: Ann's, \"left\", the crew of two", (lastTold("finish")).player == ann and howOf((lastTold("finish"))) == "left"
	and (lastTold("finish")).facts.crew == 2, howOf((lastTold("finish"))))

-- 8.1 walk-in doors in the sandbox (the owner: "no E at the house, neither in nor out"): the chalet's front door (the map's
-- SandboxDoor part) walked through both ways, after the dwell, facing it; out 4 studs from the door facing the road; no
-- way straight back; its doormat on the garden path in front of it; the E prompts off. 8.3 the big move: its back door
-- (House.back, in the back wall) a second way in, its own doormat (the fake plan has one way out: in to its entry).
do
	local D = T.Doors
	check("(Bob's move)", string.find(Moving.admin(bob, "start"), "started", 1, true) ~= nil)
	step()
	local o = E.interiors[#E.interiors]
	local foot = V3(House.door.x, House.door.y, House.door.z)
	local up = V3(0, Config.Furniture.EntryUp, 0)
	local into = V3(0, 0, 1) -- (the fake plan's +Z)
	local exitAt = o * V3(0, 0, 0.5) + up
	local function stand(player: any, at: any, look: any)
		E.rootOf(player).CFrame = M.CFrame.lookAt(at, at + look)
	end
	local function isIn(player: any): boolean
		return (E.rootOf(player).Position - o.Position).Magnitude < 100
	end
	local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{House.id}`)
	local back = V3(House.back.x, House.back.y, House.back.z)
	local backFacing = V3(0, 0, 1) -- (House.back yaw 180: out to the south, the garden)
	local mat, backMat: any, any = nil, nil
	for _, d in site:GetDescendants() do
		if d.Name == "WalkInMat" then
			if flatDistance(d.Position, foot) < 5 then
				mat = d
			elseif flatDistance(d.Position, back) < 5 then
				backMat = d
			end
		end
	end
	local label = mat and mat:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel")
	check("8.1 walk-in doors: a doormat (▲ IN) in front of the chalet's door, over the garden path (its top 0.08), shown", mat ~= nil and label.Text == "▲ IN"
		and mat.Transparency == 0 and mat.Position.Y - mat.Size.Y / 2 > 0.08 and (mat.Position - foot):Dot(facing) > 0.5 and (mat.Position - foot):Dot(facing) < D.Depth)
	check("…Enter house on the map's door there, off", promptIn(frontDoor, "Enter house") ~= nil and not promptIn(frontDoor, "Enter house").Enabled)
	stand(bob, foot + up + facing * 2, -facing)
	step(0.1)
	check("walking up to the chalet's door: not in before the dwell", not isIn(bob))
	step(D.Dwell)
	check("…in after it (no E), facing into the house", isIn(bob) and E.rootOf(bob).CFrame.LookVector:Dot(into) > 0.99)
	stand(bob, exitAt + into * 8, -into)
	step(0.1)
	step(D.Rearm)
	stand(bob, exitAt + into * 1, -into)
	step(0.1)
	step(D.Dwell)
	check("walked out by the doorway inside: 4 studs out of the chalet's door, facing the road", not isIn(bob)
		and math.abs(flatDistance(E.rootOf(bob).Position, foot) - 4) < 0.5 and E.rootOf(bob).CFrame.LookVector:Dot(facing) > 0.99, E.rootOf(bob).Position)
	stand(bob, foot + up + facing * 2, -facing)
	step(0.1)
	step(D.Dwell)
	step(0.5)
	check("…turned straight back to the door: shut for Rearm s (no ping-pong)", not isIn(bob))
	step(D.Rearm)
	step(D.Dwell)
	check("…then in again", isIn(bob))
	-- 8.3 the big move's back door: out by the front, round the house to the back wall, in by the back door
	local backLabel = backMat and backMat:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel")
	local backPrompt = promptIn(site, "Enter by the back door")
	check("8.3: the back door's doormat (▲ IN) in front of it, south of the back wall, shown; its Enter prompt there, off", backMat ~= nil
		and backLabel.Text == "▲ IN" and backMat.Transparency == 0 and (backMat.Position - back):Dot(backFacing) > 0.5
		and (backMat.Position - back):Dot(backFacing) < D.Depth and backPrompt ~= nil and not backPrompt.Enabled)
	stand(bob, exitAt + into * 8, -into)
	step(0.1)
	step(D.Rearm)
	stand(bob, exitAt + into * 1, -into)
	step(0.1)
	step(D.Dwell)
	check("(out by the front door again)", not isIn(bob))
	step(D.Rearm)
	stand(bob, back + up + backFacing * 6, -backFacing)
	step(0.1)
	check("…at the back door, not in before the dwell", not isIn(bob))
	stand(bob, back + up + backFacing * 2, -backFacing)
	step(0.1)
	step(D.Dwell)
	check("…walked into the back door's zone facing it: in (no E)", isIn(bob))
	Moving.admin(bob, "end")
	check("the move over: both doormats hidden again (no move at the house)", mat.Transparency == 1 and backMat.Transparency == 1)
end

-- Done is quiet: nothing the sandbox's players heard (their notices) or read on a result card mentions the Wall, pay or
-- XP (the contract card's note says "No pay per piece" on purpose: not checked); Danny's lines name no Wall.
local function noisy(text: string): boolean
	return string.find(text, "Wall", 1, true) ~= nil or string.find(string.lower(text), "%f[%a]pa[iy][ds]?%f[%A]") ~= nil
		or string.find(text, "%f[%a]XP%f[%A]") ~= nil
end
local loud: { string } = {}
local results = 0
for _, m in E.messages do
	if m.remote == "Notice" and type(m.kind) == "string" and noisy(m.kind) then
		table.insert(loud, m.kind)
	elseif m.remote == "Moving" and m.kind == "result" and type(m.a) == "table" then
		results += 1
		if noisy(tostring(m.a.howText)) or m.a.pay ~= 0 or m.a.money ~= 0 or m.a.xp ~= 0 then
			table.insert(loud, `result: {m.a.howText} {m.a.pay} {m.a.money} {m.a.xp}`)
		end
	end
end
for _, text in E.said do
	if string.find(text, "Wall", 1, true) then
		table.insert(loud, text)
	end
end
check("8.0.1: done is quiet: no notice, result card (of " .. results .. ") or Danny's line in the sandbox mentions the Wall, pay or XP", #loud == 0 and results >= 6,
	table.concat(loud, " | "))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
