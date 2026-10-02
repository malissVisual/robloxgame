--!strict
-- YOUR CHARACTER'S MOVEMENT: sprint and slide, with their own body language, effects and buttons (client only).
--   SPRINT  hold Left Shift, or click / tap the SPRINT button (bottom right; it toggles). The walk animation is
--           replaced by a procedural run cycle: a deep lean, long strides with the knees snapping up, the arms
--           pumping with follow-through (the forearms and hands trail and flow), a bounce and a roll on every step,
--           a lean into turns. The camera widens, speed lines rush at the screen edges, streaks trail the hands
--           and feet, dust kicks up.
--   SLIDE   C or Left Ctrl while running, or the SLIDE button: a REAL slide. The body drops to the ground (the
--           hip height goes down, so the whole character is low), slides on with the lead leg stretched and a
--           hand trailing, the speed bleeds off; dust sprays, sparks fly from the heel, scrape marks are left on
--           the floor, the camera goes down. JUMP during a slide = a SLIDE JUMP (a long leap with the momentum).
--   KEYS    the "?" button over the two buttons opens a small card with every key (it shows itself once).
-- The poses overwrite the R15 joints' Transform after the animator (Stepped) and blend in and out. All numbers
-- are in CONFIG.
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PlayerMovement = {}

local CONFIG = {
	WalkSpeed = 20, -- the server's walk speed (GameService: 16 × 1.25)
	SprintSpeed = 32,
	SprintFov = 84, -- the camera's field of view while sprinting (normal: 70)
	SprintLean = 0.42, -- radians the body leans forward at full sprint
	StrideRate = 0.52, -- the run cycle: radians of stride phase per stud travelled (faster run = faster legs)
	StrideSwing = 1.1, -- hip swing (radians)
	ArmPump = 1.25, -- shoulder swing (radians)
	TurnLean = 0.06, -- roll per radian/s of turning (leaning into a curve), at most 0.35
	SlideStartSpeed = 56, -- the slide starts this fast …
	SlideEndSpeed = 16, -- … and bleeds off to this
	SlideTime = 0.85,
	SlideMinSpeed = 12, -- you have to be moving at least this fast to slide
	SlideCooldown = 0.6,
	SlideDrop = 1.35, -- studs the hip height goes down: the body really is on the floor
	SlideCameraDrop = 0.6, -- extra studs the camera goes down
	SlideJumpForward = 40, -- a jump during a slide: this much forward speed …
	SlideJumpUp = 48, -- … and this much up
	BlendIn = 0.09, -- seconds a pose takes to blend in / out
	BlendOut = 0.22,
}

local BG = Color3.fromRGB(24, 26, 36)
local DARK = Color3.fromRGB(16, 18, 26)
local EDGE = Color3.fromRGB(70, 76, 100)
local GOLD = Color3.fromRGB(255, 205, 90)
local GREEN = Color3.fromRGB(80, 200, 120)
local MUTED = Color3.fromRGB(165, 170, 185)
local WHITE = Color3.new(1, 1, 1)

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local JOINT_PARTS: { [string]: string } = {
	Root = "LowerTorso", Waist = "UpperTorso", Neck = "Head",
	LeftShoulder = "LeftUpperArm", RightShoulder = "RightUpperArm", LeftElbow = "LeftLowerArm", RightElbow = "RightLowerArm",
	LeftWrist = "LeftHand", RightWrist = "RightHand",
	LeftHip = "LeftUpperLeg", RightHip = "RightUpperLeg", LeftKnee = "LeftLowerLeg", RightKnee = "RightLowerLeg",
	LeftAnkle = "LeftFoot", RightAnkle = "RightFoot",
}

