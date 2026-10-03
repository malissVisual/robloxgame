--!strict
-- Animates the zombies on this client: a shambling walk (legs swing with the speed, arms sway out in front),
-- a twitchy head, and a frantic clawing for the ones hanging on a car. Only joint transforms, no animation assets.

local RunService = game:GetService("RunService")

local ZombieAnimator = {}

type Rig = {
	root: BasePart,
	humanoid: Humanoid,
	neck: Motor6D?,
	leftArm: Motor6D?,
	rightArm: Motor6D?,
	leftLeg: Motor6D?,
	rightLeg: Motor6D?,
	phase: number,
	stride: number, -- walking phase, advances with the speed
}

local rigs: { [Model]: Rig } = {}
local RANGE = 220

local function find(model: Model, name: string): Motor6D?
	local motor = model:FindFirstChild(name, true)
	return if motor and motor:IsA("Motor6D") then motor else nil
end

local function rigOf(model: Model): Rig?
	local rig = rigs[model]
	if rig then
		return rig
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return nil
	end
	rig = {
		root = root,
		humanoid = humanoid,
		neck = find(model, "Neck"),
		leftArm = find(model, "Left Shoulder"),
		rightArm = find(model, "Right Shoulder"),
		leftLeg = find(model, "Left Hip"),
		rightLeg = find(model, "Right Hip"),
		phase = math.random() * 10,
		stride = 0,
	}
	rigs[model] = rig
	model.Destroying:Connect(function()
		rigs[model] = nil
	end)
	return rig
end

local function set(motor: Motor6D?, cframe: CFrame)
	if motor and motor.Parent then
		motor.Transform = cframe
	end
end

local function step(dt: number)
	local folder = workspace:FindFirstChild("Zombies")
	local camera = workspace.CurrentCamera
	if not folder or not camera then
		return
	end
	local eye = camera.CFrame.Position
	local t = os.clock()
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local rig = rigOf(model)
		if not rig or rig.humanoid.Health <= 0 then
			continue
		end
		if (rig.root.Position - eye).Magnitude > RANGE then
			continue
		end
		local p = rig.phase + t
		if model:GetAttribute("LatchedTo") then
			-- Clawing at the car.
			set(rig.leftArm, CFrame.Angles(math.sin(p * 18) * 0.6, 0, 0))
			set(rig.rightArm, CFrame.Angles(math.sin(p * 18 + 2) * 0.6, 0, 0))
			set(rig.leftLeg, CFrame.Angles(math.sin(p * 6) * 0.5, 0, 0))
			set(rig.rightLeg, CFrame.Angles(-math.sin(p * 6) * 0.5, 0, 0))
			set(rig.neck, CFrame.Angles(math.sin(p * 9) * 0.25, 0, 0))
			continue
		end
		local velocity = rig.root.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local amount = math.clamp(speed / 12, 0, 1)
		rig.stride += dt * (2 + speed * 0.45)
		local swing = math.sin(rig.stride) * 0.8 * amount
		set(rig.leftLeg, CFrame.Angles(swing, 0, 0))
		set(rig.rightLeg, CFrame.Angles(-swing, 0, 0))
		set(rig.leftArm, CFrame.Angles(math.sin(p * 2.1) * 0.15 - swing * 0.2, 0, math.sin(p * 1.3) * 0.1))
		set(rig.rightArm, CFrame.Angles(math.sin(p * 2.4 + 1) * 0.15 + swing * 0.2, 0, math.sin(p * 1.7) * 0.1))
		set(rig.neck, CFrame.Angles(math.sin(p * 3.3) * 0.1, math.sin(p * 0.7) * 0.3, math.sin(p * 5) * 0.06))
	end
end

function ZombieAnimator.start()
	RunService.Stepped:Connect(function(_time, dt)
		step(dt)
	end)
end

return ZombieAnimator
