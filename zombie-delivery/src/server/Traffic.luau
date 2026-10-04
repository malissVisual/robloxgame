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
--
-- Pedestrians. R15 people (server/Npcs.luau: Npcs.spawn, Npcs.walkTo) on the sidewalk ring of the blocks, corner to
-- corner, now and then across the street. Fewer at night. A zombie within FleeRange and they run (faster, away from
-- it, staying on their block) until it is gone.
--
-- Bandits among them. During a player's job (driving, out of the safe zone, ★★ and up when Jobs.crewStatus tells
-- the stars) a traffic car behind them can turn out to be a bandit pickup now and then: it vanishes and
-- BanditCars.chase spawns the pickup on that spot, heading the same way. Never more than one chasing at a time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
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
local PED_WALK = 8
local PED_RUN = 16
local FLEE_RANGE = 40
local CALM_AFTER = 4 -- seconds without a zombie in range
local CROSS_CHANCE = 0.22
local PAUSE_CHANCE = 0.12
local NIGHT_PEOPLE = 0.4 -- this share of the pedestrians are out at night
local BANDIT_FIRST = 25 -- seconds into a job before a traffic car can be bandits
local BANDIT_GAP = { 70, 120 } -- seconds between them (one player)
local BANDIT_RANGE = { 70, 220 }
local WALK_ANIM = "rbxassetid://507777826" -- server/Npcs.luau's walk (sped up while they run)

-- The bodies: the dealer's cars mostly, now and then a work truck (Config.Cars ids, weight).
local BODIES: { { id: string, weight: number } } = {
	{ id = "van", weight = 4 },
	{ id = "pickup", weight = 4 },
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
	"Mona", "Ned", "Olga", "Pete", "Rita", "Sam", "Tess", "Vic", "Wendy", "Yuri", "Zoe", "Max",
}
local SCREAMS = { "ZOMBIES!", "Run!", "Help!", "Get away from me!", "Not again..." }

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
	k: number, -- the corner it walks to
	dir: number, -- around the ring: +1 or -1
	order: number, -- the walkTo it is on (stale callbacks are ignored)
	walking: boolean,
	crossing: boolean, -- over the street to (ci, cj)
	ci: number,
	cj: number,
	restUntil: number,
	fleeing: boolean,
	calmAt: number,
	nextFlee: number,
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
		if def.id == id then
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

-- A civilian car out of Vehicles.buildNpc: the roof gun, the movers, the wheel colliders, the cargo marks and the
-- bandit passengers go; the driver gets ordinary clothes.
local function civilian(npc: Vehicles.NpcCar): { SpotLight }
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
	local ok, npc = pcall(Vehicles.buildNpc, def, ground)
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
		if d:IsA("BasePart") and d.Transparency < 1 then
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
		addObstacle(car.x, car.z, car.half, car)
	end
	for _, playerCar in Vehicles.all() do
		local p = playerCar.chassis.Position
		addObstacle(p.X, p.Z, playerCar.size.Z / 2, false)
	end
	local bandits = workspace:FindFirstChild("BanditCars")
	if bandits then
		for _, model in bandits:GetChildren() do
			local chassis = if model:IsA("Model") then model.PrimaryPart else nil
			if chassis then
				addObstacle(chassis.Position.X, chassis.Position.Z, 6.5, false)
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

-- The speed the car may drive with what is ahead in its lane (and whether a traffic car is what stops it).
local function clearance(car: Car, limit: number): (number, boolean)
	local look = 8 + car.half + car.speed * 1.1
	local byTraffic = false
	local now = os.clock()
	if now < car.ghostUntil then
		return limit, false
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
			byTraffic = other ~= false
		end
	end
	return limit, byTraffic
end