type State = {
	humanoid: Humanoid?,
	root: BasePart?,
	joints: { [string]: Motor6D },
	baseHip: number,
	sprintHeld: boolean,
	sprintToggled: boolean,
	sliding: boolean,
	slideStart: number,
	slideDir: Vector3,
	slideReadyAt: number,
	slideWeight: number, -- 0 … 1 blend of the slide pose
	runWeight: number, -- 0 … 1 blend of the sprint cycle
	stride: number, -- the run cycle's phase
	turnRoll: number, -- the lean into a turn (smoothed)
	lastYaw: number,
	scrapeAt: number,
	trails: { Trail },
	dust: ParticleEmitter?,
	slideDust: ParticleEmitter?,
	sparks: ParticleEmitter?,
	slideForce: LinearVelocity?,
}
local state: State = {
	humanoid = nil,
	root = nil,
	joints = {},
	baseHip = 2,
	sprintHeld = false,
	sprintToggled = false,
	sliding = false,
	slideStart = 0,
	slideDir = Vector3.new(0, 0, -1),
	slideReadyAt = 0,
	slideWeight = 0,
	runWeight = 0,
	stride = 0,
	turnRoll = 0,
	lastYaw = 0,
	scrapeAt = 0,
	trails = {},
	dust = nil,
	slideDust = nil,
	sparks = nil,
	slideForce = nil,
}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function emitter(parent: Instance, texture: string, color: Color3, rate: number, size: number, speed: number, lifetime: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, size * 1.8) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(lifetime * 0.5, lifetime)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(60, 25)
	e.Acceleration = Vector3.new(0, 2, 0)
	e.Drag = 3
	e.Rate = rate
	e.LightEmission = 0.15
	e.Enabled = false
	e.Parent = parent
	return e
end

local function bindCharacter(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	state.humanoid = humanoid
	state.root = root
	state.sliding = false
	state.slideWeight = 0
	state.runWeight = 0
	state.slideForce = nil
	state.baseHip = if humanoid then humanoid.HipHeight else 2
	table.clear(state.joints)
	for name, partName in JOINT_PARTS do
		local part = character:WaitForChild(partName, 5)
		local motor = part and part:FindFirstChild(name)
		if motor and motor:IsA("Motor6D") then
			state.joints[name] = motor
		end
	end
	if root then
		local feet = Instance.new("Attachment")
		feet.Name = "MovementFeet"
		feet.Position = Vector3.new(0, -root.Size.Y / 2 - state.baseHip + 0.2, 0.4)
		feet.Parent = root
		state.dust = emitter(feet, "rbxasset://textures/particles/smoke_main.dds", Color3.fromRGB(210, 190, 150), 30, 0.8, 5, 0.7)
		state.slideDust = emitter(feet, "rbxasset://textures/particles/smoke_main.dds", Color3.fromRGB(230, 210, 170), 110, 1.4, 11, 0.8)
		local heel = Instance.new("Attachment")
		heel.Name = "MovementHeel"
		heel.Position = Vector3.new(0.4, -root.Size.Y / 2 - state.baseHip + 0.3, -1.6)
		heel.Parent = root
		local sparks = emitter(heel, "rbxasset://textures/particles/sparkles_main.dds", Color3.fromRGB(255, 190, 90), 70, 0.35, 16, 0.35)
		sparks.Acceleration = Vector3.new(0, -30, 0)
		sparks.LightEmission = 1
		sparks.SpreadAngle = Vector2.new(35, 35)
		state.sparks = sparks
	end
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
			trail.Lifetime = 0.25
			trail.MinLength = 0.05
			trail.Color = ColorSequence.new(Color3.fromRGB(240, 248, 255), Color3.fromRGB(150, 200, 255))
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
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

local function wantsSprint(): boolean
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
		humanoid.WalkSpeed = if wantsSprint() then CONFIG.SprintSpeed else CONFIG.WalkSpeed
		local ease = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(humanoid, ease, { CameraOffset = Vector3.zero, HipHeight = state.baseHip }):Play()
		if jump and root then
			humanoid.HipHeight = state.baseHip
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			root.AssemblyLinearVelocity = state.slideDir * CONFIG.SlideJumpForward + Vector3.new(0, CONFIG.SlideJumpUp, 0)
		end
	end
	if state.slideDust then
		state.slideDust.Enabled = false
	end
	if state.sparks then
		state.sparks.Enabled = false
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
	-- The slide drives itself: a horizontal LinearVelocity on the root (gravity and the slide jump stay free).
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
	-- A REAL slide: the hip height drops, so the whole body is down on the floor (the camera follows it down).
	local drop = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(humanoid, drop, { HipHeight = math.max(0.25, state.baseHip - CONFIG.SlideDrop), CameraOffset = Vector3.new(0, -CONFIG.SlideCameraDrop, 0) }):Play()
	if state.slideDust then
		state.slideDust.Enabled = true
		state.slideDust:Emit(30)
	end
	if state.sparks then
		state.sparks.Enabled = true
		state.sparks:Emit(15)
	end
end

-- A scrape mark on the floor under the slide (a thin pale strip that fades).
local function scrape(root: BasePart)
	local down = workspace:Raycast(root.Position, Vector3.new(0, -8, 0), (function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { root.Parent :: Instance }
		return params
	end)())
	if not down then
		return
	end
	local mark = Instance.new("Part")
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Material = Enum.Material.SmoothPlastic
	mark.Color = Color3.fromRGB(235, 225, 200)
	mark.Transparency = 0.45
	mark.Size = Vector3.new(0.9, 0.04, 1.6)
	mark.CFrame = CFrame.lookAt(down.Position + Vector3.new(0, 0.03, 0), down.Position + Vector3.new(0, 0.03, 0) + state.slideDir)
	mark.Parent = workspace
	TweenService:Create(mark, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = Vector3.new(0.5, 0.04, 1.6) }):Play()
	task.delay(1, function()
		mark:Destroy()
	end)
