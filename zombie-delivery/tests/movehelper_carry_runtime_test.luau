-- 8.6 carrying in two (the owner, carrying the Dining Table with Danny: "The carrying is still bad. He teleports from side
-- to side"; a screenshot: Danny beside the table, at its side, not at its far end; and at the van: "it doesn't look good",
-- Danny bent at the table's side, the table floating between them, "Load" and "Put down" drawn on top of each other).
-- The real server/Moving.luau, server/MoveHelper.luau and server/PairHold.luau on tests/runtime/MovingRuntime.luau's
-- fakes, Config.MoveHelper.HoldLead as the game has it and a leader with a ping (0.15 s: Danny is aimed ahead). Danny's
-- hold is played as Roblox's constraints do it (no `keep` in this mover: server/MoveHelper.luau's keepAt steps his root
-- toward his hold's aim at its top speed × dt at most); the piece is welded to Sol as Moving welded it at the lift (its
-- frame from her root kept every step: a WeldConstraint), and Sol steers as client/PairSteer.luau does (shared/
-- PairCarry.luau: the heading turns PairTurn at most, a way behind walked backwards). Two pieces at their real sizes
-- (shared/FurnitureLooks.luau): the Sofa (long: 7.2 × 3.2) and the Dining Table (square-ish: 6.0 × 3.8). Each is lifted
-- with Danny (her call: he walks to his end and up it goes at once, no lift check after the wait) and walked along a way
-- with 90° turns (the heading turns: a U-turn of two), a 180° (the way behind: walked backwards), straight on, a stop,
-- and a stretch where the server hears her walk unevenly (two steps' walk in every other look, as a network does).
--   * the piece lies along the carry (its length along her facing), low (its grips at the hands, its bottom off the
--     floor), Sol at one end of its length, Danny at the other, the end decided once at the lift (MoveHelperBrain.holdEnd)
--   * every step: Danny moves no more than his end moved plus HoldLead.Rate × dt (his aim moves with his end, his lead
--     at Rate on top), never more than his top speed × dt, at walking pace never more than the pair walk's top speed;
--     he stays at his end (past the piece's middle along his end's axis, beside it no more than its half width and his
--     lead), his end never another one; the piece never jumps (its frame from Sol's root the weld's, its turn PairTurn ×
--     dt at most); his legs step while his end walks
--   * the arms: Sol's and Danny's on their end's edge at the grips' height (CarryAt / CarrySize)
--   * at the van: Load the one prompt drawn for the carrier at its back (the piece's Put down there draws nothing: its
--     Style Custom, G still puts it down), Put down drawn again away from it
-- On 8.5's code this fails: the piece is welded broadside (its length across Sol), Danny is at its long side's middle
-- (the screenshot), and his aim is Sol's root velocity × leadTime ahead, taken at once: a step back, a turn's step aside,
-- an uneven look throw it across, and he runs there faster than his end moves (the side to side).
local E = require("./MovingRuntime")
local Moving = require("./MovingServer")
local MoveHelper = require("./MoveHelperServer")
local Config = require("./Config")
local SandboxMap = require("./SandboxMap")
local Rules = require("./MovingRules")
local Brain = require("./MoveHelperBrain")
local PairCarry = require("./PairCarry") -- (client/PairSteer.luau's steering)
local FurnitureLooks = require("./FurnitureLooks")

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
local PAIR = WALK * T.Speed.Pair
local DT = 0.1
local PING = 0.15
local M = E.Mock
local V3 = M.Vector3.new
local CF = M.CFrame.new
local workspace = M.workspace
H.HoldLead.Base, H.HoldLead.Ping = E.gameLead.Base, E.gameLead.Ping -- (the game's lead)
-- 9.2: the hold the SERVER keeps, his lead and all (Danny's when no leader's client drives him: a drive it took back,
-- PairLead.On false): Sol's client drives none here (tests/movehelper_backwards_runtime_test.luau drives him)
H.PairLead.On = false
local RATE = H.HoldLead.Rate or 5 -- (the lead's change a second at most; 8.5's code had none: the same bound for it)
local EDGE = (H.Edge or { Width = 0 }).Width
T.Doors.Walk = false -- (the walk-in doors off: these walks stay in the house)
local SOFA = FurnitureLooks.Items.sofa.size
local TABLE = FurnitureLooks.Items.dining_table.size
E.items.sofa.size = V3(SOFA.X, SOFA.Y, SOFA.Z) -- (the runtime's sofa and slab at the real Sofa's and Dining Table's sizes)
E.items.slab.size = V3(TABLE.X, TABLE.Y, TABLE.Z)
E.items.slab.name = "Dining Table"

local HOUSE = "lone_house" -- (10.6: a run on the lone house, the van at its curb)
local door, facing, outside = E.doorOf(SandboxMap.house(HOUSE))
local lobby = V3(SandboxMap.Lobby.spawn.x, 3, SandboxMap.Lobby.spawn.z)
E.Zombies.findSpot = function(center: any): any
	return center + V3(900, 0, 0)
end

-- His own walk (to her call): straight toward the point, speed × dt a step. Holding the far end the mover has no `keep`:
-- MoveHelper's keepAt steps his root toward his hold's aim at its top speed × dt at most (the constraints).
MoveHelper.useMover({
	move = function(body: any, to: any, speed: number, dt: number)
		local root = body.root
		local here = root.Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		local length = way.Magnitude
		if length > 1e-6 then
			local step = math.min(length, speed * dt)
			root.CFrame = CF(here.X + way.X / length * step, here.Y, here.Z + way.Z / length * step)
		end
		body.walking = true
	end,
	halt = function(body: any)
		body.walking = false
	end,
})

local sol = E.player(44, "Sol", lobby)
sol.GetNetworkPing = function()
	return PING -- (Danny is aimed HoldLead.Base + this ahead)
end
Moving.useArt(E.art)
Moving.parkVan = E.parkVan
Moving.start()

local function promptIn(model: any, action: string?): any
	for _, d in model:GetDescendants() do
		if d.ClassName == "ProximityPrompt" and (action == nil or d.ActionText == action or string.find(tostring(d.ActionText), action, 1, true) == 1) then
			return d
		end
	end
	return nil
end
local function itemModel(spot: number): any
	for _, d in workspace:GetDescendants() do
		if d.ClassName == "Model" and d:GetAttribute("MoveSpot") == spot and not d.destroyed then
			return d
		end
	end
	return nil
end
local function flat(a: any, b: any): number
	return V3(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function yawOf(frame: any): number
	local look = frame.LookVector
	return PairCarry.yawOf(look.X, look.Z)
end
local danny: any = nil
local function holding(): boolean
	return select(2, Rules.holding(danny.s.move, danny.id)) == "helper"
end
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / DT - 1e-9) do
		E.clock += DT
		MoveHelper.step(DT)
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

local started = E.startRun(sol, HOUSE)
check("a solo run starts", started == nil, started)
Moving.step()
danny = MoveHelper.find(sol)
check("Danny comes, Sol's from the start (10.1 free)", danny ~= nil and danny.body ~= nil and danny.hirer == sol)
local body = danny.body
local truck = E.cars[sol]
local cargoDoor = truck.chassis:FindFirstChild("CargoDoor")
local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{HOUSE}`)
E.place(sol, outside)
promptIn(site, "Enter house").Triggered:Fire(sol)
local character = sol.Character

-- One carry: Sol at the piece, her Lift calls Danny; he walks over and up it goes; the way with its turns -------------------

local function carry(spot: number, name: string, size: any)
	local model = itemModel(spot)
	local root = model.PrimaryPart
	-- Sol at its +X end, facing it (as anybody takes a table: at its end)
	local lying = root.CFrame
	local at = lying * V3(size.X / 2 + 1.5, 0, 0)
	E.rootOf(sol).CFrame = M.CFrame.lookAt(V3(at.X, E.rootOf(sol).Position.Y, at.Z), V3(lying.X, E.rootOf(sol).Position.Y, lying.Z))
	local said = #E.said
	local lift = promptIn(model, "Lift")
	check(`{name}: its Lift`, lift ~= nil)
	-- the grip on, as in the game (the runtime turns it off for the moves' other tests): his arrival opens no lift check
	Config.CarryGrip.On = true
	local from = #E.messages
	lift.Triggered:Fire(sol)
	local waited = 0
	local up = run(30, function()
		waited += DT
		return holding()
	end)
	local checks = 0
	for index = from + 1, #E.messages do
		local m = E.messages[index]
		if m.player == sol and m.remote == "Moving" and m.kind == "grip" and m.a == "open" then
			checks += 1
		end
	end
	check(`8.6 {name}: Sol's Lift calls Danny, he walks to his end and up it goes at once on "On three... lift!" (the grip on: no lift check after the wait)`,
		up and character:GetAttribute("MoveCarry") == spot and E.saidSince("On three... lift!", said) and danny.call == nil and checks == 0, `{waited} s, {checks} checks`)
	check(`8.6 {name}: …balanced (he steadies it): the steady walk`, math.abs((character:GetAttribute("CarrySpeed") or 0) - PAIR * Config.CarryGrip.SteadySpeed) < 1e-6,
		character:GetAttribute("CarrySpeed"))
	Config.CarryGrip.On = false -- (no wobble checks on the way below: its steps are the hold's)
	-- the weld Moving made: the piece's frame from her root, kept every step (a WeldConstraint)
	local weld = E.rootOf(sol).CFrame:ToObjectSpace(root.CFrame)
	local function follow()
		root.CFrame = E.rootOf(sol).CFrame * weld
	end
	local long = if size.X >= size.Z then V3(1, 0, 0) else V3(0, 0, 1)
	local lengthWay = weld.Rotation * long -- (its length's way in Sol's frame)
	local half = math.max(size.X, size.Z) / 2
	local width = math.min(size.X, size.Z)
	local feet = -(E.rootOf(sol).Size.Y / 2 + character:FindFirstChildOfClass("Humanoid").HipHeight)
	local bottom = weld.Position.Y - size.Y / 2
	check(`8.6 {name}: it lies along the carry (its length along Sol's facing), low: its bottom off the floor, its top not over her head`,
		math.abs(math.abs(lengthWay.Z) - 1) < 1e-6 and math.abs(weld.Position.X) < 1e-6 and weld.Position.Z < 0
		and bottom > feet + 0.2 and weld.Position.Y + size.Y / 2 < 1.5, `{lengthWay.X}, {lengthWay.Z}; bottom {bottom - feet} over the floor`)
	follow()
	run(1, function()
		follow()
		return false
	end)
	-- his end: the hold's (8.6: decided at the lift), else where he holds it now (8.5's code), in the piece's frame
	local axis = danny.holdEnd or (function(): any
		local p = root.CFrame:PointToObjectSpace(body.root.Position)
		return V3(p.X, 0, p.Z)
	end)()
	local decided = danny.holdEnd
	local inPiece = root.CFrame:PointToObjectSpace(body.root.Position)
	local solIn = root.CFrame:PointToObjectSpace(E.rootOf(sol).Position)
	local alongLength = if size.X >= size.Z then inPiece.X else inPiece.Z
	local solAlong = if size.X >= size.Z then solIn.X else solIn.Z
	check(`8.6 {name}: Danny at the far end of its length, across it from Sol (decided at the lift: MoveHelperBrain.holdEnd)`,
		axis ~= nil and math.abs(alongLength) >= half + H.Standoff - 0.05 and solAlong * alongLength < 0 and math.abs(solAlong) > half
		and math.abs(if size.X >= size.Z then inPiece.Z else inPiece.X) < 0.05, `Danny {inPiece.X}, {inPiece.Z}; Sol {solIn.X}, {solIn.Z}`)
	check(`8.6 {name}: turned to it (to Sol)`, body.root.CFrame.LookVector:Dot(root.Position - body.root.Position) > 0)
	-- the arms: on their end's edge at the grips' height (client/ArmPose.luau's box)
	local solAt, solSize = character:GetAttribute("CarryAt"), character:GetAttribute("CarrySize")
	local hisAt, hisSize = body.model:GetAttribute("CarryAt"), body.model:GetAttribute("CarrySize")
	local grip = if Rules.pairLift then select(2, Rules.pairLift(size.Y, feet)) else 0 / 0
	local gripsAt = E.rootOf(sol).Position.Y + grip -- (the grips' height in the world)
	check(`8.6 {name}: Sol's hands on its near end's edge at its grips (close in front, at her hands' height), Danny's on his end's`,
		M.typeof(solAt) == "Vector3" and math.abs(solAt.Y - grip) < 1e-6 and grip < 0 and solAt.Z < 0 and solAt.Z > -1.5 and solSize.X <= math.min(width, EDGE) + 1e-6
		and M.typeof(hisAt) == "Vector3" and math.abs(body.root.Position.Y + hisAt.Y - gripsAt) < 1e-3 and hisAt.Z < 0 and hisAt.Z > -1.5
		and hisSize.X <= math.min(width, EDGE) + 1e-6, `Sol {solAt and solAt.Y}, Danny {hisAt and hisAt.Y}, grips {grip}`)
	-- The way: each leg Sol wants to walk `way` (a world direction) for `seconds`, steered as PairSteer does (her own
	-- frame, `truth`); `uneven`: the server hears her walk in bursts (her root as it last heard it on odd steps, then
	-- both steps' walk at once)
	local truth = E.rootOf(sol).CFrame
	local steer = PairCarry.newSteer(yawOf(truth))
	local worst = { over = 0, overTop = 0, overWalk = 0, inward = math.huge, aside = 0, flips = 0, pieceOff = 0, pieceStep = 0, turned = 0, steps = 0, legsSteps = 0, legsMoving = 0 }
	local lastAt = body.root.Position
	local lastStep = lastAt
	local lastEnd = root.CFrame * axis
	local lastPiece = root.Position
	local sign = if alongLength > 0 then 1 else -1
	local function step(wayX: number, wayZ: number, uneven: boolean, index: number)
		local before = yawOf(truth)
		steer.heading = before
		local factor = PairCarry.steer(steer, wayX, wayZ, DT, math.rad(H.PairTurn))
		local speed = (character:GetAttribute("CarrySpeed") or 0) * factor
		truth = CF(truth.Position + V3(wayX, 0, wayZ) * speed * DT) * M.CFrame.Angles(0, steer.heading, 0)
		worst.turned = math.max(worst.turned, math.abs(PairCarry.wrap(steer.heading - before)))
		if not uneven or index % 2 == 0 then
			E.rootOf(sol).CFrame = truth -- (the server's look at her)
		end
		follow()
		local strides = #E.strides
		E.clock += DT
		MoveHelper.step(DT)
		if index % 2 == 0 then
			Moving.step()
		end
		-- the piece never jumps: still where the weld keeps it (nothing re-pivoted it), a step's walk and turn at most
		worst.pieceOff = math.max(worst.pieceOff, (root.Position - (E.rootOf(sol).CFrame * weld).Position).Magnitude)
		worst.pieceStep = math.max(worst.pieceStep, (root.Position - lastPiece).Magnitude)
		lastPiece = root.Position
		-- Danny: his step against his end's own and his top speed
		local here = body.root.Position
		local endNow = root.CFrame * axis
		local stepped = flat(here, lastStep)
		worst.overTop = math.max(worst.overTop, stepped - danny.holdLimit * DT)
		if not uneven then
			worst.overWalk = math.max(worst.overWalk, stepped - Brain.holdSpeed(character:GetAttribute("CarrySpeed") or PAIR) * DT) -- (her walk: the pair's, steady)
		end
		-- (heard unevenly: over the two steps of each burst, a step's catching up inside it)
		local span = if uneven then 2 else 1
		local endMoved = flat(endNow, lastEnd)
		if not uneven or index % 2 == 0 then
			worst.over = math.max(worst.over, flat(here, lastAt) - (endMoved + RATE * DT * span))
			lastAt, lastEnd = here, endNow
		end
		lastStep = here
		-- he stays at his end: past the middle along his end's axis, beside it no more than its half width and his lead
		local inside = root.CFrame:PointToObjectSpace(here)
		local along = (if size.X >= size.Z then inside.X else inside.Z) * sign
		local aside = math.abs(if size.X >= size.Z then inside.Z else inside.X)
		worst.inward = math.min(worst.inward, along)
		worst.aside = math.max(worst.aside, aside)
		if along <= 0 or danny.holdEnd ~= decided then
			worst.flips += 1
		end
		-- his legs step while his end walks (Npcs.stride)
		if endMoved / DT >= H.HoldLegs.From * 1.5 then
			worst.legsMoving += 1
			for n = strides + 1, #E.strides do
				if E.strides[n].npc == body.model and math.abs(E.strides[n].speed) > 0.5 then
					worst.legsSteps += 1
					break
				end
			end
		end
		worst.steps += 1
	end
	local function leg(wayX: number, wayZ: number, seconds: number, uneven: boolean?)
		for index = 1, math.floor(seconds / DT + 0.5) do
			step(wayX, wayZ, uneven == true, index)
		end
	end
	-- facing into the house's room along its length: the way behind her first (backwards, away from Danny)
	local f = E.rootOf(sol).CFrame.LookVector
	local fx, fz = f.X, f.Z
	local rx, rz = -fz, fx -- (her right: a quarter turn)
	leg(-fx, -fz, 1.5) -- backwards (Danny follows)
	leg(rx, rz, 2.5) -- a 90° turn (the heading turns at PairTurn)
	leg(fx, fz, 2.5) -- …and again: a U-turn in all (180° of heading)
	leg(-fx, -fz, 1.5) -- the way back: 180° (walked backwards, no turn)
	leg(-rx, -rz, 2, true) -- a turn while the server hears her unevenly
	leg(fx, fz, 1) -- straight on
	leg(0, 0, 1.5) -- she stops
	check(`8.6 {name}: every step Danny moves no more than his end moved + HoldLead.Rate × dt (no jump of his aim: the side to side)`,
		worst.over <= 1e-3 and worst.steps > 100, `{worst.over} studs over in a step of {worst.steps}`)
	check(`8.6 {name}: …and never more than his top speed × dt; at walking pace never more than the pair walk's (HoldMargin, HoldExtra)`,
		worst.overTop <= 1e-6 and worst.overWalk <= 1e-6, `{worst.overTop}, {worst.overWalk}`)
	check(`8.6 {name}: he stays at his end all the way (past its middle along his end's axis; beside it no more than its half width + his lead), his end never another one`,
		worst.flips == 0 and worst.inward > 0.5 and worst.aside <= width / 2 + H.HoldLead.Far, `{worst.flips} flips, {worst.inward} past the middle at least, {worst.aside} aside at most`)
	local swing = (Config.Cargo.CarryFront + half) * math.rad(H.PairTurn) * DT -- (its middle round her in a step's turn)
	check(`8.6 {name}: the piece never jumps (where the weld keeps it: a step's walk and turn at most, its turn PairTurn × dt)`,
		worst.pieceOff <= 1e-6 and worst.pieceStep <= 2 * PAIR * Config.CarryGrip.SteadySpeed * DT + swing + 1e-6 and worst.turned <= math.rad(H.PairTurn) * DT + 1e-6,
		`{worst.pieceOff} off, {worst.pieceStep} a step, {worst.turned} rad`)
	check(`8.6 {name}: his legs step while his end walks (Npcs.stride)`, worst.legsMoving > 50 and worst.legsSteps >= worst.legsMoving * 0.9,
		`{worst.legsSteps} of {worst.legsMoving}`)
	local rest = (root.CFrame * axis)
	check(`8.6 {name}: she stops: he is at his end, his lead gone`, flat(body.root.Position, rest) < 0.05 and math.abs(danny.trail.leadX or 0) + math.abs(danny.trail.leadZ or 0) < 0.05,
		flat(body.root.Position, rest))
	return model, follow
end

-- The Sofa (long), then the Dining Table (square-ish) ----------------------------------------------------------------------

local sofa = carry(3, "the Sofa", SOFA)
E.Net.get("PutDown").OnServerEvent:Fire(sol)
run(0.5)
check("the Sofa down: both pairs of hands free", character:GetAttribute("MoveCarry") == nil and not holding() and danny.holdEnd == nil and sofa ~= nil)
local tableModel, follow = carry(6, "the Dining Table", TABLE)

-- At the van: Load the one prompt drawn ----------------------------------------------------------------------------------------

local putDown = promptIn(tableModel, "Put down")
check("8.6 away from the van: the Dining Table's Put down drawn (its Style Default)", putDown ~= nil and putDown.Style ~= "Custom", putDown and putDown.Style)
truck.model:SetAttribute("BackOpen", true)
local interior = E.interiors[#E.interiors]
E.place(sol, interior.Position + V3(0, 3, 1))
follow()
promptIn(workspace, "Leave house").Triggered:Fire(sol)
follow()
run(0.3, function()
	follow()
	return false
end)
local back = cargoDoor.WorldPosition
-- Sol walks straight to `to` at the pair's walk, facing it (the piece where the weld keeps it), a step every DT
local function walkTo(to: any)
	for index = 1, 400 do
		local here = E.rootOf(sol).Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		if way.Magnitude < 0.05 then
			break
		end
		local nextAt = here + way.Unit * math.min(PAIR * DT, way.Magnitude)
		E.rootOf(sol).CFrame = M.CFrame.lookAt(nextAt, V3(back.X, nextAt.Y, back.Z))
		follow()
		E.clock += DT
		MoveHelper.step(DT)
		if index % 2 == 0 then
			Moving.step()
		end
	end
	Moving.step()
	Moving.step()
end
local atBack = V3(back.X, E.rootOf(sol).Position.Y, back.Z + 6)
walkTo(atBack)
local load = promptIn(truck.model, "Load")
check("8.6 at the van's open back with it: Load drawn (\"Load Dining Table\"), the piece's Put down not (Style Custom: G still puts it down)",
	load ~= nil and load.Enabled and load.ActionText == "Load Dining Table" and putDown.Style == "Custom" and putDown.Enabled and holding(),
	`{load and load.ActionText} / {putDown.Style}`)
walkTo(atBack + V3(0, 0, 30))
check("8.6 …walked away from the van: Put down drawn again", putDown.Style ~= "Custom" and not load.Enabled and holding(), putDown.Style)
walkTo(atBack)
putDown.Triggered:Fire(sol)
run(0.3)
check("8.6 …G at the van still puts it down (the prompt only draws nothing)", character:GetAttribute("MoveCarry") == nil and not holding())

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
