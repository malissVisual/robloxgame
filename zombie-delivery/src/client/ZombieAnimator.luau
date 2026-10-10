--!strict
-- Animates the zombies and bandits on this client: a shambling walk (legs swing with the speed, arms sway out in
-- front), a twitchy head, a frantic clawing for the ones hanging on a car, a steady aim for the bandits.
-- Only joint transforms, no animation assets. The R15 bodies walk with their Animator (server); the bandits among
-- them hold their guns up with the players' aim pose (client/ArmPose.luau) laid over it.
-- The joints can be Motor6Ds or AnimationConstraints (shared/Joints.luau).
-- 6.13.1 (performance): the zombies are a list kept by the folder's ChildAdded / ChildRemoved (streaming too: a zombie
-- that streams out is forgotten), not a new GetChildren every frame; an R15 body is known once; a phone animates only
-- the nearer ones (client/DeviceBudget.luau).
-- 6.16, zombies with a life of their own: the R15 bodies get a pose of their own laid over the stock zombie animations
-- (the server's Animator) through client/PoseLedger.luau, the maths shared/ZombieStyle.luau's (ZombieStyle.pose) from
-- the model's Seed attribute (its gait), its speed, the stock walk's left thigh, Attack (a lunge and a swipe) and Hit
-- (a flinch, a bigger one with a stagger on a headshot, a punch, a ram or a blast; the people flinch too, ArmPose keeps
-- their arms): the walkers' and soldiers' shamble (a limp, a hunch, the head on one side, an arm hanging lower), the
-- runners' lurch, the brutes' stomp, a slow sway while they wait, clawing on a car. Only the Config.ZombieLife MaxPosed
-- nearest within Range of the camera (a phone fewer and nearer: DeviceBudget), picked every Retarget s; within Near
-- worked out every frame, farther every FarEvery frames (the pose kept in between); one that stops being posed (far,
-- dead) gets its joints back to the animation. The sounds hook in (client/ZombieLife.luau): ZombieAnimator.onHit /
-- onAttack / onDeath / onStomp; ZombieAnimator.list() is the zombies' models (read it, never change it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Joints = require(Shared:WaitForChild("Joints"))
local Config = require(Shared:WaitForChild("Config"))
local ZombieStyle = require(Shared:WaitForChild("ZombieStyle"))
local ArmPose = require(script.Parent.ArmPose)
local DeviceBudget = require(script.Parent.DeviceBudget)
local Ledger = require(script.Parent.PoseLedger)

local ZombieAnimator = {}

-- 6.16, set by client/ZombieLife.luau (the sounds): a hit (how: ZombieStyle.hitOf), a bite or a swipe, a death, a
-- brute's step; only for the bodies within Config.ZombieLife.Range.
ZombieAnimator.onHit = nil :: ((model: Model, code: number) -> ())?
ZombieAnimator.onAttack = nil :: ((model: Model) -> ())?
ZombieAnimator.onDeath = nil :: ((model: Model) -> ())?
ZombieAnimator.onStomp = nil :: ((model: Model, at: Vector3) -> ())?

type Rig = {
	root: BasePart,
	humanoid: Humanoid,
	neck: any, -- Motor6D or AnimationConstraint
	leftArm: any,
	rightArm: any,
	leftLeg: any,
	rightLeg: any,
	phase: number,
	stride: number, -- walking phase, advances with the speed
}

local rigs: { [Model]: Rig } = {}
local RANGE = 220
local zombies: { Model } = {} -- the Zombies folder's models
local bodies: { [Model]: boolean } = {} -- the ones known to be real R15 bodies

local function find(model: Model, name: string): any
	local found: Instance? = nil
	for _, d in model:GetDescendants() do
		if d.Name == name and Joints.isJoint(d) then
			if d:IsA("AnimationConstraint") then
				return d
			end
			found = found or d
		end
	end
	return found
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

local function set(joint: any, cframe: CFrame)
	if joint and joint.Parent then
		joint.Transform = cframe
	end
end

-- ── 6.16: the R15 bodies' own life ─────────────────────────────────────────

local Tuning = Config.ZombieLife

type Life = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	gait: ZombieStyle.Gait,
	person: boolean, -- a bandit or a gunner: only the flinch (ArmPose has the arms)
	joints: { any }, -- Root, Waist, Neck, LeftShoulder, RightShoulder (the ones written)
	thigh: any, -- LeftHip: the stock walk's step, read
	pose: ZombieStyle.Pose,
	motion: ZombieStyle.Motion,
	values: { CFrame }, -- the offsets last worked out, one per joint
	attackAt: number,
	hitAt: number,
	distance: number,
	computed: number, -- the frame they were worked out
	posed: boolean,
	stepped: boolean, -- a brute's thigh is out (its stomp was heard)
	links: { RBXScriptConnection },
}