end

-- ── The poses ───────────────────────────────────────────────────────────────

-- The slide (Transform per joint): leaning back, the lead leg stretched forward, the other tucked under, one hand
-- trailing on the ground, the other up for balance, the head looking ahead. (The hip height does the drop.)
local SLIDE_POSE: { [string]: CFrame } = {
	Root = CFrame.new(0, -0.15, 0) * CFrame.Angles(0.55, 0, 0.06),
	Waist = CFrame.Angles(-0.12, 0.15, 0),
	Neck = CFrame.Angles(-0.42, -0.12, 0),
	RightHip = CFrame.Angles(1.2, 0, -0.08),
	RightKnee = CFrame.Angles(-0.1, 0, 0),
	RightAnkle = CFrame.Angles(0.4, 0, 0),
	LeftHip = CFrame.Angles(0.55, 0, 0.2),
	LeftKnee = CFrame.Angles(-1.8, 0, 0),
	LeftAnkle = CFrame.Angles(0.25, 0, 0),
	LeftShoulder = CFrame.Angles(-0.6, 0, 0.8),
	LeftElbow = CFrame.Angles(0.15, 0, 0),
	LeftWrist = CFrame.Angles(-0.5, 0, 0),
	RightShoulder = CFrame.Angles(1.15, 0, -0.4),
	RightElbow = CFrame.Angles(0.7, 0, 0),
}

