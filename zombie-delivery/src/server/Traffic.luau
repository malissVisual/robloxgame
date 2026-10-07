--!strict
-- Traffic (Config.Traffic): civilian cars driving the roads and people walking the sidewalks, near the players only.
-- They appear out of sight (SpawnMin .. SpawnMax studs away, preferably behind you) and vanish far away (Despawn),
-- with hard caps per player and for the server. Nothing drives in the winter, on the ice road or through the tunnel
-- (shared/TrafficLanes.luau), and the pedestrians only walk the city blocks, never the far places (the bandit camps).
--
-- Cars. Ordinary bodies from Vehicles.buildNpc (van, pickup, muscle car, now and then a moving truck or a bus) in
-- civilian paint, stripped to what a civilian car needs: no roof gun, no movers, no wheel colliders, one driver.
-- They are ANCHORED and the server steps them along their lane at 10 Hz (TICK): a car drives on the right of the
-- road, slows for the turns and picks a random road at every junction (a U-turn at a dead end). Why anchored and not
-- physics: forty server-owned physics cars cost far more, they get pushed off the road, tip over and get stuck on
-- curbs; an anchored car cannot be shoved, never leaves its lane and costs one CFrame write per tick. The clients
-- smooth the 10 Hz steps (client/TrafficAnimator.luau interpolates between the server's positions every frame and
-- spins the wheels); without it the cars still drive, just in small steps.
--   * A car stops for anything in its lane ahead: another traffic car, your car, a bandit car, a player or a
--     pedestrian on foot. Two traffic cars waiting for each other at a junction give way after a few seconds.
--   * Crash into one at speed (WreckSpeed) and it is a wreck: knocked aside, dark, smoking, standing there for a
--     while (WreckTime), then it is towed away (vanishes when nobody is close).
--   * Headlights: on at night (the workspace attribute Night, set by server/DayNight.luau).
--   * 3.9, traffic lights (shared/Crossings.luau) at the districts' four-way junctions: a car whose lane ends at one
--     stops at the stop line (StopBack before the lane's end, just before the crosswalk) on red, and on amber when it
--     can still stop (AmberBrake); waiting at a red light never makes it turn around or give way. The light cycle is
--     a function of workspace:GetServerTimeNow(): the clients draw the same colours on the poles themselves.
--
-- Pedestrians. R15 people (server/Npcs.luau: Npcs.spawn, Npcs.walkTo) on the sidewalk ring of the blocks, corner to
-- corner. Fewer at night. 3.10, on the sidewalk: they walk only the walk lines of shared/TrafficLanes.luau (a line
-- per side of a block, 4.5 studs in from the curb: off the lamps and light poles on the corners, off the buildings),
-- which the server checks against the built world once at the start (a special block's wall or flag pole on a line:
-- a detour, or that side is closed; a crosswalk with something on it: nobody crosses there). A route flows from point
-- to point (no halt at the corners) at the person's own stroll (Config.Traffic.WalkSpeed, the legs at the matching
-- pace: Npcs.pace); somebody pushed off the line steps back onto it first. A walk that makes no progress for
-- StuckAfter seconds is given up (back the other way); who keeps getting stuck goes when nobody looks. A zombie
-- within FLEE_RANGE and they run (RunSpeed, the run animation) along the ring away from it, round the corners, until
-- it is gone; then they catch their breath and stroll on. 3.9, living streets:
--   * They cross a street ONLY over a crosswalk (shared/Crossings.luau, painted by server/World.luau): from a corner
--     straight over to the facing corner. They wait at the curb (a step toward the street from the corner, out of
--     the way), facing the street, for the walk phase (their street's traffic red for CrossTime more seconds) or,
--     with no lights there, for a gap in the traffic; after CrossWait they go on round the block instead. The cars
--     stop for anybody in their lane.
--   * Groups (GroupChance of the new people, GroupSize): two to four standing in an oval along the sidewalk of an
--     ordinary block, between the walk line and the buildings, or round on a corner inside the turn of the walk
--     lines (a spot the world shows clear), out of the safe zone and off the addresses, cargo spots and employers.
--     They turn to whoever talks, nod or shift (Npcs.gesture), say a line now and then (Npcs.say) and after
--     GroupTime break up and walk off both ways. Standing people cost no pathing: the cheap way to more people.
--   * Walkers stop: at a shop window now and then (WindowChance: a wall straight in from the line; they step up to
--     it and look), and two walkers passing each other may stop for a word (MeetChance): both step off the line
--     toward the buildings and face each other. The walkers pass them by.
--
-- Bandits among them. During a player's job (driving, out of the safe zone, ★★ and up when Jobs.crewStatus tells
-- the stars) a traffic car behind them can turn out to be a bandit pickup now and then: it vanishes and
-- BanditCars.chase spawns the pickup on that spot, heading the same way. Never more than one chasing at a time.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Crossings = require(Shared.Crossings)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local TrafficLanes = require(Shared.TrafficLanes)
local Vehicles = require(script.Parent.Vehicles)
local Npcs = require(script.Parent.Npcs)
local BanditCars = require(script.Parent.BanditCars)
local Zombies = require(script.Parent.Zombies)
local Jobs = require(script.Parent.Jobs)
local DayNight = require(script.Parent.DayNight)

local Traffic = {}

local Tuning = Config.Traffic

local TICK = 0.1 -- the cars move this often (client/TrafficAnimator.luau smooths it)
local MANAGE_EVERY = 0.5 -- spawning, despawning, the pedestrians' minds
local BANDIT_EVERY = 2 -- checking for a bandit among the traffic
local ACCEL = 14 -- studs / s²
local BRAKE = 40
local LANE_HALF = 3.8 -- something this far beside the lane's line is in the way
local WRECK_SPEED = 30 -- a player's car hitting a traffic car this fast wrecks it
local WRECK_TIME = 30 -- seconds a wreck stands before it may be towed away
local WRECK_MAX = 90 -- and then it goes, watched or not
local GIVE_WAY = 4 -- seconds two traffic cars wait for each other before one drives through
local TURN_BACK = 9 -- seconds behind something else that does not move (your parked car) before turning around
local SPACING = 40 -- no new car this close to another
local CAR_SPAWNS_PER_TICK = 2
local PED_SPAWNS_PER_TICK = 2
local PED_SPAWN_MIN = 70
local PED_SPAWN_MAX = 170
local PED_DESPAWN = 240
local FLEE_RANGE = 40
local CALM_AFTER = 4 -- seconds without a zombie in range
local PAUSE_CHANCE = 0.12 -- at a corner (Tuning.CrossChance: over the street)
local BANDIT_FIRST = 25 -- seconds into a job before a traffic car can be bandits
local BANDIT_GAP = { 70, 120 } -- seconds between them (one player)
local BANDIT_RANGE = { 70, 220 }

-- The bodies: the dealer's cars mostly, now and then a work truck (Config.Cars ids, weight). 5.1: no bikes.
local BODIES: { { id: string, weight: number } } = {
	{ id = "van", weight = 4 },
	{ id = "courier", weight = 2 }, -- 3.3: the new vans drive past too (their backs welded shut, no kit; 3.5: any stage)
	{ id = "highroof", weight = 1.5 },
	{ id = "pickup", weight = 4 },
	{ id = "boxtruck", weight = 1 },
	{ id = "muscle", weight = 3 },
	{ id = "movingtruck", weight = 1 },
	{ id = "bus", weight = 0.4 },
}
local PAINTS = {
	{ 178, 34, 34 },
	{ 30, 70, 140 },
	{ 220, 220, 214 },
	{ 40, 40, 44 },
	{ 120, 124, 130 },
	{ 200, 160, 40 },
	{ 46, 110, 70 },
	{ 150, 100, 60 },
	{ 90, 140, 190 },
	{ 110, 40, 90 },
}
local SHIRTS = { { 70, 110, 160 }, { 160, 60, 60 }, { 90, 130, 90 }, { 200, 180, 140 }, { 60, 60, 66 }, { 210, 140, 60 } }
local SKINS = { { 255, 224, 196 }, { 241, 194, 160 }, { 214, 160, 120 }, { 176, 122, 84 }, { 132, 88, 60 } }
-- A fixed pool of passers-by (server/Npcs.luau makes one body template per look, so the pool stays small).
local NAMES = {
	"Ann", "Bob", "Carla", "Dan", "Eva", "Frank", "Gina", "Hank", "Iris", "Jon", "Kate", "Leo",
	"Mona", "Ned", "Olive", "Pete", "Rita", "Sam", "Tess", "Vic", "Wendy", "Yvonne", "Zoe", "Max",
}
local SCREAMS = { "ZOMBIES!", "Run!", "Help!", "Get away from me!", "Not again..." }
-- 3.9: what the people say.
local CHAT = {
	"Did you hear the sirens?",
	"Stay off Route 9 tonight.",
	"They say the bridge is still open.",
	"My cousin saw one by the docks.",
	"FreshMart doubled the prices again.",
	"The radio said help is coming.",
	"Lock your doors after dark.",
	"Who still delivers in this town?",
	"Gunshots by the Harbor last night.",
	"No way. Really?",
	"Ha! Good one.",
	"...",
	"Mm-hm.",
	"That delivery van again...",
	"The clinic is out of bandages.",
	"Keep your voice down.",
}
local GREETINGS = { "Hey!", "Oh, hi!", "Long time no see.", "You're still around?", "Stay safe out there." }
local REPLIES = { "Hey yourself.", "Barely.", "Can't complain. Well...", "Same old.", "You too!" }
local BYES = { "See you around.", "Stay safe!", "Gotta go.", "Later!" }

