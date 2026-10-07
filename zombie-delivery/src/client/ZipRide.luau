--!strict
-- 5.6: riding the zip lines (shared/ZipLines.luau, Config.ZipLines; the server checks and ends every ride:
-- server/ZipLines.luau).
--
-- Your own ride: when the server marks your character (the attributes ZipLine = the line's id, ZipAt = the server
-- time it starts), the root is held on the cable by a rigid AlignPosition and AlignOrientation on an attachment in it
-- (the body stays physics-simulated and owned by you, so everybody sees it glide; nothing is anchored, no C0 written),
-- the Humanoid PlatformStands. Every PreSimulation the root goes where ZipLines.rider puts it at the server's clock
-- (from where you stood, eased onto the cable in the first moment). At the end you are set down gently on the end
-- platform. Space (or the jump button) lets go early only where ZipLines.canLetGo allows it (low over one of the
-- line's roofs; the server checks it again: the Zip remote's "letgo"), anywhere else it says so and holds on.
--
-- Everybody's riders (your own too): the hands up on a trolley's handle, the legs hanging a little bent, written into
-- the R15 joints' Transform in PreSimulation (shared/Joints.luau: Motor6Ds or AnimationConstraints), and a small
-- trolley (three local parts: the wheel box on the cable, the strap, the handle) over the hands. Both go when the ride
-- ends or the rider is far away.
--
-- 5.7: the hands reach up to the trolley as a ride starts (Config.Interact.ZipReach), the hanging pose laid on over it.
--
-- 5.7, a climb (Climb / Climb down at the ladders and the platforms) is a real one: the server marks the character
-- (ClimbLine, ClimbWhich, ClimbUp, ClimbAt: server/ZipLines.luau) and your own client carries your body along
-- shared/InteractPose.luau's climbRoute from where you stand: onto the ladder, up it hand over hand at
-- Config.Interact.ClimbSpeed, over the roof's edge, across the roof and over the platform's rail (down: all of it
-- backwards, and a step off the ladder onto the sidewalk). Your controls are off meanwhile (client/Interact.luau) and
-- the camera follows as it does on foot. Everybody's climbers near the camera are posed (the hands over hand, the knee
-- over the edge, a stride on the roof) from the same attributes. The server puts a climber who is not at the end in
-- time there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local InteractPose = require(Shared:WaitForChild("InteractPose"))
local Joints = require(Shared:WaitForChild("Joints"))
local Net = require(Shared:WaitForChild("Net"))
local ZipData = require(Shared:WaitForChild("ZipLines"))
local Drive = require(script.Parent.Drive)
local Interact = require(script.Parent.Interact)

local ZipRide = {}

-- Set by Main: a short toast.
ZipRide.notify = function(_text: string) end

local player = Players.LocalPlayer
local Tuning = Config.ZipLines
local EASE_IN = 0.45 -- seconds to ease from where you stood onto the cable
local OWNER = "climb" -- (client/Interact.luau)
local LEAD = 0.15 -- the server's ZipAt is this long after the Zip (server/ZipLines.luau): the hands go up meanwhile
local POSE_RANGE = 320 -- riders farther from the camera than this are left alone
local TROLLEY = Color3.fromRGB(40, 42, 46)
local HANDLE = Color3.fromRGB(196, 52, 46)

type Mine = {
	line: ZipData.Line,
	start: number,
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	from: Vector3,
	grip: Attachment,
	align: AlignPosition,
	orient: AlignOrientation,
}

local mine: Mine? = nil
local finished: number? = nil -- the ZipAt of the ride ended here last (the server clears the attributes a moment later)
local toldAt = -math.huge

-- The joints a rider's pose takes over: part, joint, rotation.
local POSE: { { any } } = {
	{ "RightUpperArm", "RightShoulder", CFrame.Angles(math.rad(166), 0, math.rad(-6)) },
	{ "LeftUpperArm", "LeftShoulder", CFrame.Angles(math.rad(166), 0, math.rad(6)) },
	{ "RightLowerArm", "RightElbow", CFrame.Angles(math.rad(14), 0, 0) },
	{ "LeftLowerArm", "LeftElbow", CFrame.Angles(math.rad(14), 0, 0) },
	{ "RightUpperLeg", "RightHip", CFrame.Angles(math.rad(16), 0, 0) },
	{ "LeftUpperLeg", "LeftHip", CFrame.Angles(math.rad(8), 0, 0) },
	{ "RightLowerLeg", "RightKnee", CFrame.Angles(math.rad(-22), 0, 0) },
	{ "LeftLowerLeg", "LeftKnee", CFrame.Angles(math.rad(-14), 0, 0) },
}

