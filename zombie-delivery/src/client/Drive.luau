--!strict
-- Drives the local player's car. The client is the car's network owner, so it sets the chassis movers itself:
-- the LinearVelocity "Drive" (speed along the car's nose) and the AngularVelocity "Steer" (turning).
-- Input comes from the VehicleSeat (WASD / arrows, gamepad, the mobile thumbstick), with a WASD fallback.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Drive = {}

local player = Players.LocalPlayer
local speed = 0 -- signed, along the nose

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

function Drive.speed(): number
	return speed
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
	end

	local maxSpeed = (car:GetAttribute("MaxSpeed") or 60) :: number
	local accel = (car:GetAttribute("Accel") or 26) :: number
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
	end
	speed = moveToward(speed, target, rate * dt)

	local velocity = look * speed
	linear.PlaneVelocity = Vector2.new(velocity.X, velocity.Z)
	local grip = math.clamp(math.abs(speed) / 12, 0, 1)
	local yaw = -steer * turn * grip * (if speed >= 0 then 1 else -1)
	angular.AngularVelocity = Vector3.new(0, yaw, 0)
end

function Drive.start()
	RunService.Heartbeat:Connect(step)
end

return Drive