type Car = {
	model: Model,
	chassis: BasePart,
	offset: CFrame, -- the chassis relative to the point on the road
	size: Vector3, -- the hull (width, height, length)
	half: number, -- half the length
	piece: TrafficLanes.Piece,
	s: number, -- studs along the piece
	nextEdge: number?, -- where it turns at the end of this lane
	cruise: number,
	speed: number,
	x: number,
	z: number,
	hx: number,
	hz: number,
	waited: number, -- seconds stopped behind something
	giveWayUntil: number, -- ignores the other traffic cars until then (two waiting for each other)
	ghostUntil: number, -- ignores everything until then (turning around)
	wrecked: boolean,
	wreckedAt: number,
	lights: { SpotLight }, -- the headlights' beams
}

type Ped = {
	model: Model,
	root: BasePart,
	humanoid: Humanoid?,
	d: Map.District,
	i: number,
	j: number,
	k: number, -- the corner it walks to (crossing: the corner it crosses from)
	dir: number, -- around the ring: +1 or -1
	speed: number, -- its own stroll (Tuning.WalkSpeed)
	pace: number, -- the speed it moves at now
	order: number, -- the walkTo it is on (stale callbacks are ignored)
	walking: boolean,
	route: { number }, -- flat x, z of the points still to walk (the goal last)
	crossing: number, -- 0: no; 1: to the curb; 2: waiting there; 3: over the street to corner ck of block (ci, cj)
	ci: number,
	cj: number,
	ck: number,
	zebra: Crossings.Crosswalk?, -- the crosswalk it crosses
	waitSince: number, -- at the curb, waiting to cross, since
	restUntil: number,
	stop: Vector3?, -- walking to a spot to stand (a shop window, a word with somebody): what to face there
	stopFor: number, -- and for how long
	fleeing: boolean,
	calmAt: number,
	nextFlee: number,
	spin: number, -- +1 / -1: the way it runs when a zombie is right beside it (a group scatters both ways)
	group: Group?, -- standing with others, talking
	meetAfter: number, -- no stopping for a word before this
	fails: number, -- walks given up in a row (StuckLimit: it goes, out of sight)
}

-- 3.9: people standing together, talking.
type Group = {
	members: { Ped },
	x: number,
	z: number,
	endsAt: number,
	talkAt: number,
	ka: number, -- the corners at both ends of the side it stands by (they walk off toward one or the other)
	kb: number,
}

type Viewer = {
	player: Player,
	x: number,
	z: number,
	hx: number, -- the way they look or drive (0, 0 = unknown)
	hz: number,
}

local cars: { Car } = {}
local peds: { Ped } = {}
local groups: { Group } = {}
local junctions = Crossings.junctions()
local nodeLight: { [number]: number } = {} -- lane graph node → its traffic light (a Crossings.junctions index)
local rng = Random.new()
local folder: Folder? = nil
local started = false
local graph: TrafficLanes.Graph? = nil
local banditAt: { [Player]: number } = {} -- the next time a traffic car may be bandits for this player
local jobSince: { [Player]: number } = {}

local function rand(): number
	return rng:NextNumber()
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function isNight(): boolean
	local night = workspace:GetAttribute("Night")
	if type(night) == "boolean" then
		return night
	end
	return DayNight.isNight()
end

-- ── Cars ───────────────────────────────────────────────────────────────────

