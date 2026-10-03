--!strict
-- The cars. Each player has at most one car in the world, built in code from its style.
--
-- Driving is arcade, not wheel physics: the wheels are welded, frictionless colliders (they ride over curbs) and two
-- constraints on the chassis move the car. A LinearVelocity in the ground plane (gravity still works) and an
-- AngularVelocity that turns it around the vertical axis and keeps it upright. The owner's client simulates the car
-- (network owner) and sets both constraints from the VehicleSeat's throttle / steer (client/Drive.luau), the
-- server only reads where the car is and how fast it goes (ramming, deliveries).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local CityGrid = require(Shared.CityGrid)
local World = require(script.Parent.World)
local PlayerData = require(script.Parent.PlayerData)

export type Car = {
	owner: Player,
	id: string,
	model: Model,
	chassis: Part,
	seat: VehicleSeat,
	turret: Weld,
	turretBase: CFrame,
	muzzle: Attachment,
	size: Vector3, -- the hull (width, height, length) for ramming and latching
	stats: Economy.CarStats,
	health: number,
	wrecked: boolean,
	latched: { [number]: boolean }, -- taken latch slots
}

local Vehicles = {}

local cars: { [Player]: Car } = {}
local lastSpawn: { [Player]: number } = {}

-- Set by Main: (player, car) when a car is destroyed.
Vehicles.onWrecked = function(_player: Player, _car: Car) end

local DARK = Color3.fromRGB(34, 34, 38)
local GLASS = Color3.fromRGB(150, 190, 210)

type Box = { size: Vector3, offset: Vector3, kind: string } -- kind: body | dark | glass | accent | plate

type Style = {
	width: number,
	length: number,
	wheel: number, -- radius
	wheelWidth: number,
	clearance: number, -- chassis bottom above the ground
	seat: Vector3, -- relative to the chassis top centre
	roof: number, -- turret height above the chassis top
	boxes: { Box }, -- relative to the chassis top centre (offset = centre of the box)
}

local function box(size: Vector3, offset: Vector3, kind: string): Box
	return { size = size, offset = offset, kind = kind }
end

