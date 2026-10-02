--!strict
-- YOUR CHARACTER'S MOVEMENT: sprint and slide, with their own body language (client side only).
--   SPRINT  hold Left Shift (a toggle button on touch / L3 on a gamepad): faster, the body leans into the run,
--           the camera widens, dust kicks up from your feet.
--   SLIDE   C or Left Ctrl (B on a gamepad, a button on touch) while running: you drop low and slide on, leaning
--           back with the lead leg stretched out and a hand on the ground; the speed bleeds off, dust sprays and
--           the camera goes down with you. JUMP during a slide = a SLIDE JUMP: a long leap that keeps the momentum.
-- The poses are procedural: the R15 joints' Transform is overwritten after the animator each frame (Stepped), so
-- the default run / walk animations keep playing underneath and the pose blends in and out. All numbers: CONFIG.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local PlayerMovement = {}

local CONFIG = {
	WalkSpeed = 20, -- the server's walk speed (GameService: 16 × 1.25)
	SprintSpeed = 32,
	SprintFov = 82, -- the camera's field of view while sprinting (normal: 70)
	SprintLean = 0.38, -- radians the body leans forward while sprinting
	StrideRate = 0.55, -- running cycle: radians of the stride phase per stud travelled (faster run = faster legs)
	StrideSwing = 1.05, -- hip swing (radians)
	ArmPump = 1.15, -- shoulder swing (radians)
	SlideStartSpeed = 54, -- the slide starts this fast …
	SlideEndSpeed = 18, -- … and bleeds off to this
	SlideTime = 0.8,
	SlideMinSpeed = 12, -- you have to be moving at least this fast to slide
	SlideCooldown = 0.6,
	SlideCameraDrop = 1.7, -- studs the camera goes down while sliding
	SlideJumpForward = 38, -- a jump during a slide: this much forward speed …
	SlideJumpUp = 46, -- … and this much up
	BlendIn = 0.1, -- seconds a pose takes to blend in / out
	BlendOut = 0.22,
}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

type State = {
	character: Model?,
	humanoid: Humanoid?,
	root: BasePart?,
	joints: { [string]: Motor6D },
	sprintHeld: boolean,
	sprintToggled: boolean, -- touch: the sprint button toggles
	sliding: boolean,
	slideStart: number,
	slideDir: Vector3,
	slideReadyAt: number,
	slideWeight: number, -- 0 … 1 blend of the slide pose
	leanWeight: number, -- 0 … 1 blend of the sprint pose (the procedural run cycle)
	stride: number, -- the run cycle's phase
	trails: { Trail },
	dust: ParticleEmitter?,
	slideDust: ParticleEmitter?,
	slideForce: LinearVelocity?, -- drives the slide (horizontal only; gravity and jumps stay free)
}
local state: State = {
	character = nil,
	humanoid = nil,
	root = nil,
	joints = {},
	sprintHeld = false,
	sprintToggled = false,
	sliding = false,
	slideStart = 0,
	slideDir = Vector3.new(0, 0, -1),
	slideReadyAt = 0,
	slideWeight = 0,
	leanWeight = 0,
	stride = 0,
	trails = {},
	dust = nil,
	slideDust = nil,
	slideForce = nil,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function emitter(parent: Instance, color: Color3, rate: number, size: number, speed: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, size * 1.8) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.35, 0.7)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(60, 25)
	e.Acceleration = Vector3.new(0, 2, 0)
	e.Drag = 3
	e.Rate = rate
	e.LightEmission = 0.1
	e.Enabled = false
	e.Parent = parent
	return e
end

