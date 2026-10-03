--!strict
-- The cars. Each player has at most one car in the world, built in code from its style.
--
-- Driving is arcade, not wheel physics: invisible frictionless wheel colliders (they ride over curbs) and two
-- constraints on the chassis move the car. A LinearVelocity in the ground plane (gravity still works) and an
-- AngularVelocity that turns it around the vertical axis and keeps it upright. The owner's client simulates the car
-- (network owner) and sets both constraints from the VehicleSeat's throttle / steer (client/Drive.luau), the
-- server only reads where the car is and how fast it goes (ramming, deliveries).
--
-- The visible tyres hang on Motor6Ds that every client spins and steers (client/CarVisuals.luau).
-- Other players ride along in the passenger seats (the "Ride" prompt) and shoot from there (server/Gun.luau).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local World = require(script.Parent.World)
local PlayerData = require(script.Parent.PlayerData)

export type Car = {
	owner: Player,
	id: string,
	model: Model,
	chassis: Part,
	seat: VehicleSeat,
	passengers: { Seat },
	turret: Weld,
	turretBase: CFrame,
	muzzle: Attachment,
	paintParts: { BasePart },
	size: Vector3, -- the hull (width, height, length) for ramming and latching
	stats: Economy.CarStats,
	health: number,
	wrecked: boolean,
	latched: { [number]: boolean }, -- taken latch slots
}

local Vehicles = {}

local cars: { [Player]: Car } = {}
local lastSpawn: { [Player]: number } = {}

-- Set by Main: (player, car, reason) when a car is destroyed.
Vehicles.onWrecked = function(_player: Player, _car: Car, _reason: string) end

local DARK = Color3.fromRGB(34, 34, 38)
local GLASS = Color3.fromRGB(150, 190, 210)

type Box = { size: Vector3, offset: Vector3, kind: string } -- kind: body | dark | glass | accent | plate | white | ball