-- Front of the car is -Z (the LookVector).
local STYLES: { [string]: Style } = {
	van = {
		width = 6.6,
		length = 13,
		wheel = 1.3,
		wheelWidth = 1,
		clearance = 0.9,
		seat = Vector3.new(-1.4, 0.5, -2.6),
		roof = 5.4,
		boxes = {
			box(Vector3.new(6.6, 2, 2.6), Vector3.new(0, 1, -5.2), "body"), -- hood
			box(Vector3.new(6.6, 4.4, 4), Vector3.new(0, 2.2, -2), "glass"), -- cabin
			box(Vector3.new(6.6, 0.6, 4), Vector3.new(0, 4.7, -2), "body"), -- cabin roof
			box(Vector3.new(6.6, 5, 6.4), Vector3.new(0, 2.5, 3.2), "body"), -- cargo box
			box(Vector3.new(6.8, 0.8, 0.6), Vector3.new(0, 0.4, -6.6), "dark"), -- bumper
		},
	},
	pickup = {
		width = 6.4,
		length = 13,
		wheel = 1.4,
		wheelWidth = 1.1,
		clearance = 1.0,
		seat = Vector3.new(-1.3, 0.5, -1.4),
		roof = 4.8,
		boxes = {
			box(Vector3.new(6.4, 1.8, 3.6), Vector3.new(0, 0.9, -4.7), "body"),
			box(Vector3.new(6.4, 4, 4), Vector3.new(0, 2, -0.9), "glass"),
			box(Vector3.new(6.4, 0.6, 4), Vector3.new(0, 4.3, -0.9), "body"),
			box(Vector3.new(0.4, 1.6, 5.4), Vector3.new(-3, 0.8, 3.8), "body"), -- bed walls
			box(Vector3.new(0.4, 1.6, 5.4), Vector3.new(3, 0.8, 3.8), "body"),
			box(Vector3.new(6.4, 1.6, 0.4), Vector3.new(0, 0.8, 6.3), "body"),
			box(Vector3.new(4, 1.4, 3), Vector3.new(0, 0.7, 3.4), "accent"), -- the cargo
			box(Vector3.new(6.8, 0.9, 0.7), Vector3.new(0, 0.3, -6.7), "dark"),
		},
	},
	muscle = {
		width = 6.4,
		length = 13.5,
		wheel = 1.25,
		wheelWidth = 1.2,
		clearance = 0.8,
		seat = Vector3.new(-1.3, 0.2, 0.4),
		roof = 3.6,
		boxes = {
			box(Vector3.new(6.4, 1.4, 13.5), Vector3.new(0, 0.7, 0), "body"),
			box(Vector3.new(5.6, 2.2, 5), Vector3.new(0, 2.5, 0.6), "glass"),
			box(Vector3.new(5.6, 0.4, 4), Vector3.new(0, 3.4, 0.8), "body"),
			box(Vector3.new(6.4, 0.3, 1.4), Vector3.new(0, 2.6, 6.2), "dark"), -- spoiler
			box(Vector3.new(0.4, 1.2, 0.4), Vector3.new(-2.6, 2, 6.2), "dark"),
			box(Vector3.new(0.4, 1.2, 0.4), Vector3.new(2.6, 2, 6.2), "dark"),
			box(Vector3.new(1.6, 0.05, 13.5), Vector3.new(0.9, 1.42, 0), "accent"), -- stripes
			box(Vector3.new(1.6, 0.05, 13.5), Vector3.new(-0.9, 1.42, 0), "accent"),
		},
	},
	armored = {
		width = 7.4,
		length = 15,
		wheel = 1.6,
		wheelWidth = 1.3,
		clearance = 1.1,
		seat = Vector3.new(-1.6, 0.5, -3.6),
		roof = 6.4,
		boxes = {
			box(Vector3.new(7.4, 2.4, 3), Vector3.new(0, 1.2, -6), "body"),
			box(Vector3.new(7.4, 4.6, 4), Vector3.new(0, 2.3, -2.6), "glass"),
			box(Vector3.new(7.4, 0.8, 4), Vector3.new(0, 5, -2.6), "body"),
			box(Vector3.new(7.4, 6, 7), Vector3.new(0, 3, 3.6), "body"),
			box(Vector3.new(7.8, 1, 7.4), Vector3.new(0, 1.6, 3.6), "plate"),
			box(Vector3.new(7.8, 1, 7.4), Vector3.new(0, 4.4, 3.6), "plate"),
			box(Vector3.new(8, 2.4, 1), Vector3.new(0, 0.9, -7.8), "plate"), -- ram plate
		},
	},
	monster = {
		width = 8,
		length = 14,
		wheel = 3,
		wheelWidth = 2.2,
		clearance = 2.6,
		seat = Vector3.new(-1.4, 0.5, -0.8),
		roof = 5,
		boxes = {
			box(Vector3.new(7, 2, 4), Vector3.new(0, 1, -4.6), "body"),
			box(Vector3.new(7, 4, 4), Vector3.new(0, 2, -0.6), "glass"),
			box(Vector3.new(7, 0.6, 4), Vector3.new(0, 4.3, -0.6), "body"),
			box(Vector3.new(7, 1.8, 5), Vector3.new(0, 0.9, 4), "body"),
			box(Vector3.new(8.4, 1.2, 1), Vector3.new(0, 0.2, -7.2), "plate"),
			box(Vector3.new(1, 1.4, 12), Vector3.new(-3.2, -0.6, 0), "accent"), -- frame rails
			box(Vector3.new(1, 1.4, 12), Vector3.new(3.2, -0.6, 0), "accent"),
		},
	},
}

local CHASSIS_HEIGHT = 1.2

