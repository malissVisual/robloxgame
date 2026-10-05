--!strict
-- Drives the local player's car. The client is the car's network owner, so it sets the chassis movers itself:
-- the LinearVelocity "Drive" (speed along the car's nose) and the AngularVelocity "Steer" (turning).
-- Input comes from the VehicleSeat (WASD / arrows, gamepad, the mobile thumbstick), with a WASD fallback.
-- 3.2: while the car's back is open (the attribute BackOpen, server/Vehicles.luau) the throttle stays at 0 and a
-- toast says to close it first (Drive.notify, set by Main to Hud.toast).
-- 4.0: pulling away follows a torque curve (shared/Economy.luau Economy.torque): a heavy van (the Rusty Van: accel 11)
-- pulls away slowly from a standstill, is strongest in the mid-range and creeps up to its top speed; the speed always
-- changes smoothly (no jumps). Braking and coasting stay as they were.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Map = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Map"))
local Economy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Economy"))

local Drive = {}

local player = Players.LocalPlayer
local speed = 0 -- signed, along the nose
local steerInput = 0
local boostUntil = 0
local boostMultiplier = 1
local backToldAt = -math.huge -- the "close the back" toast, at most every few seconds

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

function Drive.myCar(): Model?
	local cars = workspace:FindFirstChild("Cars")
	if not cars then
		return nil
	end
	for _, car in cars:GetChildren() do
		if car:IsA("Model") and car:GetAttribute("OwnerId") == player.UserId and (car:GetAttribute("Health") or 0) > 0 then
			return car
		end
	end
	return nil
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

	local maxSpeed = (car:GetAttribute("MaxSpeed") or 60) :: number * ((car:GetAttribute("SpeedMult") or 1) :: number)
	local accel = (car:GetAttribute("Accel") or 26) :: number
	if Drive.boosting() and throttle > 0 then
		maxSpeed *= boostMultiplier
		accel *= 2.5
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
	local actual = chassis.AssemblyLinearVelocity:Dot(look)
	if math.abs(speed) > math.abs(actual) + 8 then
		speed = actual + (if speed > 0 then 8 else -8)
	end

	local target = 0
	if throttle > 0 then
		target = maxSpeed * throttle
	elseif throttle < 0 then
		target = maxSpeed * 0.45 * throttle
	end
	local rate = accel
	if throttle == 0 then
		rate = accel * 0.7 -- coasting
	elseif math.abs(speed) > 1 and math.sign(target) ~= math.sign(speed) then
		rate = accel * 2.5 -- braking
	elseif math.abs(target) > math.abs(speed) then
		-- 4.0: pulling away, the torque curve: soft from a standstill, strong in the mid-range, soft again at the top.
		rate = accel * Economy.torque(math.abs(speed) / math.max(1, maxSpeed))
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
	end
	linear.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	local grip = math.clamp(math.abs(speed) / 12, 0, 1)
	local yaw = -steer * turn * grip * (if speed >= 0 then 1 else -1)
	angular.AngularVelocity = Vector3.new(0, yaw, 0)
end

function Drive.start()
	RunService.Heartbeat:Connect(step)
end

return Drive
