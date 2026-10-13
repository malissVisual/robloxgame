--!strict
-- 7.0, the depot's helper ("Danny from the depot"; the owner's decision in design/rework/NAVRH.md: solo play is allowed
-- with an AI helper). An NPC mover who joins a move whose crew is a single player (Config.MoveHelper.Duo: two players
-- too, off by default). server/Moving.luau calls MoveHelper.sync(session, Moving) every tick: he comes when the crew is
-- small enough and goes when it grows (setting down what he holds); his own loop (Config.MoveHelper.Tick) walks him.
-- His decisions are shared/MoveHelperBrain.luau's (pure: tests/movehelper_test.luau); what he does with the things goes
-- through Moving's helper hooks (Moving.helperTake / helperDrop / helperLoad / helperHurt: the same rules, welds and
-- damage as a player's hands); tests/movehelper_runtime_test.luau runs the real module with the real Moving.
--   * He comes with the move at its truck (an orange ZDC mover: server/Npcs.luau's body and name tag) and works while
--     the truck stands by the house (within TruckFar of its door); a truck that stands far away, he appears at its back.
--   * "Carry small stuff" (the default): the nearest one-hand thing nobody holds (★ first; none that no longer fits the
--     truck), carried out at 0.7 × a player's walk: a path inside the interior (PathfindingService), the front door (he
--     goes through it like the players, without the fade), a path to the truck's back. The back open and the truck
--     standing: loaded (MovingRules' packer, like Load); no room: set down beside the truck ("Truck's full, boss."); the
--     back shut for WaitShut s: set down beside it (he takes it in once the back opens). Never a "both" or a pair thing
--     alone.
--   * A crew player lifts a pair thing: he comes and takes the other end ("Lift on three!": the two-person walk, 0.8 ×).
--     Stuck on the way, or left behind while carrying, for HelpWait s: he lets go and the player drags it alone (he tries
--     that lift again HelpRetry s later, or once it was set down and lifted again, or on an order). The carrier goes
--     through the front door: he comes along at their side.
--   * The orders (the player attribute MoveHelper = the one in force, MoveHelperDoing = what he does: client/
--     MoveHelperHud.luau's strip under the move's panel; the Moving remote's ("helper", order)): "help" (Help me: he
--     follows you, through the doors too, and lifts with you), "carry" (Carry small stuff), "wait" (Wait at the truck).
--   * He stays out of fights: a zombie within FleeRange, he runs (not while holding his end of a pair thing). The zombies
--     go after him like after a player on foot (Zombies.extraTargets); a bite knocks what he holds (Moving.helperHurt);
--     at 0 health he drops it (knocked) and lies down; he is back at the truck Respawn s later.
--   * He talks a little: a speech bubble (Npcs.say) on the way's events, never the same line within TalkRepeat s.
-- Performance: one helper per move, one loop for all of them, a path at most every Repath s (computed in the background,
-- one Path object each), his walk ordered again only when its goal moves (Npcs.walkTo), the lists he chooses from kept
-- and refilled (every Think s), the truck's room for each thing worked out only when the load changes.
--   MoveHelper.sync(s, port)   Moving's tick: the move's crew (he comes or goes) and his hands (Moving's helper hooks)
--   MoveHelper.step(dt)        one step of every helper (his loop's; the runtime test calls it)
--   MoveHelper.useMover(m)     how he walks (a test's: the Luau CLI has no physics and no pathfinding)
--   MoveHelper.nameOf(id)      his name by his id in a move's rules (nil: not a helper's id)
--   MoveHelper.find(player)    the helper on this player's move (his state: tests, the admin)

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
}

export type Body = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid,
	walking: boolean,
	ordered: Vector3?, -- where the walk was last ordered
	orderedAt: number,
	speed: number,
	path: Path?, -- his PathfindingService path (made once)
}

-- How he walks: one step toward `to` at `speed` studs / s; a stop; his way round the walls (may yield; nil: straight).
export type Mover = {
	move: (body: Body, to: Vector3, speed: number, dt: number) -> (),
	halt: (body: Body) -> (),
	route: ((body: Body, from: Vector3, to: Vector3) -> { Vector3 }?)?,
}

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
	lastPos: Vector3?,
	doorAt: number, -- when he last went through the front door (not back at once)
	path: { Vector3 },
	pathIndex: number,
	pathGoal: Vector3?,
	pathAt: number,
	pathing: boolean,
	gaveUp: { [number]: number }, -- the lifts he gave up on: until when (HelpRetry s; or the thing goes down, an order)
	apartFor: number,
	waited: number, -- s at the truck's shut back with a thing
	dropping: boolean, -- he sets the thing in his arms down beside the truck (no room, the back stayed shut)
	thinkAt: number,
	lift: number?,
	pick: number?,
	full: boolean,
	toldFull: boolean, -- "Truck's full, boss." said since it got full
	fitKey: number, -- the truck's load when fits was worked out
	fits: { [number]: boolean },
	input: Brain.Input,
	candidates: { Brain.Candidate },
	candidatePool: { Brain.Candidate },
	lifts: { Brain.Lift },
	liftPool: { Brain.Lift },
	doors: Brain.Doors,
	exitIn: Vector3, -- the front door inside (where "Leave house" is)
	entryIn: CFrame, -- where you come in
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
local WALK = { through = true, near = 0.6 } -- Npcs.walkTo's options: he walks on into the next order

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

-- The truck stands by the house (he carries things out only then).
local function truckAtHouse(s: any, truck: Vehicles.Car?): boolean
	local door: Vector3 = s.site.door
	return truck ~= nil and flat(truck.chassis.Position, door) <= cfg.TruckFar
end

local function truckStill(truck: Vehicles.Car): boolean
	return Vehicles.speed(truck) <= Config.Cargo.MaxCarSpeed
end

-- A point by the truck's back: `side` studs to its right, `out` studs out of it (nil: no back).
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

-- The ground under (x, z) near refY (the interior's floor, not its roof), else refY.
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

local function say(h: Helper, key: string, clock: number, force: boolean?)
	local body = h.body
	local text = Brain.Lines[key]
	if not body or not text then
		return
	end
	local last = h.saidAt[key]
	if not force and ((last and clock - last < cfg.TalkRepeat) or clock - h.lastSaid < cfg.TalkGap) then
		return
	end
	h.saidAt[key], h.lastSaid = clock, clock
	Npcs.say(body.model, text, 3)
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

-- ── His body ───────────────────────────────────────────────────────────────

-- The floor under a point: the interior's (where you come in: a house of one floor), else the ground under it.
local function floorAt(h: Helper, at: Vector3): number
	return if insideAt(h, at) then h.entryIn.Position.Y else groundAt(at.X, at.Z, at.Y)
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
	h.lastPos, h.stuckFor = nil, 0
	clearPath(h)
end

-- Where he comes (and comes back): by the truck's back (on its left: out of the way), else outside the house's door.
local function homeSpot(h: Helper): Vector3
	local truck = truckOf(h.s)
	local spot = if truck then byTruck(truck, -4, 3) else nil
	if spot then
		return spot
	end
	local out: CFrame = h.s.site.outside
	return out.Position
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
	local body: Body = { model = model, root = root, humanoid = humanoid, walking = false, ordered = nil, orderedAt = 0, speed = 0, path = nil }
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
	h.body = nil
	if body then
		Npcs.remove(body.model)
	end
	clearPath(h)
end

-- Down: what he holds falls, he lies on his back; his body goes FALL s later, he is back Respawn s later.
local function fall(h: Helper, body: Body, clock: number)
	h.port.helperDrop(h.s, body.model, "died")
	say(h, "down", clock, true)
	mover.halt(body)
	h.dead, h.downAt = true, clock
	local root = body.root
	local y = floorAt(h, root.Position - Vector3.new(0, 2, 0))
	local at = Vector3.new(root.Position.X, y + 0.6, root.Position.Z)
	body.model:PivotTo(CFrame.new(at) * CFrame.Angles(-math.pi / 2, 0, 0))
	tell(h, `🧑‍🔧 {cfg.Name} is down! He is back at the truck in {cfg.Respawn} s.`)
end

-- Through the front door (no fade: he is not a player), to where the players come out or in.
local function transfer(h: Helper, inside: boolean, clock: number)
	h.doorAt = clock
	if inside then
		placeAt(h, h.entryIn.Position + h.entryIn.LookVector * 1.5, h.entryIn.LookVector)
	else
		local out: CFrame = h.s.site.outside
		local right = Vector3.new(-out.LookVector.Z, 0, out.LookVector.X)
		placeAt(h, out.Position + right * 2, out.LookVector)
	end
end

-- ── The way ────────────────────────────────────────────────────────────────

-- The next point toward `target`: his path's (worked out again at most every Repath s, in the background, when the
-- target moved off it or he is stuck), else straight.
local function wayTo(h: Helper, body: Body, here: Vector3, target: Vector3, clock: number): Vector3
	local route = mover.route
	local goal = h.pathGoal
	if route and not h.pathing and clock - h.pathAt >= cfg.Repath and (goal == nil or flat(goal, target) > 3 or h.stuckFor > 0.5) then
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
-- world, then by the way; far off (Far), or stuck StuckSnap s, he appears at the next point. True: there (within near).
local function go(h: Helper, body: Body, goal: Vector3, goalInside: boolean, near: number, speed: number, dt: number, clock: number): boolean
	local here = body.root.Position
	local inside = insideAt(h, here)
	local target = goal
	if inside ~= goalInside then
		local out: CFrame = h.s.site.outside
		local door = if inside then h.exitIn else out.Position
		if flat(here, door) <= cfg.DoorReach and clock - h.doorAt > 1 then
			transfer(h, not inside, clock)
			return false
		end
		target = door
	elseif flat(here, goal) <= near then
		mover.halt(body)
		h.stuckFor, h.lastPos = 0, nil
		return true
	end
	if flat(here, target) > cfg.Far then
		placeAt(h, target, nil)
		return false
	end
	local last = h.lastPos
	h.stuckFor = Brain.stuck(h.stuckFor, if last then flat(here, last) else speed * dt, dt, speed)
	h.lastPos = here
	local way = wayTo(h, body, here, target, clock)
	if h.stuckFor >= cfg.StuckSnap then
		placeAt(h, way, nil)
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
	-- the truck's room for each thing, again only when its load changed
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
		if thing.class == "hand" and (thing.state == "home" or thing.state == "ground") then
			local fits = h.fits[spot]
			if fits == nil then
				fits = Rules.fit(move.packing, thing.size) ~= nil
				h.fits[spot] = fits
			end
			local n = #h.candidates + 1
			local c = h.candidatePool[n]
			if not c then
				c = { spot = 0, class = "", state = "", star = false, broken = false, cost = 0, fits = false, byTruck = false }
				h.candidatePool[n] = c
			end
			c.spot, c.class, c.state, c.star, c.broken = spot, thing.class, thing.state, thing.star, Rules.broken(thing)
			c.cost = Brain.routeCost(fromInside, here.X, here.Z, inside, at.X, at.Z, h.doors)
			c.fits = fits
			c.byTruck = back ~= nil and not inside and flat(at, back) <= 12
			h.candidates[n] = c
		elseif thing.class == "pair" and thing.state == "carried" then
			local carrier = if thing.carrier then Players:GetPlayerByUserId(thing.carrier) else nil
			local n = #h.lifts + 1
			local l = h.liftPool[n]
			if not l then
				l = { spot = 0, class = "", state = "", helped = false, crew = false, cost = 0, gaveUp = false }
				h.liftPool[n] = l
			end
			l.spot, l.class, l.state = spot, thing.class, thing.state
			l.helped = thing.helper ~= nil
			l.crew = carrier ~= nil and s.members[carrier] == true
			l.cost = Brain.routeCost(fromInside, here.X, here.Z, inside, at.X, at.Z, h.doors)
			l.gaveUp = h.gaveUp[spot] ~= nil
			h.lifts[n] = l
		end
	end
	h.pick, h.full = Brain.pickItem(h.candidates, truck ~= nil and Vehicles.backOpen(truck))
	h.lift = Brain.pickLift(h.lifts)
	if not h.full then
		h.toldFull = false
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

-- ── What he does ───────────────────────────────────────────────────────────

-- At the truck's open back, the truck standing: loads what he carries (true: in).
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

-- His end of a pair thing: at its far end, with the carrier through the doors; left behind HelpWait s, he lets go.
local function actHold(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	local carrier = if thing.carrier then Players:GetPlayerByUserId(thing.carrier) else nil
	local character = carrier and carrier.Character
	local carrierRoot = character and character:FindFirstChild("HumanoidRootPart")
	if not item or not carrierRoot or not carrierRoot:IsA("BasePart") then
		return
	end
	local here = body.root.Position
	if insideAt(h, carrierRoot.Position) ~= insideAt(h, here) then
		-- the carrier went through the front door: he comes along at their side
		local side = carrierRoot.CFrame * CFrame.new(3.5, 0, 0)
		placeAt(h, side.Position - Vector3.new(0, 3, 0), carrierRoot.CFrame.LookVector)
		h.doorAt, h.apartFor = clock, 0
		return
	end
	local size = thing.size
	local reach = math.max(size.X, size.Z) / 2 + Config.Moving.Tether
	local letGo: boolean
	h.apartFor, letGo = Brain.apart(h.apartFor, flat(here, item.root.Position), reach, dt)
	if letGo then
		h.port.helperDrop(s, body.model, "apart")
		h.gaveUp[spot], h.apartFor = clock + cfg.HelpRetry, 0
		say(h, "apart", clock, true)
		return
	end
	local far = (item.root.CFrame * CFrame.new(0, 0, -(size.Z / 2 + 1))).Position
	if flat(here, far) > 0.8 then
		mover.move(body, far, Brain.speed(walkSpeed(), "hold", nil, thing.weight), dt)
	else
		mover.halt(body)
	end
end

-- To a player's lift: his own thing first (into the truck right here, else set down), then to the far end, and takes it.
local function actHelp(h: Helper, body: Body, spot: number, holding: string?, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item or thing.state ~= "carried" or thing.class ~= "pair" or thing.helper ~= nil then
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
	if h.action ~= "help" or h.spot ~= spot then
		h.stuckFor = 0
		say(h, "help", clock)
	end
	local at = item.root.Position
	local inside = insideAt(h, at)
	local here = body.root.Position
	if insideAt(h, here) == inside and flat(here, at) <= math.max(thing.size.X, thing.size.Z) / 2 + cfg.HelpReach then
		mover.halt(body)
		if h.port.helperTake(s, spot, body.model) then
			say(h, "lift", clock, true)
			h.apartFor = 0
		else
			h.gaveUp[spot] = clock + cfg.HelpRetry
		end
		h.thinkAt = 0
		return
	end
	local far = (item.root.CFrame * CFrame.new(0, 0, -(thing.size.Z / 2 + 1))).Position
	go(h, body, far, inside, 0.5, Brain.speed(walkSpeed(), "help", nil, 0), dt, clock)
	if h.stuckFor >= cfg.HelpWait then
		h.gaveUp[spot], h.stuckFor = clock + cfg.HelpRetry, 0
		say(h, "stuck", clock, true)
		h.thinkAt = 0
	end
end

-- To the next one-hand thing; there, he picks it up.
local function actFetch(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local item = s.items[spot]
	if not thing or not item or thing.class ~= "hand" or (thing.state ~= "home" and thing.state ~= "ground") then
		h.pick, h.thinkAt = nil, 0
		return
	end
	local at = item.root.Position
	local inside = insideAt(h, at)
	local here = body.root.Position
	local half = math.max(thing.size.X, thing.size.Z) / 2
	if insideAt(h, here) == inside and flat(here, at) <= half + cfg.PickReach then
		mover.halt(body)
		if not h.port.helperTake(s, spot, body.model) then
			h.pick = nil
		end
		h.waited, h.dropping, h.thinkAt = 0, false, 0
		return
	end
	-- (the way's end beside it, on his side: a path can't end inside a thing that stands in the way)
	local from = here
	if insideAt(h, here) ~= inside then
		local out: CFrame = s.site.outside
		from = if inside then h.entryIn.Position else out.Position
	end
	local side = Vector3.new(from.X - at.X, 0, from.Z - at.Z)
	local beside = if side.Magnitude > 0.1 then at + side.Unit * (half + 1.5) else at
	go(h, body, beside, inside, 0.5, Brain.speed(walkSpeed(), "fetch", nil, 0), dt, clock)
end

-- With a thing in his arms: to the truck's back and in; no room or the back shut too long: beside the truck. No truck
-- by the house: set down outside the house's door.
local function actDeliver(h: Helper, body: Body, spot: number, dt: number, clock: number)
	local s = h.s
	local thing = (s.move :: Rules.Move).things[spot]
	local speed = Brain.speed(walkSpeed(), "deliver", "hand", thing.weight)
	local truck = truckOf(s)
	local here = body.root.Position
	if not truck or not truckAtHouse(s, truck) then
		local out: CFrame = s.site.outside
		local right = Vector3.new(-out.LookVector.Z, 0, out.LookVector.X)
		if go(h, body, out.Position + right * 4, false, 1.5, speed, dt, clock) then
			h.port.helperDrop(s, body.model, "put")
			h.thinkAt = 0
		end
		return
	end
	if not truckStill(truck) then
		mover.halt(body) -- (the truck is moving: he waits with it)
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
	local verdict = Brain.atTruck(Vehicles.backOpen(truck), true, h.waited)
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
	elseif verdict == "wait" then
		h.waited += dt
		say(h, "shut", clock)
	else
		h.dropping = true
	end
end

-- Behind the player he helps ("Help me"): the owner, else the nearest of the crew on foot; nobody on foot: at the truck.
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
	go(h, body, Vector3.new(x, root.Position.Y, z), insideAt(h, root.Position), 1.5, Brain.speed(walkSpeed(), "follow", nil, 0), dt, clock)
end

-- At the truck (on its left, out of the way). It moves, or it stands far off and not by the house (driven somewhere
-- else, a stop on the way): he stands where he is (he appears at it once it is parked by the house). No truck: outside
-- the house's door.
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
	go(h, body, spot :: Vector3, false, 1.5, speed, dt, clock)
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
				h.thinkAt, h.waited, h.dropping, h.fleeing, h.apartFor = 0, 0, false, false, 0
			else
				h.downAt = clock - cfg.Respawn + 2 -- (no body yet: tried again in a moment)
			end
		end
		setDoing(h, "down", nil)
		return
	end
	if not body or not body.model.Parent or not body.humanoid.Parent then
		-- his body went (removed by something else): like a fall
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
	input.lift, input.pick = h.lift, h.pick
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
	elseif action == "help" and target then
		actHelp(h, body, target, holding, dt, clock)
	elseif action == "deliver" and spot then
		actDeliver(h, body, spot, dt, clock)
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
		lastPos = nil,
		doorAt = 0,
		path = {},
		pathIndex = 1,
		pathGoal = nil,
		pathAt = -math.huge,
		pathing = false,
		gaveUp = {},
		apartFor = 0,
		waited = 0,
		dropping = false,
		thinkAt = 0,
		lift = nil,
		pick = nil,
		full = false,
		toldFull = false,
		fitKey = -1,
		fits = {},
		input = { mode = "carry", dead = false, holding = nil, threat = nil, fleeing = false, lift = nil, pick = nil, atHouse = false },
		candidates = {},
		candidatePool = {},
		lifts = {},
		liftPool = {},
		doors = { outX = outside.Position.X, outZ = outside.Position.Z, inX = exitIn.X, inZ = exitIn.Z },
		exitIn = exitIn,
		entryIn = entry,
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
	tell(h, `🧑‍🔧 {cfg.Name} from the depot joins your move: he carries the small things to the truck and lifts with you. Orders: the DANNY buttons under the move's panel.`)
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
