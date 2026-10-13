-- 7.0, the depot's helper ("Danny from the depot"): the real server/Moving.luau and server/MoveHelper.luau in the Luau
-- CLI (tests/run_tests.py builds MovingServer.luau and MoveHelperServer.luau on tests/runtime/MovingRuntime.luau's
-- fakes). The runtime has no physics and no pathfinding: his walk here is a straight step of speed × dt (useMover), and
-- a carried thing is moved with its carrier by the test (a weld is only a record). A solo move: Danny comes with the
-- truck; the player lifts the sofa and he takes the other end (the two-person walk), comes through the door with it,
-- lets go when left behind over HelpWait s (the player drags it alone) and comes back for a new lift, and the player
-- loads it; he carries the box of memories (★ first) and then the lamp to the truck on his own; he never
-- takes a "both" or a pair thing alone; the shut back, a bite, his death and comeback, running from a zombie, the orders
-- (Help me: he follows you through the door), the truck parked far off, the crew growing (he goes) and Duo, the end of
-- the move; a second move where the room goes while he carries his thing ("Truck's full, boss.": set down beside the
-- truck), a third where nothing he may carry fits.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local Map = require("./Map")
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

local T = Config.Moving
local H = Config.MoveHelper
local WALK = Config.Movement.Walk
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace

