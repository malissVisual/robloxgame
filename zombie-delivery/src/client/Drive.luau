--!strict
-- Drives the local player's car. The client is the car's network owner, so it sets the chassis movers itself:
-- the LinearVelocity "Drive" (speed along the car's nose) and the AngularVelocity "Steer" (turning).
-- Input comes from the VehicleSeat (WASD / arrows, gamepad, the mobile thumbstick), with a WASD fallback.
-- 3.2: while the car's back is open (the attribute BackOpen, server/Vehicles.luau) the throttle stays at 0 and a
-- toast says to close it first (Drive.notify, set by Main to Hud.toast).
-- 4.0: pulling away follows a torque curve (shared/Economy.luau Economy.torque): a heavy van (the Rusty Van: accel 11)
-- pulls away slowly from a standstill, is strongest in the mid-range and creeps up to its top speed; the speed always
-- changes smoothly (no jumps). Braking and coasting stay as they were.
-- 5.1: a bike (the car's attribute Bike, server/Vehicles.luau) pedals away at once (no torque curve: full push from a
-- standstill), coasts on longer, steers already at walking pace and backs up slowly (you walk it back).
-- 5.4, fuel (server/Fuel.luau writes the car's attributes Tank and Fuel; shared/FuelMath.luau): with an empty tank the
-- top speed is Config.Fuel.CrawlSpeed at most (FuelMath.topSpeed: the nitro and the admin's boost too) and a toast says
-- so once ("Out of fuel — crawl to a pump or call a tow (phone)"); under Config.Fuel.Low of the tank a soft LOW FUEL
-- toast, once (again only after a refill). A bike has no tank.
-- 6.10, the E-Scooter (the car's attributes Bike and BikeStand; a ZDC RIDE rental too) rides on its own numbers
-- (Config.Scooter through shared/ScooterRide.luau): the steering ramps in (no snap) and turns quickly at walking pace,
-- easing off toward the top speed; a firm brake on S, a long coast. (6.14.2: its wheelie is gone, the owner: "take the
-- wheelie away, it looks silly".)
-- 6.14.1 (the owner: "a more pleasant ride on the scooter"): a gentler steering ramp, a calmer middle and a less lazy top
-- of the turn, a soft first push and a glide into the top speed (ScooterRide.pull), a softer brake, a longer coast, the
-- carve (its way follows its nose a touch later).
-- 6.16: Drive.throttle() says the driver's throttle (-1 … 1) for the engine's note (client/Sounds.luau); only read, the
-- driving is as it was.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Map = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Map"))
local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))
local FuelMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FuelMath"))
local ScooterRide = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ScooterRide"))

local Drive = {}

local player = Players.LocalPlayer
local speed = 0 -- signed, along the nose
local steerInput = 0
local throttleInput = 0 -- 6.16: the driver's throttle (-1 … 1) this step
local boostUntil = 0
local boostMultiplier = 1
local backToldAt = -math.huge -- the "close the back" toast, at most every few seconds
local fuelTold = { car = nil :: Model?, empty = false, low = false } -- 5.4: the fuel toasts already given for this car
local turnSaid = 0 -- 6.11: when the Studio diagnostic of a slow scooter turn was last printed

-- Set by Main (Hud.toast). The fallback is Roblox's own notification.
Drive.notify = nil :: ((text: string) -> ())?

local function tell(text: string)
	local notify = Drive.notify
	if notify then
		notify(text)
		return
	end
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Zombie Delivery", Text = text, Duration = 3 })
	end)
end

-- 5.9.2: your car, kept: looked for again only when workspace.Cars gains or loses a car (streaming too), or a car's
-- OwnerId or Health changes (the HUD and the visuals ask every frame).
local carWatch = { folder = nil :: Instance?, dirty = true, mine = nil :: Model? }

local function watchCars(folder: Instance)
	carWatch.folder = folder
	carWatch.dirty = true
	local function changed()
		carWatch.dirty = true
	end
	local function hook(child: Instance)
		changed()
		child.AttributeChanged:Connect(function(name: string)
			if name == "OwnerId" or name == "Health" then
				changed()
			end
		end)
	end
	for _, child in folder:GetChildren() do
		hook(child)
	end
	folder.ChildAdded:Connect(hook)
	folder.ChildRemoved:Connect(changed)
	folder.AncestryChanged:Connect(changed)
end

function Drive.myCar(): Model?
	local folder = carWatch.folder
	if not folder or folder.Parent ~= workspace then
		local cars = workspace:FindFirstChild("Cars")
		if not cars then
			return nil
		end
		if cars ~= folder then
			watchCars(cars)
		end
		folder = cars
	end
	if carWatch.dirty then
		carWatch.dirty = false
		carWatch.mine = nil
		for _, car in (folder :: Instance):GetChildren() do
			if car:IsA("Model") and car:GetAttribute("OwnerId") == player.UserId and (car:GetAttribute("Health") or 0) > 0 then
				carWatch.mine = car
				break
			end
		end
	end
	local mine = carWatch.mine
	if mine and mine.Parent ~= folder then
		carWatch.dirty = true -- (gone between the signals: look again next time)
		return nil
	end
	return mine
end

function Drive.isDriving(): boolean
	local car = Drive.myCar()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return car ~= nil and humanoid ~= nil and humanoid.SeatPart ~= nil and humanoid.SeatPart:IsDescendantOf(car)
end

-- The car the local player sits in (any seat) and whether they drive it.
function Drive.seatedCar(): (Model?, boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if not seat then
		return nil, false
	end
	local car = seat.Parent
	if car and car:IsA("Model") and car:GetAttribute("OwnerId") ~= nil then
		return car, seat.Name == "DriverSeat"
	end
	return nil, false
end

-- 3.10: getting in or out (client/CarBoarding.luau moves the body; client/CameraRig.luau eases the camera between
-- the walk and the car meanwhile and leaves the walk alone). into: getting in (false: getting out).
local boardingCar: Model? = nil
local boardingInto = false
-- Getting out, the local door opens at once (before the server's DoorOpenAt arrives): client/CarVisuals.luau.
local heldCar: Model? = nil
local heldDoor = 0
local heldUntil = 0

function Drive.setBoarding(car: Model?, into: boolean)
	boardingCar = car
	boardingInto = into
end

function Drive.boardingCar(): (Model?, boolean)
	local car = boardingCar
	if car and not car.Parent then
		boardingCar = nil
		return nil, false
	end
	return car, boardingInto
end

function Drive.holdDoor(car: Model, door: number, seconds: number)
	heldCar, heldDoor, heldUntil = car, door, os.clock() + seconds
end

function Drive.doorHeld(car: Model, door: number): boolean
	return heldCar == car and heldDoor == door and os.clock() < heldUntil
end

function Drive.speed(): number
	return speed
end

-- -1 … 1, the local driver's steering (for the front wheels).
function Drive.steer(): number
	return steerInput
end

-- 6.16: -1 … 1, the local driver's throttle (S brakes or reverses: < 0); 0 when nobody drives.
function Drive.throttle(): number
	return throttleInput
end

function Drive.boosting(): boolean
	return os.clock() < boostUntil
end

-- Nitro: `seconds` of a higher top speed.
function Drive.boost(seconds: number, multiplier: number)
	boostUntil = os.clock() + seconds
	boostMultiplier = multiplier
	speed *= 1.15
end

-- Hit something heavy: keep this share of the speed.
function Drive.bump(keep: number)
	speed *= keep
end

local function keyAxis(positive: { Enum.KeyCode }, negative: { Enum.KeyCode }): number
	if UserInputService:GetFocusedTextBox() then
		return 0
	end
	local value = 0
	for _, key in positive do
		if UserInputService:IsKeyDown(key) then
			value += 1
			break
		end
	end
	for _, key in negative do
		if UserInputService:IsKeyDown(key) then
			value -= 1
			break
		end
	end
	return value
end

local function moveToward(value: number, target: number, step: number): number
	if value < target then
		return math.min(value + step, target)
	end
	return math.max(value - step, target)
end

local function step(dt: number)
	local car = Drive.myCar()
	local chassis = car and car.PrimaryPart
	throttleInput = 0
	if not car or not chassis then
		speed = 0
		return
	end
	local linear = chassis:FindFirstChild("Drive") :: LinearVelocity?
	local angular = chassis:FindFirstChild("Steer") :: AngularVelocity?
	local seat = car:FindFirstChild("DriverSeat") :: VehicleSeat?
	if not linear or not angular or not seat then
		return
	end

	local throttle, steer = 0, 0
	if Drive.isDriving() then
		throttle, steer = seat.ThrottleFloat, seat.SteerFloat
		if throttle == 0 then
			throttle = keyAxis({ Enum.KeyCode.W, Enum.KeyCode.Up }, { Enum.KeyCode.S, Enum.KeyCode.Down })
		end
		if steer == 0 then
			steer = keyAxis({ Enum.KeyCode.D, Enum.KeyCode.Right }, { Enum.KeyCode.A, Enum.KeyCode.Left })
		end
		-- 3.2: the back is open: the car stays where it is.
		if throttle ~= 0 and car:GetAttribute("BackOpen") == true then
			throttle = 0
			local now = os.clock()
			if now - backToldAt > 4 then
				backToldAt = now
				tell("Close the back first: get out and press E at the back.")
			end
		end
	end

	throttleInput = throttle
	local maxSpeed = (car:GetAttribute("MaxSpeed") or 60) :: number * ((car:GetAttribute("SpeedMult") or 1) :: number)
	local accel = (car:GetAttribute("Accel") or 26) :: number
	if player:GetAttribute("AdminCarBoost") == true then
		-- 4.5, the admin's CAR BOOST (the player attribute, only server/Admin.luau sets it): twice the top speed.
		maxSpeed *= 2
		accel *= 1.6
	end
	if Drive.boosting() and throttle > 0 then
		maxSpeed *= boostMultiplier
		accel *= 2.5
	end
	-- 5.4: an empty tank crawls (the toasts once each: empty, low; again only after a refill).
	local tank, fuel = car:GetAttribute("Tank"), car:GetAttribute("Fuel")
	if type(tank) == "number" and type(fuel) == "number" and tank > 0 then
		maxSpeed = FuelMath.topSpeed(maxSpeed, fuel, tank)
		if fuelTold.car ~= car then
			fuelTold.car, fuelTold.empty, fuelTold.low = car, false, false
		end
		local empty, low = FuelMath.isEmpty(fuel), FuelMath.isLow(fuel, tank)
		if Drive.isDriving() and empty and not fuelTold.empty then
			fuelTold.empty, fuelTold.low = true, true
			tell("Out of fuel — crawl to a pump or call a tow (phone)")
		elseif Drive.isDriving() and low and not empty and not fuelTold.low then
			fuelTold.low = true
			tell("LOW FUEL · a gas station is on the map (⛽), or use a jerry can")
		end
		fuelTold.empty = fuelTold.empty and empty
		fuelTold.low = fuelTold.low and low
	end
	-- 6.10: the E-Scooter's own handling: the steering ramps (no snap)
	local scooter = car:GetAttribute("Bike") == true and car:GetAttribute("BikeStand") == true
	local baseMax = (car:GetAttribute("MaxSpeed") or 32) :: number -- (the curve on its own top speed, not a boost's)
	if scooter then
		steer = ScooterRide.steerStep(steerInput, steer, dt)
	end
	steerInput = steer
	local turn = (car:GetAttribute("Turn") or 1.8) :: number

	local look = chassis.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then
		return
	end
	look = look.Unit

	-- Against a wall the real speed drops: do not keep a big speed that would shoot the car off when it turns away.
	-- (6.11: a bike's or a scooter's by how fast it really goes, not only along its nose: in a quick turn the nose leads
	-- the way it moves for a moment, and that share was taken off the speed in every turn: "it slows down so much when
	-- I turn")
	local moving = chassis.AssemblyLinearVelocity
	local actual = moving:Dot(look)
	if car:GetAttribute("Bike") == true then
		local flat = Vector3.new(moving.X, 0, moving.Z).Magnitude
		actual = if actual >= 0 then flat else -flat
	end
	if math.abs(speed) > math.abs(actual) + 8 then
		speed = actual + (if speed > 0 then 8 else -8)
	end

	local bike = car:GetAttribute("Bike") == true
	local target = 0
	if throttle > 0 then
		target = maxSpeed * throttle
	elseif throttle < 0 then
		target = maxSpeed * (if bike then 0.2 else 0.45) * throttle
	end
	local rate = accel
	if throttle == 0 then
		rate = accel * (if bike then 0.4 else 0.7) -- coasting
	elseif math.abs(speed) > 1 and math.sign(target) ~= math.sign(speed) then
		rate = accel * 2.5 -- braking
	elseif math.abs(target) > math.abs(speed) and not bike then
		-- 4.0: pulling away, the torque curve: soft from a standstill, strong in the mid-range, soft again at the top.
		rate = accel * Economy.torque(math.abs(speed) / math.max(1, maxSpeed))
	end
	if scooter then
		target, rate = ScooterRide.drive(speed, throttle, maxSpeed, accel) -- 6.10: its brake, coast and walk back
	end
	speed = moveToward(speed, target, rate * dt)

	-- On ice (and a little on snow) the car does not go where it points at once: it slides.
	local velocity = look * speed
	local position = chassis.Position
	local traction = if Map.onIce(position.X, position.Z) then 1.3 elseif Map.isWinter(position.X, position.Z) then 6 else 0
	if traction > 0 then
		local current = chassis.AssemblyLinearVelocity
		current = Vector3.new(current.X, 0, current.Z)
		velocity = current + (velocity - current) * math.min(1, traction * dt)
	elseif scooter and math.abs(speed) > 1 then
		-- 6.14.1, the carve: the scooter's way follows its nose a touch later (Config.Scooter.Carve), never faster than
		-- it goes: a flowing turn instead of a cursor turning on the spot
		local current = chassis.AssemblyLinearVelocity
		current = Vector3.new(current.X, 0, current.Z)
		if current.Magnitude > 1 then
			local blended = current:Lerp(velocity, ScooterRide.carve(dt))
			velocity = if blended.Magnitude > 0.01 then blended.Unit * math.abs(speed) else velocity
		end
	end
	linear.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	local grip = math.clamp(math.abs(speed) / (if bike then 5 else 12), 0, 1)
	local yaw = -steer * turn * grip * (if speed >= 0 then 1 else -1)
	if scooter then
		-- 6.10: quick at walking pace, calm at the top speed
		yaw = -steer * ScooterRide.turnRate(speed, baseMax, turn) * (if speed >= 0 then 1 else -1)
	end
	angular.AngularVelocity = Vector3.new(0, yaw, 0)
	if scooter and RunService:IsStudio() then
		-- 6.11, Studio only: a scooter that is much slower than it should be while it turns says so in the Output (at
		-- most every 2 s): the numbers to find what holds it back if a turn still slows it
		local flat = Vector3.new(moving.X, 0, moving.Z).Magnitude
		local now = os.clock()
		if math.abs(steer) > 0.3 and throttle > 0 and flat > 3 and flat < speed * 0.75 and now - turnSaid > 2 then
			turnSaid = now
			print(string.format("[Drive] scooter in a turn: %.1f studs/s, should be %.1f (along the nose %.1f, top %.0f); steering %.2f, turning %.2f rad/s",
				flat, speed, moving:Dot(look), maxSpeed, steer, chassis.AssemblyAngularVelocity.Y))
		end
	end
end

function Drive.start()
	RunService.Heartbeat:Connect(step)
end

return Drive
