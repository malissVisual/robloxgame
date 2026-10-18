-- 8.0 SANDBOX, moves (design/sandbox/KONTRAKT.md): the real server/Moving.luau (MoveLobby, MoveHelper,
-- MoveSites with it) on tests/runtime/MovingRuntime.luau's fakes with Config.Sandbox.On (tests/run_tests.py builds
-- them; the fake art's plan records its seeds and gives each piece a colour variant).
--   * Moving.start in the sandbox: 9.7 no kiosk on the plots (the lobby's portals start the runs: server/Runs.luau), no
--     depot board, no Wall, no dressing, no soldier, no Marge or Walt: a contract a place (SandboxMap.Houses).
--   * 9.7 the run (Moving.startRun, as server/Runs.luau calls it with the host's van parked at the curb): no card, no
--     planning, no LAUNCH; a START asked opens nothing; no plot or no such house: refused (the card as it was); the run's
--     state (its difficulty, the host's), its clock the house's × the difficulty's time, no horde by default, no story;
--     the house built with a new seed (8.3 economy: kept while nothing comes home), the owner's own van (the Sprinter,
--     its walk-in bay Config.Moving.Beds.sprinter).
--   * "Enter house" on the map's front door (the part with the attribute SandboxDoor), out at the door; the truck at
--     House.curb (its nose to the road, its back to the door).
--   * 8.8 no roles (tests/noroles_runtime_test.luau has the crew's): Ann has none on the move (no MoveRole, the state's
--     team only says the van was called), the van's Load holds no time.
--   * Load at the back doors, and from inside the walk-in bay (its own Load, the back shut), every piece inside the
--     bay; Danny on a solo move (10.1: free, with you from the start; a two-person Lift without his answer, Config.MoveHelper
--     WaitForHelper off for it, is dragged alone).
--   * 9.7 no unloading at a plot during a run; FINISH at the truck: everything in it goes home at once into the
--     loader's stock (Collection.add with its item, variant, condition, name), no pay, as one trip (Moving.onTrip),
--     Moving.onRunEnd's facts (the pieces, their values, whose stock), Moving.onFinish's; FINISH with nothing loaded:
--     called off, the seed kept; the clock running out: the run ends late, the truck's load home.
--   * The edges: a Collection.add that refuses is said at the run's end, the admin's time / horde / the run's end, the
--     horde and the roamers switched on (Config.Moving.Sandbox).
-- 8.0.1 (the review's moves findings; 9.7: no driving home, so no unloading at the plot, no "Back the van up"):
--   * a death mid-move (Moving.respawnAt, SandboxBoot's spawn): beside the van's back on the ground, the van wrecked:
--     outside the house's front door; off a move: home;
--   * the Sprinter bed's Center (SHOW ZONES' box) the bay's real middle from its CargoDoor;
--   * the words: GIVE UP, the host leaving, Danny's lines; nothing a crew hears or reads at the end mentions the Wall,
--     pay or XP.
-- 8.1 walk-in doors: the chalet's front door walked through both ways (no E: its Enter house off), out 4 studs from it
-- facing the road, no way straight back, its doormat over the garden path while a move runs. 8.3 the big move: its plan
-- HouseLayout's kind "big" (its contract's Kind, Config.Moving.Sandbox.Houses); its back door (House.back) a second way in, its own doormat
-- and walk-in zone. 8.5 walking through: the leaf opens as you walk at the door (whichever way you look; from farther
-- out at a run), never as you walk past it; walking into a doorway is the trip at the first look (no dwell, your walk
-- carried on), in by the front door, out by the doorway inside, in by the back door; walking back out of the hall or
-- along the doorway goes nowhere; standing at a door facing it, the dwell as before.
-- 8.4: the house kept across servers: a player with a save has the seed of their card's house in it (rolled, kept
-- through GIVE UP and leaving); another server with that save shows the same house (a loaded save's seed counts over
-- the server's memory); a trip home drops it and the next card rolls a new one into it.
-- 8.2 analytics: Moving's listeners (onStart, onEnterHouse, onLoad, onTrip, onFinish; server/SandboxAnalytics.luau's)
-- hear each moment with its numbers, and every real end's words come out as AnalyticsPlan.moveHow's word (FINISH, the
-- admin's end, GIVE UP after a trip, the owner leaving).
local E = require("./MovingRuntime")
local Config = require("./Config")
Config.Sandbox.On = true -- (before Moving.start: it reads the mode there)
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local SandboxMap = require("./SandboxMap")
local SprinterLooks = require("./SprinterLooks")
local Brain = require("./MoveHelperBrain")

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
local F = S.Houses[House.id] -- (six houses: the farmstead's contract, one of six)
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

-- the map's front door (server/SandboxWorld.luau's FrontDoor: the attribute SandboxDoor; 8.3 a door leaf too), built
-- before the move
local frontDoor = M.Instance.new("Part")
frontDoor.Name = "FrontDoor"
frontDoor.Size = V3(4, 7, 0.4)
frontDoor.CFrame = CF(House.door.x, House.door.y + 3.5, House.door.z + 0.5) -- (10.8 on its island: over its door's height)
frontDoor:SetAttribute("SandboxDoor", true)
frontDoor:SetAttribute("DoorLeaf", 1) -- (8.3: a leaf swinging into the house, as SandboxWorld's chalet door's)
frontDoor:SetAttribute("DoorSwing", 1)
frontDoor:SetAttribute("DoorDark", true)
frontDoor.Parent = workspace
-- six houses: the other places to empty have theirs too (SandboxWorld's stand-ins: a door in a model whose SandboxHouse
-- is the house's id), each in front of its own house's door (the farmstead's above has none: a door of no house's is
-- the farmstead's). A move rotates to the next house once something came home: every later move is on one of them.
local doorOf: { [string]: any } = { [House.id] = frontDoor }
for index, h in SandboxMap.Houses do
	if index > 1 then
		local holder = M.Instance.new("Model")
		holder.Name = `StandIn_{index}`
		holder:SetAttribute("SandboxHouse", h.id)
		holder.Parent = workspace
		local look = M.CFrame.new(h.door.x, h.door.y + 3.5, h.door.z) * M.CFrame.Angles(0, math.rad(h.door.yaw), 0)
		local door = M.Instance.new("Part")
		door.Name = "FrontDoor"
		door.Size = V3(4, 7, 0.4)
		door.CFrame = look * CF(0, 0, 0.5)
		door:SetAttribute("SandboxDoor", true)
		door.Parent = holder
		doorOf[h.id] = door
	end
end
-- The house of `player`'s move now (its state's contract), where they stand outside its door, its curb's spot.
local function houseNow(player: any): any
	local view = E.last(player, "Moving", "state")
	return SandboxMap.house(view and view.a and view.a.contract) or House
end
local function outsideOf(h: any): any
	local r = math.rad(h.door.yaw)
	return V3(h.door.x, h.door.y + 3, h.door.z) + V3(-math.sin(r), 0, -math.cos(r)) * 3
end
-- 8.3 the back door's leaf (server/SandboxWorld.luau's BackLeaf: a door leaf in the back wall at House.back)
local backLeaf = M.Instance.new("Part")
backLeaf.Name = "BackLeaf"
backLeaf.Size = V3(3, 7, 0.4)
backLeaf.CFrame = CF(House.back.x, House.back.y + 3.5, House.back.z - 0.2)
backLeaf:SetAttribute("DoorLeaf", -1)
backLeaf:SetAttribute("DoorSwing", 1)
backLeaf:SetAttribute("DoorDark", true)
backLeaf.Parent = workspace

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

-- The world ----------------------------------------------------------------------------------------------------------------

local moves = workspace:FindFirstChild("Moves")
check("the sandbox: 9.7 no kiosk on the plots (the lobby's portals start the runs), no depot board, no Wall, no dressing", moves ~= nil
	and moves:FindFirstChild("MovingBoard1") == nil and moves:FindFirstChild("MovingBoard4") == nil and moves:FindFirstChild("MovingBoard") == nil
	and moves:FindFirstChild("MovingDropOff") == nil and moves:FindFirstChild("MoveDressing") == nil)
check("one contract a place: The Old Farmstead's among them (no Marge, no Walt)", moves:FindFirstChild("Move_sandbox_house") ~= nil and moves:FindFirstChild("Move_marge") == nil
	and moves:FindFirstChild("Move_walt") == nil)
E.request(cid, "start", House.id)
check("9.7: a START asked (no board anywhere): no planning, no move", E.last(cid, "MoveLobby", "lobby") == nil and E.built == 0)

-- The run (9.7: the lobby's portal; server/Runs.luau parks the truck at the curb, then Moving.startRun) -----------------------

-- server/Moving.luau's onRunEnd (server/Runs.luau's: the results card): what each run's end told
local runEnds: { { host: any, facts: any } } = {}
Moving.onRunEnd(function(host: any, facts: any)
	table.insert(runEnds, { host = host, facts = facts })
end)
check("9.7: a run without a warehouse (Cid: no plot): refused, why said", Moving.startRun(cid, House.id, "normal") ~= nil and E.built == 0 and Moving.busy(cid) == nil)
check("…a house there is none of: refused", Moving.startRun(ann, "nowhere", "normal") ~= nil and E.built == 0)
E.truckAt = V3(House.curb.x, 2, House.curb.z)
Moving.parkVan(ann, House.curb, false) -- (Runs.begin: the host's own van at the house's curb, its nose away from the door)
local truck = E.cars[ann]
park(truck, House.curb)
local startedAt = #E.messages
check("the run: Moving.startRun at Normal with the owner's own Sprinter (no card, no planning, no LAUNCH)", Moving.startRun(ann, House.id, "normal") == nil
	and E.built == 1 and E.cars[ann] == truck and heard(ann, "NORMAL", startedAt) and heard(ann, "truck", startedAt), E.lastNotice(ann))
check("…its words: no drive (the truck is at the door), FINISH or the clock", not heard(ann, "Drive", startedAt) and heard(ann, "FINISH", startedAt))
local began, starts = lastTold("start")
check("8.2: Moving.onStart: the owner, the house, its 6 pieces, solo, nothing home yet", starts == 1 and began.player == ann and began.facts.owner == ann
	and began.facts.contract == House.id and began.facts.total == 6 and began.facts.crew == 1 and began.facts.trips == 0 and began.facts.home == 0
	and began.facts.left > 0 and began.facts.minutes == 0, began and began.facts.crew)
local firstSeed = seeds[1]
check("…the house planned and built once with a new seed, 8.3: the big house's plan (kind big)", #built == 1 and built[1] == firstSeed and #seeds == 1 and firstSeed > 0
	and kinds[1] == "big" and F.Kind == "big", `{built[1]} {firstSeed} {#seeds}`)
check("…its seed the owner's card's now (kept while nothing comes home)", Moving.houseOf(ann) == House)
step()
local view = E.last(ann, "Moving", "state")
check("8.8: no role on the run (no MoveRole), the state's team says only whether the van was called", ann:GetAttribute("MoveRole") == nil and view.a.team.called == false
	and view.a.team.role == nil and view.a.team.crew == nil and view.a.team.free == nil and view.a.team.barricades == nil)
check("the state: the run's (its difficulty, Ann the host), its clock the farmstead's × Normal's (25 minutes), no horde", type(view.a.run) == "table"
	and view.a.run.difficulty == "normal" and view.a.run.mine == true and view.a.hordeAt == nil and view.a.endsAt == E.now + F.Time and F.Time == 25 * 60
	and view.a.mine == true and S.Horde == false and S.Roam == 0)
check("the GPS's house: the truck's curb", view.a.house.x == House.curb.x and view.a.house.z == House.curb.z)
local porch = false
for _, child in workspace:GetChildren() do
	if child:GetAttribute("MoveGreeter") == "porch" then
		porch = true
	end
end
check("nobody on the porch, no Marge's text (no story)", not porch and E.last(ann, "Tutorial", "message") == nil)
local danny = MoveHelper.find(ann)
check("Danny joins a crew of one", danny ~= nil and danny.body ~= nil)
check("10.1 …free: Ann's from the start (no price on the status line; the sandbox's words: his clipboard, every device's, no click)", danny.hirer == ann
	and ann:GetAttribute("MoveHelper") == "hired" and ann:GetAttribute("MoveHelperPrice") == nil and string.find(E.lastNotice(ann), "Danny is with you", 1, true) ~= nil
	and string.find(E.lastNotice(ann), "clipboard", 1, true) ~= nil and string.find(string.lower(E.lastNotice(ann) or ""), "click", 1, true) == nil, E.lastNotice(ann))
check("8.0.1: Danny says hello without the city's depot; his full van's line names no Wall", E.saidSince(Brain.line("hello", true) :: string, 0)
	and not E.saidSince(Brain.Lines.hello, 0) and string.find(Brain.line("full", true) :: string, "Wall", 1, true) == nil)

-- A death mid-move (server/SandboxBoot.luau's spawn asks Moving.respawnAt) ------------------------------------------------

local cargoBack = truck.chassis:FindFirstChild("CargoDoor")
local again = Moving.respawnAt(ann)
local rel = if again then truck.chassis.CFrame:PointToObjectSpace(again.Position) else nil
check("8.0.1: a death on a run, the van out: the new body beside the van's back (out of its body), on the ground", again ~= nil and rel ~= nil
	and math.abs(rel.X) > T.Beds.sprinter.Width / 2 + 1 and math.abs(rel.Z - truck.chassis.CFrame:PointToObjectSpace(cargoBack.WorldPosition).Z) < 3
	and math.abs(again.Position.Y - 3) < 1e-6
	and flatDistance(again.Position, cargoBack.WorldPosition) < 10, rel and `{rel.X}, {rel.Y}, {rel.Z} at {again.Position.X}, {again.Position.Y}, {again.Position.Z}`)
local toBack = V3(cargoBack.WorldPosition.X - again.Position.X, 0, cargoBack.WorldPosition.Z - again.Position.Z).Unit
check("…looking at the back doors", again.LookVector:Dot(toBack) > 0.95, `{again.LookVector.X}, {again.LookVector.Y}, {again.LookVector.Z}`)
truck.wrecked = true
local out = Moving.respawnAt(ann)
check("…the van wrecked: 6 studs out of the house's front door (SandboxMap.House.door), looking out", out ~= nil
	and flatDistance(out.Position, V3(House.door.x, 0, House.door.z - 6)) < 1e-6 and math.abs(out.Position.Y - House.door.y - 3) < 1e-6 and out.LookVector.Z < -0.99, out and out.Position)
truck.wrecked = false
check("…off a move: nil (home, the plot's spawn)", Moving.respawnAt(bob) == nil and Moving.respawnAt(cid) == nil)
check("the van's prompts say Sprinter (or the car's name), and a Load for the walk-in bay", promptIn(truck.model, "Load") ~= nil
	and truck.chassis:FindFirstChild("MoveLoadBay") ~= nil and truck.chassis:FindFirstChild("MoveTakeOut") ~= nil)

-- The house: the front door, the curb -------------------------------------------------------------------------------------------

local enter = promptIn(frontDoor, "Enter house")
check("Enter house on the map's front door (SandboxDoor), the move's own", enter ~= nil and enter:GetAttribute("MoveOwner") == 11)
local facing = V3(0, 0, -1) -- (House.door yaw 0: out to the road, north)
local outside = V3(House.door.x, House.door.y + 3, House.door.z) + facing * 3
E.place(ann, outside)
trigger(enter, ann)
local origin = E.interiors[1]
check("…into the interior", (E.rootOf(ann).Position - origin.Position).Magnitude < 6, E.rootOf(ann).Position)
local cameIn, ins = lastTold("enter")
check("8.2: Moving.onEnterHouse: Ann came into her move's house", ins == 1 and cameIn.player == ann and cameIn.facts.owner == ann, ins)
check("9.7 the truck at the house's curb already: its nose to the road, its back to the door", flatDistance(truck.chassis.Position, V3(House.curb.x, 0, House.curb.z)) < 1
	and truck.chassis.CFrame.LookVector.Z < -0.99, truck.chassis.Position)
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
check("…its back doors toward the house", cargoDoor.WorldPosition.Z > truck.chassis.Position.Z)

-- Carry and load at the back doors ---------------------------------------------------------------------------------------------

local lamp = newItem(1)
do -- 9.x loot: Moving's hook (server/Loot.luau) put each piece's rarity, stars and value on its model, and the tag
	local rarity, piece = lamp:GetAttribute("Rarity"), newItem(2)
	check("9.x loot: the house's pieces carry their rarity, stars and value and the loot tag (Normal: their own)", rarity == "common" and lamp:GetAttribute("Stars") == 1
		and lamp:GetAttribute("Value") == E.items.lamp.value and lamp:GetAttribute("Tag_" .. Config.Loot.Tag) == true and piece:GetAttribute("Rarity") == "uncommon", rarity)
end
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
check("at the open back with the lamp: the doors' Load (the bay's waits; 8.8: no hold, for anybody)", load.Enabled and not bayLoad.Enabled
	and load.HoldDuration == 0 and bayLoad.HoldDuration == 0 and load:GetAttribute("MoveQuick") == nil and string.find(load.ActionText, "Lamp", 1, true) ~= nil
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
Config.MoveHelper.WaitForHelper = false -- (10.1: Danny is always with you; his call is movehelper_runtime_test's: here the sofa is dragged alone)
trigger(promptIn(sofa, "Lift"), ann)
Config.MoveHelper.WaitForHelper = true
check("a two-person Lift without his call (WaitForHelper off): a drag alone (no call)", ann.Character:GetAttribute("MoveCarry") == 3
	and ann:GetAttribute("MoveHelperCall") == nil and MoveHelper.find(ann).call == nil)
step()
E.place(ann, origin.Position + V3(0, 3, 1))
trigger(promptIn(workspace, "Leave house"), ann)
E.place(ann, truck.chassis.CFrame * V3(BED.Width / 2 + 3, 3, cz)) -- (beside the van, by its side wall)
step()
trigger(bayLoad, ann)
check("beside the van (outside the bay), the back shut: no Load", ann.Character:GetAttribute("MoveCarry") == 3 and stateOf(ann, 3).state == "carried")
E.Net.get("PutDown").OnServerEvent:Fire(ann)

-- 9.7 no drive home: the truck in the owner's plot unloads nothing during a run --------------------------------------------------

park(truck, plot1.vanSpot)
step()
check("9.7 a run's truck at the owner's plot (it never drives there: an admin's teleport): no trip, nothing stored", #E.collected == 0
	and E.last(ann, "Moving", "state").a.trips == 0)
park(truck, House.curb)
step()

-- FINISH at the truck: everything in it goes home, into the loader's stock --------------------------------------------------------

local value = E.items.lamp.value * stateOf(ann, 1).condition + E.items.tv.value * stateOf(ann, 2).condition
E.request(ann, "finish")
check("FINISH: everything in the truck goes home at once, into Ann's stock (Collection.add: its item, variant, condition, name)", #E.collected == 2
	and E.collected[1].player == ann and E.collected[2].player == ann and Moving.busy(ann) == nil)
local lampIn, tvIn = E.collected[1].entry, E.collected[2].entry
check("…with its item, variant, condition and name", lampIn.item == "lamp" and lampIn.name == "Lamp" and lampIn.variant == 3 and type(lampIn.condition) == "number"
	and tvIn.item == "tv" and tvIn.name == "TV" and tvIn.variant == 4 and type(tvIn.condition) == "number", `{lampIn.item} {lampIn.variant} {lampIn.condition}`)
do -- 9.x loot: the run's end stores each piece with its house's roll (Collection.add's rarity)
	check("9.x loot: …each with its rarity (the lamp Common, the TV Uncommon)", lampIn.rarity == "common" and tvIn.rarity == "uncommon", `{lampIn.rarity} {tvIn.rarity}`)
end
check("…the pieces leave the truck (their models go)", lamp.destroyed == true and tv.destroyed == true)
check("…no pay per piece, no money, no XP (the warehouse earns)", #E.money == 0 and #E.xp == 0)
local trip, trips = lastTold("trip")
check("8.2: Moving.onTrip: the run's one trip home, its 2 pieces stored, the truck empty", trips == 1 and trip.player == ann and trip.facts.trips == 1
	and trip.facts.pieces == 2 and trip.facts.stored == 2 and trip.facts.home == 2 and trip.facts.out == 0 and trip.facts.value > 0, trips)
local runEnd = runEnds[#runEnds]
check("9.7 Moving.onRunEnd (server/Runs.luau's results card): the host, the house, Normal, done, its 2 pieces each with its value and whose stock it went into",
	#runEnds == 1 and runEnd.host == ann and runEnd.facts.house == House.id and runEnd.facts.difficulty == "normal" and runEnd.facts.phase == "done"
	and #runEnd.facts.pieces == 2 and runEnd.facts.pieces[1].to == ann.UserId and runEnd.facts.pieces[2].to == ann.UserId
	and math.abs(runEnd.facts.pieces[1].value + runEnd.facts.pieces[2].value - value) < 1e-6 and runEnd.facts.crew[1] == ann, runEnd and runEnd.facts.phase)
check("…no Moving result card (the run's is Runs'), the move's HUD closed", E.last(ann, "Moving", "result") == nil and E.last(ann, "Moving", "state").a == nil)
local ended, ends = lastTold("finish")
check("8.2: Moving.onFinish: the owner, done by FINISH (\"finish\"), 2 pieces home", ends == 1 and ended.player == ann
	and ended.facts.phase == "done" and ended.facts.event == "deliver" and ended.facts.home == 2 and ended.facts.total == 6 and ended.facts.left > 0
	and ended.facts.minutes >= 0, ended and howOf(ended))
check("…the analytics' MoveDone", (function()
	for _, entry in E.tracked do
		if entry.name == "event" and entry.args[2] == "MoveDone" and entry.args[4] == House.id then
			return true
		end
	end
	return false
end)())
check("…the run is over: the interior gone, the van's prompts gone (the bay's too), nobody on it", E.destroyed == 1 and truck.chassis:FindFirstChild("MoveLoadBay") == nil
	and promptIn(truck.model, "Load") == nil and ann:GetAttribute("MoveWith") == nil and enter.destroyed == true)

-- A new house after something came home; FINISH with nothing loaded; the admin --------------------------------------------------

-- The van at the house of the player's move now, at its curb (its nose the curb's way).
local function parkAt(van: any, player: any)
	local h = houseNow(player)
	park(van, { x = h.curb.x, z = h.curb.z, yaw = h.curb.yaw })
end
local function loadOne(spot: number, action: string?)
	local h = houseNow(ann)
	E.place(ann, outsideOf(h))
	trigger(promptIn(doorOf[h.id], "Enter house"), ann)
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
-- 10.6: a run on the house of `player`'s card (Moving.houseOf: its seed kept while nothing came home; none yet: the
-- farmstead), the van parked at its curb first, as server/Runs.luau parks it (Moving.parkVan); nil: it started.
local function cardRun(player: any, difficulty: string?): string?
	local h = Moving.houseOf(player) or House
	Moving.parkVan(player, h.curb, false)
	park(E.cars[player], h.curb)
	return Moving.startRun(player, h.id, difficulty or "normal")
end
local planned = #seeds
check("the next run on the farmstead: a new seed (the house refilled: 8.3 economy, the run brought pieces home)", Moving.startRun(ann, House.id, "easy") == nil
	and #seeds == planned + 1 and seeds[#seeds] ~= firstSeed and built[2] == seeds[#seeds])
step()
check("…at Easy: its clock the farmstead's × Easy's time", math.abs(E.last(ann, "Moving", "state").a.endsAt - (E.now + F.Time * Config.Runs.Difficulties[1].time)) < 1e-6
	and Config.Runs.Difficulties[1].id == "easy")
local nothingAt = #runEnds
E.request(ann, "finish")
check("FINISH with nothing loaded: called off (nothing home), the seed kept", runEnds[#runEnds].facts.phase == "cancelled" and #runEnds == nothingAt + 1
	and Moving.busy(ann) == nil and #E.collected == 2)
check("…the next run there: the same seed (no reroll by calling off)", Moving.startRun(ann, House.id, "normal") == nil and built[#built] == built[2])
check("admin: time leaves one minute", string.find(Moving.admin(ann, "time"), "minute", 1, true) ~= nil and E.last(ann, "Moving", "state") ~= nil)
step()
check("…its clock", math.abs(E.last(ann, "Moving", "state").a.endsAt - (E.now + 60)) < 1e-6)
local marched = E.marched
check("admin: horde (the house without one keeps its clock)", string.find(Moving.admin(ann, "horde"), "horde", 1, true) ~= nil
	and math.abs(E.last(ann, "Moving", "state").a.endsAt - (E.now + 60)) < 1e-6)
step(T.Horde.Every + 0.1)
check("…the horde marches on the house", E.marched > marched)
parkAt(truck, ann)
loadOne(4)
check("…the clock in the truck", stateOf(ann, 4).state == "truck")
E.now += 61
step()
check("9.7 the clock runs out: the run ends, what was in the truck went home (late)", Moving.busy(ann) == nil and #E.collected == 3 and E.collected[3].entry.item == "clock"
	and runEnds[#runEnds].facts.phase == "late" and string.find(runEnds[#runEnds].facts.why, "Time", 1, true) ~= nil, runEnds[#runEnds].facts.phase)
check("admin: the run's end (Moving.endRun, the Runs group's END RUN): nothing home, called off cleanly", cardRun(ann) == nil and Moving.endRun(ann, "Ended by the admin")
	and runEnds[#runEnds].facts.phase == "cancelled" and Moving.busy(ann) == nil and E.destroyed == E.built)
check("8.2: …onFinish: cancelled, nothing home, \"admin\"", (lastTold("finish")).facts.phase == "cancelled" and (lastTold("finish")).facts.home == 0
	and howOf((lastTold("finish"))) == "admin", howOf((lastTold("finish"))))

-- A refusing collection; the horde and roamers switched on -----------------------------------------------------------------------

S.Horde, S.Roam = true, 2
check("(Bob's run)", cardRun(bob) == nil)
local bobSeed = built[#built] -- (8.3 economy: Bob's house, kept while his runs bring nothing home)
local van = E.cars[bob]
step()
check("…its clock 25 minutes, the horde switched on at HordeAt", E.last(bob, "Moving", "state").a.hordeAt == E.last(bob, "Moving", "state").a.endsAt - S.HordeAt)
check("six houses: Bob's first card: the farmstead", houseNow(bob) == House, houseNow(bob).id)
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
E.now += F.Time - S.HordeAt + 1
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
step()

-- 8.0.1: the words -------------------------------------------------------------------------------------------------------------

E.request(bob, "giveup")
local bobEnd = runEnds[#runEnds].facts
-- (8.2 e2e: the refused piece never came home, it is lost: so this GIVE UP calls off a run with nothing home)
check("a Collection.add that refuses (no save yet): the run's end says so", heard(bob, "could not be stored") and #E.collected == 3, #E.collected)
E.refuse = false
check("8.2: the piece the warehouse refused is lost, not home (the end's facts and the tasks never count it)", #bobEnd.pieces == 0 and bobEnd.phase ~= "done",
	bobEnd.phase)
check("8.0.1: GIVE UP: \"You called it off\" (no Wall), no pay, no XP", string.find(bobEnd.why, "You called it off", 1, true) == 1
	and string.find(bobEnd.why, "Wall", 1, true) == nil and #E.money == 0 and #E.xp == 0, bobEnd.why)
check("8.2: …onFinish: Bob's, \"giveup\"", (lastTold("finish")).player == bob and howOf((lastTold("finish"))) == "giveup", howOf((lastTold("finish"))))
local plansBefore = #seeds

check("8.3 economy: no reroll: Bob's GIVE UP with nothing home kept his house: his next run is the same one (no new plan)", (function(): boolean
	local ok = cardRun(bob) == nil and #seeds == plansBefore
	Moving.endRun(bob)
	return ok
end)(), #seeds - plansBefore)

-- the host leaves with a load in the truck: the crew hears that it went home
E.crew[ann] = { cid }
check("(Ann's run with Cid in her party)", cardRun(ann) == nil)
truck = E.cars[ann] -- (the run's own van, parked at the curb for it)
cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
E.place(cid, outsideOf(houseNow(ann)))
step()
loadOne(1)
check("(the lamp in the truck)", stateOf(ann, 1).state == "truck", E.lastNotice(ann))
E.place(cid, truck.chassis.Position + V3(4, 1, 0))
local leftAt = #E.messages
E.leave(ann)
local cidEnd = runEnds[#runEnds].facts
check("8.0.1: the host left: the crew hears what was in the truck went home (no Wall)", heard(cid, "What was in the truck went home", leftAt)
	and not heard(cid, "Wall", leftAt) and cidEnd.phase == "done" and cidEnd.why == "Ann left the game: what was in the truck went home", cidEnd.why)
check("8.2: …onFinish: Ann's, \"left\", the crew of two", (lastTold("finish")).player == ann and howOf((lastTold("finish"))) == "left"
	and (lastTold("finish")).facts.crew == 2, howOf((lastTold("finish"))))
E.clock += T.Doors.Shut + 0.1
Moving.doors() -- (the front door's leaf Ann's trip opened: shut again once nobody wants it)

-- 8.1 walk-in doors in the sandbox (the owner: "no E at the house, neither in nor out"): the chalet's front door (the map's
-- SandboxDoor part) walked through both ways, after the dwell, facing it; out 4 studs from the door facing the road; no
-- way straight back; its doormat on the garden path in front of it; the E prompts off. 8.3 the big move: its back door
-- (House.back, in the back wall) a second way in, its own doormat (the fake plan has one way out: in to its entry). 8.3
-- the doors swing: the house's leaves (the map's, DoorLeaf) found and tagged at the move's start, shut; swung open as
-- Bob walks up to a door, the trip after it has been open Open s; shut again Shut s after its zone emptied.
do
	local D = T.Doors
	local THROUGH = math.max(D.Dwell, D.Open) + 0.01 -- (8.3: in the zone facing the door Dwell s, its leaf open Open s)
	check("(Bob's run)", cardRun(bob) == nil)
	check("8.3 economy: …and his next move is built in that same house (its seed kept)", built[#built] == bobSeed, `{built[#built]} {bobSeed}`)
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
	check("8.3 the map's door is the house's leaf: tagged for the clients (DoorLeaf), shut", frontDoor:GetAttribute("Tag_DoorLeaf") == true
		and frontDoor:GetAttribute("DoorOpen") ~= true, `{frontDoor:GetAttribute("Tag_DoorLeaf")} {frontDoor:GetAttribute("DoorOpen")}`)
	stand(bob, foot + up + facing * 2, -facing)
	step(0.1)
	check("walking up to the chalet's door: not in before the dwell, its leaf swinging open (DoorOpen)", not isIn(bob) and frontDoor:GetAttribute("DoorOpen") == true)
	step(THROUGH)
	check("…in after it (no E), facing into the house", isIn(bob) and E.rootOf(bob).CFrame.LookVector:Dot(into) > 0.99)
	step(D.Shut + 0.05)
	check("8.3 …its leaf shut again Shut s after its zone emptied", frontDoor:GetAttribute("DoorOpen") == false)
	stand(bob, exitAt + into * 8, -into)
	step(0.1)
	step(D.Rearm)
	stand(bob, exitAt + into * 1, -into)
	step(0.1)
	step(THROUGH)
	check("walked out by the doorway inside: 4 studs out of the chalet's door, facing the road", not isIn(bob)
		and math.abs(flatDistance(E.rootOf(bob).Position, foot) - 4) < 0.5 and E.rootOf(bob).CFrame.LookVector:Dot(facing) > 0.99, E.rootOf(bob).Position)
	stand(bob, foot + up + facing * 2, -facing)
	step(0.1)
	step(THROUGH)
	step(0.5)
	check("…turned straight back to the door: shut for Rearm s (no ping-pong)", not isIn(bob))
	step(D.Rearm)
	step(THROUGH)
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
	step(THROUGH)
	check("(out by the front door again)", not isIn(bob))
	step(D.Rearm)
	check("8.3 the back door's leaf (the map's BackLeaf) tagged for the clients at the move's start, shut", backLeaf:GetAttribute("Tag_DoorLeaf") == true
		and backLeaf:GetAttribute("DoorOpen") ~= true)
	stand(bob, back + up + backFacing * 6, -backFacing)
	step(0.1)
	check("…at the back door, not in before the dwell; walking up to it, its leaf swinging open (DoorOpen)", not isIn(bob)
		and backLeaf:GetAttribute("DoorOpen") == true)
	local since = #E.messages
	stand(bob, back + up + backFacing * 2, -backFacing)
	step(0.1)
	step(THROUGH)
	check("…walked into the back door's zone facing it: in (no E)", isIn(bob))
	local fadeOut, fadeIn: any, any = nil, nil
	for index = since + 1, #E.messages do
		local m = E.messages[index]
		if m.player == bob and m.kind == "fade" then
			if m.a == "out" then
				fadeOut = m
			else
				fadeIn = m
			end
		end
	end
	local arrival = if fadeIn then fadeIn.c else nil
	check("8.3 …the back door's trip as the front's: the fade out (FadeOut s), the fade in (FadeIn s) with where Bob is and the way he faces there",
		fadeOut ~= nil and fadeOut.b == D.FadeOut and fadeIn ~= nil and fadeIn.b == D.FadeIn and type(arrival) == "table"
		and (arrival.at - E.rootOf(bob).Position).Magnitude < 1e-6 and arrival.look:Dot(E.rootOf(bob).CFrame.LookVector) > 0.99 and arrival.dark == D.Dark)
	stand(bob, exitAt + into * 12, into)
	step(D.Shut + 0.05)
	check("…its leaf shut again Shut s after the trip", backLeaf:GetAttribute("DoorOpen") == false)
	Moving.endRun(bob)
	check("the move over: both doormats hidden again (no move at the house)", mat.Transparency == 1 and backMat.Transparency == 1)
end

-- 8.5 walking through (the owner: "the doors should open when I'm at them, so it doesn't feel like I bumped into the
-- door, but I keep walking smoothly, and then the transition"; Config.Moving.Doors Lead, Cross, Ahead): the leaf opens
-- as Bob comes at the door, walking at it in its approach whichever way he looks, from farther out only at a run (his
-- walk through its doorway within Lead s), never as he walks past it; walking into the doorway is the trip at once (one
-- look, no dwell, his walk carried on), in by the front door, out by the doorway inside, in by the back door; walking
-- back out of the hall or past the doorway goes nowhere; standing at the door facing it, the 8.3 dwell as before. 8.5.1
-- (the owner: "I'd like them to open nicely"): walking in from just beside a shut door, its leaf only starting to
-- swing, the fade waits until it has swung most of the way (Seen × Open s: WalkIn.swung), then in, still walking.
do
	local D = T.Doors
	check("(Bob's run for walking through)", cardRun(bob) == nil)
	step()
	local o = E.interiors[#E.interiors]
	local root = E.rootOf(bob)
	local foot = V3(House.door.x, House.door.y, House.door.z)
	local back = V3(House.back.x, House.back.y, House.back.z)
	local backFacing = V3(0, 0, 1) -- (House.back yaw 180: out to the south)
	local up = V3(0, Config.Furniture.EntryUp, 0)
	local into = V3(0, 0, 1) -- (the fake plan's +Z)
	local exitAt = o * V3(0, 0, 0.5) + up
	local side = V3(1, 0, 0)
	local walk, run = Config.Movement.Walk, Config.Movement.Sprint
	-- Bob at `at` looking along `look`, walking at `v` (studs/s, flat: as Roblox reports a walking body's root)
	local function go(at: any, look: any, v: any)
		root.CFrame = M.CFrame.lookAt(at, at + look)
		root.AssemblyLinearVelocity = v
	end
	local function isIn(): boolean
		return (root.Position - o.Position).Magnitude < 100
	end
	local function shut(leaf: any): boolean
		go(foot + up + facing * 40, facing, V3(0, 0, 0))
		step(D.Shut + 0.05)
		return leaf:GetAttribute("DoorOpen") ~= true
	end
	go(foot + up + facing * 40, facing, V3(0, 0, 0))
	step(0.1)
	step(D.Rearm) -- (the last move's end took him out of the house: its re-arm)
	check("(the front door's leaf shut, Bob far from it)", shut(frontDoor))
	-- walking at it in its approach, looking along the house (not at the door): open
	go(foot + up + facing * (D.Approach - 1), side, -facing * walk)
	step(0.1)
	check("8.5 walking at the door in its approach looking along the house (not facing it squarely): its leaf opens, not in", frontDoor:GetAttribute("DoorOpen") == true and not isIn())
	check("(…shut again)", shut(frontDoor))
	-- walking past it along the house, 2 studs out of the door: nothing
	go(foot + up + facing * 2 - side * 2, side, side * walk)
	step(0.01)
	check("8.5 walking past the door along the house (2 studs out, through its zone): its leaf stays shut, not in", frontDoor:GetAttribute("DoorOpen") ~= true and not isIn())
	-- farther than its approach: at a walk nothing yet, at a run (through its doorway within Lead s) open
	local far = D.Approach + 6
	check("(farther than its approach, within a run's Lead, beyond a walk's)", far > walk * D.Lead and far < run * D.Lead)
	go(foot + up + facing * far + side * 1.5, -facing, -facing * walk)
	step(0.01)
	check("8.5 walking at the door from farther than its approach: not yet open", frontDoor:GetAttribute("DoorOpen") ~= true)
	go(foot + up + facing * far + side * 1.5, -facing, -facing * run)
	step(0.01)
	check("8.5 …running at it from there (through its doorway within Lead s): its leaf opens already", frontDoor:GetAttribute("DoorOpen") == true and not isIn())
	step(D.Open) -- (8.5.1: his run there: the leaf swung all the way meanwhile)
	-- walking through: a stud out of the door, walking in: in at the first look (no dwell), still walking, facing in
	local since = #E.messages
	go(foot + up + facing * 1, -facing, -facing * walk)
	step(0.01)
	local fadeOut, fadeIn: any, any = nil, nil
	for index = since + 1, #E.messages do
		local m = E.messages[index]
		if m.player == bob and m.kind == "fade" then
			if m.a == "out" then
				fadeOut = fadeOut or m
			else
				fadeIn = m
			end
		end
	end
	local v = root.AssemblyLinearVelocity
	check("8.5 walking into the doorway (a stud out of the door, at a walk): in at the first look, no dwell; the fade out and in as ever",
		isIn() and fadeOut ~= nil and fadeOut.b == D.FadeOut and fadeIn ~= nil and fadeIn.b == D.FadeIn and frontDoor:GetAttribute("DoorOpen") == true)
	check("…he comes in still walking at his walk, facing into the house", v ~= nil and math.abs(v:Dot(into) - walk) < 1e-6 and root.CFrame.LookVector:Dot(into) > 0.99,
		v and v:Dot(into))
	-- the way out inside, walking through: out of the zone, Rearm, then a stud in front of the doorway walking out
	go(exitAt + into * 8, -into, V3(0, 0, 0))
	step(0.1)
	step(D.Rearm)
	step(D.Open) -- (8.5.1: facing it in its approach, its leaf swung open meanwhile: his walk up to it)
	go(exitAt + into * 1, -into, -into * walk)
	step(0.01)
	check("8.5 out by walking through the doorway inside (a stud in front of it, at a walk): out at the first look, 4 studs out of the door, facing the road, still walking",
		not isIn() and math.abs(flatDistance(root.Position, foot) - 4) < 0.5 and root.CFrame.LookVector:Dot(facing) > 0.99
		and math.abs(root.AssemblyLinearVelocity:Dot(facing) - walk) < 1e-6, root.Position)
	-- in its dark hall walking back out (turned round), and walking along the doorway: nowhere
	go(foot + up + facing * 8, facing, V3(0, 0, 0))
	step(0.1)
	step(D.Rearm)
	go(foot + up - facing * 3, facing, facing * walk)
	step(0.01)
	check("8.5 in the door's dark hall walking back out (turned round): not in", not isIn())
	go(foot + up - facing * 0.5 - side * 1, side, side * walk)
	step(0.01)
	check("8.5 …nor walking across the doorway on its threshold", not isIn())
	-- standing at the door facing it (no walk): the 8.3 dwell as before
	go(foot + up + facing * 1, -facing, V3(0, 0, 0))
	step(0.01)
	check("8.5 standing at the door facing it: not in at the first look (the dwell)", not isIn())
	step(math.max(D.Dwell, D.Open) + 0.01)
	check("…in after the dwell (8.3)", isIn())
	-- the back door, walking through it from outside: out by the doorway inside first (walking), round to the back
	go(exitAt + into * 8, -into, V3(0, 0, 0))
	step(0.1)
	step(D.Rearm)
	go(exitAt + into * 1, -into, -into * walk)
	step(0.01)
	check("(out by the front door again, walking)", not isIn())
	go(back + up + backFacing * 30, backFacing, V3(0, 0, 0))
	step(0.1)
	step(D.Rearm)
	check("(the back door's leaf shut)", shut(backLeaf))
	-- 8.5.1 from just beside it, its leaf shut: walking into its doorway, its leaf only starting to swing
	go(back + up + backFacing * 1, -backFacing, -backFacing * walk)
	step(0.01)
	check("8.5 walking at the back door: its leaf opens (8.5.1 since when, the server's time: DoorOpenAt, for a client that first sees it opening)",
		backLeaf:GetAttribute("DoorOpen") == true and backLeaf:GetAttribute("DoorOpenAt") == E.now)
	check("8.5.1 …walking into its doorway from just beside it (its leaf only starting to swing): not yet in, the fade waits for the swing",
		not isIn())
	local waited = 0
	while not isIn() and waited < D.Open do
		go(back + up + backFacing * 1, -backFacing, -backFacing * walk) -- (walking on: the test holds him at the threshold)
		step(0.05)
		waited += 0.05
	end
	check("8.5.1 …in once it has swung most of the way (Seen × Open s, no dwell), still walking", isIn() and waited >= D.Open * D.Seen - 0.06
		and waited <= D.Open * D.Seen + 0.11 and math.abs(root.AssemblyLinearVelocity:Dot(root.CFrame.LookVector) - walk) < 1e-6, waited)
	root.AssemblyLinearVelocity = V3(0, 0, 0)
	Moving.endRun(bob)
end

-- 8.3 economy: no house reroll (server/Moving.luau SB.seeds, by user id): a run called off with nothing home (GIVE UP,
-- the admin's end, the host leaving) keeps its house, so starting, peeking and calling off never fishes for a legendary;
-- a run that brings something home (Ann's above) gives a new one
do
	check("Bob's run ended by the admin with nothing home: the next one is the same house again", cardRun(bob) == nil and built[#built] == bobSeed)
	E.leave(bob)
	check("…he leaves mid-run with nothing home: called off", Moving.busy(bob) == nil)
	local bob2 = E.player(22, "Bob", V3(plot2.spawn.x, 3, plot2.spawn.z))
	E.plots[bob2] = plot2
	check("…back on this server (his user id): his run is the same house (planned again: its facts went when he left)", cardRun(bob2) == nil
		and seeds[#seeds] == bobSeed and built[#built] == bobSeed, `{seeds[#seeds]} {bobSeed}`)
	Moving.endRun(bob2)
end

-- 8.4: the house kept across servers (server/Moving.luau SB.seedOf / SB.keepSeed; server/PlayerData.luau's
-- sandboxHouseSeed, which tests/saving_runtime_test.luau writes to and reads from the DataStore). Dee has a save (a
-- test's own profile, E.profiles: PlayerData.loaded): the seed of the house her card shows goes into it as it is rolled
-- and stays through GIVE UP and her leaving. Joining another server with that save shows the same house: Moving takes a
-- loaded save's seed over anything the server remembers of her, so a join here with the save another server wrote is
-- the join there (a save with another house in it: that house; one a trip spent there: a new house, never the one this
-- server remembered). A trip home drops it from the save; the next card rolls a new one into it.
do
	local function join(save: any): any
		local player = E.player(44, "Dee", V3(plot1.spawn.x, 3, plot1.spawn.z))
		E.plots[player] = plot1 -- (Ann's, free: she left)
		E.profiles[player] = save
		return player
	end
	local function started(player: any): boolean
		return cardRun(player) == nil
	end
	local dee = join({ money = 5000 }) -- (a save without a house yet)
	local save = E.profiles[dee]
	check("8.4 Dee's run (her save read, no house in it): a house rolled, built, its seed in her save (her next save writes it)", started(dee) and (function(): boolean
		local first = built[#built]
		return save.sandboxHouseSeed == first and first >= 1 and first <= S.Seeds and first == math.floor(first)
	end)())
	local first = built[#built]
	E.request(dee, "giveup")
	check("…GIVE UP with nothing home: called off, the seed still in her save", Moving.busy(dee) == nil and #runEnds[#runEnds].facts.pieces == 0
		and save.sandboxHouseSeed == first)
	E.leave(dee)
	local wrote = table.clone(save) -- (what her leave save writes)
	check("…she leaves: her save keeps it", wrote.sandboxHouseSeed == first)
	-- another server, the same save
	local dee2 = join(table.clone(wrote))
	check("8.4 she joins another server with that save: the same house (the save's seed)", started(dee2) and built[#built] == first)
	Moving.endRun(dee2)
	E.leave(dee2)
	-- the save as another server left it: there she rolled a new house into it, or a trip spent hers
	local other = if first == S.Seeds then first - 1 else first + 1
	local dee3 = join({ money = 5000, sandboxHouse = House.id, sandboxHouseSeed = other })
	check("…a save with another house in it (rolled on another server): that house, not the one this server remembered", started(dee3) and built[#built] == other)
	Moving.endRun(dee3)
	E.leave(dee3)
	local dee4 = join({ money = 5000 })
	local spent = E.profiles[dee4]
	check("…a save whose house a trip spent on another server (none in it): a new house, never the one this server remembered",
		started(dee4) and built[#built] ~= first and built[#built] ~= other and spent.sandboxHouseSeed == built[#built])
	-- a trip home here spends it: out of the save, a new house next
	local spentSeed = built[#built]
	local car = E.cars[dee4]
	step()
	E.place(dee4, outside)
	trigger(promptIn(frontDoor, "Enter house"), dee4)
	local piece = newItem(1)
	E.place(dee4, piece.PrimaryPart.Position + V3(1, 0, 0))
	trigger(promptIn(piece, "Pick up"), dee4)
	step()
	E.place(dee4, E.interiors[#E.interiors].Position + V3(0, 3, 1))
	trigger(promptIn(workspace, "Leave house"), dee4)
	car.model:SetAttribute("BackOpen", true)
	E.place(dee4, car.chassis:FindFirstChild("CargoDoor").WorldPosition + V3(0, 0, 2))
	step()
	trigger(promptIn(car.model, "Load"), dee4)
	step()
	E.request(dee4, "finish")
	check("8.4 FINISH brings the piece into her warehouse: the house spent, its seed out of her save", #runEnds[#runEnds].facts.pieces == 1
		and spent.sandboxHouseSeed == nil, `{#runEnds[#runEnds].facts.pieces} {spent.sandboxHouseSeed}`)
	check("…her next run: a new house, its seed in her save", started(dee4) and built[#built] ~= spentSeed and spent.sandboxHouseSeed == built[#built])
	Moving.endRun(dee4)
	E.leave(dee4)
	-- a save not read (a fresh profile, never saved: Studio without a DataStore): this server's memory of her as before
	local dee5 = join(nil)
	local remembered = spent.sandboxHouseSeed
	check("…without a save read: this server's own memory of her (8.3 economy: the same house on a rejoin here)", started(dee5) and built[#built] == remembered)
	Moving.endRun(dee5)
	E.leave(dee5)
end

-- Done is quiet: nothing the sandbox's players heard (their notices) or read at a run's end (its words) mentions the Wall,
-- pay or XP; Danny's lines name no Wall.
local function noisy(text: string): boolean
	return string.find(text, "Wall", 1, true) ~= nil or string.find(string.lower(text), "%f[%a]pa[iy][ds]?%f[%A]") ~= nil
		or string.find(text, "%f[%a]XP%f[%A]") ~= nil
end
local loud: { string } = {}
local results = 0
for _, m in E.messages do
	if m.remote == "Notice" and type(m.kind) == "string" and noisy(m.kind) then
		table.insert(loud, m.kind)
	end
end
for _, ended in runEnds do
	results += 1
	if noisy(tostring(ended.facts.why)) then
		table.insert(loud, `end: {ended.facts.why}`)
	end
end
for _, text in E.said do
	if string.find(text, "Wall", 1, true) then
		table.insert(loud, text)
	end
end
check("8.0.1: done is quiet: no notice, run's end (of " .. results .. ") or Danny's line in the sandbox mentions the Wall, pay or XP", #loud == 0 and results >= 4,
	table.concat(loud, " | "))

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
