--!strict
-- Animates the animals (workspace.Animals, server/Animals.luau) on this client, only near the camera: the legs swing
-- with the speed (a four-beat walk that turns into a trot when the horse hurries, the knees fold as a leg swings
-- forward), the neck nods with the steps, the tail swishes, and a grazing horse lowers its head to the grass and
-- chews. A horse riding in a vehicle (Stabled) stands still and only breathes and swishes its tail.
-- Only joint Transforms, written in PreSimulation (after the animations, before the engine applies the joints).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Joints = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Joints"))
local DeviceBudget = require(script.Parent.DeviceBudget) -- 6.13.1: a phone animates only the nearer animals

local AnimalAnimator = {}

local RANGE = 180
local STRIDE = 7 -- studs per full step cycle at a walk
local TAU = math.pi * 2
local NECK_UP = Vector3.new(0, math.cos(math.rad(40)), math.sin(math.rad(40)))

type Leg = { hip: any, knee: any, walk: number, trot: number, front: boolean }
type Rig = {
	root: BasePart,
	legs: { Leg },
	neck: any,
	head: any,
	tail: any,
	stride: number,
	graze: number, -- 0 = head up, 1 = head down in the grass (smoothed)
	speed: number, -- smoothed
	seed: number,
}

local rigs: { [Model]: Rig } = {}
local watched: { [Model]: boolean } = {} -- (its Destroying hooked once)

-- The four-beat walk (left hind, left fore, right hind, right fore) and the two-beat trot (diagonal pairs).
local GAIT: { { id: string, walk: number, trot: number, front: boolean } } = {
	{ id = "HL", walk = 0, trot = 0, front = false },
	{ id = "FL", walk = 0.25, trot = 0.5, front = true },
	{ id = "HR", walk = 0.5, trot = 0.5, front = false },
	{ id = "FR", walk = 0.75, trot = 0, front = true },
}

local function rigOf(model: Model): Rig?
	local rig = rigs[model]
	if rig and rig.root.Parent == model then
		return rig
	end
	-- (6.13.1, StreamingEnabled: an animal's parts streamed out and back in are new ones: its joints looked up again)
	rigs[model] = nil
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local legs: { Leg } = {}
	for _, g in GAIT do
		local upper = model:FindFirstChild("Leg" .. g.id)
		local hip = Joints.find(root, "Hip" .. g.id)
		local knee = Joints.find(upper, "Knee" .. g.id)
		if hip then
			table.insert(legs, { hip = hip, knee = knee, walk = g.walk, trot = g.trot, front = g.front })
		end
	end
	local neckPart = model:FindFirstChild("Neck")
	if #legs < 4 or not neckPart then
		return nil -- not all streamed in yet: try again next frame
	end
	local made: Rig = {
		root = root,
		legs = legs,
		neck = Joints.find(root, "Neck"),
		head = Joints.find(neckPart, "Head"),
		tail = Joints.find(root, "Tail"),
		stride = math.random() * TAU,
		graze = if model:GetAttribute("Grazing") then 1 else 0,
		speed = 0,
		seed = math.random() * 100,
	}
	rigs[model] = made
	if not watched[model] then
		watched[model] = true
		model.Destroying:Connect(function()
			rigs[model] = nil
			watched[model] = nil
		end)
	end
	return made
end

local function set(joint: any, cframe: CFrame)
	if joint and joint.Parent then
		joint.Transform = cframe
	end
end

local function animate(model: Model, rig: Rig, dt: number, t: number)
	local root = rig.root
	local speed = 0
	if not root.Anchored and not model:GetAttribute("Stabled") then
		local v = root.AssemblyLinearVelocity
		speed = Vector3.new(v.X, 0, v.Z).Magnitude
	end
	rig.speed += (speed - rig.speed) * math.min(dt * 8, 1)
	speed = rig.speed
	local amount = math.clamp(speed / 4, 0, 1) -- how much the legs move
	local trot = math.clamp((speed - 9) / 4, 0, 1) -- 0 walk … 1 trot
	rig.stride = (rig.stride + dt * speed / STRIDE * TAU) % (TAU * 100)

	for _, leg in rig.legs do
		local offset = leg.walk + (leg.trot - leg.walk) * trot
		local p = rig.stride + offset * TAU
		local reach = (0.3 + 0.16 * trot) * amount
		local swing = math.sin(p) * reach -- + = the hoof forward
		-- The knee folds while the leg swings forward (the hoof is in the air), the hind hock a little less.
		local lift = math.max(math.cos(p), 0) * (0.75 + 0.45 * trot) * amount * (if leg.front then 1 else 0.8)
		set(leg.hip, CFrame.Angles(swing, 0, 0))
		set(leg.knee, CFrame.Angles(-lift, 0, 0))
	end

	-- Grazing: the head goes down to the grass (only while standing).
	local grazeTarget = if model:GetAttribute("Grazing") and speed < 1 then 1 else 0
	rig.graze += (grazeTarget - rig.graze) * math.min(dt * 0.9, 1)
	local graze = rig.graze
	local breathe = math.sin(t * 1.3 + rig.seed) * 0.02
	local nod = math.sin(rig.stride * 2) * (0.05 + 0.05 * trot) * amount
	local glance = math.sin(t * 0.35 + rig.seed) * 0.18 * (1 - amount) * (1 - graze)
	-- (the neck joint leans 40° forward: turning sideways is a turn about the world's up axis in its frame)
	-- Grazing: the neck swings ~80° down, the head turns up against it so the muzzle points down-forward at the grass.
	set(rig.neck, CFrame.fromAxisAngle(NECK_UP, glance) * CFrame.Angles(-1.4 * graze + nod + breathe, 0, 0))
	local chew = math.sin(t * 6 + rig.seed) * 0.05 * graze
	set(rig.head, CFrame.Angles(0.7 * graze + chew + math.sin(t * 0.8 + rig.seed) * 0.04 * (1 - graze), 0, 0))
	-- The tail swishes now and then, and lifts a little at a trot.
	local swish = math.sin(t * 1.6 + rig.seed) * (0.18 + 0.2 * math.max(math.sin(t * 0.23 + rig.seed), 0))
	set(rig.tail, CFrame.Angles(-0.3 * trot + math.sin(rig.stride) * 0.05 * amount, 0, swish))
end

local function step(dt: number)
	local folder = workspace:FindFirstChild("Animals")
	local camera = workspace.CurrentCamera
	if not folder or not camera then
		return
	end
	local eye = camera.CFrame.Position
	local t = os.clock()
	local range = DeviceBudget.range(RANGE)
	for _, model in folder:GetChildren() do
		if not model:IsA("Model") then
			continue
		end
		local rig = rigOf(model)
		if not rig or not rig.root.Parent then
			continue
		end
		if (rig.root.Position - eye).Magnitude > range then
			continue
		end
		animate(model, rig, dt, t)
	end
end

function AnimalAnimator.start()
	RunService.PreSimulation:Connect(step)
end

return AnimalAnimator