local function newPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "Car"
	p.Parent = model
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function build(player: Player, def: Config.CarDef, stats: Economy.CarStats, ground: CFrame): Car
	local style = STYLES[def.style] or STYLES.van
	local bodyColor = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
	local accent = bodyColor:Lerp(Color3.new(1, 1, 1), 0.45)

	local model = Instance.new("Model")
	model.Name = `Car_{player.Name}`

	local chassisY = style.clearance + CHASSIS_HEIGHT / 2
	local chassisCF = ground * CFrame.new(0, chassisY, 0)
	local chassis = newPart(model, "Chassis", Vector3.new(style.width - 0.4, CHASSIS_HEIGHT, style.length), chassisCF, DARK, Enum.Material.Metal)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(2, 0, 0, 100, 1)
	model.PrimaryPart = chassis

	local top = chassisCF * CFrame.new(0, CHASSIS_HEIGHT / 2, 0)
	local height = CHASSIS_HEIGHT
	for _, b in style.boxes do
		local color, material = bodyColor, Enum.Material.SmoothPlastic
		if b.kind == "dark" then
			color, material = DARK, Enum.Material.Metal
		elseif b.kind == "glass" then
			color, material = GLASS, Enum.Material.Glass
		elseif b.kind == "accent" then
			color = accent
		elseif b.kind == "plate" then
			color, material = bodyColor:Lerp(DARK, 0.5), Enum.Material.DiamondPlate
		end
		local p = newPart(model, if b.kind == "glass" then "Cabin" else "Body", b.size, top * CFrame.new(b.offset), color, material)
		p.Massless = true
		p.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
		if b.kind == "glass" then
			p.Transparency = 0.45
		end
		weld(chassis, p)
		height = math.max(height, CHASSIS_HEIGHT + b.offset.Y + b.size.Y / 2)
	end

	-- Wheels: welded, frictionless colliders (the car slides on them, the constraints drive it).
	local wheelY = style.wheel - chassisY
	local wx = style.width / 2 - style.wheelWidth / 2 + 0.3
	local wz = style.length / 2 - style.wheel - 0.5
	for _, offset in { Vector3.new(-wx, wheelY, -wz), Vector3.new(wx, wheelY, -wz), Vector3.new(-wx, wheelY, wz), Vector3.new(wx, wheelY, wz) } do
		local wheel = newPart(model, "Wheel", Vector3.new(style.wheelWidth, style.wheel * 2, style.wheel * 2), chassisCF * CFrame.new(offset), Color3.fromRGB(24, 24, 24), Enum.Material.Rubber)
		wheel.Shape = Enum.PartType.Cylinder
		wheel.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0, 0, 100, 1)
		weld(chassis, wheel)
		local hub = newPart(model, "Hub", Vector3.new(style.wheelWidth + 0.1, style.wheel, style.wheel), chassisCF * CFrame.new(offset), Color3.fromRGB(170, 170, 170), Enum.Material.Metal)
		hub.Shape = Enum.PartType.Cylinder
		hub.CanCollide = false
		hub.Massless = true
		weld(chassis, hub)
	end

	-- Lights.
	local front = -style.length / 2
	for _, x in { -style.width / 2 + 1, style.width / 2 - 1 } do
		local head = newPart(model, "Headlight", Vector3.new(1.2, 0.6, 0.2), top * CFrame.new(x, 0.5, front - 0.05), Color3.fromRGB(255, 245, 210), Enum.Material.Neon)
		head.CanCollide = false
		head.Massless = true
		weld(chassis, head)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Range = 50
		spot.Angle = 50
		spot.Brightness = 3
		spot.Color = Color3.fromRGB(255, 240, 210)
		spot.Parent = head
		local tail = newPart(model, "Taillight", Vector3.new(1, 0.5, 0.2), top * CFrame.new(x, 0.6, -front + 0.05), Color3.fromRGB(220, 30, 30), Enum.Material.Neon)
		tail.CanCollide = false
		tail.Massless = true
		weld(chassis, tail)
	end

	-- The roof gun: a base that turns (a Weld whose C0 the server rotates) and a barrel.
	local turretBase = CFrame.new(0, CHASSIS_HEIGHT / 2 + style.roof, 0.5)
	local base = newPart(model, "Turret", Vector3.new(1, 2.2, 2.2), chassisCF * turretBase * CFrame.Angles(0, 0, math.rad(90)), DARK, Enum.Material.Metal)
	base.Shape = Enum.PartType.Cylinder
	base.CanCollide = false
	base.Massless = true
	local turret = Instance.new("Weld")
	turret.Name = "TurretWeld"
	turret.Part0 = chassis
	turret.Part1 = base
	turret.C0 = turretBase
	turret.C1 = CFrame.Angles(0, 0, math.rad(90)):Inverse()
	turret.Parent = base
	local barrel = newPart(model, "Barrel", Vector3.new(0.5, 0.5, 3.4), base.CFrame * CFrame.Angles(0, 0, math.rad(-90)) * CFrame.new(0, 0.3, -1.7), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	barrel.CanCollide = false
	barrel.Massless = true
	weld(base, barrel)
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -1.8)
	muzzle.Parent = barrel

	-- The seat (only the owner may sit in it, see watchSeat).
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.CFrame = top * CFrame.new(style.seat)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.Massless = true
	seat.MaxSpeed = 0 -- the legacy motor is unused, client/Drive.luau drives the car
	seat.HeadsUpDisplay = false
	seat.CollisionGroup = "Car"
	seat.Parent = model
	weld(chassis, seat)

	-- The movers (their values are set by the owner's client).
	local root = Instance.new("Attachment")
	root.Name = "Root"
	root.Parent = chassis
	local linear = Instance.new("LinearVelocity")
	linear.Name = "Drive"
	linear.Attachment0 = root
	linear.RelativeTo = Enum.ActuatorRelativeTo.World
	linear.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	linear.PrimaryTangentAxis = Vector3.xAxis
	linear.SecondaryTangentAxis = Vector3.zAxis
	linear.PlaneVelocity = Vector2.zero
	linear.Parent = chassis
	local angular = Instance.new("AngularVelocity")
	angular.Name = "Steer"
	angular.Attachment0 = root
	angular.RelativeTo = Enum.ActuatorRelativeTo.World
	angular.AngularVelocity = Vector3.zero
	angular.Parent = chassis

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DrivePrompt"
	prompt.ActionText = "Drive"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = chassis

	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("CarId", def.id)

	local car: Car = {
		owner = player,
		id = def.id,
		model = model,
		chassis = chassis,
		seat = seat,
		turret = turret,
		turretBase = turretBase,
		muzzle = muzzle,
		size = Vector3.new(style.width, height, style.length),
		stats = stats,
		health = stats.health,
		wrecked = false,
		latched = {},
	}
	return car
end

local function writeAttributes(car: Car)
	local model = car.model
	model:SetAttribute("MaxSpeed", car.stats.maxSpeed)
	model:SetAttribute("Accel", car.stats.accel)
	model:SetAttribute("Turn", car.stats.turn)
	model:SetAttribute("MaxHealth", car.stats.health)
	model:SetAttribute("Health", math.ceil(car.health))
end

local function eject(seat: VehicleSeat)
	local occupant = seat.Occupant
	local seatWeld = seat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end
	if occupant then
		occupant.Sit = false
		occupant.Jump = true
	end
end

local function watchSeat(car: Car)
	local prompt = car.chassis:FindFirstChild("DrivePrompt") :: ProximityPrompt
	local driver: Humanoid? = nil
	car.seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = car.seat.Occupant
		prompt.Enabled = occupant == nil
		if occupant then
			if occupant.Parent ~= car.owner.Character then
				eject(car.seat) -- somebody else's car
			else
				driver = occupant
			end
			return
		end
		-- Got out: step out next to the driver's door, not inside the cabin.
		local left = driver
		driver = nil
		local character = left and left.Parent
		if left and character and character:IsA("Model") and left.Health > 0 then
			task.defer(function()
				if character.Parent and car.chassis.Parent then
					character:PivotTo(car.chassis.CFrame * CFrame.new(-(car.size.X / 2 + 3), 2, -1))
				end
			end)
		end
	end)
	prompt.Triggered:Connect(function(player)
		if player ~= car.owner or car.wrecked or car.seat.Occupant then
			return
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			car.seat:Sit(humanoid)
		end
	end)
