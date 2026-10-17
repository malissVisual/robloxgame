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
-- 6.8 review: the hands hold the handle (handleGrip: a two-bone reach of each arm on the body's own rig to the handle,
-- Config.ZipLines HandleDrop under the cable), not a fixed arms-up pose (the hands went up through the trolley).
--
-- 6.10 (the owner: "like a building you climb up by yourself, and onto the zip line you just jump"): the ladders are
-- real trusses the body climbs by itself and the 5.7 climbs (a route played here, the controls off) are gone. A jump
-- (Space, the jump button) on a line's start platform grabs the trolley: shared/ZipLines.luau startAt says which
-- platform the body is on (over its floor, the feet no higher than a jump), and the Zip remote's "grab" asks the
-- server, which checks it as the Zip prompt (server/ZipLines.luau); once a second at most (a held button asks every
-- frame). A jump anywhere else is only a jump, and on a ride it is the let go.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local InteractPose = require(Shared:WaitForChild("InteractPose"))
local BodyMotion = require(Shared:WaitForChild("BodyMotion")) -- 6.8 review: the hands reach the handle
local Joints = require(Shared:WaitForChild("Joints"))
local Net = require(Shared:WaitForChild("Net"))
local ZipData = require(Shared:WaitForChild("ZipLines"))
local Interact = require(script.Parent.Interact)
local Bodies = require(script.Parent.Bodies)

local ZipRide = {}

-- Set by Main: a short toast.
ZipRide.notify = function(_text: string) end

local player = Players.LocalPlayer
local Tuning = Config.ZipLines
local EASE_IN = 0.45 -- seconds to ease from where you stood onto the cable
local LEAD = 0.15 -- the server's ZipAt is this long after the Zip (server/ZipLines.luau): the hands go up meanwhile
local POSE_RANGE = 320 -- riders farther from the camera than this are left alone (and their trolleys)
local GRAB_EVERY = 1 -- 6.10: seconds between two jumps that ask for the trolley (and from one to a let go)
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
local grabbedAt = -math.huge -- 6.10: the last "grab" asked

-- The joints a rider's pose takes over: part, joint, rotation. (6.8 review: the arms' are the fallback for a body
-- without the rig's attachments: handleGrip reaches them to the handle.)
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
local WHEELS_UP = 0.2 -- 6.8 review: the trolley's wheel box rides on the cable (its middle this far over it)
local WHEELS_HALF = 0.3 -- (half its height)
local HANDLE_HALF = 0.08 -- (half the handle's thickness)

-- `handle`: 6.8 review: the handle's height over the root (where the hands hold it)
type Posed = { joints: { { joint: any, rotation: CFrame } }, trolley: Model, handle: number }
local posed: { [Model]: Posed } = {}

-- 6.8 review: the hands on the trolley's handle. It hangs Tuning.HandleDrop under the cable (the root Tuning.Hang under
-- it), the hands Tuning.HandSpread apart on it; each arm a two-bone reach (shared/BodyMotion.luau reach, as
-- client/ArmPose.luau's carry) from its shoulder (the rig's attachments at rest: the root, the waist, the shoulder) to
-- the grip in the fist (its GripAttachment), the elbows out and a little forward: the fists close round the bar, the
-- palms forward. 5.6's fixed pose (the arms straight up) put the hands 0.9 studs up through the trolley on the 6.7 body.
-- Arms too short for the handle bring it down to the hands. Nil without the rig's attachments (the fixed pose then).
type Arm = { from: Vector3, upper: number, lower: number }
type Grip = { rs: CFrame, re: CFrame, ls: CFrame, le: CFrame, height: number }

local function rigPoint(character: Model, part: string, name: string): Vector3?
	local p = character:FindFirstChild(part)
	local a = p and p:FindFirstChild(name)
	return if a and a:IsA("Attachment") then a.Position else nil
end

