--!strict
-- Animals: the horses of Silver Spur Ranch. A horse is a model built from parts (a round barrel of a body, chest and
-- rump, an arched neck with a mane, a head with ears, eyes and a halter, a tail and four legs with knees), about 8
-- studs long and as tall at the withers as a person. The legs, the neck, the head and the tail hang on Motor6Ds that
-- the clients swing with the speed (client/AnimalAnimator.luau); the horse moves with its own Humanoid (MoveTo).
--
-- It can stand (anchored, no physics: cheap), walk to a point, graze and wander in a paddock, follow someone on a
-- lead rope (a rope Beam from the halter ring to the leader's right hand, a few studs behind them) and ride in a
-- vehicle's stall (welded, massless). Horses are in their own collision group and touch nothing (the Humanoid keeps
-- them on the ground): cars, people and bullets pass through them, and they never get stuck on a fence.

local PhysicsService = game:GetService("PhysicsService")

local Animals = {}

local GROUP = "Animal"
local ROOT_Y = 3.9 -- the root's centre over the ground (the middle of the body)
local ROOT_SIZE = Vector3.new(1.6, 1.6, 3)
local FOLLOW = 5 -- studs behind the leader
local ROPE = 7 -- the lead rope's length (it sags when the horse is closer)
local WALK_SPEED = 7

-- Coats: body, mane and tail.
local COATS: { { body: { number }, hair: { number } } } = {
	{ body = { 118, 72, 42 }, hair = { 34, 26, 22 } }, -- bay
	{ body = { 152, 86, 44 }, hair = { 120, 64, 34 } }, -- chestnut
	{ body = { 52, 42, 36 }, hair = { 26, 22, 20 } }, -- black
	{ body = { 200, 196, 188 }, hair = { 170, 168, 162 } }, -- grey
	{ body = { 214, 176, 112 }, hair = { 240, 232, 210 } }, -- palomino
	{ body = { 96, 62, 42 }, hair = { 40, 30, 24 } }, -- dark bay
}
local HALTERS = { { 170, 40, 36 }, { 40, 80, 160 }, { 40, 120, 70 }, { 60, 44, 32 } }

type Horse = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	halter: Attachment,
	leader: Model?,
	rope: Beam?,
	hand: Attachment?,
	walkToken: number,
	stall: WeldConstraint?,
	roaming: boolean,
}

local horses: { [Model]: Horse } = {}
local folder: Folder? = nil
local looping = false
local rng = Random.new(4242)

local function init(): Folder
	if folder and folder.Parent then
		return folder
	end
	for _, name in { GROUP, "Car", "EnemyCar", "Zombie", "Bullet", "Corpse", "Npc" } do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	for _, other in { "Car", "EnemyCar", "Zombie", "Bullet", "Corpse", "Npc", GROUP } do
		pcall(function()
			PhysicsService:CollisionGroupSetCollidable(GROUP, other, false)
		end)
	end
	local f = workspace:FindFirstChild("Animals")
	if not f or not f:IsA("Folder") then
		f = Instance.new("Folder")
		f.Name = "Animals"
		f.Parent = workspace
	end
	folder = f :: Folder
	return f :: Folder
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- ── The body ───────────────────────────────────────────────────────────────