local function bindCharacter(character: Model)
	state.character = character
	state.humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	state.root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	state.sliding = false
	state.slideWeight = 0
	state.leanWeight = 0
	table.clear(state.joints)
	for _, name in { "Root", "Waist", "Neck", "LeftShoulder", "RightShoulder", "LeftElbow", "RightElbow", "LeftHip", "RightHip", "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle" } do
		local joint = character:WaitForChild(if name == "Root" then "LowerTorso" elseif name == "Waist" then "UpperTorso" elseif name == "Neck" then "Head" elseif name == "LeftShoulder" then "LeftUpperArm" elseif name == "RightShoulder" then "RightUpperArm" elseif name == "LeftElbow" then "LeftLowerArm" elseif name == "RightElbow" then "RightLowerArm" elseif name == "LeftHip" then "LeftUpperLeg" elseif name == "RightHip" then "RightUpperLeg" elseif name == "LeftKnee" then "LeftLowerLeg" elseif name == "RightKnee" then "RightLowerLeg" elseif name == "LeftAnkle" then "LeftFoot" else "RightFoot", 5)
		local motor = joint and joint:FindFirstChild(name)
		if motor and motor:IsA("Motor6D") then
			state.joints[name] = motor
		end
	end
	local root = state.root
	if root then
		local feet = Instance.new("Attachment")
		feet.Name = "MovementFeet"
		feet.Position = Vector3.new(0, -root.Size.Y / 2 - 2.6, 0.4)
		feet.Parent = root
		state.dust = emitter(feet, Color3.fromRGB(210, 190, 150), 28, 0.8, 5)
		state.slideDust = emitter(feet, Color3.fromRGB(230, 210, 170), 90, 1.3, 10)
	end
	-- Speed streaks behind the hands and feet while sprinting (Trails between two attachments on each limb).
	table.clear(state.trails)
	for _, limb in { "LeftHand", "RightHand", "LeftFoot", "RightFoot" } do
		local part = character:FindFirstChild(limb)
		if part and part:IsA("BasePart") then
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, 0.25, 0)
			a0.Parent = part
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -0.25, 0)
			a1.Parent = part
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.22
			trail.MinLength = 0.05
			trail.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255), Color3.fromRGB(150, 200, 255))
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			trail.LightEmission = 0.6
			trail.FaceCamera = true
			trail.Enabled = false
			trail.Parent = part
			table.insert(state.trails, trail)
		end
	end
end

local function isGrounded(): boolean
	local humanoid = state.humanoid
	return humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
end

local function sprinting(): boolean
	local humanoid = state.humanoid
	return (state.sprintHeld or state.sprintToggled) and humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
end

local function endSlide(jump: boolean)
	if not state.sliding then
		return
	end
	state.sliding = false
	state.slideReadyAt = os.clock() + CONFIG.SlideCooldown
	if state.slideForce then
		state.slideForce:Destroy()
		state.slideForce = nil
	end
	local humanoid, root = state.humanoid, state.root
	if humanoid then
		humanoid.WalkSpeed = if sprinting() then CONFIG.SprintSpeed else CONFIG.WalkSpeed
		TweenService:Create(humanoid, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CameraOffset = Vector3.zero }):Play()
		if jump and root then
			-- SLIDE JUMP: a long leap that keeps the slide's momentum.
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			root.AssemblyLinearVelocity = state.slideDir * CONFIG.SlideJumpForward + Vector3.new(0, CONFIG.SlideJumpUp, 0)
		end
	end
	if state.slideDust then
		state.slideDust.Enabled = false
	end
end

local function startSlide()
	local humanoid, root = state.humanoid, state.root
	if state.sliding or not humanoid or not root or humanoid.Health <= 0 or os.clock() < state.slideReadyAt or not isGrounded() then
		return
	end
	local velocity = flat(root.AssemblyLinearVelocity)
	if velocity.Magnitude < CONFIG.SlideMinSpeed then
		return
	end
	state.sliding = true
	state.slideStart = os.clock()
	state.slideDir = velocity.Unit
	-- The slide drives itself: a horizontal LinearVelocity on the root (your keys do not steer it; gravity and the
	-- slide jump stay free).
	local attachment = root:FindFirstChild("RootAttachment") or root:FindFirstChildOfClass("Attachment")
	if attachment and attachment:IsA("Attachment") then
		local force = Instance.new("LinearVelocity")
		force.Name = "SlideForce"
		force.Attachment0 = attachment
		force.RelativeTo = Enum.ActuatorRelativeTo.World
		force.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		force.PrimaryTangentAxis = Vector3.new(1, 0, 0)
		force.SecondaryTangentAxis = Vector3.new(0, 0, 1)
		force.MaxForce = 1e6
		force.PlaneVelocity = Vector2.new(state.slideDir.X, state.slideDir.Z) * CONFIG.SlideStartSpeed
		force.Parent = root
		state.slideForce = force
	end
	humanoid.WalkSpeed = CONFIG.SlideStartSpeed
	TweenService:Create(humanoid, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CameraOffset = Vector3.new(0, -CONFIG.SlideCameraDrop, 0) }):Play()
	if state.slideDust then
		state.slideDust.Enabled = true
		state.slideDust:Emit(25)
	end
