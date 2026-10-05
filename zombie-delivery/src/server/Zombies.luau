--!strict
-- The enemies: zombies and bandits, built in code (blocky bodies). Zombies chase the nearest car or player on foot;
-- bandits (Config.Zombies with ranged = true) keep their distance and shoot, often from a roadblock across the road.
--
--   * a car going fast (Horde.RamMinSpeed or more) runs them over: damage = speed × ramPower, a survivor slows it down
--   * a slow or standing car gets grabbed: the zombie hangs on its side / back / roof (welded) and bites it until shot
--   * a player on foot gets bitten
--   * the depot (the safe zone) is never entered, zombies hanging on a car die when it drives in
--
-- Who goes after whom:
--   * roamers (Config.Horde.Roam, zombie kinds only) appear around every player without a job and shamble around
--     their spot; the world's own zombies (residents) do the same. They hunt a player who comes close, shoots nearby
--     or hits them, and calm down when they lose them. Wave zombies (server/Jobs.luau) hunt from the start. At night
--     there are more roamers (Config.DayNight.NightRoam, scaled by DayNight.nightFactor).
--   * people (ZombieDef.jobOnly: bandits, gunners, the base's soldiers) only go after players on a job
--     (Zombies.hunts, set by Main): without one they stand guard, never shoot, chase, grab or steal.
--
-- The limbs are animated on the clients (client/ZombieAnimator.luau), the server only moves the bodies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Map = require(Shared.Map)
local Net = require(Shared.Net)
local Joints = require(Shared.Joints)
local GunModels = require(Shared.GunModels)
local World = require(script.Parent.World)
local Vehicles = require(script.Parent.Vehicles)
local PlayerData = require(script.Parent.PlayerData)
local DayNight = require(script.Parent.DayNight)

local Horde = Config.Horde
local Roam = Horde.Roam

export type Zombie = {
	id: number,
	kind: string,
	def: Config.ZombieDef,
	model: Model,
	humanoid: Humanoid,
	root: Part,
	torso: Part,
	owner: Player?, -- whose job / area spawned it (for the caps)
	resident: boolean, -- lives in the world: never despawns
	dead: boolean,
	guard: boolean, -- waits at a delivery address until somebody comes close
	nextAttack: number,
	nextPath: number,
	lastRam: number,
	car: Vehicles.Car?, -- the car it hangs on
	slot: number?,
	weld: WeldConstraint?,
	lastHitBy: Player?,
	home: Vector3, -- where it wanders around / stands guard
	roamer: boolean, -- roams around the players (Config.Horde.Roam), or a job's zombie after the job
	hunting: boolean, -- a roamer or a resident zombie that noticed somebody (else it wanders)
	lostSince: number?, -- hunting, but nobody in reach since
	nextWander: number,
	walkSpeed: number, -- its full speed (it shambles slower while it wanders)
}

local Zombies = {}

local zombies: { Zombie } = {}
local nextId = 0
local rng = Random.new()
local bump = Net.get("Bump")
local rewardRemote = Net.get("Reward")

-- Set by Main.
Zombies.onKill = function(_player: Player, _zombie: Zombie) end
Zombies.onCarDamaged = function(_player: Player, _amount: number) end
Zombies.onSteal = function(_player: Player, _share: number) end
-- 3.1: how a kill happened, for the challenges' counters (server/Challenges.luau; Main wires it). cause = "gun" (a
-- direct hit), "car" (run over), "splash" (a blast or a fire), "melee" (3.9: a punch or a gun strike,
-- server/CloseCombat.luau) or "other" (it just died, e.g. its humanoid); from = what
-- fired from a car seat (server/Gun.luau: "cargun" the roof gun, "window" a passenger's gun; nil = anything else).
export type KillInfo = { kind: string, bandit: boolean, headshot: boolean, cause: string, from: string? }
Zombies.onKillInfo = nil :: ((player: Player, info: KillInfo) -> ())?
-- Do the people (ZombieDef.jobOnly: bandits, gunners, soldiers) go after this player? Main: on a job or riding in
-- one's crew (Jobs.involved); Admin adds the players who called enemies. Zombies go after everybody.
Zombies.hunts = function(_player: Player): boolean
	return true
end

-- ── The body ───────────────────────────────────────────────────────────────

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function limb(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CollisionGroup = "Zombie"
	p.CanCollide = false
	p.Parent = model
	return p
end

local function motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1
	m.Parent = part0
end

local function buildBlocky(kind: string, def: Config.ZombieDef, at: Vector3): (Model, Humanoid, Part, Part)
	local s = def.scale
	local model = Instance.new("Model")
	model.Name = def.name
	local skin, shirt, pants = rgb(def.skin), rgb(def.shirt), rgb(def.pants)
	-- Ragged colours: every zombie a little different.
	local tint = rng:NextNumber(-0.08, 0.08)
	shirt = shirt:Lerp(if tint > 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), math.abs(tint) * 2)

	local root = limb(model, "HumanoidRootPart", Vector3.new(2, 2, 1) * s, skin)
	root.Transparency = 1
	local torso = limb(model, "Torso", Vector3.new(2, 2, 1) * s, shirt)
	torso.CanCollide = true
	local head = limb(model, "Head", Vector3.new(1.2, 1.2, 1.2) * s, skin)
	local leftArm = limb(model, "Left Arm", Vector3.new(1, 2, 1) * s, skin)
	local rightArm = limb(model, "Right Arm", Vector3.new(1, 2, 1) * s, skin)
	local leftLeg = limb(model, "Left Leg", Vector3.new(1, 2, 1) * s, pants)
	local rightLeg = limb(model, "Right Leg", Vector3.new(1, 2, 1) * s, pants)
	local bandit = def.ranged == true
	for _, side in { -1, 1 } do
		local eye = limb(model, "Eye", Vector3.new(0.22, 0.18, 0.1) * s, if bandit then Color3.fromRGB(20, 20, 20) else Color3.fromRGB(255, 60, 40), if bandit then Enum.Material.SmoothPlastic else Enum.Material.Neon)
		eye.Massless = true
		eye:SetAttribute("HeadPart", true) -- a hit here is a headshot
		motor("Eye", head, eye, CFrame.new(0.28 * side * s, 0.12 * s, -0.6 * s), CFrame.identity)
	end
	if bandit then
		-- A bandana, a cap and a gun.
		local bandana = limb(model, "Bandana", Vector3.new(1.25, 0.5, 1.25) * s, if kind == "gunner" then Color3.fromRGB(30, 30, 30) else Color3.fromRGB(170, 30, 30), Enum.Material.Fabric)
		bandana.Massless = true
		bandana:SetAttribute("HeadPart", true) -- a hit here is a headshot
		motor("Bandana", head, bandana, CFrame.new(0, -0.25 * s, 0), CFrame.identity)
		local cap = limb(model, "Cap", Vector3.new(1.3, 0.4, 1.3) * s, Color3.fromRGB(40, 40, 46), Enum.Material.Fabric)
		cap.Massless = true
		cap:SetAttribute("HeadPart", true) -- a hit here is a headshot
		motor("Cap", head, cap, CFrame.new(0, 0.6 * s, 0), CFrame.identity)
		local gun = limb(model, "Gun", Vector3.new(0.35, 0.5, if kind == "gunner" then 3.2 else 1.8) * s, Color3.fromRGB(25, 25, 28), Enum.Material.Metal)
		gun.Massless = true
		motor("Gun", rightArm, gun, CFrame.new(0, -0.9 * s, -0.6 * s) * CFrame.Angles(math.rad(-80), 0, 0), CFrame.identity)
	end
	if kind == "brute" then
		local jaw = limb(model, "Jaw", Vector3.new(1, 0.3, 0.4) * s, Color3.fromRGB(60, 20, 20))
		jaw.Massless = true
		jaw:SetAttribute("HeadPart", true) -- a hit here is a headshot
		motor("Jaw", head, jaw, CFrame.new(0, -0.35 * s, -0.5 * s), CFrame.identity)
	end

	-- Plain joints (no rotation in C0 / C1): the client sets Transform to swing them.
	motor("RootJoint", root, torso, CFrame.identity, CFrame.identity)
	local tilt = if bandit then CFrame.identity else CFrame.Angles(math.rad(-12), 0, math.rad(rng:NextNumber(-15, 15)))
	motor("Neck", torso, head, CFrame.new(0, s, 0) * tilt, CFrame.new(0, -0.6 * s, 0))
	local reach = CFrame.Angles(math.rad(80), 0, 0) -- arms forward: the zombie pose, or aiming the gun
	local leftReach = if bandit then CFrame.Angles(math.rad(75), math.rad(-30), 0) else reach
	motor("Left Shoulder", torso, leftArm, CFrame.new(-1.5 * s, 0.5 * s, 0) * leftReach, CFrame.new(0, 0.5 * s, 0))
	motor("Right Shoulder", torso, rightArm, CFrame.new(1.5 * s, 0.5 * s, 0) * reach, CFrame.new(0, 0.5 * s, 0))
	motor("Left Hip", torso, leftLeg, CFrame.new(-0.5 * s, -s, 0), CFrame.new(0, s, 0))
	motor("Right Hip", torso, rightLeg, CFrame.new(0.5 * s, -s, 0), CFrame.new(0, s, 0))

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15 -- R15 so HipHeight (the leg length) is respected at every scale
	humanoid.HipHeight = 2 * s
	humanoid.MaxHealth = def.health
	humanoid.Health = def.health
	humanoid.WalkSpeed = def.speed * rng:NextNumber(0.9, 1.1)
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = true
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid.Parent = model

	model.PrimaryPart = root
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	model:SetAttribute("Zombie", kind)
	if bandit then
		model:SetAttribute("Bandit", true)
	end
	return model, humanoid, root, torso
end

-- ── Realistic bodies: R15 characters with animations ───────────────────────
-- Built once per kind from a HumanoidDescription (Roblox's own R15 body), then cloned. Zombies walk with Roblox's
-- zombie animations, bandits with the normal ones. If R15 cannot be built, the blocky body above is used.

local ANIMATIONS: { [string]: { [string]: string } } = {
	zombie = { idle = "rbxassetid://616158929", walk = "rbxassetid://616168032", run = "rbxassetid://616163682" },
	human = { idle = "rbxassetid://507766388", walk = "rbxassetid://507777826", run = "rbxassetid://507767714" },
}

local templates: { [string]: Model } = {}
local noTemplate: { [string]: boolean } = {}

local function attach(model: Model, to: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, headPart: boolean): Part
	local p = limb(model, name, size, color, material)
	p.Massless = true
	p.CFrame = to.CFrame * offset
	if headPart then
		p:SetAttribute("HeadPart", true) -- a hit here is a headshot
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = p
	w.Parent = p
	return p
end

local function template(kind: string, def: Config.ZombieDef): Model?
	if templates[kind] or noTemplate[kind] then
		return templates[kind]
	end
	local s = def.scale
	local bandit = def.ranged == true
	local ok, result = pcall(function()
		local description = Instance.new("HumanoidDescription")
		local skin, shirt, pants = rgb(def.skin), rgb(def.shirt), rgb(def.pants)
		description.HeadColor = skin
		description.LeftArmColor = skin
		description.RightArmColor = skin
		description.TorsoColor = shirt
		description.LeftLegColor = pants
		description.RightLegColor = pants
		description.HeightScale = s
		description.WidthScale = if kind == "brute" then s * 1.3 else s
		description.DepthScale = if kind == "brute" then s * 1.2 else s
		description.HeadScale = if kind == "brute" then s * 0.9 else 1
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn(`[Zombies] no R15 body for {kind}, using blocks: {result}`)
		noTemplate[kind] = true
		return nil
	end
	local model = result :: Model
	model.Name = def.name
	local head = model:FindFirstChild("Head") :: BasePart?
	local hand = model:FindFirstChild("RightHand") :: BasePart?
	if head then
		local face = head:FindFirstChildOfClass("Decal")
		if bandit then
			-- A bandana over the mouth, a cap.
			attach(model, head, "Bandana", Vector3.new(1.25, 0.45, 1.25) * s, CFrame.new(0, -0.25 * s, 0), if kind == "gunner" then Color3.fromRGB(30, 30, 30) else Color3.fromRGB(170, 30, 30), Enum.Material.Fabric, true)
			attach(model, head, "Cap", Vector3.new(1.3, 0.35, 1.3) * s, CFrame.new(0, 0.55 * s, 0), Color3.fromRGB(40, 40, 46), Enum.Material.Fabric, true)
		else
			-- No smile: glowing eyes and a dark mouth.
			if face then
				face:Destroy()
			end
			for _, side in { -1, 1 } do
				attach(model, head, "Eye", Vector3.new(0.2, 0.14, 0.06) * s, CFrame.new(0.22 * side * s, 0.12 * s, -0.6 * s), Color3.fromRGB(255, 60, 40), Enum.Material.Neon, true)
			end
			attach(model, head, "Mouth", Vector3.new(0.5, 0.18, 0.06) * s, CFrame.new(0, -0.25 * s, -0.6 * s), Color3.fromRGB(40, 10, 10), Enum.Material.SmoothPlastic, true)
		end
	end
	if bandit and hand then
		-- The same guns the players carry: a gunner a scoped rifle, a bandit a pistol.
		local weapon = if kind == "gunner" then "rifle" else "pistol"
		local gun = GunModels.build(weapon, hand, GunModels.gripOn(hand), s)
		gun.Name = "Gun"
		gun.Parent = model
	end
	-- Bandits hold the gun up: the clients raise both arms over the walk (client/ZombieAnimator.luau), so it works
	-- for Motor6D and AnimationConstraint joints alike (the gun follows the hand).
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = "Zombie"
			d.CanCollide = d.Name == "UpperTorso" or d.Name == "LowerTorso"
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false -- we ragdoll instead
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	model:SetAttribute("Zombie", kind)
	if bandit then
		model:SetAttribute("Bandit", true)
	end
	templates[kind] = model
	return model
end

local function buildBody(kind: string, def: Config.ZombieDef, at: Vector3): (Model, Humanoid, Part, Part)
	local source = template(kind, def)
	if not source then
		return buildBlocky(kind, def, at)
	end
	local model = source:Clone()
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local root = model:FindFirstChild("HumanoidRootPart") :: Part
	local torso = (model:FindFirstChild("UpperTorso") or root) :: Part
	-- Every zombie a little different.
	local tint = rng:NextNumber(-0.1, 0.1)
	for _, name in { "UpperTorso", "LowerTorso" } do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part.Color = part.Color:Lerp(if tint > 0 then Color3.new(1, 1, 1) else Color3.new(0, 0, 0), math.abs(tint) * 2)
		end
	end
	humanoid.MaxHealth = def.health
	humanoid.Health = def.health
	humanoid.WalkSpeed = def.speed * rng:NextNumber(0.9, 1.1)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	model.PrimaryPart = root
	model:PivotTo(CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	return model, humanoid, root, torso
end

type Moves = { idle: AnimationTrack?, walk: AnimationTrack?, run: AnimationTrack? }
local moves: { [Model]: Moves } = {}

local function loadMoves(model: Model, humanoid: Humanoid, bandit: boolean)
	if not model:FindFirstChild("UpperTorso") then
		return -- the blocky body is animated by the clients
	end
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local set = if bandit then ANIMATIONS.human else ANIMATIONS.zombie
	local tracks: Moves = {}
	for key, id in set do
		local ok, track = pcall(function()
			local animation = Instance.new("Animation")
			animation.AnimationId = id
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Looped = true
			(tracks :: any)[key] = track
		end
	end
	moves[model] = tracks
	if tracks.idle then
		tracks.idle:Play()
	end
	model.Destroying:Connect(function()
		moves[model] = nil
	end)
end

-- Walk / run / stand, from how fast the body really moves.
local function animate(model: Model, root: BasePart, runner: boolean)
	local tracks = moves[model]
	if not tracks then
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local moving = if runner then tracks.run or tracks.walk else tracks.walk
	if speed > 1.5 and moving then
		if not moving.IsPlaying then
			moving:Play(0.2)
			if tracks.idle then
				tracks.idle:Stop(0.2)
			end
		end
		moving:AdjustSpeed(math.clamp(speed / (if runner then 24 else 12), 0.5, 2))
	elseif tracks.idle and not tracks.idle.IsPlaying then
		tracks.idle:Play(0.2)
		for _, track in { tracks.walk, tracks.run } do
			if track and track.IsPlaying then
				track:Stop(0.2)
			end
		end
	end
end

-- A ragdoll: the joints go limp and ball sockets hold the limbs (R15), else the body falls apart (blocky).
-- R15 joints are Motor6Ds or, since Roblox's Avatar Joint Upgrade, AnimationConstraints that already come with a
-- ball socket each ("<Joint>BallSocket"): that one is used, otherwise a socket is added between the rig attachments.
local function ragdoll(model: Model)
	local joints: { Instance } = {}
	for _, d in model:GetDescendants() do
		if Joints.isJoint(d) then
			table.insert(joints, d)
		end
	end
	local sockets = 0
	for _, joint in joints do
		local a0, a1, p0, p1 = Joints.ends(joint)
		if not (a0 and a1 and p0 and p1) then
			continue
		end
		local socket: BallSocketConstraint? = nil
		for _, c in p1:GetChildren() do
			if c:IsA("BallSocketConstraint") and Joints.partOf(c.Attachment0) == p0 and Joints.partOf(c.Attachment1) == p1 then
				socket = c
				break
			end
		end
		if not socket then
			local made = Instance.new("BallSocketConstraint")
			made.Attachment0 = a0
			made.Attachment1 = a1
			made.LimitsEnabled = true
			made.TwistLimitsEnabled = true
			made.UpperAngle = 60
			made.TwistLowerAngle = -45
			made.TwistUpperAngle = 45
			made.Parent = p1
			socket = made
		end
		(socket :: BallSocketConstraint).Enabled = true;
		(joint :: any).Enabled = false
		sockets += 1
	end
	if sockets == 0 then
		for _, joint in joints do
			joint:Destroy()
		end
	end
	local tracks = moves[model]
	if tracks then
		for _, track in { tracks.idle, tracks.walk, tracks.run } do
			if track then
				track:Stop(0)
			end
		end
	end
end

-- ── Life and death ─────────────────────────────────────────────────────────

-- The zombies that wander and hunt only what they notice: roamers and the world's own zombies (never the people).
local function roams(z: Zombie): boolean
	return (z.roamer or z.resident) and z.def.jobOnly ~= true
end

-- Back to wandering around where it is now, at a shamble.
local function calm(z: Zombie, position: Vector3)
	z.hunting = false
	z.lostSince = nil
	z.home = position
	z.humanoid.WalkSpeed = math.min(Roam.wanderSpeed, z.walkSpeed)
end

-- It noticed somebody: full speed.
local function wake(z: Zombie)
	if z.hunting then
		return
	end
	z.hunting = true
	z.lostSince = nil
	z.humanoid.WalkSpeed = z.walkSpeed
end

local function unlatch(z: Zombie)
	local car = z.car
	if car and z.slot then
		car.latched[z.slot] = nil
	end
	if z.weld then
		z.weld:Destroy()
	end
	z.car, z.slot, z.weld = nil, nil, nil
	z.model:SetAttribute("LatchedTo", nil)
end

local function remove(z: Zombie)
	z.dead = true
	unlatch(z)
	local index = table.find(zombies, z)
	if index then
		table.remove(zombies, index)
	end
end

-- killer = nil: no reward (despawn, the safe zone). push = velocity for the flying parts. cause, headshot and from:
-- how (Zombies.onKillInfo).
local function kill(z: Zombie, killer: Player?, push: Vector3?, cause: string?, headshot: boolean?, from: string?)
	if z.dead then
		return
	end
	remove(z)
	z.humanoid.Health = 0
	ragdoll(z.model)
	-- The body collapses: collides only with the ground and buildings, never with cars or players.
	for _, d in z.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = d.Name ~= "HumanoidRootPart"
			d.CollisionGroup = "Corpse"
			d.Massless = false
			if push then
				d.AssemblyLinearVelocity = push + Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(10, 25), rng:NextNumber(-8, 8))
			end
		end
	end
	if killer then
		local profile = PlayerData.get(killer)
		if profile then
			profile.kills += 1
		end
		PlayerData.addMoney(killer, z.def.reward)
		rewardRemote:FireClient(killer, z.root.Position + Vector3.new(0, 4, 0), z.def.reward)
		Zombies.onKill(killer, z)
		local onKillInfo = Zombies.onKillInfo
		if onKillInfo then
			task.spawn(onKillInfo, killer, {
				kind = z.kind,
				bandit = z.def.ranged == true,
				headshot = headshot == true,
				cause = cause or "other",
				from = from,
			})
		end
	end
	task.delay(6, function()
		z.model:Destroy()
	end)
end

-- cause (3.1): "car" (run over), "splash" (a blast or a fire), "melee" (3.9); nil = a gun's hit. from (3.1): the gun fired from a car
-- seat ("cargun", "window"; Zombies.KillInfo).
export type HitInfo = { crit: boolean?, push: Vector3?, cause: string?, from: string? }

-- Returns true when the hit killed it.
function Zombies.damage(z: Zombie, amount: number, by: Player?, info: HitInfo?): boolean
	if z.dead or amount <= 0 then
		return false
	end
	z.lastHitBy = by or z.lastHitBy
	if roams(z) then
		wake(z) -- shot, burnt or run into: now it hunts
	end
	local health = z.humanoid.Health - amount
	if health <= 0 then
		kill(z, by, info and info.push, if info then info.cause or "gun" else "gun", info ~= nil and info.crit == true, info and info.from)
		return true
	end
	z.humanoid.Health = health
	-- A short red flash.
	local torso = z.torso
	local color = torso.Color
	torso.Color = Color3.fromRGB(200, 40, 40)
	task.delay(0.08, function()
		if torso.Parent then
			torso.Color = color
		end
	end)
	return false
end

-- The zombie that owns a part (a hit of the roof gun).
function Zombies.fromPart(part: Instance): Zombie?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model or model:GetAttribute("Zombie") == nil then
		return nil
	end
	for _, z in zombies do
		if z.model == model then
			return z
		end
	end
	return nil
end

-- roamer = one of the zombies around a player without a job (Config.Horde.Roam): it wanders until it notices you.
function Zombies.spawn(kind: string, at: Vector3, owner: Player?, guard: boolean?, resident: boolean?, roamer: boolean?): Zombie?
	if #zombies >= Horde.MaxTotal then
		return nil
	end
	local def = Config.Zombies[kind] or Config.Zombies.walker
	local model, humanoid, root, torso = buildBody(kind, def, at + Vector3.new(0, 3 * def.scale, 0))
	nextId += 1
	local z: Zombie = {
		id = nextId,
		kind = kind,
		def = def,
		model = model,
		humanoid = humanoid,
		root = root,
		torso = torso,
		owner = owner,
		resident = resident == true,
		dead = false,
		guard = guard == true,
		nextAttack = 0,
		nextPath = 0,
		lastRam = 0,
		car = nil,
		slot = nil,
		weld = nil,
		lastHitBy = nil,
		home = at,
		roamer = roamer == true and def.jobOnly ~= true,
		hunting = false,
		lostSince = nil,
		nextWander = 0,
		walkSpeed = humanoid.WalkSpeed,
	}
	if roams(z) then
		calm(z, at)
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model.Parent = workspace:FindFirstChild("Zombies") or workspace
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	loadMoves(model, humanoid, def.ranged == true)
	humanoid.Died:Connect(function()
		if not z.dead then
			kill(z, z.lastHitBy, nil)
		end
	end)
	table.insert(zombies, z)
	return z
end

-- A free spot on a road somewhere around `center`, out of the safe zone and not right next to a player.
function Zombies.findSpot(center: Vector3, heading: Vector3?, minDistance: number?, maxDistance: number?): Vector3?
	local low = minDistance or Horde.SpawnMin
	local high = maxDistance or Horde.SpawnMax
	for _ = 1, 6 do
		local angle = rng:NextNumber(0, math.pi * 2)
		if heading and heading.Magnitude > 10 and rng:NextNumber() < Horde.SpawnAheadChance then
			angle = math.atan2(heading.Z, heading.X) + rng:NextNumber(-1, 1)
		end
		local distance = rng:NextNumber(low, high)
		local px = center.X + math.cos(angle) * distance
		local pz = center.Z + math.sin(angle) * distance
		local x, z, dx, dz, width = Map.nearestRoad(px, pz)
		local lateral = rng:NextNumber(-1, 1) * (width / 2 - 4)
		local spot = Vector3.new(x - dz * lateral, World.RoadTop, z + dx * lateral)
		if World.isSafe(spot) or (spot - center).Magnitude < low * 0.6 then
			continue
		end
		local tooClose = false
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if rootPart and (rootPart.Position - spot).Magnitude < low * 0.6 then
				tooClose = true
				break
			end
		end
		if not tooClose then
			return spot
		end
	end
	return nil
end

-- Returns how many really appeared (no road spot, or the server's cap reached).
function Zombies.spawnAround(owner: Player, center: Vector3, heading: Vector3?, count: number, kinds: { [string]: number }): number
	local made = 0
	for _ = 1, count do
		local spot = Zombies.findSpot(center, heading)
		if spot and Zombies.spawn(Economy.pickKind(kinds, rng:NextNumber()), spot, owner, false) then
			made += 1
		end
	end
	return made
end

-- A horde waiting at a delivery address. outward = the unit vector from the block to the road (they never stand
-- inside the block, where the buildings are).
function Zombies.spawnGuards(owner: Player, at: Vector3, outward: Vector3, count: number, kinds: { [string]: number })
	local along = Vector3.new(outward.Z, 0, -outward.X)
	for _ = 1, count do
		local offset = along * rng:NextNumber(-16, 16) + outward * rng:NextNumber(0, 12)
		if outward.Magnitude < 0.5 then
			-- an open yard: all around
			local angle = rng:NextNumber(0, math.pi * 2)
			offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(8, 26)
		end
		Zombies.spawn(Economy.pickKind(kinds, rng:NextNumber()), at + offset, owner, true)
	end
end

-- The enemies a player's job brought (not the roamers around them). zombiesOnly = without the bandits and gunners
-- (the soldiers bite, they count).
function Zombies.countFor(owner: Player, zombiesOnly: boolean?): number
	local n = 0
	for _, z in zombies do
		if z.owner == owner and not z.roamer and not (zombiesOnly and z.def.ranged) then
			n += 1
		end
	end
	return n
end

-- A car is gone: whoever hung on it lets go.
function Zombies.releaseCar(car: Vehicles.Car)
	for _, z in table.clone(zombies) do
		if z.car == car then
			unlatch(z)
			z.humanoid.PlatformStand = false
		end
	end
end

local roamWant: { [Player]: { n: number, at: number } } = {}
local noiseAt: { [Player]: number } = {}

-- The player left (or an admin cleared): their zombies go too.
function Zombies.clearOwner(owner: Player)
	for _, z in table.clone(zombies) do
		if z.owner == owner then
			remove(z)
			z.model:Destroy()
		end
	end
	roamWant[owner] = nil
	noiseAt[owner] = nil
end

-- The job is over: its enemies stop being special. Its zombies roam on (they keep after you until they lose you,
-- then wander); its people (roadblocks, the ones from the stops, the guards) belong to nobody and stand where they
-- are until they despawn, far from everybody.
function Zombies.release(owner: Player)
	for _, z in zombies do
		if z.owner ~= owner or z.dead or z.resident or z.roamer then
			continue
		end
		if z.def.jobOnly then
			z.owner = nil
			z.home = z.root.Position
		else
			z.roamer = true
			if z.guard then
				z.guard = false
				calm(z, z.root.Position)
			else
				z.home = z.root.Position
				z.hunting = true
				z.lostSince = nil
			end
		end
	end
end

-- A shot at `at`: the calm zombies that hear it come to look (once per Roam.think per player, a minigun is loud
-- enough as it is).
function Zombies.noise(player: Player, at: Vector3)
	local now = os.clock()
	if now - (noiseAt[player] or 0) < Roam.think then
		return
	end
	noiseAt[player] = now
	local safe = World.isSafe(at)
	for _, z in zombies do
		if not z.dead and not z.hunting and not z.car and roams(z) and (z.root.Position - at).Magnitude < Roam.gunHearing then
			wake(z)
			z.nextPath = now + 0.3
			if not safe then
				z.humanoid:MoveTo(at)
			end
		end
	end
end

-- ── Behaviour ──────────────────────────────────────────────────────────────

local shoot: (Zombie, any) -> ()
local nearestPlayerDistanceFn: (Vector3) -> number

local LATCH_SLOTS = 4

-- Where on the car a latched zombie hangs (car space) and which way it faces.
local function latchFrame(car: Vehicles.Car, slot: number, scale: number): CFrame
	local size = car.size
	local half = 1.2 * scale
	local chassisHalf = car.chassis.Size.Y / 2
	local y = size.Y * 0.45 - chassisHalf
	if slot == 1 then
		return CFrame.new(-(size.X / 2 + half), y, -1) * CFrame.Angles(0, math.rad(-90), 0)
	elseif slot == 2 then
		return CFrame.new(size.X / 2 + half, y, 1) * CFrame.Angles(0, math.rad(90), 0)
	elseif slot == 3 then
		return CFrame.new(0, y, size.Z / 2 + half)
	end
	return CFrame.new(0, size.Y - chassisHalf + 3 * scale, 1.5)
end

local function latch(z: Zombie, car: Vehicles.Car): boolean
	local slot: number? = nil
	for i = 1, math.min(LATCH_SLOTS, Horde.LatchSlots) do
		if not car.latched[i] then
			slot = i
			break
		end
	end
	if not slot then
		return false
	end
	car.latched[slot] = true
	z.car, z.slot = car, slot
	z.humanoid.PlatformStand = true
	for _, d in z.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Massless = true
		end
	end
	z.model:PivotTo(car.chassis.CFrame * latchFrame(car, slot, z.def.scale))
	local w = Instance.new("WeldConstraint")
	w.Part0 = car.chassis
	w.Part1 = z.root
	w.Parent = z.root
	z.weld = w
	z.model:SetAttribute("LatchedTo", car.owner.UserId)
	z.nextAttack = os.clock() + 0.5
	return true
end

-- player = whose car it is, or who stands there.
type Target = { position: Vector3, velocity: Vector3, car: Vehicles.Car?, humanoid: Humanoid?, player: Player }

-- Zombies.hunts for every player, asked a few times a second (not for every enemy in every frame).
local hunted: { [Player]: boolean } = {}
local nextHuntCheck = 0

local function refreshHunted(now: number)
	if now < nextHuntCheck then
		return
	end
	nextHuntCheck = now + 0.25
	table.clear(hunted)
	for _, player in Players:GetPlayers() do
		local ok, result = pcall(Zombies.hunts, player)
		hunted[player] = ok and result == true
	end
end

local function gatherTargets(): { Target }
	local targets: { Target } = {}
	for _, car in Vehicles.all() do
		local position = car.chassis.Position
		if not World.isSafe(position) then
			table.insert(targets, { position = position, velocity = car.chassis.AssemblyLinearVelocity, car = car, player = car.owner })
		end
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and rootPart and humanoid.Health > 0 and not humanoid.SeatPart and not World.isSafe(rootPart.Position) then
			table.insert(targets, { position = rootPart.Position, velocity = rootPart.AssemblyLinearVelocity, humanoid = humanoid, player = player })
		end
	end
	return targets
end

local function nearestPlayerDistance(position: Vector3): number
	local best = math.huge
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if rootPart then
			best = math.min(best, (rootPart.Position - position).Magnitude)
		end
	end
	return best
end

nearestPlayerDistanceFn = nearestPlayerDistance

-- Is the zombie touching this car? (car space box test)
local function touches(car: Vehicles.Car, position: Vector3, reach: number): boolean
	local p = car.chassis.CFrame:PointToObjectSpace(position)
	local size = car.size
	return math.abs(p.X) < size.X / 2 + reach and math.abs(p.Z) < size.Z / 2 + reach and p.Y > -6 and p.Y < size.Y + 4
end

local function hitByCar(z: Zombie, car: Vehicles.Car, now: number)
	local speed = Vehicles.speed(car)
	if speed >= Horde.RamMinSpeed then
		if now - z.lastRam < 0.5 then
			return
		end
		z.lastRam = now
		local velocity = car.chassis.AssemblyLinearVelocity
		local push = velocity * 0.9 + Vector3.new(0, 25, 0)
		local health = z.humanoid.Health
		local killed = Zombies.damage(z, Economy.ramDamage(speed, car.stats.ramPower), car.owner, { push = push, cause = "car" })
		if not killed then
			-- Something big: the car bounces off it and takes a dent.
			bump:FireClient(car.owner, Horde.RamSlowdown)
			Vehicles.damage(car, health * Horde.RamSelfDamage)
			Zombies.onCarDamaged(car.owner, health * Horde.RamSelfDamage)
			z.root.AssemblyLinearVelocity = velocity * 0.6 + Vector3.new(0, 15, 0)
		end
		return
	end
	if z.def.ranged then
		return -- bandits do not grab cars, they shoot them
	end
	if z.def.jobOnly and not hunted[car.owner] then
		return -- a soldier leaves the car of somebody without a job alone
	end
	-- Brutes are too heavy to hang on a car, they hit it from the ground.
	if z.kind ~= "brute" and latch(z, car) then
		return
	end
	-- No room on the car: bite it from the ground.
	if now >= z.nextAttack then
		z.nextAttack = now + z.def.attackEvery
		Vehicles.damage(car, z.def.damage)
		Zombies.onCarDamaged(car.owner, z.def.damage)
	end
end

local tracer = Net.get("Tracer")
local BANDIT_TRACER = Color3.fromRGB(255, 80, 60)

-- A bandit's shot: needs a clear line, hits less often at a fast target.
function shoot(z: Zombie, target: Target)
	local position = z.root.Position
	local flat = Vector3.new(target.position.X, position.Y, target.position.Z)
	z.root.CFrame = CFrame.lookAt(position, flat)
	local from = position + Vector3.new(0, 1.2 * z.def.scale, 0) + z.root.CFrame.LookVector * 2
	local aim = target.position + Vector3.new(0, 1.5, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace:FindFirstChild("Zombies") or z.model }
	local result = workspace:Raycast(from, aim - from, params)
	local targetModel: Instance? = if target.car then target.car.model elseif target.humanoid then target.humanoid.Parent else nil
	if result and not (targetModel and result.Instance:IsDescendantOf(targetModel)) then
		return -- no clear line of fire
	end
	local speed = Vector3.new(target.velocity.X, 0, target.velocity.Z).Magnitude
	local chance = (z.def.accuracy or 0.6) * math.clamp(1 - speed / 120, 0.3, 1)
	local damage = z.def.shotDamage or 6
	if rng:NextNumber() < chance then
		tracer:FireAllClients(from, aim, BANDIT_TRACER, 0)
		local car = target.car
		if car then
			Vehicles.damage(car, damage, "The bandits shot your car to pieces!")
			Zombies.onCarDamaged(car.owner, damage)
		elseif target.humanoid then
			target.humanoid:TakeDamage(damage)
		end
	else
		local miss = aim + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(-2, 4), rng:NextNumber(-6, 6))
		tracer:FireAllClients(from, miss, BANDIT_TRACER, 0)
	end
end

-- ── Roadblocks ─────────────────────────────────────────────────────────────

type Roadblock = { model: Model, owner: Player, born: number }
local roadblocks: { Roadblock } = {}

-- A bandit car across one lane and bandits behind it. at = on the road, along = the road's direction.
function Zombies.roadblock(owner: Player, at: Vector3, along: Vector3, count: number)
	local model = Instance.new("Model")
	model.Name = "Roadblock"
	local side = Vector3.new(-along.Z, 0, along.X)
	local lane = if rng:NextNumber() < 0.5 then -1 else 1
	local center = at + side * lane * 7
	local frame = CFrame.lookAt(center, center + side) -- across the road
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.Size = size
		p.CFrame = frame * offset
		p.Color = color
		p.Material = material
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
	end
	piece("Body", Vector3.new(6.4, 2.6, 13), CFrame.new(0, World.RoadTop + 2, 0), Color3.fromRGB(28, 28, 32), Enum.Material.Metal)
	piece("Cabin", Vector3.new(5.6, 2, 6), CFrame.new(0, World.RoadTop + 4.2, 0.5), Color3.fromRGB(28, 28, 32), Enum.Material.Metal)
	piece("Stripe", Vector3.new(6.5, 0.6, 13.1), CFrame.new(0, World.RoadTop + 2.4, 0), Color3.fromRGB(170, 30, 30), Enum.Material.SmoothPlastic)
	for _, x in { -6, 6 } do
		piece("Barrel", Vector3.new(3, 3.6, 3), CFrame.new(x, World.RoadTop + 1.8, -9), Color3.fromRGB(120, 60, 30), Enum.Material.CorrodedMetal)
	end
	model.Parent = workspace:FindFirstChild("Effects") or workspace
	table.insert(roadblocks, { model = model, owner = owner, born = os.clock() })
	for _ = 1, count do
		local spot = center - along * rng:NextNumber(4, 16) + side * rng:NextNumber(-10, 10)
		local kind = if rng:NextNumber() < 0.25 then "gunner" else "bandit"
		Zombies.spawn(kind, Vector3.new(spot.X, World.RoadTop, spot.Z), owner, true)
	end
end

local function cleanRoadblocks()
	local now = os.clock()
	for n = #roadblocks, 1, -1 do
		local r = roadblocks[n]
		local pivot = r.model:GetPivot().Position
		if now - r.born > 150 or not r.owner.Parent or nearestPlayerDistanceFn(pivot) > 400 then
			r.model:Destroy()
			table.remove(roadblocks, n)
		end
	end
end

-- ── Who notices whom ───────────────────────────────────────────────────────

local function flatSpeed(v: Vector3): number
	return Vector3.new(v.X, 0, v.Z).Magnitude
end

-- The nearest target within reach. people = only the players they go after (Zombies.hunts).
local function nearestTarget(position: Vector3, targets: { Target }, reach: number, people: boolean): (Target?, number)
	local best: Target? = nil
	local bestDistance = reach
	for _, t in targets do
		if people and not hunted[t.player] then
			continue
		end
		local d = (t.position - position).Magnitude
		if d < bestDistance then
			best, bestDistance = t, d
		end
	end
	return best, bestDistance
end

-- A calm zombie notices a player on foot within Roam.aggro, a car further the faster (the louder) it goes.
local function noticed(position: Vector3, targets: { Target }): (Target?, number)
	local best: Target? = nil
	local bestDistance = math.huge
	for _, t in targets do
		local reach = if t.car then math.min(Roam.aggroCar + flatSpeed(t.velocity) * Roam.aggroPerSpeed, Roam.aggroCarMax) else Roam.aggro
		local d = (t.position - position).Magnitude
		if d < reach and d < bestDistance then
			best, bestDistance = t, d
		end
	end
	return best, bestDistance
end

-- A slow shamble around its spot: a few steps, or it just stands there for a while.
local function wander(z: Zombie, position: Vector3, now: number)
	if now < z.nextWander then
		return
	end
	z.nextWander = now + rng:NextNumber(2.5, 6)
	if rng:NextNumber() < Roam.idleChance then
		z.humanoid:MoveTo(position)
		return
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local goal = z.home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(4, Roam.wander)
	if not World.isSafe(goal) then
		z.humanoid:MoveTo(goal)
	end
end

-- People with nobody to go after: they stand guard (at the camps, the base, a roadblock), now and then a step or two.
local function standGuard(z: Zombie, position: Vector3, now: number)
	z.nextPath = now + rng:NextNumber(1.5, 3)
	if z.guard then
		return -- a roadblock or a stop's guards: they wait right there
	end
	local away = Vector3.new(position.X - z.home.X, 0, position.Z - z.home.Z).Magnitude
	if away > 30 then
		z.humanoid:MoveTo(if z.resident then z.home else position) -- back to the post (a camp's), or just stop
	elseif rng:NextNumber() < 0.25 then
		local angle = rng:NextNumber(0, math.pi * 2)
		z.humanoid:MoveTo(z.home + Vector3.new(math.cos(angle), 0, math.sin(angle)) * rng:NextNumber(1, 6))
	else
		z.humanoid:MoveTo(position)
	end
end

local function step()
	local now = os.clock()
	refreshHunted(now)
	local targets = gatherTargets()
	local cars = Vehicles.all()
	for _, z in table.clone(zombies) do
		if z.dead then
			continue
		end
		local position = z.root.Position
		if not z.car then
			animate(z.model, z.root, z.humanoid.WalkSpeed > 20) -- a wandering runner walks
		end

		-- Hanging on a car: bite it, die in the depot.
		local car = z.car
		if car then
			if car.wrecked then
				unlatch(z)
				z.humanoid.PlatformStand = false
			elseif World.isSafe(car.chassis.Position) then
				kill(z, nil, car.chassis.AssemblyLinearVelocity + Vector3.new(0, 20, 0))
			elseif z.def.jobOnly and not hunted[car.owner] then
				-- The job is over: a soldier lets go.
				unlatch(z)
				z.humanoid.PlatformStand = false
			elseif now >= z.nextAttack then
				z.nextAttack = now + z.def.attackEvery
				Vehicles.damage(car, z.def.damage)
				Zombies.onCarDamaged(car.owner, z.def.damage)
			end
			continue
		end

		-- Too far from everybody: gone.
		if position.Y < -8 or (not z.resident and nearestPlayerDistance(position) > (if z.roamer then Roam.despawn else Horde.DespawnDistance)) then
			-- drowned in the river / the sea, or nobody around
			remove(z)
			z.model:Destroy()
			continue
		end
		if World.isSafe(position) then
			-- Wandered into the depot (pushed in by a car): it burns.
			kill(z, nil, nil)
			continue
		end

		-- Touching a car?
		local touched = false
		for _, c in cars do
			if touches(c, position, Horde.LatchReach * z.def.scale) then
				hitByCar(z, c, now)
				touched = true
				break
			end
		end
		if touched or z.dead or z.car then
			continue
		end

		if now < z.nextPath then
			continue
		end
		z.nextPath = now + Horde.RepathEvery * rng:NextNumber(0.8, 1.2)

		-- Chase the nearest target.
		local ranged = z.def.ranged == true
		local range = z.def.range or 0
		local best: Target?, bestDistance: number
		if roams(z) then
			if not z.hunting then
				-- Calm: shamble around its spot and look around now and then.
				z.nextPath = now + Roam.think * rng:NextNumber(0.8, 1.2)
				best, bestDistance = noticed(position, targets)
				if not best then
					wander(z, position, now)
					continue
				end
				wake(z)
			else
				best, bestDistance = nearestTarget(position, targets, Roam.chase, false)
				if not best then
					-- Lost them: it goes on where it was heading for a while, then calms down.
					local since = z.lostSince or now
					z.lostSince = since
					if now - since >= Roam.giveUp then
						calm(z, position)
					end
					continue
				end
				z.lostSince = nil
			end
		else
			local reach = if ranged then range + 40 elseif z.guard then 90 elseif z.resident then 160 else 400
			best, bestDistance = nearestTarget(position, targets, reach, z.def.jobOnly == true)
			if not best then
				if z.def.jobOnly then
					standGuard(z, position, now)
				elseif not z.guard then
					z.nextPath = now + rng:NextNumber(2, 4) -- shamble around
					z.humanoid:MoveTo(position + Vector3.new(rng:NextNumber(-20, 20), 0, rng:NextNumber(-20, 20)))
				end
				continue
			end
		end
		if not best then
			continue
		end
		z.guard = false
		if ranged then
			-- Bandits: get within range, stand and shoot.
			if bestDistance > range * 0.85 then
				local goal = position + (best.position - position).Unit * (bestDistance - range * 0.6)
				if not World.isSafe(goal) then
					z.humanoid:MoveTo(goal)
				end
			else
				z.humanoid:MoveTo(position)
				-- Right next to a car: they grab what they can from the cargo.
				local targetCar = best.car
				if targetCar and bestDistance < 14 then
					Zombies.onSteal(targetCar.owner, Config.BanditCar.StealPerSecond * Horde.RepathEvery)
				end
				if now >= z.nextAttack then
					z.nextAttack = now + (z.def.fireEvery or 1.5) * rng:NextNumber(0.85, 1.15)
					shoot(z, best)
				end
			end
			continue
		end
		local lead = Vector3.new(best.velocity.X, 0, best.velocity.Z) * math.clamp(bestDistance / 60, 0, 0.8)
		local goal = best.position + lead
		if World.isSafe(goal) then
			continue
		end
		z.humanoid:MoveTo(goal)

		-- Bite a player on foot.
		local humanoid = best.humanoid
		if humanoid and bestDistance < Horde.BiteReach * z.def.scale + 1 and now >= z.nextAttack then
			z.nextAttack = now + z.def.attackEvery
			humanoid:TakeDamage(z.def.damage)
		end
	end
end

-- A blast or a fire: damage everything in the radius (less at the edge). Returns the number killed. from: a car gun's
-- blast ("cargun", server/Gun.luau; HitInfo.from).
function Zombies.damageArea(center: Vector3, radius: number, damage: number, by: Player?, from: string?): number
	local killed = 0
	for _, z in table.clone(zombies) do
		if z.dead then
			continue
		end
		local offset = z.root.Position - center
		local distance = offset.Magnitude
		if distance <= radius then
			local share = 1 - 0.5 * distance / radius
			local push = if distance > 0.1 then offset.Unit * 40 + Vector3.new(0, 30, 0) else Vector3.new(0, 40, 0)
			if Zombies.damage(z, damage * share, by, { push = push, cause = "splash", from = from }) then
				killed += 1
			end
		end
	end
	return killed
end

-- ── Residents: the zombies that live in the world ──────────────────────────

local RESIDENT_KINDS = { walker = 0.72, runner = 0.22, brute = 0.06 }

local function residentSpot(): (Vector3?, string)
	if rng:NextNumber() < 0.15 then
		-- A bandit camp at one of the far places.
		local camps = { "gas", "farm", "radio", "lodge" }
		local id = camps[rng:NextInteger(1, #camps)]
		for _, yard in Map.Yards do
			if yard.id == id then
				return Vector3.new(rng:NextNumber(yard.x0 + 15, yard.x1 - 15), World.RoadTop, rng:NextNumber(yard.z0 + 15, yard.z1 - 15)), if rng:NextNumber() < 0.3 then "gunner" else "bandit"
			end
		end
	end
	if rng:NextNumber() < 0.2 then
		for _, yard in Map.Yards do
			if yard.id == "base" then
				return Vector3.new(rng:NextNumber(yard.x0 + 30, yard.x1 - 30), World.RoadTop, rng:NextNumber(yard.z0 + 30, yard.z1 - 30)), "soldier"
			end
		end
	end
	local addresses = Map.addresses()
	local a = addresses[rng:NextInteger(1, #addresses)]
	local spot = Vector3.new(a.x + rng:NextNumber(-8, 8), World.RoadTop, a.z + rng:NextNumber(-8, 8))
	return spot, Economy.pickKind(RESIDENT_KINDS, rng:NextNumber())
end

local function keepResidents()
	local alive = 0
	for _, z in zombies do
		if z.resident then
			alive += 1
		end
	end
	local missing = Horde.Residents.count - alive
	-- Everybody at once when the server starts, then a couple at a time.
	local batch = if alive == 0 then missing else math.min(missing, 2)
	for _ = 1, batch do
		local spot, kind = residentSpot()
		if spot and nearestPlayerDistance(spot) > 90 then
			Zombies.spawn(kind, spot, nil, false, true)
		end
	end
end

-- ── Roamers: zombies around every player without a job ────────────────────

local function keepRoamers()
	local now = os.clock()
	local radius = Roam.far + 40
	-- More of them at night (smoothly at dusk and dawn).
	local night = Economy.nightScale(Config.DayNight.NightRoam, DayNight.nightFactor())
	for _, player in Players:GetPlayers() do
		if #zombies >= Horde.MaxTotal - Roam.reserve then
			return -- the rest is for the jobs' waves
		end
		if Zombies.hunts(player) then
			continue -- on a job: the waves come instead
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not rootPart or humanoid.Health <= 0 or World.isSafe(rootPart.Position) then
			continue
		end
		local center = rootPart.Position
		local entry = roamWant[player]
		local base: number
		if entry and now < entry.at then
			base = entry.n
		else
			base = rng:NextInteger(Roam.min, Roam.max)
			roamWant[player] = { n = base, at = now + Roam.rethink }
		end
		local want = math.floor(base * night + 0.5)
		-- Anybody's roamers count (two friends together share them).
		local around = 0
		for _, z in zombies do
			if not z.dead and roams(z) and (z.root.Position - center).Magnitude < radius then
				around += 1
			end
		end
		for _ = 1, math.min(want - around, Roam.batch) do
			local spot = Zombies.findSpot(center, nil, Roam.near, Roam.far)
			if spot then
				Zombies.spawn(Economy.pickKind(Roam.kinds, rng:NextNumber()), spot, player, false, false, true)
			end
		end
	end
end

function Zombies.all(): { Zombie }
	return zombies
end

function Zombies.start()
	-- Build the R15 bodies up front (it can take a moment), not in the middle of a fight.
	task.spawn(function()
		for kind, def in Config.Zombies do
			template(kind, def)
		end
	end)
	RunService.Heartbeat:Connect(step)
	task.spawn(function()
		while true do
			keepResidents()
			cleanRoadblocks()
			task.wait(Horde.Residents.respawn / 5)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Roam.every)
			local ok, err = pcall(function()
				keepRoamers()
			end)
			if not ok then
				warn(`[Zombies] roamers: {err}`)
			end
		end
	end)
end

return Zombies
