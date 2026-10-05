--!strict
-- What every client does for every car: spins the tyres with the speed and turns the front ones, shows only the
-- prompt that fits (Drive on your own car, Ride along on a friend's car with a free seat) and puts the owner's
-- name over other players' cars.
-- 3.2: swings the back that opens (rear doors, a tailgate, a trunk lid, a ramp: the Motor6Ds "BackHinge" on the
-- chassis, server/Vehicles.luau) toward the car's attribute BackOpen, a short eased swing.
-- The back's prompt shows only to the owner and the crew of the owner's job (the attribute BackCrew, server/Cargo.luau).
-- 3.6: the owner's name sits on a cream pill in ink (Theme.Postage.pill), readable over a night street and a sunny one.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Drive = require(script.Parent.Drive)
local Theme = require(script.Parent.Theme)

local CarVisuals = {}

type Wheel = { motor: Motor6D, front: boolean, radius: number }
type Hinge = { motor: Motor6D, axis: Vector3, angle: number } -- angle: the open turn in radians
type CarState = {
	wheels: { Wheel },
	hinges: { Hinge },
	back: number,
	spin: number,
	steer: number,
	tagged: boolean,
	backReach: number?, -- the BackPrompt's own reach (the server's), before it was hidden here
}

local player = Players.LocalPlayer
local states: { [Model]: CarState } = {}
local RANGE = 260
local BACK_TIME = 0.45 -- seconds for the back to swing open or shut

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
	local hinges: { Hinge } = {}
	for _, child in chassis:GetChildren() do
		if child:IsA("Motor6D") and child.Name == "WheelMotor" then
			table.insert(wheels, {
				motor = child,
				front = child:GetAttribute("Front") == true,
				radius = (child:GetAttribute("Radius") or 1.3) :: number,
			})
		elseif child:IsA("Motor6D") and child.Name == "BackHinge" then
			local angle = child:GetAttribute("Angle")
			table.insert(hinges, {
				motor = child,
				axis = if child:GetAttribute("Axis") == "X" then Vector3.xAxis else Vector3.yAxis,
				angle = math.rad(if type(angle) == "number" then angle else 90),
			})
		end
	end
	state = { wheels = wheels, hinges = hinges, back = 0, spin = 0, steer = 0, tagged = false, backReach = nil }
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
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.Position = UDim2.fromScale(0.5, 0)
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundColor3 = Theme.Postage.pill
	label.BackgroundTransparency = 0.05
	label.Text = `{car:GetAttribute("OwnerName") or "?"}'s car`
	label.TextColor3 = Theme.Postage.ink
	label.Font = Theme.HeadingFont
	label.TextSize = 15
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = label
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Theme.Postage.line
	stroke.Parent = label
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = label
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
		-- 3.2: the back's prompt only for the owner and the crew of the owner's job (the car's BackCrew, server/Cargo.luau);
		-- out of reach for everybody else, so a stranger's car does not take the E. (Enabled is the server's: one E at a time.)
		local door = chassis:FindFirstChild("CargoDoor")
		local back = door and door:FindFirstChild("BackPrompt")
		if back and back:IsA("ProximityPrompt") then
			local crew = car:GetAttribute("BackCrew")
			local usable = mine or (type(crew) == "string" and string.find(`,{crew},`, `,{player.UserId},`, 1, true) ~= nil)
			local reach: number = state.backReach or back.MaxActivationDistance
			state.backReach = reach
			local want = if usable then reach else 0
			if back.MaxActivationDistance ~= want then
				back.MaxActivationDistance = want
			end
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

		-- 3.2: the back swings toward BackOpen (eased); held there every frame while it is open.
		if #state.hinges > 0 then
			local target = if car:GetAttribute("BackOpen") == true then 1 else 0
			local before = state.back
			if before ~= target then
				state.back = if target > before then math.min(target, before + dt / BACK_TIME) else math.max(target, before - dt / BACK_TIME)
			end
			if state.back > 0 or before > 0 then
				local t = state.back * state.back * (3 - 2 * state.back)
				for _, hinge in state.hinges do
					if hinge.motor.Parent then
						hinge.motor.Transform = CFrame.fromAxisAngle(hinge.axis, hinge.angle * t)
					end
				end
			end
		end
	end
end

function CarVisuals.start()
	RunService.Stepped:Connect(function(_time, dt)
		step(dt)
	end)
end

return CarVisuals
