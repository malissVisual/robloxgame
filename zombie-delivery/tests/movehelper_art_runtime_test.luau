-- 7.x Danny, a partner, × the real house art: the real shared/FurnitureLooks.luau, shared/HouseLayout.luau and
-- server/HouseInterior.luau (tests/run_tests.py builds them on tools/fixtures/item-mock.luau, the recorder that
-- tests/runtime/MovingRuntime.luau's fakes stand on) with the real server/Moving.luau and server/MoveHelper.luau. No
-- physics: his walk is a straight step (useMover, no `keep`: carrying together his root is put at the piece's far end
-- each step, as the constraints hold him in Roblox), a carried piece goes where its carrier is (the test moves it).
-- A solo move into Marge's real house: Ann lifts the real sofa, Danny takes the far end within 2 s; they carry it out
-- of the living room through its doorway ("Watch the doorframe!"), out of the front door and across the yard to the van
-- without a drop, he opens the van's back for the two of them, Ann loads it; Danny carries a real two-hands piece (★ one
-- first) to the van at his slower walk; on HELP ME, Ann stopped just past a doorway: he stands beside it, not in it.
-- 8.1 carrying in two: Ann's walk is the leader's client's (shared/PairCarry.luau steer, client/PairSteer.luau's: the
-- heading turns PairTurn degrees a second at most, a way behind walked backwards, the pair's walk slower while it
-- turns); through the real house Danny is never put at the far end (each of his steps within his top speed: the pair's
-- walk and a margin), only the front door's fade does; Ann turns round in the hall, the heading slowly.
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local Map = require("./Map")
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

local home = Map.home(T.Contracts[1].home) :: any
local door = V3(home.door.x, 3, home.door.z)
local facing = V3(home.facing.x, 0, home.facing.z)
local outside = door + facing * 3
E.truckAt = V3(home.park.x, 2, home.park.z)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0) -- (the roamers far off)
end
local ann = E.player(11, "Ann", outside)
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
	model.PrimaryPart.CFrame = E.rootOf(ann).CFrame * M.CFrame.new(0, 0, -3)
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

local started = Moving.admin(ann, "start")
check("a solo move into Marge's real house starts", string.find(started, "started", 1, true) ~= nil and #built == 1, started)
Moving.step()
danny = MoveHelper.find(ann)
local truck = E.cars[ann]
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
check("Danny comes with the van", danny ~= nil and danny.body ~= nil and distance(danny.body.root.Position, cargoDoor.WorldPosition) < 8)
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
local site = workspace:FindFirstChild("Moves"):FindFirstChild("Move_marge")
E.place(ann, outside)
trigger(promptIn(site, "Enter house"), ann)
local front = sofa.PrimaryPart.CFrame * M.CFrame.new(0, 0, -(FurnitureLooks.Items.sofa.size.Z / 2 + 2)) -- (its front: its -Z)
E.rootOf(ann).CFrame = M.CFrame.lookAt(V3(front.Position.X, origin.Position.Y + 3, front.Position.Z), V3(sofa.PrimaryPart.Position.X, origin.Position.Y + 3, sofa.PrimaryPart.Position.Z))
trigger(promptIn(sofa, "Lift"), ann)
follow(sofa)
check("Ann lifts the sofa: alone she drags it", ann.Character:GetAttribute("MoveCarry") == sofaSpot.id and Rules.mode(danny.s.move.things[sofaSpot.id]) == "drag")
local said = #E.said
local took = 0
local lifted = run(5, function()
	took += 0.1
	return helped()
end)
check("Danny takes the far end within 2 s: the two-person walk", lifted and took <= 2 + 1e-6 and E.saidSince("Got the other end!", said), took)
follow(sofa)
run(0.2)
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

-- Danny carries a real two-hands piece --------------------------------------------------------------------------------------

E.place(ann, back + away * 30) -- (out of the way: nothing of his is "about to be lifted" by Ann)
local own: any = nil
local ownSpeed = 0
local ownArms: any = nil
local delivered = run(200, function()
	local spot, role = Rules.holding(danny.s.move, danny.id)
	if spot and role == "carrier" and danny.s.move.things[spot].class == "both" and danny.action == "deliver" then
		own = own or spot
		if spot == own then
			ownSpeed = lastSpeed
			ownArms = ownArms or { danny.body.model:GetAttribute("Carrying"), danny.body.model:GetAttribute("CarryHands") }
		end
	end
	return own ~= nil and danny.s.move.things[own].state == "truck"
end)
local thing = if own then danny.s.move.things[own] else nil
check("Danny carries a real two-hands piece to the van and loads it", delivered and thing ~= nil and thing.class == "both", thing and thing.item)
check("…a ★ one first", thing ~= nil and thing.star, thing and thing.item)
check("…at 0.7 × a player's two-hands walk, in both arms", thing ~= nil and math.abs(ownSpeed - Rules.carrySpeed(WALK, "both", thing.weight) * H.Speed) < 1e-6
	and ownArms ~= nil and ownArms[1] == "furniture" and ownArms[2] == 2, ownSpeed)

-- HELP ME: Ann just past a doorway, he stands beside it, not in it ---------------------------------------------------------------

E.request(ann, "helper", "help")
E.place(ann, outside)
trigger(promptIn(site, "Enter house"), ann)
-- 5 studs past the doorway into the living room, her back to it: his place behind her is the doorway itself
local past = origin * (livingDoor.at + V3(-H.Follow, 3, 0))
E.rootOf(ann).CFrame = M.CFrame.lookAt(past, past + V3(-1, 0, 0))
run(12)
local at = danny.body.root.Position
local rel = origin:PointToObjectSpace(at) - livingDoor.at
local half = livingDoor.width / 2
local inDoor = math.abs(rel.Z) <= half + H.Aside.Margin and math.abs(rel.X) <= H.Aside.Depth
check("HELP ME: Ann stops just past a doorway, he stands beside it, out of the way", danny.action == "follow" and not inDoor
	and distance(at, origin * livingDoor.at) < half + H.Aside.Step + 3, `{rel.X}, {rel.Z}`)

Moving.admin(ann, "end")
run(0.2)
check("the move ends: he goes, the interior is taken down", MoveHelper.find(ann) == nil and E.destroyed == 1)

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