-- One joint of the sprint cycle at stride phase `p` (nil = leave the animation's value). The arms lag the legs a
-- little and the forearms / hands lag the upper arms (follow-through), so the arms FLOW instead of swinging stiff.
local function sprintPose(name: string, p: number, roll: number): CFrame?
	local s, c = math.sin(p), math.cos(p)
	local swing, pump, lean = CONFIG.StrideSwing, CONFIG.ArmPump, CONFIG.SprintLean
	local a = p - 0.35 -- the arms lag the legs
	local sa = math.sin(a)
	local lag = math.sin(a - 0.6) -- the forearms and hands lag the upper arms
	if name == "Root" then
		return CFrame.new(0, 0.26 * math.abs(c) - 0.16, 0) * CFrame.Angles(-lean, 0.16 * s, 0.06 * s + roll)
	elseif name == "Waist" then
		return CFrame.Angles(-0.08 + 0.05 * math.abs(c), -0.3 * s, -0.04 * s)
	elseif name == "Neck" then
		return CFrame.Angles(lean * 0.8 - 0.06 * math.abs(c), 0.14 * s, -roll * 0.5)
	elseif name == "RightHip" then
		return CFrame.Angles(swing * s, 0, 0)
	elseif name == "LeftHip" then
		return CFrame.Angles(-swing * s, 0, 0)
	elseif name == "RightKnee" then
		return CFrame.Angles(-0.25 - 1.45 * math.max(0, -s) - 0.4 * math.max(0, c), 0, 0)
	elseif name == "LeftKnee" then
		return CFrame.Angles(-0.25 - 1.45 * math.max(0, s) - 0.4 * math.max(0, -c), 0, 0)
	elseif name == "RightAnkle" then
		return CFrame.Angles(0.5 * math.max(0, -s) - 0.18 * math.max(0, s), 0, 0)
	elseif name == "LeftAnkle" then
		return CFrame.Angles(0.5 * math.max(0, s) - 0.18 * math.max(0, -s), 0, 0)
	elseif name == "RightShoulder" then
		return CFrame.Angles(-pump * sa + 0.15, 0, -0.14 - 0.08 * math.abs(sa))
	elseif name == "LeftShoulder" then
		return CFrame.Angles(pump * sa + 0.15, 0, 0.14 + 0.08 * math.abs(sa))
	elseif name == "RightElbow" then
		return CFrame.Angles(1.15 + 0.5 * math.max(0, -lag), 0, 0)
	elseif name == "LeftElbow" then
		return CFrame.Angles(1.15 + 0.5 * math.max(0, lag), 0, 0)
	elseif name == "RightWrist" then
		return CFrame.Angles(0.3 * lag, 0, 0.1)
	elseif name == "LeftWrist" then
		return CFrame.Angles(-0.3 * lag, 0, -0.1)
	end
	return nil
end

-- ── Screen: speed lines, buttons, the keys card ────────────────────────────

local gui = Instance.new("ScreenGui")
gui.Name = "Movement"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 2
gui.Parent = player:WaitForChild("PlayerGui")

-- Speed lines: thin streaks rushing outward at the screen edges while sprinting / sliding.
local linesLayer = Instance.new("Frame")
linesLayer.Name = "SpeedLines"
linesLayer.Size = UDim2.fromScale(1, 1)
linesLayer.BackgroundTransparency = 1
linesLayer.Parent = gui
type Line = { frame: Frame, angle: number, dist: number, speed: number, length: number }
local lines: { Line } = {}
for i = 1, 22 do
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = WHITE
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Parent = linesLayer
	lines[i] = { frame = f, angle = math.random() * math.pi * 2, dist = 0.4 + math.random() * 0.3, speed = 0.6 + math.random() * 0.6, length = 60 + math.random() * 110 }
end

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end
local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end
local function text(parent: Instance, value: string, size: number, font: Enum.Font, color: Color3, position: UDim2, frameSize: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = value
	l.TextSize = size
	l.Font = font
	l.TextColor3 = color
	l.Position = position
	l.Size = frameSize
	l.RichText = true
	l.Parent = parent
	return l
end

-- The two buttons in the bottom right corner (and the "?" over them).
local dock = Instance.new("Frame")
dock.Name = "MoveButtons"
dock.AnchorPoint = Vector2.new(1, 1)
dock.Position = UDim2.new(1, -18, 1, -18)
dock.Size = UDim2.fromOffset(196, 92)
dock.BackgroundTransparency = 1
dock.Parent = gui

type MoveButton = { button: TextButton, stroke: UIStroke, fill: Frame, title: TextLabel }
local function moveButton(x: number, title: string, key: string, icon: string): MoveButton
	local b = Instance.new("TextButton")
	b.Position = UDim2.fromOffset(x, 0)
	b.Size = UDim2.fromOffset(92, 92)
	b.BackgroundColor3 = BG
	b.BackgroundTransparency = 0.08
	b.AutoButtonColor = false
	b.Text = ""
	b.Parent = dock
	corner(b, 46)
	local s = stroke(b, EDGE, 2)
	local fill = Instance.new("Frame") -- the cooldown / active glow
	fill.AnchorPoint = Vector2.new(0.5, 1)
	fill.Position = UDim2.new(0.5, 0, 1, 0)
	fill.Size = UDim2.new(1, 0, 0, 0)
	fill.BackgroundColor3 = GOLD
	fill.BackgroundTransparency = 0.8
	fill.BorderSizePixel = 0
	fill.Parent = b
	corner(fill, 46)
	local iconLabel = text(b, icon, 26, Enum.Font.GothamBlack, WHITE, UDim2.fromOffset(0, 12), UDim2.new(1, 0, 0, 30))
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	local titleLabel = text(b, title, 12, Enum.Font.GothamBlack, WHITE, UDim2.fromOffset(0, 44), UDim2.new(1, 0, 0, 14))
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	local keyLabel = text(b, key, 10, Enum.Font.GothamBold, MUTED, UDim2.fromOffset(0, 62), UDim2.new(1, 0, 0, 12))
	keyLabel.TextXAlignment = Enum.TextXAlignment.Center
	b.MouseEnter:Connect(function()
		s.Thickness = 3
	end)
	b.MouseLeave:Connect(function()
		s.Thickness = 2
	end)
	return { button = b, stroke = s, fill = fill, title = titleLabel }
end
local slideButton = moveButton(0, "SLIDE", "C / Ctrl", "⤓")
local sprintButton = moveButton(104, "SPRINT", "Shift", "»")

-- The keys card ("?").
local helpButton = Instance.new("TextButton")
helpButton.AnchorPoint = Vector2.new(1, 1)
helpButton.Position = UDim2.new(1, -18, 1, -118)
helpButton.Size = UDim2.fromOffset(64, 24)
helpButton.BackgroundColor3 = BG
helpButton.BackgroundTransparency = 0.08
helpButton.AutoButtonColor = false
helpButton.Font = Enum.Font.GothamBold
helpButton.TextSize = 12
helpButton.TextColor3 = MUTED
helpButton.Text = "KEYS ?"
helpButton.Parent = gui
corner(helpButton, 12)
stroke(helpButton, EDGE, 1.5)

local KEYS = {
	{ "W A S D", "move" },
	{ "Space", "jump" },
	{ "Shift (hold)", "sprint" },
	{ "C / Ctrl", "slide (while running)" },
	{ "Space in a slide", "slide jump" },
	{ "Click a mage", "its card" },
	{ "Hold & drag", "move / merge a mage" },
	{ "H", "hide / show the panel" },
	{ "Esc", "close panels" },
}
local card = Instance.new("CanvasGroup")
card.AnchorPoint = Vector2.new(1, 1)
card.Position = UDim2.new(1, -18, 1, -150)
card.Size = UDim2.fromOffset(250, 34 + #KEYS * 22)
card.BackgroundColor3 = BG
card.BackgroundTransparency = 0.05
card.BorderSizePixel = 0
card.Visible = false
card.Parent = gui
corner(card, 12)
stroke(card, EDGE, 1.5)
text(card, "KEYS", 11, Enum.Font.GothamBlack, GOLD, UDim2.fromOffset(14, 8), UDim2.fromOffset(200, 16)).TextXAlignment = Enum.TextXAlignment.Left
for i, entry in KEYS do
	local y = 28 + (i - 1) * 22
	local badge = Instance.new("Frame")
	badge.Position = UDim2.fromOffset(12, y)
	badge.Size = UDim2.fromOffset(104, 18)
	badge.BackgroundColor3 = DARK
	badge.BorderSizePixel = 0
	badge.Parent = card
	corner(badge, 5)
	local k = text(badge, entry[1], 10, Enum.Font.GothamBold, WHITE, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1))
	k.TextXAlignment = Enum.TextXAlignment.Center
	text(card, entry[2], 11, Enum.Font.GothamMedium, MUTED, UDim2.fromOffset(124, y), UDim2.fromOffset(120, 18)).TextXAlignment = Enum.TextXAlignment.Left
end
local cardOpen = false
local function showCard(open: boolean)
	cardOpen = open
	helpButton.TextColor3 = if open then GOLD else MUTED
	if open then
		card.Visible = true
		card.GroupTransparency = 1
		TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 0 }):Play()
	else
		local t = TweenService:Create(card, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { GroupTransparency = 1 })
		t:Play()
		t.Completed:Connect(function()
			if not cardOpen then
				card.Visible = false
			end
		end)
	end