local function pickBody(): Config.CarDef?
	local total = 0
	for _, b in BODIES do
		total += b.weight
	end
	local roll = rand() * total
	local id = BODIES[1].id
	for _, b in BODIES do
		roll -= b.weight
		if roll <= 0 then
			id = b.id
			break
		end
	end
	for _, def in Config.Cars do
		if def.id == id and not def.bike then -- (5.1: never a bike, CarDef.bike: Vehicles.buildTraffic takes the van)
			local copy = table.clone(def)
			if id ~= "bus" then
				copy.color = PAINTS[rng:NextInteger(1, #PAINTS)]
			end
			return copy
		end
	end
	return nil
end

local function setLights(car: Car, on: boolean)
	for _, light in car.lights do
		light.Enabled = on
	end
end

-- A civilian car out of Vehicles.buildTraffic (no gun, a civilian driver): the movers and the leftover cargo marks
-- go (it is stepped by CFrame), the headlight beams are collected; the old bandit leftovers are cleaned defensively.
local function civilian(npc: Vehicles.TrafficCar): { SpotLight }
	local model = npc.model
	local gun = model:FindFirstChild("CarGun")
	if gun then
		gun:Destroy()
	end
	npc.linear:Destroy()
	npc.angular:Destroy()
	for _, name in { "Root", "CargoDoor", "CargoEntry" } do
		local a = npc.chassis:FindFirstChild(name)
		if a then
			a:Destroy()
		end
	end
	model:SetAttribute("CargoCount", nil)
	local body, head = false, false
	local lights: { SpotLight } = {}
	for _, child in model:GetChildren() do
		if not child:IsA("BasePart") then
			continue
		end
		local name = child.Name
		if name == "WheelCollider" or name == "Bandana" or name == "BanditGun" then
			child:Destroy()
		elseif name == "BanditBody" then
			if body then
				child:Destroy() -- a passenger
			else
				body = true
				child.Name = "Driver"
				child.Color = rgb(SHIRTS[rng:NextInteger(1, #SHIRTS)])
				child.CanQuery = false
			end
		elseif name == "BanditHead" then
			if head then
				child:Destroy()
			else
				head = true
				child.Name = "DriverHead"
				child.Color = rgb(SKINS[rng:NextInteger(1, #SKINS)])
				child.CanQuery = false
			end
		else
			child.CanTouch = false
			if name == "Headlight" then
				local light = child:FindFirstChildOfClass("SpotLight")
				if light then
					table.insert(lights, light)
				end
			end
		end
	end
	return lights
end

local function carFrame(x: number, z: number, hx: number, hz: number): CFrame
	local at = Vector3.new(x, Map.RoadTop, z)
	if hx * hx + hz * hz < 1e-6 then
		return CFrame.new(at)
	end
	return CFrame.lookAt(at, at + Vector3.new(hx, 0, hz))
end

local function enterLane(car: Car, g: TrafficLanes.Graph, edge: number)
	car.piece = TrafficLanes.lane(g, edge)
	car.nextEdge = TrafficLanes.nextEdge(g, edge, rand())
end

local function spawnCar(g: TrafficLanes.Graph, edge: number, s: number): Car?
	local def = pickBody()
	local parent = folder
	if not def or not parent then
		return nil
	end
	local piece = TrafficLanes.lane(g, edge)
	local x, z, hx, hz = TrafficLanes.at(piece, s)
	local ground = carFrame(x, z, hx, hz)
	-- 3.5: at a random stage (a Rusty Van, a Work Van, a Cargo Van …).
	local stage = math.floor(rand() * (Economy.maxStage(def.id) + 1))
	local ok, npc = pcall(Vehicles.buildTraffic, def, ground, nil, stage)
	if not ok then
		warn(`[Traffic] no car: {npc}`)
		return nil
	end
	local lights = civilian(npc)
	local chassis = npc.chassis
	chassis.Anchored = true
	npc.model.Name = "Traffic Car"
	npc.model:SetAttribute("Traffic", true)
	local car: Car = {
		model = npc.model,
		chassis = chassis,
		offset = ground:ToObjectSpace(chassis.CFrame),
		size = npc.size,
		half = npc.size.Z / 2,
		piece = piece,
		s = s,
		nextEdge = nil,
		cruise = Tuning.CarSpeed * rng:NextNumber(0.85, 1.1),
		speed = 0,
		x = x,
		z = z,
		hx = hx,
		hz = hz,
		waited = 0,
		giveWayUntil = 0,
		ghostUntil = 0,
		wrecked = false,
		wreckedAt = 0,
		lights = lights,
	}
	enterLane(car, g, edge)
	car.s = s
	car.speed = car.cruise * piece.speed * 0.8
	setLights(car, isNight())
	npc.model.Parent = parent
	table.insert(cars, car)
	return car
end

local function removeCar(car: Car)
	local index = table.find(cars, car)
	if index then
		table.remove(cars, index)
	end
	car.model:Destroy()
end

-- Knocked aside, dark and smoking; it stands there for a while.
local function wreck(car: Car, push: Vector3)
	if car.wrecked then
		return
	end
	car.wrecked = true
	car.wreckedAt = os.clock()
	car.speed = 0
	setLights(car, false)
	local flat = Vector3.new(push.X, 0, push.Z)
	local shove = if flat.Magnitude > 1 then flat.Unit * math.min(flat.Magnitude * 0.08, 4) else Vector3.zero
	local spin = CFrame.Angles(0, rng:NextNumber(0.2, 0.5) * (if rand() < 0.5 then -1 else 1), 0)
	car.x += shove.X
	car.z += shove.Z
	car.chassis.CFrame = carFrame(car.x, car.z, car.hx, car.hz) * spin * car.offset
	for _, d in car.model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		if CollectionService:HasTag(d, DayNight.Tag) then
			-- A lamp of the car: off for good (DayNight would light it again at the next dusk).
			CollectionService:RemoveTag(d, DayNight.Tag)
			d.Material = Enum.Material.SmoothPlastic
			local dim = d:GetAttribute("DimColor")
			if typeof(dim) == "Color3" then
				d.Color = dim
			end
			for _, l in d:GetChildren() do
				if l:IsA("Light") then
					l.Enabled = false
				end
			end
		end
		if d.Transparency < 1 then
			d.Color = d.Color:Lerp(Color3.fromRGB(30, 28, 26), 0.55)
		end
	end
	local smoke = Instance.new("Smoke")
	smoke.Color = Color3.fromRGB(60, 60, 60)
	smoke.Size = 6
	smoke.RiseVelocity = 6
	smoke.Opacity = 0.35
	smoke.Parent = car.chassis
	car.model:SetAttribute("Wrecked", true)
end

-- Is the point within `reach` of the car's box (flat)?
local function inBox(cframe: CFrame, size: Vector3, point: Vector3, reach: number): boolean
	local p = cframe:PointToObjectSpace(point)
	return math.abs(p.X) <= size.X / 2 + reach and math.abs(p.Z) <= size.Z / 2 + reach and math.abs(p.Y) <= size.Y + reach
end

-- ── The things a car stops for ─────────────────────────────────────────────
-- Flat arrays, refilled every tick (no tables made in the loop).

local obstacleX: { number } = {}
local obstacleZ: { number } = {}
local obstacleR: { number } = {} -- radius
local obstacleCar: { Car | false } = {} -- the traffic car it is (false: anything else)
local obstacleCount = 0

local function addObstacle(x: number, z: number, r: number, car: Car | false)
	obstacleCount += 1
	obstacleX[obstacleCount] = x
	obstacleZ[obstacleCount] = z
	obstacleR[obstacleCount] = r
	obstacleCar[obstacleCount] = car
end

local function gatherObstacles()
	obstacleCount = 0
	for _, car in cars do
		-- A wreck is not traffic: the cars behind it wait and turn around, never give way into it.
		addObstacle(car.x, car.z, car.half, if car.wrecked then false else car)
	end
	-- Player cars and bandit cars as three points along their middle (nose, centre, tail), each with half the width:
	-- a car standing across the road blocks both lanes.
	for _, playerCar in Vehicles.all() do
		local frame = playerCar.chassis.CFrame
		local p = frame.Position
		local r = playerCar.size.X / 2
		local along = frame.LookVector * math.max(playerCar.size.Z / 2 - r, 0)
		addObstacle(p.X, p.Z, r, false)
		addObstacle(p.X + along.X, p.Z + along.Z, r, false)
		addObstacle(p.X - along.X, p.Z - along.Z, r, false)
	end
	local bandits = workspace:FindFirstChild("BanditCars")
	if bandits then
		for _, model in bandits:GetChildren() do
			local chassis = if model:IsA("Model") then model.PrimaryPart else nil
			if chassis then
				local frame = chassis.CFrame
				local p = frame.Position
				local along = frame.LookVector * (6.5 - 3.5)
				addObstacle(p.X, p.Z, 3.5, false)
				addObstacle(p.X + along.X, p.Z + along.Z, 3.5, false)
				addObstacle(p.X - along.X, p.Z - along.Z, 3.5, false)
			end
		end
	end
	-- 5.5: the city buses (server/Buses.luau) keep their timetable and never stop for a car: the cars give way to them
	-- (five points along the bus's middle, its half width each).
	local buses = workspace:FindFirstChild("Buses")
	if buses then
		for _, model in buses:GetChildren() do
			local chassis = if model:IsA("Model") then model.PrimaryPart else nil
			if chassis then
				local frame = chassis.CFrame
				local p = frame.Position
				for _, along in { -8, -4, 0, 4, 8 } do
					local at = p + frame.LookVector * along
					addObstacle(at.X, at.Z, 4, false)
				end
			end
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			addObstacle(root.Position.X, root.Position.Z, 1.5, false)
		end
	end
	for _, ped in peds do
		local p = ped.root.Position
		addObstacle(p.X, p.Z, 1.2, false)
	end
end

-- The speed the car may drive with what is ahead in its lane (and the traffic car that stops it, if one does).
local function clearance(car: Car, limit: number): (number, Car?)
	local look = 8 + car.half + car.speed * 1.1
	local blocker: Car? = nil
	local now = os.clock()
	if now < car.ghostUntil then
		return limit, nil
	end
	local giveWay = now < car.giveWayUntil
	for n = 1, obstacleCount do
		local other = obstacleCar[n]
		if other == car or (giveWay and other) then
			continue
		end
		local rx, rz = obstacleX[n] - car.x, obstacleZ[n] - car.z
		local ahead = rx * car.hx + rz * car.hz
		local r = obstacleR[n]
		if ahead <= 0 or ahead > look + r then
			continue
		end
		local beside = math.abs(rx * car.hz - rz * car.hx)
		if beside > LANE_HALF + math.min(r, 3.5) then
			continue
		end
		local gap = ahead - car.half - r - 3
		local allowed = math.max(gap, 0) * 1.3
		if allowed < limit then
			limit = allowed
			blocker = if other then other :: Car else nil -- false: not a traffic car
		end
	end
	return limit, blocker
end

-- 3.9: the traffic light at the end of the car's lane: the speed that stops it at the stop line (math.huge: none,
-- green, already past the line, or too close to stop on amber).
local function lightLimit(car: Car, g: TrafficLanes.Graph, clock: number): number
	if car.piece.turn then
		return math.huge
	end
	local edge = car.piece.edge
	local light = nodeLight[g.to[edge]]
	if not light then
		return math.huge
	end
	local remaining = car.piece.length - Tuning.StopBack - car.s - car.half
	if remaining < -0.5 or remaining > 80 then
		return math.huge
	end
	local state = Crossings.state(clock, junctions[light].offset, Crossings.axisOf(g.dx[edge], g.dz[edge]))
	if state == "green" or (state == "amber" and remaining < car.speed * car.speed / (2 * Tuning.AmberBrake)) then
		return math.huge
	end
	return math.max(remaining, 0) * 1.3
end

local function moveCar(car: Car, g: TrafficLanes.Graph, dt: number, clock: number)
	local target = car.cruise * car.piece.speed
	-- Slow down before a turn.
	if not car.piece.turn and car.nextEdge then
		local turn = TrafficLanes.turn(g, car.piece.edge, car.nextEdge :: number)
		local remaining = car.piece.length - car.s
		if turn.speed < 1 and remaining < 30 then
			target = math.min(target, car.cruise * turn.speed + remaining * 0.7)
		end
	end
	local limit, blocker = clearance(car, target)
	local stopLine = lightLimit(car, g, clock)
	local byLight = stopLine < limit
	if byLight then
		limit, blocker = stopLine, nil
	end
	local byTraffic = blocker ~= nil
	if limit < 1 and byLight then
		car.waited = 0 -- a red light: just wait (no giving way, no turning around)
	elseif limit < 1 then
		car.waited += dt
		if
			blocker
			and car.waited > GIVE_WAY
			and car.hx * blocker.hx + car.hz * blocker.hz < 0.5 -- across its way, not the car ahead in its queue
			and os.clock() >= blocker.giveWayUntil -- that one is not already going: only one of the two goes
		then
			-- Two cars waiting for each other (a junction): this one drives through.
			car.giveWayUntil = os.clock() + 2.5
			car.waited = 0
		elseif not byTraffic and car.waited > TURN_BACK and not car.piece.turn then
			-- Something that stays (a parked car, somebody standing in the road): turn around.
			car.piece = TrafficLanes.turnAround(g, car.piece.edge, car.s)
			car.s = 0
			car.ghostUntil = os.clock() + 3
			car.waited = 0
			limit = car.cruise * car.piece.speed
		end
	else
		car.waited = 0
	end
	car.speed += math.clamp(limit - car.speed, -BRAKE * dt, ACCEL * dt)
	car.speed = math.max(car.speed, 0)
	if car.speed < 0.01 then
		return
	end
	car.s += car.speed * dt
	local guard = 0
	while car.s >= car.piece.length and guard < 6 do
		guard += 1
		car.s -= car.piece.length
		if car.piece.turn then
			local enter = car.piece.enter
			enterLane(car, g, car.piece.edge)
			car.s += enter
		else
			local nextEdge = car.nextEdge
			if not nextEdge then
				removeCar(car) -- nowhere to go (cannot happen on this map: dead ends turn around)
				return
			end
			car.piece = TrafficLanes.turn(g, car.piece.edge, nextEdge)
		end
	end
	local x, z, hx, hz = TrafficLanes.at(car.piece, car.s)
	car.x, car.z = x, z
	if hx * hx + hz * hz > 0.5 then
		car.hx, car.hz = hx, hz
	end
	car.chassis.CFrame = carFrame(car.x, car.z, car.hx, car.hz) * car.offset
end

-- Player cars crashing into traffic: speeds of the last tick (the crash itself has already stopped the car).
local lastSpeed: { [Model]: number } = {}

local function checkCrashes()
	local speeds: { [Model]: number } = {}
	for _, playerCar in Vehicles.all() do
		local v = playerCar.chassis.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		speeds[playerCar.model] = speed
		local fast = math.max(speed, lastSpeed[playerCar.model] or 0)
		if fast < WRECK_SPEED then
			continue
		end
		-- The player's car as three points along its middle (nose, centre, tail), each with half its width.
		local frame = playerCar.chassis.CFrame
		local p = frame.Position
		local along = frame.LookVector * (playerCar.size.Z / 2 - playerCar.size.X / 2)
		local reach = playerCar.size.X / 2 + 0.8
		for _, car in cars do
			if car.wrecked or math.abs(car.x - p.X) > 30 or math.abs(car.z - p.Z) > 30 then
				continue
			end
			local box = car.chassis.CFrame
			local size = car.size
			-- The driver hit it where their screen showed it: one animator step and about half a ping behind the
			-- server (client/TrafficAnimator.luau), so the box is also tried that far back along its heading.
			local lag = car.speed * (TICK + 0.15)
			local back = if lag > 0.5 then box - Vector3.new(car.hx, 0, car.hz) * lag else nil
			if
				inBox(box, size, p, reach)
				or inBox(box, size, p + along, reach)
				or inBox(box, size, p - along, reach)
				or (back ~= nil and (inBox(back, size, p, reach) or inBox(back, size, p + along, reach) or inBox(back, size, p - along, reach)))
			then
				local relative = Vector3.new(car.x - p.X, 0, car.z - p.Z)
				wreck(car, if relative.Magnitude > 0.1 then relative.Unit * fast else Vector3.zero)
			end
		end
	end
	lastSpeed = speeds
end

-- ── Who is around ──────────────────────────────────────────────────────────

local function viewers(): { Viewer }
	local list: { Viewer } = {}
	for _, player in Players:GetPlayers() do
		local car = Vehicles.seatedIn(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local part: BasePart? = if car then car.chassis elseif root and root:IsA("BasePart") then root else nil
		if not part then
			continue
		end
		local p = part.Position
		local v = part.AssemblyLinearVelocity
		local hx, hz = v.X, v.Z
		local speed = math.sqrt(hx * hx + hz * hz)
		if speed > 4 then
			hx, hz = hx / speed, hz / speed
		else
			local look = part.CFrame.LookVector
			local flat = math.sqrt(look.X * look.X + look.Z * look.Z)
			hx, hz = if flat > 0.1 then look.X / flat else 0, if flat > 0.1 then look.Z / flat else 0
		end
		table.insert(list, { player = player, x = p.X, z = p.Z, hx = hx, hz = hz })
	end
	return list
end

local function nearest(list: { Viewer }, x: number, z: number): number
	local best = math.huge
	for _, v in list do
		best = math.min(best, math.sqrt((v.x - x) ^ 2 + (v.z - z) ^ 2))
	end
	return best
end

-- Out of everybody's sight: far enough from all, and not in front of the one it is for when close.
local function hidden(list: { Viewer }, x: number, z: number, minD: number): boolean
	for _, v in list do
		local dx, dz = x - v.x, z - v.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < minD * 0.9 then
			return false
		end
		if d < minD * 1.6 and d > 0 and (dx * v.hx + dz * v.hz) / d > 0.55 then
			return false -- right in front of them
		end
	end
	return true
end

local lastViewers: { Viewer } = {} -- the players' places at the last manage step (a stuck person goes when unseen)

-- ── The built world, for the people on foot ────────────────────────────────
-- 3.10: what a person would bump into, asked of the world itself (the solid parts that collide with the Npc group:
-- walls, poles, lamps, benches, hydrants; not the people, the cars or the flat paint). Used once at the start for the
-- walk lines (TrafficLanes.survey) and the crosswalks, and now and then for a spot to stand (a group, two talking, a
-- shop window).

local PROBE_LOW = 1 -- studs over the sidewalk where the probe starts (a curb, a step, a lawn's edge: stepped over)
local PROBE_HIGH = 5.5
local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Exclude
overlap.RespectCanCollide = true
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true
local zebraClear: { [Crossings.Crosswalk]: boolean } = {} -- the crosswalks people may use (nothing on their line)
local surveyed = false

-- Not the traffic, not the people, not the players.
local function refreshFilter()
	local list: { Instance } = {}
	if folder then
		table.insert(list, folder)
	end
	local npcs = workspace:FindFirstChild("Npcs")
	if npcs then
		table.insert(list, npcs)
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	overlap.FilterDescendantsInstances = list
	rayParams.FilterDescendantsInstances = list
end

-- Nothing solid in this upright box: (x, z) its middle, (tx, tz) the way along it (unit), the half sizes.
local function clearRect(x: number, z: number, tx: number, tz: number, halfAlong: number, halfAcross: number): boolean
	local middle = Vector3.new(x, Map.WalkTop + (PROBE_LOW + PROBE_HIGH) / 2, z)
	local frame = CFrame.lookAt(middle, middle + Vector3.new(tx, 0, tz))
	local size = Vector3.new(halfAcross * 2, PROBE_HIGH - PROBE_LOW, halfAlong * 2)
	return #workspace:GetPartBoundsInBox(frame, size, overlap) == 0
end

-- Can a person walk this straight line (ends included)?
local function clearLine(ax: number, az: number, bx: number, bz: number): boolean
	local dx, dz = bx - ax, bz - az
	local length = math.sqrt(dx * dx + dz * dz)
	local tx, tz = if length > 0.01 then dx / length else 1, if length > 0.01 then dz / length else 0
	local body = TrafficLanes.Body
	return clearRect((ax + bx) / 2, (az + bz) / 2, tx, tz, length / 2 + body, body)
end

-- Every block's walk lines and every crosswalk, once (the world is built by then).
local function surveyAll()
	refreshFilter()
	local blocks, detours, closed, zebrasClosed = 0, 0, 0, 0
	for _, d in Map.Districts do
		for i = d.i0, d.i1 do
			for j = d.j0, d.j1 do
				blocks += 1
				closed += 4 - TrafficLanes.survey(d, i, j, clearLine)
				for s = 1, 4 do
					local inset = TrafficLanes.sideInset(d, i, j, s)
					if inset and inset ~= TrafficLanes.SidewalkInset then
						detours += 1
					end
				end
			end
			task.wait()
		end
	end
	local half = (Map.Cell - Map.BlockSize) / 2 + TrafficLanes.SidewalkInset -- the crossing: corner to corner
	for _, c in Crossings.crosswalks() do
		local ok = if c.alongX then clearLine(c.x, c.z - half, c.x, c.z + half) else clearLine(c.x - half, c.z, c.x + half, c.z)
		zebraClear[c] = ok
		if not ok then
			zebrasClosed += 1
		end
	end
	surveyed = true
	print(`[Traffic] sidewalks surveyed: {blocks} blocks, {detours} sides on a detour, {closed} closed, {zebrasClosed} crosswalks closed to people`)
end

-- ── Pedestrians ────────────────────────────────────────────────────────────

local WALK_OPTIONS: Npcs.WalkOptions = { through = true, stuck = Tuning.StuckAfter, near = 1.2 }
local WINDOW_LOOK = 12 -- a wall this far in from the walk line is a shop window to look at
local WINDOW_GAP = 2.2 -- they stand this far from it

local function removePed(ped: Ped)
	local index = table.find(peds, ped)
	if index then
		table.remove(peds, index)
	end
	local group = ped.group
	if group then
		ped.group = nil
		local at = table.find(group.members, ped)
		if at then
			table.remove(group.members, at)
		end
	end
	Npcs.remove(ped.model)
end

local function pace(ped: Ped, speed: number)
	ped.pace = speed
	Npcs.pace(ped.model, speed)
end

-- Stands where it is (anchored, idle); whatever it walked is forgotten.
local function standStill(ped: Ped)
	ped.order += 1
	ped.walking = false
	Npcs.stop(ped.model)
end

-- Stops a walker where it is for `seconds` (somewhere off the line no walk was planned to); it walks on later.
local function halt(ped: Ped, now: number, seconds: number)
	standStill(ped)
	ped.stop = nil
	ped.restUntil = now + seconds
end

-- The nearest living zombie within FLEE_RANGE of a point.
local function zombieNear(position: Vector3): Vector3?
	local best: Vector3? = nil
	local bestD = FLEE_RANGE
	for _, z in Zombies.all() do
		if z.dead then
			continue
		end
		local p = z.root.Position
		local d = Vector3.new(p.X - position.X, 0, p.Z - position.Z).Magnitude
		if d < bestD then
			best, bestD = p, d
		end
	end
	return best
end

local arrive: (Ped) -> ()
local failed: (Ped) -> ()

-- Walks the next point of its route (false: the route is done). The points flow into each other (no halt at each);
-- at the end `arrive` decides what next.
local function walkOn(ped: Ped): boolean
	local route = ped.route
	if #route < 2 then
		return false
	end
	ped.order += 1
	local order = ped.order
	ped.walking = true
	Npcs.walkTo(ped.model, Vector3.new(route[1], Map.WalkTop, route[2]), function(ok: boolean)
		if ped.order ~= order or not ped.model.Parent then
			return -- a newer walk, a halt, gone
		end
		ped.walking = false
		if not ok then
			failed(ped)
			return
		end
		ped.fails = 0
		table.remove(route, 1)
		table.remove(route, 1)
		if not walkOn(ped) then
			arrive(ped)
		end
	end, nil, WALK_OPTIONS)
	return true
end

local function setRoute(ped: Ped, route: { number }, speed: number): boolean
	ped.route = route
	pace(ped, speed)
	return walkOn(ped)
end

-- Along its side of the ring to corner k (from where it is, back onto the walk line first if it is off it). False
-- when that side is closed.
local function toCorner(ped: Ped, speed: number): boolean
	local p = ped.root.Position
	local route = TrafficLanes.route(ped.d, ped.i, ped.j, ped.k, ped.dir, p.X, p.Z)
	return route ~= nil and setRoute(ped, route, speed)
end

-- Standing at corner `from`: the next corner round the ring its way, or the other way when that side is closed.
local function chooseNext(ped: Ped, from: number): boolean
	for _ = 1, 2 do
		local k = TrafficLanes.nextCorner(from, ped.dir)
		if TrafficLanes.sideInset(ped.d, ped.i, ped.j, TrafficLanes.sideOf(k, ped.dir)) then
			ped.k = k
			return true
		end
		ped.dir = -ped.dir
	end
	return false
end

-- At corner `from` with a zombie about: of the two sides there, the way whose far corner is farther from it.
local function awayFrom(ped: Ped, from: number, zombie: Vector3): boolean
	local best, bestD = 0, -1
	for n = 1, 2 do
		local dir = if n == 1 then 1 else -1
		local k = TrafficLanes.nextCorner(from, dir)
		if TrafficLanes.sideInset(ped.d, ped.i, ped.j, TrafficLanes.sideOf(k, dir)) then
			local x, z = TrafficLanes.corner(ped.d, ped.i, ped.j, k)
			local d2 = (x - zombie.X) ^ 2 + (z - zombie.Z) ^ 2
			if d2 > bestD then
				best, bestD = dir, d2
			end
		end
	end
	if best == 0 then
		return false
	end
	ped.dir = best
	ped.k = TrafficLanes.nextCorner(from, best)
	return true
end

-- Back onto the ring after something odd (the side it was on is closed): the nearest open side, its own way.
local function rehome(ped: Ped): boolean
	local p = ped.root.Position
	local s = TrafficLanes.nearestSide(ped.d, ped.i, ped.j, p.X, p.Z)
	if not s then
		return false
	end
	ped.k = if ped.dir == 1 then TrafficLanes.nextCorner(s, 1) else s
	return true
end

-- The crosswalk from corner (i, j, k) over to corner (i2, j2, k2), if people may use it.
local function zebraBetween(d: Map.District, i: number, j: number, k: number, i2: number, j2: number, k2: number): Crossings.Crosswalk?
	local ax, az = TrafficLanes.corner(d, i, j, k)
	local bx, bz = TrafficLanes.corner(d, i2, j2, k2)
	local zebra = Crossings.at((ax + bx) / 2, (az + bz) / 2)
	return if zebra and zebraClear[zebra] then zebra else nil
end

-- At corner k: over the street now and then (to the curb, waiting there for the lights), a moment's rest, or on
-- round the block (no halt).
local function atCorner(ped: Ped)
	local k = ped.k
	local roll = rand()
	if roll < Tuning.CrossChance then
		local alongX = rand() < 0.5
		for _ = 1, 2 do
			local k2, i2, j2 = TrafficLanes.across(ped.d, ped.i, ped.j, k, alongX)
			local zebra = if k2 then zebraBetween(ped.d, ped.i, ped.j, k, i2, j2, k2) else nil
			if k2 and zebra then
				ped.crossing = 1
				ped.zebra = zebra
				ped.ci, ped.cj, ped.ck = i2, j2, k2
				local x, z = TrafficLanes.curbSpot(ped.d, ped.i, ped.j, k, alongX)
				if setRoute(ped, { x, z }, ped.speed) then
					return
				end
			end
			alongX = not alongX
		end
		ped.crossing = 0
		ped.zebra = nil
	elseif roll < Tuning.CrossChance + PAUSE_CHANCE then
		standStill(ped)
		ped.restUntil = os.clock() + rng:NextNumber(2, 5)
		chooseNext(ped, k)
		return
	end
	if not (chooseNext(ped, k) and toCorner(ped, ped.speed)) then
		standStill(ped)
		ped.fails += 1
	end
end

-- The end of a route.
arrive = function(ped: Ped)
	local now = os.clock()
	local stop = ped.stop
	if stop then
		-- At a shop window or by somebody to talk to: stand there a while, facing it.
		ped.stop = nil
		standStill(ped)
		ped.restUntil = now + ped.stopFor
		Npcs.face(ped.model, stop)
		return
	end
	if ped.crossing == 1 then
		-- At the curb: wait for the walk phase, facing the other side.
		standStill(ped)
		ped.crossing = 2
		ped.waitSince = now
		local bx, bz = TrafficLanes.corner(ped.d, ped.ci, ped.cj, ped.ck)
		Npcs.face(ped.model, Vector3.new(bx, Map.WalkTop, bz))
		return
	elseif ped.crossing == 3 then
		-- Over: on round the new block from the corner it reached.
		ped.crossing = 0
		ped.zebra = nil
		ped.i, ped.j = ped.ci, ped.cj
		local speed = if ped.fleeing then Tuning.RunSpeed else ped.speed
		if not (chooseNext(ped, ped.ck) and toCorner(ped, speed)) then
			standStill(ped)
		end
		return
	end
	if ped.fleeing then
		-- On round the block, away from the zombie.
		local zombie = zombieNear(ped.root.Position)
		local ok = if zombie then awayFrom(ped, ped.k, zombie) else chooseNext(ped, ped.k)
		if not (ok and toCorner(ped, Tuning.RunSpeed)) then
			standStill(ped)
		end
		return
	end
	atCorner(ped)
end

-- A walk given up (something in the way, no progress): back the other way round the block, or back to the curb it
-- crossed from. thinkPed sends it on after a moment (or lets it go, out of sight, when it keeps failing).
failed = function(ped: Ped)
	ped.fails += 1
	ped.stop = nil
	if ped.crossing ~= 0 then
		ped.crossing = 0
		ped.zebra = nil
	else
		ped.dir = -ped.dir
		ped.k = TrafficLanes.nextCorner(ped.k, ped.dir)
	end
	standStill(ped)
	ped.restUntil = os.clock() + rng:NextNumber(0.6, 1.6)
end

-- A person at (x, z) on the ring of block (i, j), facing (fx, fz), on the way to corner k.
local function makePed(d: Map.District, i: number, j: number, k: number, x: number, z: number, fx: number, fz: number, name: string): Ped?
	local look = Npcs.look("townsperson", name)
	local at = Vector3.new(x, Map.WalkTop, z)
	local facing = Vector3.new(fx - x, 0, fz - z)
	local ok, model = pcall(Npcs.spawn, look, if facing.Magnitude > 0.1 then CFrame.lookAt(at, at + facing) else CFrame.new(at))
	if not ok then
		warn(`[Traffic] no pedestrian: {model}`)
		return nil
	end
	model.Name = "Passer-by"
	model:SetAttribute("Pedestrian", true)
	-- Passers-by carry no name tag (the people you work with do).
	local head = model:FindFirstChild("Head")
	local tag = head and head:FindFirstChild("NameTag")
	if tag then
		tag:Destroy()
	end
	local root = model.PrimaryPart
	if not root then
		Npcs.remove(model)
		return nil
	end
	local ped: Ped = {
		model = model,
		root = root,
		humanoid = model:FindFirstChildOfClass("Humanoid"),
		d = d,
		i = i,
		j = j,
		k = k,
		dir = 1,
		speed = rng:NextNumber(Tuning.WalkSpeed[1], Tuning.WalkSpeed[2]),
		pace = 0,
		order = 0,
		walking = false,
		route = {},
		crossing = 0,
		ci = i,
		cj = j,
		ck = k,
		zebra = nil,
		waitSince = 0,
		restUntil = 0,
		stop = nil,
		stopFor = 0,
		fleeing = false,
		calmAt = 0,
		nextFlee = 0,
		spin = 1,
		group = nil,
		meetAfter = 0,
		fails = 0,
	}
	pace(ped, ped.speed)
	table.insert(peds, ped)
	return ped
end

local function spawnPed(spot: TrafficLanes.Sidewalk): Ped?
	local dir = if rand() < 0.5 then 1 else -1
	local k = if dir == 1 then spot.k else spot.side
	local tx, tz = TrafficLanes.corner(spot.d, spot.i, spot.j, k)
	local ped = makePed(spot.d, spot.i, spot.j, k, spot.x, spot.z, tx, tz, NAMES[rng:NextInteger(1, #NAMES)])
	if ped then
		ped.dir = dir
	end
	return ped
end

-- ── Groups ─────────────────────────────────────────────────────────────────

-- The group goes: everybody on their own (scatter: running from a zombie, thinkPed does the rest), else off toward
-- one end of their side of the block or the other, not all at the same moment.
local function breakUp(group: Group, now: number, scatter: boolean)
	local index = table.find(groups, group)
	if index then
		table.remove(groups, index)
	end
	for n, ped in group.members do
		ped.group = nil
		ped.meetAfter = now + Tuning.MeetCooldown -- they just talked
		if scatter then
			continue
		end
		ped.dir = if rand() < 0.5 then 1 else -1
		ped.k = if ped.dir == 1 then group.kb else group.ka
		ped.restUntil = now + rng:NextNumber(0, 1.2) + (n - 1) * 0.4
		if n == 1 and rand() < 0.5 then
			Npcs.say(ped.model, BYES[rng:NextInteger(1, #BYES)], 2)
		end
	end
	table.clear(group.members)
end

-- May a group stand here: out of the safe zone, off the addresses (somebody brings cargo there), the cargo spots and
-- the employers, and not next to another group?
local function groupSpotClear(x: number, z: number): boolean
	if Map.isSafe(x, z) then
		return false
	end
	local function near(px: number, pz: number, r: number): boolean
		return (px - x) ^ 2 + (pz - z) ^ 2 < r * r
	end
	for _, a in Map.addresses() do
		if near(a.x, a.z, 20) then
			return false
		end
	end
	for _, spot in Map.CargoSpots do
		if near(spot.park.x, spot.park.z, 20) or near(spot.pile.x, spot.pile.z, 20) then
			return false
		end
	end
	for _, spot in Map.EmployerSpots do
		if near(spot.x, spot.z, 20) then
			return false
		end
	end
	for _, other in groups do
		if near(other.x, other.z, 30) then
			return false
		end
	end
	return true
end

-- Two to four people standing together on the sidewalk of an ordinary block, facing each other: in an oval along
-- the side, between the walk line and the buildings (TrafficLanes.GroupDepth: the walkers pass them by), or on a
-- corner inside the turn of the walk lines. False when the spot will not do.
local function spawnGroup(spot: TrafficLanes.Sidewalk, size: number, now: number): boolean
	local d, i, j, s = spot.d, spot.i, spot.j, spot.side
	if Map.special(d.id, i, j) or TrafficLanes.sideInset(d, i, j, s) ~= TrafficLanes.SidewalkInset then
		return false -- the shops, the depot, the places: their own people and props; a side on a detour: no room
	end
	local ka, kb = s, TrafficLanes.nextCorner(s, 1)
	local nx, nz, tx, tz = TrafficLanes.inward(s)
	local along, across = TrafficLanes.GroupRadius.along, TrafficLanes.GroupRadius.across
	local x, z = spot.x, spot.z
	local placed = false
	refreshFilter()
	if rand() < 0.3 then
		-- On the corner, a round group (the walkers and the people waiting to cross keep the corner itself).
		x, z = TrafficLanes.cornerSpot(d, i, j, kb, TrafficLanes.CornerGroupDepth)
		along, across = 1.6, 1.6
		placed = clearRect(x, z, tx, tz, along + 1, across + 1)
	else
		local _, _, _, _, _, f = TrafficLanes.nearestSide(d, i, j, x, z)
		if f < 0.15 or f > 0.85 then
			return false
		end
		x, z = TrafficLanes.sideSpot(d, i, j, s, f, TrafficLanes.GroupDepth)
		placed = clearRect(x, z, tx, tz, along + 1, across + 1)
	end
	if not placed or not groupSpotClear(x, z) then
		return false
	end
	local group: Group = {
		members = {},
		x = x,
		z = z,
		endsAt = now + rng:NextNumber(Tuning.GroupTime[1], Tuning.GroupTime[2]),
		talkAt = now + rng:NextNumber(1, 3),
		ka = ka,
		kb = kb,
	}
	-- Round the middle, the first two along the street (a pair faces each other along the sidewalk, not one behind
	-- the other toward the wall).
	local first = rng:NextInteger(1, #NAMES)
	for n = 1, size do
		local angle = (n - 1) * math.pi * 2 / size + rng:NextNumber(-0.25, 0.25)
		local ca, sa = math.cos(angle), math.sin(angle)
		local px, pz = x + tx * ca * along + nx * sa * across, z + tz * ca * along + nz * sa * across
		local name = NAMES[(first + n * 5) % #NAMES + 1]
		local ped = makePed(d, i, j, kb, px, pz, x + rng:NextNumber(-0.4, 0.4), z + rng:NextNumber(-0.4, 0.4), name)
		if ped then
			ped.group = group
			table.insert(group.members, ped)
		end
	end
	if #group.members < 2 then
		breakUp(group, now, false)
		return #group.members > 0
	end
	table.insert(groups, group)
	return true
end

-- A group talking: the others turn to whoever speaks, who nods, shifts or says a line; the group breaks up after a
-- while (or when it is down to one).
local function thinkGroup(group: Group, now: number)
	for n = #group.members, 1, -1 do
		local m = group.members[n]
		if m.group ~= group or not m.model.Parent then
			table.remove(group.members, n)
		end
	end
	if #group.members < 2 or now >= group.endsAt then
		breakUp(group, now, false)
		return
	end
	if now < group.talkAt then
		return
	end
	group.talkAt = now + rng:NextNumber(Tuning.TalkEvery[1], Tuning.TalkEvery[2])
	local speaker = group.members[rng:NextInteger(1, #group.members)]
	local at = speaker.root.Position
	for _, m in group.members do
		if m ~= speaker and rand() < 0.6 then
			Npcs.face(m.model, at)
		end
	end
	if rand() < 0.4 then
		local other = group.members[rng:NextInteger(1, #group.members)]
		if other ~= speaker then
			Npcs.face(speaker.model, other.root.Position)
		end
	end
	if rand() < Tuning.SayChance then
		Npcs.say(speaker.model, CHAT[rng:NextInteger(1, #CHAT)], 3.5)
	else
		Npcs.gesture(speaker.model)
	end
end

-- ── Stopping and crossing ──────────────────────────────────────────────────

-- A walker along an ordinary stretch of its side stops at a shop window: a wall within WINDOW_LOOK of the walk line,
-- straight in. It steps off the line to stand WINDOW_GAP in front of it, facing it, for a few seconds.
local function windowStop(ped: Ped, position: Vector3)
	local d, i, j = ped.d, ped.i, ped.j
	local s, px, pz, _, _, f = TrafficLanes.nearestSide(d, i, j, position.X, position.Z)
	if not s or f < 0.15 or f > 0.85 or TrafficLanes.sideInset(d, i, j, s) ~= TrafficLanes.SidewalkInset then
		return
	end
	if (px - position.X) ^ 2 + (pz - position.Z) ^ 2 > 4 then
		return -- not on its line (stepping back onto it)
	end
	local nx, nz = TrafficLanes.inward(s)
	refreshFilter()
	local hit = workspace:Raycast(Vector3.new(px, Map.WalkTop + 3, pz), Vector3.new(nx, 0, nz) * WINDOW_LOOK, rayParams)
	if not hit then
		return -- nothing to look at (a park, a car park)
	end
	local room = hit.Distance - WINDOW_GAP
	if room < 1.5 then
		return
	end
	local x, z = px + nx * room, pz + nz * room
	if not clearLine(px, pz, x, z) then
		return
	end
	ped.stop = Vector3.new(x + nx * 4, Map.WalkTop, z + nz * 4)
	ped.stopFor = rng:NextNumber(Tuning.WindowTime[1], Tuning.WindowTime[2])
	setRoute(ped, { x, z }, ped.speed)
end

local function canMeet(ped: Ped, now: number): boolean
	return ped.walking and ped.crossing == 0 and not ped.fleeing and ped.group == nil and ped.stop == nil and ped.humanoid ~= nil and now >= ped.meetAfter
end

-- Two walkers stop for a word: both step off the walk line toward the buildings (MeetDepth), side by side along the
-- sidewalk, and face each other; where there is no room for that, they stop right there.
local function meet(p: Ped, q: Ped, now: number, seconds: number)
	local pp, qp = p.root.Position, q.root.Position
	local mx, mz = (pp.X + qp.X) / 2, (pp.Z + qp.Z) / 2
	local s, _, _, tx, tz, f = TrafficLanes.nearestSide(p.d, p.i, p.j, mx, mz)
	if s and p.d == q.d and p.i == q.i and p.j == q.j and f > 0.06 and f < 0.94 and TrafficLanes.sideInset(p.d, p.i, p.j, s) == TrafficLanes.SidewalkInset then
		local sx, sz = TrafficLanes.sideSpot(p.d, p.i, p.j, s, f, TrafficLanes.MeetDepth)
		local sign = if (pp.X - mx) * tx + (pp.Z - mz) * tz >= 0 then 1.3 else -1.3
		local ax, az = sx + tx * sign, sz + tz * sign
		local bx, bz = sx - tx * sign, sz - tz * sign
		refreshFilter()
		if clearLine(ax, az, bx, bz) then
			p.stop, p.stopFor = Vector3.new(bx, Map.WalkTop, bz), seconds
			q.stop, q.stopFor = Vector3.new(ax, Map.WalkTop, az), seconds
			setRoute(p, { ax, az }, p.speed)
			setRoute(q, { bx, bz }, q.speed)
			return
		end
	end
	halt(p, now, seconds)
	halt(q, now, seconds)
	Npcs.face(p.model, qp)
	Npcs.face(q.model, pp)
end

-- Two walkers passing each other: now and then they stop for a word.
local function meetings(now: number)
	for a = 1, #peds do
		local p = peds[a]
		if not canMeet(p, now) then
			continue
		end
		local pp = p.root.Position
		for b = a + 1, #peds do
			local q = peds[b]
			if not canMeet(q, now) then
				continue
			end
			local qp = q.root.Position
			if (pp.X - qp.X) ^ 2 + (pp.Z - qp.Z) ^ 2 > 16 then
				continue
			end
			p.meetAfter = now + Tuning.MeetCooldown
			q.meetAfter = now + Tuning.MeetCooldown
			if rand() < Tuning.MeetChance then
				meet(p, q, now, rng:NextNumber(Tuning.MeetTime[1], Tuning.MeetTime[2]))
				Npcs.say(p.model, GREETINGS[rng:NextInteger(1, #GREETINGS)], 2.5)
				task.delay(1.6, function()
					if q.model.Parent and not q.fleeing then
						Npcs.say(q.model, REPLIES[rng:NextInteger(1, #REPLIES)], 2.5)
					end
				end)
			end
			break
		end
	end
end

-- May somebody waiting at this crosswalk step out now? With lights: the walk phase; without: no traffic car close
-- and coming toward it (or standing on it).
local function mayCross(zebra: Crossings.Crosswalk, clock: number): boolean
	if zebra.light > 0 then
		return Crossings.walk(clock, junctions[zebra.light].offset, zebra.alongX)
	end
	local gap = Tuning.CrossGap
	for _, car in cars do
		if car.wrecked then
			continue
		end
		local dx, dz = zebra.x - car.x, zebra.z - car.z
		local d2 = dx * dx + dz * dz
		if d2 < gap * gap and dx * car.hx + dz * car.hz > -car.half - 3 and (car.speed > 1 or d2 < (car.half + 10) ^ 2) then
			return false
		end
	end
	return true
end

-- Running from a zombie: along the ring, away from it (each its own way when it is right beside them), on round
-- the corners; out on the street, over to the other side first. Never off the walk lines.
local function flee(ped: Ped, position: Vector3, zombie: Vector3, now: number)
	ped.calmAt = now + CALM_AFTER
	if not ped.fleeing then
		ped.fleeing = true
		ped.stop = nil
		ped.nextFlee = 0
		ped.waitSince = 0
		ped.spin = if rand() < 0.5 then 1 else -1
		local group = ped.group
		if group then
			breakUp(group, now, true)
		end
		if ped.crossing == 3 and ped.walking then
			pace(ped, Tuning.RunSpeed)
		else
			ped.crossing = 0
			ped.zebra = nil
		end
		if rand() < 0.5 then
			Npcs.say(ped.model, SCREAMS[rng:NextInteger(1, #SCREAMS)], 2)
		end
	end
	if ped.crossing ~= 0 or now < ped.nextFlee then
		return
	end
	ped.nextFlee = now + 1
	local s, px, pz, tx, tz, f = TrafficLanes.nearestSide(ped.d, ped.i, ped.j, position.X, position.Z)
	if not s then
		return
	end
	local dir, k = ped.dir, ped.k
	if f < 0.06 or f > 0.94 then
		-- At a corner: on along the side that leads away.
		local saveDir, saveK = ped.dir, ped.k
		if not awayFrom(ped, if f < 0.06 then s else TrafficLanes.nextCorner(s, 1), zombie) then
			return
		end
		dir, k = ped.dir, ped.k
		ped.dir, ped.k = saveDir, saveK
	else
		local away = (px - zombie.X) * tx + (pz - zombie.Z) * tz
		dir = if away > 2 then 1 elseif away < -2 then -1 else ped.spin
		k = if dir == 1 then TrafficLanes.nextCorner(s, 1) else s
	end
	if ped.walking and ped.dir == dir and ped.k == k and ped.pace >= Tuning.RunSpeed then
		return -- already running that way
	end
	ped.dir, ped.k = dir, k
	toCorner(ped, Tuning.RunSpeed)
end

local function thinkPed(ped: Ped, now: number, clock: number)
	local position = ped.root.Position
	local zombie = zombieNear(position)
	if zombie then
		flee(ped, position, zombie, now)
		return
	end
	if ped.fleeing then
		if now < ped.calmAt then
			return
		end
		-- Calm again: catching their breath, then on at a stroll.
		ped.fleeing = false
		if ped.crossing == 0 then
			standStill(ped)
			ped.restUntil = now + rng:NextNumber(1, 2.5)
		end
		pace(ped, ped.speed)
		return
	end
	if ped.group then
		return -- thinkGroup
	end
	if ped.walking then
		if ped.crossing == 0 and ped.stop == nil and ped.humanoid and rand() < Tuning.WindowChance then
			windowStop(ped, position)
		end
		return
	end
	if now < ped.restUntil then
		return
	end
	if ped.fails >= Tuning.StuckLimit and hidden(lastViewers, position.X, position.Z, PED_SPAWN_MIN * 0.6) then
		removePed(ped) -- stuck somewhere: gone while nobody looks (a new one comes elsewhere)
		return
	end
	if ped.crossing == 2 then
		local zebra = ped.zebra
		if zebra and not mayCross(zebra, clock) then
			if now - ped.waitSince > Tuning.CrossWait then
				-- Waited long enough: on round the block instead.
				ped.crossing = 0
				ped.zebra = nil
				ped.waitSince = 0
				if not (chooseNext(ped, ped.k) and toCorner(ped, ped.speed)) then
					ped.fails += 1
				end
			end
			return
		end
		ped.crossing = 3
		ped.waitSince = 0
		local x, z = TrafficLanes.corner(ped.d, ped.ci, ped.cj, ped.ck)
		setRoute(ped, { x, z }, ped.speed)
		return
	end
	-- (Interrupted on the way to the curb or over: back onto its own block's ring.)
	ped.crossing = 0
	ped.zebra = nil
	if not toCorner(ped, ped.speed) and not (rehome(ped) and toCorner(ped, ped.speed)) then
		ped.fails += 1
		ped.restUntil = now + 2
	end
end

-- ── Keeping the numbers ────────────────────────────────────────────────────

local function manageCars(g: TrafficLanes.Graph, list: { Viewer }, now: number)
	for _, car in table.clone(cars) do
		local d = nearest(list, car.x, car.z)
		if d > Tuning.Despawn then
			removeCar(car)
		elseif car.wrecked then
			local age = now - car.wreckedAt
			if age > WRECK_MAX or (age > WRECK_TIME and d > 120) then
				removeCar(car)
			end
		end
	end
	local spawned = 0
	for _, v in list do
		if spawned >= CAR_SPAWNS_PER_TICK or #cars >= Tuning.MaxCars then
			break
		end
		local around = 0
		for _, car in cars do
			if (car.x - v.x) ^ 2 + (car.z - v.z) ^ 2 < Tuning.Despawn ^ 2 then
				around += 1
			end
		end
		if around >= Tuning.CarsPerPlayer then
			continue
		end
		for _ = 1, 3 do
			local edge, s, x, z = TrafficLanes.spawnSpot(g, v.x, v.z, Tuning.SpawnMin, Tuning.SpawnMax, rand)
			if not edge or not hidden(list, x, z, Tuning.SpawnMin) then
				continue
			end
			local crowded = false
			for _, car in cars do
				if (car.x - x) ^ 2 + (car.z - z) ^ 2 < SPACING * SPACING then
					crowded = true
					break
				end
			end
			if not crowded then
				-- Nor on a parked car, a bandit car, a wreck or somebody on foot (gathered this step).
				for n = 1, obstacleCount do
					if obstacleCar[n] == false then
						local r = obstacleR[n] + 12
						if (obstacleX[n] - x) ^ 2 + (obstacleZ[n] - z) ^ 2 < r * r then
							crowded = true
							break
						end
					end
				end
			end
			if not crowded and spawnCar(g, edge, s) then
				spawned += 1
				break
			end
		end
	end
end

local function managePeds(list: { Viewer }, now: number, clock: number)
	lastViewers = list
	if not surveyed then
		return -- the walk lines first (Traffic.start)
	end
	for _, ped in table.clone(peds) do
		if not ped.model.Parent then
			removePed(ped)
			continue
		end
		local p = ped.root.Position
		if nearest(list, p.X, p.Z) > PED_DESPAWN then
			removePed(ped)
		end
	end
	local share = 1 - (1 - Tuning.NightPeople) * DayNight.nightFactor()
	local perPlayer = math.max(1, math.floor(Tuning.PedestriansPerPlayer * share + 0.5))
	local cap = math.floor(Tuning.MaxPedestrians * share + 0.5)
	local spawned = 0
	for _, v in list do
		if spawned >= PED_SPAWNS_PER_TICK or #peds >= cap then
			break
		end
		local around = 0
		for _, ped in peds do
			local p = ped.root.Position
			if (p.X - v.x) ^ 2 + (p.Z - v.z) ^ 2 < PED_DESPAWN ^ 2 then
				around += 1
			end
		end
		if around >= perPlayer then
			continue
		end
		local spot = TrafficLanes.sidewalkSpot(v.x, v.z, PED_SPAWN_MIN, PED_SPAWN_MAX, rand)
		if not spot or not hidden(list, spot.x, spot.z, PED_SPAWN_MIN) then
			continue
		end
		-- Room for two or more under both caps: now and then a group (standing: cheaper than walkers).
		local room = math.min(perPlayer - around, cap - #peds)
		if room >= 2 and rand() < Tuning.GroupChance then
			local size = math.min(room, rng:NextInteger(Tuning.GroupSize[1], Tuning.GroupSize[2]))
			if spawnGroup(spot, size, now) then
				spawned += 1
				continue
			end
		end
		if spawnPed(spot) then
			spawned += 1
		end
	end
	for _, group in table.clone(groups) do
		thinkGroup(group, now)
	end
	for _, ped in table.clone(peds) do
		thinkPed(ped, now, clock)
	end
	meetings(now)
end

-- ── Bandits among the traffic ──────────────────────────────────────────────

-- The job's stars, when Jobs tells them (Jobs.crewStatus, stream "jobs"); nil when it does not.
local function jobStars(player: Player): number?
	local status = (Jobs :: any).crewStatus
	if type(status) ~= "function" then
		return nil
	end
	local ok, info = pcall(status, player)
	if ok and type(info) == "table" and type(info.stars) == "number" then
		return info.stars
	end
	return nil
end

local function banditCheck(list: { Viewer }, now: number)
	for _, v in list do
		local player = v.player
		if not Jobs.active(player) then
			jobSince[player] = nil
			continue
		end
		local since = jobSince[player]
		if not since then
			jobSince[player] = now
			banditAt[player] = now + BANDIT_FIRST + rng:NextNumber(0, 20)
			continue
		end
		if now < (banditAt[player] or 0) or not Vehicles.isDriving(player) or Map.isSafe(v.x, v.z) then
			continue
		end
		local stars = jobStars(player)
		if (stars and stars < 2) or BanditCars.countFor(player) > 0 then
			banditAt[player] = now + 10
			continue
		end
		-- A traffic car behind them or to the side, out of the safe zone.
		local pick: Car? = nil
		for _, car in cars do
			if car.wrecked or Map.isSafe(car.x, car.z) or Map.onIce(car.x, car.z) then
				continue
			end
			local dx, dz = car.x - v.x, car.z - v.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d >= BANDIT_RANGE[1] and d <= BANDIT_RANGE[2] and (dx * v.hx + dz * v.hz) / d < 0.2 then
				pick = car
				break
			end
		end
		if not pick then
			banditAt[player] = now + 5
			continue
		end
		local x, z, hx, hz = pick.x, pick.z, pick.hx, pick.hz
		removeCar(pick)
		-- The pickup appears right where the car was, in its lane, driving on the same way.
		banditAt[player] = now + rng:NextNumber(BANDIT_GAP[1], BANDIT_GAP[2])
		if BanditCars.chaseAt(player, carFrame(x, z, hx, hz)) then
			Net.get("Notice"):FireClient(player, "That car was no civilian: BANDITS on your tail!")
		end
	end
end

-- ── The loop ───────────────────────────────────────────────────────────────

local manageIn = 0
local banditIn = BANDIT_EVERY

local function step(dt: number)
	local g = graph
	if not g then
		return
	end
	local now = os.clock()
	local clock = workspace:GetServerTimeNow() -- the traffic lights' time (the clients draw the same)
	gatherObstacles()
	for _, car in table.clone(cars) do
		if not car.wrecked and car.model.Parent then
			moveCar(car, g, dt, clock)
		end
	end
	checkCrashes()
	manageIn -= dt
	if manageIn <= 0 then
		manageIn = MANAGE_EVERY
		local list = viewers()
		manageCars(g, list, now)
		managePeds(list, now, clock)
		banditIn -= MANAGE_EVERY
		if banditIn <= 0 then
			banditIn = BANDIT_EVERY
			banditCheck(list, now)
		end
	end
end

local function refreshLights()
	local on = isNight()
	for _, car in cars do
		if not car.wrecked then
			setLights(car, on)
		end
	end
end

-- How many cars and pedestrians are out (the admin panel, tests).
function Traffic.counts(): (number, number)
	return #cars, #peds
end

-- 4.5, the admin tools (server/Admin.luau): one more traffic car on a lane 25 … 120 studs from `at`, not on top of
-- another one. True when it came.
function Traffic.adminSpawn(at: Vector3): boolean
	local g = graph
	if not g then
		return false
	end
	for _ = 1, 6 do
		local edge, s, x, z = TrafficLanes.spawnSpot(g, at.X, at.Z, 25, 120, rand)
		if not edge then
			return false
		end
		local crowded = false
		for _, car in cars do
			if (car.x - x) ^ 2 + (car.z - z) ^ 2 < (SPACING / 2) ^ 2 then
				crowded = true
				break
			end
		end
		if not crowded then
			return spawnCar(g, edge, s) ~= nil
		end
	end
	return false
end

-- Everything off the streets (they come back around the players).
function Traffic.clear()
	for _, car in table.clone(cars) do
		removeCar(car)
	end
	for _, ped in table.clone(peds) do
		removePed(ped)
	end
	table.clear(groups)
end

function Traffic.start()
	if started then
		return
	end
	started = true
	local f = Instance.new("Folder")
	f.Name = "Traffic"
	f:SetAttribute("Tick", TICK)
	f.Parent = workspace
	folder = f
	local g = TrafficLanes.graph()
	graph = g
	nodeLight = Crossings.nodeLights(g)
	pcall(function()
		overlap.CollisionGroup = "Npc" -- what the people collide with (server/Npcs.luau)
		rayParams.CollisionGroup = "Npc"
	end)
	task.spawn(function()
		local ok, err = pcall(function()
			surveyAll()
		end)
		if not ok then
			warn(`[Traffic] sidewalk survey failed, straight lines everywhere: {err}`)
			surveyed = true
		end
	end)
	workspace:GetAttributeChangedSignal("Night"):Connect(refreshLights)
	Players.PlayerRemoving:Connect(function(player)
		banditAt[player] = nil
		jobSince[player] = nil
	end)
	task.spawn(function()
		while true do
			local dt = math.min(task.wait(TICK), 0.3)
			local ok, err = pcall(function()
				step(dt)
			end)
			if not ok then
				warn(`[Traffic] {err}`)
			end
		end
	end)
	-- Without the Night attribute (no day/night yet) the lights follow the clock now and then.
	task.spawn(function()
		while true do
			task.wait(10)
			if workspace:GetAttribute("Night") == nil then
				refreshLights()
			end
		end
	end)
end

return Traffic
