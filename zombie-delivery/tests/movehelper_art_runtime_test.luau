-- 7.x Danny, a partner, × the real house art: the real shared/FurnitureLooks.luau, shared/HouseLayout.luau and
-- server/HouseInterior.luau (tests/run_tests.py builds them on tools/fixtures/item-mock.luau, the recorder that
-- tests/runtime/MovingRuntime.luau's fakes stand on) with the real server/Moving.luau and server/MoveHelper.luau. No
-- physics: his walk is a straight step (useMover, no `keep`: carrying together his root is put at the piece's far end
-- each step, as the constraints hold him in Roblox), a carried piece goes where its carrier is (the test moves it).
-- A solo run into a real family house (the lone house's plan, seed 1955): Ann lifts the real sofa, Danny takes the far end within 2 s; they carry it out
-- of the living room through its doorway ("Watch the doorframe!"), out of the front door and across the yard to the van
-- without a drop, he opens the van's back for the two of them, Ann loads it (10.1: Danny with her from the start); Danny carries a real
-- two-hands piece Ann gave him (a click: his list) to the van at his slower walk; a real two-person piece on his list:
-- he waits at it for her, never in a doorway.
-- 8.1 carrying in two: Ann's walk is the leader's client's (shared/PairCarry.luau steer, client/PairSteer.luau's: the
-- heading turns PairTurn degrees a second at most, a way behind walked backwards, the pair's walk slower while it
-- turns); through the real house Danny is never put at the far end (each of his steps within his top speed: the pair's
-- walk and a margin), only the front door's fade does; Ann turns round in the hall, the heading slowly.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local Rules = require("./MovingRules")
local FurnitureLooks = require("./FurnitureLooks")
local HouseLayout = require("./HouseLayout")
local HouseInterior = require("./HouseInterior")
local PairCarry = require("./PairCarry")
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
local H = Config.MoveHelper
local WALK = Config.Movement.Walk
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace

-- the real art, its interiors' origins given to the recorder's rays (the interior's floor)
local built: { any } = {}
Moving.useArt({
	looks = FurnitureLooks,
	layout = HouseLayout,
	interior = {
		slot = HouseInterior.slot,
		build = function(plan: any, origin: any): (any, any)
			E.built += 1
			table.insert(E.interiors, origin)
			local model, pieces = HouseInterior.build(plan, origin)
			table.insert(built, { model = model, plan = plan, origin = origin, pieces = pieces })
			return model, pieces
		end,
		destroy = function(model: any)
			E.destroyed += 1
			HouseInterior.destroy(model)
		end,
	},
})

-- His walk: straight toward the point, speed × dt a step (the last speed asked is kept to check it).
local lastSpeed = 0
MoveHelper.useMover({
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
})

local HOUSE = "lone_house" -- (10.6: a run on the lone house, a family house's plan; the van at its curb)
local door, facing, outside = E.doorOf(SandboxMap.house(HOUSE))
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (the roamers far off)
end
local ann = E.player(11, "Ann", outside)
E.profiles[ann] = { sandboxHouse = HOUSE, sandboxHouseSeed = 1955 } -- (her card's house and seed: the plan this test knows)
Moving.parkVan = E.parkVan
Moving.start()

local function promptIn(model: any, action: string): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and d.ActionText ~= nil and string.find(tostring(d.ActionText), action, 1, true) == 1 then
			return d
		end
	end
	return nil
end
local function trigger(prompt: any, player: any)
	prompt.Triggered:Fire(player)
end
local function distance(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local danny: any = nil
-- What he carries alone stays in front of him; what Ann carries in front of her (the welds, in Roblox; the root set
-- straight: the recorder's PivotTo adds its rounding up step after step).
local carried: any = nil
local function follow(model: any)
	if not E.welded(model) then -- (8.6: where Moving's weld keeps it: carried in two, lengthwise)
		model.PrimaryPart.CFrame = E.rootOf(ann).CFrame * M.CFrame.new(0, 0, -3)
	end
end
local function pieceOf(spot: number): any
	return built[#built].pieces[spot]
end
-- 8.1 while he holds the far end: the most his root moved in one of his steps over what his top speed allows (a door's
-- fade aside: the interior is far off the map).
local jump = { over = 0, steps = 0, slowest = math.huge }
local lastHeld: any = nil
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		MoveHelper.step(0.1)
		local h = danny
		if h and h.body then
			local spot, role = Rules.holding(h.s.move, h.id)
			if spot and role == "carrier" then
				pieceOf(spot).PrimaryPart.CFrame = h.body.root.CFrame * M.CFrame.new(0, 0, -1.5)
			end
			local at = h.body.root.Position
			if role == "helper" and lastHeld and (at - lastHeld).Magnitude < 300 then
				jump.over = math.max(jump.over, (at - lastHeld).Magnitude - h.holdLimit * 0.1)
				jump.slowest = math.min(jump.slowest, h.holdLimit)
				jump.steps += 1
			end
			lastHeld = if role == "helper" then at else nil
		end
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
local function helped(): boolean
	return math.abs((ann.Character:GetAttribute("CarrySpeed") or 0) - WALK * T.Speed.Pair) < 1e-6
end
local function farEnd(model: any): any
	local ends = danny and danny.gripped == model.PrimaryPart and danny.holdEnd -- (8.6 his end, decided at the lift)
	if ends then
		return model.PrimaryPart.CFrame * ends
	end
	return (model.PrimaryPart.CFrame * M.CFrame.new(0, 0, -(model.PrimaryPart.Size.Z / 2 + H.Standoff))).Position
end
-- Ann walks to `to` with the piece (8.1 the leader's client: the heading turns PairTurn degrees a second at most toward
-- the way, a way behind walked backwards, the pair's walk × the turn's factor); the most Danny was off its far end, and
-- whether it ever went down. turnedMost: the most the heading turned in one step.
local steer = PairCarry.newSteer(0)
local turnedMost = 0
local function heading(): number
	local look = E.rootOf(ann).CFrame.LookVector
	return PairCarry.yawOf(look.X, look.Z)
end
local function walk(to: any): (number, boolean)
	local worst, down = 0, false
	for _ = 1, 400 do
		local here = E.rootOf(ann).Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		if way.Magnitude < 0.05 then
			break
		end
		local before = heading()
		steer.heading = before
		local factor = PairCarry.steer(steer, way.X, way.Z, 0.1, math.rad(ann.Character:GetAttribute("PairTurn") or H.PairTurn))
		turnedMost = math.max(turnedMost, math.abs(PairCarry.wrap(steer.heading - before)))
		local nextAt = here + way.Unit * math.min((ann.Character:GetAttribute("CarrySpeed") or 0) * factor * 0.1, way.Magnitude)
		E.rootOf(ann).CFrame = M.CFrame.new(nextAt) * M.CFrame.Angles(0, steer.heading, 0)
		follow(carried)
		run(0.1)
		local _, role = Rules.holding(danny.s.move, danny.id)
		if role == "helper" then
			worst = math.max(worst, distance(danny.body.root.Position, farEnd(carried)))
		else
			down = true
		end
	end
	return worst, down
end

-- A solo move into the real house: Danny comes ------------------------------------------------------------------------------

local started = E.startRun(ann, HOUSE)
check("a solo run into the real house starts", started == nil and #built == 1, started)
Moving.step()
danny = MoveHelper.find(ann)
local truck = E.cars[ann]
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
check("Danny comes with the van", danny ~= nil and danny.body ~= nil and distance(danny.body.root.Position, cargoDoor.WorldPosition) < 8)
check("10.1 Danny is Ann's from the start (free, no hire)", danny.hirer == ann)
-- 8.3 a click on a piece: Ann beside it (the server checks she could see it)
local function give(model: any)
	local was = E.rootOf(ann).Position
	E.place(ann, model.PrimaryPart.Position + V3(3, 0, 0))
	ann.Character:SetAttribute("ClipboardHeld", true) -- (8.5 orders mode: her clipboard out, server/Clipboard.luau's)
	E.request(ann, "helper", "assign", model)
	E.place(ann, was)
end
local plan = built[1].plan
local origin = built[1].origin
local frontDoor, livingDoor = nil, nil
for _, d in plan.doors do
	if d.front then
		frontDoor = d
	elseif table.find(d.rooms, "living") and table.find(d.rooms, "hall") then
		livingDoor = d
	end
end
check("the real plan: the front door and the living room's doorway to the hall", frontDoor ~= nil and livingDoor ~= nil and #danny.doorways == #plan.doors)

-- The real sofa: lifted together, carried out together -------------------------------------------------------------------------

local sofaSpot: any = nil
for _, s in plan.spots do
	if s.item == "sofa" then
		sofaSpot = s
	end
end
check("the real sofa stands in the living room", sofaSpot ~= nil and FurnitureLooks.Items.sofa.class == "pair")
local sofa = pieceOf(sofaSpot.id)
carried = sofa
local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{HOUSE}`)
E.place(ann, outside)
trigger(promptIn(site, "Enter house"), ann)
local front = sofa.PrimaryPart.CFrame * M.CFrame.new(0, 0, -(FurnitureLooks.Items.sofa.size.Z / 2 + 2)) -- (its front: its -Z)
E.rootOf(ann).CFrame = M.CFrame.lookAt(V3(front.Position.X, origin.Position.Y + 3, front.Position.Z), V3(sofa.PrimaryPart.Position.X, origin.Position.Y + 3, sofa.PrimaryPart.Position.Z))
local said = #E.said
trigger(promptIn(sofa, "Lift"), ann)
check("8.3 Ann lifts the sofa: no drag alone, she calls Danny and waits at her end", ann.Character:GetAttribute("MoveCarry") == nil
	and danny.call ~= nil and ann:GetAttribute("MoveHelperCall") == FurnitureLooks.Items.sofa.name)
local took = 0
local alone = false
local lifted = run(20, function()
	took += 0.1
	alone = alone or (ann.Character:GetAttribute("MoveCarry") == sofaSpot.id and not helped())
	return helped()
end)
check("8.3 Danny walks over from the van (in by the front door), \"On three... lift!\": up together, the two-person walk, never dragged alone",
	lifted and not alone and E.saidSince("On three... lift!", said), took)
follow(sofa)
run(0.6)
check("…at its far end, turned to Ann, his arms on it, Ann's grip steadied", distance(danny.body.root.Position, farEnd(sofa)) < 0.05
	and danny.body.root.CFrame.LookVector:Dot(E.rootOf(ann).Position - danny.body.root.Position) > 0
	and danny.body.model:GetAttribute("Carrying") == "furniture" and ann.Character:GetAttribute("GripSteady") == true)
-- out of the living room through its doorway (a wall along Z: through it along X), to the front door's inside
local through = origin * livingDoor.at
local hall = origin * (livingDoor.at + V3(4, 0, 0))
local room = origin * (livingDoor.at + V3(-6, 0, 0))
said = #E.said
local worst, down = walk(V3(room.X, origin.Position.Y + 3, room.Z))
local w2, d2 = walk(V3(hall.X, origin.Position.Y + 3, hall.Z))
local exitAt = (origin * M.CFrame.new(plan.exit)).Position
local w3, d3 = walk(V3(exitAt.X, origin.Position.Y + 3, exitAt.Z + 3))
worst, down = math.max(worst, w2, w3), down or d2 or d3
check("through the living room's doorway and the hall together: he never leaves its far end", worst < 0.05 and not down and helped(), worst)
check("…\"Watch the doorframe!\" at the doorway", E.saidSince("Watch the doorframe!", said) and distance(through, hall) > 0)
-- out of the front door: he comes through the fade with Ann
truck.model:SetAttribute("BackOpen", false)
local saidOut = #E.said
E.place(ann, exitAt + V3(0, 0, 1))
E.rootOf(ann).CFrame = M.CFrame.lookAt(exitAt + V3(0, 0, 1), exitAt)
follow(sofa)
trigger(promptIn(workspace, "Leave house"), ann)
follow(sofa)
run(0.2)
check("out of the front door: Danny comes through with it, at its far end", (E.rootOf(ann).Position - origin.Position).Magnitude > 1000
	and distance(danny.body.root.Position, farEnd(sofa)) < 0.05 and helped())
-- across the yard to the van's back: he opens it for the two of them
local back = cargoDoor.WorldPosition + V3(0, 0, 0)
local away = V3(back.X - truck.chassis.Position.X, 0, back.Z - truck.chassis.Position.Z).Unit
worst, down = walk(back + away * 3)
check("across the yard to the van's back together, no drop", worst < 0.05 and not down and helped(), worst)
check("8.1 all the way the heading turned PairTurn degrees a second at most (Ann's PairTurn: the leader's)", turnedMost > 0
	and turnedMost <= math.rad(H.PairTurn) * 0.1 + 1e-9 and ann.Character:GetAttribute("PairTurn") == H.PairTurn, math.deg(turnedMost) * 10)
check("8.1 …and Danny was never put at the far end: every step of his within his top speed (the pair's walk and a margin)",
	jump.steps > 30 and jump.over <= 1e-6 and math.abs(jump.slowest - Brain.holdSpeed(WALK * T.Speed.Pair)) < 1e-6, `{jump.steps} steps, {jump.over} over, {jump.slowest}`)
check("…the back shut: he opens it for the two of them (\"I'll get the doors!\")", truck.model:GetAttribute("BackOpen") == true and E.saidSince("I'll get the doors!", saidOut))
run(0.2)
trigger(promptIn(truck.model, "Load"), ann)
check("Ann loads the sofa: in the van, never set down on the way", danny.s.move.things[sofaSpot.id].state == "truck" and ann.Character:GetAttribute("MoveCarry") == nil
	and string.find(E.lastNotice(ann), "Sofa", 1, true) ~= nil, E.lastNotice(ann))
local apart = false
for _, m in E.messages do
	if m.player == ann and m.remote == "Notice" and (string.find(tostring(m.kind), "Too far apart", 1, true) or string.find(tostring(m.kind), "let go", 1, true)) then
		apart = true
	end
end
check("…no \"Too far apart\", no \"let go\" all the way", not apart)
run(0.3)
check("…both pairs of hands free, his arms down, Ann's grip as before", Rules.holding(danny.s.move, danny.id) == nil and danny.body.model:GetAttribute("Carrying") == nil
	and ann.Character:GetAttribute("GripSteady") == nil)

-- Danny carries a real two-hands piece Ann gives him (8.3: his list) --------------------------------------------------------

local ownSpot: any = nil
for _, sp in plan.spots do
	local def = FurnitureLooks.Items[sp.item]
	local thing = danny.s.move.things[sp.id]
	if def and def.class == "both" and thing and thing.state == "home" and (ownSpot == nil or (sp.star and not ownSpot.star)) then
		ownSpot = sp
	end
end
check("the real house has a two-hands piece", ownSpot ~= nil)
give(pieceOf(ownSpot.id))
check("8.3 Ann gives it to him: his list", danny.queue[1] == ownSpot.id and #danny.queue == 1)
E.place(ann, back + away * 30) -- (out of the way)
local own = ownSpot.id
local ownSpeed = 0
local ownArms: any = nil
local delivered = run(200, function()
	local spot, role = Rules.holding(danny.s.move, danny.id)
	if spot == own and role == "carrier" and danny.action == "deliver" then
		ownSpeed = math.max(ownSpeed, lastSpeed) -- (his walk there: the most of it; he slows into his goal at the van)
		ownArms = ownArms or { danny.body.model:GetAttribute("Carrying"), danny.body.model:GetAttribute("CarryHands") }
	end
	return danny.s.move.things[own].state == "truck"
end)
local thing = danny.s.move.things[own]
check("Danny carries the real two-hands piece of his list to the van and loads it", delivered and thing.class == "both", thing.item)
check("…at 0.7 × a player's two-hands walk, in both arms", math.abs(ownSpeed - Rules.carrySpeed(WALK, "both", thing.weight) * H.Speed) < 1e-6
	and ownArms ~= nil and ownArms[1] == "furniture" and ownArms[2] == 2, ownSpeed)

-- 8.3 a real two-person piece of his list: he waits at it for Ann, never in a doorway ------------------------------------------

local pairSpot: any = nil
for _, sp in plan.spots do
	local def = FurnitureLooks.Items[sp.item]
	if not pairSpot and def and def.class == "pair" and danny.s.move.things[sp.id].state == "home" then
		pairSpot = sp
	end
end
check("the real house has another two-person piece", pairSpot ~= nil)
give(pieceOf(pairSpot.id))
local waiting = run(60, function()
	return danny.needs == pairSpot.id and danny.needsAt > 0
end)
local at = danny.body.root.Position
local inDoor = false
for _, d in plan.doors do
	local rel = origin:PointToObjectSpace(at) - d.at
	local along = if d.axis == "X" then math.abs(rel.X) else math.abs(rel.Z)
	local through = if d.axis == "X" then math.abs(rel.Z) else math.abs(rel.X)
	inDoor = inDoor or (along <= (d.width or 4) / 2 + H.Aside.Margin and through <= H.Aside.Depth)
end
check("8.3 he goes to it and waits at it for Ann (\"🙋 Danny needs you\"), out of every doorway", waiting and danny.action == "needs" and not inDoor
	and pieceOf(pairSpot.id):GetAttribute("DannyNeeds") == true, `{at.X}, {at.Z}`)

Moving.endRun(ann)
run(0.2)
check("the move ends: he goes, the interior is taken down", MoveHelper.find(ann) == nil and E.destroyed == 1)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