local home = Map.home(T.Contracts[1].home) :: any
local door = V3(home.door.x, 3, home.door.z)
local facing = V3(home.facing.x, 0, home.facing.z)
local outside = door + facing * 3
E.truckAt = V3(home.door.x + 30, 2, home.door.z - 20) -- (placeNear's spot: the truck is at the house at once, its back
-- 30 studs from the front door)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (the move's own roamers far off: this test brings its zombie itself)
end

-- His walk: straight toward the point, speed × dt a step (the last speed asked is kept to check it).
local lastSpeed = 0
local walker = {
	move = function(body: any, to: any, speed: number, dt: number)
		local root = body.root
		local here = root.Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		local length = way.Magnitude
		if length > 1e-6 then
			local step = math.min(length, speed * dt)
			root.CFrame = M.CFrame.new(here.X + way.X / length * step, here.Y, here.Z + way.Z / length * step)
		end
		body.walking = true
		lastSpeed = speed
	end,
	halt = function(body: any)
		body.walking = false
	end,
}
MoveHelper.useMover(walker)

local sol = E.player(44, "Sol", V3(Map.Depot.x, 3, Map.Depot.z))
Moving.useArt(E.art)
Moving.start()

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
local function itemModel(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
local function stateOf(spot: number): any
	local view = E.last(sol, "Moving", "state")
	for _, item in (view and view.a and view.a.items) or {} do
		if item.spot == spot then
			return item
		end
	end
	return nil
end
-- A carried thing stays in front of its carrier (the weld, in Roblox).
local function follow(model: any, player: any)
	model:PivotTo(E.rootOf(player).CFrame * M.CFrame.new(0, 0, -3))
end
local danny: any = nil
-- What he carries stays in front of him (the weld, in Roblox).
local function carryAlong()
	local h = danny
	if not h or not h.body then
		return
	end
	local spot, role = Rules.holding(h.s.move, h.id)
	local model = if spot and role == "carrier" then itemModel(spot) else nil
	if model then
		model:PivotTo(h.body.root.CFrame * M.CFrame.new(0, 0, -1.5))
	end
end
-- Steps of 0.1 s (his loop's), the move's tick every other one; until `done` (true when it came), or `seconds` long.
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1) do
		E.clock += 0.1
		MoveHelper.step(0.1)
		carryAlong()
		if index % 2 == 0 then
			Moving.step()
		end
		if done and done() then
			Moving.step()
			return true
		end
	end
	Moving.step()
	return done == nil
end
local function distance(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Danny comes ----------------------------------------------------------------------------------------------------------------

local started = Moving.admin(sol, "start")
check("a solo move starts", string.find(started, "started", 1, true) ~= nil, started)
local truck = E.cars[sol]
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
Moving.step()
danny = MoveHelper.find(sol)
check("Danny comes with a crew of one", danny ~= nil and danny.body ~= nil and danny.mode == "carry")
local body = danny.body
local npc = body.model
check("his body: Danny, ZDC Moving, his id in the rules (no player's)", npc.Name == "Danny" and npc:GetAttribute("MoveHelper") == danny.id and danny.id < -1000000
	and body.humanoid.MaxHealth == H.Health and body.humanoid.Health == H.Health)
check("…at the truck's back", distance(body.root.Position, cargoDoor.WorldPosition) < 8, distance(body.root.Position, cargoDoor.WorldPosition))
check("he says: Got your back!", E.saidSince("Danny from the depot. Got your back!", 0))
check("the player hears it", string.find(E.lastNotice(sol), "Danny from the depot joins", 1, true) ~= nil, E.lastNotice(sol))
check("the orders' strip: MoveHelper = carry, what he does", sol:GetAttribute("MoveHelper") == "carry" and type(sol:GetAttribute("MoveHelperDoing")) == "string")
check("his name in the rules' list", MoveHelper.nameOf(danny.id) == "Danny" and MoveHelper.nameOf(44) == nil)
local targets = E.Zombies.extraTargets()
local hunted = false
for _, t in targets do
	if t.humanoid == body.humanoid and t.player == sol then
		hunted = true
	end
end
check("the zombies go after him too (Zombies.extraTargets)", hunted)

-- The sofa: lifted together --------------------------------------------------------------------------------------------------

local site = workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge")
local enter = promptIn(site, "Enter house")
-- 7.0 planning: every move's front door is locked (no keys; Danny waits outside it): solo, Sol switches to the
-- Technician and picks it, then goes back where they were
local function unlock()
	local at = E.rootOf(sol).Position
	E.request(sol, "role", "tech")
	E.place(sol, outside)
	trigger(promptIn(site, "Pick lock"), sol)
	E.place(sol, at)
end
E.place(sol, outside)
unlock()
check("the front door: Sol (the Technician now) picks its lock", sol:GetAttribute("MoveRole") == "tech" and sol:GetAttribute("MoveLocked") == nil)
trigger(enter, sol)
local origin = E.interiors[1]
check("Sol is inside", (E.rootOf(sol).Position - origin.Position).Magnitude < 10)
local sofa = itemModel(3)
E.place(sol, sofa.PrimaryPart.Position + V3(0, 0, -3))
trigger(promptIn(sofa, "Lift"), sol)
local character = sol.Character
check("alone: Sol drags the sofa at 0.35", character:GetAttribute("MoveCarry") == 3 and math.abs((character:GetAttribute("CarrySpeed") or 0) - WALK * 0.35) < 1e-6)
local said = #E.said
local lifted = run(30, function()
	return math.abs((character:GetAttribute("CarrySpeed") or 0) - WALK * 0.8) < 1e-6
end)
check("Danny comes through the door and takes the other end: the two-person walk (0.8)", lifted, character:GetAttribute("CarrySpeed"))
check("…\"Lift on three!\"", E.saidSince("Lift on three!", said))
check("…inside, by the sofa", (body.root.Position - origin.Position).Magnitude < 40 and distance(body.root.Position, sofa.PrimaryPart.Position) < 8)
check("Sol hears it", string.find(E.lastNotice(sol), "Danny took the other end of the Sofa", 1, true) ~= nil, E.lastNotice(sol))
check("the list says who: Sol + Danny", stateOf(3) ~= nil and stateOf(3).by == "Sol + Danny", stateOf(3) and stateOf(3).by)
check("he has no G prompt (only players do)", (function()
	for _, d in sofa:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d:GetAttribute("MoveOnly") == danny.id then
			return false
		end
	end
	return true
end)())
-- out of the door with it: he comes along at Sol's side
local leave = promptIn(workspace, "Leave house")
E.place(sol, origin.Position + V3(0, 3, 1))
trigger(leave, sol)
local back = cargoDoor.WorldPosition + V3(0, 0, 2)
E.place(sol, back)
follow(sofa, sol)
run(0.4)
check("Sol out with the sofa, Danny at his side", (E.rootOf(sol).Position - origin.Position).Magnitude > 1000 and distance(body.root.Position, E.rootOf(sol).Position) < 8
	and character:GetAttribute("MoveCarry") == 3, distance(body.root.Position, E.rootOf(sol).Position))
check("…still two on it", math.abs((character:GetAttribute("CarrySpeed") or 0) - WALK * 0.8) < 1e-6)
-- left behind (stuck: his walk goes nowhere) for HelpWait s: he lets go, Sol drags it alone
MoveHelper.useMover({ move = function() end, halt = function() end })
said = #E.said
for step = 1, 40 do -- (out of his reach after about 15 studs, then over HelpWait s)
	E.place(sol, back + V3(step * 0.6, 0, 0))
	follow(sofa, sol)
	run(0.2)
end
check("left behind over HelpWait s: he lets go, Sol drags the sofa alone (0.35)", character:GetAttribute("MoveCarry") == 3
	and math.abs((character:GetAttribute("CarrySpeed") or 0) - WALK * 0.35) < 1e-6 and E.saidSince("Too quick for me, boss: you drag it.", said)
	and string.find(E.lastNotice(sol), "Danny let go", 1, true) ~= nil, E.lastNotice(sol))
run(1)
check("…and stays off that lift", Rules.holding(danny.s.move, danny.id) == nil and danny.action ~= "help")
MoveHelper.useMover(walker)
E.place(sol, back)
follow(sofa, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
trigger(promptIn(sofa, "Lift"), sol)
said = #E.said
lifted = run(15, function()
	return math.abs((character:GetAttribute("CarrySpeed") or 0) - WALK * 0.8) < 1e-6
end)
check("set down and lifted again: he comes back for it", lifted and E.saidSince("Lift on three!", said))
truck.model:SetAttribute("BackOpen", true)
run(0.4)
local load = promptIn(truck.model, "Load")
trigger(load, sol)
check("Sol loads the sofa: in the truck, both hands free", character:GetAttribute("MoveCarry") == nil and string.find(E.lastNotice(sol), "Sofa", 1, true) ~= nil, E.lastNotice(sol))
run(0.3)
check("…and Danny's hands are free", Rules.holding(danny.s.move, danny.id) == nil)

-- The small things: the box of memories (★) first, then the lamp --------------------------------------------------------------

local loadedAt: { [number]: number } = {}
local carrySpeed = 0
local loadShown = false
local n = 0
run(90, function()
	n += 1
	local spot, role = Rules.holding(danny.s.move, danny.id)
	if spot == 5 and role == "carrier" and danny.action == "deliver" then
		carrySpeed = lastSpeed
		loadShown = loadShown or load.Enabled
	end
	for _, s in { 1, 5 } do
		local item = stateOf(s)
		if item and item.state == "truck" and not loadedAt[s] then
			loadedAt[s] = n
		end
	end
	return loadedAt[1] ~= nil and loadedAt[5] ~= nil
end)
check("Danny carries the box of memories (★) to the truck and loads it", loadedAt[5] ~= nil)
check("…then the lamp", loadedAt[1] ~= nil and loadedAt[5] ~= nil and loadedAt[5] < loadedAt[1], `{loadedAt[5]} {loadedAt[1]}`)
check("…at 0.7 × a player's walk with it", math.abs(carrySpeed - Rules.carrySpeed(WALK, "hand", 3) * 0.7) < 1e-6, carrySpeed)
check("…the truck's Load prompt stays off for what he carries (the back's own E stays free)", not loadShown)
check("Sol hears what he loaded", (function()
	for _, m in E.messages do
		if m.player == sol and m.remote == "Notice" and string.find(tostring(m.kind), "Danny loaded", 1, true) then
			return true
		end
	end
	return false
end)())
run(4)
check("only 'both' and pair things left: he takes none alone", Rules.holding(danny.s.move, danny.id) == nil and stateOf(2).state == "home" and stateOf(4).state == "home"
	and stateOf(6).state == "home")
check("…he waits at the truck", danny.action == "wait" and sol:GetAttribute("MoveHelperDoing") == "Waiting at the truck" and distance(body.root.Position, cargoDoor.WorldPosition) < 8,
	sol:GetAttribute("MoveHelperDoing"))

-- The shut back, a bite ----------------------------------------------------------------------------------------------------

local lamp = itemModel(1)
local unload = promptIn(truck.model, "Unload")
E.place(sol, back)
trigger(unload, sol)
check("Sol takes the lamp back out", character:GetAttribute("MoveCarry") == 1, E.lastNotice(sol))
E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
check("…and sets it down by the house", character:GetAttribute("MoveCarry") == nil)
truck.model:SetAttribute("BackOpen", false)
said = #E.said
local carried = run(30, function()
	return Rules.holding(danny.s.move, danny.id) == 1
end)
check("Danny goes for the lamp", carried)
body.humanoid.Health = 80
body.humanoid.HealthChanged:Fire(80)
run(0.3)
local bitten = stateOf(1)
check("a bite knocks the fragile lamp in his arms", bitten ~= nil and math.abs(bitten.condition - (1 - 20 * T.Damage.PerHp * T.Damage.Fragile)) < 0.011, bitten and bitten.condition)
local shut = run(30, function()
	return E.saidSince("Open the back, boss!", said)
end)
check("the back shut: \"Open the back, boss!\"", shut)
local down = run(H.WaitShut + 5, function()
	return Rules.holding(danny.s.move, danny.id) == nil
end)
check("…WaitShut s later he sets it down beside the truck", down and stateOf(1).state == "ground" and distance(lamp.PrimaryPart.Position, cargoDoor.WorldPosition) < 14,
	distance(lamp.PrimaryPart.Position, cargoDoor.WorldPosition))
run(3)
check("…and leaves it there while the back stays shut", Rules.holding(danny.s.move, danny.id) == nil and stateOf(1).state == "ground")
truck.model:SetAttribute("BackOpen", true)
local inAgain = run(20, function()
	return stateOf(1).state == "truck"
end)
check("the back open: he takes it in", inAgain)

-- Down and back up -----------------------------------------------------------------------------------------------------------

E.place(sol, back)
trigger(unload, sol)
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
carried = run(15, function()
	return Rules.holding(danny.s.move, danny.id) == 1
end)
check("he picks the lamp up again", carried)
danny.s.move.things[1].condition = 1 -- (as good as new again: the bite above and this fall would break it)
local before = 1
said = #E.said
body.humanoid.Health = 0
body.humanoid.HealthChanged:Fire(0)
run(0.3)
check("killed: the lamp falls, knocked", stateOf(1).state == "ground" and stateOf(1).condition < before - 0.1 and Rules.holding(danny.s.move, danny.id) == nil, stateOf(1).condition)
check("…he is down (\"I'll be back!\"), the player hears it", danny.dead and E.saidSince("Ugh... I'll be back!", said)
	and string.find(E.lastNotice(sol), "Danny is down", 1, true) ~= nil and sol:GetAttribute("MoveHelperDoing") == "Down: back at the truck soon")
run(3.2)
check("…his body goes a moment later", npc.Parent == nil and danny.body == nil)
local backUp = run(H.Respawn, function()
	return danny.body ~= nil
end)
check("Respawn s later he is back at the truck", backUp and not danny.dead and distance(danny.body.root.Position, cargoDoor.WorldPosition) < 8 and E.saidSince("Back on my feet!", said))
body = danny.body
npc = body.model
local again = run(20, function()
	return stateOf(1).state == "truck"
end)
check("…and takes the lamp in", again)

-- A zombie: he runs ----------------------------------------------------------------------------------------------------------

local here = body.root.Position
local z = E.Zombies.spawn("walker", here + V3(6, 0, 0), sol)
run(0.2)
check("a zombie near: he runs", danny.action == "flee" and danny.fleeing)
run(1)
local away = distance(body.root.Position, z.root.Position)
check("…away from it", away > 6 + 5, away)
z.dead = true
run(4)
check("…it's gone: he goes back to the truck", danny.action == "wait" and not danny.fleeing)

-- The orders -----------------------------------------------------------------------------------------------------------------

said = #E.said
E.request(sol, "helper", "dance")
check("a wrong order changes nothing", danny.mode == "carry")
E.request(sol, "helper", "wait")
check("WAIT AT TRUCK: the order, the strip, his word", danny.mode == "wait" and sol:GetAttribute("MoveHelper") == "wait" and E.saidSince("Waiting at the truck.", said))
E.request(sol, "helper", "help")
E.place(sol, outside + V3(-3, 0, 0))
local followed = run(15, function()
	return distance(body.root.Position, E.rootOf(sol).Position) <= H.Follow + 2
end)
check("HELP ME: he follows you", followed and danny.mode == "help" and danny.action == "follow" and sol:GetAttribute("MoveHelperDoing") == "Right behind you")
trigger(enter, sol)
local inside = run(15, function()
	return (body.root.Position - origin.Position).Magnitude < 60
end)
check("…through the door too", inside)
E.request(sol, "helper", "carry")
check("SMALL STUFF again", danny.mode == "carry" and sol:GetAttribute("MoveHelper") == "carry")
E.Net.get("MoveLobby").OnServerEvent:Fire(sol, "chat", 2)
check("7.0 planning: \"Need a hand here\" in the quick chat calls him over (HELP ME)", danny.mode == "help" and sol:GetAttribute("MoveHelper") == "help")
E.request(sol, "helper", "carry")

-- The truck parked far off (driven somewhere else), then back by the house -------------------------------------------------------

local parked = truck.chassis.CFrame
truck.chassis.CFrame = M.CFrame.new(Map.Depot.x - 60, 2, Map.Depot.z)
local stayed = body.root.Position
run(3)
check("the truck parked far off, not by the house: he stays where he is (no popping along its way)", distance(body.root.Position, stayed) < 1)
truck.chassis.CFrame = parked
local rejoined = run(20, function()
	return distance(body.root.Position, cargoDoor.WorldPosition) < 8
end)
check("…parked by the house again: he goes to it", rejoined)

-- The crew grows: he goes; Duo ---------------------------------------------------------------------------------------------

local bob = E.player(55, "Bob", outside)
E.crew[sol] = { bob }
Moving.step()
check("a crew of two: Danny heads back (Duo is off)", MoveHelper.find(sol) == nil and npc.Parent == nil and sol:GetAttribute("MoveHelper") == nil
	and string.find(E.lastNotice(sol), "heads back", 1, true) ~= nil)
H.Duo = true
Moving.step()
danny = MoveHelper.find(sol)
check("Duo on: he comes for two as well", danny ~= nil and sol:GetAttribute("MoveHelper") == "carry" and bob:GetAttribute("MoveHelper") == "carry")
H.Duo = false
E.crew[sol] = {}
Moving.step()
danny = MoveHelper.find(sol)
check("Bob left: Danny stays for Sol alone, Bob's strip goes", danny ~= nil and bob:GetAttribute("MoveHelper") == nil and sol:GetAttribute("MoveHelper") == "carry")
npc = danny.body.model

-- The end ------------------------------------------------------------------------------------------------------------------

Moving.admin(sol, "end")
run(0.2)
check("the move ends: he goes, the strip goes", MoveHelper.find(sol) == nil and npc.Parent == nil and sol:GetAttribute("MoveHelper") == nil
	and sol:GetAttribute("MoveHelperDoing") == nil)

-- A second move: no room for his thing ---------------------------------------------------------------------------------------

local bedHeight = T.Bed.Height
T.Bed.Height = 1.6 -- (a low bed: the box of memories fits, the lamp never does)
Moving.admin(sol, "start")
T.Bed.Height = bedHeight
truck = E.cars[sol]
cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
truck.model:SetAttribute("BackOpen", true)
Moving.step()
unlock()
danny = MoveHelper.find(sol)
check("the next move: Danny again", danny ~= nil and danny.body ~= nil)
carried = run(40, function()
	return Rules.holding(danny.s.move, danny.id) == 5
end)
check("he goes for the box of memories (★)", carried)
danny.s.move.packing.height = 1 -- (the room went while he walked: the box is 1.5 high)
said = #E.said
local refused = run(40, function()
	return E.saidSince("Truck's full, boss.", said)
end)
check("no room at the truck: \"Truck's full, boss.\"", refused)
run(6)
local box = itemModel(5)
check("…the box set down beside the truck, not in it", stateOf(5).state == "ground" and distance(box.PrimaryPart.Position, cargoDoor.WorldPosition) < 14)
check("…nothing else fits: he waits, the truck full", Rules.holding(danny.s.move, danny.id) == nil and stateOf(1).state == "home"
	and sol:GetAttribute("MoveHelperDoing") == "Waiting: the truck is full", sol:GetAttribute("MoveHelperDoing"))
Moving.admin(sol, "end")
run(0.2)

-- A third move: a truck with no room for anything he carries ------------------------------------------------------------------

T.Bed.Height = 1
said = #E.said
Moving.admin(sol, "start")
T.Bed.Height = bedHeight
Moving.step()
unlock()
danny = MoveHelper.find(sol)
local full = run(8, function()
	return E.saidSince("Truck's full, boss.", said)
end)
check("nothing fits: he says so and waits at the truck", full and danny.action == "wait" and sol:GetAttribute("MoveHelperDoing") == "Waiting: the truck is full"
	and Rules.holding(danny.s.move, danny.id) == nil)
E.leave(sol)
run(0.2)
check("the owner leaves: the move and Danny are gone", MoveHelper.find(sol) == nil and E.destroyed == E.built)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