type Posed = { joints: { { joint: any, rotation: CFrame } }, trolley: Model }
local posed: { [Model]: Posed } = {}

local function lineOf(character: Model): (ZipData.Line?, number?)
	local id, at = character:GetAttribute("ZipLine"), character:GetAttribute("ZipAt")
	if type(id) ~= "number" or type(at) ~= "number" then
		return nil, nil
	end
	return ZipData.line(id), at
end

-- ── The trolley and the pose (everybody's riders) ──────────────────────────

local function piece(parent: Instance, name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function makeTrolley(): Model
	local model = Instance.new("Model")
	model.Name = "ZipTrolley"
	piece(model, "Wheels", Vector3.new(0.5, 0.6, 1.1), TROLLEY)
	piece(model, "Strap", Vector3.new(0.12, 0.6, 0.12), TROLLEY)
	piece(model, "Handle", Vector3.new(2.3, 0.16, 0.16), HANDLE)
	model.Parent = workspace.CurrentCamera or workspace
	return model
end

local function pose(character: Model, line: ZipData.Line, reach: number)
	local state = posed[character]
	if not state then
		local joints = {}
		for _, entry in POSE do
			local joint = Joints.find(character:FindFirstChild(entry[1]), entry[2])
			if joint then
				table.insert(joints, { joint = joint, rotation = entry[3] })
			end
		end
		state = { joints = joints, trolley = makeTrolley() }
		posed[character] = state
	end
	local current = state :: Posed
	for _, entry in current.joints do
		if entry.joint.Parent then
			-- (5.7: the hands reach up to the trolley as the ride starts)
			entry.joint.Transform = if reach >= 1 then entry.rotation else CFrame.identity:Lerp(entry.rotation, reach)
		end
	end
	-- The trolley over the hands: on the cable over the root, along the line.
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local top = root.Position + Vector3.new(0, Tuning.Hang, 0)
		local frame = CFrame.lookAt(top, top + Vector3.new(line.dx, 0, line.dz))
		local trolley = current.trolley
		local wheels = trolley:FindFirstChild("Wheels") :: BasePart?
		local strap = trolley:FindFirstChild("Strap") :: BasePart?
		local handle = trolley:FindFirstChild("Handle") :: BasePart?
		if wheels and strap and handle then
			wheels.CFrame = frame * CFrame.new(0, 0, 0)
			strap.CFrame = frame * CFrame.new(0, -0.55, 0)
			handle.CFrame = frame * CFrame.new(0, -0.9, 0)
		end
	end
end

local function unpose(character: Model)
	local state = posed[character]
	if not state then
		return
	end
	posed[character] = nil
	for _, entry in state.joints do
		if entry.joint.Parent then
			entry.joint.Transform = CFrame.identity
		end
	end
	state.trolley:Destroy()
end

-- ── Your own ride ──────────────────────────────────────────────────────────

local function release(landed: boolean)
	local m = mine
	if not m then
		return
	end
	mine = nil
	finished = m.start
	m.align:Destroy()
	m.orient:Destroy()
	m.grip:Destroy()
	if not m.root.Parent or m.humanoid.Health <= 0 then
		return
	end
	m.humanoid.PlatformStand = false
	local line = m.line
	if landed then
		-- set down gently on the end platform
		local at = Vector3.new(line.b.x, line.b.floor + 3, line.b.z)
		m.root.CFrame = CFrame.lookAt(at, at + Vector3.new(line.dx, 0, line.dz))
		m.root.AssemblyLinearVelocity = Vector3.new(0, -2, 0)
	else
		m.root.AssemblyLinearVelocity = Vector3.new(line.dx * 6, -2, line.dz * 6)
	end
	m.root.AssemblyAngularVelocity = Vector3.zero
	m.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
end

local function begin(character: Model, line: ZipData.Line, start: number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	local grip = Instance.new("Attachment")
	grip.Name = "ZipGrip"
	grip.Parent = root
	local align = Instance.new("AlignPosition")
	align.Name = "ZipAlign"
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = grip
	align.RigidityEnabled = true
	align.Position = root.Position
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Name = "ZipOrient"
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = grip
	orient.RigidityEnabled = true
	orient.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(line.dx, 0, line.dz))
	orient.Parent = root
	humanoid.PlatformStand = true
	mine = {
		line = line,
		start = start,
		character = character,
		humanoid = humanoid,
		root = root,
		from = root.Position,
		grip = grip,
		align = align,
		orient = orient,
	}
end

local function steer()
	local character = player.Character
	local line, start = nil, nil
	if character then
		line, start = lineOf(character)
	end
	local m = mine
	if m and (m.character ~= character or line ~= m.line or m.humanoid.Health <= 0) then
		-- the server ended it (let go, a late rider put down, a death) or the body changed
		local t = workspace:GetServerTimeNow() - m.start
		release(m.character == character and t >= m.line.duration)
		m = nil
	end
	if not m and character and line and start and start ~= finished then
		begin(character, line, start)
		m = mine
	end
	if not m then
		return
	end
	local t = workspace:GetServerTimeNow() - m.start
	local x, y, z = ZipData.rider(m.line, t)
	local target = Vector3.new(x, y, z)
	local ease = math.clamp((t + 0.15) / EASE_IN, 0, 1)
	if ease < 1 then
		local s = ease * ease * (3 - 2 * ease)
		target = m.from:Lerp(target, s)
	end
	m.align.Position = target
	if t >= m.line.duration then
		release(true)
	end
end

local function letGo()
	local m = mine
	if not m then
		return
	end
	local t = workspace:GetServerTimeNow() - m.start
	if ZipData.canLetGo(m.line, t) then
		Net.get("Zip"):FireServer("letgo")
		release(false)
	elseif os.clock() - toldAt > 2.5 then
		toldAt = os.clock()
		ZipRide.notify("Too high to let go: hold on.")
	end
end

-- ── 5.7: the climbs ─────────────────────────────────────────────────────────

type Climbing = {
	at: number, -- the ClimbAt it plays
	route: InteractPose.Route,
	character: Model,
	humanoid: Humanoid?,
	root: BasePart?,
}

local climbing: Climbing? = nil -- your own
local climbed: number? = nil -- the ClimbAt of the climb ended here last (the server clears it a moment later)
local others: { [Model]: Climbing } = {} -- everybody else's near the camera (for the pose)

local function climbOf(character: Model): (ZipData.Line?, number, boolean, number?)
	local id, which, up, at = character:GetAttribute("ClimbLine"), character:GetAttribute("ClimbWhich"), character:GetAttribute("ClimbUp"), character:GetAttribute("ClimbAt")
	if type(id) ~= "number" or type(at) ~= "number" then
		return nil, 1, true, nil
	end
	return ZipData.line(id), if which == 2 then 2 else 1, up ~= false, at
end

-- The zip line's own model (the camera leaves the walk alone while you climb: Drive.setBoarding).
local function lineModel(line: ZipData.Line): Model?
	local world = workspace:FindFirstChild("World")
	local folder = world and world:FindFirstChild("ZipLines")
	local model = folder and folder:FindFirstChild(line.name)
	return if model and model:IsA("Model") then model else nil
end

-- A climb's pose t seconds in: the segment's, the stride fading in and out at the route's ends.
local function climbPose(route: InteractPose.Route, t: number): InteractPose.Pose
	local _, _, _, _, _, kind, u, dist = InteractPose.sample(route, t)
	if kind == "walk" then
		local amount = math.clamp(t / 0.2, 0, 1) * math.clamp((route.total - t) / 0.25, 0, 1)
		return InteractPose.walk(dist, amount)
	end
	return InteractPose.forKind(kind, u, dist)
end

local function endClimb(c: Climbing)
	climbing = nil
	climbed = c.at
	Interact.release(c.character, OWNER)
	Interact.freeze(nil, false)
	Drive.setBoarding(nil, false)
	local root = c.root
	if root and root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Your own climb this frame: started when the server marks you, carried along its route, over at its end (or when
-- the server ended it: a death, a reset).
local function climbStep(dt: number)
	local character = player.Character
	local line, which, up, at = nil, 1, true, nil
	if character then
		line, which, up, at = climbOf(character)
	end
	local c = climbing
	if c and (c.character ~= character or at ~= c.at) then
		endClimb(c)
		c = nil
	end
	if not c and character and line and at and at ~= climbed and not mine then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = humanoid and humanoid.RootPart
		if not humanoid or not root or humanoid.Health <= 0 or humanoid.SeatPart then
			return
		end
		local p = root.Position
		local made: Climbing = {
			at = at,
			route = InteractPose.climbRoute(line, which, up, p.X, p.Y, p.Z, Interact.standHeight(humanoid, root)),
			character = character,
			humanoid = humanoid,
			root = root,
		}
		climbing = made
		c = made
		Interact.freeze(humanoid, true)
		local model = lineModel(line)
		if model then
			Drive.setBoarding(model, false) -- (no aiming, the walk left alone; the view stays the walk's)
		end
	end
	if not c then
		return
	end
	local humanoid, root = c.humanoid, c.root
	if not humanoid or not root or not root.Parent or humanoid.Health <= 0 then
		endClimb(c)
		return
	end
	local t = workspace:GetServerTimeNow() - c.at
	local x, y, z, fx, fz = InteractPose.sample(c.route, t)
	Interact.place(root, Interact.frame(x, y, z, fx, fz), dt)
	Interact.pose(c.character, climbPose(c.route, t), dt, OWNER)
	if t >= c.route.total then
		endClimb(c)
	end
end

-- Everybody else's climbs near the camera: the pose from their attributes (their own clients move them).
local function othersStep(dt: number, eye: Vector3)
	local now = workspace:GetServerTimeNow()
	local seen: { [Model]: boolean } = {}
	for _, other in Players:GetPlayers() do
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if other == player or not character or not root or not root:IsA("BasePart") or (root.Position - eye).Magnitude > POSE_RANGE then
			continue
		end
		local line, which, up, at = climbOf(character)
		if not line or not at then
			continue
		end
		local c = others[character]
		if not c or c.at ~= at then
			-- (from the route's first point: only the limbs are played here)
			local ladder = if which == 1 then line.ladderA else line.ladderB
			local x, y, z = ladder.x + ladder.nx * 3, ladder.base + 3, ladder.z + ladder.nz * 3
			if not up then
				x, y, z = InteractPose.climbEnd(line, which, true, 3)
			end
			local made: Climbing = { at = at, route = InteractPose.climbRoute(line, which, up, x, y, z, 3), character = character, humanoid = nil, root = nil }
			others[character] = made
			c = made
		end
		local current = c :: Climbing
		local t = now - at
		seen[character] = true
		if t >= 0 and t <= current.route.total then
			Interact.pose(character, climbPose(current.route, t), dt, OWNER)
		else
			Interact.release(character, OWNER) -- (over: the server clears the attributes a moment later)
		end
	end
	for character in others do
		if not seen[character] then
			others[character] = nil
			Interact.release(character, OWNER)
		end
	end
end

-- ── Start ──────────────────────────────────────────────────────────────────

function ZipRide.start()
	RunService.PreSimulation:Connect(function(dt: number)
		steer()
		climbStep(dt)
		-- Everybody's riders near the camera: the pose and the trolley.
		local camera = workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		othersStep(dt, eye)
		local seen: { [Model]: boolean } = {}
		local now = workspace:GetServerTimeNow()
		for _, other in Players:GetPlayers() do
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if character and root and root:IsA("BasePart") and (root.Position - eye).Magnitude < POSE_RANGE then
				local line, at = lineOf(character)
				-- (over the end, or let go here: standing again, though the server clears the ride a moment later)
				local over = at == nil or (line ~= nil and now - at > line.duration + 0.1) or (other == player and at == finished)
				if line and at and not over then
					seen[character] = true
					pose(character, line, InteractPose.reachUp(now - at + LEAD))
				end
			end
		end
		for character in table.clone(posed) do
			if not seen[character] then
				unpose(character)
			end
		end
	end)
	UserInputService.JumpRequest:Connect(letGo)
end

return ZipRide