end

function Vehicles.get(player: Player): Car?
	local car = cars[player]
	if car and not car.wrecked then
		return car
	end
	return nil
end

-- All live cars (for the zombies).
function Vehicles.all(): { Car }
	local list = {}
	for _, car in cars do
		if not car.wrecked then
			table.insert(list, car)
		end
	end
	return list
end

function Vehicles.isDriving(player: Player): boolean
	local car = Vehicles.get(player)
	local occupant = car and car.seat.Occupant
	return occupant ~= nil and player.Character ~= nil and occupant.Parent == player.Character
end

-- Speed along the ground (studs / s).
function Vehicles.speed(car: Car): number
	local v = car.chassis.AssemblyLinearVelocity
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

function Vehicles.remove(player: Player)
	local car = cars[player]
	if car then
		cars[player] = nil
		car.wrecked = true
		car.model:Destroy()
	end
end

-- Puts the player's equipped car on the nearest road and seats them. Returns an error text when it cannot.
-- force skips the cooldown (a car just bought or equipped).
function Vehicles.spawn(player: Player, force: boolean?): string?
	local profile = PlayerData.get(player)
	if not profile then
		return "Still loading..."
	end
	local now = os.clock()
	if not force and lastSpawn[player] and now - lastSpawn[player] < Config.SpawnCarCooldown then
		return "Wait a moment before calling the car again."
	end
	local def = Economy.findCar(profile.car) or Config.Cars[1]
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if rootPart then rootPart.Position else World.DepotSpawn
	local look = if rootPart then rootPart.CFrame.LookVector else Vector3.new(0, 0, 1)

	Vehicles.remove(player)
	lastSpawn[player] = now

	local x, z, axis = CityGrid.nearestRoad(from.X, from.Z)
	local direction = if axis == "z" then Vector3.new(0, 0, if look.Z >= 0 then 1 else -1) else Vector3.new(if look.X >= 0 then 1 else -1, 0, 0)
	-- Step along the road if another car stands there.
	local position = Vector3.new(x, World.RoadTop + 0.5, z)
	for _ = 1, 6 do
		local free = true
		for _, other in cars do
			if (other.chassis.Position - position).Magnitude < 16 then
				free = false
				break
			end
		end
		if free then
			break
		end
		position += direction * 18
	end
	local ground = CFrame.lookAt(position, position + direction)
	local stats = Economy.carStats(def.id, profile.upgrades)
	local car = build(player, def, stats, ground)
	writeAttributes(car)
	car.model.Parent = workspace:FindFirstChild("Cars") or workspace
	cars[player] = car
	watchSeat(car)

	-- Heavy enough to plough through, light enough to stop against a wall.
	local mass = car.chassis.AssemblyMass
	local linear = car.chassis:FindFirstChild("Drive") :: LinearVelocity
	local angular = car.chassis:FindFirstChild("Steer") :: AngularVelocity
	linear.MaxForce = mass * 160
	angular.MaxTorque = mass * 6000

	pcall(function()
		car.chassis:SetNetworkOwner(player)
	end)

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		task.defer(function()
			if not car.wrecked then
				car.seat:Sit(humanoid)
			end
		end)
	end
	return nil