local lives: { [Model]: Life } = {}
local waiting: { [Model]: number } = {} -- a body still missing a joint: looked at again from then on
local posed: { Life } = {} -- the ones posed now (picked every Retarget s)
local order: { Life } = {}
local frame = 0
local nextRetarget = 0
local JOINTS = { { "LowerTorso", "Root" }, { "UpperTorso", "Waist" }, { "Head", "Neck" }, { "LeftUpperArm", "LeftShoulder" }, { "RightUpperArm", "RightShoulder" } }

local function forget(model: Model)
	local life = lives[model]
	if not life then
		return
	end
	lives[model] = nil
	life.posed = false -- (out of `posed` at the next retarget)
	for _, link in life.links do
		link:Disconnect()
	end
end

local function lifeOf(model: Model, now: number): Life?
	local life = lives[model]
	if life then
		return life
	end
	if waiting[model] and now < waiting[model] then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local thigh = Joints.find(model:FindFirstChild("LeftUpperLeg"), "LeftHip")
	local joints: { any } = {}
	for _, j in JOINTS do
		local joint = Joints.find(model:FindFirstChild(j[1]), j[2])
		if not joint then
			break
		end
		table.insert(joints, joint)
	end
	if not (root and root:IsA("BasePart") and humanoid and thigh and #joints == #JOINTS) then
		waiting[model] = now + 1
		return nil
	end
	waiting[model] = nil
	local kind = model:GetAttribute("Zombie")
	local seed = model:GetAttribute("Seed")
	local gait = ZombieStyle.gait(if type(kind) == "string" then kind else "walker", if type(seed) == "number" then seed else 0)
	local made: Life = {
		model = model,
		humanoid = humanoid,
		root = root,
		gait = gait,
		person = gait.style == "person" or model:GetAttribute("Bandit") == true,
		joints = joints,
		thigh = thigh,
		pose = ZombieStyle.newPose(),
		motion = { speed = 0, legs = 0, t = 0, attack = -1, attackSide = 1, hit = -1, hitCode = 0, hitSide = 1, latched = false },
		values = { CFrame.identity, CFrame.identity, CFrame.identity, CFrame.identity, CFrame.identity },
		attackAt = -math.huge,
		hitAt = -math.huge,
		distance = math.huge,
		computed = -math.huge,
		posed = false,
		stepped = false,
		links = {},
	}
	table.insert(made.links, model:GetAttributeChangedSignal("Hit"):Connect(function()
		local mark = model:GetAttribute("Hit")
		if type(mark) ~= "number" then
			return
		end
		made.hitAt = os.clock()
		made.motion.hitCode = ZombieStyle.hitOf(mark)
		made.motion.hitSide = if math.random() < 0.5 then -1 else 1
		made.computed = -math.huge -- (worked out again at once)
		local onHit = ZombieAnimator.onHit
		if onHit then
			onHit(model, made.motion.hitCode)
		end
	end))
	table.insert(made.links, model:GetAttributeChangedSignal("Attack"):Connect(function()
		local count = model:GetAttribute("Attack")
		made.attackAt = os.clock()
		made.motion.attackSide = if type(count) == "number" and count % 2 == 0 then -1 else 1
		made.computed = -math.huge
		local onAttack = ZombieAnimator.onAttack
		if onAttack then
			onAttack(model)
		end
	end))
	table.insert(made.links, humanoid.Died:Connect(function()
		local onDeath = ZombieAnimator.onDeath
		if onDeath then
			onDeath(model)
		end
	end))
	lives[model] = made
	return made
end

-- Back to the animation (no longer posed: far, out of the nearest, dead or gone).
local function unpose(life: Life)
	life.posed = false
	for _, joint in life.joints do
		if joint.Parent then
			Ledger.release(joint)
		end
	end
end

-- The nearest living R15 bodies within the range get posed (every Retarget s).
local function retarget(eye: Vector3, now: number)
	local range = DeviceBudget.range(Tuning.Range)
	table.clear(order)
	for _, model in zombies do
		if not bodies[model] then
			continue
		end
		local life = lifeOf(model, now)
		if life and life.humanoid.Health > 0 and life.root.Parent then
			life.distance = (life.root.Position - eye).Magnitude
			if life.distance <= range then
				table.insert(order, life)
			end
		end
	end
	table.sort(order, function(a: Life, b: Life): boolean
		return a.distance < b.distance
	end)
	local count = DeviceBudget.count(Tuning.MaxPosed)
	for i = count + 1, #order do
		order[i] = nil
	end
	for _, life in posed do
		if life.posed and not table.find(order, life) then
			unpose(life)
		end
	end
	table.clear(posed)
	for _, life in order do
		life.posed = true
		table.insert(posed, life)
	end
end

local rad = math.rad

local function work(life: Life, t: number)
	local m = life.motion
	local v = life.root.AssemblyLinearVelocity
	m.speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local thigh = Ledger.base(life.thigh):ToEulerAnglesXYZ()
	m.legs = thigh / rad(Tuning.HipSwing)
	m.t = t
	m.attack = if t - life.attackAt < Tuning.AttackTime then t - life.attackAt else -1
	m.hit = if t - life.hitAt < Tuning.HardTime then t - life.hitAt else -1
	m.latched = life.model:GetAttribute("LatchedTo") ~= nil
	local p = ZombieStyle.pose(life.pose, life.gait, m)
	local values = life.values
	values[1] = CFrame.new(0, p.rootY, p.rootZ)
	values[2] = CFrame.Angles(p.waistPitch, 0, p.waistRoll)
	values[3] = CFrame.Angles(p.neckPitch, p.neckYaw, p.neckRoll)
	values[4] = CFrame.Angles(p.leftArm, 0, p.leftArmRoll)
	values[5] = CFrame.Angles(p.rightArm, 0, p.rightArmRoll)
	-- A brute's stomp: heard as a thigh swings out.
	if life.gait.style == "stomp" then
		local out = math.abs(m.legs) > 0.85 and m.speed > 2
		local onStomp = ZombieAnimator.onStomp
		if out and not life.stepped and onStomp then
			onStomp(life.model, life.root.Position)
		end
		life.stepped = out
	end
end

local function lay(life: Life)
	-- The people: the waist and the head only (ArmPose has their arms; their root is left alone).
	local from, to = if life.person then 2 else 1, if life.person then 3 else 5
	for i = from, to do
		local joint = life.joints[i]
		if joint.Parent then
			Ledger.write(joint, Ledger.now(joint) * life.values[i])
		end
	end
end

local function lifeStep(eye: Vector3)
	frame += 1
	local t = os.clock()
	if t >= nextRetarget then
		nextRetarget = t + Tuning.Retarget
		retarget(eye, t)
	end
	local near = DeviceBudget.range(Tuning.Near)
	for _, life in posed do
		if not life.posed then
			continue
		end
		if life.humanoid.Health <= 0 or not life.root.Parent then
			unpose(life)
			continue
		end
		if life.distance <= near or frame - life.computed >= Tuning.FarEvery then
			life.computed = frame
			work(life, t)
		end
		lay(life)
	end
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera or #zombies == 0 then
		return
	end
	local eye = camera.CFrame.Position
	local t = os.clock()
	local range = DeviceBudget.range(RANGE)
	for _, model in zombies do
		if not bodies[model] and model:FindFirstChild("UpperTorso") then
			bodies[model] = true
		end
		if bodies[model] then
			-- A real R15 body: animated by its Animator (server). A bandit holds the gun up over the walk.
			if model:GetAttribute("Bandit") then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				local root = model:FindFirstChild("HumanoidRootPart")
				if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") and (root.Position - eye).Magnitude <= range then
					ArmPose.apply(model, 1, 0)
				end
			end
			continue
		end
		local rig = rigOf(model)
		if not rig or rig.humanoid.Health <= 0 then
			continue
		end
		if (rig.root.Position - eye).Magnitude > range then
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
		if model:GetAttribute("Bandit") then
			-- Bandits hold the gun steady and look around.
			set(rig.leftArm, CFrame.identity)
			set(rig.rightArm, CFrame.Angles(math.sin(p * 1.5) * 0.04, 0, 0))
			set(rig.neck, CFrame.Angles(0, math.sin(p * 0.9) * 0.25, 0))
			continue
		end
		set(rig.leftArm, CFrame.Angles(math.sin(p * 2.1) * 0.15 - swing * 0.2, 0, math.sin(p * 1.3) * 0.1))
		set(rig.rightArm, CFrame.Angles(math.sin(p * 2.4 + 1) * 0.15 + swing * 0.2, 0, math.sin(p * 1.7) * 0.1))
		set(rig.neck, CFrame.Angles(math.sin(p * 3.3) * 0.1, math.sin(p * 0.7) * 0.3, math.sin(p * 5) * 0.06))
	end
	-- 6.16: after the bandits' aim, the R15 bodies' own life (composed over what is there).
	lifeStep(eye)
end

-- 6.13.1: the folder's zombies as a list (made by the server, maybe after this client starts).
local function watch(folder: Instance)
	local function add(child: Instance)
		if child:IsA("Model") and not table.find(zombies, child) then
			table.insert(zombies, child)
		end
	end
	for _, child in folder:GetChildren() do
		add(child)
	end
	folder.ChildAdded:Connect(add)
	folder.ChildRemoved:Connect(function(child: Instance)
		if not child:IsA("Model") then
			return
		end
		local at = table.find(zombies, child)
		if at then
			table.remove(zombies, at)
		end
		rigs[child] = nil
		bodies[child] = nil
		forget(child) -- 6.16
		waiting[child] = nil
	end)
end

-- 6.16: the zombies' models (client/ZombieLife.luau: the eyes, the voices). Read it, never change it.
function ZombieAnimator.list(): { Model }
	return zombies
end

function ZombieAnimator.start()
	-- After the animations, before the engine applies the joints.
	RunService.PreSimulation:Connect(step)
	local folder = workspace:FindFirstChild("Zombies")
	if folder then
		watch(folder)
	else
		local hook: RBXScriptConnection? = nil
		hook = workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Zombies" and #zombies == 0 then
				if hook then
					hook:Disconnect()
				end
				watch(child)
			end
		end)
	end
end

return ZombieAnimator