end

-- Input: sprint (hold; a toggle on touch) and slide; jump during a slide = slide jump.
local function onSprint(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if input.UserInputType == Enum.UserInputType.Touch then
		if inputState == Enum.UserInputState.Begin then
			state.sprintToggled = not state.sprintToggled
		end
	else
		state.sprintHeld = inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.Change
	end
	return Enum.ContextActionResult.Pass
end
local function onSlide(_: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		startSlide()
	end
	return Enum.ContextActionResult.Pass
end

-- The slide pose (Transform of each joint; the body leans back, the lead leg stretched forward, the other tucked
-- under, one hand trailing on the ground, the other up for balance, the head looking ahead).
local SLIDE_POSE: { [string]: CFrame } = {
	Root = CFrame.new(0, -1.35, 0) * CFrame.Angles(0.5, 0, 0.05),
	Waist = CFrame.Angles(-0.12, 0.15, 0),
	Neck = CFrame.Angles(-0.38, -0.12, 0),
	RightHip = CFrame.Angles(1.15, 0, -0.08),
	RightKnee = CFrame.Angles(-0.12, 0, 0),
	RightAnkle = CFrame.Angles(0.35, 0, 0),
	LeftHip = CFrame.Angles(0.55, 0, 0.18),
	LeftKnee = CFrame.Angles(-1.75, 0, 0),
	LeftAnkle = CFrame.Angles(0.25, 0, 0),
	LeftShoulder = CFrame.Angles(-0.55, 0, 0.75),
	LeftElbow = CFrame.Angles(0.15, 0, 0),
	RightShoulder = CFrame.Angles(1.1, 0, -0.35),
	RightElbow = CFrame.Angles(0.6, 0, 0),
}

local function update(dt: number)
	local humanoid, root = state.humanoid, state.root
	if not humanoid or not root or not humanoid.Parent then
		return
	end
	local now = os.clock()
	local run = sprinting()

	-- Speeds.
	if state.sliding then
		local t = math.clamp((now - state.slideStart) / CONFIG.SlideTime, 0, 1)
		local e = 1 - (1 - t) ^ 2
		local slideSpeed = CONFIG.SlideStartSpeed + (CONFIG.SlideEndSpeed - CONFIG.SlideStartSpeed) * e
		humanoid.WalkSpeed = slideSpeed
		if state.slideForce then
			state.slideForce.PlaneVelocity = Vector2.new(state.slideDir.X, state.slideDir.Z) * slideSpeed
		end
		if t >= 1 or humanoid.Health <= 0 then
			endSlide(false)
		elseif not isGrounded() and now - state.slideStart > 0.15 then
			endSlide(false) -- slid off an edge
		end
	elseif humanoid.WalkSpeed ~= CONFIG.WalkSpeed and humanoid.WalkSpeed ~= CONFIG.SprintSpeed then
		-- someone else (the server) set a speed: leave it
	else
		humanoid.WalkSpeed = if run then CONFIG.SprintSpeed else CONFIG.WalkSpeed
	end

	-- Camera: wider while sprinting.
	local fov = if run and not state.sliding then CONFIG.SprintFov else 70
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, dt * 8)

	-- Blends.
	local function approach(value: number, target: number, inTime: number, outTime: number): number
		local rate = dt / (if target > value then inTime else outTime)
		if math.abs(target - value) <= rate then
			return target
		end
		return value + (if target > value then rate else -rate)
	end
	state.slideWeight = approach(state.slideWeight, if state.sliding then 1 else 0, CONFIG.BlendIn, CONFIG.BlendOut)
	state.leanWeight = approach(state.leanWeight, if run and isGrounded() and not state.sliding then 1 else 0, 0.2, 0.25)

	-- The run cycle advances with the distance travelled (the legs never skate).
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	state.stride = (state.stride + speed * dt * CONFIG.StrideRate) % (math.pi * 2)

	-- Dust and the speed streaks.
	local sprintingNow = run and isGrounded() and not state.sliding and speed > CONFIG.WalkSpeed * 0.8
	if state.dust then
		state.dust.Enabled = sprintingNow
	end
	for _, trail in state.trails do
		trail.Enabled = sprintingNow or state.sliding
	end
end

-- One joint of the sprint cycle at stride phase `p` (nil = leave the animation's value).
local function sprintPose(name: string, p: number): CFrame?
	local s, c = math.sin(p), math.cos(p)
	local swing, pump, lean = CONFIG.StrideSwing, CONFIG.ArmPump, CONFIG.SprintLean
	if name == "Root" then
		return CFrame.new(0, 0.18 * math.abs(c) - 0.12, 0) * CFrame.Angles(-lean, 0.14 * s, 0)
	elseif name == "Waist" then
		return CFrame.Angles(-0.06, -0.24 * s, 0)
	elseif name == "Neck" then
		return CFrame.Angles(lean * 0.75, 0.1 * s, 0)
	elseif name == "RightHip" then
		return CFrame.Angles(swing * s, 0, 0)
	elseif name == "LeftHip" then
		return CFrame.Angles(-swing * s, 0, 0)
	elseif name == "RightKnee" then
		return CFrame.Angles(-0.25 - 1.35 * math.max(0, -s) - 0.35 * math.max(0, c), 0, 0)
	elseif name == "LeftKnee" then
		return CFrame.Angles(-0.25 - 1.35 * math.max(0, s) - 0.35 * math.max(0, -c), 0, 0)
	elseif name == "RightAnkle" then
		return CFrame.Angles(0.45 * math.max(0, -s) - 0.15 * math.max(0, s), 0, 0)
	elseif name == "LeftAnkle" then
		return CFrame.Angles(0.45 * math.max(0, s) - 0.15 * math.max(0, -s), 0, 0)
	elseif name == "RightShoulder" then
		return CFrame.Angles(-pump * s + 0.1, 0, -0.12)
	elseif name == "LeftShoulder" then
		return CFrame.Angles(pump * s + 0.1, 0, 0.12)
	elseif name == "RightElbow" then
		return CFrame.Angles(1.25 + 0.3 * math.max(0, -s), 0, 0)
	elseif name == "LeftElbow" then
		return CFrame.Angles(1.25 + 0.3 * math.max(0, s), 0, 0)
	end
	return nil
end

-- The poses, after the animator wrote this frame's Transforms.
local function pose()
	local sw, lw = state.slideWeight, state.leanWeight
	if sw <= 0.001 and lw <= 0.001 then
		return
	end
	for name, joint in state.joints do
		if not joint.Parent then
			continue
		end
		local current = joint.Transform
		if lw > 0.001 then
			-- THE SPRINT: a full procedural run cycle replaces the walk animation (blended by lw): a deep forward
			-- lean, long strides with the knees snapping up behind, the toes pointing, the arms pumping hard with
			-- bent elbows opposite to the legs, the hips and shoulders twisting against each other, a bounce on
			-- every step, the head held level.
			local runPose = sprintPose(name, state.stride)
			if runPose then
				current = current:Lerp(runPose, lw)
			end
		end
		local target = SLIDE_POSE[name]
		if sw > 0.001 and target then
			current = current:Lerp(target, sw)
		end
		joint.Transform = current
	end
end

function PlayerMovement.start()
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)
	ContextActionService:BindAction("MB_Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:SetTitle("MB_Sprint", "RUN")
	ContextActionService:SetPosition("MB_Sprint", UDim2.new(1, -200, 1, -150))
	ContextActionService:BindAction("MB_Slide", onSlide, true, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("MB_Slide", "SLIDE")
	ContextActionService:SetPosition("MB_Slide", UDim2.new(1, -200, 1, -80))
	UserInputService.JumpRequest:Connect(function()
		if state.sliding then
			endSlide(true)
		end
	end)
	RunService.RenderStepped:Connect(update)
	RunService.Stepped:Connect(pose) -- after the animator: overwrite / blend the joints' Transform
end

return PlayerMovement