end
helpButton.Activated:Connect(function()
	showCard(not cardOpen)
end)

sprintButton.button.Activated:Connect(function()
	state.sprintToggled = not state.sprintToggled
end)
slideButton.button.Activated:Connect(function()
	if state.sliding then
		endSlide(true) -- the button again during a slide = the slide jump
	else
		startSlide()
	end
end)

local function updateScreen(dt: number, speedFraction: number)
	-- Speed lines.
	local strength = math.max(state.runWeight, state.slideWeight) * speedFraction
	local size = gui.AbsoluteSize
	local center = size / 2
	for _, line in lines do
		if strength < 0.05 then
			line.frame.BackgroundTransparency = 1
			continue
		end
		line.dist += line.speed * dt * (1 + strength)
		if line.dist > 0.95 then
			line.dist = 0.42 + math.random() * 0.12
			line.angle = math.random() * math.pi * 2
		end
		local dir = Vector2.new(math.cos(line.angle), math.sin(line.angle))
		local radius = math.max(size.X, size.Y) * 0.5 * line.dist
		local pos = center + dir * radius
		line.frame.Position = UDim2.fromOffset(pos.X, pos.Y)
		line.frame.Size = UDim2.fromOffset(line.length * (0.6 + strength), 2)
		line.frame.Rotation = math.deg(line.angle)
		line.frame.BackgroundTransparency = 1 - (0.5 * strength * math.clamp((line.dist - 0.42) / 0.2, 0, 1))
	end
	-- Buttons: the sprint button glows green while sprinting; the slide button fills with its cooldown.
	local sprinting = state.sprintHeld or state.sprintToggled
	sprintButton.stroke.Color = if sprinting then GREEN else EDGE
	sprintButton.fill.BackgroundColor3 = GREEN
	sprintButton.fill.Size = UDim2.new(1, 0, if sprinting then 1 else 0, 0)
	sprintButton.title.TextColor3 = if sprinting then GREEN else WHITE
	local now = os.clock()
	local cooling = math.clamp((state.slideReadyAt - now) / CONFIG.SlideCooldown, 0, 1)
	slideButton.stroke.Color = if state.sliding then GOLD else EDGE
	slideButton.fill.Size = UDim2.new(1, 0, if state.sliding then 1 else cooling, 0)
	slideButton.title.TextColor3 = if state.sliding then GOLD else WHITE