local function piece(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CollisionGroup = GROUP
	p.Parent = model
	return p
end

-- A part fixed to `on` at `offset`.
local function stick(model: Model, on: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = piece(model, name, size, color, material, shape)
	p.CFrame = on.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = on
	w.Part1 = p
	w.Parent = p
	return p
end

-- A part on a joint the clients move (Part0.CFrame * C0 * Transform = Part1.CFrame * C1). Our own Motor6Ds: C0 and
-- C1 are set once here, before the joint exists; the animator only writes Transform.
local function hinge(model: Model, name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	part1.CFrame = part0.CFrame * c0 * c1:Inverse()
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
end

local function build(coatIndex: number, halterColor: Color3, socks: { boolean }, blaze: boolean): (Model, BasePart, Humanoid, Attachment)
	local coat = COATS[coatIndex]
	local body = rgb(coat.body)
	local hair = rgb(coat.hair)
	local dark = body:Lerp(Color3.new(0, 0, 0), 0.25)
	local hoofColor = Color3.fromRGB(44, 38, 34)
	local white = Color3.fromRGB(236, 232, 224)
	local model = Instance.new("Model")
	model.Name = "Horse"

	local root = piece(model, "HumanoidRootPart", ROOT_SIZE, body)
	root.Transparency = 1
	root.Massless = false
	root.CFrame = CFrame.new(0, ROOT_Y, 0)

	-- The barrel, the chest and the rump.
	stick(model, root, "Body", Vector3.new(4.4, 2.5, 2.5), CFrame.new(0, 0.05, 0) * CFrame.Angles(0, math.rad(90), 0), body, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	stick(model, root, "Chest", Vector3.new(2.6, 2.6, 2.6), CFrame.new(0, 0.12, -2.1), body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	stick(model, root, "Rump", Vector3.new(2.75, 2.75, 2.75), CFrame.new(0, 0.2, 2.05), body, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	stick(model, root, "Withers", Vector3.new(1.0, 0.7, 1.8), CFrame.new(0, 1.15, -1.6) * CFrame.Angles(math.rad(-12), 0, 0), body, Enum.Material.SmoothPlastic)
	stick(model, root, "Belly", Vector3.new(2.1, 0.5, 3.6), CFrame.new(0, -1.05, 0), dark, Enum.Material.SmoothPlastic)

	-- The neck, arched up and forward from the chest, with the mane along its top.
	local neck = piece(model, "Neck", Vector3.new(1.0, 3.2, 1.55), body, Enum.Material.SmoothPlastic)
	hinge(model, "Neck", root, neck, CFrame.new(0, 0.7, -2.55) * CFrame.Angles(math.rad(-40), 0, 0), CFrame.new(0, -1.3, 0))
	stick(model, neck, "Mane", Vector3.new(0.32, 3.1, 0.5), CFrame.new(0, 0.15, 0.78), hair, Enum.Material.Fabric)
	stick(model, neck, "Throat", Vector3.new(0.9, 1.6, 1.2), CFrame.new(0, 0.8, -0.35), body, Enum.Material.SmoothPlastic)

	-- The head: skull, muzzle, ears, eyes, nostrils, forelock and the halter.
	local head = piece(model, "Head", Vector3.new(0.92, 0.98, 1.45), body, Enum.Material.SmoothPlastic)
	hinge(model, "Head", neck, head, CFrame.new(0, 1.5, 0.1), CFrame.new(0, 0.12, 0.62))
	stick(model, head, "Muzzle", Vector3.new(0.78, 0.8, 1.25), CFrame.new(0, -0.08, -1.22), body, Enum.Material.SmoothPlastic)
	stick(model, head, "Nose", Vector3.new(0.74, 0.62, 0.3), CFrame.new(0, -0.14, -1.86), dark, Enum.Material.SmoothPlastic)
	stick(model, head, "Jaw", Vector3.new(0.96, 0.7, 0.9), CFrame.new(0, -0.3, 0.2), body, Enum.Material.SmoothPlastic)
	for _, side in { -1, 1 } do
		stick(model, head, "Ear", Vector3.new(0.18, 0.58, 0.3), CFrame.new(side * 0.27, 0.72, 0.5) * CFrame.Angles(math.rad(-10), 0, math.rad(side * -12)), body, Enum.Material.SmoothPlastic)
		stick(model, head, "Eye", Vector3.new(0.24, 0.24, 0.24), CFrame.new(side * 0.44, 0.2, -0.28), Color3.fromRGB(18, 14, 12), Enum.Material.Glass, Enum.PartType.Ball)
		stick(model, head, "Nostril", Vector3.new(0.14, 0.14, 0.14), CFrame.new(side * 0.22, -0.06, -2.0), Color3.fromRGB(26, 20, 18), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
		-- Halter: the cheek straps.
		stick(model, head, "HalterCheek", Vector3.new(0.05, 0.12, 1.55), CFrame.new(side * 0.47, -0.12, -0.25) * CFrame.Angles(math.rad(-8), 0, 0), halterColor, Enum.Material.Fabric)
	end
	stick(model, head, "Forelock", Vector3.new(0.5, 0.18, 0.5), CFrame.new(0, 0.52, 0.3), hair, Enum.Material.Fabric)
	if blaze then
		stick(model, head, "Blaze", Vector3.new(0.3, 0.06, 1.9), CFrame.new(0, 0.42, -0.85) * CFrame.Angles(math.rad(-9), 0, 0), white, Enum.Material.SmoothPlastic)
	end
	stick(model, head, "HalterNose", Vector3.new(0.86, 0.88, 0.16), CFrame.new(0, -0.08, -1.0), halterColor, Enum.Material.Fabric)
	stick(model, head, "HalterCrown", Vector3.new(1.0, 1.04, 0.15), CFrame.new(0, 0.02, 0.5), halterColor, Enum.Material.Fabric)
	local ring = stick(model, head, "HalterRing", Vector3.new(0.22, 0.22, 0.22), CFrame.new(0, -0.5, -0.95), Color3.fromRGB(190, 190, 196), Enum.Material.Metal, Enum.PartType.Ball)
	local halter = Instance.new("Attachment")
	halter.Name = "LeadRing"
	halter.Parent = ring
	halter.Axis = Vector3.new(0, -1, 0) -- the rope sags down from here (Beam curve)
	halter.SecondaryAxis = Vector3.new(1, 0, 0)

	-- The tail hangs down and a little back; its long hair is a second, wider piece.
	local tail = piece(model, "Tail", Vector3.new(0.42, 1.5, 0.42), hair, Enum.Material.Fabric)
	hinge(model, "Tail", root, tail, CFrame.new(0, 1.05, 3.2) * CFrame.Angles(math.rad(-28), 0, 0), CFrame.new(0, 0.65, 0))
	stick(model, tail, "TailHair", Vector3.new(0.6, 1.9, 0.55), CFrame.new(0, -1.4, 0.05), hair, Enum.Material.Fabric)

	-- The legs: the upper leg on the hip / shoulder joint, the cannon on the knee / hock, the hoof on the cannon.
	local legs = {
		{ id = "FL", x = -0.62, z = -2.0, front = true },
		{ id = "FR", x = 0.62, z = -2.0, front = true },
		{ id = "HL", x = -0.66, z = 2.0, front = false },
		{ id = "HR", x = 0.66, z = 2.0, front = false },
	}
	for n, leg in legs do
		local upperSize = if leg.front then Vector3.new(0.62, 1.7, 0.78) else Vector3.new(0.7, 1.7, 1.0)
		local upper = piece(model, "Leg" .. leg.id, upperSize, body, Enum.Material.SmoothPlastic)
		hinge(model, "Hip" .. leg.id, root, upper, CFrame.new(leg.x, -0.5, leg.z), CFrame.new(0, 0.75, 0))
		local cannon = piece(model, "Cannon" .. leg.id, Vector3.new(0.38, 1.5, 0.42), dark, Enum.Material.SmoothPlastic)
		hinge(model, "Knee" .. leg.id, upper, cannon, CFrame.new(0, -0.8, 0), CFrame.new(0, 0.7, 0))
		if socks[n] then
			stick(model, cannon, "Sock", Vector3.new(0.43, 0.55, 0.47), CFrame.new(0, -0.5, 0), white, Enum.Material.Fabric)
		end
		stick(model, cannon, "Hoof", Vector3.new(0.52, 0.42, 0.6), CFrame.new(0, -0.94, -0.05), hoofColor, Enum.Material.SmoothPlastic)
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- R15: HipHeight is the leg length
	humanoid.HipHeight = ROOT_Y - ROOT_SIZE.Y / 2
	humanoid.WalkSpeed = WALK_SPEED
	humanoid.MaxHealth = 1e6
	humanoid.Health = 1e6
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	for _, state in { Enum.HumanoidStateType.Dead, Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming, Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Jumping } do
		humanoid:SetStateEnabled(state, false)
	end
	humanoid.Parent = model
	model.PrimaryPart = root
	return model, root, humanoid, halter
end

-- ── Standing and moving ────────────────────────────────────────────────────

-- Stand still on the spot: anchored, upright, no physics.
local function stand(h: Horse)
	local root = h.root
	h.humanoid:MoveTo(root.Position)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	root.Anchored = true
	root.CFrame = if flat.Magnitude > 0.01 then CFrame.lookAt(root.Position, root.Position + flat) else CFrame.new(root.Position)
end

local function release(h: Horse)
	if h.stall then
		h.stall:Destroy()
		h.stall = nil
		h.humanoid.PlatformStand = false
	end
	h.root.Massless = false
	h.model:SetAttribute("Stabled", nil)
	h.root.Anchored = false
	pcall(function()
		h.root:SetNetworkOwner(nil)
	end)
end

local function dropRope(h: Horse)
	if h.rope then
		h.rope:Destroy()
		h.rope = nil
	end
	if h.hand then
		h.hand:Destroy()
		h.hand = nil
	end
	h.leader = nil
	h.model:SetAttribute("LedBy", nil)
end

-- A horse standing at `at` (hooves on the ground at at.Position, facing at.LookVector). Parented to workspace.Animals.
function Animals.horse(at: CFrame, coat: { number }?): Model
	local parent = init()
	local coatIndex = rng:NextInteger(1, #COATS)
	local socks = { rng:NextNumber() < 0.3, rng:NextNumber() < 0.3, rng:NextNumber() < 0.4, rng:NextNumber() < 0.4 }
	local model, root, humanoid, halter = build(coatIndex, rgb(HALTERS[rng:NextInteger(1, #HALTERS)]), socks, rng:NextNumber() < 0.4)
	if coat then
		-- A given coat colour: the body in it, the legs a shade darker.
		local color = rgb(coat)
		for _, d in model:GetChildren() do
			if d:IsA("BasePart") and (d.Name == "Body" or d.Name == "Chest" or d.Name == "Rump" or d.Name == "Withers" or d.Name == "Neck" or d.Name == "Throat" or d.Name == "Head" or d.Name == "Muzzle" or d.Name == "Jaw" or d.Name == "Ear" or d.Name:sub(1, 3) == "Leg") then
				d.Color = color
			elseif d:IsA("BasePart") and (d.Name:sub(1, 6) == "Cannon" or d.Name == "Belly" or d.Name == "Nose") then
				d.Color = color:Lerp(Color3.new(0, 0, 0), 0.25)
			end
		end
	end
	local look = Vector3.new(at.LookVector.X, 0, at.LookVector.Z)
	local facing = if look.Magnitude > 0.01 then CFrame.lookAt(at.Position, at.Position + look) else CFrame.new(at.Position)
	root.Anchored = true
	model:PivotTo(facing * CFrame.new(0, ROOT_Y, 0))
	model:SetAttribute("Animal", "horse")
	model.Parent = parent
	local h: Horse = {
		model = model,
		humanoid = humanoid,
		root = root,
		halter = halter,
		walkToken = 0,
		roaming = false,
	}
	horses[model] = h
	model.Destroying:Connect(function()
		dropRope(h)
		horses[model] = nil
	end)
	return model
end

-- Walk to a point, then call `arrived` (false when it could not get there in time).
function Animals.walkTo(horse: Model, point: Vector3, arrived: ((boolean) -> ())?)
	local h = horses[horse]
	if not h then
		if arrived then
			task.spawn(arrived, false)
		end
		return
	end
	dropRope(h)
	release(h)
	horse:SetAttribute("Grazing", nil)
	h.walkToken += 1
	local token = h.walkToken
	local root, humanoid = h.root, h.humanoid
	humanoid.WalkSpeed = WALK_SPEED
	local distance = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z).Magnitude
	local limit = distance / WALK_SPEED * 2 + 4
	task.spawn(function()
		local startedAt = os.clock()
		local ordered = -10
		local ok = false
		while horse.Parent and h.walkToken == token do
			local p = root.Position
			if Vector3.new(point.X - p.X, 0, point.Z - p.Z).Magnitude < 2 then
				ok = true
				break
			end
			if os.clock() - startedAt > limit then
				break
			end
			if os.clock() - ordered > 4 then
				humanoid:MoveTo(point)
				ordered = os.clock()
			end
			task.wait(0.1)
		end
		if not horse.Parent or h.walkToken ~= token then
			return
		end
		stand(h)
		if arrived then
			arrived(ok)
		end
	end)
end

-- ── The lead rope ──────────────────────────────────────────────────────────

local function handOf(character: Model): BasePart?
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	return if hand and hand:IsA("BasePart") then hand else nil
end

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	return if root and root:IsA("BasePart") then root else nil
end

-- The rope: a Beam from the halter ring to the hand, sagging more the closer the horse walks.
local function tieRope(h: Horse, leader: Model)
	local hand = handOf(leader) or rootOf(leader)
	if not hand then
		return
	end
	local grip = Instance.new("Attachment")
	grip.Name = "LeadRopeGrip"
	grip.Position = if hand.Name == "RightHand" then Vector3.new(0, -0.15, -0.1) else Vector3.new(0, -0.9, 0)
	grip.Axis = Vector3.new(0, 1, 0) -- the Beam's second control point goes against the axis: down
	grip.SecondaryAxis = Vector3.new(1, 0, 0)
	grip.Parent = hand
	local rope = Instance.new("Beam")
	rope.Name = "LeadRope"
	rope.Attachment0 = h.halter
	rope.Attachment1 = grip
	rope.Color = ColorSequence.new(Color3.fromRGB(150, 116, 70))
	rope.Width0 = 0.12
	rope.Width1 = 0.12
	rope.FaceCamera = true
	rope.Segments = 12
	rope.LightInfluence = 0.6
	rope.CurveSize0 = 1.2
	rope.CurveSize1 = 0.8
	rope.Parent = h.model
	h.rope = rope
	h.hand = grip
end

local function follow(h: Horse)
	local leader = h.leader
	local leaderRoot = if leader and leader.Parent then rootOf(leader) else nil
	if not leader or not leaderRoot then
		Animals.lead(h.model, nil)
		return
	end
	if h.hand and not h.hand.Parent then
		-- The leader's body was rebuilt (avatar loaded): tie the rope again.
		dropRope(h)
		h.leader = leader
		h.model:SetAttribute("LedBy", leader.Name)
		tieRope(h, leader)
	end
	local root = h.root
	local from, to = root.Position, leaderRoot.Position
	local away = Vector3.new(from.X - to.X, 0, from.Z - to.Z)
	local distance = away.Magnitude
	if distance > 40 then
		-- Left far behind (the leader teleported): catch up at once, behind them.
		local behind = to - leaderRoot.CFrame.LookVector * FOLLOW
		local center = Vector3.new(behind.X, to.Y - 3 + ROOT_Y, behind.Z) -- a character's root is ~3 over its feet
		h.model:PivotTo(CFrame.lookAt(center, Vector3.new(to.X, center.Y, to.Z)))
		return
	end
	if distance > FOLLOW + 0.6 then
		local target = to + away.Unit * FOLLOW
		h.humanoid.WalkSpeed = math.clamp((distance - FOLLOW) * 4, 5, 18)
		h.humanoid:MoveTo(Vector3.new(target.X, from.Y, target.Z))
	elseif distance < FOLLOW - 1.2 then
		h.humanoid:MoveTo(from) -- close enough: stop
	end
	-- The rope sags by the slack.
	local rope = h.rope
	if rope and h.hand then
		local slack = math.max(ROPE - (h.halter.WorldPosition - h.hand.WorldPosition).Magnitude, 0)
		rope.CurveSize0 = math.clamp(slack * 0.7, 0.1, 1.8)
		rope.CurveSize1 = math.clamp(slack * 0.5, 0.1, 1.3)
	end
end

local function ensureLoop()
	if looping then
		return
	end
	looping = true
	task.spawn(function()
		while true do
			task.wait(0.15)
			for _, h in horses do
				if h.leader then
					local ok, err = pcall(function()
						follow(h)
					end)
					if not ok then
						warn(`[Animals] {err}`)
					end
				end
			end
		end
	end)
end

-- Follow `leader` (a character) on a rope, a few studs behind; nil lets go (the horse stands).
function Animals.lead(horse: Model, leader: Model?)
	local h = horses[horse]
	if not h then
		return
	end
	if leader == nil then
		local wasLed = h.leader ~= nil
		dropRope(h)
		if wasLed and not h.stall then
			stand(h)
		end
		return
	end
	if h.leader == leader and h.rope then
		return
	end
	dropRope(h)
	h.walkToken += 1
	h.roaming = false
	horse:SetAttribute("Grazing", nil)
	release(h)
	h.leader = leader
	horse:SetAttribute("LedBy", leader.Name)
	tieRope(h, leader)
	ensureLoop()
end

-- Put the horse at a spot without walking: into a vehicle's stall (welded to `weldTo`, massless, rides along) or
-- tied up (anchored). Without `at` the horse is free again (it can walk).
function Animals.stable(horse: Model, at: CFrame?, weldTo: BasePart?)
	local h = horses[horse]
	if not h then
		return
	end
	if not at then
		release(h)
		stand(h)
		return
	end
	dropRope(h)
	h.walkToken += 1
	h.roaming = false
	horse:SetAttribute("Grazing", nil)
	if h.stall then
		h.stall:Destroy()
		h.stall = nil
	end
	h.humanoid:MoveTo(h.root.Position)
	h.root.Anchored = true
	local look = Vector3.new(at.LookVector.X, 0, at.LookVector.Z)
	local facing = if look.Magnitude > 0.01 then CFrame.lookAt(at.Position, at.Position + look) else CFrame.new(at.Position)
	horse:PivotTo(facing * CFrame.new(0, ROOT_Y, 0))
	horse:SetAttribute("Stabled", true)
	if weldTo then
		-- Part of the vehicle now: the Humanoid rests, the root weighs nothing.
		h.humanoid.PlatformStand = true
		h.root.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Name = "Stall"
		weld.Part0 = weldTo
		weld.Part1 = h.root
		weld.Parent = h.root
		h.stall = weld
		h.root.Anchored = false
	end
end

-- Decoration: wander and graze inside an area (a paddock, an arena), for as long as nobody leads it.
function Animals.roam(horse: Model, x0: number, z0: number, x1: number, z1: number)
	local h = horses[horse]
	if not h then
		return
	end
	h.roaming = true
	local wander = Random.new(math.floor(h.root.Position.X * 7 + h.root.Position.Z))
	task.spawn(function()
		horse:SetAttribute("Grazing", true)
		task.wait(wander:NextNumber(2, 10))
		while horse.Parent and h.roaming and not h.leader and not h.stall do
			if wander:NextNumber() < 0.45 then
				horse:SetAttribute("Grazing", nil)
				local y = h.root.Position.Y - ROOT_Y
				local done = false
				Animals.walkTo(horse, Vector3.new(wander:NextNumber(x0, x1), y, wander:NextNumber(z0, z1)), function()
					done = true
				end)
				while not done and horse.Parent and h.roaming do
					task.wait(0.5)
				end
			end
			if not horse.Parent or not h.roaming then
				break
			end
			horse:SetAttribute("Grazing", wander:NextNumber() < 0.7 or nil)
			task.wait(wander:NextNumber(6, 16))
		end
	end)
end

function Animals.remove(horse: Model)
	local h = horses[horse]
	if h then
		dropRope(h)
		h.walkToken += 1
		h.roaming = false
		horses[horse] = nil
	end
	horse:Destroy()
end

function Animals.start()
	init()
	ensureLoop()
end

return Animals