type Style = {
	width: number,
	length: number,
	wheel: number, -- radius
	wheelWidth: number,
	clearance: number, -- chassis bottom above the ground
	seat: Vector3, -- the driver, relative to the chassis top centre
	passengers: { Vector3 },
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
		passengers = { Vector3.new(1.4, 0.5, -2.6) },
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
		passengers = { Vector3.new(1.3, 0.5, -1.4), Vector3.new(-1.5, 0.4, 2.8), Vector3.new(1.5, 0.4, 2.8) },
		roof = 4.8,
		boxes = {
			box(Vector3.new(6.4, 1.8, 3.6), Vector3.new(0, 0.9, -4.7), "body"),
			box(Vector3.new(6.4, 4, 4), Vector3.new(0, 2, -0.9), "glass"),
			box(Vector3.new(6.4, 0.6, 4), Vector3.new(0, 4.3, -0.9), "body"),
			box(Vector3.new(0.4, 1.6, 5.4), Vector3.new(-3, 0.8, 3.8), "body"), -- bed walls
			box(Vector3.new(0.4, 1.6, 5.4), Vector3.new(3, 0.8, 3.8), "body"),
			box(Vector3.new(6.4, 1.6, 0.4), Vector3.new(0, 0.8, 6.3), "body"),
			box(Vector3.new(4, 1.4, 1.4), Vector3.new(0, 0.7, 5.3), "accent"), -- the cargo
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
		passengers = { Vector3.new(1.3, 0.2, 0.4) },
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
	icecream = {
		width = 6.8,
		length = 14,
		wheel = 1.35,
		wheelWidth = 1.1,
		clearance = 0.9,
		seat = Vector3.new(-1.4, 0.5, -2.4),
		passengers = { Vector3.new(1.4, 0.5, -2.4) },
		roof = 5.8,
		boxes = {
			box(Vector3.new(6.8, 2, 2.6), Vector3.new(0, 1, -5.7), "body"),
			box(Vector3.new(6.8, 4.4, 4), Vector3.new(0, 2.2, -2.4), "glass"),
			box(Vector3.new(6.8, 0.6, 4), Vector3.new(0, 4.7, -2.4), "body"),
			box(Vector3.new(6.8, 5.6, 7.4), Vector3.new(0, 2.8, 3.3), "body"),
			box(Vector3.new(6.9, 0.8, 7.4), Vector3.new(0, 1.2, 3.3), "accent"), -- pink stripe
			box(Vector3.new(0.2, 2.2, 4), Vector3.new(3.45, 3.4, 3.3), "dark"), -- serving window
			box(Vector3.new(1.4, 2.4, 1.4), Vector3.new(0, 6.6, 4.6), "white"), -- the cone
			box(Vector3.new(2.6, 2.6, 2.6), Vector3.new(0, 8.4, 4.6), "ball"), -- the scoop
			box(Vector3.new(7, 0.8, 0.6), Vector3.new(0, 0.4, -7.1), "dark"),
		},
	},
	armored = {
		width = 7.4,
		length = 15,
		wheel = 1.6,
		wheelWidth = 1.3,
		clearance = 1.1,
		seat = Vector3.new(-1.6, 0.5, -3.6),
		passengers = { Vector3.new(1.6, 0.5, -3.6), Vector3.new(-2, 6.2, 5), Vector3.new(2, 6.2, 5) },
		roof = 6.4,
		boxes = {
			box(Vector3.new(7.4, 2.4, 3), Vector3.new(0, 1.2, -6), "body"),
			box(Vector3.new(7.4, 4.6, 4), Vector3.new(0, 2.3, -2.6), "glass"),
			box(Vector3.new(7.4, 0.8, 4), Vector3.new(0, 5, -2.6), "body"),
			box(Vector3.new(7.4, 6, 7), Vector3.new(0, 3, 3.6), "body"),
			box(Vector3.new(7.8, 1, 7.4), Vector3.new(0, 1.6, 3.6), "plate"),
			box(Vector3.new(7.8, 1, 7.4), Vector3.new(0, 4.4, 3.6), "plate"),
			box(Vector3.new(8, 2.4, 1), Vector3.new(0, 0.9, -7.8), "plate"), -- ram plate
			box(Vector3.new(7.6, 1.2, 0.4), Vector3.new(0, 6.6, 7), "plate"), -- roof rail for the gunners
		},
	},
	bus = {
		width = 8,
		length = 24,
		wheel = 1.6,
		wheelWidth = 1.2,
		clearance = 1.0,
		seat = Vector3.new(-2.4, 0.5, -9.4),
		passengers = {
			Vector3.new(2.4, 0.5, -6),
			Vector3.new(-2.4, 0.5, -2),
			Vector3.new(2.4, 0.5, -2),
			Vector3.new(-2.4, 0.5, 3),
			Vector3.new(2.4, 0.5, 3),
		},
		roof = 7,
		boxes = {
			box(Vector3.new(8, 3, 24), Vector3.new(0, 1.5, 0), "body"),
			box(Vector3.new(8, 3, 23), Vector3.new(0, 4.5, 0.5), "glass"),
			box(Vector3.new(8.2, 0.8, 24.2), Vector3.new(0, 6.4, 0), "body"),
			box(Vector3.new(8.1, 0.4, 24.1), Vector3.new(0, 2.6, 0), "dark"), -- black stripe
			box(Vector3.new(8.4, 0.8, 0.6), Vector3.new(0, 0.4, -12.2), "dark"),
			box(Vector3.new(0.2, 1.6, 1.6), Vector3.new(-4.2, 3.6, -8.6), "accent"), -- stop sign
		},
	},
	monster = {
		width = 8,
		length = 14,
		wheel = 3,
		wheelWidth = 2.2,
		clearance = 2.6,
		seat = Vector3.new(-1.4, 0.5, -0.8),
		passengers = { Vector3.new(1.4, 0.5, -0.8), Vector3.new(-1.8, 2.0, 4), Vector3.new(1.8, 2.0, 4) },
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
local FRICTIONLESS = PhysicalProperties.new(0.7, 0, 0, 100, 1)

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

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The colour of a car: its paint job, or the factory colour.
local function paintColor(def: Config.CarDef, paintId: string?): Color3
	local paint = paintId and Economy.findPaint(paintId)
	if paint and paint.color then
		return rgb(paint.color)
	end
	return rgb(def.color)
end

type Built = {
	model: Model,
	chassis: Part,
	seat: VehicleSeat?,
	passengers: { Seat },
	turret: Weld,
	turretBase: CFrame,
	muzzle: Attachment,
	paintParts: { BasePart },
	size: Vector3,
}

-- Builds the body. display = a showroom model (anchored, no seats, no movers).
local function build(def: Config.CarDef, color: Color3, ground: CFrame, display: boolean): Built
	local style = STYLES[def.style] or STYLES.van
	local accent = if def.style == "icecream" then Color3.fromRGB(255, 120, 180) elseif def.style == "bus" then Color3.fromRGB(200, 30, 30) else color:Lerp(Color3.new(1, 1, 1), 0.45)

	local model = Instance.new("Model")
	model.Name = def.name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	local chassisY = style.clearance + CHASSIS_HEIGHT / 2
	local chassisCF = ground * CFrame.new(0, chassisY, 0)
	local chassis = newPart(model, "Chassis", Vector3.new(style.width - 0.4, CHASSIS_HEIGHT, style.length), chassisCF, DARK, Enum.Material.Metal)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(2, 0, 0, 100, 1)
	model.PrimaryPart = chassis

	local paintParts: { BasePart } = {}
	local top = chassisCF * CFrame.new(0, CHASSIS_HEIGHT / 2, 0)
	local height = CHASSIS_HEIGHT
	for _, b in style.boxes do
		local c, material = color, Enum.Material.SmoothPlastic
		if b.kind == "dark" then
			c, material = DARK, Enum.Material.Metal
		elseif b.kind == "glass" then
			c, material = GLASS, Enum.Material.Glass
		elseif b.kind == "accent" then
			c = accent
		elseif b.kind == "plate" then
			c, material = color:Lerp(DARK, 0.5), Enum.Material.DiamondPlate
		elseif b.kind == "white" then
			c = Color3.fromRGB(220, 180, 120)
		elseif b.kind == "ball" then
			c = Color3.fromRGB(255, 150, 200)
		end
		local p = newPart(model, if b.kind == "glass" then "Cabin" else "Body", b.size, top * CFrame.new(b.offset), c, material)
		p.Massless = true
		p.CustomPhysicalProperties = FRICTIONLESS
		if b.kind == "glass" then
			p.Transparency = 0.45
		elseif b.kind == "ball" then
			p.Shape = Enum.PartType.Ball
		end
		if b.kind == "body" then
			table.insert(paintParts, p)
		end
		weld(chassis, p)
		height = math.max(height, CHASSIS_HEIGHT + b.offset.Y + b.size.Y / 2)
	end

	-- Wheels: an invisible welded frictionless collider (the car slides on it) and a visible tyre on a Motor6D.
	local wheelY = style.wheel - chassisY
	local wx = style.width / 2 - style.wheelWidth / 2 + 0.3
	local wz = style.length / 2 - style.wheel - 0.5
	for _, offset in { Vector3.new(-wx, wheelY, -wz), Vector3.new(wx, wheelY, -wz), Vector3.new(-wx, wheelY, wz), Vector3.new(wx, wheelY, wz) } do
		local collider = newPart(model, "WheelCollider", Vector3.new(style.wheelWidth, style.wheel * 2, style.wheel * 2), chassisCF * CFrame.new(offset), DARK, Enum.Material.Rubber)
		collider.Shape = Enum.PartType.Cylinder
		collider.Transparency = 1
		collider.CustomPhysicalProperties = FRICTIONLESS
		weld(chassis, collider)
		local tyre = newPart(model, "Tyre", Vector3.new(style.wheelWidth, style.wheel * 2, style.wheel * 2), chassisCF * CFrame.new(offset), Color3.fromRGB(24, 24, 24), Enum.Material.Rubber)
		tyre.Shape = Enum.PartType.Cylinder
		tyre.CanCollide = false
		tyre.CanQuery = false
		tyre.Massless = true
		local motor = Instance.new("Motor6D")
		motor.Name = "WheelMotor"
		motor.Part0 = chassis
		motor.Part1 = tyre
		motor.C0 = CFrame.new(offset)
		motor:SetAttribute("Front", offset.Z < 0)
		motor:SetAttribute("Radius", style.wheel)
		motor.Parent = chassis
		local hub = newPart(model, "Hub", Vector3.new(style.wheelWidth + 0.1, style.wheel, style.wheel), tyre.CFrame, Color3.fromRGB(170, 170, 170), Enum.Material.Metal)
		hub.Shape = Enum.PartType.Cylinder
		hub.CanCollide = false
		hub.CanQuery = false
		hub.Massless = true
		weld(tyre, hub)
		-- A spoke, so the spin shows.
		local spoke = newPart(model, "Spoke", Vector3.new(style.wheelWidth + 0.15, style.wheel * 1.6, 0.35), tyre.CFrame, Color3.fromRGB(90, 90, 90), Enum.Material.Metal)
		spoke.CanCollide = false
		spoke.CanQuery = false
		spoke.Massless = true
		weld(tyre, spoke)
	end

	-- Lights.
	local front = -style.length / 2
	for _, x in { -style.width / 2 + 1, style.width / 2 - 1 } do
		local head = newPart(model, "Headlight", Vector3.new(1.2, 0.6, 0.2), top * CFrame.new(x, 0.5, front - 0.05), Color3.fromRGB(255, 245, 210), Enum.Material.Neon)
		head.CanCollide = false
		head.Massless = true
		weld(chassis, head)
		if not display then
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Front
			spot.Range = 55
			spot.Angle = 50
			spot.Brightness = 3
			spot.Color = Color3.fromRGB(255, 240, 210)
			spot.Parent = head
		end
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

	local built: Built = {
		model = model,
		chassis = chassis,
		seat = nil,
		passengers = {},
		turret = turret,
		turretBase = turretBase,
		muzzle = muzzle,
		paintParts = paintParts,
		size = Vector3.new(style.width, height, style.length),
	}

	if display then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CollisionGroup = "Default"
			end
		end
		return built
	end

	-- The driver's seat (only the owner may sit in it, see watchSeats) and the passenger seats.
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 2)
	seat.CFrame = top * CFrame.new(style.seat)
	seat.Transparency = 1
	seat.CanCollide = false
	seat.CanTouch = false
	seat.Massless = true
	seat.MaxSpeed = 0 -- the legacy motor is unused, client/Drive.luau drives the car
	seat.HeadsUpDisplay = false
	seat.CollisionGroup = "Car"
	seat.Parent = model
	weld(chassis, seat)
	built.seat = seat
	for n, position in style.passengers do
		local p = Instance.new("Seat")
		p.Name = "PassengerSeat"
		p.Size = Vector3.new(2, 0.4, 2)
		p.CFrame = top * CFrame.new(position)
		p.Transparency = 1
		p.CanCollide = false
		p.CanTouch = false
		p.Massless = true
		p.CollisionGroup = "Car"
		p:SetAttribute("Index", n)
		p.Parent = model
		weld(chassis, p)
		table.insert(built.passengers, p)
	end

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

	-- Prompts: the owner drives, everybody else rides (the clients show only the one that fits them).
	type PromptInfo = { name: string, action: string, key: Enum.KeyCode }
	local promptInfos: { PromptInfo } = {
		{ name = "DrivePrompt", action = "Drive", key = Enum.KeyCode.E },
		{ name = "RidePrompt", action = "Ride along", key = Enum.KeyCode.R },
	}
	for _, info in promptInfos do
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = info.name
		prompt.ActionText = info.action
		prompt.ObjectText = def.name
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = info.key
		prompt.Parent = chassis
	end
	return built
end

-- A showroom model for the dealer (anchored, no seats).
function Vehicles.displayModel(def: Config.CarDef, ground: CFrame): Model
	local built = build(def, rgb(def.color), ground, true)
	return built.model
end

local function writeAttributes(car: Car)
	local model = car.model
	model:SetAttribute("MaxSpeed", car.stats.maxSpeed)
	model:SetAttribute("Accel", car.stats.accel)
	model:SetAttribute("Turn", car.stats.turn)
	model:SetAttribute("MaxHealth", car.stats.health)
	model:SetAttribute("Health", math.ceil(car.health))
end

local function eject(seat: Seat | VehicleSeat)
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

-- Whoever gets out steps out next to the car, not inside the cabin.
local function watchSeat(car: Car, seat: Seat | VehicleSeat, side: number, driver: boolean)
	local sitting: Humanoid? = nil
	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local occupant = seat.Occupant
		if occupant then
			if driver and occupant.Parent ~= car.owner.Character then
				eject(seat) -- somebody else's car
			else
				sitting = occupant
			end
			return
		end
		local left = sitting
		sitting = nil
		local character = left and left.Parent
		if left and character and character:IsA("Model") and left.Health > 0 then
			task.defer(function()
				if character.Parent and car.chassis.Parent then
					character:PivotTo(car.chassis.CFrame * CFrame.new(side * (car.size.X / 2 + 3), 2, -1))
				end
			end)
		end
	end)
end

local function watchPrompts(car: Car)
	local drive = car.chassis:FindFirstChild("DrivePrompt") :: ProximityPrompt
	local ride = car.chassis:FindFirstChild("RidePrompt") :: ProximityPrompt
	local function humanoidOf(player: Player): Humanoid?
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return if humanoid and humanoid.Health > 0 then humanoid else nil
	end
	drive.Triggered:Connect(function(player)
		local humanoid = humanoidOf(player)
		if player == car.owner and not car.wrecked and not car.seat.Occupant and humanoid then
			car.seat:Sit(humanoid)
		end
	end)
	ride.Triggered:Connect(function(player)
		local humanoid = humanoidOf(player)
		if player == car.owner or car.wrecked or not humanoid or humanoid.SeatPart then
			return
		end
		for _, seat in car.passengers do
			if not seat.Occupant then
				seat:Sit(humanoid)
				return
			end
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

-- The car the player sits in (any seat) and whether they drive it.
function Vehicles.seatedIn(player: Player): (Car?, boolean, BasePart?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seatPart = humanoid and humanoid.SeatPart
	if not seatPart then
		return nil, false, nil
	end
	for _, car in cars do
		if not car.wrecked and seatPart:IsDescendantOf(car.model) then
			return car, seatPart == car.seat, seatPart
		end
	end
	return nil, false, nil
end

-- The players riding in a car's passenger seats.
function Vehicles.passengersOf(car: Car): { Player }
	local list = {}
	for _, seat in car.passengers do
		local occupant = seat.Occupant
		local player = occupant and Players:GetPlayerFromCharacter(occupant.Parent)
		if player then
			table.insert(list, player)
		end
	end
	return list
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

	local x, z, dx, dz = Map.nearestRoad(from.X, from.Z)
	local direction = Vector3.new(dx, 0, dz)
	if direction:Dot(look) < 0 then
		direction = -direction
	end
	-- Step along the road if another car stands there.
	local position = Vector3.new(x, World.RoadTop + 0.5, z)
	for _ = 1, 6 do
		local free = true
		for _, other in cars do
			if (other.chassis.Position - position).Magnitude < 26 then
				free = false
				break
			end
		end
		if free then
			break
		end
		position += direction * 28
	end
	local ground = CFrame.lookAt(position, position + direction)
	local stats = Economy.carStats(def.id, profile.upgrades)
	local built = build(def, paintColor(def, profile.carPaint[def.id]), ground, false)
	local seat = built.seat :: VehicleSeat
	local car: Car = {
		owner = player,
		id = def.id,
		model = built.model,
		chassis = built.chassis,
		seat = seat,
		passengers = built.passengers,
		turret = built.turret,
		turretBase = built.turretBase,
		muzzle = built.muzzle,
		paintParts = built.paintParts,
		size = built.size,
		stats = stats,
		health = stats.health,
		wrecked = false,
		latched = {},
	}
	car.model.Name = `{player.DisplayName}'s {def.name}`
	car.model:SetAttribute("OwnerId", player.UserId)
	car.model:SetAttribute("OwnerName", player.DisplayName)
	car.model:SetAttribute("CarId", def.id)
	car.model:SetAttribute("SpeedMult", 1)
	writeAttributes(car)
	car.model.Parent = workspace:FindFirstChild("Cars") or workspace
	cars[player] = car
	watchSeat(car, seat, -1, true)
	for _, p in car.passengers do
		watchSeat(car, p, 1, false)
	end
	watchPrompts(car)

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
				seat:Sit(humanoid)
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

-- A new paint job on the live car.
function Vehicles.repaint(player: Player)
	local car = Vehicles.get(player)
	local profile = PlayerData.get(player)
	local def = car and Economy.findCar(car.id)
	if not car or not profile or not def then
		return
	end
	local color = paintColor(def, profile.carPaint[car.id])
	for _, p in car.paintParts do
		p.Color = color
	end
end

-- A job modifier (HEAVY LOAD) slows the car down; the owner's client reads the attribute.
function Vehicles.setSpeedMultiplier(player: Player, multiplier: number)
	local car = Vehicles.get(player)
	if car then
		car.model:SetAttribute("SpeedMult", multiplier)
	end
end

local function wreck(car: Car, reason: string)
	car.wrecked = true
	eject(car.seat)
	for _, seat in car.passengers do
		eject(seat)
	end
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
	Vehicles.onWrecked(car.owner, car, reason)
	task.delay(5, function()
		if cars[car.owner] == car then
			cars[car.owner] = nil
		end
		car.model:Destroy()
	end)
end

function Vehicles.damage(car: Car, amount: number, reason: string?)
	if car.wrecked or amount <= 0 then
		return
	end
	car.health = math.max(0, car.health - amount)
	car.model:SetAttribute("Health", math.ceil(car.health))
	if car.health <= 0 then
		wreck(car, reason or "Your car was destroyed!")
	end
end

function Vehicles.repair(car: Car, share: number)
	if car.wrecked then
		return
	end
	car.health = math.min(car.stats.health, car.health + car.stats.health * share)
	car.model:SetAttribute("Health", math.ceil(car.health))
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
	RunService.Heartbeat:Connect(function(dt)
		for _, car in cars do
			if car.wrecked then
				continue
			end
			local position = car.chassis.Position
			-- Repairs in the depot yard and in Wrench Garage: 15 % of the health per second.
			if car.health < car.stats.health and World.canRepair(position) then
				Vehicles.repair(car, 0.15 * dt)
			end
			-- Drove into the water (or off the world).
			if position.Y < -7 then
				Vehicles.damage(car, math.huge, "Your car sank!")
			end
		end
	end)
end

return Vehicles
