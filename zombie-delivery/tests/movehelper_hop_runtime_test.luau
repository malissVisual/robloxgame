-- 8.3 Danny's hops (the owner: "the helping works weirdly, he just jumps weirdly", carrying a Dining Table together
-- inside the house): the real server/Moving.luau, server/MoveHelper.luau and server/PairHold.luau (his own mover: the
-- real constraints made on the recorder) with the real house art (shared/FurnitureLooks.luau, shared/HouseLayout.luau,
-- server/HouseInterior.luau: its Shell, the porch's roof, the real Dining Table), and a ray down that finds the parts'
-- tops the way Roblox's does (a ray from inside a part does not find it; its filter kept; CanCollide false skipped).
-- The constraints are played by the test: after each of his steps his root is where they pull it (the align's far end
-- along the ground, the lift's height; a hold without a lift, 8.1's: the far end's height too).
--   * his paths never jump: AgentCanJump and AgentCanClimb false, a Jump waypoint never walked to, every walk with
--     Npcs.walkTo's jump = false
--   * the Dining Table carried toward the front door, Ann walking forwards, Danny ahead of her backwards: his end out
--     on the porch, under its roof (10.5 over the floor; the old ray started 6 over the table's middle, 10.7: it found
--     the roof and he popped HoldStep up): his feet stay on the floor
--   * Ann jumps with it (6 studs): he stays on the floor (the old clamp to her root's height, and the old ray then
--     starting over the ceiling and finding its top, lifted him 8.5)
--   * the rays under his end never find the piece, his body or a player's (8.1's did not either: not a cause)
--   * outside: a kerb under his end, he steps up onto it at HoldClimb a second at most; an eave over it never found
--   * his legs (MoveHelperBrain.holdLegs through Npcs.stride): his root driven forwards, backwards, sideways and on a
--     diagonal: each step the direction and the rate the module picks (8.1's: still legs sideways, a diagonal's legs
--     at its share along his facing only)
-- (Run on 8.1's MoveHelper / PairHold / MoveHelperBrain, the porch, the jump, the eave and the legs checks fail.)
-- 9.2 (you drive Danny's end): his body is Ann's (she leads), her client sets his hold's goals (the real client/
-- PairLead.luau, E.leadClient: its own rays down under his end, the same rules: from a step over the floor under her
-- down to a step under it, the house's Shell inside, never the pieces, his body or hers outside), and the constraints
-- are played on what it set: the lift at its MaxVelocity (HoldClimb) up and down, as Roblox's AlignPosition does.
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
local C = Config.Cargo
local WALK = Config.Movement.Walk
local M = E.Mock
local V3 = M.Vector3.new
local workspace = M.workspace

-- the real art (the interiors' origins given to the runtime as in tests/movehelper_art_runtime_test.luau)
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

-- A ray down that finds the highest top of a part under its start, between its start and its end: the parts of an
-- Include list, or of the workspace but an Exclude list's; a part it starts inside is not found (Roblox's), nor one
-- with CanCollide false (RespectCanCollide). Every ray is kept (its start, reach and filter).
local rays: { any } = {}
local stepping = false -- (a ray cast in one of his steps: MoveHelper's own)
local clientRays = false -- (9.2 a ray cast by Ann's client/PairLead.luau)
local function within(part: any, list: { any }): boolean
	for _, top in list do
		if part == top or part:IsDescendantOf(top) then
			return true
		end
	end
	return false
end
workspace.Raycast = function(_, origin: any, direction: any, params: any): any
	local include = params ~= nil and params.FilterType == "Include"
	local list = (params and params.FilterDescendantsInstances) or {}
	table.insert(rays, { origin = origin, direction = direction, include = include, list = list, his = stepping, client = clientRays })
	local best: number? = nil
	for _, root in (if include then list else { workspace }) do
		for _, part in root:GetDescendants() do
			if not part:IsA("BasePart") or part.CanCollide == false or part.Size == nil or part.CFrame == nil or (not include and within(part, list)) then
				continue
			end
			local size = part.Size
			local p = part.CFrame:PointToObjectSpace(origin)
			if math.abs(p.X) > size.X / 2 or math.abs(p.Z) > size.Z / 2 then
				continue
			end
			local top = part.CFrame.Position.Y + size.Y / 2
			if origin.Y > top and top >= origin.Y + direction.Y and (best == nil or top > best) then
				best = top
			end
		end
	end
	return if best then { Position = V3(origin.X, best, origin.Z) } else nil
end

-- His paths: a PathfindingService that records how his Path is made and gives a way with a Jump waypoint in it (a
-- jump over a piece of furniture between two walks).
local created: { any } = {}
local jumpPoints: { any } = {}
local computed = 0
E.services.PathfindingService = {
	CreatePath = function(_, params: any): any
		table.insert(created, params)
		local path: any = { Status = "NoPath", points = {} }
		function path.ComputeAsync(self: any, from: any, to: any)
			computed += 1
			local mid = from + (to - from) * 0.5
			local hop = mid + V3(2.5, 0, 0)
			table.insert(jumpPoints, hop)
			self.points = {
				{ Position = from, Action = "Walk" },
				{ Position = mid, Action = "Walk" },
				{ Position = hop, Action = "Jump" },
				{ Position = to, Action = "Walk" },
			}
			self.Status = "Success"
		end
		function path.GetWaypoints(self: any): any
			return self.points
		end
		return path
	end,
}
-- His walks (server/Npcs.luau's walkTo: the runtime's walks nowhere) kept: where to, with what options.
local walks: { any } = {}
E.Npcs.walkTo = function(_npc: any, point: any, _arrived: any, _timeout: any, options: any)
	table.insert(walks, { point = point, options = options })
end

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
local danny: any = nil
local carried: any = nil
-- The piece in Ann's arms (the weld, in Roblox): server/Moving.luau's place for a carried piece (CarryLow over her
-- root's middle, CarryFront in front of it), so its middle is as high as in the game.
local function hold()
	if carried and not E.welded(carried) then -- (8.6: where Moving's weld keeps it: carried in two, lengthwise and low)
		local size = carried.PrimaryPart.Size
		carried.PrimaryPart.CFrame = E.rootOf(ann).CFrame * M.CFrame.new(0, C.CarryLow + size.Y / 2, -(C.CarryFront + size.Z / 2))
	end
end
-- The constraints (Roblox's physics): his root where his hold pulls it, after each of his steps. 9.2: Ann's client sets
-- the goals first while she drives him (client/PairLead.luau: its rays marked `client`), the lift climbs at its
-- MaxVelocity at most.
local playing = true
local lead: any = nil
local function physics()
	local body = danny and danny.body
	local grip = body and body.grip
	if not playing or not grip or grip.align.Parent == nil then
		return
	end
	local drive = if lead then lead.of(body.model) else nil
	if drive then
		clientRays = true
		lead.step(drive, 0.1, E.rootOf(ann), ann.Character:FindFirstChildOfClass("Humanoid"))
		clientRays = false
	end
	-- (the goals as they were set: the recorder answers an instance's Position from its default CFrame)
	local goal = grip.align.props.Position
	local lift = grip.lift
	local y = goal.Y
	if lift then
		local was = body.root.Position.Y
		local most = lift.MaxVelocity * 0.1
		y = was + math.clamp(lift.props.Position.Y - was, -most, most)
	end
	body.root.CFrame = M.CFrame.new(goal.X, y, goal.Z) * grip.orient.CFrame.Rotation
end
-- Steps of 0.1 s (his loop's), the move's tick every other one; a path he asked for worked out at once (the runtime
-- keeps a spawned function: his path's).
local function run(seconds: number, done: (() -> boolean)?): boolean
	for index = 1, math.ceil(seconds / 0.1 - 1e-9) do
		E.clock += 0.1
		local before = E.spawned
		stepping = true
		MoveHelper.step(0.1)
		stepping = false
		local spawned = E.spawned
		if spawned ~= nil and spawned ~= before then
			E.spawned = nil
			spawned()
		end
		physics()
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
local function holding(): boolean
	local _, role = Rules.holding(danny.s.move, danny.id)
	return role == "helper"
end
local function farEnd(): any
	local ends = danny and danny.gripped == carried.PrimaryPart and danny.holdEnd -- (8.6 his end, decided at the lift)
	if ends then
		return carried.PrimaryPart.CFrame * ends
	end
	return (carried.PrimaryPart.CFrame * M.CFrame.new(0, 0, -(carried.PrimaryPart.Size.Z / 2 + H.Standoff))).Position
end
-- Ann walks to `to` with the piece (the leader's client: shared/PairCarry.luau steer, the pair's walk), `look` after
-- each of his steps.
local steer = PairCarry.newSteer(0)
local function heading(): number
	local look = E.rootOf(ann).CFrame.LookVector
	return PairCarry.yawOf(look.X, look.Z)
end
local function walk(to: any, look: (() -> ())?)
	for _ = 1, 400 do
		local here = E.rootOf(ann).Position
		local way = V3(to.X - here.X, 0, to.Z - here.Z)
		if way.Magnitude < 0.05 then
			break
		end
		steer.heading = heading()
		local factor = PairCarry.steer(steer, way.X, way.Z, 0.1, math.rad(ann.Character:GetAttribute("PairTurn") or H.PairTurn))
		local nextAt = here + way.Unit * math.min((ann.Character:GetAttribute("CarrySpeed") or 0) * factor * 0.1, way.Magnitude)
		E.rootOf(ann).CFrame = M.CFrame.new(nextAt) * M.CFrame.Angles(0, steer.heading, 0)
		hold()
		run(0.1)
		if look then
			look()
		end
	end
end

-- A solo run into the real house: Danny comes, his paths never jump ------------------------------------------------------

local started = E.startRun(ann, HOUSE)
check("a solo run into the real house (seed 1955) starts", started == nil and #built == 1, started)
Moving.step()
danny = MoveHelper.find(ann)
lead = E.leadClient(ann) -- 9.2 Ann's client/PairLead.luau
check("Danny comes with the van", danny ~= nil and danny.body ~= nil)
do -- (his body in workspace.Npcs, as server/Npcs.luau's people are, and the van in workspace.Cars, as server/
	-- Vehicles.luau's are: the runtime's stand-ins put them in the workspace)
	local folder = M.Instance.new("Folder")
	folder.Name = "Npcs"
	folder.Parent = workspace
	danny.body.model.Parent = folder
	local cars = M.Instance.new("Folder")
	cars.Name = "Cars"
	cars.Parent = workspace
	E.cars[ann].model.Parent = cars
end
local plan = built[1].plan
local origin = built[1].origin
local truck = E.cars[ann]

-- (8.3: across the yard by his paths, back to his place by the van)
danny.body.root.CFrame = M.CFrame.new(outside + facing * 26 + V3(0, 3, 0))
run(6)
local made = created[1]
check("8.3 his Path: never a jump, never a climb (AgentCanJump, AgentCanClimb false), Config.MoveHelper's Path* numbers", made ~= nil
	and made.AgentCanJump == false and made.AgentCanClimb == false and made.AgentRadius == H.PathRadius and made.AgentHeight == H.PathHeight
	and made.WaypointSpacing == H.PathSpacing, made and made.AgentCanJump)
local hopped = false
for _, point in danny.path do
	for _, hop in jumpPoints do
		if (point - hop).Magnitude < 0.01 then
			hopped = true
		end
	end
end
local walkedToHop, jumpy = false, 0
for _, w in walks do
	for _, hop in jumpPoints do
		if (w.point - hop).Magnitude < 0.01 then
			walkedToHop = true
		end
	end
	if not (w.options and w.options.jump == false) then
		jumpy += 1
	end
end
check("8.3 …a Jump waypoint in his way is never his: not in his path, never walked to (he walks the rest of it)", computed > 0 and #walks > 0
	and not hopped and not walkedToHop and #danny.path > 0, `{computed} paths, {#walks} walks`)
check("8.3 …every walk of his asks Npcs.walkTo for no jump (jump = false)", #walks > 0 and jumpy == 0, jumpy)
check("10.1 Danny is Ann's from the start (her Lift calls him)", danny.hirer == ann)

-- The real Dining Table, lifted together ---------------------------------------------------------------------------------------

local tableSpot: any = nil
for _, s in plan.spots do
	if s.item == "dining_table" then
		tableSpot = s
	end
end
check("the real Dining Table stands in the house: a pair piece, 3.3 studs tall (its middle 4.7 over the floor in Ann's arms)",
	tableSpot ~= nil and FurnitureLooks.Items.dining_table.class == "pair" and math.abs(FurnitureLooks.Items.dining_table.size.Y - 3.3) < 1e-6)
carried = built[1].pieces[tableSpot.id]
local site = workspace:FindFirstChild("Moves"):FindFirstChild(`Move_{HOUSE}`)
E.place(ann, outside)
trigger(promptIn(site, "Enter house"), ann)
local ground = origin.Position.Y
local exitAt = (origin * M.CFrame.new(plan.exit)).Position
-- (the table stood in the hall, its long side across, 14 studs in from the front door: Ann lifts it there facing the
-- door, so it is in front of her and Danny takes the end toward the door; a carried piece put somewhere at once would
-- be "too fast": it would go down)
local tableAt = V3(exitAt.X, ground + carried.PrimaryPart.Size.Y / 2, exitAt.Z + 14)
carried:PivotTo(M.CFrame.lookAt(tableAt, tableAt + V3(0, 0, -1)))
local inHall = V3(exitAt.X, ground + 3, exitAt.Z + 14 + carried.PrimaryPart.Size.Z / 2 + 1.5)
E.rootOf(ann).CFrame = M.CFrame.lookAt(inHall, inHall + V3(0, 0, -1)) -- (facing the table and the front door beyond it)
danny.body.root.CFrame = M.CFrame.new(inHall + V3(0, 0, 5)) -- (in the hall behind her)
trigger(promptIn(carried, "Lift"), ann)
hold()
-- (8.3: Ann's Lift calls him and she waits; his walk goes nowhere here, so CallBlink s later he fades
-- over as the last resort, and up it goes together)
local lifted = run(H.CallBlink + 3, function()
	hold()
	return helped()
end)
hold()
run(0.3)
local body = danny.body
local grip = body.grip
check("Danny takes its far end (faded over as the last resort, 8.3: this runtime's walk goes nowhere)", lifted and holding() and helped())
check("8.3 his hold: the align along the ground only, his height the lift's (a second AlignPosition on his root, one attachment, up and down only, HoldClimb a second at most)",
	grip ~= nil and grip.align.MaxAxesForce.Y == 0 and grip.align.MaxAxesForce.X > 0 and grip.lift ~= nil and grip.lift.Parent == body.root
	and grip.lift.Mode == "OneAttachment" and grip.lift.Attachment0 == grip.own and grip.lift.MaxAxesForce.X == 0 and grip.lift.MaxAxesForce.Z == 0
	and grip.lift.MaxAxesForce.Y > 0 and grip.lift.MaxVelocity == H.HoldClimb, grip and grip.lift)
check("9.2 …his body Ann's meanwhile (she leads: her client drives his end)", body.root.NetworkOwner == ann and body.model:GetAttribute("PairLead") == ann.UserId
	and lead.of(body.model) ~= nil)

-- Out toward the front door, Ann forwards, Danny ahead of her backwards: his end out on the porch, under its roof ----------------

T.Doors.Walk = false -- (the front door's zone stays shut: Ann stops short of it, his end out on the porch)
local porchRoof: any = nil
for _, part in built[1].model:FindFirstChild("Shell"):GetChildren() do
	if part.Name == "PorchRoof" then
		porchRoof = part
	end
end
local roofTop = porchRoof.CFrame.Position.Y + porchRoof.Size.Y / 2
check("the real porch's roof: its top 10.5 over the floor, under the old ray's start (the table's middle + 6 = 10.7)", porchRoof ~= nil
	and math.abs(roofTop - (ground + 10.5)) < 1e-6 and C.CarryLow + 3 + 3.3 / 2 + 6 > 10.5)
local function underRoof(at: any): boolean
	local p = porchRoof.CFrame:PointToObjectSpace(at)
	return math.abs(p.X) <= porchRoof.Size.X / 2 and math.abs(p.Z) <= porchRoof.Size.Z / 2
end
hold()
run(0.5)
local stand = body.humanoid.HipHeight + body.root.Size.Y / 2
local highest, lowest, porch, steps = -math.huge, math.huge, 0, 0
local function onFeet()
	if not holding() then
		return
	end
	local y = body.root.Position.Y - (ground + stand)
	highest, lowest = math.max(highest, y), math.min(lowest, y)
	steps += 1
	if underRoof(body.root.Position) then
		porch += 1
	end
end
walk(V3(exitAt.X, ground + 3, exitAt.Z + 2.5), onFeet)
for _ = 1, 6 do -- (Ann stands at the door a moment)
	hold()
	run(0.1)
	onFeet()
end
check("8.3 Ann walks forwards to the front door, Danny ahead walking backwards: his end out on the porch under its roof", porch >= 6 and steps > 10
	and holding(), `{porch} steps under the roof of {steps}`)
check("8.3 …his feet on the floor all the way (his root floor + his stand: never popped up onto the roof's height)", highest < 0.06 and lowest > -0.06,
	`{highest} .. {lowest} studs off`)

-- Ann jumps with it: he stays on the floor -------------------------------------------------------------------------------------

local jumpAt = V3(exitAt.X, ground + 3, exitAt.Z + 9)
walk(jumpAt) -- (back into the hall: the way behind her, walked backwards, Danny after her)
run(0.3)
highest, lowest = -math.huge, math.huge
for _, rise in { 1.5, 3, 4.5, 5.5, 6, 5.5, 4.5, 3, 1.5, 0 } do
	E.rootOf(ann).CFrame = M.CFrame.lookAt(jumpAt + V3(0, rise, 0), jumpAt + V3(0, rise, -1))
	hold()
	run(0.1)
	onFeet()
end
check("8.3 Ann jumps 6 studs with the table: Danny's feet stay on the floor (the floor under hers, never her root's height)", highest < 0.06 and lowest > -0.06
	and holding(), `{highest} .. {lowest} studs off`)

-- The rays under his end: never the piece, his body or a player's ----------------------------------------------------------------

local moves = workspace:FindFirstChild("Moves")
local npcs = workspace:FindFirstChild("Npcs")
local function clean(from: number): (boolean, number, number)
	local ok, inside, out = true, 0, 0
	for index = from + 1, #rays do
		local r = rays[index]
		if not r.his then
			continue
		elseif r.include then
			inside += 1
			ok = ok and #r.list == 1 and r.list[1].Name == "Shell" and not within(carried, r.list) and not within(body.model, r.list)
				and not within(ann.Character, r.list)
		else
			out += 1
			ok = ok and within(carried, r.list) and within(body.model, r.list) and within(ann.Character, r.list)
		end
	end
	return ok, inside, out
end
local cleanInside, insideRays = clean(0)
check("8.3 inside, the rays under his end and under Ann: the interior's Shell only (never the table, his body or Ann's)", cleanInside and insideRays > 40
	and carried:IsDescendantOf(moves) and body.model:IsDescendantOf(npcs), insideRays)
-- 9.2 her client's rays down (under her, under his end): inside the Shell first (its floors), else never the pieces,
-- his body or hers
local function cleanClient(from: number): (boolean, number)
	local ok, count = true, 0
	for index = from + 1, #rays do
		local r = rays[index]
		if not r.client or math.abs(r.direction.X) + math.abs(r.direction.Z) > 1e-6 then
			continue
		end
		count += 1
		if r.include then
			for _, top in r.list do
				ok = ok and top.Name == "Shell"
			end
		else
			ok = ok and within(carried, r.list) and within(body.model, r.list) and within(ann.Character, r.list)
		end
	end
	return ok, count
end
local cleanMine, mine = cleanClient(0)
check("9.2 inside, Ann's client's rays down: the interior's Shell first (never the table, his body or hers)", cleanMine and mine > 40, mine)

-- Outside: a kerb under his end (he steps up onto it), an eave over it (never found) ------------------------------------------------

local leave = promptIn(workspace, "Leave house")
walk(V3(exitAt.X, ground + 3, exitAt.Z + 1)) -- (forwards to the door: facing it)
trigger(leave, ann)
hold()
run(0.3)
T.Doors.Walk = true
check("out of the front door together: he came through the fade, still holding", holding() and (E.rootOf(ann).Position - origin.Position).Magnitude > 1000)
local rayMark = #rays
local start = E.rootOf(ann).Position
local street = start.Y - 3 -- (the street under Ann: nothing solid there in this runtime but what the test puts)
local ahead = V3(E.rootOf(ann).CFrame.LookVector.X, 0, E.rootOf(ann).CFrame.LookVector.Z).Unit
local function slab(name: string, at: any, size: any): any
	local part = M.Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = M.CFrame.lookAt(at, at + ahead)
	part.Anchored = true
	part.CanCollide = true
	part.Parent = workspace
	return part
end
local kerbAt = start + ahead * 14
local kerb = slab("Kerb", V3(kerbAt.X, street + 0.5, kerbAt.Z), V3(10, 1, 8))
local eave = slab("Eave", V3(kerbAt.X, street + 10, kerbAt.Z), V3(10, 1, 8))
local climbMost, lastY, onKerb = 0, body.root.Position.Y, 0
highest = -math.huge
walk(start + ahead * 12, function()
	local y = body.root.Position.Y
	climbMost = math.max(climbMost, y - lastY)
	lastY = y
	highest = math.max(highest, y - (street + stand))
	local p = kerb.CFrame:PointToObjectSpace(body.root.Position)
	if math.abs(p.X) <= 5 and math.abs(p.Z) <= 4 and math.abs(y - (street + 1 + stand)) < 0.06 then
		onKerb += 1
	end
end)
check("8.3 outside, a kerb (1 stud) under his end: he steps up onto it, HoldClimb × 0.1 s a step at most (never popped)", onKerb >= 3
	and climbMost <= H.HoldClimb * 0.1 + 1e-6 and climbMost > 0, `{onKerb} steps on it, {climbMost} the most in a step`)
check("8.3 …the eave over it (its top 10.5 over the street) never found: never higher than the kerb", highest < 1 + 0.06, highest)
local cleanOut, _, outRays = clean(rayMark)
check("8.3 outside, the rays: never the pieces (Moves), his body (Npcs) or Ann's", cleanOut and outRays > 10, outRays)
local cleanMineOut, mineOut = cleanClient(rayMark)
check("9.2 outside, Ann's client's rays down: never the pieces, his body or hers", cleanMineOut and mineOut > 10, mineOut)
kerb:Destroy()
eave:Destroy()

-- His legs: his root driven forwards, backwards, sideways, on a diagonal (MoveHelperBrain.holdLegs, Npcs.stride) ---------------

playing = false
local path = body.root.Position
local runs: { { v: any, want: number, name: string } } = {
	{ v = V3(4.9, 0, 0), want = 4.9, name = "forwards (the way ahead of him: Ann backs away)" },
	{ v = V3(-9.8, 0, 0), want = -9.8, name = "backwards (the way behind him: Ann walks toward him)" },
	{ v = V3(0, 0, 5), want = -5, name = "sideways (the way they went: backwards)" },
	{ v = V3(3, 0, -4), want = 5, name = "a diagonal ahead (his whole speed, forwards)" },
	{ v = V3(-0.3, 0, 0), want = 0, name = "standing (under HoldLegs.To)" },
}
local current = runs[1].v
MoveHelper.useMover({
	move = function() end,
	halt = function() end,
	keep = function(b: any)
		path += current * 0.1
		b.root.CFrame = M.CFrame.lookAt(path, path + V3(1, 0, 0)) -- (he faces +X: the piece and Ann)
	end,
})
run(0.1) -- (the first step: from where his hold had him)
for _, r in runs do
	current = r.v
	local worst, count = 0, 0
	for _ = 1, 5 do
		local mark = #E.strides
		run(0.1)
		for index = mark + 1, #E.strides do
			if E.strides[index].npc == body.model then
				worst = math.max(worst, math.abs(E.strides[index].speed - r.want))
				count += 1
			end
		end
	end
	check(`8.3 his legs, his root driven {r.name}: every step at {r.want} studs a second`, count == 5 and worst < 1e-6, `{count} steps, {worst} off`)
end

if failures == 0 then
	print("ALL CHECKS PASSED")
else
	print(`{failures} CHECK(S) FAILED`)
end
