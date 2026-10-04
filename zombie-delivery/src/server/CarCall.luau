--!strict
-- Calling your car (Config.CarCall). The CAR button does not make the car appear out of thin air: a chauffeur
-- brings it.
--
--   1. The car appears out of your sight on a road SpawnMin .. SpawnMax studs from you, facing the way to you, or at
--      the drive-out spot of a garage you own (a home's or a standalone one) when one is within 400 studs: it
--      rolls out of your garage.
--   2. The chauffeur (an R15 person from server/Npcs.luau in a black suit and cap, seated in the driver's seat,
--      seen through the windows) drives it along the roads (shared/Roads.luau's route, on the right-hand lane, a
--      look-ahead point steered like server/BanditCars.luau) at Config.CarCall.Speed: slower in the turns, braking
--      for the traffic, the other cars and people in the lane (overtaking on the left when they stay), backing up
--      when stuck, re-routing when you walk away.
--   3. It parks beside you (on your road's lane; a little before you when you stand in it), the chauffeur gets out
--      of the driver's door, says a line, walks ~15 studs away and fades out over Config.CarCall.DriverFade s.
--      The car is then yours as always (Vehicles.handOver: the prompts come back, your client owns it again).
--   4. Not there within Config.CarCall.ArriveWithin s (stuck, blocked, you ran off): the chauffeur vanishes and the
--      car is placed next to you, seated, the old instant way (Vehicles.placeNear).
--
-- Network ownership: while the chauffeur drives, the SERVER owns the car (SetNetworkOwner(nil)) and sets its movers
-- (the LinearVelocity "Drive" and AngularVelocity "Steer") every Heartbeat; its Drive / Ride prompts are parked, so
-- nobody gets in. Your client's Drive.luau keeps writing the movers locally, which changes nothing it does not own.
-- At the hand-over the chauffeur's body is unwelded first, then the car goes to its owner.
--
-- The client hears about it through the CarCall remote: (seconds left, car model) about once a second while it is
-- on the way, (nil) when it arrived, was placed or the call ended (client/Hud.luau shows "Your car is on the way ·
-- 9 s" and a marker over the car).
--
-- The instant cases stay instant (server/Vehicles.luau, force): PLAY, a respawn, a car bought or equipped, a job's
-- vehicle. When you spawn at home (Estate.homeOf, just spawned / pressed PLAY, or standing at home) that car stands
-- at your home's garage drive-out spot (World.EstateGarages[home]) instead of next to you: the hook
-- Vehicles.homeGarage below. Company vehicles called with the CAR button during a job are delivered too.
-- Sitting in your own car, CAR still resets it right there (Vehicles.spawn).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Roads = require(Shared.Roads)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local Npcs = require(script.Parent.Npcs)
local Estate = require(script.Parent.Estate)

local Tuning = Config.CarCall

local CarCall = {}

type Point = Roads.Point

type Saved = { massless: boolean, collide: boolean }

type Delivery = {
	player: Player,
	car: Vehicles.Car,
	carId: string?, -- a company vehicle (nil: the equipped car)
	name: string, -- the car's name, for the lines
	npc: Model?,
	seatWeld: Weld?,
	sitTrack: AnimationTrack?,
	saved: { [BasePart]: Saved }, -- the chauffeur's parts while seated (massless, not colliding)
	route: { Point },
	step: number, -- how far along the route (its step k: points k .. k + 1)
	stopShort: number, -- stop this far before the end (you stand in the lane)
	side: number, -- park on this side of the road at the end (+1 right of the way it comes, -1 left: your side)
	goalX: number, -- where you were when the route was planned
	goalZ: number,
	left: number, -- studs still to go (to the stop)
	started: number,
	deadline: number,
	speed: number, -- signed, along the nose
	target: Vector3, -- the steering point
	limit: number, -- the speed the turns and what is ahead allow
	stuck: number,
	reverseUntil: number,
	blocked: number, -- seconds stopped behind something
	overtakeUntil: number,
	nextThink: number,
	nextRoute: number,
	sent: number, -- the seconds last told to the client
	parking: number?, -- since when it brakes for the stop
}

local deliveries: { [Player]: Delivery } = {}
local spawnedAt: { [Player]: number } = {}
local playedAt: { [Player]: number } = {}
local rng = Random.new()

local THINK = 0.2 -- seconds between the route / obstacle decisions
local REROUTE = 1.5 -- seconds between checks whether you moved
local GARAGE_RANGE = 400 -- a garage of yours this close sends the car out of it
local MAX_YAW = 2.6 -- rad / s
local ACCEL = 24
local BRAKE = 36
local BRAKE_PLAN = 26 -- the deceleration the stop is planned with (gentler than BRAKE)
local SIT_LIFT = 1.5 -- the root above the seat's top, seated
local WALK_AWAY = 15
local PARK_LANE = 1.25 -- parked: this × the lane offset off the centre line (near the curb)
local PARK_STRETCH = 40 -- studs before the stop where it moves over to your side of the road
local SIT_ANIMATION = "rbxassetid://2506281703" -- Roblox's R15 sit

local NAMES = { "Marco", "Jules", "Bruno", "Vince", "Otto", "Luca", "Hank", "Rosa", "Greta", "Nina", "Ivo", "Dora" }
local LINES = {
	"Your {car}, boss. Keys are in it.",
	"Here she is. Drive safe out there!",
	"Delivered. Mind the zombies!",
	"All yours. Not a scratch on it... mostly.",
	"Parked and ready. Good luck out there.",
}

-- ── Helpers ────────────────────────────────────────────────────────────────

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
		return root
	end
	return nil
end

-- World.EstateGarages / World.EstateSpawns (id → CFrame) come from server/World.luau (stream estate-world).
-- FALLBACK: read loosely, so a World without them (yet) just means "no garages, no homes" here.
local function estateSpots(name: string): { [string]: CFrame }
	local value = (World :: any)[name]
	if type(value) ~= "table" then
		return {}
	end
	return value :: { [string]: CFrame }
end

local function carName(carId: string): string
	local def = Economy.findCar(carId)
	return if def then def.name else "car"
end

-- What the sight line and the obstacle scan look past.
local function sightIgnore(): { Instance }
	local list: { Instance } = {}
	for _, name in { "Cars", "Traffic", "BanditCars", "Npcs", "Zombies", "Animals", "Loot" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			table.insert(list, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

-- Can the player see this spot from where they stand?
local function inSight(eye: Vector3, spot: Vector3, ignore: { Instance }): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return workspace:Raycast(eye, spot - eye, params) == nil
end

-- Another car (traffic, a player's, a bandit's) standing within `reach` of the spot; `except` (your own old car,
-- it goes anyway) does not count.
local function carNear(spot: Vector3, reach: number, except: Instance?): boolean
	for _, name in { "Traffic", "Cars", "BanditCars" } do
		local folder = workspace:FindFirstChild(name)
		if not folder then
			continue
		end
		for _, model in folder:GetChildren() do
			local pp = if model:IsA("Model") then model.PrimaryPart else nil
			if pp and model ~= except and flat(pp.Position - spot).Magnitude < reach then
				return true
			end
		end
	end
	return false
end

-- The lane offset at a point: a quarter of the road's width to the right, nothing off the road.
local function laneAt(x: number, z: number): number
	local rx, rz, _, _, width = Map.nearestRoad(x, z)
	if (rx - x) ^ 2 + (rz - z) ^ 2 > (width / 2 + 1) ^ 2 then
		return 0
	end
	return width * 0.25
end

-- The point `dist` studs on along the route from (x, z) on step k, the direction of the step it lands on (unit)
-- and that step.
local function ahead(route: { Point }, k: number, x: number, z: number, dist: number): (number, number, number, number, number)
	local i = k
	while i < #route do
		local q = route[i + 1]
		local sx, sz = q.x - x, q.z - z
		local length = math.sqrt(sx * sx + sz * sz)
		if length >= dist and length > 1e-6 then
			return x + sx / length * dist, z + sz / length * dist, sx / length, sz / length, i
		end
		dist -= length
		x, z = q.x, q.z
		i += 1
	end
	local n = #route
	local last = route[n]
	for j = n - 1, 1, -1 do
		local a = route[j]
		local dx, dz = last.x - a.x, last.z - a.z
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 0.5 then
			return last.x, last.z, dx / length, dz / length, n
		end
	end
	return last.x, last.z, 0, 0, n
end

-- Studs from (x, z) on step k to the end of the route.
local function remaining(route: { Point }, k: number, x: number, z: number): number
	if k >= #route then
		return 0
	end
	local q = route[k + 1]
	local total = math.sqrt((q.x - x) ^ 2 + (q.z - z) ^ 2)
	for i = k + 1, #route - 1 do
		total += math.sqrt((route[i + 1].x - route[i].x) ^ 2 + (route[i + 1].z - route[i].z) ^ 2)
	end
	return total
end

-- The direction the route starts in (unit), skipping the tiny first bits (the snap onto the road).
local function startDirection(route: { Point }): (number, number)
	for i = 1, #route - 1 do
		local dx, dz = route[i + 1].x - route[i].x, route[i + 1].z - route[i].z
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 2 then
			return dx / length, dz / length
		end
	end
	return 0, 1
end

-- Where the car goes for a player standing at P: the road next to them (the car stops on its lane), or the player
-- themselves in a yard (the depot's, the far places': asphalt you can drive on).
local function routeTo(fromX: number, fromZ: number, P: Vector3): ({ Point }, boolean)
	if Map.inYard(P.X, P.Z) then
		return Roads.route(fromX, fromZ, P.X, P.Z), true
	end
	local gx, gz = Map.nearestRoad(P.X, P.Z)
	return Roads.route(fromX, fromZ, gx, gz), false
end

-- Where the car parks at the end of the route: on your side of the road (side: +1 right of the way it comes, -1
-- left), near the curb (PARK_LANE × the lane offset). How far before the end it stops: in a yard short of you; on
-- the road a little before you when you stand where it would park; else right there, beside you.
local function parkingFor(route: { Point }, yard: boolean, P: Vector3, car: Vehicles.Car): (number, number)
	if yard then
		return car.size.Z / 2 + 6, 1
	end
	local last = route[#route]
	local _, _, dx, dz = ahead(route, #route, last.x, last.z, 0)
	local side = if (P.X - last.x) * -dz + (P.Z - last.z) * dx < 0 then -1 else 1
	local offset = laneAt(last.x, last.z) * PARK_LANE * side
	local parkX, parkZ = last.x - dz * offset, last.z + dx * offset
	if math.sqrt((P.X - parkX) ^ 2 + (P.Z - parkZ) ^ 2) < car.size.X / 2 + 4 then
		return car.size.Z / 2 + 5, side
	end
	return 0, side
end

local function maxRoute(): number
	return Tuning.Speed * math.max(Tuning.ArriveWithin - 3, 4) * 0.8
end

-- ── Where the car starts ───────────────────────────────────────────────────

type Start = { ground: CFrame, route: { Point }, yard: boolean }

-- Out of a garage of yours (a home's or a standalone one) within GARAGE_RANGE, the nearest.
local function garageStart(player: Player, P: Vector3): Start?
	local spots = estateSpots("EstateGarages")
	local best: Start? = nil
	local bestD = GARAGE_RANGE
	for _, def in Config.Estate.Properties do
		local spot = spots[def.id]
		if not spot or def.garageSlots <= 0 or not Estate.owns(player, def.id) then
			continue
		end
		local d = flat(spot.Position - P).Magnitude
		if d >= bestD then
			continue
		end
		local route, yard = routeTo(spot.X, spot.Z, P)
		if Roads.length(route) > maxRoute() then
			continue
		end
		local look = flat(spot.LookVector)
		look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, 1)
		local position = Vector3.new(spot.X, Vehicles.groundY(spot.X, spot.Z, spot.Y) + 0.5, spot.Z)
		local mine = Vehicles.get(player)
		if carNear(position, 10, if mine then mine.model else nil) then
			continue -- a co-owner's car stands in the way
		end
		best, bestD = { ground = CFrame.lookAt(position, position + look), route = route, yard = yard }, d
	end
	return best
end

-- A road spot SpawnMin .. SpawnMax studs away, out of sight if it can be, with a drive to you that fits the time.
local function roadStart(P: Vector3): Start?
	local mountain = Map.Mountain
	local ignore = sightIgnore()
	local eye = P + Vector3.new(0, 2.5, 0)
	local best: Start? = nil
	local bestScore = math.huge
	for attempt = 1, 14 do
		-- The second half of the tries takes anything near enough (far from the roads the ring has none).
		local loose = attempt > 8
		local angle = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(Tuning.SpawnMin, Tuning.SpawnMax)
		local x, z, _, _, width = Map.nearestRoad(P.X + math.cos(angle) * r, P.Z + math.sin(angle) * r)
		local d = math.sqrt((x - P.X) ^ 2 + (z - P.Z) ^ 2)
		local low, high = if loose then 30 else Tuning.SpawnMin * 0.8, if loose then Tuning.SpawnMax * 1.6 else Tuning.SpawnMax * 1.2
		if d < low or d > high or Map.inWater(x, z) then
			continue
		end
		if (x - mountain.x) ^ 2 + (z - mountain.z) ^ 2 < (mountain.radius + 40) ^ 2 then
			continue -- not in the tunnel
		end
		local route, yard = routeTo(x, z, P)
		local length = Roads.length(route)
		if length > maxRoute() then
			continue
		end
		-- On the right-hand lane, facing the way to you.
		local dx, dz = startDirection(route)
		local offset = width * 0.25
		local sx, sz = x - dz * offset, z + dx * offset
		local position = Vector3.new(sx, Vehicles.groundY(sx, sz, P.Y) + 0.5, sz)
		if carNear(position, 14) then
			continue
		end
		local seen = inSight(eye, position + Vector3.new(0, 3, 0), ignore)
		local score = math.abs(length - 170) + (if seen then 1000 else 0) + (if loose then 500 else 0)
		if score < bestScore then
			bestScore = score
			best = { ground = CFrame.lookAt(position, position + Vector3.new(dx, 0, dz)), route = route, yard = yard }
			if not seen and not loose then
				break -- out of sight and a fair drive: good
			end
		end
	end
	return best
end

-- ── The chauffeur ──────────────────────────────────────────────────────────

local function chauffeurLook(): Npcs.Look
	local name = NAMES[rng:NextInteger(1, #NAMES)]
	local look = Npcs.look("clerk", name, "Your chauffeur")
	look.hat, look.hatColor = "cap", { 24, 24, 28 }
	look.shirt, look.pants = { 30, 30, 34 }, { 28, 28, 32 }
	look.vest, look.apron, look.coat = nil, nil, nil
	look.tie = { 150, 24, 30 }
	look.shoes = { 18, 18, 20 }
	look.shortSleeves = false
	return look
end

-- Into the driver's seat: welded to it, massless and not colliding (the car carries it), the sit pose.
local function seatChauffeur(d: Delivery, npc: Model)
	local seat = d.car.seat
	local root = npc.PrimaryPart
	if not root then
		return
	end
	npc:SetAttribute("Busy", true) -- the Npcs greeting leaves them be
	for _, part in npc:GetDescendants() do
		if part:IsA("BasePart") then
			d.saved[part] = { massless = part.Massless, collide = part.CanCollide }
			part.Massless = true
			part.CanCollide = false
		end
	end
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true -- no forces of its own in the car
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0)
			end
			local ok, track = pcall(function()
				local animation = Instance.new("Animation")
				animation.AnimationId = SIT_ANIMATION
				return animator:LoadAnimation(animation)
			end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				track.Looped = true
				track:Play(0)
				d.sitTrack = track
			end
		end
	end
	local sit = CFrame.new(0, seat.Size.Y / 2 + SIT_LIFT, 0)
	npc:PivotTo(seat.CFrame * sit)
	local weld = Instance.new("Weld")
	weld.Name = "ChauffeurWeld"
	weld.Part0 = seat
	weld.Part1 = root
	weld.C0 = sit
	weld.Parent = root
	d.seatWeld = weld
	root.Anchored = false
	-- The body joined the car's assembly: the server keeps simulating it.
	pcall(function()
		d.car.chassis:SetNetworkOwner(nil)
	end)
end

-- Fades a person out (every visible part and the face) and removes them.
local function fadeOut(npc: Model)
	if not npc.Parent then
		return
	end
	local info = TweenInfo.new(Tuning.DriverFade, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, item in npc:GetDescendants() do
		if item:IsA("BasePart") and item.Transparency < 1 then
			TweenService:Create(item, info, { Transparency = 1 }):Play()
		elseif item:IsA("Decal") then
			TweenService:Create(item, info, { Transparency = 1 }):Play()
		elseif item:IsA("BillboardGui") then
			item.Enabled = false
		end
	end
	task.delay(Tuning.DriverFade + 0.1, function()
		if npc.Parent then
			Npcs.remove(npc)
		end
	end)
end

-- Out of the driver's door, a line, a walk away (from you and the car), the fade.
local function stepOut(d: Delivery)
	local npc = d.npc
	d.npc = nil
	if not npc or not npc.Parent then
		return
	end
	local root = npc.PrimaryPart
	if d.seatWeld then
		d.seatWeld:Destroy()
		d.seatWeld = nil
	end
	if d.sitTrack then
		d.sitTrack:Stop(0.15)
		d.sitTrack = nil
	end
	for part, saved in d.saved do
		if part.Parent then
			part.Massless = saved.massless
			part.CanCollide = saved.collide
		end
	end
	table.clear(d.saved)
	local humanoid = npc:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = false
	end
	if not root then
		Npcs.remove(npc)
		return
	end
	root.Anchored = true
	local frame = d.car.chassis.CFrame
	local seatZ = frame:PointToObjectSpace(d.car.seat.Position).Z
	local door = (frame * CFrame.new(-(d.car.size.X / 2 + 2.2), 0, seatZ)).Position
	local groundY = Vehicles.groundY(door.X, door.Z, frame.Position.Y)
	local lift = if humanoid then humanoid.HipHeight + root.Size.Y / 2 else 3
	local at = Vector3.new(door.X, groundY + lift, door.Z)
	-- Away: back along the car and away from the player.
	local back = flat(-frame.LookVector)
	back = if back.Magnitude > 0.01 then back.Unit else Vector3.new(0, 0, 1)
	local playerRoot = rootOf(d.player)
	local away = if playerRoot then flat(at - playerRoot.Position) else Vector3.zero
	away = if away.Magnitude > 0.5 then away.Unit else back
	local way = back + away
	way = if way.Magnitude > 0.1 then way.Unit else back
	npc:PivotTo(CFrame.lookAt(at, at + way))
	local line = string.gsub(LINES[rng:NextInteger(1, #LINES)], "{car}", function()
		return d.name
	end)
	Npcs.say(npc, line, 2.6)
	local goal = at + way * WALK_AWAY
	local faded = false
	local function leave()
		if not faded then
			faded = true
			fadeOut(npc)
		end
	end
	task.delay(0.35, function()
		if npc.Parent then
			Npcs.walkTo(npc, goal, function()
				leave()
			end, 6)
		end
	end)
	-- Whatever happens on the way, they are gone soon.
	task.delay(8, leave)
end

-- ── The client's status line ───────────────────────────────────────────────

local function secondsLeft(d: Delivery, now: number): number
	local eta = math.min(d.deadline - now, math.max(d.left, 0) / (Tuning.Speed * 0.75) + 1)
	return math.max(1, math.ceil(eta))
end

local function tell(d: Delivery, now: number)
	local seconds = secondsLeft(d, now)
	if seconds ~= d.sent then
		d.sent = seconds
		Net.get("CarCall"):FireClient(d.player, seconds, d.car.model)
	end
end

local function tellDone(player: Player)
	if player.Parent then
		Net.get("CarCall"):FireClient(player, nil)
	end
end

-- ── Ending a call ──────────────────────────────────────────────────────────

-- The call is over without a hand-over (the car is gone, replaced, the player left): the chauffeur just goes.
local function abort(d: Delivery)
	if deliveries[d.player] == d then
		deliveries[d.player] = nil
	end
	local npc = d.npc
	d.npc = nil
	if npc and npc.Parent then
		Npcs.remove(npc)
	end
	tellDone(d.player)
end

-- Arrived: the car stops, the chauffeur gets out, the car is yours.
local function arrive(d: Delivery)
	deliveries[d.player] = nil
	local linear = d.car.chassis:FindFirstChild("Drive")
	if linear and linear:IsA("LinearVelocity") then
		linear.PlaneVelocity = Vector2.zero
	end
	stepOut(d) -- first: the body leaves the car's assembly before the car changes owner
	Vehicles.handOver(d.car)
	tellDone(d.player)
	Net.get("Notice"):FireClient(d.player, `Your {d.name} is here.`)
end

-- Too late: the car is placed next to the player the old way.
local function fallback(d: Delivery)
	abort(d)
	if not d.player.Parent then
		return
	end
	local err = Vehicles.placeNear(d.player, d.carId)
	Net.get("Notice"):FireClient(d.player, err or `Your chauffeur got held up: your {d.name} is right here.`)
end

-- ── Driving ────────────────────────────────────────────────────────────────

-- The gap to the nearest thing in the lane ahead (cars, people), or nil.
local function obstacleGap(d: Delivery, position: Vector3, look: Vector3): number?
	local car = d.car
	local right = Vector3.new(-look.Z, 0, look.X)
	local halfW, halfL = car.size.X / 2, car.size.Z / 2
	local reach = 10 + math.abs(d.speed) * 0.9
	local best: number? = nil
	local function consider(p: Vector3, radius: number)
		local rel = p - position
		local forward = rel.X * look.X + rel.Z * look.Z
		if forward <= 0 or forward > reach + halfL + radius then
			return
		end
		if math.abs(rel.Y) > 12 or math.abs(rel.X * right.X + rel.Z * right.Z) > halfW + radius + 0.5 then
			return
		end
		local gap = forward - halfL - radius
		if best == nil or gap < best then
			best = gap
		end
	end
	-- A car as three points along its middle (nose, centre, tail), each with half its width.
	local function considerCar(chassis: BasePart)
		local frame = chassis.CFrame
		local size = chassis.Size
		local r = size.X / 2 + 0.3
		local along = frame.LookVector * math.max(size.Z / 2 - r, 0)
		consider(frame.Position, r)
		consider(frame.Position + along, r)
		consider(frame.Position - along, r)
	end
	for _, name in { "Traffic", "BanditCars" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			for _, model in folder:GetChildren() do
				local pp = if model:IsA("Model") then model.PrimaryPart else nil
				if pp and (name ~= "Traffic" or model:GetAttribute("Traffic") == true) then
					considerCar(pp)
				end
			end
		end
	end
	for _, other in Vehicles.all() do
		if other ~= car then
			considerCar(other.chassis)
		end
	end
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root then
			consider(root.Position, 1.5)
		end
	end
	-- Anything solid in the way: the burnt-out wrecks in the lanes, a roadblock, a wall. A box as wide as the car at
	-- bumper height (over the curbs), swept ahead along its nose (up and down the hills with it).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = sightIgnore()
	params.RespectCanCollide = true
	local frame = car.chassis.CFrame
	local hit = workspace:Blockcast(frame * CFrame.new(0, 0.9, -(halfL + 0.6)), Vector3.new(car.size.X - 0.4, 2, 1), frame.LookVector * reach, params)
	if hit and (best == nil or hit.Distance < best) then
		best = hit.Distance
	end
	return best
end

local function reroute(d: Delivery, position: Vector3, P: Vector3)
	local route, yard = routeTo(position.X, position.Z, P)
	d.route = route
	d.step = 1
	d.goalX, d.goalZ = P.X, P.Z
	d.stopShort, d.side = parkingFor(route, yard, P, d.car)
	d.parking = nil
end

-- The decisions, THINK times a second: the route, the steering point, the speed the road ahead allows.
local function think(d: Delivery, now: number)
	local chassis = d.car.chassis
	local position = chassis.Position
	local playerRoot = rootOf(d.player)
	if playerRoot and now >= d.nextRoute then
		d.nextRoute = now + REROUTE
		local P = playerRoot.Position
		if math.sqrt((P.X - d.goalX) ^ 2 + (P.Z - d.goalZ) ^ 2) > 18 then
			reroute(d, position, P)
		end
	end
	local k, px, pz, off = Roads.closest(d.route, position.X, position.Z, d.step)
	if off > 35 and playerRoot then
		-- Pushed off the way: plan again from here.
		reroute(d, position, playerRoot.Position)
		k, px, pz = Roads.closest(d.route, position.X, position.Z, 1)
	end
	d.step = k
	d.left = remaining(d.route, k, px, pz) - d.stopShort

	local look = flat(chassis.CFrame.LookVector)
	look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
	local speed = math.abs(d.speed)

	-- The steering point: a bit ahead on the route, on the right-hand lane (on the left while overtaking), over to
	-- your side of the road for the last stretch (it parks at your curb).
	local reach = 9 + speed * 0.3
	local tx, tz, sdx, sdz = ahead(d.route, k, px, pz, reach)
	local lane = laneAt(tx, tz)
	if d.left + d.stopShort - reach < PARK_STRETCH then
		lane *= PARK_LANE * d.side
	elseif now < d.overtakeUntil then
		lane = -lane
	end
	d.target = Vector3.new(tx - sdz * lane, position.Y, tz + sdx * lane)

	-- Slower into the turns: the angle to a point further ahead.
	local fx, fz = ahead(d.route, k, px, pz, 22 + speed * 0.45)
	local toFar = Vector3.new(fx - position.X, 0, fz - position.Z)
	local turn = if toFar.Magnitude > 1 then math.acos(math.clamp(look:Dot(toFar.Unit), -1, 1)) else 0
	local limit = Tuning.Speed * (1 - math.min(turn, 1.4) / 1.4 * 0.62)

	-- Something in the lane: brake for it, overtake when it stays.
	local gap = obstacleGap(d, position, look)
	if gap then
		local allowed = math.max(0, (gap - 3) * 1.4)
		if now < d.overtakeUntil and gap > 1 then
			allowed = math.max(allowed, 7)
		end
		limit = math.min(limit, allowed)
		local actual = chassis.AssemblyLinearVelocity:Dot(look)
		if allowed < 3 and math.abs(actual) < 2 then
			d.blocked += THINK
			if d.blocked > 1.2 and now >= d.overtakeUntil then
				d.blocked = 0
				d.overtakeUntil = now + 3.5
				if gap < 3 then
					d.reverseUntil = now + 0.9 -- nose to it: back up a little first, turning out
				end
			end
		else
			d.blocked = 0
		end
	else
		d.blocked = 0
	end
	d.limit = limit
	tell(d, now)
end

-- Every frame: steer toward the point, speed up / brake to what is allowed, stop at the end.
local function drive(d: Delivery, dt: number, now: number)
	local chassis = d.car.chassis
	local linear = chassis:FindFirstChild("Drive")
	local angular = chassis:FindFirstChild("Steer")
	if not linear or not linear:IsA("LinearVelocity") or not angular or not angular:IsA("AngularVelocity") then
		fallback(d)
		return
	end
	local position = chassis.Position
	local look = flat(chassis.CFrame.LookVector)
	if look.Magnitude < 0.01 then
		return
	end
	look = look.Unit
	local actual = chassis.AssemblyLinearVelocity:Dot(look)
	d.left -= math.max(actual, 0) * dt -- between the decisions

	-- The stop: brake on a plan that ends right there; standing, the chauffeur gets out.
	if d.left <= 1.5 then
		d.parking = d.parking or now
	end
	if d.parking then
		d.speed = math.max(0, d.speed - BRAKE * 1.5 * dt)
		linear.PlaneVelocity = Vector2.new(look.X * d.speed, look.Z * d.speed)
		angular.AngularVelocity = Vector3.zero
		if (math.abs(actual) < 1.5 and d.speed < 1) or now - (d.parking :: number) > 1.6 then
			arrive(d)
		end
		return
	end

	local toward = flat(d.target - position)
	local desired = if toward.Magnitude > 0.5 then toward.Unit else look
	local cross = look.X * desired.Z - look.Z * desired.X
	local angle = math.atan2(cross, look:Dot(desired))
	local yaw = math.clamp(-angle * 2.6, -MAX_YAW, MAX_YAW)
	if toward.Magnitude < 4 then
		yaw = 0
	end

	local target = math.min(d.limit, math.sqrt(2 * BRAKE_PLAN * math.max(d.left - 1, 0)) + 2)
	if now < d.reverseUntil then
		target = -14
		yaw = -yaw
	elseif target > 8 and math.abs(actual) < 2.5 then
		-- Pushing and not moving: back up a little, then try again.
		d.stuck += dt
		if d.stuck > 1.4 then
			d.stuck = 0
			d.reverseUntil = now + 1.1
		end
	else
		d.stuck = 0
	end
	-- Against something the real speed drops: do not keep a big speed that shoots the car off when it is free.
	if math.abs(d.speed) > math.abs(actual) + 10 then
		d.speed = actual + (if d.speed > 0 then 10 else -10)
	end
	local rate = if math.sign(target) ~= math.sign(d.speed) or math.abs(target) < math.abs(d.speed) then BRAKE else ACCEL
	d.speed = if d.speed < target then math.min(d.speed + rate * dt, target) else math.max(d.speed - rate * dt, target)
	linear.PlaneVelocity = Vector2.new(look.X * d.speed, look.Z * d.speed)
	local grip = math.clamp(math.abs(d.speed) / 10, 0, 1)
	angular.AngularVelocity = Vector3.new(0, yaw * grip * (if d.speed >= 0 then 1 else -1), 0)
end

local function step(dt: number)
	if next(deliveries) == nil then
		return
	end
	local now = os.clock()
	for player, d in table.clone(deliveries) do
		if deliveries[player] ~= d then
			continue
		end
		local car = d.car
		if not player.Parent or Vehicles.get(player) ~= car or not car.chassis.Parent then
			abort(d) -- the car is gone (wrecked, replaced, the player left)
			continue
		end
		if now >= d.deadline and not d.parking then
			fallback(d)
			continue
		end
		if now >= d.nextThink then
			d.nextThink = now + THINK
			think(d, now)
		end
		drive(d, dt, now)
	end
end

-- ── Calling ────────────────────────────────────────────────────────────────

-- Is a chauffeur on the way to this player?
function CarCall.busy(player: Player): boolean
	return deliveries[player] ~= nil
end

-- The CAR button (Vehicles.spawn without force, through Vehicles.callCar): sends the chauffeur. Returns an error
-- text, or nil when the car is on its way (or, with no road for a chauffeur around, was placed next to you).
function CarCall.call(player: Player, carId: string?): string?
	local now = os.clock()
	local current = deliveries[player]
	if current then
		return `Your {current.name} is on the way · {secondsLeft(current, now)} s.`
	end
	local root = rootOf(player)
	if not root then
		return "Still loading..."
	end
	local err = Vehicles.cooldown(player)
	if err then
		return err
	end
	local P = root.Position
	local start = garageStart(player, P) or roadStart(P)
	if not start then
		return Vehicles.placeNear(player, carId) -- no road for a chauffeur out here: as before
	end
	local car = Vehicles.spawnAt(player, carId, start.ground, false, true)
	if not car then
		return "Still loading..."
	end
	local d: Delivery = {
		player = player,
		car = car,
		carId = carId,
		name = carName(car.id),
		npc = nil,
		seatWeld = nil,
		sitTrack = nil,
		saved = {},
		route = start.route,
		step = 1,
		stopShort = 0,
		side = 1,
		goalX = P.X,
		goalZ = P.Z,
		left = 0,
		started = now,
		deadline = now + Tuning.ArriveWithin,
		speed = 0,
		target = start.ground.Position + start.ground.LookVector * 10,
		limit = 0,
		stuck = 0,
		reverseUntil = 0,
		blocked = 0,
		overtakeUntil = 0,
		nextThink = 0,
		nextRoute = now + REROUTE,
		sent = 0,
		parking = nil,
	}
	d.stopShort, d.side = parkingFor(start.route, start.yard, P, car)
	d.left = Roads.length(start.route) - d.stopShort
	local ok, npc = pcall(Npcs.spawn, chauffeurLook(), car.seat.CFrame)
	if ok and npc then
		d.npc = npc
		seatChauffeur(d, npc)
	else
		warn(`[CarCall] no chauffeur: {npc}`) -- the car drives itself, nobody minds
	end
	deliveries[player] = d
	tell(d, now)
	Net.get("Notice"):FireClient(player, `Your chauffeur is bringing the {d.name}.`)
	return nil
end

-- Ends a call at once (the chauffeur and the car go), e.g. before a respawn brings a new car.
function CarCall.cancel(player: Player)
	local d = deliveries[player]
	if d then
		abort(d)
		Vehicles.remove(player)
	end
end

-- ── Home garage (the instant cases) ────────────────────────────────────────

-- Where an instant car goes when the player spawns at home: their home's garage drive-out spot, when they just
-- spawned or pressed PLAY (the server puts them at home, server/Estate.luau) or stand at home; else nil.
local function homeGarage(player: Player): CFrame?
	local home = Estate.homeOf(player)
	local spot = if home then estateSpots("EstateGarages")[home] else nil
	if not home or not spot then
		return nil
	end
	local now = os.clock()
	if now - (spawnedAt[player] or -math.huge) < 10 or now - (playedAt[player] or -math.huge) < 10 then
		return spot
	end
	local root = rootOf(player)
	if root then
		local door = estateSpots("EstateSpawns")[home]
		if flat(root.Position - spot.Position).Magnitude < 140 or (door and flat(root.Position - door.Position).Magnitude < 140) then
			return spot
		end
	end
	return nil
end

function CarCall.start()
	Vehicles.callCar = CarCall.call
	Vehicles.homeGarage = homeGarage
	RunService.Heartbeat:Connect(step)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			spawnedAt[player] = os.clock()
			-- A respawn (death, reset) ends a call: the new character gets its car the instant way (Main).
			CarCall.cancel(player)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local d = deliveries[player]
		if d then
			abort(d)
		end
		spawnedAt[player] = nil
		playedAt[player] = nil
	end)
	Net.get("Play").OnServerEvent:Connect(function(player)
		playedAt[player] = os.clock()
		-- Main gives the car on PLAY too; whichever handler ran first, the car that just came for a player with a home
		-- stands at the home garage (they spawn at home, server/Estate.luau).
		task.defer(function()
			local car = Vehicles.get(player)
			local spot = homeGarage(player)
			if car and spot and not car.chauffeured and os.clock() - car.born < 2 and flat(car.chassis.Position - spot.Position).Magnitude > 40 then
				local def = Economy.findCar(car.id)
				Vehicles.spawn(player, true, if def and def.company then car.id else nil)
			end
		end)
	end)
end

return CarCall