local function moveCar(car: Car, g: TrafficLanes.Graph, dt: number)
	local target = car.cruise * car.piece.speed
	-- Slow down before a turn.
	if not car.piece.turn and car.nextEdge then
		local turn = TrafficLanes.turn(g, car.piece.edge, car.nextEdge :: number)
		local remaining = car.piece.length - car.s
		if turn.speed < 1 and remaining < 30 then
			target = math.min(target, car.cruise * turn.speed + remaining * 0.7)
		end
	end
	local limit, byTraffic = clearance(car, target)
	if limit < 1 then
		car.waited += dt
		if byTraffic and car.waited > GIVE_WAY then
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
			if inBox(box, size, p, reach) or inBox(box, size, p + along, reach) or inBox(box, size, p - along, reach) then
				local relative = Vector3.new(car.x - p.X, 0, car.z - p.Z)
				wreck(car, if relative.Magnitude > 0.1 then relative.Unit * fast else Vector3.zero)
			end
		end
	end
	lastSpeed = speeds
end

-- ── Pedestrians ────────────────────────────────────────────────────────────

local function removePed(ped: Ped)
	local index = table.find(peds, ped)
	if index then
		table.remove(peds, index)
	end
	Npcs.remove(ped.model)
end

local function setPace(ped: Ped, speed: number)
	local humanoid = ped.humanoid
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = speed
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			if track.Animation and track.Animation.AnimationId == WALK_ANIM then
				track:AdjustSpeed(speed / 11)
			end
		end
	end
end

local function walk(ped: Ped, x: number, z: number, speed: number)
	ped.order += 1
	local order = ped.order
	ped.walking = true
	Npcs.walkTo(ped.model, Vector3.new(x, Map.WalkTop, z), function(arrived: boolean)
		if ped.order ~= order then
			return
		end
		ped.walking = false
		if ped.fleeing then
			return -- thinkPed sends them on
		end
		if not arrived then
			-- Something in the way: back the other way round the block (or back off the street).
			ped.dir = -ped.dir
			if ped.crossing then
				ped.crossing = false
			end
			ped.k = TrafficLanes.nextCorner(ped.k, ped.dir)
		elseif ped.crossing then
			ped.crossing = false
			ped.i, ped.j = ped.ci, ped.cj
			ped.k = TrafficLanes.nextCorner(ped.k, ped.dir)
		else
			-- At a corner: on round the block, across the street, or a moment's rest.
			local roll = rand()
			if roll < CROSS_CHANCE then
				local k2, i2, j2 = TrafficLanes.across(ped.d, ped.i, ped.j, ped.k, rand() < 0.5)
				if k2 then
					ped.crossing = true
					ped.ci, ped.cj = i2, j2
					ped.k = k2
					return
				end
			elseif roll < CROSS_CHANCE + PAUSE_CHANCE then
				ped.restUntil = os.clock() + rng:NextNumber(2, 5)
			end
			ped.k = TrafficLanes.nextCorner(ped.k, ped.dir)
		end
	end)
	setPace(ped, speed)
end