end

-- ── Every frame ─────────────────────────────────────────────────────────────

local function update(dt: number)
	local humanoid, root = state.humanoid, state.root
	if not humanoid or not root or not humanoid.Parent then
		updateScreen(dt, 0)
		return
	end
	local now = os.clock()
	local run = wantsSprint()

	-- Speeds.
	if state.sliding then
		local t = math.clamp((now - state.slideStart) / CONFIG.SlideTime, 0, 1)
		local e = 1 - (1 - t) ^ 2
		local slideSpeed = CONFIG.SlideStartSpeed + (CONFIG.SlideEndSpeed - CONFIG.SlideStartSpeed) * e
		humanoid.WalkSpeed = slideSpeed
		if state.slideForce then
			state.slideForce.PlaneVelocity = Vector2.new(state.slideDir.X, state.slideDir.Z) * slideSpeed
		end
		if now - state.scrapeAt > 0.05 then
			state.scrapeAt = now
			scrape(root)
		end
		if state.sparks then
			state.sparks.Rate = 70 * (1 - e)
		end
		if t >= 1 or humanoid.Health <= 0 then
			endSlide(false)
		elseif not isGrounded() and now - state.slideStart > 0.15 then
			endSlide(false) -- slid off an edge
		end
	elseif humanoid.WalkSpeed == CONFIG.WalkSpeed or humanoid.WalkSpeed == CONFIG.SprintSpeed or humanoid.WalkSpeed > CONFIG.SprintSpeed then
		humanoid.WalkSpeed = if run then CONFIG.SprintSpeed else CONFIG.WalkSpeed
	end

	-- Camera: wider while sprinting.
	local fov = if run and not state.sliding then CONFIG.SprintFov else 70
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, dt * 8)

	-- The run cycle advances with the distance travelled (the legs never skate); the lean into turns.
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	state.stride = (state.stride + speed * dt * CONFIG.StrideRate) % (math.pi * 2)
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local turn = (yaw - state.lastYaw + math.pi) % (math.pi * 2) - math.pi
	state.lastYaw = yaw
	local wantRoll = math.clamp(-turn / math.max(dt, 1 / 240) * CONFIG.TurnLean, -0.35, 0.35)
	state.turnRoll += (wantRoll - state.turnRoll) * math.min(1, dt * 8)

	-- Blends.
	local function approach(value: number, target: number, inTime: number, outTime: number): number
		local rate = dt / (if target > value then inTime else outTime)
		if math.abs(target - value) <= rate then
			return target
		end
		return value + (if target > value then rate else -rate)
	end
	local sprintingNow = run and isGrounded() and not state.sliding and speed > CONFIG.WalkSpeed * 0.8
	state.slideWeight = approach(state.slideWeight, if state.sliding then 1 else 0, CONFIG.BlendIn, CONFIG.BlendOut)
	state.runWeight = approach(state.runWeight, if sprintingNow then 1 else 0, 0.18, 0.25)

	-- Dust and the speed streaks.
	if state.dust then
		state.dust.Enabled = sprintingNow
	end
	for _, trail in state.trails do
		trail.Enabled = sprintingNow or state.sliding
	end
	updateScreen(dt, math.clamp(speed / CONFIG.SprintSpeed, 0, 1.4))
