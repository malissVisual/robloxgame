--!strict
-- Smooth traffic on this client. The server (server/Traffic.luau) steps the anchored civilian cars along their lanes
-- 10 times a second (the folder workspace.Traffic carries the step as the attribute Tick); here every car glides
-- from where it is shown to the server's newest position over one step, every frame, and its wheels spin and steer
-- with the way it moves. The picture runs about one step behind the server, without jumps.
--
-- How a new server position is noticed without a second channel: this client writes the car's CFrame itself every
-- frame, so when the chassis holds something other than what was written last, the server's update has arrived in
-- between. It writes before the physics too (PreSimulation), so your car collides with the car where you see it.
-- Far away (beyond RANGE) the cars are left as the server places them.

local RunService = game:GetService("RunService")

local TrafficAnimator = {}

type Wheel = { motor: Motor6D, front: boolean, radius: number }
type Track = {
	chassis: BasePart,
	from: CFrame, -- where the glide started
	to: CFrame, -- the server's newest position
	at: number, -- when it arrived
	shown: CFrame,
	wrote: CFrame?, -- what this client wrote last
	wheels: { Wheel },
	spin: number,
	steer: number,
	lastPosition: Vector3,
	lastLook: Vector3,
}

local RANGE = 450 -- smooth the cars within this distance of the camera
local WHEEL_RANGE = 220
local SNAP = 45 -- a jump this big (a new car, a wreck knocked aside far): no glide

local tracks: { [Model]: Track } = {}
local models: { [Model]: boolean } = {}
local tick = 0.1
local started = false

local function trackOf(model: Model): Track?
	local track = tracks[model]
	if track then
		return track
	end
	local chassis = model.PrimaryPart
	if not chassis then
		return nil -- not streamed in yet
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
	local now = chassis.CFrame
	track = {
		chassis = chassis,
		from = now,
		to = now,
		at = os.clock(),
		shown = now,
		wrote = nil,
		wheels = wheels,
		spin = 0,
		steer = 0,
		lastPosition = now.Position,
		lastLook = now.LookVector,
	}
	tracks[model] = track
	return track
end

local function forget(model: Model)
	models[model] = nil
	tracks[model] = nil
end

-- The glide: notice a new server position, then place the car between the last two.
local function place(now: number)
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for model in models do
		local track = trackOf(model)
		if not track then
			continue
		end
		local chassis = track.chassis
		if not chassis.Parent then
			forget(model)
			continue
		end
		local current = chassis.CFrame
		if (current.Position - eye).Magnitude > RANGE then
			track.wrote = nil -- left to the server; picked up again when it comes closer
			track.shown, track.from, track.to = current, current, current
			continue
		end
		if track.wrote == nil or current ~= track.wrote then
			if (current.Position - track.shown.Position).Magnitude > SNAP then
				track.shown = current
			end
			track.from = track.shown
			track.to = current
			track.at = now
		end
		local alpha = math.clamp((now - track.at) / tick, 0, 1)
		local cframe = track.from:Lerp(track.to, alpha)
		track.shown = cframe
		if cframe ~= current then
			chassis.CFrame = cframe
		end
		track.wrote = chassis.CFrame
	end
end

-- The wheels roll with the distance the car moved and the front ones turn with its turning.
local function wheels(dt: number)
	if dt <= 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local eye = if camera then camera.CFrame.Position else Vector3.zero
	for _, track in tracks do
		local shown = track.shown
		local moved = shown.Position - track.lastPosition
		local look = shown.LookVector
		local forward = moved:Dot(look) / dt
		local yaw = math.atan2(track.lastLook:Cross(look).Y, track.lastLook:Dot(look)) / dt
		track.lastPosition = shown.Position
		track.lastLook = look
		if (shown.Position - eye).Magnitude > WHEEL_RANGE or #track.wheels == 0 then
			continue
		end
		local target = math.clamp(yaw * 0.35, -0.45, 0.45)
		track.steer += (target - track.steer) * math.min(1, dt * 8)
		track.spin -= forward / 1.3 * dt
		for _, wheel in track.wheels do
			if wheel.motor.Parent then
				local spin = track.spin * 1.3 / wheel.radius
				local turn = if wheel.front then CFrame.Angles(0, track.steer, 0) else CFrame.identity
				wheel.motor.Transform = turn * CFrame.Angles(spin, 0, 0)
			end
		end
	end
end

local function watch(folder: Instance)
	local value = folder:GetAttribute("Tick")
	if type(value) == "number" and value > 0 then
		tick = value
	end
	local function add(child: Instance)
		if child:IsA("Model") then
			models[child] = true
		end
	end
	for _, child in folder:GetChildren() do
		add(child)
	end
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			forget(child)
		end
	end)
end

function TrafficAnimator.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local folder = workspace:WaitForChild("Traffic", 60)
		if not folder then
			return -- no traffic on this server
		end
		watch(folder)
		RunService.RenderStepped:Connect(function()
			place(os.clock())
		end)
		RunService.PreSimulation:Connect(function(dt)
			place(os.clock())
			wheels(dt)
		end)
	end)
end

return TrafficAnimator