local function armOf(character: Model, torso: Vector3, side: string): Arm?
	local shoulder = rigPoint(character, "UpperTorso", side .. "ShoulderRigAttachment")
	local s1, e1 = rigPoint(character, side .. "UpperArm", side .. "ShoulderRigAttachment"), rigPoint(character, side .. "UpperArm", side .. "ElbowRigAttachment")
	local e2, w2 = rigPoint(character, side .. "LowerArm", side .. "ElbowRigAttachment"), rigPoint(character, side .. "LowerArm", side .. "WristRigAttachment")
	local w3, g3 = rigPoint(character, side .. "Hand", side .. "WristRigAttachment"), rigPoint(character, side .. "Hand", side .. "GripAttachment")
	if not (shoulder and s1 and e1 and e2 and w2 and w3 and g3) then
		return nil
	end
	return { from = torso + shoulder, upper = (s1 - e1).Magnitude, lower = (e2 - w2).Magnitude + (w3 - g3).Magnitude }
end

local function handleGrip(character: Model): Grip?
	local rootAt, lowerRoot = rigPoint(character, "HumanoidRootPart", "RootRigAttachment"), rigPoint(character, "LowerTorso", "RootRigAttachment")
	local lowerWaist, upperWaist = rigPoint(character, "LowerTorso", "WaistRigAttachment"), rigPoint(character, "UpperTorso", "WaistRigAttachment")
	if not (rootAt and lowerRoot and lowerWaist and upperWaist) then
		return nil
	end
	local torso = rootAt - lowerRoot + lowerWaist - upperWaist -- (the UpperTorso's middle from the root, at rest)
	local right, left = armOf(character, torso, "Right"), armOf(character, torso, "Left")
	if not right or not left or right.upper < 0.2 or right.lower < 0.2 or left.upper < 0.2 or left.lower < 0.2 then
		return nil
	end
	local x = Tuning.HandSpread / 2
	local height = Tuning.Hang - Tuning.HandleDrop
	for _, arm in { right, left } do
		local most = arm.upper + arm.lower - 0.02
		local dx, dz = x - math.abs(arm.from.X), arm.from.Z
		height = math.min(height, arm.from.Y + math.sqrt(math.max(0, most * most - dx * dx - dz * dz)))
	end
	local function reach(arm: Arm, side: number): (CFrame, CFrame)
		local d = Vector3.new(side * x, height, 0) - arm.from
		local xx, xy, xz, yx, yy, yz, bend = BodyMotion.reach(d.X, d.Y, d.Z, arm.upper, arm.lower, side, 0, -0.4)
		return CFrame.fromMatrix(Vector3.zero, Vector3.new(xx, xy, xz), Vector3.new(yx, yy, yz)), CFrame.Angles(bend, 0, 0)
	end
	local rs, re = reach(right, 1)
	local ls, le = reach(left, -1)
	return { rs = rs, re = re, ls = ls, le = le, height = height }
end

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

-- `drop`: 6.8 review: the handle's middle under the cable (the strap reaches down to it from the wheels).
local function makeTrolley(drop: number): Model
	local model = Instance.new("Model")
	model.Name = "ZipTrolley"
	piece(model, "Wheels", Vector3.new(0.5, WHEELS_HALF * 2, 1.1), TROLLEY)
	piece(model, "Strap", Vector3.new(0.12, math.max(0.05, drop - HANDLE_HALF - (WHEELS_HALF - WHEELS_UP)), 0.12), TROLLEY)
	piece(model, "Handle", Vector3.new(2.3, HANDLE_HALF * 2, 0.16), HANDLE)
	model.Parent = workspace.CurrentCamera or workspace
	return model
end

local function pose(character: Model, line: ZipData.Line, reach: number)
	local state = posed[character]
	if not state then
		-- 6.8 review: the arms reach the handle (handleGrip), measured once per ride on this body
		local grip = handleGrip(character)
		local arms: { [string]: CFrame } = if grip then { RightShoulder = grip.rs, RightElbow = grip.re, LeftShoulder = grip.ls, LeftElbow = grip.le } else {}
		local joints = {}
		for _, entry in POSE do
			local joint = Joints.find(character:FindFirstChild(entry[1]), entry[2])
			if joint then
				table.insert(joints, { joint = joint, rotation = arms[entry[2]] or entry[3] })
			end
		end
		local handle = if grip then grip.height else Tuning.Hang - Tuning.HandleDrop
		state = { joints = joints, trolley = makeTrolley(Tuning.Hang - handle), handle = handle }
		posed[character] = state
	end
	local current = state :: Posed
	for _, entry in current.joints do
		if entry.joint.Parent then
			-- (5.7: the hands reach up to the trolley as the ride starts)
			entry.joint.Transform = if reach >= 1 then entry.rotation else CFrame.identity:Lerp(entry.rotation, reach)
		end
	end
	-- The trolley over the hands: on the cable over the root, along the line (6.8 review: the handle where the hands
	-- hold it, the strap from the wheels down to it).
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local top = root.Position + Vector3.new(0, Tuning.Hang, 0)
		local frame = CFrame.lookAt(top, top + Vector3.new(line.dx, 0, line.dz))
		local trolley = current.trolley
		local wheels = trolley:FindFirstChild("Wheels") :: BasePart?
		local strap = trolley:FindFirstChild("Strap") :: BasePart?
		local handle = trolley:FindFirstChild("Handle") :: BasePart?
		if wheels and strap and handle then
			local drop = Tuning.Hang - current.handle
			wheels.CFrame = frame * CFrame.new(0, WHEELS_UP, 0)
			strap.CFrame = frame * CFrame.new(0, (WHEELS_UP - WHEELS_HALF - drop + HANDLE_HALF) / 2, 0)
			handle.CFrame = frame * CFrame.new(0, -drop, 0)
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
		local at = Vector3.new(line.b.x, line.b.floor + Interact.standHeight(m.humanoid, m.root), line.b.z) -- (6.8 review: the body's own height, not 3)
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

-- ── 6.10: a jump grabs the trolley ─────────────────────────────────────────

-- A jump on a line's start platform: the server starts the ride if the Zip prompt would (see the top).
local function grab()
	if os.clock() - grabbedAt < GRAB_EVERY then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = humanoid and humanoid.RootPart
	if not character or not humanoid or not root or humanoid.Health <= 0 or humanoid.SeatPart ~= nil or (lineOf(character)) ~= nil then
		return
	end
	local at = root.Position
	local line = ZipData.startAt(at.X, at.Y, at.Z, Interact.standHeight(humanoid, root))
	if line then
		grabbedAt = os.clock()
		Net.get("Zip"):FireServer("grab", line.id)
	end
end

-- Space or the jump button: on a ride the let go, else maybe the grab. (Not the jump that grabbed the trolley: a
-- held button asks again as the ride starts, low over the start's roof, where letting go is allowed.)
local function jumped()
	if mine then
		if os.clock() - grabbedAt >= GRAB_EVERY then
			letGo()
		end
	else
		grab()
	end
end

-- ── Start ──────────────────────────────────────────────────────────────────

function ZipRide.start()
	RunService.PreSimulation:Connect(function()
		steer()
		-- Everybody's riders near the camera: the pose and the trolley.
		local camera = workspace.CurrentCamera
		local eye = if camera then camera.CFrame.Position else Vector3.zero
		local seen: { [Model]: boolean } = {}
		local now = workspace:GetServerTimeNow()
		for _, other in Bodies.players() do
			local character = other.Character
			if not character then
				continue
			end
			-- (5.9.2: the far ones skipped first, the body's parts looked up once)
			local _, near = Bodies.near(character, eye, POSE_RANGE)
			if not near then
				continue
			end
			local line, at = lineOf(character)
			-- (over the end, or let go here: standing again, though the server clears the ride a moment later)
			local over = at == nil or (line ~= nil and now - at > line.duration + 0.1) or (other == player and at == finished)
			if line and at and not over then
				seen[character] = true
				pose(character, line, InteractPose.reachUp(now - at + LEAD))
			end
		end
		for character in table.clone(posed) do
			if not seen[character] then
				unpose(character)
			end
		end
	end)
	UserInputService.JumpRequest:Connect(jumped)
end

return ZipRide
