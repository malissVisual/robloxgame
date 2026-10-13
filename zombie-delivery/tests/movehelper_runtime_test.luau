-- 7.0, the depot's helper ("Danny from the depot"): the real server/Moving.luau and server/MoveHelper.luau in the Luau
-- CLI (tests/run_tests.py builds MovingServer.luau and MoveHelperServer.luau on tests/runtime/MovingRuntime.luau's
-- fakes). The runtime has no physics and no pathfinding: his walk here is a straight step of speed × dt (useMover, no
-- `keep`: carrying together he is put at your piece's far end each step, as the constraints hold him in Roblox), and a
-- carried piece is moved with its carrier by the test (a weld is only a record). A solo move: Danny comes with the van;
-- the player lifts the sofa and he takes the far end at once (faded over from the van) or sprinting (from near), turned
-- to the player, his arms on it, the player's grip steadied; he moves with it (a walk that goes nowhere changes nothing:
-- no "too far apart" any more), out through the door; set down and lifted again; the player loads it; he carries the
-- ★ pieces first, a two-hands one too (slower), then the others; he opens the van's back himself (or, not allowed, asks
-- and sets the piece down after WaitShut s); he opens it for the player coming with a piece; a piece the player is about
-- to lift is theirs; the other side of the player's heavy two-hands piece (the pair's walk); stuck: a new path after 2 s,
-- a nudge after 4 s; a bite, his death and comeback, running from a zombie, the orders (Help me: he follows you through
-- the door), the van parked far off, the crew growing (he goes) and Duo, the end of the move; a second move where the
-- room goes while he carries his piece ("Van's full, boss - drive it to the Wall?": set down beside the van), a third
-- where nothing he may carry fits, a fourth where his body goes.
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
E.truckAt = V3(home.door.x + 30, 2, home.door.z - 20) -- (placeNear's spot: the van is at the house at once, its back
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
-- A carried piece stays in front of its carrier (the weld, in Roblox; its root set straight: the recorder's PivotTo
-- adds its rounding up step after step).
local function follow(model: any, player: any)
	model.PrimaryPart.CFrame = E.rootOf(player).CFrame * M.CFrame.new(0, 0, -3)
end
local danny: any = nil
-- What he carries alone stays in front of him (the weld, in Roblox).
local function carryAlong()
	local h = danny
	if not h or not h.body then
		return
	end
	local spot, role = Rules.holding(h.s.move, h.id)
	local model = if spot and role == "carrier" then itemModel(spot) else nil
	if model then
		model.PrimaryPart.CFrame = h.body.root.CFrame * M.CFrame.new(0, 0, -1.5)
	end
end
-- Steps of 0.1 s (his loop's), the move's tick every other one; until `done` (true when it came), or `seconds` long.
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
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
-- A piece's state now (the rules'; the list the player was sent comes a tick later).
local function stateNow(spot: number): string
	return danny.s.move.things[spot].state
end
local function distance(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function helped(): boolean
	return math.abs((sol.Character:GetAttribute("CarrySpeed") or 0) - WALK * 0.8) < 1e-6
end
-- Where his root belongs: the far end of the piece (Standoff past its far face).
local function farEnd(model: any, depth: number): any
	return (model.PrimaryPart.CFrame * M.CFrame.new(0, 0, -(depth / 2 + H.Standoff))).Position
end

-- Sol walks to `to` with the piece (a stud every 0.1 s: under the pair's walk, the pace check's; facing the way), the
-- run's steps between; returns the most his root was off the piece's far end while he held it.
local function walk(model: any, to: any): number
	local worst = 0
	local depth = model.PrimaryPart.Size.Z
	for _ = 1, 400 do
		local here = E.rootOf(sol).Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		if way.Magnitude < 0.05 then
			break
		end
		local nextAt = here + way.Unit * math.min(1, way.Magnitude)
		E.rootOf(sol).CFrame = M.CFrame.lookAt(nextAt, nextAt + way.Unit)
		follow(model, sol)
		run(0.1)
		local _, role = Rules.holding(danny.s.move, danny.id)
		if role == "helper" then
			worst = math.max(worst, distance(danny.body.root.Position, farEnd(model, depth)))
		end
	end
	return worst
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
check("…at the van's back", distance(body.root.Position, cargoDoor.WorldPosition) < 8, distance(body.root.Position, cargoDoor.WorldPosition))
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

-- The sofa: lifted together, carried together -------------------------------------------------------------------------------

local site = workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge")
local enter = promptIn(site, "Enter house")
-- the owner took the Technician out: the front door is open from the start (no lock for Danny to wait at)
E.place(sol, outside)
check("the front door is open: Enter house at once, no Pick lock", enter ~= nil and enter.Enabled and promptIn(site, "Pick lock") == nil and sol:GetAttribute("MoveRole") == "driver")
trigger(enter, sol)
local origin = E.interiors[1]
check("Sol is inside", (E.rootOf(sol).Position - origin.Position).Magnitude < 10)
local sofa = itemModel(3)
local SOFA = E.items.sofa.size
E.place(sol, sofa.PrimaryPart.Position + V3(0, 0, 3))
trigger(promptIn(sofa, "Lift"), sol)
follow(sofa, sol)
local character = sol.Character
check("alone: Sol drags the sofa at 0.35", character:GetAttribute("MoveCarry") == 3 and math.abs((character:GetAttribute("CarrySpeed") or 0) - WALK * 0.35) < 1e-6)
local said = #E.said
local took = 0
local lifted = run(5, function()
	took += 0.1
	return helped()
end)
check("7.x Danny takes the far end within 2 s (from the van: he fades over to it): the two-person walk (0.8)", lifted and took <= 2 + 1e-6, took)
check("…\"Got the other end!\"", E.saidSince("Got the other end!", said))
follow(sofa, sol)
run(0.3)
check("…inside, at the sofa's far end, turned to Sol", (body.root.Position - origin.Position).Magnitude < 40 and distance(body.root.Position, farEnd(sofa, SOFA.Z)) < 0.05
	and body.root.CFrame.LookVector:Dot(E.rootOf(sol).Position - body.root.Position) > 0, distance(body.root.Position, farEnd(sofa, SOFA.Z)))
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
local at = npc:GetAttribute("CarryAt")
check("7.x his arms on its edge (Carrying, two hands, CarryAt in front of him)", npc:GetAttribute("Carrying") == "furniture" and npc:GetAttribute("CarryHands") == 2
	and M.typeof(at) == "Vector3" and at.Z < 0 and at.Z > -2 and M.typeof(npc:GetAttribute("CarrySize")) == "Vector3", at and at.Z)
check("7.x Sol's grip steadied (GripSteady: a bigger box)", character:GetAttribute("GripSteady") == true)
said = #E.said
run(H.ThreeAfter + 0.2)
check("7.x …\"On three... lift!\" a moment later", E.saidSince("On three... lift!", said))
check("…the strip: carrying the Sofa with you", sol:GetAttribute("MoveHelperDoing") == "Carrying the Sofa with you", sol:GetAttribute("MoveHelperDoing"))
-- walking and turning together: he moves with it, every step at its far end
local worst = walk(sofa, origin.Position + V3(6, 3, 8))
worst = math.max(worst, walk(sofa, origin.Position + V3(0, 3, 2)))
check("7.x walking and turning together: he stays at its far end", worst < 0.05 and helped(), worst)
-- out of the door with it: he comes through with Sol
local leave = promptIn(workspace, "Leave house")
E.place(sol, origin.Position + V3(0, 3, 1))
follow(sofa, sol)
trigger(leave, sol)
follow(sofa, sol)
run(0.2)
check("out of the door: Danny comes through with the sofa, at its far end", (E.rootOf(sol).Position - origin.Position).Magnitude > 1000 and distance(body.root.Position, farEnd(sofa, SOFA.Z)) < 0.05
	and character:GetAttribute("MoveCarry") == 3, distance(body.root.Position, E.rootOf(sol).Position))
check("…still two on it", helped())
local back = cargoDoor.WorldPosition + V3(0, 0, 2)
worst = walk(sofa, back + V3(24, 0, 0))
check("…across the yard together", worst < 0.05 and helped(), worst)
-- a walk that goes nowhere (in Roblox: his own walk is off while he carries with you): nothing changes, no drop
MoveHelper.useMover({ move = function() end, halt = function() end })
worst = walk(sofa, back + V3(24, 0, 24))
check("7.x never a \"too far apart\" drop: 24 studs on he still holds the far end", helped() and Rules.holding(danny.s.move, danny.id) == 3 and worst < 0.05
	and string.find(E.lastNotice(sol), "let go", 1, true) == nil, E.lastNotice(sol))
MoveHelper.useMover(walker)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
run(0.2)
check("Sol sets it down: Danny's hands free, his arms down, Sol's grip as before", Rules.holding(danny.s.move, danny.id) == nil and npc:GetAttribute("Carrying") == nil
	and npc:GetAttribute("CarryAt") == nil and character:GetAttribute("GripSteady") == nil and stateNow(3) == "ground")
-- lifted again with Danny near: he sprints over (no fade)
body.root.CFrame = M.CFrame.new(back.X + 18, 3, back.Z + 14)
trigger(promptIn(sofa, "Lift"), sol)
follow(sofa, sol)
said = #E.said
took = 0
local sprint = 0
lifted = run(5, function()
	took += 0.1
	if danny.action == "help" then
		sprint = math.max(sprint, lastSpeed)
	end
	return helped()
end)
check("7.x lifted again, Danny near: he sprints over (Sprint × the walk) and takes it within 2 s", lifted and took <= 2 + 1e-6 and math.abs(sprint - WALK * H.Sprint) < 1e-6
	and E.saidSince("Got the other end!", said), `{took} s, {sprint}`)
worst = walk(sofa, back)
check("…to the van's back together", worst < 0.05 and helped(), worst)
truck.model:SetAttribute("BackOpen", true)
run(0.4)
local load = promptIn(truck.model, "Load")
trigger(load, sol)
check("Sol loads the sofa: in the van, both hands free", character:GetAttribute("MoveCarry") == nil and danny.s.move.things[3].state == "truck", E.lastNotice(sol))
run(0.3)
check("…and Danny's hands are free", Rules.holding(danny.s.move, danny.id) == nil and npc:GetAttribute("Carrying") == nil and character:GetAttribute("GripSteady") == nil)

-- (c) the other side of your heavy two-hands piece ----------------------------------------------------------------------------------

local tv = itemModel(2)
E.place(sol, outside)
trigger(enter, sol)
E.place(sol, tv.PrimaryPart.Position + V3(0, 0, 2))
trigger(promptIn(tv, "Pick up"), sol)
follow(tv, sol)
check("Sol picks up the TV (two hands, weight 4) alone", character:GetAttribute("MoveCarry") == 2
	and math.abs((character:GetAttribute("CarrySpeed") or 0) - Rules.carrySpeed(WALK, "both", 4)) < 1e-6, character:GetAttribute("CarrySpeed"))
said = #E.said
local assisted = run(6, function()
	return Rules.holding(danny.s.move, danny.id) == 2
end)
check("7.x Danny takes its other side (\"Here, let me take the other side.\"): the pair's walk for both (0.8)", assisted and helped()
	and E.saidSince("Here, let me take the other side.", said) and select(2, Rules.holding(danny.s.move, danny.id)) == "helper")
follow(tv, sol)
run(0.3)
check("…at its far side, Sol's grip steadied", distance(body.root.Position, farEnd(tv, E.items.tv.size.Z)) < 0.05 and character:GetAttribute("GripSteady") == true)
E.place(sol, origin.Position + V3(0, 3, 1))
follow(tv, sol)
trigger(leave, sol)
follow(tv, sol)
run(0.2)
worst = walk(tv, back)
check("…out through the door and to the van together", worst < 0.05 and helped(), worst)
run(0.2)
trigger(load, sol)
check("…Sol loads it, both pairs of hands free", danny.s.move.things[2].state == "truck" and Rules.holding(danny.s.move, danny.id) == nil and character:GetAttribute("MoveCarry") == nil)

-- On his own: the ★ pieces first, a two-hands one too, then the others ---------------------------------------------------------

E.place(sol, back + V3(30, 0, 0)) -- (out of the way: no piece of his is "about to be lifted" by Sol)
local loadedAt: { [number]: number } = {}
local clockSpeed = 0
local loadShown = false
local n = 0
local arms: any = nil
run(160, function()
	n += 1
	local spot, role = Rules.holding(danny.s.move, danny.id)
	if spot == 4 and role == "carrier" and danny.action == "deliver" then
		clockSpeed = lastSpeed
		loadShown = loadShown or load.Enabled
		arms = arms or { npc:GetAttribute("Carrying"), npc:GetAttribute("CarryHands") }
	end
	for _, s in { 1, 4, 5 } do
		local item = stateOf(s)
		if item and item.state == "truck" and not loadedAt[s] then
			loadedAt[s] = n
		end
	end
	return loadedAt[1] ~= nil and loadedAt[4] ~= nil and loadedAt[5] ~= nil
end)
check("7.x Danny carries Grandpa's Clock (★, two hands) to the van and loads it", loadedAt[4] ~= nil)
check("…at 0.7 × a player's two-hands walk (slower than a one-hand piece)", math.abs(clockSpeed - Rules.carrySpeed(WALK, "both", 6) * 0.7) < 1e-6, clockSpeed)
check("…in both arms (his Carrying: furniture, two hands)", arms ~= nil and arms[1] == "furniture" and arms[2] == 2)
check("the ★ ones first (the clock, the box of memories), then the lamp", loadedAt[4] ~= nil and loadedAt[5] ~= nil and loadedAt[1] ~= nil
	and math.max(loadedAt[4], loadedAt[5]) < loadedAt[1], `{loadedAt[4]} {loadedAt[5]} {loadedAt[1]}`)
check("…the van's Load prompt stays off for what he carries (the back's own E stays free)", not loadShown)
check("Sol hears what he loaded", (function()
	for _, m in E.messages do
		if m.player == sol and m.remote == "Notice" and string.find(tostring(m.kind), "Danny loaded", 1, true) then
			return true
		end
	end
	return false
end)())
run(4)
check("only the marble slab (two people) left: he never takes it alone", Rules.holding(danny.s.move, danny.id) == nil and stateNow(6) == "home")
check("…he waits at the van", danny.action == "wait" and sol:GetAttribute("MoveHelperDoing") == "Waiting at the van" and distance(body.root.Position, cargoDoor.WorldPosition) < 8,
	sol:GetAttribute("MoveHelperDoing"))

-- The van's back: he opens it himself; not allowed, he asks --------------------------------------------------------------------

local lamp = itemModel(1)
local unload = promptIn(truck.model, "Take out")
E.place(sol, back)
trigger(unload, sol)
check("Sol takes the lamp back out", character:GetAttribute("MoveCarry") == 1, E.lastNotice(sol))
E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, back + V3(30, 0, 0))
truck.model:SetAttribute("BackOpen", false)
said = #E.said
local opened = E.backSet or 0
local inAgain = run(30, function()
	return stateNow(1) == "truck"
end)
check("7.x the back shut: he opens it himself (\"I'll get the doors!\") and loads the lamp", inAgain and E.saidSince("I'll get the doors!", said) and (E.backSet or 0) > opened)
H.OpenBack = false
E.place(sol, back)
trigger(unload, sol)
E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, back + V3(30, 0, 0))
truck.model:SetAttribute("BackOpen", false)
said = #E.said
local carried = run(30, function()
	return Rules.holding(danny.s.move, danny.id) == 1
end)
check("not allowed to open it: Danny goes for the lamp", carried)
body.humanoid.Health = 80
body.humanoid.HealthChanged:Fire(80)
run(0.3)
local bitten = stateOf(1)
check("a bite knocks the fragile lamp in his arms", bitten ~= nil and math.abs(bitten.condition - (1 - 20 * T.Damage.PerHp * T.Damage.Fragile)) < 0.011, bitten and bitten.condition)
local shut = run(30, function()
	return E.saidSince("Open the back, boss!", said)
end)
check("…the back shut: \"Open the back, boss!\"", shut)
local down = run(H.WaitShut + 5, function()
	return Rules.holding(danny.s.move, danny.id) == nil
end)
check("…WaitShut s later he sets it down beside the van", down and stateNow(1) == "ground" and distance(lamp.PrimaryPart.Position, cargoDoor.WorldPosition) < 14,
	distance(lamp.PrimaryPart.Position, cargoDoor.WorldPosition))
