--!strict
-- 7.0, the depot's helper ("Danny from the depot"; the owner's decision in design/rework/NAVRH.md: solo play is allowed
-- with an AI helper). An NPC mover who joins a move whose crew is a single player (Config.MoveHelper.Duo: two players
-- too, off by default). server/Moving.luau calls MoveHelper.sync(session, Moving) every tick: he comes when the crew is
-- small enough and goes when it grows (setting down what he holds); his own loop (Config.MoveHelper.Tick) walks him.
-- His decisions are shared/MoveHelperBrain.luau's (pure: tests/movehelper_test.luau); what he does with the pieces goes
-- through Moving's helper hooks (Moving.helperTake / helperDrop / helperLoad / helperHurt: the same rules, welds and
-- damage as a player's hands); tests/movehelper_runtime_test.luau and tests/movehelper_art_runtime_test.luau run the
-- real module with the real Moving.
-- 7.x Danny, a partner (the owner: "my helper Danny helps weirdly, only some things, and mainly we don't carry anything
-- together"): a clear priority list each step (MoveHelperBrain.decide), and carrying together that just works.
--   * He comes with the move at its van (an orange ZDC mover: server/Npcs.luau's body and name tag) and works while the
--     van stands by the house (within TruckFar of its door); a van that stands far away, he appears at its back.
--   * Carrying together: you Lift a two-person piece and he sprints to its far end (Sprint × the walk; farther than
--     BlinkFar on foot, his path failing, or not there HelpBlink s later: he fades over to it) and takes it ("Got the
--     other end!", "On three... lift!"). Then he moves WITH the piece: his own walk is off (Npcs.carried), constraints on
--     his root (AlignPosition / AlignOrientation to an attachment at the piece's far end, turned to you) hold him there
--     every physics step, on the floor under that end (stairs, steps: within HoldStep of you), through walls and door
--     frames like the piece itself (a collision group nothing collides with), through the front door's fade with you
--     (farther than HoldSnap from his place: put there at once). Never a "too far apart" drop. His arms hold its edge
--     (the Carrying / CarryAt / CarrySize attributes on his body: client/ArmPose.luau), his legs step with his speed
--     (Npcs.stride, backwards when he walks backwards). Your grip bar is easier meanwhile (the character attribute
--     GripSteady: Config.CarryGrip.Steadied × the box). He talks on the way: "Watch the doorframe!", "That's going in
--     the van."
--   * A heavy two-hands piece you carry alone (AssistWeight or more, within AssistFar): he takes its other side (the
--     pair's walk for both: MovingRules.mode), the same way.
--   * On his own: the one-hand and two-hands pieces nobody holds (★ first, then the most value a second of the trip;
--     none that no longer fits the van; never one you are about to lift: a crew player with free hands within Reserve
--     studs of it and nearer than he is gets it, "All yours, boss."), carried out at Speed × a player's walk (× the
--     carry's: slower with a two-hands piece): a path inside the interior (PathfindingService), the front door (he goes
--     through it like the players, without the fade), a path to the van's back. The back open and the van standing:
--     loaded (MovingRules' packer, like Load: "That's going in the van."); shut: he opens it himself (OpenBack, else
--     "Open the back, boss!" and WaitShut s, then set down beside it); no room: set down beside the van ("Van's full,
--     boss - drive it to the Wall?").
--   * The van's back: somebody of the crew coming with a piece within OpenNear of the shut back while he is within
--     OpenFar of it: he opens it ("I'll get the doors!").
--   * Unstuck: no progress for StuckRepath s, a new path; StuckSnap s, he appears at his way's next point (Nudge studs
--     at most). Where he stands still (waiting, behind you) he keeps out of the doorways (MoveHelperBrain.aside).
--   * The orders (the player attribute MoveHelper = the one in force, MoveHelperDoing = what he does: client/
--     MoveHelperHud.luau's strip under the move's panel; the Moving remote's ("helper", order)): "help" (Help me: he
--     follows you, through the doors too, and lifts with you), "carry" (Carry small stuff), "wait" (Wait at the van).
--   * He stays out of fights: a zombie within FleeRange, he runs (never while holding the other end of your piece). The
--     zombies go after him like after a player on foot (Zombies.extraTargets); a bite knocks what he holds
--     (Moving.helperHurt); at 0 health he drops it (knocked) and lies down; he is back at the van Respawn s later.
--   * He talks a little: a speech bubble (Npcs.say) on the way's events, never the same line within TalkRepeat s.
-- Performance: one helper per move, one loop for all of them, a path at most every Repath s (computed in the background,
-- one Path object each), his walk ordered again only when its goal moves (Npcs.walkTo), the lists he chooses from kept
-- and refilled (every Think s), the van's room for each piece worked out only when the load changes; carrying together
-- the physics engine moves him (the loop only re-aims the far end's attachment, a ray down a step).
--   MoveHelper.sync(s, port)   Moving's tick: the move's crew (he comes or goes) and his hands (Moving's helper hooks)
--   MoveHelper.step(dt)        one step of every helper (his loop's; the runtime test calls it)
--   MoveHelper.useMover(m)     how he walks (a test's: the Luau CLI has no physics and no pathfinding)
--   MoveHelper.nameOf(id)      his name by his id in a move's rules (nil: not a helper's id)
--   MoveHelper.find(player)    the helper on this player's move (his state: tests, the admin)
--   MoveHelper.order(p, mode)  7.0 planning: an order as the Moving remote's ("helper", mode) (server/Moving.luau: the
--                              quick chat's "Need a hand here" is HELP ME)
-- 7.x farm move: a place with several ways in and out (a farm's front door and barn doors: the session's `ways`, each
-- an exit inside, where you come in by it and its door's outside) has him take the nearest way he may (Moving's
-- helperExits: a piece may only leave by the exits it fits through) and come out at its own door.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Rules = require(Shared.MovingRules)
local Brain = require(Shared.MoveHelperBrain)
local Npcs = require(script.Parent.Npcs)
local Vehicles = require(script.Parent.Vehicles)
local Zombies = require(script.Parent.Zombies)

local cfg = Config.MoveHelper
local MoveHelper = {}

-- His hands: server/Moving.luau's helper hooks (Moving itself is passed: no require loop).
export type Port = {
	helperTake: (s: any, spot: number, npc: Model) -> (boolean, string?),
	helperDrop: (s: any, npc: Model, why: string) -> (),
	helperLoad: (s: any, npc: Model) -> (boolean, string?),
	helperHurt: (s: any, npc: Model, hp: number) -> (),
	helperExits: ((s: any, spot: number?) -> { number })?, -- 7.x farm move: the ways out he may take with it
}

-- 7.x his hold on the far end of your piece (the real mover's): the attachment on the piece and on his root, the two
-- constraints, his parts' own collision groups (given back when he lets go).
export type Grip = {
	anchor: BasePart,
	far: Attachment,
	own: Attachment,
	align: AlignPosition,
	orient: AlignOrientation,
	groups: { [BasePart]: string },
	offset: CFrame,
	lastAt: Vector3?,
}

-- 7.x farm move: one way in and out (the house's front door; a farm's barn doors too): the exit inside, where he comes
-- in, the door's outside, as Brain.Doors for the costs.
type Way = { exitIn: Vector3, entryIn: CFrame, outside: CFrame, doors: Brain.Doors }

export type Body = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	walking: boolean,
	ordered: Vector3?, -- where the walk was last ordered
	orderedAt: number,
	speed: number,
	path: Path?, -- his PathfindingService path (made once)
	grip: Grip?, -- 7.x carrying together (the real mover)
	alpha: { [Instance]: number }?, -- 7.x his parts' own transparency (a fade-over)
	fade: number, -- 7.x the fade-over in progress
}

-- How he walks: one step toward `to` at `speed` studs / s; a stop; his way round the walls (may yield; nil: straight).
-- 7.x carrying together: keep him at `offset` in `anchor`'s frame (the far end of your piece) / let go of it; a fade-in
-- where he was just put (the fade-over). Without keep he is simply put there (a test: no physics).
export type Mover = {
	move: (body: Body, to: Vector3, speed: number, dt: number) -> (),
	halt: (body: Body) -> (),
	route: ((body: Body, from: Vector3, to: Vector3) -> { Vector3 }?)?,
	keep: ((body: Body, anchor: BasePart, offset: CFrame, dt: number) -> ())?,
	free: ((body: Body) -> ())?,
	appear: ((body: Body) -> ())?,
}

-- A crew player with free hands (a piece they are about to lift is theirs).
type Free = { inside: boolean, x: number, z: number }

type Helper = {
	s: any, -- server/Moving.luau's Session (read here: move, site, origin, plan, items, truck, owner, members, ended, id)
	port: Port,
	id: number, -- his id in the move's rules (MovingRules' holders): ID_BASE - the move's id
	mode: Brain.Mode,
	body: Body?,
	hooks: { RBXScriptConnection },
	health: number, -- his health a step ago (a bite takes a share of what he holds)
	dead: boolean,
	downAt: number,
	action: string,
	spot: number?,
	fleeing: boolean,
	fleeAt: Vector3?,
	fleeSet: number,
	stuckFor: number,
	repathed: boolean, -- a new path asked in this stuck spell (StuckRepath)
	lastPos: Vector3?,
	doorAt: number, -- when he last went through the front door (not back at once)
	path: { Vector3 },
	pathIndex: number,
	pathGoal: Vector3?,
	pathAt: number,
	pathing: boolean,
	pathFailedAt: number, -- 7.x when his last path failed (a lift: he fades over)
	gaveUp: { [number]: number }, -- the lifts whose take failed: until when (HelpRetry s; or the piece goes down, an order)
	helpSince: number, -- 7.x when he set off to your lift (HelpBlink)
	gripped: BasePart?, -- 7.x the piece whose far end he holds (its root)
	holdOffset: CFrame?, -- 7.x his place in its frame
	steadied: Model?, -- 7.x the carrier's character with GripSteady
	lineKey: string?, -- 7.x a line to say at lineAt ("On three... lift!" after "Got the other end!")
	lineAt: number,
	vanSaid: number?, -- 7.x the piece "That's going in the van." was said for
	waited: number, -- s at the van's shut back with a piece
	dropping: boolean, -- he sets the piece in his arms down beside the van (no room, the back stayed shut)
	thinkAt: number,
	lift: number?,
	assist: number?,
	pick: number?,
	full: boolean,
	toldFull: boolean, -- "Van's full" said since it got full
	fitKey: number, -- the van's load when fits was worked out
	fits: { [number]: boolean },
	input: Brain.Input,
	candidates: { Brain.Candidate },
	candidatePool: { Brain.Candidate },
	lifts: { Brain.Lift },
	liftPool: { Brain.Lift },
	free: { Free },
	freePool: { Free },
	doors: Brain.Doors,
	doorways: { Brain.Doorway }, -- 7.x the interior's doorways (world)
	fronts: { Brain.Doorway }, -- 7.x the doors outside (the front door; a farm's barn doors too)
	exitIn: Vector3, -- the front door inside (where "Leave house" is)
	entryIn: CFrame, -- where you come in
	ways: { Way }, -- 7.x farm move: every way (ways[1] the front door: doors, exitIn, entryIn)
	wayDoors: { Brain.Doors }, -- (their doors, for Brain.routeVia)
	saidAt: { [string]: number },
	lastSaid: number,
	doing: string,
	doingAction: string,
	doingSpot: number?,
	doingFull: boolean,
	told: { [Player]: boolean }, -- the players with his attributes
}

local ID_BASE = -2000000000 -- (no player's id is this low; Studio's test players are -1, -2 …)
local FALL = 3 -- s he lies there before his body goes
local INSIDE = 400 -- studs from a move's interior origin that count as inside it
local NUDGE = 8 -- studs at most a stuck nudge puts him on (his way's next point)
local WALK = { through = true, near = 0.6 } -- Npcs.walkTo's options: he walks on into the next order
local HELD = "MoveHelperHeld" -- 7.x his collision group carrying together: nothing collides with it
local HANDS = { "Carrying", "CarryCount", "CarryHands", "CarryAt", "CarrySize" } -- 7.x his arms (client/ArmPose.luau)
local EDGE = { Width = 2.4, Depth = 0.6 } -- 7.x the piece's near edge his hands hold at its far end (studs)

local helpers: { [any]: Helper } = {} -- by the move's session
local byId: { [number]: Helper } = {}
local wired = false
local notice = Net.get("Notice")

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function walkSpeed(): number
	return Config.Movement.Walk
end

-- ── How he walks (a test gives its own) ────────────────────────────────────

local function computeRoute(body: Body, from: Vector3, to: Vector3): { Vector3 }?
	local path = body.path
	if not path then
		local made = game:GetService("PathfindingService"):CreatePath({ AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 })
		body.path = made
		path = made
	end
	local p = path :: Path
	local ok = pcall(function()
		p:ComputeAsync(from, to)
	end)
	if not ok or (p.Status ~= Enum.PathStatus.Success and p.Status ~= Enum.PathStatus.ClosestNoPath) then
		return nil
	end
	local points: { Vector3 } = {}
	for _, waypoint in p:GetWaypoints() do
		table.insert(points, waypoint.Position)
	end
	return points
end

-- 7.x the collision group he carries in: registered once, colliding with nothing there is.
local heldReady = false
local function heldGroup()
	if heldReady then
		return
	end
	heldReady = true
	local physics = game:GetService("PhysicsService")
	pcall(function()
		physics:RegisterCollisionGroup(HELD)
	end)
	local ok, groups = pcall(function(): { any }
		return physics:GetRegisteredCollisionGroups()
	end)
	if ok and groups then
		for _, group in groups do
			pcall(function()
				physics:CollisionGroupSetCollidable(HELD, group.name, false)
			end)
		end
	end
end

-- 7.x the hold's constraints and attachments gone, his parts' groups given back, he stands again.
local function gripOff(body: Body)
	local grip = body.grip
	if not grip then
		return
	end
	body.grip = nil
	local made: { Instance } = { grip.align, grip.orient, grip.own, grip.far }
	for _, obj in made do
		obj:Destroy()
	end
	for part, group in grip.groups do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	Npcs.carried(body.model, false)
	body.speed = -1 -- (Npcs.pace again on his next walk)
end

-- 7.x his root glued to `offset` in the piece's frame: AlignPosition and AlignOrientation between an attachment on his
-- root and one on the piece (the physics engine moves him every step, the server owns him), his own walk off.
local function gripOn(body: Body, anchor: BasePart, offset: CFrame)
	gripOff(body)
	heldGroup()
	local root = body.root
	Npcs.carried(body.model, true)
	body.walking, body.ordered = false, nil
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local far = Instance.new("Attachment")
	far.Name = "MoveHelperGrip"
	far.CFrame = offset
	far.Parent = anchor
	local own = Instance.new("Attachment")
	own.Name = "MoveHelperGrip"
	own.Parent = root
	local align = Instance.new("AlignPosition")
	align.Name = "MoveHelperHold"
	align.Attachment0 = own
	align.Attachment1 = far
	align.MaxForce = 1e6
	align.MaxVelocity = cfg.HoldSpeed
	align.Responsiveness = cfg.HoldResponse
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Name = "MoveHelperTurn"
	orient.Attachment0 = own
	orient.Attachment1 = far
	orient.MaxTorque = 1e6
	orient.MaxAngularVelocity = 40
	orient.Responsiveness = cfg.HoldResponse
	orient.Parent = root
	local groups: { [BasePart]: string } = {}
	for _, d in body.model:GetDescendants() do
		if d:IsA("BasePart") then
			groups[d] = d.CollisionGroup
			d.CollisionGroup = HELD
		end
	end
	body.grip = { anchor = anchor, far = far, own = own, align = align, orient = orient, groups = groups, offset = offset, lastAt = nil }
end

local mover: Mover = {
	move = function(body: Body, to: Vector3, speed: number, _dt: number)
		if math.abs(body.speed - speed) > 0.05 then
			body.speed = speed
			Npcs.pace(body.model, speed)
		end
		local ordered = body.ordered
		local clock = os.clock()
		if not body.walking or not ordered or (to - ordered).Magnitude > 1.5 or clock - body.orderedAt > 2 then
			body.walking, body.ordered, body.orderedAt = true, to, clock
			Npcs.walkTo(body.model, to, nil, 8, WALK)
		end
	end,
	halt = function(body: Body)
		if body.walking then
			body.walking, body.ordered = false, nil
			Npcs.stop(body.model)
		end
	end,
	route = computeRoute,
	-- 7.x carrying together: the constraints made once (again for another piece), the far end's attachment re-aimed
	-- when his place moved (the floor under it), put there at once when he is far off it (a door's fade), the legs
	keep = function(body: Body, anchor: BasePart, offset: CFrame, dt: number)
		local grip = body.grip
		if not grip or grip.anchor ~= anchor or not grip.far.Parent or not grip.align.Parent then
			gripOn(body, anchor, offset)
			grip = body.grip
		end
		local g = grip :: Grip
		if (g.offset.Position - offset.Position).Magnitude > 0.05 then
			g.offset = offset
			g.far.CFrame = offset
		end
		local root = body.root
		local goal = anchor.CFrame * offset
		local here = root.Position
		if (here - goal.Position).Magnitude > cfg.HoldSnap then
			body.model:PivotTo(goal)
			root.AssemblyLinearVelocity = Vector3.zero
			g.lastAt = nil
			Npcs.stride(body.model, 0)
			return
		end
		local last = g.lastAt
		g.lastAt = here
		if last and dt > 0 then
			local look = root.CFrame.LookVector
			local v = (here - last) / dt
			Npcs.stride(body.model, v.X * look.X + v.Z * look.Z)
		end
	end,
	free = gripOff,
	-- 7.x the fade-over's end: he fades in where he was just put (his parts from clear to their own look)
	appear = function(body: Body)
		local alpha = body.alpha
		if not alpha then
			local seen: { [Instance]: number } = {}
			for _, d in body.model:GetDescendants() do
				if d:IsA("BasePart") then
					seen[d] = d.Transparency
				elseif d:IsA("Decal") then
					seen[d] = d.Transparency
				end
			end
			alpha = seen
			body.alpha = seen
		end
		local own = alpha :: { [Instance]: number }
		body.fade += 1
		local token = body.fade
		for obj in own do
			(obj :: any).Transparency = 1
		end
		task.spawn(function()
			for k = 1, 5 do
				task.wait(0.05)
				if body.fade ~= token then
					return
				end
				for obj, t in own do
					if obj.Parent then
						(obj :: any).Transparency = 1 - (1 - t) * k / 5
					end
				end
			end
		end)
	end,
}

function MoveHelper.useMover(given: Mover)
	mover = given
end

-- ── Small helpers ──────────────────────────────────────────────────────────

local function insideAt(h: Helper, at: Vector3): boolean
	local origin: CFrame = h.s.origin
	return (at - origin.Position).Magnitude < INSIDE
end

local function truckOf(s: any): Vehicles.Car?
	local truck: Vehicles.Car? = s.truck
	if truck and not truck.wrecked and truck.model.Parent then
		return truck
	end
	return nil
end

-- The van stands by the house (he carries pieces out only then).
local function truckAtHouse(s: any, truck: Vehicles.Car?): boolean
	local door: Vector3 = s.site.door
	return truck ~= nil and flat(truck.chassis.Position, door) <= cfg.TruckFar
end

local function truckStill(truck: Vehicles.Car): boolean
	return Vehicles.speed(truck) <= Config.Cargo.MaxCarSpeed
end

-- A point by the van's back: `side` studs to its right, `out` studs out of it (nil: no back).
local function byTruck(truck: Vehicles.Car, side: number, out: number): Vector3?
	local door = Vehicles.cargoDoor(truck)
	if not door then
		return nil
	end
	local at = door.WorldPosition
	local chassis = truck.chassis.Position
	local away = Vector3.new(at.X - chassis.X, 0, at.Z - chassis.Z)
	local dir = if away.Magnitude > 0.1 then away.Unit else Vector3.new(0, 0, 1)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	return Vector3.new(at.X, chassis.Y, at.Z) + dir * out + right * side
end

-- The ground under (x, z) near refY (outside), else refY.
local function groundAt(x: number, z: number, refY: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, name in { "Npcs", "Zombies", "Cars", "Traffic", "BanditCars", "Animals", "Moves" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local hit = workspace:Raycast(Vector3.new(x, refY + 6, z), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y else refY
end

-- 7.x the interior's floor under (x, z) near refY (its shell only: not the furniture, not the counters; the Moves folder
-- it sits in is left out of groundAt's ray), else the floor at its front door (its origin).
local function interiorFloorAt(h: Helper, x: number, z: number, refY: number): number
	local origin: CFrame = h.s.origin
	local interior: Instance? = h.s.interior
	if interior and interior.Parent then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { interior:FindFirstChild("Shell") or interior }
		params.RespectCanCollide = true
		local hit = workspace:Raycast(Vector3.new(x, refY + 6, z), Vector3.new(0, -40, 0), params)
		if hit then
			return hit.Position.Y
		end
	end
	return origin.Position.Y
end

local function clearPath(h: Helper)
	table.clear(h.path)
	h.pathIndex, h.pathGoal = 1, nil
end

local function tell(h: Helper, text: string)
	for player in h.s.members do
		if player.Parent then
			notice:FireClient(player, text)
		end
	end
end

-- A line in a speech bubble (never the same within TalkRepeat s, two TalkGap s apart; `force`: now; 7.x the lines of
-- the moment, URGENT, wait for no TalkGap): true when said.
local URGENT: { [string]: boolean } = { help = true, assist = true, three = true, door = true, open = true, mine = true }
local function say(h: Helper, key: string, clock: number, force: boolean?): boolean
	local body = h.body
	local text = Brain.Lines[key]
	if not body or not text then
		return false
	end
	local last = h.saidAt[key]
	if not force and ((last and clock - last < cfg.TalkRepeat) or (clock - h.lastSaid < cfg.TalkGap and not URGENT[key])) then
		return false
	end
	h.saidAt[key], h.lastSaid = clock, clock
	Npcs.say(body.model, text, 3)
	return true
end

-- His attributes on the crew (the orders' strip): the order in force and what he does; off for those who left.
local function tellCrew(h: Helper)
	local s = h.s
	for player in s.members do
		if not player.Parent then
			continue
		end
		h.told[player] = true
		if player:GetAttribute("MoveHelper") ~= h.mode then
			player:SetAttribute("MoveHelper", h.mode)
		end
		if player:GetAttribute("MoveHelperDoing") ~= h.doing then
			player:SetAttribute("MoveHelperDoing", h.doing)
		end
	end
	for player in h.told do
		if not s.members[player] then
			h.told[player] = nil
			player:SetAttribute("MoveHelper", nil)
			player:SetAttribute("MoveHelperDoing", nil)
		end
	end
end

-- What he does, in words (made again only when it changes).
local function setDoing(h: Helper, action: string, spot: number?)
	if action == h.doingAction and spot == h.doingSpot and h.full == h.doingFull then
		return
	end
	h.doingAction, h.doingSpot, h.doingFull = action, spot, h.full
	local thing = if spot then (h.s.move :: Rules.Move).things[spot] else nil
	h.doing = Brain.doing(action, if thing then thing.name else nil, h.full)
end

local function playerRoot(id: number?): BasePart?
	local player = if id and id > 0 then Players:GetPlayerByUserId(id) else nil
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- ── Doorways (7.x: he never stands where you walk through) ─────────────────

-- The interior's doorways in the world (the plan's, at its origin) and the doors outside (the site's: the front door, a
-- farm's barn doors too).
local function doorwaysOf(s: any, origin: CFrame): ({ Brain.Doorway }, { Brain.Doorway })
	local a = cfg.Aside
	local list: { Brain.Doorway } = {}
	local frontHalf = 2
	for _, door in (s.plan.doors or {}) :: { any } do
		local at = origin * (door.at :: Vector3)
		local through = if door.axis == "X" then Vector3.new(0, 0, 1) else Vector3.new(1, 0, 0) -- (a wall along X: through along Z)
		local dir = (origin * through) - origin.Position
		local half = (tonumber(door.width) or 4) / 2
		if door.front then
			frontHalf = half
		end
		table.insert(list, { x = at.X, z = at.Z, half = half, dirX = dir.X, dirZ = dir.Z, depth = a.Depth })
	end
	local site = s.site
	local fronts: { Brain.Doorway } = {}
	for index, d in (if type(site.doors) == "table" then site.doors else {}) :: { any } do
		local foot: Vector3, facing: Vector3 = d.door, d.facing
		local half = if index == 1 then frontHalf else (tonumber(d.width) or 4) / 2
		table.insert(fronts, { x = foot.X, z = foot.Z, half = half, dirX = facing.X, dirZ = facing.Z, depth = a.FrontDepth })
	end
	if #fronts == 0 then
		local facing: Vector3 = site.facing
		local doorAt: Vector3 = site.door
		table.insert(fronts, { x = doorAt.X, z = doorAt.Z, half = frontHalf, dirX = facing.X, dirZ = facing.Z, depth = a.FrontDepth })
	end
	return list, fronts
end

-- A place where he will stand still: moved beside a doorway it is in (inside: the interior's; outside: the front door).
local function clearOf(h: Helper, at: Vector3, inside: boolean): Vector3
	if inside then
		for _, door in h.doorways do
			local x, z, moved = Brain.aside(at.X, at.Z, door)
			if moved then
				return Vector3.new(x, at.Y, z)
			end
		end
		return at
	end
	for _, door in h.fronts do
		local x, z, moved = Brain.aside(at.X, at.Z, door)
		if moved then
			return Vector3.new(x, at.Y, z)
		end
	end
	return at
end

-- Is a point within `reach` studs of an interior doorway (or the front door inside)?
local function nearDoorway(h: Helper, at: Vector3, reach: number): boolean
	for _, door in h.doorways do
		local dx, dz = at.X - door.x, at.Z - door.z
		if math.sqrt(dx * dx + dz * dz) <= door.half + reach then
			return true
		end
	end
	return false
end

-- ── His body ───────────────────────────────────────────────────────────────

-- The floor under a point: the interior's (inside), else the ground under it.
local function floorAt(h: Helper, at: Vector3): number
	return if insideAt(h, at) then interiorFloorAt(h, at.X, at.Z, at.Y) else groundAt(at.X, at.Z, at.Y)
end

-- Stands him with his feet at `at`, facing along `face` (flat); the walk stops, the way is worked out again.
local function placeAt(h: Helper, at: Vector3, face: Vector3?)
	local body = h.body
	if not body then
		return
	end
	mover.halt(body)
	local look = face or body.root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local up = Vector3.new(at.X, floorAt(h, at) + body.humanoid.HipHeight + body.root.Size.Y / 2, at.Z)
	body.model:PivotTo(if flatLook.Magnitude > 0.05 then CFrame.lookAt(up, up + flatLook) else CFrame.new(up))
	h.lastPos, h.stuckFor, h.repathed = nil, 0, false
	clearPath(h)
end

-- 7.x the carrier's grip box bigger while he holds the other end (the character attribute GripSteady).
local function steady(h: Helper, character: Model?)
	local was = h.steadied
	if was == character then
		return
	end
	if was and was.Parent then
		was:SetAttribute("GripSteady", nil)
	end
	h.steadied = character
	if character then
		character:SetAttribute("GripSteady", true)
	end
end

-- 7.x the far end let go of: the glue off (he stands again), the carrier's grip as before.
local function ungrip(h: Helper, body: Body?)
	local free = mover.free
	if body and free then
		free(body)
	end
	steady(h, nil)
	h.gripped, h.holdOffset, h.lineKey = nil, nil, nil
end

-- …and on his feet on the floor where he is.
local function unhold(h: Helper, body: Body)
	ungrip(h, body)
	placeAt(h, body.root.Position, body.root.CFrame.LookVector)
end

-- 7.x his arms (client/ArmPose.luau reads them on every body in workspace.Npcs): a piece of his own held like a
-- player's (its box in his root's frame), the far end of yours by its near edge; nothing held: down.
local function poseHands(h: Helper, body: Body, spot: number?, role: string?)
	local model = body.model
	local thing = if spot then (h.s.move :: Rules.Move).things[spot] else nil
	local item = if spot then h.s.items[spot] else nil
	if not thing or not item or h.dead then
		if model:GetAttribute("Carrying") ~= nil then
			for _, name in HANDS do
				model:SetAttribute(name, nil)
			end
		end
		return
	end
	local together = role == "helper"
	local at: Vector3
	local size: Vector3
	if together then
		local offset = h.holdOffset
		if not offset then
			return
		end
		local middle = offset:Inverse().Position -- (the piece's middle from his root)
		at = Vector3.new(0, middle.Y, -(cfg.Standoff + EDGE.Depth / 2))
		size = Vector3.new(math.min(thing.size.X, EDGE.Width), thing.size.Y, EDGE.Depth)
	else
		at = body.root.CFrame:PointToObjectSpace(item.root.Position)
		size = Vector3.new(thing.size.X, thing.size.Y, thing.size.Z)
	end
	local alone = not together and thing.class == "hand"
	local carrying = if alone then "crate" else "furniture"
	if model:GetAttribute("Carrying") ~= carrying then
		model:SetAttribute("Carrying", carrying)
	end
	if model:GetAttribute("CarryCount") ~= 1 then
		model:SetAttribute("CarryCount", 1)
	end
	local hands = if alone then 1 else 2
	if model:GetAttribute("CarryHands") ~= hands then
		model:SetAttribute("CarryHands", hands)
	end
	local was = model:GetAttribute("CarryAt")
	if typeof(was) ~= "Vector3" or (was - at).Magnitude > 0.05 then
		model:SetAttribute("CarryAt", at)
	end
	local wasSize = model:GetAttribute("CarrySize")
	if typeof(wasSize) ~= "Vector3" or (wasSize - size).Magnitude > 0.01 then
		model:SetAttribute("CarrySize", size)
	end
end

-- Where he comes (and comes back): by the van's back (on its left: out of the way), else outside the house's door.
local function homeSpot(h: Helper): Vector3
	local truck = truckOf(h.s)
	local spot = if truck then byTruck(truck, -4, 3) else nil
	if spot then
		return spot
	end
	local out: CFrame = h.s.site.outside
	return clearOf(h, out.Position, false)
end

local function spawnBody(h: Helper, at: Vector3): boolean
	local look = Npcs.look("mover", cfg.Name, cfg.Title)
	look.walkSpeed = walkSpeed() * cfg.Speed
	local ok, made = pcall(Npcs.spawn, look, CFrame.new(at))
	if not ok or typeof(made) ~= "Instance" then
		warn(`[MoveHelper] no body: {made}`)
		return false
	end
	local model = made :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	if not humanoid or not root then
		Npcs.remove(model) -- (no R15 rig on this server: no helper)
		return false
	end
	model.Name = cfg.Name
	model:SetAttribute("MoveHelper", h.id)
	model:SetAttribute("Busy", true) -- (Npcs' greeting leaves him alone)
	humanoid.MaxHealth = cfg.Health
	humanoid.Health = cfg.Health
	h.health = cfg.Health
	local body: Body = { model = model, root = root, humanoid = humanoid, walking = false, ordered = nil, orderedAt = 0, speed = 0, path = nil, grip = nil, alpha = nil, fade = 0 }
	h.body = body
	h.dead = false
	-- a bite (any health lost) knocks what he holds
	table.insert(h.hooks, humanoid.HealthChanged:Connect(function(health: number)
		local before = h.health
		h.health = health
		if health < before and health > 0 and h.body == body and not h.s.ended then
			h.port.helperHurt(h.s, model, before - health)
		end
	end))
	placeAt(h, at, nil)
	return true
end

local function removeBody(h: Helper)
	for _, hook in h.hooks do
		hook:Disconnect()
	end
	table.clear(h.hooks)
	local body = h.body
	ungrip(h, body) -- (7.x the attachment on the piece goes too)
	h.body = nil
	if body then
		Npcs.remove(body.model)
	end
	clearPath(h)
end

-- Down: what he holds falls, he lies on his back; his body goes FALL s later, he is back Respawn s later.
local function fall(h: Helper, body: Body, clock: number)
	ungrip(h, body)
	h.port.helperDrop(h.s, body.model, "died")
	say(h, "down", clock, true)
	mover.halt(body)
	h.dead, h.downAt = true, clock
	poseHands(h, body, nil, nil)
	local root = body.root
	local y = floorAt(h, root.Position - Vector3.new(0, 2, 0))
	local at = Vector3.new(root.Position.X, y + 0.6, root.Position.Z)
	body.model:PivotTo(CFrame.new(at) * CFrame.Angles(-math.pi / 2, 0, 0))
	tell(h, `🧑‍🔧 {cfg.Name} is down! He is back at the van in {cfg.Respawn} s.`)
end

-- 7.x farm move: the ways a piece may leave by (Moving's helperExits; nil: every way, one way only, or no piece).
local function exitsOf(h: Helper, spot: number?): { number }?
	local exits = h.port.helperExits
	if not exits or #h.ways < 2 then
		return nil
	end
	return exits(h.s, spot)
end

-- 7.x farm move: the ways he may take now (with what he holds).
local function allowedWays(h: Helper): { number }?
	return exitsOf(h, (Rules.holding(h.s.move, h.id)))
end

-- 7.x farm move: the best way from `here` (inside or not) to `goal` in the other world, among those he may take.
local function wayFor(h: Helper, here: Vector3, inside: boolean, goal: Vector3): Way
	if #h.ways < 2 then
		return h.ways[1]
	end
	local _, which = Brain.routeVia(inside, here.X, here.Z, not inside, goal.X, goal.Z, h.wayDoors, allowedWays(h))
	return h.ways[which] or h.ways[1]
end

-- Through the front door (no fade: he is not a player), to where the players come out or in (7.x farm move: through
-- `way`, the front door's when nil).
local function transfer(h: Helper, inside: boolean, clock: number, way: Way?)
	h.doorAt = clock
	local through = way or h.ways[1]
	if inside then
		placeAt(h, through.entryIn.Position + through.entryIn.LookVector * 1.5, through.entryIn.LookVector)
	else
		local out: CFrame = through.outside
		local right = Vector3.new(-out.LookVector.Z, 0, out.LookVector.X)
		placeAt(h, out.Position + right * 2, out.LookVector)
	end
end

-- ── The way ────────────────────────────────────────────────────────────────

-- The next point toward `target`: his path's (worked out again at most every Repath s, in the background, when the
-- target moved off it, or at once when asked: a stuck spell), else straight.
local function wayTo(h: Helper, body: Body, here: Vector3, target: Vector3, clock: number): Vector3
	local route = mover.route
	local goal = h.pathGoal
	if route and not h.pathing and clock - h.pathAt >= cfg.Repath and (goal == nil or flat(goal, target) > 3) then
		h.pathAt, h.pathing = clock, true
		task.spawn(function()
			local ok, points = pcall(route, body, here, target)
			h.pathing = false
			if h.body ~= body then
				return
			end
			table.clear(h.path)
			if ok and points then
				for index, point in points do
					h.path[index] = point
				end
				h.pathIndex, h.pathGoal = 2, target
			else
				h.pathGoal = nil
				h.pathFailedAt = clock -- (7.x a lift: he fades over)
			end
		end)
	end
	goal = h.pathGoal
	if goal and flat(goal, target) <= 3 then
		local path = h.path
		while h.pathIndex <= #path and flat(path[h.pathIndex], here) < 2 do
			h.pathIndex += 1
		end
		if h.pathIndex <= #path then
			return path[h.pathIndex]
		end
	end
	return target
end

-- Toward `goal` (inside the interior or in the street: `goalInside`): to the front door first when it is in the other
-- world, then by the way; far off (Far), he appears at the next point. Stuck (Brain.unstuck): a new path after
-- StuckRepath s, a nudge to the way's next point (NUDGE studs at most) after StuckSnap s. True: there (within near).
local function go(h: Helper, body: Body, goal: Vector3, goalInside: boolean, near: number, speed: number, dt: number, clock: number): boolean
	local here = body.root.Position
	local inside = insideAt(h, here)
	local target = goal
	if inside ~= goalInside then
		local way = wayFor(h, here, inside, goal) -- (7.x farm move: the nearest way he may take)
		local door = if inside then way.exitIn else way.outside.Position
		if flat(here, door) <= cfg.DoorReach and clock - h.doorAt > 1 then
			transfer(h, not inside, clock, way)
			return false
		end
		target = door
	elseif flat(here, goal) <= near then
		mover.halt(body)
		h.stuckFor, h.lastPos, h.repathed = 0, nil, false
		return true
	end
	if flat(here, target) > cfg.Far then
		placeAt(h, target, nil)
		return false
	end
	local last = h.lastPos
	h.stuckFor = Brain.stuck(h.stuckFor, if last then flat(here, last) else speed * dt, dt, speed)
	h.lastPos = here
	local fix = Brain.unstuck(h.stuckFor)
	if fix == "walk" then
		h.repathed = false
	elseif fix == "repath" and not h.repathed then
		h.repathed = true
		h.pathAt, h.pathGoal = -math.huge, nil -- (a new path at once)
	end
	local way = wayTo(h, body, here, target, clock)
	if fix == "nudge" then
		local step = Vector3.new(way.X - here.X, 0, way.Z - here.Z)
		local spot = if step.Magnitude > NUDGE then here + step.Unit * NUDGE else Vector3.new(way.X, here.Y, way.Z)
		placeAt(h, spot, if step.Magnitude > 0.05 then step else nil)
		return false
	end
	mover.move(body, way, speed, dt)
	return false
end

-- ── Choosing (every Think s) ───────────────────────────────────────────────

local function think(h: Helper, body: Body, clock: number)
	h.thinkAt = clock + cfg.Think
	local s = h.s
	local move: Rules.Move = s.move
	local here = body.root.Position
	local fromInside = insideAt(h, here)
	local truck = truckOf(s)
	local back = if truck then byTruck(truck, 0, 0) else nil
	-- the van's room for each piece, again only when its load changed
	local key = #move.packing.placed + Rules.fill(move.packing)
	if key ~= h.fitKey then
		h.fitKey = key
		table.clear(h.fits)
	end
	for spot, untilAt in h.gaveUp do
		local thing = move.things[spot]
		if not thing or thing.state ~= "carried" or clock >= untilAt then
			h.gaveUp[spot] = nil
		end
	end
	-- 7.x the crew's free hands: a piece one of them is about to lift is theirs
	table.clear(h.free)
	for player in s.members do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not character or not humanoid or humanoid.Health <= 0 or humanoid.SeatPart or not root or not root:IsA("BasePart") then
			continue
		end
		if character:GetAttribute("Carrying") ~= nil or character:GetAttribute("MoveCarry") ~= nil then
			continue
		end
		local n = #h.free + 1
		local f = h.freePool[n]
		if not f then
			f = { inside = false, x = 0, z = 0 }
			h.freePool[n] = f
		end
		f.inside, f.x, f.z = insideAt(h, root.Position), root.Position.X, root.Position.Z
		h.free[n] = f
	end
	local pay = Config.Moving.Pay
	table.clear(h.candidates)
	table.clear(h.lifts)
	for _, spot in move.order do
		local thing = move.things[spot]
		local item = s.items[spot]
		if not item then
			continue
		end
		local at = item.root.Position
		local inside = insideAt(h, at)
		if (thing.class == "hand" or thing.class == "both") and (thing.state == "home" or thing.state == "ground") then
			local fits = h.fits[spot]
			if fits == nil then
				fits = Rules.fit(move.packing, thing.size) ~= nil
				h.fits[spot] = fits
			end
			local n = #h.candidates + 1
			local c = h.candidatePool[n]
			if not c then
				c = { spot = 0, class = "", state = "", star = false, broken = false, cost = 0, haul = 0, value = 0, weight = 0, fits = false, byTruck = false, reserved = false }
				h.candidatePool[n] = c
			end
			c.spot, c.class, c.state, c.star, c.broken = spot, thing.class, thing.state, thing.star, Rules.broken(thing)
			c.cost = (Brain.routeVia(fromInside, here.X, here.Z, inside, at.X, at.Z, h.wayDoors))
			c.haul = if back then (Brain.routeVia(inside, at.X, at.Z, false, back.X, back.Z, h.wayDoors, exitsOf(h, spot))) else 0
			c.value = thing.value * thing.condition * (if thing.star then pay.Star else 1)
			c.weight = thing.weight
			c.fits = fits
			c.byTruck = back ~= nil and not inside and flat(at, back) <= 12
			local nearest: number? = nil
			for _, f in h.free do
				local d = (Brain.routeVia(f.inside, f.x, f.z, inside, at.X, at.Z, h.wayDoors))
				if nearest == nil or d < nearest then
					nearest = d
				end
			end
			c.reserved = Brain.reserved(nearest, c.cost)
			h.candidates[n] = c
		elseif (thing.class == "pair" or thing.class == "both") and thing.state == "carried" then
			local carrier = if thing.carrier and thing.carrier > 0 then Players:GetPlayerByUserId(thing.carrier) else nil
			local n = #h.lifts + 1
			local l = h.liftPool[n]
			if not l then
				l = { spot = 0, class = "", state = "", helped = false, crew = false, cost = 0, gaveUp = false, weight = 0, byBack = false }
				h.liftPool[n] = l
			end
			l.spot, l.class, l.state = spot, thing.class, thing.state
			l.helped = thing.helper ~= nil
			l.crew = carrier ~= nil and s.members[carrier] == true
			l.cost = (Brain.routeVia(fromInside, here.X, here.Z, inside, at.X, at.Z, h.wayDoors))
			l.gaveUp = h.gaveUp[spot] ~= nil
			l.weight = thing.weight
			l.byBack = back ~= nil and not inside and flat(at, back) <= cfg.AssistBack
			h.lifts[n] = l
		end
	end
	local before = if h.action == "fetch" then h.spot else nil
	h.pick, h.full = Brain.pickItem(h.candidates, truck ~= nil and Vehicles.backOpen(truck))
	h.lift = Brain.pickLift(h.lifts)
	h.assist = Brain.pickAssist(h.lifts)
	if not h.full then
		h.toldFull = false
	end
	-- his plan taken: the piece he went for is yours now
	if before and h.pick ~= before then
		for _, c in h.candidates do
			if c.spot == before and c.reserved then
				say(h, "mine", clock)
				break
			end
		end
	end
end

-- The nearest living zombie within SafeRange: (studs, where) or nils.
local function nearestZombie(here: Vector3): (number?, Vector3?)
	local best: number? = nil
	local at: Vector3? = nil
	for _, z in Zombies.all() do
		local root = z.root
		if z.dead or not root or not root.Parent then
			continue
		end
		local d = (root.Position - here).Magnitude
		if d <= cfg.SafeRange and (best == nil or d < best) then
			best, at = d, root.Position
		end
	end
	return best, at
end

-- 7.x is the van's back shut while somebody of the crew comes with a piece and he is near enough to open it?
local function wantOpen(h: Helper, body: Body): boolean
	local s = h.s
	local truck = truckOf(s)
	if not cfg.OpenBack or not truck or Vehicles.backOpen(truck) or not Vehicles.backPrompt(truck) or not truckAtHouse(s, truck) or not truckStill(truck) then
		return false
	end
	local back = byTruck(truck, 0, 0)
	local here = body.root.Position
	if not back or insideAt(h, here) or flat(here, back) > cfg.OpenFar then
		return false
	end
	for player in s.members do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if character and root and root:IsA("BasePart") and character:GetAttribute("MoveCarry") ~= nil and not insideAt(h, root.Position)
			and flat(root.Position, back) <= cfg.OpenNear then
			return true
		end
	end
	return false
end

-- ── What he does ───────────────────────────────────────────────────────────

-- At the van's open back, the van standing: loads what he carries (true: in).
local function loadHere(h: Helper, body: Body): boolean
	local truck = truckOf(h.s)
	local back = if truck then byTruck(truck, 0, 0) else nil
	if not truck or not back or insideAt(h, body.root.Position) or flat(body.root.Position, back) > cfg.LoadReach then
		return false
	end
	if not Vehicles.backOpen(truck) or not truckStill(truck) then
		return false
	end
	return (h.port.helperLoad(h.s, body.model))
end

-- 7.x his place at the far end of your piece, in its frame: Standoff past its far face, turned to you, on the floor
-- under it (within HoldStep of your root's height).
local function endOffset(h: Helper, body: Body, thing: Rules.Thing, anchor: BasePart, carrierRoot: BasePart?): CFrame
	local frame = anchor.CFrame
	local ahead = Brain.farEnd(thing.size.Z)
	local far = frame * Vector3.new(0, 0, -ahead)
	local stand = body.humanoid.HipHeight + body.root.Size.Y / 2
	local carrierRise = if carrierRoot then carrierRoot.Position.Y - frame.Position.Y else -(thing.size.Y / 2 + Config.Cargo.CarryLow)
	local rise = Brain.endRise(floorAt(h, far) + stand - frame.Position.Y, carrierRise)
	return CFrame.new(0, rise, -ahead) * CFrame.Angles(0, math.pi, 0)
end

-- 7.x kept at `offset` in the piece's frame (the mover's constraints; a test's mover without them: his root put there).
local function keepAt(body: Body, anchor: BasePart, offset: CFrame, dt: number)
	local keep = mover.keep
	if keep then
		keep(body, anchor, offset, dt)
	else
		body.root.CFrame = anchor.CFrame * offset
	end
end

-- 7.x the far end of your piece (or the other side of your two-hands piece): he moves with it, glued there; the words.
local function actHold(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item or not item.root.Parent then
		h.port.helperDrop(s, body.model, "put")
		ungrip(h, body)
		return
	end
	local carrierRoot = playerRoot(thing.carrier)
	local offset = endOffset(h, body, thing, item.root, carrierRoot)
	h.holdOffset, h.gripped = offset, item.root
	keepAt(body, item.root, offset, dt)
	steady(h, if carrierRoot then carrierRoot.Parent :: Model? else nil)
	local at = item.root.Position
	if insideAt(h, at) and nearDoorway(h, at, cfg.DoorWarn) then
		say(h, "door", clock)
	end
	local truck = truckOf(s)
	local back = if truck then byTruck(truck, 0, 0) else nil
	if not truck or not back or insideAt(h, at) or flat(at, back) > cfg.VanSay then
		return
	end
	-- by the van together: the back shut, he opens it (your hands are full, his has an elbow free), else "That's going in
	-- the van."
	if cfg.OpenBack and not Vehicles.backOpen(truck) and Vehicles.backPrompt(truck) and truckStill(truck) then
		Vehicles.setBack(truck, true)
		say(h, "open", clock)
	elseif h.vanSaid ~= spot and say(h, "van", clock) then
		h.vanSaid = spot
	end
end

-- 7.x takes your piece's far end (or its other side): "Got the other end!", "On three... lift!" a moment later.
local function takeEnd(h: Helper, body: Body, spot: number, clock: number)
	mover.halt(body)
	if h.port.helperTake(h.s, spot, body.model) then
		say(h, "lift", clock, true)
		h.lineKey, h.lineAt, h.vanSaid = "three", clock + cfg.ThreeAfter, nil
	else
		h.gaveUp[spot] = clock + cfg.HelpRetry
	end
	h.thinkAt = 0
end

-- 7.x the fade-over: he is at `goal` at once (on the floor there, turned its way) and fades in.
local function blink(h: Helper, body: Body, goal: CFrame)
	placeAt(h, goal.Position, goal.LookVector)
	local appear = mover.appear
	if appear then
		appear(body)
	end
end

-- To your lift ("help": a pair piece; "assist": the other side of a heavy two-hands piece): his own piece first (into
-- the van right here, else set down), then a sprint to its far end, and he takes it. Far on foot (BlinkFar), his path
-- failing or not there HelpBlink s after he set off: he fades over to it.
local function actHelp(h: Helper, body: Body, action: string, spot: number, holding: string?, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item or thing.state ~= "carried" or (thing.class ~= "pair" and thing.class ~= "both") or thing.helper ~= nil then
		h.thinkAt = 0
		return
	end
	if holding == "hand" then
		if not loadHere(h, body) then
			h.port.helperDrop(s, body.model, "put")
		end
		h.thinkAt = 0
		return
	end
	if h.action ~= action or h.spot ~= spot then
		h.helpSince, h.stuckFor, h.repathed = clock, 0, false
		say(h, action, clock)
	end
	local goal = item.root.CFrame * endOffset(h, body, thing, item.root, playerRoot(thing.carrier))
	local at = goal.Position
	local here = body.root.Position
	local inside = insideAt(h, at)
	local hereInside = insideAt(h, here)
	if hereInside == inside and flat(here, at) <= cfg.HelpReach then
		takeEnd(h, body, spot, clock)
		return
	end
	local cost = (Brain.routeVia(hereInside, here.X, here.Z, inside, at.X, at.Z, h.wayDoors))
	if cost > cfg.BlinkFar or clock - h.helpSince >= cfg.HelpBlink or h.pathFailedAt >= h.helpSince then
		blink(h, body, goal)
		takeEnd(h, body, spot, clock)
		return
	end
	go(h, body, at, inside, 0.5, Brain.speed(walkSpeed(), action, nil, 0), dt, clock)
end

-- Is a crew player with free hands about to lift the piece at `at` (nearer to it than he is, within Reserve)?
local function reservedNow(h: Helper, at: Vector3, inside: boolean, mine: number): boolean
	for _, f in h.free do
		if f.inside == inside and Brain.reserved(flat(Vector3.new(f.x, at.Y, f.z), at), mine) then
			return true
		end
	end
	return false
end

-- To the next piece; there, he picks it up (not when one of the crew is about to: theirs).
local function actFetch(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item or (thing.class ~= "hand" and thing.class ~= "both") or (thing.state ~= "home" and thing.state ~= "ground") then
		h.pick, h.thinkAt = nil, 0
		return
	end
	local at = item.root.Position
	local inside = insideAt(h, at)
	local here = body.root.Position
	local half = math.max(thing.size.X, thing.size.Z) / 2
	if insideAt(h, here) == inside and flat(here, at) <= half + cfg.PickReach then
		mover.halt(body)
		if reservedNow(h, at, inside, flat(here, at)) then
			say(h, "mine", clock)
			h.pick, h.thinkAt = nil, clock + cfg.Think -- (his plan dropped: the next piece)
			return
		end
		if not h.port.helperTake(s, spot, body.model) then
			h.pick = nil
		end
		h.waited, h.dropping, h.thinkAt = 0, false, 0
		return
	end
	-- (the way's end beside it, on his side: a path can't end inside a piece that stands in the way)
	local from = here
	if insideAt(h, here) ~= inside then
		local way = wayFor(h, here, not inside, at) -- (7.x farm move: the way he will come by)
		from = if inside then way.entryIn.Position else way.outside.Position
	end
	local side = Vector3.new(from.X - at.X, 0, from.Z - at.Z)
	local beside = if side.Magnitude > 0.1 then at + side.Unit * (half + 1.5) else at
	go(h, body, beside, inside, 0.5, Brain.speed(walkSpeed(), "fetch", nil, 0), dt, clock)
end

-- With a piece in his arms: to the van's back and in (shut: he opens it when he may, else he asks and waits); no room
-- or the back shut too long: beside the van. No van by the house: set down outside the house's door.
local function actDeliver(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local speed = Brain.speed(walkSpeed(), "deliver", Rules.mode(thing), thing.weight)
	local truck = truckOf(s)
	local here = body.root.Position
	if not truck or not truckAtHouse(s, truck) then
		local out: CFrame = s.site.outside
		local right = Vector3.new(-out.LookVector.Z, 0, out.LookVector.X)
		if go(h, body, clearOf(h, out.Position + right * 4, false), false, 1.5, speed, dt, clock) then
			h.port.helperDrop(s, body.model, "put")
			h.thinkAt = 0
		end
		return
	end
	if not truckStill(truck) then
		mover.halt(body) -- (the van is moving: he waits with it)
		return
	end
	if h.dropping then
		local beside = byTruck(truck, 4 + (spot % 3) * 2.2, 2 + (spot // 3 % 2) * 2.5)
		if not beside or go(h, body, beside, false, 1, speed, dt, clock) then
			h.port.helperDrop(s, body.model, "put")
			h.dropping, h.waited, h.thinkAt = false, 0, 0
		end
		return
	end
	local back = byTruck(truck, 0, 2)
	if not back then
		h.dropping = true
		return
	end
	if insideAt(h, here) or flat(here, back) > cfg.LoadReach then
		go(h, body, back, false, 1, speed, dt, clock)
		return
	end
	mover.halt(body)
	local verdict = Brain.atTruck(Vehicles.backOpen(truck), true, h.waited, cfg.OpenBack and Vehicles.backPrompt(truck) ~= nil)
	if verdict == "load" then
		local ok = h.port.helperLoad(s, body.model)
		h.waited, h.thinkAt = 0, 0
		if ok then
			say(h, "loaded", clock)
		else
			h.dropping, h.fits[spot] = true, false -- (no room for it after all: not this one again until the load changes)
			h.toldFull = true
			say(h, "full", clock, true)
		end
	elseif verdict == "open" then
		Vehicles.setBack(truck, true)
		say(h, "open", clock)
	elseif verdict == "wait" then
		h.waited += dt
		say(h, "shut", clock)
	else
		h.dropping = true
	end
end

-- 7.x the van's back for whoever comes with a piece: to it, and open.
local function actOpen(h: Helper, body: Body, dt: number, clock: number)
	local truck = truckOf(h.s)
	local spot = if truck then byTruck(truck, -1.5, 1.5) else nil
	if not truck or not spot then
		return
	end
	if flat(body.root.Position, spot) > cfg.LoadReach then
		go(h, body, spot, false, 1, Brain.speed(walkSpeed(), "open", nil, 0), dt, clock)
		return
	end
	mover.halt(body)
	Vehicles.setBack(truck, true)
	say(h, "open", clock)
	h.thinkAt = 0
end

-- Behind the player he helps ("Help me"): the owner, else the nearest of the crew on foot; nobody on foot: at the van.
local function followed(h: Helper, here: Vector3): BasePart?
	local s = h.s
	local best: BasePart? = nil
	local bestDistance = math.huge
	for player in s.members do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or humanoid.SeatPart or not root or not root:IsA("BasePart") then
			continue
		end
		local d = if player == s.owner then -1 else (root.Position - here).Magnitude
		if d < bestDistance then
			best, bestDistance = root, d
		end
	end
	return best
end

local actWait: (Helper, Body, number, number) -> ()

local function actFollow(h: Helper, body: Body, dt: number, clock: number)
	local here = body.root.Position
	local root = followed(h, here)
	if not root then
		actWait(h, body, dt, clock)
		return
	end
	local look = root.CFrame.LookVector
	local x, z = Brain.followSpot(root.Position.X, root.Position.Z, look.X, look.Z)
	local inside = insideAt(h, root.Position)
	go(h, body, clearOf(h, Vector3.new(x, root.Position.Y, z), inside), inside, 1.5, Brain.speed(walkSpeed(), "follow", nil, 0), dt, clock)
end

-- At the van (on its left, out of the way). It moves, or it stands far off and not by the house (driven somewhere
-- else, a stop on the way): he stands where he is (he appears at it once it is parked by the house). No van: outside
-- the house's door (beside it, out of the doorway).
actWait = function(h: Helper, body: Body, dt: number, clock: number)
	local truck = truckOf(h.s)
	local speed = Brain.speed(walkSpeed(), "wait", nil, 0)
	if truck and not truckStill(truck) then
		mover.halt(body)
		return
	end
	local spot = if truck then byTruck(truck, -4, 3) else nil
	if not spot then
		local out: CFrame = h.s.site.outside
		spot = out.Position
	elseif truck and not truckAtHouse(h.s, truck) and flat(body.root.Position, spot) > cfg.Far then
		mover.halt(body)
		return
	end
	go(h, body, clearOf(h, spot :: Vector3, false), false, 1.5, speed, dt, clock)
end

local function actFlee(h: Helper, body: Body, from: Vector3, dt: number, clock: number)
	local here = body.root.Position
	local target = h.fleeAt
	if not target or clock - h.fleeSet > 1 or flat(here, target) < 2 then
		local x, z = Brain.fleeTo(here.X, here.Z, from.X, from.Z)
		target = Vector3.new(x, here.Y, z)
		h.fleeAt, h.fleeSet = target, clock
	end
	say(h, "flee", clock)
	mover.move(body, target :: Vector3, Brain.speed(walkSpeed(), "flee", nil, 0), dt)
end

-- ── One step ───────────────────────────────────────────────────────────────

local function stepHelper(h: Helper, dt: number, clock: number)
	local s = h.s
	local body = h.body
	if h.dead then
		if body and clock - h.downAt >= FALL then
			removeBody(h)
		end
		if clock - h.downAt >= cfg.Respawn then
			if h.body then
				removeBody(h)
			end
			if spawnBody(h, homeSpot(h)) then
				say(h, "back", clock, true)
				h.thinkAt, h.waited, h.dropping, h.fleeing = 0, 0, false, false
			else
				h.downAt = clock - cfg.Respawn + 2 -- (no body yet: tried again in a moment)
			end
		end
		setDoing(h, "down", nil)
		return
	end
	if not body or not body.model.Parent or not body.humanoid.Parent then
		-- his body went (removed by something else): like a fall (7.0 review: what he holds falls first, never left
		-- "carried" by nobody)
		if body then
			h.port.helperDrop(s, body.model, "died")
		end
		removeBody(h)
		h.dead, h.downAt = true, clock - FALL
		return
	end
	if body.humanoid.Health <= 0 then
		fall(h, body, clock)
		return
	end
	local move: Rules.Move = s.move
	local spot, role = Rules.holding(move, h.id)
	local holding = if role == "helper" then "pair" elseif spot then "hand" else nil
	if holding ~= "pair" and h.gripped then
		unhold(h, body) -- (7.x your piece went down, into the van, or he let go: on his feet again)
	end
	if clock >= h.thinkAt then
		think(h, body, clock)
	end
	local threat, threatAt = nil, nil
	if holding ~= "pair" then
		threat, threatAt = nearestZombie(body.root.Position)
	end
	local input = h.input
	input.mode, input.dead, input.holding = h.mode, false, holding
	input.threat, input.fleeing = threat, h.fleeing
	input.lift, input.assist, input.pick = h.lift, h.assist, h.pick
	input.open = holding == nil and wantOpen(h, body)
	input.atHouse = truckAtHouse(s, truckOf(s))
	local action, target = Brain.decide(input)
	h.fleeing = action == "flee"
	if action ~= "flee" then
		h.fleeAt = nil
	end
	if action == "hold" and spot then
		actHold(h, body, spot, dt, clock)
	elseif action == "flee" and threatAt then
		actFlee(h, body, threatAt, dt, clock)
	elseif (action == "help" or action == "assist") and target then
		actHelp(h, body, action, target, holding, dt, clock)
	elseif action == "deliver" and spot then
		actDeliver(h, body, spot, dt, clock)
	elseif action == "open" then
		actOpen(h, body, dt, clock)
	elseif action == "fetch" and target then
		actFetch(h, body, target, dt, clock)
	elseif action == "follow" then
		actFollow(h, body, dt, clock)
	else
		if h.full and h.mode == "carry" and not h.toldFull then
			say(h, "full", clock, true) -- (once while it stays full)
			h.toldFull = true
		end
		actWait(h, body, dt, clock)
	end
	-- (what he holds now: his arms; a line due: "On three... lift!")
	local nowSpot, nowRole = Rules.holding(move, h.id)
	poseHands(h, body, nowSpot, nowRole)
	local line = h.lineKey
	if line and clock >= h.lineAt then
		h.lineKey = nil
		if nowRole == "helper" then
			say(h, line, clock, true)
		end
	end
	h.action, h.spot = action, target or spot
	setDoing(h, action, target or spot)
end

-- ── Coming and going ───────────────────────────────────────────────────────

local function dismiss(h: Helper, why: string?)
	local s = h.s
	local body = h.body
	if body and not h.dead and not s.ended then
		h.port.helperDrop(s, body.model, "put")
	end
	if why == "crew" then
		tell(h, `🧑‍🔧 {cfg.Name} heads back to the depot: your crew has it now.`)
	end
	removeBody(h)
	helpers[s] = nil
	byId[h.id] = nil
	for player in h.told do
		if player.Parent then
			player:SetAttribute("MoveHelper", nil)
			player:SetAttribute("MoveHelperDoing", nil)
		end
	end
	table.clear(h.told)
end

function MoveHelper.step(dt: number)
	local clock = os.clock()
	for s, h in helpers do
		if s.ended then
			dismiss(h, nil)
			continue
		end
		local ok, err = pcall(stepHelper :: any, h, dt, clock) -- (no closure a step)
		if not ok then
			warn(`[MoveHelper] {err}`)
		end
	end
end

-- The crew's orders: the Moving remote's ("helper", "help" | "carry" | "wait").
local function onOrder(player: Player, action: any, mode: any)
	if action ~= "helper" or not Brain.validMode(mode) or not Net.limit(player, "MoveHelper", cfg.Orders) then
		return
	end
	local clock = os.clock()
	for s, h in helpers do
		if s.ended or not s.members[player] or h.mode == mode then
			continue
		end
		h.mode = mode :: Brain.Mode
		h.thinkAt, h.waited = 0, 0
		table.clear(h.gaveUp) -- (an order: he tries the lifts he gave up on again)
		say(h, `{mode}Mode`, clock, true)
		tellCrew(h)
	end
end

-- 7.0 planning: an order from elsewhere (server/Moving.luau: the quick chat's "Need a hand here" is HELP ME).
function MoveHelper.order(player: Player, mode: string)
	onOrder(player, "helper", mode)
end

-- Once: the zombies go after him too (Zombies.extraTargets, after server/Buddy.luau's), the orders, his loop.
local function wire()
	if wired then
		return
	end
	wired = true
	local before = Zombies.extraTargets
	Zombies.extraTargets = function(): { Zombies.ExtraTarget }
		local list: { Zombies.ExtraTarget } = {}
		if before then
			local ok, got = pcall(before)
			if ok and type(got) == "table" then
				list = got
			end
		end
		for s, h in helpers do
			local body = h.body
			if not h.dead and not s.ended and body and body.model.Parent and body.humanoid.Health > 0 then
				table.insert(list, { position = body.root.Position, velocity = body.root.AssemblyLinearVelocity, humanoid = body.humanoid, player = s.owner })
			end
		end
		return list
	end
	Net.get("Moving").OnServerEvent:Connect(onOrder)
	task.spawn(function()
		while true do
			local dt = task.wait(cfg.Tick)
			if next(helpers) ~= nil then
				MoveHelper.step(math.min(dt or cfg.Tick, 0.5))
			end
		end
	end)
end

local function create(s: any, port: Port): Helper
	wire()
	local clock = os.clock()
	local id = ID_BASE - (tonumber(s.id) or 0)
	local origin: CFrame = s.origin
	local entry: CFrame = origin * (s.plan.entry :: CFrame)
	local exitIn = (origin * CFrame.new(s.plan.exit :: Vector3)).Position
	local outside: CFrame = s.site.outside
	-- 7.x farm move: every way in and out (Moving's s.ways), else the front door's
	local ways: { Way } = {}
	local wayDoors: { Brain.Doors } = {}
	for _, way in (if type(s.ways) == "table" then s.ways else {}) :: { any } do
		local out: CFrame = way.door.outside
		local made: Way = { exitIn = way.inside, entryIn = way.entry, outside = out, doors = { outX = out.Position.X, outZ = out.Position.Z, inX = way.inside.X, inZ = way.inside.Z } }
		table.insert(ways, made)
		table.insert(wayDoors, made.doors)
	end
	if #ways == 0 then
		local made: Way = { exitIn = exitIn, entryIn = entry, outside = outside, doors = { outX = outside.Position.X, outZ = outside.Position.Z, inX = exitIn.X, inZ = exitIn.Z } }
		table.insert(ways, made)
		table.insert(wayDoors, made.doors)
	end
	local doorways, fronts = doorwaysOf(s, origin)
	local h: Helper = {
		s = s,
		port = port,
		id = id,
		mode = "carry",
		body = nil,
		hooks = {},
		health = cfg.Health,
		dead = false,
		downAt = 0,
		action = "wait",
		spot = nil,
		fleeing = false,
		fleeAt = nil,
		fleeSet = 0,
		stuckFor = 0,
		repathed = false,
		lastPos = nil,
		doorAt = 0,
		path = {},
		pathIndex = 1,
		pathGoal = nil,
		pathAt = -math.huge,
		pathing = false,
		pathFailedAt = -math.huge,
		gaveUp = {},
		helpSince = 0,
		gripped = nil,
		holdOffset = nil,
		steadied = nil,
		lineKey = nil,
		lineAt = 0,
		vanSaid = nil,
		waited = 0,
		dropping = false,
		thinkAt = 0,
		lift = nil,
		assist = nil,
		pick = nil,
		full = false,
		toldFull = false,
		fitKey = -1,
		fits = {},
		input = { mode = "carry", dead = false, holding = nil, threat = nil, fleeing = false, lift = nil, assist = nil, pick = nil, open = false, atHouse = false },
		candidates = {},
		candidatePool = {},
		lifts = {},
		liftPool = {},
		free = {},
		freePool = {},
		doors = ways[1].doors,
		doorways = doorways,
		fronts = fronts,
		exitIn = ways[1].exitIn,
		entryIn = ways[1].entryIn,
		ways = ways,
		wayDoors = wayDoors,
		saidAt = {},
		lastSaid = -math.huge,
		doing = Brain.doing("wait", nil, false),
		doingAction = "wait",
		doingSpot = nil,
		doingFull = false,
		told = {},
	}
	helpers[s] = h
	byId[id] = h
	if spawnBody(h, homeSpot(h)) then
		say(h, "hello", clock, true)
	else
		h.dead, h.downAt = true, clock - cfg.Respawn + 2 -- (tried again in a moment)
	end
	tell(h, `🧑‍🔧 {cfg.Name} from the depot joins your move: he lifts with you, carries the smaller pieces to the van and opens its back. Orders: the DANNY buttons under the move's panel.`)
	return h
end

local function syncOne(s: any, port: Port)
	if s.ended then
		return
	end
	local count = 0
	for player in s.members do
		if player.Parent then
			count += 1
		end
	end
	local h = helpers[s]
	local want = Brain.wanted(count)
	if want and not h then
		h = create(s, port)
	elseif not want and h then
		dismiss(h, "crew")
		return
	end
	if h then
		tellCrew(h)
	end
end

function MoveHelper.sync(s: any, port: Port)
	local ok, err = pcall(syncOne :: any, s, port)
	if not ok then
		warn(`[MoveHelper] {err}`)
	end
end

function MoveHelper.nameOf(id: number?): string?
	return if id and byId[id] then cfg.Name else nil
end

-- The helper on this player's move (his state, for the tests and the admin), or nil.
function MoveHelper.find(player: Player): any
	for s, h in helpers do
		if not s.ended and (s.owner == player or s.members[player]) then
			return h
		end
	end
	return nil
end

return MoveHelper
