--!strict
-- What every client does for every car: spins the tyres with the speed and turns the front ones, shows only the
-- prompt that fits (Drive on your own car, Ride along on a friend's car with a free seat) and puts the owner's
-- name over other players' cars.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Drive = require(script.Parent.Drive)

local CarVisuals = {}

type Wheel = { motor: Motor6D, front: boolean, radius: number }
type CarState = { wheels: { Wheel }, spin: number, steer: number, tagged: boolean }

local player = Players.LocalPlayer
local states: { [Model]: CarState } = {}
local RANGE = 260

local function stateOf(car: Model): CarState?
	local state = states[car]
	if state then
		return state
	end
	local chassis = car.PrimaryPart
	if not chassis then
		return nil
	end
	local wheels: { Wheel } = {}
	for _, child in chassis:GetChildren() do
		if child:IsA("Motor6D") and child.Name == "WheelMotor" then
			table.insert(wheels, {
				motor = child,
				front = child:GetAttribute("Front") == true,
				radius = (child:GetAttribute("Radius") or 1.3) :: number,
			})
		end
	end
	state = { wheels = wheels, spin = 0, steer = 0, tagged = false }
	states[car] = state
	car.Destroying:Connect(function()
		states[car] = nil
	end)
	return state
end

local function nameTag(car: Model, chassis: BasePart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "OwnerTag"
	gui.Size = UDim2.fromOffset(200, 30)
	gui.StudsOffset = Vector3.new(0, 10, 0)
	gui.MaxDistance = 160
	gui.LightInfluence = 0
	gui.Parent = chassis
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = `{car:GetAttribute("OwnerName") or "?"}'s car`
	label.TextColor3 = Color3.fromRGB(140, 210, 255)
	label.TextStrokeTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.Parent = gui
end

local function freeSeat(car: Model): boolean
	for _, child in car:GetChildren() do
		if child:IsA("Seat") and child.Name == "PassengerSeat" and child.Occupant == nil then
			return true
		end
	end
	return false
end

local function allCars(): { Instance }
	local list = {}
	for _, name in { "Cars", "BanditCars" } do
		local folder = workspace:FindFirstChild(name)
		if folder then
			for _, car in folder:GetChildren() do
				table.insert(list, car)
			end
		end
	end
	return list
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local eye = camera.CFrame.Position
	local seatedIn = Drive.seatedCar()
	for _, car in allCars() do
		if not car:IsA("Model") then
			continue
		end
		local chassis = car.PrimaryPart
		local state = stateOf(car)
		if not chassis or not state then
			continue
		end
		local mine = car:GetAttribute("OwnerId") == player.UserId

		-- Prompts.
		local drive = chassis:FindFirstChild("DrivePrompt")
		if drive and drive:IsA("ProximityPrompt") then
			drive.Enabled = mine and seatedIn ~= car
		end
		local ride = chassis:FindFirstChild("RidePrompt")
		if ride and ride:IsA("ProximityPrompt") then
			ride.Enabled = not mine and seatedIn == nil and freeSeat(car)
		end
		if not mine and not state.tagged and car:GetAttribute("OwnerId") ~= nil then
			state.tagged = true
			nameTag(car, chassis)
		end

		-- Wheels.
		if (chassis.Position - eye).Magnitude > RANGE then
			continue
		end
		local forward = chassis.AssemblyLinearVelocity:Dot(chassis.CFrame.LookVector)
		local targetSteer: number
		if mine and Drive.isDriving() then
			targetSteer = -Drive.steer() * 0.45
		else
			targetSteer = math.clamp(chassis.AssemblyAngularVelocity.Y * 0.35, -0.45, 0.45) * (if forward >= 0 then 1 else -1)
		end
		state.steer += (targetSteer - state.steer) * math.min(1, dt * 10)
		for _, wheel in state.wheels do
			if not wheel.motor.Parent then
				continue
			end
			local spin = state.spin * 1.3 / wheel.radius
			local turn = if wheel.front then CFrame.Angles(0, state.steer, 0) else CFrame.identity
			wheel.motor.Transform = turn * CFrame.Angles(spin, 0, 0)
		end
		state.spin -= forward / 1.3 * dt
	end
end

function CarVisuals.start()
	RunService.Stepped:Connect(function(_time, dt)
		step(dt)
	end)
end

return CarVisuals