end

-- The poses, after the animator wrote this frame's Transforms.
local function pose()
	local sw, rw = state.slideWeight, state.runWeight
	if sw <= 0.001 and rw <= 0.001 then
		return
	end
	for name, joint in state.joints do
		if not joint.Parent then
			continue
		end
		local current = joint.Transform
		if rw > 0.001 then
			local runPose = sprintPose(name, state.stride, state.turnRoll)
			if runPose then
				current = current:Lerp(runPose, rw)
			end
		end
		local target = SLIDE_POSE[name]
		if sw > 0.001 and target then
			current = current:Lerp(target, sw)
		end
		joint.Transform = current
	end
end

local function onSprint(_: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	state.sprintHeld = inputState == Enum.UserInputState.Begin or inputState == Enum.UserInputState.Change
	return Enum.ContextActionResult.Pass
end
local function onSlide(_: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		startSlide()
	end
	return Enum.ContextActionResult.Pass
end

function PlayerMovement.start()
	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)
	-- Keys (no automatic touch buttons: the screen has its own SPRINT / SLIDE buttons in the bottom right).
	ContextActionService:BindAction("MB_Sprint", onSprint, false, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:BindAction("MB_Slide", onSlide, false, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	game:GetService("UserInputService").JumpRequest:Connect(function()
		if state.sliding then
			endSlide(true)
		end
	end)
	RunService.RenderStepped:Connect(update)
	RunService.Stepped:Connect(pose) -- after the animator: overwrite / blend the joints' Transform
	-- The keys card shows itself once, for a few seconds, the first time.
	task.delay(3, function()
		showCard(true)
		task.delay(7, function()
			if cardOpen then
				showCard(false)
			end
		end)
	end)
end

return PlayerMovement