run(3)
check("…and leaves it there while the back stays shut", Rules.holding(danny.s.move, danny.id) == nil and stateNow(1) == "ground")
H.OpenBack = true
truck.model:SetAttribute("BackOpen", true)
inAgain = run(20, function()
	return stateNow(1) == "truck"
end)
check("the back open: he takes it in", inAgain)

-- (d) the back for you: you come with a piece, the back shut, he opens it ---------------------------------------------------------

run(3)
E.place(sol, back)
trigger(unload, sol)
truck.model:SetAttribute("BackOpen", false)
said = #E.said
walk(lamp, back + V3(6, 0, 4))
local forYou = run(10, function()
	return truck.model:GetAttribute("BackOpen") == true
end)
check("7.x Sol at the van with the lamp, the back shut: Danny opens it (\"I'll get the doors!\")", forYou and E.saidSince("I'll get the doors!", said)
	and Rules.holding(danny.s.move, danny.id) == nil)
walk(lamp, back)
run(0.2)
trigger(load, sol)
check("…and Sol loads it", danny.s.move.things[1].state == "truck", E.lastNotice(sol))

-- The reservation: the piece you are about to lift is yours ------------------------------------------------------------------------

trigger(unload, sol)
E.place(sol, outside + V3(6, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, lamp.PrimaryPart.Position + V3(2, 0, 0)) -- (right by it, hands free)
run(6)
check("7.x Sol stands by the lamp, hands free: he leaves it to Sol", Rules.holding(danny.s.move, danny.id) == nil and stateNow(1) == "ground" and danny.action ~= "fetch",
	danny.action)
trigger(promptIn(lamp, "Pick up"), sol)
check("…Sol's lift wins", character:GetAttribute("MoveCarry") == 1)
walk(lamp, back)
run(0.2)
trigger(load, sol)
check("…and Sol loads it", danny.s.move.things[1].state == "truck", E.lastNotice(sol))

-- Down and back up -----------------------------------------------------------------------------------------------------------

E.place(sol, back)
trigger(unload, sol)
E.place(sol, outside + V3(2, 0, 0))
follow(lamp, sol)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
E.place(sol, back + V3(30, 0, 0))
carried = run(15, function()
	return Rules.holding(danny.s.move, danny.id) == 1
end)
check("he picks the lamp up again", carried)
danny.s.move.things[1].condition = 1 -- (as good as new again: the bites and this fall would break it)
local before = 1
said = #E.said
body.humanoid.Health = 0
body.humanoid.HealthChanged:Fire(0)
run(0.3)
check("killed: the lamp falls, knocked", stateNow(1) == "ground" and stateOf(1).condition < before - 0.1 and Rules.holding(danny.s.move, danny.id) == nil, stateOf(1).condition)
check("…he is down (\"I'll be back!\"), the player hears it", danny.dead and E.saidSince("Ugh... I'll be back!", said)
	and string.find(E.lastNotice(sol), "Danny is down", 1, true) ~= nil and sol:GetAttribute("MoveHelperDoing") == "Down: back at the van soon")
run(3.2)
check("…his body goes a moment later", npc.Parent == nil and danny.body == nil)
local backUp = run(H.Respawn, function()
	return danny.body ~= nil
end)
check("Respawn s later he is back at the van", backUp and not danny.dead and distance(danny.body.root.Position, cargoDoor.WorldPosition) < 8 and E.saidSince("Back on my feet!", said))
body = danny.body
npc = body.model
local again = run(20, function()
	return stateNow(1) == "truck"
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
check("…it's gone: he goes back to the van", danny.action == "wait" and not danny.fleeing)

-- The orders -----------------------------------------------------------------------------------------------------------------

said = #E.said
E.request(sol, "helper", "dance")
check("a wrong order changes nothing", danny.mode == "carry")
E.request(sol, "helper", "wait")
check("WAIT AT VAN: the order, the strip, his word", danny.mode == "wait" and sol:GetAttribute("MoveHelper") == "wait" and E.saidSince("Waiting at the van.", said))
E.request(sol, "helper", "help")
E.place(sol, outside + V3(-3, 0, 0) + facing * 6)
local followed = run(15, function()
	return distance(body.root.Position, E.rootOf(sol).Position) <= H.Follow + 2
end)
check("HELP ME: he follows you", followed and danny.mode == "help" and danny.action == "follow" and sol:GetAttribute("MoveHelperDoing") == "Right behind you")
E.place(sol, outside)
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

-- The van parked far off (driven somewhere else), then back by the house -------------------------------------------------------

local parked = truck.chassis.CFrame
truck.chassis.CFrame = M.CFrame.new(Map.Depot.x - 60, 2, Map.Depot.z)
local stayed = body.root.Position
run(3)
check("the van parked far off, not by the house: he stays where he is (no popping along its way)", distance(body.root.Position, stayed) < 1)
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

-- A second move: no room for his piece ----------------------------------------------------------------------------------------

E.place(sol, V3(Map.Depot.x, 3, Map.Depot.z))
local bedHeight = T.Beds[E.carId].Height
T.Beds[E.carId].Height = 1.6 -- (a low bed: the box of memories fits, the lamp never does)
Moving.admin(sol, "start")
T.Beds[E.carId].Height = bedHeight
truck = E.cars[sol]
cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
truck.model:SetAttribute("BackOpen", true)
Moving.step()
danny = MoveHelper.find(sol)
check("the next move: Danny again", danny ~= nil and danny.body ~= nil)
carried = run(40, function()
	return Rules.holding(danny.s.move, danny.id) == 5
end)
check("he goes for the box of memories (★)", carried)
danny.s.move.packing.height = 1 -- (the room went while he walked: the box is 1.5 high)
said = #E.said
local refused = run(40, function()
	return E.saidSince("Van's full, boss - drive it to the Wall?", said)
end)
check("no room at the van: \"Van's full, boss - drive it to the Wall?\"", refused)
run(6)
local box = itemModel(5)
check("…the box set down beside the van, not in it", stateNow(5) == "ground" and distance(box.PrimaryPart.Position, cargoDoor.WorldPosition) < 14)
check("…nothing else fits: he waits, the van full", Rules.holding(danny.s.move, danny.id) == nil and stateNow(1) == "home"
	and sol:GetAttribute("MoveHelperDoing") == "Waiting: the van is full", sol:GetAttribute("MoveHelperDoing"))
Moving.admin(sol, "end")
run(0.2)

-- A third move: a van with no room for anything he carries ------------------------------------------------------------------

T.Beds[E.carId].Height = 1
said = #E.said
Moving.admin(sol, "start")
T.Beds[E.carId].Height = bedHeight
Moving.step()
danny = MoveHelper.find(sol)
local full = run(8, function()
	return E.saidSince("Van's full, boss - drive it to the Wall?", said)
end)
check("nothing fits: he says so and waits at the van", full and danny.action == "wait" and sol:GetAttribute("MoveHelperDoing") == "Waiting: the van is full"
	and Rules.holding(danny.s.move, danny.id) == nil)
Moving.admin(sol, "end")
run(0.2)

-- Stuck: a new path after StuckRepath s, a nudge to the way's next point after StuckSnap s -------------------------------------

Moving.admin(sol, "start")
Moving.step()
danny = MoveHelper.find(sol)
local routes: { any } = {}
local spawn = E.task.spawn
E.task.spawn = function(callback: any, ...: any) -- (the path in the background: at once here)
	callback(...)
end
MoveHelper.useMover({
	move = function(b: any, _to: any, speed: number)
		b.walking = true -- (blocked: he goes nowhere)
		lastSpeed = speed
	end,
	halt = function(b: any)
		b.walking = false
	end,
	route = function(_b: any, from: any, to: any): any
		table.insert(routes, from)
		return { from, from + V3(3, 0, 0), to }
	end,
})
local stuckAt = danny.body.root.Position
local repath, nudged = 0, 0
local t = 0
run(5, function()
	t += 0.1
	if repath == 0 and #routes >= 2 then
		repath = t
	end
	if nudged == 0 and distance(danny.body.root.Position, stuckAt) > 2 then
		nudged = t
	end
	return nudged > 0
end)
E.task.spawn = spawn
MoveHelper.useMover(walker)
check("7.x stuck: a new path after StuckRepath (2) s", repath >= H.StuckRepath - 0.15 and repath <= H.StuckRepath + 0.35, repath)
check("…a nudge to his way's next point after StuckSnap (4) s", nudged >= H.StuckSnap - 0.15 and nudged <= H.StuckSnap + 0.35
	and distance(danny.body.root.Position, stuckAt + V3(3, 0, 0)) < 0.05, `{nudged} s at {danny.body.root.Position}`)
Moving.admin(sol, "end")
run(0.2)

-- 7.0 review: his body taken away (by something else) while he carries a piece: it falls, nobody holds it -----------------

Moving.admin(sol, "start")
Moving.step()
danny = MoveHelper.find(sol)
local holds = run(40, function()
	return danny.body ~= nil and Rules.holding(danny.s.move, danny.id) ~= nil
end)
local held = Rules.holding(danny.s.move, danny.id)
check("a fifth move: Danny carries a piece", holds and held ~= nil)
danny.body.model:Destroy()
run(0.5)
check("his body gone: what he held fell (never 'carried' by nobody)", Rules.holding(danny.s.move, danny.id) == nil and held ~= nil
	and danny.s.move.things[held].state == "ground", held and danny.s.move.things[held].state)
E.leave(sol)
run(0.2)
check("the owner leaves: the move and Danny are gone", MoveHelper.find(sol) == nil and E.destroyed == E.built)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
