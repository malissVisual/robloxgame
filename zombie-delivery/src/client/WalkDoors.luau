--!strict
-- 8.3 walk-in doors on the client (the owner: "when I go into the house, the door should open, and then it teleports me
-- smoothly"; Config.Moving.Doors; the server's side is server/Moving.luau's WalkIn and travel):
--   * the leaves: every door leaf the server tagged DoorLeaf (a part or a model with the attributes of
--     shared/DoorSwing.luau, at a doorway as it is shut: the sandbox house's front door, the interior's way out) swings
--     open on its hinge here, for whoever sees it, while its DoorOpen is true: Open s easing into the stop, the door's
--     creak at it (Sound.Open, 3D: client/Sounds.luau playAt), and shut again in Close s with a soft thud as it meets
--     its frame (Sound.Shut). Only this client's view moves (the server's parts stay where they are, never colliding):
--     nothing is pushed. A double door (DoorLeaf 0, a part) swings as two halves made here, the part hidden here
--     meanwhile; DoorDark shows a dark doorway where it stood while it is open (a house's solid body behind it). A leaf
--     first seen open (streamed in, joined late) stands open at once; an invisible one (a Blender house's door over it)
--     does not swing.
--   * the trip's arrival: client/Fade.luau holds the black until your body is where the server put it, then calls
--     Fade.onArrive: here the camera is put behind you, looking the way you face there (client/CameraRig.luau face; a
--     touch screen's Roblox camera turned the same way): no snap, no spin once the screen clears.
-- Started by client/Main.client.luau (the sandbox). Presentation only.
--   WalkDoors.start()          the tagged leaves watched, the arrival's hook set
--   WalkDoors.behind(look)     the camera behind you, looking along `look` (the arrival's)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local DoorSwing = require(Shared.DoorSwing)
local CameraRig = require(script.Parent.CameraRig)
local Fade = require(script.Parent.Fade)
local Sounds = require(script.Parent.Sounds)

local WalkDoors = {}

local D = Config.Moving.Doors
local TAG = "DoorLeaf"

-- A swinging piece: the instance moved (the leaf itself, or a half made here), its frame shut, its swing.
type Piece = { moved: Instance, shut: CFrame, swing: DoorSwing.Piece }
type Leaf = {
	inst: Instance,
	pieces: { Piece },
	made: { Instance }, -- what this client made for it (the halves, the dark doorway)
	dark: BasePart?,
	hidden: BasePart?, -- a double door's part, hidden here while its halves swing
	at: Vector3, -- its middle (the sounds')
	u: number, -- openness now (0 shut … 1 open)
	from: number, -- the openness this swing started at
	t: number, -- the swing's progress (0 … 1 of its time)
	opening: boolean,
	time: number, -- this swing's length (s)
	hooks: { RBXScriptConnection },
}

local leaves: { [Instance]: Leaf } = {}
local moving: { [Leaf]: boolean } = {}
local waiting: { [Instance]: RBXScriptConnection } = {} -- a model leaf → its PrimaryPart's watch (its parts stream)
local stepper: RBXScriptConnection? = nil
local started = false

-- The leaf's frame and size: a part's own, a model's pivot and its PrimaryPart's size; nil: neither (a model whose
-- parts have not streamed in yet).
local function shape(inst: Instance): (CFrame?, Vector3?)
	if inst:IsA("BasePart") then
		return inst.CFrame, inst.Size
	elseif inst:IsA("Model") then
		local primary = inst.PrimaryPart
		if primary then
			return inst:GetPivot(), primary.Size
		end
	end
	return nil, nil
end

local function visible(inst: Instance): boolean
	local part = if inst:IsA("BasePart") then inst elseif inst:IsA("Model") then inst.PrimaryPart else nil
	return part == nil or part.Transparency < 0.99
end

local function place(piece: Piece, u: number)
	local s = piece.swing
	local frame = piece.shut * CFrame.new(s.hx, 0, s.hz) * CFrame.Angles(0, s.yaw * u, 0) * CFrame.new(-s.hx, 0, -s.hz)
	local moved = piece.moved
	if moved:IsA("BasePart") then
		moved.CFrame = frame
	elseif moved:IsA("Model") then
		moved:PivotTo(frame)
	end
end

local function pose(leaf: Leaf, u: number)
	leaf.u = u
	for _, piece in leaf.pieces do
		place(piece, u)
	end
	local dark = leaf.dark
	if dark then
		dark.Transparency = if u > 0.01 then 0 else 1
	end
	local hidden = leaf.hidden
	if hidden then
		hidden.LocalTransparencyModifier = 1
	end
end

local function step(dt: number)
	for leaf in moving do
		leaf.t = math.min(1, leaf.t + dt / math.max(leaf.time, 0.01))
		local to = if leaf.opening then 1 else 0
		pcall(pose, leaf, leaf.from + (to - leaf.from) * DoorSwing.ease(leaf.t, leaf.opening))
		if leaf.t >= 1 then
			moving[leaf] = nil
			if not leaf.opening then
				Sounds.playAt("car_door_close", leaf.at, D.Sound.Shut, D.Sound.ShutPitch, D.Sound.Range) -- (it meets its frame)
			end
		end
	end
	if next(moving) == nil and stepper then
		stepper:Disconnect()
		stepper = nil
	end
end

-- Open or shut it: swung from where it is now (a swing turned round midway takes only the rest of its time); `now`: at
-- once (first seen that way).
local function swing(leaf: Leaf, open: boolean, now: boolean)
	if now then
		moving[leaf] = nil
		leaf.opening = open
		pcall(pose, leaf, if open then 1 else 0)
		return
	end
	if leaf.opening == open and (moving[leaf] or leaf.u == (if open then 1 else 0)) then
		return
	end
	leaf.opening = open
	local rest = if open then 1 - leaf.u else leaf.u
	if rest <= 0.001 then
		moving[leaf] = nil
		return
	end
	-- (from where it is now: a swing turned round midway goes on from there, the rest of the way in its share of the time)
	leaf.from, leaf.t = leaf.u, 0
	leaf.time = (if open then D.Open else D.Close) * rest
	if open then
		Sounds.playAt("house_door_creak", leaf.at, D.Sound.Open, 1, D.Sound.Range)
	end
	moving[leaf] = true
	if not stepper then
		stepper = RunService.Heartbeat:Connect(step)
	end
end

local function forget(inst: Instance)
	local leaf = leaves[inst]
	if not leaf then
		return
	end
	leaves[inst] = nil
	moving[leaf] = nil
	for _, hook in leaf.hooks do
		hook:Disconnect()
	end
	for _, made in leaf.made do
		made:Destroy()
	end
	local hidden = leaf.hidden
	if hidden and hidden.Parent then
		hidden.LocalTransparencyModifier = 0
	end
	if inst.Parent then
		pcall(pose, leaf, 0) -- (back where the server has it)
	end
end

-- A half of a double door: a copy of its part, its looks only (no tag, no attributes, no prompt: never a leaf itself),
-- made here.
local LOOKS = { Decal = true, Texture = true, SurfaceGui = true, SurfaceAppearance = true, SpecialMesh = true }
local function half(part: BasePart, frame: CFrame, size: Vector3): BasePart
	local copy = part:Clone()
	for _, tag in CollectionService:GetTags(copy) do
		CollectionService:RemoveTag(copy, tag)
	end
	for name in copy:GetAttributes() do
		copy:SetAttribute(name, nil)
	end
	for _, child in copy:GetChildren() do
		if not LOOKS[child.ClassName] then
			child:Destroy()
		end
	end
	copy.Name = "DoorHalf"
	copy.Size = size
	copy.CFrame = frame
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Parent = part
	return copy
end

local function watch(inst: Instance)
	if inst:IsA("Model") and not waiting[inst] then
		-- (a model's parts stream in and out, the model stays: looked at again as it is whenever they do)
		waiting[inst] = inst:GetPropertyChangedSignal("PrimaryPart"):Connect(function()
			forget(inst)
			pcall(watch, inst)
		end)
	end
	if leaves[inst] or not (inst:IsA("BasePart") or inst:IsA("Model")) or not visible(inst) then
		return
	end
	local hinge, side, angle = DoorSwing.read(inst:GetAttribute("DoorLeaf"), inst:GetAttribute("DoorSwing"), inst:GetAttribute("DoorAngle"), D.Angle)
	local frame, size = shape(inst)
	if hinge == nil or not frame or not size then
		return
	end
	if hinge == 0 and not inst:IsA("BasePart") then
		hinge = 1 -- (a model swings whole)
	end
	local leaf: Leaf = { inst = inst, pieces = {}, made = {}, dark = nil, hidden = nil, at = frame.Position, u = 0, from = 0, t = 1, opening = false, time = 0, hooks = {} }
	for _, s in DoorSwing.pieces(size.X, size.Z, hinge, side, angle) do
		local shut = frame * CFrame.new(s.ox, 0, s.oz)
		local moved: Instance = inst
		if hinge == 0 and inst:IsA("BasePart") then
			moved = half(inst, shut, Vector3.new(s.sx, size.Y, s.sz))
			table.insert(leaf.made, moved)
			leaf.hidden = inst
		end
		table.insert(leaf.pieces, { moved = moved, shut = shut, swing = s })
	end
	if inst:GetAttribute("DoorDark") == true then
		local dx, dy, dz = DoorSwing.dark(size.X, size.Y, size.Z)
		local dark = Instance.new("Part")
		dark.Name = "DoorDark"
		dark.Size = Vector3.new(dx, dy, dz)
		dark.CFrame = frame
		dark.Anchored = true
		dark.CanCollide = false
		dark.CanQuery = false
		dark.CanTouch = false
		dark.CastShadow = false
		dark.Material = Enum.Material.SmoothPlastic
		dark.Color = Color3.fromRGB(24, 18, 14) -- (a dark hall behind the open door)
		dark.Transparency = 1
		dark.Parent = if inst:IsA("BasePart") then inst else inst.Parent -- (a model's would swing with it)
		leaf.dark = dark
		table.insert(leaf.made, dark)
	end
	leaves[inst] = leaf
	table.insert(leaf.hooks, inst:GetAttributeChangedSignal("DoorOpen"):Connect(function()
		swing(leaf, inst:GetAttribute("DoorOpen") == true, false)
	end))
	if inst:GetAttribute("DoorOpen") == true then
		swing(leaf, true, true)
	elseif leaf.hidden then
		pose(leaf, 0)
	end
end

-- The camera behind your body, looking along `look` (flat), the way it is set now kept (its height and distance).
function WalkDoors.behind(look: Vector3)
	if CameraRig.face(look) then
		return
	end
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local way = Vector3.new(look.X, 0, look.Z)
	if not camera or camera.CameraType ~= Enum.CameraType.Custom or not root or not root:IsA("BasePart") or way.Magnitude < 1e-3 then
		return
	end
	local offset = camera.CFrame.Position - camera.Focus.Position
	local across = Vector3.new(offset.X, 0, offset.Z).Magnitude
	local subject = root.Position + Vector3.new(0, 1.5, 0)
	camera.CFrame = CFrame.lookAt(subject - way.Unit * math.max(across, 4) + Vector3.new(0, offset.Y, 0), subject)
end

function WalkDoors.start()
	if started then
		return
	end
	started = true
	Fade.onArrive = WalkDoors.behind
	for _, inst in CollectionService:GetTagged(TAG) do
		pcall(watch, inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(inst: Instance)
		pcall(watch, inst)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst: Instance)
		local hook = waiting[inst]
		if hook then
			waiting[inst] = nil
			hook:Disconnect()
		end
		pcall(forget, inst)
	end)
end

return WalkDoors