end

-- New upgrades / a new car equipped: the live car takes the new numbers (health keeps its share).
function Vehicles.refreshStats(player: Player)
	local car = Vehicles.get(player)
	local profile = PlayerData.get(player)
	if not car or not profile or profile.car ~= car.id then
		return
	end
	local share = car.health / car.stats.health
	car.stats = Economy.carStats(car.id, profile.upgrades)
	car.health = car.stats.health * share
	writeAttributes(car)
end

local function wreck(car: Car)
	car.wrecked = true
	eject(car.seat)
	local explosion = Instance.new("Explosion")
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.BlastRadius = 8
	explosion.Position = car.chassis.Position
	explosion.Parent = workspace
	for _, d in car.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color = d.Color:Lerp(Color3.new(0.08, 0.08, 0.08), 0.75)
		elseif d:IsA("ProximityPrompt") or d:IsA("SpotLight") then
			d:Destroy()
		end
	end
	local fire = Instance.new("Fire")
	fire.Size = 9
	fire.Heat = 12
	fire.Parent = car.chassis
	local linear = car.chassis:FindFirstChild("Drive")
	if linear then
		linear:Destroy()
	end
	car.model:SetAttribute("Health", 0)
	Vehicles.onWrecked(car.owner, car)
	task.delay(5, function()
		if cars[car.owner] == car then
			cars[car.owner] = nil
		end
		car.model:Destroy()
	end)
end

function Vehicles.damage(car: Car, amount: number)
	if car.wrecked or amount <= 0 then
		return
	end
	car.health = math.max(0, car.health - amount)
	car.model:SetAttribute("Health", math.ceil(car.health))
	if car.health <= 0 then
		wreck(car)
	end
end

-- Points the roof gun at a world position.
function Vehicles.aim(car: Car, target: Vector3)
	local localTarget = car.chassis.CFrame:PointToObjectSpace(target)
	local yaw = math.atan2(-localTarget.X, -localTarget.Z)
	car.turret.C0 = car.turretBase * CFrame.Angles(0, yaw, 0)
end

function Vehicles.start()
	Players.PlayerRemoving:Connect(function(player)
		Vehicles.remove(player)
		lastSpawn[player] = nil
	end)
	-- Repairs in the depot (the safe zone): 15 % of the health per second.
	RunService.Heartbeat:Connect(function(dt)
		for _, car in cars do
			if not car.wrecked and car.health < car.stats.health and World.isSafe(car.chassis.Position) then
				car.health = math.min(car.stats.health, car.health + car.stats.health * 0.15 * dt)
				car.model:SetAttribute("Health", math.ceil(car.health))
			end
		end
	end)
end

return Vehicles