local function spawnPed(spot: TrafficLanes.Sidewalk): Ped?
	local name = NAMES[rng:NextInteger(1, #NAMES)]
	local look = Npcs.look("townsperson", name)
	local tx, tz = TrafficLanes.corner(spot.d, spot.i, spot.j, spot.k)
	local at = Vector3.new(spot.x, Map.WalkTop, spot.z)
	local facing = Vector3.new(tx - spot.x, 0, tz - spot.z)
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
		d = spot.d,
		i = spot.i,
		j = spot.j,
		k = spot.k,
		dir = 1,
		order = 0,
		walking = false,
		crossing = false,
		ci = spot.i,
		cj = spot.j,
		restUntil = 0,
		fleeing = false,
		calmAt = 0,
		nextFlee = 0,
	}
	table.insert(peds, ped)
	return ped
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

local function thinkPed(ped: Ped, now: number)
	local position = ped.root.Position
	local zombie = zombieNear(position)
	if zombie then
		ped.calmAt = now + CALM_AFTER
		if not ped.fleeing then
			ped.fleeing = true
			ped.crossing = false
			if rand() < 0.5 then
				Npcs.say(ped.model, SCREAMS[rng:NextInteger(1, #SCREAMS)], 2)
			end
		end
		if now >= ped.nextFlee then
			ped.nextFlee = now + 1.2
			local away = Vector3.new(position.X - zombie.X, 0, position.Z - zombie.Z)
			away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
			local x, z = TrafficLanes.clampToBlock(ped.d, ped.i, ped.j, position.X + away.X * 30, position.Z + away.Z * 30)
			if Vector3.new(x - position.X, 0, z - position.Z).Magnitude < 6 then
				-- Cornered against the street: the corner farthest from the zombie.
				local bestK, bestD = ped.k, -1
				for k = 1, 4 do
					local cx, cz = TrafficLanes.corner(ped.d, ped.i, ped.j, k)
					local d = (cx - zombie.X) ^ 2 + (cz - zombie.Z) ^ 2
					if d > bestD then
						bestK, bestD = k, d
					end
				end
				x, z = TrafficLanes.corner(ped.d, ped.i, ped.j, bestK)
				ped.k = bestK
			end
			walk(ped, x, z, PED_RUN)
		end
		return
	end
	if ped.fleeing then
		if now < ped.calmAt then
			return
		end
		ped.fleeing = false
		ped.walking = false
		ped.order += 1 -- forget the run
		setPace(ped, PED_WALK)
	end
	if ped.walking or now < ped.restUntil then
		return
	end
	if ped.crossing then
		local x, z = TrafficLanes.corner(ped.d, ped.ci, ped.cj, ped.k)
		walk(ped, x, z, PED_WALK)
	else
		local x, z = TrafficLanes.corner(ped.d, ped.i, ped.j, ped.k)
		walk(ped, x, z, PED_WALK)
	end
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
			if not crowded and spawnCar(g, edge, s) then
				spawned += 1
				break
			end
		end
	end
end

local function managePeds(list: { Viewer }, now: number)
	for _, ped in table.clone(peds) do
		if not ped.model.Parent then
			local index = table.find(peds, ped)
			if index then
				table.remove(peds, index)
			end
			continue
		end
		local p = ped.root.Position
		if nearest(list, p.X, p.Z) > PED_DESPAWN then
			removePed(ped)
		end
	end
	local share = 1 - (1 - NIGHT_PEOPLE) * DayNight.nightFactor()
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
		if spot and hidden(list, spot.x, spot.z, PED_SPAWN_MIN) and spawnPed(spot) then
			spawned += 1
		end
	end
	for _, ped in peds do
		thinkPed(ped, now)
	end
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
		-- BanditCars.chase puts the pickup SpawnBehind studs behind `position` (heading the way it faces): ask for
		-- the spot ahead of the traffic car, so it appears where the car was, driving on the same way.
		local heading = Vector3.new(hx, 0, hz)
		local position = Vector3.new(x, Map.RoadTop, z) + heading * Config.BanditCar.SpawnBehind
		banditAt[player] = now + rng:NextNumber(BANDIT_GAP[1], BANDIT_GAP[2])
		if BanditCars.chase(player, position, heading * 30) then
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
	gatherObstacles()
	for _, car in table.clone(cars) do
		if not car.wrecked and car.model.Parent then
			moveCar(car, g, dt)
		end
	end
	checkCrashes()
	manageIn -= dt
	if manageIn <= 0 then
		manageIn = MANAGE_EVERY
		local list = viewers()
		manageCars(g, list, now)
		managePeds(list, now)
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

-- Everything off the streets (they come back around the players).
function Traffic.clear()
	for _, car in table.clone(cars) do
		removeCar(car)
	end
	for _, ped in table.clone(peds) do
		removePed(ped)
	end
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
	graph = TrafficLanes.graph()
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
